--[[
	GraphicsPrompt: on a player's first join, asks which graphics mode to use (Ultra or
	Performance), with the one that suits the device marked. The choice is saved in the profile
	(Settings.Graphics) and can be changed later in Menus > Settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Graphics = require(script.Parent.Parent.Graphics)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)

local GraphicsPrompt = {}

local New = Theme.New
local C = Theme.Colors

local OPTIONS = {
	{ Mode = "Ultra", Title = "✨ ULTRA", Line = "The full look: sun shadows, clouds, sun rays, lens blur on the skyline, lit streets at night. For PCs, consoles and new phones.", Color = C.Orange },
	{ Mode = "Performance", Title = "⚡ PERFORMANCE", Line = "Smoother riding on phones, tablets and older computers. No shadows, clouds or lens blur, fewer night lights.", Color = C.Blue },
}

-- Save the choice (with the rest of the settings) and apply it here straight away
function GraphicsPrompt.Choose(mode: string)
	local data = State.Get()
	if data then
		local settings = table.clone(data.Settings)
		settings.Graphics = mode
		data.Settings = settings
		Remotes.Event("SaveSettings"):FireServer(settings)
	end
	Graphics.Apply()
end

function GraphicsPrompt.Show(gui: Instance)
	local recommended = Graphics.Recommended()
	local shade = New("Frame", { Name = "GraphicsPrompt", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 50, Active = true, Parent = gui })
	local card = New("Frame", { BackgroundColor3 = C.Panel, Size = UDim2.fromOffset(640, 380), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 51, Parent = shade })
	Theme.Corner(card, 12)
	Theme.Stroke(card, C.TileStroke, 3)
	Theme.Label({ Text = "Choose your graphics", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 16), TextSize = 32, ZIndex = 52, Parent = card })
	Theme.Label({ Text = "You can change it any time in Menus › Settings.", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 58), TextSize = 16, Font = Theme.BodyRegular, Color = C.SubText, Stroke = 0, ZIndex = 52, Parent = card })
	for i, option in OPTIONS do
		local x = if i == 1 then 20 else 330
		local box = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.fromOffset(290, 270), Position = UDim2.fromOffset(x, 92), ZIndex = 52, Parent = card })
		Theme.Corner(box, 10)
		if option.Mode == recommended then
			Theme.Stroke(box, option.Color, 3)
			Theme.Label({ Text = "RECOMMENDED FOR THIS DEVICE", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 8), TextSize = 14, Color = option.Color, Stroke = 1, ZIndex = 53, Parent = box })
		end
		Theme.Label({ Text = option.Title, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 30), TextSize = 28, Color = option.Color, ZIndex = 53, Parent = box })
		Theme.Label({ Text = option.Line, Size = UDim2.new(1, -24, 0, 120), Position = UDim2.fromOffset(12, 70), TextSize = 17, Font = Theme.BodyRegular, Wrapped = true, Stroke = 0, ZIndex = 53, Parent = box })
		Theme.Button({ Text = "Play in " .. option.Mode, Size = UDim2.new(1, -24, 0, 48), Position = UDim2.new(0, 12, 1, -60), Color = option.Color, TextSize = 22, ZIndex = 53, Parent = box, OnClick = function()
			GraphicsPrompt.Choose(option.Mode)
			shade:Destroy()
		end })
	end
	Theme.Pop(card)
end

-- Ask once the profile has loaded, if the player hasn't picked yet
function GraphicsPrompt.Init(gui: Instance)
	local asked = false
	local function check()
		if asked or not State.Get() then
			return
		end
		asked = true
		if not Graphics.Chosen() then
			GraphicsPrompt.Show(gui)
		end
	end
	State.Changed:Connect(check)
	check()
end

return GraphicsPrompt
