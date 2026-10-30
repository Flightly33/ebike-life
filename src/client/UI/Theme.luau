--[[
	Theme: colours, fonts and small builders for the UI, matching the reference game's look: dark
	rounded tiles, chunky rounded white text with a dark outline (Fredoka One), green cash, red close
	buttons, coloured glows behind bikes by rarity.
]]

local TweenService = game:GetService("TweenService")

local Sound = require(script.Parent.Parent.Sound)

local Theme = {}

Theme.Colors = {
	Tile = Color3.fromRGB(34, 34, 37),
	TileStroke = Color3.fromRGB(16, 16, 18),
	Panel = Color3.fromRGB(30, 30, 33),
	Card = Color3.fromRGB(44, 44, 48),
	Chip = Color3.fromRGB(28, 28, 31),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(190, 190, 196),
	Outline = Color3.fromRGB(18, 18, 22),
	Cash = Color3.fromRGB(122, 240, 58),
	CashDark = Color3.fromRGB(36, 88, 18),
	Green = Color3.fromRGB(46, 178, 46),
	GreenDark = Color3.fromRGB(28, 120, 28),
	Red = Color3.fromRGB(196, 32, 34),
	Orange = Color3.fromRGB(255, 132, 22),
	OrangeDark = Color3.fromRGB(90, 40, 0),
	Gray = Color3.fromRGB(86, 86, 92),
	Purple = Color3.fromRGB(176, 70, 255),
	Blue = Color3.fromRGB(50, 140, 255),
	Gold = Color3.fromRGB(255, 196, 46),
	Digit = Color3.fromRGB(246, 246, 246),
	DigitOff = Color3.fromRGB(46, 46, 50),
}
local C = Theme.Colors

Theme.Font = Font.fromEnum(Enum.Font.FredokaOne)
Theme.Body = Font.fromEnum(Enum.Font.GothamBold)
Theme.BodyRegular = Font.fromEnum(Enum.Font.GothamMedium)

-- Creates an instance with properties and children
function Theme.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local New = Theme.New

function Theme.Corner(parent: Instance, radius: number?): UICorner
	return New("UICorner", { CornerRadius = UDim.new(0, radius or 8), Parent = parent })
end

function Theme.Round(parent: Instance): UICorner
	return New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function Theme.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return New("UIStroke", {
		Color = color or C.Outline,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Outline around text (the chunky cartoon look)
function Theme.TextStroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return New("UIStroke", {
		Color = color or C.Outline,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function Theme.Padding(parent: Instance, px: number)
	New("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function Theme.List(parent: Instance, direction: Enum.FillDirection, gap: number, horizontal: Enum.HorizontalAlignment?, vertical: Enum.VerticalAlignment?): UIListLayout
	return New("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vertical or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

export type LabelProps = {
	Text: string,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	Color: Color3?,
	Font: Font?,
	Stroke: number?,
	StrokeColor: Color3?,
	Align: Enum.TextXAlignment?,
	Scaled: boolean?,
	Parent: Instance?,
	LayoutOrder: number?,
	Name: string?,
	ZIndex: number?,
	Wrapped: boolean?,
}

function Theme.Label(props: LabelProps): TextLabel
	local label = New("TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, props.TextSize or 18),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Text = props.Text,
		TextSize = props.TextSize or 18,
		TextColor3 = props.Color or C.Text,
		FontFace = props.Font or Theme.Font,
		TextXAlignment = props.Align or Enum.TextXAlignment.Center,
		TextScaled = props.Scaled == true,
		TextWrapped = props.Wrapped == true,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	if props.Stroke ~= 0 then
		Theme.TextStroke(label, props.Stroke or 2, props.StrokeColor)
	end
	return label
end

export type ButtonProps = {
	Text: string,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	TextColor: Color3?,
	TextSize: number?,
	Font: Font?,
	Parent: Instance?,
	LayoutOrder: number?,
	Name: string?,
	Corner: number?,
	OnClick: (() -> ())?,
	ZIndex: number?,
}

-- A chunky button that dips when pressed and clicks
function Theme.Button(props: ButtonProps): TextButton
	local button = New("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = props.Color or C.Green,
		Size = props.Size or UDim2.fromOffset(120, 36),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Text = props.Text,
		TextSize = props.TextSize or 20,
		TextColor3 = props.TextColor or C.Text,
		FontFace = props.Font or Theme.Font,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	Theme.Corner(button, props.Corner or 6)
	Theme.TextStroke(button, 2)
	-- gloss: lighter on top, a soft shine, a dark edge
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 196, 200)), Parent = button })
	local shine = New("Frame", { Name = "Shine", BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.84, Size = UDim2.new(1, -6, 0.42, 0), Position = UDim2.fromOffset(3, 2), ZIndex = (props.ZIndex or 1), Parent = button })
	Theme.Corner(shine, math.max(2, (props.Corner or 6) - 2))
	local edge = New("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Transparency = 0.55, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
	local _ = edge
	local scale = New("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.05), { Scale = 0.94 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1 }):Play()
	end)
	if props.OnClick then
		local onClick = props.OnClick
		button.Activated:Connect(function()
			Sound.Play("Click")
			onClick()
		end)
	end
	return button
end

-- A soft round glow (concentric circles), used behind bikes in cards (colour = rarity)
function Theme.Glow(parent: Instance, color: Color3, size: UDim2, position: UDim2?): Frame
	local holder = New("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Size = size,
		Position = position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = parent,
	})
	for i, step in { { 1, 0.86 }, { 0.78, 0.78 }, { 0.56, 0.68 }, { 0.34, 0.6 } } do
		local circle = New("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = step[2],
			Size = UDim2.fromScale(step[1], step[1]),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = i,
			Parent = holder,
		})
		Theme.Round(circle)
	end
	return holder
end

-- Small stat chip: grey caption over a white value (as on the reference's ride cards)
function Theme.Chip(parent: Instance, caption: string, value: string, size: UDim2, order: number?): (Frame, TextLabel)
	local chip = New("Frame", {
		Name = "Chip_" .. caption,
		BackgroundColor3 = C.Chip,
		Size = size,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	Theme.Corner(chip, 6)
	Theme.Label({ Text = caption, Size = UDim2.new(1, -4, 0.4, 0), Position = UDim2.new(0, 2, 0.06, 0), TextSize = 11, Color = C.SubText, Font = Theme.Body, Stroke = 0, Scaled = true, Parent = chip })
	local valueLabel = Theme.Label({ Name = "Value", Text = value, Size = UDim2.new(1, -6, 0.5, 0), Position = UDim2.new(0, 3, 0.45, 0), TextSize = 15, Font = Theme.Font, Stroke = 0, Scaled = true, Parent = chip })
	return chip, valueLabel
end

-- Pops a GuiObject in with a scale tween
function Theme.Pop(gui: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale") or New("UIScale", { Parent = gui })
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

return Theme
