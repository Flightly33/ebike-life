--[[
	BikeCamera: the chase camera while riding.

	It orbits the bike at a yaw and pitch of its own. The yaw follows the bike's heading on the ground
	and its direction of travel in the air, so wheelies, flips and spins never swing the view. The
	follow is one exponential ease (no second positional lag), quick enough that turns feel direct.
	Drag with the right mouse button, the right stick or a finger to look around; while riding it eases
	back behind the bike a moment after you let go (standing still it stays where you put it).

	Walls pull the camera in at once and let it back out slowly; lamp posts, trees and other small
	props are ignored so the view doesn't pump in and out on a street.

	First person (F / R3 / CAM): the eye sits in the rider's head and rides with the bike: it leans
	into turns, tips back in a wheelie, dips on landings and buzzes with the road (more off-road and
	at speed). Look around as in the chase view (right mouse, right stick, drag); the head turns up
	to ~110° either way and eases back to the front while riding. Your own head and hats are hidden; your
	arms on the bars stay visible.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BikeCamera = {}

local BASE_PITCH = 0.2 -- radians above horizontal
local MIN_PITCH, MAX_PITCH = -0.25, 1.1
local MOUSE_RATE = 0.006 -- radians per pixel
local TOUCH_RATE = 0.008
local STICK_RATE = 3.2 -- radians per second at full tilt
local RECENTER_DELAY = 1.4
local SMALL_PROP = 5 -- props smaller than this (largest side, studs) don't block the camera

local active = false
BikeCamera.FirstPerson = false
BikeCamera.Rough = 0.2 -- how bumpy the surface is, 0..1 (the controller sets it)
local hidden: { [BasePart]: number } = {}
local bobTime = 0
local dip = 0 -- landing dip, studs
local roll = 0
local yaw = 0 -- the camera's follow yaw (behind the bike)
local orbitYaw, orbitPitch = 0, 0 -- the player's look-around offset
local zoom = 1
local lastLook = 0
local focusY: number? = nil
local distance: number? = nil
local shake = 0
local shakeTime = 0
local looking = false
local touchLook: InputObject? = nil

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true
local ignored: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local ignoredList: { Instance } = {}

local function wrap(angle: number): number
	return (angle + math.pi) % (math.pi * 2) - math.pi
end

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function refreshFilter()
	local list: { Instance } = {}
	for _, name in { "Bikes", "Vehicles" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, part in ignoredList do
		table.insert(list, part)
	end
	castParams.FilterDescendantsInstances = list
end

-- Distance the camera can sit from `origin` along `direction` before a wall
local function clearance(origin: Vector3, direction: Vector3): number
	local length = direction.Magnitude
	for _ = 1, 4 do
		local hit = Workspace:Spherecast(origin, 0.6, direction, castParams)
		if not hit then
			return length
		end
		local part = hit.Instance
		if part:IsA("BasePart") and not ignored[part] then
			local size = part.Size
			if math.max(size.X, size.Y, size.Z) < SMALL_PROP or part.Transparency > 0.9 then
				ignored[part] = true
				table.insert(ignoredList, part)
				refreshFilter()
				continue
			end
		end
		return math.max(hit.Distance, 1.5)
	end
	return length
end

local function look(dx: number, dy: number)
	orbitYaw = wrap(orbitYaw - dx)
	orbitPitch = math.clamp(orbitPitch + dy, MIN_PITCH - BASE_PITCH, MAX_PITCH - BASE_PITCH)
	lastLook = os.clock()
end

local function setHeadHidden(on: boolean)
	if on then
		local character = Players.LocalPlayer.Character
		if not character then
			return
		end
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				local accessory = d:FindFirstAncestorOfClass("Accessory")
				if d.Name == "Head" or accessory then
					hidden[d] = d.LocalTransparencyModifier
					d.LocalTransparencyModifier = 1
				end
			elseif d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
				d.Transparency = 1
			end
		end
	else
		for part, value in hidden do
			if part.Parent then
				part.LocalTransparencyModifier = value
			end
		end
		table.clear(hidden)
		local character = Players.LocalPlayer.Character
		local head = character and character:FindFirstChild("Head")
		if head then
			for _, d in head:GetChildren() do
				if d:IsA("Decal") then
					d.Transparency = 0
				end
			end
		end
	end
end

-- Switch between the chase camera and first person
function BikeCamera.Toggle()
	BikeCamera.FirstPerson = not BikeCamera.FirstPerson
	orbitYaw, orbitPitch = 0, 0
	if active then
		setHeadHidden(BikeCamera.FirstPerson)
	end
end

function BikeCamera.Start(target: CFrame)
	active = true
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local lookVector = target.LookVector
	yaw = math.atan2(-lookVector.X, -lookVector.Z)
	-- Start from wherever the walking camera was looking, then ease round behind the bike
	local camLook = camera.CFrame.LookVector
	orbitYaw = wrap(math.atan2(-camLook.X, -camLook.Z) - yaw)
	orbitPitch = 0
	lastLook = os.clock() - RECENTER_DELAY + 0.4
	focusY = nil
	distance = nil
	table.clear(ignoredList)
	table.clear(ignored)
	refreshFilter()
	if BikeCamera.FirstPerson then
		setHeadHidden(true)
	end
end

function BikeCamera.Stop(subject: Instance?)
	active = false
	looking = false
	touchLook = nil
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	if subject and subject:IsA("Humanoid") then
		camera.CameraSubject = subject
	end
	camera.FieldOfView = 70
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	setHeadHidden(false)
end

function BikeCamera.Shake(amount: number)
	shake = math.max(shake, amount)
	dip = math.max(dip, amount * 0.35)
end

-- First person: the eye in the rider's head, riding with the bike
local function firstPerson(dt: number, bike: CFrame, kmh: number, airborne: boolean)
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	local eye: Vector3
	if head and head:IsA("BasePart") then
		eye = head.Position + head.CFrame.LookVector * 0.35 + Vector3.new(0, 0.25, 0)
	else
		eye = (bike * CFrame.new(0, 5.4, 0.6)).Position
	end
	-- recentre the look while riding
	if kmh > 6 and os.clock() - lastLook > RECENTER_DELAY + 0.6 then
		orbitYaw *= 1 - ease(2, dt)
		orbitPitch *= 1 - ease(2, dt)
	end
	orbitYaw = math.clamp(orbitYaw, -1.9, 1.9)
	-- the bike's heading, pitch and some of its lean
	local _, yaw, _ = bike:ToEulerAnglesYXZ()
	local look = bike.LookVector
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	local right = bike.RightVector
	local lean = math.asin(math.clamp(-right.Y, -1, 1))
	roll += (lean * 0.55 - roll) * ease(8, dt)
	-- road buzz and a slow bob with speed; a dip on landings
	local speed = math.clamp(kmh / 60, 0, 1.5)
	bobTime += dt * (6 + kmh * 0.25)
	local buzz = if airborne then 0 else (0.012 + 0.05 * BikeCamera.Rough) * speed
	local bobY = math.sin(bobTime) * 0.04 * speed + math.noise(bobTime * 2.3, 3.1) * buzz * 3
	local bobX = math.noise(bobTime * 2.1, 9.7) * buzz * 2
	dip = math.max(0, dip - dt * 2.5)
	local cf = CFrame.new(eye + Vector3.new(0, bobY - dip * 0.6, 0))
		* CFrame.fromEulerAnglesYXZ(0, yaw + orbitYaw, 0)
		* CFrame.Angles(pitch * 0.85 - orbitPitch - 0.08, 0, 0)
		* CFrame.Angles(0, 0, roll)
		* CFrame.new(bobX, 0, 0)
	if shake > 0.01 then
		shakeTime += dt * 18
		local s = shake * 0.03
		cf *= CFrame.Angles(math.noise(shakeTime, 1.3) * s, math.noise(shakeTime, 7.1) * s, 0)
		shake = math.max(0, shake - dt * 2.5)
	end
	camera.CFrame = cf
	camera.Focus = cf * CFrame.new(0, 0, -8)
	camera.FieldOfView += (78 + math.clamp(kmh / 90, 0, 1) * 14 - camera.FieldOfView) * ease(3, dt)
end

--[[
	`bike`: the bike's drawn frame; `travelYaw`: the yaw to sit behind (the heading on the ground, the
	direction of travel in the air, nil to hold); `kmh`: speed; `airborne` lifts the camera a little.
]]
function BikeCamera.Update(dt: number, bike: CFrame, travelYaw: number?, kmh: number, airborne: boolean)
	if not active then
		return
	end
	local camera = Workspace.CurrentCamera

	if BikeCamera.FirstPerson then
		if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
			for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
				if state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.18 then
					look(state.Position.X * STICK_RATE * dt, -state.Position.Y * STICK_RATE * 0.6 * dt)
				end
			end
		end
		firstPerson(dt, bike, kmh, airborne)
		return
	end

	-- Right stick
	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.18 then
				look(state.Position.X * STICK_RATE * dt, -state.Position.Y * STICK_RATE * 0.6 * dt)
			end
		end
	end

	-- Follow the bike
	if travelYaw then
		local rate = if airborne then 2.5 else 6 + math.clamp(kmh / 40, 0, 1) * 3
		yaw = wrap(yaw + wrap(travelYaw - yaw) * ease(rate, dt))
	end
	if kmh > 6 and os.clock() - lastLook > RECENTER_DELAY then
		orbitYaw *= 1 - ease(3, dt)
		orbitPitch *= 1 - ease(3, dt)
	end

	-- Focus: exactly on the bike sideways, a little softened up and down (bumps, landings)
	local target = bike.Position + Vector3.new(0, 3.4, 0)
	local y = focusY or target.Y
	y += (target.Y - y) * ease(if airborne then 6 else 14, dt)
	y = math.clamp(y, target.Y - 3, target.Y + 3)
	focusY = y
	local focus = Vector3.new(target.X, y, target.Z)

	local speed = math.clamp(kmh / 90, 0, 1)
	local wanted = (11 + speed * 6 + (if airborne then 2 else 0)) * zoom
	local camYaw = yaw + orbitYaw
	local pitch = BASE_PITCH + orbitPitch
	local direction = Vector3.new(math.sin(camYaw) * math.cos(pitch), math.sin(pitch), math.cos(camYaw) * math.cos(pitch))

	-- Walls: in at once, back out gently
	local free = clearance(focus, direction * wanted)
	local current = distance or free
	if free < current then
		current = free
	else
		current += (free - current) * ease(3, dt)
	end
	distance = current

	local position = focus + direction * current
	local forward = Vector3.new(-math.sin(camYaw), 0, -math.cos(camYaw))
	local cf = CFrame.lookAt(position, focus + forward * 3)

	if shake > 0.01 then
		shakeTime += dt * 18
		local s = shake * 0.035
		cf *= CFrame.Angles(math.noise(shakeTime, 1.3) * s, math.noise(shakeTime, 7.1) * s, math.noise(shakeTime, 13.7) * s * 0.6)
		shake = math.max(0, shake - dt * 2.5)
	end
	camera.CFrame = cf
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView += (70 + speed * 12 - camera.FieldOfView) * ease(3, dt)
end

function BikeCamera.Init()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.Touch and not touchLook then
			touchLook = input
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and looking then
			looking = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input == touchLook then
			touchLook = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and looking then
			look(input.Delta.X * MOUSE_RATE, input.Delta.Y * MOUSE_RATE)
		elseif input == touchLook then
			look(input.Delta.X * TOUCH_RATE, input.Delta.Y * TOUCH_RATE)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			zoom = math.clamp(zoom - input.Position.Z * 0.1, 0.6, 2.2)
		end
	end)
end

return BikeCamera
