--[[
	RiderPose: poses every rider on every client, every frame, by writing their joints' Transforms
	itself (after Roblox's animation step, so the default sit animation and the avatar's animation
	pack don't matter; works for Motor6D and AnimationConstraint bodies alike).

	The hips sit on the seat (the seat weld is set from the avatar's own hip height), the torso
	leans forward far enough for the hands to reach the grips, and arms and legs are two-bone IK to
	the grips and the pedals (or footpegs). On top of that:
		pedalling      lean in a little more, a slight side-to-side rock with effort
		wheelie        pull back, arms straight
		stoppie        weight forward over the bars
		air tricks     a full-body pose per trick, blended in and out
		one / no hands right hand up / both arms out
	A crash leaves the body to the ragdoll. R15 only (R6 riders keep the default sit).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BikeController = require(script.Parent.BikeController)
local Ragdoll = require(script.Parent.Ragdoll)
local Rig = require(script.Parent.Rig)
local RiderIK = require(script.Parent.RiderIK)

local RiderPose = {}

local POSE_RANGE = 300 -- studs from the camera

type Rider = {
	Character: Model,
	Humanoid: Humanoid,
	Bike: Model,
	Rig: Rig.RigInfo,
	SeatC0: CFrame, -- the seat weld that puts the hips on the seat
	SeatTop: Vector3, -- in the bike root's space
	Fit: number, -- torso pitch that brings the hands to the grips
	Lean: number, -- smoothed torso pitch (forward +)
	Roll: number,
	Ext: number, -- trick pose, smoothed 0..1
	TrickName: string,
	Hands: { L: number, R: number }, -- 0 on the grips .. 1 free, smoothed
	Points: { [string]: Attachment }, -- GripL/R, PedalL/R (or PegL/R as PedalL/R)
}

-- Trick poses: where the feet go (seat-relative, in leg lengths; +X right, +Y up, +Z back) and how
-- much the torso pitches forward on top of the riding lean
type TrickPose = { L: Vector3?, R: Vector3?, Lean: number }
local TRICKS: { [string]: TrickPose } = {
	Superman = { L = Vector3.new(-0.2, 0.35, 1.15), R = Vector3.new(0.2, 0.35, 1.15), Lean = 0.9 },
	CanCan = { L = Vector3.new(0.75, -0.3, -0.25), Lean = 0.1 },
	NacNac = { L = Vector3.new(0.6, 0.15, 0.8), Lean = 0.25 },
	KneeKnocker = { L = Vector3.new(-0.1, 0.05, -0.55), R = Vector3.new(0.1, 0.05, -0.55), Lean = -0.25 },
	NoFooter = { L = Vector3.new(-1.0, -0.2, 0.1), R = Vector3.new(1.0, -0.2, 0.1), Lean = 0 },
}

local riders: { [Model]: Rider } = {}

-- a limb: its three joints and which side it's on
type Chain = { Side: string, A: Rig.Joint, B: Rig.Joint, C: Rig.Joint, Sign: number }

local function find(model: Model, name: string): Attachment?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("Attachment") then found else nil
end

local function setup(bike: Model, humanoid: Humanoid): Rider?
	local character = humanoid.Parent
	local root = bike.PrimaryPart
	local seat = bike:FindFirstChildOfClass("Seat")
	if not character or not character:IsA("Model") or not root or not seat or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local rig = Rig.FromCharacter(character)
	if not rig then
		return nil
	end
	local J = rig.Joints
	-- hips on the seat: the hip pivots sit a little above the seat's top, level with the bike
	local seatTop = root.CFrame:PointToObjectSpace(seat.Position) + Vector3.new(0, seat.Size.Y / 2, 0)
	local restLower = J.Root.C0 * J.Root.C1:Inverse()
	local hipMid = (restLower * ((J.LeftHip.C0.Position + J.RightHip.C0.Position) / 2))
	local hrpInRoot = CFrame.new(seatTop + Vector3.new(0, rig.Leg * 0.12, 0) - hipMid)
	local seatC0 = seat.CFrame:ToObjectSpace(root.CFrame * hrpInRoot)

	-- lean forward until the shoulders are an arm's length (a little bent) from the grips
	local gripL, gripR = find(bike, "GripL"), find(bike, "GripR")
	local fit = 0.35
	if gripL and gripR then
		local grips = root.CFrame:PointToObjectSpace((gripL.WorldPosition + gripR.WorldPosition) / 2)
		local best = math.huge
		for i = 0, 26 do
			local pitch = i * 0.05
			local _, upper = RiderIK.Torso(rig, hrpInRoot, pitch, 0)
			local shoulders = upper * ((J.LeftShoulder.C0.Position + J.RightShoulder.C0.Position) / 2)
			local miss = math.abs((grips - shoulders).Magnitude - rig.Arm * 0.92)
			if miss < best then
				best, fit = miss, pitch
			end
		end
	end
	local points: { [string]: Attachment } = {}
	for _, side in { "L", "R" } do
		points["Grip" .. side] = find(bike, "Grip" .. side) :: Attachment
		points["Pedal" .. side] = (find(bike, "Pedal" .. side) or find(bike, "Peg" .. side)) :: Attachment
	end
	return {
		Points = points,
		Character = character,
		Humanoid = humanoid,
		Bike = bike,
		Rig = rig,
		SeatC0 = seatC0,
		SeatTop = seatTop,
		Fit = fit,
		Lean = fit,
		Roll = 0,
		Ext = 0,
		TrickName = "",
		Hands = { L = 0, R = 0 },
	}
end

local function teardown(rider: Rider)
	for _, joint in rider.Rig.Joints do
		if joint.Instance.Parent then
			Rig.Set(joint, CFrame.identity)
		end
	end
end

type Read = { Crashed: boolean, Hands: number, Trick: string, Ext: number, Barspin: boolean, Wheelie: number, Stoppie: number, Pedal: number, Steer: number }

local function read(bike: Model): Read
	local physics = BikeController.Physics
	if bike == BikeController.Model and physics then
		return {
			Crashed = physics.Crash > 0 or Ragdoll.Active,
			Hands = physics.Hands,
			Trick = physics.TrickName,
			Ext = physics.TrickExt,
			Barspin = physics.BarSpin > 0,
			Wheelie = physics.Wheelie,
			Stoppie = physics.Stoppie,
			Pedal = math.clamp(physics.Cadence / 90, 0, 1),
			Steer = physics.Steer,
		}
	end
	local function number(name: string): number
		local v = bike:GetAttribute(name)
		return if type(v) == "number" then v else 0
	end
	local trick = bike:GetAttribute("Trick")
	local trickName = if type(trick) == "string" then trick else ""
	local wheelie = bike:GetAttribute("Wheelie")
	return {
		Crashed = bike:GetAttribute("Crash") == true,
		Hands = number("Hands"),
		Trick = trickName,
		Ext = if trickName ~= "" then 1 else 0,
		Barspin = bike:GetAttribute("Barspin") == true,
		Wheelie = if wheelie == true then 0.45 elseif type(wheelie) == "number" then wheelie else 0,
		Stoppie = if bike:GetAttribute("Stoppie") == true then 0.3 else 0,
		Pedal = math.clamp(number("Cadence") / 90, 0, 1),
		Steer = number("Steer"),
	}
end

local function pose(rider: Rider, dt: number)
	local bike = rider.Bike
	local root = bike.PrimaryPart
	local seat = bike:FindFirstChildOfClass("Seat")
	local hrpPart = rider.Character:FindFirstChild("HumanoidRootPart")
	if not root or not seat or not hrpPart or not hrpPart:IsA("BasePart") then
		return
	end
	local state = read(bike)
	if state.Crashed then
		return
	end
	-- hips on the seat (each client sets the weld for itself; the server's is the default one)
	local weld = seat:FindFirstChild("SeatWeld")
	if weld and weld:IsA("Weld") and weld.Part1 == hrpPart and (weld.C0 ~= rider.SeatC0 or weld.C1 ~= CFrame.identity) then
		weld.C0 = rider.SeatC0
		weld.C1 = CFrame.identity
	end

	local rig = rider.Rig
	local J = rig.Joints
	local k = math.min(1, dt * 8)

	-- tricks blend in and out
	if state.Trick ~= "" then
		rider.TrickName = state.Trick
	end
	rider.Ext += (state.Ext - rider.Ext) * math.min(1, dt * 14)
	local trick = TRICKS[rider.TrickName]
	local ext = if trick then rider.Ext else 0

	-- torso: the fitted lean, more when pushing hard, back on a wheelie, forward on a stoppie
	local t = os.clock()
	local lean = rider.Fit + state.Pedal * 0.12 + state.Stoppie * 0.8 - math.min(state.Wheelie, 1.1) * 0.75
	if trick then
		lean += trick.Lean * ext
	end
	rider.Lean += (lean - rider.Lean) * k
	local rock = math.sin(t * (2 + state.Pedal * 6)) * 0.05 * state.Pedal
	rider.Roll += (rock - rider.Roll) * k

	local hrp = hrpPart.CFrame
	local lower, upper, rootT, waistT = RiderIK.Torso(rig, hrp, rider.Lean, rider.Roll)
	Rig.Set(J.Root, rootT)
	Rig.Set(J.Waist, waistT)
	-- keep looking up the road
	Rig.Set(J.Neck, Rig.ToTransform(J.Neck, CFrame.Angles(math.clamp(rider.Lean, -0.4, 1.2) * 0.75, -state.Steer * 0.35, 0)))

	local bikeCF = root.CFrame
	local look, up, right = bikeCF.LookVector, bikeCF.UpVector, bikeCF.RightVector
	local seatWorld = bikeCF * rider.SeatTop
	local level = bikeCF - bikeCF.Position

	-- legs: feet on the pedals / pegs, or out into the trick
	local legs: { Chain } = {
		{ Side = "L", A = J.LeftHip, B = J.LeftKnee, C = J.LeftAnkle, Sign = -1 },
		{ Side = "R", A = J.RightHip, B = J.RightKnee, C = J.RightAnkle, Sign = 1 },
	}
	for _, leg in legs do
		local side, hip, knee, ankle, sign = leg.Side, leg.A, leg.B, leg.C, leg.Sign
		local pedal = rider.Points["Pedal" .. side]
		local target = if pedal then pedal.WorldPosition + up * rig.AnkleToSole else seatWorld + right * (sign * 0.6) - up * rig.Leg
		local spot = trick and (trick :: any)[side]
		if spot and ext > 0.01 then
			local s = spot :: Vector3
			local trickTarget = seatWorld + (right * s.X + up * s.Y + look * -s.Z) * rig.Leg
			target = target:Lerp(trickTarget, ext)
		end
		local pole = look + up * 0.35 + right * (sign * 0.2)
		RiderIK.Limb(lower, hip, knee, ankle, target, pole, Vector3.new(0, 0, -1), level)
	end

	-- arms: hands on the grips; one hand waves the right one up, no hands (or a barspin) both out
	local free = if state.Barspin then 2 else state.Hands
	local wantL = if free >= 2 then 1 else 0
	local wantR = if free >= 1 then 1 else 0
	rider.Hands.L += (wantL - rider.Hands.L) * math.min(1, dt * 10)
	rider.Hands.R += (wantR - rider.Hands.R) * math.min(1, dt * 10)
	local arms: { Chain } = {
		{ Side = "L", A = J.LeftShoulder, B = J.LeftElbow, C = J.LeftWrist, Sign = -1 },
		{ Side = "R", A = J.RightShoulder, B = J.RightElbow, C = J.RightWrist, Sign = 1 },
	}
	for _, arm in arms do
		local side, shoulder, elbow, wrist, sign = arm.Side, arm.A, arm.B, arm.C, arm.Sign
		local shoulderWorld = (upper * shoulder.C0).Position
		local grip = rider.Points["Grip" .. side]
		local target = if grip then grip.WorldPosition else shoulderWorld + look * rig.Arm * 0.8 - up * 0.4
		target += (shoulderWorld - target).Unit * 0.2 -- the wrist sits just behind the grip
		local amount = rider.Hands[side]
		if amount > 0.01 then
			local out = if side == "R" and free == 1
				then shoulderWorld + up * rig.Arm * 0.9 + right * 0.3 -- a wave
				else shoulderWorld + right * (sign * rig.Arm * 0.95) + up * 0.15
			target = target:Lerp(out, amount)
		end
		local pole = -look * 0.5 + right * (sign * 0.9) - up * 0.4
		RiderIK.Limb(upper, shoulder, elbow, wrist, target, pole, Vector3.new(0, 0, 1), nil)
	end
end

local function sync()
	local folder = Workspace:FindFirstChild("Bikes")
	local seen: { [Model]: boolean } = {}
	if folder then
		for _, bike in folder:GetChildren() do
			if not bike:IsA("Model") then
				continue
			end
			-- Only the owner gets the "Enter" prompt (the server can't hide it per player)
			if bike:GetAttribute("Owner") ~= Players.LocalPlayer.UserId then
				local root = bike.PrimaryPart
				local prompt = root and root:FindFirstChild("EnterPrompt")
				if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
					prompt.Enabled = false
				end
			end
			local seat = bike:FindFirstChildOfClass("Seat")
			local occupant = if seat and seat:IsA("Seat") then seat.Occupant else nil
			local current = riders[bike]
			if current and (not occupant or current.Humanoid ~= occupant) then
				teardown(current)
				riders[bike] = nil
			end
			if occupant and not riders[bike] then
				local made = setup(bike, occupant)
				if made then
					riders[bike] = made
				end
			end
			if riders[bike] then
				seen[bike] = true
			end
		end
	end
	for bike, rider in riders do
		if not seen[bike] then
			teardown(rider)
			riders[bike] = nil
		end
	end
end

function RiderPose.Init()
	local clock = 0
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if clock >= 0.2 then
			clock = 0
			sync()
		end
	end)
	-- after Roblox's animation step, so ours is the pose that shows
	RunService.PreSimulation:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		for _, rider in riders do
			local root = rider.Bike.PrimaryPart
			if root and (root.Position - eye).Magnitude < POSE_RANGE then
				local ok, err = pcall(function()
					pose(rider, dt)
				end)
				if not ok then
					warn("[RiderPose]", rider.Character.Name, err)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(sync)
	end)
end

-- For tests: the riders being posed
function RiderPose.Riders(): { [Model]: any }
	return riders
end

return RiderPose
