--[[
	Tuning: work on any bike you own.

	Performance: battery packs, motor controller stages, tyres, suspension, brakes and the speed
	limiter (street legal or off-road mode). Each stage is bought once; any stage you own can be
	switched back to for free (e.g. go street legal again when the cops are about).
	Paint: frame, accent and rim colours and underglow, from the free colours and the ones won in
	crates.
	Ride Modes: set each assist mode the way e-bike apps allow: support factor, motor power cap and
	how punchy the motor's response is.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bikes = require(Shared.Bikes)
local BikeStats = require(Shared.BikeStats)
local Economy = require(Shared.Economy)
local Modes = require(Shared.Modes)
local Paints = require(Shared.Paints)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local Upgrades = require(Shared.Upgrades)

local State = require(script.Parent.Parent.State)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Viewport = require(script.Parent.Viewport)

local Tuning = {}

local New = Theme.New
local C = Theme.Colors

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function scroller(parent: Instance): ScrollingFrame
	local scroll = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = parent,
	})
	Theme.List(scroll, Enum.FillDirection.Vertical, 6)
	New("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = scroll })
	return scroll
end

function Tuning.new(gui: Instance): Panel.Panel
	-- (parts and paint moved to Flighty Garage, UI/Garage: this is the ride modes panel now)
	local panel = Panel.new(gui, "RideModes", "Ride Modes", Vector2.new(1080, 600), "Parts, paint and setup: Flighty Garage, next to the dealership")
	local body = panel.Body
	local bikeId = ""
	local tab = "Ride Modes"

	-- Left: bike picker, preview, numbers
	local left = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(0, 300, 1, 0), Parent = body })
	Theme.Corner(left, 6)
	local picker = New("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -12, 0, 34), Position = UDim2.fromOffset(6, 6), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.X, Parent = left })
	Theme.List(picker, Enum.FillDirection.Horizontal, 4)
	local preview = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), Position = UDim2.fromOffset(0, 44), Parent = left })
	local bikeName = Theme.Label({ Text = "", Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 214), TextSize = 22, Stroke = 2, Parent = left })
	local stats = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 200), Position = UDim2.fromOffset(8, 246), Parent = left })
	New("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 40), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = stats })

	-- Right: tabs and content
	local right = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -312, 1, 0), Position = UDim2.fromOffset(312, 0), Parent = body })
	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = right })
	Theme.List(tabs, Enum.FillDirection.Horizontal, 6)
	local content = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -42), Position = UDim2.fromOffset(0, 42), Parent = right })
	local tabButtons: { [string]: TextButton } = {}

	local render: () -> ()

	local function owned(): { Bikes.Bike }
		local data = State.Get()
		local list = {}
		for _, bike in Bikes.List do
			if data and data.Owned[bike.Id] then
				table.insert(list, bike)
			end
		end
		return list
	end

	local function currentBike(): Bikes.Bike
		local bike = Bikes.Get(bikeId)
		if bike then
			return bike
		end
		return owned()[1] or Bikes.List[1]
	end

	local function buyUpgrade(slot: string, level: number)
		local ok, message = Remotes.Function("BuyUpgrade"):InvokeServer(currentBike().Id, slot, level)
		Toasts.Message(if ok then "Cash" else "Error", tostring(message))
	end

	local function setPaint(slot: string, paintId: string)
		local ok, message = Remotes.Function("SetPaint"):InvokeServer(currentBike().Id, slot, paintId)
		if not ok then
			Toasts.Message("Error", tostring(message))
		end
	end

	local function performance(data: Profile.Data, bike: Bikes.Bike)
		local scroll = scroller(content)
		local levels = Profile.Levels(data, bike.Id)
		for i, slot in Upgrades.Slots do
			local row = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 74), LayoutOrder = i, Parent = scroll })
			Theme.Corner(row, 6)
			Theme.Label({ Text = slot.Title, Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.fromOffset(10, 4), TextSize = 21, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = row })
			Theme.Label({ Text = slot.Description, Size = UDim2.new(0.55, -10, 0, 34), Position = UDim2.fromOffset(10, 30), TextSize = 12, Font = Theme.BodyRegular, Color = C.SubText, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 0, Parent = row })
			if slot.Name == "Limiter" and not BikeStats.HasLimiter(bike) then
				Theme.Label({ Text = "Off-road bikes have no limiter", Size = UDim2.new(0.42, 0, 1, 0), Position = UDim2.new(0.57, 0, 0, 0), TextSize = 14, Font = Theme.Body, Color = C.SubText, Stroke = 0, Parent = row })
				continue
			end
			local selected = Upgrades.Level(levels, slot.Name)
			local ownedLevel = Upgrades.Owned(levels, slot.Name)
			local maxLevel = Upgrades.MaxLevel(slot.Name)
			-- selector among owned stages
			local selector = New("Frame", { BackgroundColor3 = C.Chip, Size = UDim2.new(0.42, 0, 0, 28), Position = UDim2.new(0.57, 0, 0, 6), Parent = row })
			Theme.Corner(selector, 5)
			Theme.Label({ Text = slot.Levels[selected + 1], Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(30, 0), TextSize = 13, Font = Theme.Body, Stroke = 0, Scaled = true, Parent = selector })
			Theme.Button({ Text = "◀", Size = UDim2.fromOffset(26, 24), Position = UDim2.fromOffset(2, 2), Color = if selected > 0 then C.Gray else Color3.fromRGB(50, 50, 54), TextSize = 14, Parent = selector, OnClick = function()
				if selected > 0 then
					buyUpgrade(slot.Name, selected - 1)
				end
			end })
			Theme.Button({ Text = "▶", Size = UDim2.fromOffset(26, 24), Position = UDim2.new(1, -28, 0, 2), Color = if selected < ownedLevel then C.Gray else Color3.fromRGB(50, 50, 54), TextSize = 14, Parent = selector, OnClick = function()
				if selected < ownedLevel then
					buyUpgrade(slot.Name, selected + 1)
				end
			end })
			if ownedLevel < maxLevel then
				local cost = Upgrades.Cost(bike.Id, slot.Name, ownedLevel + 1)
				local affordable = State.Cash() >= cost
				Theme.Button({
					Text = string.format("Buy %s · %s", slot.Levels[ownedLevel + 2], Economy.FormatCash(cost)),
					Size = UDim2.new(0.42, 0, 0, 30),
					Position = UDim2.new(0.57, 0, 0, 38),
					Color = if affordable then C.Green else Color3.fromRGB(150, 40, 40),
					TextSize = 13,
					Font = Theme.Body,
					Parent = row,
					OnClick = function()
						buyUpgrade(slot.Name, ownedLevel + 1)
					end,
				})
			else
				Theme.Label({ Text = "Fully upgraded ✓", Size = UDim2.new(0.42, 0, 0, 30), Position = UDim2.new(0.57, 0, 0, 38), TextSize = 15, Color = C.Cash, Stroke = 1, Parent = row })
			end
		end
	end

	local function swatch(parent: Instance, color: Color3, selectedNow: boolean, locked: boolean, label: string, order: number, onClick: () -> ())
		local button = New("TextButton", { Text = "", BackgroundColor3 = color, Size = UDim2.fromOffset(38, 38), LayoutOrder = order, AutoButtonColor = not locked, Parent = parent })
		Theme.Corner(button, 6)
		Theme.Stroke(button, if selectedNow then Color3.new(1, 1, 1) else Color3.fromRGB(14, 14, 16), if selectedNow then 3 else 1.5)
		if locked then
			button.BackgroundTransparency = 0.6
			Theme.Label({ Text = "🔒", Size = UDim2.fromScale(1, 1), TextSize = 16, Stroke = 0, Parent = button })
		end
		local tip = Theme.Label({ Text = label, Size = UDim2.new(0, 160, 0, 18), Position = UDim2.new(0.5, 0, 0, -20), AnchorPoint = Vector2.new(0.5, 0), TextSize = 13, Stroke = 2, ZIndex = 30, Parent = button })
		tip.Visible = false
		button.MouseEnter:Connect(function()
			tip.Visible = true
		end)
		button.MouseLeave:Connect(function()
			tip.Visible = false
		end)
		button.Activated:Connect(function()
			if not locked then
				onClick()
			else
				Toasts.Message("Info", label .. " comes out of crates")
			end
		end)
	end

	local function paint(data: Profile.Data, bike: Bikes.Bike)
		local scroll = scroller(content)
		local choice = data.Paint[bike.Id] or {}
		for i, slot in Paints.Slots do
			local section = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = scroll })
			Theme.Corner(section, 6)
			Theme.Padding(section, 8)
			Theme.List(section, Enum.FillDirection.Vertical, 6)
			Theme.Label({ Text = if slot == "Glow" then "Underglow" else slot, Size = UDim2.new(1, 0, 0, 22), TextSize = 20, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = 0, Parent = section })
			local grid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = section })
			New("UIGridLayout", { CellSize = UDim2.fromOffset(38, 38), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
			local current = (choice :: any)[slot]
			local kind = if slot == "Glow" then "Glow" else "Paint"
			if kind == "Glow" then
				swatch(grid, Color3.fromRGB(40, 40, 44), current == nil, false, "No underglow", 0, function()
					setPaint(slot, "none")
				end)
			else
				local stock = (bike.Colors :: any)[slot] or Color3.new(0.5, 0.5, 0.5)
				swatch(grid, stock, current == nil, false, "Factory " .. string.lower(slot), 0, function()
					setPaint(slot, "stock")
				end)
			end
			for order, p in Paints.List do
				if p.Kind == kind and p.Id ~= "stock" then
					local unlocked = Profile.HasPaint(data, p.Id)
					swatch(grid, p.Color, current == p.Id, not unlocked, string.format("%s (%s)", p.Name, p.Rarity), order, function()
						setPaint(slot, p.Id)
					end)
				end
			end
		end
	end

	local pendingModes: Modes.ModeSet? = nil
	local saveToken = 0
	local function saveModes()
		saveToken += 1
		local token = saveToken
		task.delay(0.6, function()
			if token == saveToken and pendingModes then
				Remotes.Event("SaveModes"):FireServer(pendingModes)
			end
		end)
	end

	local function modes(data: Profile.Data, bike: Bikes.Bike)
		local scroll = scroller(content)
		local set = pendingModes or Modes.Sanitize(data.Modes)
		pendingModes = set
		local note = if bike.Throttle and not bike.Pedals then "This bike has a throttle and no pedals: each mode's max power is its throttle limit." else "Assist is the support factor: how much the motor adds to what your legs put in. Max power caps the motor. Response sets how hard it kicks in."
		Theme.Label({ Text = note, Size = UDim2.new(1, 0, 0, 34), TextSize = 13, Font = Theme.BodyRegular, Color = C.SubText, Wrapped = true, Align = Enum.TextXAlignment.Left, Stroke = 0, LayoutOrder = 0, Parent = scroll })
		for i, name in Modes.Order do
			if name == "OFF" then
				continue
			end
			local mode = set[name]
			local row = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = i, Parent = scroll })
			Theme.Corner(row, 6)
			local pill = New("Frame", { BackgroundColor3 = Modes.Colors[name], Size = UDim2.fromOffset(84, 30), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = row })
			Theme.Corner(pill, 5)
			Theme.Label({ Text = name, Size = UDim2.fromScale(1, 1), TextSize = 18, Stroke = 2, Parent = pill })
			local function stepper(caption: string, x: number, value: string, onDown: () -> (), onUp: () -> ())
				Theme.Label({ Text = caption, Size = UDim2.fromOffset(150, 16), Position = UDim2.fromOffset(x, 6), TextSize = 12, Font = Theme.Body, Color = C.SubText, Stroke = 0, Parent = row })
				Theme.Button({ Text = "−", Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(x, 26), Color = C.Gray, TextSize = 20, Parent = row, OnClick = onDown })
				Theme.Label({ Text = value, Size = UDim2.fromOffset(86, 28), Position = UDim2.fromOffset(x + 32, 26), TextSize = 17, Stroke = 1, Parent = row })
				Theme.Button({ Text = "+", Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(x + 122, 26), Color = C.Gray, TextSize = 20, Parent = row, OnClick = onUp })
			end
			local function change(field: string, delta: number)
				local limit = (Modes.Limits :: any)[field]
				local m = set[name]
				local value = math.clamp((m :: any)[field] + delta * limit.Step, limit.Min, limit.Max)
				local updated = table.clone(m)
				;(updated :: any)[field] = math.floor(value * 1000 + 0.5) / 1000
				set[name] = updated
				pendingModes = set
				saveModes()
				render()
			end
			stepper("Assist", 110, string.format("%d%%", math.floor(mode.Assist * 100 + 0.5)), function()
				change("Assist", -1)
			end, function()
				change("Assist", 1)
			end)
			stepper("Max power", 270, string.format("%d%%", math.floor(mode.MaxPower * 100 + 0.5)), function()
				change("MaxPower", -1)
			end, function()
				change("MaxPower", 1)
			end)
			stepper("Response", 430, Modes.ResponseName(mode.Response), function()
				change("Response", -1)
			end, function()
				change("Response", 1)
			end)
		end
		Theme.Button({ Text = "Reset to factory modes", Size = UDim2.fromOffset(220, 32), Color = C.Gray, TextSize = 16, LayoutOrder = 99, Parent = scroll, OnClick = function()
			pendingModes = Modes.Sanitize(nil)
			saveModes()
			render()
		end })
	end

	render = function()
		local data = State.Get()
		if not data then
			return
		end
		local bike = currentBike()
		bikeId = bike.Id
		-- picker
		clear(picker)
		for i, b in owned() do
			Theme.Button({ Text = b.Name, Size = UDim2.fromOffset(92, 28), Color = if b.Id == bike.Id then C.Orange else C.Gray, TextSize = 13, Font = Theme.Body, LayoutOrder = i, Parent = picker, OnClick = function()
				bikeId = b.Id
				render()
			end })
		end
		-- preview and stats
		clear(preview)
		Theme.Glow(preview, Bikes.RarityColors[bike.Rarity], UDim2.fromOffset(170, 170))
		Viewport.Bike(preview, bike, data.Paint[bike.Id], UDim2.fromScale(1, 1))
		bikeName.Text = Bikes.FullName(bike)
		clear(stats)
		local levels = Profile.Levels(data, bike.Id)
		local spec = BikeStats.Compute(bike, levels)
		local chips = {
			{ "Top speed", string.format("%d km/h", math.min(spec.CutoffKmh, BikeStats.TopSpeedKmh(spec, 1, 3.4))) },
			{ "Peak power", Bikes.FormatWatts(math.floor(spec.MotorW / 10 + 0.5) * 10) },
			{ "Battery", Bikes.FormatWh(math.floor(spec.BatteryWh)) },
			{ "Wheel torque", string.format("%d N", math.floor(spec.WheelForceN)) },
			{ "Brakes", string.format("%.2f g", spec.BrakeG) },
			{ "Landing", string.format("±%d°", math.floor(math.deg(spec.Landing))) },
			{ "Grip (road)", string.format("%.2f", spec.GripRoad) },
			{ "Grip (grass)", string.format("%.2f", spec.GripOff) },
		}
		for i, chip in chips do
			Theme.Chip(stats, chip[1], chip[2], UDim2.fromScale(1, 1), i)
		end
		-- tabs
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == tab then C.Orange else C.Gray
		end
		clear(content)
		if tab == "Performance" then
			performance(data, bike)
		elseif tab == "Paint" then
			paint(data, bike)
		else
			modes(data, bike)
		end
	end

	for i, name in { "Ride Modes" } do
		tabButtons[name] = Theme.Button({ Text = name, Size = UDim2.fromOffset(150, 32), Color = C.Gray, TextSize = 18, LayoutOrder = i, Parent = tabs, OnClick = function()
			tab = name
			render()
		end })
	end

	panel.Refresh = function()
		local data = State.Get()
		local spawned = Players.LocalPlayer:GetAttribute("BikeId")
		if type(spawned) == "string" and spawned ~= "" then
			bikeId = spawned
		elseif data then
			bikeId = data.Equipped
		end
		pendingModes = nil
		render()
	end
	State.Changed:Connect(function()
		if panel.Frame.Visible and tab ~= "Ride Modes" then
			render()
		end
	end)
	return panel
end

return Tuning
