--[[
	MeshKit: puts the Blender meshes (blender/build_vehicles.py) on bikes and cars when they've
	been imported into the place, and leaves the part-built models alone when they haven't.

	Import: Studio, File > Import 3D, blender/out/Vehicles.fbx, then name the imported model
	"VehicleMeshes" and put it in ReplicatedStorage. It holds one model per vehicle (bike id, or
	Car_<Kind>) with MeshParts named "<Group>__<Slot>". MeshManifest says where each one sits in
	the vehicle (metres) and which joint group it rides on; the slot gives its colour and material
	(Frame / Accent / Rims / Paint are the paintable ones).

	Each mesh's proportions are checked against the manifest first: if the importer turned the file
	(a swapped axis), that vehicle keeps its part-built model and a warning says so.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshManifest = require(script.Parent.MeshManifest)

local MeshKit = {}

export type Slot = { Color: Color3, Material: Enum.Material, Transparency: number?, Reflectance: number?, Shadow: boolean? }

local SM = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon

MeshKit.Slots = {
	Black = { Color = Color3.fromRGB(26, 26, 28), Material = SM },
	Dark = { Color = Color3.fromRGB(52, 54, 58), Material = METAL },
	Metal = { Color = Color3.fromRGB(192, 194, 198), Material = METAL },
	Gold = { Color = Color3.fromRGB(205, 160, 45), Material = METAL },
	Tire = { Color = Color3.fromRGB(30, 30, 32), Material = SM },
	Leather = { Color = Color3.fromRGB(34, 30, 28), Material = Enum.Material.Leather },
	Brown = { Color = Color3.fromRGB(96, 62, 40), Material = Enum.Material.Leather },
	Wood = { Color = Color3.fromRGB(150, 105, 60), Material = Enum.Material.WoodPlanks },
	NeonWhite = { Color = Color3.fromRGB(255, 250, 232), Material = NEON, Shadow = false },
	NeonRed = { Color = Color3.fromRGB(255, 30, 30), Material = NEON, Shadow = false },
	NeonAmber = { Color = Color3.fromRGB(255, 150, 20), Material = NEON, Shadow = false },
	NeonCyan = { Color = Color3.fromRGB(120, 230, 255), Material = NEON, Shadow = false },
	NeonGreen = { Color = Color3.fromRGB(80, 255, 110), Material = NEON, Shadow = false },
	Glass = { Color = Color3.fromRGB(28, 36, 46), Material = Enum.Material.Glass, Transparency = 0.3, Reflectance = 0.18, Shadow = false },
	Chrome = { Color = Color3.fromRGB(215, 218, 224), Material = METAL, Reflectance = 0.25 },
	Interior = { Color = Color3.fromRGB(48, 46, 46), Material = Enum.Material.Fabric },
	White = { Color = Color3.fromRGB(242, 242, 242), Material = SM },
	Orange = { Color = Color3.fromRGB(250, 120, 20), Material = SM },
	Blue = { Color = Color3.fromRGB(30, 80, 200), Material = SM },
	Red = { Color = Color3.fromRGB(170, 30, 30), Material = SM },
} :: { [string]: Slot }

-- Slots the player's paint (or a car's colour) decides
MeshKit.Paintable = { Frame = true, Accent = true, Rims = true, Paint = true }

local checked: { [string]: boolean } = {}

local function folderFor(vehicleId: string): Instance?
	-- (pcall: the offline city bake runs under Lune, where there's no real ReplicatedStorage)
	local ok, found = pcall(function()
		local root = ReplicatedStorage:FindFirstChild("VehicleMeshes")
		return if root then root:FindFirstChild(vehicleId, true) else nil
	end)
	return if ok and typeof(found) == "Instance" then found else nil
end

-- Same shape up to scale? (the importer may scale, but must not swap axes)
local function sameShape(a: Vector3, b: Vector3): boolean
	local function norm(v: Vector3): Vector3
		local m = math.max(v.X, v.Y, v.Z, 1e-6)
		return v / m
	end
	local na, nb = norm(a), norm(b)
	return (na - nb).Magnitude < 0.12
end

-- Are this vehicle's meshes imported and the right way round?
function MeshKit.Has(vehicleId: string): boolean
	local cached = checked[vehicleId]
	if cached ~= nil then
		return cached
	end
	local entries = MeshManifest[vehicleId]
	local folder = folderFor(vehicleId)
	local ok = entries ~= nil and folder ~= nil
	if ok and folder and entries then
		for _, entry in entries do
			local mesh = folder:FindFirstChild(entry.Name, true)
			if not mesh or not mesh:IsA("MeshPart") then
				ok = false
				warn(string.format("[MeshKit] %s: mesh %s missing from VehicleMeshes; using the part-built model", vehicleId, entry.Name))
				break
			end
			-- thin meshes (rotors, plates) are too flat to judge; check the chunky ones
			local size = entry.Size
			if math.min(size.X, size.Y, size.Z) > 0.03 and not sameShape(mesh.MeshSize, size) then
				ok = false
				warn(string.format("[MeshKit] %s: %s came in turned (MeshSize %s, expected %s); re-import with Y up, -Z forward", vehicleId, entry.Name, tostring(mesh.MeshSize), tostring(size)))
				break
			end
		end
	end
	checked[vehicleId] = ok
	return ok
end

-- Check a vehicle's import again next time (after re-importing)
function MeshKit.Forget(vehicleId: string)
	checked[vehicleId] = nil
end

export type Placed = { Part: MeshPart, Group: string, Slot: string }

--[[
	Clones the vehicle's meshes into `model`, placed in model space (`scale` studs per metre, the
	model built around the origin). `colors` fills the paintable slots. Returns each part with its
	group, so the caller welds it to the right joint.
]]
function MeshKit.Place(model: Model, vehicleId: string, scale: number, colors: { [string]: Color3 }, materials: { [string]: Enum.Material? }?): { Placed }
	local placed: { Placed } = {}
	local entries = MeshManifest[vehicleId]
	local folder = folderFor(vehicleId)
	if not entries or not folder then
		return placed
	end
	for _, entry in entries do
		local source = folder:FindFirstChild(entry.Name, true)
		if source and source:IsA("MeshPart") then
			local part = source:Clone()
			for _, child in part:GetChildren() do
				if not child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			part.Name = entry.Name
			part.Size = entry.Size * scale
			part.CFrame = CFrame.new(entry.Center * scale)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local slot = MeshKit.Slots[entry.Slot]
			if MeshKit.Paintable[entry.Slot] then
				part.Color = colors[entry.Slot] or Color3.fromRGB(200, 30, 35)
				part.Material = (materials and materials[entry.Slot]) or SM
				part:SetAttribute("Paint", entry.Slot)
			elseif slot then
				part.Color = slot.Color
				part.Material = slot.Material
				part.Transparency = slot.Transparency or 0
				part.Reflectance = slot.Reflectance or 0
				part.CastShadow = slot.Shadow ~= false
			end
			part.Parent = model
			table.insert(placed, { Part = part, Group = entry.Group, Slot = entry.Slot })
		end
	end
	return placed
end

return MeshKit
