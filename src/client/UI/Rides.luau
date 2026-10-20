--[[
	Rides: the two bike menus.

	My Rides (as in the reference): the bikes you own as cards with a Spawn button, "Buy more rides
	in the dealership!" underneath.
	Flighty Mechanics: every Flightly bike with its price; pick one to see its full spec sheet (class
	and assist limit, motor, nominal/peak power, torque, battery voltage and capacity, weight, brakes,
	suspension, tyres) and buy it. Opened from the dealership's counter or kiosk, or the menu.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bikes = require(Shared.Bikes)
local BikeStats = require(Shared.BikeStats)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Viewport = require(script.Parent.Viewport)

local Rides = {}

local New = Theme.New
local C = Theme.Colors
local CARD = Vector2.new(250, 282)

local function spawnedId(): string
	local id = Players.LocalPlayer:GetAttribute("BikeId")
	return if type(id) == "string" then id else ""
end

function Rides.MyRides(gui: Instance, close: () -> (), openDealership: () -> ()): Panel.Panel
	local panel = Panel.new(gui, "MyRides", "My Rides", Vector2.new(820, 560), "Buy more rides in the dealership!")
	local grid = Panel.Grid(panel.Body, CARD, 3)
	local signature = ""
	local function build()
		local data = State.Get()
		if not data then
			return
		end
		-- rebuild only when something on the cards changed
		local parts = { spawnedId() }
		for _, bike in Bikes.List do
			if data.Owned[bike.Id] then
				table.insert(parts, bike.Id)
				local paint = data.Paint[bike.Id]
				if paint then
					table.insert(parts, tostring(paint.Frame) .. tostring(paint.Accent) .. tostring(paint.Rims) .. tostring(paint.Glow))
				end
				for slot, level in Profile.Levels(data, bike.Id) do
					table.insert(parts, slot .. level)
				end
			end
		end
		local sig = table.concat(parts, "|")
		if sig == signature then
			return
		end
		signature = sig
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local current = spawnedId()
		for index, bike in Bikes.List do
			if data.Owned[bike.Id] then
				local out = bike.Id == current
				Panel.BikeCard(grid, bike, Profile.Levels(data, bike.Id), data.Paint[bike.Id], {
					Text = if out then "Put Away" else "Spawn",
					Color = if out then C.Gray else C.Green,
					OnClick = function()
						if out then
							Remotes.Event("DespawnBike"):FireServer()
						else
							Remotes.Event("SpawnBike"):FireServer(bike.Id)
							close()
						end
					end,
				}, index)
			end
		end
		-- a card that leads to the dealership
		local more = New("TextButton", { Name = "More", Text = "", BackgroundColor3 = C.Card, LayoutOrder = 999, AutoButtonColor = true, Parent = grid })
		Theme.Corner(more, 6)
		Theme.Label({ Text = "+", Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromOffset(0, 60), TextSize = 90, Color = C.Cash, StrokeColor = C.CashDark, Parent = more })
		Theme.Label({ Text = Config.DEALERSHIP, Size = UDim2.new(1, -10, 0, 50), Position = UDim2.fromOffset(5, 170), TextSize = 22, Wrapped = true, Parent = more })
		more.Activated:Connect(openDealership)
	end
	panel.Refresh = function()
		signature = ""
		build()
	end
	State.Changed:Connect(function()
		if panel.Frame.Visible then
			build()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("BikeId"):Connect(function()
		if panel.Frame.Visible then
			build()
		end
	end)
	return panel
end

local function specRows(parent: Instance, bike: Bikes.Bike)
	for _, child in parent:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local spec = BikeStats.Compute(bike, nil)
	local unlocked = BikeStats.TopSpeedKmh(BikeStats.Compute(bike, { Limiter = 1 }), 1, 3.4)
	local rows = {
		{ "Class", if bike.Class == "Off-road" then "Off-road only" else string.format("%s · %d km/h assist", bike.Class, bike.LegalKmh) },
		{ "Motor", bike.Drive },
		{ "Power", string.format("%s nominal · %s peak", Bikes.FormatWatts(bike.NominalW), Bikes.FormatWatts(bike.PeakW)) },
		{ "Torque", string.format("%d Nm", bike.TorqueNm) },
		{ "Battery", string.format("%d V · %s", bike.Volts, Bikes.FormatWh(bike.BatteryWh)) },
		{ "Throttle", if bike.Throttle then "Yes" else "Pedal assist only" },
		{ "Weight", string.format("%d kg", bike.WeightKg) },
		{ "Top speed", string.format("%d km/h (%d unlocked)", math.min(spec.CutoffKmh, BikeStats.TopSpeedKmh(spec, 1, 3.4)), math.min(bike.MaxKmh, unlocked)) },
		{ "Brakes", bike.Brakes },
		{ "Suspension", bike.Suspension },
		{ "Tyres", bike.Tires },
	}
	for i, row in rows do
		local line = New("Frame", { BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(38, 38, 42) else Color3.fromRGB(34, 34, 37), Size = UDim2.new(1, 0, 0, 22), LayoutOrder = i, Parent = parent })
		Theme.Label({ Text = row[1], Size = UDim2.new(0.36, 0, 1, 0), Position = UDim2.fromOffset(6, 0), TextSize = 12, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, Parent = line })
		Theme.Label({ Text = row[2], Size = UDim2.new(0.64, -8, 1, 0), Position = UDim2.new(0.36, 0, 0, 0), TextSize = 12, Font = Theme.Body, Align = Enum.TextXAlignment.Left, Stroke = 0, Scaled = #row[2] > 26, Parent = line })
	end
end

function Rides.Dealership(gui: Instance, _close: () -> ()): Panel.Panel
	local panel = Panel.new(gui, "Dealership", Config.DEALERSHIP, Vector2.new(1080, 600), nil)
	local left = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -290, 1, 0), Parent = panel.Body })
	local grid = Panel.Grid(left, CARD, 3)
	local detail = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(0, 280, 1, 0), Position = UDim2.new(1, -280, 0, 0), Parent = panel.Body })
	Theme.Corner(detail, 6)
	local detailName = Theme.Label({ Text = "", Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 6), TextSize = 24, Stroke = 2, Parent = detail })
	local detailType = Theme.Label({ Text = "", Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(6, 34), TextSize = 14, Color = C.Orange, Font = Theme.Body, Stroke = 0, Parent = detail })
	local viewHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 130), Position = UDim2.fromOffset(0, 50), Parent = detail })
	local blurb = Theme.Label({ Text = "", Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 180), TextSize = 13, Font = Theme.BodyRegular, Wrapped = true, Stroke = 0, Parent = detail })
	local rows = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 250), Position = UDim2.fromOffset(6, 228), Parent = detail })
	Theme.List(rows, Enum.FillDirection.Vertical, 0)
	local buy: TextButton
	local selected: Bikes.Bike = Bikes.List[1]

	local function priceButton(bike: Bikes.Bike): (string, Color3)
		local data = State.Get()
		if not data then
			return "...", C.Gray
		end
		if data.Owned[bike.Id] then
			return "Owned ✓", C.Gray
		end
		if data.Level < bike.Level then
			return string.format("Level %d", bike.Level), C.Gray
		end
		local text = if bike.Price == 0 then "Free" else Economy.FormatCash(bike.Price)
		return text, if State.Cash() >= bike.Price then C.Green else Color3.fromRGB(150, 40, 40)
	end

	local function purchase(bike: Bikes.Bike)
		local data = State.Get()
		if data and data.Owned[bike.Id] then
			Remotes.Event("SpawnBike"):FireServer(bike.Id)
			return
		end
		local ok, message = Remotes.Function("BuyBike"):InvokeServer(bike.Id)
		if not ok then
			Toasts.Message("Error", tostring(message))
		end
	end

	local function select(bike: Bikes.Bike)
		selected = bike
		detailName.Text = Bikes.FullName(bike)
		detailType.Text = string.upper(bike.Type) .. " · " .. bike.Rarity
		blurb.Text = bike.Blurb
		for _, child in viewHolder:GetChildren() do
			child:Destroy()
		end
		Theme.Glow(viewHolder, Bikes.RarityColors[bike.Rarity], UDim2.fromOffset(130, 130))
		Viewport.Bike(viewHolder, bike, nil, UDim2.fromScale(1, 1))
		specRows(rows, bike)
		local text, color = priceButton(bike)
		buy.Text = if text == "Owned ✓" then "Spawn" else (if string.sub(text, 1, 1) == "$" then "Buy " .. text else text)
		buy.BackgroundColor3 = if text == "Owned ✓" then C.Green else color
	end

	buy = Theme.Button({ Text = "Buy", Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 1, -48), TextSize = 24, Corner = 3, Parent = detail, OnClick = function()
		purchase(selected)
	end })

	local signature = ""
	local function build()
		local data = State.Get()
		if not data then
			return
		end
		local parts = { tostring(data.Level) }
		for _, bike in Bikes.List do
			local text, color = priceButton(bike)
			table.insert(parts, text .. tostring(color))
		end
		local sig = table.concat(parts, "|")
		if sig ~= signature then
			signature = sig
			for _, child in grid:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			for index, bike in Bikes.List do
				local text, color = priceButton(bike)
				Panel.BikeCard(grid, bike, nil, nil, {
					Text = text,
					Color = color,
					OnClick = function()
						select(bike)
						if text ~= "Owned ✓" and string.sub(text, 1, 5) ~= "Level" then
							purchase(bike)
						end
					end,
				}, index, function()
					select(bike)
				end)
			end
			select(selected)
		end
	end
	panel.Refresh = function()
		signature = ""
		build()
	end
	State.Changed:Connect(function()
		if panel.Frame.Visible then
			build()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("Cash"):Connect(function()
		if panel.Frame.Visible then
			build()
		end
	end)
	return panel
end

return Rides
