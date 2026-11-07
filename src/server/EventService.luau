--[[
	EventService: announces the city events (Shared/Events) as they start and end. The timetable is
	worked out from the server time, so the multipliers need no state here: EconomyService,
	JobService and RaceService ask Shared/Events directly. ReplicatedStorage carries the running
	event's id ("Event", "" between events) and when it ends ("EventEnds") for the HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Events)
local Remotes = require(Shared.Remotes)

local ObjectiveService = require(script.Parent.ObjectiveService)

local EventService = {}

local current: string? = nil

local function step()
	local t = Workspace:GetServerTimeNow()
	local event, ends, nextEvent, starts = Events.At(t)
	local id = if event then event.Id else ""
	ReplicatedStorage:SetAttribute("Event", id)
	ReplicatedStorage:SetAttribute("EventEnds", ends)
	if current ~= nil and id ~= current then
		for _, player in Players:GetPlayers() do
			if event then
				Remotes.Event("Notify"):FireClient(player, "Event", string.format("%s %s: %s for %d minutes!", event.Icon, event.Name, event.Text, math.floor((ends - t) / 60 + 0.5)))
			else
				Remotes.Event("Notify"):FireClient(player, "Info", string.format("Event over. Next up in %d min: %s %s", math.floor((starts - t) / 60 + 0.5), nextEvent.Icon, nextEvent.Name))
			end
		end
	end
	current = id
end

function EventService.Init()
	ObjectiveService.Overview("Events", function()
		local t = Workspace:GetServerTimeNow()
		local event, ends = Events.At(t)
		local slot = math.floor(t / Events.SLOT)
		local upcoming = {}
		for k = (if event then 1 else 1), 5 do
			local e = Events.List[(slot + k) % #Events.List + 1]
			table.insert(upcoming, { Id = e.Id, Name = e.Name, Text = e.Text, Icon = e.Icon, In = (slot + k) * Events.SLOT - t })
		end
		return {
			Current = if event then { Id = event.Id, Name = event.Name, Text = event.Text, Icon = event.Icon, Ends = ends - t } else nil,
			Upcoming = upcoming,
		}
	end)
	task.spawn(function()
		while true do
			step()
			task.wait(1)
		end
	end)
end

return EventService
