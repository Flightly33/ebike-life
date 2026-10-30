--[[
	Billboards: draws the ads on the city's ad faces near the camera, on this client only.

	The baked city has the structures (City/Billboards: highway monopoles, rooftop boards, LED
	screens on downtown podiums) and the bus shelter panels; each face is a part named `AdFace`
	(attributes `AdKind`, `AdSeed`). Within `RANGE` of the camera (the nearest `MAX_FACES`) a face
	gets a SurfaceGui built from Instances: a gradient, a stripe, the brand's pill, the headline and
	line, a badge, and per layout (Shared/Ads) a big emoji in a ring, the item turning in 3D
	(ItemModel) or a Flighty e-moto in 3D (BikeModel); the owner's own images (AssetIds.Billboards)
	are shown in turn with the built-in ads. Static faces keep one ad (by seed); LED screens change
	ad every `CYCLE` seconds (the same ad for everyone: it follows the server time), slide it in,
	and run a news ticker. At night the boards' `AdLamp`s light up and the ads glow.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ads = require(Shared.Ads)
local AssetIds = require(Shared.AssetIds)
local Bikes = require(Shared.Bikes)
local BikeModel = require(Shared.Models.BikeModel)
local Config = require(Shared.Config)
local ItemModel = require(Shared.Models.ItemModel)

local Graphics = require(script.Parent.Graphics)

local Billboards = {}

local MAP = Config.MAP_SCALE / 1.25
local CYCLE = 8 -- seconds an LED screen shows each ad

type Entry = { Kind: string, Ad: Ads.Ad?, Image: string?, Name: string? }
type Face = {
	Part: BasePart,
	Gui: SurfaceGui,
	Kind: string,
	Seed: number,
	Index: number,
	Content: Frame?,
	Ticker: TextLabel?,
	Spin: { { Camera: Camera, Center: Vector3, Dist: number } },
	Restore: { SurfaceGui },
}

local known: { [BasePart]: boolean } = {}
local lamps: { [BasePart]: boolean } = {}
local shown: { [BasePart]: Face } = {}
local models3d = 0
local offline = false -- composing for an offline preview (tools/lune/preview_gui.luau): no 3D

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Every ad in turn: the built-in ones, and the owner's images every third slot
local function pool(tall: boolean): { Entry }
	local list: { Entry } = {}
	local images: { Entry } = {}
	for _, img in AssetIds.Billboards do
		local id = AssetIds.Resolve(if tall and img.Tall ~= "" then img.Tall else img.Wide)
		if id then
			table.insert(images, { Kind = "Image", Ad = nil, Image = id, Name = img.Name })
		end
	end
	local k = 0
	for _, ad in Ads.List do
		table.insert(list, { Kind = "Ad", Ad = ad, Image = nil, Name = nil })
		if #images > 0 and #list % 2 == 0 then
			k = k % #images + 1
			table.insert(list, images[k])
		end
	end
	return list
end
local WIDE = pool(false)
local TALL = pool(true)

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, scale: number?)
	new("UICorner", { CornerRadius = UDim.new(scale or 0.2, 0) }, parent)
end

local function text(parent: Instance, value: string, props: { [string]: any }): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = rgb(255, 255, 255),
	}, parent)
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, parent)
end

-- A 3D model turning in a ViewportFrame
local function view3d(face: Face, parent: Instance, model: Model, size: UDim2, position: UDim2, tilt: number)
	local vf = new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = size,
		Position = position,
		Ambient = rgb(180, 180, 186),
		LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(-0.5, -1, -0.7),
	}, parent)
	model.Parent = vf
	local cf, extents = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 28
	camera.Parent = vf
	vf.CurrentCamera = camera
	local dist = extents.Magnitude / 2 / math.tan(math.rad(14)) * 1.02
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.7, dist * tilt, dist * 0.7), cf.Position)
	table.insert(face.Spin, { Camera = camera, Center = cf.Position, Dist = dist })
end

-- Draws one ad into a fresh content frame
local function compose(face: Face, entry: Entry, canvas: Vector2): Frame
	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(20, 20, 24), BorderSizePixel = 0, ClipsDescendants = true })
	local tall = canvas.Y > canvas.X
	if entry.Kind == "Image" and entry.Image then
		new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = entry.Image, ScaleType = Enum.ScaleType.Crop }, root)
		return root
	end
	local ad = entry.Ad :: Ads.Ad
	-- background: gradient, a big soft stripe, dots
	local bg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 255, 255), BorderSizePixel = 0 }, root)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ad.Top, ad.Bottom) }, bg)
	local stripe = new("Frame", { Size = UDim2.fromScale(0.5, 2.2), Position = UDim2.fromScale(if tall then 0.15 else 0.32, -0.6), Rotation = 22, BackgroundColor3 = ad.Accent, BackgroundTransparency = 0.82, BorderSizePixel = 0 }, root)
	local _ = stripe
	for i = 0, if tall then -1 else 5 do
		local dot = new("Frame", { Size = UDim2.fromScale(0.05, 0.05), SizeConstraint = Enum.SizeConstraint.RelativeYY, Position = UDim2.fromScale(0.86 + (i % 3) * 0.04, 0.08 + math.floor(i / 3) * 0.08), BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.75 }, root)
		corner(dot, 0.5)
	end
	-- the brand's pill
	local pill = new("Frame", { Size = UDim2.fromScale(if tall then 0.84 else 0.36, if tall then 0.08 else 0.13), Position = UDim2.fromScale(0.04, 0.05), BackgroundColor3 = ad.Accent }, root)
	corner(pill, 0.5)
	text(pill, ad.Brand, { Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1), TextColor3 = if ad.Accent.R + ad.Accent.G + ad.Accent.B > 1.8 then rgb(24, 24, 28) else rgb(255, 255, 255), Font = Enum.Font.GothamBlack })
	-- the picture: 3D item or bike, else a big emoji in a ring
	local picSize = if tall then UDim2.fromScale(0.9, 0.42) else UDim2.fromScale(0.42, 0.8)
	local picPos = if tall then UDim2.fromScale(0.05, 0.15) else (if ad.Layout == "Bike" then UDim2.fromScale(0.55, 0.14) else UDim2.fromScale(0.03, 0.17))
	local budget = if Graphics.Current().Shadows then 8 else 2
	local drew3d = false
	if offline and (ad.Layout == "Product" or ad.Layout == "Bike") then
		local mark = new("Frame", { Size = picSize, Position = picPos, BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.6, Name = "Viewport3D" }, root)
		text(mark, (if ad.Layout == "Bike" then "🏍" else ad.Emoji) .. " 3D", { Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.25) })
		drew3d = true
	elseif (ad.Layout == "Product" or ad.Layout == "Bike") and models3d < budget then
		local model: Model? = nil
		if ad.Layout == "Product" and ad.Item then
			model = ItemModel.Build(ad.Item, 10)
		elseif ad.Layout == "Bike" and ad.Bike then
			local bike = Bikes.ById[ad.Bike]
			if bike then
				local ok, built = pcall(BikeModel.Build, bike, nil, { Static = true })
				model = if ok then built else nil
			end
		end
		if model then
			local glow = new("Frame", { Size = UDim2.fromScale(0.8, 0.8), SizeConstraint = Enum.SizeConstraint.RelativeYY, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.7 }, new("Frame", { Size = picSize, Position = picPos, BackgroundTransparency = 1 }, root))
			corner(glow, 0.5)
			view3d(face, root, model, picSize, picPos, if ad.Layout == "Bike" then 0.25 else 0.55)
			models3d += 1
			drew3d = true
		end
	end
	if not drew3d and ad.Layout ~= "Bold" then
		local holder = new("Frame", { Size = picSize, Position = picPos, BackgroundTransparency = 1 }, root)
		local ring = new("Frame", { Size = UDim2.fromScale(0.9, 0.9), SizeConstraint = Enum.SizeConstraint.RelativeYY, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.65 }, holder)
		corner(ring, 0.5)
		stroke(ring, ad.Accent, 6)
		text(ring, ad.Emoji, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Font = Enum.Font.GothamBlack })
	end
	-- words (narrower where the badge sits beside them)
	local badged = ad.Badge ~= nil
	local words = if tall
		then new("Frame", { Size = UDim2.fromScale(0.92, 0.36), Position = UDim2.fromScale(0.04, 0.58), BackgroundTransparency = 1 }, root)
		elseif ad.Layout == "Bold" then new("Frame", { Size = UDim2.fromScale(if badged then 0.76 else 0.92, 0.66), Position = UDim2.fromScale(0.04, 0.22), BackgroundTransparency = 1 }, root)
		elseif ad.Layout == "Bike" then new("Frame", { Size = UDim2.fromScale(0.5, 0.72), Position = UDim2.fromScale(0.04, 0.22), BackgroundTransparency = 1 }, root)
		else new("Frame", { Size = UDim2.fromScale(if badged then 0.34 else 0.5, 0.72), Position = UDim2.fromScale(0.47, 0.2), BackgroundTransparency = 1 }, root)
	local headline = text(words, ad.Headline, { Size = UDim2.fromScale(1, if ad.Layout == "Bold" then 0.62 else 0.5), TextColor3 = ad.Ink, TextXAlignment = if tall or ad.Layout == "Bold" then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left, TextWrapped = true })
	local function bright(c: Color3): boolean
		return c.R * 0.3 + c.G * 0.59 + c.B * 0.11 > 0.6
	end
	-- a dark headline gets a white outline, a light one a dark outline; the line reads on the background
	stroke(headline, if bright(ad.Ink) then rgb(0, 0, 0) else rgb(255, 255, 255), if tall then 3 else 5)
	local lightBg = bright(ad.Top:Lerp(ad.Bottom, 0.6))
	text(words, ad.Line, {
		Size = UDim2.fromScale(1, 0.2),
		Position = UDim2.fromScale(0, if ad.Layout == "Bold" then 0.64 else 0.54),
		Font = Enum.Font.GothamBold,
		TextColor3 = if lightBg then rgb(28, 28, 32) else rgb(255, 255, 255),
		TextXAlignment = if tall or ad.Layout == "Bold" then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	if ad.Layout == "Bold" then
		text(words, string.rep(ad.Emoji .. " ", 4), { Size = UDim2.fromScale(0.6, 0.16), Position = UDim2.fromScale(0.2, 0.86), Font = Enum.Font.GothamBlack })
	end
	-- the badge: a burst (two turned squares) with the price
	local badge = ad.Badge
	if badge then
		local bsize = if tall then 0.16 else 0.34
		local burst = new("Frame", { Size = UDim2.fromScale(bsize, bsize), SizeConstraint = Enum.SizeConstraint.RelativeYY, AnchorPoint = Vector2.new(0.5, 0.5), Position = if tall then UDim2.fromScale(0.82, 0.22) elseif ad.Layout == "Bike" then UDim2.fromScale(0.92, 0.3) else UDim2.fromScale(0.89, 0.58), BackgroundColor3 = ad.Accent, Rotation = 12 }, root)
		new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = ad.Accent, Rotation = 45 }, burst)
		local inner = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = -12, ZIndex = 3 }, burst)
		local label = text(inner, badge, { Size = UDim2.fromScale(0.86, 0.6), Position = UDim2.fromScale(0.07, 0.2), Font = Enum.Font.GothamBlack, TextColor3 = if ad.Accent.R + ad.Accent.G + ad.Accent.B > 1.8 then rgb(24, 24, 28) else rgb(255, 255, 255), ZIndex = 4 })
		local _l = label
	end
	-- fine print
	text(root, "Offer valid in Miami only. Terms apply.", { Size = UDim2.fromScale(0.4, 0.035), Position = UDim2.fromScale(0.58, 0.955), Font = Enum.Font.Gotham, TextColor3 = rgb(255, 255, 255), TextTransparency = 0.35, TextXAlignment = Enum.TextXAlignment.Right })
	return root
end

local function entryFor(face: Face): Entry
	local list = if face.Part.Size.Y > face.Part.Size.X then TALL else WIDE
	return list[(face.Seed + face.Index) % #list + 1]
end

local function show(face: Face, slide: boolean)
	local canvas = face.Part.Size * face.Gui.PixelsPerStud
	local old = face.Content
	-- (the old ad's 3D models stop counting once it goes)
	if old then
		for _ in face.Spin do
			models3d = math.max(0, models3d - 1)
		end
	end
	table.clear(face.Spin)
	local content = compose(face, entryFor(face), Vector2.new(canvas.X, canvas.Y))
	content.Parent = face.Gui
	face.Content = content
	if old then
		if slide then
			content.Position = UDim2.fromScale(1, 0)
			TweenService:Create(content, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
			TweenService:Create(old, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.fromScale(-1, 0) }):Play()
			task.delay(0.65, function()
				old:Destroy()
			end)
		else
			old:Destroy()
		end
	end
	-- the LED screen's ticker and scanlines stay on top
	local ticker = face.Ticker
	if ticker then
		local bar = ticker.Parent :: Frame
		bar.ZIndex = 10
	end
end

local function screenTime(): number
	return Workspace:GetServerTimeNow()
end

local function addFace(part: BasePart)
	local kind = part:GetAttribute("AdKind")
	local seed = part:GetAttribute("AdSeed")
	local pps = math.clamp(900 / math.max(part.Size.X, part.Size.Y), 4, 80)
	local gui = new("SurfaceGui", {
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pps,
		LightInfluence = 0.6,
		ClipsDescendants = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Name = "Ad",
	}, part)
	local face: Face = {
		Part = part,
		Gui = gui,
		Kind = if type(kind) == "string" then kind else "Billboard",
		Seed = if type(seed) == "number" then seed else 1,
		Index = 0,
		Content = nil,
		Ticker = nil,
		Spin = {},
		Restore = {},
	}
	-- the baked sign (bus shelter panels) hides while the ad shows
	for _, g in part:GetChildren() do
		if g:IsA("SurfaceGui") and g ~= gui and g.Enabled then
			g.Enabled = false
			table.insert(face.Restore, g)
		end
	end
	if face.Kind == "Screen" then
		face.Index = math.floor(screenTime() / CYCLE)
		local bar = new("Frame", { Size = UDim2.fromScale(1, 0.11), Position = UDim2.fromScale(0, 0.89), BackgroundColor3 = rgb(12, 12, 16), BorderSizePixel = 0, ZIndex = 10, ClipsDescendants = true }, gui)
		new("Frame", { Size = UDim2.fromScale(0.16, 1), BackgroundColor3 = rgb(220, 30, 30), BorderSizePixel = 0, ZIndex = 12 }, bar)
		text(bar, "LIVE", { Size = UDim2.fromScale(0.14, 0.8), Position = UDim2.fromScale(0.01, 0.1), ZIndex = 13, Font = Enum.Font.GothamBlack })
		face.Ticker = text(bar, table.concat(Ads.Ticker, "   •   "), { Size = UDim2.fromScale(6, 0.8), Position = UDim2.fromScale(0.2, 0.1), ZIndex = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true })
		-- scanlines
		local scan = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 1, ZIndex = 20 }, gui)
		for i = 0, 23 do
			new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, i / 24), BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 20 }, scan)
		end
	end
	show(face, false)
	shown[part] = face
end

local function removeFace(face: Face)
	models3d = math.max(0, models3d - #face.Spin)
	face.Gui:Destroy()
	for _, g in face.Restore do
		g.Enabled = true
	end
	shown[face.Part] = nil
end

local function isNight(): boolean
	local t = Lighting.ClockTime
	return t < 6.6 or t > 18.6
end

local lampsLit: boolean? = nil
local function light(d: BasePart, night: boolean)
	d.Material = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local lit = d:GetAttribute("Lit")
	d.Color = if night and typeof(lit) == "Color3" then lit else rgb(70, 72, 78)
end

local function updateLamps()
	local night = isNight()
	if night == lampsLit then
		return
	end
	lampsLit = night
	for d in lamps do
		if d.Parent == nil then
			lamps[d] = nil
		else
			light(d, night)
		end
	end
end

local function choose()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local ultra = Graphics.Current().Shadows
	local range = (if ultra then 1500 else 800) * MAP
	local panelRange = (if ultra then 320 else 200) * MAP
	local maxFaces = if ultra then 40 else 14
	local from = camera.CFrame.Position
	local want: { { Part: BasePart, D: number } } = {}
	for part in known do
		if part.Parent == nil then
			known[part] = nil
		else
			local d = (part.Position - from).Magnitude
			local limit = if part:GetAttribute("AdKind") == "Panel" then panelRange else range
			if d < limit then
				table.insert(want, { Part = part, D = d })
			end
		end
	end
	table.sort(want, function(a, b)
		return a.D < b.D
	end)
	local keep: { [BasePart]: boolean } = {}
	for i = 1, math.min(#want, maxFaces) do
		keep[want[i].Part] = true
	end
	for part, face in shown do
		if not keep[part] then
			removeFace(face)
		end
	end
	local added = 0
	for part in keep do
		if not shown[part] and added < 4 then
			added += 1
			addFace(part)
		end
	end
	-- LED screens move on to their next ad
	local slot = math.floor(screenTime() / CYCLE)
	local night = isNight()
	for _, face in shown do
		if face.Kind == "Screen" and face.Index ~= slot then
			face.Index = slot
			show(face, true)
		end
		local lit = face.Kind == "Screen" or face.Kind == "Panel" or night
		face.Gui.LightInfluence = if lit then 0.1 else 0.6
		face.Gui.Brightness = if face.Kind == "Screen" then 1.6 elseif night then 1.25 else 1
	end
end

local function found(d: Instance)
	if d:IsA("BasePart") then
		if d.Name == "AdFace" then
			known[d] = true
		elseif d.Name == "AdLamp" then
			lamps[d] = true
			if lampsLit ~= nil then
				light(d, lampsLit)
			end
		end
	end
end

local function watch(city: Instance)
	for _, d in city:GetDescendants() do
		found(d)
	end
	city.DescendantAdded:Connect(found)
end

-- For offline previews: one ad composed on a canvas of `size` pixels
function Billboards.Compose(index: number, size: Vector2): Frame
	offline = true
	local list = if size.Y > size.X then TALL else WIDE
	local face = { Spin = {} } :: any
	return compose(face, list[(index - 1) % #list + 1], size)
end

function Billboards.Init()
	task.spawn(function()
		local city = Workspace:WaitForChild("City", 600)
		if city then
			watch(city)
		end
	end)
	local since, lampsSince = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		lampsSince += dt
		if since >= 1 then
			since = 0
			choose()
		end
		if lampsSince >= 10 then
			lampsSince = 0
			updateLamps()
		end
		-- turn the 3D products and roll the tickers on the faces near the camera
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		for part, face in shown do
			if (part.Position - camera.CFrame.Position).Magnitude < 400 * MAP then
				for i, s in face.Spin do
					local a = now * 0.6 + i
					s.Camera.CFrame = CFrame.lookAt(s.Center + Vector3.new(math.sin(a) * s.Dist, s.Dist * 0.35, math.cos(a) * s.Dist), s.Center)
				end
				local ticker = face.Ticker
				if ticker then
					local x = 0.2 - ((now * 0.05) % 6)
					ticker.Position = UDim2.fromScale(x, 0.1)
				end
			end
		end
	end)
end

return Billboards
