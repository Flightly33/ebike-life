--[[
	RiderPose: puts riders' hands on the bars and feet on the pedals (or footpegs) with IKControls,
	on every client, for every rider. The seated animation does the rest of the body; the bike's seat
	is tipped forward so the rider leans into a riding position.

	One hand lets go with the right hand (a wave out to the side), no hands puts both arms out. A
	crash lets the body go limp until the rider recovers. R15 avatars only (R6 riders just sit).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BikeController = require(script.Parent.BikeController)

local RiderPose = {}

type Rider = {
	Character: Model,
	Humanoid: Humanoid,
	Bike: Model,
	Controls: { [string]: IKControl },
	Targets: { [string]: Attachment },
	SeatY: number,
	Ext: number, -- how far out the current trick pose is (smoothed)
	TrickName: string,
}

-- Where the feet go for each air trick, in the bike's frame (+X right, -Z forward), relative to
-- the seat height
local TRICK_FEET: { [string]: { L: Vector3?, R: Vector3? } } = {
	Superman = { L = Vector3.new(-0.5, 0.9, 3.4), R = Vector3.new(0.5, 0.9, 3.4) },
	CanCan = { L = Vector3.new(1.5, -0.3, -0.6) },
	NacNac = { L = Vector3.new(-1.9, 0.3, 2.1) },
	KneeKnocker = { L = Vector3.new(-0.45, 0.7, -1.7), R = Vector3.new(0.45, 0.7, -1.7) },
	NoFooter = { L = Vector3.new(-2.3, -0.5, 0.2), R = Vector3.new(2.3, -0.5, 0.2) },
}

local riders: { [Model]: Rider } = {}

local function attachment(parent: BasePart, name: string, position: Vector3): Attachment
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Parent = parent
	return a
end

local function control(rider: Rider, name: string, chainRoot: string, endEffector: string, target: Attachment?, pole: Attachment?): IKControl?
	local character = rider.Character
	local rootPart = character:FindFirstChild(chainRoot)
	local effector = character:FindFirstChild(endEffector)
	if not rootPart or not effector or not target then
		return nil
	end
	local ik = Instance.new("IKControl")
	ik.Name = "EB_" .. name
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = rootPart
	ik.EndEffector = effector
	ik.Target = target
	if pole then
		ik.Pole = pole
	end
	ik.SmoothTime = 0.06
	ik.Weight = 1
	ik.Parent = rider.Humanoid
	rider.Controls[name] = ik
	return ik
end

local function find(model: Model, name: string): Attachment?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("Attachment") then found else nil
end

local function setup(bike: Model, humanoid: Humanoid): Rider?
	local character = humanoid.Parent
	local root = bike.PrimaryPart
	if not character or not character:IsA("Model") or not root or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local rider: Rider = { Character = character, Humanoid = humanoid, Bike = bike, Controls = {}, Targets = {}, SeatY = 2.6, Ext = 0, TrickName = "" }
	local seat = bike:FindFirstChildOfClass("Seat")
	local seatY = if seat and seat:IsA("BasePart") then root.CFrame:PointToObjectSpace(seat.Position).Y else 2.6
	rider.SeatY = seatY
	rider.Targets.TrickL = attachment(root, "EB_TrickL", Vector3.new(0, seatY, 0))
	rider.Targets.TrickR = attachment(root, "EB_TrickR", Vector3.new(0, seatY, 0))
	-- Free-hand targets and elbow / knee poles, in the bike's frame
	rider.Targets.FreeL = attachment(root, "EB_FreeL", Vector3.new(-2.1, seatY + 2.4, 0.3))
	rider.Targets.FreeR = attachment(root, "EB_FreeR", Vector3.new(2.1, seatY + 2.6, 0.3))
	rider.Targets.Wave = attachment(root, "EB_Wave", Vector3.new(2.0, seatY + 3.4, -0.2))
	local elbowL = attachment(root, "EB_ElbowL", Vector3.new(-2.5, seatY + 0.6, 1.5))
	local elbowR = attachment(root, "EB_ElbowR", Vector3.new(2.5, seatY + 0.6, 1.5))
	local kneeL = attachment(root, "EB_KneeL", Vector3.new(-0.8, seatY + 0.6, -3))
	local kneeR = attachment(root, "EB_KneeR", Vector3.new(0.8, seatY + 0.6, -3))
	local gripL, gripR = find(bike, "GripL"), find(bike, "GripR")
	local footL = find(bike, "PedalL") or find(bike, "PegL")
	local footR = find(bike, "PedalR") or find(bike, "PegR")
	control(rider, "HandL", "LeftUpperArm", "LeftHand", gripL, elbowL)
	control(rider, "HandR", "RightUpperArm", "RightHand", gripR, elbowR)
	control(rider, "FootL", "LeftUpperLeg", "LeftFoot", footL, kneeL)
	control(rider, "FootR", "RightUpperLeg", "RightFoot", footR, kneeR)
	rider.Targets.GripL = gripL :: Attachment
	rider.Targets.GripR = gripR :: Attachment
	rider.Targets.FootL = footL :: Attachment
	rider.Targets.FootR = footR :: Attachment
	return rider
end

local function teardown(rider: Rider)
	for _, ik in rider.Controls do
		ik:Destroy()
	end
	rider.Controls = {}
end

local function update()
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
			local rider: Rider? = riders[bike]
			if rider and (not occupant or rider.Humanoid ~= occupant) then
				teardown(rider)
				riders[bike] = nil
				rider = nil
			end
			if occupant and not rider then
				rider = setup(bike, occupant)
				if rider then
					riders[bike] = rider
				end
			end
			if rider then
				seen[bike] = true
				-- hands and crashes (the local rider's from physics, others' from attributes)
				local hands: number, crashed: boolean
				local trick, ext, barspin = "", 0, false
				local physics = BikeController.Physics
				if bike == BikeController.Model and physics then
					hands = physics.Hands
					crashed = physics.Crash > 0
					trick, ext = physics.TrickName, physics.TrickExt
					barspin = physics.BarSpin > 0
				else
					local h = bike:GetAttribute("Hands")
					hands = if type(h) == "number" then h else 0
					crashed = bike:GetAttribute("Crash") == true
					local t = bike:GetAttribute("Trick")
					trick = if type(t) == "string" then t else ""
					ext = if trick ~= "" then 1 else 0
					barspin = bike:GetAttribute("Barspin") == true
				end
				-- trick pose: blend the feet from the pedals toward the trick's spots
				if trick ~= "" then
					rider.TrickName = trick
				end
				rider.Ext += (ext - rider.Ext) * 0.5
				local feet = TRICK_FEET[rider.TrickName]
				local targets0 = rider.Targets
				local feetSides: { [string]: string } = { L = "FootL", R = "FootR" }
				for side, name in feetSides do
					local ik = rider.Controls[name]
					local pedal = targets0[name]
					local spot = feet and (feet :: any)[side]
					local trickTarget = targets0["Trick" .. side]
					if ik and pedal and trickTarget then
						if spot and rider.Ext > 0.05 then
							local root = bike.PrimaryPart
							local from = if root then root.CFrame:PointToObjectSpace(pedal.WorldPosition) else Vector3.zero
							local to = spot + Vector3.new(0, rider.SeatY, 0)
							trickTarget.Position = from:Lerp(to, rider.Ext)
							ik.Target = trickTarget
						else
							ik.Target = pedal
						end
					end
				end
				if barspin then
					hands = math.max(hands, 2) -- hands off while the bars spin
				end
				local left, right = rider.Controls.HandL, rider.Controls.HandR
				local targets = rider.Targets
				if left then
					left.Target = if hands >= 2 then targets.FreeL else targets.GripL
					left.Enabled = not crashed
				end
				if right then
					right.Target = if hands >= 2 then targets.FreeR elseif hands == 1 then targets.Wave else targets.GripR
					right.Enabled = not crashed
				end
				for _, name in { "FootL", "FootR" } do
					local ik = rider.Controls[name]
					if ik then
						ik.Enabled = not crashed
					end
				end
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
		if clock >= 1 / 30 then
			clock = 0
			update()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(update)
	end)
end

return RiderPose
