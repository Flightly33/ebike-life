--[[
	Store: the Crates and Shop menus.

	Crates: three cash crates with their odds; opening one spins through paints and lands on the
	prize (frame colours, metallic and neon finishes, underglow kits), with the rarity's colour.
	Duplicates refund a quarter of the price.
	Shop: timed 2x cash boosts for in-game cash, and game passes once their ids are set up.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared.AssetIds)
local Economy = require(Shared.Economy)
local Paints = require(Shared.Paints)
local Remotes = require(Shared.Remotes)
local Shop = require(Shared.Shop)

local Sound = require(script.Parent.Parent.Sound)
local State = require(script.Parent.Parent.State)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)
local Viewport = require(script.Parent.Viewport)

local Store = {}

local New = Theme.New
local C = Theme.Colors

function Store.Crates(gui: Instance): Panel.Panel
	local panel = Panel.new(gui, "Crates", "Crates", Vector2.new(860, 560), "Win paints and underglow for your bikes")
	local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 300), Parent = panel.Body })
	Theme.List(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	-- result area
	local result = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 160), Position = UDim2.fromOffset(0, 312), Parent = panel.Body })
	Theme.Corner(result, 6)
	local glowHolder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(150, 150), Position = UDim2.new(0, 120, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), Parent = result })
	local swatch = New("Frame", { BackgroundColor3 = Color3.fromRGB(60, 60, 64), Size = UDim2.fromOffset(90, 90), Position = UDim2.new(0, 120, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 6, Parent = result })
	Theme.Corner(swatch, 10)
	Theme.Stroke(swatch, Color3.new(1, 1, 1), 3)
	local prizeName = Theme.Label({ Text = "Pick a crate!", Size = UDim2.new(1, -260, 0, 40), Position = UDim2.fromOffset(240, 30), TextSize = 34, Align = Enum.TextXAlignment.Left, Stroke = 3, Parent = result })
	local prizeSub = Theme.Label({ Text = "Paints show up in Tuning → Paint", Size = UDim2.new(1, -260, 0, 26), Position = UDim2.fromOffset(240, 78), TextSize = 20, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = result })
	local spinning = false

	local function open(crateId: string)
		if spinning then
			return
		end
		spinning = true
		local ok, message, paintId, duplicate = Remotes.Function("OpenCrate"):InvokeServer(crateId)
		if not ok then
			spinning = false
			Toasts.Message("Error", tostring(message))
			return
		end
		Sound.Play("CrateOpen")
		for _, child in glowHolder:GetChildren() do
			child:Destroy()
		end
		-- spin through paints, slowing down
		local delay = 0.04
		for _ = 1, 22 do
			local p = Paints.List[math.random(1, #Paints.List)]
			swatch.BackgroundColor3 = p.Color
			prizeName.Text = p.Name
			prizeName.TextColor3 = Paints.RarityColors[p.Rarity]
			Sound.Play("Click", nil, 1.4, 0.4)
			task.wait(delay)
			delay *= 1.12
		end
		local paint = Paints.Get(paintId)
		if paint then
			swatch.BackgroundColor3 = paint.Color
			prizeName.Text = paint.Name
			prizeName.TextColor3 = Paints.RarityColors[paint.Rarity]
			Theme.Glow(glowHolder, Paints.RarityColors[paint.Rarity], UDim2.fromScale(1, 1))
			prizeSub.Text = if duplicate then string.format("%s · duplicate, 25%% refunded", paint.Rarity) else string.format("%s · NEW! Use it in Tuning → Paint", paint.Rarity)
			Theme.Pop(swatch)
			Sound.Play(if paint.Rarity == "Legendary" or paint.Rarity == "Epic" then "LevelUp" else "Cash")
		end
		spinning = false
	end

	for i, crate in Paints.Crates do
		local card = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.fromOffset(266, 300), LayoutOrder = i, Parent = row })
		Theme.Corner(card, 6)
		Theme.Stroke(card, crate.Color, 2)
		Theme.Label({ Text = crate.Name, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), TextSize = 26, Color = crate.Color, Stroke = 2, Parent = card })
		Theme.Glow(card, crate.Color, UDim2.fromOffset(120, 120), UDim2.new(0.5, 0, 0, 96))
		Viewport.Icon(card, "Crates", UDim2.new(1, 0, 0, 110), UDim2.fromOffset(0, 40))
		local odds = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0, 80), Position = UDim2.fromOffset(10, 156), Parent = card })
		Theme.List(odds, Enum.FillDirection.Vertical, 1)
		local total = 0
		for _, w in crate.Weights do
			total += w
		end
		for j, rarity in { "Common", "Rare", "Epic", "Legendary" } do
			local weight = crate.Weights[rarity] or 0
			if weight > 0 then
				Theme.Label({ Text = string.format("%s  %d%%", rarity, math.floor(weight / total * 100 + 0.5)), Size = UDim2.new(1, 0, 0, 18), TextSize = 15, Color = (Paints.RarityColors :: any)[rarity], Stroke = 1, LayoutOrder = j, Parent = odds })
			end
		end
		Theme.Button({ Text = "Open " .. Economy.FormatCash(crate.Price), Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 1, -48), TextSize = 22, Corner = 3, Parent = card, OnClick = function()
			task.spawn(open, crate.Id)
		end })
	end
	return panel
end

function Store.Shop(gui: Instance): Panel.Panel
	local panel = Panel.new(gui, "Shop", "Shop", Vector2.new(760, 520), nil)
	local list = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })
	Theme.List(list, Enum.FillDirection.Vertical, 8)
	Theme.Label({ Text = "Boosts", Size = UDim2.new(1, 0, 0, 28), TextSize = 26, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = 0, Parent = list })
	local boostStatus = Theme.Label({ Text = "", Size = UDim2.new(1, 0, 0, 20), TextSize = 17, Color = C.Cash, Align = Enum.TextXAlignment.Left, Stroke = 1, LayoutOrder = 1, Parent = list })
	for i, boost in Shop.Boosts do
		local row = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 1 + i, Parent = list })
		Theme.Corner(row, 6)
		Theme.Label({ Text = boost.Name, Size = UDim2.new(0.6, 0, 0, 28), Position = UDim2.fromOffset(12, 6), TextSize = 24, Color = C.Cash, StrokeColor = C.CashDark, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = row })
		Theme.Label({ Text = boost.Description, Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(12, 36), TextSize = 14, Font = Theme.BodyRegular, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, Parent = row })
		Theme.Button({ Text = Economy.FormatCash(boost.Price), Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 22, Parent = row, OnClick = function()
			local ok, message = Remotes.Function("BuyBoost"):InvokeServer(boost.Id)
			Toasts.Message(if ok then "Cash" else "Error", tostring(message))
		end })
	end
	Theme.Label({ Text = "Game passes", Size = UDim2.new(1, 0, 0, 28), TextSize = 26, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = 10, Parent = list })
	for i, pass in Shop.Passes do
		local id = (AssetIds.GamePasses :: any)[pass.Key]
		local ready = type(id) == "number" and id > 0
		local row = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 10 + i, Parent = list })
		Theme.Corner(row, 6)
		Theme.Label({ Text = pass.Name, Size = UDim2.new(0.6, 0, 0, 28), Position = UDim2.fromOffset(12, 6), TextSize = 24, Color = C.Gold, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = row })
		Theme.Label({ Text = pass.Description, Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(12, 36), TextSize = 14, Font = Theme.BodyRegular, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, Parent = row })
		Theme.Button({ Text = if ready then "Buy" else "Coming soon", Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = if ready then C.Gold else C.Gray, TextSize = 20, Parent = row, OnClick = function()
			if ready then
				MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
			end
		end })
	end
	panel.Refresh = function()
		local data = State.Get()
		local left = if data then data.BoostUntil - os.time() else 0
		boostStatus.Text = if left > 0 then string.format("2x Cash active: %d:%02d left", math.floor(left / 60), left % 60) else "No boost active"
	end
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Frame.Visible then
				local refresh = panel.Refresh
				if refresh then
					refresh()
				end
			end
		end
	end)
	return panel
end

return Store
