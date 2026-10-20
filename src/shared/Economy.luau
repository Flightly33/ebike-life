--[[
	Economy: what riding pays. Pure functions shared by the server (which pays) and the client (which
	shows the numbers).

	Riding pays a steady rate that grows with speed. Everything you do on top of riding multiplies it:
		cash multiplier = (1 + wheelie + hands + combo + chase) x boost
	where wheelie grows 0.05x per second of the current wheelie (as in the reference game), one hand
	and no hands add a flat bonus while held, the combo grows with every jump, flip and spin you land
	(and drains if you stop doing tricks), and a police chase adds 0.5x per wanted star.
	Tricks also pay a lump sum when they finish. Levels need a linearly growing amount of XP and pay a
	linearly growing reward.
]]

local Config = require(script.Parent.Config)

local Economy = {}

local E = Config.Economy

-- $ per second at a speed, before multipliers
function Economy.BaseRate(kmh: number): number
	if kmh < E.MinPaySpeed then
		return 0
	end
	return E.BaseRate + E.RatePerKmh * math.min(kmh, E.MaxPayKmh)
end

export type Bonus = {
	WheelieTime: number,
	Hands: number, -- 0, 1 (one hand), 2 (no hands)
	Combo: number,
	Stars: number,
	Boost: number, -- 1 or 2
}

function Economy.WheelieBonus(seconds: number): number
	return math.min(math.max(seconds, 0) * E.WheeliePerSecond, E.WheelieMax)
end

function Economy.HandsBonus(hands: number): number
	if hands >= 2 then
		return E.NoHands
	elseif hands == 1 then
		return E.OneHand
	end
	return 0
end

function Economy.Multiplier(bonus: Bonus): number
	local add = Economy.WheelieBonus(bonus.WheelieTime)
		+ Economy.HandsBonus(bonus.Hands)
		+ math.clamp(bonus.Combo, 0, E.ComboMax)
		+ math.max(bonus.Stars, 0) * E.ChasePerStar
	return (1 + add) * math.max(bonus.Boost, 1)
end

-- Lump sums for finished tricks (before the combo bonus)
-- A drift's lump: longer and deeper pays more
function Economy.DriftLump(seconds: number, degrees: number): number
	if seconds < E.DriftLumpMin then
		return 0
	end
	return math.floor(E.DriftLump * seconds ^ 1.15 * (1 + math.clamp(degrees, 0, 75) / 60))
end

function Economy.WheelieLump(seconds: number): number
	if seconds < E.WheelieLumpMin then
		return 0
	end
	return math.floor(E.WheelieLump * seconds ^ 1.2)
end

function Economy.AirLump(seconds: number, clean: boolean): number
	if seconds < Config.Physics.MinAirTime then
		return 0
	end
	local amount = E.AirLump * seconds
	if clean then
		amount *= 1 + E.CleanLandingBonus
	end
	return math.floor(amount)
end

-- XP to go from `level` to `level + 1`
function Economy.XpToNext(level: number): number
	return E.XpBase + E.XpStep * (math.max(level, 1) - 1)
end

-- Cash for reaching `level`
function Economy.LevelReward(level: number): number
	return E.LevelReward + E.LevelRewardStep * math.max(level - 2, 0)
end

-- Adds XP; returns the new level, the XP into that level and the levels gained
function Economy.AddXp(level: number, xp: number, gained: number): (number, number, { number })
	local reached = {}
	xp += gained
	while xp >= Economy.XpToNext(level) do
		xp -= Economy.XpToNext(level)
		level += 1
		table.insert(reached, level)
	end
	return level, xp, reached
end

function Economy.FormatCash(amount: number): string
	local whole = math.floor(math.abs(amount) + 0.5)
	local text = tostring(whole)
	local formatted = ""
	while #text > 3 do
		formatted = "," .. string.sub(text, -3) .. formatted
		text = string.sub(text, 1, -4)
	end
	return (if amount < 0 then "-$" else "$") .. text .. formatted
end

return Economy
