--[[
	Buildings: downtown towers, midtown shops and flats, industrial sheds and suburban houses.
	Everything sits on a block's lot at Layout.CURB_Y.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Detail = require(script.Parent.Detail)
local CarModel = require(script.Parent.Parent.Models.CarModel)
local Config = require(script.Parent.Parent.Config)
local PartKit = require(script.Parent.Parent.PartKit)

local Buildings = {}

local Y = Layout.CURB_Y
local SMOOTH = Enum.Material.SmoothPlastic
local CONCRETE = Enum.Material.Concrete
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }

local GLASS_TINTS = {
	Color3.fromRGB(78, 128, 158),
	Color3.fromRGB(62, 102, 132),
	Color3.fromRGB(110, 150, 172),
	Color3.fromRGB(72, 92, 112),
	Color3.fromRGB(120, 168, 186),
	Color3.fromRGB(90, 118, 140),
}
local CONCRETE_TONES = {
	Color3.fromRGB(205, 208, 212),
	Color3.fromRGB(182, 186, 192),
	Color3.fromRGB(226, 226, 222),
	Color3.fromRGB(160, 166, 172),
}
local BRICKS = {
	Color3.fromRGB(158, 82, 62),
	Color3.fromRGB(176, 120, 90),
	Color3.fromRGB(196, 170, 140),
	Color3.fromRGB(120, 72, 58),
	Color3.fromRGB(214, 200, 180),
	Color3.fromRGB(140, 150, 160),
}
local HOUSE_COLORS = {
	Color3.fromRGB(240, 228, 196),
	Color3.fromRGB(214, 228, 236),
	Color3.fromRGB(236, 214, 208),
	Color3.fromRGB(250, 246, 238),
	Color3.fromRGB(206, 222, 196),
	Color3.fromRGB(246, 224, 160),
	Color3.fromRGB(200, 205, 215),
}
local ROOFS = {
	Color3.fromRGB(70, 72, 78),
	Color3.fromRGB(150, 64, 50),
	Color3.fromRGB(96, 70, 56),
	Color3.fromRGB(58, 74, 96),
}
local SHOPS = {
	"Volt Coffee", "Corner Café", "Bolt Pizza", "City Books", "Pedal & Co", "Sunny Deli", "Metro Pharmacy",
	"Taco Loco", "Spin Laundry", "Gadget Hub", "Green Grocer", "Noodle Bar", "Flower Shop", "Game Zone",
	"Burger Barn", "Bike Parts", "Ice Cream", "Bakery", "Sushi Go", "Hardware",
}
local AWNINGS = {
	Color3.fromRGB(200, 40, 40),
	Color3.fromRGB(30, 110, 70),
	Color3.fromRGB(30, 80, 160),
	Color3.fromRGB(230, 150, 30),
	Color3.fromRGB(120, 60, 140),
	Color3.fromRGB(40, 40, 40),
}

local TOWER_NAMES = { "VOLTA TOWER", "ONE MERIDIAN", "HARBOR TRUST", "SKYLINE PLAZA", "NOVA CENTRE", "ATLAS HOUSE", "CIRCUIT BANK", "PARKVIEW" }
local COMPANIES = { "VOLT LOGISTICS", "CELLWORKS", "IRONSIDE", "NORTHLINE FREIGHT", "AMP SUPPLY", "GRIDCO" }

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- A glass tower: curtain wall with mullions on every face, floor bands, corner piers, a lobby,
-- roof plant and sometimes a crown and antenna
function Buildings.Tower(parent: Instance, cx: number, cz: number, w: number, d: number, h: number, rng: Random)
	local model = PartKit.Model(parent, "Tower")
	local glass = pick(rng, GLASS_TINTS)
	local stone = pick(rng, CONCRETE_TONES)
	local lobbyH = 16
	local core = PartKit.Box(model, "Glass", Vector3.new(w - 1.6, h - lobbyH, d - 1.6), CFrame.new(cx, Y + lobbyH + (h - lobbyH) / 2, cz), glass, GLASS)
	core.Reflectance = 0.2
	-- recessed lobby: darker glass behind columns
	local lobby = PartKit.Box(model, "Lobby", Vector3.new(w - 6, lobbyH, d - 6), CFrame.new(cx, Y + lobbyH / 2, cz), Color3.fromRGB(60, 80, 90), GLASS)
	lobby.Reflectance = 0.25
	local floor = 15
	for y = lobbyH, h - 4, floor do
		PartKit.Box(model, "Floor", Vector3.new(w, 1.2, d), CFrame.new(cx, Y + y, cz), stone, CONCRETE)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			PartKit.Box(model, "Pier", Vector3.new(2.4, h, 2.4), CFrame.new(cx + sx * (w / 2 - 1.2), Y + h / 2, cz + sz * (d / 2 - 1.2)), stone, CONCRETE)
		end
	end
	-- mullions on all four faces
	local spacing = 7
	for _, out in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local faceW = if out.X ~= 0 then d else w
		local half = if out.X ~= 0 then w / 2 else d / 2
		local face = Detail.Face(cx, cz, out, half - 0.6, Y)
		local n = math.floor((faceW - 6) / spacing)
		for i = 1, n - 1 do
			local x = -faceW / 2 + 3 + i * (faceW - 6) / n
			PartKit.Box(model, "Mullion", Vector3.new(0.5, h - lobbyH, 0.6), face * CFrame.new(x, lobbyH + (h - lobbyH) / 2, -0.2), stone, CONCRETE, DECOR)
		end
		-- lobby columns and doors
		local cols = math.max(3, math.floor(faceW / 14))
		for i = 1, cols - 1 do
			local x = -faceW / 2 + i * faceW / cols
			PartKit.Box(model, "Column", Vector3.new(1.8, lobbyH, 1.8), face * CFrame.new(x, lobbyH / 2, 1.5), stone, CONCRETE)
		end
	end
	local front = Detail.Face(cx, cz, Vector3.new(0, 0, 1), d / 2 - 3, Y)
	for _, x in { -3, 3 } do
		PartKit.Box(model, "LobbyDoor", Vector3.new(5, 9, 0.3), front * CFrame.new(x, 4.5, -0.2), Color3.fromRGB(150, 180, 190), GLASS, DECOR).Transparency = 0.3
	end
	PartKit.Box(model, "Canopy", Vector3.new(w * 0.45, 0.8, 9), front * CFrame.new(0, lobbyH - 2, -4.5), stone, CONCRETE, NO_COLLIDE)
	local label = PartKit.Box(model, "TowerName", Vector3.new(w * 0.4, 2.4, 0.3), front * CFrame.new(0, lobbyH - 0.4, -9.1), Color3.fromRGB(30, 30, 34), SMOOTH, DECOR)
	PartKit.Sign(label, Enum.NormalId.Front, pick(rng, TOWER_NAMES), Color3.fromRGB(240, 240, 240), nil, Enum.Font.GothamBold, 12)
	PartKit.Box(model, "Parapet", Vector3.new(w + 0.8, 3, d + 0.8), CFrame.new(cx, Y + h + 1.5, cz), stone, CONCRETE)
	PartKit.Box(model, "Roof", Vector3.new(w - 3, 0.4, d - 3), CFrame.new(cx, Y + h + 2.8, cz), Color3.fromRGB(80, 82, 86), CONCRETE, DECOR)
	PartKit.Box(model, "Plant", Vector3.new(w * 0.3, 8, d * 0.3), CFrame.new(cx + w * 0.15, Y + h + 4, cz - d * 0.1), Color3.fromRGB(150, 155, 160), Enum.Material.DiamondPlate)
	Detail.Roof(model, cx - w * 0.15, cz + d * 0.15, w * 0.55, d * 0.55, Y + h + 3, rng)
	if rng:NextNumber() < 0.4 then
		-- stepped glass crown
		for k = 1, 2 do
			local f = 1 - k * 0.22
			local crown = PartKit.Box(model, "Crown", Vector3.new(w * f, 10, d * f), CFrame.new(cx, Y + h + 3 + (k - 0.5) * 10, cz), glass, GLASS)
			crown.Reflectance = 0.2
			PartKit.Box(model, "CrownBand", Vector3.new(w * f + 0.6, 1, d * f + 0.6), CFrame.new(cx, Y + h + 3 + k * 10, cz), stone, CONCRETE, DECOR)
		end
	end
	if h > 260 then
		PartKit.Post(model, "Antenna", 1.2, 40, Vector3.new(cx - w * 0.2, Y + h + 3, cz + d * 0.15), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		PartKit.Ball(model, "Beacon", 2, Vector3.new(cx - w * 0.2, Y + h + 43, cz + d * 0.15), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, DECOR)
	end
end

-- A brick (or render) building with framed windows on every face; the ground floor is a shopfront
-- facing `front`, sometimes a fire escape on a side, roof plant on top
function Buildings.Midrise(parent: Instance, cx: number, cz: number, w: number, d: number, floors: number, front: Vector3, rng: Random, openSides: { Vector3 }?)
	local model = PartKit.Model(parent, "Building")
	local floorH = 12
	local h = floors * floorH + 2
	local brick = pick(rng, BRICKS)
	local material = if rng:NextNumber() < 0.75 then Enum.Material.Brick else Enum.Material.Plaster
	PartKit.Box(model, "Body", Vector3.new(w, h, d), CFrame.new(cx, Y + h / 2, cz), brick, material)
	local trim = pick(rng, { Color3.fromRGB(235, 230, 220), Color3.fromRGB(60, 62, 66), Color3.fromRGB(200, 196, 186) })
	local style: Detail.WindowStyle = {
		Width = pick(rng, { 4, 4.5, 5 }),
		Height = pick(rng, { 6, 7, 7.5 }),
		Spacing = pick(rng, { 8, 9, 10 }),
		Frame = trim,
	}
	for _, out in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local faceW = if out.X ~= 0 then d else w
		local half = if out.X ~= 0 then w / 2 else d / 2
		local face = Detail.Face(cx, cz, out, half, Y)
		-- side walls in a row face their neighbours: windows only where a street can see them
		local isSide = math.abs(out:Dot(front)) < 0.5
		local open = not isSide
		if isSide and openSides then
			for _, o in openSides do
				if o:Dot(out) > 0.5 then
					open = true
				end
			end
		end
		if open then
			Detail.Windows(model, face, faceW, floorH, h - 2, floorH, style, 3)
		end
		-- string course between floors on the street face
		if out == front then
			for f = 1, floors - 1 do
				PartKit.Box(model, "StringCourse", Vector3.new(faceW + 0.4, 0.6, 0.5), face * CFrame.new(0, f * floorH, -0.15), trim, CONCRETE, DECOR)
			end
		end
	end
	-- shopfront
	local faceWidth = if math.abs(front.X) > 0.5 then d else w
	local faceDepth = if math.abs(front.X) > 0.5 then w else d
	local face = Detail.Face(cx, cz, front, faceDepth / 2, Y)
	Detail.Storefront(model, face, faceWidth, 9.5, pick(rng, SHOPS), pick(rng, AWNINGS), rng)
	-- side door to the flats above
	-- fire escape on one side
	if floors >= 3 and rng:NextNumber() < 0.45 then
		local side = Vector3.new(-front.Z, 0, front.X) * (if rng:NextNumber() < 0.5 then 1 else -1)
		local sideWidth = if math.abs(side.X) > 0.5 then d else w
		local sideDepth = if math.abs(side.X) > 0.5 then w else d
		Detail.FireEscape(model, Detail.Face(cx, cz, side, sideDepth / 2, Y), sideWidth * 0.15, floors, floorH)
	end
	-- cornice, roof clutter and sometimes a water tank
	PartKit.Box(model, "Cornice", Vector3.new(w + 1.4, 1.4, d + 1.4), CFrame.new(cx, Y + h + 0.2, cz), trim, CONCRETE)
	PartKit.Box(model, "CorniceDentil", Vector3.new(w + 0.8, 0.6, d + 0.8), CFrame.new(cx, Y + h - 0.8, cz), trim, CONCRETE, DECOR)
	Detail.Roof(model, cx, cz, w - 4, d - 4, Y + h + 0.9, rng)
	if rng:NextNumber() < 0.35 then
		local tank = Vector3.new(cx + rng:NextNumber(-w / 4, w / 4), Y + h + 1, cz + rng:NextNumber(-d / 4, d / 4))
		for _, o in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) } do
			PartKit.Post(model, "TankLeg", 0.4, 6, tank + o, Color3.fromRGB(60, 50, 40), Enum.Material.Wood, DECOR)
		end
		PartKit.Post(model, "Tank", 7, 7, tank + Vector3.new(0, 6, 0), Color3.fromRGB(130, 96, 66), Enum.Material.WoodPlanks)
		PartKit.Cylinder(model, "TankRoof", 7.6, 1.2, CFrame.new(tank + Vector3.new(0, 13.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 60, 50), Enum.Material.WoodPlanks, DECOR)
	end
end

function Buildings.Warehouse(parent: Instance, cx: number, cz: number, w: number, d: number, h: number, front: Vector3, rng: Random)
	local model = PartKit.Model(parent, "Warehouse")
	local wall = pick(rng, { Color3.fromRGB(190, 192, 186), Color3.fromRGB(160, 170, 175), Color3.fromRGB(196, 180, 150), Color3.fromRGB(120, 140, 150) })
	PartKit.Box(model, "Walls", Vector3.new(w, h, d), CFrame.new(cx, Y + h / 2, cz), wall, Enum.Material.Concrete)
	PartKit.Box(model, "Roof", Vector3.new(w + 2, 1.5, d + 2), CFrame.new(cx, Y + h + 0.75, cz), Color3.fromRGB(110, 115, 120), Enum.Material.DiamondPlate)
	local rib = wall:Lerp(Color3.new(0, 0, 0), 0.12)
	-- corrugated cladding (ribs) above a concrete plinth, and a strip of high windows
	for _, out in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local faceW = if out.X ~= 0 then d else w
		local half = if out.X ~= 0 then w / 2 else d / 2
		local face = Detail.Face(cx, cz, out, half, Y)
		PartKit.Box(model, "Plinth", Vector3.new(faceW + 0.4, 4, 0.6), face * CFrame.new(0, 2, -0.2), Color3.fromRGB(150, 150, 146), CONCRETE, DECOR)
		local n = math.floor(faceW / 3.5)
		for i = 0, n do
			local x = -faceW / 2 + i * faceW / n
			PartKit.Box(model, "Rib", Vector3.new(0.6, h - 4, 0.35), face * CFrame.new(x, 4 + (h - 4) / 2, -0.12), rib, METAL, DECOR)
		end
		local band = PartKit.Box(model, "HighWindows", Vector3.new(faceW - 8, 3, 0.3), face * CFrame.new(0, h - 5, -0.3), Color3.fromRGB(150, 180, 196), GLASS, DECOR)
		band.Reflectance = 0.15
	end
	local right = Vector3.new(-front.Z, 0, front.X)
	local faceWidth = if math.abs(front.X) > 0.5 then d else w
	local faceDepth = if math.abs(front.X) > 0.5 then w else d
	local face = Detail.Face(cx, cz, front, faceDepth / 2, Y)
	local doors = math.max(1, math.floor(faceWidth / 40))
	for i = 1, doors do
		local x = -faceWidth / 2 + (i - 0.5) * faceWidth / doors
		local at = face * CFrame.new(x, 0, 0)
		PartKit.Box(model, "LoadingDoor", Vector3.new(16, 16, 0.5), at * CFrame.new(0, 8, -0.4), Color3.fromRGB(90, 96, 104), Enum.Material.CorrodedMetal, DECOR)
		for k = 1, 7 do
			PartKit.Box(model, "DoorSlat", Vector3.new(16, 0.25, 0.6), at * CFrame.new(0, k * 2, -0.45), Color3.fromRGB(70, 76, 84), METAL, DECOR)
		end
		PartKit.Box(model, "DoorStripe", Vector3.new(16.6, 1, 0.7), at * CFrame.new(0, 16.6, -0.4), Color3.fromRGB(240, 190, 30), SMOOTH, DECOR)
		-- dock: a raised concrete apron with rubber bumpers
		PartKit.Box(model, "Dock", Vector3.new(20, 4, 6), at * CFrame.new(0, 2, -3), Color3.fromRGB(170, 168, 162), CONCRETE)
		for _, s in { -1, 1 } do
			PartKit.Box(model, "Bumper", Vector3.new(1, 1.6, 0.8), at * CFrame.new(s * 6, 2.6, -6.3), Color3.fromRGB(20, 20, 20), SMOOTH, DECOR)
		end
		PartKit.Box(model, "DockLight", Vector3.new(1.2, 0.6, 1.2), at * CFrame.new(10.5, 18, -1), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, DECOR)
	end
	-- personnel door with a small canopy
	local pd = face * CFrame.new(faceWidth / 2 - 8, 0, 0)
	PartKit.Box(model, "StaffDoor", Vector3.new(3.6, 7.5, 0.4), pd * CFrame.new(0, 3.75, -0.35), Color3.fromRGB(40, 90, 150), METAL, DECOR)
	PartKit.Box(model, "DoorCanopy", Vector3.new(6, 0.4, 3), pd * CFrame.new(0, 8.6, -1.5), Color3.fromRGB(80, 84, 90), METAL, DECOR)
	local logo = PartKit.Box(model, "Logo", Vector3.new(math.min(30, faceWidth * 0.4), 4, 0.3), face * CFrame.new(-faceWidth * 0.2, h - 10, -0.5), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	PartKit.Sign(logo, Enum.NormalId.Front, pick(rng, COMPANIES), Color3.fromRGB(30, 60, 120), nil, Enum.Font.GothamBlack, 10)
	-- roof vents
	for i = 1, math.max(2, math.floor(w / 30)) do
		local p = Vector3.new(cx - w / 2 + i * w / (math.floor(w / 30) + 1), Y + h + 1.5, cz)
		PartKit.Post(model, "RoofVent", 2.4, 2.4, p, Color3.fromRGB(190, 192, 196), METAL, DECOR)
		PartKit.Ball(model, "VentCap", 2.6, p + Vector3.new(0, 2.6, 0), Color3.fromRGB(190, 192, 196), METAL, DECOR)
	end
	-- a pipe run down one side
	local side = Detail.Face(cx, cz, right, (if math.abs(right.X) > 0.5 then w else d) / 2, Y)
	PartKit.Box(model, "Pipe", Vector3.new(1.2, h, 1.2), side * CFrame.new(faceWidth * 0.3, h / 2, -0.8), Color3.fromRGB(180, 70, 50), METAL, DECOR)
end

function Buildings.Chimney(parent: Instance, base: Vector3, height: number)
	local model = PartKit.Model(parent, "Chimney")
	local bands = 6
	for i = 0, bands - 1 do
		local color = if i % 2 == 0 then Color3.fromRGB(196, 60, 50) else Color3.fromRGB(235, 235, 230)
		PartKit.Post(model, "Stack", 9 - i * 0.6, height / bands, base + Vector3.new(0, i * height / bands, 0), color, Enum.Material.Brick)
	end
end

-- A suburban house facing `front` (a unit axis vector toward its street), `setback` studs from it
function Buildings.House(parent: Instance, center: Vector3, front: Vector3, setback: number, rng: Random, lotWidth: number?)
	local model = PartKit.Model(parent, "House")
	-- two storeys (real suburban houses: ~2.7 m a storey, eaves ~5.5 m), a 35 degree gable roof
	local w, d, h = rng:NextNumber(30, 38), rng:NextNumber(26, 32), rng:NextNumber(19, 20.5)
	local look = CFrame.lookAt(center, center + front) -- -Z toward the street
	local wall = pick(rng, HOUSE_COLORS)
	local roof = pick(rng, ROOFS)
	local material = if rng:NextNumber() < 0.5 then Enum.Material.Plaster else Enum.Material.WoodPlanks
	PartKit.Box(model, "Walls", Vector3.new(w, h, d), look * CFrame.new(0, h / 2, 0), wall, material)
	-- gable roof: two pitched slabs meeting at the ridge (along the width), wedge gables closing the ends
	local pitch = math.rad(35)
	local rise = d / 2 * math.tan(pitch)
	local over = 1.6
	local eaveY = h - over * math.tan(pitch)
	for _, zs in { -1, 1 } do
		PartKit.Slab(model, "Roof", (look * CFrame.new(0, eaveY, zs * (d / 2 + over))).Position, (look * CFrame.new(0, h + rise + 0.35, 0)).Position, w + 2.4, 0.7, roof, Enum.Material.Slate)
		for _, xs in { -1, 1 } do
			-- full height on local +Z: turn the back half round so both rise to the ridge
			local turn = if zs > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity
			PartKit.Wedge(model, "Gable", Vector3.new(0.8, rise, d / 2), look * CFrame.new(xs * (w / 2 - 0.4), h + rise / 2, zs * d / 4) * turn, wall, material)
		end
	end
	PartKit.Box(model, "Ridge", Vector3.new(w + 2.6, 0.6, 0.9), look * CFrame.new(0, h + rise + 0.3, 0), roof:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Slate, DECOR)
	-- the floor line between the storeys
	PartKit.Box(model, "Band", Vector3.new(w + 0.4, 0.6, d + 0.4), look * CFrame.new(0, 10.4, 0), Color3.fromRGB(245, 245, 242), SMOOTH, DECOR)
	for _, x in { -w * 0.36, -w * 0.12, w * 0.15, w * 0.36 } do
		PartKit.Box(model, "WindowFrame", Vector3.new(5, 5, 0.3), look * CFrame.new(x, 15.4, -d / 2 - 0.12), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
		PartKit.Box(model, "Window", Vector3.new(4.2, 4.2, 0.35), look * CFrame.new(x, 15.4, -d / 2 - 0.15), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
		PartKit.Box(model, "Sill", Vector3.new(5.8, 0.4, 0.9), look * CFrame.new(x, 12.7, -d / 2 - 0.4), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	end
	for _, side in { -1, 1 } do
		for _, z in { -d * 0.2, d * 0.2 } do
			PartKit.Box(model, "SideWindow", Vector3.new(0.35, 4.2, 4.2), look * CFrame.new(side * (w / 2 + 0.1), 15.4, z), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
			PartKit.Box(model, "SideFrame", Vector3.new(0.3, 5, 5), look * CFrame.new(side * (w / 2 + 0.05), 15.4, z), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
		end
		-- a small window up in each gable
		PartKit.Box(model, "SideWindow", Vector3.new(0.35, 2.6, 2.6), look * CFrame.new(side * (w / 2 + 0.1), h + rise * 0.4, 0), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
	end
	for _, x in { -w * 0.25, w * 0.25 } do
		PartKit.Box(model, "BackWindow", Vector3.new(5, 4.2, 0.35), look * CFrame.new(x, 15.4, d / 2 + 0.1), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
	end
	PartKit.Box(model, "Door", Vector3.new(4, 7.5, 0.4), look * CFrame.new(-w * 0.15, 3.75, -d / 2 - 0.15), Color3.fromRGB(90, 56, 40), Enum.Material.Wood, DECOR)
	PartKit.Box(model, "Step", Vector3.new(7, 0.8, 3), look * CFrame.new(-w * 0.15, 0.4, -d / 2 - 1.5), Color3.fromRGB(190, 186, 180), CONCRETE)
	for _, x in { -w * 0.36, w * 0.15, w * 0.36 } do
		PartKit.Box(model, "WindowFrame", Vector3.new(5, 5, 0.3), look * CFrame.new(x, 6.5, -d / 2 - 0.12), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
		PartKit.Box(model, "Window", Vector3.new(4.2, 4.2, 0.35), look * CFrame.new(x, 6.5, -d / 2 - 0.15), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
	end
	-- garage + driveway
	local gx = w / 2 + 9
	PartKit.Box(model, "Garage", Vector3.new(16, 10, 22), look * CFrame.new(gx, 5, -d / 2 + 11), wall, material)
	PartKit.Box(model, "GarageRoof", Vector3.new(17, 1, 23), look * CFrame.new(gx, 10.5, -d / 2 + 11), roof, Enum.Material.Slate)
	PartKit.Box(model, "GarageDoor", Vector3.new(12, 8, 0.3), look * CFrame.new(gx, 4, -d / 2 - 0.1), Color3.fromRGB(240, 240, 238), SMOOTH, DECOR)
	local drive = setback - d / 2
	if drive > 1 then
		PartKit.Box(model, "Driveway", Vector3.new(12, 0.1, drive), look * CFrame.new(gx, 0.05, -d / 2 - drive / 2), Color3.fromRGB(176, 174, 170), CONCRETE, DECOR)
		PartKit.Box(model, "Path", Vector3.new(3.5, 0.1, drive - 3), look * CFrame.new(-w * 0.15, 0.05, -d / 2 - 3 - (drive - 3) / 2), Color3.fromRGB(190, 186, 180), CONCRETE, DECOR)
	end
	if rng:NextNumber() < 0.5 then
		PartKit.Box(model, "Chimney", Vector3.new(3, rise + 5, 3), look * CFrame.new(-w * 0.35, h + (rise + 5) / 2, d * 0.15), Color3.fromRGB(150, 80, 60), Enum.Material.Brick)
	end
	-- porch over the door: roof on two posts
	local porchX = -w * 0.15
	PartKit.Box(model, "PorchRoof", Vector3.new(10, 0.6, 6), look * CFrame.new(porchX, 9.2, -d / 2 - 3) * CFrame.Angles(math.rad(8), 0, 0), roof, Enum.Material.Slate, NO_COLLIDE)
	for _, sx in { -4.4, 4.4 } do
		PartKit.Box(model, "PorchPost", Vector3.new(0.6, 9, 0.6), look * CFrame.new(porchX + sx, 4.5, -d / 2 - 5.6), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	end
	PartKit.Box(model, "PorchLight", Vector3.new(0.7, 1, 0.5), look * CFrame.new(porchX + 2.8, 6.4, -d / 2 - 0.4), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, DECOR)
	-- shutters beside the front windows, windows on the sides and back
	local shutter = pick(rng, { Color3.fromRGB(40, 70, 110), Color3.fromRGB(40, 90, 60), Color3.fromRGB(120, 40, 40), Color3.fromRGB(50, 50, 54) })
	for _, x in { -w * 0.36, w * 0.15, w * 0.36 } do
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "Shutter", Vector3.new(1.6, 5, 0.3), look * CFrame.new(x + sx * 3.4, 6.5, -d / 2 - 0.2), shutter, SMOOTH, DECOR)
		end
		PartKit.Box(model, "Sill", Vector3.new(5.8, 0.4, 0.9), look * CFrame.new(x, 3.8, -d / 2 - 0.4), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	end
	for _, side in { -1, 1 } do
		for _, z in { -d * 0.2, d * 0.2 } do
			PartKit.Box(model, "SideWindow", Vector3.new(0.35, 4.2, 4.2), look * CFrame.new(side * (w / 2 + 0.1), 6.5, z), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
			PartKit.Box(model, "SideFrame", Vector3.new(0.3, 5, 5), look * CFrame.new(side * (w / 2 + 0.05), 6.5, z), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
		end
	end
	for _, x in { -w * 0.25, w * 0.25 } do
		PartKit.Box(model, "BackWindow", Vector3.new(5, 4.2, 0.35), look * CFrame.new(x, 6.5, d / 2 + 0.1), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
	end
	PartKit.Box(model, "Gutter", Vector3.new(w + 2.4, 0.5, 0.6), look * CFrame.new(0, eaveY - 0.6, -d / 2 - over - 0.2), Color3.fromRGB(240, 240, 240), SMOOTH, DECOR)
	-- garage door panels and a light
	for k = 1, 3 do
		PartKit.Box(model, "GaragePanel", Vector3.new(12, 0.2, 0.4), look * CFrame.new(gx, k * 2, -d / 2 - 0.2), Color3.fromRGB(215, 215, 212), SMOOTH, DECOR)
	end

	-- the garden out front: flower bed under the windows, a fence or hedge with gaps for the drive
	-- and path, a mailbox at the end of the drive, sometimes a car on the drive or a hoop
	local lot = lotWidth or (w + 30)
	if rng:NextNumber() < 0.6 then
		Detail.FlowerBed(model, look * CFrame.new(w * 0.25, 0, -d / 2 - 2), 14, rng)
	end
	local fz = -(setback - 1.5)
	local function at(x: number): Vector3
		return (look * CFrame.new(x, 0, fz)).Position
	end
	local gaps = { { porchX - 2.5, porchX + 2.5 }, { gx - 7, gx + 7 } }
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	local x = -lot / 2 + 1
	local picket = rng:NextNumber() < 0.35
	for _, gap in gaps do
		if gap[1] > x then
			if picket then
				Detail.Picket(model, at(x), at(gap[1]))
			else
				Detail.Hedge(model, at(x), at(gap[1]), 3.2)
			end
		end
		x = gap[2]
	end
	if lot / 2 - 1 > x then
		if picket then
			Detail.Picket(model, at(x), at(lot / 2 - 1))
		else
			Detail.Hedge(model, at(x), at(lot / 2 - 1), 3.2)
		end
	end
	Detail.Mailbox(model, (look * CFrame.new(gx - 8.5, 0, fz + 0.5)).Position, -front, pick(rng, { Color3.fromRGB(30, 30, 30), Color3.fromRGB(40, 70, 130), Color3.fromRGB(150, 30, 30) }))
	if rng:NextNumber() < 0.3 and drive > 20 then
		local car = CarModel.Build(pick(rng, { "Sedan", "Hatch", "SUV" }), { Static = true, Color = pick(rng, CarModel.CivilianColors) })
		PartKit.Scale(car, 1 / Config.WORLD_SCALE) -- true-size car in the design-unit city
		PartKit.PlaceStatic(car, look * CFrame.new(gx, 0.1, -d / 2 - 12))
		car.Parent = model
	elseif rng:NextNumber() < 0.25 and drive > 20 then
		local hoop = look * CFrame.new(gx + 6.5, 0, -d / 2 - 2)
		PartKit.Post(model, "HoopPole", 0.5, 10, hoop.Position, Color3.fromRGB(40, 40, 40), METAL, DECOR)
		PartKit.Box(model, "Backboard", Vector3.new(5, 3.4, 0.3), hoop * CFrame.new(0, 10.5, -0.6), Color3.fromRGB(245, 245, 245), SMOOTH, DECOR)
		PartKit.Cylinder(model, "Rim", 2.4, 0.2, hoop * CFrame.new(0, 9.4, -1.9) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(230, 90, 30), METAL, DECOR)
	end
	return model
end

-- Fills a block according to its district
function Buildings.Fill(parent: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local folder = PartKit.Folder(parent, block.District .. "_" .. block.Bx .. "_" .. block.Bz)

	if block.District == "Downtown" then
		-- four quadrants: towers in most, a little tree plaza in the rest
		local plazas = 0
		for _, qx in { -1, 1 } do
			for _, qz in { -1, 1 } do
				local qcx, qcz = cx + qx * w / 4, cz + qz * d / 4
				if plazas == 0 and rng:NextNumber() < 0.25 then
					plazas += 1
					PartKit.Box(folder, "Plaza", Vector3.new(w / 2 - 6, 0.3, d / 2 - 6), CFrame.new(qcx, Y + 0.15, qcz), Color3.fromRGB(200, 196, 188), Enum.Material.Pavement)
					for _ = 1, 4 do
						Props.Tree(folder, Vector3.new(qcx + rng:NextNumber(-w / 6, w / 6), Y + 0.3, qcz + rng:NextNumber(-d / 6, d / 6)), rng)
					end
					Props.Bench(folder, CFrame.new(qcx, Y + 0.3, qcz))
				else
					local tw, td = w / 2 - rng:NextNumber(14, 26), d / 2 - rng:NextNumber(14, 26)
					local height = rng:NextNumber(120, 420)
					Buildings.Tower(folder, qcx, qcz, tw, td, height, rng)
				end
			end
		end
	elseif block.District == "Midtown" then
		-- shops along the north and south streets, a car park in the middle
		for _, side in { -1, 1 } do
			local front = Vector3.new(0, 0, side)
			local n = 3
			local each = w / n
			for i = 0, n - 1 do
				local bw = each - rng:NextNumber(4, 10)
				local bd = rng:NextNumber(70, 95)
				local bx = x0 + each * (i + 0.5)
				local bz = cz + side * (d / 2 - bd / 2 - 2)
				local open = {}
				if i == 0 then
					table.insert(open, Vector3.new(-1, 0, 0))
				end
				if i == n - 1 then
					table.insert(open, Vector3.new(1, 0, 0))
				end
				Buildings.Midrise(folder, bx, bz, bw, bd, rng:NextInteger(3, 8), front, rng, open)
			end
		end
		PartKit.Box(folder, "CarPark", Vector3.new(w - 10, 0.25, d - 200), CFrame.new(cx, Y + 0.12, cz), Color3.fromRGB(80, 82, 86), Enum.Material.Asphalt)
		for i = -4, 4 do
			PartKit.Box(folder, "Bay", Vector3.new(0.4, 0.05, 16), CFrame.new(cx + i * 12, Y + 0.27, cz), Color3.fromRGB(235, 235, 235), SMOOTH, DECOR)
		end
		-- a few parked cars, nose in, a lamp at each end and a pay machine
		for i = -4, 3 do
			if rng:NextNumber() < 0.45 then
				local car = CarModel.Build(pick(rng, CarModel.CivilianKinds), { Static = true, Color = pick(rng, CarModel.CivilianColors) })
				PartKit.Scale(car, 1 / Config.WORLD_SCALE)
				PartKit.PlaceStatic(car, CFrame.new(cx + i * 12 + 6, Y + 0.3, cz) * CFrame.Angles(0, if rng:NextNumber() < 0.5 then 0 else math.pi, 0))
				car.Parent = folder
			end
		end
		for _, sx in { -1, 1 } do
			Props.Lamp(folder, Vector3.new(cx + sx * 58, Y + 0.25, cz + 12))
		end
		PartKit.Box(folder, "PayMachine", Vector3.new(2, 5, 1.4), CFrame.new(cx - 52, Y + 2.75, cz - 12), Color3.fromRGB(40, 90, 160), METAL)
	elseif block.District == "Industrial" then
		Buildings.Warehouse(folder, cx - w / 4, cz - d / 6, w / 2 - 20, d / 2, rng:NextNumber(30, 45), Vector3.new(0, 0, 1), rng)
		Buildings.Warehouse(folder, cx + w / 4, cz + d / 6, w / 2 - 20, d / 2.4, rng:NextNumber(26, 40), Vector3.new(0, 0, -1), rng)
		Buildings.Chimney(folder, Vector3.new(cx + w / 3, Y, cz - d / 3), rng:NextNumber(70, 110))
		Buildings.Chimney(folder, Vector3.new(cx + w / 3 - 14, Y, cz - d / 3 + 6), rng:NextNumber(60, 90))
		-- shipping containers in the yard
		local colors = { Color3.fromRGB(180, 50, 40), Color3.fromRGB(40, 90, 160), Color3.fromRGB(50, 130, 70), Color3.fromRGB(220, 150, 30) }
		for i = 1, 8 do
			local px = cx - w / 2 + 20 + (i % 4) * 22
			local pz = cz + d / 2 - 30 - math.floor(i / 5) * 12
			PartKit.Box(folder, "Container", Vector3.new(8.5, 9, 20), CFrame.new(px, Y + 4.5, pz), colors[(i % #colors) + 1], Enum.Material.CorrodedMetal)
		end
		PartKit.Box(folder, "Yard", Vector3.new(w - 6, 0.2, d - 6), CFrame.new(cx, Y + 0.1, cz), Color3.fromRGB(120, 120, 118), Enum.Material.Concrete)
		-- yard clutter: box trucks at the docks, pallets, barrels, a fence round the lot
		local truckColors = { Color3.fromRGB(200, 40, 40), Color3.fromRGB(30, 90, 170), Color3.fromRGB(40, 130, 70), Color3.fromRGB(230, 140, 30) }
		Detail.BoxTruck(folder, CFrame.new(cx - w / 4 + 10, Y + 0.2, cz - d / 6 + d / 4 + 26) * CFrame.Angles(0, math.pi, 0), pick(rng, truckColors), pick(rng, COMPANIES))
		Detail.BoxTruck(folder, CFrame.new(cx + w / 4 - 10, Y + 0.2, cz + d / 6 - d / 4.8 - 26), pick(rng, truckColors), pick(rng, COMPANIES))
		for _ = 1, 4 do
			Detail.Pallets(folder, Vector3.new(cx + rng:NextNumber(-w / 2 + 12, -8), Y + 0.2, cz + rng:NextNumber(d / 6, d / 2 - 50)), rng)
		end
		Detail.Barrels(folder, Vector3.new(cx + w / 2 - 22, Y + 0.2, cz - d / 2 + 14), rng)
		local m = 2
		Detail.ChainLink(folder, Vector3.new(x0 + m, Y, z0 + m), Vector3.new(x1 - m, Y, z0 + m), 9)
		Detail.ChainLink(folder, Vector3.new(x0 + m, Y, z0 + m), Vector3.new(x0 + m, Y, z1 - m), 9)
		Detail.ChainLink(folder, Vector3.new(x1 - m, Y, z0 + m), Vector3.new(x1 - m, Y, cz - 20), 9)
		Detail.ChainLink(folder, Vector3.new(x0 + m, Y, z1 - m), Vector3.new(cx - 30, Y, z1 - m), 9)
	elseif block.District == "Suburb" then
		PartKit.Box(folder, "Lawns", Vector3.new(w, 0.3, d), CFrame.new(cx, Y + 0.15, cz), Props.Palette.Lawn, Enum.Material.Grass)
		for _, side in { -1, 1 } do
			local front = Vector3.new(0, 0, side)
			local n = 4
			local each = w / n
			for i = 0, n - 1 do
				local hx = x0 + each * (i + 0.5) + 6 * side
				local hz = cz + side * (d / 2 - 42)
				Buildings.House(folder, Vector3.new(hx, Y + 0.3, hz), front, 42, rng, each)
				if rng:NextNumber() < 0.7 then
					Props.Tree(folder, Vector3.new(hx + 24 * side, Y + 0.3, cz + side * (d / 2 - 12)), rng)
				end
				-- back fence
				PartKit.Box(folder, "Fence", Vector3.new(each - 2, 4, 0.5), CFrame.new(x0 + each * (i + 0.5), Y + 2.3, cz + side * 2), Color3.fromRGB(150, 120, 90), Enum.Material.WoodPlanks)
			end
		end
	end
end

return Buildings
