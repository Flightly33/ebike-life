--[[
	Interior: the inside of a walk-in shop, fast food restaurant or gas station store (design units,
	like the rest of the city; Builder scales it).

	`base` sits on the floor in the middle of the room with -Z toward the street. The room is a
	shell (floor, ceiling with light panels, back and side walls, and a glazed front with an open
	doorway when `Front` is set; otherwise the storefront in front of it is the front), a counter
	at the back with the `OrderCounter` part (attributes `Menu`, `ShopName`; OrderService puts the
	Order prompt on it), a menu board, someone serving, and the room's fittings by kind: tables and
	stools (Food), shelves and a drinks fridge (Gas, Shop).
]]

local Config = require(script.Parent.Parent.Config)
local PartKit = require(script.Parent.Parent.PartKit)

local Interior = {}

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local SOLID = { Touch = false, Shadow = false }
local WALL = 1

export type Options = {
	Kind: string, -- "Food", "Gas" or "Shop" (the menu it sells)
	Name: string,
	Accent: Color3,
	Wall: Color3?,
	Front: boolean?, -- build a glazed front with a doorway (FastFood, gas stores)
	DoorX: number?, -- the doorway's x on that front
	Sides: boolean?, -- build the side walls (false where the building's own walls are)
	Rng: Random,
}

local FLOORS = { Color3.fromRGB(226, 222, 212), Color3.fromRGB(200, 196, 188), Color3.fromRGB(176, 150, 120), Color3.fromRGB(236, 236, 232) }
local GOODS = { Color3.fromRGB(220, 60, 50), Color3.fromRGB(250, 200, 50), Color3.fromRGB(60, 140, 220), Color3.fromRGB(70, 180, 100), Color3.fromRGB(240, 130, 40), Color3.fromRGB(240, 240, 236) }

local function person(parent: Instance, at: CFrame, shirt: Color3, rng: Random)
	local skins = { Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 140, 100), Color3.fromRGB(150, 100, 70), Color3.fromRGB(96, 64, 46) }
	local skin = skins[rng:NextInteger(1, #skins)]
	-- the avatar's height in design units (Builder grows the city by WORLD_SCALE)
	local S = Config.Avatar.Height / Config.WORLD_SCALE / 5.15
	local function V(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z) * S
	end
	local function at2(x: number, y: number, z: number): CFrame
		return at * CFrame.new(x * S, y * S, z * S)
	end
	PartKit.Box(parent, "StaffLegs", V(1.8, 2.1, 0.9), at2(0, 1.05, 0), Color3.fromRGB(40, 44, 60), Enum.Material.Fabric, DECOR)
	PartKit.Box(parent, "StaffTorso", V(2, 1.9, 1), at2(0, 3.05, 0), shirt, Enum.Material.Fabric, DECOR)
	PartKit.Box(parent, "StaffApron", V(1.6, 2.2, 0.1), at2(0, 2.6, -0.55), Color3.fromRGB(245, 245, 240), Enum.Material.Fabric, DECOR)
	PartKit.Box(parent, "StaffArms", V(3.7, 1.8, 0.85), at2(0, 3.05, 0), skin, SMOOTH, DECOR)
	PartKit.Box(parent, "StaffHead", V(1.15, 1.15, 1.15), at2(0, 4.6, 0), skin, SMOOTH, DECOR)
	PartKit.Box(parent, "StaffCap", V(1.22, 0.35, 1.22), at2(0, 5.25, 0), shirt, Enum.Material.Fabric, DECOR)
	PartKit.Box(parent, "StaffBrim", V(1, 0.08, 0.55), at2(0, 5.12, -0.8), shirt, Enum.Material.Fabric, DECOR)
	for _, x in { -0.24, 0.24 } do
		PartKit.Box(parent, "StaffEye", V(0.14, 0.16, 0.04), at2(x, 4.68, -0.58), Color3.fromRGB(20, 20, 24), SMOOTH, DECOR)
	end
end

function Interior.Build(parent: Instance, base: CFrame, w: number, d: number, h: number, o: Options): Model
	local model = PartKit.Model(parent, "Interior")
	model:SetAttribute("Kind", o.Kind)
	local rng = o.Rng
	local wall = o.Wall or Color3.fromRGB(240, 236, 226)
	-- shell
	PartKit.Box(model, "ShopFloor", Vector3.new(w, 0.3, d), base * CFrame.new(0, 0.15, 0), FLOORS[rng:NextInteger(1, #FLOORS)], Enum.Material.Marble, SOLID)
	PartKit.Box(model, "Ceiling", Vector3.new(w, 0.6, d), base * CFrame.new(0, h - 0.3, 0), Color3.fromRGB(236, 236, 232), SMOOTH, SOLID)
	for i = 0, 1 do
		PartKit.Box(model, "ShopLight", Vector3.new(math.min(w * 0.6, 24), 0.2, 1.6), base * CFrame.new(0, h - 0.7, -d / 4 + i * d / 2), Color3.fromRGB(255, 250, 235), Enum.Material.Neon, DECOR)
	end
	PartKit.Box(model, "BackWall", Vector3.new(w, h, WALL), base * CFrame.new(0, h / 2, d / 2 - WALL / 2), wall, Enum.Material.Plaster, SOLID)
	if o.Sides ~= false then
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "SideWall", Vector3.new(WALL, h, d), base * CFrame.new(sx * (w / 2 - WALL / 2), h / 2, 0), wall, Enum.Material.Plaster, SOLID)
		end
	end
	if o.Front then
		-- a glazed front: bulkhead, glass either side of an open doorway, and the wall above
		local door = 5
		local dx = math.clamp(o.DoorX or 0, -w / 2 + door, w / 2 - door)
		local glassH = math.min(8, h - 2)
		PartKit.Box(model, "FrontHeader", Vector3.new(w, h - glassH - 1, WALL), base * CFrame.new(0, glassH + 1 + (h - glassH - 1) / 2, -d / 2 + WALL / 2), wall, Enum.Material.Plaster, SOLID)
		local left0, left1 = -w / 2, dx - door / 2
		local right0, right1 = dx + door / 2, w / 2
		for _, span in { { left0, left1 }, { right0, right1 } } do
			local sw = span[2] - span[1]
			if sw > 0.2 then
				local cx = (span[1] + span[2]) / 2
				PartKit.Box(model, "Bulkhead", Vector3.new(sw, 1, WALL), base * CFrame.new(cx, 0.5, -d / 2 + WALL / 2), o.Accent:Lerp(Color3.new(0, 0, 0), 0.4), SMOOTH, SOLID)
				local glass = PartKit.Box(model, "ShopGlass", Vector3.new(sw, glassH, 0.4), base * CFrame.new(cx, 1 + glassH / 2, -d / 2 + 0.2), Color3.fromRGB(80, 110, 124), GLASS, SOLID)
				glass.Transparency = 0.45
				glass.Reflectance = 0.15
			end
		end
		PartKit.Box(model, "DoorFrame", Vector3.new(door + 0.6, 0.5, WALL + 0.2), base * CFrame.new(dx, glassH + 1, -d / 2 + WALL / 2), Color3.fromRGB(40, 42, 46), METAL, DECOR)
		PartKit.Box(model, "DoorMat", Vector3.new(door, 0.06, 3), base * CFrame.new(dx, 0.33, -d / 2 + 2.5), Color3.fromRGB(50, 50, 54), Enum.Material.Fabric, DECOR)
	end

	-- the counter across the back, the till and someone serving
	local cw = math.clamp(w * 0.55, 8, 22)
	local cz = d / 2 - 6
	local counter = PartKit.Box(model, "OrderCounter", Vector3.new(cw, 2.6, 2.4), base * CFrame.new(-w * 0.1, 1.3, cz), o.Accent:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Wood, SOLID)
	counter:SetAttribute("Menu", o.Kind)
	counter:SetAttribute("ShopName", o.Name)
	PartKit.Box(model, "CounterTop", Vector3.new(cw + 0.4, 0.3, 2.8), base * CFrame.new(-w * 0.1, 2.75, cz), Color3.fromRGB(230, 228, 222), Enum.Material.Marble, DECOR)
	PartKit.Box(model, "Till", Vector3.new(1.6, 1.1, 1.2), base * CFrame.new(-w * 0.1 + cw / 2 - 2, 3.45, cz), Color3.fromRGB(34, 36, 40), SMOOTH, DECOR)
	local screen = PartKit.Box(model, "TillScreen", Vector3.new(1.4, 0.8, 0.1), base * CFrame.new(-w * 0.1 + cw / 2 - 2, 4.2, cz - 0.4), Color3.fromRGB(30, 60, 90), Enum.Material.Neon, DECOR)
	local _ = screen
	person(model, base * CFrame.new(-w * 0.1, 0.3, cz + 2.6) * CFrame.Angles(0, math.pi, 0), o.Accent, rng)
	-- the menu board on the back wall, facing in
	local board = PartKit.Box(model, "MenuBoard", Vector3.new(math.min(cw, 14), 3.6, 0.3), base * CFrame.new(-w * 0.1, math.min(h - 2.6, 8.2), d / 2 - WALL - 0.2), Color3.fromRGB(26, 26, 30), SMOOTH, DECOR)
	local lines = if o.Kind == "Food" then "🍟 FRIES & SHAKE   🍔 #1 COMBO   🍗 FEAST" elseif o.Kind == "Gas" then "☕ COFFEE   ⚡ ENERGY   🔋 BATTERY TOP-UP" else "💧 WATER   🥭 SMOOTHIES   🥐 PASTELITOS"
	PartKit.Sign(board, Enum.NormalId.Front, o.Name .. "\n" .. lines, Color3.fromRGB(255, 220, 120), Color3.fromRGB(26, 26, 30), Enum.Font.GothamBold, 10)

	-- fittings
	local room0, room1 = -d / 2 + 4, cz - 4 -- free floor between the door and the counter
	if o.Kind == "Food" then
		local cols = math.max(1, math.floor((w - 6) / 9))
		local rows = math.max(1, math.floor((room1 - room0) / 8))
		for i = 0, cols - 1 do
			for j = 0, rows - 1 do
				if (i + j) % 2 == 0 or cols * rows <= 2 then
					local at = base * CFrame.new(-w / 2 + 4.5 + i * 9, 0.3, room0 + 4 + j * 8)
					PartKit.Box(model, "Table", Vector3.new(3.4, 0.25, 3.4), at * CFrame.new(0, 2.0, 0), Color3.fromRGB(245, 245, 240), SMOOTH, DECOR)
					PartKit.Box(model, "TableLeg", Vector3.new(0.35, 1.9, 0.35), at * CFrame.new(0, 0.95, 0), Color3.fromRGB(60, 60, 64), METAL, DECOR)
					for _, sx in { -1, 1 } do
						PartKit.Box(model, "Stool", Vector3.new(1.4, 1.2, 1.4), at * CFrame.new(sx * 2.6, 0.6, 0), o.Accent, SMOOTH, DECOR)
					end
				end
			end
		end
	else
		-- aisles of shelves with goods, a drinks fridge on a side wall
		local aisles = math.max(1, math.min(3, math.floor((w - 8) / 8)))
		local len = math.max(4, math.min(room1 - room0 - 4, 14))
		for i = 0, aisles - 1 do
			local x = -w / 2 + 6 + i * ((w - 12) / math.max(1, aisles - 1))
			if aisles == 1 then
				x = w * 0.2
			end
			local at = base * CFrame.new(x, 0.3, (room0 + room1) / 2)
			PartKit.Box(model, "Shelf", Vector3.new(2, 4.4, len), at * CFrame.new(0, 2.2, 0), Color3.fromRGB(236, 236, 232), METAL, SOLID)
			for k = 0, 2 do
				for _, sx in { -1, 1 } do
					PartKit.Box(model, "Goods", Vector3.new(0.5, 1, len - 0.6), at * CFrame.new(sx * 1.2, 1.0 + k * 1.3, 0), GOODS[rng:NextInteger(1, #GOODS)], SMOOTH, DECOR)
				end
			end
		end
		local fx = if (o.DoorX or 0) > 0 then -w / 2 + 1.6 else w / 2 - 1.6
		local fridge = PartKit.Box(model, "Fridge", Vector3.new(2.2, 7, math.min(12, room1 - room0)), base * CFrame.new(fx, 3.8, (room0 + room1) / 2), Color3.fromRGB(200, 230, 240), GLASS, SOLID)
		fridge.Transparency = 0.3
		PartKit.Box(model, "FridgeLight", Vector3.new(0.3, 6.4, math.min(11, room1 - room0 - 1)), base * CFrame.new(fx + (if fx > 0 then 1 else -1) * 0.8, 3.8, (room0 + room1) / 2), Color3.fromRGB(220, 245, 255), Enum.Material.Neon, DECOR)
	end
	-- a plant by the door
	PartKit.Post(model, "Planter", 1.8, 1.8, (base * CFrame.new(w / 2 - 2.2, 0.3, -d / 2 + 2.6)).Position, Color3.fromRGB(70, 70, 74), Enum.Material.Concrete, DECOR)
	PartKit.Ball(model, "Plant", 2.6, (base * CFrame.new(w / 2 - 2.2, 3.1, -d / 2 + 2.6)).Position, Color3.fromRGB(60, 130, 60), Enum.Material.Grass, DECOR)
	return model
end

return Interior
