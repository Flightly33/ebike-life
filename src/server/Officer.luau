--[[
	Officer: a police officer on foot, built from parts (an R6-style rig, so no assets are needed),
	walked by its Humanoid. Clients swing the arms and legs (Visuals) from how fast it's moving.

	Officer.new(position, facing) -> Model with a Humanoid; the server drives it with MoveTo.
]]

local Workspace = game:GetService("Workspace")

local Officer = {}

local UNIFORM = Color3.fromRGB(28, 40, 72)
local TROUSERS = Color3.fromRGB(22, 26, 36)
local SKINS = { Color3.fromRGB(234, 192, 160), Color3.fromRGB(198, 146, 108), Color3.fromRGB(141, 96, 66), Color3.fromRGB(96, 64, 46) }

local folder: Folder? = nil

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "Officers"
	f.Parent = Workspace
	folder = f
	return f
end

local function part(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

function Officer.new(position: Vector3, facing: Vector3, seed: number): Model
	local model = Instance.new("Model")
	model.Name = "Officer"
	model:SetAttribute("Kind", "Officer")
	local skin = SKINS[(seed % #SKINS) + 1]
	local hrp = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), UNIFORM)
	hrp.Transparency = 1
	hrp.CanCollide = false
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), UNIFORM)
	local head = part(model, "Head", Vector3.new(2, 1, 1), skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local larm = part(model, "Left Arm", Vector3.new(1, 2, 1), UNIFORM)
	local rarm = part(model, "Right Arm", Vector3.new(1, 2, 1), UNIFORM)
	local lleg = part(model, "Left Leg", Vector3.new(1, 2, 1), TROUSERS)
	local rleg = part(model, "Right Leg", Vector3.new(1, 2, 1), TROUSERS)
	for _, limb in { larm, rarm, lleg, rleg } do
		limb.CanCollide = false
	end
	-- cap, badge, belt, hands
	local cap = part(model, "Cap", Vector3.new(1.3, 0.35, 1.3), UNIFORM)
	cap.CanCollide = false
	local brim = part(model, "Brim", Vector3.new(1.2, 0.1, 0.5), Color3.fromRGB(15, 15, 18))
	brim.CanCollide = false
	local badge = part(model, "Badge", Vector3.new(0.35, 0.4, 0.1), Color3.fromRGB(230, 190, 60), Enum.Material.Metal)
	badge.CanCollide = false
	local belt = part(model, "Belt", Vector3.new(2.05, 0.3, 1.05), Color3.fromRGB(15, 15, 18))
	belt.CanCollide = false
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head

	motor("RootJoint", hrp, torso, CFrame.Angles(-math.pi / 2, 0, math.pi), CFrame.Angles(-math.pi / 2, 0, math.pi))
	motor("Neck", torso, head, CFrame.new(0, 1, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi), CFrame.new(0, -0.5, 0) * CFrame.Angles(-math.pi / 2, 0, math.pi))
	motor("Left Shoulder", torso, larm, CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0), CFrame.new(0.5, 0.5, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	motor("Right Shoulder", torso, rarm, CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0), CFrame.new(-0.5, 0.5, 0) * CFrame.Angles(0, math.pi / 2, 0))
	motor("Left Hip", torso, lleg, CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi / 2, 0), CFrame.new(-0.5, 1, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	motor("Right Hip", torso, rleg, CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi / 2, 0), CFrame.new(0.5, 1, 0) * CFrame.Angles(0, math.pi / 2, 0))
	local function weld(piece: BasePart, to: BasePart, offset: CFrame)
		local w = Instance.new("Weld")
		w.Part0 = to
		w.Part1 = piece
		w.C0 = offset
		w.Parent = piece
	end
	weld(cap, head, CFrame.new(0, 0.65, 0))
	weld(brim, head, CFrame.new(0, 0.5, -0.75))
	weld(badge, torso, CFrame.new(-0.5, 0.4, -0.52))
	weld(belt, torso, CFrame.new(0, -0.85, 0))
	-- duty kit: radio, holster, cuffs, shoulder patches, name tag, cap badge, boots, gloves
	local BLACK = Color3.fromRGB(15, 15, 18)
	local function bit(name: string, size: Vector3, color: Color3, to: BasePart, offset: CFrame, material: Enum.Material?)
		local piece = part(model, name, size, color, material)
		piece.CanCollide = false
		piece.Massless = true
		weld(piece, to, offset)
	end
	bit("CapBadge", Vector3.new(0.3, 0.25, 0.05), Color3.fromRGB(230, 190, 60), head, CFrame.new(0, 0.68, -0.66), Enum.Material.Metal)
	bit("NameTag", Vector3.new(0.5, 0.14, 0.06), Color3.fromRGB(200, 200, 205), torso, CFrame.new(0.5, 0.45, -0.52), Enum.Material.Metal)
	bit("Radio", Vector3.new(0.3, 0.45, 0.2), BLACK, torso, CFrame.new(0.55, 0.75, -0.58))
	bit("Antenna", Vector3.new(0.06, 0.35, 0.06), BLACK, torso, CFrame.new(0.65, 1.12, -0.58))
	bit("Holster", Vector3.new(0.3, 0.7, 0.45), BLACK, torso, CFrame.new(1.12, -0.95, 0), Enum.Material.Leather)
	bit("Cuffs", Vector3.new(0.4, 0.25, 0.2), Color3.fromRGB(160, 160, 166), torso, CFrame.new(-0.6, -0.85, 0.56), Enum.Material.Metal)
	bit("Buckle", Vector3.new(0.3, 0.22, 0.06), Color3.fromRGB(200, 200, 205), torso, CFrame.new(0, -0.85, -0.54), Enum.Material.Metal)
	bit("Tie", Vector3.new(0.22, 0.9, 0.05), BLACK, torso, CFrame.new(0, 0.35, -0.52))
	for _, arm in { larm, rarm } do
		bit("Patch", Vector3.new(0.05, 0.4, 0.35), Color3.fromRGB(230, 190, 60), arm, CFrame.new(if arm == larm then -0.52 else 0.52, 0.55, 0))
		bit("Glove", Vector3.new(1.02, 0.45, 1.02), BLACK, arm, CFrame.new(0, -0.8, 0), Enum.Material.Leather)
	end
	for _, leg in { lleg, rleg } do
		bit("Boot", Vector3.new(1.04, 0.5, 1.2), BLACK, leg, CFrame.new(0, -0.78, -0.08), Enum.Material.Leather)
		bit("Stripe", Vector3.new(0.05, 1.4, 0.15), Color3.fromRGB(230, 190, 60), leg, CFrame.new(if leg == lleg then -0.51 else 0.51, 0.2, 0))
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.WalkSpeed = 21
	humanoid.HipHeight = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	model.PrimaryPart = hrp
	local look = Vector3.new(facing.X, 0, facing.Z)
	local cf = CFrame.lookAt(position + Vector3.new(0, 3, 0), position + Vector3.new(0, 3, 0) + (if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)))
	-- lay the rig out around the root before parenting
	hrp.CFrame = cf
	torso.CFrame = cf
	head.CFrame = cf * CFrame.new(0, 1.5, 0)
	larm.CFrame = cf * CFrame.new(-1.5, 0, 0)
	rarm.CFrame = cf * CFrame.new(1.5, 0, 0)
	lleg.CFrame = cf * CFrame.new(-0.5, -2, 0)
	rleg.CFrame = cf * CFrame.new(0.5, -2, 0)
	cap.CFrame = head.CFrame * CFrame.new(0, 0.65, 0)
	brim.CFrame = head.CFrame * CFrame.new(0, 0.5, -0.75)
	badge.CFrame = torso.CFrame * CFrame.new(-0.5, 0.4, -0.52)
	belt.CFrame = torso.CFrame * CFrame.new(0, -0.85, 0)
	model.Parent = getFolder()
	pcall(function()
		hrp:SetNetworkOwner(nil)
	end)
	return model
end

return Officer
