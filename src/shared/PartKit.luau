--[[
	PartKit: small helpers for building things out of parts (the city, bikes, cars, menu icons).
	Everything is created anchored unless told otherwise; models that move weld themselves later.
	Works under Lune as well (the city is baked offline), so it only sets plain properties.
]]

local PartKit = {}

export type Opts = {
	Collide: boolean?,
	Query: boolean?,
	Touch: boolean?,
	Shadow: boolean?,
	Transparency: number?,
	Reflectance: number?,
	Anchored: boolean?,
	Shape: Enum.PartType?,
	Massless: boolean?,
}

local function apply(p: BasePart, opts: Opts?)
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if not opts then
		return
	end
	if opts.Anchored ~= nil then
		p.Anchored = opts.Anchored
	end
	if opts.Collide ~= nil then
		p.CanCollide = opts.Collide
	end
	if opts.Query ~= nil then
		p.CanQuery = opts.Query
	end
	if opts.Touch ~= nil then
		p.CanTouch = opts.Touch
	end
	if opts.Shadow ~= nil then
		p.CastShadow = opts.Shadow
	end
	if opts.Transparency then
		p.Transparency = opts.Transparency
	end
	if opts.Reflectance then
		p.Reflectance = opts.Reflectance
	end
	if opts.Massless then
		p.Massless = true
	end
end

-- A box. `cframe` is the centre.
function PartKit.Box(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	apply(p, opts)
	if opts and opts.Shape then
		p.Shape = opts.Shape
	end
	p.Parent = parent
	return p
end

-- A cylinder whose axis runs along `cframe`'s X (right) vector
function PartKit.Cylinder(parent: Instance, name: string, diameter: number, length: number, cframe: CFrame, color: Color3, material: Enum.Material, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	apply(p, opts)
	p.Parent = parent
	return p
end

-- An upright cylinder (axis vertical) standing on `base`
function PartKit.Post(parent: Instance, name: string, diameter: number, height: number, base: Vector3, color: Color3, material: Enum.Material, opts: Opts?): Part
	local cf = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	return PartKit.Cylinder(parent, name, diameter, height, cf, color, material, opts)
end

function PartKit.Ball(parent: Instance, name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = CFrame.new(position)
	p.Color = color
	p.Material = material
	apply(p, opts)
	p.Parent = parent
	return p
end

-- A frame at `from` whose -Z points at `to` (robust when the two are straight above each other)
function PartKit.LookAt(from: Vector3, to: Vector3): CFrame
	local dir = to - from
	if dir.Magnitude < 1e-6 then
		return CFrame.new(from)
	end
	local up = Vector3.yAxis
	if math.abs(dir.Unit:Dot(up)) > 0.99 then
		up = Vector3.zAxis
	end
	return CFrame.lookAt(from, to, up)
end

-- A round tube from `a` to `b`
function PartKit.Tube(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material, opts: Opts?): Part
	local length = (b - a).Magnitude
	local cf = PartKit.LookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	return PartKit.Cylinder(parent, name, diameter, math.max(length, 0.01), cf, color, material, opts)
end

-- A square-section bar from `a` to `b` (`width` across, `height` up)
function PartKit.Bar(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, height: number, color: Color3, material: Enum.Material, opts: Opts?): Part
	local length = (b - a).Magnitude
	local cf = PartKit.LookAt((a + b) / 2, b)
	return PartKit.Box(parent, name, Vector3.new(width, height, math.max(length, 0.01)), cf, color, material, opts)
end

-- A flat slab whose TOP surface runs along the line from `from` to `to` (a ramp or a roof plane)
function PartKit.Slab(parent: Instance, name: string, from: Vector3, to: Vector3, width: number, thickness: number, color: Color3, material: Enum.Material, opts: Opts?): Part
	local length = (to - from).Magnitude
	local cf = PartKit.LookAt((from + to) / 2, to)
	cf *= CFrame.new(0, -thickness / 2, 0)
	return PartKit.Box(parent, name, Vector3.new(width, thickness, length), cf, color, material, opts)
end

-- A solid ramp: a thick block whose top face rises from `low` to `high` (both on the top face's
-- centre line). The block's underside runs into the ground below `low`, so it reads as a solid
-- mound from the side without needing wedge parts. Returns the riding surface part.
function PartKit.Ramp(parent: Instance, name: string, low: Vector3, high: Vector3, width: number, color: Color3, material: Enum.Material, opts: Opts?): Part
	local rise = high.Y - low.Y
	local run = (Vector3.new(high.X, 0, high.Z) - Vector3.new(low.X, 0, low.Z)).Magnitude
	local slope = math.atan2(rise, run)
	-- thick enough that the back edge reaches the ground
	local thickness = math.max(1, rise / math.max(math.cos(slope), 0.2) + 1)
	return PartKit.Slab(parent, name, low, high, width, thickness, color, material, opts)
end

-- Text on one face of a part
function PartKit.Sign(part: BasePart, face: Enum.NormalId, text: string, textColor: Color3, background: Color3?, font: Enum.Font?, pixelsPerStud: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 20
	gui.LightInfluence = 0.2
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	if background then
		label.BackgroundColor3 = background
	end
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.FontFace = Font.fromEnum(font or Enum.Font.FredokaOne)
	label.Parent = gui
	return label
end

-- Moves a freshly built, unwelded model (built around the origin) to `cframe`. Works under Lune,
-- which has no PivotTo; runtime code with welded models uses Model:PivotTo instead.
function PartKit.PlaceStatic(model: Instance, cframe: CFrame)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cframe * d.CFrame
		end
	end
end

-- Scales a built (static) model about the world origin: positions, sizes, attachments, light
-- ranges, prompt distances; SurfaceGui text keeps its size on screen
function PartKit.Scale(root: Instance, k: number)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			d.Size *= k
			d.CFrame = CFrame.new(cf.Position * k) * (cf - cf.Position)
		elseif d:IsA("Attachment") then
			d.Position *= k
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Range *= k
		elseif d:IsA("SurfaceGui") then
			d.PixelsPerStud /= k
		elseif d:IsA("ProximityPrompt") then
			d.MaxActivationDistance *= k
		end
	end
end

function PartKit.Model(parent: Instance?, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

function PartKit.Folder(parent: Instance?, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	if parent then
		f.Parent = parent
	end
	return f
end

function PartKit.Attach(parent: BasePart, name: string, worldPosition: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = parent.CFrame:PointToObjectSpace(worldPosition)
	a.Parent = parent
	return a
end

return PartKit
