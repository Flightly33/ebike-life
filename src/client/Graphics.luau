--[[
	Graphics: the player's graphics mode (Config.Graphics: Ultra or Performance), applied on this
	client only. Ultra is the full look: sun shadows, clouds, sun rays, a soft far blur over the
	distant skyline, real light from many street lamps and headlights. Performance drops those for
	phones and older computers.

	The mode is saved in the profile (Settings.Graphics). Until the player picks one it follows the
	device (Performance on phones and tablets), and a prompt on join asks.

	The frame budget: it keeps a running average of the frame time, and when frames run long (over
	`Config.Graphics.Budget.SlowMs` for a few seconds) it turns Graphics.Scale() down a step, and back
	up when they've been quick a while. The client's own detail follows it (Client/CityDetail's
	ranges, Client/Ambient's pedestrians, Client/DayNight's lamp lights, Client/ShopFit's range), so a
	slow phone sheds the near-camera extras before the frame rate goes. If the scale is at its floor
	and frames are still long in Ultra, Graphics.Suggest fires once (the UI suggests Performance).
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)

local State = require(script.Parent.State)

local Graphics = {}

Graphics.Suggest = Signal.new() -- frames stay long at the lowest detail scale in Ultra

export type Mode = "Ultra" | "Performance"

local applied: string? = nil

-- What this device should start on before the player picks
function Graphics.Recommended(): Mode
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Performance"
	end
	return "Ultra"
end

-- Has the player picked a mode yet
function Graphics.Chosen(): boolean
	local mode = State.Settings().Graphics
	return mode == "Ultra" or mode == "Performance"
end

function Graphics.Mode(): Mode
	local mode = State.Settings().Graphics
	if mode == "Ultra" or mode == "Performance" then
		return mode
	end
	return Graphics.Recommended()
end

-- The settings of the mode in use
function Graphics.Current(): typeof(Config.Graphics.Ultra)
	return Config.Graphics[Graphics.Mode()]
end

--------------------------------------------------------------------------------
-- The frame budget
--------------------------------------------------------------------------------

local frameMs = 1000 / 60 -- running average of the frame time
local worstMs = 0 -- the longest frame of the last second or so
local scale = 1
local slowFor, quickFor = 0, 0
local suggested = false

function Graphics.Scale(): number
	return scale
end

function Graphics.FrameMs(): number
	return frameMs
end

function Graphics.WorstMs(): number
	return worstMs
end

local function budget(dt: number)
	local cfg = Config.Graphics.Budget
	local ms = dt * 1000
	frameMs += (ms - frameMs) * math.min(1, dt * 2) -- (about a half-second average)
	worstMs = math.max(ms, worstMs - dt * 40)
	if frameMs > cfg.SlowMs then
		slowFor += dt
		quickFor = 0
	elseif frameMs < cfg.QuickMs then
		quickFor += dt
		slowFor = 0
	else
		slowFor, quickFor = 0, 0
	end
	if slowFor > cfg.SlowFor then
		slowFor = 0
		if scale > cfg.MinScale then
			scale = math.max(cfg.MinScale, scale - cfg.Step)
		elseif not suggested and Graphics.Mode() == "Ultra" then
			suggested = true
			Graphics.Suggest:Fire()
		end
	elseif quickFor > cfg.QuickFor and scale < 1 then
		quickFor = 0
		scale = math.min(1, scale + cfg.Step)
	end
end

-- The far blur: distant towers and the horizon soften like a camera lens; near things stay sharp
local function depthOfField(on: boolean)
	local dof = Lighting:FindFirstChild("FarBlur")
	if on and not dof then
		local effect = Instance.new("DepthOfFieldEffect")
		effect.Name = "FarBlur"
		effect.FarIntensity = 0.12
		effect.NearIntensity = 0
		effect.FocusDistance = 160
		effect.InFocusRadius = 420
		effect.Parent = Lighting
		dof = effect
	end
	if dof and dof:IsA("DepthOfFieldEffect") then
		dof.Enabled = on
	end
end

-- Performance hides the city kit's finest detail on this device (Models/CityKit tags it: cornices,
-- string courses, rails, shutters, eyebrows, tower fins, rooftop AC units, shrubs and ground cover)
local FINE_TAG = "KitFine"
local function fineDetail(part: Instance, show: boolean)
	if part:IsA("BasePart") then
		part.LocalTransparencyModifier = if show then 0 else 1
	end
end

function Graphics.Apply()
	local mode = Graphics.Mode()
	if applied == mode then
		return
	end
	applied = mode
	local cfg = Config.Graphics[mode]
	for _, part in CollectionService:GetTagged(FINE_TAG) do
		fineDetail(part, cfg.FineDetail)
	end
	Lighting.GlobalShadows = cfg.Shadows
	Lighting.EnvironmentSpecularScale = cfg.Specular
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Enabled = cfg.SunRays
	end
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Enabled = cfg.Clouds
	end
	depthOfField(cfg.DepthOfField)
end

function Graphics.Init()
	RunService.RenderStepped:Connect(budget)
	Graphics.Apply()
	State.Changed:Connect(Graphics.Apply)
	-- (streaming brings the city's parts in as you ride)
	CollectionService:GetInstanceAddedSignal(FINE_TAG):Connect(function(part: Instance)
		fineDetail(part, Graphics.Current().FineDetail)
	end)
	-- the clouds are made after this runs (Client/DayNight); catch them
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		terrain.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Clouds") then
				child.Enabled = Graphics.Current().Clouds
			end
		end)
	end
end

return Graphics
