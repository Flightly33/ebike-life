--[[
	ObjectiveService: runs each player's active objective (Shared/Objectives): a story mission, a
	delivery job, a time trial or a race. One at a time; starting another replaces it. Every tick it
	checks the current step against what the server sees (where the rider is, their speed, the
	police), and tricks reach it through EconomyService's validated signals, so nothing the client
	says is taken on trust. The last step pays the objective's reward (unless its owner pays: jobs
	and races work out their own) and tells the owner how it went.

	It also routes the phone's Activity remote: each service registers its actions with Handle and
	its part of the "Overview" with Overview.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Objectives = require(Shared.Objectives)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local BikeService = require(script.Parent.BikeService)
local EconomyService = require(script.Parent.EconomyService)
local PoliceService = require(script.Parent.PoliceService)

local ObjectiveService = {}

export type Run = {
	Objective: Objectives.Objective,
	Step: number,
	Progress: number, -- the current step's progress, in its own units
	Phase: number, -- Escape: 1 getting wanted, 2 losing them
	StartedAt: number, -- server time the clock started (0 until the ClockFrom step)
	Ends: number, -- server time the limit runs out (0: none)
	Crashes: number,
	DistanceAt: number, -- Stats.Distance when the step began
	Pay: boolean,
	OnDone: ((player: Player, run: Run, ok: boolean, reason: string) -> ())?,
	Published: number, -- os.clock of the last progress publish
}

export type Options = {
	Pay: boolean?, -- pay the objective's Reward (default true)
	OnDone: ((player: Player, run: Run, ok: boolean, reason: string) -> ())?,
}

local runs: { [Player]: Run } = {}
local handlers: { [string]: (Player, any, any) -> ...any } = {}
local overviews: { [string]: (Player) -> any } = {}
local calls: { [Player]: { number } } = {}

local ATTRIBUTES = { "ObjKind", "ObjTitle", "ObjText", "ObjStep", "ObjSteps", "ObjTarget", "ObjProgress", "ObjEnds", "ObjStarted" }

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Where the player is: the bike's root while riding, else their character's
local function positionOf(player: Player): (Vector3?, boolean)
	local ride = BikeService.Get(player)
	if ride and ride.Riding then
		return ride.Root.Position, true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position, false
	end
	return nil, false
end

local function fraction(run: Run): number
	local step = run.Objective.Steps[run.Step]
	if step.Kind == "Trick" or step.Kind == "Distance" then
		return math.clamp(run.Progress / math.max(step.Amount or 1, 1e-6), 0, 1)
	end
	return 0
end

local function publish(player: Player)
	local run = runs[player]
	if not run then
		for _, name in ATTRIBUTES do
			player:SetAttribute(name, nil)
		end
		return
	end
	local step = run.Objective.Steps[run.Step]
	local text = Objectives.Describe(step, fraction(run))
	if step.Kind == "Escape" and run.Phase == 2 then
		text = "Lose the police!"
	end
	player:SetAttribute("ObjKind", run.Objective.Kind)
	player:SetAttribute("ObjTitle", run.Objective.Title)
	player:SetAttribute("ObjText", text)
	player:SetAttribute("ObjStep", run.Step)
	player:SetAttribute("ObjSteps", #run.Objective.Steps)
	player:SetAttribute("ObjTarget", step.At)
	player:SetAttribute("ObjProgress", fraction(run))
	player:SetAttribute("ObjEnds", run.Ends)
	player:SetAttribute("ObjStarted", run.StartedAt)
	run.Published = os.clock()
end

local function finish(player: Player, run: Run, ok: boolean, reason: string)
	if runs[player] ~= run then
		return
	end
	runs[player] = nil
	publish(player)
	local objective = run.Objective
	local elapsed = if run.StartedAt > 0 then now() - run.StartedAt else 0
	if ok and run.Pay then
		EconomyService.Reward(player, objective.Reward.Cash, objective.Reward.Xp, objective.Title)
	end
	Remotes.Event("Objective"):FireClient(player, if ok then "Done" else "Failed", {
		Title = objective.Title,
		Kind = objective.Kind,
		Reason = reason,
		Cash = if ok and run.Pay then objective.Reward.Cash else nil,
		Time = elapsed,
	})
	local onDone = run.OnDone
	if onDone then
		onDone(player, run, ok, reason)
	end
end

local function enterStep(player: Player, run: Run, index: number)
	run.Step = index
	run.Progress = 0
	run.Phase = 1
	local data = DataService.Get(player)
	run.DistanceAt = if data then data.Stats.Distance else 0
	if index == (run.Objective.ClockFrom or 1) then
		run.StartedAt = now()
		local limit = run.Objective.TimeLimit
		run.Ends = if limit then run.StartedAt + limit else 0
	end
	publish(player)
	if index > 1 then
		Remotes.Event("Objective"):FireClient(player, "Step", { Step = index, Steps = #run.Objective.Steps, Text = run.Objective.Steps[index].Text })
	end
end

local function advance(player: Player, run: Run)
	if run.Step >= #run.Objective.Steps then
		finish(player, run, true, "Done")
	else
		enterStep(player, run, run.Step + 1)
	end
end

-- Start an objective for a player, replacing any other. Returns the run.
function ObjectiveService.Start(player: Player, objective: Objectives.Objective, options: Options?): Run
	local old = runs[player]
	if old then
		finish(player, old, false, "Replaced")
	end
	local run: Run = {
		Objective = objective,
		Step = 1,
		Progress = 0,
		Phase = 1,
		StartedAt = 0,
		Ends = 0,
		Crashes = 0,
		DistanceAt = 0,
		Pay = not (options and options.Pay == false),
		OnDone = options and options.OnDone,
		Published = 0,
	}
	runs[player] = run
	Remotes.Event("Objective"):FireClient(player, "Started", {
		Title = objective.Title,
		Kind = objective.Kind,
		Intro = objective.Intro,
		Giver = objective.Giver,
		Steps = #objective.Steps,
		TimeLimit = objective.TimeLimit,
	})
	enterStep(player, run, 1)
	return run
end

function ObjectiveService.Active(player: Player): Run?
	return runs[player]
end

function ObjectiveService.Cancel(player: Player, reason: string?)
	local run = runs[player]
	if run then
		finish(player, run, false, reason or "Cancelled")
	end
end

-- The phone's Activity actions and its Overview, registered by each service
function ObjectiveService.Handle(action: string, handler: (Player, any, any) -> ...any)
	handlers[action] = handler
end

function ObjectiveService.Overview(name: string, provider: (Player) -> any)
	overviews[name] = provider
end

-- Tricks and police events move the current step on
local function onTrick(player: Player, kind: string, value: number)
	local run = runs[player]
	if not run then
		return
	end
	if kind == "Crash" then
		run.Crashes += 1
		return
	end
	local step = run.Objective.Steps[run.Step]
	local amount = step.Amount or 1
	if step.Kind == "Wheelie" and kind == "Wheelie" and value >= amount then
		advance(player, run)
	elseif step.Kind == "Air" and kind == "Jump" and value >= amount then
		advance(player, run)
	elseif step.Kind == "Trick" and step.Trick == kind then
		run.Progress += if kind == "Drift" or kind == "Flip" then value else 1
		if run.Progress >= amount then
			advance(player, run)
		else
			publish(player)
		end
	end
end

local function tick()
	local t = now()
	-- (a copy: finishing one can start another, e.g. a race's next stage)
	for player, run in table.clone(runs) do
		if runs[player] ~= run then
			continue
		end
		if run.Ends > 0 and t > run.Ends then
			finish(player, run, false, "Out of time")
			continue
		end
		local step = run.Objective.Steps[run.Step]
		if step.Kind == "Reach" and step.At then
			local at = step.At :: Vector3
			local position, riding = positionOf(player)
			if position and (riding or not step.Ride) then
				local flat = Vector3.new(position.X - at.X, 0, position.Z - at.Z).Magnitude
				if flat <= (step.Radius or Objectives.REACH_RADIUS) and math.abs(position.Y - at.Y) < 60 then
					advance(player, run)
				end
			end
		elseif step.Kind == "Speed" then
			local ride = BikeService.Get(player)
			if ride and ride.Riding and BikeService.Kmh(ride) >= (step.Amount or 0) then
				advance(player, run)
			end
		elseif step.Kind == "Distance" then
			local data = DataService.Get(player)
			if data then
				run.Progress = data.Stats.Distance - run.DistanceAt
				if run.Progress >= (step.Amount or 0) then
					advance(player, run)
				elseif os.clock() - run.Published > 0.5 then
					publish(player)
				end
			end
		elseif step.Kind == "Escape" and run.Phase == 1 then
			if PoliceService.Stars(player) >= (step.Amount or 1) then
				run.Phase = 2
				publish(player)
			end
		end
	end
end

function ObjectiveService.Init()
	EconomyService.Trick:Connect(onTrick)
	EconomyService.Scored:Connect(function(player: Player, amount: number)
		local run = runs[player]
		if not run then
			return
		end
		local step = run.Objective.Steps[run.Step]
		if step.Kind == "Trick" and step.Trick == "Score" then
			run.Progress += amount
			if run.Progress >= (step.Amount or 0) then
				advance(player, run)
			else
				publish(player)
			end
		end
	end)
	PoliceService.Escaped:Connect(function(player: Player)
		local run = runs[player]
		if run and run.Objective.Steps[run.Step].Kind == "Escape" and run.Phase == 2 then
			advance(player, run)
		end
	end)
	PoliceService.Busted:Connect(function(player: Player)
		local run = runs[player]
		if run then
			finish(player, run, false, "Busted")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local run = runs[player]
		if run then
			finish(player, run, false, "Left")
		end
		calls[player] = nil
	end)

	ObjectiveService.Handle("Cancel", function(player: Player)
		if not runs[player] then
			return false, "Nothing to cancel"
		end
		ObjectiveService.Cancel(player, "Cancelled")
		return true, "Cancelled"
	end)
	ObjectiveService.Handle("Overview", function(player: Player)
		local out: { [string]: any } = {}
		for name, provider in overviews do
			local ok, result = pcall(provider, player)
			if ok then
				out[name] = result
			else
				warn(string.format("[ObjectiveService] %s overview failed: %s", name, tostring(result)))
			end
		end
		local run = runs[player]
		out.Active = if run then { Kind = run.Objective.Kind, Title = run.Objective.Title } else nil
		return true, out
	end)
	Remotes.Function("Activity").OnServerInvoke = function(player: Player, action: any, a: any, b: any)
		if type(action) ~= "string" then
			return false, "Bad request"
		end
		-- at most 20 requests in 5 s
		local list = calls[player] or {}
		calls[player] = list
		local t = now()
		while #list > 0 and t - list[1] > 5 do
			table.remove(list, 1)
		end
		if #list >= 20 then
			return false, "Slow down"
		end
		table.insert(list, t)
		local handler = handlers[action]
		if not handler then
			return false, "Unknown action"
		end
		if not DataService.Get(player) then
			return false, "Your save is still loading"
		end
		return handler(player, a, b)
	end

	task.spawn(function()
		while true do
			task.wait(0.1)
			tick()
		end
	end)
end

return ObjectiveService
