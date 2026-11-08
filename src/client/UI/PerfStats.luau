--[[
	PerfStats: a small readout of how the game is running on this device, for checking a phone or
	an older computer (Menus > Settings > Performance stats; saved as Settings.Stats). Twice a
	second: the frame rate and frame time (the running average and the worst recent frame), the
	ping, the client's memory, how many instances and parts are loaded (streaming), how much of
	the near-camera detail is built (street and home detail, pedestrians, fitted shops), the
	graphics mode and the frame budget's detail scale (Client/Graphics), and the radio station.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local Graphics = require(script.Parent.Parent.Graphics)
local Music = require(script.Parent.Parent.Music)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)

local PerfStats = {}

local label: TextLabel
local frame: Frame
local counts = { Detail = 0, People = 0, Shops = 0 }
local sinceCount = math.huge

local function parts(folderName: string): number
	local folder = Workspace:FindFirstChild(folderName)
	if not folder then
		return 0
	end
	local n = 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function read(fn: () -> number): number?
	local ok, value = pcall(fn)
	return if ok and type(value) == "number" then value else nil
end

local function update()
	local frameMs = Graphics.FrameMs()
	local ping = read(function()
		return Players.LocalPlayer:GetNetworkPing() * 1000
	end)
	local memory = read(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	local instances = read(function()
		return (Stats :: any).InstanceCount
	end)
	local primitives = read(function()
		return (Stats :: any).PrimitivesCount
	end)
	if sinceCount >= 2 then
		sinceCount = 0
		counts.Detail = parts("CityDetail")
		counts.People = parts("Ambient")
		counts.Shops = parts("ShopFit")
	end
	label.Text = table.concat({
		string.format("%d fps  %.1f ms  (worst %.0f ms)   ping %s", math.floor(1000 / math.max(frameMs, 1) + 0.5), frameMs, Graphics.WorstMs(), if ping then string.format("%d ms", math.floor(ping + 0.5)) else "?"),
		string.format("memory %s   instances %s   parts %s", if memory then string.format("%d MB", math.floor(memory)) else "?", if instances then tostring(math.floor(instances)) else "?", if primitives then tostring(math.floor(primitives)) else "?"),
		string.format("near detail %d   people %d   shops %d", counts.Detail, counts.People, counts.Shops),
		string.format("%s   detail scale %d%%   %s", Graphics.Mode(), math.floor(Graphics.Scale() * 100 + 0.5), if Music.Enabled() then "📻 " .. (Music.Station() or "...") else "music off"),
	}, "\n")
end

function PerfStats.Init(gui: ScreenGui)
	frame = Instance.new("Frame")
	frame.Name = "PerfStats"
	frame.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
	frame.BackgroundTransparency = 0.35
	frame.Size = UDim2.fromOffset(430, 74)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 4)
	frame.Visible = false
	frame.ZIndex = 50
	frame.Parent = gui
	Theme.Corner(frame, 8)
	label = Theme.Label({ Text = "", Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), TextSize = 13, Font = Font.fromEnum(Enum.Font.Code), Align = Enum.TextXAlignment.Left, Stroke = 0, ZIndex = 51, Parent = frame })
	label.TextYAlignment = Enum.TextYAlignment.Top
	local since = 0
	RunService.RenderStepped:Connect(function(dt)
		local show = State.Settings().Stats == true
		frame.Visible = show
		if not show then
			return
		end
		since += dt
		sinceCount += dt
		if since >= 0.5 then
			since = 0
			update()
		end
	end)
end

return PerfStats
