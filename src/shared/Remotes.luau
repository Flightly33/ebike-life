--[[
	All remotes in one place. The server creates them, the client waits for them.

	Client -> Server (RemoteEvent)
		SpawnBike(bikeId)                 take a bike out of the garage, next to you
		DespawnBike()
		BikeState(state)                  (unreliable, ~10 Hz) what the rider is doing: tricks, mode, battery
		Trick(kind, value, extra, text)   finished tricks and crashes, for payouts and police heat
		SetMode(modeName)
		SaveModes(modes)                  custom assist modes from the Tuning menu
		SaveSettings(settings)
		Teleport(destination)
		ClientReady()

	Client -> Server (RemoteFunction; returns ok, message, ...)
		BuyBike(bikeId)
		BuyUpgrade(bikeId, slot)
		SetPaint(bikeId, slot, paintId)
		OpenCrate(crateId)                also returns the paint won
		BuyBoost(boostId)
		GetProfile()                      the player's whole save
		Admin(command, value)             admin commands (AdminService checks who may)

	Server -> Client
		Profile(profile)                  the save changed (bikes, upgrades, paints, settings)
		Notify(kind, text, amount)        toasts: "Level", "Cash", "Error", "Info", "Police"
		Payout(amount, reason)            "+$12 Air 1.2s" pops
		Police(kind, data)                "Wanted", "Busted", "Escaped", "Spotted"
		Charge(percent)                   a charging station topped your battery up
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- The folder must not share this ModuleScript's name, or the client's WaitForChild finds the script
local FOLDER_NAME = "GameRemotes"

local EVENTS = {
	"SpawnBike",
	"DespawnBike",
	"Trick",
	"SetMode",
	"SaveModes",
	"SaveSettings",
	"Teleport",
	"ClientReady",
	"Profile",
	"Notify",
	"Payout",
	"Police",
	"Charge",
}
local UNRELIABLE = { "BikeState" }
local FUNCTIONS = { "BuyBike", "BuyUpgrade", "SetPaint", "OpenCrate", "BuyBoost", "GetProfile", "Admin" }

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in UNRELIABLE do
		local remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.Unreliable(name: string): UnreliableRemoteEvent
	return folder:WaitForChild(name) :: UnreliableRemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
