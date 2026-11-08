--[[
	AudioService: finds sound effects and music in Roblox's audio library when the server starts.

	For every sound slot that has no id in Shared/AssetIds, it searches the library with the terms in
	Shared/AudioCatalog and publishes what it found as attributes on ReplicatedStorage.Audio; the
	client's Sound and Music modules pick them up (and fall back to built-in sounds for anything that
	is missing or fails to load). Effects first, then the general playlist ("Music"), then each radio
	station ("Music_<Mood>"), each published as soon as it's found. The picks are printed as a table:
	paste it into Shared/AssetIds to keep them, since search results can change from one server to
	the next.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local AssetIds = require(Shared.AssetIds)
local AudioCatalog = require(Shared.AudioCatalog)

local AudioService = {}

type Found = { Id: number, Title: string }

local SEARCH_GAP = 0.4 -- seconds between requests, to stay well inside the rate limit

local folder: Folder

-- Search results are plain tables; read them defensively in case field names change.
local function readItem(item: any): Found?
	if type(item) ~= "table" then
		return nil
	end
	local id = tonumber(item.Id or item.AssetId or item.id)
	if not id or id <= 0 then
		return nil
	end
	local title = item.Title or item.Name or item.title
	return { Id = id, Title = if type(title) == "string" then title else "?" }
end

local function search(keyword: string, subType: Enum.AudioSubType, minDuration: number?, maxDuration: number?): ({ Found }, string?)
	local params = Instance.new("AudioSearchParams")
	params.SearchKeyword = keyword
	params.AudioSubType = subType
	if minDuration then
		params.MinDuration = math.floor(minDuration)
	end
	if maxDuration then
		params.MaxDuration = math.ceil(maxDuration)
	end
	local ok, result = pcall(function()
		return AssetService:SearchAudioAsync(params)
	end)
	params:Destroy()
	if not ok then
		return {}, tostring(result)
	end
	local okPage, page = pcall(function()
		return (result :: AudioPages):GetCurrentPage()
	end)
	if not okPage or type(page) ~= "table" then
		return {}, "no results page"
	end
	-- Endorsed (Roblox-curated) sounds first, otherwise keep the search order
	local endorsed: { Found } = {}
	local rest: { Found } = {}
	for _, item in page :: { any } do
		local found = readItem(item)
		if found then
			table.insert(if type(item) == "table" and item.IsEndorsed == true then endorsed else rest, found)
		end
	end
	table.move(rest, 1, #rest, #endorsed + 1, endorsed)
	return endorsed, nil
end

local function idList(found: { Found }): string
	local parts = {}
	for _, f in found do
		table.insert(parts, "rbxassetid://" .. f.Id)
	end
	return table.concat(parts, ",")
end

local function findEffects(report: { string }): number
	local names = {}
	for name in AudioCatalog.Effects do
		table.insert(names, name)
	end
	table.sort(names)
	local count = 0
	for _, name in names do
		local manual = (AssetIds.Sounds :: any)[name]
		if type(manual) == "string" and manual ~= "" then
			continue
		end
		local spec = AudioCatalog.Effects[name]
		for _, keyword in spec.Keywords do
			local found, err = search(keyword, Enum.AudioSubType.SoundEffect, spec.MinDuration, spec.MaxDuration)
			task.wait(SEARCH_GAP)
			if err then
				warn(string.format("[AudioService] search failed (%s): %s", keyword, err))
				return count -- the service is unavailable (Studio not published, outage...); stop trying
			end
			if #found > 0 then
				local keep = table.move(found, 1, math.min(#found, spec.Pick or 1), 1, {})
				folder:SetAttribute(name, idList(keep))
				count += 1
				local ids = {}
				for _, f in keep do
					table.insert(ids, tostring(f.Id))
				end
				table.insert(report, string.format('\t%s = "%s", -- %s', name, table.concat(ids, ","), keep[1].Title))
				break
			end
		end
	end
	return count
end

-- Tracks for one playlist: up to `perKeyword` from each keyword until there are `maxTracks`,
-- none twice (across every playlist: `seen`). Returns the tracks and whether the service failed.
local function findTracks(keywords: { string }, minDuration: number, maxDuration: number, perKeyword: number, maxTracks: number, seen: { [number]: boolean }): ({ Found }, boolean)
	local tracks: { Found } = {}
	for _, keyword in keywords do
		if #tracks >= maxTracks then
			break
		end
		local found, err = search(keyword, Enum.AudioSubType.Music, minDuration, maxDuration)
		task.wait(SEARCH_GAP)
		if err then
			warn(string.format("[AudioService] music search failed (%s): %s", keyword, err))
			return tracks, true
		end
		local taken = 0
		for _, f in found do
			if taken >= perKeyword or #tracks >= maxTracks then
				break
			end
			if not seen[f.Id] then
				seen[f.Id] = true
				table.insert(tracks, f)
				taken += 1
			end
		end
	end
	return tracks, false
end

local function findMusic(report: { string }, moodReport: { string }): number
	local seen: { [number]: boolean } = {}
	local count = 0
	local spec = AudioCatalog.Music
	if #AssetIds.Music == 0 then
		local tracks, failed = findTracks(spec.Keywords, spec.MinDuration, spec.MaxDuration, spec.PerKeyword, spec.MaxTracks, seen)
		if #tracks > 0 then
			folder:SetAttribute("Music", idList(tracks))
			count += #tracks
			for _, f in tracks do
				table.insert(report, string.format('\t"%d", -- %s', f.Id, f.Title))
			end
		end
		if failed then
			return count
		end
	end
	-- the radio stations, in a steady order
	local moods = {}
	for name in AudioCatalog.Moods do
		table.insert(moods, name)
	end
	table.sort(moods)
	local ms = AudioCatalog.MoodSearch
	for _, name in moods do
		local pinned = AssetIds.MusicByMood[name]
		if pinned and #pinned > 0 then
			continue
		end
		local tracks, failed = findTracks(AudioCatalog.Moods[name].Keywords, ms.MinDuration, ms.MaxDuration, ms.PerKeyword, ms.MaxTracks, seen)
		if #tracks > 0 then
			folder:SetAttribute("Music_" .. name, idList(tracks))
			count += #tracks
			local ids = {}
			for _, f in tracks do
				table.insert(ids, string.format('"%d"', f.Id))
			end
			table.insert(moodReport, string.format("\t%s = { %s }, -- %s", name, table.concat(ids, ", "), tracks[1].Title))
		end
		if failed then
			break
		end
	end
	return count
end

function AudioService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Audio"
	folder.Parent = ReplicatedStorage
	if not Config.Audio.Search then
		folder:SetAttribute("Ready", true)
		return
	end
	task.spawn(function()
		local effectLines: { string } = {}
		local musicLines: { string } = {}
		local moodLines: { string } = {}
		local effects = findEffects(effectLines)
		local music = findMusic(musicLines, moodLines)
		folder:SetAttribute("Ready", true)
		print(string.format("[AudioService] found %d sound effect(s) and %d music track(s) in the audio library", effects, music))
		if RunService:IsStudio() and (#effectLines > 0 or #musicLines > 0 or #moodLines > 0) then
			print("[AudioService] to keep these picks, paste into Shared/AssetIds.luau:\n"
				.. "AssetIds.Sounds = {\n" .. table.concat(effectLines, "\n") .. "\n}\n"
				.. "AssetIds.Music = {\n" .. table.concat(musicLines, "\n") .. "\n}\n"
				.. "AssetIds.MusicByMood = {\n" .. table.concat(moodLines, "\n") .. "\n}")
		end
	end)
end

return AudioService
