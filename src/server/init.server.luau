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

print("[E-Bike Life] server ready")
