--[[
	Music: a shuffled background playlist with crossfades. Tracks come from Shared/AssetIds.Music or
	the server's audio-library search (ReplicatedStorage.Audio "Music"). The speedometer's ♪ button
	toggles it; the volume comes from Settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared.AssetIds)
local Signal = require(Shared.Signal)

local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)

local Music = {}

Music.Toggled = Signal.new() -- (enabled)

local FADE = 2.5
local playlist: { string } = {}
local order: { number } = {}
local cursor = 0
local current: Sound? = nil
local enabled = true
local generation = 0

local function shuffle()
	order = {}
	for i = 1, #playlist do
		table.insert(order, math.random(1, i), i)
	end
	cursor = 0
end

local function volume(): number
	return if enabled then 0.5 * State.Settings().Music * 2 else 0
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
			task.wait(0.5)
			playNext()
			return
		end
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(FADE), { Volume = volume() }):Play()
	end)
end

playNext = function()
	if #playlist == 0 then
		return
	end
	cursor += 1
	if cursor > #order then
		shuffle()
		cursor = 1
	end
	startTrack(playlist[order[cursor]])
end

function Music.Enabled(): boolean
	return enabled
end

function Music.Toggle()
	enabled = not enabled
	local sound = current
	if sound then
		TweenService:Create(sound, TweenInfo.new(0.6), { Volume = volume() }):Play()
	end
	Music.Toggled:Fire(enabled)
end

function Music.Init()
	State.Changed:Connect(function()
		local sound = current
		if sound and sound.IsPlaying then
			sound.Volume = volume()
		end
	end)
	task.spawn(function()
		for _, id in AssetIds.Music do
			local resolved = AssetIds.Resolve(id)
			if resolved then
				table.insert(playlist, resolved)
			end
		end
		if #playlist == 0 then
			local folder = ReplicatedStorage:WaitForChild("Audio", 30)
			if not folder then
				return
			end
			local deadline = os.clock() + 60
			while folder:GetAttribute("Ready") ~= true and os.clock() < deadline do
				task.wait(1)
			end
			playlist = Sound.SplitIds(folder:GetAttribute("Music") :: string?)
		end
		if #playlist > 0 then
			shuffle()
			playNext()
		end
	end)
end

return Music
