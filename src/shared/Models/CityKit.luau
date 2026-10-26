--[[
	CityKit: puts the Blender city kit (blender/citykit.py, "Kit_*" in Vehicles.fbx) on the city in
	place of its part-built placeholders, when the kit has been imported (MeshKit); without it the
	parts stay. Run once by CityService on the server, a few hundred pieces a frame.

	  Window frames  each "WindowFrame" (and its "Sill") becomes the window surround mesh (casing,
	                 sash with glazing bars, moulded sill on corbels, lintel and keystone), fitted to
	                 the frame; the glass ("Window") stays a part, set back into the new reveal, so
	                 the windows still light up at night.
	  Trees          each "Tree" model becomes its species' mesh ("Species" attribute), scaled to the
	                 model and tinted its leaves' colour; the trunk stays as an invisible collider.
	  Lamps          each "Lamp" model becomes the Victorian post; the pole stays as an invisible
	                 collider and the globe stays a part (it glows at night).

	Kit space: windows map onto the WindowFrame part's box (the kit's frame is 5.7 x 7.2 x 0.3 at
	its origin, -Z out of the wall); trees and lamps onto their model's bounding box.
]]

local MeshKit = require(script.Parent.MeshKit)

local CityKit = {}

local WINDOW_FRAME = Vector3.new(5.7, 7.2, 0.3)
local TREES = { Broadleaf = "Kit_Tree_Broadleaf", Birch = "Kit_Tree_Birch", Conifer = "Kit_Tree_Conifer" }

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
			end
		elseif d:IsA("Model") then
			if d.Name == "Tree" then
				table.insert(trees, d)
			elseif d.Name == "Lamp" then
				table.insert(lamps, d)
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
		local pieces = MeshKit.Pieces(TREES[if type(species) == "string" then species else "Broadleaf"] or TREES.Broadleaf)
		if not pieces then
			continue
		end
		local cf, size = model:GetBoundingBox()
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
			local cf, size = model:GetBoundingBox()
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
	return done
end

return CityKit
