--[[
	RiderLook: what riding certain bikes does to the rider. The Deathrider's Hellfire turns the head
	into a burning skull (a sculpted cranium, brow and cheekbones, ember-lit sockets, teeth and a
	hanging jaw, a column of hellfire) and the body black leather with spiked shoulders and a chain;
	getting off puts everything back exactly as it was.

	Done on the server so every player sees it. Built from parts and a Fire (no assets).
]]

local RiderLook = {}

type Saved = {
	Transparency: { [BasePart]: number },
	Colors: { [BasePart]: Color3 },
	Decals: { [Decal]: number },
	Added: { Instance },
}

local saved: { [Model]: Saved } = {}

local BONE = Color3.fromRGB(232, 226, 205)
local SOCKET = Color3.fromRGB(10, 6, 4)
local LEATHER = Color3.fromRGB(18, 18, 20)
local SHADE = Color3.fromRGB(196, 188, 160) -- the skull's shadowed hollows
local TOOTH = Color3.fromRGB(240, 232, 196)
local CRACK = Color3.fromRGB(70, 56, 40)
local EMBER = Color3.fromRGB(255, 120, 20)
local STEEL = Color3.fromRGB(150, 152, 158)
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds" -- a built-in engine texture

local function piece(parent: Instance, name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function weld(part: Part, to: BasePart, offset: CFrame)
	part.CFrame = to.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
end

function RiderLook.Apply(character: Model, effect: string?)
	if effect ~= "Hellfire" or saved[character] then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local state: Saved = { Transparency = {}, Colors = {}, Decals = {}, Added = {} }
	saved[character] = state
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local inAccessory = d:FindFirstAncestorOfClass("Accessory") ~= nil
			if d == head or inAccessory then
				state.Transparency[d] = d.Transparency
				d.Transparency = 1
			elseif d.Name ~= "HumanoidRootPart" then
				state.Colors[d] = d.Color
				d.Color = LEATHER
			end
		elseif d:IsA("Decal") and d.Parent == head then
			state.Decals[d] = d.Transparency
			d.Transparency = 1
		end
	end
	local function add(p: Instance)
		table.insert(state.Added, p)
	end
	-- an ellipsoid (a sphere mesh fills the part's box) welded to the head, in head units
	local s = head.Size.Y
	local function blob(name: string, size: Vector3, at: Vector3, color: Color3, turn: CFrame?): Part
		local p = piece(character, name, size * s, color)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		weld(p, head, CFrame.new(at * s) * (turn or CFrame.identity))
		add(p)
		return p
	end
	local function block(name: string, size: Vector3, at: Vector3, color: Color3, turn: CFrame?): Part
		local p = piece(character, name, size * s, color)
		weld(p, head, CFrame.new(at * s) * (turn or CFrame.identity))
		add(p)
		return p
	end

	-- the skull: domed cranium, heavy brow, cheekbones and temples, deep sockets with embers, the
	-- nasal hole, a row of teeth and a hanging jaw
	local skull = blob("EB_Skull", Vector3.new(1.0, 1.0, 1.15), Vector3.new(0, 0.14, 0.06), BONE)
	blob("EB_Back", Vector3.new(0.9, 0.8, 0.7), Vector3.new(0, 0.1, 0.3), SHADE)
	for _, side in { -1, 1 } do
		-- the brow ridge over each socket, low at the middle: a scowl
		blob("EB_Brow", Vector3.new(0.42, 0.15, 0.26), Vector3.new(side * 0.2, 0.11, -0.44), BONE, CFrame.Angles(0, 0, side * 0.3))
		blob("EB_Cheek", Vector3.new(0.28, 0.2, 0.32), Vector3.new(side * 0.32, -0.2, -0.38), BONE, CFrame.Angles(0, 0, side * 0.25))
		blob("EB_Socket", Vector3.new(0.32, 0.28, 0.22), Vector3.new(side * 0.21, -0.04, -0.5), SOCKET)
		local ember = blob("EB_Ember", Vector3.new(0.11, 0.11, 0.06), Vector3.new(side * 0.21, -0.05, -0.6), EMBER)
		ember.Material = Enum.Material.Neon
		local flare = Instance.new("Fire")
		flare.Size = 1
		flare.Heat = 3
		flare.Color = Color3.fromRGB(255, 90, 0)
		flare.SecondaryColor = Color3.fromRGB(255, 200, 60)
		flare.Parent = ember
	end
	blob("EB_Face", Vector3.new(0.62, 0.42, 0.46), Vector3.new(0, -0.27, -0.3), BONE)
	blob("EB_Nose", Vector3.new(0.13, 0.2, 0.1), Vector3.new(0, -0.2, -0.53), SOCKET)
	block("EB_NoseTip", Vector3.new(0.05, 0.08, 0.06), Vector3.new(0, -0.3, -0.53), SOCKET, CFrame.Angles(0, 0, math.rad(45)))
	-- the mouth: a dark gap between two rows of teeth, the jaw hanging a little open
	blob("EB_Mouth", Vector3.new(0.44, 0.14, 0.26), Vector3.new(0, -0.5, -0.36), SOCKET)
	blob("EB_Chin", Vector3.new(0.5, 0.2, 0.34), Vector3.new(0, -0.7, -0.34), BONE)
	for _, side in { -1, 1 } do
		blob("EB_JawSide", Vector3.new(0.13, 0.42, 0.28), Vector3.new(side * 0.26, -0.52, -0.2), SHADE, CFrame.Angles(math.rad(-12), 0, side * 0.12))
	end
	for row, y in { -0.44, -0.58 } do
		for i = 0, 7 do
			local a = math.rad(-56 + i * 16)
			local r = 0.22
			block("EB_Tooth", Vector3.new(0.055, if row == 1 then 0.1 else 0.08, 0.05), Vector3.new(math.sin(a) * r, y, -0.3 - math.cos(a) * r), TOOTH, CFrame.Angles(0, -a, 0))
		end
	end
	-- one jagged hairline crack down the dome to the brow
	for i, seg in { { 0.1, 0.56, -0.28, 25, 18 }, { 0.14, 0.45, -0.36, 35, -22 }, { 0.12, 0.34, -0.42, 45, 15 } } do
		local _ = i
		block("EB_Crack", Vector3.new(0.018, 0.13, 0.018), Vector3.new(seg[1], seg[2], seg[3]), CRACK, CFrame.Angles(math.rad(seg[4]), 0, math.rad(seg[5])))
	end

	-- hellfire pouring off the skull: a roaring Fire, a column of flame particles, and its glow
	local fire = Instance.new("Fire")
	fire.Size = 7
	fire.Heat = 14
	fire.Color = Color3.fromRGB(255, 100, 10)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
	fire.Parent = skull
	local flames = Instance.new("ParticleEmitter")
	flames.Name = "Hellfire"
	flames.Texture = FIRE_TEXTURE
	flames.Rate = 70
	flames.Lifetime = NumberRange.new(0.35, 0.7)
	flames.Speed = NumberRange.new(5, 9)
	flames.SpreadAngle = Vector2.new(18, 18)
	flames.Acceleration = Vector3.new(0, 6, 0)
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4 * s), NumberSequenceKeypoint.new(0.6, 1.0 * s), NumberSequenceKeypoint.new(1, 0.2 * s) })
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	flames.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 120)), ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 120, 20)), ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 20, 0)) })
	flames.LightEmission = 1
	flames.LightInfluence = 0
	flames.RotSpeed = NumberRange.new(-60, 60)
	flames.Rotation = NumberRange.new(0, 360)
	flames.Parent = skull
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 30)
	light.Range = 16
	light.Brightness = 3
	light.Shadows = false
	light.Parent = skull

	-- spiked shoulders and a chain over the leather
	for _, name in { "LeftUpperArm", "RightUpperArm", "Left Arm", "Right Arm" } do
		local arm = character:FindFirstChild(name)
		if arm and arm:IsA("BasePart") then
			local top = arm.Size.Y / 2
			local pad = piece(character, "EB_Shoulder", Vector3.new(arm.Size.X * 1.5, arm.Size.Y * 0.35, arm.Size.Z * 1.5), LEATHER)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = pad
			weld(pad, arm, CFrame.new(0, top - arm.Size.Y * 0.08, 0))
			add(pad)
			for i = -1, 1 do
				local spike = piece(character, "EB_Spike", Vector3.new(0.22, 0.22, 0.22) * s, STEEL)
				spike.Material = Enum.Material.Metal
				weld(spike, arm, CFrame.new(0, top + 0.1 * s, i * arm.Size.Z * 0.35) * CFrame.Angles(math.rad(45), 0, math.rad(45)))
				add(spike)
			end
		end
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		local size = torso.Size
		for i = 0, 7 do
			local f = i / 7
			local link = piece(character, "EB_Chain", Vector3.new(0.14, 0.07, 0.04) * s, STEEL)
			link.Material = Enum.Material.Metal
			local x = (f - 0.5) * size.X * 0.9
			local y = (0.5 - f) * size.Y * 0.8
			weld(link, torso, CFrame.new(x, y, -size.Z / 2 - 0.02) * CFrame.Angles(0, 0, math.rad(-40) + (i % 2) * math.rad(90)))
			add(link)
		end
	end
end

function RiderLook.Clear(character: Model)
	local state = saved[character]
	if not state then
		return
	end
	saved[character] = nil
	for part, value in state.Transparency do
		if part.Parent then
			part.Transparency = value
		end
	end
	for part, color in state.Colors do
		if part.Parent then
			part.Color = color
		end
	end
	for decal, value in state.Decals do
		if decal.Parent then
			decal.Transparency = value
		end
	end
	for _, inst in state.Added do
		inst:Destroy()
	end
end

return RiderLook
