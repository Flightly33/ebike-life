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

-- Billboard images (uploaded decals or images: Creator Dashboard -> Development Items -> Decals).
-- Each entry is an ad of your own that the billboards, rooftop boards, LED screens and bus shelter
-- panels show in turn with the built-in ones (Shared/Ads). `Wide` images (about 3:1) suit the
-- billboards and screens, `Tall` ones (about 2:3) the bus shelter panels; leave the other "".
-- Example: { Wide = "1234567890", Tall = "", Name = "My Brand" }
AssetIds.Billboards = {} :: { { Wide: string, Tall: string, Name: string } }

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

-- (PBR materials and textured trees come from the realism pack instead: blender/textures.py,
-- imported with Vehicles.fbx and set up in Studio by tools/studio/SetupRealism.luau. A
-- MaterialVariant's texture maps can't be set by game scripts, so there are no material ids here.)

return AssetIds
