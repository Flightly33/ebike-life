--[[
	ItemModel: the shop items (Shared/Menus ids) as little part-built models at real size: burgers,
	fries, drinks, pastries, gear. Used on the order menu (ViewportFrames), on display in the shops
	(Client/ShopFit) and in the hand when bought (OrderService).

	Build(id, studsPerMeter) returns a Model whose PrimaryPart `Handle` (invisible) is the bottom
	middle of the item, where a hand holds it or a counter carries it. Parts are anchored,
	massless and collide with nothing; welders unanchor them.
]]

local PartKit = require(script.Parent.Parent.PartKit)

local ItemModel = {}

local SMOOTH = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local FABRIC = Enum.Material.Fabric
local NEON = Enum.Material.Neon
local OPTS = { Collide = false, Query = false, Touch = false, Shadow = false }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BUN = rgb(214, 150, 70)
local WHITE = rgb(246, 244, 238)
local RED = rgb(206, 40, 40)
local PAPER = rgb(236, 226, 204)
local GOLD = rgb(226, 178, 60)
local DARK = rgb(28, 28, 32)

type Kit = {
	Box: (size: Vector3, at: Vector3, color: Color3, material: Enum.Material?, rot: CFrame?) -> BasePart,
	Cyl: (d: number, h: number, at: Vector3, color: Color3, material: Enum.Material?, rot: CFrame?) -> BasePart,
	Ball: (d: number, at: Vector3, color: Color3, material: Enum.Material?) -> BasePart,
	Ell: (size: Vector3, at: Vector3, color: Color3, material: Enum.Material?, rot: CFrame?) -> BasePart,
	Label: (part: BasePart, face: Enum.NormalId, text: string, color: Color3) -> (),
}

-- Every builder works in metres, the origin at the bottom middle; `at` is a part's centre
local BUILDERS: { [string]: (Kit) -> () } = {}

local function cup(k: Kit, d: number, h: number, color: Color3, band: Color3?, lid: Color3?)
	k.Cyl(d * 0.86, h * 0.5, Vector3.new(0, h * 0.25, 0), color)
	k.Cyl(d, h * 0.5, Vector3.new(0, h * 0.75, 0), color)
	if band then
		k.Cyl(d * 1.01, h * 0.22, Vector3.new(0, h * 0.62, 0), band)
	end
	if lid then
		k.Cyl(d * 1.04, h * 0.05, Vector3.new(0, h + h * 0.02, 0), lid)
	end
end

BUILDERS.burger = function(k)
	k.Cyl(0.11, 0.025, Vector3.new(0, 0.0125, 0), BUN)
	k.Cyl(0.115, 0.022, Vector3.new(0, 0.036, 0), rgb(96, 52, 30), Enum.Material.Sand)
	k.Box(Vector3.new(0.1, 0.004, 0.1), Vector3.new(0, 0.049, 0), rgb(250, 196, 40), SMOOTH, CFrame.Angles(0, math.rad(45), 0))
	k.Cyl(0.105, 0.008, Vector3.new(0, 0.054, 0), rgb(214, 54, 40))
	k.Cyl(0.122, 0.006, Vector3.new(0, 0.061, 0), rgb(110, 180, 60), FABRIC)
	k.Ell(Vector3.new(0.115, 0.06, 0.115), Vector3.new(0, 0.074, 0), BUN)
	for i = 0, 5 do
		local a = i * math.pi / 3
		k.Ell(Vector3.new(0.008, 0.004, 0.004), Vector3.new(math.cos(a) * 0.03, 0.1, math.sin(a) * 0.03), rgb(250, 240, 214))
	end
end

BUILDERS.fries = function(k)
	k.Box(Vector3.new(0.09, 0.1, 0.045), Vector3.new(0, 0.05, 0), RED)
	k.Box(Vector3.new(0.092, 0.02, 0.047), Vector3.new(0, 0.085, 0), rgb(250, 196, 40))
	for i = 0, 9 do
		local x = -0.035 + (i % 5) * 0.0175
		local z = if i < 5 then -0.01 else 0.01
		k.Box(Vector3.new(0.008, 0.08, 0.008), Vector3.new(x, 0.12 + (i % 3) * 0.008, z), rgb(244, 200, 80), SMOOTH, CFrame.Angles(0, 0, math.rad((i % 4 - 1.5) * 6)))
	end
end

BUILDERS.soda = function(k)
	cup(k, 0.09, 0.17, WHITE, RED, WHITE)
	k.Cyl(0.008, 0.1, Vector3.new(0.012, 0.21, 0), RED)
end

BUILDERS.shake = function(k)
	cup(k, 0.085, 0.16, rgb(250, 190, 210), WHITE)
	k.Ell(Vector3.new(0.09, 0.07, 0.09), Vector3.new(0, 0.17, 0), WHITE)
	k.Ball(0.022, Vector3.new(0, 0.21, 0), RED)
	k.Cyl(0.009, 0.12, Vector3.new(0.02, 0.22, 0), rgb(240, 80, 120), SMOOTH, CFrame.Angles(0, 0, math.rad(12)))
end

BUILDERS.combo = function(k)
	k.Box(Vector3.new(0.34, 0.012, 0.24), Vector3.new(0, 0.006, 0), RED)
	k.Box(Vector3.new(0.3, 0.003, 0.2), Vector3.new(0, 0.013, 0), PAPER, FABRIC)
	-- (burger, fries and a drink on the tray: little copies of their builders, shifted)
	local function shifted(builder: (Kit) -> (), offset: Vector3)
		local inner: Kit = {
			Box = function(s, at, c, m, r)
				return k.Box(s, at + offset, c, m, r)
			end,
			Cyl = function(d, h, at, c, m, r)
				return k.Cyl(d, h, at + offset, c, m, r)
			end,
			Ball = function(d, at, c, m)
				return k.Ball(d, at + offset, c, m)
			end,
			Ell = function(s, at, c, m, r)
				return k.Ell(s, at + offset, c, m, r)
			end,
			Label = k.Label,
		}
		builder(inner)
	end
	shifted(BUILDERS.burger, Vector3.new(-0.08, 0.015, 0.03))
	shifted(BUILDERS.fries, Vector3.new(0.05, 0.015, 0.05))
	shifted(BUILDERS.soda, Vector3.new(0.1, 0.015, -0.05))
end

BUILDERS.bucket = function(k)
	k.Cyl(0.15, 0.08, Vector3.new(0, 0.04, 0), RED)
	k.Cyl(0.17, 0.08, Vector3.new(0, 0.12, 0), RED)
	for i = 0, 7 do
		local a = i * math.pi / 4
		k.Box(Vector3.new(0.025, 0.155, 0.004), Vector3.new(math.cos(a) * 0.081, 0.08, math.sin(a) * 0.081), WHITE, SMOOTH, CFrame.Angles(0, -a + math.pi / 2, 0))
	end
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		local p = Vector3.new(math.cos(a) * 0.04, 0.175, math.sin(a) * 0.04)
		k.Ell(Vector3.new(0.06, 0.045, 0.045), p, rgb(190, 120, 50), Enum.Material.Sand, CFrame.Angles(0, a, math.rad(30)))
		k.Cyl(0.012, 0.04, p + Vector3.new(math.cos(a) * 0.035, 0.03, math.sin(a) * 0.035), rgb(250, 244, 230), SMOOTH, CFrame.Angles(0, 0, math.rad(40)))
	end
end

BUILDERS.cone = function(k)
	for i = 0, 3 do
		k.Cyl(0.015 + i * 0.012, 0.03, Vector3.new(0, 0.015 + i * 0.03, 0), rgb(214, 160, 90), Enum.Material.Sand)
	end
	k.Ell(Vector3.new(0.07, 0.05, 0.07), Vector3.new(0, 0.135, 0), WHITE)
	k.Ell(Vector3.new(0.05, 0.04, 0.05), Vector3.new(0, 0.17, 0), WHITE)
	k.Ell(Vector3.new(0.025, 0.03, 0.025), Vector3.new(0, 0.195, 0), WHITE)
end

BUILDERS.hotdog = function(k)
	k.Ell(Vector3.new(0.17, 0.035, 0.05), Vector3.new(0, 0.018, 0), BUN)
	k.Cyl(0.026, 0.19, Vector3.new(0, 0.038, 0), rgb(170, 70, 50), SMOOTH, CFrame.Angles(0, 0, math.pi / 2))
	for i = 0, 6 do
		k.Box(Vector3.new(0.022, 0.004, 0.006), Vector3.new(-0.065 + i * 0.022, 0.052, (i % 2 - 0.5) * 0.008), rgb(250, 200, 30), SMOOTH, CFrame.Angles(0, math.rad(if i % 2 == 0 then 35 else -35), 0))
	end
end

BUILDERS.chips = function(k)
	local bag = k.Box(Vector3.new(0.14, 0.2, 0.05), Vector3.new(0, 0.1, 0), rgb(40, 150, 60), Enum.Material.Foil)
	k.Box(Vector3.new(0.14, 0.015, 0.02), Vector3.new(0, 0.205, 0), rgb(40, 150, 60), Enum.Material.Foil)
	k.Label(bag, Enum.NormalId.Front, "🥔\nCHIPS", rgb(250, 230, 90))
end

BUILDERS.coffee = function(k)
	cup(k, 0.08, 0.14, WHITE, rgb(150, 100, 60), DARK)
	k.Cyl(0.03, 0.012, Vector3.new(0.02, 0.153, 0), DARK)
end

BUILDERS.slushie = function(k)
	local c = k.Cyl(0.085, 0.16, Vector3.new(0, 0.08, 0), rgb(200, 230, 255), GLASS)
	c.Transparency = 0.4
	k.Cyl(0.078, 0.14, Vector3.new(0, 0.075, 0), rgb(40, 120, 255), NEON)
	k.Ell(Vector3.new(0.09, 0.05, 0.09), Vector3.new(0, 0.165, 0), rgb(220, 240, 255), GLASS).Transparency = 0.5
	k.Cyl(0.01, 0.12, Vector3.new(0.015, 0.2, 0), rgb(240, 40, 60), SMOOTH, CFrame.Angles(0, 0, math.rad(10)))
end

BUILDERS.energy = function(k)
	local can = k.Cyl(0.066, 0.16, Vector3.new(0, 0.08, 0), rgb(30, 30, 34), METAL)
	k.Cyl(0.067, 0.05, Vector3.new(0, 0.085, 0), rgb(120, 255, 60), NEON)
	k.Cyl(0.06, 0.008, Vector3.new(0, 0.164, 0), rgb(200, 200, 205), METAL)
	k.Label(can, Enum.NormalId.Front, "⚡", rgb(120, 255, 60))
end

BUILDERS.battery = function(k)
	local pack = k.Box(Vector3.new(0.12, 0.2, 0.07), Vector3.new(0, 0.1, 0), DARK, SMOOTH)
	for i = 0, 3 do
		k.Box(Vector3.new(0.06, 0.018, 0.004), Vector3.new(0, 0.05 + i * 0.03, -0.037), rgb(80, 255, 120), NEON)
	end
	k.Box(Vector3.new(0.05, 0.02, 0.03), Vector3.new(0, 0.21, 0), rgb(70, 74, 80), METAL)
	k.Label(pack, Enum.NormalId.Back, "⚡", rgb(80, 255, 120))
end

BUILDERS.cap = function(k)
	k.Ell(Vector3.new(0.2, 0.1, 0.2), Vector3.new(0, 0.05, 0), rgb(30, 60, 120), FABRIC)
	k.Box(Vector3.new(0.16, 0.008, 0.1), Vector3.new(0, 0.01, -0.12), rgb(30, 60, 120), FABRIC)
	k.Box(Vector3.new(0.08, 0.05, 0.004), Vector3.new(0, 0.06, -0.09), WHITE, FABRIC, CFrame.Angles(math.rad(-20), 0, 0))
end

BUILDERS.cafecito = function(k)
	k.Cyl(0.11, 0.008, Vector3.new(0, 0.004, 0), WHITE)
	k.Cyl(0.05, 0.045, Vector3.new(0, 0.03, 0), WHITE)
	k.Cyl(0.044, 0.004, Vector3.new(0, 0.05, 0), rgb(60, 34, 20))
	k.Box(Vector3.new(0.02, 0.025, 0.006), Vector3.new(0.032, 0.032, 0), WHITE)
end

BUILDERS.latte = function(k)
	local c = k.Cyl(0.085, 0.16, Vector3.new(0, 0.08, 0), rgb(230, 240, 250), GLASS)
	c.Transparency = 0.45
	k.Cyl(0.078, 0.1, Vector3.new(0, 0.05, 0), rgb(196, 150, 100))
	k.Cyl(0.078, 0.04, Vector3.new(0, 0.12, 0), rgb(110, 66, 36))
	k.Cyl(0.088, 0.008, Vector3.new(0, 0.164, 0), rgb(240, 240, 240))
	k.Cyl(0.009, 0.12, Vector3.new(0.015, 0.2, 0), rgb(30, 30, 30), SMOOTH, CFrame.Angles(0, 0, math.rad(10)))
end

BUILDERS.pastelito = function(k)
	k.Box(Vector3.new(0.13, 0.004, 0.13), Vector3.new(0, 0.002, 0), PAPER, FABRIC)
	k.Box(Vector3.new(0.1, 0.03, 0.08), Vector3.new(0, 0.019, 0), rgb(226, 170, 80), Enum.Material.Sand)
	k.Box(Vector3.new(0.096, 0.004, 0.076), Vector3.new(0, 0.035, 0), rgb(240, 196, 110), Enum.Material.Sand)
	k.Box(Vector3.new(0.08, 0.006, 0.006), Vector3.new(0, 0.02, -0.041), rgb(196, 40, 70))
end

BUILDERS.croqueta = function(k)
	k.Box(Vector3.new(0.14, 0.004, 0.1), Vector3.new(0, 0.002, 0), PAPER, FABRIC)
	for i = -1, 1 do
		k.Cyl(0.03, 0.08, Vector3.new(0, 0.018, i * 0.032), rgb(200, 130, 50), Enum.Material.Sand, CFrame.Angles(0, 0, math.pi / 2))
	end
end

BUILDERS.donut = function(k)
	for i = 0, 9 do
		local a = i * math.pi / 5
		k.Ball(0.032, Vector3.new(math.cos(a) * 0.032, 0.016, math.sin(a) * 0.032), rgb(220, 160, 90))
		k.Ell(Vector3.new(0.034, 0.012, 0.034), Vector3.new(math.cos(a) * 0.032, 0.028, math.sin(a) * 0.032), rgb(250, 150, 190))
	end
end

BUILDERS.gelato = function(k)
	k.Cyl(0.08, 0.04, Vector3.new(0, 0.02, 0), WHITE)
	k.Ball(0.06, Vector3.new(-0.012, 0.055, 0), rgb(255, 180, 60))
	k.Ball(0.05, Vector3.new(0.018, 0.07, 0.01), rgb(255, 210, 120))
	k.Box(Vector3.new(0.008, 0.06, 0.02), Vector3.new(0.025, 0.09, -0.01), rgb(240, 80, 120), SMOOTH, CFrame.Angles(0, 0, math.rad(-25)))
end

BUILDERS.water = function(k)
	local b = k.Cyl(0.065, 0.2, Vector3.new(0, 0.1, 0), rgb(190, 225, 255), GLASS)
	b.Transparency = 0.35
	k.Cyl(0.067, 0.06, Vector3.new(0, 0.1, 0), rgb(40, 120, 220))
	k.Cyl(0.03, 0.025, Vector3.new(0, 0.212, 0), rgb(40, 120, 220))
end

BUILDERS.coconut = function(k)
	k.Ell(Vector3.new(0.16, 0.15, 0.16), Vector3.new(0, 0.075, 0), rgb(90, 140, 50), Enum.Material.Sand)
	k.Cyl(0.06, 0.006, Vector3.new(0, 0.15, 0), rgb(240, 236, 220))
	k.Cyl(0.009, 0.14, Vector3.new(0.01, 0.2, 0), rgb(240, 80, 140), SMOOTH, CFrame.Angles(0, 0, math.rad(15)))
	k.Ell(Vector3.new(0.08, 0.02, 0.08), Vector3.new(-0.03, 0.24, 0), rgb(250, 90, 60), FABRIC)
end

BUILDERS.smoothie = function(k)
	local c = k.Cyl(0.085, 0.17, Vector3.new(0, 0.085, 0), rgb(255, 240, 220), GLASS)
	c.Transparency = 0.45
	k.Cyl(0.078, 0.15, Vector3.new(0, 0.078, 0), rgb(255, 170, 40))
	k.Ell(Vector3.new(0.09, 0.05, 0.09), Vector3.new(0, 0.175, 0), rgb(255, 240, 220), GLASS).Transparency = 0.5
	k.Cyl(0.011, 0.12, Vector3.new(0.015, 0.21, 0), rgb(40, 180, 90), SMOOTH, CFrame.Angles(0, 0, math.rad(10)))
end

BUILDERS.fruitcup = function(k)
	local c = k.Cyl(0.1, 0.1, Vector3.new(0, 0.05, 0), rgb(240, 245, 255), GLASS)
	c.Transparency = 0.5
	local colors = { rgb(240, 70, 70), rgb(255, 180, 40), rgb(120, 200, 80), rgb(250, 230, 120), rgb(200, 60, 120) }
	for i = 0, 11 do
		local a = i * 2.4
		k.Box(Vector3.new(0.022, 0.022, 0.022), Vector3.new(math.cos(a) * 0.025, 0.02 + (i % 4) * 0.02, math.sin(a) * 0.025), colors[i % #colors + 1], SMOOTH, CFrame.Angles(a, a * 2, 0))
	end
	k.Box(Vector3.new(0.008, 0.12, 0.012), Vector3.new(0.02, 0.1, 0), rgb(250, 250, 250), SMOOTH, CFrame.Angles(0, 0, math.rad(-15)))
end

BUILDERS.taco = function(k)
	k.Box(Vector3.new(0.24, 0.006, 0.12), Vector3.new(0, 0.003, 0), WHITE)
	for i = -1, 1 do
		local x = i * 0.075
		for _, s in { -1, 1 } do
			k.Box(Vector3.new(0.065, 0.06, 0.004), Vector3.new(x, 0.032, s * 0.012), rgb(240, 200, 100), Enum.Material.Sand, CFrame.Angles(math.rad(s * 22), 0, 0))
		end
		k.Box(Vector3.new(0.06, 0.012, 0.018), Vector3.new(x, 0.03, 0), rgb(120, 60, 40), Enum.Material.Sand)
		k.Box(Vector3.new(0.062, 0.008, 0.02), Vector3.new(x, 0.042, 0), rgb(120, 200, 80), FABRIC)
		k.Box(Vector3.new(0.03, 0.006, 0.012), Vector3.new(x, 0.048, 0), rgb(240, 240, 230))
	end
	k.Ell(Vector3.new(0.03, 0.012, 0.03), Vector3.new(0.1, 0.012, 0.04), rgb(120, 220, 60))
end

BUILDERS.cubano = function(k)
	k.Box(Vector3.new(0.24, 0.006, 0.12), Vector3.new(0, 0.003, 0), PAPER, FABRIC)
	for _, x in { -0.055, 0.055 } do
		k.Box(Vector3.new(0.1, 0.015, 0.08), Vector3.new(x, 0.014, 0), rgb(220, 160, 80), Enum.Material.Sand)
		k.Box(Vector3.new(0.098, 0.008, 0.082), Vector3.new(x, 0.025, 0), rgb(230, 140, 140))
		k.Box(Vector3.new(0.098, 0.004, 0.082), Vector3.new(x, 0.031, 0), rgb(250, 220, 120))
		k.Box(Vector3.new(0.096, 0.004, 0.08), Vector3.new(x, 0.035, 0), rgb(110, 160, 60))
		k.Box(Vector3.new(0.1, 0.015, 0.08), Vector3.new(x, 0.045, 0), rgb(230, 170, 90), Enum.Material.Sand)
	end
end

BUILDERS.noodles = function(k)
	k.Cyl(0.08, 0.02, Vector3.new(0, 0.01, 0), WHITE)
	k.Cyl(0.16, 0.06, Vector3.new(0, 0.05, 0), WHITE)
	k.Cyl(0.15, 0.004, Vector3.new(0, 0.078, 0), rgb(200, 130, 60))
	for i = 0, 5 do
		local a = i * 1.1
		k.Cyl(0.006, 0.09, Vector3.new(math.cos(a) * 0.02, 0.081, math.sin(a) * 0.02), rgb(250, 230, 160), SMOOTH, CFrame.Angles(0, a, math.pi / 2))
	end
	k.Ell(Vector3.new(0.035, 0.02, 0.025), Vector3.new(0.035, 0.085, 0.02), WHITE)
	k.Ell(Vector3.new(0.018, 0.012, 0.014), Vector3.new(0.035, 0.093, 0.02), rgb(250, 180, 40))
	k.Box(Vector3.new(0.04, 0.004, 0.03), Vector3.new(-0.03, 0.082, -0.03), rgb(40, 90, 40))
	for _, z in { -0.006, 0.006 } do
		k.Box(Vector3.new(0.22, 0.005, 0.005), Vector3.new(0.02, 0.09, z + 0.05), rgb(180, 130, 80), Enum.Material.Wood, CFrame.Angles(0, math.rad(20), math.rad(8)))
	end
end

BUILDERS.sushi = function(k)
	k.Box(Vector3.new(0.26, 0.02, 0.1), Vector3.new(0, 0.01, 0), rgb(170, 120, 70), Enum.Material.Wood)
	for i = 0, 3 do
		local x = -0.09 + i * 0.06
		k.Cyl(0.042, 0.03, Vector3.new(x, 0.035, 0), DARK)
		k.Cyl(0.034, 0.002, Vector3.new(x, 0.051, 0), WHITE)
		k.Cyl(0.014, 0.003, Vector3.new(x, 0.052, 0), if i % 2 == 0 then rgb(250, 120, 80) else rgb(220, 60, 60))
	end
	k.Ell(Vector3.new(0.025, 0.012, 0.02), Vector3.new(0.11, 0.026, 0.03), rgb(140, 200, 60))
end

BUILDERS.gel = function(k)
	local p = k.Box(Vector3.new(0.05, 0.1, 0.012), Vector3.new(0, 0.05, 0), rgb(250, 120, 20), Enum.Material.Foil)
	k.Box(Vector3.new(0.02, 0.02, 0.008), Vector3.new(0, 0.11, 0), rgb(250, 120, 20), Enum.Material.Foil)
	k.Label(p, Enum.NormalId.Front, "⚡\nGEL", WHITE)
end

BUILDERS.shades = function(k)
	for _, x in { -0.035, 0.035 } do
		k.Cyl(0.05, 0.004, Vector3.new(x, 0.02, 0), rgb(20, 20, 26), GLASS, CFrame.Angles(math.pi / 2, 0, 0)).Reflectance = 0.4
	end
	k.Box(Vector3.new(0.025, 0.005, 0.004), Vector3.new(0, 0.03, 0), DARK)
	for _, x in { -0.065, 0.065 } do
		k.Box(Vector3.new(0.004, 0.005, 0.12), Vector3.new(x, 0.03, 0.06), DARK)
	end
end

BUILDERS.hoodie = function(k)
	k.Box(Vector3.new(0.3, 0.08, 0.24), Vector3.new(0, 0.04, 0), rgb(70, 74, 82), FABRIC)
	k.Ell(Vector3.new(0.16, 0.05, 0.1), Vector3.new(0, 0.09, 0.06), rgb(70, 74, 82), FABRIC)
	k.Box(Vector3.new(0.14, 0.004, 0.06), Vector3.new(0, 0.082, -0.06), rgb(60, 64, 72), FABRIC)
	for _, x in { -0.03, 0.03 } do
		k.Box(Vector3.new(0.005, 0.003, 0.08), Vector3.new(x, 0.083, 0), WHITE)
	end
end

BUILDERS.helmetcam = function(k)
	local body = k.Box(Vector3.new(0.06, 0.045, 0.03), Vector3.new(0, 0.04, 0), DARK)
	local lens = k.Cyl(0.026, 0.012, Vector3.new(0.012, 0.045, -0.02), rgb(30, 30, 40), GLASS, CFrame.Angles(math.pi / 2, 0, 0))
	lens.Reflectance = 0.5
	k.Box(Vector3.new(0.008, 0.008, 0.002), Vector3.new(-0.02, 0.055, -0.016), rgb(255, 40, 40), NEON)
	k.Box(Vector3.new(0.04, 0.018, 0.04), Vector3.new(0, 0.009, 0), rgb(60, 60, 64))
	k.Label(body, Enum.NormalId.Back, "REC", rgb(255, 60, 60))
end

BUILDERS.chain = function(k)
	for i = 0, 15 do
		local a = i * math.pi / 8
		k.Ell(Vector3.new(0.014, 0.008, 0.008), Vector3.new(math.cos(a) * 0.06, 0.004, math.sin(a) * 0.08), GOLD, METAL, CFrame.Angles(0, -a, 0)).Reflectance = 0.3
	end
	k.Cyl(0.035, 0.006, Vector3.new(0, 0.004, -0.095), GOLD, METAL).Reflectance = 0.3
end

BUILDERS.bucket_hat = function(k)
	k.Cyl(0.26, 0.01, Vector3.new(0, 0.01, 0), rgb(200, 190, 160), FABRIC)
	k.Cyl(0.18, 0.07, Vector3.new(0, 0.05, 0), rgb(200, 190, 160), FABRIC)
	k.Ell(Vector3.new(0.18, 0.04, 0.18), Vector3.new(0, 0.085, 0), rgb(200, 190, 160), FABRIC)
	k.Cyl(0.182, 0.015, Vector3.new(0, 0.025, 0), rgb(120, 90, 60), FABRIC)
end

BUILDERS.flowers = function(k)
	k.Cyl(0.06, 0.12, Vector3.new(0, 0.06, 0), rgb(240, 236, 220), FABRIC)
	local colors = { rgb(250, 80, 120), rgb(250, 200, 40), rgb(255, 140, 60), rgb(200, 80, 220), rgb(255, 255, 255) }
	for i = 0, 6 do
		local a = i * 0.9
		local r = if i == 0 then 0 else 0.035
		local p = Vector3.new(math.cos(a) * r, 0.2 + (i % 2) * 0.02, math.sin(a) * r)
		k.Cyl(0.006, 0.14, p - Vector3.new(0, 0.07, 0), rgb(60, 140, 50))
		k.Ball(0.04, p, colors[i % #colors + 1], FABRIC)
		k.Ball(0.014, p + Vector3.new(0, 0.012, 0), rgb(250, 220, 60))
	end
end

ItemModel.Ids = {}
for id in BUILDERS do
	table.insert(ItemModel.Ids, id)
end
table.sort(ItemModel.Ids)

function ItemModel.Has(id: string): boolean
	return BUILDERS[id] ~= nil
end

function ItemModel.Build(id: string, studsPerMeter: number): Model
	local model = Instance.new("Model")
	model.Name = "Item_" .. id
	local s = studsPerMeter
	local handle = PartKit.Box(model, "Handle", Vector3.new(0.02, 0.02, 0.02) * s, CFrame.identity, WHITE, SMOOTH, OPTS)
	handle.Transparency = 1
	local function finish(p: BasePart): BasePart
		p.Anchored = true
		p.Massless = true
		return p
	end
	local kit: Kit = {
		Box = function(size, at, color, material, rot)
			return finish(PartKit.Box(model, "Piece", size * s, CFrame.new(at * s) * (rot or CFrame.identity), color, material or SMOOTH, OPTS))
		end,
		Cyl = function(d, h, at, color, material, rot)
			-- upright: PartKit's cylinders lie along X
			return finish(PartKit.Cylinder(model, "Piece", d * s, h * s, CFrame.new(at * s) * (rot or CFrame.identity) * CFrame.Angles(0, 0, math.pi / 2), color, material or SMOOTH, OPTS))
		end,
		Ball = function(d, at, color, material)
			return finish(PartKit.Ball(model, "Piece", d * s, at * s, color, material or SMOOTH, OPTS))
		end,
		Ell = function(size, at, color, material, rot)
			return finish(PartKit.Ellipsoid(model, "Piece", size * s, CFrame.new(at * s) * (rot or CFrame.identity), color, material or SMOOTH, OPTS))
		end,
		Label = function(part, face, text, color)
			PartKit.Sign(part, face, text, color, nil, Enum.Font.GothamBlack, 400)
		end,
	}
	local builder = BUILDERS[id] or BUILDERS.water
	builder(kit)
	handle.Anchored = true
	handle.Massless = true
	model.PrimaryPart = handle
	return model
end

return ItemModel
