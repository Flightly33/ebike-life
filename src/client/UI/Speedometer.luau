--[[
	Speedometer: the reference game's dark panel with big seven-segment digits (unlit segments show
	faintly), the unit under them and the ride-mode buttons on the right, plus what a real e-bike
	display shows: motor power and the battery with the range left.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modes = require(Shared.Modes)

local Theme = require(script.Parent.Theme)

local Speedometer = {}

local New = Theme.New
local C = Theme.Colors

-- segment -> which digits light it
local PATTERNS = {
	[0] = "abcdef",
	[1] = "bc",
	[2] = "abged",
	[3] = "abgcd",
	[4] = "fgbc",
	[5] = "afgcd",
	[6] = "afgecd",
	[7] = "abc",
	[8] = "abcdefg",
	[9] = "abcdfg",
}

type Digit = { [string]: Frame }

local function digit(parent: Instance, x: number, w: number, h: number): Digit
	local t = math.floor(w * 0.22) -- segment thickness
	local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, 0), Parent = parent })
	local half = h / 2
	local function seg(name: string, px: number, py: number, sw: number, sh: number): Frame
		return New("Frame", {
			Name = name,
			BorderSizePixel = 0,
			BackgroundColor3 = C.DigitOff,
			Position = UDim2.fromOffset(px, py),
			Size = UDim2.fromOffset(sw, sh),
			Parent = holder,
		})
	end
	local segments: Digit = {
		a = seg("a", t, 0, w - 2 * t, t),
		b = seg("b", w - t, t, t, half - t - 1),
		c = seg("c", w - t, half + 1, t, half - t - 1),
		d = seg("d", t, h - t, w - 2 * t, t),
		e = seg("e", 0, half + 1, t, half - t - 1),
		f = seg("f", 0, t, t, half - t - 1),
		g = seg("g", t, half - t / 2, w - 2 * t, t),
	}
	return segments
end

local function show(d: Digit, value: number?)
	local lit = if value then PATTERNS[value] else ""
	for name, segment in d do
		local on = string.find(lit, name, 1, true) ~= nil
		segment.BackgroundColor3 = if on then C.Digit else C.DigitOff
	end
end

export type Speedometer = {
	Frame: Frame,
	Update: (self: Speedometer, kmh: number, units: string, mode: string, battery: number, rangeKm: number, power: number, charging: boolean) -> (),
	OnMode: ((string) -> ())?,
	OnMusic: (() -> ())?,
	SetMusic: (self: Speedometer, on: boolean) -> (),
}

function Speedometer.new(parent: Instance): Speedometer
	local panel = New("Frame", {
		Name = "Speedometer",
		BackgroundColor3 = Color3.fromRGB(18, 18, 20),
		BackgroundTransparency = 0.08,
		Size = UDim2.fromOffset(196, 132),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		Parent = parent,
	})
	Theme.Corner(panel, 10)
	Theme.Stroke(panel, Color3.fromRGB(8, 8, 10), 2)

	local digits = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(126, 62), Position = UDim2.fromOffset(10, 10), Parent = panel })
	local w, h, gap = 34, 62, 8
	local d = { digit(digits, 0, w, h), digit(digits, w + gap, w, h), digit(digits, 2 * (w + gap), w, h) }
	local unit = Theme.Label({ Text = "0 km/h", Size = UDim2.fromOffset(120, 14), Position = UDim2.fromOffset(10, 76), TextSize = 12, Font = Theme.Body, Align = Enum.TextXAlignment.Left, Stroke = 0, Parent = panel })

	-- power bar
	local powerBack = New("Frame", { BackgroundColor3 = C.DigitOff, BorderSizePixel = 0, Size = UDim2.fromOffset(126, 5), Position = UDim2.fromOffset(10, 94), Parent = panel })
	Theme.Corner(powerBack, 3)
	local powerFill = New("Frame", { BackgroundColor3 = C.Orange, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = powerBack })
	Theme.Corner(powerFill, 3)

	-- battery
	local batteryBack = New("Frame", { BackgroundColor3 = C.DigitOff, BorderSizePixel = 0, Size = UDim2.fromOffset(126, 12), Position = UDim2.fromOffset(10, 104), Parent = panel })
	Theme.Corner(batteryBack, 4)
	local batteryFill = New("Frame", { BackgroundColor3 = C.Cash, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = batteryBack })
	Theme.Corner(batteryFill, 4)
	local batteryText = Theme.Label({ Text = "100%", Size = UDim2.fromScale(1, 1), TextSize = 10, Font = Theme.Body, Stroke = 1, Parent = batteryBack, ZIndex = 2 })

	-- right column: music + modes (top to bottom TURBO..OFF)
	local column = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(46, 116), Position = UDim2.new(1, -54, 0, 8), Parent = panel })
	Theme.List(column, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Center)
	local self: Speedometer
	local music = Theme.Button({ Text = "♪", Size = UDim2.fromOffset(24, 20), Color = Color3.fromRGB(40, 40, 44), TextSize = 14, LayoutOrder = 0, Parent = column, OnClick = function()
		local cb = self.OnMusic
		if cb then
			cb()
		end
	end })
	local modeButtons: { [string]: TextButton } = {}
	for i = #Modes.Order, 1, -1 do
		local name = Modes.Order[i]
		local button = Theme.Button({
			Name = name,
			Text = name,
			Size = UDim2.fromOffset(46, 15),
			Color = Color3.fromRGB(40, 40, 44),
			TextSize = 10,
			Font = Theme.Body,
			Corner = 3,
			LayoutOrder = #Modes.Order - i + 1,
			Parent = column,
			OnClick = function()
				local cb = self.OnMode
				if cb then
					cb(name)
				end
			end,
		})
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = 1
		end
		modeButtons[name] = button
	end

	local lastMode = ""
	self = {
		Frame = panel,
		OnMode = nil,
		OnMusic = nil,
		Update = function(_self: Speedometer, kmh: number, units: string, mode: string, battery: number, rangeKm: number, power: number, charging: boolean)
			local value = if units == "mph" then kmh * 0.621371 else kmh
			local n = math.clamp(math.floor(value + 0.5), 0, 999)
			show(d[1], if n >= 100 then math.floor(n / 100) else nil)
			show(d[2], if n >= 10 then math.floor(n / 10) % 10 else nil)
			show(d[3], n % 10)
			unit.Text = string.format("%d %s", n, if units == "mph" then "mph" else "km/h")
			powerFill.Size = UDim2.fromScale(math.clamp(power, 0, 1), 1)
			batteryFill.Size = UDim2.fromScale(math.clamp(battery, 0, 1), 1)
			batteryFill.BackgroundColor3 = if battery > 0.5 then C.Cash elseif battery > 0.2 then C.Gold else C.Red
			local range = if units == "mph" then rangeKm * 0.621371 else rangeKm
			if charging then
				batteryText.Text = string.format("⚡ Charging %d%%", math.floor(battery * 100))
			elseif battery <= 0 then
				batteryText.Text = "EMPTY - pedal or find ⚡"
			else
				batteryText.Text = string.format("%d%%  ·  %.1f %s", math.floor(battery * 100 + 0.5), math.min(range, 99.9), if units == "mph" then "mi" else "km")
			end
			if mode ~= lastMode then
				lastMode = mode
				for name, button in modeButtons do
					local active = name == mode
					button.BackgroundColor3 = if active then Modes.Colors[name] else Color3.fromRGB(40, 40, 44)
					button.TextColor3 = if active then C.Text else Color3.fromRGB(130, 130, 136)
				end
			end
		end,
		SetMusic = function(_self: Speedometer, on: boolean)
			music.TextColor3 = if on then C.Text else Color3.fromRGB(110, 110, 116)
		end,
	}
	return self
end

return Speedometer
