--[[
	Client entry point.
]]

local State = require(script.State)
local Sound = require(script.Sound)
local Music = require(script.Music)
local World = require(script.World)
local Input = require(script.Input)
local BikeCamera = require(script.BikeCamera)
local BikeController = require(script.BikeController)
local Visuals = require(script.Visuals)
local RiderPose = require(script.RiderPose)
local FX = require(script.FX)
local DayNight = require(script.DayNight)
local Graphics = require(script.Graphics)
local Ambient = require(script.Ambient)
local ShopFit = require(script.ShopFit)
local Billboards = require(script.Billboards)
local CityDetail = require(script.CityDetail)
local CineCam = require(script.CineCam)
local UI = require(script.UI)

-- Each system starts in its own guard: one that fails is reported as an error (in a thread of its
-- own, so it shows in the Output and the tests count it) and the rest still start, so a cosmetic
-- system going wrong can't take the ride, the HUD or the menus with it
local function start(name: string, init: () -> ())
	local ok, err = xpcall(init, function(e)
		return debug.traceback(tostring(e), 2)
	end)
	if not ok then
		task.spawn(error, string.format("[Client] %s failed to start: %s", name, tostring(err)), 0)
	end
end

start("State", State.Init)
start("Sound", Sound.Init)
start("World", World.Init)
start("Input", Input.Init)
start("BikeCamera", BikeCamera.Init)
start("BikeController", BikeController.Init)
start("Visuals", Visuals.Init)
start("RiderPose", RiderPose.Init)
start("FX", FX.Init)
start("DayNight", DayNight.Init)
start("Graphics", Graphics.Init)
start("Ambient", Ambient.Init)
start("ShopFit", ShopFit.Init)
start("Billboards", Billboards.Init)
start("CityDetail", CityDetail.Init)
start("CineCam", CineCam.Init)
start("UI", UI.Init)
start("Music", Music.Init)
