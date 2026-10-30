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
		node.yy = inst.SizeConstraint.Name == "RelativeYY"
		node.xx = inst.SizeConstraint.Name == "RelativeXX"
		node.clips = inst.ClipsDescendants
		node.autoX = inst.AutomaticSize.Name == "X" or inst.AutomaticSize.Name == "XY"
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			node.text = inst.Text
			node.textColor = color(inst.TextColor3)
			node.textT = inst.TextTransparency
			node.font = if has(inst, "FontFace") then tostring(inst.FontFace.Family) .. "|" .. inst.FontFace.Weight.Name else inst.Font.Name
			node.fontEnum = inst.Font.Name
			node.xAlign = inst.TextXAlignment.Name
			node.yAlign = inst.TextYAlignment.Name
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
			node.stroke = { color = color(c.Color), thick = c.Thickness, t = c.Transparency, mode = c.ApplyStrokeMode.Name }
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
			node.list = { dir = c.FillDirection.Name, pad = { c.Padding.Scale, c.Padding.Offset }, h = c.HorizontalAlignment.Name, v = c.VerticalAlignment.Name }
		elseif k == "UIGridLayout" then
			node.grid = { cell = udim2(c.CellSize), pad = udim2(c.CellPadding) }
		elseif c:IsA("GuiObject") then
			table.insert(node.children, GuiExport.Node(c))
		end
	end
	return node
end

return GuiExport
