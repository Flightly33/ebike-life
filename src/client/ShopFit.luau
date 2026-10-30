--[[
	ShopFit: fits out the walk-in shops near the camera in full detail, on this client only.

	The baked city holds each shop's shell, its counter (`OrderCounter`, where OrderService's Order
	prompt lives) and a light `Placeholder` that the street sees through the glass (City/Interior).
	When the camera comes within `Graphics.ShopRange` of a shop, the nearest `Graphics.ShopRooms`
	are fitted out: the placeholder is hidden and the room built by its theme (Shared/Menus):
	  Food      checker floor, kitchen line (fryers, grill, heat lamp with burgers, hood), soda
	            fountain, digital menu screens, now-serving board, self-order kiosk, booths, tables,
	            condiment station
	  Gas       tiled floor, snack gondolas full of products, a cooler wall of drinks, slushie and
	            coffee machines, hot dog roller, ice chest, ATM, merch wall behind the till
	  Cafe      plank floor, espresso machine and grinder, pastry case, chalkboard menus, round
	            tables, pendant bulbs, ceiling fan
	  Market    produce crates, juice bar, gondola, cooler
	  Eatery    open kitchen (range, woks, steam), red lanterns, tables set with bowls
	  Gear      slatwall of helmets and tyres, gadget case, mannequin in a hoodie, workbench
	  Boutique  clothing racks, mannequins, mirror, shades spinner, jewellery case, chandelier
	and in every room: lights, trims, a clock, an exit sign, plants, a bin, menu boards built from
	the menu, and someone serving who greets you, follows you with their eyes, and makes and hands
	over what anyone orders (the counter's `LastOrder` attribute). A room further than 1.3x the
	range goes back to its placeholder. Furniture collides (only for this client: the local
	character's physics runs here).

	Everything is sized in metres at the avatar's scale (`S` studs per metre), in the room's frame:
	the floor's top middle, +X across, -Z toward the street.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local ItemModel = require(Shared.Models.ItemModel)
local Bikes = require(Shared.Bikes)
local BikeModel = require(Shared.Models.BikeModel)
local Menus = require(Shared.Menus)
local PartKit = require(Shared.PartKit)

local Graphics = require(script.Parent.Graphics)
local Sound = require(script.Parent.Sound)

local ShopFit = {}

local S = Config.Avatar.Height / 1.75 -- studs per metre at the avatar's size
local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local STEEL = Enum.Material.DiamondPlate
local GLASS = Enum.Material.Glass
local WOOD = Enum.Material.Wood
local FABRIC = Enum.Material.Fabric
local NEON = Enum.Material.Neon
local MARBLE = Enum.Material.Marble

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = rgb(246, 246, 242)
local OFFWHITE = rgb(232, 228, 220)
local DARK = rgb(30, 30, 34)
local CHROME = rgb(196, 200, 206)
local INOX = rgb(170, 174, 180)
local GOODS = { rgb(220, 50, 46), rgb(250, 196, 40), rgb(40, 120, 220), rgb(60, 170, 90), rgb(240, 120, 30), rgb(150, 60, 200), rgb(250, 250, 246), rgb(30, 30, 34), rgb(240, 90, 150) }
local FRUIT = { rgb(250, 140, 20), rgb(120, 200, 50), rgb(220, 30, 40), rgb(250, 210, 40), rgb(250, 170, 60) }

type Spinner = { Part: BasePart, Base: CFrame, Axis: Vector3, Rate: number, Pivot: CFrame? }
type Staff = {
	Model: Model,
	Parts: { [string]: BasePart },
	Pos: Vector3, -- metres, room frame
	Yaw: number,
	HeadYaw: number,
	State: string, -- "Idle", "Wave", "Prep", "Hand"
	T: number,
	ItemId: string?,
	Held: Model?,
	Bubble: TextLabel,
	BubbleGui: BillboardGui,
	BubbleUntil: number,
}
type Room = {
	Interior: Model,
	Floor: BasePart,
	Counter: BasePart?,
	Base: CFrame,
	W: number,
	D: number,
	H: number,
	Wall: number,
	Theme: string,
	Name: string,
	Accent: Color3,
	DoorX: number,
	Front: boolean,
	Rng: Random,
	Model: Model,
	Staff: Staff?,
	Spinners: { Spinner },
	Clock: TextLabel?,
	Serving: TextLabel?,
	ServingNo: number,
	Inside: boolean,
	Conns: { RBXScriptConnection },
	Hidden: { BasePart },
	Guis: { SurfaceGui },
}

local folder: Folder
local offline = false -- fitting rooms for an offline preview: no signals, no placeholder
local known: { [Model]: boolean } = {}
local fitted: { [Model]: Room } = {}

--------------------------------------------------------------------------------
-- Building in the room's frame (metres)
--------------------------------------------------------------------------------

local function at(x: number, y: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0)
end

local function world(room: Room, cf: CFrame): CFrame
	return room.Base * CFrame.new(cf.Position * S) * cf.Rotation
end

local shadows = true
local function finish(p: BasePart, solid: boolean?): BasePart
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true and shadows
	return p
end

local function box(room: Room, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return finish(PartKit.Box(room.Model, name, size * S, world(room, cf), color, material or SMOOTH), solid)
end

-- an upright cylinder (diameter d, height h) centred at cf
local function cyl(room: Room, name: string, d: number, h: number, cf: CFrame, color: Color3, material: Enum.Material?, solid: boolean?): BasePart
	return finish(PartKit.Cylinder(room.Model, name, d * S, h * S, world(room, cf) * CFrame.Angles(0, 0, math.pi / 2), color, material or SMOOTH), solid)
end

-- a cylinder lying along the frame's X
local function rod(room: Room, name: string, d: number, len: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return finish(PartKit.Cylinder(room.Model, name, d * S, len * S, world(room, cf), color, material or SMOOTH))
end

local function ball(room: Room, name: string, d: number, p: Vector3, color: Color3, material: Enum.Material?): BasePart
	return finish(PartKit.Ball(room.Model, name, d * S, world(room, CFrame.new(p)).Position, color, material or SMOOTH))
end

local function ell(room: Room, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	return finish(PartKit.Ellipsoid(room.Model, name, size * S, world(room, cf), color, material or SMOOTH))
end

local function item(room: Room, id: string, cf: CFrame, scale: number?): Model
	local model = ItemModel.Build(id, S * (scale or 1))
	PartKit.PlaceStatic(model, world(room, cf)) -- (built at the origin; works offline too)
	model.Parent = room.Model
	return model
end

-- A SurfaceGui on a part's face with a vertical list inside; returns the list frame
local function screen(part: BasePart, face: Enum.NormalId, background: Color3, glow: boolean?): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = if glow then 0 else 0.6
	gui.Brightness = if glow then 1.6 else 1
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = background
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingTop = UDim.new(0.05, 0)
	pad.PaddingBottom = UDim.new(0.05, 0)
	pad.Parent = frame
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.02, 0)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = frame
	return frame
end

local function line(parent: Instance, text: string, height: number, color: Color3, font: Enum.Font, order: number, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, height, 0)
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = font
	label.TextXAlignment = align or Enum.TextXAlignment.Center
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function sign(part: BasePart, face: Enum.NormalId, text: string, color: Color3, background: Color3?, font: Enum.Font?): TextLabel
	local label = PartKit.Sign(part, face, text, color, background, font or Enum.Font.GothamBlack, 40)
	local gui = label.Parent :: SurfaceGui
	gui.LightInfluence = 0.4
	return label
end

local function light(room: Room, p: Vector3, range: number, brightness: number, color: Color3)
	local holder = box(room, "LightHolder", Vector3.new(0.05, 0.05, 0.05), CFrame.new(p), WHITE)
	holder.Transparency = 1
	local l = Instance.new("PointLight")
	l.Range = range * S
	l.Brightness = brightness
	l.Color = color
	l.Shadows = false
	l.Parent = holder
end

-- turns a part about its own axis, or (with `pivot`, world) about the pivot's
local function spin(room: Room, part: BasePart, axis: Vector3, rate: number, pivot: CFrame?)
	local rel = if pivot then pivot:ToObjectSpace(part.CFrame) else part.CFrame
	table.insert(room.Spinners, { Part = part, Base = rel, Axis = axis, Rate = rate, Pivot = pivot })
end

--------------------------------------------------------------------------------
-- Shared pieces
--------------------------------------------------------------------------------

local function chair(room: Room, cf: CFrame, color: Color3, stool: boolean?)
	local seat = if stool then 0.75 else 0.46
	cyl(room, "ChairLeg", 0.05, seat, cf * CFrame.new(0, seat / 2, 0), DARK, METAL)
	cyl(room, "ChairFoot", 0.36, 0.03, cf * CFrame.new(0, 0.015, 0), DARK, METAL)
	if stool then
		cyl(room, "Seat", 0.38, 0.07, cf * CFrame.new(0, seat + 0.035, 0), color, FABRIC, true)
		rod(room, "FootRing", 0.025, 0.36, cf * CFrame.new(0, 0.3, 0), CHROME, METAL)
	else
		box(room, "Seat", Vector3.new(0.44, 0.06, 0.44), cf * CFrame.new(0, seat + 0.03, 0), color, SMOOTH, true)
		box(room, "ChairBack", Vector3.new(0.44, 0.42, 0.05), cf * CFrame.new(0, seat + 0.27, 0.2) * CFrame.Angles(math.rad(-8), 0, 0), color, SMOOTH)
	end
end

local function roundTable(room: Room, cf: CFrame, top: Color3, d: number)
	cyl(room, "TableTop", d, 0.04, cf * CFrame.new(0, 0.74, 0), top, MARBLE, true)
	cyl(room, "TableEdge", d + 0.01, 0.015, cf * CFrame.new(0, 0.715, 0), DARK, METAL)
	cyl(room, "TableLeg", 0.07, 0.72, cf * CFrame.new(0, 0.36, 0), DARK, METAL)
	cyl(room, "TableFoot", 0.45, 0.03, cf * CFrame.new(0, 0.015, 0), DARK, METAL)
end

local function plant(room: Room, p: Vector3, tall: boolean?)
	local h = if tall then 0.55 else 0.35
	cyl(room, "Pot", 0.42, h, CFrame.new(p + Vector3.new(0, h / 2, 0)), rgb(70, 70, 74), Enum.Material.Concrete, true)
	cyl(room, "Soil", 0.38, 0.02, CFrame.new(p + Vector3.new(0, h, 0)), rgb(60, 40, 26), Enum.Material.Ground)
	local leaves = if tall then 7 else 5
	for i = 1, leaves do
		local a = i * 2.4
		local y = h + 0.25 + (i % 3) * (if tall then 0.32 else 0.15)
		ell(room, "Leaf", Vector3.new(0.5, 0.08, 0.2), CFrame.new(p + Vector3.new(math.cos(a) * 0.18, y, math.sin(a) * 0.18)) * CFrame.Angles(0, -a, math.rad(25)), rgb(50, 120 + (i % 3) * 20, 50), Enum.Material.Grass)
	end
	if tall then
		cyl(room, "Stem", 0.04, 1.1, CFrame.new(p + Vector3.new(0, h + 0.5, 0)), rgb(90, 70, 40), WOOD)
	end
end

local function bin(room: Room, p: Vector3, yaw: number, label: string, color: Color3)
	local b = box(room, "Bin", Vector3.new(0.5, 1.0, 0.5), at(p.X, 0.5, p.Z, yaw), color, SMOOTH, true)
	box(room, "BinTop", Vector3.new(0.54, 0.06, 0.54), at(p.X, 1.03, p.Z, yaw), DARK, SMOOTH)
	box(room, "BinFlap", Vector3.new(0.34, 0.16, 0.02), at(p.X, 0.86, p.Z, yaw) * CFrame.new(0, 0, -0.26), DARK, SMOOTH)
	sign(b, Enum.NormalId.Front, label, WHITE)
end

local function poster(room: Room, cf: CFrame, w: number, h: number, big: string, small: string, bg: Color3, fg: Color3)
	box(room, "PosterFrame", Vector3.new(w + 0.06, h + 0.06, 0.03), cf, DARK, METAL)
	local p = box(room, "Poster", Vector3.new(w, h, 0.02), cf * CFrame.new(0, 0, -0.02), bg)
	local list = screen(p, Enum.NormalId.Front, bg)
	line(list, big, 0.6, fg, Enum.Font.GothamBlack, 1)
	line(list, small, 0.25, fg, Enum.Font.GothamBold, 2)
end

-- Products on a shelf run: bags, cans, boxes and bottles in bright packaging
local function stock(room: Room, cf: CFrame, len: number, depth: number, maxH: number, rng: Random, cap: number)
	local n = math.min(cap, math.floor(len / 0.3))
	local step = len / math.max(n, 1)
	for i = 0, n - 1 do
		local x = -len / 2 + (i + 0.5) * step
		local color = GOODS[rng:NextInteger(1, #GOODS)]
		local kind = rng:NextInteger(1, 4)
		if kind == 1 then -- bag
			local h = math.min(maxH, 0.3)
			box(room, "Bag", Vector3.new(step * 0.85, h, depth * 0.5), cf * CFrame.new(x, h / 2, 0) * CFrame.Angles(math.rad(-6), 0, 0), color, Enum.Material.Foil)
		elseif kind == 2 then -- cans, a row deep
			local h = math.min(maxH, 0.13)
			cyl(room, "Can", math.min(step * 0.8, 0.075), h, cf * CFrame.new(x, h / 2, -depth * 0.2), color, METAL)
			cyl(room, "Can", math.min(step * 0.8, 0.075), h, cf * CFrame.new(x, h / 2, depth * 0.2), color, METAL)
		elseif kind == 3 then -- cereal-type box
			local h = math.min(maxH, 0.28)
			box(room, "Box", Vector3.new(step * 0.8, h, depth * 0.35), cf * CFrame.new(x, h / 2, 0), color)
		else -- bottle
			local h = math.min(maxH, 0.26)
			local b = cyl(room, "Bottle", math.min(step * 0.6, 0.08), h * 0.75, cf * CFrame.new(x, h * 0.375, 0), color, GLASS)
			b.Transparency = 0.2
			cyl(room, "Cap", 0.03, h * 0.25, cf * CFrame.new(x, h * 0.875, 0), WHITE)
		end
	end
	-- the price strip on the shelf edge
	box(room, "PriceStrip", Vector3.new(len, 0.035, 0.01), cf * CFrame.new(0, -0.02, -depth / 2 - 0.005), rgb(250, 220, 60))
end

-- A double-sided gondola shelf of products, its length along the room's Z
local function gondola(room: Room, x: number, z0: number, z1: number, rng: Random, label: string)
	local len = z1 - z0
	local cz = (z0 + z1) / 2
	local base = at(x, 0, cz, math.pi / 2) -- local X runs along the room's Z
	box(room, "GondolaBase", Vector3.new(len, 0.12, 0.9), base * CFrame.new(0, 0.06, 0), rgb(220, 220, 216), METAL, true)
	box(room, "GondolaBack", Vector3.new(len, 1.55, 0.05), base * CFrame.new(0, 0.9, 0), rgb(236, 236, 232), METAL, true)
	for _, side in { -1, 1 } do
		for level = 0, 3 do
			local y = 0.16 + level * 0.36
			local shelf = base * CFrame.new(0, y, side * 0.23)
			box(room, "Shelf", Vector3.new(len, 0.025, 0.42), shelf, rgb(226, 226, 222), METAL)
			local face = shelf * CFrame.new(0, 0.013, 0) * (if side < 0 then CFrame.identity else CFrame.Angles(0, math.pi, 0))
			stock(room, face, len - 0.06, 0.4, 0.32, rng, 7)
		end
	end
	for _, e in { -1, 1 } do
		local cap = box(room, "EndCap", Vector3.new(0.04, 0.4, 0.86), base * CFrame.new(e * (len / 2 + 0.02), 1.5, 0), room.Accent)
		sign(cap, if e > 0 then Enum.NormalId.Right else Enum.NormalId.Left, label, WHITE)
	end
end

-- A wall of glass-door coolers full of drinks, against a side wall (`side` -1 left, 1 right)
local function cooler(room: Room, side: number, z0: number, z1: number, rng: Random)
	local wallX = side * (room.W / 2 - room.Wall)
	local len = math.min(z1 - z0, 4.2)
	local doors = math.max(1, math.floor(len / 0.8))
	len = doors * 0.8
	local cz = z0 + len / 2
	local yaw = if side < 0 then -math.pi / 2 else math.pi / 2 -- face into the room
	local frame = at(wallX - side * 0.4, 0, cz, yaw)
	box(room, "CoolerBody", Vector3.new(len + 0.1, 2.1, 0.8), frame * CFrame.new(0, 1.05, 0.02), rgb(40, 42, 46), METAL, true)
	local header = box(room, "CoolerHeader", Vector3.new(len + 0.1, 0.22, 0.02), frame * CFrame.new(0, 2.0, -0.39), room.Accent, NEON)
	sign(header, Enum.NormalId.Front, "❄ COLD DRINKS ❄", WHITE)
	for d = 0, doors - 1 do
		local dx = -len / 2 + (d + 0.5) * 0.8
		for s = 0, 3 do
			local y = 0.2 + s * 0.42
			box(room, "CoolerShelf", Vector3.new(0.74, 0.02, 0.6), frame * CFrame.new(dx, y, 0), rgb(200, 200, 204), METAL)
			for b = 0, 3 do
				local color = GOODS[rng:NextInteger(1, #GOODS)]
				local bottle = cyl(room, "Bottle", 0.075, 0.24, frame * CFrame.new(dx - 0.27 + b * 0.18, y + 0.13, -0.15), color, GLASS)
				bottle.Transparency = 0.15
				cyl(room, "Cap", 0.035, 0.03, frame * CFrame.new(dx - 0.27 + b * 0.18, y + 0.265, -0.15), WHITE)
			end
		end
		local pane = box(room, "CoolerDoor", Vector3.new(0.76, 1.85, 0.03), frame * CFrame.new(dx, 0.98, -0.41), rgb(210, 235, 250), GLASS)
		pane.Transparency = 0.55
		pane.Reflectance = 0.15
		box(room, "DoorFrame", Vector3.new(0.04, 1.85, 0.04), frame * CFrame.new(dx - 0.39, 0.98, -0.41), DARK, METAL)
		box(room, "Handle", Vector3.new(0.025, 0.5, 0.04), frame * CFrame.new(dx + 0.3, 1.1, -0.45), CHROME, METAL)
	end
	box(room, "CoolerGlow", Vector3.new(len, 0.03, 0.03), frame * CFrame.new(0, 1.9, -0.3), rgb(230, 245, 255), NEON)
end

--------------------------------------------------------------------------------
-- The person serving
--------------------------------------------------------------------------------

local SKINS = { rgb(234, 184, 146), rgb(198, 140, 100), rgb(150, 100, 70), rgb(96, 64, 46), rgb(246, 210, 180) }
local HAIRS = { rgb(30, 22, 18), rgb(70, 46, 28), rgb(150, 110, 60), rgb(210, 180, 120) }
local Q = Config.Avatar.Height / 5.15 -- studs per unit of the box figure (5.15 units tall)

local function buildStaff(room: Room, pos: Vector3): Staff
	local model = Instance.new("Model")
	model.Name = "Staff"
	model.Parent = room.Model
	local rng = room.Rng
	local skin = SKINS[rng:NextInteger(1, #SKINS)]
	local hair = HAIRS[rng:NextInteger(1, #HAIRS)]
	local shirt = room.Accent
	local parts: { [string]: BasePart } = {}
	local function add(name: string, size: Vector3, color: Color3, material: Enum.Material?): BasePart
		local p = finish(PartKit.Box(model, name, size * Q, CFrame.identity, color, material or SMOOTH))
		parts[name] = p
		return p
	end
	add("LegL", Vector3.new(0.9, 2.1, 0.9), rgb(40, 44, 60), FABRIC)
	add("LegR", Vector3.new(0.9, 2.1, 0.9), rgb(40, 44, 60), FABRIC)
	add("Torso", Vector3.new(2, 1.9, 1), shirt, FABRIC)
	add("Apron", Vector3.new(1.7, 2.3, 0.08), if room.Theme == "Cafe" then rgb(90, 60, 40) else WHITE, FABRIC)
	add("Tag", Vector3.new(0.45, 0.2, 0.05), WHITE)
	add("Head", Vector3.new(1.15, 1.15, 1.15), skin)
	add("Hair", Vector3.new(1.22, 0.3, 1.22), hair, FABRIC)
	if room.Theme == "Food" or room.Theme == "Gas" then
		add("Cap", Vector3.new(1.24, 0.32, 1.24), shirt, FABRIC)
		add("Brim", Vector3.new(1.0, 0.07, 0.6), shirt, FABRIC)
	end
	add("EyeL", Vector3.new(0.14, 0.16, 0.04), DARK)
	add("EyeR", Vector3.new(0.14, 0.16, 0.04), DARK)
	add("Smile", Vector3.new(0.36, 0.06, 0.04), rgb(140, 50, 50))
	add("ArmL", Vector3.new(0.85, 1.9, 0.85), skin)
	add("ArmR", Vector3.new(0.85, 1.9, 0.85), skin)
	add("SleeveL", Vector3.new(0.92, 0.8, 0.92), shirt, FABRIC)
	add("SleeveR", Vector3.new(0.92, 0.8, 0.92), shirt, FABRIC)
	local tag = parts.Tag
	sign(tag, Enum.NormalId.Front, "HI!", DARK)
	-- the speech bubble
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(300, 64)
	gui.StudsOffset = Vector3.new(0, 1.9 * Q, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Adornee = parts.Head
	gui.Parent = parts.Head
	local bubble = Instance.new("Frame")
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = WHITE
	bubble.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = room.Accent
	stroke.Thickness = 3
	stroke.Parent = bubble
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, -16, 1, -10)
	text.Position = UDim2.fromOffset(8, 5)
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = DARK
	text.Parent = bubble
	return {
		Model = model,
		Parts = parts,
		Pos = pos,
		Yaw = 0,
		HeadYaw = 0,
		State = "Idle",
		T = 0,
		ItemId = nil,
		Held = nil,
		Bubble = text,
		BubbleGui = gui,
		BubbleUntil = 0,
	}
end

local function say(staff: Staff, text: string, seconds: number)
	staff.Bubble.Text = text
	staff.BubbleGui.Enabled = true
	staff.BubbleUntil = os.clock() + seconds
end

local function approach(a: number, b: number, step: number): number
	if a < b then
		return math.min(a + step, b)
	end
	return math.max(a - step, b)
end

local function poseStaff(room: Room, staff: Staff, dt: number, now: number, viewer: Vector3?)
	staff.T += dt
	local p = staff.Parts
	-- what they're doing
	local targetYaw = 0
	local armLx, armLz, armRx, armRz = 0, -0.08, 0, 0.08
	local sway = math.sin(now * 1.3) * 0.04
	if staff.State == "Wave" then
		armRz = 2.5 + math.sin(staff.T * 9) * 0.35
		if staff.T > 2.2 then
			staff.State = "Idle"
		end
	elseif staff.State == "Prep" then
		targetYaw = math.pi
		local work = math.sin(staff.T * 10) * 0.15
		armLx, armRx = 1.0 + work, 1.0 - work
		if staff.T > 1.6 then
			staff.State = "Hand"
			staff.T = 0
			local id = staff.ItemId
			if id then
				local held = ItemModel.Build(id, S)
				held.Parent = staff.Model
				staff.Held = held
				local menuItem = Menus.Get(room.Theme, id)
				say(staff, "Here you go! " .. (if menuItem then menuItem.Icon else "🙂"), 2.6)
			end
		end
	elseif staff.State == "Hand" then
		armRx = 1.35
		armLx = 0.3
		if staff.T > 2.4 then
			staff.State = "Idle"
			local held = staff.Held
			if held then
				held:Destroy()
				staff.Held = nil
			end
		end
	end
	staff.Yaw = approach(staff.Yaw, targetYaw, dt * 5)
	-- follow the viewer with the head when facing the shop floor
	local headTarget = 0
	local root = world(room, CFrame.new(staff.Pos) * CFrame.Angles(0, staff.Yaw, 0))
	if viewer and staff.State ~= "Prep" then
		local rel = root:PointToObjectSpace(viewer)
		if rel.Magnitude < 12 * S and rel.Z < 0 then
			headTarget = math.clamp(math.atan2(-rel.X, -rel.Z), -0.8, 0.8)
		end
	end
	staff.HeadYaw = approach(staff.HeadYaw, headTarget, dt * 3)
	local bob = math.sin(now * 2.1) * 0.02 * Q
	local function u(x: number, y: number, z: number): CFrame
		return CFrame.new(x * Q, y * Q, z * Q)
	end
	local hip = root * CFrame.new(0, bob, 0) * u(0, 2.1, 0)
	p.LegL.CFrame = hip * u(-0.5, -1.05, 0)
	p.LegR.CFrame = hip * u(0.5, -1.05, 0)
	local torso = root * CFrame.new(0, bob, 0) * u(0, 3.05, 0) * CFrame.Angles(0, sway, 0)
	p.Torso.CFrame = torso
	p.Apron.CFrame = torso * u(0, -0.45, -0.55)
	p.Tag.CFrame = torso * u(0.5, 0.45, -0.54)
	local head = torso * u(0, 1.55, 0) * CFrame.Angles(0, staff.HeadYaw, 0)
	p.Head.CFrame = head
	p.Hair.CFrame = head * u(0, 0.47, 0.03)
	local cap = p.Cap
	if cap then
		cap.CFrame = head * u(0, 0.6, 0)
		p.Brim.CFrame = head * u(0, 0.48, -0.82)
	end
	p.EyeL.CFrame = head * u(-0.24, 0.1, -0.58)
	p.EyeR.CFrame = head * u(0.24, 0.1, -0.58)
	p.Smile.CFrame = head * u(0, -0.25, -0.58)
	local shoulder = torso * u(0, 0.85, 0)
	local armL = shoulder * u(-1.43, 0, 0) * CFrame.Angles(armLx, 0, armLz) * u(0, -0.9, 0)
	local armR = shoulder * u(1.43, 0, 0) * CFrame.Angles(armRx, 0, armRz) * u(0, -0.9, 0)
	p.ArmL.CFrame = armL
	p.ArmR.CFrame = armR
	p.SleeveL.CFrame = armL * u(0, 0.55, 0)
	p.SleeveR.CFrame = armR * u(0, 0.55, 0)
	local held = staff.Held
	if held then
		held:PivotTo(armR * u(0, -1.05, 0) * CFrame.Angles(-armRx, 0, 0))
	end
	if staff.BubbleGui.Enabled and now > staff.BubbleUntil then
		staff.BubbleGui.Enabled = false
	end
end

--------------------------------------------------------------------------------
-- Room-wide fittings
--------------------------------------------------------------------------------

local function floorFinish(room: Room)
	local w, d = room.W - 2 * room.Wall, room.D - 0.1
	local y = 0.006
	if room.Theme == "Food" or room.Theme == "Eatery" then
		local base = if room.Theme == "Food" then WHITE else rgb(220, 200, 170)
		local dark = if room.Theme == "Food" then rgb(36, 36, 40) else rgb(150, 50, 40)
		box(room, "FloorFinish", Vector3.new(w, 0.012, d), CFrame.new(0, y, 0), base, MARBLE)
		local tile = math.max(0.9, math.sqrt(w * d / 180))
		local nx, nz = math.floor(w / tile), math.floor(d / tile)
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				if (i + j) % 2 == 0 then
					box(room, "Tile", Vector3.new(tile, 0.014, tile), CFrame.new(-w / 2 + (i + 0.5) * tile, y + 0.001, -d / 2 + (j + 0.5) * tile), dark, MARBLE)
				end
			end
		end
	elseif room.Theme == "Cafe" or room.Theme == "Boutique" then
		local light = if room.Theme == "Cafe" then rgb(170, 120, 76) else rgb(214, 186, 150)
		box(room, "FloorFinish", Vector3.new(w, 0.012, d), CFrame.new(0, y, 0), light, WOOD)
		local plank = 0.24
		for i = 0, math.floor(w / plank) - 1, 2 do
			box(room, "Plank", Vector3.new(plank, 0.014, d), CFrame.new(-w / 2 + (i + 0.5) * plank, y + 0.001, 0), light:Lerp(rgb(60, 40, 24), 0.18), WOOD)
		end
	elseif room.Theme == "Gear" then
		box(room, "FloorFinish", Vector3.new(w, 0.012, d), CFrame.new(0, y, 0), rgb(46, 48, 52), Enum.Material.Rubber)
		for i = 1, 3 do
			box(room, "SafetyLine", Vector3.new(0.08, 0.014, d * 0.8), CFrame.new(-w / 2 + i * w / 4, y + 0.001, 0), rgb(250, 200, 30), SMOOTH)
		end
	else
		box(room, "FloorFinish", Vector3.new(w, 0.012, d), CFrame.new(0, y, 0), rgb(236, 234, 228), MARBLE)
		local tile = 0.6
		for i = 1, math.floor(w / tile) - 1 do
			if i % 2 == 0 then
				box(room, "Grout", Vector3.new(0.012, 0.014, d), CFrame.new(-w / 2 + i * tile, y + 0.001, 0), rgb(190, 188, 182))
			end
		end
		for j = 1, math.floor(d / tile) - 1 do
			if j % 2 == 0 then
				box(room, "Grout", Vector3.new(w, 0.014, 0.012), CFrame.new(0, y + 0.001, -d / 2 + j * tile), rgb(190, 188, 182))
			end
		end
	end
end

local function trims(room: Room)
	local w, d, h = room.W, room.D, room.H
	local inner = w / 2 - room.Wall
	local back = d / 2 - room.Wall
	local accent = room.Accent
	-- skirting and an accent band round the back and side walls, a dado rail, cornice
	box(room, "Skirting", Vector3.new(inner * 2, 0.12, 0.02), CFrame.new(0, 0.06, back - 0.01), DARK)
	box(room, "AccentBand", Vector3.new(inner * 2, 0.25, 0.015), CFrame.new(0, 1.15, back - 0.01), accent)
	box(room, "Cornice", Vector3.new(inner * 2, 0.1, 0.06), CFrame.new(0, h - 0.05, back - 0.03), OFFWHITE)
	for _, sx in { -1, 1 } do
		box(room, "Skirting", Vector3.new(0.02, 0.12, d - 0.2), CFrame.new(sx * (inner - 0.01), 0.06, 0), DARK)
		box(room, "AccentBand", Vector3.new(0.015, 0.25, d - 0.2), CFrame.new(sx * (inner - 0.01), 1.15, 0), accent)
		box(room, "Cornice", Vector3.new(0.06, 0.1, d - 0.2), CFrame.new(sx * (inner - 0.03), h - 0.05, 0), OFFWHITE)
	end
	-- ceiling: light panels in a grid, vents, a smoke detector, a camera dome in the corner
	local nx = math.clamp(math.floor(w / 3.5), 1, 4)
	local nz = math.clamp(math.floor(d / 3.5), 1, 4)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x, z = -w / 2 + (i + 0.5) * w / nx, -d / 2 + (j + 0.5) * d / nz
			if room.Theme == "Cafe" or room.Theme == "Eatery" or room.Theme == "Boutique" then
				-- pendant lights
				local drop = math.min(1.4, h - 2.6)
				cyl(room, "Cord", 0.012, drop, CFrame.new(x, h - drop / 2, z), DARK)
				if room.Theme == "Eatery" then
					ell(room, "Lantern", Vector3.new(0.36, 0.44, 0.36), CFrame.new(x, h - drop - 0.18, z), rgb(220, 40, 40), NEON)
					cyl(room, "LanternCap", 0.2, 0.05, CFrame.new(x, h - drop + 0.05, z), DARK)
				else
					cyl(room, "Shade", 0.34, 0.2, CFrame.new(x, h - drop, z), if room.Theme == "Cafe" then DARK else rgb(210, 180, 110), METAL)
					ball(room, "Bulb", 0.14, Vector3.new(x, h - drop - 0.12, z), rgb(255, 214, 150), NEON)
				end
			else
				box(room, "Panel", Vector3.new(1.2, 0.04, 0.6), CFrame.new(x, h - 0.03, z), rgb(255, 252, 240), NEON)
				box(room, "PanelRim", Vector3.new(1.28, 0.03, 0.68), CFrame.new(x, h - 0.015, z), WHITE)
			end
		end
	end
	box(room, "Vent", Vector3.new(0.6, 0.03, 0.6), CFrame.new(-w / 4, h - 0.02, d / 4), rgb(210, 210, 210), METAL)
	box(room, "Vent", Vector3.new(0.6, 0.03, 0.6), CFrame.new(w / 4, h - 0.02, -d / 4), rgb(210, 210, 210), METAL)
	cyl(room, "SmokeAlarm", 0.14, 0.04, CFrame.new(0, h - 0.02, 0), WHITE)
	ell(room, "CameraDome", Vector3.new(0.22, 0.12, 0.22), CFrame.new(inner - 0.3, h - 0.03, -d / 2 + 0.6), DARK, GLASS)
	-- lights that actually light the room
	local lights = if Graphics.Current().Shadows then 2 else 1
	for i = 1, lights do
		light(room, Vector3.new(0, h - 0.6, -d / 2 + i * d / (lights + 1)), math.max(w, d) * 0.7, 1.1, rgb(255, 238, 214))
	end
	-- a clock on a side wall, the exit sign over the door
	local clockSide = if room.DoorX > 0 then -1 else 1
	local face = cyl(room, "Clock", 0.42, 0.04, CFrame.new(clockSide * (inner - 0.02), h * 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(0, 0, -math.pi / 2), WHITE)
	local _ = face
	local clockPanel = box(room, "ClockFace", Vector3.new(0.3, 0.16, 0.01), at(clockSide * (inner - 0.05), h * 0.62, 0, clockSide * math.pi / 2), DARK)
	room.Clock = sign(clockPanel, Enum.NormalId.Front, "12:00", rgb(255, 80, 60), DARK, Enum.Font.Code)
	local exit = box(room, "ExitSign", Vector3.new(0.5, 0.18, 0.06), at(room.DoorX, math.min(h - 0.3, 2.55), -d / 2 + room.Wall + 0.05, math.pi), rgb(20, 120, 50), NEON)
	sign(exit, Enum.NormalId.Front, "EXIT ➜", WHITE)
	-- a doormat inside the door
	box(room, "DoorMat", Vector3.new(1.4, 0.015, 0.9), CFrame.new(room.DoorX, 0.02, -d / 2 + room.Wall + 0.6), rgb(50, 50, 54), FABRIC)
end

-- Menu boards on the back wall above the counter, built from the theme's menu
local function menuBoards(room: Room, counterX: number, counterW: number)
	local theme = Menus.Themes[room.Theme]
	if not theme then
		return
	end
	local items = theme.Items
	local panels = math.clamp(math.ceil(#items / 4), 1, 3)
	local pw = math.min(1.7, (counterW + 1) / panels - 0.12)
	local y = math.min(room.H - 0.75, 2.75)
	local back = room.D / 2 - room.Wall - 0.04
	local style = room.Theme
	for i = 0, panels - 1 do
		local x = counterX - (panels - 1) * (pw + 0.12) / 2 + i * (pw + 0.12)
		box(room, "BoardFrame", Vector3.new(pw + 0.06, 1.06, 0.04), at(x, y, back), DARK, METAL)
		local bg = if style == "Cafe" then rgb(30, 44, 36) elseif style == "Food" or style == "Gas" then rgb(14, 14, 18) else rgb(246, 242, 232)
		local fg = if style == "Cafe" then rgb(240, 236, 220) elseif style == "Food" or style == "Gas" then rgb(255, 220, 90) else DARK
		local board = box(room, "MenuScreen", Vector3.new(pw, 1.0, 0.02), at(x, y, back - 0.03), bg)
		local list = screen(board, Enum.NormalId.Front, bg, style == "Food" or style == "Gas")
		local font = if style == "Cafe" then Enum.Font.PermanentMarker else Enum.Font.GothamBlack
		line(list, if i == 0 then string.upper(theme.Title) else "★ MORE ★", 0.16, room.Accent:Lerp(Color3.new(1, 1, 1), 0.35), font, 0)
		for j = i * 4 + 1, math.min(#items, i * 4 + 4) do
			local it = items[j]
			line(list, string.format("%s %s   %s", it.Icon, it.Name, Economy.FormatCash(it.Price)), 0.13, fg, font, j * 2, Enum.TextXAlignment.Left)
			line(list, it.Description, 0.06, fg:Lerp(bg, 0.35), Enum.Font.GothamMedium, j * 2 + 1, Enum.TextXAlignment.Left)
		end
	end
end

-- The counter dressed: a front panel in the accent colour, a stone top, the till and card reader
local function dressCounter(room: Room, cx: number, cz: number, cw: number, cd: number, ch: number)
	local front = cz - cd / 2
	box(room, "CounterFace", Vector3.new(cw, ch - 0.12, 0.02), CFrame.new(cx, (ch - 0.12) / 2 + 0.1, front - 0.012), room.Accent)
	box(room, "CounterKick", Vector3.new(cw, 0.1, 0.03), CFrame.new(cx, 0.05, front - 0.01), DARK)
	box(room, "CounterTop", Vector3.new(cw + 0.12, 0.05, cd + 0.12), CFrame.new(cx, ch + 0.025, cz), rgb(236, 232, 226), MARBLE, true)
	for i = 0, 3 do
		box(room, "CounterRib", Vector3.new(0.03, ch - 0.25, 0.03), CFrame.new(cx - cw / 2 + (i + 0.5) * cw / 4, ch / 2, front - 0.03), room.Accent:Lerp(Color3.new(1, 1, 1), 0.4), METAL)
	end
	local tillX = cx + cw / 2 - 0.45
	box(room, "Till", Vector3.new(0.4, 0.12, 0.35), CFrame.new(tillX, ch + 0.11, cz + 0.05), DARK)
	local tillScreen = box(room, "TillScreen", Vector3.new(0.36, 0.26, 0.02), at(tillX, ch + 0.3, cz - 0.05) * CFrame.Angles(math.rad(-15), 0, 0), rgb(20, 40, 70), NEON)
	sign(tillScreen, Enum.NormalId.Front, "$ PAY HERE", rgb(120, 255, 160), rgb(20, 40, 70))
	box(room, "CardReader", Vector3.new(0.09, 0.15, 0.03), at(tillX - 0.35, ch + 0.11, cz - 0.3) * CFrame.Angles(math.rad(-30), 0, 0), DARK)
	box(room, "ReaderScreen", Vector3.new(0.07, 0.06, 0.005), at(tillX - 0.35, ch + 0.13, cz - 0.318) * CFrame.Angles(math.rad(-30), 0, 0), rgb(80, 220, 255), NEON)
	-- a small sign on the counter
	local tent = box(room, "Tent", Vector3.new(0.3, 0.18, 0.02), at(cx - cw / 2 + 0.4, ch + 0.14, cz - 0.3) * CFrame.Angles(math.rad(-12), 0, 0), WHITE)
	sign(tent, Enum.NormalId.Front, "ORDER\nHERE ↓", room.Accent)
end

--------------------------------------------------------------------------------
-- Themes
--------------------------------------------------------------------------------

type Zone = { X0: number, X1: number, Z0: number, Z1: number, BackZ: number, CX: number, CZ: number, CW: number, CD: number, CH: number }

local function clearOfDoor(room: Room, x: number, half: number): boolean
	return math.abs(x - room.DoorX) > 1.0 + half
end

-- Tables (or round tables) in a grid over the shop floor, skipping the door's lane
local function dining(room: Room, z: Zone, round: boolean, chairColor: Color3, setTable: ((CFrame) -> ())?)
	local cell = 2.3
	local nx = math.floor((z.X1 - z.X0) / cell)
	local nz = math.floor((z.Z1 - z.Z0) / cell)
	local count = 0
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x = z.X0 + (i + 0.5) * (z.X1 - z.X0) / nx
			local zz = z.Z0 + (j + 0.5) * (z.Z1 - z.Z0) / nz
			if clearOfDoor(room, x, 1.0) and count < 8 then
				count += 1
				local cf = at(x, 0, zz)
				if round then
					roundTable(room, cf, rgb(240, 238, 232), 0.75)
				else
					box(room, "TableTop", Vector3.new(0.8, 0.04, 0.8), cf * CFrame.new(0, 0.74, 0), WHITE, MARBLE, true)
					box(room, "TableEdge", Vector3.new(0.82, 0.02, 0.82), cf * CFrame.new(0, 0.71, 0), room.Accent, SMOOTH)
					cyl(room, "TableLeg", 0.08, 0.72, cf * CFrame.new(0, 0.36, 0), DARK, METAL)
					box(room, "TableFoot", Vector3.new(0.5, 0.03, 0.5), cf * CFrame.new(0, 0.015, 0), DARK, METAL)
				end
				for _, s in { -1, 1 } do
					chair(room, at(x + s * 0.68, 0, zz, if s > 0 then math.pi / 2 else -math.pi / 2), chairColor)
				end
				if setTable then
					setTable(cf * CFrame.new(0, 0.76, 0))
				end
			end
		end
	end
end

local function fitFood(room: Room, z: Zone)
	local rng = room.Rng
	-- the kitchen line behind the counter
	local lineZ = z.BackZ - 0.38
	local lineW = math.min(z.CW + 1.2, room.W - 2 * room.Wall - 0.2)
	box(room, "KitchenLine", Vector3.new(lineW, 0.9, 0.7), CFrame.new(z.CX, 0.45, lineZ), INOX, STEEL, true)
	box(room, "LineTop", Vector3.new(lineW, 0.03, 0.72), CFrame.new(z.CX, 0.915, lineZ), CHROME, METAL)
	local x0 = z.CX - lineW / 2
	for f = 0, 1 do
		local fx = x0 + 0.4 + f * 0.5
		box(room, "Fryer", Vector3.new(0.45, 0.25, 0.55), CFrame.new(fx, 1.05, lineZ), INOX, METAL)
		box(room, "Oil", Vector3.new(0.38, 0.02, 0.45), CFrame.new(fx, 1.18, lineZ), rgb(230, 170, 40), NEON)
		box(room, "Basket", Vector3.new(0.3, 0.12, 0.3), CFrame.new(fx, 1.24, lineZ - 0.05), rgb(150, 150, 150), Enum.Material.Metal).Transparency = 0.3
		rod(room, "BasketHandle", 0.025, 0.3, at(fx, 1.27, lineZ - 0.3, math.pi / 2), DARK)
	end
	local gx = x0 + 1.6
	box(room, "Grill", Vector3.new(0.9, 0.05, 0.6), CFrame.new(gx, 0.96, lineZ), DARK, METAL)
	for i = 0, 3 do
		cyl(room, "Patty", 0.13, 0.025, CFrame.new(gx - 0.3 + i * 0.2, 0.995, lineZ + (i % 2 - 0.5) * 0.2), rgb(96, 52, 30), Enum.Material.Sand)
	end
	-- the hood over the line, and a heat-lamp shelf of wrapped burgers
	box(room, "Hood", Vector3.new(lineW * 0.8, 0.5, 0.85), CFrame.new(z.CX, math.min(room.H - 0.3, 2.35), lineZ), INOX, STEEL)
	local shelfY = 1.5
	box(room, "HeatShelf", Vector3.new(1.4, 0.03, 0.32), CFrame.new(x0 + lineW - 0.8, shelfY, lineZ - 0.15), CHROME, METAL)
	for i = 0, 2 do
		box(room, "HeatLamp", Vector3.new(0.3, 0.03, 0.1), CFrame.new(x0 + lineW - 1.3 + i * 0.5, shelfY + 0.35, lineZ - 0.15), rgb(255, 120, 40), NEON)
		item(room, "burger", CFrame.new(x0 + lineW - 1.3 + i * 0.5, shelfY + 0.015, lineZ - 0.15))
	end
	-- the soda fountain at the counter's end, on the dining side
	local side = if z.CX > room.DoorX then 1 else -1
	local fx = z.CX + side * (z.CW / 2 + 0.75)
	if math.abs(fx) < room.W / 2 - room.Wall - 0.6 then
		box(room, "FountainCab", Vector3.new(1.1, 0.95, 0.6), CFrame.new(fx, 0.475, z.CZ), room.Accent:Lerp(DARK, 0.4), SMOOTH, true)
		box(room, "FountainTop", Vector3.new(1.14, 0.03, 0.64), CFrame.new(fx, 0.965, z.CZ), CHROME, METAL)
		local head = box(room, "Fountain", Vector3.new(0.9, 0.55, 0.4), CFrame.new(fx, 1.33, z.CZ + 0.08), CHROME, METAL)
		local _ = head
		for n = 0, 5 do
			local logo = box(room, "Logo", Vector3.new(0.12, 0.16, 0.01), at(fx - 0.375 + n * 0.15, 1.42, z.CZ - 0.125), GOODS[n + 1], NEON)
			local _l = logo
			box(room, "Nozzle", Vector3.new(0.05, 0.08, 0.05), CFrame.new(fx - 0.375 + n * 0.15, 1.02, z.CZ - 0.05), DARK)
		end
		for n = 0, 1 do
			cyl(room, "CupStack", 0.09, 0.5, CFrame.new(fx - 0.35 + n * 0.12, 1.23, z.CZ - 0.2), WHITE)
		end
	end
	-- now serving
	local servingY = math.min(room.H - 0.35, 3.45)
	local serving = box(room, "NowServing", Vector3.new(1.1, 0.35, 0.05), at(z.CX - z.CW / 2 - 0.2, servingY, z.BackZ - 0.05), DARK)
	room.Serving = sign(serving, Enum.NormalId.Front, "NOW SERVING  #" .. room.ServingNo, rgb(255, 80, 60), DARK, Enum.Font.Code)
	-- a self-order kiosk beside the door
	local kx = room.DoorX + (if room.DoorX > 0 then -1.8 else 1.8)
	local kz = -room.D / 2 + room.Wall + 1.3
	box(room, "KioskPole", Vector3.new(0.18, 1.2, 0.12), at(kx, 0.6, kz), DARK, METAL, true)
	box(room, "KioskFoot", Vector3.new(0.5, 0.04, 0.4), at(kx, 0.02, kz), DARK, METAL)
	local kiosk = box(room, "Kiosk", Vector3.new(0.55, 0.9, 0.05), at(kx, 1.55, kz, math.pi) * CFrame.Angles(math.rad(10), 0, 0), room.Accent:Lerp(DARK, 0.3))
	local list = screen(kiosk, Enum.NormalId.Front, rgb(250, 250, 248), true)
	line(list, "👆", 0.3, room.Accent, Enum.Font.GothamBlack, 1)
	line(list, "TOUCH TO ORDER", 0.12, DARK, Enum.Font.GothamBlack, 2)
	line(list, "🍔 🍟 🥤 🍦", 0.18, DARK, Enum.Font.GothamBlack, 3)
	-- booths along the wall away from the door, tables in the middle
	local wallSide = if room.DoorX > 0 then -1 else 1
	local bx = wallSide * (room.W / 2 - room.Wall - 0.75)
	local booths = math.clamp(math.floor((z.Z1 - z.Z0) / 2.0), 0, 3)
	for b = 0, booths - 1 do
		local bz = z.Z0 + 1.0 + b * 2.0
		for _, s in { -1, 1 } do
			box(room, "BoothSeat", Vector3.new(1.3, 0.45, 0.5), CFrame.new(bx, 0.225, bz + s * 0.7), room.Accent, FABRIC, true)
			box(room, "BoothBack", Vector3.new(1.3, 0.75, 0.16), CFrame.new(bx, 0.82, bz + s * 0.93), room.Accent:Lerp(DARK, 0.2), FABRIC, true)
			box(room, "BoothPiping", Vector3.new(1.32, 0.05, 0.18), CFrame.new(bx, 1.2, bz + s * 0.93), WHITE)
		end
		box(room, "BoothTable", Vector3.new(1.1, 0.04, 0.7), CFrame.new(bx, 0.74, bz), WHITE, MARBLE, true)
		cyl(room, "BoothLeg", 0.08, 0.72, CFrame.new(bx, 0.36, bz), DARK, METAL)
		box(room, "NapkinBox", Vector3.new(0.12, 0.12, 0.08), CFrame.new(bx + wallSide * 0.4, 0.82, bz), CHROME, METAL)
		cyl(room, "Ketchup", 0.05, 0.18, CFrame.new(bx + wallSide * 0.4, 0.85, bz + 0.12), rgb(200, 30, 30))
		cyl(room, "Mustard", 0.05, 0.18, CFrame.new(bx + wallSide * 0.4, 0.85, bz - 0.12), rgb(250, 200, 30))
	end
	local inner = { X0 = z.X0, X1 = z.X1, Z0 = z.Z0, Z1 = z.Z1, BackZ = z.BackZ, CX = z.CX, CZ = z.CZ, CW = z.CW, CD = z.CD, CH = z.CH }
	if wallSide < 0 then
		inner.X0 = bx + 1.0
	else
		inner.X1 = bx - 1.0
	end
	dining(room, inner, false, room.Accent:Lerp(WHITE, 0.2), function(top)
		if rng:NextNumber() < 0.5 then
			box(room, "Tray", Vector3.new(0.45, 0.02, 0.33), top * CFrame.new(0, 0.01, 0), room.Accent, SMOOTH)
			item(room, if rng:NextNumber() < 0.5 then "fries" else "soda", top * CFrame.new(0.08, 0.02, 0))
		end
	end)
	-- condiments and the bin near the door
	local sx = -wallSide * (room.W / 2 - room.Wall - 0.35)
	local sz = -room.D / 2 + room.Wall + 2.4
	if math.abs(sx - room.DoorX) > 1.4 then
		box(room, "Condiments", Vector3.new(0.6, 0.95, 1.2), CFrame.new(sx, 0.475, sz), room.Accent:Lerp(DARK, 0.4), SMOOTH, true)
		box(room, "CondimentTop", Vector3.new(0.62, 0.03, 1.22), CFrame.new(sx, 0.965, sz), CHROME, METAL)
		for i = 0, 1 do
			cyl(room, "Pump", 0.12, 0.25, CFrame.new(sx, 1.1, sz - 0.4 + i * 0.25), if i == 0 then rgb(200, 30, 30) else rgb(250, 200, 30))
		end
		box(room, "Straws", Vector3.new(0.12, 0.2, 0.12), CFrame.new(sx, 1.08, sz + 0.2), rgb(220, 220, 220), GLASS)
		box(room, "Napkins", Vector3.new(0.15, 0.15, 0.2), CFrame.new(sx, 1.05, sz + 0.42), CHROME, METAL)
		bin(room, Vector3.new(sx, 0, sz + 1.0), wallSide * math.pi / 2, "THANK\nYOU", room.Accent:Lerp(DARK, 0.4))
	end
	poster(room, at(wallSide * (room.W / 2 - room.Wall - 0.02), 2.1, z.Z0 + 0.5, wallSide * math.pi / 2), 1.0, 1.3, "🍔", "BIGGER.\nBETTER.\nBAY.", room.Accent, WHITE)
	poster(room, at(-wallSide * (room.W / 2 - room.Wall - 0.02), 2.1, z.Z1 - 0.5, -wallSide * math.pi / 2), 1.0, 1.3, "🍟", "CRISPY\nSINCE\nTODAY", rgb(250, 196, 40), DARK)
end

local function fitGas(room: Room, z: Zone)
	local rng = room.Rng
	-- merch and lottery wall behind the till
	local wz = z.BackZ - 0.05
	local mw = math.min(z.CW, 3.0)
	box(room, "MerchWall", Vector3.new(mw, 1.5, 0.08), CFrame.new(z.CX, 1.65, wz), rgb(40, 40, 46), SMOOTH)
	for r = 0, 3 do
		for c = 0, 9 do
			box(room, "Merch", Vector3.new(mw / 10 - 0.03, 0.22, 0.08), CFrame.new(z.CX - mw / 2 + (c + 0.5) * mw / 10, 1.08 + r * 0.36, wz - 0.08), GOODS[rng:NextInteger(1, #GOODS)])
		end
	end
	local lotto = box(room, "Lotto", Vector3.new(mw, 0.3, 0.04), at(z.CX, 2.6, wz - 0.06), rgb(250, 200, 30), NEON)
	sign(lotto, Enum.NormalId.Front, "★ SUNFUEL REWARDS ★", DARK)
	local monitor = box(room, "Monitor", Vector3.new(0.5, 0.32, 0.06), at(z.CX + z.CW / 2 - 0.3, 2.3, wz - 0.3), DARK)
	sign(monitor, Enum.NormalId.Front, "CAM 1 ● REC", rgb(255, 60, 60), rgb(30, 50, 40), Enum.Font.Code)
	-- a hot dog roller and a candy rack on the counter
	local hx = z.CX - z.CW / 2 + 0.5
	box(room, "Roller", Vector3.new(0.6, 0.12, 0.45), CFrame.new(hx, z.CH + 0.11, z.CZ), INOX, METAL)
	local hood = box(room, "SneezeGuard", Vector3.new(0.62, 0.3, 0.02), at(hx, z.CH + 0.32, z.CZ - 0.24) * CFrame.Angles(math.rad(-20), 0, 0), rgb(220, 240, 255), GLASS)
	hood.Transparency = 0.6
	for i = 0, 5 do
		local dog = rod(room, "HotDog", 0.05, 0.4, at(hx, z.CH + 0.2, z.CZ - 0.18 + i * 0.07), rgb(170, 70, 50))
		spin(room, dog, Vector3.xAxis, 2.5)
	end
	box(room, "CandyRack", Vector3.new(0.6, 0.35, 0.25), CFrame.new(z.CX, z.CH + 0.2, z.CZ - 0.35), rgb(230, 230, 226), METAL)
	for i = 0, 7 do
		box(room, "Candy", Vector3.new(0.06, 0.1, 0.12), CFrame.new(z.CX - 0.26 + i * 0.075, z.CH + 0.33, z.CZ - 0.38), GOODS[rng:NextInteger(1, #GOODS)], Enum.Material.Foil)
	end
	-- gondolas down the middle, the cooler wall along the far side
	local coolerSide = if room.DoorX > 0 then -1 else 1
	local gx0 = if coolerSide < 0 then z.X0 + 1.4 else z.X0 + 0.6
	local gx1 = if coolerSide > 0 then z.X1 - 1.4 else z.X1 - 0.6
	local labels = { "SNACKS", "CANDY", "DRINKS", "AUTO", "TRAVEL" }
	local placed = 0
	local x = gx0 + 0.5
	while x < gx1 - 0.4 and placed < 5 do
		if clearOfDoor(room, x, 0.6) then
			placed += 1
			gondola(room, x, z.Z0 + 0.3, math.min(z.Z1 - 0.2, z.Z0 + 4.5), rng, labels[placed])
			x += 2.3
		else
			x += 0.5
		end
	end
	cooler(room, coolerSide, z.Z0, z.Z1 + 0.6, rng)
	-- slushie and coffee on a cabinet by the counter's end
	local side = -coolerSide
	local fx = z.CX + side * (z.CW / 2 + 0.8)
	if math.abs(fx) < room.W / 2 - room.Wall - 0.6 then
		box(room, "DrinkCab", Vector3.new(1.3, 0.95, 0.6), CFrame.new(fx, 0.475, z.CZ), rgb(60, 60, 66), SMOOTH, true)
		box(room, "DrinkTop", Vector3.new(1.32, 0.03, 0.62), CFrame.new(fx, 0.965, z.CZ), CHROME, METAL)
		for t = 0, 1 do
			local tx = fx - 0.4 + t * 0.32
			local tank = box(room, "SlushTank", Vector3.new(0.28, 0.45, 0.3), CFrame.new(tx, 1.22, z.CZ), rgb(220, 240, 255), GLASS)
			tank.Transparency = 0.4
			box(room, "Slush", Vector3.new(0.25, 0.32, 0.27), CFrame.new(tx, 1.16, z.CZ), if t == 0 then rgb(40, 120, 255) else rgb(240, 40, 70), NEON)
			local paddle = box(room, "Paddle", Vector3.new(0.2, 0.02, 0.04), CFrame.new(tx, 1.2, z.CZ), WHITE)
			spin(room, paddle, Vector3.yAxis, 3)
		end
		box(room, "SlushHead", Vector3.new(0.65, 0.12, 0.34), CFrame.new(fx - 0.24, 1.5, z.CZ), DARK)
		box(room, "Brewer", Vector3.new(0.35, 0.5, 0.35), CFrame.new(fx + 0.4, 1.23, z.CZ + 0.05), DARK)
		local pot = cyl(room, "CoffeePot", 0.16, 0.18, CFrame.new(fx + 0.4, 1.07, z.CZ - 0.05), rgb(80, 50, 30), GLASS)
		pot.Transparency = 0.3
		cyl(room, "Cups", 0.09, 0.4, CFrame.new(fx + 0.15, 1.18, z.CZ - 0.18), WHITE)
	end
	-- ice chest and ATM by the door
	local ix = room.DoorX + (if room.DoorX > 0 then -1.7 else 1.7)
	local iz = -room.D / 2 + room.Wall + 0.6
	local ice = box(room, "IceChest", Vector3.new(1.1, 0.9, 0.6), CFrame.new(ix, 0.45, iz), WHITE, SMOOTH, true)
	sign(ice, Enum.NormalId.Back, "❄ ICE ❄", rgb(40, 120, 220))
	local ax = ix + (if room.DoorX > 0 then -1.0 else 1.0)
	if math.abs(ax) < room.W / 2 - room.Wall - 0.4 then
		box(room, "ATM", Vector3.new(0.6, 1.5, 0.55), CFrame.new(ax, 0.75, iz), rgb(60, 70, 90), METAL, true)
		local atm = box(room, "ATMScreen", Vector3.new(0.34, 0.26, 0.02), at(ax, 1.25, iz + 0.28, math.pi), rgb(30, 90, 160), NEON)
		sign(atm, Enum.NormalId.Front, "ATM\n💳", WHITE)
	end
	poster(room, at(coolerSide * -1 * (room.W / 2 - room.Wall - 0.02), 2.1, z.Z1 - 0.3, -coolerSide * math.pi / 2), 1.0, 1.3, "⚡", "FREE EV\nCHARGING\nOUTSIDE", rgb(40, 160, 90), WHITE)
end

local function fitCafe(room: Room, z: Zone)
	local rng = room.Rng
	-- the back bar: wood counter, espresso machine, grinder, shelves of bags and mugs
	local lineZ = z.BackZ - 0.35
	local lineW = math.min(z.CW + 0.8, room.W - 2 * room.Wall - 0.2)
	box(room, "BackBar", Vector3.new(lineW, 0.9, 0.6), CFrame.new(z.CX, 0.45, lineZ), rgb(110, 74, 46), WOOD, true)
	box(room, "BackBarTop", Vector3.new(lineW, 0.04, 0.62), CFrame.new(z.CX, 0.92, lineZ), rgb(236, 232, 226), MARBLE)
	local ex = z.CX - 0.3
	box(room, "Espresso", Vector3.new(0.75, 0.42, 0.5), CFrame.new(ex, 1.15, lineZ), CHROME, METAL)
	box(room, "EspressoAccent", Vector3.new(0.76, 0.06, 0.51), CFrame.new(ex, 1.3, lineZ), rgb(190, 40, 40), METAL)
	for g = 0, 1 do
		cyl(room, "GroupHead", 0.08, 0.08, CFrame.new(ex - 0.18 + g * 0.36, 0.98, lineZ - 0.25), DARK, METAL)
		rod(room, "Portafilter", 0.03, 0.2, at(ex - 0.18 + g * 0.36, 0.95, lineZ - 0.38, math.pi / 2), DARK)
	end
	for c = 0, 3 do
		item(room, "cafecito", CFrame.new(ex - 0.25 + c * 0.17, 1.365, lineZ), 0.9)
	end
	local steam = box(room, "SteamWand", Vector3.new(0.02, 0.2, 0.02), CFrame.new(ex + 0.42, 1.0, lineZ - 0.2), CHROME, METAL)
	local puff = Instance.new("ParticleEmitter")
	puff.Rate = 3
	puff.Lifetime = NumberRange.new(1, 2)
	puff.Speed = NumberRange.new(0.5, 1.2)
	puff.Size = NumberSequence.new(0.3, 0.9)
	puff.Transparency = NumberSequence.new(0.6, 1)
	puff.Color = ColorSequence.new(WHITE)
	puff.Parent = steam
	cyl(room, "Grinder", 0.2, 0.35, CFrame.new(ex + 0.75, 1.12, lineZ), DARK)
	local hopper = cyl(room, "Hopper", 0.18, 0.25, CFrame.new(ex + 0.75, 1.42, lineZ), rgb(230, 240, 250), GLASS)
	hopper.Transparency = 0.4
	cyl(room, "Beans", 0.16, 0.14, CFrame.new(ex + 0.75, 1.37, lineZ), rgb(70, 40, 20), Enum.Material.Sand)
	for s = 0, 1 do
		local sy = 1.75 + s * 0.45
		box(room, "WallShelf", Vector3.new(lineW * 0.8, 0.04, 0.25), CFrame.new(z.CX, sy, z.BackZ - 0.13), rgb(110, 74, 46), WOOD)
		for i = 0, 5 do
			local bx = z.CX - lineW * 0.35 + i * lineW * 0.14
			if s == 0 then
				box(room, "BeanBag", Vector3.new(0.16, 0.26, 0.1), CFrame.new(bx, sy + 0.15, z.BackZ - 0.13), rgb(190, 150, 100), FABRIC)
			else
				cyl(room, "Mug", 0.09, 0.1, CFrame.new(bx, sy + 0.07, z.BackZ - 0.13), GOODS[rng:NextInteger(1, #GOODS)])
			end
		end
	end
	-- the pastry case on the counter
	local px = z.CX - z.CW / 2 + 0.6
	local case = box(room, "PastryCase", Vector3.new(0.95, 0.5, 0.55), CFrame.new(px, z.CH + 0.27, z.CZ), rgb(220, 240, 250), GLASS)
	case.Transparency = 0.6
	case.Reflectance = 0.1
	for tier = 0, 1 do
		box(room, "CaseShelf", Vector3.new(0.9, 0.015, 0.5), CFrame.new(px, z.CH + 0.05 + tier * 0.22, z.CZ), WHITE, GLASS).Transparency = 0.3
		for k = 0, 2 do
			local ids = { "pastelito", "croqueta", "donut" }
			item(room, ids[(k + tier) % 3 + 1], CFrame.new(px - 0.3 + k * 0.3, z.CH + 0.06 + tier * 0.22, z.CZ), 0.85)
		end
	end
	cyl(room, "TipJar", 0.12, 0.16, CFrame.new(z.CX + 0.2, z.CH + 0.1, z.CZ - 0.25), rgb(220, 240, 250), GLASS).Transparency = 0.4
	-- chalkboard by the door, tables, plants, a ceiling fan
	local bx = room.DoorX + (if room.DoorX > 0 then -1.4 else 1.4)
	local bz = -room.D / 2 + room.Wall + 0.9
	local chalk = box(room, "Chalkboard", Vector3.new(0.6, 0.9, 0.04), at(bx, 0.7, bz, math.pi) * CFrame.Angles(math.rad(12), 0, 0), rgb(30, 44, 36), SMOOTH, true)
	local list = screen(chalk, Enum.NormalId.Front, rgb(30, 44, 36))
	line(list, "TODAY", 0.2, rgb(250, 220, 120), Enum.Font.PermanentMarker, 1)
	line(list, "☕ Cafecito $30", 0.14, WHITE, Enum.Font.PermanentMarker, 2)
	line(list, "🥐 Pastelitos!", 0.14, WHITE, Enum.Font.PermanentMarker, 3)
	line(list, "🍨 Mango gelato", 0.14, WHITE, Enum.Font.PermanentMarker, 4)
	dining(room, z, true, rgb(60, 40, 26), function(top)
		if rng:NextNumber() < 0.6 then
			item(room, if rng:NextNumber() < 0.5 then "latte" else "cafecito", top * CFrame.new(0.12, 0.02, 0))
		end
		cyl(room, "Vase", 0.06, 0.14, top * CFrame.new(-0.15, 0.09, 0), rgb(220, 240, 250), GLASS).Transparency = 0.3
		ball(room, "Bloom", 0.07, (top * CFrame.new(-0.15, 0.2, 0)).Position, rgb(250, 90, 120), FABRIC)
	end)
	plant(room, Vector3.new(room.W / 2 - room.Wall - 0.4, 0, -room.D / 2 + room.Wall + 0.5), true)
	plant(room, Vector3.new(-room.W / 2 + room.Wall + 0.4, 0, -room.D / 2 + room.Wall + 0.5), true)
	local fanY = room.H - 0.45
	cyl(room, "FanRod", 0.04, 0.4, CFrame.new(0, room.H - 0.2, 0), DARK)
	local hub = cyl(room, "FanHub", 0.2, 0.12, CFrame.new(0, fanY, 0), rgb(110, 74, 46), WOOD)
	local _ = hub
	for b = 0, 3 do
		local blade = box(room, "FanBlade", Vector3.new(0.6, 0.015, 0.14), CFrame.new(0, fanY, 0) * CFrame.Angles(0, b * math.pi / 2, 0) * CFrame.new(0.4, 0, 0), rgb(110, 74, 46), WOOD)
		spin(room, blade, Vector3.yAxis, 2.2)
	end
	for i = 0, 1 do
		local side = if i == 0 then -1 else 1
		poster(room, at(side * (room.W / 2 - room.Wall - 0.02), 2.0, z.Z0 + 1 + i * 1.5, side * math.pi / 2), 0.8, 1.0, if i == 0 then "☕" else "🌴", if i == 0 then "CAFÉ\nCUBANO" else "MIAMI\nMORNINGS", rgb(240, 230, 210), rgb(90, 50, 30))
	end
end

local function fitMarket(room: Room, z: Zone)
	local rng = room.Rng
	-- produce crates by the door
	local crates = 0
	local x = z.X0 + 0.6
	while x < z.X1 - 0.6 and crates < 4 do
		if clearOfDoor(room, x, 0.5) then
			crates += 1
			local cz = z.Z0 + 0.5
			local crate = at(x, 0, cz) * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(-20), 0, 0)
			box(room, "CrateStand", Vector3.new(0.8, 0.6, 0.6), at(x, 0.3, cz), rgb(110, 80, 50), WOOD, true)
			box(room, "Crate", Vector3.new(0.8, 0.12, 0.6), crate, rgb(150, 110, 70), WOOD)
			local color = FRUIT[(crates - 1) % #FRUIT + 1]
			for i = 0, 3 do
				for j = 0, 2 do
					ball(room, "Fruit", 0.15, (crate * CFrame.new(-0.3 + i * 0.2, 0.1 + (j % 2) * 0.02, -0.18 + j * 0.18)).Position, color)
				end
			end
			local tag = box(room, "PriceTag", Vector3.new(0.25, 0.14, 0.01), crate * CFrame.new(0, 0.05, -0.31), WHITE)
			sign(tag, Enum.NormalId.Front, string.format("$%d/lb", rng:NextInteger(1, 4)), DARK)
			x += 1.0
		else
			x += 0.4
		end
	end
	-- a gondola and a cooler
	local coolerSide = if room.DoorX > 0 then -1 else 1
	local gx = (z.X0 + z.X1) / 2
	if clearOfDoor(room, gx, 0.6) and z.Z1 - z.Z0 > 3 then
		gondola(room, gx, z.Z0 + 1.6, math.min(z.Z1, z.Z0 + 4.6), rng, "GROCERY")
	end
	cooler(room, coolerSide, z.Z0 + 1.0, z.Z1 + 0.6, rng)
	-- the juice bar behind the counter
	local lineZ = z.BackZ - 0.35
	local lineW = math.min(z.CW + 0.6, room.W - 2 * room.Wall - 0.2)
	box(room, "JuiceBar", Vector3.new(lineW, 0.9, 0.6), CFrame.new(z.CX, 0.45, lineZ), rgb(240, 236, 226), SMOOTH, true)
	box(room, "JuiceTop", Vector3.new(lineW, 0.04, 0.62), CFrame.new(z.CX, 0.92, lineZ), rgb(120, 200, 80), MARBLE)
	for b = 0, 1 do
		local bx = z.CX - 0.4 + b * 0.8
		box(room, "BlenderBase", Vector3.new(0.2, 0.18, 0.2), CFrame.new(bx, 1.03, lineZ), DARK)
		local jug = cyl(room, "Jug", 0.16, 0.3, CFrame.new(bx, 1.27, lineZ), rgb(230, 240, 250), GLASS)
		jug.Transparency = 0.4
		cyl(room, "Juice", 0.14, 0.2, CFrame.new(bx, 1.23, lineZ), if b == 0 then rgb(255, 170, 40) else rgb(240, 80, 120))
	end
	for i = 0, 3 do
		ball(room, "BasketFruit", 0.14, Vector3.new(z.CX + 0.2 + (i % 2) * 0.15, z.CH + 0.1, z.CZ - 0.1 + math.floor(i / 2) * 0.15), FRUIT[i + 1])
	end
	cyl(room, "Basket", 0.45, 0.1, CFrame.new(z.CX + 0.27, z.CH + 0.05, z.CZ - 0.02), rgb(170, 120, 70), WOOD)
	poster(room, at(-coolerSide * (room.W / 2 - room.Wall - 0.02), 2.1, (z.Z0 + z.Z1) / 2, -coolerSide * math.pi / 2), 1.0, 1.2, "🥭", "FRESH\nEVERY\nDAY", rgb(250, 170, 40), WHITE)
end

local function fitEatery(room: Room, z: Zone)
	local rng = room.Rng
	-- the open kitchen: a range with woks and a pot, steam, shelves of bowls, a noren curtain
	local lineZ = z.BackZ - 0.4
	local lineW = math.min(z.CW + 1.0, room.W - 2 * room.Wall - 0.2)
	box(room, "Range", Vector3.new(lineW, 0.9, 0.75), CFrame.new(z.CX, 0.45, lineZ), INOX, STEEL, true)
	box(room, "RangeTop", Vector3.new(lineW, 0.03, 0.77), CFrame.new(z.CX, 0.915, lineZ), DARK, METAL)
	for i = 0, 2 do
		local wx = z.CX - lineW / 2 + 0.5 + i * 0.7
		if i < 2 then
			ell(room, "Wok", Vector3.new(0.45, 0.16, 0.45), CFrame.new(wx, 1.0, lineZ), rgb(50, 50, 54), METAL)
			rod(room, "WokHandle", 0.03, 0.35, at(wx, 1.04, lineZ - 0.3, math.pi / 2), rgb(90, 60, 40))
		else
			cyl(room, "StockPot", 0.38, 0.4, CFrame.new(wx, 1.13, lineZ), CHROME, METAL)
		end
		ball(room, "Flame", 0.12, Vector3.new(wx, 0.94, lineZ), rgb(80, 160, 255), NEON)
		local steamer = box(room, "Steam", Vector3.new(0.05, 0.05, 0.05), CFrame.new(wx, 1.25, lineZ), WHITE)
		steamer.Transparency = 1
		local puff = Instance.new("ParticleEmitter")
		puff.Rate = 4
		puff.Lifetime = NumberRange.new(1.2, 2.2)
		puff.Speed = NumberRange.new(0.6, 1.4)
		puff.Size = NumberSequence.new(0.4, 1.4)
		puff.Transparency = NumberSequence.new(0.65, 1)
		puff.Color = ColorSequence.new(WHITE)
		puff.Parent = steamer
	end
	box(room, "Hood", Vector3.new(lineW * 0.9, 0.45, 0.85), CFrame.new(z.CX, math.min(room.H - 0.3, 2.3), lineZ), INOX, STEEL)
	for s = 0, 1 do
		local sy = 1.55 + s * 0.4
		local sx = z.CX + lineW / 2 - 0.6
		box(room, "BowlShelf", Vector3.new(0.9, 0.03, 0.25), CFrame.new(sx, sy, z.BackZ - 0.13), CHROME, METAL)
		for b = 0, 3 do
			cyl(room, "Bowl", 0.17, 0.08, CFrame.new(sx - 0.3 + b * 0.2, sy + 0.055, z.BackZ - 0.13), WHITE)
		end
	end
	for k = 0, 2 do
		local noren = box(room, "Noren", Vector3.new(0.3, 0.6, 0.01), CFrame.new(z.CX - lineW / 2 + 0.3 + k * 0.32, 2.3, z.BackZ - 0.02), room.Accent, FABRIC)
		if k == 1 then
			sign(noren, Enum.NormalId.Back, "🍜", WHITE)
		end
	end
	dining(room, z, false, rgb(60, 40, 26), function(top)
		local id = ({ "noodles", "sushi", "taco", "cubano" })[rng:NextInteger(1, 4)]
		if rng:NextNumber() < 0.7 then
			item(room, id, top * CFrame.new(0, 0.02, 0.1))
		end
		cyl(room, "SoySauce", 0.05, 0.12, top * CFrame.new(-0.25, 0.06, -0.25), DARK, GLASS)
		box(room, "Chopsticks", Vector3.new(0.22, 0.01, 0.02), top * CFrame.new(0.2, 0.01, -0.22), rgb(180, 130, 80), WOOD)
	end)
	poster(room, at((room.W / 2 - room.Wall - 0.02), 2.1, (z.Z0 + z.Z1) / 2, math.pi / 2), 1.0, 1.3, "🌮🍜🍣", "STREET\nFOOD\nKITCHEN", room.Accent, WHITE)
	plant(room, Vector3.new(-room.W / 2 + room.Wall + 0.4, 0, -room.D / 2 + room.Wall + 0.5), true)
end

local function fitGear(room: Room, z: Zone)
	local rng = room.Rng
	-- slatwall of helmets, gloves and tyres along the wall away from the door
	local side = if room.DoorX > 0 then -1 else 1
	local wx = side * (room.W / 2 - room.Wall - 0.02)
	local len = math.min(z.Z1 - z.Z0 + 1, 5)
	local mid = (z.Z0 + z.Z1) / 2
	local yaw = -side * math.pi / 2
	box(room, "Slatwall", Vector3.new(len, 2.0, 0.04), at(wx, 1.3, mid, yaw), rgb(60, 62, 68), WOOD)
	for r = 0, 6 do
		box(room, "Slat", Vector3.new(len, 0.02, 0.06), at(wx - side * 0.03, 0.4 + r * 0.3, mid, yaw), rgb(40, 42, 46), METAL)
	end
	local slots = math.floor(len / 0.6)
	for i = 0, slots - 1 do
		local zz = mid - len / 2 + (i + 0.5) * len / slots
		local color = GOODS[rng:NextInteger(1, #GOODS)]
		-- helmet on the top row, gloves below, a tyre at the bottom
		local helmet = CFrame.new(wx - side * 0.2, 1.95, zz)
		ell(room, "Helmet", Vector3.new(0.3, 0.28, 0.36), helmet, color, SMOOTH)
		box(room, "Visor", Vector3.new(0.02, 0.12, 0.26), helmet * CFrame.new(-side * 0.14, -0.02, 0), DARK, GLASS)
		box(room, "Glove", Vector3.new(0.06, 0.22, 0.14), CFrame.new(wx - side * 0.08, 1.4, zz), color:Lerp(DARK, 0.4), FABRIC)
		local tyre = rod(room, "Tyre", 0.62, 0.12, CFrame.new(wx - side * 0.1, 0.65, zz), DARK, Enum.Material.Rubber)
		local _ = tyre
		rod(room, "Rim", 0.4, 0.13, CFrame.new(wx - side * 0.1, 0.65, zz), CHROME, METAL)
	end
	-- a glass gadget case in the middle
	local gx = (z.X0 + z.X1) / 2
	if not clearOfDoor(room, gx, 0.8) then
		gx += if room.DoorX > gx then -2 else 2
	end
	local gz = math.max(z.Z1 - 0.5, (z.Z0 + z.Z1) / 2)
	-- the featured e-moto on a turntable in front of it
	local tz = gz - 2.4
	if tz > z.Z0 + 0.6 then
		local table0 = at(gx, 0, tz)
		cyl(room, "Turntable", 2.4, 0.16, table0 * CFrame.new(0, 0.08, 0), rgb(26, 26, 30), MARBLE, true)
		cyl(room, "TurntableRing", 2.46, 0.04, table0 * CFrame.new(0, 0.14, 0), room.Accent, NEON)
		local bike = Bikes.List[room.Rng:NextInteger(1, #Bikes.List)]
		local ok, model = pcall(BikeModel.Build, bike, nil, { Static = true })
		if ok then
			local pivot = world(room, table0 * CFrame.new(0, 0.16, 0))
			PartKit.PlaceStatic(model, pivot)
			model.Parent = room.Model
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					spin(room, d, Vector3.yAxis, 0.35, pivot)
				end
			end
			local plaque = box(room, "Plaque", Vector3.new(0.7, 0.25, 0.03), at(gx, 0.3, tz - 1.25) * CFrame.Angles(math.rad(-20), 0, 0), DARK)
			sign(plaque, Enum.NormalId.Front, bike.Name .. "\nAT FLIGHTY MECHANICS", rgb(250, 220, 90))
		end
	end
	box(room, "CaseBase", Vector3.new(1.6, 0.8, 0.7), CFrame.new(gx, 0.4, gz), rgb(40, 42, 46), SMOOTH, true)
	local glass = box(room, "CaseGlass", Vector3.new(1.6, 0.3, 0.7), CFrame.new(gx, 0.95, gz), rgb(220, 240, 250), GLASS)
	glass.Transparency = 0.7
	box(room, "CaseLight", Vector3.new(1.5, 0.02, 0.02), CFrame.new(gx, 1.08, gz - 0.3), rgb(230, 245, 255), NEON)
	local ids = { "helmetcam", "battery", "shades", "gel" }
	for i, id in ids do
		item(room, id, CFrame.new(gx - 0.6 + (i - 1) * 0.4, 0.81, gz), 1.2)
	end
	-- a mannequin in a hoodie by the door
	local mx = room.DoorX + (if room.DoorX > 0 then -1.6 else 1.6)
	local mz = -room.D / 2 + room.Wall + 1.0
	cyl(room, "MannequinBase", 0.4, 0.05, CFrame.new(mx, 0.025, mz), DARK, METAL)
	cyl(room, "MannequinPole", 0.04, 0.9, CFrame.new(mx, 0.45, mz), CHROME, METAL)
	box(room, "Hoodie", Vector3.new(0.48, 0.62, 0.26), CFrame.new(mx, 1.25, mz), rgb(70, 74, 82), FABRIC, true)
	ell(room, "Hood", Vector3.new(0.3, 0.2, 0.2), CFrame.new(mx, 1.6, mz + 0.08), rgb(70, 74, 82), FABRIC)
	box(room, "Pocket", Vector3.new(0.28, 0.12, 0.01), CFrame.new(mx, 1.05, mz - 0.135), rgb(60, 64, 72), FABRIC)
	ell(room, "MannequinHead", Vector3.new(0.2, 0.26, 0.22), CFrame.new(mx, 1.75, mz), WHITE)
	-- surfboards leaning on the other wall, near the front
	local ox = -side * (room.W / 2 - room.Wall - 0.18)
	for b = 0, 2 do
		local bz = z.Z0 + 0.3 + b * 0.75
		if math.abs(ox - room.DoorX) > 1.4 then
			local board = CFrame.new(ox, 1.05, bz) * CFrame.Angles(0, 0, side * math.rad(-12))
			ell(room, "Surfboard", Vector3.new(0.08, 2.1, 0.55), board, GOODS[room.Rng:NextInteger(1, #GOODS)], SMOOTH)
			box(room, "BoardStripe", Vector3.new(0.085, 1.9, 0.06), board, WHITE)
		end
	end
	-- a workbench with a wheel on a truing stand along the other wall
	local bx = -side * (room.W / 2 - room.Wall - 0.35)
	local bz = z.Z1 - 0.6
	if math.abs(bx - room.DoorX) > 1.4 then
		box(room, "Workbench", Vector3.new(0.6, 0.9, 1.6), CFrame.new(bx, 0.45, bz), rgb(120, 90, 60), WOOD, true)
		box(room, "Pegboard", Vector3.new(0.03, 0.9, 1.6), CFrame.new(bx + side * -0.29 * -1, 1.55, bz), rgb(200, 170, 120), WOOD)
		for t = 0, 4 do
			box(room, "Tool", Vector3.new(0.03, 0.25, 0.04), CFrame.new(bx - side * 0.27, 1.5, bz - 0.6 + t * 0.3) * CFrame.Angles(math.rad(t * 15), 0, 0), GOODS[t + 1], METAL)
		end
		box(room, "TruingStand", Vector3.new(0.1, 0.4, 0.5), CFrame.new(bx, 1.1, bz + 0.3), rgb(40, 120, 220), METAL)
		local wheel = rod(room, "Wheel", 0.6, 0.05, at(bx, 1.35, bz + 0.3, math.pi / 2), DARK, Enum.Material.Rubber)
		spin(room, wheel, Vector3.xAxis, 1.5)
	end
	poster(room, at(-side * (room.W / 2 - room.Wall - 0.02), 2.2, z.Z0 + 0.6, -side * math.pi / 2), 1.1, 1.3, "🏍", "RIDE\nFAST\nSTAY\nFRESH", rgb(30, 30, 34), rgb(120, 255, 60))
end

local function fitBoutique(room: Room, z: Zone)
	local rng = room.Rng
	-- clothing racks
	local racks = 0
	local x = z.X0 + 0.8
	while x < z.X1 - 0.6 and racks < 3 do
		if clearOfDoor(room, x, 0.4) then
			racks += 1
			local rz0, rz1 = z.Z0 + 0.4, math.min(z.Z1 - 0.2, z.Z0 + 2.4)
			local mid = (rz0 + rz1) / 2
			local len = rz1 - rz0
			for _, e in { -1, 1 } do
				cyl(room, "RackPost", 0.04, 1.5, CFrame.new(x, 0.75, mid + e * len / 2), CHROME, METAL)
				cyl(room, "RackFoot", 0.3, 0.03, CFrame.new(x, 0.015, mid + e * len / 2), CHROME, METAL)
			end
			rod(room, "Rail", 0.03, len, at(x, 1.48, mid, math.pi / 2), CHROME, METAL)
			local n = math.min(10, math.floor(len / 0.18))
			for i = 0, n - 1 do
				local hz = mid - len / 2 + (i + 0.5) * len / n
				-- each shirt hangs across the rail on a hanger
				local shirt = GOODS[rng:NextInteger(1, #GOODS)]
				box(room, "Shirt", Vector3.new(0.48, 0.62, 0.04), at(x, 1.12, hz), shirt, FABRIC)
				box(room, "Sleeves", Vector3.new(0.62, 0.16, 0.04), at(x, 1.36, hz), shirt, FABRIC)
				box(room, "Hanger", Vector3.new(0.4, 0.02, 0.02), at(x, 1.45, hz), CHROME, METAL)
			end
			x += 1.6
		else
			x += 0.4
		end
	end
	-- a mirror and mannequins along the far wall
	local side = if room.DoorX > 0 then -1 else 1
	local wx = side * (room.W / 2 - room.Wall - 0.03)
	local mirror = box(room, "Mirror", Vector3.new(0.9, 1.9, 0.02), at(wx, 1.1, z.Z1 - 0.6, side * math.pi / 2), rgb(200, 210, 220), GLASS)
	mirror.Reflectance = 0.6
	box(room, "MirrorFrame", Vector3.new(1.0, 2.0, 0.015), at(wx + side * 0.005, 1.1, z.Z1 - 0.6, side * math.pi / 2), rgb(200, 160, 60), METAL)
	for m = 0, 1 do
		local mx = wx - side * 0.6
		local mz = z.Z0 + 0.6 + m * 1.2
		cyl(room, "Plinth", 0.5, 0.15, CFrame.new(mx, 0.075, mz), WHITE)
		ell(room, "Torso", Vector3.new(0.42, 0.65, 0.26), CFrame.new(mx, 1.2, mz), WHITE)
		box(room, "Dress", Vector3.new(0.46, 0.8, 0.3), CFrame.new(mx, 0.95, mz), GOODS[rng:NextInteger(1, #GOODS)], FABRIC, true)
		ell(room, "Head", Vector3.new(0.2, 0.26, 0.22), CFrame.new(mx, 1.68, mz), WHITE)
		item(room, if m == 0 then "bucket_hat" else "shades", CFrame.new(mx, 1.78, mz), 0.9)
	end
	-- a shades spinner by the counter, jewellery in a case on the counter
	local sx = z.CX + (if z.CX > room.DoorX then -1 else 1) * (z.CW / 2 + 0.6)
	if math.abs(sx) < room.W / 2 - room.Wall - 0.3 then
		cyl(room, "SpinnerPole", 0.05, 1.7, CFrame.new(sx, 0.85, z.CZ), CHROME, METAL, true)
		for t = 0, 2 do
			for k = 0, 3 do
				local a = k * math.pi / 2
				item(room, "shades", CFrame.new(sx + math.cos(a) * 0.12, 0.9 + t * 0.3, z.CZ + math.sin(a) * 0.12) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(-80), 0, 0))
			end
		end
	end
	local jc = box(room, "JewelCase", Vector3.new(0.8, 0.25, 0.45), CFrame.new(z.CX - z.CW / 2 + 0.55, z.CH + 0.14, z.CZ), rgb(220, 240, 250), GLASS)
	jc.Transparency = 0.6
	box(room, "Velvet", Vector3.new(0.76, 0.02, 0.42), CFrame.new(z.CX - z.CW / 2 + 0.55, z.CH + 0.03, z.CZ), rgb(40, 20, 60), FABRIC)
	item(room, "chain", CFrame.new(z.CX - z.CW / 2 + 0.4, z.CH + 0.045, z.CZ), 1)
	item(room, "chain", CFrame.new(z.CX - z.CW / 2 + 0.7, z.CH + 0.045, z.CZ), 1)
	-- shelves of folded clothes on the back wall
	for s = 0, 2 do
		local sy = 1.3 + s * 0.4
		local shx = z.CX + z.CW / 2 + 0.2
		box(room, "ClothesShelf", Vector3.new(1.2, 0.03, 0.35), CFrame.new(shx - 0.8, sy, z.BackZ - 0.18), WHITE)
		for k = 0, 2 do
			for f = 0, 2 do
				box(room, "Folded", Vector3.new(0.3, 0.06, 0.25), CFrame.new(shx - 1.2 + k * 0.38, sy + 0.05 + f * 0.065, z.BackZ - 0.18), GOODS[rng:NextInteger(1, #GOODS)], FABRIC)
			end
		end
	end
	-- a round rug, a chandelier, flowers
	cyl(room, "Rug", math.min(2.6, z.X1 - z.X0), 0.015, CFrame.new((z.X0 + z.X1) / 2, 0.02, (z.Z0 + z.Z1) / 2), room.Accent:Lerp(WHITE, 0.5), FABRIC)
	local cy = room.H - 0.9
	for i = 0, 7 do
		local a = i * math.pi / 4
		ball(room, "Crystal", 0.1, Vector3.new(math.cos(a) * 0.35, cy, (z.Z0 + z.Z1) / 2 + math.sin(a) * 0.35), rgb(255, 240, 210), NEON)
	end
	cyl(room, "ChandelierRing", 0.75, 0.03, CFrame.new(0, cy + 0.05, (z.Z0 + z.Z1) / 2), rgb(200, 160, 60), METAL)
	item(room, "flowers", CFrame.new(z.CX + 0.3, z.CH + 0.05, z.CZ - 0.2), 1.3)
	plant(room, Vector3.new(room.DoorX + (if room.DoorX > 0 then -1.2 else 1.2), 0, -room.D / 2 + room.Wall + 0.5), true)
end

local FITTERS: { [string]: (Room, Zone) -> () } = {
	Food = fitFood,
	Gas = fitGas,
	Cafe = fitCafe,
	Market = fitMarket,
	Eatery = fitEatery,
	Gear = fitGear,
	Boutique = fitBoutique,
}

--------------------------------------------------------------------------------
-- Fitting rooms out and back
--------------------------------------------------------------------------------

local function hidePlaceholder(room: Room)
	local lod = room.Interior:FindFirstChild("Placeholder")
	if not lod then
		return
	end
	for _, d in lod:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			table.insert(room.Hidden, d)
		elseif d:IsA("SurfaceGui") and d.Enabled then
			d.Enabled = false
			table.insert(room.Guis, d)
		end
	end
end

local function unfit(room: Room)
	for _, c in room.Conns do
		c:Disconnect()
	end
	for _, p in room.Hidden do
		p.LocalTransparencyModifier = 0
	end
	for _, g in room.Guis do
		g.Enabled = true
	end
	room.Model:Destroy()
	fitted[room.Interior] = nil
end

local function fit(interior: Model): Room?
	local floor = interior:FindFirstChild("ShopFloor")
	local ceiling = interior:FindFirstChild("Ceiling")
	local counter = interior:FindFirstChild("OrderCounter")
	if not floor or not floor:IsA("BasePart") or not ceiling or not ceiling:IsA("BasePart") then
		return nil -- not streamed in yet
	end
	local base = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	local k = floor.Size.Y / 0.3 -- the scale the city was built at
	local theme = interior:GetAttribute("Theme")
	local name = interior:GetAttribute("ShopName")
	local accent = interior:GetAttribute("Accent")
	local doorFrac = interior:GetAttribute("DoorFrac")
	local seed = interior:GetAttribute("Seed")
	local w = floor.Size.X / S
	local model = Instance.new("Model")
	model.Name = "ShopFit"
	shadows = Graphics.Current().Shadows
	local room: Room = {
		Interior = interior,
		Floor = floor,
		Counter = if counter and counter:IsA("BasePart") then counter else nil,
		Base = base,
		W = w,
		D = floor.Size.Z / S,
		H = (base:PointToObjectSpace(ceiling.CFrame.Position).Y - ceiling.Size.Y / 2) / S,
		Wall = k / S,
		Theme = if type(theme) == "string" and FITTERS[theme] then theme else "Boutique",
		Name = if type(name) == "string" then name else "Shop",
		Accent = if typeof(accent) == "Color3" then accent else rgb(200, 60, 60),
		DoorX = (if type(doorFrac) == "number" then doorFrac else 0) * w,
		Front = interior:GetAttribute("Front") == true,
		Rng = Random.new(if type(seed) == "number" then seed else 1),
		Model = model,
		Staff = nil,
		Spinners = {},
		Clock = nil,
		Serving = nil,
		ServingNo = 0,
		Inside = false,
		Conns = {},
		Hidden = {},
		Guis = {},
	}
	room.ServingNo = room.Rng:NextInteger(10, 80)
	-- the counter in the room's frame
	local cx, cz, cw, cd, ch = 0, room.D / 2 - 6 * k / S, 3, 0.65, 1.0
	local c = room.Counter
	if c then
		local rel = base:ToObjectSpace(c.CFrame)
		cx, cz = rel.Position.X / S, rel.Position.Z / S
		cw, cd, ch = c.Size.X / S, c.Size.Z / S, c.Size.Y / S
	end
	local inner = room.W / 2 - room.Wall - 0.15
	local zone: Zone = {
		X0 = -inner,
		X1 = inner,
		Z0 = -room.D / 2 + room.Wall + 1.4,
		Z1 = cz - cd / 2 - 1.4,
		BackZ = room.D / 2 - room.Wall,
		CX = cx,
		CZ = cz,
		CW = cw,
		CD = cd,
		CH = ch,
	}
	floorFinish(room)
	trims(room)
	dressCounter(room, cx, cz, cw, cd, ch)
	menuBoards(room, cx, cw)
	if zone.Z1 - zone.Z0 > 0.8 then
		FITTERS[room.Theme](room, zone)
	end
	-- a plant and a bin by the door in every room
	local px = room.DoorX + (if room.DoorX > 0 then 1.3 else -1.3)
	if math.abs(px) < inner - 0.2 and room.Theme ~= "Food" then
		plant(room, Vector3.new(px, 0, -room.D / 2 + room.Wall + 0.45), false)
	end
	room.Staff = buildStaff(room, Vector3.new(cx, 0, cz + cd / 2 + 0.45))
	model.Parent = folder
	hidePlaceholder(room)
	if c and not offline then
		table.insert(room.Conns, c:GetAttributeChangedSignal("LastOrder"):Connect(function()
			local value = c:GetAttribute("LastOrder")
			local staff = room.Staff
			if type(value) ~= "string" or not staff then
				return
			end
			local id = string.match(value, "^([%w_]+):")
			staff.State = "Prep"
			staff.T = 0
			staff.ItemId = id
			say(staff, "Coming right up!", 1.5)
			room.ServingNo += 1
			local serving = room.Serving
			if serving then
				serving.Text = "NOW SERVING  #" .. room.ServingNo
			end
		end))
	end
	fitted[interior] = room
	return room
end

--------------------------------------------------------------------------------
-- Choosing rooms, animating them
--------------------------------------------------------------------------------

local function distanceTo(interior: Model, from: Vector3): number?
	local floor = interior:FindFirstChild("ShopFloor")
	if floor and floor:IsA("BasePart") then
		return (floor.CFrame.Position - from).Magnitude
	end
	return nil
end

local function choose()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local g = Graphics.Current()
	local from = camera.CFrame.Position
	local range: number = g.ShopRange
	local want: { { Interior: Model, D: number } } = {}
	for interior in known do
		if interior.Parent == nil then
			known[interior] = nil
		else
			local d = distanceTo(interior, from)
			if d and d < range then
				table.insert(want, { Interior = interior, D = d })
			end
		end
	end
	table.sort(want, function(a, b)
		return a.D < b.D
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(#want, g.ShopRooms) do
		keep[want[i].Interior] = true
	end
	for interior, room in fitted do
		local d = distanceTo(interior, from)
		if interior.Parent == nil or not d or (not keep[interior] and d > range * 1.3) or (not keep[interior] and #want >= g.ShopRooms) then
			unfit(room)
		end
	end
	-- one new room per check, so a fit-out never stalls a frame for long
	for interior in keep do
		if not fitted[interior] then
			fit(interior)
			return
		end
	end
end

local function update(dt: number)
	local now = os.clock()
	local player = Players.LocalPlayer
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local viewer: Vector3? = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else nil
	for _, room in fitted do
		for _, s in room.Spinners do
			local pivot = s.Pivot
			if pivot then
				s.Part.CFrame = pivot * CFrame.fromAxisAngle(s.Axis, now * s.Rate) * s.Base
			else
				s.Part.CFrame = s.Base * CFrame.fromAxisAngle(s.Axis, now * s.Rate)
			end
		end
		local staff = room.Staff
		if staff then
			poseStaff(room, staff, dt, now, viewer)
			-- walking in: a chime, a wave and a greeting
			if viewer then
				local rel = room.Base:PointToObjectSpace(viewer)
				local inside = math.abs(rel.X) < room.W * S / 2 and math.abs(rel.Z) < room.D * S / 2 and rel.Y > -2 and rel.Y < room.H * S
				if inside and not room.Inside then
					local theme = Menus.Themes[room.Theme]
					Sound.Play("Bell", viewer, 1.8, 0.35)
					if staff.State == "Idle" then
						staff.State = "Wave"
						staff.T = 0
					end
					say(staff, if theme then theme.Greeting else "Welcome!", 3)
				end
				room.Inside = inside
			end
		end
	end
end

local clockAt = 0
local function updateClocks()
	local t = Lighting.ClockTime
	local text = string.format("%02d:%02d", math.floor(t) % 24, math.floor((t % 1) * 60))
	for _, room in fitted do
		local clock = room.Clock
		if clock then
			clock.Text = text
		end
	end
end

local function watch(city: Instance)
	for _, d in city:GetDescendants() do
		if d.Name == "Interior" and d:IsA("Model") then
			known[d] = true
		end
	end
	city.DescendantAdded:Connect(function(d)
		if d.Name == "Interior" and d:IsA("Model") then
			known[d] = true
		end
	end)
end

-- For offline previews (tools/lune/preview_shops.luau): fit a room out into `parent` and pose its staff
function ShopFit.Preview(interior: Model, parent: Instance): Model?
	folder = parent :: Folder
	offline = true
	local room = fit(interior)
	if not room then
		return nil
	end
	local staff = room.Staff
	if staff then
		poseStaff(room, staff, 0, 0, nil)
	end
	return room.Model
end

function ShopFit.Init()
	folder = Instance.new("Folder")
	folder.Name = "ShopFit"
	folder.Parent = Workspace
	task.spawn(function()
		local city = Workspace:WaitForChild("City", 600)
		if city then
			watch(city)
		end
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= 0.3 then
			since = 0
			choose()
		end
		update(dt)
		clockAt += dt
		if clockAt >= 1 then
			clockAt = 0
			updateClocks()
		end
	end)
end

return ShopFit
