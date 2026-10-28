--[[
	CityKit: puts the Blender city kit (blender/citykit.py, "Kit_*" in Vehicles.fbx) on the city in
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
]]

local MeshKit = require(script.Parent.MeshKit)

local CityKit = {}

local WINDOW_FRAME = Vector3.new(5.7, 7.2, 0.3)
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
-- (less `centre`) scaled by `scale`, sized by `scale`; Paint takes `paint`
local function place(pieces: { Piece }, parent: Instance, origin: CFrame, centre: Vector3, scale: Vector3, paint: Color3, turn: number): { MeshPart }
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
		part.CastShadow = true
		local slot = MeshKit.Slots[e.Slot]
		if e.Slot == "Paint" then
			part.Color = paint
			part.Material = Enum.Material.SmoothPlastic
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

-- Windows: fit the surround to the frame; drop the sill under it; set the glass into the reveal
local function windows(frames: { BasePart }, sills: { [string]: BasePart }, panes: { [string]: BasePart }, pieces: { Piece }, turn: number, pace: () -> ())
	local function key(p: Vector3): string
		return string.format("%d,%d,%d", math.round(p.X * 2), math.round(p.Y * 2), math.round(p.Z * 2))
	end
	for _, frame in frames do
		local cf = frame.CFrame
		-- the city may be built bigger than its design (Builder's WORLD_SCALE): the frame's depth
		-- (0.3 in design units) says by how much
		local k = frame.Size.Z / WINDOW_FRAME.Z
		local scale = Vector3.new(frame.Size.X / WINDOW_FRAME.X, frame.Size.Y / WINDOW_FRAME.Y, k)
		place(pieces, frame.Parent :: Instance, cf, Vector3.zero, scale, frame.Color, turn)
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
	local function key(p: Vector3): string
		return string.format("%d,%d,%d", math.round(p.X * 2), math.round(p.Y * 2), math.round(p.Z * 2))
	end
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") then
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
		windows(frames, sills, panes, windowKit, turn, step)
		done += #frames
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
