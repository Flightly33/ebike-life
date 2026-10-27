--[[
	Sound: one-shot effects and loops (motor whine, wind, sirens).

	Each named sound resolves, in order, to: an id set in Shared/AssetIds.Sounds, a sound the server
	found in Roblox's audio library (ReplicatedStorage.Audio attributes, see Server/AudioService), or
	one of the few built-in sounds every client ships with. Library sounds are preloaded and only
	used once they load. Loops with nothing to play stay silent until something resolves.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared.AssetIds)
local AudioCatalog = require(Shared.AudioCatalog)

local Sound = {}

type Def = { Id: string, Pitch: number, Volume: number, Library: boolean }

-- Sounds that ship with the Roblox client
local BUILTIN: { [string]: Def } = {
	Click = { Id = "rbxasset://sounds/button.wav", Pitch = 1, Volume = 0.4, Library = false },
	Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Pitch = 0.8, Volume = 0.8, Library = false },
	Crash = { Id = "rbxasset://sounds/action_jump_land.mp3", Pitch = 0.5, Volume = 1, Library = false },
	Splash = { Id = "rbxasset://sounds/impact_water.mp3", Pitch = 0.9, Volume = 1, Library = false },
	Cash = { Id = "rbxasset://sounds/electronicpingshort.wav", Pitch = 1.6, Volume = 0.3, Library = false },
	LevelUp = { Id = "rbxasset://sounds/electronicpingshort.wav", Pitch = 1.0, Volume = 0.5, Library = false },
	Bell = { Id = "rbxasset://sounds/electronicpingshort.wav", Pitch = 2.2, Volume = 0.5, Library = false },
	CrateOpen = { Id = "rbxasset://sounds/electronicpingshort.wav", Pitch = 0.8, Volume = 0.5, Library = false },
	Charge = { Id = "rbxasset://sounds/electronicpingshort.wav", Pitch = 1.3, Volume = 0.4, Library = false },
	Escaped = { Id = "rbxasset://sounds/electronicpingshort.wav", Pitch = 1.2, Volume = 0.5, Library = false },
}

local status: { [string]: boolean | string } = {}
local groups: { [string]: SoundGroup } = {}
type Loop = { Sound: Sound, Name: string }
local loops: { Loop } = {}
local audioFolder: Instance? = nil

function Sound.Group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = "EB_" .. name
	g.Volume = 1
	g.Parent = SoundService
	groups[name] = g
	return g
end

function Sound.SetVolume(groupName: string, volume: number)
	Sound.Group(groupName).Volume = volume
end

local function splitIds(text: string?): { string }
	local out: { string } = {}
	if not text or text == "" then
		return out
	end
	for _, piece in string.split(text, ",") do
		local id = AssetIds.Resolve((string.gsub(piece, "%s", "")))
		if id then
			table.insert(out, id)
		end
	end
	return out
end
Sound.SplitIds = splitIds

local refreshLoops: () -> ()

function Sound.Verify(id: string)
	if status[id] ~= nil then
		return
	end
	status[id] = false
	task.spawn(function()
		local probe = Instance.new("Sound")
		probe.SoundId = id
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ probe }, function(_content: string, fetch: Enum.AssetFetchStatus)
				if fetch == Enum.AssetFetchStatus.Failure then
					status[id] = "failed"
				end
			end)
		end)
		if status[id] ~= "failed" then
			status[id] = if ok and probe.IsLoaded then true else "failed"
		end
		probe:Destroy()
		if status[id] == true then
			refreshLoops()
		end
	end)
end

function Sound.Status(id: string): boolean | string | nil
	return status[id]
end

local function pick(list: { string }): string?
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function definition(name: string): Def?
	local base = BUILTIN[name]
	local spec = AudioCatalog.Effects[name]
	local volume = if spec then spec.Volume else if base then base.Volume else 0.6
	local manual = pick(splitIds((AssetIds.Sounds :: any)[name]))
	if manual then
		return { Id = manual, Pitch = 1, Volume = volume, Library = true }
	end
	local folder = audioFolder
	if folder then
		local ready: { string } = {}
		for _, id in splitIds(folder:GetAttribute(name) :: string?) do
			Sound.Verify(id)
			if status[id] == true then
				table.insert(ready, id)
			end
		end
		local found = pick(ready)
		if found then
			return { Id = found, Pitch = 1, Volume = volume, Library = true }
		end
	end
	return base
end

-- One-shot at a position (3D) or on the listener (2D)
function Sound.Play(name: string, position: Vector3?, pitch: number?, volume: number?)
	local def = definition(name)
	if not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume * (volume or 1)
	local shift = pitch or 1
	if def.Library then
		shift = math.clamp(1 + (shift - 1) * 0.35, 0.8, 1.2)
	end
	sound.PlaybackSpeed = def.Pitch * shift * (0.96 + math.random() * 0.08)
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = 300
	sound.SoundGroup = Sound.Group("SFX")
	local holder: Instance = sound
	if position then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = position
		attachment.Parent = workspace.Terrain
		sound.Parent = attachment
		holder = attachment
	else
		sound.Parent = SoundService
	end
	sound.Ended:Connect(function()
		holder:Destroy()
	end)
	task.delay(12, function()
		holder:Destroy()
	end)
	sound:Play()
end

-- A looping sound on `parent` (3D) that starts as soon as its name resolves. Caller sets volume and
-- pitch every frame and destroys it when done.
function Sound.Loop(name: string, parent: Instance?): Sound
	local sound = Instance.new("Sound")
	sound.Name = "Loop_" .. name
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = 250
	sound.SoundGroup = Sound.Group("SFX")
	sound.Parent = parent or SoundService
	table.insert(loops, { Sound = sound, Name = name })
	local def = definition(name)
	if def then
		sound.SoundId = def.Id
		sound:Play()
	end
	sound.Destroying:Connect(function()
		for i, loop in loops do
			if loop.Sound == sound then
				table.remove(loops, i)
				break
			end
		end
	end)
	return sound
end

-- Base volume for a named sound (catalog or built-in), for loops that scale it
function Sound.BaseVolume(name: string): number
	local def = definition(name)
	return if def then def.Volume else 0
end

refreshLoops = function()
	for _, loop in loops do
		local def = definition(loop.Name)
		if def and loop.Sound.SoundId ~= def.Id then
			loop.Sound.SoundId = def.Id
			loop.Sound:Play()
		end
	end
end

function Sound.Init()
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("Audio", 30)
		if not folder then
			return
		end
		audioFolder = folder
		local function check(attribute: string)
			if attribute == "Ready" or attribute == "Music" then
				return
			end
			for _, id in splitIds(folder:GetAttribute(attribute) :: string?) do
				Sound.Verify(id)
			end
		end
		for attribute in folder:GetAttributes() do
			check(attribute)
		end
		folder.AttributeChanged:Connect(check)
	end)
end

return Sound
