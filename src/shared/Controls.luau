--[[
	Controls: the keyboard controls a player can rebind (Menus > Controls), their default keys and
	the keys that stay fixed. A binding is a KeyCode name ("W", "LeftShift"); the save keeps only the
	ones changed from the default (Settings.Keys). Strings, not Enum values, so the server's
	clean-up (Shared/Profile) and the tests can check them without the engine.

	Each action has one key the player chooses. Some also keep fixed extras (the arrow keys steer,
	Ctrl wheelies as well as Shift) unless the player has given that key to another action.

	The gamepad and touch buttons aren't rebindable (Client/Input, UI/TouchControls).
]]

local Controls = {}

export type Action = {
	Id: string,
	Label: string,
	Group: string, -- "Ride", "Air" or "Bike": the heading it's listed under
	Default: string,
	Alt: { string }?, -- fixed extra keys
}

export type Keys = { [string]: string } -- action id -> KeyCode name (only the changed ones)

Controls.List = {
	{ Id = "Gas", Label = "Gas", Group = "Ride", Default = "W", Alt = { "Up" } },
	{ Id = "Brake", Label = "Brake / reverse", Group = "Ride", Default = "S", Alt = { "Down" } },
	{ Id = "Left", Label = "Steer left", Group = "Ride", Default = "A", Alt = { "Left" } },
	{ Id = "Right", Label = "Steer right", Group = "Ride", Default = "D", Alt = { "Right" } },
	{ Id = "Wheelie", Label = "Wheelie (with brake: stoppie)", Group = "Ride", Default = "LeftShift", Alt = { "RightShift", "LeftControl", "RightControl" } },
	{ Id = "Hop", Label = "Bunny hop (hold to preload)", Group = "Ride", Default = "Q" },
	{ Id = "Drift", Label = "Drift (locks the rear)", Group = "Ride", Default = "R" },
	{ Id = "OneHand", Label = "One hand", Group = "Ride", Default = "C" },
	{ Id = "NoHands", Label = "No hands", Group = "Ride", Default = "V" },
	{ Id = "Superman", Label = "Superman", Group = "Air", Default = "Z" },
	{ Id = "CanCan", Label = "Can-Can", Group = "Air", Default = "X" },
	{ Id = "NacNac", Label = "Nac-Nac", Group = "Air", Default = "T" },
	{ Id = "KneeKnocker", Label = "Knee Knocker", Group = "Air", Default = "G" },
	{ Id = "NoFooter", Label = "No-Footer", Group = "Air", Default = "N" },
	{ Id = "Barspin", Label = "Barspin (tap)", Group = "Air", Default = "Y" },
	{ Id = "Mode", Label = "Next ride mode", Group = "Bike", Default = "M" },
	{ Id = "Bell", Label = "Bell", Group = "Bike", Default = "H" },
	{ Id = "Camera", Label = "First person camera", Group = "Bike", Default = "F" },
} :: { Action }

Controls.Groups = { "Ride", "Air", "Bike" }
Controls.GroupNames = { Ride = "Riding", Air = "Air tricks", Bike = "Bike" } :: { [string]: string }

-- Keys the game or Roblox already uses for something else, and what (can't be bound)
Controls.Reserved = {
	B = "My Rides",
	E = "prompts (get on, order, buy)",
	J = "the map",
	K = "the Play hub",
	P = "the video camera",
	Space = "getting off",
	One = "ride mode 1",
	Two = "ride mode 2",
	Three = "ride mode 3",
	Four = "ride mode 4",
	Five = "ride mode 5",
	Escape = "Roblox's menu",
	Backquote = "the phone",
	Tab = "the player list",
	Slash = "chat",
	F2 = "the admin panel",
	LeftBracket = "the video camera",
	RightBracket = "the video camera",
	Comma = "the video camera",
	Period = "the video camera",
	Semicolon = "the video camera",
	Quote = "the video camera",
	Equals = "the video camera",
	Minus = "the video camera",
} :: { [string]: string }

-- Every key that can be bound, with how it's written on screen
local LABELS: { [string]: string } = {
	Up = "↑",
	Down = "↓",
	Left = "←",
	Right = "→",
	LeftShift = "Shift",
	RightShift = "R-Shift",
	LeftControl = "Ctrl",
	RightControl = "R-Ctrl",
	LeftAlt = "Alt",
	RightAlt = "R-Alt",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
	Zero = "0",
	Insert = "Ins",
	Delete = "Del",
	Home = "Home",
	End = "End",
	PageUp = "PgUp",
	PageDown = "PgDn",
	KeypadPlus = "Num +",
	KeypadMinus = "Num -",
	KeypadMultiply = "Num *",
	KeypadDivide = "Num /",
	KeypadPeriod = "Num .",
	KeypadEnter = "Num Enter",
}
for _, letter in string.split("ACDFGHILMNOQRSTUVWXYZ", "") do
	LABELS[letter] = letter
end
for i, digit in { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" } do
	LABELS["Keypad" .. digit] = "Num " .. tostring(i - 1)
end
for i = 3, 8 do
	LABELS["F" .. tostring(i)] = "F" .. tostring(i)
end

local byId: { [string]: Action } = {}
for _, action in Controls.List do
	byId[action.Id] = action
end

function Controls.Get(id: string): Action?
	return byId[id]
end

-- A key a player may bind (a KeyCode name on the list, not reserved)
function Controls.ValidKey(name: string): boolean
	return LABELS[name] ~= nil and Controls.Reserved[name] == nil
end

-- How a key is written on the HUD and in the menu ("Shift", "↑", "Num 4")
function Controls.Label(name: string): string
	return LABELS[name] or name
end

-- The key the player has on this action
function Controls.Key(keys: Keys?, id: string): string
	local chosen = keys and keys[id]
	if chosen and Controls.ValidKey(chosen) then
		return chosen
	end
	local action = byId[id]
	return if action then action.Default else ""
end

-- Every key that does this action: the chosen one plus the fixed extras no other action has taken
function Controls.Keys(keys: Keys?, id: string): { string }
	local primary = Controls.Key(keys, id)
	local out = { primary }
	local action = byId[id]
	if action and action.Alt then
		local taken: { [string]: boolean } = {}
		for _, other in Controls.List do
			taken[Controls.Key(keys, other.Id)] = true
		end
		for _, alt in action.Alt do
			if not taken[alt] and not table.find(out, alt) then
				table.insert(out, alt)
			end
		end
	end
	return out
end

-- Bind `key` to an action. The action that had it gets this one's old key, so nothing is left
-- without a key. Returns the new Keys (only what differs from the defaults), or nil and why not.
function Controls.Bind(keys: Keys?, id: string, key: string): (Keys?, string?)
	local action = byId[id]
	if not action then
		return nil, "No such control"
	end
	if not Controls.ValidKey(key) then
		local use = Controls.Reserved[key]
		return nil, if use then string.format("%s is used for %s", key, use) else "That key can't be used"
	end
	local resolved: { [string]: string } = {}
	for _, a in Controls.List do
		resolved[a.Id] = Controls.Key(keys, a.Id)
	end
	local old = resolved[id]
	for otherId, otherKey in resolved do
		if otherId ~= id and otherKey == key then
			resolved[otherId] = old
		end
	end
	resolved[id] = key
	local out: Keys = {}
	for _, a in Controls.List do
		if resolved[a.Id] ~= a.Default then
			out[a.Id] = resolved[a.Id]
		end
	end
	return out, nil
end

-- The action a key does (the chosen key or a fixed extra), if any
function Controls.ActionOf(keys: Keys?, key: string): string?
	for _, a in Controls.List do
		if table.find(Controls.Keys(keys, a.Id), key) then
			return a.Id
		end
	end
	return nil
end

return Controls
