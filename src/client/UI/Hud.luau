--[[
	Hud: the always-on layout from the reference game.

	Bottom-left: the menu stack (Phone, Play, Menus, Crates, Shop, Garage, My Rides) as dark tiles
	with chunky labels, the round minimap beside it, and the cash pill with its green "+" underneath.
	Red badges count what's waiting: rewards to claim on Play, those plus unread messages and
	achievements on the phone. The compact layout (touch-only screens, short windows, or the
	player's choice in Settings) keeps just Phone, Play and My Rides: the rest are phone apps.
	Bottom-centre while riding: the key hints bar, with the keys the player has bound (Shared/
	Controls). Bottom-right while riding: the speedometer. Top right, under the wanted stars: the city
	event running now and how long it has left, or the next one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Controls = require(Shared.Controls)
local Economy = require(Shared.Economy)
local Events = require(Shared.Events)

local BikeController = require(script.Parent.Parent.BikeController)
local Music = require(script.Parent.Parent.Music)
local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Kit)
local Minimap = require(script.Parent.Minimap)
local Speedometer = require(script.Parent.Speedometer)
local Theme = require(script.Parent.Theme)
local Viewport = require(script.Parent.Viewport)

local Hud = {}

local New = Theme.New
local C = Theme.Colors

local cashLabel: TextLabel
local shownCash = 0
local hints: Frame
local speedo: Speedometer.Speedometer
local minimap: Minimap.Minimap
local ridesIcon: Frame
local ridesIconBike = ""
local stack: Frame
local tiles: { [string]: TextButton } = {}
local playBadge: Kit.Badge
local phoneBadge: Kit.Badge
local eventPill: TextButton
local eventText: TextLabel
local eventStroke: UIStroke
local eventSince = 1
local hintsFor = "" -- the bindings the hints were last built with

Hud.Minimap = nil :: Frame?
Hud.FULL_ONLY = { "Menus", "Crates", "Shop", "Garage" } -- tiles the compact layout leaves to the phone
Hud.FULL_HEIGHT = 680 -- design units of screen height the full stack needs (with the objective card above it)

local function tile(parent: Instance, name: string, order: number, size: Vector2, highlight: Color3?, onClick: () -> ()): TextButton
	local button = New("TextButton", {
		Name = name,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.Tile,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(size.X, size.Y),
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.Corner(button, 7)
	Theme.Stroke(button, highlight or C.TileStroke, if highlight then 2 else 1.5)
	Theme.Label({ Text = name, Size = UDim2.new(1, 0, 0, 17), Position = UDim2.new(0, 0, 1, -19), TextSize = 16, Stroke = 2, ZIndex = 6, Parent = button })
	tiles[name] = button
	local scale = New("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		scale.Scale = 1.06
	end)
	button.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	button.Activated:Connect(onClick)
	return button
end

-- The purple stacked-bars "Menus" icon from the reference, drawn with frames
local function menusIcon(parent: Instance)
	for i = 0, 2 do
		local bar = New("Frame", {
			BackgroundColor3 = Color3.fromRGB(190, 80, 255),
			Size = UDim2.new(0.72, 0, 0, 7),
			Position = UDim2.new(0.5, 0, 0, 8 + i * 10),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 4,
			Parent = parent,
		})
		Theme.Round(bar)
		Theme.Stroke(bar, Color3.fromRGB(60, 10, 90), 1.5)
		New("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(240, 160, 255), Color3.fromRGB(140, 40, 220)),
			Rotation = 90,
			Parent = bar,
		})
	end
end

local function keycap(parent: Instance, key: string, order: number)
	local chars = utf8.len(key) or #key
	local cap = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(if chars > 4 then 34 elseif chars > 1 then 26 else 18, 18), LayoutOrder = order, Parent = parent })
	Theme.Corner(cap, 4)
	Theme.Stroke(cap, Color3.fromRGB(240, 240, 240), 1.4)
	Theme.Label({ Text = key, Size = UDim2.fromScale(1, 1), TextSize = if chars > 1 then 9 else 11, Font = Theme.Body, Stroke = 0, Parent = cap })
end

-- How a key is written on a keycap (shorter than the menu's names where there's a glyph)
local CAPS: { [string]: string } = { LeftShift = "⇧", RightShift = "⇧", Space = "␣" }
local function cap(name: string): string
	return CAPS[name] or Controls.Label(name)
end

-- The keycaps for an action: its key, plus one fixed extra if it has one (Shift or Ctrl)
local function capsFor(id: string, most: number?): { string }
	local out = {}
	for i, name in Controls.Keys(State.Settings().Keys, id) do
		if i > (most or 1) then
			break
		end
		local text = cap(name)
		if not table.find(out, text) then
			table.insert(out, text)
		end
	end
	return out
end

-- Every binding in one string: the hints rebuild when it changes
local function bindingsKey(): string
	local parts = {}
	for _, action in Controls.List do
		table.insert(parts, Controls.Key(State.Settings().Keys, action.Id))
	end
	return table.concat(parts, ",")
end

local function hintGroup(parent: Instance, keys: { string }, label: string, order: number): Frame
	local group = New("Frame", { BackgroundColor3 = Color3.fromRGB(44, 44, 48), BackgroundTransparency = 0.15, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), LayoutOrder = order, Parent = parent })
	Theme.Corner(group, 6)
	New("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 7), Parent = group })
	Theme.List(group, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	for i, key in keys do
		keycap(group, key, i)
	end
	local text = Theme.Label({ Text = label, Size = UDim2.fromOffset(0, 26), TextSize = 13, Font = Theme.Body, Stroke = 0, LayoutOrder = 10, Parent = group })
	text.AutomaticSize = Enum.AutomaticSize.X
	return group
end

-- The air tricks, in order, with their keyboard keys and controller buttons (the row above the key
-- hints; the one being done lights up)
local TRICK_KEYS = {
	{ Pad = "↑", Label = "Superman", Name = "Superman" },
	{ Pad = "B", Label = "Can-Can", Name = "CanCan" },
	{ Pad = "LB", Label = "Nac-Nac", Name = "NacNac" },
	{ Pad = "↓", Label = "Knee Knocker", Name = "KneeKnocker" },
	{ Pad = "RB", Label = "No-Footer", Name = "NoFooter" },
	{ Pad = "Y", Label = "Barspin", Name = "Barspin" },
}
local trickRow: Frame
local trickGroups: { [string]: Frame } = {}
local riding = false

local function usingPad(): boolean
	local last = UserInputService:GetLastInputType()
	return last.Name:sub(1, 7) == "Gamepad"
end

-- (Re)builds the trick row for the keyboard or a controller, scaled down to fit its slot
local function buildTrickRow(pad: boolean)
	for _, child in trickRow:GetChildren() do
		child:Destroy()
	end
	table.clear(trickGroups)
	local layout = Theme.List(trickRow, Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local fit = New("UIScale", { Parent = trickRow })
	local title = Theme.Label({ Text = "AIR TRICKS", Size = UDim2.fromOffset(0, 26), TextSize = 13, Color = C.Orange, LayoutOrder = 0, Parent = trickRow })
	title.AutomaticSize = Enum.AutomaticSize.X
	for i, trick in TRICK_KEYS do
		trickGroups[trick.Name] = hintGroup(trickRow, if pad then { trick.Pad } else capsFor(trick.Name), string.format("%d. %s", i, trick.Label), i)
	end
	hintGroup(trickRow, if pad then { "B" } else capsFor("Drift"), "Drift", 7)
	hintGroup(trickRow, if pad then { "RS" } else capsFor("Camera"), "Camera", 8)
	-- the row never runs into the minimap or the speedometer: shrink it to its slot
	-- (changing the scale changes the content size, which fires this again: run it deferred, once
	-- at a time, and only for a real change, or it re-enters itself until Roblox errors)
	local pending = false
	local function refit()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if not fit.Parent then
				return
			end
			local content = layout.AbsoluteContentSize.X / math.max(fit.Scale, 0.01)
			local room = trickRow.AbsoluteSize.X
			if content > 0 and room > 0 then
				local scale = math.min(1, room / content)
				if math.abs(scale - fit.Scale) > 0.01 then
					fit.Scale = scale
				end
			end
		end)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refit)
	trickRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
end

-- The keyboard hints along the bottom, with the keys the player has bound
local function buildHints()
	for _, child in hints:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	hintGroup(hints, capsFor("Gas"), "Gas", 1)
	hintGroup(hints, capsFor("Brake"), "Brake", 2)
	local steer = capsFor("Left")
	table.insert(steer, capsFor("Right")[1])
	hintGroup(hints, steer, "Steer", 3)
	hintGroup(hints, capsFor("Wheelie", 3), "Wheelie", 4)
	hintGroup(hints, capsFor("OneHand"), "One Hand", 5)
	hintGroup(hints, capsFor("NoHands"), "No Hands", 6)
	hintGroup(hints, capsFor("Hop"), "Hop", 7)
	hintGroup(hints, capsFor("Mode"), "Mode", 8)
	hintGroup(hints, { cap("Space") }, "Get Off", 9)
end

-- The compact layout: asked for, or "Auto" on a screen too short for the full stack (phones, small
-- windows; a tablet has the room). Before the screen can be measured, touch-only screens get it.
function Hud.Compact(): boolean
	local settings = State.Settings()
	if settings.HudLayout == "Compact" then
		return true
	elseif settings.HudLayout == "Full" then
		return false
	end
	local gui = stack and stack.Parent
	if gui and gui:IsA("ScreenGui") then
		local scale = gui:FindFirstChildOfClass("UIScale")
		local height = gui.AbsoluteSize.Y / (if scale then math.max(scale.Scale, 0.01) else 1)
		if height > 0 then
			return height < Hud.FULL_HEIGHT
		end
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Hud.ApplyLayout()
	if not stack then
		return
	end
	local compact = Hud.Compact()
	for _, name in Hud.FULL_ONLY do
		local tile = tiles[name]
		if tile then
			tile.Visible = not compact
		end
	end
	local height, count = 0, 0
	for _, tile in tiles do
		if tile.Visible then
			height += tile.Size.Y.Offset
			count += 1
		end
	end
	stack.Size = UDim2.fromOffset(76, height + 5 * math.max(count - 1, 0))
	-- on a phone the speedometer moves in from the corner (the riding buttons take it): centred
	-- between the minimap and the buttons' toggles (520 design units in from the right)
	if speedo then
		if compact and UserInputService.TouchEnabled then
			local gui = stack.Parent :: ScreenGui
			local scale = gui:FindFirstChildOfClass("UIScale")
			local width = gui.AbsoluteSize.X / (if scale then math.max(scale.Scale, 0.01) else 1)
			local left, right = 94 + 150 + 12, width - 520
			speedo.Frame.AnchorPoint = Vector2.new(0, 1)
			speedo.Frame.Position = UDim2.new(0, math.floor(math.max(left, (left + right) / 2 - 98)), 1, -14)
		else
			speedo.Frame.AnchorPoint = Vector2.new(1, 1)
			speedo.Frame.Position = UDim2.new(1, -14, 1, -14)
		end
	end
	-- the key hints follow the bindings
	local bindings = bindingsKey()
	if bindings ~= hintsFor and hints then
		hintsFor = bindings
		buildHints()
		buildTrickRow(usingPad())
	end
end

-- The red counts: rewards waiting on Play, and everything waiting on the phone
function Hud.SetBadges(play: number, phone: number)
	if playBadge then
		playBadge.Set(play)
		phoneBadge.Set(phone)
	end
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The event pill: what's on and for how long, or what's next
local function updateEvent()
	local t = Workspace:GetServerTimeNow()
	local event, ends, nextEvent, starts = Events.At(t)
	if event then
		eventText.Text = string.format("%s %s  ·  %s", event.Icon, event.Name, clock(ends - t))
		eventText.TextColor3 = C.Gold
		eventStroke.Transparency = 0.15
		eventPill.BackgroundTransparency = 0.05
	else
		eventText.Text = string.format("Next: %s %s in %s", nextEvent.Icon, nextEvent.Name, clock(starts - t))
		eventText.TextColor3 = Theme.Roles.Muted
		eventStroke.Transparency = 0.8
		eventPill.BackgroundTransparency = 0.35
	end
end

function Hud.Init(gui: ScreenGui, open: (string) -> ())
	-- Cash pill (bottom-left)
	local pill = New("Frame", { Name = "Cash", BackgroundColor3 = Color3.fromRGB(28, 28, 31), BackgroundTransparency = 0.05, Size = UDim2.fromOffset(170, 38), Position = UDim2.new(0, 10, 1, -10), AnchorPoint = Vector2.new(0, 1), Parent = gui })
	Theme.Corner(pill, 7)
	Theme.Stroke(pill, C.TileStroke, 1.5)
	Theme.Button({ Text = "+", Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(6, 6), Color = Color3.fromRGB(96, 214, 56), TextSize = 22, Parent = pill, OnClick = function()
		open("Shop")
	end })
	cashLabel = Theme.Label({ Text = "$0", Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(36, 0), TextSize = 30, Color = C.Cash, StrokeColor = C.CashDark, Stroke = 2.5, Align = Enum.TextXAlignment.Right, Parent = pill })
	New("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = cashLabel })

	-- Menu stack
	stack = New("Frame", { Name = "Menu", BackgroundTransparency = 1, Size = UDim2.fromOffset(76, 444), Position = UDim2.new(0, 10, 1, -54), AnchorPoint = Vector2.new(0, 1), Parent = gui })
	Theme.List(stack, Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom)
	-- the phone (` backquote): every menu, the map and the stats as apps
	local phone = tile(stack, "Phone", 0, Vector2.new(60, 58), Color3.fromRGB(80, 160, 255), function()
		open("Phone")
	end)
	Theme.Label({ Text = "📱", Size = UDim2.new(1, 0, 1, -16), TextSize = 30, Stroke = 0, Parent = phone })
	phoneBadge = Kit.Badge(phone)
	-- missions, jobs, races, dailies and events (K)
	local play = tile(stack, "Play", 1, Vector2.new(60, 58), Theme.Roles.Mission, function()
		open("Activities")
	end)
	Theme.Label({ Text = "🎯", Size = UDim2.new(1, 0, 1, -16), TextSize = 30, Stroke = 0, Parent = play })
	playBadge = Kit.Badge(play)
	local menus = tile(stack, "Menus", 2, Vector2.new(60, 58), nil, function()
		open("Menus")
	end)
	menusIcon(menus)
	local crates = tile(stack, "Crates", 3, Vector2.new(60, 58), nil, function()
		open("Crates")
	end)
	Viewport.Icon(crates, "Crates", UDim2.new(1, 0, 1, -16))
	local shop = tile(stack, "Shop", 4, Vector2.new(60, 58), Color3.fromRGB(70, 210, 80), function()
		open("Shop")
	end)
	Viewport.Icon(shop, "Shop", UDim2.new(1, 0, 1, -16))
	local tuning = tile(stack, "Garage", 5, Vector2.new(60, 58), nil, function()
		open("Tuning")
	end)
	Viewport.Icon(tuning, "Tuning", UDim2.new(1, 0, 1, -16))
	local rides = tile(stack, "My Rides", 6, Vector2.new(74, 66), nil, function()
		open("MyRides")
	end)
	ridesIcon = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -16), Parent = rides })

	-- Minimap beside the stack
	minimap = Minimap.new(gui, UDim2.new(0, 94, 1, -58))
	Hud.Minimap = minimap.Frame
	-- click the minimap for the full map
	local mapButton = New("TextButton", { Name = "OpenMap", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = minimap.Frame })
	mapButton.Activated:Connect(function()
		open("Map")
	end)

	-- Speedometer (riding only)
	speedo = Speedometer.new(gui)
	speedo.Frame.Visible = false
	speedo.OnMode = function(name: string)
		BikeController.SetMode(name)
	end
	speedo.OnMusic = function()
		Music.Toggle()
	end
	Music.Toggled:Connect(function(on: boolean)
		speedo:SetMusic(on)
	end)

	-- Key hints (riding only, keyboard)
	hints = New("Frame", { Name = "Hints", BackgroundTransparency = 1, Size = UDim2.new(1, -520, 0, 28), Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1), Visible = false, Parent = gui })
	Theme.List(hints, Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	hintsFor = bindingsKey()
	buildHints()

	-- The city event (top right, under the wanted stars and the level): tap for the timetable
	eventPill = New("TextButton", { Name = "Event", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Roles.Surface, BackgroundTransparency = 0.1, Size = UDim2.fromOffset(250, 30), Position = UDim2.new(1, -12, 0, 132), AnchorPoint = Vector2.new(1, 0), Parent = gui })
	Theme.Round(eventPill)
	eventStroke = Theme.Stroke(eventPill, C.Gold, 1.5, 0.2)
	eventText = Theme.Label({ Text = "", Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextSize = 15, Align = Enum.TextXAlignment.Right, Stroke = 1.5, Parent = eventPill })
	eventPill.Activated:Connect(function()
		open("Events")
	end)
	updateEvent()

	-- Air tricks, numbered in order, above the hints
	trickRow = New("Frame", { Name = "Tricks", BackgroundTransparency = 1, Size = UDim2.new(1, -520, 0, 28), Position = UDim2.new(0.5, 0, 1, -44), AnchorPoint = Vector2.new(0.5, 1), Visible = false, Parent = gui })
	local pad = usingPad()
	buildTrickRow(pad)
	Hud.ApplyLayout()
	-- keyboard <-> controller: swap the trick row's glyphs, and the keyboard-only hints come and go
	UserInputService.LastInputTypeChanged:Connect(function()
		local now = usingPad()
		if now ~= pad then
			pad = now
			buildTrickRow(pad)
			Hud.SetRiding(riding)
		end
	end)

	State.Changed:Connect(function()
		local data = State.Get()
		if data and data.Equipped ~= ridesIconBike then
			ridesIconBike = data.Equipped
			for _, child in ridesIcon:GetChildren() do
				child:Destroy()
			end
			Viewport.Icon(ridesIcon, data.Equipped, UDim2.fromScale(1, 1))
		end
	end)
end

function Hud.SetRiding(isRiding: boolean)
	riding = isRiding
	speedo.Frame.Visible = riding
	local show = riding and State.Settings().Hints and not UserInputService.TouchEnabled
	hints.Visible = show and not usingPad() -- the bottom row is keyboard keys
	trickRow.Visible = show
end

function Hud.Update(dt: number)
	-- cash counts up to the new value
	local cash = Players.LocalPlayer:GetAttribute("Cash")
	local target = if type(cash) == "number" then cash else 0
	if shownCash ~= target then
		local diff = target - shownCash
		local step = math.max(1, math.abs(diff) * math.min(1, dt * 8))
		shownCash = if math.abs(diff) <= step then target else shownCash + math.sign(diff) * step
		cashLabel.Text = Economy.FormatCash(math.floor(shownCash + 0.5))
	end
	minimap:Update()
	eventSince += dt
	if eventSince >= 0.5 then
		eventSince = 0
		updateEvent()
	end
	-- light up the trick being done
	if trickRow.Visible then
		local physics = BikeController.Physics
		local active = ""
		if physics and not physics.Grounded then
			active = if physics.BarSpin > 0 then "Barspin" elseif physics.TrickExt > 0.05 then physics.TrickName else ""
		end
		for name, group in trickGroups do
			group.BackgroundColor3 = if name == active then C.Orange else Color3.fromRGB(44, 44, 48)
		end
	end
	if speedo.Frame.Visible then
		local spec = BikeController.Spec
		local physics = BikeController.Physics
		local power = if spec and physics and spec.MotorW > 0 then physics.MotorPower / spec.MotorW else 0
		local charging = BikeController.Charging()
		speedo:Update(BikeController.Kmh(), State.Settings().Units, BikeController.ModeName, BikeController.BatteryFraction(), BikeController.RangeKm(), power, charging)
	end
end

return Hud
