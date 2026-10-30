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

-- A catwalk with a railing under a face
local function catwalk(parent: Instance, cf: CFrame, w: number, h: number)
	local walk = cf * CFrame.new(0, -h / 2 - 1.4, -1.6)
	PartKit.Box(parent, "Catwalk", Vector3.new(w + 1, 0.3, 2.6), walk, STEEL, Enum.Material.DiamondPlate, DECOR)
	PartKit.Box(parent, "Rail", Vector3.new(w + 1, 0.2, 0.2), walk * CFrame.new(0, 2.6, -1.2), STEEL, METAL, DECOR)
	local posts = math.max(2, math.floor(w / 8))
	for i = 0, posts do
		PartKit.Box(parent, "RailPost", Vector3.new(0.2, 2.6, 0.2), walk * CFrame.new(-w / 2 + i * w / posts, 1.3, -1.2), STEEL, METAL, DECOR)
	end
end

-- A highway monopole at `base` (ground), its two faces turned toward traffic each way along `along`
function Billboards.Monopole(parent: Instance, base: Vector3, along: Vector3, side: Vector3, rng: Random, w: number?, h: number?)
	local model = PartKit.Model(parent, "Billboard")
	local fw, fh = w or 48, h or 16
	local height = rng:NextNumber(46, 60)
	PartKit.Post(model, "Column", 4.5, height, base, STEEL, METAL)
	PartKit.Post(model, "Footing", 7, 1.2, base - Vector3.new(0, 0.6, 0), Color3.fromRGB(170, 168, 160), Enum.Material.Concrete)
	local top = base + Vector3.new(0, height, 0)
	PartKit.Box(model, "Head", Vector3.new(6, 3, 6), CFrame.new(top), STEEL, METAL, DECOR)
	-- two faces in a V hinged at the column, opening toward the road (`side` points away from it),
	-- each turned 22 degrees off square to the road toward the drivers it faces
	local angle = math.rad(22)
	local towardRoad = -side
	for _, dir in { 1, -1 } do
		local look = (-along * dir * math.cos(angle) + towardRoad * math.sin(angle)).Unit
		local across = Vector3.new(-look.Z, 0, look.X)
		if across:Dot(towardRoad) < 0 then
			across = -across
		end
		local centre = top + Vector3.new(0, fh / 2 + 1.5, 0) + across * (fw / 2 + 1.5) + look * 0.6
		local cf = CFrame.lookAt(centre, centre + look)
		framedFace(model, "Billboard", cf, fw, fh, rng)
		catwalk(model, cf, fw, fh)
		-- the truss behind the face, and an arm from the column
		PartKit.Box(model, "Truss", Vector3.new(fw * 0.9, 0.6, 0.6), cf * CFrame.new(0, 0, 1.4), STEEL, METAL, DECOR)
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "Strut", Vector3.new(0.6, fh + 2, 0.6), cf * CFrame.new(sx * fw * 0.3, 0, 1.4), STEEL, METAL, DECOR)
		end
		local armEnd = (cf * CFrame.new(0, -fh / 2 - 1, 1.4)).Position
		local armStart = top + Vector3.new(0, 1, 0)
		PartKit.Box(model, "Arm", Vector3.new(1, 1, (armEnd - armStart).Magnitude), CFrame.lookAt((armStart + armEnd) / 2, armEnd), STEEL, METAL, DECOR)
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
