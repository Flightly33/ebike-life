--[[
	CityDetail: the fine detail of the streets and buildings near the camera, built on this client
	only (nothing replicates or collides), so the baked map stays light.

	Roads (from Layout's road graph, in chunks of `CHUNK` studs):
	  carriageway  asphalt patches and seams, cracks, oil stains in the lanes, skid marks, manholes,
	               kerb drains, tyre debris on the freeways
	  pavements    slab joints, gum and stains, litter, dockless scooters, newspaper boxes, rubbish
	               bags, planters, now and then a roadworks pit with cones and a sign
	  verges       (country roads and the turnpike) reflector posts and mile markers
	Buildings (their `Body` part, mid-rises, podiums and hotels): window AC units, balconies,
	drainpipes, utility meters, graffiti tags at street level, satellite dishes and masts on the
	roof, and an OPEN sign in the shop window. Faces against a neighbour get nothing.

	Each chunk and building is built once it comes within `Range` of the camera (deterministic: the
	same detail every time, from its own seed) and dropped beyond 1.25x. All sizes are real ones at
	the city's scale (`M` studs per metre).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.City.Layout)
local PartKit = require(Shared.PartKit)

local Graphics = require(script.Parent.Graphics)

local CityDetail = {}

local M = Config.CITY_STUDS_PER_METER
local CHUNK = 60 * M -- road chunk length
local CELL = 400 -- spatial hash cell (studs)
local MAP = Config.MAP_SCALE / 1.25

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local ASPHALT = Enum.Material.Asphalt
local OPTS = { Collide = false, Query = false, Touch = false, Shadow = false }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type Unit = {
	Kind: string, -- "Road" or "Building"
	Center: Vector3,
	Seed: number,
	-- roads
	A: Vector3?,
	Dir: Vector3?,
	Len: number?,
	Width: number?,
	Sidewalk: number?,
	RoadKind: string?,
	-- buildings
	Body: BasePart?,
	Model: Model?,
}

local units: { [number]: { Unit } } = {} -- by cell
local built: { [Unit]: Model } = {}
local folder: Folder
local bodies: { [BasePart]: Unit } = {}

local function key(x: number, z: number): number
	return math.floor(x / CELL) * 100000 + math.floor(z / CELL)
end

local function add(unit: Unit)
	local k = key(unit.Center.X, unit.Center.Z)
	local list = units[k]
	if not list then
		list = {}
		units[k] = list
	end
	table.insert(list, unit)
end

local function remove(unit: Unit)
	local k = key(unit.Center.X, unit.Center.Z)
	local list = units[k]
	if list then
		local i = table.find(list, unit)
		if i then
			table.remove(list, i)
		end
	end
	local model = built[unit]
	if model then
		model:Destroy()
		built[unit] = nil
	end
end

--------------------------------------------------------------------------------
-- Road chunks from the road graph
--------------------------------------------------------------------------------

local function indexRoads()
	for _, edge in Layout.Edges do
		local a = Layout.Nodes[edge.A].Position
		local b = Layout.Nodes[edge.B].Position
		local dir = b - a
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 1 then
			local grid = Layout.Nodes[edge.A].Grid ~= nil and (edge.Kind == "Avenue" or edge.Kind == "Street")
			local sidewalk = if grid then Layout.SidewalkFor(edge.Width) else 0
			-- skip the crossing at each end
			local skip = if grid then edge.Width / 2 + sidewalk else 0
			local len = flat.Magnitude - 2 * skip
			if len > 20 then
				local n = math.max(1, math.floor(len / CHUNK + 0.5))
				local step = len / n
				local unitDir = dir.Unit
				local start = a + unitDir * (skip * dir.Magnitude / flat.Magnitude)
				for i = 0, n - 1 do
					local p0 = start + unitDir * (i * step * dir.Magnitude / flat.Magnitude)
					local p1 = start + unitDir * ((i + 1) * step * dir.Magnitude / flat.Magnitude)
					add({
						Kind = "Road",
						Center = (p0 + p1) / 2,
						Seed = edge.Id * 131 + i,
						A = p0,
						Dir = (p1 - p0).Unit,
						Len = (p1 - p0).Magnitude,
						Width = edge.Width,
						Sidewalk = sidewalk,
						RoadKind = edge.Kind,
					})
				end
			end
		end
	end
end

-- A flat piece lying on a surface: `cf` is on the surface, size in metres (x across, z along)
local function decal(model: Model, name: string, sizeM: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	local p = PartKit.Box(model, name, Vector3.new(sizeM.X * M, math.max(0.02, sizeM.Y * M), sizeM.Z * M), cf * CFrame.new(0, sizeM.Y * M / 2, 0), color, material or SMOOTH, OPTS)
	if transparency then
		p.Transparency = transparency
	end
	return p
end

local function disc(model: Model, name: string, d: number, thick: number, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	local p = PartKit.Cylinder(model, name, d * M, math.max(0.02, thick * M), cf * CFrame.new(0, thick * M / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, material or SMOOTH, OPTS)
	if transparency then
		p.Transparency = transparency
	end
	return p
end

local function cone(model: Model, base: CFrame)
	for k = 0, 3 do
		local d = (0.32 - k * 0.07)
		local p = PartKit.Cylinder(model, "Cone", d * M, 0.18 * M, base * CFrame.new(0, (0.09 + k * 0.17) * M, 0) * CFrame.Angles(0, 0, math.pi / 2), if k % 2 == 1 then rgb(250, 250, 250) else rgb(255, 110, 20), SMOOTH, OPTS)
		local _ = p
	end
	PartKit.Box(model, "ConeBase", Vector3.new(0.4, 0.04, 0.4) * M, base * CFrame.new(0, 0.02 * M, 0), rgb(30, 30, 30), SMOOTH, OPTS)
end

local function scooter(model: Model, base: CFrame, color: Color3)
	PartKit.Box(model, "Deck", Vector3.new(0.16, 0.06, 0.95) * M, base * CFrame.new(0, 0.12 * M, 0), rgb(30, 30, 34), SMOOTH, OPTS)
	for _, z in { -0.48, 0.48 } do
		PartKit.Cylinder(model, "Wheel", 0.2 * M, 0.05 * M, base * CFrame.new(0, 0.1 * M, z * M), rgb(20, 20, 22), SMOOTH, OPTS)
	end
	PartKit.Box(model, "Stem", Vector3.new(0.06, 1.05, 0.06) * M, base * CFrame.new(0, 0.62 * M, -0.47 * M) * CFrame.Angles(math.rad(-10), 0, 0), color, SMOOTH, OPTS)
	PartKit.Box(model, "Bars", Vector3.new(0.5, 0.05, 0.05) * M, base * CFrame.new(0, 1.12 * M, -0.56 * M), rgb(30, 30, 34), SMOOTH, OPTS)
	local tag = PartKit.Box(model, "Tag", Vector3.new(0.14, 0.2, 0.02) * M, base * CFrame.new(0, 0.8 * M, -0.45 * M) * CFrame.Angles(math.rad(-10), 0, 0), color, SMOOTH, OPTS)
	PartKit.Sign(tag, Enum.NormalId.Front, "ZIP", rgb(255, 255, 255), nil, Enum.Font.GothamBlack, 200)
end

local LITTER = { rgb(250, 250, 248), rgb(210, 40, 40), rgb(60, 140, 220), rgb(240, 200, 60), rgb(160, 120, 80) }
local SCOOTERS = { rgb(140, 220, 40), rgb(255, 120, 20), rgb(40, 180, 230) }

local function buildRoad(unit: Unit): Model
	local model = Instance.new("Model")
	model.Name = "RoadDetail"
	local rng = Random.new(unit.Seed)
	local a = unit.A :: Vector3
	local dir = unit.Dir :: Vector3
	local len = unit.Len :: number
	local width = unit.Width :: number
	local sidewalk = unit.Sidewalk :: number
	local kind = unit.RoadKind :: string
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local right = Vector3.new(-flat.Z, 0, flat.X)
	local grid = sidewalk > 0
	local deck = kind == "Freeway" or kind == "Ramp" or kind == "Causeway"
	-- a point on the carriageway: s along, u across; its frame lies on the road's slope
	local function road(s: number, u: number, yaw: number?): CFrame
		local p = a + dir * s + right * u + Vector3.new(0, 0.03, 0)
		return CFrame.lookAt(p, p + dir) * CFrame.Angles(0, yaw or 0, 0)
	end
	local half = width / 2
	local lanes = math.max(1, math.floor(width / (3.6 * M)))
	-- patches and seams
	local per = len / (60 * M) -- (densities are per 60 m)
	for _ = 1, math.floor(rng:NextInteger(3, 6) * per) do
		local w, l = rng:NextNumber(0.7, 2.0), rng:NextNumber(0.9, 3.2)
		local fresh = rng:NextNumber() < 0.5
		local cf = road(rng:NextNumber(0, len), rng:NextNumber(-half + w * M, half - w * M))
		decal(model, "Patch", Vector3.new(w, 0.012, l), cf, if fresh then rgb(54, 55, 59) else rgb(98, 98, 100), ASPHALT)
		-- the sealed seam round it
		decal(model, "Seam", Vector3.new(w + 0.12, 0.008, l + 0.12), cf, rgb(24, 24, 26), SMOOTH, 0.4)
	end
	-- cracks: short zigzags
	for _ = 1, math.floor(rng:NextInteger(5, 9) * per) do
		local s, u = rng:NextNumber(0, len), rng:NextNumber(-half * 0.9, half * 0.9)
		local yaw = rng:NextNumber(-1.2, 1.2)
		for k = 0, rng:NextInteger(2, 4) do
			decal(model, "Crack", Vector3.new(0.09, 0.008, rng:NextNumber(0.8, 1.6)), road(s + k * 1.1 * M, u + math.sin(k * 2.1) * 0.35 * M, yaw + (k % 2 - 0.5) * 0.7), rgb(22, 22, 25), SMOOTH, 0.1)
		end
	end
	-- a puddle where the road dips
	if rng:NextNumber() < 0.35 * per then
		local p = disc(model, "Puddle", rng:NextNumber(1.2, 2.6), 0.01, road(rng:NextNumber(0, len), (if rng:NextNumber() < 0.5 then -1 else 1) * (half - 1.2 * M)), rgb(120, 140, 160), Enum.Material.Glass, 0.35)
		p.Reflectance = 0.5
	end
	-- oil down the middle of the lanes
	for lane = 0, lanes - 1 do
		for _ = 1, math.floor(rng:NextInteger(1, 3) * per) do
			local u = -half + (lane + 0.5) * width / lanes
			disc(model, "Oil", rng:NextNumber(0.6, 1.4), 0.006, road(rng:NextNumber(0, len), u + rng:NextNumber(-0.4, 0.4) * M), rgb(20, 20, 24), SMOOTH, 0.4)
		end
	end
	-- skid marks
	if rng:NextNumber() < 0.35 then
		local s, u = rng:NextNumber(0, len * 0.7), rng:NextNumber(-half * 0.6, half * 0.6)
		local l = rng:NextNumber(5, 12)
		local bend = rng:NextNumber(-0.15, 0.15)
		for _, off in { -0.8, 0.8 } do
			decal(model, "Skid", Vector3.new(0.22, 0.006, l / 2), road(s, u + off * M, bend), rgb(22, 22, 24), SMOOTH, 0.35)
			decal(model, "Skid", Vector3.new(0.22, 0.006, l / 2), road(s + l / 2 * M, u + off * M + bend * l * M * 0.4, bend * 2), rgb(22, 22, 24), SMOOTH, 0.45)
		end
	end
	if grid then
		-- a manhole and kerb drains
		for _ = 1, math.floor(rng:NextInteger(1, 2) * per + 0.5) do
			local cf = road(rng:NextNumber(0.1, 0.9) * len, rng:NextNumber(-half * 0.5, half * 0.5))
			disc(model, "ManholeRim", 0.95, 0.012, cf, rgb(96, 96, 98), METAL)
			disc(model, "Manhole", 0.8, 0.02, cf, rgb(46, 44, 42), Enum.Material.DiamondPlate)
		end
		for _, side in { -1, 1 } do
			for k = 1, math.max(2, math.floor(4 * per)) do
				local cf = road(len * (k / (math.max(2, math.floor(4 * per)) + 1)) + rng:NextNumber(-3, 3) * M, side * (half - 0.35 * M))
				decal(model, "DrainFrame", Vector3.new(0.42, 0.01, 0.8), cf, rgb(110, 110, 112), METAL)
				decal(model, "Drain", Vector3.new(0.32, 0.02, 0.68), cf, rgb(30, 30, 32), Enum.Material.DiamondPlate)
			end
		end
	elseif deck then
		if rng:NextNumber() < 0.3 then
			-- a shredded truck tyre
			local cf = road(rng:NextNumber(0, len), rng:NextNumber(-half * 0.8, half * 0.8), rng:NextNumber(0, 6))
			for k = 0, 2 do
				decal(model, "TyreShred", Vector3.new(0.25, 0.05, rng:NextNumber(0.4, 0.9)), cf * CFrame.new(k * 0.3 * M, 0, k * 0.5 * M) * CFrame.Angles(0, k * 0.7, 0), rgb(20, 20, 22), Enum.Material.Rubber)
			end
		end
	else
		-- verges: reflector posts both sides, a mile marker now and then
		for _, side in { -1, 1 } do
			for k = 0, math.floor(len / (25 * M)) - 1 do
				local p = a + dir * (k + 0.5) * 25 * M + right * side * (half + 1.2 * M)
				PartKit.Box(model, "ReflectorPost", Vector3.new(0.1, 1.1, 0.1) * M, CFrame.new(p + Vector3.new(0, 0.55 * M, 0)), rgb(245, 245, 240), SMOOTH, OPTS)
				PartKit.Box(model, "Reflector", Vector3.new(0.08, 0.12, 0.11) * M, CFrame.new(p + Vector3.new(0, 0.95 * M, 0)), if side > 0 then rgb(255, 150, 20) else rgb(240, 240, 240), Enum.Material.Neon, OPTS)
			end
		end
		if rng:NextNumber() < 0.4 then
			local p = a + dir * len * 0.5 + right * (half + 2 * M)
			PartKit.Box(model, "MarkerPost", Vector3.new(0.08, 1.4, 0.08) * M, CFrame.new(p + Vector3.new(0, 0.7 * M, 0)), rgb(180, 180, 184), METAL, OPTS)
			local plate = PartKit.Box(model, "MileMarker", Vector3.new(0.3, 0.6, 0.03) * M, CFrame.lookAt(p + Vector3.new(0, 1.3 * M, 0), p + Vector3.new(0, 1.3 * M, 0) - flat), rgb(20, 110, 60), SMOOTH, OPTS)
			PartKit.Sign(plate, Enum.NormalId.Front, "MILE\n" .. tostring(rng:NextInteger(2, 48)), rgb(255, 255, 255), nil, Enum.Font.GothamBold, 120)
		end
	end
	-- pavements
	if grid then
		for _, side in { -1, 1 } do
			local mid = half + sidewalk / 2
			local function walk(s: number, u: number, yaw: number?): CFrame
				local p = a + dir * s + right * side * (half + u) + Vector3.new(0, Layout.CURB_Y - Layout.ROAD_Y + 0.02, 0)
				return CFrame.lookAt(p, p + flat) * CFrame.Angles(0, yaw or 0, 0)
			end
			-- slab joints every 3 m
			for k = 1, math.floor(len / (3 * M)) do
				decal(model, "Joint", Vector3.new(sidewalk / M - 0.4, 0.004, 0.04), walk(k * 3 * M, sidewalk / 2), rgb(150, 148, 142), SMOOTH, 0.3)
			end
			-- gum and stains
			for _ = 1, rng:NextInteger(3, 6) do
				disc(model, "Gum", rng:NextNumber(0.04, 0.09), 0.004, walk(rng:NextNumber(0, len), rng:NextNumber(1, sidewalk / M - 0.5) * M), rgb(70, 70, 74), SMOOTH, 0.2)
			end
			if rng:NextNumber() < 0.5 then
				disc(model, "Stain", rng:NextNumber(0.4, 0.9), 0.004, walk(rng:NextNumber(0, len), rng:NextNumber(1, 3) * M), rgb(120, 116, 108), SMOOTH, 0.5)
			end
			-- litter
			for _ = 1, math.floor(rng:NextInteger(2, 6) * per) do
				local cf = walk(rng:NextNumber(0, len), rng:NextNumber(0.3, sidewalk / M - 0.3) * M, rng:NextNumber(0, 6))
				local color = LITTER[rng:NextInteger(1, #LITTER)]
				if rng:NextNumber() < 0.5 then
					PartKit.Cylinder(model, "Cup", 0.08 * M, 0.12 * M, cf * CFrame.new(0, 0.04 * M, 0) * CFrame.Angles(0, 0, 0), color, SMOOTH, OPTS)
				else
					decal(model, "Paper", Vector3.new(0.21, 0.004, 0.28), cf, color)
				end
			end
			-- a dockless scooter by the kerb
			for _ = 1, if rng:NextNumber() < 0.6 * per then rng:NextInteger(1, 2) else 0 do
				scooter(model, walk(rng:NextNumber(0.1, 0.9) * len, 0.7 * M, rng:NextNumber(-0.5, 0.5) + (if side > 0 then math.pi else 0)), SCOOTERS[rng:NextInteger(1, #SCOOTERS)])
			end
			-- newspaper boxes in a row by the kerb
			if rng:NextNumber() < 0.35 * per then
				local cf = walk(rng:NextNumber(0.1, 0.9) * len, 0.9 * M, if side > 0 then math.pi else 0)
				local colors = { rgb(30, 90, 170), rgb(200, 40, 40), rgb(250, 200, 30), rgb(40, 140, 70) }
				for k = 0, rng:NextInteger(1, 3) do
					local c = colors[rng:NextInteger(1, #colors)]
					PartKit.Box(model, "NewsBox", Vector3.new(0.45, 1.0, 0.45) * M, cf * CFrame.new((k - 1) * 0.5 * M, 0.5 * M, 0), c, SMOOTH, OPTS)
					PartKit.Box(model, "NewsWindow", Vector3.new(0.34, 0.25, 0.02) * M, cf * CFrame.new((k - 1) * 0.5 * M, 0.8 * M, -0.23 * M), rgb(200, 220, 230), Enum.Material.Glass, OPTS)
				end
			end
			-- a café sandwich board outside the shops
			if rng:NextNumber() < 0.4 * per then
				local cf = walk(rng:NextNumber(0.1, 0.9) * len, (sidewalk / M - 1.4) * M, rng:NextNumber(-0.3, 0.3) + (if side > 0 then math.pi / 2 else -math.pi / 2))
				for _, lean in { -1, 1 } do
					local board = PartKit.Box(model, "SandwichBoard", Vector3.new(0.6, 0.9, 0.03) * M, cf * CFrame.new(0, 0.44 * M, lean * 0.12 * M) * CFrame.Angles(lean * math.rad(12), 0, 0), rgb(36, 44, 38), SMOOTH, OPTS)
					local specials = { "TODAY:\nCAFECITO\n$1", "HAPPY\nHOUR\n4-7PM", "FRESH\nJUICE\n🥭", "WE'RE\nOPEN\n☺", "TRY THE\nCUBANO" }
					PartKit.Sign(board, if lean > 0 then Enum.NormalId.Back else Enum.NormalId.Front, specials[rng:NextInteger(1, #specials)], rgb(245, 240, 225), nil, Enum.Font.PermanentMarker, 100)
				end
			end
			-- rubbish bags by the kerb
			if rng:NextNumber() < 0.25 then
				local cf = walk(rng:NextNumber(0.1, 0.9) * len, 0.6 * M)
				for k = 0, rng:NextInteger(1, 3) do
					PartKit.Ellipsoid(model, "BinBag", Vector3.new(0.55, 0.65, 0.5) * M, cf * CFrame.new((k - 1) * 0.45 * M, 0.3 * M, (k % 2) * 0.3 * M) * CFrame.Angles(0, k, 0.2), rgb(26, 26, 28), Enum.Material.Plastic, OPTS)
				end
			end
			-- a planter by the shops
			if rng:NextNumber() < 0.2 then
				local cf = walk(rng:NextNumber(0.2, 0.8) * len, (sidewalk / M - 0.7) * M)
				PartKit.Box(model, "Planter", Vector3.new(1.0, 0.6, 1.0) * M, cf * CFrame.new(0, 0.3 * M, 0), rgb(196, 192, 184), Enum.Material.Concrete, OPTS)
				PartKit.Ellipsoid(model, "Shrub", Vector3.new(0.9, 0.7, 0.9) * M, cf * CFrame.new(0, 0.85 * M, 0), rgb(60, 120 + rng:NextInteger(0, 40), 50), Enum.Material.Grass, OPTS)
			end
			-- roadworks: a patch of fresh asphalt, cones and a sign
			if rng:NextNumber() < 0.06 then
				local s = rng:NextNumber(0.2, 0.7) * len
				decal(model, "FreshPatch", Vector3.new(1.6, 0.015, 3.5), road(s + 2 * M, side * (half - 1.6 * M)), rgb(30, 30, 34), ASPHALT)
				for k = 0, 3 do
					cone(model, road(s + k * 1.5 * M, side * (half - 3.2 * M)))
				end
				local frame = road(s - 1.5 * M, side * (half - 1.4 * M), if side > 0 then math.pi else 0)
				local board = PartKit.Box(model, "WorkSign", Vector3.new(0.9, 0.8, 0.04) * M, frame * CFrame.new(0, 0.9 * M, 0) * CFrame.Angles(math.rad(-12), 0, 0), rgb(255, 140, 20), SMOOTH, OPTS)
				PartKit.Sign(board, Enum.NormalId.Front, "ROAD\nWORK\nAHEAD", rgb(20, 20, 20), nil, Enum.Font.GothamBlack, 120)
				PartKit.Sign(board, Enum.NormalId.Back, "ROAD\nWORK\nAHEAD", rgb(20, 20, 20), nil, Enum.Font.GothamBlack, 120)
			end
			local _ = mid
		end
	end
	return model
end

--------------------------------------------------------------------------------
-- Buildings
--------------------------------------------------------------------------------

local TAGS = { "305", "VIBEZ", "SOL", "ZAP!", "OLA", "MIAMI", "KING", "FLY", "WAVE", "LOCO", "NEON", "RIDE" }
local TAG_COLORS = { rgb(255, 60, 140), rgb(60, 220, 255), rgb(255, 220, 40), rgb(120, 255, 80), rgb(255, 120, 30), rgb(170, 90, 255) }
local TAG_FONTS = { Enum.Font.PermanentMarker, Enum.Font.Bangers, Enum.Font.Creepster, Enum.Font.FredokaOne }

local BUILDING_MODELS: { [string]: boolean } = { Building = true, Podium = true, DecoHotel = true }

-- Is something solid right outside this face (a neighbour built against it)?
local offline = false
local function blocked(p: Vector3, exclude: { Instance }): boolean
	if offline then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hits = Workspace:GetPartBoundsInBox(CFrame.new(p), Vector3.new(2, 2, 2), params)
	for _, h in hits do
		if h.Size.Y > 12 and h.Transparency < 0.5 then
			return true
		end
	end
	return false
end

local function buildBuilding(unit: Unit): Model?
	local body = unit.Body :: BasePart
	local owner = unit.Model :: Model
	if body.Parent == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "BuildingDetail"
	local rng = Random.new(unit.Seed)
	local size = body.Size
	local cf = body.CFrame
	local bottom = cf.Position.Y - size.Y / 2
	local top = cf.Position.Y + size.Y / 2
	-- the building's real ground: a podium body starts above a lobby; a mid-rise above its shop
	local ground = Layout.CURB_Y
	local floorH = 3.6 * M
	local floors = math.max(1, math.floor((top - ground) / floorH))
	local acCount, balconyCount = 0, 0
	local graffiti = false
	for _, out in { cf.RightVector, -cf.RightVector, cf.LookVector, -cf.LookVector } do
		local localOut = cf:VectorToObjectSpace(out)
		local half = math.abs(localOut.X) * size.X / 2 + math.abs(localOut.Z) * size.Z / 2
		local faceW = math.abs(localOut.X) * size.Z + math.abs(localOut.Z) * size.X
		local face = CFrame.lookAt(cf.Position + out * half, cf.Position + out * (half + 1))
		-- skip faces built against a neighbour
		local probe = cf.Position + out * (half + 1.5)
		if not blocked(Vector3.new(probe.X, bottom + math.min(size.Y / 2, 20), probe.Z), { owner, folder }) then
			local function onFace(x: number, y: number, outM: number): CFrame
				-- `y` is world height
				return face * CFrame.new(x, y - face.Position.Y, -outM * M)
			end
			-- window air conditioners under some windows
			local cols = math.max(1, math.floor(faceW / (4 * M)))
			for f = 1, floors - 1 do
				for c = 0, cols - 1 do
					if acCount < 24 and rng:NextNumber() < 0.14 then
						acCount += 1
						local x = -faceW / 2 + (c + 0.5) * faceW / cols
						local y = ground + f * floorH + 0.5 * M
						if y > bottom + 1 and y < top - 2 then
							PartKit.Box(model, "AC", Vector3.new(0.7, 0.45, 0.55) * M, onFace(x, y, 0.27), rgb(214, 212, 204), SMOOTH, OPTS)
							PartKit.Box(model, "ACGrille", Vector3.new(0.6, 0.35, 0.02) * M, onFace(x, y, 0.56), rgb(120, 120, 124), Enum.Material.DiamondPlate, OPTS)
							PartKit.Box(model, "ACBracket", Vector3.new(0.6, 0.04, 0.5) * M, onFace(x, y - 0.25 * M, 0.25), rgb(60, 60, 64), METAL, OPTS)
						end
					end
				end
			end
			-- balconies up the middle of tall faces
			if floors >= 4 and faceW > 14 * M and rng:NextNumber() < 0.45 then
				local bx = rng:NextNumber(-0.3, 0.3) * faceW
				for f = 1, floors - 1, if rng:NextNumber() < 0.5 then 1 else 2 do
					local y = ground + f * floorH
					if balconyCount < 12 and y > bottom + 1 and y < top - 2 then
						balconyCount += 1
						PartKit.Box(model, "Balcony", Vector3.new(3.2, 0.18, 1.3) * M, onFace(bx, y, 0.65), rgb(226, 224, 218), Enum.Material.Concrete, OPTS)
						local rail = PartKit.Box(model, "BalconyGlass", Vector3.new(3.2, 1.0, 0.03) * M, onFace(bx, y + 0.6 * M, 1.28), rgb(170, 200, 214), Enum.Material.Glass, OPTS)
						rail.Transparency = 0.5
						PartKit.Box(model, "Handrail", Vector3.new(3.2, 0.05, 0.06) * M, onFace(bx, y + 1.1 * M, 1.28), rgb(200, 204, 208), METAL, OPTS)
						if rng:NextNumber() < 0.4 then
							PartKit.Box(model, "Towel", Vector3.new(0.6, 0.5, 0.02) * M, onFace(bx + 0.6 * M, y + 0.85 * M, 1.31), TAG_COLORS[rng:NextInteger(1, #TAG_COLORS)], Enum.Material.Fabric, OPTS)
						end
					end
				end
			end
			-- a drainpipe down one end
			if rng:NextNumber() < 0.6 then
				local x = (if rng:NextNumber() < 0.5 then -1 else 1) * (faceW / 2 - 0.4 * M)
				PartKit.Cylinder(model, "Downpipe", 0.12 * M, top - ground, onFace(x, (top + ground) / 2, 0.1) * CFrame.Angles(0, 0, math.pi / 2), rgb(170, 170, 166), METAL, OPTS)
			end
			-- meters and a utility box at street level
			if rng:NextNumber() < 0.4 then
				local x = rng:NextNumber(-0.4, 0.4) * faceW
				PartKit.Box(model, "UtilityBox", Vector3.new(0.7, 1.0, 0.3) * M, onFace(x, ground + 1.2 * M, 0.15), rgb(140, 146, 140), METAL, OPTS)
				for k = 0, 2 do
					PartKit.Cylinder(model, "Meter", 0.22 * M, 0.12 * M, onFace(x + (k - 1) * 0.3 * M, ground + 0.55 * M, 0.06) * CFrame.Angles(0, math.pi / 2, 0), rgb(200, 200, 196), METAL, OPTS)
				end
			end
			-- a tag at street level
			if not graffiti and bottom < ground + 2 and rng:NextNumber() < 0.3 then
				graffiti = true
				local wall = PartKit.Box(model, "Graffiti", Vector3.new(math.min(faceW / M - 1, 6), 1.6, 0.02) * M, onFace(rng:NextNumber(-0.25, 0.25) * faceW, ground + 1.3 * M, 0.02), rgb(255, 255, 255), SMOOTH, OPTS)
				wall.Transparency = 1
				local label = PartKit.Sign(wall, Enum.NormalId.Front, TAGS[rng:NextInteger(1, #TAGS)], TAG_COLORS[rng:NextInteger(1, #TAG_COLORS)], nil, TAG_FONTS[rng:NextInteger(1, #TAG_FONTS)], 40)
				label.Rotation = rng:NextNumber(-8, 8)
				local stroke = Instance.new("UIStroke")
				stroke.Color = rgb(20, 20, 24)
				stroke.Thickness = 3
				stroke.Parent = label
			end
		end
	end
	-- blinds and curtains half drawn in some windows
	local BLINDS = { rgb(236, 230, 214), rgb(214, 196, 160), rgb(180, 60, 60), rgb(70, 110, 160), rgb(240, 240, 236), rgb(120, 150, 110) }
	local shades = 0
	for _, pane in owner:GetChildren() do
		if pane:IsA("BasePart") and pane.Name == "Window" and shades < 40 and rng:NextNumber() < 0.3 then
			shades += 1
			local s = pane.Size
			local drawn = rng:NextNumber(0.25, 0.7)
			local blind = PartKit.Box(model, "Blind", Vector3.new(s.X * 0.96, s.Y * drawn, 0.05), pane.CFrame * CFrame.new(0, s.Y * (1 - drawn) / 2, -s.Z / 2 - 0.03), BLINDS[rng:NextInteger(1, #BLINDS)], Enum.Material.Fabric, OPTS)
			local _ = blind
		end
	end
	-- the roof: satellite dishes and sometimes a mast
	for _ = 1, rng:NextInteger(0, 2) do
		local p = cf * CFrame.new(rng:NextNumber(-0.4, 0.4) * size.X, size.Y / 2, rng:NextNumber(-0.4, 0.4) * size.Z)
		local dish = CFrame.new(p.Position + Vector3.new(0, 0.9 * M, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0) * CFrame.Angles(math.rad(-50), 0, 0)
		PartKit.Box(model, "DishPole", Vector3.new(0.06, 0.9, 0.06) * M, CFrame.new(p.Position + Vector3.new(0, 0.45 * M, 0)), rgb(120, 120, 124), METAL, OPTS)
		PartKit.Ellipsoid(model, "Dish", Vector3.new(0.9, 0.9, 0.18) * M, dish, rgb(236, 236, 232), SMOOTH, OPTS)
	end
	if rng:NextNumber() < 0.2 then
		local p = cf * CFrame.new(rng:NextNumber(-0.3, 0.3) * size.X, size.Y / 2, rng:NextNumber(-0.3, 0.3) * size.Z)
		PartKit.Cylinder(model, "Mast", 0.1 * M, 6 * M, CFrame.new(p.Position + Vector3.new(0, 3 * M, 0)) * CFrame.Angles(0, 0, math.pi / 2), rgb(160, 160, 164), METAL, OPTS)
		PartKit.Ball(model, "MastLight", 0.25 * M, p.Position + Vector3.new(0, 6.1 * M, 0), rgb(255, 40, 40), Enum.Material.Neon, OPTS)
	end
	-- an OPEN sign in the shop window
	for _, glass in owner:GetChildren() do
		if glass:IsA("BasePart") and glass.Name == "ShopGlass" and glass.Size.X > 6 then
			local sign = PartKit.Box(model, "OpenSign", Vector3.new(1.0, 0.45, 0.04) * M, glass.CFrame * CFrame.new(rng:NextNumber(-0.3, 0.3) * glass.Size.X, glass.Size.Y * 0.15, 0.35), rgb(20, 20, 24), SMOOTH, OPTS)
			sign.Transparency = 1
			local label = PartKit.Sign(sign, Enum.NormalId.Front, "OPEN", if rng:NextNumber() < 0.5 then rgb(255, 50, 80) else rgb(60, 200, 255), nil, Enum.Font.Bangers, 60)
			local gui = label.Parent :: SurfaceGui
			gui.LightInfluence = 0
			gui.Brightness = 2
			local stroke = Instance.new("UIStroke")
			stroke.Color = rgb(255, 255, 255)
			stroke.Thickness = 1.5
			stroke.Transparency = 0.3
			stroke.Parent = label
			break
		end
	end
	return model
end

local function watchBodies(city: Instance)
	local function found(d: Instance)
		if d:IsA("BasePart") and d.Name == "Body" and d.Size.Y > 20 then
			local owner = d.Parent
			if owner and owner:IsA("Model") and BUILDING_MODELS[owner.Name] and not bodies[d] then
				local unit: Unit = { Kind = "Building", Center = d.Position, Seed = math.floor(math.abs(d.Position.X * 3 + d.Position.Z * 7)) % 1000003, Body = d, Model = owner }
				bodies[d] = unit
				add(unit)
			end
		end
	end
	for _, d in city:GetDescendants() do
		found(d)
	end
	city.DescendantAdded:Connect(found)
	city.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then
			local unit = bodies[d]
			if unit then
				bodies[d] = nil
				remove(unit)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Streaming the detail in and out round the camera
--------------------------------------------------------------------------------

local function update()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local ultra = Graphics.Current().Shadows
	local roadRange = (if ultra then 700 else 380) * MAP
	local buildingRange = (if ultra then 450 else 240) * MAP
	local from = camera.CFrame.Position
	local reach = math.max(roadRange, buildingRange)
	local budget = if ultra then 10 else 5
	-- drop what's far
	for unit, model in built do
		local range = if unit.Kind == "Road" then roadRange else buildingRange
		if (unit.Center - from).Magnitude > range * 1.25 then
			model:Destroy()
			built[unit] = nil
		end
	end
	-- build what's near, nearest first
	local want: { { Unit: Unit, D: number } } = {}
	local c0x, c0z = math.floor((from.X - reach) / CELL), math.floor((from.Z - reach) / CELL)
	local c1x, c1z = math.floor((from.X + reach) / CELL), math.floor((from.Z + reach) / CELL)
	for cx = c0x, c1x do
		for cz = c0z, c1z do
			local list = units[cx * 100000 + cz]
			if list then
				for _, unit in list do
					if not built[unit] then
						local d = (unit.Center - from).Magnitude
						if d < (if unit.Kind == "Road" then roadRange else buildingRange) then
							table.insert(want, { Unit = unit, D = d })
						end
					end
				end
			end
		end
	end
	table.sort(want, function(x, y)
		return x.D < y.D
	end)
	for i = 1, math.min(#want, budget) do
		local unit = want[i].Unit
		local model = if unit.Kind == "Road" then buildRoad(unit) else buildBuilding(unit)
		if model then
			model.Parent = folder
			built[unit] = model
		end
	end
end

function CityDetail.Init()
	folder = Instance.new("Folder")
	folder.Name = "CityDetail"
	folder.Parent = Workspace
	indexRoads()
	task.spawn(function()
		local city = Workspace:WaitForChild("City", 600)
		if city then
			watchBodies(city)
		end
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= 0.25 then
			since = 0
			update()
		end
	end)
end

-- For offline previews: the detail of the roads and buildings of `city` near a point, into `parent`
function CityDetail.BuildAround(city: Instance, parent: Instance, at: Vector3, radius: number): number
	folder = parent :: Folder
	offline = true
	if next(units) == nil then
		indexRoads()
	end
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Body" and d.Size.Y > 20 and (d.CFrame.Position - at).Magnitude < radius then
			local owner = d.Parent
			if owner and owner:IsA("Model") and BUILDING_MODELS[owner.Name] then
				add({ Kind = "Building", Center = d.CFrame.Position, Seed = 7, Body = d, Model = owner })
			end
		end
	end
	local n = 0
	for _, list in units do
		for _, unit in list do
			if (unit.Center - at).Magnitude < radius then
				local model = if unit.Kind == "Road" then buildRoad(unit) else buildBuilding(unit)
				if model then
					model.Parent = parent
					n += 1
				end
			end
		end
	end
	return n
end

return CityDetail
