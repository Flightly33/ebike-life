--[[
	Kit: the UI's components, built on Theme's tokens so every screen looks and moves the same:

	  List      a scrolling column that grows with its contents
	  Heading   a section title in a list
	  Row       a card in a list: icon, title, a line under it, an optional progress bar and badge,
	            up to two buttons on the right
	  Tabs      a row of tab buttons, one lit
	  Progress  a rounded bar
	  Badge     a red counter on a corner (a dot with no number)
	  Toggle    an on/off pill
	  Slider    a draggable bar with its value
	  Segmented one choice of a few, side by side
	  Setting   a row with a label on the left and a control on the right
	  Dialog    a modal question over a dimmed screen

	Instances only (no image ids), like the rest of the UI.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Kit = {}

local New = Theme.New
local C = Theme.Colors
local R = Theme.Roles
local T = Theme.Type
local S = Theme.Space

function Kit.List(parent: Instance, size: UDim2?, position: UDim2?, gap: number?): ScrollingFrame
	local list = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = size or UDim2.fromScale(1, 1),
		Position = position or UDim2.new(),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromRGB(120, 120, 126),
		Parent = parent,
	})
	Theme.List(list, Enum.FillDirection.Vertical, gap or S.S)
	New("UIPadding", { PaddingRight = UDim.new(0, S.S), Parent = list })
	return list
end

function Kit.Clear(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Kit.Heading(parent: Instance, text: string, order: number, color: Color3?): TextLabel
	return Theme.Label({ Text = text, Size = UDim2.new(1, 0, 0, 28), TextSize = T.Heading + 2, Color = color or R.Warning, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = order, Parent = parent })
end

function Kit.Progress(parent: Instance, size: UDim2, position: UDim2, fraction: number, color: Color3?): Frame
	local back = New("Frame", { Name = "Progress", BackgroundColor3 = R.Sunken, Size = size, Position = position, Parent = parent })
	Theme.Round(back)
	local fill = New("Frame", { Name = "Fill", BackgroundColor3 = color or (if fraction >= 1 then C.Cash else R.Accent), Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1), Parent = back })
	Theme.Round(fill)
	return back
end

-- A red badge on a corner of `parent`: Set(n) shows a count, Set(true) a dot, Set(0 / false) hides it
export type Badge = { Frame: TextLabel, Set: (value: number | boolean) -> () }
function Kit.Badge(parent: Instance): Badge
	local label = Theme.Label({ Text = "", Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, 4, 0, -6), AnchorPoint = Vector2.new(1, 0), TextSize = 12, Font = Theme.Body, Stroke = 0, ZIndex = 50, Parent = parent })
	label.Name = "Badge"
	label.BackgroundColor3 = Color3.fromRGB(240, 50, 50)
	label.BackgroundTransparency = 0
	label.Visible = false
	Theme.Round(label)
	Theme.Stroke(label, Color3.fromRGB(255, 255, 255), 1.5)
	return {
		Frame = label,
		Set = function(value: number | boolean)
			if value == true then
				label.Text = ""
				label.Size = UDim2.fromOffset(14, 14)
				label.Visible = true
			elseif type(value) == "number" and value > 0 then
				label.Text = if value > 9 then "9+" else tostring(value)
				label.Size = UDim2.fromOffset(20, 20)
				label.Visible = true
			else
				label.Visible = false
			end
		end,
	}
end

export type Action = { Text: string, Color: Color3?, OnClick: () -> () }
export type RowProps = {
	Title: string,
	Sub: string?,
	Icon: string?,
	Order: number?,
	Height: number?,
	Progress: number?,
	ProgressColor: Color3?,
	Actions: { Action }?,
	Accent: Color3?, -- a stripe down the left
	Dim: boolean?, -- locked or done
}

function Kit.Row(parent: Instance, props: RowProps): Frame
	local frame = New("Frame", { Name = "Row", BackgroundColor3 = R.Raised, Size = UDim2.new(1, 0, 0, props.Height or 66), LayoutOrder = props.Order or 0, Parent = parent })
	Theme.Corner(frame, Theme.Radius.M)
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 214, 220)), Parent = frame })
	local left = S.M
	if props.Accent then
		local stripe = New("Frame", { BackgroundColor3 = props.Accent, Size = UDim2.new(0, 5, 1, -14), Position = UDim2.fromOffset(7, 7), Parent = frame })
		Theme.Corner(stripe, 3)
		left += 8
	end
	if props.Icon then
		Theme.Label({ Text = props.Icon, Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, left, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextSize = 28, Stroke = 0, Parent = frame })
		left += 46
	end
	local actions: { Action } = props.Actions or {}
	local right = if #actions > 0 then 130 * #actions + S.S else S.S
	local title = Theme.Label({ Text = props.Title, Size = UDim2.new(1, -left - right - S.S, 0, 24), Position = UDim2.fromOffset(left, 6), TextSize = T.Heading, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = frame })
	if props.Sub then
		Theme.Label({ Text = props.Sub, Size = UDim2.new(1, -left - right - S.S, 1, -40), Position = UDim2.fromOffset(left, 30), TextSize = T.Caption + 1, Font = Theme.Body, Color = R.Muted, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 1, Parent = frame })
	end
	if props.Progress then
		Kit.Progress(frame, UDim2.new(1, -left - right - S.M, 0, 6), UDim2.new(0, left, 1, -10), props.Progress, props.ProgressColor)
	end
	for i, action in actions do
		Theme.Button({
			Text = action.Text,
			Size = UDim2.fromOffset(122, 40),
			Position = UDim2.new(1, -S.S - (i - 1) * 130, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = action.Color or R.Positive,
			TextSize = 17,
			Parent = frame,
			OnClick = action.OnClick,
		})
	end
	if props.Dim then
		frame.BackgroundTransparency = 0.35
		title.TextTransparency = 0.25
	end
	return frame
end

-- Tab buttons in a row: Set(name) lights one (and calls onSelect when `fire` is true)
export type Tabs = { Frame: Frame, Set: (name: string, fire: boolean?) -> (), Buttons: { [string]: TextButton } }
function Kit.Tabs(parent: Instance, names: { string }, labels: { [string]: string }?, onSelect: (string) -> (), width: number?): Tabs
	local frame = New("Frame", { Name = "Tabs", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = parent })
	Theme.List(frame, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	local buttons: { [string]: TextButton } = {}
	local self: Tabs
	for i, name in names do
		buttons[name] = Theme.Button({
			Text = if labels and labels[name] then labels[name] else name,
			Size = UDim2.fromOffset(width or 124, 36),
			Color = C.Gray,
			TextSize = 17,
			LayoutOrder = i,
			Parent = frame,
			OnClick = function()
				self.Set(name, true)
			end,
		})
	end
	self = {
		Frame = frame,
		Buttons = buttons,
		Set = function(name: string, fire: boolean?)
			for n, button in buttons do
				button.BackgroundColor3 = if n == name then R.Accent else C.Gray
			end
			if fire then
				onSelect(name)
			end
		end,
	}
	return self
end

-- An on/off pill
function Kit.Toggle(parent: Instance, value: boolean, onChange: (boolean) -> ()): TextButton
	local on = value
	local pill = New("TextButton", { Name = "Toggle", Text = "", AutoButtonColor = false, BackgroundColor3 = if on then R.Positive else R.Sunken, Size = UDim2.fromOffset(64, 32), Parent = parent })
	Theme.Round(pill)
	Theme.Stroke(pill, Color3.fromRGB(0, 0, 0), 1.5, 0.5)
	local knob = New("Frame", { BackgroundColor3 = Color3.fromRGB(250, 250, 250), Size = UDim2.fromOffset(26, 26), Position = if on then UDim2.new(1, -29, 0.5, 0) else UDim2.new(0, 3, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = pill })
	Theme.Round(knob)
	pill.Activated:Connect(function()
		on = not on
		TweenService:Create(knob, Theme.Motion.Fast, { Position = if on then UDim2.new(1, -29, 0.5, 0) else UDim2.new(0, 3, 0.5, 0) }):Play()
		TweenService:Create(pill, Theme.Motion.Fast, { BackgroundColor3 = if on then R.Positive else R.Sunken }):Play()
		onChange(on)
	end)
	return pill
end

-- A draggable bar from `min` to `max` in steps of `step`; `format` writes the value beside it;
-- onChange runs when the drag ends, onMove (if given) as it moves
function Kit.Slider(parent: Instance, min: number, max: number, step: number, value: number, format: (number) -> string, onChange: (number) -> (), width: number?, onMove: ((number) -> ())?): Frame
	local holder = New("Frame", { Name = "Slider", BackgroundTransparency = 1, Size = UDim2.fromOffset((width or 220) + 70, 32), Parent = parent })
	local bar = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = R.Sunken, Size = UDim2.new(1, -70, 0, 10), Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = holder })
	Theme.Round(bar)
	local fill = New("Frame", { BackgroundColor3 = R.Accent, Size = UDim2.fromScale(0, 1), Parent = bar })
	Theme.Round(fill)
	local knob = New("Frame", { BackgroundColor3 = Color3.fromRGB(250, 250, 250), Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), ZIndex = 3, Parent = bar })
	Theme.Round(knob)
	Theme.Stroke(knob, Color3.fromRGB(0, 0, 0), 1.5, 0.4)
	local label = Theme.Label({ Text = "", Size = UDim2.fromOffset(64, 32), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), TextSize = T.Body + 2, Align = Enum.TextXAlignment.Right, Stroke = 2, Parent = holder })
	local current = value
	local function show(v: number)
		local f = (v - min) / math.max(max - min, 1e-6)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		label.Text = format(v)
	end
	local function fromX(x: number)
		local f = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		local v = math.clamp(math.floor((min + f * (max - min)) / step + 0.5) * step, min, max)
		if v ~= current then
			current = v
			show(current)
			if onMove then
				onMove(current)
			end
		end
	end
	show(current)
	local dragging = false
	bar.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	local moved = UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			onChange(current)
		end
	end)
	holder.Destroying:Connect(function()
		moved:Disconnect()
		ended:Disconnect()
	end)
	return holder
end

-- One of a few options, side by side
function Kit.Segmented(parent: Instance, options: { string }, value: string, onChange: (string) -> (), width: number?): Frame
	local holder = New("Frame", { Name = "Segmented", BackgroundColor3 = R.Sunken, Size = UDim2.fromOffset((width or 96) * #options + 8, 36), Parent = parent })
	Theme.Corner(holder, Theme.Radius.M)
	Theme.List(holder, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local buttons: { [string]: TextButton } = {}
	local function light(v: string)
		for name, b in buttons do
			b.BackgroundColor3 = if name == v then R.Accent else R.Raised
		end
	end
	for i, option in options do
		buttons[option] = Theme.Button({ Text = option, Size = UDim2.fromOffset((width or 96) - 2, 30), Color = R.Raised, TextSize = 15, LayoutOrder = i, Parent = holder, OnClick = function()
			light(option)
			onChange(option)
		end })
	end
	light(value)
	return holder
end

-- A settings row: the label on the left, `control` (made by `build`) on the right
function Kit.Setting(parent: Instance, label: string, note: string?, order: number, build: (holder: Frame) -> ()): Frame
	local row = New("Frame", { Name = "Setting", BackgroundColor3 = R.Raised, Size = UDim2.new(1, 0, 0, if note then 60 else 50), LayoutOrder = order, Parent = parent })
	Theme.Corner(row, Theme.Radius.M)
	Theme.Label({ Text = label, Size = UDim2.new(0.5, -12, 0, 26), Position = UDim2.fromOffset(S.M, if note then 6 else 12), TextSize = T.Body + 3, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = row })
	if note then
		Theme.Label({ Text = note, Size = UDim2.new(0.5, -12, 0, 20), Position = UDim2.fromOffset(S.M, 32), TextSize = T.Caption, Font = Theme.Body, Color = R.Muted, Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = row })
	end
	local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, -S.M, 1, 0), Position = UDim2.new(1, -S.M, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = row })
	Theme.List(holder, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	build(holder)
	return row
end

-- A modal question over a dimmed screen; any button closes it
function Kit.Dialog(gui: Instance, title: string, body: string, actions: { Action }): Frame
	local dim = New("TextButton", { Name = "Dialog", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 80, Parent = gui })
	local card = New("Frame", { BackgroundColor3 = R.Surface, Size = UDim2.fromOffset(440, 210), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 81, Parent = dim })
	Theme.Corner(card, Theme.Radius.L)
	Theme.Stroke(card, Color3.fromRGB(10, 10, 12), 3)
	Theme.Label({ Text = title, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 12), TextSize = T.Title, Stroke = 2.5, ZIndex = 82, Parent = card })
	Theme.Label({ Text = body, Size = UDim2.new(1, -32, 0, 90), Position = UDim2.fromOffset(16, 52), TextSize = T.Body, Font = Theme.Body, Color = R.Muted, Wrapped = true, Stroke = 1, ZIndex = 82, Parent = card })
	local buttons = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 44), Position = UDim2.new(0, 12, 1, -56), ZIndex = 82, Parent = card })
	Theme.List(buttons, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i, action in actions do
		Theme.Button({ Text = action.Text, Size = UDim2.fromOffset(150, 42), Color = action.Color or R.Positive, TextSize = 19, LayoutOrder = i, ZIndex = 83, Parent = buttons, OnClick = function()
			dim:Destroy()
			action.OnClick()
		end })
	end
	Theme.Pop(card)
	return dim
end

return Kit
