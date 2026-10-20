--[[
	BikeCamera: the chase camera while riding. It sits behind and above the bike, swings round with
	it a little late, pulls back and widens with speed, and can be dragged around with the right
	mouse button (or the right stick) before easing back behind the bike. Shakes on landings and
	crashes.
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local World = require(script.Parent.World)

local BikeCamera = {}

local active = false
local position: Vector3? = nil
local focus = Vector3.zero
local orbitYaw = 0
local orbitPitch = 0
local zoom = 1
local idleSince = 0
local shake = 0
local headingYaw = 0

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function wrap(angle: number): number
	return (angle + math.pi) % (math.pi * 2) - math.pi
end

function BikeCamera.Start(target: CFrame)
	active = true
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	position = camera.CFrame.Position
	focus = target.Position
	headingYaw = math.atan2(-target.LookVector.X, -target.LookVector.Z)
	orbitYaw, orbitPitch = 0, 0
end

function BikeCamera.Stop(subject: Instance?)
	active = false
	position = nil
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	if subject and subject:IsA("Humanoid") then
		camera.CameraSubject = subject
	end
	camera.FieldOfView = 70
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function BikeCamera.Shake(amount: number)
	shake = math.max(shake, amount)
end

-- `bike`: the bike's frame; `kmh`: speed; `airborne` raises the camera a touch
function BikeCamera.Update(dt: number, bike: CFrame, kmh: number, airborne: boolean)
	if not active then
		return
	end
	local camera = Workspace.CurrentCamera
	-- Orbit with the right mouse button or the right stick
	local orbiting = false
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		local delta = UserInputService:GetMouseDelta()
		orbitYaw -= delta.X * 0.006
		orbitPitch = math.clamp(orbitPitch - delta.Y * 0.005, -0.35, 0.9)
		orbiting = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick2 and state.Position.Magnitude > 0.2 then
				orbitYaw -= state.Position.X * dt * 2.5
				orbitPitch = math.clamp(orbitPitch + state.Position.Y * dt * 1.5, -0.35, 0.9)
				orbiting = true
			end
		end
	end
	if orbiting then
		idleSince = os.clock()
	elseif os.clock() - idleSince > 1.2 then
		orbitYaw = lerp(orbitYaw, 0, 1 - math.exp(-dt * 2.5))
		orbitPitch = lerp(orbitPitch, 0, 1 - math.exp(-dt * 2.5))
	end

	-- Follow the bike's heading (flattened), lagging a little in turns
	local look = bike.LookVector
	local bikeYaw = math.atan2(-look.X, -look.Z)
	headingYaw += wrap(bikeYaw - headingYaw) * (1 - math.exp(-dt * (if airborne then 1.5 else 4.5)))
	local yaw = headingYaw + orbitYaw
	local speed = math.clamp(kmh / 100, 0, 1)
	local distance = (12 + speed * 7) * zoom
	local height = 4.6 + speed * 1.2 + (if airborne then 1.5 else 0)
	local pitch = orbitPitch
	local back = Vector3.new(math.sin(yaw), 0, math.cos(yaw)) -- behind the bike
	focus = focus:Lerp(bike.Position + Vector3.new(0, 3.2, 0), 1 - math.exp(-dt * 14))
	local offset = back * (distance * math.cos(pitch)) + Vector3.new(0, height + distance * math.sin(pitch), 0)
	local wanted = focus + offset

	-- Keep the camera out of walls
	local hit = Workspace:Raycast(focus, wanted - focus, World.Params())
	if hit then
		wanted = hit.Position + (focus - hit.Position).Unit * 0.8
	end
	local current = position or wanted
	current = current:Lerp(wanted, 1 - math.exp(-dt * 9))
	position = current

	local cf = CFrame.lookAt(current, focus + look * 6)
	if shake > 0.01 then
		local s = shake
		cf *= CFrame.Angles((math.random() - 0.5) * s * 0.06, (math.random() - 0.5) * s * 0.06, (math.random() - 0.5) * s * 0.04)
		shake = math.max(0, shake - dt * 3)
	end
	camera.CFrame = cf
	camera.FieldOfView = lerp(camera.FieldOfView, 70 + speed * 14, 1 - math.exp(-dt * 3))
end

function BikeCamera.Init()
	UserInputService.InputChanged:Connect(function(input, processed)
		if active and not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			zoom = math.clamp(zoom - input.Position.Z * 0.1, 0.6, 2.2)
		end
	end)
end

return BikeCamera
