--[[
	MainMenu: the "Menus" button. Stats, Settings (units, music and sound volume, key hints),
	Teleports (not while wanted) and a short How to Play.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Layout = require(Shared.City.Layout)
local Remotes = require(Shared.Remotes)

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
	"R + steer = drift (locks the rear brake; let go to straighten up). F = first person.",
	"Wheelies and no-hands near cops fill their heat meter. A full meter is a wanted star and a chase.",
	"Lose the cops (get out of sight) to escape and get paid. Stop next to them and you're busted.",
	"Assist modes (M or 1-5): ECO goes far, TURBO goes hard. Customise them in Tuning → Ride Modes.",
	"Batteries drain with the motor's power. Charge at ⚡ stations. Pedal bikes still move on an empty pack.",
	"Buy new Flightly bikes at Flighty Mechanics; upgrade and paint them in Tuning.",
}

function MainMenu.new(gui: Instance, close: () -> ()): Panel.Panel
	local panel = Panel.new(gui, "Menus", "Menu", Vector2.new(700, 520), nil)
	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = panel.Body })
	Theme.List(tabs, Enum.FillDirection.Horizontal, 6)
	local content = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -42), Position = UDim2.fromOffset(0, 42), Parent = panel.Body })
	local tab = "Stats"
	local draft: { Units: string, Music: number, Sounds: number, Hints: boolean }? = nil
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
		elseif tab == "Teleport" then
			teleports()
		else
			help()
		end
	end
	for i, name in { "Stats", "Settings", "Teleport", "Help" } do
		buttons[name] = Theme.Button({ Text = name, Size = UDim2.fromOffset(130, 32), Color = C.Gray, TextSize = 18, LayoutOrder = i, Parent = tabs, OnClick = function()
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
