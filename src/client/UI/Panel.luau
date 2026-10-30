--[[
	Panel: the reference game's menu window (dark panel, big outlined title, red X) and the bike card
	used by My Rides and the dealership (name, the bike on a rarity-coloured glow, stat chips, one
	button). Only one panel is open at a time (UI/init handles that).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bikes = require(Shared.Bikes)
local BikeStats = require(Shared.BikeStats)
local Upgrades = require(Shared.Upgrades)
local BikeModel = require(Shared.Models.BikeModel)

local Theme = require(script.Parent.Theme)
local Viewport = require(script.Parent.Viewport)

local Panel = {}

local New = Theme.New
local C = Theme.Colors

export type Panel = {
	Name: string,
	Frame: Frame,
	Body: Frame,
	Title: TextLabel,
	Footer: TextLabel,
	OnClose: (() -> ())?,
	Refresh: (() -> ())?,
}

function Panel.new(gui: Instance, name: string, title: string, size: Vector2, footer: string?): Panel
	local frame = New("Frame", {
		Name = name,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.02,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	Theme.Corner(frame, 10)
	Theme.Stroke(frame, Color3.fromRGB(12, 12, 14), 3)
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 205, 212)), Parent = frame })
	-- a drop shadow behind the panel, shown with it
	local shadow = New("Frame", {
		Name = name .. "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromOffset(size.X + 16, size.Y + 16),
		Position = UDim2.new(0.5, 6, 0.5, 10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 19,
		Parent = gui,
	})
	Theme.Corner(shadow, 16)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		shadow.Visible = frame.Visible
	end)
	-- an accent bar under the title
	local accent = New("Frame", { BackgroundColor3 = C.Orange, Size = UDim2.fromOffset(120, 4), Position = UDim2.new(0.5, 0, 0, 50), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 21, Parent = frame })
	Theme.Corner(accent, 2)
	New("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 60)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 40)) }), Parent = accent })
	local titleLabel = Theme.Label({ Text = title, Size = UDim2.new(1, -120, 0, 44), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0), TextSize = 38, Stroke = 3, Parent = frame })
	local self: Panel
	Theme.Button({
		Name = "Close",
		Text = "X",
		Size = UDim2.fromOffset(40, 36),
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.Red,
		TextSize = 26,
		Corner = 4,
		Parent = frame,
		OnClick = function()
			local cb = self.OnClose
			if cb then
				cb()
			end
		end,
	})
	local body = New("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -66), Position = UDim2.fromOffset(12, 56), Parent = frame })
	local footerLabel = Theme.Label({ Text = footer or "", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0.5, 0, 1, 6), AnchorPoint = Vector2.new(0.5, 0), TextSize = 24, Stroke = 2, Parent = frame })
	footerLabel.Visible = footer ~= nil
	self = { Name = name, Frame = frame, Body = body, Title = titleLabel, Footer = footerLabel, OnClose = nil, Refresh = nil }
	return self
end

-- A scrolling grid of cards inside a body
function Panel.Grid(parent: Instance, cellSize: Vector2, columns: number?): ScrollingFrame
	local scroll = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromRGB(120, 120, 126),
		Parent = parent,
	})
	New("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellSize.X, cellSize.Y),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = columns or 0,
		Parent = scroll,
	})
	New("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = scroll })
	return scroll
end

export type CardButton = { Text: string, Color: Color3, OnClick: (() -> ())? }

-- A ride card: name, bike on a glow, four stat chips and a button
function Panel.BikeCard(parent: Instance, bike: Bikes.Bike, levels: Upgrades.Levels?, paint: BikeModel.PaintChoice?, button: CardButton, order: number, onSelect: (() -> ())?): (Frame, TextButton)
	local card = New("Frame", { Name = bike.Id, BackgroundColor3 = C.Card, LayoutOrder = order, Parent = parent })
	Theme.Corner(card, 6)
	local nameSize = if #bike.Name > 10 then 22 else 28
	Theme.Label({ Text = bike.Name, Size = UDim2.new(1, -8, 0, 30), Position = UDim2.fromOffset(4, 4), TextSize = nameSize, Stroke = 2, Parent = card })
	Theme.Glow(card, Bikes.RarityColors[bike.Rarity], UDim2.fromOffset(150, 150), UDim2.new(0.5, 0, 0, 104))
	Viewport.Bike(card, bike, paint, UDim2.new(1, -10, 0, 112), UDim2.fromOffset(5, 40))
	local chips = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 74), Position = UDim2.fromOffset(8, 156), Parent = card })
	New("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 34), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = chips })
	for i, chip in BikeStats.Chips(bike, levels) do
		Theme.Chip(chips, chip.Label, chip.Value, UDim2.fromScale(1, 1), i)
	end
	local action = Theme.Button({
		Text = button.Text,
		Color = button.Color,
		Size = UDim2.new(1, -16, 0, 36),
		Position = UDim2.new(0, 8, 1, -44),
		TextSize = 24,
		Corner = 3,
		Parent = card,
		OnClick = button.OnClick,
	})
	if onSelect then
		local hit = New("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, -50), ZIndex = 8, Parent = card })
		hit.Activated:Connect(onSelect)
	end
	return card, action
end

return Panel
