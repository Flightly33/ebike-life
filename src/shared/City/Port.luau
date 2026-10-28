--[[
	Port: the port island in the bay (Layout.PORT). Its south half is the container terminal (stacks
	in rows, ship-to-shore gantry cranes on the quay, a container ship alongside), its north half the
	cruise terminal with two cruise ships moored off it. A road runs down the middle from the bridge
	(Layout.PortRoad, drawn by Roads). The shipping lines and ships' names are made up.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local PartKit = require(script.Parent.Parent.PartKit)

local Port = {}

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local CONCRETE = Enum.Material.Concrete
local GLASS = Enum.Material.Glass
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }

local CONTAINERS = {
	Color3.fromRGB(176, 52, 40),
	Color3.fromRGB(36, 84, 150),
	Color3.fromRGB(48, 120, 70),
	Color3.fromRGB(226, 140, 30),
	Color3.fromRGB(140, 146, 152),
	Color3.fromRGB(236, 236, 232),
	Color3.fromRGB(110, 60, 120),
	Color3.fromRGB(30, 110, 130),
}
local CRANE = Color3.fromRGB(214, 70, 46)

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function skyline(model: Model)
	pcall(function()
		(model :: any).LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	end)
end

-- A ship-to-shore gantry crane on the quay at `base`, its boom reaching out over the water along
-- `out`
local function crane(parent: Instance, base: Vector3, out: Vector3)
	local model = PartKit.Model(parent, "GantryCrane")
	local look = CFrame.lookAt(base, base + out)
	local h, gauge, span = 90, 50, 30 -- leg height, along the boom, across the rails
	for _, z in { -gauge / 2, gauge / 2 } do
		for _, x in { -span / 2, span / 2 } do
			PartKit.Box(model, "Leg", Vector3.new(3, h, 3), look * CFrame.new(x, h / 2, z), CRANE, METAL)
		end
		PartKit.Box(model, "Sill", Vector3.new(span + 3, 3, 3), look * CFrame.new(0, h, z), CRANE, METAL)
	end
	for _, x in { -span / 2, span / 2 } do
		PartKit.Box(model, "Girder", Vector3.new(3, 4, gauge + 140), look * CFrame.new(x, h + 3, -70 + 10), CRANE, METAL, NO_COLLIDE)
		PartKit.Bar(model, "Stay", (look * CFrame.new(x, h + 40, gauge / 2)).Position, (look * CFrame.new(x, h + 4, -130)).Position, 1, 1, CRANE, METAL, DECOR)
	end
	PartKit.Box(model, "AFrame", Vector3.new(span + 3, 40, 3), look * CFrame.new(0, h + 22, gauge / 2), CRANE, METAL, NO_COLLIDE)
	PartKit.Box(model, "Cab", Vector3.new(10, 7, 10), look * CFrame.new(0, h - 4, -60), Color3.fromRGB(240, 240, 236), SMOOTH, NO_COLLIDE)
	PartKit.Box(model, "Machinery", Vector3.new(span, 10, 24), look * CFrame.new(0, h + 10, gauge / 2 + 16), Color3.fromRGB(240, 240, 236), SMOOTH, NO_COLLIDE)
	PartKit.Box(model, "Spreader", Vector3.new(10, 2, 44), look * CFrame.new(0, h - 26, -80), Color3.fromRGB(240, 200, 30), METAL, DECOR)
	skyline(model)
	return model
end

-- A ship's hull with a raked bow at `cf` (the waterline under its middle, bow along -Z)
local function hull(parent: Instance, cf: CFrame, length: number, beam: number, freeboard: number, color: Color3, bottom: Color3)
	local body = length * 0.86
	PartKit.Box(parent, "Hull", Vector3.new(beam, freeboard + 8, body), cf * CFrame.new(0, freeboard / 2 - 4, length * 0.07), color, SMOOTH)
	PartKit.Box(parent, "Boot", Vector3.new(beam + 0.2, 3, body), cf * CFrame.new(0, 0, length * 0.07), bottom, SMOOTH, DECOR)
	for _, side in { -1, 1 } do
		PartKit.Wedge(parent, "Bow", Vector3.new(freeboard + 8, beam / 2, length * 0.14), cf * CFrame.new(side * beam / 4, freeboard / 2 - 4, -length * 0.43) * CFrame.Angles(0, 0, -side * math.pi / 2), color, SMOOTH)
	end
end

-- A cruise ship: white decks stacked over the hull, balcony rows (their glass lights at night), a
-- funnel, orange lifeboats along the sides, a pool deck
function Port.CruiseShip(parent: Instance, cf: CFrame, length: number, rng: Random): Model
	local model = PartKit.Model(parent, "CruiseShip")
	local beam = length * 0.13
	local white = Color3.fromRGB(248, 248, 246)
	hull(model, cf, length, beam, 30, white, Color3.fromRGB(20, 40, 90))
	local decks = 12
	local deckH = 10.5 -- 2.9 m
	for k = 0, decks - 1 do
		local f = 1 - k * 0.04
		local y = 30 + k * deckH
		local dl = length * 0.78 * f
		PartKit.Box(model, "Deck", Vector3.new(beam - 2, deckH - 1, dl), cf * CFrame.new(0, y + deckH / 2, length * 0.06), white, SMOOTH)
		for _, side in { -1, 1 } do
			local band = PartKit.Box(model, "Window", Vector3.new(0.4, 3.6, dl - 8), cf * CFrame.new(side * (beam / 2 - 0.8), y + deckH / 2, length * 0.06), Color3.fromRGB(40, 56, 74), GLASS, DECOR)
			band.Reflectance = 0.3
		end
	end
	local top = 30 + decks * deckH
	-- the funnel and the bridge
	local funnelColor = pick(rng, { Color3.fromRGB(30, 60, 140), Color3.fromRGB(200, 40, 40), Color3.fromRGB(250, 196, 30) })
	PartKit.Box(model, "Funnel", Vector3.new(22, 30, 40), cf * CFrame.new(0, top + 15, length * 0.22), funnelColor, SMOOTH)
	PartKit.Box(model, "FunnelTop", Vector3.new(23, 4, 41), cf * CFrame.new(0, top + 32, length * 0.22), Color3.fromRGB(30, 30, 32), SMOOTH, DECOR)
	PartKit.Box(model, "Bridge", Vector3.new(beam + 6, 8, 14), cf * CFrame.new(0, top - 12, -length * 0.3), white, SMOOTH)
	local bridgeGlass = PartKit.Box(model, "Window", Vector3.new(beam + 6.2, 3, 14.2), cf * CFrame.new(0, top - 11, -length * 0.3), Color3.fromRGB(30, 40, 50), GLASS, DECOR)
	bridgeGlass.Reflectance = 0.3
	-- pool deck and a water slide's tower
	local pool = PartKit.Box(model, "Pool", Vector3.new(26, 0.6, 40), cf * CFrame.new(0, top + 0.4, -length * 0.05), Color3.fromRGB(60, 190, 220), GLASS, DECOR)
	pool.Transparency = 0.15
	PartKit.Post(model, "SlideTower", 8, 24, (cf * CFrame.new(-20, top, length * 0.05)).Position, Color3.fromRGB(240, 120, 40), SMOOTH, NO_COLLIDE)
	-- lifeboats
	for _, side in { -1, 1 } do
		for k = 0, 7 do
			PartKit.Box(model, "Lifeboat", Vector3.new(6, 6, 22), cf * CFrame.new(side * (beam / 2 + 3), 30 + 2 * deckH + 3, -length * 0.25 + k * length * 0.07), Color3.fromRGB(255, 130, 20), SMOOTH, DECOR)
		end
	end
	local name = PartKit.Box(model, "ShipName", Vector3.new(0.3, 8, 80), cf * CFrame.new(beam / 2 + 0.2, 22, -length * 0.3), white, SMOOTH, DECOR)
	name.Transparency = 1
	PartKit.Sign(name, Enum.NormalId.Right, pick(rng, { "SEA SERENADE", "OCEAN DREAM", "TROPIC STAR", "SUNWARD" }), Color3.fromRGB(20, 40, 90), nil, Enum.Font.Garamond, 6)
	skyline(model)
	return model
end

-- A container ship: a dark hull, stacks of boxes the length of her, the bridge house aft
function Port.ContainerShip(parent: Instance, cf: CFrame, length: number, rng: Random): Model
	local model = PartKit.Model(parent, "ContainerShip")
	local beam = length * 0.14
	hull(model, cf, length, beam, 22, Color3.fromRGB(40, 44, 52), Color3.fromRGB(150, 40, 36))
	local bays = 10
	for k = 0, bays - 1 do
		local z = -length * 0.34 + k * length * 0.062
		local tiers = rng:NextInteger(3, 6)
		PartKit.Box(model, "Stack", Vector3.new(beam - 6, tiers * 9.25, length * 0.055), cf * CFrame.new(0, 22 + tiers * 9.25 / 2, z), pick(rng, CONTAINERS), Enum.Material.CorrodedMetal)
	end
	PartKit.Box(model, "BridgeHouse", Vector3.new(beam - 10, 60, 30), cf * CFrame.new(0, 22 + 30, length * 0.36), Color3.fromRGB(246, 246, 244), SMOOTH)
	local glass = PartKit.Box(model, "Window", Vector3.new(beam - 9.8, 4, 30.2), cf * CFrame.new(0, 22 + 54, length * 0.36), Color3.fromRGB(30, 40, 50), GLASS, DECOR)
	glass.Reflectance = 0.3
	PartKit.Box(model, "Funnel", Vector3.new(12, 20, 14), cf * CFrame.new(0, 22 + 70, length * 0.4), Color3.fromRGB(30, 30, 32), SMOOTH, NO_COLLIDE)
	skyline(model)
	return model
end

function Port.Build(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "Port")
	local p = Layout.PORT
	local cx, cz = (p.MinX + p.MaxX) / 2, (p.MinZ + p.MaxZ) / 2
	local w, d = p.MaxX - p.MinX, p.MaxZ - p.MinZ
	local roadZ = Layout.PORT_ROAD_Z
	-- the paved yard
	-- (a hair under the road's surface, so the road through it shows)
	local yard = PartKit.Box(folder, "Yard", Vector3.new(w - 4, 0.2, d - 4), CFrame.new(cx, Layout.ROAD_Y - 0.13, cz), Color3.fromRGB(150, 150, 146), CONCRETE)
	yard:SetAttribute("Surface", "Road")
	PartKit.Box(folder, "Kerb", Vector3.new(w - 4, 1, 2), CFrame.new(cx, Layout.ROAD_Y + 0.5, p.MinZ + 3), Color3.fromRGB(240, 200, 40), CONCRETE)

	-- the container terminal (south): rows of stacks with lanes between, cranes on the quay
	local yardZ0, yardZ1 = roadZ + 30, p.MaxZ - 70
	local rowStep = 30
	for z = yardZ0 + 10, yardZ1 - 10, rowStep do
		for x = p.MinX + 60, p.MaxX - 60, 50 do
			if rng:NextNumber() < 0.85 then
				local tiers = rng:NextInteger(1, 4)
				for t = 0, tiers - 1 do
					PartKit.Box(folder, "Container", Vector3.new(43.6, 9.2, 8.7), CFrame.new(x, Layout.ROAD_Y + 4.6 + t * 9.25, z) * CFrame.Angles(0, 0, 0), pick(rng, CONTAINERS), Enum.Material.CorrodedMetal)
				end
			end
		end
	end
	for k = 0, 2 do
		crane(folder, Vector3.new(cx - 260 + k * 260, Layout.ROAD_Y, p.MaxZ - 30), Vector3.new(0, 0, 1))
	end
	-- the container ship alongside the south quay (a 230 m feeder)
	local boxLength = 820
	Port.ContainerShip(folder, CFrame.lookAt(Vector3.new(cx, Layout.WATER_Y, p.MaxZ + boxLength * 0.07 + 8), Vector3.new(cx - 1, Layout.WATER_Y, p.MaxZ + boxLength * 0.07 + 8)), boxLength, rng)

	-- the cruise terminal (north), two ships off it
	local term = Vector3.new(cx, Layout.ROAD_Y, (p.MinZ + roadZ) / 2 - 10)
	local terminal = PartKit.Model(folder, "CruiseTerminal")
	PartKit.Box(terminal, "Hall", Vector3.new(320, 30, 90), CFrame.new(term + Vector3.new(0, 15, 0)), Color3.fromRGB(242, 244, 246), SMOOTH)
	local glass = PartKit.Box(terminal, "ShopGlass", Vector3.new(320.4, 18, 90.4), CFrame.new(term + Vector3.new(0, 12, 0)), Color3.fromRGB(70, 110, 130), GLASS, DECOR)
	glass.Reflectance = 0.35
	for k = 0, 3 do
		-- sail-shaped canopies on the roof
		local at = term + Vector3.new(-120 + k * 80, 30, 0)
		PartKit.Slab(terminal, "Sail", at + Vector3.new(-30, 0, 0), at + Vector3.new(20, 26, 0), 60, 0.6, Color3.fromRGB(250, 250, 248), Enum.Material.Fabric, NO_COLLIDE)
	end
	local sign = PartKit.Box(terminal, "TerminalSign", Vector3.new(120, 8, 0.4), CFrame.new(term + Vector3.new(0, 24, 45.4)), Color3.fromRGB(30, 30, 34), SMOOTH, DECOR)
	sign.Transparency = 1
	PartKit.Sign(sign, Enum.NormalId.Back, "PORT OF MIAMI · CRUISE TERMINAL", Color3.fromRGB(20, 60, 120), nil, Enum.Font.GothamBold, 5)
	-- (a 250 m cruise ship, alongside the north quay)
	local cruiseLength = 900
	Port.CruiseShip(folder, CFrame.lookAt(Vector3.new(cx, Layout.WATER_Y, p.MinZ - cruiseLength * 0.065 - 8), Vector3.new(cx + 1, Layout.WATER_Y, p.MinZ - cruiseLength * 0.065 - 8)), cruiseLength, rng)

	-- light towers and a gatehouse at the bridge end
	for _, at in { Vector3.new(p.MinX + 40, Layout.ROAD_Y, yardZ0 - 6), Vector3.new(cx, Layout.ROAD_Y, yardZ0 - 6), Vector3.new(p.MaxX - 40, Layout.ROAD_Y, yardZ0 - 6) } do
		PartKit.Post(folder, "LightTower", 2.4, 70, at, Color3.fromRGB(150, 154, 158), METAL)
		PartKit.Box(folder, "Globe", Vector3.new(10, 2, 3), CFrame.new(at + Vector3.new(0, 70, 0)), Color3.fromRGB(255, 240, 210), Enum.Material.Neon, DECOR)
	end
	PartKit.Box(folder, "Gatehouse", Vector3.new(12, 10, 10), CFrame.new(p.MinX + 50, Layout.ROAD_Y + 5, roadZ - 26), Color3.fromRGB(240, 240, 236), SMOOTH)
	for _ = 1, 6 do
		Props.Palm(folder, Vector3.new(rng:NextNumber(p.MinX + 20, p.MinX + 120), Layout.ROAD_Y, rng:NextNumber(p.MinZ + 20, roadZ - 40)), rng)
	end
	return folder
end

return Port
