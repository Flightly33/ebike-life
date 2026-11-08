--[[
	Server entry point. Services start in dependency order.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
require(Shared.Remotes) -- creates the remotes before anything listens

local DataService = require(script.DataService)
local CharacterService = require(script.CharacterService)
local BikeService = require(script.BikeService)
local EconomyService = require(script.EconomyService)
local ShopService = require(script.ShopService)
local CityService = require(script.CityService)
local AudioService = require(script.AudioService)
local PoliceService = require(script.PoliceService)
local TrafficService = require(script.TrafficService)
local AdminService = require(script.AdminService)
local OrderService = require(script.OrderService)
local ObjectiveService = require(script.ObjectiveService)
local MissionService = require(script.MissionService)
local JobService = require(script.JobService)
local RaceService = require(script.RaceService)
local DailyService = require(script.DailyService)
local EventService = require(script.EventService)
local LeaderboardService = require(script.LeaderboardService)
local GearService = require(script.GearService)
local Regulars = require(script.Regulars)

-- Each service starts in its own guard: one that fails is reported as an error (in a thread of its
-- own, so the Output shows it and the tests count it) and the rest still start
local function start(name: string, init: () -> ())
	local ok, err = xpcall(init, function(e)
		return debug.traceback(tostring(e), 2)
	end)
	if not ok then
		task.spawn(error, string.format("[Server] %s failed to start: %s", name, tostring(err)), 0)
	end
end

start("DataService", DataService.Init)
start("CharacterService", CharacterService.Init)
start("BikeService", BikeService.Init)
start("EconomyService", EconomyService.Init)
start("ShopService", ShopService.Init)
start("CityService", CityService.Init)
start("AudioService", AudioService.Init)
start("PoliceService", PoliceService.Init)
start("TrafficService", TrafficService.Init)
start("AdminService", AdminService.Init)
start("OrderService", OrderService.Init)
-- missions, delivery jobs, races, dailies, events and leaderboards (after the city: jobs read it)
start("ObjectiveService", ObjectiveService.Init)
start("MissionService", MissionService.Init)
start("JobService", JobService.Init)
start("RaceService", RaceService.Init)
start("DailyService", DailyService.Init)
start("EventService", EventService.Init)
start("LeaderboardService", LeaderboardService.Init)
start("GearService", GearService.Init)
start("Regulars", Regulars.Init)

print("[E-Bike Life] server ready")
