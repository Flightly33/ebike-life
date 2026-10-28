--[[
	AdminPanel: buttons for the admin commands (AdminService checks every call on the server). Opens
	from the ADMIN button or F2, and only exists for players the server marked "Admin".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Admin)
local Bikes = require(Shared.Bikes)
local Remotes = require(Shared.Remotes)

local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)

local AdminPanel = {}

local New = Theme.New
local C = Theme.Colors

function AdminPanel.new(gui: Instance, open: () -> ()): Panel.Panel
	local player = Players.LocalPlayer
	local panel = Panel.new(gui, "Admin", "ADMIN", Vector2.new(620, 470))
	local status = Theme.Label({ Text = "Commands run on the server.", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22), TextSize = 18, Parent = panel.Body })

	local scroll = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -28),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel.Body,
	})
	Theme.List(scroll, Enum.FillDirection.Vertical, 8)

	local function run(command: string, value: any)
		local ok, result, message = pcall(function()
			return Remotes.Function("Admin"):InvokeServer(command, value)
		end)
		if not ok then
			status.Text = "Failed: " .. tostring(result)
			status.TextColor3 = C.Red
			return
		end
		status.Text = tostring(message or (if result then "Done" else "Failed"))
		status.TextColor3 = if result then C.Cash else C.Red
	end

	local order = 0
	local function row(title: string): Frame
		order += 1
		local frame = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 64), LayoutOrder = order, Parent = scroll })
		Theme.Label({ Text = title, Size = UDim2.new(1, 0, 0, 22), TextSize = 20, Align = Enum.TextXAlignment.Left, Parent = frame })
		local buttons = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 26), Parent = frame })
		Theme.List(buttons, Enum.FillDirection.Horizontal, 6)
		return buttons
	end
	local function button(parent: Instance, text: string, color: Color3, onClick: () -> (), width: number?)
		Theme.Button({ Text = text, Size = UDim2.fromOffset(width or 92, 34), Color = color, TextSize = 18, Corner = 4, Parent = parent, OnClick = onClick })
	end
	local function input(parent: Instance, placeholder: string, width: number): TextBox
		local box = New("TextBox", {
			Size = UDim2.fromOffset(width, 34),
			BackgroundColor3 = Color3.fromRGB(40, 40, 44),
			TextColor3 = C.Text,
			PlaceholderText = placeholder,
			Text = "",
			TextSize = 18,
			FontFace = Theme.Font,
			ClearTextOnFocus = false,
			Parent = parent,
		})
		Theme.Corner(box, 4)
		return box
	end

	local cash = row("Cash")
	for _, amount in { 1000, 10000, 100000, 1000000 } do
		button(cash, "+$" .. (if amount >= 1000000 then "1M" elseif amount >= 1000 then (amount // 1000) .. "K" else tostring(amount)), C.Green, function()
			run("cash", amount)
		end)
	end
	local cashBox = input(cash, "amount", 110)
	button(cash, "Set +/-", C.Gray, function()
		run("cash", tonumber(cashBox.Text))
	end, 80)

	local level = row("Level")
	local levelBox = input(level, "level", 110)
	button(level, "Set level", C.Blue, function()
		run("level", tonumber(levelBox.Text))
	end, 110)
	button(level, "Own all bikes", C.Purple, function()
		run("allbikes")
	end, 150)
	button(level, "Max upgrades", C.Orange, function()
		run("maxupgrades")
	end, 150)

	local wanted = row("Wanted level")
	for stars = 0, 5 do
		button(wanted, if stars == 0 then "Clear" else string.rep("★", stars), if stars == 0 then C.Green else C.Red, function()
			run("wanted", stars)
		end, if stars == 0 then 80 else 30 + stars * 14)
	end

	local time = row("Time of day")
	local presets: { { Name: string, Hour: number } } = {
		{ Name = "Dawn", Hour = 6 },
		{ Name = "Noon", Hour = 12.5 },
		{ Name = "Sunset", Hour = 18 },
		{ Name = "Night", Hour = 22 },
		{ Name = "Midnight", Hour = 0 },
	}
	for _, preset in presets do
		button(time, preset.Name, C.Gray, function()
			run("time", preset.Hour)
		end, 100)
	end

	local weather = row("Weather")
	for _, kind in { "Auto", "Clear", "Cloudy", "Overcast" } do
		button(weather, kind, if kind == "Auto" then C.Green else C.Gray, function()
			run("weather", kind)
		end, 100)
	end

	order += 1
	Theme.Label({ Text = "Teleport", Size = UDim2.new(1, -10, 0, 22), TextSize = 20, Align = Enum.TextXAlignment.Left, LayoutOrder = order, Parent = scroll })
	order += 1
	local places = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = scroll })
	New("UIGridLayout", { CellSize = UDim2.fromOffset(140, 34), CellPadding = UDim2.fromOffset(6, 6), Parent = places })
	for _, place in Admin.Places do
		button(places, place, C.Blue, function()
			run("teleport", place)
		end)
	end

	order += 1
	Theme.Label({ Text = "Spawn any bike", Size = UDim2.new(1, -10, 0, 22), TextSize = 20, Align = Enum.TextXAlignment.Left, LayoutOrder = order, Parent = scroll })
	order += 1
	local bikes = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = scroll })
	New("UIGridLayout", { CellSize = UDim2.fromOffset(140, 34), CellPadding = UDim2.fromOffset(6, 6), Parent = bikes })
	for _, bike in Bikes.List do
		button(bikes, bike.Name, Bikes.RarityColors[bike.Rarity], function()
			run("bike", bike.Id)
		end)
	end

	-- The ADMIN button, for admins only
	local launcher = Theme.Button({ Name = "AdminButton", Text = "ADMIN", Size = UDim2.fromOffset(84, 30), Position = UDim2.new(1, -12, 0, 60), AnchorPoint = Vector2.new(1, 0), Color = C.Red, TextSize = 18, Corner = 4, Parent = gui, OnClick = open })
	local function refresh()
		launcher.Visible = player:GetAttribute("Admin") == true
	end
	player:GetAttributeChangedSignal("Admin"):Connect(refresh)
	refresh()
	return panel
end

return AdminPanel
