--[[
	Music: the radio. Each part of the city has a station of its own (Shared/AudioCatalog.Moods:
	Downtown 305 House, Wynwood Beats, Calle Ocho Radio, Ocean Drive FM, Suburb Chill, Glades
	Country, Stunt Jam Live at the Jump and Loop parks, Race Day Radio at the Race Plaza); after dark
	(or during a Neon Ride) downtown, Wynwood and the beach play Neon Nights; and the moment can take
	over: a race or time trial (Race Day Radio), a police chase of two stars or more (Code Red, which
	plays on a little after you've lost them), the garage (Flighty Garage).

	Tracks come from Shared/AssetIds.MusicByMood (pinned) or the server's audio-library search
	(ReplicatedStorage.Audio "Music_<Mood>"); a station that found nothing plays the general playlist
	("Music", or AssetIds.Music). A station has to stay wanted for a few seconds before the radio
	retunes to it, so riding along a district's edge doesn't flap between two. Tracks crossfade, and
	the music ducks under the stings (Sound.Stung). The speedometer's ♪ toggles it; the volume comes
	from Settings. Music.Tuned fires with the station's name when it changes (the HUD shows it).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared.AssetIds)
local AudioCatalog = require(Shared.AudioCatalog)
local DayNight = require(Shared.DayNight)
local Events = require(Shared.Events)
local Layout = require(Shared.City.Layout)
local Signal = require(Shared.Signal)

local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)

local Music = {}

Music.Toggled = Signal.new() -- (enabled)
Music.Tuned = Signal.new() -- (station name, mood)

local FADE = 2.5
-- how long a station has to be wanted before the radio retunes to it (seconds)
local HOLD: { [string]: number } = { Race = 0.5, Chase = 1, Garage = 0.3 }
local HOLD_PLACE = 6
local CHASE_LINGER = 10 -- the chase music plays on this long after the stars go

-- the place stations by district (the rest of the grids play downtown's)
local PLACE: { [string]: string } = {
	Wynwood = "Wynwood",
	Havana = "Havana",
	HavanaPark = "Havana",
	ArtDeco = "Beach",
	Condo = "Beach",
	Mansion = "Beach",
	KeyPark = "Beach",
	Marina = "Beach",
	Suburb = "Suburbs",
	Gables = "Suburbs",
	GablesHotel = "Suburbs",
	Grove = "Suburbs",
	GroveBay = "Suburbs",
	KeyHomes = "Suburbs",
	Jump = "Stunt",
	RaceHub = "Race",
}
-- the places that play Neon Nights after dark
local NIGHT_PLACES: { [string]: boolean } = { Downtown = true, Wynwood = true, Beach = true }

type Deck = { Order: { number }, Cursor: number, Size: number }

local folder: Instance? = nil
local playlists: { [string]: { string } } = {} -- by mood, and "General"
local decks: { [string]: Deck } = {}
local current: Sound? = nil
local currentMood: string? = nil
local playingFrom: string? = nil -- the playlist the current track came from
local enabled = true
local generation = 0
local failures = 0
local wanted: string? = nil
local wantedSince = 0
local chaseUntil = 0
local sceneSource: (() -> string?)? = nil
local duckUntil = 0
local ducked = false

local function volume(): number
	return if enabled then 0.5 * State.Settings().Music * 2 else 0
end

local function resolveAll(ids: { string }?): { string }
	local out: { string } = {}
	local list: { string } = ids or {}
	for _, id in list do
		local resolved = AssetIds.Resolve(id)
		if resolved then
			table.insert(out, resolved)
		end
	end
	return out
end

local function loadPlaylists()
	local general = resolveAll(AssetIds.Music)
	local f = folder
	if #general == 0 and f then
		general = Sound.SplitIds(f:GetAttribute("Music") :: string?)
	end
	playlists.General = general
	for mood in AudioCatalog.Moods do
		local list = resolveAll(AssetIds.MusicByMood[mood])
		if #list == 0 and f then
			list = Sound.SplitIds(f:GetAttribute("Music_" .. mood) :: string?)
		end
		playlists[mood] = list
	end
end

-- The next track of a playlist: each playlist is shuffled into a deck, dealt to the end, reshuffled
local function nextTrack(name: string): string?
	local list = playlists[name]
	if not list or #list == 0 then
		return nil
	end
	local deck: Deck? = decks[name]
	if not deck or deck.Size ~= #list or deck.Cursor >= #deck.Order then
		local order: { number } = {}
		for i = 1, #list do
			table.insert(order, math.random(1, i), i)
		end
		local fresh: Deck = { Order = order, Cursor = 0, Size = #list }
		decks[name] = fresh
		deck = fresh
	end
	local d = deck :: Deck
	d.Cursor += 1
	return list[d.Order[d.Cursor]]
end

-- The playlist a station plays: its own, or the general one when it found nothing
local function source(mood: string): string?
	local own = playlists[mood]
	if own and #own > 0 then
		return mood
	end
	local general = playlists.General
	if general and #general > 0 then
		return "General"
	end
	return nil
end

local playNext: () -> ()

local function startTrack(id: string)
	generation += 1
	local mine = generation
	local old = current
	if old then
		local fade = TweenService:Create(old, TweenInfo.new(FADE), { Volume = 0 })
		fade.Completed:Once(function()
			old:Destroy()
		end)
		fade:Play()
	end
	local sound = Instance.new("Sound")
	sound.Name = "MusicTrack"
	sound.SoundId = id
	sound.Volume = 0
	sound.SoundGroup = Sound.Group("Music")
	sound.Parent = SoundService
	current = sound
	sound.Ended:Connect(function()
		if generation == mine then
			playNext()
		end
	end)
	task.spawn(function()
		Sound.Verify(id)
		local waited = 0
		while Sound.Status(id) == false and waited < 10 and sound.Parent do
			waited += task.wait(0.25)
		end
		if generation ~= mine or not sound.Parent then
			return
		end
		if Sound.Status(id) ~= true then
			-- (a track that won't load: try the next, but not forever round a playlist of duds)
			failures += 1
			local list = if playingFrom then playlists[playingFrom] else nil
			if not list or failures <= #list then
				task.wait(0.5)
				playNext()
			end
			return
		end
		failures = 0
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(FADE), { Volume = if ducked then volume() * 0.35 else volume() }):Play()
	end)
end

playNext = function()
	local from = source(currentMood or "Downtown")
	if not from then
		return
	end
	local id = nextTrack(from)
	if id then
		playingFrom = from
		startTrack(id)
	end
end

local function retune(mood: string)
	currentMood = mood
	failures = 0
	local from = source(mood)
	if not from then
		return
	end
	-- (two stations on the general playlist share it: the track carries on)
	local playing = current
	if from ~= playingFrom or not (playing and playing.IsPlaying) then
		local id = nextTrack(from)
		if id then
			playingFrom = from
			startTrack(id)
		end
	end
	if enabled then
		local info = AudioCatalog.Moods[mood]
		Music.Tuned:Fire(if info then info.Station else mood, mood)
	end
end

--------------------------------------------------------------------------------
-- Where you are and what's happening
--------------------------------------------------------------------------------

local CELL = 600
local NEAR = 120 -- studs from a block's pad that's still its district (half an avenue or so)
local cells: { [number]: { Layout.Block } }? = nil

local function districtNear(p: Vector3): string?
	local grid = cells
	if not grid then
		local built: { [number]: { Layout.Block } } = {}
		for _, block in Layout.Blocks do
			for gx = math.floor((block.MinX - NEAR) / CELL), math.floor((block.MaxX + NEAR) / CELL) do
				for gz = math.floor((block.MinZ - NEAR) / CELL), math.floor((block.MaxZ + NEAR) / CELL) do
					local k = gx * 100003 + gz
					local list = built[k] or {}
					table.insert(list, block)
					built[k] = list
				end
			end
		end
		cells = built
		grid = built
	end
	local best: Layout.Block? = nil
	local bestD = NEAR
	local list: { Layout.Block } = (grid :: { [number]: { Layout.Block } })[math.floor(p.X / CELL) * 100003 + math.floor(p.Z / CELL)] or {}
	for _, block in list do
		local dx = math.max(block.MinX - p.X, 0, p.X - block.MaxX)
		local dz = math.max(block.MinZ - p.Z, 0, p.Z - block.MaxZ)
		local d = math.max(dx, dz)
		if d < bestD then
			best, bestD = block, d
		end
	end
	return if best then best.District else nil
end

local function inRect(r: Layout.Rect, p: Vector3): boolean
	return p.X >= r.MinX and p.X <= r.MaxX and p.Z >= r.MinZ and p.Z <= r.MaxZ
end

function Music.PlaceMood(p: Vector3): string
	local district = districtNear(p)
	if district then
		return PLACE[district] or "Downtown"
	end
	for _, r in Layout.Beaches do
		if inRect(r, p) then
			return "Beach"
		end
	end
	if inRect(Layout.ISLAND, p) or inRect(Layout.KEY, p) then
		return "Beach"
	end
	-- (over the bay: the causeways and bridges)
	if not inRect(Layout.PORT, p) and Layout.InWater(p.X, p.Z) then
		return "Beach"
	end
	return "Open"
end

local function isNight(t: number): boolean
	local offset = ReplicatedStorage:GetAttribute("ClockOffset")
	local hour = DayNight.Hour(t, if type(offset) == "number" then offset else nil)
	return hour < 6.3 or hour > 19.7
end

-- The station for this moment
function Music.Desired(): string
	local player = Players.LocalPlayer
	local kind = player:GetAttribute("ObjKind")
	if kind == "Race" or kind == "Trial" then
		return "Race"
	end
	local t = Workspace:GetServerTimeNow()
	local event = Events.At(t)
	local stars = tonumber(player:GetAttribute("Wanted")) or 0
	if stars >= 2 or (stars >= 1 and event ~= nil and event.Id == "Crackdown") then
		chaseUntil = os.clock() + CHASE_LINGER
		return "Chase"
	end
	if os.clock() < chaseUntil then
		return "Chase"
	end
	local source = sceneSource
	if source and source() == "Garage" then
		return "Garage"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	local p = if root and root:IsA("BasePart") then root.Position elseif camera then camera.CFrame.Position else nil
	if not p then
		return currentMood or "Downtown"
	end
	local place = Music.PlaceMood(p)
	if NIGHT_PLACES[place] and (isNight(t) or (event ~= nil and event.Id == "NeonNight")) then
		return "Night"
	end
	return place
end

local function update()
	local want = Music.Desired()
	if want ~= wanted then
		wanted = want
		wantedSince = os.clock()
	end
	if want ~= currentMood and os.clock() - wantedSince >= (HOLD[want] or HOLD_PLACE) then
		retune(want)
	elseif currentMood and not current then
		-- (the station's tracks arrived after it was tuned)
		retune(currentMood)
	end
	-- the duck under a sting ends
	if ducked and os.clock() >= duckUntil then
		ducked = false
		local sound = current
		if sound and sound.IsPlaying then
			TweenService:Create(sound, TweenInfo.new(0.8), { Volume = volume() }):Play()
		end
	end
end

--------------------------------------------------------------------------------

function Music.Enabled(): boolean
	return enabled
end

function Music.Station(): string?
	local info = if currentMood then AudioCatalog.Moods[currentMood] else nil
	return if info then info.Station else nil
end

function Music.Toggle()
	enabled = not enabled
	local sound = current
	if sound then
		TweenService:Create(sound, TweenInfo.new(0.6), { Volume = volume() }):Play()
	end
	Music.Toggled:Fire(enabled)
end

-- Lower the music for a moment (under a sting): `level` of its volume for `seconds`
function Music.Duck(seconds: number, level: number?)
	duckUntil = math.max(duckUntil, os.clock() + seconds)
	local sound = current
	if not ducked and sound and sound.IsPlaying then
		ducked = true
		TweenService:Create(sound, TweenInfo.new(0.25), { Volume = volume() * (level or 0.35) }):Play()
	end
end

-- What the UI is showing that has a station of its own ("Garage"), asked every update
function Music.SetSceneSource(fn: () -> string?)
	sceneSource = fn
end

local LONG_STINGS: { [string]: boolean } = { MissionComplete = true, Finish = true, EventStart = true, Achievement = true }

function Music.Init()
	State.SettingsChanged:Connect(function()
		local sound = current
		if sound and sound.IsPlaying and not ducked then
			sound.Volume = volume()
		end
	end)
	Sound.Stung:Connect(function(name: string)
		Music.Duck(if LONG_STINGS[name] then 3 else 1.4)
	end)
	loadPlaylists()
	task.spawn(function()
		local f = ReplicatedStorage:WaitForChild("Audio", 30)
		if f then
			folder = f
			loadPlaylists()
			f.AttributeChanged:Connect(function(name: string)
				if name == "Music" or string.sub(name, 1, 6) == "Music_" then
					loadPlaylists()
				end
			end)
		end
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= 0.25 then
			since = 0
			update()
		end
	end)
end

return Music
