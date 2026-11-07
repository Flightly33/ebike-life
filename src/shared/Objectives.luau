--[[
	Objectives: what a story mission, a delivery job, a time trial or a race asks of you, as a list of
	steps done one after another. The server checks them (ObjectiveService) and pays on the last one;
	the client draws the current one (UI/Objective: the tracker, a beacon over the target, a marker on
	the minimap) from the player's attributes:

	  ObjKind      "Mission" | "Job" | "Trial" | "Race" ("" when there's none)
	  ObjTitle     the objective's name
	  ObjText      what the current step asks ("Deliver to Calle Ocho")
	  ObjStep      the step number, ObjSteps how many there are
	  ObjTarget    where the current step is (a Vector3), when it's a place
	  ObjProgress  0..1 through the current step (tricks, distance, wheelie seconds)
	  ObjEnds      server time the time limit runs out (0: none)
	  ObjStarted   server time the clock started (races and trials time from here)

	Step kinds:
	  Reach     get within Radius studs of At (Ride: on the bike)
	  Speed     reach Amount km/h
	  Distance  ride Amount metres
	  Wheelie   hold one wheelie for Amount seconds
	  Air       one jump of Amount seconds
	  Trick     Amount of Trick: "Score" ($ from tricks), "Flip", "AirTrick", "Loop", "Drift" (s)
	  Escape    get Amount wanted stars, then lose them (a bust fails it)
]]

local Objectives = {}

export type Step = {
	Kind: string,
	Text: string,
	At: Vector3?,
	Radius: number?,
	Ride: boolean?,
	Amount: number?,
	Trick: string?,
}

export type Reward = { Cash: number, Xp: number }

export type Objective = {
	Id: string,
	Kind: string,
	Title: string,
	Steps: { Step },
	TimeLimit: number?, -- seconds, counted from step `ClockFrom`
	ClockFrom: number?, -- the step the clock starts on (1 if nil)
	Reward: Reward,
	Intro: string?, -- what the mission's giver says as it starts
	Giver: string?,
}

Objectives.REACH_RADIUS = 28 -- studs (the city's lanes are 19 studs)
Objectives.RACE_RADIUS = 46 -- checkpoints span the carriageway

function Objectives.Reach(text: string, at: Vector3, radius: number?, ride: boolean?): Step
	return { Kind = "Reach", Text = text, At = at, Radius = radius or Objectives.REACH_RADIUS, Ride = ride }
end

function Objectives.Trick(text: string, trick: string, amount: number): Step
	return { Kind = "Trick", Text = text, Trick = trick, Amount = amount }
end

function Objectives.Do(kind: string, text: string, amount: number): Step
	return { Kind = kind, Text = text, Amount = amount }
end

-- The current step's line on the tracker, with how far through it is
function Objectives.Describe(step: Step, progress: number): string
	local amount = step.Amount or 0
	if step.Kind == "Trick" then
		if step.Trick == "Score" then
			return string.format("%s ($%d / $%d)", step.Text, math.floor(progress * amount), amount)
		elseif step.Trick == "Drift" then
			return string.format("%s (%.1f / %d s)", step.Text, progress * amount, amount)
		end
		return string.format("%s (%d / %d)", step.Text, math.floor(progress * amount + 0.001), amount)
	elseif step.Kind == "Distance" then
		return string.format("%s (%.1f / %.1f km)", step.Text, progress * amount / 1000, amount / 1000)
	end
	return step.Text
end

-- "1:23.4"
function Objectives.FormatTime(seconds: number): string
	seconds = math.max(0, seconds)
	local m = math.floor(seconds / 60)
	return string.format("%d:%04.1f", m, seconds - m * 60)
end

return Objectives
