--[[
	AudioCatalog: what each sound slot should sound like, as Roblox audio-library searches.

	The server (AudioService) runs these through AssetService:SearchAudioAsync when it starts, shares
	the ids it finds, and in Studio prints them as a table you can paste into Shared/AssetIds so the
	picks stop changing between servers. Keywords are tried in order until one returns results.
]]

local AudioCatalog = {}

export type Search = {
	Keywords: { string },
	MinDuration: number?,
	MaxDuration: number?,
	Volume: number,
	Pick: number?,
}

AudioCatalog.Effects = {
	Motor = { Keywords = { "electric motor whine loop", "electric scooter", "electric motor hum" }, MinDuration = 1, MaxDuration = 30, Volume = 0.35 },
	MotoMotor = { Keywords = { "electric motorcycle", "electric dirt bike", "electric motor loop" }, MinDuration = 1, MaxDuration = 30, Volume = 0.45 },
	Wind = { Keywords = { "wind loop", "wind rushing", "wind ambience" }, MinDuration = 2, MaxDuration = 60, Volume = 0.3 },
	Freewheel = { Keywords = { "bicycle freewheel", "bike freewheel clicking", "bicycle coasting" }, MinDuration = 0.5, MaxDuration = 20, Volume = 0.35 },
	Brake = { Keywords = { "bicycle brake squeal", "brake squeal", "bike brake" }, MaxDuration = 3, Volume = 0.35 },
	Crash = { Keywords = { "bike crash", "body fall", "crash impact" }, MaxDuration = 3, Volume = 0.6 },
	Land = { Keywords = { "bike landing", "heavy thud", "landing thump" }, MaxDuration = 1.5, Volume = 0.5 },
	Splash = { Keywords = { "big water splash", "water splash", "splash" }, MaxDuration = 3, Volume = 0.6 },
	Bell = { Keywords = { "bicycle bell", "bike bell ring", "bell ding" }, MaxDuration = 2, Volume = 0.6 },
	Siren = { Keywords = { "police siren loop", "police siren", "siren" }, MinDuration = 2, MaxDuration = 30, Volume = 0.5 },
	Cash = { Keywords = { "cash register", "coins", "money" }, MaxDuration = 2, Volume = 0.4 },
	LevelUp = { Keywords = { "level up", "success fanfare", "achievement" }, MaxDuration = 4, Volume = 0.5 },
	Click = { Keywords = { "ui click", "button click", "click" }, MaxDuration = 0.8, Volume = 0.4 },
	Busted = { Keywords = { "handcuffs", "jail door slam", "police whistle" }, MaxDuration = 4, Volume = 0.6 },
	Escaped = { Keywords = { "success", "victory jingle", "win" }, MaxDuration = 4, Volume = 0.5 },
	CrateOpen = { Keywords = { "chest open", "reward", "unlock" }, MaxDuration = 4, Volume = 0.5 },
	Charge = { Keywords = { "electric charge", "power up", "charging" }, MaxDuration = 4, Volume = 0.45 },
} :: { [string]: Search }

AudioCatalog.Music = {
	Keywords = { "chill lofi", "upbeat electronic", "summer pop instrumental", "chill hip hop", "feel good" },
	MinDuration = 60,
	MaxDuration = 400,
	PerKeyword = 3,
	MaxTracks = 12,
}

return AudioCatalog
