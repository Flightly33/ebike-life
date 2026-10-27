--[[
	Graphics: the player's graphics mode (Config.Graphics: Ultra or Performance), applied on this
	client only. Ultra is the full look: sun shadows, clouds, sun rays, a soft far blur over the
	distant skyline, real light from many street lamps and headlights. Performance drops those for
	phones and older computers.

	The mode is saved in the profile (Settings.Graphics). Until the player picks one it follows the
	device (Performance on phones and tablets), and a prompt on join asks.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local State = require(script.Parent.State)

local Graphics = {}

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

function Graphics.Apply()
	local mode = Graphics.Mode()
	if applied == mode then
		return
	end
	applied = mode
	local cfg = Config.Graphics[mode]
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
	Graphics.Apply()
	State.Changed:Connect(Graphics.Apply)
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
