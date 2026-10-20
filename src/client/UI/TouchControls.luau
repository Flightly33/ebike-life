--[[
	TouchControls: riding buttons for phones and tablets (the thumbstick steers and also works as
	gas). Gas, brake, wheelie and hop are held; one hand and no hands toggle; MODE cycles the assist.
]]

local UserInputService = game:GetService("UserInputService")

local BikeController = require(script.Parent.Parent.BikeController)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Theme)

local TouchControls = {}

local New = Theme.New
local C = Theme.Colors

local holder: Frame

local function holdButton(text: string, color: Color3, size: number, position: UDim2, field: string)
	local button = New("TextButton", {
		Text = text,
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(size, size),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = math.floor(size / 4.2),
		TextColor3 = C.Text,
		FontFace = Theme.Font,
		Parent = holder,
	})
	Theme.Round(button)
	Theme.TextStroke(button, 2)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			(Input.Touch :: any)[field] = true
			button.BackgroundTransparency = 0
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			(Input.Touch :: any)[field] = false
			button.BackgroundTransparency = 0.25
		end
	end)
end

local function toggleButton(text: string, position: UDim2, field: string)
	local button = Theme.Button({ Text = text, Size = UDim2.fromOffset(84, 34), Position = position, AnchorPoint = Vector2.new(0.5, 0.5), Color = C.Gray, TextSize = 14, Parent = holder })
	button.Activated:Connect(function()
		local on = not (Input.Touch :: any)[field]
		;(Input.Touch :: any)[field] = on
		button.BackgroundColor3 = if on then C.Orange else C.Gray
	end)
end

function TouchControls.Init(gui: ScreenGui)
	holder = New("Frame", { Name = "TouchControls", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	holdButton("GAS", C.Green, 96, UDim2.new(1, -80, 1, -250), "Gas")
	holdButton("BRAKE", C.Red, 72, UDim2.new(1, -180, 1, -200), "Brake")
	holdButton("WHEELIE", C.Orange, 80, UDim2.new(1, -90, 1, -360), "Wheelie")
	holdButton("HOP", C.Blue, 64, UDim2.new(1, -190, 1, -300), "Hop")
	toggleButton("ONE HAND", UDim2.new(1, -270, 1, -380), "OneHand")
	toggleButton("NO HANDS", UDim2.new(1, -270, 1, -340), "NoHands")
	Theme.Button({ Text = "MODE", Size = UDim2.fromOffset(84, 34), Position = UDim2.new(1, -270, 1, -300), AnchorPoint = Vector2.new(0.5, 0.5), Color = C.Purple, TextSize = 14, Parent = holder, OnClick = function()
		Input.Action:Fire("ModeUp")
	end })
	BikeController.Started:Connect(function()
		holder.Visible = UserInputService.TouchEnabled
	end)
	BikeController.Stopped:Connect(function()
		holder.Visible = false
	end)
end

return TouchControls
