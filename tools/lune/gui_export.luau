--[[
	Turns a GUI tree (Frames, TextLabels, ImageLabels, ViewportFrames with their UICorner, UIStroke,
	UIGradient, UIPadding and UIListLayout) into JSON for tools/preview/gui.mjs, which lays it out
	in HTML and screenshots it: a way to look at the game's UI and ads offline.
]]
local GuiExport = {}

local function udim2(u: any): { number }
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end

local function color(c: any): { number }
	return { c.R, c.G, c.B }
end

local function has(inst: any, prop: string): boolean
	local ok = pcall(function()
		return inst[prop]
	end)
	return ok
end

-- an enum property's name, or nil (the simulator leaves unset ones nil)
local function enum(inst: any, prop: string): string?
	local ok, value = pcall(function()
		return inst[prop]
	end)
	if ok and value ~= nil and type(value) ~= "string" then
		local okName, name = pcall(function()
			return value.Name
		end)
		return if okName then name else nil
	end
	return if ok then value else nil
end

local function get(inst: any, prop: string, default: any): any
	local ok, value = pcall(function()
		return inst[prop]
	end)
	if ok and value ~= nil then
		return value
	end
	return default
end

function GuiExport.Node(inst: any): any
	local node: any = { class = inst.ClassName, name = inst.Name, children = {} }
	if inst:IsA("GuiObject") then
		node.size = udim2(inst.Size)
		node.pos = udim2(inst.Position)
		node.anchor = { inst.AnchorPoint.X, inst.AnchorPoint.Y }
		node.rot = inst.Rotation
		node.bg = color(inst.BackgroundColor3)
		node.bgT = inst.BackgroundTransparency
		node.visible = inst.Visible
		node.z = inst.ZIndex
		node.order = inst.LayoutOrder
		node.yy = enum(inst, "SizeConstraint") == "RelativeYY"
		node.xx = enum(inst, "SizeConstraint") == "RelativeXX"
		node.clips = inst.ClipsDescendants
		node.autoX = enum(inst, "AutomaticSize") == "X" or enum(inst, "AutomaticSize") == "XY"
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			node.text = inst.Text
			node.textColor = color(inst.TextColor3)
			node.textT = inst.TextTransparency
			local face = get(inst, "FontFace", nil)
			node.font = if face then tostring(face.Family) .. "|" .. tostring(enum(face, "Weight")) else ""
			node.fontEnum = enum(inst, "Font") or ""
			node.xAlign = enum(inst, "TextXAlignment") or "Center"
			node.yAlign = enum(inst, "TextYAlignment") or "Center"
			node.scaled = inst.TextScaled
			node.textSize = inst.TextSize
			node.wrapped = inst.TextWrapped
		end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			node.image = inst.Image
		end
		if inst:IsA("ViewportFrame") then
			node.viewport = true
		end
	end
	for _, c in inst:GetChildren() do
		local k = c.ClassName
		if k == "UICorner" then
			node.corner = { c.CornerRadius.Scale, c.CornerRadius.Offset }
		elseif k == "UIStroke" then
			node.stroke = { color = color(c.Color), thick = c.Thickness, t = c.Transparency, mode = enum(c, "ApplyStrokeMode") }
		elseif k == "UIGradient" then
			local cols = {}
			for _, kp in c.Color.Keypoints do
				table.insert(cols, { kp.Time, kp.Value.R, kp.Value.G, kp.Value.B })
			end
			local ts = {}
			for _, kp in c.Transparency.Keypoints do
				table.insert(ts, { kp.Time, kp.Value })
			end
			node.gradient = { rot = c.Rotation, colors = cols, transp = ts }
		elseif k == "UIPadding" then
			node.padding = { c.PaddingLeft.Scale, c.PaddingLeft.Offset, c.PaddingRight.Scale, c.PaddingRight.Offset, c.PaddingTop.Scale, c.PaddingTop.Offset, c.PaddingBottom.Scale, c.PaddingBottom.Offset }
		elseif k == "UIListLayout" then
			node.list = { dir = enum(c, "FillDirection"), pad = { c.Padding.Scale, c.Padding.Offset }, h = enum(c, "HorizontalAlignment"), v = enum(c, "VerticalAlignment") }
		elseif k == "UIGridLayout" then
			node.grid = { cell = udim2(c.CellSize), pad = udim2(c.CellPadding) }
		elseif c:IsA("GuiObject") then
			table.insert(node.children, GuiExport.Node(c))
		end
	end
	return node
end

-- A whole ScreenGui (or several stacked) as one full-screen node
function GuiExport.Screens(screens: { any }): any
	local root: any = { class = "Screen", name = "Screen", size = { 1, 0, 1, 0 }, pos = { 0, 0, 0, 0 }, anchor = { 0, 0 }, rot = 0, bg = { 0, 0, 0 }, bgT = 1, visible = true, z = 1, children = {} }
	for _, sg in screens do
		if sg.Enabled ~= false then
			local layer = GuiExport.Node(sg)
			layer.size = { 1, 0, 1, 0 }
			layer.pos = { 0, 0, 0, 0 }
			layer.anchor = { 0, 0 }
			layer.rot = 0
			layer.bgT = 1
			layer.bg = { 0, 0, 0 }
			layer.visible = true
			layer.z = 1
			table.insert(root.children, layer)
		end
	end
	return root
end

return GuiExport
