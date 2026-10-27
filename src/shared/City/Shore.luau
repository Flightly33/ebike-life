--[[
	Shore: everything where the land meets Biscayne Bay and the ocean. The ground tiles (land
	only), the bay floor, the mainland's seawall and baywalk, the island's rock edges and its beach
	sloping into the surf, the two causeways across the bay, and the marina's docks and boats.

	The water itself is Terrain, filled at runtime by CityService from Layout.Water (Terrain isn't
	part of the baked model). Bikes that touch it splash and are put back on the shore.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Detail = require(script.Parent.Detail)
local Roads = require(script.Parent.Roads)
local PartKit = require(script.Parent.Parent.PartKit)

local Shore = {}

local C = Props.Palette
local Y = Layout.CURB_Y
local CONCRETE = Enum.Material.Concrete
local SMOOTH = Enum.Material.SmoothPlastic
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }

local SAND = Color3.fromRGB(226, 208, 168)
local WET_SAND = Color3.fromRGB(190, 170, 130)
local ROCK = Color3.fromRGB(128, 124, 116)
local SEAWALL = Color3.fromRGB(186, 182, 172)
local BAYWALK = Color3.fromRGB(214, 200, 178)
local DECK_WOOD = Color3.fromRGB(150, 116, 80)

local MAX_PART = 2000

-- Boxes covering a rect, split into pieces no bigger than MAX_PART (the part size limit)
local function tiles(parent: Instance, name: string, rect: LayoutModule.Rect, top: number, thickness: number, color: Color3, material: Enum.Material, surface: string?)
	local w, d = rect.MaxX - rect.MinX, rect.MaxZ - rect.MinZ
	local nx, nz = math.ceil(w / MAX_PART), math.ceil(d / MAX_PART)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local sx, sz = w / nx, d / nz
			local cx, cz = rect.MinX + sx * (i + 0.5), rect.MinZ + sz * (j + 0.5)
			local p = PartKit.Box(parent, name, Vector3.new(sx, thickness, sz), CFrame.new(cx, top - thickness / 2, cz), color, material)
			if surface then
				p:SetAttribute("Surface", surface)
			end
		end
	end
end

-- A rock slope from the ground edge at `top` (y = 0) out and down to the bay floor, facing `out`,
-- `length` long (centred on `top`), in pieces within the part size limit
local function revetment(parent: Instance, top: Vector3, out: Vector3, length: number)
	local run = (0 - Layout.SEABED_Y) * 1.4
	local along = Vector3.new(out.Z, 0, -out.X)
	local n = math.ceil(length / MAX_PART)
	for k = 0, n - 1 do
		local c = top + along * (-length / 2 + length * (k + 0.5) / n)
		local low = Vector3.new(c.X, Layout.SEABED_Y, c.Z) + out * run
		local slope = PartKit.Ramp(parent, "Revetment", low, c, length / n, ROCK, Enum.Material.Rock)
		slope:SetAttribute("Surface", "Dirt")
	end
end

-- A low dock or causeway guard rail (metal W-beam on posts)
local function guardRail(parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local steel = Color3.fromRGB(176, 180, 184)
	PartKit.Bar(parent, "GuardRail", a + Vector3.new(0, 2.1, 0), b + Vector3.new(0, 2.1, 0), 0.4, 1.1, steel, Enum.Material.Metal)
	for k = 0, math.floor(length / 14) do
		PartKit.Post(parent, "RailPost", 0.5, 2.4, a + dir * (k * 14), steel, Enum.Material.Metal, DECOR)
	end
end

-- A moored boat at `cf` (on the water line, facing its bow): motor yachts, sailboats, centre consoles
function Shore.Boat(parent: Instance, cf: CFrame, rng: Random)
	local model = PartKit.Model(parent, "Boat")
	local kind = rng:NextInteger(1, 3)
	local hullColor = ({ Color3.fromRGB(245, 245, 242), Color3.fromRGB(240, 238, 230), Color3.fromRGB(28, 46, 84), Color3.fromRGB(200, 40, 40) })[rng:NextInteger(1, 4)]
	local length = if kind == 1 then rng:NextNumber(46, 62) elseif kind == 2 then rng:NextNumber(30, 40) else rng:NextNumber(20, 28)
	local beam = length * 0.3
	local freeboard = if kind == 1 then 5 else 3.4
	-- hull: a box and a wedge bow
	PartKit.Box(model, "Hull", Vector3.new(beam, freeboard + 2, length * 0.72), cf * CFrame.new(0, freeboard / 2 - 1, length * 0.14), hullColor, SMOOTH)
	-- a pointed bow: two wedges, their straight faces meeting on the centre line
	for _, side in { -1, 1 } do
		PartKit.Wedge(model, "Bow", Vector3.new(freeboard + 2, beam / 2, length * 0.28), cf * CFrame.new(side * beam / 4, freeboard / 2 - 1, -length * 0.36) * CFrame.Angles(0, 0, -side * math.pi / 2), hullColor, SMOOTH)
	end
	PartKit.Box(model, "Stripe", Vector3.new(beam + 0.1, 0.5, length * 0.72), cf * CFrame.new(0, freeboard - 1.2, length * 0.14), Color3.fromRGB(30, 80, 140), SMOOTH, DECOR)
	PartKit.Box(model, "Deck", Vector3.new(beam - 0.8, 0.3, length * 0.7), cf * CFrame.new(0, freeboard + 0.15, length * 0.14), Color3.fromRGB(196, 170, 130), Enum.Material.WoodPlanks)
	if kind == 1 then
		-- motor yacht: two cabin tiers with dark glass
		PartKit.Box(model, "Cabin", Vector3.new(beam - 3, 6, length * 0.42), cf * CFrame.new(0, freeboard + 3.3, length * 0.08), Color3.fromRGB(250, 250, 248), SMOOTH)
		local glass = PartKit.Box(model, "CabinGlass", Vector3.new(beam - 2.8, 2.4, length * 0.4), cf * CFrame.new(0, freeboard + 4, length * 0.08), Color3.fromRGB(30, 40, 50), Enum.Material.Glass, DECOR)
		glass.Reflectance = 0.3
		PartKit.Box(model, "Flybridge", Vector3.new(beam - 5, 3.5, length * 0.22), cf * CFrame.new(0, freeboard + 8, length * 0.12), Color3.fromRGB(250, 250, 248), SMOOTH)
		PartKit.Post(model, "Radar", 0.4, 4, (cf * CFrame.new(0, freeboard + 9.7, length * 0.1)).Position, Color3.fromRGB(230, 230, 230), Enum.Material.Metal, DECOR)
	elseif kind == 2 then
		-- sailboat: a low cabin, a mast and a furled boom
		PartKit.Box(model, "Cabin", Vector3.new(beam - 3, 2.6, length * 0.3), cf * CFrame.new(0, freeboard + 1.4, length * 0.02), Color3.fromRGB(250, 250, 248), SMOOTH)
		PartKit.Post(model, "Mast", 0.7, length * 1.3, (cf * CFrame.new(0, freeboard, -length * 0.08)).Position, Color3.fromRGB(220, 222, 226), Enum.Material.Metal)
		PartKit.Bar(model, "Boom", (cf * CFrame.new(0, freeboard + 4, -length * 0.08)).Position, (cf * CFrame.new(0, freeboard + 4, length * 0.32)).Position, 1.2, 1.2, Color3.fromRGB(20, 60, 120), Enum.Material.Fabric, NO_COLLIDE)
	else
		-- centre console with twin outboards
		PartKit.Box(model, "Console", Vector3.new(3, 3.5, 3), cf * CFrame.new(0, freeboard + 1.9, -length * 0.02), Color3.fromRGB(250, 250, 248), SMOOTH)
		PartKit.Box(model, "TTop", Vector3.new(5.5, 0.3, 6), cf * CFrame.new(0, freeboard + 7, -length * 0.02), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric, NO_COLLIDE)
		for _, x in { -1.4, 1.4 } do
			PartKit.Box(model, "Outboard", Vector3.new(1.4, 4, 1.8), cf * CFrame.new(x, freeboard - 0.5, length * 0.52), Color3.fromRGB(240, 240, 240), SMOOTH, DECOR)
		end
	end
	return model
end

local function palmsAlong(parent: Instance, a: Vector3, b: Vector3, every: number, rng: Random)
	local length = (b - a).Magnitude
	local n = math.floor(length / every)
	for k = 0, n do
		Props.Palm(parent, a:Lerp(b, (k + 0.5) / (n + 1)), rng)
	end
end

function Shore.Build(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "Shore")
	local ground = PartKit.Folder(city, "Ground")
	local W = Layout.WORLD_HALF
	local isl = Layout.ISLAND
	local shoreX = Layout.SHORE_X

	-- Land: the mainland's grass, the island's (its beach is its own slope)
	tiles(ground, "Grass", { MinX = -W, MaxX = shoreX, MinZ = -W, MaxZ = W }, 0, 4, C.Grass, Enum.Material.Grass, "Grass")
	tiles(ground, "Grass", { MinX = isl.MinX, MaxX = Layout.BEACH_X, MinZ = isl.MinZ, MaxZ = isl.MaxZ }, 0, 4, C.Grass, Enum.Material.Grass, "Grass")
	-- the bay and ocean floor
	for _, rect in Layout.Water do
		tiles(ground, "Seabed", rect, Layout.SEABED_Y, 4, Color3.fromRGB(196, 186, 150), Enum.Material.Sand, "Sand")
	end
	-- invisible walls at the map edge
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local along = Vector3.new(d.Z, 0, -d.X)
		for k = 0, 3 do
			local center = d * (W + 2) + along * (-W + W / 4 + k * W / 2) + Vector3.new(0, 100, 0)
			local size = if d.X ~= 0 then Vector3.new(4, 260, W / 2 + 8) else Vector3.new(W / 2 + 8, 260, 4)
			local wall = PartKit.Box(ground, "Boundary", size, CFrame.new(center), Color3.new(1, 1, 1), SMOOTH, { Transparency = 1, Shadow = false })
			wall:SetAttribute("Surface", "Wall")
		end
	end

	-- The mainland's seawall, the full length of the shore, and the baywalk along Biscayne Blvd
	local walls = PartKit.Folder(folder, "Seawall")
	local wallTop = Y
	local wallH = wallTop - Layout.SEABED_Y
	for k = 0, 3 do
		PartKit.Box(walls, "Seawall", Vector3.new(3, wallH, W / 2), CFrame.new(shoreX - 1.5, Layout.SEABED_Y + wallH / 2, -W + W / 4 + k * W / 2), SEAWALL, CONCRETE)
	end
	local walk = PartKit.Folder(folder, "Baywalk")
	local bayEdge = Layout.Line(Layout.BAY_INDEX) + Layout.AVENUE_WIDTH / 2
	local walkEnd = Layout.RING_HALF + 40
	local gaps = {}
	for _, z in Layout.CAUSEWAY_ZS do
		table.insert(gaps, { z - (Layout.STREET_WIDTH + 4) / 2 - 2, z + (Layout.STREET_WIDTH + 4) / 2 + 2 })
	end
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	local pieces = {}
	local from = -walkEnd
	for _, gap in gaps do
		table.insert(pieces, { from, gap[1] })
		from = gap[2]
	end
	table.insert(pieces, { from, walkEnd })
	local thickness = Y + 0.4
	for _, piece in pieces do
		local z0, z1 = piece[1], piece[2]
		local cz, d = (z0 + z1) / 2, z1 - z0
		local w = shoreX - 3 - bayEdge
		local pave = PartKit.Box(walk, "Pavement", Vector3.new(w, thickness, d), CFrame.new(bayEdge + w / 2, Y - thickness / 2, cz), BAYWALK, Enum.Material.Pavement)
		pave:SetAttribute("Surface", "Sidewalk")
		PartKit.Box(walk, "Kerb", Vector3.new(1.1, 0.06, d), CFrame.new(bayEdge + 0.55, Y + 0.01, cz), C.Kerb, CONCRETE, DECOR)
		-- a band of darker paving and the railing along the water (decorative: ride off it and
		-- you splash)
		PartKit.Box(walk, "Paving", Vector3.new(6, 0.05, d), CFrame.new(bayEdge + 16, Y + 0.02, cz), Color3.fromRGB(176, 150, 126), Enum.Material.Brick, DECOR)
		PartKit.Box(walk, "Railing", Vector3.new(0.3, 0.3, d), CFrame.new(shoreX - 3.6, Y + 3.4, cz), Color3.fromRGB(235, 235, 232), Enum.Material.Metal, DECOR)
		PartKit.Box(walk, "Railing", Vector3.new(0.25, 0.25, d), CFrame.new(shoreX - 3.6, Y + 1.8, cz), Color3.fromRGB(235, 235, 232), Enum.Material.Metal, DECOR)
		local n = math.floor(d / 9)
		for k = 0, n do
			PartKit.Post(walk, "RailPost", 0.35, 3.4, Vector3.new(shoreX - 3.6, Y, z0 + k * d / n), Color3.fromRGB(235, 235, 232), Enum.Material.Metal, DECOR)
		end
		-- palms, lights and benches
		palmsAlong(walk, Vector3.new(bayEdge + 9, Y, z0 + 6), Vector3.new(bayEdge + 9, Y, z1 - 6), 44, rng)
		local lights = math.floor(d / 90)
		for k = 1, lights do
			local z = z0 + k * d / (lights + 1)
			Props.StreetLight(walk, Vector3.new(bayEdge + 2.5, Y, z + 20), Vector3.new(-1, 0, 0))
			Props.Bench(walk, CFrame.new(shoreX - 7, Y, z) * CFrame.Angles(0, math.rad(-90), 0))
		end
	end

	-- The island's edges: rocks on the bay side and both ends, a seawall walk along West Ave
	local edges = PartKit.Folder(folder, "IslandEdge")
	revetment(edges, Vector3.new(isl.MinX, 0, 0), Vector3.new(-1, 0, 0), isl.MaxZ - isl.MinZ)
	revetment(edges, Vector3.new((isl.MinX + Layout.BEACH_X) / 2, 0, isl.MinZ), Vector3.new(0, 0, -1), Layout.BEACH_X - isl.MinX)
	revetment(edges, Vector3.new((isl.MinX + Layout.BEACH_X) / 2, 0, isl.MaxZ), Vector3.new(0, 0, 1), Layout.BEACH_X - isl.MinX)

	-- The beach: sand sloping from the beach walk into the surf, and on down to the ocean floor
	local beach = PartKit.Folder(folder, "Beach")
	local beachLen = isl.MaxZ - isl.MinZ
	for _, half in { -1, 1 } do
		local cz = half * beachLen / 4
		local sand = PartKit.Ramp(beach, "Sand", Vector3.new(Layout.SURF_X, Layout.WATER_Y, cz), Vector3.new(Layout.BEACH_X, 0, cz), beachLen / 2, SAND, Enum.Material.Sand)
		sand:SetAttribute("Surface", "Sand")
		local under = PartKit.Ramp(beach, "Shelf", Vector3.new(Layout.SURF_X + 150, Layout.SEABED_Y, cz), Vector3.new(Layout.SURF_X, Layout.WATER_Y - 0.05, cz), beachLen / 2, WET_SAND, Enum.Material.Sand)
		under:SetAttribute("Surface", "Sand")
	end
	-- the beach's ends drop to the rocks too
	for _, sz in { -1, 1 } do
		local z = sz * isl.MaxZ
		revetment(edges, Vector3.new((Layout.BEACH_X + Layout.SURF_X) / 2, 0, z), Vector3.new(0, 0, sz), Layout.SURF_X - Layout.BEACH_X)
	end
	-- lifeguard towers, umbrellas and loungers along the sand
	local towerColors = { Color3.fromRGB(255, 120, 160), Color3.fromRGB(80, 200, 220), Color3.fromRGB(255, 210, 60), Color3.fromRGB(150, 220, 120), Color3.fromRGB(255, 150, 70) }
	local umbrellaColors = { Color3.fromRGB(230, 60, 60), Color3.fromRGB(40, 120, 220), Color3.fromRGB(250, 200, 40), Color3.fromRGB(40, 170, 120), Color3.fromRGB(245, 245, 240) }
	local sandAt = function(x: number): number
		return (Layout.SURF_X - x) / (Layout.SURF_X - Layout.BEACH_X) * (0 - Layout.WATER_Y) + Layout.WATER_Y
	end
	for k = 0, 7 do
		local z = isl.MinZ + 180 + k * (beachLen - 360) / 7
		local x = Layout.BEACH_X + 70
		Detail.LifeguardTower(beach, CFrame.new(x, sandAt(x), z) * CFrame.Angles(0, math.rad(-90), 0), towerColors[(k % #towerColors) + 1])
		for _ = 1, 6 do
			local ux = Layout.BEACH_X + rng:NextNumber(20, 120)
			local uz = z + rng:NextNumber(-130, 130)
			Detail.BeachUmbrella(beach, Vector3.new(ux, sandAt(ux), uz), umbrellaColors[rng:NextInteger(1, #umbrellaColors)], rng)
		end
	end

	-- Causeways: a road on a rock embankment across the bay, with verges, rails, lights and palms
	local causeways = PartKit.Folder(folder, "Causeways")
	for k, link in Layout.Causeways do
		local z = Layout.CAUSEWAY_ZS[k]
		local x0 = bayEdge
		local x1 = Layout.ISLAND_XS[1] - Layout.ISLAND_X_WIDTHS[1] / 2
		local roadW = Layout.STREET_WIDTH + 4
		local crest = 54 -- the embankment's width across its top
		local cx, len = (x0 + x1) / 2, x1 - x0
		Roads.Slab(causeways, "Causeway", Vector3.new(cx, 0, z), Vector3.new(len, 0, roadW))
		local a, b = Vector3.new(x0, Layout.ROAD_Y, z), Vector3.new(x1, Layout.ROAD_Y, z)
		Roads.Markings(causeways, a, b, "Street", roadW, 1)
		Roads.Line(causeways, a, b, roadW / 2 - 1.4, 0.45, C.White)
		Roads.Line(causeways, a, b, -(roadW / 2 - 1.4), 0.45, C.White)
		-- the embankment over the water (the ends are on land)
		local w0, w1 = shoreX, isl.MinX
		local wcx, wlen = (w0 + w1) / 2, w1 - w0
		local fillTop = Layout.ROAD_Y - 0.6
		PartKit.Box(causeways, "Fill", Vector3.new(wlen, fillTop - Layout.SEABED_Y, crest), CFrame.new(wcx, (fillTop + Layout.SEABED_Y) / 2, z), ROCK:Lerp(SAND, 0.4), Enum.Material.Rock)
		for _, side in { -1, 1 } do
			local verge = PartKit.Box(causeways, "Verge", Vector3.new(wlen, 0.6, (crest - roadW) / 2), CFrame.new(wcx, Layout.ROAD_Y - 0.3, z + side * (roadW / 2 + (crest - roadW) / 4)), C.Grass, Enum.Material.Grass)
			verge:SetAttribute("Surface", "Grass")
			revetment(causeways, Vector3.new(wcx, 0, z + side * crest / 2), Vector3.new(0, 0, side), wlen)
			guardRail(causeways, Vector3.new(w0 + 4, Layout.ROAD_Y, z + side * (roadW / 2 + 1)), Vector3.new(w1 - 4, Layout.ROAD_Y, z + side * (roadW / 2 + 1)))
			palmsAlong(causeways, Vector3.new(w0 + 30, Layout.ROAD_Y, z + side * (roadW / 2 + 8)), Vector3.new(w1 - 30, Layout.ROAD_Y, z + side * (roadW / 2 + 8)), 60, rng)
		end
		for i = 1, math.floor(wlen / 110) do
			local x = w0 + i * wlen / (math.floor(wlen / 110) + 1)
			local side = if i % 2 == 0 then 1 else -1
			Props.StreetLight(causeways, Vector3.new(x, Layout.ROAD_Y, z + side * (roadW / 2 + 3)), Vector3.new(0, 0, -side))
		end
		local _ = link
	end

	-- The marina: docks off the baywalk beside the Marina block, boats in the slips
	local marina = Layout.FindDistrict("Marina")
	if marina then
		local docks = PartKit.Folder(folder, "Docks")
		local z0, z1 = marina.MinZ + 20, marina.MaxZ - 20
		local deckY = Y - 0.2
		local mainX = shoreX + 50
		-- a gangway from the seawall, then a main walk along the shore with finger piers out east
		for _, z in { z0 + 40, z1 - 40 } do
			local g = PartKit.Box(docks, "Gangway", Vector3.new(50, 0.8, 10), CFrame.new(shoreX + 25, deckY - 0.4, z), DECK_WOOD, Enum.Material.WoodPlanks)
			g:SetAttribute("Surface", "Sidewalk")
		end
		local walkPart = PartKit.Box(docks, "Dock", Vector3.new(12, 0.8, z1 - z0), CFrame.new(mainX + 6, deckY - 0.4, (z0 + z1) / 2), DECK_WOOD, Enum.Material.WoodPlanks)
		walkPart:SetAttribute("Surface", "Sidewalk")
		local fingers = math.floor((z1 - z0) / 34)
		for i = 0, fingers - 1 do
			local z = z0 + 17 + i * 34
			local finger = PartKit.Box(docks, "Finger", Vector3.new(70, 0.8, 5), CFrame.new(mainX + 12 + 35, deckY - 0.4, z), DECK_WOOD, Enum.Material.WoodPlanks)
			finger:SetAttribute("Surface", "Sidewalk")
			for _, px in { 20, 45, 70 } do
				PartKit.Post(docks, "Piling", 1.4, deckY - Layout.SEABED_Y + 3, Vector3.new(mainX + 12 + px, Layout.SEABED_Y, z + 3), Color3.fromRGB(110, 90, 70), Enum.Material.Wood)
			end
			if rng:NextNumber() < 0.8 then
				Shore.Boat(docks, CFrame.lookAt(Vector3.new(mainX + 52, Layout.WATER_Y, z + 17), Vector3.new(mainX + 152, Layout.WATER_Y, z + 17)), rng)
			end
		end
		for k = 0, 3 do
			Props.StreetLight(docks, Vector3.new(mainX + 1, deckY, z0 + 20 + k * (z1 - z0 - 40) / 3), Vector3.new(1, 0, 0))
		end
		-- a few boats at anchor further out in the bay
		for _ = 1, 6 do
			local p = Vector3.new(rng:NextNumber(shoreX + 220, isl.MinX - 120), Layout.WATER_Y, rng:NextNumber(-1700, 1700))
			if math.abs(p.Z - Layout.I395_Z) > 120 and math.abs(math.abs(p.Z) - 900) > 120 then
				Shore.Boat(docks, CFrame.lookAt(p, p + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))), rng)
			end
		end
	end
	return folder
end

return Shore
