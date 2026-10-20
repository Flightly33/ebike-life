--[[
	Heat: the wanted system, as pure rules the PoliceService drives.

	Cops that can see you fill a heat meter while you break the rules: wheelies, drifts and no-hands riding
	(the main way to get chased), speeding past the bike's legal limit, fast riding on the pavement,
	running red lights, jumps and flips, and hitting a cop car. A full meter is a wanted star; each
	star needs a bigger meter than the last. During a chase, staying in sight adds stars over time.

	Get out of sight for long enough and you escape (and get paid for it). Stop near a cop (or get off
	the bike) and the bust meter fills.
]]

local Config = require(script.Parent.Config)

local Heat = {}

local C = Config.Police

export type State = {
	Heat: number,
	Stars: number,
	ChaseTime: number,
	SeenTime: number,
	Evade: number, -- seconds out of sight during a chase
	Bust: number, -- 0..1
}

export type Offences = {
	Wheelie: boolean,
	NoHands: boolean,
	Drift: boolean,
	SpeedOver: number, -- km/h over the legal limit (0 when not speeding)
	Sidewalk: boolean,
}

export type Event = { Kind: string, Stars: number, Time: number? }

function Heat.new(): State
	return { Heat = 0, Stars = 0, ChaseTime = 0, SeenTime = 0, Evade = 0, Bust = 0 }
end

function Heat.NoOffences(): Offences
	return { Drift = false, Wheelie = false, NoHands = false, SpeedOver = 0, Sidewalk = false }
end

-- Heat for the next star
function Heat.Needed(stars: number): number
	return C.HeatPerStar + C.HeatStarStep * stars
end

function Heat.EvadeTime(stars: number): number
	return C.EvadeBase + C.EvadePerStar * math.max(stars - 1, 0)
end

-- Heat per second for what the player is doing right now
function Heat.Rate(offences: Offences): number
	local rate = 0
	if offences.Wheelie then
		rate += C.Wheelie
	end
	if offences.Drift then
		rate += C.Drift
	end
	if offences.NoHands then
		rate += C.NoHands
	end
	if offences.SpeedOver > C.SpeedingGrace then
		rate += C.Speeding + C.SpeedingPerKmh * (offences.SpeedOver - C.SpeedingGrace)
	end
	if offences.Sidewalk then
		rate += C.Sidewalk
	end
	return rate
end

local function addHeat(state: State, amount: number, events: { Event })
	state.Heat += amount
	while state.Stars < 5 and state.Heat >= Heat.Needed(state.Stars) do
		state.Heat -= Heat.Needed(state.Stars)
		state.Stars += 1
		state.SeenTime = 0
		state.Evade = 0
		table.insert(events, { Kind = "Wanted", Stars = state.Stars })
	end
	if state.Stars >= 5 then
		state.Heat = math.min(state.Heat, Heat.Needed(5))
	end
end

-- A one-off offence a cop saw (jump, flip, red light, hitting a cop car)
function Heat.Offence(state: State, amount: number): { Event }
	local events = {}
	addHeat(state, amount, events)
	return events
end

function Heat.Update(state: State, dt: number, seen: boolean, offences: Offences): { Event }
	local events: { Event } = {}
	local rate = if seen then Heat.Rate(offences) else 0
	if rate > 0 then
		addHeat(state, rate * dt, events)
	else
		state.Heat = math.max(0, state.Heat - C.HeatDecay * dt)
	end

	if state.Stars > 0 then
		state.ChaseTime += dt
		if seen then
			state.Evade = 0
			state.SeenTime += dt
			if state.SeenTime >= C.StarEvery and state.Stars < 5 then
				state.SeenTime = 0
				state.Stars += 1
				table.insert(events, { Kind = "Wanted", Stars = state.Stars })
			end
		else
			state.Evade += dt
			if state.Evade >= Heat.EvadeTime(state.Stars) then
				table.insert(events, { Kind = "Escaped", Stars = state.Stars, Time = state.ChaseTime })
				Heat.Clear(state)
			end
		end
	end
	return events
end

-- `cornered`: a cop is close and the player is (nearly) stopped, or off the bike
function Heat.UpdateBust(state: State, dt: number, cornered: boolean): boolean
	if state.Stars <= 0 then
		state.Bust = 0
		return false
	end
	if cornered then
		state.Bust = math.min(1, state.Bust + dt / C.BustTime)
	else
		state.Bust = math.max(0, state.Bust - dt / C.BustTime * 1.5)
	end
	return state.Bust >= 1
end

function Heat.Clear(state: State)
	state.Heat = 0
	state.Stars = 0
	state.ChaseTime = 0
	state.SeenTime = 0
	state.Evade = 0
	state.Bust = 0
end

function Heat.Fine(cash: number): number
	return math.clamp(math.floor(cash * C.FinePercent), math.min(C.FineMin, cash), C.FineMax)
end

function Heat.EscapeReward(stars: number, chaseTime: number): number
	return math.floor(C.EscapeReward * stars + C.EscapePerSecond * chaseTime * stars)
end

return Heat
