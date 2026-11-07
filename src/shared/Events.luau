--[[
	Events: a city-wide bonus that comes round on a timetable everyone shares (worked out from the
	server time, like the weather): every SLOT seconds the next event in the list runs for the first
	ACTIVE seconds of the slot. EconomyService, JobService and RaceService read the multipliers; the
	HUD shows a banner and the phone the timetable.
]]

local Events = {}

export type Event = {
	Id: string,
	Name: string,
	Text: string,
	Icon: string,
	Trick: number?, -- trick payouts
	Jobs: number?, -- delivery pay
	Races: number?, -- race and trial pay
	Xp: number?, -- riding XP
	Wanted: number?, -- riding pay while the police are after you
}

Events.SLOT = 1200
Events.ACTIVE = 600

Events.List = {
	{ Id = "StuntJam", Name = "Stunt Jam", Text = "Tricks pay double", Icon = "🤸", Trick = 2 },
	{ Id = "CourierRush", Name = "Courier Rush", Text = "Deliveries pay double", Icon = "📦", Jobs = 2 },
	{ Id = "Crackdown", Name = "Police Crackdown", Text = "Riding pays 1.5x while you're wanted", Icon = "🚨", Wanted = 1.5 },
	{ Id = "NeonNight", Name = "Neon Ride", Text = "Double XP for riding", Icon = "🌃", Xp = 2 },
	{ Id = "RaceDay", Name = "Race Day", Text = "Races and time trials pay double", Icon = "🏁", Races = 2 },
} :: { Event }

-- The event running at `t` (nil between events), when it ends, and the next one and when it starts
function Events.At(t: number): (Event?, number, Event, number)
	local slot = math.floor(t / Events.SLOT)
	local start = slot * Events.SLOT
	local current = Events.List[slot % #Events.List + 1]
	local nextEvent = Events.List[(slot + 1) % #Events.List + 1]
	if t - start < Events.ACTIVE then
		return current, start + Events.ACTIVE, nextEvent, start + Events.SLOT
	end
	return nil, start + Events.SLOT, nextEvent, start + Events.SLOT
end

-- The running event's multiplier for one kind of pay (1 when there's none)
function Events.Multiplier(t: number, key: string): number
	local event = Events.At(t)
	if not event then
		return 1
	end
	local value = (event :: any)[key]
	return if type(value) == "number" then value else 1
end

return Events
