--[[
	GeoWorld: a stand-in for client/World.luau's World.Physics over real part geometry, for riding the
	baked city offline (tools/lune/ride_ramps.luau). Rays hit blocks, wedges and balls exactly
	(cylinders as their box); body sweeps step a box along the move and test it against each part's
	box (separating axes), ignoring parts the box already overlaps at the start, like Blockcast.
	The surface and wall rules are copied from client/World.luau.
]]

local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local GeoWorld = {}

local CELL = 48

local MATERIALS: { [string]: string } = {
	Asphalt = "Road",
	Pavement = "Sidewalk",
	Concrete = "Sidewalk",
	Cobblestone = "Sidewalk",
	Brick = "Sidewalk",
	Marble = "Sidewalk",
	Granite = "Sidewalk",
	Slate = "Sidewalk",
	Grass = "Grass",
	LeafyGrass = "Grass",
	Ground = "Dirt",
	Mud = "Mud",
	Sand = "Sand",
	WoodPlanks = "Ramp",
	Wood = "Ramp",
	DiamondPlate = "Ramp",
	Metal = "Ramp",
}
local NATURAL = { Grass = true, LeafyGrass = true, Ground = true, Sand = true, Mud = true }

local function surfaceOf(part: any): string
	local tagged = part:GetAttribute("Surface")
	if type(tagged) == "string" then
		return tagged
	end
	return MATERIALS[part.Material.Name] or "Road"
end

local function kindOf(part: any): string
	local size = part.Size
	if math.max(size.X, size.Y, size.Z) < 7 and part:GetAttribute("Surface") == nil then
		return "Prop"
	end
	return "Wall"
end

local function rideable(part: any): boolean
	if NATURAL[part.Material.Name] or part:GetAttribute("Surface") == "Ramp" then
		return true
	end
	if part.ClassName == "Part" and part.Shape.Name ~= "Block" then
		return false
	end
	local cf = part.CFrame
	local top = math.max(math.abs(cf.RightVector.Y), math.abs(cf.UpVector.Y), math.abs(cf.LookVector.Y))
	return top > 0.3 and top < 0.995
end
GeoWorld.Rideable = rideable

type Entry = { Part: any, CF: any, Inv: any, Half: any, Shape: string, Min: any, Max: any }

-- `water` (optional): the water surface's height at (x, z), or nil where there's none (the game's
-- Terrain water isn't in the baked model)
function GeoWorld.new(root: any, water: ((number, number) -> number?)?)
	local self = { Cells = {} :: { [number]: { Entry } }, Count = 0, Stats = { Rays = 0, Sweeps = 0 } }
	local function key(i: number, j: number): number
		return (i + 4096) * 8192 + (j + 4096)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and d.CanQuery then
			local cf, size = d.CFrame, d.Size
			local half = size / 2
			-- world AABB of the oriented box
			local ex = math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z
			local ey = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
			local ez = math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z
			local p = cf.Position
			local shape = if d.ClassName == "WedgePart" then "Wedge" elseif d.ClassName == "Part" then d.Shape.Name else "Block"
			local e: Entry = { Part = d, CF = cf, Inv = cf:Inverse(), Half = half, Shape = shape, Min = Vector3.new(p.X - ex, p.Y - ey, p.Z - ez), Max = Vector3.new(p.X + ex, p.Y + ey, p.Z + ez) }
			for i = math.floor(e.Min.X / CELL), math.floor(e.Max.X / CELL) do
				for j = math.floor(e.Min.Z / CELL), math.floor(e.Max.Z / CELL) do
					local k = key(i, j)
					local list = self.Cells[k]
					if not list then
						list = {}
						self.Cells[k] = list
					end
					table.insert(list, e)
				end
			end
			self.Count += 1
		end
	end

	local function near(minX: number, minZ: number, maxX: number, maxZ: number): { Entry }
		local out, seen = {}, {}
		for i = math.floor(minX / CELL), math.floor(maxX / CELL) do
			for j = math.floor(minZ / CELL), math.floor(maxZ / CELL) do
				local list = self.Cells[key(i, j)]
				if list then
					for _, e in list do
						if not seen[e] then
							seen[e] = true
							table.insert(out, e)
						end
					end
				end
			end
		end
		return out
	end

	-- ray against one part (local space slabs, plus the wedge's slope plane); returns t and local normal
	local function rayPart(e: Entry, origin: any, dir: any): (number?, any)
		local o = e.Inv * origin
		local d = e.Inv:VectorToWorldSpace(dir)
		local h = e.Half
		if e.Shape == "Ball" then
			local r = math.min(h.X, h.Y, h.Z)
			local b = o:Dot(d)
			local c = o:Dot(o) - r * r
			local disc = b * b - c
			if disc < 0 then
				return nil, nil
			end
			local t = -b - math.sqrt(disc)
			if t < 0 then
				return nil, nil
			end
			return t, (o + d * t).Unit
		end
		local tmin, tmax = -math.huge, math.huge
		local nmin = nil
		local planes = {
			{ Vector3.new(1, 0, 0), h.X },
			{ Vector3.new(-1, 0, 0), h.X },
			{ Vector3.new(0, 1, 0), h.Y },
			{ Vector3.new(0, -1, 0), h.Y },
			{ Vector3.new(0, 0, 1), h.Z },
			{ Vector3.new(0, 0, -1), h.Z },
		}
		if e.Shape == "Wedge" then
			-- y/h.Y - z/h.Z <= 0
			local n = Vector3.new(0, 1 / h.Y, -1 / h.Z)
			local len = n.Magnitude
			table.insert(planes, { n / len, 0 })
		end
		for _, pl in planes do
			local n, dist = pl[1], pl[2]
			local denom = n:Dot(d)
			local num = dist - n:Dot(o)
			if math.abs(denom) < 1e-9 then
				if num < 0 then
					return nil, nil
				end
			else
				local t = num / denom
				if denom < 0 then
					if t > tmin then
						tmin = t
						nmin = n
					end
				else
					if t < tmax then
						tmax = t
					end
				end
			end
		end
		if tmin > tmax or tmax < 0 or tmin < 0 or nmin == nil then
			return nil, nil
		end
		return tmin, nmin
	end

	function self.Raycast(origin: any, direction: any): any
		self.Stats.Rays += 1
		local length = direction.Magnitude
		local dir = direction / length
		local a, b = origin, origin + direction
		local best, bestT, bestN = nil, length, nil
		for _, e in near(math.min(a.X, b.X), math.min(a.Z, b.Z), math.max(a.X, b.X), math.max(a.Z, b.Z)) do
			if e.Max.Y >= math.min(a.Y, b.Y) and e.Min.Y <= math.max(a.Y, b.Y) then
				local t, n = rayPart(e, origin, dir)
				if t and t <= bestT then
					best, bestT, bestN = e, t, n
				end
			end
		end
		if not best then
			return nil
		end
		return { Instance = best.Part, Position = origin + dir * bestT, Normal = best.CF:VectorToWorldSpace(bestN), Distance = bestT }
	end

	-- separating-axis overlap of two oriented boxes; returns overlap and, per part axis, penetration
	local function overlap(acf: any, ah: any, e: Entry): boolean
		local bcf, bh = e.CF, e.Half
		local A = { acf.RightVector, acf.UpVector, acf.LookVector }
		local B = { bcf.RightVector, bcf.UpVector, bcf.LookVector }
		local ae = { ah.X, ah.Y, ah.Z }
		local be = { bh.X, bh.Y, bh.Z }
		local t = bcf.Position - acf.Position
		local axes = {}
		for i = 1, 3 do
			table.insert(axes, A[i])
			table.insert(axes, B[i])
		end
		for i = 1, 3 do
			for j = 1, 3 do
				local c = A[i]:Cross(B[j])
				if c.Magnitude > 1e-6 then
					table.insert(axes, c.Unit)
				end
			end
		end
		for _, L in axes do
			local ra = math.abs(A[1]:Dot(L)) * ae[1] + math.abs(A[2]:Dot(L)) * ae[2] + math.abs(A[3]:Dot(L)) * ae[3]
			local rb = math.abs(B[1]:Dot(L)) * be[1] + math.abs(B[2]:Dot(L)) * be[2] + math.abs(B[3]:Dot(L)) * be[3]
			if math.abs(t:Dot(L)) > ra + rb then
				return false
			end
		end
		return true
	end

	-- the hit face's normal: the part axis the box is least deep along, pointing at the box
	local function hitNormal(acf: any, ah: any, e: Entry): any
		local bcf, bh = e.CF, e.Half
		local A = { acf.RightVector, acf.UpVector, acf.LookVector }
		local ae = { ah.X, ah.Y, ah.Z }
		local B = { bcf.RightVector, bcf.UpVector, bcf.LookVector }
		local be = { bh.X, bh.Y, bh.Z }
		local t = acf.Position - bcf.Position
		local best, bestDepth = B[2], math.huge
		for i = 1, 3 do
			local L = B[i]
			local ra = math.abs(A[1]:Dot(L)) * ae[1] + math.abs(A[2]:Dot(L)) * ae[2] + math.abs(A[3]:Dot(L)) * ae[3]
			local depth = ra + be[i] - math.abs(t:Dot(L))
			if depth < bestDepth then
				bestDepth = depth
				best = if t:Dot(L) >= 0 then L else -L
			end
		end
		return best
	end

	function self.Blockcast(frame: any, size: any, delta: any): any
		self.Stats.Sweeps += 1
		local length = delta.Magnitude
		if length < 1e-6 then
			return nil
		end
		local half = size / 2
		local r = half.Magnitude
		local p0, p1 = frame.Position, frame.Position + delta
		local candidates = {}
		for _, e in near(math.min(p0.X, p1.X) - r, math.min(p0.Z, p1.Z) - r, math.max(p0.X, p1.X) + r, math.max(p0.Z, p1.Z) + r) do
			if e.Max.Y >= math.min(p0.Y, p1.Y) - r and e.Min.Y <= math.max(p0.Y, p1.Y) + r and not overlap(frame, half, e) then
				table.insert(candidates, e)
			end
		end
		if #candidates == 0 then
			return nil
		end
		local steps = math.max(2, math.ceil(length / 0.1))
		local rot = frame - frame.Position
		for k = 1, steps do
			local f = k / steps
			local cf = CFrame.new(p0 + delta * f) * rot
			for _, e in candidates do
				if overlap(cf, half, e) then
					local prev = CFrame.new(p0 + delta * ((k - 1) / steps)) * rot
					return { Instance = e.Part, Distance = length * (k - 1) / steps, Normal = hitNormal(prev, half, e), Position = prev.Position }
				end
			end
		end
		return nil
	end

	-- the BikePhysics.World adapter, as client/World.luau builds it
	self.Physics = {
		Down = function(origin: any, length: number): any
			local hit = self.Raycast(origin, Vector3.new(0, -length, 0))
			local surface = if water then water(origin.X, origin.Z) else nil
			if surface and origin.Y >= surface and origin.Y - length <= surface and (not hit or hit.Position.Y < surface) then
				return { Position = Vector3.new(origin.X, surface, origin.Z), Normal = Vector3.new(0, 1, 0), Kind = "Water" }
			end
			if not hit then
				return nil
			end
			return { Position = hit.Position, Normal = hit.Normal, Kind = surfaceOf(hit.Instance), Part = hit.Instance }
		end,
		Sweep = function(frame: any, size: any, delta: any): (number?, any, string?)
			local hit = self.Blockcast(frame, size, delta)
			if not hit then
				return nil, nil, nil
			end
			self.LastSweepPart = hit.Instance
			if rideable(hit.Instance) then
				return hit.Distance, Vector3.new(0, 1, 0), "Slope"
			end
			return hit.Distance, hit.Normal, kindOf(hit.Instance)
		end,
		Loop = nil,
	}
	return self
end

return GeoWorld
