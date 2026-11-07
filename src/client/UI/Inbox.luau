--[[
	Inbox: the phone's Messages app. Texts from the regulars (Nina, Marco, Jet, Officer Reyes) and
	from the city (daily rewards, events), and the calls that start missions, newest first. When a
	text arrives a card slides in on the HUD (tap it to read); the HUD's phone tile and the Messages
	app carry the unread count. Kept on the client for the session: the server sends each one once
	(the Message remote; Notify's events land here too).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Missions = require(Shared.Missions)
local Signal = require(Shared.Signal)

local Kit = require(script.Parent.Kit)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)

local Inbox = {}

local New = Theme.New
local R = Theme.Roles

export type Message = { From: string, Text: string, Kind: string, At: number, Read: boolean }

Inbox.Changed = Signal.new() -- the unread count may have changed
Inbox.MAX = 60
Inbox.CARD_SECONDS = 5

-- the city's own senders (the regulars come from Shared/Missions.Givers)
local SENDERS: { [string]: { Icon: string, Title: string, Color: Color3 } } = {
	Flighty = { Icon = "📱", Title = "Flighty", Color = R.Info },
	Daily = { Icon = "🎁", Title = "Daily rewards", Color = R.Positive },
	Events = { Icon = "🎉", Title = "City events", Color = R.Warning },
}
local GIVER_COLORS: { [string]: Color3 } = {
	Nina = R.Accent,
	Marco = R.Job,
	Jet = R.Trial,
	Reyes = R.Info,
}

local messages: { Message } = {}
local panel: Panel.Panel? = nil
local list: ScrollingFrame? = nil
local card: TextButton? = nil
local cardIcon: TextLabel
local cardTitle: TextLabel
local cardText: TextLabel
local cardToken = 0
local clock = os.clock

-- Who a message is from: the icon, the name to show and a colour
function Inbox.Sender(from: string): (string, string, Color3)
	local giver = Missions.Givers[from]
	if giver then
		return giver.Icon, giver.Title, GIVER_COLORS[from] or R.Warning
	end
	local sender = SENDERS[from]
	if sender then
		return sender.Icon, sender.Title, sender.Color
	end
	return "📱", from, R.Info
end

function Inbox.Unread(): number
	local n = 0
	for _, m in messages do
		if not m.Read then
			n += 1
		end
	end
	return n
end

function Inbox.All(): { Message }
	return messages
end

local function ago(at: number): string
	local s = clock() - at
	if s < 60 then
		return "now"
	elseif s < 3600 then
		return string.format("%d min ago", math.floor(s / 60))
	end
	return string.format("%d h ago", math.floor(s / 3600))
end

local function render()
	local l = list
	if not l then
		return
	end
	Kit.Clear(l)
	if #messages == 0 then
		local empty = Theme.Label({ Text = "No messages yet. Nina, Marco, Jet and the city text you here when there's work or a reward waiting.", Size = UDim2.new(1, -20, 0, 80), TextSize = Theme.Type.Body, Font = Theme.Body, Color = R.Muted, Wrapped = true, Stroke = 1, LayoutOrder = 1, Parent = l })
		empty.TextYAlignment = Enum.TextYAlignment.Top
		return
	end
	for i, m in messages do
		local icon, title, color = Inbox.Sender(m.From)
		-- a bubble: the sender's line (icon in a coloured disc, name, when) over the text
		local bubble = New("Frame", { Name = "Message", BackgroundColor3 = R.Raised, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = l })
		Theme.Corner(bubble, Theme.Radius.M)
		New("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 62), PaddingRight = UDim.new(0, 12), Parent = bubble })
		Theme.List(bubble, Enum.FillDirection.Vertical, 2)
		local head = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Parent = bubble })
		local disc = New("Frame", { BackgroundColor3 = color, BackgroundTransparency = 0.55, Size = UDim2.fromOffset(42, 42), Position = UDim2.fromOffset(-52, 0), Parent = head })
		Theme.Round(disc)
		Theme.Label({ Text = icon, Size = UDim2.fromScale(1, 1), TextSize = 26, Stroke = 0, Parent = disc })
		if not m.Read then
			local dot = New("Frame", { BackgroundColor3 = Color3.fromRGB(240, 50, 50), Size = UDim2.fromOffset(12, 12), Position = UDim2.fromOffset(-58, -4), ZIndex = 3, Parent = head })
			Theme.Round(dot)
		end
		Theme.Label({ Text = (if m.Kind == "Call" then "📞 " else "") .. title, Size = UDim2.new(1, -90, 1, 0), TextSize = Theme.Type.Body + 2, Color = color, Align = Enum.TextXAlignment.Left, Stroke = 1.5, Parent = head })
		Theme.Label({ Text = ago(m.At), Size = UDim2.new(0, 90, 1, 0), Position = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(1, 0), TextSize = Theme.Type.Caption, Font = Theme.Body, Color = R.Muted, Align = Enum.TextXAlignment.Right, Stroke = 0, Parent = head })
		local text = Theme.Label({ Text = m.Text, Size = UDim2.new(1, 0, 0, 0), TextSize = Theme.Type.Body, Font = Theme.Body, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 1, LayoutOrder = 2, Parent = bubble })
		text.AutomaticSize = Enum.AutomaticSize.Y
		-- (a bubble is never shorter than its disc)
		New("UISizeConstraint", { MinSize = Vector2.new(0, 60), Parent = bubble })
	end
end

local function markRead()
	local changed = false
	for _, m in messages do
		if not m.Read then
			m.Read = true
			changed = true
		end
	end
	if changed then
		Inbox.Changed:Fire()
	end
end

local function slideCard(from: string, text: string)
	local c = card
	if not c then
		return
	end
	local icon, title, color = Inbox.Sender(from)
	cardIcon.Text = icon
	cardTitle.Text = title
	cardTitle.TextColor3 = color
	cardText.Text = text
	cardToken += 1
	local token = cardToken
	c.Visible = true
	c.Position = UDim2.new(1, 340, 0, 170)
	TweenService:Create(c, Theme.Motion.Spring, { Position = UDim2.new(1, -12, 0, 170) }):Play()
	task.delay(Inbox.CARD_SECONDS, function()
		if token == cardToken and c.Parent then
			local out = TweenService:Create(c, Theme.Motion.Base, { Position = UDim2.new(1, 340, 0, 170) })
			out:Play()
			out.Completed:Wait()
			if token == cardToken then
				c.Visible = false
			end
		end
	end)
end

-- A new message. A call (a mission's intro) is shown by UI/Objective, so it lands already read.
function Inbox.Add(from: string, text: string, kind: string?)
	local k = kind or "Text"
	table.insert(messages, 1, { From = from, Text = text, Kind = k, At = clock(), Read = k == "Call" })
	while #messages > Inbox.MAX do
		table.remove(messages)
	end
	local p = panel
	if p and p.Frame.Visible then
		markRead()
		render()
	elseif k ~= "Call" then
		slideCard(from, text)
	end
	Inbox.Changed:Fire()
end

-- The card that slides in on the HUD (top right, under the wanted stars and the event)
function Inbox.InitHud(gui: ScreenGui, open: (string) -> ())
	local c = New("TextButton", { Name = "MessageCard", Text = "", AutoButtonColor = false, BackgroundColor3 = R.Surface, BackgroundTransparency = 0.04, Size = UDim2.fromOffset(300, 68), Position = UDim2.new(1, 340, 0, 170), AnchorPoint = Vector2.new(1, 0), Visible = false, ZIndex = 30, Parent = gui })
	Theme.Corner(c, Theme.Radius.L)
	Theme.Stroke(c, Color3.fromRGB(10, 10, 12), 2)
	cardIcon = Theme.Label({ Text = "", Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextSize = 28, Stroke = 0, ZIndex = 31, Parent = c })
	cardTitle = Theme.Label({ Text = "", Size = UDim2.new(1, -66, 0, 20), Position = UDim2.fromOffset(56, 6), TextSize = 16, Align = Enum.TextXAlignment.Left, Stroke = 1.5, ZIndex = 31, Parent = c })
	cardText = Theme.Label({ Text = "", Size = UDim2.new(1, -66, 0, 36), Position = UDim2.fromOffset(56, 26), TextSize = 13, Font = Theme.Body, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 1, ZIndex = 31, Parent = c })
	cardText.TextTruncate = Enum.TextTruncate.AtEnd
	cardText.TextYAlignment = Enum.TextYAlignment.Top
	c.Activated:Connect(function()
		cardToken += 1
		c.Visible = false
		open("Messages")
	end)
	card = c
end

function Inbox.new(gui: Instance): Panel.Panel
	local p = Panel.new(gui, "Messages", "MESSAGES", Vector2.new(560, 520), nil)
	list = Kit.List(p.Body, UDim2.fromScale(1, 1), nil, Theme.Space.S)
	p.Refresh = function()
		markRead()
		render()
	end
	panel = p
	return p
end

return Inbox
