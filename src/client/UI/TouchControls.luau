--[[
	TouchControls: riding buttons for phones and tablets (the thumbstick steers and also works as
	gas). Gas, brake, wheelie, hop and drift are held; one hand and no hands toggle; MODE cycles the
	assist, CAM switches to first person. Two layouts: the full one stacks the buttons above the
	speedometer; the compact one (phones: UI/Hud's compact layout) puts gas in the corner under the
	thumb with the rest in an arc round it and the toggles in a 2x2 block, so nothing reaches the
	wanted stars, and the speedometer moves to the bottom middle.
]]

local UserInputService = game:GetService("UserInputService")

local BikeController = require(script.Parent.Parent.BikeController)
local Input = require(script.Parent.Parent.Input)
local Theme = require(script.Parent.Theme)

local TouchControls = {}

local New = Theme.New
local C = Theme.Colors

local holder: Frame
type Placed = { Button: GuiObject, Full: UDim2, Compact: UDim2 }
local placed: { Placed } = {}

local function place(button: GuiObject, full: UDim2, compact: UDim2)
	local entry: Placed = { Button = button, Full = full, Compact = compact }
	table.insert(placed, entry)
end

local function holdButton(text: string, color: Color3, size: number, position: UDim2, compact: UDim2, field: string)
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
	place(button, position, compact)
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

local function toggleButton(text: string, position: UDim2, compact: UDim2, field: string)
	local button = Theme.Button({ Text = text, Size = UDim2.fromOffset(84, 34), Position = position, AnchorPoint = Vector2.new(0.5, 0.5), Color = C.Gray, TextSize = 14, Parent = holder })
	place(button, position, compact)
	button.Activated:Connect(function()
		local on = not (Input.Touch :: any)[field]
		;(Input.Touch :: any)[field] = on
		button.BackgroundColor3 = if on then C.Orange else C.Gray
	end)
end

function TouchControls.Init(gui: ScreenGui)
	holder = New("Frame", { Name = "TouchControls", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = gui })
	-- (full, then compact: offsets from the bottom-right corner)
	holdButton("GAS", C.Green, 96, UDim2.new(1, -80, 1, -250), UDim2.new(1, -70, 1, -70), "Gas")
	holdButton("BRAKE", C.Red, 72, UDim2.new(1, -180, 1, -200), UDim2.new(1, -180, 1, -48), "Brake")
	holdButton("WHEELIE", C.Orange, 80, UDim2.new(1, -90, 1, -360), UDim2.new(1, -74, 1, -184), "Wheelie")
	holdButton("HOP", C.Blue, 64, UDim2.new(1, -190, 1, -300), UDim2.new(1, -170, 1, -142), "Hop")
	holdButton("DRIFT", C.Purple, 64, UDim2.new(1, -190, 1, -390), UDim2.new(1, -262, 1, -52), "Drift")
	holdButton("TRICK", C.Gold, 64, UDim2.new(1, -90, 1, -460), UDim2.new(1, -258, 1, -140), "Trick")
	holdButton("SPIN", C.Blue, 56, UDim2.new(1, -180, 1, -470), UDim2.new(1, -156, 1, -230), "Barspin")
	toggleButton("ONE HAND", UDim2.new(1, -270, 1, -380), UDim2.new(1, -470, 1, -76), "OneHand")
	toggleButton("NO HANDS", UDim2.new(1, -270, 1, -340), UDim2.new(1, -380, 1, -76), "NoHands")
	local mode = Theme.Button({ Text = "MODE", Size = UDim2.fromOffset(84, 34), Position = UDim2.new(1, -270, 1, -300), AnchorPoint = Vector2.new(0.5, 0.5), Color = C.Purple, TextSize = 14, Parent = holder, OnClick = function()
		Input.Action:Fire("ModeUp")
	end })
	place(mode, mode.Position, UDim2.new(1, -470, 1, -36))
	local cam = Theme.Button({ Text = "CAM", Size = UDim2.fromOffset(84, 34), Position = UDim2.new(1, -270, 1, -260), AnchorPoint = Vector2.new(0.5, 0.5), Color = C.Gray, TextSize = 14, Parent = holder, OnClick = function()
		Input.Action:Fire("Camera")
	end })
	place(cam, cam.Position, UDim2.new(1, -380, 1, -36))
	BikeController.Started:Connect(function()
		holder.Visible = UserInputService.TouchEnabled
	end)
	BikeController.Stopped:Connect(function()
		holder.Visible = false
	end)
end

-- The compact layout (phones) or the full one
function TouchControls.SetCompact(compact: boolean)
	for _, p in placed do
		p.Button.Position = if compact then p.Compact else p.Full
	end
end

return TouchControls
