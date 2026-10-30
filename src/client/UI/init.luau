--[[
	UI: builds the HUD and the menus and wires them to the game: server notices (Notify, Payout,
	Police remotes), the local ride (BikeController) and the dealership / tuning prompts in the city.
	One menu panel is open at a time; opening the same one again (or Esc) closes it.
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
local Panel = require(script.Panel)
local Rides = require(script.Rides)
local Store = require(script.Store)
local Theme = require(script.Theme)
local Toasts = require(script.Toasts)
local TouchControls = require(script.TouchControls)
local TrickHud = require(script.TrickHud)
local Tuning = require(script.Tuning)
local WantedHud = require(script.WantedHud)

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

function UI.Open(name: string)
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

local function screenScale(scale: UIScale)
	local function update()
		local size = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(size.Y / 750, size.X / 1250), 0.65, 1.5)
	end
	update()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
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
	screenScale(scale)

	Hud.Init(gui, UI.Open)
	Toasts.Init(gui, Hud.Minimap :: Frame)
	TrickHud.Init(gui)
	WantedHud.Init(gui)
	OrderMenu.InitHud(gui)
	TouchControls.Init(gui)

	-- Menus (a second ScreenGui above the HUD)
	local menus = Theme.New("ScreenGui", { Name = "EbikeMenus", ResetOnSpawn = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
	local menuScale = Theme.New("UIScale", { Parent = menus })
	screenScale(menuScale)
	panels.MyRides = Rides.MyRides(menus, close, function()
		UI.Open("Dealership")
	end)
	panels.Dealership = Rides.Dealership(menus, close)
	panels.Tuning = Tuning.new(menus)
	panels.Crates = Store.Crates(menus)
	panels.Shop = Store.Shop(menus)
	panels.Order = OrderMenu.new(menus)
	panels.Menus = MainMenu.new(menus, close)
	panels.Admin = AdminPanel.new(menus, function()
		UI.Open("Admin")
	end)
	for _, panel in panels do
		panel.OnClose = close
	end
	GraphicsPrompt.Init(menus)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape and openName then
			close()
		elseif not processed and input.KeyCode == Enum.KeyCode.B and not UserInputService:GetFocusedTextBox() then
			UI.Open("MyRides")
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
		if prompt.Name == "DealershipPrompt" then
			UI.Open("Dealership")
		elseif prompt.Name == "TuningPrompt" then
			UI.Open("Tuning")
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
		Toasts.Message(kind, text)
		if kind == "Level" then
			Sound.Play("LevelUp")
		elseif kind == "Cash" then
			Sound.Play("Cash")
		end
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
	State.Changed:Connect(function()
		Hud.SetRiding(BikeController.Active)
		Sound.SetVolume("SFX", State.Settings().Sounds)
		BikeCamera.BodyCamFov = State.Settings().Fov or 90
	end)

	RunService.RenderStepped:Connect(function(dt)
		Hud.Update(dt)
		TrickHud.Update(dt)
		WantedHud.Update()
	end)

	-- Welcome
	task.delay(3, function()
		Toasts.Message("Info", "Welcome to Flighty Mechanics! Open My Rides (B) and spawn your bike.")
	end)
end

return UI
