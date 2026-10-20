--[[
	Buildings: downtown towers, midtown shops and flats, industrial sheds and suburban houses.
	Everything sits on a block's lot at Layout.CURB_Y.
]]

local Layout = require(script.Parent.Layout)
local Props = require(script.Parent.Props)
local PartKit = require(script.Parent.Parent.PartKit)

local Buildings = {}

local Y = Layout.CURB_Y
local SMOOTH = Enum.Material.SmoothPlastic
local CONCRETE = Enum.Material.Concrete
local GLASS = Enum.Material.Glass
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

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- A glass tower with concrete floor bands and corner piers
function Buildings.Tower(parent: Instance, cx: number, cz: number, w: number, d: number, h: number, rng: Random)
	local model = PartKit.Model(parent, "Tower")
	local glass = pick(rng, GLASS_TINTS)
	local stone = pick(rng, CONCRETE_TONES)
	local core = PartKit.Box(model, "Glass", Vector3.new(w - 1.6, h, d - 1.6), CFrame.new(cx, Y + h / 2, cz), glass, GLASS)
	core.Reflectance = 0.18
	local floor = 15
	for y = floor, h - 4, floor do
		PartKit.Box(model, "Floor", Vector3.new(w, 1.3, d), CFrame.new(cx, Y + y, cz), stone, CONCRETE)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			PartKit.Box(model, "Pier", Vector3.new(2.4, h, 2.4), CFrame.new(cx + sx * (w / 2 - 1.2), Y + h / 2, cz + sz * (d / 2 - 1.2)), stone, CONCRETE)
		end
	end
	-- mid-face mullions on the long faces
	for _, sx in { -1, 1 } do
		PartKit.Box(model, "Mullion", Vector3.new(0.6, h, 1.2), CFrame.new(cx + sx * 0, Y + h / 2, cz + sx * (d / 2 - 0.5)), stone, CONCRETE, DECOR)
	end
	PartKit.Box(model, "Parapet", Vector3.new(w + 0.8, 3, d + 0.8), CFrame.new(cx, Y + h + 1.5, cz), stone, CONCRETE)
	PartKit.Box(model, "Roof", Vector3.new(w - 3, 0.4, d - 3), CFrame.new(cx, Y + h + 2.8, cz), Color3.fromRGB(80, 82, 86), CONCRETE, DECOR)
	PartKit.Box(model, "Plant", Vector3.new(w * 0.3, 8, d * 0.3), CFrame.new(cx + w * 0.15, Y + h + 4, cz - d * 0.1), Color3.fromRGB(150, 155, 160), Enum.Material.DiamondPlate)
	if h > 260 then
		PartKit.Post(model, "Antenna", 1.2, 40, Vector3.new(cx - w * 0.2, Y + h + 3, cz + d * 0.15), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		PartKit.Ball(model, "Beacon", 2, Vector3.new(cx - w * 0.2, Y + h + 43, cz + d * 0.15), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, DECOR)
	end
	-- lobby canopy
	PartKit.Box(model, "Canopy", Vector3.new(w * 0.4, 0.8, 8), CFrame.new(cx, Y + 11, cz + d / 2 + 4), stone, CONCRETE, NO_COLLIDE)
end

-- A brick building with ribbon windows; the ground floor is shopfronts facing `front`
function Buildings.Midrise(parent: Instance, cx: number, cz: number, w: number, d: number, floors: number, front: Vector3, rng: Random)
	local model = PartKit.Model(parent, "Building")
	local floorH = 12
	local h = floors * floorH + 2
	local brick = pick(rng, BRICKS)
	PartKit.Box(model, "Body", Vector3.new(w, h, d), CFrame.new(cx, Y + h / 2, cz), brick, Enum.Material.Brick)
	local glass = Color3.fromRGB(56, 74, 92)
	for f = 1, floors - 1 do
		local band = PartKit.Box(model, "Windows", Vector3.new(w + 0.3, 5, d + 0.3), CFrame.new(cx, Y + f * floorH + 6.5, cz), glass, GLASS, DECOR)
		band.Reflectance = 0.12
	end
	-- vertical brick piers break the ribbons into windows (on the front face)
	local right = Vector3.new(-front.Z, 0, front.X)
	local faceWidth = if math.abs(front.X) > 0.5 then d else w
	local faceDepth = if math.abs(front.X) > 0.5 then w else d
	local frontCenter = Vector3.new(cx, Y, cz) + front * (faceDepth / 2)
	local piers = math.max(2, math.floor(faceWidth / 14))
	for i = 1, piers - 1 do
		local p = frontCenter + right * (-faceWidth / 2 + i * faceWidth / piers) + front * 0.25
		PartKit.Box(model, "Pier", Vector3.new(1.6, h - floorH, 1.6), CFrame.lookAt(p + Vector3.new(0, floorH + (h - floorH) / 2, 0), p + Vector3.new(0, floorH + (h - floorH) / 2, 0) + front), brick, Enum.Material.Brick, DECOR)
	end
	-- shopfront
	local shopCF = CFrame.lookAt(frontCenter + Vector3.new(0, 4.5, 0) + front * 0.2, frontCenter + Vector3.new(0, 4.5, 0) + front * 2)
	local shop = PartKit.Box(model, "Shopfront", Vector3.new(faceWidth - 3, 8, 0.6), shopCF, Color3.fromRGB(70, 96, 110), GLASS, DECOR)
	shop.Reflectance = 0.2
	local awningColor = pick(rng, AWNINGS)
	local awningCF = CFrame.lookAt(frontCenter + Vector3.new(0, 10.2, 0) + front * 3, frontCenter + Vector3.new(0, 10.2, 0) + front * 6) * CFrame.Angles(math.rad(-15), 0, 0)
	PartKit.Box(model, "Awning", Vector3.new(faceWidth - 4, 0.5, 6), awningCF, awningColor, Enum.Material.Fabric, NO_COLLIDE)
	local signCF = CFrame.lookAt(frontCenter + Vector3.new(0, 13.5, 0) + front * 0.4, frontCenter + Vector3.new(0, 13.5, 0) + front * 2)
	local sign = PartKit.Box(model, "ShopSign", Vector3.new(math.min(faceWidth - 6, 34), 3.6, 0.5), signCF, Color3.fromRGB(245, 242, 235), SMOOTH, DECOR)
	PartKit.Sign(sign, Enum.NormalId.Front, pick(rng, SHOPS), awningColor, nil, Enum.Font.FredokaOne, 12)
	-- roof trim and sometimes a water tank
	PartKit.Box(model, "Cornice", Vector3.new(w + 1, 1.2, d + 1), CFrame.new(cx, Y + h + 0.6, cz), Color3.fromRGB(220, 215, 205), CONCRETE)
	if rng:NextNumber() < 0.35 then
		local tank = Vector3.new(cx + rng:NextNumber(-w / 4, w / 4), Y + h + 1, cz + rng:NextNumber(-d / 4, d / 4))
		for _, o in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) } do
			PartKit.Post(model, "TankLeg", 0.4, 6, tank + o, Color3.fromRGB(60, 50, 40), Enum.Material.Wood, DECOR)
		end
		PartKit.Post(model, "Tank", 7, 7, tank + Vector3.new(0, 6, 0), Color3.fromRGB(130, 96, 66), Enum.Material.WoodPlanks)
	end
end

function Buildings.Warehouse(parent: Instance, cx: number, cz: number, w: number, d: number, h: number, front: Vector3, rng: Random)
	local model = PartKit.Model(parent, "Warehouse")
	local wall = pick(rng, { Color3.fromRGB(190, 192, 186), Color3.fromRGB(160, 170, 175), Color3.fromRGB(196, 180, 150) })
	PartKit.Box(model, "Walls", Vector3.new(w, h, d), CFrame.new(cx, Y + h / 2, cz), wall, Enum.Material.Concrete)
	PartKit.Box(model, "Roof", Vector3.new(w + 2, 1.5, d + 2), CFrame.new(cx, Y + h + 0.75, cz), Color3.fromRGB(110, 115, 120), Enum.Material.DiamondPlate)
	local right = Vector3.new(-front.Z, 0, front.X)
	local faceWidth = if math.abs(front.X) > 0.5 then d else w
	local faceDepth = if math.abs(front.X) > 0.5 then w else d
	local face = Vector3.new(cx, Y, cz) + front * (faceDepth / 2 + 0.2)
	local doors = math.max(1, math.floor(faceWidth / 40))
	for i = 1, doors do
		local p = face + right * (-faceWidth / 2 + (i - 0.5) * faceWidth / doors) + Vector3.new(0, 8, 0)
		PartKit.Box(model, "LoadingDoor", Vector3.new(16, 16, 0.5), CFrame.lookAt(p, p + front), Color3.fromRGB(90, 96, 104), Enum.Material.CorrodedMetal, DECOR)
		PartKit.Box(model, "DoorStripe", Vector3.new(16.2, 1, 0.6), CFrame.lookAt(p + Vector3.new(0, 8.5, 0), p + Vector3.new(0, 8.5, 0) + front), Color3.fromRGB(240, 190, 30), SMOOTH, DECOR)
	end
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
function Buildings.House(parent: Instance, center: Vector3, front: Vector3, setback: number, rng: Random)
	local model = PartKit.Model(parent, "House")
	local w, d, h = rng:NextNumber(30, 38), rng:NextNumber(24, 30), rng:NextNumber(11, 13)
	local look = CFrame.lookAt(center, center + front) -- -Z toward the street
	local wall = pick(rng, HOUSE_COLORS)
	local roof = pick(rng, ROOFS)
	local material = if rng:NextNumber() < 0.5 then Enum.Material.Plaster else Enum.Material.WoodPlanks
	PartKit.Box(model, "Walls", Vector3.new(w, h, d), look * CFrame.new(0, h / 2, 0), wall, material)
	-- gable roof: a square prism turned 45 degrees along the ridge (its lower half hides in the walls)
	local s = (d + 3) / math.sqrt(2)
	PartKit.Box(model, "Roof", Vector3.new(w + 2, s, s), look * CFrame.new(0, h, 0) * CFrame.Angles(math.rad(45), 0, 0), roof, Enum.Material.Slate)
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
		PartKit.Box(model, "Chimney", Vector3.new(3, 8, 3), look * CFrame.new(-w * 0.35, h + 4, d * 0.15), Color3.fromRGB(150, 80, 60), Enum.Material.Brick)
	end
	return model
end

-- Fills a block according to its district
function Buildings.Fill(parent: Instance, block: Layout.Block, rng: Random)
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
				Buildings.Midrise(folder, bx, bz, bw, bd, rng:NextInteger(3, 8), front, rng)
			end
		end
		PartKit.Box(folder, "CarPark", Vector3.new(w - 10, 0.25, d - 200), CFrame.new(cx, Y + 0.12, cz), Color3.fromRGB(80, 82, 86), Enum.Material.Asphalt)
		for i = -4, 4 do
			PartKit.Box(folder, "Bay", Vector3.new(0.4, 0.05, 16), CFrame.new(cx + i * 12, Y + 0.27, cz), Color3.fromRGB(235, 235, 235), SMOOTH, DECOR)
		end
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
	elseif block.District == "Suburb" then
		PartKit.Box(folder, "Lawns", Vector3.new(w, 0.3, d), CFrame.new(cx, Y + 0.15, cz), Props.Palette.Lawn, Enum.Material.Grass)
		for _, side in { -1, 1 } do
			local front = Vector3.new(0, 0, side)
			local n = 4
			local each = w / n
			for i = 0, n - 1 do
				local hx = x0 + each * (i + 0.5) + 6 * side
				local hz = cz + side * (d / 2 - 42)
				Buildings.House(folder, Vector3.new(hx, Y + 0.3, hz), front, 42, rng)
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
