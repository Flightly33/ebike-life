--[[
	GearService: rider gear (Shared/Gear). The Gear remote buys, wears and takes off pieces; what's
	worn is built onto the character from parts sized to each body part (R15, or R6's limbs) and
	welded on, in a "Gear" folder, so every player sees it; it follows the rider pose and the ragdoll
	because it's welded to the limbs. Helmet pieces carry FirstPersonHide (the body cam hides them).
	A Blender mesh `Gear_<Style>_<Slot>__Shell__Paint` (blender/gearkit.py, in CityKit.fbx) in
	ReplicatedStorage.VehicleMeshes, once imported, replaces a piece's main shell. While the Deathrider's look is on (RiderLook's attribute) no gear is shown.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared.Gear)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local GearService = {}

local SMOOTH = Enum.Material.SmoothPlastic
local GLASS = Color3.fromRGB(16, 18, 22)

local function part(character: Model, folder: Folder, body: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = body.CFrame * offset
	p.Color = color
	p.Material = material or SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = folder
	local _ = character
	return p
end

-- an imported mesh for this style and slot, sized to `size` (nil before the owner's import)
local function mesh(style: string, slot: string, size: Vector3): MeshPart?
	local meshes = ReplicatedStorage:FindFirstChild("VehicleMeshes")
	-- (blender/gearkit.py: the shell's mesh object is Gear_<Style>_<Slot>__Shell__Paint)
	local found = meshes and (meshes:FindFirstChild("Gear_" .. style .. "_" .. slot .. "__Shell__Paint", true) or meshes:FindFirstChild("Gear_" .. style .. "_" .. slot, true))
	if found and found:IsA("MeshPart") then
		local copy = found:Clone()
		copy.Size = size
		return copy
	end
	return nil
end

-- the main shell of a piece: the imported mesh when there is one, else a part
local function shell(character: Model, folder: Folder, body: BasePart, item: Gear.Item, name: string, size: Vector3, offset: CFrame, shape: Enum.PartType?): BasePart
	local m = mesh(item.Style, item.Slot, size)
	if m then
		m.Name = name
		m.CFrame = body.CFrame * offset
		m.Color = item.Main
		m.CanCollide = false
		m.CanQuery = false
		m.CanTouch = false
		m.Massless = true
		m.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = m
		weld.Parent = m
		m.Parent = folder
		return m
	end
	return part(character, folder, body, name, size, offset, item.Main, nil, shape)
end

local function trimMaterial(item: Gear.Item): Enum.Material
	return if item.Glow then Enum.Material.Neon else SMOOTH
end

local function find(character: Model, ...: string): BasePart?
	for _, name in { ... } do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local function helmet(character: Model, folder: Folder, item: Gear.Item)
	local head = find(character, "Head")
	if not head then
		return
	end
	local s = head.Size
	local d = math.max(s.X, s.Y, s.Z) * 1.22
	local pieces: { BasePart } = {}
	local style = item.Style
	-- open-face: the shell rides high and back so the face shows; the others cover the head
	local lift = if style == "OpenFace" then 0.18 else 0.06
	local back = if style == "OpenFace" then 0.1 else 0.03
	table.insert(pieces, shell(character, folder, head, item, "GearHelmet", Vector3.one * d, CFrame.new(0, s.Y * lift, s.Z * back), Enum.PartType.Ball))
	if style == "OpenFace" then
		table.insert(pieces, part(character, folder, head, "GearHelmetBrim", Vector3.new(s.X * 0.9, s.Y * 0.06, s.Z * 0.3), CFrame.new(0, s.Y * 0.32, -s.Z * 0.5), item.Trim))
	elseif style == "MX" then
		table.insert(pieces, part(character, folder, head, "GearHelmetPeak", Vector3.new(s.X * 0.95, s.Y * 0.08, s.Z * 0.55), CFrame.new(0, s.Y * 0.42, -s.Z * 0.62) * CFrame.Angles(math.rad(-12), 0, 0), item.Trim, trimMaterial(item)))
		table.insert(pieces, part(character, folder, head, "GearHelmetChin", Vector3.new(s.X * 0.6, s.Y * 0.32, s.Z * 0.3), CFrame.new(0, -s.Y * 0.3, -s.Z * 0.55) * CFrame.Angles(math.rad(20), 0, 0), item.Main))
		table.insert(pieces, part(character, folder, head, "GearGoggles", Vector3.new(s.X * 0.95, s.Y * 0.22, s.Z * 0.12), CFrame.new(0, s.Y * 0.12, -s.Z * 0.6), GLASS, Enum.Material.Glass))
	else
		-- full-face and race: a dark visor across the front
		table.insert(pieces, part(character, folder, head, "GearVisor", Vector3.new(s.X * 0.82, s.Y * 0.32, s.Z * 0.1), CFrame.new(0, s.Y * 0.08, -s.Z * 0.62), GLASS, Enum.Material.Glass))
		table.insert(pieces, part(character, folder, head, "GearHelmetStripe", Vector3.new(s.X * 0.16, s.Y * 0.06, s.Z * 1.25), CFrame.new(0, s.Y * 0.62, s.Z * 0.03), item.Trim, trimMaterial(item)))
		if style == "Race" then
			table.insert(pieces, part(character, folder, head, "GearSpoiler", Vector3.new(s.X * 0.7, s.Y * 0.08, s.Z * 0.25), CFrame.new(0, s.Y * 0.48, s.Z * 0.62) * CFrame.Angles(math.rad(15), 0, 0), item.Trim, trimMaterial(item)))
		end
	end
	for _, p in pieces do
		p:SetAttribute("FirstPersonHide", true)
	end
end

local function jacket(character: Model, folder: Folder, item: Gear.Item)
	local torso = find(character, "UpperTorso", "Torso")
	if torso then
		local s = torso.Size
		shell(character, folder, torso, item, "GearJacket", s * Vector3.new(1.1, 1.04, 1.16), CFrame.new(0, s.Y * 0.02, 0))
		part(character, folder, torso, "GearJacketBand", Vector3.new(s.X * 1.12, s.Y * 0.1, s.Z * 1.18), CFrame.new(0, s.Y * 0.12, 0), item.Trim, trimMaterial(item))
		part(character, folder, torso, "GearCollar", Vector3.new(s.X * 0.55, s.Y * 0.12, s.Z * 1.1), CFrame.new(0, s.Y * 0.55, 0), item.Trim)
		if item.Style == "Leather" then
			part(character, folder, torso, "GearZip", Vector3.new(s.X * 0.05, s.Y * 0.9, s.Z * 0.05), CFrame.new(s.X * 0.12, 0, -s.Z * 0.59), item.Trim, Enum.Material.Metal)
		elseif item.Style == "Race" then
			part(character, folder, torso, "GearHump", Vector3.new(s.X * 0.5, s.Y * 0.55, s.Z * 0.35), CFrame.new(0, s.Y * 0.2, s.Z * 0.66), item.Main)
			part(character, folder, torso, "GearHumpStripe", Vector3.new(s.X * 0.12, s.Y * 0.56, s.Z * 0.36), CFrame.new(0, s.Y * 0.2, s.Z * 0.67), item.Trim, trimMaterial(item))
		end
		local lower = find(character, "LowerTorso")
		if lower then
			shell(character, folder, lower, item, "GearJacketHem", lower.Size * Vector3.new(1.1, 0.6, 1.16), CFrame.new(0, lower.Size.Y * 0.2, 0))
		end
	end
	-- sleeves: R15's upper and lower arms, or R6's whole arms
	for _, side in { "Left", "Right" } do
		for _, name in { side .. "UpperArm", side .. "LowerArm", side .. " Arm" } do
			local arm = find(character, name)
			if arm then
				local s = arm.Size
				local r6 = string.find(name, " ") ~= nil
				shell(character, folder, arm, item, "GearSleeve", s * Vector3.new(1.14, if r6 then 0.82 else 1.02, 1.14), CFrame.new(0, if r6 then s.Y * 0.08 else 0, 0))
				if name == side .. "UpperArm" or r6 then
					-- shoulder armour / sliders in the trim colour
					part(character, folder, arm, "GearShoulder", Vector3.new(s.X * 1.2, s.Y * 0.18, s.Z * 1.2), CFrame.new(0, s.Y * (if r6 then 0.38 else 0.36), 0), item.Trim, trimMaterial(item))
				end
			end
		end
	end
end

local function gloves(character: Model, folder: Folder, item: Gear.Item)
	for _, side in { "Left", "Right" } do
		local hand = find(character, side .. "Hand")
		if hand then
			local s = hand.Size
			shell(character, folder, hand, item, "GearGlove", s * 1.18, CFrame.new())
			part(character, folder, hand, "GearKnuckle", Vector3.new(s.X * 1.22, s.Y * 0.25, s.Z * 0.5), CFrame.new(0, -s.Y * 0.1, -s.Z * 0.35), item.Trim)
			if item.Style == "Gauntlets" then
				local forearm = find(character, side .. "LowerArm")
				if forearm then
					local f = forearm.Size
					part(character, folder, forearm, "GearCuff", Vector3.new(f.X * 1.25, f.Y * 0.32, f.Z * 1.25), CFrame.new(0, -f.Y * 0.34, 0), item.Main)
				end
			end
		else
			-- R6: a glove at the end of the arm
			local arm = find(character, side .. " Arm")
			if arm then
				local s = arm.Size
				shell(character, folder, arm, item, "GearGlove", Vector3.new(s.X * 1.12, s.Y * 0.22, s.Z * 1.12), CFrame.new(0, -s.Y * 0.4, 0))
			end
		end
	end
end

local function boots(character: Model, folder: Folder, item: Gear.Item)
	for _, side in { "Left", "Right" } do
		local foot = find(character, side .. "Foot")
		if foot then
			local s = foot.Size
			shell(character, folder, foot, item, "GearBoot", s * Vector3.new(1.16, 1.25, 1.12), CFrame.new(0, s.Y * 0.05, 0))
			local shin = find(character, side .. "LowerLeg")
			if shin then
				local l = shin.Size
				local tall = item.Style == "MXBoots"
				part(character, folder, shin, "GearBootShaft", Vector3.new(l.X * 1.16, l.Y * (if tall then 0.62 else 0.3), l.Z * 1.16), CFrame.new(0, -l.Y * (if tall then 0.18 else 0.34), 0), item.Main)
				if tall then
					for i = 1, 3 do
						part(character, folder, shin, "GearBuckle", Vector3.new(l.X * 1.2, l.Y * 0.05, l.Z * 0.3), CFrame.new(0, -l.Y * (0.42 - i * 0.14), -l.Z * 0.5), item.Trim, Enum.Material.Metal)
					end
				end
			end
		else
			local leg = find(character, side .. " Leg")
			if leg then
				local s = leg.Size
				shell(character, folder, leg, item, "GearBoot", Vector3.new(s.X * 1.12, s.Y * 0.35, s.Z * 1.2), CFrame.new(0, -s.Y * 0.33, -s.Z * 0.04))
			end
		end
	end
end

local BUILDERS: { [string]: (Model, Folder, Gear.Item) -> () } = {
	Helmet = helmet,
	Jacket = jacket,
	Gloves = gloves,
	Boots = boots,
}

-- (Re)build what the player wears on their character
function GearService.Apply(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild("Gear")
	if old then
		old:Destroy()
	end
	local data = DataService.Get(player)
	if not data or character:GetAttribute("RiderLook") ~= nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Gear"
	for _, slot in Gear.Slots do
		local item = Gear.Get(data.Gear.Worn[slot])
		if item then
			BUILDERS[slot](character, folder, item)
		end
	end
	folder.Parent = character
end

local function buy(player: Player, id: string): (boolean, string)
	local data = DataService.Get(player)
	local item = Gear.Get(id)
	if not data or not item then
		return false, "No such gear"
	end
	if data.Gear.Owned[id] then
		return false, "You already have it"
	end
	if data.Level < item.Level then
		return false, string.format("Unlocks at level %d", item.Level)
	end
	if not DataService.Spend(player, item.Price) then
		return false, "Not enough cash"
	end
	data.Gear.Owned[id] = true
	data.Gear.Worn[item.Slot] = id -- (put it straight on)
	DataService.Changed(player)
	GearService.Apply(player)
	return true, item.Name
end

local function wear(player: Player, id: string): (boolean, string)
	local data = DataService.Get(player)
	local item = Gear.Get(id)
	if not data or not item then
		return false, "No such gear"
	end
	if not data.Gear.Owned[id] then
		return false, "Buy it first"
	end
	data.Gear.Worn[item.Slot] = id
	DataService.Changed(player)
	GearService.Apply(player)
	return true, item.Name
end

local function takeOff(player: Player, slot: string): (boolean, string)
	local data = DataService.Get(player)
	if not data or not Gear.IsSlot(slot) then
		return false, "Nothing to take off"
	end
	data.Gear.Worn[slot] = nil
	DataService.Changed(player)
	GearService.Apply(player)
	return true, slot
end

-- the character is ready for gear once CharacterService has scaled it (or it isn't going to)
local function onCharacter(player: Player, character: Model)
	DataService.WaitFor(player)
	local since = os.clock()
	while character.Parent and character:GetAttribute("BodyHeight") == nil and os.clock() - since < 4 do
		task.wait(0.2)
	end
	if player.Character == character then
		GearService.Apply(player)
	end
	character:GetAttributeChangedSignal("RiderLook"):Connect(function()
		if player.Character == character then
			GearService.Apply(player)
		end
	end)
end

function GearService.Init()
	Remotes.Function("Gear").OnServerInvoke = function(player: Player, action: any, id: any)
		if type(action) ~= "string" or type(id) ~= "string" then
			return false, "Bad request"
		end
		if action == "Buy" then
			return buy(player, id)
		elseif action == "Wear" then
			return wear(player, id)
		elseif action == "TakeOff" then
			return takeOff(player, id)
		end
		return false, "Bad request"
	end
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		local character = player.Character
		if character then
			task.spawn(onCharacter, player, character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return GearService
