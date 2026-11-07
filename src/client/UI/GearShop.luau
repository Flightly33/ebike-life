--[[
	GearShop: the phone's Gear app (rider gear, Shared/Gear). A tab per slot (helmets, jackets,
	gloves, boots); each piece a row with its colours, what it costs and when it unlocks, and Buy,
	Wear or Take off. The server (GearService, the Gear remote) checks and puts it on, so everyone
	sees it. Built from UI/Kit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Gear = require(Shared.Gear)
local Remotes = require(Shared.Remotes)

local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Kit)
local Panel = require(script.Parent.Panel)
local Sound = require(script.Parent.Parent.Sound)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local GearShop = {}

local R = Theme.Roles
local LABELS = { Helmet = "🪖 Helmets", Jacket = "🧥 Jackets", Gloves = "🧤 Gloves", Boots = "🥾 Boots" }

function GearShop.new(gui: Instance): Panel.Panel
	local panel = Panel.new(gui, "Gear", "RIDER GEAR", Vector2.new(760, 540), nil)
	local slot: string = "Helmet"
	local list = Kit.List(panel.Body, UDim2.new(1, 0, 1, -82), UDim2.fromOffset(0, 48), Theme.Space.S)
	local note = Theme.Label({ Text = "Gear is a look: everyone sees it, and it changes nothing about the ride.", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, -26), TextSize = Theme.Type.Caption + 1, Font = Theme.Body, Color = R.Muted, Stroke = 1, Parent = panel.Body })
	local _ = note
	local render: () -> ()

	-- the server's answer: ok, and why not
	local function call(action: string, id: string): boolean
		local ok, success, message = pcall(function()
			return Remotes.Function("Gear"):InvokeServer(action, id)
		end)
		if not ok then
			Toasts.Message("Error", "Try again")
			return false
		elseif success ~= true then
			Toasts.Message("Error", tostring(message or "Try again"))
			return false
		end
		return true
	end

	render = function()
		Kit.Clear(list)
		local data = State.Get()
		if not data then
			return
		end
		for i, item in Gear.ForSlot(slot) do
			local owned = data.Gear.Owned[item.Id] == true
			local worn = data.Gear.Worn[item.Slot] == item.Id
			local locked = data.Level < item.Level
			local price = if item.Price == 0 then "Free" else Economy.FormatCash(item.Price)
			local sub = string.format("%s  ·  %s%s", item.Blurb, if owned then "Owned" else price, if locked then string.format("  ·  unlocks at level %d", item.Level) else "")
			local actions: { Kit.Action } = {}
			if worn then
				table.insert(actions, { Text = "Take off", Color = R.Raised, OnClick = function()
					if call("TakeOff", item.Slot) then
						Sound.Play("Cash", nil, 1.2, 0.3)
					end
				end })
			elseif owned then
				table.insert(actions, { Text = "Wear", Color = R.Info, OnClick = function()
					if call("Wear", item.Id) then
						Sound.Play("Cash", nil, 1.4, 0.4)
						Toasts.Message("Info", "Wearing the " .. item.Name)
					end
				end })
			elseif not locked then
				table.insert(actions, { Text = "Buy " .. price, Color = R.Positive, OnClick = function()
					if call("Buy", item.Id) then
						Sound.Play("Cash")
						Toasts.Message("Cash", "Bought the " .. item.Name .. ": you're wearing it")
					end
				end })
			end
			local row = Kit.Row(list, {
				Title = item.Name .. (if worn then "  ✓" else ""),
				Sub = sub,
				Icon = Gear.SlotIcons[item.Slot],
				Order = i,
				Height = 74,
				Accent = item.Main,
				Actions = actions,
				Dim = locked,
			})
			-- the trim colour as a second chip beside the icon
			local chip = Theme.New("Frame", { Name = "Trim", BackgroundColor3 = item.Trim, Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(44, 50), Parent = row })
			Theme.Round(chip)
			if item.Glow then
				chip.BackgroundTransparency = 0
				Theme.Stroke(chip, item.Trim, 2, 0.2)
			end
		end
	end

	local names: { string } = {}
	for _, s in Gear.Slots do
		table.insert(names, s)
	end
	local tabs = Kit.Tabs(panel.Body, names, LABELS, function(name: string)
		slot = name
		render()
	end, 150)
	panel.Refresh = function()
		tabs.Set(slot)
		render()
	end
	State.Changed:Connect(function()
		if panel.Frame.Visible then
			render()
		end
	end)
	return panel
end

return GearShop
