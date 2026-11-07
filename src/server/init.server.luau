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

DataService.Init()
CharacterService.Init()
BikeService.Init()
EconomyService.Init()
ShopService.Init()
CityService.Init()
AudioService.Init()
PoliceService.Init()
TrafficService.Init()
AdminService.Init()
OrderService.Init()
-- missions, delivery jobs, races, dailies, events and leaderboards (after the city: jobs read it)
ObjectiveService.Init()
MissionService.Init()
JobService.Init()
RaceService.Init()
DailyService.Init()
EventService.Init()
LeaderboardService.Init()

print("[E-Bike Life] server ready")
