--[[
	Interior: the baked inside of a walk-in shop, fast food restaurant or gas station store (design
	units, like the rest of the city; Builder scales it). Only what everyone needs is baked: the
	shell (floor, ceiling, walls, and a glazed front with an open doorway when `Front` is set;
	otherwise the storefront in front of it is the front) and the counter, the `OrderCounter` part
	(attributes `Menu` = the theme, `ShopName`; OrderService puts the Order prompt on it). The rest is
	a light `Placeholder` (tables or shelves, a menu board, someone serving) seen through the glass
	from the street; Client/ShopFit hides it and fits the room out in full detail, on each client,
	when the camera comes near.

	The model's attributes tell ShopFit how: `Theme` (Shared/Menus), `ShopName`, `Accent`,
	`DoorFrac` (the doorway's x over the room's width), `Front`, `Seed`.
]]

local Config = require(script.Parent.Parent.Config)
local Menus = require(script.Parent.Parent.Menus)
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
	local rng = o.Rng
	local theme = Menus.ThemeOf(o.Kind, o.Name)
	local wall = o.Wall or Color3.fromRGB(240, 236, 226)
	local doorX = math.clamp(o.DoorX or 0, -w / 2 + 3, w / 2 - 3)
	model:SetAttribute("Theme", theme)
	model:SetAttribute("ShopName", o.Name)
	model:SetAttribute("Accent", o.Accent)
	model:SetAttribute("DoorFrac", doorX / w)
	model:SetAttribute("Front", o.Front == true)
	model:SetAttribute("Seed", rng:NextInteger(1, 1e6))
	-- shell
	PartKit.Box(model, "ShopFloor", Vector3.new(w, 0.3, d), base * CFrame.new(0, 0.15, 0), FLOORS[rng:NextInteger(1, #FLOORS)], Enum.Material.Marble, SOLID)
	PartKit.Box(model, "Ceiling", Vector3.new(w, 0.6, d), base * CFrame.new(0, h - 0.3, 0), Color3.fromRGB(236, 236, 232), SMOOTH, SOLID)
	PartKit.Box(model, "BackWall", Vector3.new(w, h, WALL), base * CFrame.new(0, h / 2, d / 2 - WALL / 2), wall, Enum.Material.Plaster, SOLID)
	if o.Sides ~= false then
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "SideWall", Vector3.new(WALL, h, d), base * CFrame.new(sx * (w / 2 - WALL / 2), h / 2, 0), wall, Enum.Material.Plaster, SOLID)
		end
	end
	if o.Front then
		-- a glazed front: bulkhead, glass either side of an open doorway, and the wall above
		local door = 5
		local glassH = math.min(8, h - 2)
		PartKit.Box(model, "FrontHeader", Vector3.new(w, h - glassH - 1, WALL), base * CFrame.new(0, glassH + 1 + (h - glassH - 1) / 2, -d / 2 + WALL / 2), wall, Enum.Material.Plaster, SOLID)
		for _, span in { { -w / 2, doorX - door / 2 }, { doorX + door / 2, w / 2 } } do
			local sw = span[2] - span[1]
			if sw > 0.2 then
				local cx = (span[1] + span[2]) / 2
				PartKit.Box(model, "Bulkhead", Vector3.new(sw, 1, WALL), base * CFrame.new(cx, 0.5, -d / 2 + WALL / 2), o.Accent:Lerp(Color3.new(0, 0, 0), 0.4), SMOOTH, SOLID)
				local glass = PartKit.Box(model, "ShopGlass", Vector3.new(sw, glassH, 0.4), base * CFrame.new(cx, 1 + glassH / 2, -d / 2 + 0.2), Color3.fromRGB(80, 110, 124), GLASS, SOLID)
				glass.Transparency = 0.45
				glass.Reflectance = 0.15
			end
		end
		PartKit.Box(model, "DoorFrame", Vector3.new(door + 0.6, 0.5, WALL + 0.2), base * CFrame.new(doorX, glassH + 1, -d / 2 + WALL / 2), Color3.fromRGB(40, 42, 46), METAL, DECOR)
	end

	-- the counter across the back
	local cw = math.clamp(w * 0.55, 8, 22)
	local cz = d / 2 - 6
	local cx = math.clamp(-doorX * 0.3, -w / 2 + cw / 2 + 1.5, w / 2 - cw / 2 - 1.5)
	local counter = PartKit.Box(model, "OrderCounter", Vector3.new(cw, 2.6, 2.4), base * CFrame.new(cx, 1.3, cz), o.Accent:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Wood, SOLID)
	counter:SetAttribute("Menu", theme)
	counter:SetAttribute("ShopName", o.Name)

	-- the placeholder: what the street sees until a client fits the room out
	local lod = PartKit.Model(model, "Placeholder")
	for i = 0, 1 do
		PartKit.Box(lod, "ShopLight", Vector3.new(math.min(w * 0.6, 24), 0.2, 1.6), base * CFrame.new(0, h - 0.7, -d / 4 + i * d / 2), Color3.fromRGB(255, 250, 235), Enum.Material.Neon, DECOR)
	end
	PartKit.Box(lod, "CounterTop", Vector3.new(cw + 0.4, 0.3, 2.8), base * CFrame.new(cx, 2.75, cz), Color3.fromRGB(230, 228, 222), Enum.Material.Marble, DECOR)
	person(lod, base * CFrame.new(cx, 0.3, cz + 2.6) * CFrame.Angles(0, math.pi, 0), o.Accent, rng)
	local board = PartKit.Box(lod, "MenuBoard", Vector3.new(math.min(cw, 14), 3.6, 0.3), base * CFrame.new(cx, math.min(h - 2.6, 8.2), d / 2 - WALL - 0.2), Color3.fromRGB(26, 26, 30), SMOOTH, DECOR)
	local menu = Menus.Themes[theme]
	PartKit.Sign(board, Enum.NormalId.Front, o.Name .. "\n" .. (if menu then menu.Title else ""), Color3.fromRGB(255, 220, 120), Color3.fromRGB(26, 26, 30), Enum.Font.GothamBold, 10)
	local room0, room1 = -d / 2 + 4, cz - 4 -- free floor between the door and the counter
	if theme == "Food" or theme == "Cafe" or theme == "Eatery" then
		local cols = math.max(1, math.floor((w - 6) / 9))
		local rows = math.max(1, math.floor((room1 - room0) / 8))
		for i = 0, cols - 1 do
			for j = 0, rows - 1 do
				if (i + j) % 2 == 0 then
					local at = base * CFrame.new(-w / 2 + 4.5 + i * 9, 0.3, room0 + 4 + j * 8)
					PartKit.Box(lod, "Table", Vector3.new(3.4, 0.25, 3.4), at * CFrame.new(0, 2.0, 0), Color3.fromRGB(245, 245, 240), SMOOTH, DECOR)
					PartKit.Box(lod, "TableLeg", Vector3.new(0.35, 1.9, 0.35), at * CFrame.new(0, 0.95, 0), Color3.fromRGB(60, 60, 64), METAL, DECOR)
				end
			end
		end
	else
		local aisles = math.max(1, math.min(3, math.floor((w - 8) / 8)))
		local len = math.max(4, math.min(room1 - room0 - 4, 14))
		for i = 0, aisles - 1 do
			local x = if aisles == 1 then w * 0.2 else -w / 2 + 6 + i * ((w - 12) / (aisles - 1))
			local at = base * CFrame.new(x, 0.3, (room0 + room1) / 2)
			PartKit.Box(lod, "Shelf", Vector3.new(2, 4.4, len), at * CFrame.new(0, 2.2, 0), Color3.fromRGB(236, 236, 232), METAL, DECOR)
			for _, sx in { -1, 1 } do
				PartKit.Box(lod, "Goods", Vector3.new(0.5, 3.6, len - 0.6), at * CFrame.new(sx * 1.2, 2.2, 0), GOODS[rng:NextInteger(1, #GOODS)], SMOOTH, DECOR)
			end
		end
	end
	return model
end

return Interior
