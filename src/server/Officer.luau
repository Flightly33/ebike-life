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
