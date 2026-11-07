--[[
	CityKit: puts the Blender city kit (blender/citykit.py, "Kit_*" in CityKit.fbx) on the city in
	place of its part-built placeholders, when the kit has been imported (MeshKit); without it the
	parts stay. Run once by CityService on the server, a few hundred pieces a frame.

	  Window frames  each "WindowFrame" (and its "Sill") becomes the window surround mesh (casing,
	                 sash with glazing bars, moulded sill on corbels, lintel and keystone), fitted to
	                 the frame; the glass ("Window") stays a part, set back into the new reveal, so
	                 the windows still light up at night.
	  Trees, palms   each "Tree", "Palm" and "Pine" model becomes its species' textured mesh from
	                 the realism pack (blender/vegetation.py: live oaks, coconut and royal palms,
	                 slash pines), scaled to the model's height and turned to its trunk's lean; the
	                 trunk stays as an invisible collider. (An older import's flat-coloured trees,
	                 "Kit_Tree_<Species>", are used if that's all there is.)
	  Lamps          each "Lamp" model becomes the Victorian post; the pole stays as an invisible
	                 collider and the globe stays a part (it glows at night).

	Kit space: windows map onto the WindowFrame part's box (the kit's frame is 5.7 x 7.2 x 0.3 at
	its origin, -Z out of the wall); trees and lamps onto their model's bounding box.

	  Stand-ins      any part the builders marked with PartKit.Kit (a "Kit" attribute): shopfront
	                 mullions, transoms, fascias, bulkheads, doors and awnings, house windows,
	                 shutters, doors, garage doors, porch posts and columns, rooftop AC units,
	                 street light poles, arms and heads, traffic signal heads. The kit
	                 (blender/facadekit.py) is fitted to the part's box (KitSpec says the box it was
	                 modelled on; tiled kits repeat along the part, each module in proportion); its
	                 Paint takes the part's colour and material. A part that collides stays as an
	                 invisible collider, the rest go. Parts marked PartKit.KitDrop (trim a kit draws
	                 itself: an AC unit's fan, a garage door's panel lines) go when that kit is there.
	                 Detail.Windows frames can name their surround (the "WindowKit" attribute:
	                 Window_Modern for stucco), falling back to the classical one.
]]

local CollectionService = game:GetService("CollectionService")

local MeshKit = require(script.Parent.MeshKit)
local KitSpec = require(script.Parent.KitSpec)

local CityKit = {}

local WINDOW_FRAME = Vector3.new(5.7, 7.2, 0.3)
-- a stand-in's axes by name (PartKit.Kit's `up` and `out`)
local AXES: { [string]: Vector3 } = {
	["+X"] = Vector3.new(1, 0, 0),
	["-X"] = Vector3.new(-1, 0, 0),
	["+Y"] = Vector3.new(0, 1, 0),
	["-Y"] = Vector3.new(0, -1, 0),
	["+Z"] = Vector3.new(0, 0, 1),
	["-Z"] = Vector3.new(0, 0, -1),
}
local TREES = { Broadleaf = "Kit_Tree_Broadleaf", Birch = "Kit_Tree_Birch", Conifer = "Kit_Tree_Conifer" }
-- the realism pack's vegetation by model name and species ("Default" when there's no species)
local VEGETATION: { [string]: { [string]: string } } = {
	Tree = { Broadleaf = "Kit_Tree_Oak", Birch = "Kit_Tree_OakTall", Conifer = "Kit_Tree_Pine", Default = "Kit_Tree_Oak" },
	Palm = { Coconut = "Kit_Palm_Coconut", Royal = "Kit_Palm_Royal", Default = "Kit_Palm_Coconut" },
	Pine = { Default = "Kit_Tree_Pine" },
}

type Piece = MeshKit.Piece

local function bounds(pieces: { Piece }): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, piece in pieces do
		local e = piece.Entry
		lo = lo:Min(e.Center - e.Size / 2)
		hi = hi:Max(e.Center + e.Size / 2)
	end
	return (lo + hi) / 2, hi - lo
end

-- Clone a kit's meshes into `parent`: each piece offset from `origin` by its kit-space centre
-- (less `centre`) scaled by `scale`, sized by `scale`; Paint takes `paint` (and `paintMaterial`,
-- smooth plastic by default); `shadow` false keeps small trim out of the shadow map
local function place(pieces: { Piece }, parent: Instance, origin: CFrame, centre: Vector3, scale: Vector3, paint: Color3, turn: number, paintMaterial: Enum.Material?, shadow: boolean?): { MeshPart }
	local out = {}
	for _, piece in pieces do
		local e = piece.Entry
		local part = piece.Source:Clone()
		for _, child in part:GetChildren() do
			if not child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		part.Name = "Kit_" .. e.Slot
		part.Size = e.Size * scale
		part.CFrame = origin * CFrame.new((e.Center - centre) * scale) * (if turn == 180 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = shadow ~= false
		local slot = MeshKit.Slots[e.Slot]
		if e.Slot == "Paint" then
			part.Color = paint
			part.Material = paintMaterial or Enum.Material.SmoothPlastic
		elseif slot then
			part.Color = slot.Color
			part.Material = slot.Material
		end
		part.Parent = parent
		table.insert(out, part)
	end
	return out
end

-- A model's box in `frame`'s axes (Roblox's own GetBoundingBox takes its axes from the model's
-- pivot, which for these is a pole or trunk lying on its side: a rotated cylinder)
local function boxIn(model: Instance, frame: CFrame): (CFrame, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local half = part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)))
						lo = lo:Min(p)
						hi = hi:Max(p)
					end
				end
			end
		end
	end
	return frame * CFrame.new((lo + hi) / 2), hi - lo
end

local function hide(part: BasePart)
	part.Transparency = 1
	part.CastShadow = false
end

-- A stand-in's kit frame: its CFrame turned so the kit's +Y is the part's `KitUp` axis and the kit's
-- -Z its `KitOut` axis, and the part's size along the kit's axes
local function kitFrame(part: BasePart): (CFrame, Vector3)
	local upName, outName = part:GetAttribute("KitUp"), part:GetAttribute("KitOut")
	local up = (if type(upName) == "string" then AXES[upName] else nil) or AXES["+Y"]
	local out = (if type(outName) == "string" then AXES[outName] else nil) or AXES["-Z"]
	local z = -out
	local x = up:Cross(z)
	local size = part.Size
	local function along(v: Vector3): number
		return math.abs(v.X) * size.X + math.abs(v.Y) * size.Y + math.abs(v.Z) * size.Z
	end
	return part.CFrame * CFrame.fromMatrix(Vector3.zero, x, up, z), Vector3.new(along(x), along(up), along(z))
end

-- Fit a kit to its stand-in: stretched to the part's box, or (a tiled kit) laid along it as many
-- modules as fit at the module's own proportions. Returns false if the part's box can't take it.
-- Kits that only add detail over what's already there (no hole when they're hidden): tagged
-- "KitFine" so Performance mode can hide them on that device (Client/Graphics)
CityKit.FINE = { Cornice = true, StringCourse = true, IronRail = true, Shutter = true, DecoEyebrow = true, TowerMullion = true, ACUnit = true, LightBase = true } :: { [string]: boolean }
CityKit.FINE_TAG = "KitFine"

local function tagFine(parts: { MeshPart })
	for _, p in parts do
		CollectionService:AddTag(p, CityKit.FINE_TAG)
	end
end

local function fit(part: BasePart, pieces: { Piece }, spec: KitSpec.Spec, turn: number, fine: boolean?): boolean
	local frame, size = kitFrame(part)
	local ref = spec.Reference
	if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		return false
	end
	local scale = Vector3.new(size.X / ref.X, size.Y / ref.Y, size.Z / ref.Z)
	local n = 1
	if spec.Tile then
		local k = if spec.Tile == "Z" then scale.Z else scale.Y
		n = math.max(1, math.round(size.X / (ref.X * k)))
		scale = Vector3.new(size.X / n / ref.X, scale.Y, scale.Z)
	end
	local parent = part.Parent :: Instance
	for i = 1, n do
		local x = -size.X / 2 + (i - 0.5) * size.X / n
		local placed = place(pieces, parent, frame * CFrame.new(x, 0, 0), Vector3.zero, scale, part.Color, turn, part.Material, part.CastShadow)
		if fine then
			tagFine(placed)
		end
	end
	return true
end

-- A ring kit (a cornice) round its stand-in's box, the box being the ring's outside: each wall lies
-- the kit's projection (scaled) inside it; modules tile along the four walls at their proportions
-- and the corner kit fills each corner. Returns false if the box can't take it.
local function ring(part: BasePart, pieces: { Piece }, corner: { Piece }?, spec: KitSpec.Spec, turn: number, fine: boolean?): boolean
	local size, ref = part.Size, spec.Reference
	local k = size.Y / ref.Y
	local proj = ref.Z * k
	local a, b = size.X / 2 - proj, size.Z / 2 - proj
	if k <= 0 or a <= 0 or b <= 0 then
		return false
	end
	local parent, cf = part.Parent :: Instance, part.CFrame
	-- each wall's frame (its kit -Z pointing out of the building) and length
	local walls: { { Frame: CFrame, Length: number } } = {
		{ Frame = CFrame.new(0, 0, -b), Length = 2 * a },
		{ Frame = CFrame.new(0, 0, b) * CFrame.Angles(0, math.pi, 0), Length = 2 * a },
		{ Frame = CFrame.new(a, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), Length = 2 * b },
		{ Frame = CFrame.new(-a, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), Length = 2 * b },
	}
	for _, wall in walls do
		local frame, length = wall.Frame, wall.Length
		local n = math.max(1, math.round(length / (ref.X * k)))
		local scale = Vector3.new(length / n / ref.X, k, k)
		for i = 1, n do
			local placed = place(pieces, parent, cf * frame * CFrame.new(-length / 2 + (i - 0.5) * length / n, 0, 0), Vector3.zero, scale, part.Color, turn, part.Material, part.CastShadow)
			if fine then
				tagFine(placed)
			end
		end
	end
	if corner then
		-- (the corner kit sits outside the walls' corner: its -Z out of one wall, its +X out of the next)
		local corners = { CFrame.new(a, 0, -b), CFrame.new(a, 0, b) * CFrame.Angles(0, -math.pi / 2, 0), CFrame.new(-a, 0, b) * CFrame.Angles(0, math.pi, 0), CFrame.new(-a, 0, -b) * CFrame.Angles(0, math.pi / 2, 0) }
		for _, c in corners do
			local placed = place(corner, parent, cf * c, Vector3.zero, Vector3.new(k, k, k), part.Color, turn, part.Material, part.CastShadow)
			if fine then
				tagFine(placed)
			end
		end
	end
	return true
end

-- Windows: fit the surround to the frame; drop the sill under it; set the glass into the reveal
local function windows(frames: { BasePart }, sills: { [string]: BasePart }, panes: { [string]: BasePart }, pieces: { Piece }, turn: number, pace: () -> (), styled: { [string]: { Piece } }?)
	local function key(p: Vector3): string
		return string.format("%d,%d,%d", math.round(p.X * 2), math.round(p.Y * 2), math.round(p.Z * 2))
	end
	for _, frame in frames do
		local cf = frame.CFrame
		-- the city may be built bigger than its design (Builder's WORLD_SCALE): the frame's depth
		-- (0.3 in design units) says by how much
		local k = frame.Size.Z / WINDOW_FRAME.Z
		local scale = Vector3.new(frame.Size.X / WINDOW_FRAME.X, frame.Size.Y / WINDOW_FRAME.Y, k)
		-- the surround Detail.Windows asked for (its style's Kit), if that one's imported
		local style = frame:GetAttribute("WindowKit")
		local own = if styled and type(style) == "string" then styled[style] else nil
		place(own or pieces, frame.Parent :: Instance, cf, Vector3.zero, scale, frame.Color, turn)
		-- (Detail.Windows, design units: the frame sits at at * (0, 0, -0.1), the pane at
		-- at * (0, 0, -0.2), the sill at at * (0, -H / 2 - 0.45, -0.35), H the pane's height)
		local at = cf * CFrame.new(0, 0, 0.1 * k)
		local h = frame.Size.Y / k - 0.7
		local sill = sills[key((at * CFrame.new(0, (-h / 2 - 0.45) * k, -0.35 * k)).Position)]
		if sill then
			sill:Destroy()
		end
		local pane = panes[key((at * CFrame.new(0, 0, -0.2 * k)).Position)]
		if pane then
			pane.Size = Vector3.new(pane.Size.X, pane.Size.Y, 0.05 * k)
			pane.CFrame = at * CFrame.new(0, 0, -0.03 * k)
		end
		frame:Destroy()
		pace()
	end
end

-- The ends of a model's trunk (its "Trunk" cylinders run along their own X): the lowest and the
-- highest end
local function trunkEnds(model: Instance): (Vector3?, Vector3?)
	local lo: Vector3?, hi: Vector3? = nil, nil
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Trunk" then
			local half = part.CFrame.RightVector * (part.Size.X / 2)
			for _, p in { part.Position + half, part.Position - half } do
				if lo == nil or p.Y < (lo :: Vector3).Y then
					lo = p
				end
				if hi == nil or p.Y > (hi :: Vector3).Y then
					hi = p
				end
			end
		end
	end
	return lo, hi
end

-- A tree or palm: the kit stands on the trunk's foot, as tall as the model, leaning the same way
-- (every vegetation kit leans toward its +X); the trunk stays as the collider, the rest goes
local function plant(model: Model, pieces: { Piece }, turn: number): boolean
	local base, top = trunkEnds(model)
	if not base or not top then
		return false
	end
	local foot, tip = base :: Vector3, top :: Vector3
	local cf, size = boxIn(model, CFrame.new(foot))
	local height = (cf.Position.Y + size.Y / 2) - foot.Y
	local kc, ks = bounds(pieces)
	local kitTop = kc.Y + ks.Y / 2
	if height <= 0 or kitTop <= 0 then
		return false
	end
	local k = height / kitTop
	local lean = Vector3.new(tip.X - foot.X, 0, tip.Z - foot.Z)
	local yaw
	if lean.Magnitude > 0.005 * height then
		yaw = math.atan2(-lean.Z, lean.X)
	else
		-- upright (royal palms, trees): a steady turn from where it stands, so neighbours differ
		yaw = ((foot.X * 12.9898 + foot.Z * 78.233) % 6.2832)
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			if part.Name == "Trunk" then
				hide(part)
			else
				part:Destroy()
			end
		end
	end
	place(pieces, model, CFrame.new(foot) * CFrame.Angles(0, yaw, 0), Vector3.zero, Vector3.new(k, k, k), Color3.new(0, 0, 0), turn)
	return true
end

-- Apply the kit to a city (the baked map or a fresh build). Returns how many pieces it replaced.
function CityKit.Apply(city: Instance, pace: (() -> ())?): number
	local step = pace or function() end
	-- the half turn the importer may have given the whole file (read from the vehicles, which
	-- CityService checks first)
	local turn = MeshKit.ImportTurn()
	local done = 0
	local frames: { BasePart } = {}
	local sills: { [string]: BasePart } = {}
	local panes: { [string]: BasePart } = {}
	local trees: { Model } = {}
	local lamps: { Model } = {}
	local benches: { Model } = {}
	local hydrants: { Model } = {}
	local loose: { [string]: { BasePart } } = {}
	local LOOSE = { Bin = true, BinLid = true, Bollard = true, BollardBand = true, MeterPole = true, Meter = true }
	local standIns: { BasePart } = {}
	local drops: { BasePart } = {}
	local function key(p: Vector3): string
		return string.format("%d,%d,%d", math.round(p.X * 2), math.round(p.Y * 2), math.round(p.Z * 2))
	end
	-- the stand-ins' kits, looked up once each (false: not in this import)
	local kits: { [string]: { Piece } | false } = {}
	local missing: { string } = {}
	local function kitPieces(name: string): { Piece }?
		local cached = kits[name]
		if cached == nil then
			local found: { Piece }? = if KitSpec["Kit_" .. name] then MeshKit.Pieces("Kit_" .. name) else nil
			if found then
				kits[name] = found
				return found
			end
			kits[name] = false
			table.insert(missing, "Kit_" .. name)
			return nil
		end
		if type(cached) == "table" then
			return cached
		end
		return nil
	end
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") then
			local kit, drop = d:GetAttribute("Kit"), d:GetAttribute("KitDrop")
			if type(kit) == "string" and kitPieces(kit) then
				-- (a house's window frame with its own kit imported skips the classical surround)
				table.insert(standIns, d)
				continue
			elseif type(drop) == "string" then
				table.insert(drops, d)
			end
			if d.Name == "WindowFrame" then
				table.insert(frames, d)
			elseif d.Name == "Sill" then
				sills[key(d.Position)] = d
			elseif d.Name == "Window" then
				panes[key(d.Position)] = d
			elseif LOOSE[d.Name] and (d:FindFirstAncestorWhichIsA("Model") == nil or d:FindFirstAncestorWhichIsA("Model") == city) then
				local list = loose[d.Name] or {}
				table.insert(list, d)
				loose[d.Name] = list
			end
		elseif d:IsA("Model") then
			if d.Name == "Tree" or d.Name == "Palm" or d.Name == "Pine" then
				table.insert(trees, d)
			elseif d.Name == "Lamp" then
				table.insert(lamps, d)
			elseif d.Name == "Bench" then
				table.insert(benches, d)
			elseif d.Name == "Hydrant" then
				table.insert(hydrants, d)
			end
		end
	end

	local windowKit = MeshKit.Pieces("Kit_Window")
	if windowKit then
		-- the other surrounds Detail.Windows' styles name (the classical one if one isn't imported)
		local styled: { [string]: { Piece } } = {}
		for _, frame in frames do
			local style = frame:GetAttribute("WindowKit")
			if type(style) == "string" and styled[style] == nil then
				local pieces = MeshKit.Pieces("Kit_" .. style)
				if pieces then
					styled[style] = pieces
				elseif not table.find(missing, "Kit_" .. style) then
					table.insert(missing, "Kit_" .. style)
				end
			end
		end
		windows(frames, sills, panes, windowKit, turn, step, styled)
		done += #frames
	end

	-- the stand-ins (PartKit.Kit) and the trim their kits draw themselves (PartKit.KitDrop)
	for _, part in standIns do
		local name = part:GetAttribute("Kit") :: string
		local pieces = kitPieces(name)
		local spec = KitSpec["Kit_" .. name]
		local placed = false
		if pieces and spec and part.Parent then
			if spec.Ring then
				placed = ring(part, pieces, if spec.Corner then MeshKit.Pieces(spec.Corner) else nil, spec, turn, CityKit.FINE[name])
			else
				placed = fit(part, pieces, spec, turn, CityKit.FINE[name])
			end
		end
		if placed then
			if part.CanCollide then
				hide(part)
			else
				part:Destroy()
			end
			done += 1
			step()
		end
	end
	for _, part in drops do
		if kitPieces(part:GetAttribute("KitDrop") :: string) and part.Parent then
			if part.CanCollide then
				hide(part)
			else
				part:Destroy()
			end
		end
	end
	if #missing > 0 and windowKit then
		table.sort(missing)
		print(string.format("[CityKit] %d city kits aren't in this import yet (their parts stay; re-import CityKit.fbx for them): %s", #missing, table.concat(missing, ", ")))
	end

	for _, model in trees do
		local species = model:GetAttribute("Species")
		local kinds = VEGETATION[model.Name]
		local real = kinds and MeshKit.Pieces(kinds[if type(species) == "string" and kinds[species] then species else "Default"])
		if real then
			if plant(model, real, turn) then
				done += 1
			end
			step()
			continue
		end
		if model.Name ~= "Tree" then
			continue
		end
		local pieces = MeshKit.Pieces(TREES[if type(species) == "string" then species else "Broadleaf"] or TREES.Broadleaf)
		if not pieces then
			continue
		end
		local trunk = model:FindFirstChild("Trunk")
		local cf, size = boxIn(model, CFrame.new(if trunk and trunk:IsA("BasePart") then trunk.Position else Vector3.zero))
		local kc, ks = bounds(pieces)
		local across = (size.X / ks.X + size.Z / ks.Z) / 2
		local scale = Vector3.new(across, size.Y / ks.Y, across)
		-- the leaves' colour: the biggest canopy piece's
		local paint, biggest = Color3.fromRGB(110, 150, 60), 0
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				if part.Name == "Leaves" then
					local v = part.Size.X * part.Size.Y * part.Size.Z
					if v > biggest then
						biggest, paint = v, part.Color
					end
					part:Destroy()
				elseif part.Name == "Trunk" then
					hide(part)
				else
					part:Destroy()
				end
			end
		end
		place(pieces, model, cf, kc, scale, paint, turn)
		done += 1
		step()
	end

	local lampKit = MeshKit.Pieces("Kit_Lamp")
	if lampKit then
		local kc, ks = bounds(lampKit)
		for _, model in lamps do
			local pole = model:FindFirstChild("Pole")
			local cf, size = boxIn(model, CFrame.new(if pole and pole:IsA("BasePart") then pole.Position else Vector3.zero))
			local globe = model:FindFirstChild("Globe")
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") and part ~= globe then
					if part.Name == "Pole" then
						hide(part)
					else
						part:Destroy()
					end
				end
			end
			place(lampKit, model, cf, kc, Vector3.new(size.X / ks.X, size.Y / ks.Y, size.Z / ks.Z), Color3.new(0, 0, 0), turn)
			done += 1
			step()
		end
	end

	-- benches and hydrants (models), bins, bollards and parking meters (loose parts)
	local benchKit = MeshKit.Pieces("Kit_Bench")
	if benchKit then
		local kc, ks = bounds(benchKit)
		for _, model in benches do
			local seat = model:FindFirstChild("Seat")
			if not (seat and seat:IsA("BasePart")) then
				continue
			end
			local cf, size = boxIn(model, CFrame.new(seat.Position) * seat.CFrame.Rotation)
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					if part == seat then
						hide(part)
					else
						part:Destroy()
					end
				end
			end
			place(benchKit, model, cf, kc, Vector3.new(size.X / ks.X, size.Y / ks.Y, size.Z / ks.Z), Color3.new(0, 0, 0), turn)
			done += 1
			step()
		end
	end
	local hydrantKit = MeshKit.Pieces("Kit_Hydrant")
	if hydrantKit then
		local kc, ks = bounds(hydrantKit)
		for _, model in hydrants do
			local body = model:FindFirstChild("Body")
			if not (body and body:IsA("BasePart")) then
				continue
			end
			local cf, size = boxIn(model, CFrame.new(body.Position))
			local paint = body.Color
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					if part == body then
						hide(part)
					else
						part:Destroy()
					end
				end
			end
			local k = size.Y / ks.Y
			place(hydrantKit, model, cf * CFrame.new(0, 0, 0), kc, Vector3.new(k, k, k), paint, turn)
			done += 1
			step()
		end
	end
	-- loose posts: the kit stands on the post's foot, scaled by its height against the design's;
	-- `extra` names the part that sat on it at `extraY` (design units) above the foot
	type PostKit = { Name: string, Kit: string, Length: number, Extra: string, ExtraY: number, Keep: boolean }
	local posts: { PostKit } = {
		{ Name = "Bin", Kit = "Kit_Bin", Length = 3, Extra = "BinLid", ExtraY = 3.15, Keep = true },
		{ Name = "Bollard", Kit = "Kit_Bollard", Length = 2.6, Extra = "BollardBand", ExtraY = 2.15, Keep = true },
		{ Name = "MeterPole", Kit = "Kit_Meter", Length = 3.4, Extra = "Meter", ExtraY = 4.0, Keep = false },
	}
	for _, spec in posts do
		local pieces = MeshKit.Pieces(spec.Kit)
		local list = loose[spec.Name]
		if not pieces or not list then
			continue
		end
		local kc, ks = bounds(pieces)
		local extras: { BasePart } = loose[spec.Extra] or {}
		local byKey: { [string]: BasePart } = {}
		for _, extraPart in extras do
			byKey[key(extraPart.Position)] = extraPart
		end
		for _, part in list do
			local length = part.Size.X -- (posts are cylinders stood on end)
			local k = length / spec.Length
			local foot = part.Position - Vector3.new(0, length / 2, 0)
			local extra = byKey[key(foot + Vector3.new(0, spec.ExtraY * k, 0))]
			local paint = part.Color
			if extra then
				extra:Destroy()
			end
			-- the kit's own foot is its bounds' bottom
			local origin = CFrame.new(foot + Vector3.new(0, (ks.Y / 2) * k, 0))
			place(pieces, part.Parent :: Instance, origin, kc, Vector3.new(k, k, k), paint, turn)
			if spec.Keep then
				hide(part)
			else
				part:Destroy()
			end
			done += 1
			step()
		end
	end
	return done
end

return CityKit
