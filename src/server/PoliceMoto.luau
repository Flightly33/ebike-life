--[[
	PoliceMoto: the police e-moto units' machine (Shared/Bikes.PoliceMoto, built by BikeModel: a
	windscreen, LightRed / LightBlue strobes and a light bar, panniers) with its officer, a part-built
	figure welded on in a riding pose: hands on the grips, boots on the pegs, a white helmet with a
	dark visor and a hi-vis vest over the uniform. PoliceService drives it with CarDriver like a car
	(CarDriver leans it into turns); the client's Visuals spins its wheels and flashes its strobes in
	a pursuit, like a cruiser's.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bikes = require(Shared.Bikes)
local Config = require(Shared.Config)
local PartKit = require(Shared.PartKit)
local BikeModel = require(Shared.Models.BikeModel)

local PoliceMoto = {}

local UNIFORM = Color3.fromRGB(22, 30, 58)
local VEST = Color3.fromRGB(205, 245, 45)
local HELMET = Color3.fromRGB(240, 240, 242)
local VISOR = Color3.fromRGB(18, 18, 22)
local BLACK = Color3.fromRGB(16, 16, 18)
local SMOOTH = Enum.Material.SmoothPlastic
local FIGURE: PartKit.Opts = { Collide = false, Query = false, Touch = false, Massless = true }

export type Built = {
	Model: Model,
	Lift: number, -- studs from the ground to the model's pivot
	HalfLength: number,
	HalfWidth: number,
	WheelRadius: number, -- studs
}

-- (worked out from the parent's CFrame: it runs in the offline previews too)
local function attachmentAt(model: Model, name: string): Vector3?
	local a = model:FindFirstChild(name, true)
	if a and a:IsA("Attachment") then
		local parent = a.Parent
		if parent and parent:IsA("BasePart") then
			return parent.CFrame:PointToWorldSpace(a.Position)
		end
	end
	return nil
end

-- A box from a to b (its length along the line), welded to the bike's root
local function limb(model: Model, root: BasePart, name: string, a: Vector3, b: Vector3, width: number, depth: number, color: Color3): BasePart
	local length = math.max((b - a).Magnitude, 0.05)
	local part = PartKit.Box(model, name, Vector3.new(width, depth, length), CFrame.lookAt((a + b) / 2, b), color, SMOOTH, FIGURE)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function block(model: Model, root: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = PartKit.Box(model, name, size, cf, color, material or SMOOTH, FIGURE)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	return part
end

-- The officer, posed on the bike as it stands (facing -Z, built at the origin)
local function rider(model: Model, root: BasePart)
	local seatPart = model:FindFirstChild("SeatAnchor", true)
	local seat = if seatPart and seatPart:IsA("BasePart") then seatPart.CFrame.Position else root.CFrame.Position + Vector3.new(0, 2, 0)
	local gripL = attachmentAt(model, "GripL") or (seat + Vector3.new(-1, 1.5, -2))
	local gripR = attachmentAt(model, "GripR") or (seat + Vector3.new(1, 1.5, -2))
	local pegL = attachmentAt(model, "PegL") or (seat + Vector3.new(-0.8, -1.6, -0.5))
	local pegR = attachmentAt(model, "PegR") or (seat + Vector3.new(0.8, -1.6, -0.5))
	-- proportions of an avatar the game's height (Config.Avatar.Height: 1.3x a 5-stud R6 figure)
	local k = Config.Avatar.Height / 5
	local hips = seat + Vector3.new(0, 0.35 * k, 0.1 * k)
	local shoulders = hips + Vector3.new(0, 1.75 * k, -0.7 * k)
	-- torso and vest
	limb(model, root, "OfficerTorso", hips, shoulders, 2 * k, 1 * k, UNIFORM)
	local vestFrom, vestTo = hips:Lerp(shoulders, 0.25), hips:Lerp(shoulders, 0.95)
	limb(model, root, "OfficerVest", vestFrom, vestTo, 2.08 * k, 1.08 * k, VEST)
	-- head under a helmet, visor at the front
	local headAt = shoulders + Vector3.new(0, 0.75 * k, -0.25 * k)
	-- (the helmet covers the head: just the neck shows under it)
	block(model, root, "OfficerNeck", Vector3.new(0.55, 0.5, 0.55) * k, CFrame.new(headAt + Vector3.new(0, -0.6 * k, 0.1 * k)), Color3.fromRGB(205, 160, 125))
	local helmet = PartKit.Ball(model, "OfficerHelmet", 1.45 * k, headAt + Vector3.new(0, 0.12 * k, 0.04 * k), HELMET, SMOOTH, FIGURE)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = helmet
	weld.Parent = helmet
	block(model, root, "OfficerVisor", Vector3.new(1.05, 0.42, 0.1) * k, CFrame.new(headAt + Vector3.new(0, 0.05 * k, -0.72 * k)), VISOR, Enum.Material.Glass)
	-- arms to the grips (gloves at the ends)
	for side, grip in { [-1] = gripL, [1] = gripR } do
		local shoulder = shoulders + Vector3.new(side * 1.45 * k, -0.25 * k, 0)
		local elbow = shoulder:Lerp(grip, 0.5) + Vector3.new(side * 0.25 * k, -0.15 * k, 0)
		limb(model, root, "OfficerUpperArm", shoulder, elbow, 0.9 * k, 0.9 * k, UNIFORM)
		limb(model, root, "OfficerForearm", elbow, grip, 0.82 * k, 0.82 * k, UNIFORM)
		block(model, root, "OfficerGlove", Vector3.new(0.6, 0.5, 0.55) * k, CFrame.new(grip), BLACK)
	end
	-- legs bent to the pegs, boots on them
	for side, peg in { [-1] = pegL, [1] = pegR } do
		local hip = hips + Vector3.new(side * 0.5 * k, 0, 0)
		local knee = hip:Lerp(peg, 0.5) + Vector3.new(side * 0.15 * k, 0.45 * k, -0.75 * k)
		limb(model, root, "OfficerThigh", hip, knee, 0.95 * k, 0.95 * k, UNIFORM)
		limb(model, root, "OfficerShin", knee, peg + Vector3.new(0, 0.25 * k, 0), 0.88 * k, 0.88 * k, UNIFORM)
		block(model, root, "OfficerBoot", Vector3.new(0.75, 0.55, 1.1) * k, CFrame.new(peg + Vector3.new(0, 0.2 * k, -0.15 * k)), BLACK)
	end
end

-- (sized to its officer the way a player's bike is fitted to them: hip to ankle ~0.45 of their height)
PoliceMoto.HIP_TO_ANKLE = 0.45

function PoliceMoto.Build(): Built
	local bike = Bikes.PoliceMoto
	local fit = BikeModel.FitScale(bike, Config.Avatar.Height * PoliceMoto.HIP_TO_ANKLE)
	local model = BikeModel.Build(bike, nil, { Scale = fit })
	model.Name = "PoliceMoto"
	local root = model.PrimaryPart :: BasePart
	-- the rider's seat stays empty (nobody can get on a police bike)
	for _, d in model:GetDescendants() do
		if d:IsA("Seat") then
			d.Disabled = true
		elseif d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	rider(model, root)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	root.CanQuery = false
	model:SetAttribute("Kind", "Cop")
	model:SetAttribute("CarKind", "PoliceMoto")
	model:SetAttribute("Moto", true)
	-- how it sits: the bottom of its tyres to the pivot (the root's frame), and its footprint (the
	-- box round every part's corners, as built facing -Z)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local half = d.Size / 2
			for _, c in { Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1) } do
				local p = d.CFrame:PointToWorldSpace(half * c)
				lo = lo:Min(p)
				hi = hi:Max(p)
			end
		end
	end
	local size = hi - lo
	local bottom = lo.Y
	local radius = bike.Geometry.WheelDiameter / 2 * Config.VISUAL_STUDS_PER_METER * fit
	model:SetAttribute("WheelRadius", radius)
	return {
		Model = model,
		Lift = root.CFrame.Position.Y - bottom,
		HalfLength = size.Z / 2,
		HalfWidth = size.X / 2,
		WheelRadius = radius,
	}
end

return PoliceMoto
