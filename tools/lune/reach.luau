--[[
	Prints, for every bike, the seat height, the seat-to-lowest-pedal distance and the seat-to-grip
	distance in studs, against a default R15 avatar (legs ~2.0 studs hip to sole, arms ~1.9 shoulder
	to wrist), to check a rider can reach.

	lune run tools/lune/reach.luau
]]
local roblox = require("@lune/roblox")
local Loader = require("./loader")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local Bikes = Loader.Require("ReplicatedStorage.Shared.Bikes")
local BikeModel = Loader.Require("ReplicatedStorage.Shared.Models.BikeModel")
local Config = Loader.Require("ReplicatedStorage.Shared.Config")

print(string.format("BIKE_SIZE %.2f", Config.BIKE_SIZE))
for _, bike in Bikes.List do
	local model = BikeModel.Build(bike, nil, nil)
	local root = model.PrimaryPart
	local seat = model:FindFirstChild("Seat")
	local function find(name: string)
		for _, d in model:GetDescendants() do
			if d.Name == name and d.ClassName == "Attachment" then
				return d
			end
		end
		return nil
	end
	local function world(a): any
		return (a.Parent.CFrame * a.CFrame).Position
	end
	local pedal = find("PedalL") or find("PegL")
	local grip = find("GripL")
	local s = seat.CFrame.Position
	local p = world(pedal)
	local g = world(grip)
	-- lowest pedal point: crank centre minus crank length (pedals sit on the crank arm)
	-- a default R15 avatar: hips sit ~0.21 above the seat, ankles 0.24 above the pegs, 1.76 studs hip
	-- to ankle; a rider's knees bend to ~85% of that. The size that gives exactly that reach:
	local hipToAnkle = ((s + Vector3.new(0, 0.21, 0)) - (p + Vector3.new(0, 0.24, 0))).Magnitude
	local fit = Config.BIKE_SIZE * 1.5 / hipToAnkle
	print(string.format("%-12s seat %.2f  seat->foot %.2f  seat->grip %.2f  fits a default avatar at size %.2f", bike.Id, s.Y, (s - p).Magnitude, (s - g).Magnitude, fit))
	local _ = root
	local _ = CFrame
end
