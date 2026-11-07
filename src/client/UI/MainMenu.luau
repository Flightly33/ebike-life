--[[
	MainMenu: the "Menus" button. Stats; Settings (HUD size and layout, speed units, key hints, the
	body cam's field of view, music and sound volume, graphics Ultra / Performance), each tried out
	as you change it and saved; Controls (rebind the keyboard: click a control, press a key; a key
	another control has swaps over; Shared/Controls); Tricks (every trick and control, with your
	keys and the controller's buttons); Teleports (not while wanted); and a short How to Play.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Controls = require(Shared.Controls)
local Economy = require(Shared.Economy)
local Layout = require(Shared.City.Layout)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)

local BikeCamera = require(script.Parent.Parent.BikeCamera)
local Graphics = require(script.Parent.Parent.Graphics)
local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Kit)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local MainMenu = {}

local New = Theme.New
local C = Theme.Colors
local R = Theme.Roles

-- ({Id} is the key the player has on that control: see keysText)
local HELP = {
	"Spawn a bike from My Rides, walk up to it and press E to get on. Space gets you off.",
	"Riding pays: the faster you go, the more you earn. Tricks multiply it.",
	"Wheelie: hold {Wheelie}. Throttle lifts the front, the brake ({Brake}) brings it down. Stay in the green.",
	"{OneHand} = one hand, {NoHands} = no hands. {Hop} = bunny hop. In the air, hold {Wheelie} to backflip and steer to spin.",
	"{Drift} + steer = drift (locks the rear brake; let go to straighten up). {Camera} = body cam (first person).",
	"Air tricks (hold the key in the air; you tuck back in on your own before landing): 1. {Superman} Superman, 2. {CanCan} Can-Can, 3. {NacNac} Nac-Nac, 4. {KneeKnocker} Knee Knocker, 5. {NoFooter} No-Footer, 6. {Barspin} Barspin (tap). Brake + {Wheelie} on the ground = stoppie.",
	"Wheelies and no-hands near cops fill their heat meter. A full meter is a wanted star and a chase.",
	"Lose the cops (get out of sight) to escape and get paid. Stop next to them and you're busted.",
	"Assist modes ({Mode} or 1-5): ECO goes far, TURBO goes hard. Customise them on the phone's Modes app.",
	"Batteries drain with the motor's power: an empty pack stops you dead, so charge at ⚡ stations.",
	"Buy new Flightly bikes at Flighty Mechanics; upgrade and paint them at Flighty Garage next door.",
	"Missions, delivery jobs, races, daily rewards and city events are on Play (K, the 🎯 tile, or the phone).",
	"Rebind any riding key in Menus > Controls.",
}

-- Every trick and control: what it is, the keyboard keys, the controller buttons
local CONTROLS: { { Section: string?, Name: string?, Keys: string?, Pad: string?, Note: string? } } = {
	{ Section = "Riding" },
	{ Name = "Gas / brake", Keys = "{Gas} / {Brake}", Pad = "RT / LT" },
	{ Name = "Steer", Keys = "{Left} / {Right}", Pad = "Left stick" },
	{ Name = "Front brake (stoppie)", Keys = "{Brake} + {Wheelie}", Pad = "LT + X", Note = "at speed: balance on the front wheel" },
	{ Name = "Assist mode", Keys = "{Mode} or 1-5", Pad = "RB" },
	{ Name = "Get off", Keys = "Space", Pad = "A" },
	{ Section = "Ground tricks" },
	{ Name = "Wheelie", Keys = "{Wheelie}", Pad = "X", Note = "throttle lifts, brake lowers; stay in the green" },
	{ Name = "One hand", Keys = "{OneHand}", Pad = "D-pad left" },
	{ Name = "No hands", Keys = "{NoHands}", Pad = "D-pad right" },
	{ Name = "Bunny hop", Keys = "{Hop} (hold, release)", Pad = "Y (hold, release)" },
	{ Name = "Drift", Keys = "{Drift} + steer", Pad = "B + steer", Note = "locks the rear; let go to straighten up" },
	{ Section = "Air tricks (hold in the air)" },
	{ Name = "1. Superman", Keys = "{Superman}", Pad = "D-pad up" },
	{ Name = "2. Can-Can", Keys = "{CanCan}", Pad = "B" },
	{ Name = "3. Nac-Nac", Keys = "{NacNac}", Pad = "LB" },
	{ Name = "4. Knee Knocker", Keys = "{KneeKnocker}", Pad = "D-pad down" },
	{ Name = "5. No-Footer", Keys = "{NoFooter}", Pad = "RB" },
	{ Name = "6. Barspin", Keys = "{Barspin} (tap)", Pad = "Y (tap)" },
	{ Name = "Backflip", Keys = "{Wheelie}", Pad = "X", Note = "pull back in the air; brake pushes the nose down" },
	{ Name = "Spin", Keys = "{Left} / {Right}", Pad = "Left stick" },
	{ Name = "Quarter pipe", Note = "ride up the face: you go up past the coping, turn round and come back down" },
	{ Name = "Loops and foam pits", Note = "ride into a loop at speed; the foam pit always catches you" },
	{ Section = "Camera" },
	{ Name = "Body cam", Keys = "{Camera}", Pad = "R3", Note = "field of view in Settings" },
	{ Name = "Video camera", Keys = "P", Pad = "", Note = "[ ] shots, , . zoom, ; letterbox" },
	{ Name = "Look around", Keys = "Right mouse drag", Pad = "Right stick" },
	{ Section = "Menus" },
	{ Name = "Phone (every menu, map, stats)", Keys = "` (backquote)", Pad = "", Note = "or the 📱 button" },
	{ Name = "Play (missions, jobs, races, daily)", Keys = "K", Pad = "", Note = "or the 🎯 button" },
	{ Name = "Full map", Keys = "J", Pad = "", Note = "or click the minimap; tap the map for a waypoint" },
	{ Name = "My Rides", Keys = "B", Pad = "" },
	{ Name = "Order at a counter", Keys = "E", Pad = "X", Note = "walk into any shop" },
}

-- Text with each {Id} written as the key the player has on it (Wheelie lists its extras too)
local function keysText(text: string): string
	local keys = State.Settings().Keys
	return (string.gsub(text, "{(%w+)}", function(id: string): string
		if not Controls.Get(id) then
			return id
		end
		local names = {}
		for _, name in Controls.Keys(keys, id) do
			local label = Controls.Label(name)
			-- (Shift and Ctrl: the right-hand ones go without saying)
			if not string.find(name, "^Right") or id ~= "Wheelie" then
				table.insert(names, label)
			end
		end
		return table.concat(names, " or ")
	end))
end

-- A copy of the settings to edit (the key table too)
local function copy(settings: Profile.Settings): Profile.Settings
	local out = table.clone(settings)
	out.Keys = table.clone(settings.Keys or {})
	return out
end

function MainMenu.new(gui: Instance, close: () -> ()): Panel.Panel
	local panel = Panel.new(gui, "Menus", "Menu", Vector2.new(720, 540), nil)
	local content = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -48), Position = UDim2.fromOffset(0, 48), Parent = panel.Body })
	local tab = "Stats"
	local draft: Profile.Settings? = nil
	local capturing: string? = nil -- the control waiting for a key
	local render: () -> ()

	local function setCapturing(id: string?)
		capturing = id
		if id then
			State.CapturingKey = true
		else
			-- (after every handler of this key press has run, so none of them acts on it)
			task.defer(function()
				if not capturing then
					State.CapturingKey = false
				end
			end)
		end
	end

	local function clear()
		setCapturing(nil)
		for _, child in content:GetChildren() do
			child:Destroy()
		end
	end

	-- the settings being edited: tried out at once (State.SetSettings), saved when `save` is set
	local function settingsDraft(): Profile.Settings
		local current = draft or copy(State.Settings())
		draft = current
		return current
	end
	local function apply(save: boolean)
		local current = settingsDraft()
		State.SetSettings(copy(current), save)
	end

	local function row(parent: Instance, label: string, value: string, order: number)
		local line = New("Frame", { BackgroundColor3 = if order % 2 == 0 then Color3.fromRGB(40, 40, 44) else Color3.fromRGB(36, 36, 40), Size = UDim2.new(1, 0, 0, 32), LayoutOrder = order, Parent = parent })
		Theme.Corner(line, 4)
		Theme.Label({ Text = label, Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.fromOffset(10, 0), TextSize = 17, Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = line })
		Theme.Label({ Text = value, Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.new(0.5, 0, 0, 0), TextSize = 17, Color = C.Cash, Align = Enum.TextXAlignment.Right, Stroke = 1, Parent = line })
	end

	local function stats()
		local data = State.Get()
		if not data then
			return
		end
		local list = Kit.List(content, nil, nil, 4)
		local s = data.Stats
		local units = State.Settings().Units
		local distance = if units == "mph" then string.format("%.1f mi", s.Distance / 1609.34) else string.format("%.1f km", s.Distance / 1000)
		row(list, "Level", tostring(data.Level), 1)
		row(list, "Cash", Economy.FormatCash(State.Cash()), 2)
		row(list, "Total earned", Economy.FormatCash(s.Earned), 3)
		row(list, "Distance ridden", distance, 4)
		row(list, "Best wheelie", string.format("%.1f s", s.BestWheelie), 5)
		row(list, "Longest air", string.format("%.1f s", s.LongestAir), 6)
		row(list, "Backflips", tostring(math.floor(s.Flips)), 7)
		row(list, "Police escapes", tostring(math.floor(s.Escapes)), 8)
		row(list, "Busted", tostring(math.floor(s.Busts)), 9)
		row(list, "Most stars", string.rep("★", math.floor(s.MaxStars)), 10)
		row(list, "Missions done", tostring(math.floor(s.Missions)), 11)
		row(list, "Deliveries", tostring(math.floor(s.Deliveries)), 12)
		row(list, "Races finished / won", string.format("%d / %d", math.floor(s.Races), math.floor(s.Wins)), 13)
		row(list, "Challenges claimed", tostring(math.floor(s.Challenges)), 14)
	end

	local function settings()
		if not State.Get() then
			return
		end
		local current = settingsDraft()
		local list = Kit.List(content, nil, nil, Theme.Space.S)
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		local function percent(v: number): string
			return string.format("%d%%", math.floor(v + 0.5))
		end

		Kit.Heading(list, "Display", nextOrder())
		Kit.Setting(list, "HUD size", "Bigger buttons and text, or more room to see", nextOrder(), function(holder)
			Kit.Slider(holder, 70, 130, 5, current.HudScale * 100, percent, function(v)
				current.HudScale = v / 100
				apply(true)
			end, 200, function(v)
				current.HudScale = v / 100
				apply(false)
			end)
		end)
		Kit.Setting(list, "HUD layout", "Compact: just Phone, Play and My Rides", nextOrder(), function(holder)
			Kit.Segmented(holder, { "Auto", "Full", "Compact" }, current.HudLayout, function(v)
				current.HudLayout = v
				apply(true)
			end, 96)
		end)
		Kit.Setting(list, "Speed units", nil, nextOrder(), function(holder)
			Kit.Segmented(holder, { "km/h", "mph" }, if current.Units == "mph" then "mph" else "km/h", function(v)
				current.Units = if v == "mph" then "mph" else "kmh"
				apply(true)
			end, 90)
		end)
		Kit.Setting(list, "Key hints while riding", "The keys along the bottom of the screen", nextOrder(), function(holder)
			Kit.Toggle(holder, current.Hints, function(on)
				current.Hints = on
				apply(true)
			end)
		end)

		Kit.Heading(list, "Camera", nextOrder())
		Kit.Setting(list, "Body cam field of view", "First person (" .. keysText("{Camera}") .. ")", nextOrder(), function(holder)
			Kit.Slider(holder, 60, 120, 1, current.Fov or 90, function(v)
				return string.format("%d°", v)
			end, function(v)
				current.Fov = v
				apply(true)
			end, 200, function(v)
				current.Fov = v
				BikeCamera.BodyCamFov = v
			end)
		end)

		Kit.Heading(list, "Sound", nextOrder())
		Kit.Setting(list, "Music", nil, nextOrder(), function(holder)
			Kit.Slider(holder, 0, 100, 5, current.Music * 100, percent, function(v)
				current.Music = v / 100
				apply(true)
			end, 200, function(v)
				current.Music = v / 100
				apply(false)
			end)
		end)
		Kit.Setting(list, "Sound effects", nil, nextOrder(), function(holder)
			Kit.Slider(holder, 0, 100, 5, current.Sounds * 100, percent, function(v)
				current.Sounds = v / 100
				apply(true)
			end, 200, function(v)
				current.Sounds = v / 100
				apply(false)
			end)
		end)

		Kit.Heading(list, "Graphics", nextOrder())
		local mode = if current.Graphics == "Ultra" or current.Graphics == "Performance" then current.Graphics else Graphics.Mode()
		Kit.Setting(list, "Graphics", "Performance: no shadows or clouds, less detail", nextOrder(), function(holder)
			Kit.Segmented(holder, { "Ultra", "Performance" }, mode, function(v)
				current.Graphics = v
				apply(true)
				Graphics.Apply()
			end, 120)
		end)
	end

	-- the keyboard controls: one row per control, its key on a button; click it and press a key
	local function controls()
		if not State.Get() then
			return
		end
		local current = settingsDraft()
		local list = Kit.List(content, nil, nil, 6)
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			local note = Theme.Label({ Text = "Controls are for keyboards. On a phone or tablet, ride with the on-screen buttons and the thumbstick.", Size = UDim2.new(1, -20, 0, 60), TextSize = Theme.Type.Body, Font = Theme.Body, Color = R.Muted, Wrapped = true, Stroke = 1, LayoutOrder = 1, Parent = list })
			note.TextYAlignment = Enum.TextYAlignment.Top
			return
		end
		local top = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 0, Parent = list })
		Theme.Label({ Text = "Click a control, then press the key you want (Esc cancels). A key another control has swaps over.", Size = UDim2.new(1, -190, 1, 0), TextSize = Theme.Type.Caption + 1, Font = Theme.Body, Color = R.Muted, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 1, Parent = top })
		Theme.Button({ Text = "Reset to defaults", Size = UDim2.fromOffset(176, 38), Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = C.Gray, TextSize = 16, Parent = top, OnClick = function()
			current.Keys = {}
			apply(true)
			Toasts.Message("Info", "Controls back to the defaults")
			task.defer(render)
		end })
		local order = 1
		for _, group in Controls.Groups do
			order += 1
			Kit.Heading(list, Controls.GroupNames[group] or group, order)
			for _, action in Controls.List do
				if action.Group ~= group then
					continue
				end
				order += 1
				-- the fixed extras that still work (the arrows, Ctrl), as the row's note
				local keys = Controls.Keys(current.Keys, action.Id)
				local extras = {}
				for i = 2, #keys do
					table.insert(extras, Controls.Label(keys[i]))
				end
				local note = if #extras > 0 then "also " .. table.concat(extras, ", ") else nil
				Kit.Setting(list, action.Label, note, order, function(holder)
					local key = keys[1]
					local changed = key ~= action.Default
					local button = Theme.Button({ Text = Controls.Label(key), Size = UDim2.fromOffset(150, 36), Color = if changed then R.Info else C.Gray, TextSize = 18, Parent = holder })
					button.Activated:Connect(function()
						if capturing then
							return
						end
						setCapturing(action.Id)
						button.Text = "Press a key…"
						button.BackgroundColor3 = R.Accent
					end)
				end)
			end
		end
	end

	-- the next key pressed while a control waits for one (keyboard only)
	local captureConn = UserInputService.InputBegan:Connect(function(input: InputObject)
		local id = capturing
		if not id or not panel.Frame.Visible or tab ~= "Controls" or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		setCapturing(nil)
		if input.KeyCode ~= Enum.KeyCode.Escape then
			local current = settingsDraft()
			local keys, why = Controls.Bind(current.Keys, id, input.KeyCode.Name)
			if keys then
				current.Keys = keys
				apply(true)
			else
				Toasts.Message("Error", why or "That key can't be used")
			end
		end
		task.defer(render)
	end)
	panel.Frame.Destroying:Connect(function()
		captureConn:Disconnect()
	end)

	local function tricks()
		local scroll = Kit.List(content, nil, nil, 4)
		for i, entry in CONTROLS do
			if entry.Section then
				Theme.Label({ Text = entry.Section, Size = UDim2.new(1, 0, 0, 30), TextSize = 20, Color = C.Orange, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = i, Parent = scroll })
			else
				local line = New("Frame", { BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(40, 40, 44) else Color3.fromRGB(36, 36, 40), Size = UDim2.new(1, -8, 0, if entry.Note then 46 else 30), LayoutOrder = i, Parent = scroll })
				Theme.Corner(line, 4)
				Theme.Label({ Text = entry.Name or "", Size = UDim2.new(0.4, -10, 0, 30), Position = UDim2.fromOffset(10, 0), TextSize = 16, Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = line })
				Theme.Label({ Text = keysText(entry.Keys or ""), Size = UDim2.new(0.3, -6, 0, 30), Position = UDim2.new(0.4, 0, 0, 0), TextSize = 16, Color = C.Cash, Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = line })
				Theme.Label({ Text = if entry.Pad and entry.Pad ~= "" then "🎮 " .. entry.Pad else "", Size = UDim2.new(0.3, -6, 0, 30), Position = UDim2.new(0.7, 0, 0, 0), TextSize = 15, Color = Color3.fromRGB(150, 200, 255), Align = Enum.TextXAlignment.Left, Stroke = 1, Parent = line })
				if entry.Note then
					Theme.Label({ Text = entry.Note, Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 28), TextSize = 13, Font = Theme.BodyRegular, Color = Color3.fromRGB(190, 190, 196), Align = Enum.TextXAlignment.Left, Stroke = 0, Parent = line })
				end
			end
		end
	end

	local function teleports()
		local grid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content })
		New("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 54), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		for i, place in Layout.Teleports do
			Theme.Button({ Text = place.Name, Color = if place.Id == "Dealership" then C.Orange else C.Blue, TextSize = 22, LayoutOrder = i, Parent = grid, OnClick = function()
				Remotes.Event("Teleport"):FireServer(place.Id)
				close()
			end })
		end
	end

	local function help()
		local scroll = Kit.List(content, nil, nil, 6)
		Theme.Label({ Text = "How to play " .. Config.GAME_NAME, Size = UDim2.new(1, 0, 0, 30), TextSize = 24, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = 0, Parent = scroll })
		for i, line in HELP do
			local label = Theme.Label({ Text = "• " .. keysText(line), Size = UDim2.new(1, -10, 0, 0), TextSize = 16, Font = Theme.BodyRegular, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 0, LayoutOrder = i, Parent = scroll })
			label.AutomaticSize = Enum.AutomaticSize.Y
		end
	end

	local tabs = Kit.Tabs(panel.Body, { "Stats", "Settings", "Controls", "Tricks", "Teleport", "Help" }, { Stats = "📈 Stats", Settings = "⚙️ Settings", Controls = "⌨️ Controls", Tricks = "🤸 Tricks", Teleport = "📍 Teleport", Help = "❔ Help" }, function(name)
		tab = name
		render()
	end, 106)

	render = function()
		tabs.Set(tab)
		clear()
		if tab == "Stats" then
			stats()
		elseif tab == "Settings" then
			settings()
		elseif tab == "Controls" then
			controls()
		elseif tab == "Tricks" then
			tricks()
		elseif tab == "Teleport" then
			teleports()
		else
			help()
		end
	end
	panel.Refresh = function()
		draft = nil
		render()
	end
	State.Changed:Connect(function()
		-- (the settings tabs keep their draft: the profile coming back is the save they just sent)
		if panel.Frame.Visible and tab ~= "Settings" and tab ~= "Controls" then
			render()
		end
	end)
	return panel
end

return MainMenu
