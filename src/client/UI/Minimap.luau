--[[
	Minimap: the round map in the bottom-left corner, as in the reference game. Drawn from the city
	layout (the open land and the Everglades, the bay, lakes and beaches, the runway, blocks, roads,
	the freeways in orange), it turns with the camera so "up" is where you're looking, with the
	player's arrow in the middle, other riders, police cars (flashing during a chase) and the places
	that matter (Flighty Mechanics, the police station, the jump park, the airport, the port, the
	Everglades, chargers).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.City.Layout)

local Theme = require(script.Parent.Theme)

local Minimap = {}

local New = Theme.New
local SCALE = 0.21 -- pixels per stud
local SIZE = 150

export type Minimap = {
	Frame: Frame,
	Update: (self: Minimap) -> (),
}

local LEAFY = Color3.fromRGB(52, 60, 50)
local PARK = Color3.fromRGB(48, 86, 50)
local DISTRICT_COLORS: { [string]: Color3 } = {
	BayPark = PARK,
	HavanaPark = PARK,
	KeyPark = PARK,
	Jump = Color3.fromRGB(92, 70, 48),
	Suburb = LEAFY,
	Gables = LEAFY,
	Grove = LEAFY,
	Mansion = LEAFY,
	KeyHomes = LEAFY,
	Marina = Color3.fromRGB(52, 62, 74),
	GroveBay = Color3.fromRGB(52, 62, 74),
}
-- built-up blocks get a darker footprint inside
local BUILT: { [string]: boolean } = { Downtown = true, Brickell = true, Edgewater = true, Condo = true, Midtown = true, Wynwood = true, ArtDeco = true, Havana = true, GablesHotel = true }
local WATER = Color3.fromRGB(34, 86, 124)
local SAND = Color3.fromRGB(150, 136, 100)
local OPEN = Color3.fromRGB(38, 52, 36) -- the open grass between the districts
local MARSH = Color3.fromRGB(46, 52, 34) -- the Everglades
local RUNWAY = Color3.fromRGB(70, 70, 76)
local ROAD = Color3.fromRGB(150, 150, 156)
local FREEWAY = Color3.fromRGB(232, 150, 52)
local ELEVATED: { [string]: boolean } = { Freeway = true, Ramp = true }

function Minimap.new(parent: Instance, position: UDim2): Minimap
	local holder = New("Frame", {
		Name = "Minimap",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(SIZE, SIZE),
		Position = position,
		AnchorPoint = Vector2.new(0, 1),
		Parent = parent,
	})
	local ring = New("Frame", { BackgroundColor3 = Color3.fromRGB(20, 20, 22), Size = UDim2.new(1, 8, 1, 8), Position = UDim2.fromOffset(-4, -4), Parent = holder })
	Theme.Round(ring)
	Theme.Stroke(ring, Color3.fromRGB(10, 10, 12), 2)
	local canvas = New("CanvasGroup", { BackgroundColor3 = Color3.fromRGB(30, 30, 33), Size = UDim2.fromScale(1, 1), Parent = holder })
	Theme.Round(canvas)
	local pivot = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Position = UDim2.fromScale(0.5, 0.5), Parent = canvas })
	local W = Layout.WORLD_HALF
	local mapSize = math.floor(2 * W * SCALE + 0.5)
	local map = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(mapSize, mapSize), Parent = pivot })

	-- UI offsets are whole pixels
	local function px(v: number): number
		return math.floor(v + 0.5)
	end
	local function toMap(x: number, z: number): (number, number)
		return px((x + W) * SCALE), px((z + W) * SCALE)
	end
	local function rect(x0: number, z0: number, x1: number, z1: number, color: Color3, z: number)
		local mx, mz = toMap(x0, z0)
		New("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			Position = UDim2.fromOffset(mx, mz),
			Size = UDim2.fromOffset(math.max(1, px((x1 - x0) * SCALE)), math.max(1, px((z1 - z0) * SCALE))),
			ZIndex = z,
			Parent = map,
		})
	end
	-- the open land and the marsh, the bay, the ocean, the lakes and the beaches, the runway
	for _, ground in Layout.OpenGround do
		rect(ground.MinX, ground.MinZ, ground.MaxX, ground.MaxZ, if ground.Kind == "Marsh" then MARSH else OPEN, 1)
	end
	for _, water in Layout.Water do
		rect(water.MinX, water.MinZ, water.MaxX, water.MaxZ, WATER, 1)
	end
	for _, beach in Layout.Beaches do
		rect(beach.MinX, beach.MinZ, beach.MaxX, beach.MaxZ, SAND, 1)
	end
	local airport = Layout.Airport
	rect(airport.Apron.MinX, airport.Apron.MinZ, airport.Apron.MaxX, airport.Apron.MaxZ, RUNWAY, 2)
	rect(airport.RunwayX0, airport.RunwayZ - airport.RunwayWidth / 2, airport.RunwayX1, airport.RunwayZ + airport.RunwayWidth / 2, RUNWAY, 2)
	-- blocks
	for _, block in Layout.Blocks do
		rect(block.MinX, block.MinZ, block.MaxX, block.MaxZ, DISTRICT_COLORS[block.District] or Color3.fromRGB(44, 44, 48), 1)
		if BUILT[block.District] then
			-- building footprints suggested by a darker inner square
			rect(block.LotMinX + 6, block.LotMinZ + 6, block.LotMaxX - 6, block.LotMaxZ - 6, Color3.fromRGB(58, 58, 64), 2)
		end
	end
	-- roads; the freeways in orange over the streets they cross
	for _, edge in Layout.Edges do
		local a, b = Layout.Nodes[edge.A].Position, Layout.Nodes[edge.B].Position
		local ax, az = toMap(a.X, a.Z)
		local bx, bz = toMap(b.X, b.Z)
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local freeway = ELEVATED[edge.Kind] == true
		New("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = if freeway then FREEWAY else ROAD,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(px((ax + bx) / 2), px((az + bz) / 2)),
			Size = UDim2.fromOffset(px(length + edge.Width * SCALE), math.max(3, px(edge.Width * SCALE))),
			Rotation = math.deg(math.atan2(bz - az, bx - ax)),
			ZIndex = if freeway then 4 else 3,
			Parent = map,
		})
	end
	-- places
	local icons: { TextLabel } = {}
	local function icon(text: string, world: Vector3, size: number)
		local mx, mz = toMap(world.X, world.Z)
		local label = Theme.Label({ Text = text, Size = UDim2.fromOffset(size, size), Position = UDim2.fromOffset(mx, mz), AnchorPoint = Vector2.new(0.5, 0.5), TextSize = size - 2, Stroke = 0, ZIndex = 6, Parent = map })
		table.insert(icons, label)
	end
	icon("🚲", Layout.Places.Dealership, 18)
	icon("🚓", Layout.Places.Police, 18)
	icon("🛹", Layout.Places.JumpPark, 16)
	icon("⛲", Layout.Places.Plaza, 14)
	icon("🏖", Layout.Places.Beach, 16)
	icon("🌴", Layout.Places.Park, 14)
	icon("✈", Layout.Places.Airport, 18)
	icon("🚢", Layout.Places.Port, 16)
	icon("🐊", Layout.Places.Everglades, 16)
	for _, charger in Layout.Chargers do
		icon("⚡", charger, 13)
	end

	-- live dots (cops, other players)
	local dots: { Frame } = {}
	local function dot(index: number): Frame
		local existing = dots[index]
		if existing then
			return existing
		end
		local f = New("Frame", { BorderSizePixel = 0, Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 7, Parent = map })
		Theme.Round(f)
		Theme.Stroke(f, Color3.fromRGB(255, 255, 255), 1)
		dots[index] = f
		return f
	end

	local arrow = Theme.Label({ Text = "▲", Size = UDim2.fromOffset(18, 18), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), TextSize = 16, Color = Color3.fromRGB(255, 255, 255), Stroke = 2, ZIndex = 10, Parent = canvas })
	local _ = arrow

	local self: Minimap = {
		Frame = holder,
		Update = function(_self: Minimap)
			local camera = Workspace.CurrentCamera
			local player = Players.LocalPlayer
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local position = if root and root:IsA("BasePart") then root.Position else camera.Focus.Position
			local look = camera.CFrame.LookVector
			local angle = math.atan2(look.X, -look.Z)
			pivot.Rotation = -math.deg(angle)
			local mx, mz = toMap(position.X, position.Z)
			map.Position = UDim2.fromOffset(-mx, -mz)
			for _, label in icons do
				label.Rotation = math.deg(angle)
			end
			-- dots
			local count = 0
			local flash = (os.clock() * 5) % 2 < 1
			local vehicles = Workspace:FindFirstChild("Vehicles")
			if vehicles then
				for _, car in vehicles:GetChildren() do
					if car:IsA("Model") and car:GetAttribute("Kind") == "Cop" and car.PrimaryPart then
						local p = car.PrimaryPart.Position
						if (p - position).Magnitude < 600 then
							count += 1
							local d = dot(count)
							local x, z = toMap(p.X, p.Z)
							d.Position = UDim2.fromOffset(x, z)
							local pursuit = car:GetAttribute("Pursuit") == true
							d.BackgroundColor3 = if pursuit then (if flash then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(40, 90, 255)) else Color3.fromRGB(40, 70, 200)
							d.Size = UDim2.fromOffset(if pursuit then 10 else 7, if pursuit then 10 else 7)
							d.Visible = true
						end
					end
				end
			end
			for _, other in Players:GetPlayers() do
				if other ~= player then
					local otherCharacter = other.Character
					local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
					if otherRoot and otherRoot:IsA("BasePart") then
						count += 1
						local d = dot(count)
						local x, z = toMap(otherRoot.Position.X, otherRoot.Position.Z)
						d.Position = UDim2.fromOffset(x, z)
						d.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						d.Size = UDim2.fromOffset(6, 6)
						d.Visible = true
					end
				end
			end
			for i = count + 1, #dots do
				dots[i].Visible = false
			end
		end,
	}
	return self
end

return Minimap
