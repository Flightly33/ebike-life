--[[
	State: the client's copy of the player's profile (Shared/Profile), kept in sync by the server's
	Profile remote, plus a few local things the HUD and menus share.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local State = {}

State.Player = Players.LocalPlayer
State.Profile = nil :: Profile.Data?
State.Changed = Signal.new() -- (profile)
State.MenuOpened = Signal.new() -- (name) a menu asked to open ("MyRides", "Dealership", ...)

function State.Get(): Profile.Data?
	return State.Profile
end

-- Cash right now (the attribute is fresher than the profile copy)
function State.Cash(): number
	local cash = State.Player:GetAttribute("Cash")
	if type(cash) == "number" then
		return cash
	end
	local data = State.Profile
	return if data then data.Cash else 0
end

function State.Settings(): Profile.Settings
	local data = State.Profile
	if data then
		return data.Settings
	end
	return Profile.Default().Settings
end

function State.Init()
	Remotes.Event("Profile").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" then
			State.Profile = data
			State.Changed:Fire(data)
		end
	end)
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.Function("GetProfile"):InvokeServer()
		end)
		if ok and type(data) == "table" and State.Profile == nil then
			State.Profile = data
			State.Changed:Fire(data)
		end
	end)
end

return State
