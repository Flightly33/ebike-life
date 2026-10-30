--[[
	OrderMenu: a shop counter's menu (Shared/Menus), opened by its Order prompt. Item cards show the
	item turning in 3D (Shared/Models/ItemModel in a ViewportFrame), its effects as chips and its
	price; tabs filter by category; the side column shows the shop, the greeting, your cash and the
	boosts you have running. Buying goes through the Order remote (OrderService checks you're at
	the counter and applies the item).

	OrderMenu.InitHud puts the running boosts on the HUD (top middle): a chip per boost with its
	multiplier and a draining bar, from the player's `BuffCash` / `BuffXp` attributes and their
	`...Until` server times.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local ItemModel = require(Shared.Models.ItemModel)
local Menus = require(Shared.Menus)
local Remotes = require(Shared.Remotes)

local Sound = require(script.Parent.Parent.Sound)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local OrderMenu = {}

local New = Theme.New
local C = Theme.Colors

local counter: BasePart? = nil
local spinning: { { Camera: Camera, Center: Vector3, Dist: number, Phase: number } } = {}

function OrderMenu.SetCounter(part: BasePart)
	counter = part
end

local function timeLeft(untilAt: number): string
	local s = math.max(0, math.floor(untilAt - Workspace:GetServerTimeNow()))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- A turning 3D icon of an item
local function itemView(parent: Instance, id: string, size: UDim2, position: UDim2)
	local vf = New("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = size,
		Position = position,
		Ambient = Color3.fromRGB(170, 170, 176),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.5),
		Parent = parent,
	})
	local model = ItemModel.Build(id, 10)
	model.Parent = vf
	local cf, extents = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = vf
	vf.CurrentCamera = camera
	local radius = extents.Magnitude / 2
	local dist = radius / math.tan(math.rad(15)) * 1.05
	table.insert(spinning, { Camera = camera, Center = cf.Position, Dist = dist, Phase = math.random() * 6 })
end

local function chip(parent: Instance, text: string, color: Color3, order: number)
	local f = New("Frame", { BackgroundColor3 = color, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), LayoutOrder = order, Parent = parent })
	Theme.Corner(f, 11)
	New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = f })
	Theme.Label({ Text = text, Size = UDim2.fromOffset(0, 22), TextSize = 14, Font = Theme.Body, Stroke = 0, Color = C.Text, Parent = f }).AutomaticSize = Enum.AutomaticSize.X
end

function OrderMenu.new(gui: Instance): Panel.Panel
	local panel = Panel.new(gui, "Order", "Order", Vector2.new(1000, 600), nil)
	local side = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(0, 230, 1, 0), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = panel.Body })
	Theme.Corner(side, 8)
	New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 12), Parent = side })
	local sideList = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = side })
	Theme.List(sideList, Enum.FillDirection.Vertical, 8)
	local greet = Theme.Label({ Text = "", Size = UDim2.new(1, 0, 0, 70), TextSize = 20, Wrapped = true, Stroke = 2, LayoutOrder = 1, Parent = sideList })
	local cash = Theme.Label({ Text = "", Size = UDim2.new(1, 0, 0, 32), TextSize = 28, Color = C.Cash, StrokeColor = C.CashDark, Stroke = 2, LayoutOrder = 2, Parent = sideList })
	Theme.Label({ Text = "Your boosts", Size = UDim2.new(1, 0, 0, 24), TextSize = 20, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = 3, Parent = sideList })
	local boosts = Theme.Label({ Text = "", Size = UDim2.new(1, 0, 0, 90), TextSize = 17, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 0, LayoutOrder = 4, Parent = sideList })
	Theme.Label({ Text = "Boosts of a kind don't add up: the best one counts. They multiply a 2x Cash boost.", Size = UDim2.new(1, 0, 0, 70), TextSize = 14, Font = Theme.BodyRegular, Color = C.SubText, Wrapped = true, Stroke = 0, LayoutOrder = 5, Parent = sideList })

	local main = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -242, 1, 0), Parent = panel.Body })
	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = main })
	Theme.List(tabs, Enum.FillDirection.Horizontal, 8)
	local gridHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50), Parent = main })
	local grid = Panel.Grid(gridHolder, Vector2.new(236, 236), 3)

	local player = Players.LocalPlayer
	local function refreshSide()
		cash.Text = Economy.FormatCash((player:GetAttribute("Cash") :: number?) or 0)
		local lines = {}
		local cashBoost = player:GetAttribute("BuffCash")
		local cashUntil = player:GetAttribute("BuffCashUntil")
		if type(cashBoost) == "number" and type(cashUntil) == "number" then
			table.insert(lines, string.format("💵 %gx cash  %s", cashBoost, timeLeft(cashUntil)))
		end
		local xpBoost = player:GetAttribute("BuffXp")
		local xpUntil = player:GetAttribute("BuffXpUntil")
		if type(xpBoost) == "number" and type(xpUntil) == "number" then
			table.insert(lines, string.format("⭐ %gx XP  %s", xpBoost, timeLeft(xpUntil)))
		end
		boosts.Text = if #lines > 0 then table.concat(lines, "\n") else "None yet. Grab a bite!"
	end

	local function fill(theme: Menus.Theme, category: string?)
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(spinning)
		for i, it in theme.Items do
			if category == nil or it.Category == category then
				local card = New("Frame", { BackgroundColor3 = C.Tile, LayoutOrder = i, Parent = grid })
				Theme.Corner(card, 8)
				Theme.Stroke(card, Color3.fromRGB(16, 16, 18), 2)
				New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 196)), Parent = card })
				Theme.Glow(card, if it.Heat then C.Blue elseif it.Charge then C.Green elseif it.Xp and not it.Cash then C.Purple else C.Gold, UDim2.fromOffset(120, 120), UDim2.new(0.5, 0, 0, 62))
				itemView(card, it.Id, UDim2.new(1, 0, 0, 110), UDim2.fromOffset(0, 6))
				Theme.Label({ Text = it.Icon .. " " .. it.Name, Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 116), TextSize = 21, Stroke = 2, Parent = card })
				local chips = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 146), Parent = card })
				Theme.List(chips, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center)
				if it.Cash then
					chip(chips, string.format("💵 %gx", it.Cash), C.GreenDark, 1)
				end
				if it.Xp then
					chip(chips, string.format("⭐ %gx XP", it.Xp), Color3.fromRGB(110, 40, 170), 2)
				end
				if it.Minutes then
					chip(chips, string.format("⏱ %dm", it.Minutes), C.Gray, 3)
				end
				if it.Charge then
					chip(chips, "🔋 Full charge", C.GreenDark, 4)
				end
				if it.Heat then
					chip(chips, string.format("🚓 -%d★", it.Heat), Color3.fromRGB(30, 80, 170), 5)
				end
				local affordable = ((player:GetAttribute("Cash") :: number?) or 0) >= it.Price
				Theme.Button({
					Text = "Buy " .. Economy.FormatCash(it.Price),
					Size = UDim2.new(1, -16, 0, 42),
					Position = UDim2.new(0, 8, 1, -50),
					Color = if affordable then C.Green else C.Gray,
					TextSize = 22,
					Parent = card,
					OnClick = function()
						local at = counter
						if not at then
							return
						end
						local ok, message = Remotes.Function("Order"):InvokeServer(at, it.Id)
						Toasts.Message(if ok then "Cash" else "Error", tostring(message))
						if ok then
							Sound.Play("Cash")
							Theme.Pop(card)
						end
						refreshSide()
					end,
				})
			end
		end
	end

	local currentTheme: Menus.Theme? = nil
	local function buildTabs(theme: Menus.Theme)
		for _, child in tabs:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local cats: { string } = {}
		for _, it in theme.Items do
			if not table.find(cats, it.Category) then
				table.insert(cats, it.Category)
			end
		end
		local function tab(label: string, category: string?, order: number)
			Theme.Button({ Text = label, Size = UDim2.fromOffset(120, 36), TextSize = 18, Color = C.Card, LayoutOrder = order, Parent = tabs, OnClick = function()
				fill(theme, category)
			end })
		end
		tab("All", nil, 0)
		local icons = { Food = "🍔 Food", Drinks = "🥤 Drinks", Treats = "🍩 Treats", Gear = "🧢 Gear" }
		for i, c in cats do
			tab(icons[c] or c, c, i)
		end
	end

	panel.Refresh = function()
		local at = counter
		if not at then
			return
		end
		local shopName = at:GetAttribute("ShopName")
		local themeId = at:GetAttribute("Menu")
		local theme = if type(themeId) == "string" then Menus.Themes[themeId] else nil
		if not theme then
			return
		end
		currentTheme = theme
		panel.Title.Text = if type(shopName) == "string" then shopName else theme.Title
		greet.Text = "“" .. theme.Greeting .. "”"
		buildTabs(theme)
		fill(theme, nil)
		refreshSide()
	end

	local sinceSide = 0
	RunService.RenderStepped:Connect(function(dt)
		if not panel.Frame.Visible then
			return
		end
		local t = os.clock()
		for _, s in spinning do
			local a = t * 0.8 + s.Phase
			s.Camera.CFrame = CFrame.lookAt(s.Center + Vector3.new(math.sin(a) * s.Dist, s.Dist * 0.45, math.cos(a) * s.Dist), s.Center)
		end
		sinceSide += dt
		if sinceSide > 0.5 and currentTheme then
			sinceSide = 0
			refreshSide()
		end
	end)
	return panel
end

-- The running boosts on the HUD
function OrderMenu.InitHud(gui: Instance)
	local player = Players.LocalPlayer
	local bar = New("Frame", { Name = "Boosts", BackgroundTransparency = 1, Size = UDim2.fromOffset(420, 34), Position = UDim2.new(0.5, 0, 0, 64), AnchorPoint = Vector2.new(0.5, 0), Parent = gui })
	Theme.List(bar, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	type Chip = { Frame: Frame, Label: TextLabel, Fill: Frame, Total: number }
	local chips: { [string]: Chip } = {}
	local function make(kind: string, icon: string, color: Color3): Chip
		local f = New("Frame", { BackgroundColor3 = C.Tile, Size = UDim2.fromOffset(150, 32), Visible = false, Parent = bar })
		Theme.Corner(f, 8)
		Theme.Stroke(f, color, 2)
		local fillBar = New("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.55, Size = UDim2.fromScale(1, 1), Parent = f })
		Theme.Corner(fillBar, 8)
		local label = Theme.Label({ Text = icon, Size = UDim2.fromScale(1, 1), TextSize = 18, Stroke = 2, Parent = f })
		return { Frame = f, Label = label, Fill = fillBar, Total = 60 }
	end
	chips.Cash = make("Cash", "💵", C.Cash)
	chips.Xp = make("Xp", "⭐", C.Purple)
	local last: { [string]: number } = {}
	RunService.Heartbeat:Connect(function()
		for kind, c in chips do
			local factor = player:GetAttribute("Buff" .. kind)
			local untilAt = player:GetAttribute("Buff" .. kind .. "Until")
			if type(factor) == "number" and type(untilAt) == "number" then
				local left = untilAt - Workspace:GetServerTimeNow()
				if last[kind] ~= untilAt then
					last[kind] = untilAt
					c.Total = math.max(left, 1)
					Theme.Pop(c.Frame)
				end
				c.Frame.Visible = left > 0
				c.Fill.Size = UDim2.fromScale(math.clamp(left / c.Total, 0, 1), 1)
				c.Label.Text = string.format("%s %gx%s  %s", if kind == "Cash" then "💵" else "⭐", factor, if kind == "Xp" then " XP" else "", timeLeft(untilAt))
			else
				c.Frame.Visible = false
			end
		end
	end)
end

return OrderMenu
