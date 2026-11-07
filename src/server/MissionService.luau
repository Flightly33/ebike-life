--[[
	MissionService: the story missions (Shared/Missions). The phone's Missions tab starts the next
	one that's open; ObjectiveService runs it and pays it; the save remembers which are done, and the
	next mission's giver gets in touch.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Missions = require(Shared.Missions)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local ObjectiveService = require(script.Parent.ObjectiveService)

local MissionService = {}

local function notify(player: Player, kind: string, text: string)
	Remotes.Event("Notify"):FireClient(player, kind, text)
end

-- The first mission that's open for this player, if any
function MissionService.Next(player: Player): Missions.Mission?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	for _, mission in Missions.List do
		if Missions.Status(mission, data.Missions, data.Level) == "Ready" then
			return mission
		end
	end
	return nil
end

function MissionService.Start(player: Player, id: any): (boolean, string)
	local mission = if type(id) == "string" then Missions.Get(id) else nil
	local data = DataService.Get(player)
	if not mission or not data then
		return false, "No such mission"
	end
	local status = Missions.Status(mission, data.Missions, data.Level)
	if status == "Done" then
		return false, "You've done that one"
	elseif status == "Locked" then
		if data.Level < mission.Level then
			return false, string.format("Opens at level %d", mission.Level)
		end
		return false, "Finish the mission before it first"
	end
	ObjectiveService.Start(player, Missions.Objective(mission), {
		OnDone = function(who: Player, _run, ok: boolean)
			if not ok then
				return
			end
			local saved = DataService.Get(who)
			if not saved then
				return
			end
			saved.Missions[mission.Id] = true
			saved.Stats.Missions += 1
			DataService.Changed(who)
			local giver = Missions.Givers[mission.Giver]
			notify(who, "Info", string.format("%s %s: \"%s\"", if giver then giver.Icon else "📱", mission.Giver, mission.Outro))
			local nextMission = MissionService.Next(who)
			if nextMission then
				local nextGiver = Missions.Givers[nextMission.Giver]
				task.delay(4, function()
					if who.Parent then
						notify(who, "Info", string.format("📱 %s %s has a job for you: \"%s\" (phone > Play)", if nextGiver then nextGiver.Icon else "", nextMission.Giver, nextMission.Name))
					end
				end)
			end
		end,
	})
	return true, mission.Name
end

function MissionService.Init()
	ObjectiveService.Handle("StartMission", function(player: Player, id: any)
		return MissionService.Start(player, id)
	end)
	ObjectiveService.Overview("Missions", function(player: Player)
		local data = DataService.Get(player)
		local list = {}
		if not data then
			return list
		end
		for _, mission in Missions.List do
			table.insert(list, {
				Id = mission.Id,
				Name = mission.Name,
				Giver = mission.Giver,
				Level = mission.Level,
				Intro = mission.Intro,
				Status = Missions.Status(mission, data.Missions, data.Level),
				Cash = mission.Reward.Cash,
				Xp = mission.Reward.Xp,
				Steps = #mission.Steps,
				TimeLimit = mission.TimeLimit,
			})
		end
		return list
	end)
end

return MissionService
