--[[
	Viewport: 3D pictures in the UI with no image assets. Bikes in ride cards and the tuning preview,
	and the menu icons (a gold crate, a green shopping bag, a blue paint bucket), all built from
	parts and shown in ViewportFrames.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bikes = require(Shared.Bikes)
local PartKit = require(Shared.PartKit)
local BikeModel = require(Shared.Models.BikeModel)

local Theme = require(script.Parent.Theme)

local Viewport = {}

local New = Theme.New

local function frame(parent: Instance, size: UDim2, position: UDim2?, anchor: Vector2?): ViewportFrame
	return New("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		Size = size,
		Position = position or UDim2.new(),
		AnchorPoint = anchor or Vector2.zero,
		Ambient = Color3.fromRGB(150, 150, 160),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.6, -1, -0.4),
		ZIndex = 5,
		Parent = parent,
	})
end

-- Points a camera at a model inside a viewport from `direction` (relative to the model's centre)
local function aim(vf: ViewportFrame, model: Model, direction: Vector3, fov: number, padding: number)
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius * padding / math.tan(math.rad(fov / 2))
	local camera = vf:FindFirstChildOfClass("Camera") or New("Camera", { Parent = vf })
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(cf.Position + direction.Unit * distance, cf.Position)
	vf.CurrentCamera = camera
end

-- A bike in a viewport; returns the frame and a function to repaint / swap the bike
function Viewport.Bike(parent: Instance, bike: Bikes.Bike, paint: BikeModel.PaintChoice?, size: UDim2, position: UDim2?, anchor: Vector2?): (ViewportFrame, (Bikes.Bike, BikeModel.PaintChoice?) -> ())
	local vf = frame(parent, size, position, anchor)
	local current: Model? = nil
	local function show(b: Bikes.Bike, p: BikeModel.PaintChoice?)
		if current then
			current:Destroy()
		end
		local model = BikeModel.Build(b, p, { Static = true })
		model.Parent = vf
		current = model
		aim(vf, model, Vector3.new(1, 0.28, -0.5), 30, 1.05)
	end
	show(bike, paint)
	return vf, show
end

local function crate(): Model
	local model = Instance.new("Model")
	local gold = Color3.fromRGB(236, 170, 40)
	local dark = Color3.fromRGB(96, 56, 24)
	PartKit.Box(model, "Body", Vector3.new(2.2, 1.3, 1.4), CFrame.new(0, 0.65, 0), gold, Enum.Material.SmoothPlastic)
	PartKit.Box(model, "Lid", Vector3.new(2.3, 0.55, 1.5), CFrame.new(0, 1.55, 0), Color3.fromRGB(250, 196, 70), Enum.Material.SmoothPlastic)
	for _, x in { -0.6, 0.6 } do
		PartKit.Box(model, "Strap", Vector3.new(0.22, 1.9, 1.56), CFrame.new(x, 0.95, 0), dark, Enum.Material.SmoothPlastic)
	end
	PartKit.Box(model, "Lock", Vector3.new(0.4, 0.45, 0.2), CFrame.new(0, 1.2, -0.78), Color3.fromRGB(255, 230, 120), Enum.Material.Neon)
	PartKit.Ball(model, "Sparkle", 0.35, Vector3.new(0.9, 2.2, -0.4), Color3.fromRGB(255, 250, 200), Enum.Material.Neon)
	PartKit.Ball(model, "Sparkle", 0.22, Vector3.new(-1, 2.0, -0.5), Color3.fromRGB(255, 250, 200), Enum.Material.Neon)
	return model
end

local function bag(): Model
	local model = Instance.new("Model")
	local green = Color3.fromRGB(60, 200, 70)
	PartKit.Box(model, "Bag", Vector3.new(1.7, 1.8, 1.0), CFrame.new(0, 0.9, 0), green, Enum.Material.SmoothPlastic)
	PartKit.Box(model, "Band", Vector3.new(1.75, 0.3, 1.05), CFrame.new(0, 1.55, 0), Color3.fromRGB(30, 120, 40), Enum.Material.SmoothPlastic)
	PartKit.Bar(model, "Handle", Vector3.new(-0.5, 1.8, 0), Vector3.new(-0.3, 2.5, 0), 0.15, 0.15, Color3.fromRGB(30, 120, 40), Enum.Material.SmoothPlastic)
	PartKit.Bar(model, "Handle", Vector3.new(-0.3, 2.5, 0), Vector3.new(0.3, 2.5, 0), 0.15, 0.15, Color3.fromRGB(30, 120, 40), Enum.Material.SmoothPlastic)
	PartKit.Bar(model, "Handle", Vector3.new(0.3, 2.5, 0), Vector3.new(0.5, 1.8, 0), 0.15, 0.15, Color3.fromRGB(30, 120, 40), Enum.Material.SmoothPlastic)
	for i, p in { Vector3.new(-1.1, 0.5, -0.4), Vector3.new(1.1, 0.7, -0.3), Vector3.new(0.2, 0.3, -0.8) } do
		PartKit.Box(model, "Gem", Vector3.new(0.6, 0.6, 0.6), CFrame.new(p) * CFrame.Angles(0.6, i, 0.6), Color3.fromRGB(110, 255, 120), Enum.Material.Neon)
	end
	return model
end

local function bucket(): Model
	local model = Instance.new("Model")
	local blue = Color3.fromRGB(40, 120, 230)
	PartKit.Post(model, "Bucket", 1.6, 1.7, Vector3.zero, Color3.fromRGB(40, 44, 52), Enum.Material.Metal)
	PartKit.Post(model, "Rim", 1.75, 0.18, Vector3.new(0, 1.62, 0), Color3.fromRGB(70, 76, 86), Enum.Material.Metal)
	PartKit.Post(model, "Paint", 1.5, 0.05, Vector3.new(0, 1.68, 0), Color3.fromRGB(60, 170, 255), Enum.Material.SmoothPlastic)
	for i, p in { Vector3.new(0.7, 1.3, -0.3), Vector3.new(0.75, 0.9, -0.2), Vector3.new(-0.6, 1.4, -0.5), Vector3.new(0.2, 2.1, -0.2), Vector3.new(-0.3, 2.3, 0) } do
		PartKit.Ball(model, "Splash", 0.35 + (i % 2) * 0.2, p, blue, Enum.Material.SmoothPlastic)
	end
	return model
end

local function scooter(): Model
	return BikeModel.Build(Bikes.List[1], nil, { Static = true })
end

-- The left menu's icons: "Crates", "Shop", "Tuning" or a bike id
function Viewport.Icon(parent: Instance, kind: string, size: UDim2, position: UDim2?): ViewportFrame
	local vf = frame(parent, size, position)
	local model: Model
	local direction = Vector3.new(0.7, 0.55, -1)
	if kind == "Crates" then
		model = crate()
	elseif kind == "Shop" then
		model = bag()
	elseif kind == "Tuning" then
		model = bucket()
		direction = Vector3.new(0.5, 0.8, -1)
	else
		local bike = Bikes.Get(kind)
		model = if bike then BikeModel.Build(bike, nil, { Static = true }) else scooter()
		direction = Vector3.new(1, 0.25, -0.4)
	end
	model.Parent = vf
	aim(vf, model, direction, 32, 1.0)
	return vf
end

return Viewport
