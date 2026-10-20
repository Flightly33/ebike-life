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

return AssetIds
