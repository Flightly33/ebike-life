--[[
	MainMenu: the "Menus" button. Stats, Settings (units, music and sound volume, key hints, the
	body cam's field of view, graphics Ultra / Performance), Tricks (every trick and control, keyboard and controller), Teleports
	(not while wanted) and a short How to Play.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Layout = require(Shared.City.Layout)
local Remotes = require(Shared.Remotes)

local BikeCamera = require(script.Parent.Parent.BikeCamera)
local Graphics = require(script.Parent.Parent.Graphics)
local Sound = require(script.Parent.Parent.Sound)
local State = require(script.Parent.Parent.State)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)

local MainMenu = {}

local New = Theme.New
local C = Theme.Colors

local HELP = {
	"Spawn a bike from My Rides, walk up to it and press E to get on. Space gets you off.",
	"Riding pays: the faster you go, the more you earn. Tricks multiply it.",
	"Wheelie: hold Shift (or Ctrl). Throttle lifts the front, the brake (S) brings it down. Stay in the green.",
	"C = one hand, V = no hands. Q = bunny hop. In the air, hold Shift to backflip and steer to spin.",
	"R + steer = drift (locks the rear brake; let go to straighten up). F = body cam (first person).",
	"Air tricks (hold the key in the air; you tuck back in on your own before landing): 1. Z Superman, 2. X Can-Can, 3. T Nac-Nac, 4. G Knee Knocker, 5. N No-Footer, 6. Y Barspin (tap). Brake + Shift on the ground = stoppie.",
	"Wheelies and no-hands near cops fill their heat meter. A full meter is a wanted star and a chase.",
	"Lose the cops (get out of sight) to escape and get paid. Stop next to them and you're busted.",
	"Assist modes (M or 1-5): ECO goes far, TURBO goes hard. Customise them in Tuning → Ride Modes.",
	"Batteries drain with the motor's power: an empty pack stops you dead, so charge at ⚡ stations.",
	"Buy new Flightly bikes at Flighty Mechanics; upgrade and paint them in Tuning.",
}

-- Every trick and control: what it is, the keyboard keys, the controller buttons
local CONTROLS: { { Section: string?, Name: string?, Keys: string?, Pad: string?, Note: string? } } = {
	{ Section = "Riding" },
	{ Name = "Gas / brake", Keys = "W / S", Pad = "RT / LT" },
	{ Name = "Steer", Keys = "A / D", Pad = "Left stick" },
	{ Name = "Front brake (stoppie)", Keys = "S + Shift", Pad = "LT + X", Note = "at speed: balance on the front wheel" },
	{ Name = "Assist mode", Keys = "M or 1-5", Pad = "RB" },
	{ Name = "Get off", Keys = "Space", Pad = "A" },
	{ Section = "Ground tricks" },
	{ Name = "Wheelie", Keys = "Shift or Ctrl", Pad = "X", Note = "throttle lifts, brake lowers; stay in the green" },
	{ Name = "One hand", Keys = "C", Pad = "D-pad left" },
	{ Name = "No hands", Keys = "V", Pad = "D-pad right" },
	{ Name = "Bunny hop", Keys = "Q (hold, release)", Pad = "Y (hold, release)" },
	{ Name = "Drift", Keys = "R + steer", Pad = "B + steer", Note = "locks the rear; let go to straighten up" },
	{ Section = "Air tricks (hold in the air)" },
	{ Name = "1. Superman", Keys = "Z", Pad = "D-pad up" },
	{ Name = "2. Can-Can", Keys = "X", Pad = "B" },
	{ Name = "3. Nac-Nac", Keys = "T", Pad = "LB" },
	{ Name = "4. Knee Knocker", Keys = "G", Pad = "D-pad down" },
	{ Name = "5. No-Footer", Keys = "N", Pad = "RB" },
	{ Name = "6. Barspin", Keys = "Y (tap)", Pad = "Y (tap)" },
	{ Name = "Backflip", Keys = "Shift", Pad = "X", Note = "pull back in the air; brake pushes the nose down" },
	{ Name = "Spin", Keys = "A / D", Pad = "Left stick" },
	{ Name = "Quarter pipe", Note = "ride up the face: you go up past the coping, turn round and come back down" },
	{ Name = "Loops and foam pits", Note = "ride into a loop at speed; the foam pit always catches you" },
	{ Section = "Camera" },
	{ Name = "Body cam", Keys = "F", Pad = "R3", Note = "field of view in Settings" },
	{ Name = "Video camera", Keys = "P", Pad = "", Note = "[ ] shots, , . zoom, ; letterbox" },
	{ Name = "Look around", Keys = "Right mouse drag", Pad = "Right stick" },
}

function MainMenu.new(gui: Instance, close: () -> ()): Panel.Panel
	local panel = Panel.new(gui, "Menus", "Menu", Vector2.new(700, 520), nil)
	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = panel.Body })
	Theme.List(tabs, Enum.FillDirection.Horizontal, 6)
	local content = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -42), Position = UDim2.fromOffset(0, 42), Parent = panel.Body })
	local tab = "Stats"
	local draft: { Units: string, Music: number, Sounds: number, Hints: boolean, Fov: number, Graphics: string }? = nil
	local buttons: { [string]: TextButton } = {}
	local render: () -> ()

	local function clear()
		for _, child in content:GetChildren() do
			child:Destroy()
		end
	end

	local function row(parent: Instance, label: string, value: string, order: number)
		local line = New("Frame", { BackgroundColor3 = if order % 2 == 0 then Color3.fromRGB(40, 40, 44) else Color3.fromRGB(36, 36, 40), Size = UDim2.new(1, 0, 0, 32), LayoutOrder = order, Parent = parent })
		Theme.Corner(line, 4)
		Theme.Label({ Text = label, Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.fromOffset(10, 0), TextSize = 17, Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = line })
		Theme.Label({ Text = value, Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.new(0.5, 0, 0, 0), TextSize = 17, Color = C.Cash, Align = Enum.TextXAlignment.Right, Stroke = 1, Parent = line })
	end

	local function stats()
		local data = State.Get()
		if not data then
			return
		end
		local list = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })
		Theme.List(list, Enum.FillDirection.Vertical, 4)
		local s = data.Stats
		local units = State.Settings().Units
		local distance = if units == "mph" then string.format("%.1f mi", s.Distance / 1609.34) else string.format("%.1f km", s.Distance / 1000)
		row(list, "Level", tostring(data.Level), 1)
		row(list, "Cash", Economy.FormatCash(State.Cash()), 2)
		row(list, "Total earned", Economy.FormatCash(s.Earned), 3)
		row(list, "Distance ridden", distance, 4)
		row(list, "Best wheelie", string.format("%.1f s", s.BestWheelie), 5)
		row(list, "Longest air", string.format("%.1f s", s.LongestAir), 6)
		row(list, "Backflips", tostring(math.floor(s.Flips)), 7)
		row(list, "Police escapes", tostring(math.floor(s.Escapes)), 8)
		row(list, "Busted", tostring(math.floor(s.Busts)), 9)
		row(list, "Most stars", string.rep("★", math.floor(s.MaxStars)), 10)
	end

	local function settings()
		local data = State.Get()
		if not data then
			return
		end
		local current = draft or table.clone(data.Settings)
		draft = current
		local list = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })
		Theme.List(list, Enum.FillDirection.Vertical, 8)
		local function save()
			Remotes.Event("SaveSettings"):FireServer(current)
			Sound.SetVolume("SFX", current.Sounds)
		end
		local function setting(label: string, value: string, order: number, onClick: () -> ())
			local line = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = order, Parent = list })
			Theme.Corner(line, 6)
			Theme.Label({ Text = label, Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(12, 0), TextSize = 20, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = line })
			Theme.Button({ Text = value, Size = UDim2.fromOffset(160, 34), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = C.Gray, TextSize = 18, Parent = line, OnClick = onClick })
		end
		setting("Speed units", if current.Units == "mph" then "mph" else "km/h", 1, function()
			current.Units = if current.Units == "mph" then "kmh" else "mph"
			save()
			task.defer(render)
		end)
		setting("Music volume", string.format("%d%%", math.floor(current.Music * 100 + 0.5)), 2, function()
			current.Music = (math.floor(current.Music * 4 + 0.5) + 1) % 5 / 4
			save()
			task.defer(render)
		end)
		setting("Sound volume", string.format("%d%%", math.floor(current.Sounds * 100 + 0.5)), 3, function()
			current.Sounds = (math.floor(current.Sounds * 4 + 0.5) + 1) % 5 / 4
			save()
			task.defer(render)
		end)
		setting("Key hints while riding", if current.Hints then "On" else "Off", 4, function()
			current.Hints = not current.Hints
			save()
			task.defer(render)
		end)
		local mode = if current.Graphics == "Ultra" or current.Graphics == "Performance" then current.Graphics else Graphics.Mode()
		setting("Graphics", if mode == "Ultra" then "✨ Ultra" else "⚡ Performance", 6, function()
			current.Graphics = if mode == "Ultra" then "Performance" else "Ultra"
			data.Settings = table.clone(current)
			save()
			Graphics.Apply()
			task.defer(render)
		end)
		-- body cam field of view: a slider (drag, or tap anywhere on the bar)
		local MIN_FOV, MAX_FOV = 60, 120
		local line = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 5, Parent = list })
		Theme.Corner(line, 6)
		local valueLabel = Theme.Label({ Text = "", Size = UDim2.new(0.45, 0, 1, 0), Position = UDim2.fromOffset(12, 0), TextSize = 20, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = line })
		local bar = New("Frame", { BackgroundColor3 = Color3.fromRGB(30, 30, 34), Size = UDim2.new(0.5, -24, 0, 10), Position = UDim2.new(1, -16, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Active = true, Parent = line })
		Theme.Corner(bar, 5)
		local fill = New("Frame", { BackgroundColor3 = C.Orange, Size = UDim2.fromScale(0, 1), Parent = bar })
		Theme.Corner(fill, 5)
		local knob = New("Frame", { BackgroundColor3 = Color3.fromRGB(245, 245, 245), Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), ZIndex = 3, Parent = bar })
		Theme.Corner(knob, 12)
		local function show(fov: number)
			local f = (fov - MIN_FOV) / (MAX_FOV - MIN_FOV)
			fill.Size = UDim2.fromScale(f, 1)
			knob.Position = UDim2.fromScale(f, 0.5)
			valueLabel.Text = string.format("Body cam FOV  %d°", fov)
		end
		show(current.Fov or 90)
		local dragging: InputObject? = nil
		local function setFrom(x: number)
			local f = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
			current.Fov = math.floor(MIN_FOV + f * (MAX_FOV - MIN_FOV) + 0.5)
			BikeCamera.BodyCamFov = current.Fov
			show(current.Fov)
		end
		bar.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = input
				setFrom(input.Position.X)
			end
		end)
		local moved = UserInputService.InputChanged:Connect(function(input: InputObject)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragging) then
				setFrom(input.Position.X)
			end
		end)
		local ended = UserInputService.InputEnded:Connect(function(input: InputObject)
			if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1) then
				dragging = nil
				save()
			end
		end)
		line.Destroying:Connect(function()
			moved:Disconnect()
			ended:Disconnect()
		end)
	end

	local function tricks()
		local scroll = New("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, Parent = content })
		Theme.List(scroll, Enum.FillDirection.Vertical, 4)
		for i, entry in CONTROLS do
			if entry.Section then
				Theme.Label({ Text = entry.Section, Size = UDim2.new(1, 0, 0, 30), TextSize = 20, Color = C.Orange, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = i, Parent = scroll })
			else
				local line = New("Frame", { BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(40, 40, 44) else Color3.fromRGB(36, 36, 40), Size = UDim2.new(1, -8, 0, if entry.Note then 46 else 30), LayoutOrder = i, Parent = scroll })
				Theme.Corner(line, 4)
				Theme.Label({ Text = entry.Name or "", Size = UDim2.new(0.4, -10, 0, 30), Position = UDim2.fromOffset(10, 0), TextSize = 16, Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = line })
				Theme.Label({ Text = entry.Keys or "", Size = UDim2.new(0.3, -6, 0, 30), Position = UDim2.new(0.4, 0, 0, 0), TextSize = 16, Color = C.Cash, Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = line })
				Theme.Label({ Text = if entry.Pad and entry.Pad ~= "" then "🎮 " .. entry.Pad else "", Size = UDim2.new(0.3, -6, 0, 30), Position = UDim2.new(0.7, 0, 0, 0), TextSize = 15, Color = Color3.fromRGB(150, 200, 255), Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = line })
				if entry.Note then
					Theme.Label({ Text = entry.Note, Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 28), TextSize = 13, Font = Theme.BodyRegular, Color = Color3.fromRGB(190, 190, 196), Align = Enum.TextXAlignment.Left, Stroke = 0, Parent = line })
				end
			end
		end
	end

	local function teleports()
		local grid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })
		New("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 54), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, place in Layout.Teleports do
			Theme.Button({ Text = place.Name, Color = if place.Id == "Dealership" then C.Orange else C.Blue, TextSize = 22, LayoutOrder = i, Parent = grid, OnClick = function()
				Remotes.Event("Teleport"):FireServer(place.Id)
				close()
			end })
		end
	end

	local function help()
		local scroll = New("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, Parent = content })
		Theme.List(scroll, Enum.FillDirection.Vertical, 6)
		Theme.Label({ Text = "How to play " .. Config.GAME_NAME, Size = UDim2.new(1, 0, 0, 30), TextSize = 24, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = 0, Parent = scroll })
		for i, line in HELP do
			local label = Theme.Label({ Text = "• " .. line, Size = UDim2.new(1, -10, 0, 0), TextSize = 16, Font = Theme.BodyRegular, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 0, LayoutOrder = i, Parent = scroll })
			label.AutomaticSize = Enum.AutomaticSize.Y
		end
	end

	render = function()
		for name, button in buttons do
			button.BackgroundColor3 = if name == tab then C.Orange else C.Gray
		end
		clear()
		if tab == "Stats" then
			stats()
		elseif tab == "Settings" then
			settings()
		elseif tab == "Tricks" then
			tricks()
		elseif tab == "Teleport" then
			teleports()
		else
			help()
		end
	end
	for i, name in { "Stats", "Settings", "Tricks", "Teleport", "Help" } do
		buttons[name] = Theme.Button({ Text = name, Size = UDim2.fromOffset(120, 32), Color = C.Gray, TextSize = 18, LayoutOrder = i, Parent = tabs, OnClick = function()
			tab = name
			render()
		end })
	end
	panel.Refresh = function()
		draft = nil
		render()
	end
	State.Changed:Connect(function()
		if panel.Frame.Visible and tab ~= "Settings" then
			render()
		end
	end)
	return panel
end

return MainMenu
