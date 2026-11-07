--[[
	MissionService: the story missions (Shared/Missions). The phone's Missions tab starts the next
	one that's open; ObjectiveService runs it and pays it; the save remembers which are done, and the
	next mission's giver gets in touch.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Missions = require(Shared.Missions)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local ObjectiveService = require(script.Parent.ObjectiveService)

local MissionService = {}

-- a text from one of the regulars, for the phone's Messages
local function text(player: Player, from: string, message: string)
	Remotes.Event("Message"):FireClient(player, from, message)
end

-- The first mission that's open for this player, if any (the tutorial only when nothing else is:
-- a rider who's done a story mission doesn't need it suggested)
function MissionService.Next(player: Player): Missions.Mission?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local tutorial: Missions.Mission? = nil
	for _, mission in Missions.List do
		if Missions.Status(mission, data.Missions, data.Level) == "Ready" then
			if mission.Id ~= MissionService.TUTORIAL then
				return mission
			end
			tutorial = mission
		end
	end
	return tutorial
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
			text(who, mission.Giver, mission.Outro)
			local nextMission = MissionService.Next(who)
			if nextMission then
				task.delay(4, function()
					if who.Parent then
						text(who, nextMission.Giver, string.format("Got a job for you: \"%s\". Phone > Play when you're ready.", nextMission.Name))
					end
				end)
			end
		end,
	})
	return true, mission.Name
end

MissionService.TUTORIAL = "m00_tutorial"
MissionService.TUTORIAL_DELAY = 5 -- seconds after the save loads

-- A new rider (hardly ridden, tutorial not done) gets the tutorial started for them
local function welcome(player: Player)
	local data = DataService.WaitFor(player)
	if not data or data.Missions[MissionService.TUTORIAL] or data.Stats.Distance > 200 then
		return
	end
	task.wait(MissionService.TUTORIAL_DELAY)
	if player.Parent and not ObjectiveService.Active(player) then
		local ok = MissionService.Start(player, MissionService.TUTORIAL)
		if ok then
			player:SetAttribute("TutorialStarted", true)
		end
	end
end

function MissionService.Init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(welcome, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(welcome, player)
	end
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
