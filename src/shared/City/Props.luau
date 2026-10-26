--[[
	Props: street furniture and greenery for the city builder (trees, lamps, benches, hydrants,
	traffic lights, charging stations).
]]

local PartKit = require(script.Parent.Parent.PartKit)

local Props = {}

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }

Props.Palette = {
	Asphalt = Color3.fromRGB(92, 94, 99),
	Pavement = Color3.fromRGB(178, 175, 170),
	Kerb = Color3.fromRGB(196, 196, 192),
	Grass = Color3.fromRGB(104, 148, 66),
	Lawn = Color3.fromRGB(96, 156, 72),
	Dirt = Color3.fromRGB(128, 92, 60),
	Field = Color3.fromRGB(116, 80, 52),
	White = Color3.fromRGB(240, 240, 238),
	Yellow = Color3.fromRGB(245, 196, 40),
	Trunk = Color3.fromRGB(92, 66, 46),
	LampBlack = Color3.fromRGB(28, 32, 34),
	Hydrant = Color3.fromRGB(245, 205, 30),
}
local C = Props.Palette

-- Autumn canopy colours (the reference city is mid-autumn) with some green left in
Props.Leaves = {
	Color3.fromRGB(214, 96, 38),
	Color3.fromRGB(196, 58, 38),
	Color3.fromRGB(232, 178, 52),
	Color3.fromRGB(176, 120, 48),
	Color3.fromRGB(118, 150, 62),
	Color3.fromRGB(150, 160, 60),
	Color3.fromRGB(222, 140, 40),
}

-- Trees: mostly broadleaf (a shaped canopy of clumps, sunlit on top and shaded underneath, on a
-- trunk with a root flare and two limbs), some birches (white bark, a tall oval crown) and some
-- conifers (tiers narrowing to a point)
local BIRCH_BARK = Color3.fromRGB(226, 222, 212)
local CONIFER = { Color3.fromRGB(46, 92, 58), Color3.fromRGB(58, 104, 62), Color3.fromRGB(40, 80, 60) }

function Props.Tree(parent: Instance, base: Vector3, rng: Random, size: number?)
	local s = size or rng:NextNumber(0.85, 1.3)
	local model = PartKit.Model(parent, "Tree")
	local kind = rng:NextNumber()
	local spin = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	if kind < 0.1 then
		-- conifer: flat, overlapping tiers narrowing to a point above a clear trunk
		local height = 5 * s
		PartKit.Post(model, "Trunk", 0.8 * s, height + 4 * s, base, C.Trunk, Enum.Material.Wood)
		local color = CONIFER[rng:NextInteger(1, #CONIFER)]
		for tier = 0, 4 do
			local w = (7.5 - tier * 1.45) * s
			local y = height + tier * 2.5 * s
			local shade = color:Lerp(Color3.fromRGB(150, 190, 120), tier * 0.05)
			PartKit.Ellipsoid(model, "Leaves", Vector3.new(w, 3.2 * s, w), CFrame.new(base + Vector3.new(0, y, 0)) * spin, shade, Enum.Material.Grass, NO_COLLIDE)
		end
		PartKit.Ellipsoid(model, "Leaves", Vector3.new(1.2, 2.6, 1.2) * s, CFrame.new(base + Vector3.new(0, height + 12.4 * s, 0)), color:Lerp(Color3.fromRGB(150, 190, 120), 0.3), Enum.Material.Grass, NO_COLLIDE)
		return
	end
	local birch = kind < 0.25
	local height = (if birch then 11 else 9) * s
	local bark = if birch then BIRCH_BARK else C.Trunk
	PartKit.Post(model, "Trunk", (if birch then 0.9 else 1.3) * s, height, base, bark, Enum.Material.Wood)
	PartKit.Post(model, "Roots", (if birch then 1.4 else 2.1) * s, 0.7 * s, base, bark, Enum.Material.Wood, NO_COLLIDE)
	if birch then
		for i = 1, 4 do
			PartKit.Post(model, "Bark", 0.95 * s, 0.25 * s, base + Vector3.new(0, i * 2.2 * s, 0), Color3.fromRGB(40, 38, 36), Enum.Material.Wood, NO_COLLIDE)
		end
	end
	local top = base + Vector3.new(0, height, 0)
	-- two limbs reaching into the crown
	for i = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2) + i * math.pi
		local from = base + Vector3.new(0, height * 0.62, 0)
		local to = from + Vector3.new(math.cos(a) * 3 * s, 3.2 * s, math.sin(a) * 3 * s)
		PartKit.Tube(model, "Limb", from, to, 0.55 * s, bark, Enum.Material.Wood, NO_COLLIDE)
	end
	local color = Props.Leaves[rng:NextInteger(1, #Props.Leaves)]
	if birch then
		color = color:Lerp(Color3.fromRGB(170, 190, 80), 0.5)
	end
	local light = color:Lerp(Color3.fromRGB(255, 240, 170), 0.18)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.18)
	local crown = if birch then Vector3.new(7.5, 11, 7.5) * s else Vector3.new(12, 9, 12) * s
	PartKit.Ellipsoid(model, "Leaves", crown, CFrame.new(top + Vector3.new(0, 1.2 * s, 0)) * spin, color, Enum.Material.Grass, NO_COLLIDE)
	local clumps = if birch then 3 else 5
	for i = 1, clumps do
		local a = (i / clumps) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local r = (if birch then 2.6 else 4.6) * s
		local up = rng:NextNumber(-1.5, 3.5) * s
		local d = rng:NextNumber(5.5, 7.5) * s * (if birch then 0.75 else 1)
		local tone = if up > 1.5 * s then light elseif up < 0 then dark else color
		PartKit.Ellipsoid(model, "Leaves", Vector3.new(d, d * 0.8, d), CFrame.new(top + Vector3.new(math.cos(a) * r, 1.2 * s + up, math.sin(a) * r)) * spin, tone, Enum.Material.Grass, NO_COLLIDE)
	end
	-- a sunlit crown on top
	PartKit.Ellipsoid(model, "Leaves", Vector3.new(7, 5, 7) * s * (if birch then 0.7 else 1), CFrame.new(top + Vector3.new(rng:NextNumber(-1, 1) * s, (if birch then 6.5 else 5) * s, rng:NextNumber(-1, 1) * s)), light, Enum.Material.Grass, NO_COLLIDE)
end

-- Old-fashioned black lamp post with a white globe (as in the reference city)
function Props.Lamp(parent: Instance, base: Vector3)
	local model = PartKit.Model(parent, "Lamp")
	PartKit.Post(model, "Pole", 0.6, 13, base, C.LampBlack, METAL)
	-- a fluted cast base, collars up the pole, a cage under the globe and a finial on top
	PartKit.Post(model, "Base", 1.3, 1.6, base, C.LampBlack, METAL, DECOR)
	PartKit.Post(model, "BaseCap", 1.0, 0.35, base + Vector3.new(0, 1.6, 0), C.LampBlack, METAL, DECOR)
	for _, y in { 4.5, 9, 12.4 } do
		PartKit.Post(model, "Collar", 0.85, 0.22, base + Vector3.new(0, y, 0), C.LampBlack, METAL, DECOR)
	end
	PartKit.Box(model, "Head", Vector3.new(1.6, 0.4, 1.6), CFrame.new(base + Vector3.new(0, 13.2, 0)), C.LampBlack, METAL, DECOR)
	PartKit.Ball(model, "Globe", 1.9, base + Vector3.new(0, 14.3, 0), Color3.fromRGB(255, 246, 220), Enum.Material.Neon, DECOR)
	PartKit.Post(model, "Crown", 0.9, 0.3, base + Vector3.new(0, 15.15, 0), C.LampBlack, METAL, DECOR)
	PartKit.Ball(model, "Finial", 0.35, base + Vector3.new(0, 15.6, 0), C.LampBlack, METAL, DECOR)
end

function Props.Bench(parent: Instance, cf: CFrame)
	local model = PartKit.Model(parent, "Bench")
	local wood = Color3.fromRGB(120, 84, 52)
	PartKit.Box(model, "Seat", Vector3.new(6, 0.4, 1.8), cf * CFrame.new(0, 1.7, 0), wood, Enum.Material.Wood)
	PartKit.Box(model, "Back", Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 2.8, 0.85), wood, Enum.Material.Wood, NO_COLLIDE)
	for _, x in { -2.6, 2.6 } do
		PartKit.Box(model, "Leg", Vector3.new(0.3, 1.5, 1.6), cf * CFrame.new(x, 0.75, 0.1), C.LampBlack, METAL, NO_COLLIDE)
	end
end

function Props.Hydrant(parent: Instance, base: Vector3)
	local model = PartKit.Model(parent, "Hydrant")
	PartKit.Post(model, "Body", 1.0, 2.0, base, C.Hydrant, SMOOTH)
	PartKit.Ball(model, "Cap", 1.05, base + Vector3.new(0, 2.0, 0), C.Hydrant, SMOOTH, DECOR)
	PartKit.Cylinder(model, "Nozzles", 0.45, 1.6, CFrame.new(base + Vector3.new(0, 1.35, 0)), Color3.fromRGB(60, 60, 200), SMOOTH, DECOR)
end

function Props.Bin(parent: Instance, base: Vector3)
	PartKit.Post(parent, "Bin", 1.4, 2.6, base, Color3.fromRGB(40, 90, 60), METAL)
end

-- One signal head on a pole at an intersection corner, facing the traffic it controls.
-- The head carries attributes Node and Axis; its lamps are named Red / Yellow / Green.
function Props.Signal(parent: Instance, nodeId: number, axis: string, base: Vector3, facing: Vector3, overRoad: number)
	local model = PartKit.Model(parent, "Signal")
	model:SetAttribute("Node", nodeId)
	model:SetAttribute("Axis", axis)
	PartKit.Post(model, "Pole", 0.7, 17, base, Color3.fromRGB(70, 74, 78), METAL)
	-- arm reaching out over the near lanes
	local right = Vector3.new(-facing.Z, 0, facing.X) -- to the right of someone looking along `facing`
	local armEnd = base + Vector3.new(0, 16, 0) + right * overRoad
	PartKit.Bar(model, "Arm", base + Vector3.new(0, 16, 0), armEnd, 0.5, 0.5, Color3.fromRGB(70, 74, 78), METAL, NO_COLLIDE)
	local headPos = armEnd + Vector3.new(0, -2.2, 0)
	local cf = CFrame.lookAt(headPos, headPos + facing)
	PartKit.Box(model, "Head", Vector3.new(1.6, 4.4, 1.2), cf, Color3.fromRGB(230, 190, 30), SMOOTH, NO_COLLIDE)
	for i, name in { "Red", "Yellow", "Green" } do
		PartKit.Box(model, name, Vector3.new(1.0, 1.0, 0.2), cf * CFrame.new(0, 1.35 - (i - 1) * 1.35, -0.62), Color3.fromRGB(40, 40, 40), SMOOTH, DECOR)
	end
	-- pedestrian push box and a small sign
	PartKit.Box(model, "PushBox", Vector3.new(0.6, 0.9, 0.5), CFrame.new(base + Vector3.new(0, 4, 0)), Color3.fromRGB(230, 190, 30), SMOOTH, NO_COLLIDE)
	return model
end

-- Charging station kiosk with a prompt (the server listens to every ChargerPrompt)
function Props.Charger(parent: Instance, base: Vector3, facing: Vector3)
	local model = PartKit.Model(parent, "Charger")
	local cf = CFrame.lookAt(base, base + facing)
	local green = Color3.fromRGB(40, 210, 110)
	PartKit.Box(model, "Pad", Vector3.new(12, 0.1, 9), cf * CFrame.new(0, 0.05, -5), green, Enum.Material.Neon, DECOR).Transparency = 0.55
	local body = PartKit.Box(model, "Kiosk", Vector3.new(3, 7, 1.6), cf * CFrame.new(0, 3.5, 0), Color3.fromRGB(240, 242, 245), SMOOTH)
	PartKit.Box(model, "Stripe", Vector3.new(3.05, 0.6, 1.65), cf * CFrame.new(0, 5.2, 0), green, Enum.Material.Neon, DECOR)
	local screen = PartKit.Box(model, "Screen", Vector3.new(2.2, 2.2, 0.1), cf * CFrame.new(0, 4.5, -0.82), Color3.fromRGB(20, 30, 30), SMOOTH, DECOR)
	PartKit.Sign(screen, Enum.NormalId.Front, "⚡ CHARGE", green, Color3.fromRGB(14, 22, 22), Enum.Font.FredokaOne, 40)
	PartKit.Tube(model, "Cable", cf * Vector3.new(1.3, 2.2, -0.6), cf * Vector3.new(2.6, 0.4, -2.2), 0.25, Color3.fromRGB(30, 30, 30), SMOOTH, NO_COLLIDE)
	-- Tall sign so it can be spotted from down the street
	PartKit.Post(model, "SignPole", 0.4, 14, cf * Vector3.new(-2.2, 0, 0.4), Color3.fromRGB(70, 74, 78), METAL)
	local sign = PartKit.Box(model, "SignBoard", Vector3.new(4, 4, 0.3), cf * CFrame.new(-2.2, 15, 0.4), green, SMOOTH, NO_COLLIDE)
	PartKit.Sign(sign, Enum.NormalId.Front, "⚡", Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 30)
	PartKit.Sign(sign, Enum.NormalId.Back, "⚡", Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 30)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChargerPrompt"
	prompt.ActionText = "Charge battery"
	prompt.ObjectText = "Charging station"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = body
	return model
end

-- Kerbside features along one pad edge from `a` to `b` (both on the pavement, near the kerb)
function Props.Streetscape(parent: Instance, a: Vector3, b: Vector3, rng: Random, trees: boolean)
	local length = (b - a).Magnitude
	if length < 30 then
		return
	end
	local dir = (b - a).Unit
	local lampEvery = 80
	local count = math.max(1, math.floor(length / lampEvery))
	for i = 0, count do
		local t = (i + 0.5) / (count + 1)
		local p = a:Lerp(b, t)
		Props.Lamp(parent, p)
		if trees and i < count then
			local mid = a:Lerp(b, (i + 1) / (count + 1))
			Props.Tree(parent, mid, rng, rng:NextNumber(0.75, 1.0))
			PartKit.Box(parent, "TreeGrate", Vector3.new(4, 0.08, 4), CFrame.new(mid + Vector3.new(0, 0.04, 0)), Color3.fromRGB(46, 44, 42), Enum.Material.DiamondPlate, DECOR)
		end
	end
	if rng:NextNumber() < 0.5 then
		Props.Hydrant(parent, a + dir * math.min(18, length * 0.2))
	end
end

return Props
