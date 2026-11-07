--[[
	PartKit: small helpers for building things out of parts (the city, bikes, cars, menu icons).
	Everything is created anchored unless told otherwise; models that move weld themselves later.
	Works under Lune as well (the city is baked offline), so it only sets plain properties.
]]

local Config = require(script.Parent.Config)
local Surfaces = require(script.Parent.Surfaces)

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

-- Marks `part` as the stand-in for a city kit mesh ("Kit_<kit>" in the Blender import): Models/
-- CityKit fits the mesh to the part's box when the owner has imported it, and the part stays as it
-- is when they haven't. The kit is modelled up its +Y with its front toward -Z; `up` and `out`
-- name the part's own axes that play those roles ("+X", "-Z"...) when they differ (a PartKit.Post
-- stands on its X axis).
function PartKit.Kit<T>(part: T, kit: string, up: string?, out: string?): T
	local p = part :: any
	p:SetAttribute("Kit", kit)
	if up then
		p:SetAttribute("KitUp", up)
	end
	if out then
		p:SetAttribute("KitOut", out)
	end
	return part
end

-- Marks `part` as trim that the kit mesh "Kit_<kit>" draws itself: it goes when that kit is imported
function PartKit.KitDrop<T>(part: T, kit: string): T
	(part :: any):SetAttribute("KitDrop", kit)
	return part
end

-- A named facade material (Shared/Materials.Facade: "RealStucco", "RealBrickOld"...) for a share of
-- the buildings, picked by where `at` is (x, z) so it takes nothing from the builders' random
-- streams; nil for the rest. Give it to the building's walls with PartKit.Wear.
function PartKit.FacadeFor(at: Vector3, variant: string, share: number): string?
	local h = math.abs(math.sin(at.X * 12.9898 + at.Z * 78.233) * 43758.5453) % 1
	return if h < share then variant else nil
end

-- The realism pack's named materials (blender/textures.py, `named`) and the base material each is a
-- variant of: a part shows one only while its own material is that base (PartKit.Dress sets both)
PartKit.NAMED = {
	RealStucco = Enum.Material.Plaster,
	RealBrickOld = Enum.Material.Brick,
	RealConcreteBoard = Enum.Material.Concrete,
	RealCorrugated = Enum.Material.Metal,
	-- the detail pass (Textures2.fbx)
	RealAsphaltWorn = Enum.Material.Asphalt,
	RealConcreteDeck = Enum.Material.Concrete,
	RealRoadPaint = Enum.Material.SmoothPlastic,
	RealBrickPavers = Enum.Material.Brick,
	RealCoralStone = Enum.Material.Limestone,
	RealCoralRubble = Enum.Material.Limestone,
	RealStuccoStreaked = Enum.Material.Plaster,
	RealPaintedBlock = Enum.Material.Concrete,
	RealWoodSiding = Enum.Material.Wood,
	RealGraniteCladding = Enum.Material.Granite,
	RealPoolTile = Enum.Material.CeramicTiles,
	RealTerrazzo = Enum.Material.Marble,
	RealRoofMembrane = Enum.Material.SmoothPlastic,
	RealGravel = Enum.Material.Pebble,
	RealMetalRoof = Enum.Material.Metal,
	RealMulch = Enum.Material.Ground,
	RealWetSand = Enum.Material.Sand,
	RealRustySteel = Enum.Material.CorrodedMetal,
	RealContainerPaint = Enum.Material.Metal,
	RealMarineConcrete = Enum.Material.Concrete,
	RealHedge = Enum.Material.Grass,
	RealPlanksWeathered = Enum.Material.WoodPlanks,
	RealTactilePaving = Enum.Material.SmoothPlastic,
} :: { [string]: Enum.Material }
-- the ones with a quarter-turned copy ("<Name>90": boards, seams, corrugations run the other way)
PartKit.TURNABLE = { RealWoodSiding = true, RealMetalRoof = true, RealContainerPaint = true, RealPlanksWeathered = true } :: { [string]: boolean }

-- Dresses a part in a named material: its base material and the variant's name (the turned copy if
-- `turned`, flipped again where Config.Realism.TurnedNamed says the pattern runs the wrong way in
-- Studio), and a colour if given. The part keeps the kind of ground it was to the bike and the
-- police (Shared/Surfaces): if the new material would change that, its "Surface" attribute holds
-- the old one. Without the pack the part just shows its base material. Returns the part.
function PartKit.Dress<T>(part: T, name: string, color: Color3?, turned: boolean?): T
	local p = part :: any
	local base = PartKit.NAMED[name]
	if not base then
		return part
	end
	local before = Surfaces.Of(p)
	p.Material = base
	local flip = (turned == true) ~= (Config.Realism.TurnedNamed[name] == true)
	p.MaterialVariant = if flip and PartKit.TURNABLE[name] then name .. "90" else name
	if color then
		p.Color = color
	end
	if Surfaces.Of(p) ~= before then
		p:SetAttribute("Surface", before)
	end
	return part
end

-- A stable 0..1 number for a spot (x, z), from a salt: picks without touching the random streams
function PartKit.Hash(at: Vector3, salt: number?): number
	local s = salt or 0
	return math.abs(math.sin(at.X * 12.9898 + at.Z * 78.233 + s * 37.719) * 43758.5453) % 1
end

-- Puts a named material (PartKit.FacadeFor) on parts; their base material shows where it's not
-- imported. Returns the first part.
function PartKit.Wear<T>(variant: string?, ...: T): T
	local parts = { ... }
	if variant then
		for _, part in parts do
			(part :: any).MaterialVariant = variant
		end
	end
	return parts[1]
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

-- A wedge (Roblox WedgePart: full height on its +Z face, a slope down to its -Z edge). `cframe` is the centre.
function PartKit.Wedge(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, opts: Opts?): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	apply(p, opts)
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

-- An ellipsoid filling `size` (a sphere mesh on a box part: Ball parts are always round)
function PartKit.Ellipsoid(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, opts: Opts?): Part
	local p = PartKit.Box(parent, name, size, cframe, color, material, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
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
	PartKit.ScaleAbout(root, Vector3.zero, k)
end

-- Scales everything under `root` by `k` about the point `pivot`
function PartKit.ScaleAbout(root: Instance, pivot: Vector3, k: number)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			d.Size *= k
			d.CFrame = CFrame.new(pivot + (cf.Position - pivot) * k) * (cf - cf.Position)
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

-- Cuts every plain block part longer than `limit` studs along a flat-lying axis into equal pieces
-- (an upright axis only past Roblox's 2048-stud cap), each covering its share of the original.
-- Roblox caps a part at 2048 studs a side, and streams a part in by where it is, so the far end
-- of a long slab can be missing under a player riding on it. Returns how many pieces it added.
function PartKit.SplitLarge(root: Instance, limit: number): number
	local added = 0
	for _, d in root:GetDescendants() do
		if d.ClassName ~= "Part" or (d :: Part).Shape ~= Enum.PartType.Block or #d:GetChildren() > 0 then
			continue
		end
		local part = d :: Part
		local cf, size = part.CFrame, part.Size
		local function count(length: number, axis: Vector3): number
			return math.max(1, math.ceil(length / (if math.abs(axis.Y) > 0.7 then 2048 else limit) - 1e-6))
		end
		local nx, ny, nz = count(size.X, cf.RightVector), count(size.Y, cf.UpVector), count(size.Z, cf.LookVector)
		if nx * ny * nz == 1 then
			continue
		end
		local piece = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
		for i = 0, nx - 1 do
			for j = 0, ny - 1 do
				for k = 0, nz - 1 do
					local p = if i + j + k == 0 then part else part:Clone()
					p.Size = piece
					p.CFrame = cf * CFrame.new((i + 0.5) * piece.X - size.X / 2, (j + 0.5) * piece.Y - size.Y / 2, (k + 0.5) * piece.Z - size.Z / 2)
					p.Parent = part.Parent
				end
			end
		end
		added += nx * ny * nz - 1
	end
	return added
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
