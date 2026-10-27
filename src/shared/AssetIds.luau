--[[
	Optional uploaded assets. The game runs without any of these: bikes, cars and the city are built
	from parts, and empty sound slots are filled by the server's audio-library search (Server/
	AudioService, terms in Shared/AudioCatalog). Paste an id (just the number, or "rbxassetid://...")
	to pin a sound; several ids separated by commas are picked at random per play.

	Never guess ids: only paste ones you have checked in Studio or the Creator Store.
]]

local AssetIds = {}

AssetIds.Sounds = {
	Motor = "", -- loop: hub/mid-drive motor whine (pitch follows speed)
	MotoMotor = "", -- loop: e-moto motor
	Wind = "", -- loop: wind at speed
	Freewheel = "", -- loop: freewheel ticking when coasting
	Brake = "", -- disc brake squeal
	Crash = "",
	Land = "",
	Bell = "", -- the H key
	Siren = "", -- loop: police siren
	Cash = "",
	LevelUp = "",
	Click = "",
	Busted = "",
	Escaped = "",
	CrateOpen = "",
	Charge = "",
	AmbientCity = "", -- loop: city ambience (downtown, the grids)
	AmbientSurf = "", -- loop: waves (the beaches and the baywalk)
	AmbientNature = "", -- loop: birds (the open land, the Everglades, by day)
	AmbientNight = "", -- loop: crickets and night insects
	Jet = "", -- loop: an airliner's engines (landing and taking off at the airport)
	Gulls = "", -- seagull calls over the beach
}

-- Background music ids (a shuffled playlist). Empty: the server searches the library.
AssetIds.Music = {} :: { string }

-- Game pass ids (Creator Dashboard -> your experience -> Monetization -> Passes). 0 = not set up yet;
-- the Shop shows those as "Coming soon".
AssetIds.GamePasses = {
	DoubleCash = 0,
	VIP = 0,
}

-- "123" -> "rbxassetid://123"; full urls pass through; "" -> nil
function AssetIds.Resolve(id: string?): string?
	if not id or id == "" then
		return nil
	end
	if string.find(id, "://", 1, true) then
		return id
	end
	return "rbxassetid://" .. id
end

-- Optional photo-scanned PBR textures (Creator Store "PBR texture" or "MaterialVariant" packs you
-- have checked, or your own uploads). Each set replaces one Roblox material everywhere it's used
-- (roads, pavements, brick, roofs...): Shared/Materials makes a MaterialVariant from it at startup.
-- Leave a set's ColorMap empty to keep Roblox's own 2022 material, which is already photo-based.
export type TextureSet = { ColorMap: string, NormalMap: string, RoughnessMap: string, MetalnessMap: string, StudsPerTile: number }
local function set(studsPerTile: number): TextureSet
	return { ColorMap = "", NormalMap = "", RoughnessMap = "", MetalnessMap = "", StudsPerTile = studsPerTile }
end
AssetIds.Materials = {
	Asphalt = set(24), -- roads
	Concrete = set(16), -- pavements, kerbs, walls
	Pavement = set(12),
	Brick = set(10),
	Plaster = set(16),
	RoofShingles = set(10),
	ClayRoofTiles = set(10),
	Grass = set(20),
	WoodPlanks = set(12), -- ramps, kickers
	Wood = set(12),
	Ground = set(20), -- dirt
	Metal = set(8),
} :: { [string]: TextureSet }

return AssetIds
