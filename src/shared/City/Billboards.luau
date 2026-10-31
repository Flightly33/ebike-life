--[[
	Billboards: the advertising structures in the city (design units, like the rest; Builder scales
	them). Only the structure is baked: steel, catwalks, lamps and a plain face. Each face is a part
	named `AdFace` (its Front face carries the ad) with attributes `AdKind` ("Billboard", "Rooftop",
	"Screen", "Panel") and `AdSeed`; Client/Billboards draws the ads on the faces near the camera
	(Shared/Ads, plus the owner's uploaded images in AssetIds.Billboards) and lights the `AdLamp`s
	at night.

	  Monopole   a highway billboard on one steel column, two faces in a shallow V, one for each
	             direction of traffic (Builder puts them along the turnpike, the rural
	             roads and the freeways, wherever the ground beside them is open)
	  Rooftop    a billboard on a truss on a roof, facing the street (Buildings.Midrise / Warehouse)
	  Screen     a framed LED screen on a building's face (Buildings.Podium, downtown)
]]

local PartKit = require(script.Parent.Parent.PartKit)

local Billboards = {}

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }
local STEEL = Color3.fromRGB(96, 100, 106)
local DARK = Color3.fromRGB(30, 32, 36)
local LAMP = Color3.fromRGB(70, 72, 78)

local seedCount = 0
local function face(parent: Instance, kind: string, size: Vector3, cf: CFrame, rng: Random): Part
	seedCount += 1
	local p = PartKit.Box(parent, "AdFace", size, cf, Color3.fromRGB(236, 236, 230), SMOOTH, NO_COLLIDE)
	p:SetAttribute("AdKind", kind)
	p:SetAttribute("AdSeed", rng:NextInteger(1, 1e6) + seedCount)
	return p
end

-- A framed face with lamps over it: `cf` is the face's middle, its -Z toward the viewer
local function framedFace(parent: Instance, kind: string, cf: CFrame, w: number, h: number, rng: Random)
	PartKit.Box(parent, "AdBack", Vector3.new(w + 1.2, h + 1.2, 0.8), cf * CFrame.new(0, 0, 0.5), DARK, METAL, NO_COLLIDE)
	PartKit.Box(parent, "AdTrim", Vector3.new(w + 1.4, 0.5, 0.9), cf * CFrame.new(0, h / 2 + 0.6, 0.3), STEEL, METAL, DECOR)
	PartKit.Box(parent, "AdTrim", Vector3.new(w + 1.4, 0.5, 0.9), cf * CFrame.new(0, -h / 2 - 0.6, 0.3), STEEL, METAL, DECOR)
	face(parent, kind, Vector3.new(w, h, 0.2), cf, rng)
	-- gooseneck lamps along the top, leaning out over the face
	local lamps = math.max(2, math.floor(w / 12))
	for i = 0, lamps - 1 do
		local x = -w / 2 + (i + 0.5) * w / lamps
		PartKit.Box(parent, "LampArm", Vector3.new(0.3, 0.3, 4.2), cf * CFrame.new(x, h / 2 + 1.4, -1.9) * CFrame.Angles(math.rad(-20), 0, 0), STEEL, METAL, DECOR)
		local lamp = PartKit.Box(parent, "AdLamp", Vector3.new(1.6, 0.6, 1.0), cf * CFrame.new(x, h / 2 + 0.6, -3.8) * CFrame.Angles(math.rad(35), 0, 0), LAMP, SMOOTH, DECOR)
		lamp:SetAttribute("Lit", Color3.fromRGB(255, 240, 200))
	end
end

-- A catwalk with a railing under a face (the railing stays below the ad)
local function catwalk(parent: Instance, cf: CFrame, w: number, h: number)
	local walk = cf * CFrame.new(0, -h / 2 - 3.2, -1.6)
	PartKit.Box(parent, "Catwalk", Vector3.new(w + 1, 0.3, 2.6), walk, STEEL, Enum.Material.DiamondPlate, DECOR)
	PartKit.Box(parent, "Rail", Vector3.new(w + 1, 0.2, 0.2), walk * CFrame.new(0, 2.4, -1.2), STEEL, METAL, DECOR)
	PartKit.Box(parent, "Rail", Vector3.new(w + 1, 0.15, 0.15), walk * CFrame.new(0, 1.2, -1.2), STEEL, METAL, DECOR)
	local posts = math.max(2, math.floor(w / 8))
	for i = 0, posts do
		PartKit.Box(parent, "RailPost", Vector3.new(0.2, 2.4, 0.2), walk * CFrame.new(-w / 2 + i * w / posts, 1.2, -1.2), STEEL, METAL, DECOR)
	end
	-- brackets from the catwalk up to the face's frame
	for i = 0, posts, 2 do
		PartKit.Box(parent, "WalkBracket", Vector3.new(0.3, 3.2, 0.3), cf * CFrame.new(-w / 2 + i * w / posts, -h / 2 - 1.6, -0.4), STEEL, METAL, DECOR)
	end
end

-- A highway billboard at `base` (ground): one flat, double-sided board square on a steel pole, its
-- faces looking up and down the road (`along`) so drivers each way see one, the front face turned
-- a little toward the road (`side` points away from it)
function Billboards.Monopole(parent: Instance, base: Vector3, along: Vector3, side: Vector3, rng: Random, w: number?, h: number?)
	local model = PartKit.Model(parent, "Billboard")
	local fw, fh = w or 48, h or 16
	local height = rng:NextNumber(40, 52)
	PartKit.Post(model, "Column", 4.5, height, base, STEEL, METAL)
	PartKit.Post(model, "ColumnCollar", 6, 2.4, base, STEEL, METAL)
	PartKit.Post(model, "Footing", 8, 1.2, base - Vector3.new(0, 0.6, 0), Color3.fromRGB(170, 168, 160), Enum.Material.Concrete)
	local top = base + Vector3.new(0, height, 0)
	-- the board looks along the road, turned 12 degrees toward it
	local turn = math.rad(12)
	local look = (along * math.cos(turn) - side * math.sin(turn)).Unit
	local centre = top + Vector3.new(0, fh / 2 + 4.5, 0)
	local cf = CFrame.lookAt(centre, centre + look)
	-- the head on the pole and the cabinet the two faces are mounted on
	PartKit.Box(model, "Head", Vector3.new(7, 3, 7), CFrame.new(top + Vector3.new(0, 1.5, 0)) * (cf - cf.Position), STEEL, METAL, DECOR)
	PartKit.Box(model, "Cabinet", Vector3.new(fw + 1.6, fh + 1.6, 2.4), cf, DARK, METAL, NO_COLLIDE)
	PartKit.Box(model, "CabinetCap", Vector3.new(fw + 2.2, 0.6, 3.0), cf * CFrame.new(0, fh / 2 + 1.1, 0), STEEL, METAL, DECOR)
	PartKit.Box(model, "Stringer", Vector3.new(fw * 0.8, 1.2, 1.2), cf * CFrame.new(0, -fh / 2 - 1.4, 0), STEEL, METAL, DECOR)
	for _, sx in { -1, 1 } do
		PartKit.Box(model, "Brace", Vector3.new(1, 1, ((fw * 0.4) ^ 2 + 9) ^ 0.5), CFrame.lookAt((top + Vector3.new(0, 2, 0) + (cf * CFrame.new(sx * fw * 0.4, -fh / 2 - 1.4, 0)).Position) / 2, (cf * CFrame.new(sx * fw * 0.4, -fh / 2 - 1.4, 0)).Position), STEEL, METAL, DECOR)
	end
	-- a face, lamps and a catwalk on each side
	for _, flip in { 0, math.pi } do
		local f = cf * CFrame.Angles(0, flip, 0) * CFrame.new(0, 0, -1.3)
		PartKit.Box(model, "AdTrim", Vector3.new(fw + 1.4, 0.5, 0.5), f * CFrame.new(0, fh / 2 + 0.5, 0.1), STEEL, METAL, DECOR)
		PartKit.Box(model, "AdTrim", Vector3.new(fw + 1.4, 0.5, 0.5), f * CFrame.new(0, -fh / 2 - 0.5, 0.1), STEEL, METAL, DECOR)
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "AdTrim", Vector3.new(0.5, fh + 1.5, 0.5), f * CFrame.new(sx * (fw / 2 + 0.45), 0, 0.1), STEEL, METAL, DECOR)
		end
		face(model, "Billboard", Vector3.new(fw, fh, 0.2), f, rng)
		local lamps = math.max(2, math.floor(fw / 12))
		for i = 0, lamps - 1 do
			local x = -fw / 2 + (i + 0.5) * fw / lamps
			PartKit.Box(model, "LampArm", Vector3.new(0.3, 0.3, 4.2), f * CFrame.new(x, -fh / 2 - 1.2, -1.9) * CFrame.Angles(math.rad(25), 0, 0), STEEL, METAL, DECOR)
			local lamp = PartKit.Box(model, "AdLamp", Vector3.new(1.6, 0.6, 1.0), f * CFrame.new(x, -fh / 2 - 1.9, -3.8) * CFrame.Angles(math.rad(-35), 0, 0), LAMP, SMOOTH, DECOR)
			lamp:SetAttribute("Lit", Color3.fromRGB(255, 240, 200))
		end
		catwalk(model, f, fw, fh)
	end
	return model
end

-- A rooftop billboard on a truss: `roof` is the roof's middle, `front` the way it faces
function Billboards.Rooftop(parent: Instance, roof: Vector3, front: Vector3, w: number, rng: Random)
	local model = PartKit.Model(parent, "RooftopBillboard")
	local fh = math.clamp(w * 0.36, 10, 18)
	local legs = 14
	local centre = roof + Vector3.new(0, legs + fh / 2, 0) + front * 2
	local cf = CFrame.lookAt(centre, centre + front)
	framedFace(model, "Rooftop", cf, w, fh, rng)
	catwalk(model, cf, w, fh)
	local n = math.max(2, math.floor(w / 10))
	for i = 0, n do
		local x = -w / 2 + i * w / n
		local foot = (cf * CFrame.new(x, -fh / 2 - legs / 2, 1.5)).Position
		PartKit.Box(model, "Leg", Vector3.new(0.8, legs, 0.8), CFrame.new(foot), STEEL, METAL, DECOR)
		PartKit.Box(model, "Brace", Vector3.new(0.5, legs * 1.15, 0.5), cf * CFrame.new(x, -fh / 2 - legs / 2, 5) * CFrame.Angles(math.rad(-30), 0, 0), STEEL, METAL, DECOR)
	end
	return model
end

-- An LED screen on a face: `cf` is the screen's middle, its -Z out from the wall
function Billboards.Screen(parent: Instance, cf: CFrame, w: number, h: number, rng: Random)
	local model = PartKit.Model(parent, "AdScreen")
	PartKit.Box(model, "ScreenFrame", Vector3.new(w + 2, h + 2, 1.6), cf * CFrame.new(0, 0, 0.8), DARK, METAL, NO_COLLIDE)
	PartKit.Box(model, "ScreenTrim", Vector3.new(w + 2.4, 0.6, 1.8), cf * CFrame.new(0, h / 2 + 1.2, 0.7), Color3.fromRGB(200, 204, 210), METAL, DECOR)
	local f = face(model, "Screen", Vector3.new(w, h, 0.2), cf * CFrame.new(0, 0, -0.1), rng)
	f.Color = Color3.fromRGB(20, 22, 26)
	return model
end

return Billboards
