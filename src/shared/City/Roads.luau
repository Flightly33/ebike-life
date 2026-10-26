--[[
	Roads: carriageways, intersections, markings, crosswalks and traffic signals, from Layout.

	Asphalt tops sit at Layout.ROAD_Y. Markings are thin, non-colliding, non-queryable parts a hair
	above it (bikes' ground rays pass through them).
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Detail = require(script.Parent.Detail)
local PartKit = require(script.Parent.Parent.PartKit)

local Roads = {}

local C = Props.Palette
local ASPHALT = Enum.Material.Asphalt
local SMOOTH = Enum.Material.SmoothPlastic
local MARK = { Collide = false, Query = false, Touch = false, Shadow = false }
local THICK = 0.6 -- asphalt slab thickness
local MARK_Y = Layout.ROAD_Y + 0.025
local PATCH = Color3.fromRGB(72, 74, 78) -- repaired asphalt, darker than the road
local SIGN_GREEN = Color3.fromRGB(28, 104, 62)

-- Street names: the avenues run along Z (grid lines I), the streets along X (lines J)
local AVENUES = { "1st Ave", "2nd Ave", "3rd Ave", "4th Ave", "5th Ave", "6th Ave", "7th Ave", "8th Ave", "9th Ave" }
local STREETS = { "Maple St", "Oak St", "Cedar St", "Elm St", "Birch St", "Willow St", "Aspen St", "Spruce St", "Ash St" }

local function slab(parent: Instance, name: string, center: Vector3, size: Vector3, yaw: number?): Part
	local cf = CFrame.new(center.X, Layout.ROAD_Y - THICK / 2, center.Z) * CFrame.Angles(0, yaw or 0, 0)
	return PartKit.Box(parent, name, Vector3.new(size.X, THICK, size.Z), cf, C.Asphalt, ASPHALT)
end

-- A straight painted line from a to b (flat), `offset` to the right of travel a -> b
local function line(parent: Instance, a: Vector3, b: Vector3, offset: number, width: number, color: Color3)
	local dir = (b - a).Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local p0 = Vector3.new(a.X, MARK_Y, a.Z) + right * offset
	local p1 = Vector3.new(b.X, MARK_Y, b.Z) + right * offset
	local length = (p1 - p0).Magnitude
	if length < 0.5 then
		return
	end
	local cf = CFrame.lookAt((p0 + p1) / 2, p1)
	PartKit.Box(parent, "Line", Vector3.new(width, 0.05, length), cf, color, SMOOTH, MARK)
end

local function dashes(parent: Instance, a: Vector3, b: Vector3, offset: number, dash: number, gap: number, width: number, color: Color3)
	local length = (b - a).Magnitude
	local count = math.floor((length + gap) / (dash + gap))
	if count <= 0 then
		return
	end
	local used = count * dash + (count - 1) * gap
	local start = (length - used) / 2
	local dir = (b - a).Unit
	for i = 0, count - 1 do
		local s0 = start + i * (dash + gap)
		line(parent, a + dir * s0, a + dir * (s0 + dash), offset, width, color)
	end
end

-- Markings for one road piece from a to b
local function markings(parent: Instance, a: Vector3, b: Vector3, kind: string, width: number, lanes: number)
	if kind == "Street" then
		dashes(parent, a, b, 0, 9, 9, 0.55, C.Yellow)
	elseif kind == "Avenue" or kind == "Highway" then
		line(parent, a, b, -0.45, 0.4, C.Yellow)
		line(parent, a, b, 0.45, 0.4, C.Yellow)
		local laneWidth = width / (lanes * 2)
		for lane = 1, lanes - 1 do
			local o = laneWidth * lane
			if kind == "Highway" then
				dashes(parent, a, b, o, 12, 26, 0.45, C.White)
				dashes(parent, a, b, -o, 12, 26, 0.45, C.White)
			else
				dashes(parent, a, b, o, 9, 11, 0.45, C.White)
				dashes(parent, a, b, -o, 9, 11, 0.45, C.White)
			end
		end
		if kind == "Highway" then
			line(parent, a, b, width / 2 - 1.2, 0.45, C.White)
			line(parent, a, b, -(width / 2 - 1.2), 0.45, C.White)
		end
	elseif kind == "Rural" then
		dashes(parent, a, b, 0, 10, 14, 0.5, C.Yellow)
		line(parent, a, b, width / 2 - 1, 0.45, C.White)
		line(parent, a, b, -(width / 2 - 1), 0.45, C.White)
	end
end

-- Zebra crossing across a road piece at distance `at` from `a`
local function crosswalk(parent: Instance, a: Vector3, b: Vector3, at: number, width: number)
	local dir = (b - a).Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local center = Vector3.new(a.X, MARK_Y, a.Z) + dir * at
	local stripes = math.floor(width / 4.2)
	local span = stripes * 4.2
	for i = 0, stripes - 1 do
		local o = -span / 2 + 2.1 + i * 4.2
		local p = center + right * o
		PartKit.Box(parent, "Crosswalk", Vector3.new(2.2, 0.05, 9), CFrame.lookAt(p, p + dir), C.White, SMOOTH, MARK)
	end
end

function Roads.Build(city: Instance)
	local roads = PartKit.Folder(city, "Roads")
	local marks = PartKit.Folder(city, "Markings")
	local signals = PartKit.Folder(city, "Signals")

	-- Grid road pieces between intersections
	for _, edge in Layout.Edges do
		local na, nb = Layout.Nodes[edge.A], Layout.Nodes[edge.B]
		if na.Grid and nb.Grid then
			local a, b = na.Position, nb.Position
			local dir = edge.Direction
			local ca = Layout.NodeClearance(edge.A, edge.Axis)
			local cb = Layout.NodeClearance(edge.B, edge.Axis)
			local p0 = a + dir * ca
			local p1 = b - dir * cb
			local length = (p1 - p0).Magnitude
			local center = (p0 + p1) / 2
			local size = if edge.Axis == "X" then Vector3.new(length, 0, edge.Width) else Vector3.new(edge.Width, 0, length)
			slab(roads, "Road", center, size)
			markings(marks, p0, p1, edge.Kind, edge.Width, edge.Lanes)
			-- white edge lines along both kerbs, and a few darker repair patches in the asphalt
			line(marks, p0 + dir * 4, p1 - dir * 4, edge.Width / 2 - 1.8, 0.4, C.White)
			line(marks, p0 + dir * 4, p1 - dir * 4, -(edge.Width / 2 - 1.8), 0.4, C.White)
			local rng = Random.new(edge.A * 7919 + edge.B * 104729)
			for _ = 1, rng:NextInteger(1, 3) do
				local along = rng:NextNumber(0.15, 0.85) * length
				local across = rng:NextNumber(-0.35, 0.35) * edge.Width
				local at = Vector3.new(p0.X, Layout.ROAD_Y + 0.012, p0.Z) + dir * along + Vector3.new(-dir.Z, 0, dir.X) * across
				local size2 = Vector3.new(rng:NextNumber(3, 7), 0.02, rng:NextNumber(4, 10))
				PartKit.Box(marks, "Patch", size2, CFrame.lookAt(at, at + dir) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0), PATCH, ASPHALT, MARK)
			end
			-- manholes in the lanes, drains along both kerbs
			local side = Vector3.new(-dir.Z, 0, dir.X)
			local laneW = edge.Width / (edge.Lanes * 2)
			Detail.Manhole(marks, Vector3.new(center.X, MARK_Y, center.Z) + side * laneW * 0.5 + dir * (length * 0.18))
			Detail.Manhole(marks, Vector3.new(center.X, MARK_Y, center.Z) - side * laneW * 0.5 - dir * (length * 0.3))
			local drains = math.floor(length / 70)
			for k = 1, drains do
				for _, sgn in { -1, 1 } do
					local p = Vector3.new(p0.X, MARK_Y, p0.Z) + dir * (k * length / (drains + 1)) + side * sgn * (edge.Width / 2 - 1)
					Detail.Drain(marks, CFrame.lookAt(p, p + dir))
				end
			end
			-- crosswalks and stop lines where there are lights
			local lightsA, lightsB = Layout.HasLights(na), Layout.HasLights(nb)
			if lightsA then
				crosswalk(marks, p0, p1, 6, edge.Width)
			end
			if lightsB then
				crosswalk(marks, p1, p0, 6, edge.Width)
			end
			-- stop lines across the lanes arriving at each lit end
			local right = Vector3.new(-dir.Z, 0, dir.X)
			-- lane arrows before the stop lines on the avenues
			if edge.Kind == "Avenue" then
				for lane = 1, edge.Lanes do
					local o = laneW * (lane - 0.5)
					if lightsB then
						Detail.Arrow(marks, Vector3.new(p1.X, MARK_Y, p1.Z) - dir * 24 + side * o, dir, if lane == 1 then -1 else 0, C.White)
					end
					if lightsA then
						Detail.Arrow(marks, Vector3.new(p0.X, MARK_Y, p0.Z) + dir * 24 - side * o, -dir, if lane == 1 then -1 else 0, C.White)
					end
				end
			end
			if lightsB then
				local s = p1 - dir * 12
				local from, to = s + right * 0.6, s + right * (edge.Width / 2 - 0.6)
				local mid = (from + to) / 2
				PartKit.Box(marks, "StopLine", Vector3.new((to - from).Magnitude, 0.05, 1.2), CFrame.lookAt(Vector3.new(mid.X, MARK_Y, mid.Z), Vector3.new(mid.X, MARK_Y, mid.Z) + dir), C.White, SMOOTH, MARK)
			end
			if lightsA then
				local s = p0 + dir * 12
				local from, to = s - right * 0.6, s - right * (edge.Width / 2 - 0.6)
				local mid = (from + to) / 2
				PartKit.Box(marks, "StopLine", Vector3.new((to - from).Magnitude, 0.05, 1.2), CFrame.lookAt(Vector3.new(mid.X, MARK_Y, mid.Z), Vector3.new(mid.X, MARK_Y, mid.Z) + dir), C.White, SMOOTH, MARK)
			end
		end
	end

	-- Intersections
	local signs = PartKit.Folder(city, "StreetSigns")
	for _, node in Layout.Nodes do
		if node.Grid and node.I and node.J then
			local wx = Layout.LineWidth(node.I) -- the road along Z is this wide (in X)
			local wz = Layout.LineWidth(node.J)
			slab(roads, "Intersection", node.Position, Vector3.new(wx, 0, wz))
			-- a street-name sign on one corner: the avenue's name along Z, the street's along X
			local foot = node.Position + Vector3.new(wx / 2 + 3, Layout.CURB_Y - Layout.ROAD_Y, -(wz / 2 + 7))
			local model = PartKit.Model(signs, "StreetSign")
			PartKit.Post(model, "Pole", 0.35, 10.5, foot, C.LampBlack, Enum.Material.Metal)
			PartKit.Ball(model, "Cap", 0.45, foot + Vector3.new(0, 10.5, 0), C.LampBlack, Enum.Material.Metal, MARK)
			local blades = {
				{ Name = AVENUES[node.I + 1] or "Avenue", Y = 9.4, Along = Vector3.new(0, 0, 1) },
				{ Name = STREETS[node.J + 1] or "Street", Y = 10.1, Along = Vector3.new(1, 0, 0) },
			}
			for _, blade in blades do
				local at = foot + Vector3.new(0, blade.Y, 0)
				local part = PartKit.Box(model, "Blade", Vector3.new(6, 0.9, 0.12), CFrame.lookAt(at, at + blade.Along:Cross(Vector3.yAxis)), SIGN_GREEN, SMOOTH, MARK)
				for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
					PartKit.Sign(part, face, blade.Name, Color3.fromRGB(245, 245, 240), nil, Enum.Font.GothamBold, 24)
				end
			end
			if Layout.HasLights(node) then
				-- corner signals: SE and NW control traffic along Z, NE and SW along X
				local corners = {
					{ sx = 1, sz = 1, axis = "Z", facing = Vector3.new(0, 0, 1) },
					{ sx = -1, sz = -1, axis = "Z", facing = Vector3.new(0, 0, -1) },
					{ sx = 1, sz = -1, axis = "X", facing = Vector3.new(1, 0, 0) },
					{ sx = -1, sz = 1, axis = "X", facing = Vector3.new(-1, 0, 0) },
				}
				for _, corner in corners do
					local base = node.Position + Vector3.new(corner.sx * (wx / 2 + 3), Layout.CURB_Y - Layout.ROAD_Y, corner.sz * (wz / 2 + 3))
					local over = if corner.axis == "Z" then wx / 4 + 3 else wz / 4 + 3
					Props.Signal(signals, node.Id, corner.axis, base, corner.facing, over)
				end
			end
		end
	end

	-- Ring highway and country roads: straight pieces with round caps at the joints
	for _, edge in Layout.Edges do
		local na, nb = Layout.Nodes[edge.A], Layout.Nodes[edge.B]
		if not (na.Grid and nb.Grid) then
			local a, b = na.Position, nb.Position
			local dir = edge.Direction
			-- a country road starts at the edge of the grid crossing / ring
			if na.Grid then
				a += dir * Layout.NodeClearance(edge.A, edge.Axis)
			end
			if nb.Grid then
				b -= dir * Layout.NodeClearance(edge.B, edge.Axis)
			end
			local length = (b - a).Magnitude
			local center = (a + b) / 2
			local yaw = math.atan2(-dir.X, -dir.Z)
			slab(roads, if edge.Kind == "Highway" then "Highway" else "CountryRoad", center, Vector3.new(edge.Width, 0, length), yaw)
			local trimA = if na.Grid then 0 else edge.Width * 0.3
			local trimB = if nb.Grid then 0 else edge.Width * 0.3
			if edge.Kind == "Rural" and not nb.Grid then
				trimB = Layout.RING_WIDTH / 2 + 2
			end
			markings(marks, a + dir * trimA, b - dir * trimB, edge.Kind, edge.Width, edge.Lanes)
		end
	end
	for _, id in Layout.RingNodes do
		local node = Layout.Nodes[id]
		local cf = CFrame.new(node.Position.X, Layout.ROAD_Y - THICK / 2 - 0.04, node.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
		PartKit.Cylinder(roads, "Joint", Layout.RING_WIDTH, THICK, cf, C.Asphalt, ASPHALT)
	end
end

return Roads
