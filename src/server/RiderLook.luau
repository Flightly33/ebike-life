--[[
	RiderLook: what riding certain bikes does to the rider. The Deathrider's Hellfire turns the head
	into a burning skull (bone-white, dark eye sockets, a jaw, fire) and the body black, like the
	comic-book ghost rider; getting off puts everything back exactly as it was.

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
	-- the skull
	local s = head.Size.Y
	local skull = piece(character, "EB_Skull", Vector3.new(1.15, 1.15, 1.15) * s, BONE, Enum.PartType.Ball)
	weld(skull, head, CFrame.new(0, 0.05 * s, 0))
	local jaw = piece(character, "EB_Jaw", Vector3.new(0.7, 0.3, 0.6) * s, BONE)
	weld(jaw, head, CFrame.new(0, -0.45 * s, -0.12 * s))
	for _, x in { -0.22, 0.22 } do
		local eye = piece(character, "EB_Socket", Vector3.new(0.3, 0.3, 0.3) * s, SOCKET, Enum.PartType.Ball)
		weld(eye, head, CFrame.new(x * s, 0.08 * s, -0.48 * s))
		local glow = piece(character, "EB_Ember", Vector3.new(0.1, 0.1, 0.1) * s, Color3.fromRGB(255, 120, 20), Enum.PartType.Ball)
		glow.Material = Enum.Material.Neon
		weld(glow, head, CFrame.new(x * s, 0.08 * s, -0.6 * s))
		table.insert(state.Added, eye)
		table.insert(state.Added, glow)
	end
	local nose = piece(character, "EB_Nose", Vector3.new(0.12, 0.16, 0.1) * s, SOCKET)
	weld(nose, head, CFrame.new(0, -0.15 * s, -0.55 * s))
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 12
	fire.Color = Color3.fromRGB(255, 110, 10)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
	fire.Parent = skull
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 30)
	light.Range = 14
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = skull
	for _, p in { skull, jaw, nose } do
		table.insert(state.Added, p)
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
