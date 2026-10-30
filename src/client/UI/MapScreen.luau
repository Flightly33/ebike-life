--[[
	MapScreen: the full map (J, the minimap, or the phone's Map app). The whole of Miami drawn from
	Layout like the minimap (open land, the Everglades, water, beaches, the airport, the blocks by
	district, the streets and the freeways in orange), with the places you can travel to, the
	charging stations, police cars and the other riders on it, and you as an arrow. Scroll to zoom,
	drag to move; click a place (or a row in the list) to travel there through the Teleport remote.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.City.Layout)
local Remotes = require(Shared.Remotes)

local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local MapScreen = {}

local New = Theme.New
local C = Theme.Colors

local BASE = 1000 -- pixels across the whole map at zoom 1
local W = Layout.WORLD_HALF
local SCALE = BASE / (2 * W)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local LEAFY = rgb(60, 72, 58)
local PARK = rgb(54, 104, 58)
local DISTRICTS: { [string]: Color3 } = {
	BayPark = PARK,
	HavanaPark = PARK,
	KeyPark = PARK,
	Jump = rgb(110, 84, 56),
	Suburb = LEAFY,
	Gables = LEAFY,
	Grove = LEAFY,
	Mansion = LEAFY,
	KeyHomes = LEAFY,
	Marina = rgb(58, 72, 88),
	GroveBay = rgb(58, 72, 88),
	Downtown = rgb(70, 70, 82),
	Brickell = rgb(70, 70, 86),
	Edgewater = rgb(72, 74, 86),
	Midtown = rgb(84, 76, 80),
	Wynwood = rgb(96, 72, 84),
	ArtDeco = rgb(96, 82, 90),
	FastFood = rgb(96, 70, 58),
	Freeway = rgb(56, 56, 60),
	Parking = rgb(62, 62, 66),
}

local PLACE_ICONS: { [string]: string } = {
	Dealership = "🏍",
	JumpPark = "🛹",
	Downtown = "🏙",
	Wynwood = "🎨",
	Park = "🌳",
	Beach = "🏖",
	NorthBeach = "🌊",
	LittleHavana = "☕",
	CoralGables = "🏛",
	CoconutGrove = "⛵",
	KeyBiscayne = "🏝",
	Port = "🚢",
	Airport = "✈️",
	Everglades = "🐊",
	Plaza = "⛲",
}

function MapScreen.new(gui: Instance, close: () -> ()): Panel.Panel
	local panel = Panel.new(gui, "Map", "Miami", Vector2.new(1180, 680), "Scroll to zoom · drag to move · click a place to travel")
	local view = New("Frame", { BackgroundColor3 = rgb(26, 70, 104), Size = UDim2.new(1, -250, 1, 0), ClipsDescendants = true, Active = true, Parent = panel.Body })
	Theme.Corner(view, 8)
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 255, 255), rgb(200, 220, 235)), Parent = view })
	local map = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(BASE, BASE), Parent = view })
	local zoomScale = New("UIScale", { Parent = map })

	-- (offsets in whole pixels)
	local function px(v: number): number
		return math.floor(v + 0.5)
	end
	local function toMap(x: number, z: number): (number, number)
		return px((x + W) * SCALE), px((z + W) * SCALE)
	end
	local function rect(x0: number, z0: number, x1: number, z1: number, color: Color3, zIndex: number, corner: number?)
		local mx, mz = toMap(x0, z0)
		local f = New("Frame", { BorderSizePixel = 0, BackgroundColor3 = color, Position = UDim2.fromOffset(mx, mz), Size = UDim2.fromOffset(math.max(1, px((x1 - x0) * SCALE)), math.max(1, px((z1 - z0) * SCALE))), ZIndex = zIndex, Parent = map })
		if corner then
			Theme.Corner(f, corner)
		end
		return f
	end
	for _, ground in Layout.OpenGround do
		rect(ground.MinX, ground.MinZ, ground.MaxX, ground.MaxZ, if ground.Kind == "Marsh" then rgb(66, 78, 46) else rgb(58, 86, 52), 1)
	end
	for _, water in Layout.Water do
		rect(water.MinX, water.MinZ, water.MaxX, water.MaxZ, rgb(38, 104, 150), 1)
	end
	for _, beach in Layout.Beaches do
		rect(beach.MinX, beach.MinZ, beach.MaxX, beach.MaxZ, rgb(214, 196, 146), 2)
	end
	local airport = Layout.Airport
	rect(airport.Apron.MinX, airport.Apron.MinZ, airport.Apron.MaxX, airport.Apron.MaxZ, rgb(84, 84, 90), 2)
	rect(airport.RunwayX0, airport.RunwayZ - airport.RunwayWidth / 2, airport.RunwayX1, airport.RunwayZ + airport.RunwayWidth / 2, rgb(50, 50, 56), 3)
	for _, block in Layout.Blocks do
		rect(block.MinX, block.MinZ, block.MaxX, block.MaxZ, DISTRICTS[block.District] or rgb(64, 64, 70), 2)
	end
	for _, edge in Layout.Edges do
		local a, b = Layout.Nodes[edge.A].Position, Layout.Nodes[edge.B].Position
		local ax, az = toMap(a.X, a.Z)
		local bx, bz = toMap(b.X, b.Z)
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local freeway = edge.Kind == "Freeway" or edge.Kind == "Ramp"
		local main = edge.Kind == "Avenue" or edge.Kind == "Highway" or edge.Kind == "Causeway"
		New("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = if freeway then rgb(240, 160, 56) elseif main then rgb(236, 232, 214) else rgb(196, 196, 200),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(px((ax + bx) / 2), px((az + bz) / 2)),
			Size = UDim2.fromOffset(px(length + edge.Width * SCALE), math.max(if main or freeway then 2 else 1, px(edge.Width * SCALE))),
			Rotation = math.deg(math.atan2(bz - az, bx - ax)),
			ZIndex = if freeway then 5 else 4,
			Parent = map,
		})
	end
	-- charging stations
	for _, p in Layout.Chargers do
		local mx, mz = toMap(p.X, p.Z)
		local dot = New("Frame", { Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(mx, mz), BackgroundColor3 = rgb(60, 200, 90), ZIndex = 7, Parent = map })
		Theme.Round(dot)
		Theme.Label({ Text = "⚡", Size = UDim2.fromScale(1, 1), TextSize = 9, Stroke = 0, ZIndex = 8, Parent = dot })
	end
	-- places: a pin with its icon and name, click to travel
	local function travel(id: string, name: string)
		Remotes.Event("Teleport"):FireServer(id)
		Toasts.Message("Info", "Travelling to " .. name)
		close()
	end
	for _, place in Layout.Teleports do
		local world = (Layout.Places :: any)[place.Id]
		if typeof(world) == "Vector3" then
			local mx, mz = toMap(world.X, world.Z)
			local pin = New("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(mx, mz), BackgroundColor3 = C.Orange, ZIndex = 9, Parent = map })
			Theme.Round(pin)
			Theme.Stroke(pin, rgb(255, 255, 255), 2)
			Theme.Label({ Text = PLACE_ICONS[place.Id] or "📍", Size = UDim2.fromScale(1, 1), TextSize = 17, Stroke = 0, ZIndex = 10, Parent = pin })
			local tag = Theme.Label({ Text = place.Name, Size = UDim2.fromOffset(0, 16), Position = UDim2.new(0.5, 0, 1, 2), AnchorPoint = Vector2.new(0.5, 0), TextSize = 12, Stroke = 2, ZIndex = 10, Parent = pin })
			tag.AutomaticSize = Enum.AutomaticSize.X
			pin.Activated:Connect(function()
				travel(place.Id, place.Name)
			end)
		end
	end
	-- live markers: you, the other riders, police cars
	local me = New("Frame", { Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 20, Parent = map })
	local halo = New("Frame", { Size = UDim2.fromScale(1.6, 1.6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = rgb(80, 180, 255), BackgroundTransparency = 0.6, ZIndex = 19, Parent = me })
	Theme.Round(halo)
	local arrow = Theme.Label({ Text = "▲", Size = UDim2.fromScale(1, 1), TextSize = 22, Color = rgb(255, 255, 255), StrokeColor = rgb(20, 90, 200), Stroke = 2, ZIndex = 21, Parent = me })
	local dots: { Frame } = {}
	local function dot(i: number, color: Color3): Frame
		local d: Frame = dots[i]
		if not d then
			local made: Frame = New("Frame", { Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 18, Parent = map })
			Theme.Round(made)
			Theme.Stroke(made, rgb(255, 255, 255), 1.5)
			dots[i] = made
			d = made
		end
		d.BackgroundColor3 = color
		d.Visible = true
		return d
	end

	-- legend and the travel list
	local side = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(0, 238, 1, 0), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = panel.Body })
	Theme.Corner(side, 8)
	New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), Parent = side })
	Theme.Label({ Text = "Travel", Size = UDim2.new(1, 0, 0, 26), TextSize = 24, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = side })
	local list = New("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -150), Position = UDim2.fromOffset(0, 30), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5, Parent = side })
	Theme.List(list, Enum.FillDirection.Vertical, 5)
	for i, place in Layout.Teleports do
		Theme.Button({ Text = (PLACE_ICONS[place.Id] or "📍") .. "  " .. place.Name, Size = UDim2.new(1, -8, 0, 34), TextSize = 17, Color = rgb(58, 58, 64), LayoutOrder = i, Parent = list, OnClick = function()
			travel(place.Id, place.Name)
		end })
	end
	local legend = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 110), Position = UDim2.new(0, 0, 1, -118), Parent = side })
	Theme.List(legend, Enum.FillDirection.Vertical, 2)
	type Row = { Mark: string, Name: string, Color: Color3 }
	local rows: { Row } = {
		{ Mark = "▲", Name = "You", Color = rgb(80, 180, 255) },
		{ Mark = "●", Name = "Riders", Color = rgb(250, 220, 60) },
		{ Mark = "●", Name = "Police", Color = rgb(240, 60, 60) },
		{ Mark = "⚡", Name = "Chargers", Color = rgb(60, 200, 90) },
		{ Mark = "━", Name = "Freeways", Color = rgb(240, 160, 56) },
	}
	for i, row in rows do
		Theme.Label({ Text = row.Mark .. "  " .. row.Name, Size = UDim2.new(1, 0, 0, 20), TextSize = 16, Color = row.Color, Align = Enum.TextXAlignment.Left, Stroke = 1, LayoutOrder = i, Parent = legend })
	end

	-- zoom and pan
	local zoom, pan = 1, Vector2.new(0, 0)
	local function apply()
		zoomScale.Scale = zoom
		local size = view.AbsoluteSize
		local span = BASE * zoom
		-- keep the map covering the view where it can
		local minX, minY = math.min(0, size.X - span), math.min(0, size.Y - span)
		pan = Vector2.new(math.clamp(pan.X, minX, math.max(0, (size.X - span) / 2)), math.clamp(pan.Y, minY, math.max(0, (size.Y - span) / 2)))
		map.Position = UDim2.fromOffset(px(pan.X), px(pan.Y))
	end
	local function centreOn(world: Vector3)
		local mx, mz = toMap(world.X, world.Z)
		local size = view.AbsoluteSize
		pan = Vector2.new(size.X / 2 - mx * zoom, size.Y / 2 - mz * zoom)
		apply()
	end
	view.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local mouse = Vector2.new(input.Position.X, input.Position.Y) - view.AbsolutePosition
			local before = (mouse - pan) / zoom
			zoom = math.clamp(zoom * (if input.Position.Z > 0 then 1.25 else 0.8), 0.6, 6)
			pan = mouse - before * zoom
			apply()
		end
	end)
	local dragging: Vector2? = nil
	view.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local from = dragging
		if from and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local now = Vector2.new(input.Position.X, input.Position.Y)
			pan += now - from
			dragging = now
			apply()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = nil
		end
	end)
	-- zoom buttons
	type Zoom = { Text: string, Factor: number }
	local zooms: { Zoom } = { { Text = "+", Factor = 1.4 }, { Text = "−", Factor = 1 / 1.4 }, { Text = "◎", Factor = 0 } }
	for i, z in zooms do
		Theme.Button({ Text = z.Text, Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -46, 0, 10 + (i - 1) * 42), TextSize = 22, Color = rgb(40, 40, 46), ZIndex = 30, Parent = view, OnClick = function()
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if z.Factor == 0 then
				if root and root:IsA("BasePart") then
					zoom = math.max(zoom, 2.5)
					centreOn(root.Position)
				end
			else
				local size = view.AbsoluteSize
				local mid = size / 2
				local before = (mid - pan) / zoom
				zoom = math.clamp(zoom * z.Factor, 0.6, 6)
				pan = mid - before * zoom
				apply()
			end
		end })
	end

	panel.Refresh = function()
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		zoom = 2.2
		if root and root:IsA("BasePart") then
			task.defer(centreOn, root.Position)
		else
			task.defer(apply)
		end
	end

	RunService.RenderStepped:Connect(function()
		if not panel.Frame.Visible then
			return
		end
		local player = Players.LocalPlayer
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local mx, mz = toMap(root.Position.X, root.Position.Z)
			me.Position = UDim2.fromOffset(mx, mz)
			local look = (Workspace.CurrentCamera :: Camera).CFrame.LookVector
			arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
			halo.BackgroundTransparency = 0.5 + 0.3 * math.sin(os.clock() * 4)
		end
		for _, d in dots do
			d.Visible = false
		end
		local i = 0
		for _, other in Players:GetPlayers() do
			local oc = other.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
			if other ~= player and oroot and oroot:IsA("BasePart") then
				i += 1
				local mx, mz = toMap(oroot.Position.X, oroot.Position.Z)
				dot(i, rgb(250, 220, 60)).Position = UDim2.fromOffset(mx, mz)
			end
		end
		local vehicles = Workspace:FindFirstChild("Vehicles")
		if vehicles then
			local blink = math.floor(os.clock() * 3) % 2 == 0
			for _, car in vehicles:GetChildren() do
				if car:IsA("Model") and car:GetAttribute("Kind") == "Cop" then
					i += 1
					local p = car:GetPivot().Position
					local mx, mz = toMap(p.X, p.Z)
					dot(i, if blink then rgb(240, 60, 60) else rgb(60, 120, 255)).Position = UDim2.fromOffset(mx, mz)
				end
			end
		end
	end)
	return panel
end

return MapScreen
