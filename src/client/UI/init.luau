--[[
	UI: builds the HUD and the menus and wires them to the game: server notices (Notify, Payout,
	Police, Message remotes), the local ride (BikeController) and the dealership / tuning prompts in
	the city. One menu panel is open at a time; opening the same one again (or Esc) closes it. It
	counts what's waiting for the badges (rewards to claim, achievements, unread texts) and sizes the
	HUD (the screen's own fit times the player's HUD size setting) and the menus (fitted to the space
	under Roblox's top bar).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dailies = require(Shared.Dailies)
local Missions = require(Shared.Missions)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)

local BikeCamera = require(script.Parent.BikeCamera)
local BikeController = require(script.Parent.BikeController)
local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)
local Hud = require(script.Hud)
local MainMenu = require(script.MainMenu)
local AdminPanel = require(script.AdminPanel)
local GraphicsPrompt = require(script.GraphicsPrompt)
local OrderMenu = require(script.OrderMenu)
local MapScreen = require(script.MapScreen)
local Phone = require(script.Phone)
local StatsScreen = require(script.StatsScreen)
local Panel = require(script.Panel)
local Rides = require(script.Rides)
local Store = require(script.Store)
local Theme = require(script.Theme)
local Toasts = require(script.Toasts)
local TouchControls = require(script.TouchControls)
local TrickHud = require(script.TrickHud)
local Tuning = require(script.Tuning)
local Garage = require(script.Garage)
local WantedHud = require(script.WantedHud)
local Objective = require(script.Objective)
local Activities = require(script.Activities)
local Inbox = require(script.Inbox)
local GearShop = require(script.GearShop)
local Route = require(script.Route)

local UI = {}

local panels: { [string]: Panel.Panel } = {}
local openName: string? = nil

local function close()
	if openName then
		local panel = panels[openName]
		if panel then
			panel.Frame.Visible = false
		end
		openName = nil
	end
end

-- what the regulars say when you talk to them (Server/Regulars)
local REGULAR_LINES: { [string]: string } = {
	Nina = "Need something to do? Here's what I've got.",
	Marco = "Parcels don't deliver themselves.",
	Jet = "Ready to show me what you've got?",
	Reyes = "Keep it clean out there. Or don't: I'll be waiting.",
}

-- A "!" over each regular with a mission ready for you
local function markRegulars()
	local folder = Workspace:FindFirstChild("Regulars")
	local data = State.Get()
	if not folder or not data then
		return
	end
	for _, model in folder:GetChildren() do
		local tag = model:FindFirstChild("NameTag")
		local mark = tag and tag:FindFirstChild("Ready")
		if mark and mark:IsA("TextLabel") then
			local ready = false
			for _, mission in Missions.List do
				if mission.Giver == model.Name and Missions.Status(mission, data.Missions, data.Level) == "Ready" then
					ready = true
					break
				end
			end
			mark.Visible = ready
		end
	end
end

-- the Play hub's tabs, which UI.Open takes as names too (the Ranks app, the event pill)
local PLAY_TABS = { Missions = true, Jobs = true, Races = true, Daily = true, Events = true, Ranks = true }

function UI.Open(name: string)
	if PLAY_TABS[name] then
		Activities.Show(name)
		name = "Activities"
	end
	-- tuning, parts and paint happen at Flighty Garage
	if name == "Tuning" then
		if Garage.Near() then
			name = "Garage"
		else
			Toasts.Message("Info", "🔧 Tuning, parts and paint are done at Flighty Garage, next to the dealership")
			name = "Map"
		end
	end
	if openName == name then
		close()
		return
	end
	close()
	local panel = panels[name]
	if not panel then
		return
	end
	openName = name
	local refresh = panel.Refresh
	if refresh then
		refresh()
	end
	panel.Frame.Visible = true
	Theme.Pop(panel.Frame)
end

-- What's waiting, by the panel that shows it: rewards to claim (Play), achievements (Stats), texts
local function counts(): { [string]: number }
	local data = State.Get()
	return {
		Activities = if data then Dailies.Claimable(data.Daily, Workspace:GetServerTimeNow()) else 0,
		Stats = StatsScreen.Unclaimed(),
		Messages = Inbox.Unread(),
	}
end

-- Fit a ScreenGui's UIScale to the screen (1250 x 750 design units). The HUD never goes below 0.65
-- (its compact layout makes the room on a phone) and is times the player's HUD size; the menus fit
-- the space under Roblox's top bar whatever it takes, so a panel never runs off a phone's screen.
-- `after` runs once the scale changes (the HUD's layout depends on the room left).
local function screenScale(scale: UIScale, hud: boolean, after: (() -> ())?)
	local gui = scale.Parent :: ScreenGui
	local function update()
		local fit
		if hud then
			local size = Workspace.CurrentCamera.ViewportSize
			fit = math.clamp(math.min(size.Y / 750, size.X / 1250), 0.65, 1.5) * math.clamp(State.Settings().HudScale or 1, 0.7, 1.3)
		else
			local size = gui.AbsoluteSize
			if size.Y <= 0 then
				size = Workspace.CurrentCamera.ViewportSize
			end
			fit = math.clamp(math.min(size.Y / 750, size.X / 1250), 0.4, 1.5)
		end
		if math.abs(scale.Scale - fit) > 1e-4 then
			scale.Scale = fit
		end
		if after then
			after()
		end
	end
	update()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	if hud then
		State.SettingsChanged:Connect(update)
	end
end

function UI.Init()
	local player = Players.LocalPlayer
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	local gui = Theme.New("ScreenGui", {
		Name = "EbikeHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local scale = Theme.New("UIScale", { Parent = gui })

	Hud.Init(gui, UI.Open)
	screenScale(scale, true, function()
		Hud.ApplyLayout()
		TouchControls.SetCompact(Hud.Compact())
	end)
	Toasts.Init(gui, Hud.Minimap :: Frame)
	Inbox.InitHud(gui, UI.Open)
	Objective.Init(gui)
	Route.Init()
	Route.OnArrive(function()
		Toasts.Message("Info", "📍 You're at your waypoint")
		Sound.Play("Cash", nil, 1.5, 0.4)
	end)
	TrickHud.Init(gui)
	WantedHud.Init(gui)
	OrderMenu.InitHud(gui)
	TouchControls.Init(gui)
	TouchControls.SetCompact(Hud.Compact())

	-- Menus (a second ScreenGui above the HUD)
	local menus = Theme.New("ScreenGui", { Name = "EbikeMenus", ResetOnSpawn = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	local menuScale = Theme.New("UIScale", { Parent = menus })
	screenScale(menuScale, false)
	panels.MyRides = Rides.MyRides(menus, close, function()
		UI.Open("Dealership")
	end)
	panels.Dealership = Rides.Dealership(menus, close)
	panels.RideModes = Tuning.new(menus)
	panels.Garage = Garage.new(menus, close)
	panels.Crates = Store.Crates(menus)
	panels.Shop = Store.Shop(menus)
	panels.Order = OrderMenu.new(menus)
	panels.Map = MapScreen.new(menus, close)
	panels.Stats = StatsScreen.new(menus)
	panels.Activities = Activities.new(menus)
	panels.Messages = Inbox.new(menus)
	panels.Gear = GearShop.new(menus)
	panels.Phone = Phone.new(menus, UI.Open, close, counts)
	panels.Menus = MainMenu.new(menus, close)
	panels.Admin = AdminPanel.new(menus, function()
		UI.Open("Admin")
	end)
	for _, panel in panels do
		panel.OnClose = close
	end
	GraphicsPrompt.Init(menus)

	UserInputService.InputBegan:Connect(function(input, processed)
		if State.CapturingKey then
			return -- (Menus > Controls takes this key)
		end
		if input.KeyCode == Enum.KeyCode.Escape and openName then
			close()
		elseif not processed and input.KeyCode == Enum.KeyCode.B and not UserInputService:GetFocusedTextBox() then
			UI.Open("MyRides")
		elseif not processed and input.KeyCode == Enum.KeyCode.Backquote and not UserInputService:GetFocusedTextBox() then
			UI.Open("Phone")
		elseif not processed and input.KeyCode == Enum.KeyCode.J and not UserInputService:GetFocusedTextBox() then
			UI.Open("Map")
		elseif not processed and input.KeyCode == Enum.KeyCode.K and not UserInputService:GetFocusedTextBox() then
			UI.Open("Activities")
		elseif not processed and input.KeyCode == Enum.KeyCode.F2 and player:GetAttribute("Admin") == true then
			UI.Open("Admin")
		end
	end)
	GuiService.MenuOpened:Connect(close)

	-- Prompts in the city that open menus
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player then
			return
		end
		if prompt.Name == "TalkPrompt" then
			-- one of the regulars: their line, and their missions on the phone
			local attribute = prompt:GetAttribute("Giver")
			local giver = if type(attribute) == "string" then attribute else ""
			local info = Missions.Givers[giver]
			local line = REGULAR_LINES[giver]
			if info and line then
				Toasts.Message("Info", string.format("%s %s: \"%s\"", info.Icon, giver, line))
			end
			UI.Open("Missions")
		elseif prompt.Name == "DealershipPrompt" then
			UI.Open("Dealership")
		elseif prompt.Name == "TuningPrompt" then
			UI.Open("Garage")
		elseif prompt.Name == "GearPrompt" then
			-- the gear rack in Flighty Bike Gear at the courier depot
			if openName ~= "Gear" then
				UI.Open("Gear")
			end
		elseif prompt.Name == "RacePrompt" then
			-- the race desk at the Race Plaza
			if openName ~= "Activities" then
				UI.Open("Races")
			else
				Activities.Show("Races")
			end
		elseif prompt.Name == "OrderPrompt" then
			local counter = prompt.Parent
			if counter and counter:IsA("BasePart") then
				OrderMenu.SetCounter(counter)
				if openName == "Order" then
					close()
				end
				UI.Open("Order")
			end
		end
	end)

	-- Server notices
	Remotes.Event("Notify").OnClientEvent:Connect(function(kind: any, text: any)
		if type(kind) ~= "string" or type(text) ~= "string" then
			return
		end
		if kind == "Event" then
			-- a city event starting: a banner as well as the message, and it's kept in Messages
			Toasts.Banner("EVENT!", text, Theme.Colors.Gold, 4)
			Sound.Play("LevelUp")
			Inbox.Add("Events", text)
		end
		Toasts.Message(if kind == "Event" then "Cash" else kind, text)
		if kind == "Level" then
			Sound.Play("LevelUp")
		elseif kind == "Cash" then
			Sound.Play("Cash")
		end
	end)
	-- Texts from the regulars and the city: the phone's Messages (a card slides in on the HUD)
	Remotes.Event("Message").OnClientEvent:Connect(function(from: any, text: any)
		if type(from) ~= "string" or type(text) ~= "string" then
			return
		end
		Inbox.Add(from, text)
		Sound.Play("Cash", nil, 1.8, 0.35)
	end)
	Remotes.Event("Payout").OnClientEvent:Connect(function(amount: any, label: any)
		if type(amount) ~= "number" then
			return
		end
		if type(label) == "string" and label ~= "" then
			Toasts.TrickPop(amount, label)
			Sound.Play("Cash", nil, 1.1, 0.7)
		else
			Toasts.CashPop(amount)
		end
	end)
	Remotes.Event("Police").OnClientEvent:Connect(function(kind: any, data: any)
		local info = if type(data) == "table" then data else {}
		if kind == "Wanted" then
			local stars = tonumber(info.Stars) or 1
			if stars <= 0 then
				return
			end
			Toasts.Banner(string.rep("★", stars), if stars == 1 then "The cops saw that! Lose them!" else "More cops are coming!", Color3.fromRGB(255, 255, 255), 2)
		elseif kind == "Busted" then
			Toasts.Banner("BUSTED!", "Fined " .. Economy.FormatCash(tonumber(info.Fine) or 0), Color3.fromRGB(255, 70, 60), 3.5)
			Sound.Play("Busted")
		elseif kind == "Escaped" then
			Toasts.Banner("ESCAPED!", "+" .. Economy.FormatCash(tonumber(info.Reward) or 0) .. string.format("  (%.0fs chase)", tonumber(info.Time) or 0), Theme.Colors.Cash, 3.5)
			Sound.Play("Escaped")
		elseif kind == "Spotted" then
			Toasts.Message("Police", "👮 A cop is watching. Wheelies here will start a chase!")
		end
	end)

	-- The local ride
	BikeController.Started:Connect(function()
		Hud.SetRiding(true)
		close()
	end)
	BikeController.Stopped:Connect(function()
		Hud.SetRiding(false)
	end)
	BikeController.Event:Connect(function(event: any)
		if event.Kind == "Spiked" then
			Toasts.Message("Police", "Spike strip! Your tyre's flat for a while.")
		elseif event.Kind == "Splash" then
			Toasts.Message("Error", "Splash! Wade back to the shore")
		elseif event.Kind == "BatteryEmpty" then
			Toasts.Message("Error", "Battery empty! Push it to a ⚡ charging station")
		elseif event.Kind == "Flip" then
			Toasts.Banner("BACKFLIP!", nil, Theme.Colors.Orange, 1.2)
		end
	end)
	State.SettingsChanged:Connect(function()
		Hud.SetRiding(BikeController.Active)
		Sound.SetVolume("SFX", State.Settings().Sounds)
		BikeCamera.BodyCamFov = State.Settings().Fov or 90
	end)

	-- the badges: what's waiting on Play and on the phone
	local function badges()
		local c = counts()
		Hud.SetBadges(c.Activities, c.Activities + c.Stats + c.Messages)
	end
	State.Changed:Connect(badges)
	State.Changed:Connect(markRegulars)
	Inbox.Changed:Connect(badges)
	local sinceBadges = 0

	RunService.RenderStepped:Connect(function(dt)
		-- (a new day brings a new streak reward without a profile change)
		sinceBadges += dt
		if sinceBadges >= 1 then
			sinceBadges = 0
			badges()
			markRegulars()
		end
		Hud.Update(dt)
		TrickHud.Update(dt)
		WantedHud.Update()
		Objective.Update()
	end)

	-- Welcome
	task.delay(3, function()
		Toasts.Message("Info", "Welcome to Flighty Mechanics! Open My Rides (B) and spawn your bike.")
	end)
end

return UI
