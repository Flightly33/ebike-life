--[[
	AudioCatalog: what each sound slot should sound like, as Roblox audio-library searches.

	The server (AudioService) runs these through AssetService:SearchAudioAsync when it starts, shares
	the ids it finds, and in Studio prints them as a table you can paste into Shared/AssetIds so the
	picks stop changing between servers. Keywords are tried in order until one returns results.

	Music is a radio: each mood (Moods) is a station of its own, found by its keywords, and
	Client/Music tunes to the one for where you are and what's happening (the place's station, night
	downtown and on the beach, a race, a chase, the garage).
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
	-- Flighty Garage
	SprayPaint = { Keywords = { "spray paint can", "spray can", "aerosol spray" }, MaxDuration = 4, Volume = 0.5 },
	Ratchet = { Keywords = { "ratchet wrench", "socket wrench", "ratchet" }, MaxDuration = 3, Volume = 0.5 },
	AirWrench = { Keywords = { "impact wrench", "air wrench", "pneumatic wrench" }, MaxDuration = 3, Volume = 0.45 },
	Lift = { Keywords = { "hydraulic lift", "hydraulic press", "pneumatic hiss" }, MaxDuration = 4, Volume = 0.4 },
	-- ambience (Client/Ambient blends them by where the camera is and the hour)
	AmbientCity = { Keywords = { "city ambience", "city traffic ambience", "urban ambience" }, MinDuration = 20, MaxDuration = 600, Volume = 0.22 },
	AmbientSurf = { Keywords = { "ocean waves", "beach waves ambience", "sea waves" }, MinDuration = 15, MaxDuration = 600, Volume = 0.35 },
	AmbientNature = { Keywords = { "birds ambience", "forest birds", "nature ambience" }, MinDuration = 15, MaxDuration = 600, Volume = 0.3 },
	AmbientNight = { Keywords = { "crickets night", "night insects", "crickets" }, MinDuration = 10, MaxDuration = 600, Volume = 0.25 },
	Jet = { Keywords = { "jet engine loop", "airplane engine", "jet flyby" }, MinDuration = 3, MaxDuration = 120, Volume = 0.8 },
	Gulls = { Keywords = { "seagulls", "seagull", "gull call" }, MaxDuration = 8, Volume = 0.35 },
	-- stings: the moments of a ride (Client/Sound.Sting; the music ducks under them)
	Countdown = { Keywords = { "countdown beep", "race countdown beep", "timer beep" }, MaxDuration = 1.5, Volume = 0.5 },
	RaceGo = { Keywords = { "race start horn", "air horn", "start signal" }, MaxDuration = 3, Volume = 0.55 },
	Checkpoint = { Keywords = { "checkpoint", "positive chime", "ding" }, MaxDuration = 1.5, Volume = 0.45 },
	Finish = { Keywords = { "race finish", "finish line", "victory fanfare" }, MaxDuration = 6, Volume = 0.55 },
	JobPickup = { Keywords = { "item pickup", "package pickup", "pickup pop" }, MaxDuration = 2, Volume = 0.5 },
	JobDeliver = { Keywords = { "doorbell", "door bell ding dong", "delivery complete" }, MaxDuration = 3, Volume = 0.5 },
	MissionStart = { Keywords = { "phone ringtone", "phone ringing", "incoming call" }, MaxDuration = 4, Volume = 0.45 },
	MissionComplete = { Keywords = { "mission complete", "level complete", "success fanfare" }, MaxDuration = 6, Volume = 0.55 },
	MissionFail = { Keywords = { "mission failed", "error buzzer", "fail sound" }, MaxDuration = 3, Volume = 0.5 },
	StarUp = { Keywords = { "police radio chatter", "police scanner", "alarm beep" }, MaxDuration = 4, Volume = 0.5 },
	Achievement = { Keywords = { "achievement unlocked", "trophy", "reward chime" }, MaxDuration = 4, Volume = 0.5 },
	Message = { Keywords = { "text message", "message notification", "phone notification" }, MaxDuration = 2, Volume = 0.45 },
	EventStart = { Keywords = { "crowd cheer", "stadium cheer", "air horn" }, MaxDuration = 6, Volume = 0.5 },
} :: { [string]: Search }

-- the general playlist: any station that found nothing plays these
AudioCatalog.Music = {
	Keywords = { "chill lofi", "upbeat electronic", "summer pop instrumental", "chill hip hop", "feel good" },
	MinDuration = 60,
	MaxDuration = 400,
	PerKeyword = 3,
	MaxTracks = 12,
}

-- The radio's stations: a made-up name for each and what it plays. Places: Downtown (the core,
-- Brickell, Edgewater, Midtown), Wynwood, Havana (Little Havana), Beach (the beach island, North
-- Beach, Key Biscayne, the marina), Suburbs (the suburbs, the Gables, the Grove, Key homes), Open
-- (the countryside, the Everglades, the airport, the port), Stunt (the Jump and Loop parks).
-- Moments: Night (downtown, Wynwood and the beach after dark), Chase (two stars or more), Race (a race
-- or a time trial), Garage (in Flighty Garage).
export type Mood = { Station: string, Keywords: { string } }
AudioCatalog.Moods = {
	Downtown = { Station = "Downtown 305 House", Keywords = { "deep house", "upbeat electronic", "house music" } },
	Wynwood = { Station = "Wynwood Beats", Keywords = { "hip hop instrumental", "boom bap beat", "chill hip hop" } },
	Havana = { Station = "Calle Ocho Radio", Keywords = { "salsa", "latin instrumental", "cuban music" } },
	Beach = { Station = "Ocean Drive FM", Keywords = { "tropical house", "summer pop instrumental", "reggae instrumental" } },
	Suburbs = { Station = "Suburb Chill", Keywords = { "chill lofi", "acoustic chill", "feel good acoustic" } },
	Open = { Station = "Glades Country", Keywords = { "acoustic guitar", "country instrumental", "ambient chill" } },
	Stunt = { Station = "Stunt Jam Live", Keywords = { "rock instrumental", "skate punk", "energetic rock" } },
	Night = { Station = "Neon Nights", Keywords = { "synthwave", "retrowave", "night drive" } },
	Chase = { Station = "Code Red", Keywords = { "action music", "intense electronic", "chase music" } },
	Race = { Station = "Race Day Radio", Keywords = { "drum and bass", "racing music", "high energy electronic" } },
	Garage = { Station = "Flighty Garage", Keywords = { "funk instrumental", "chill beats", "garage funk" } },
} :: { [string]: Mood }
-- each station's search: a few tracks from each keyword until it has MaxTracks
AudioCatalog.MoodSearch = { MinDuration = 60, MaxDuration = 400, PerKeyword = 2, MaxTracks = 5 }

return AudioCatalog
