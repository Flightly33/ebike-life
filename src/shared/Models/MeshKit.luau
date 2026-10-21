--[[
	MeshKit: puts the Blender meshes (blender/build_vehicles.py) on bikes and cars when they've
	been imported into the place, and leaves the part-built models alone when they haven't.

	Import: Studio, File > Import 3D, blender/out/Vehicles.fbx, then name the imported model
	"VehicleMeshes" and put it in ReplicatedStorage. It holds one model per vehicle (bike id, or
	Car_<Kind>) with MeshParts named "<vehicle>__<Group>__<Slot>" (found by name anywhere inside). MeshManifest says where each one sits in
	the vehicle (metres) and which joint group it rides on; the slot gives its colour and material
	(Frame / Accent / Rims / Paint are the paintable ones).

	Each mesh's proportions are checked against the manifest first: if the importer turned the file
	(a swapped axis), that vehicle keeps its part-built model and a warning says so.

	Studio's importer can also turn the file half a turn about the vertical (its forward axis is the
	opposite of Blender's), which keeps every size the same but puts each piece back to front. The
	import keeps the pieces laid out as a vehicle, so that turn is read from where they sit compared
	with the manifest and undone. A "Turn" attribute (0 or 180) on VehicleMeshes overrides it.
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
local turns: { [string]: number } = {}
local rootFolder: Instance? = nil

local index: { [string]: MeshPart }? = nil
local reported = false

-- Every MeshPart under ReplicatedStorage.VehicleMeshes by name, wherever the importer put it
-- (Studio's importer may flatten or rename the per-vehicle folders, so names carry the vehicle).
local function meshIndex(): { [string]: MeshPart }
	if index then
		return index
	end
	local found: { [string]: MeshPart } = {}
	-- (pcall: the offline city bake runs under Lune, where there's no real ReplicatedStorage)
	local ok, root = pcall(function()
		return ReplicatedStorage:FindFirstChild("VehicleMeshes")
	end)
	if ok and typeof(root) == "Instance" then
		rootFolder = root
		local count = 0
		for _, d in (root :: Instance):GetDescendants() do
			if d:IsA("MeshPart") then
				count += 1
				-- the importer can append suffixes like ".001" or " (1)"; match on the base name
				local base = string.match(d.Name, "^([%w_]+__[%w_]+__[%w_]+)") or d.Name
				if not found[base] then
					found[base] = d
				end
			end
		end
		if not reported then
			reported = true
			print(string.format("[MeshKit] VehicleMeshes found: %d MeshParts", count))
			if count == 0 then
				warn("[MeshKit] VehicleMeshes has no MeshParts in it. Re-import Vehicles.fbx with File > Import 3D.")
			end
		end
	elseif not reported and ok then
		reported = true
		print("[MeshKit] no ReplicatedStorage.VehicleMeshes; using part-built vehicles")
	end
	index = found
	return found
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

-- How far the importer turned this vehicle about the vertical (0 or 180 degrees): compare where its
-- pieces sit (centred, any scale) with the manifest, as is and half a turn round
local function readTurn(vehicleId: string, entries: { MeshManifest.Entry }, meshes: { [string]: MeshPart }): number
	local forced = if rootFolder then rootFolder:GetAttribute("Turn") else nil
	if type(forced) == "number" then
		return if math.abs(forced - 180) < 1 then 180 else 0
	end
	local got: { Vector3 } = {}
	local want: { Vector3 } = {}
	local gotMean, wantMean = Vector3.zero, Vector3.zero
	for _, entry in entries do
		local mesh = meshes[entry.Name]
		if mesh then
			table.insert(got, mesh.Position)
			table.insert(want, entry.Center)
			gotMean += mesh.Position
			wantMean += entry.Center
		end
	end
	if #got < 3 then
		return 0
	end
	gotMean /= #got
	wantMean /= #want
	local gotSpread, wantSpread = 0, 0
	for i = 1, #got do
		gotSpread += (got[i] - gotMean).Magnitude
		wantSpread += (want[i] - wantMean).Magnitude
	end
	if gotSpread < 1e-3 or wantSpread < 1e-3 then
		return 0 -- the pieces were all moved to one spot: nothing to read
	end
	local k = gotSpread / wantSpread
	local asIs, turned = 0, 0
	for i = 1, #got do
		local g = (got[i] - gotMean) / k
		local w = want[i] - wantMean
		asIs += (g - w).Magnitude
		turned += (g - Vector3.new(-w.X, w.Y, -w.Z)).Magnitude
	end
	if turned < asIs * 0.5 then
		print(string.format("[MeshKit] %s: the import came in turned half round; turning it back", vehicleId))
		return 180
	end
	return 0
end

-- Are this vehicle's meshes imported and the right way round?
function MeshKit.Has(vehicleId: string): boolean
	local cached = checked[vehicleId]
	if cached ~= nil then
		return cached
	end
	local entries = MeshManifest[vehicleId]
	local meshes = meshIndex()
	local ok = entries ~= nil and next(meshes) ~= nil
	if ok and entries then
		for _, entry in entries do
			local mesh = meshes[entry.Name]
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
	if ok and entries then
		turns[vehicleId] = readTurn(vehicleId, entries, meshes)
	end
	checked[vehicleId] = ok
	return ok
end

-- Check a vehicle's import again next time (after re-importing)
function MeshKit.Forget(vehicleId: string)
	checked[vehicleId] = nil
	turns[vehicleId] = nil
	index = nil
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
	local meshes = meshIndex()
	if not entries then
		return placed
	end
	for _, entry in entries do
		local source = meshes[entry.Name]
		if source and source:IsA("MeshPart") then
			local part = source:Clone()
			for _, child in part:GetChildren() do
				if not child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			part.Name = entry.Name
			part.Size = entry.Size * scale
			-- undo a half-turned import: the geometry turned with it, about the piece's own centre
			part.CFrame = CFrame.new(entry.Center * scale) * (if turns[vehicleId] == 180 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
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
