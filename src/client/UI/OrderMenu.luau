--[[
	OrderMenu: a shop counter's menu (Shared/Menus), opened by its Order prompt. Buying goes
	through the Order remote; OrderService checks you're at the counter and applies the item.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
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

function OrderMenu.SetCounter(part: BasePart)
	counter = part
end

function OrderMenu.new(gui: Instance): Panel.Panel
	local panel = Panel.new(gui, "Order", "Order", Vector2.new(640, 420), "Food and drinks boost your cash for a few minutes")
	local list = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel.Body })
	Theme.List(list, Enum.FillDirection.Vertical, 8)
	panel.Refresh = function()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local at = counter
		if not at then
			return
		end
		local shopName = at:GetAttribute("ShopName")
		panel.Title.Text = if type(shopName) == "string" then shopName else "Order"
		local menu = at:GetAttribute("Menu")
		local items: { Menus.Item } = (if type(menu) == "string" then Menus.Lists[menu] else nil) or {}
		for i, item in items do
			local row = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, 0, 0, 80), LayoutOrder = i, Parent = list })
			Theme.Corner(row, 6)
			Theme.Label({ Text = item.Icon, Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(8, 8), TextSize = 46, Stroke = 0, Parent = row })
			Theme.Label({ Text = item.Name, Size = UDim2.new(1, -260, 0, 30), Position = UDim2.fromOffset(80, 10), TextSize = 26, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = row })
			Theme.Label({ Text = item.Description, Size = UDim2.new(1, -260, 0, 22), Position = UDim2.fromOffset(80, 44), TextSize = 16, Font = Theme.BodyRegular, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, Wrapped = true, Parent = row })
			Theme.Button({ Text = Economy.FormatCash(item.Price), Size = UDim2.fromOffset(150, 44), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextSize = 22, Parent = row, OnClick = function()
				local ok, message = Remotes.Function("Order"):InvokeServer(at, item.Id)
				Toasts.Message(if ok then "Cash" else "Error", tostring(message))
				if ok then
					Sound.Play("Cash")
				end
			end })
		end
	end
	return panel
end

return OrderMenu
