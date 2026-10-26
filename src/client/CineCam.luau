--[[
	CineCam: a camera mode for recording videos and stunt edits. P toggles it (or the 🎥 button on
	touch); it hides the HUD and the Roblox menus and takes over the camera, aimed at your bike when
	you're riding and at you when you're not. The game keeps playing: ride as usual while it films.

	Shots ([ and ] to cycle):
	  Chase     low and smooth behind, a touch of lag and a wide lens
	  Wheel     down at the rear wheel, beside it
	  Side      tracking alongside at the bike's pace
	  Tripod    a fixed spot ahead that pans to follow, and leapfrogs ahead once you're past
	  Drone     a slow orbit from above
	  Helmet    the rider's eyes, rolling with the lean
	  Free      fly anywhere: I/K forward/back, J/L left/right, U/O down/up, right-drag to look,
	            = and - for speed
	, and . zoom; ; letterbox bars; ' focus blur on the subject. Touch: prev / next / bars / exit.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BikeController = require(script.Parent.BikeController)

local CineCam = {}

local player = Players.LocalPlayer
local SHOTS = { "Chase", "Wheel", "Side", "Tripod", "Drone", "Helmet", "Free" }

local active = false
local shot = 1
local fov = 60
local bars = false
local blur = true
local freeCF = CFrame.identity
local freeSpeed = 40
local looking = false
local camCF: CFrame? = nil
local tripod: Vector3? = nil
local orbit = 0
local hidden: { [ScreenGui]: boolean } = {}
local overlay: ScreenGui? = nil
local hint: TextLabel? = nil
local hintAt = 0
local dof: DepthOfFieldEffect? = nil

-- What the camera films: your bike's root while riding, else your character
local function subject(): (Vector3, CFrame, Vector3)
	local model = BikeController.Model
	local root = if BikeController.Active and model then model.PrimaryPart else nil
	if not root then
		local character = player.Character
		root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	if root then
		return root.Position, root.CFrame, root.AssemblyLinearVelocity
	end
	local camera = Workspace.CurrentCamera
	return camera.Focus.Position, camera.Focus, Vector3.zero
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function showHint()
	local label = hint
	if label then
		label.Text = string.format("🎥 %s   [ ] shot   , . zoom (%d)   ; bars   ' blur   P exit", SHOTS[shot], fov)
		hintAt = os.clock()
		label.TextTransparency = 0
		label.BackgroundTransparency = 0.45
	end
end

local function setShot(index: number)
	shot = (index - 1) % #SHOTS + 1
	tripod = nil
	camCF = nil
	if SHOTS[shot] == "Free" then
		freeCF = Workspace.CurrentCamera.CFrame
	end
	showHint()
end

local function hideInterface(hide: boolean)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if hide and gui then
		for _, g in gui:GetChildren() do
			if g:IsA("ScreenGui") and g ~= overlay and g.Enabled then
				hidden[g] = true
				g.Enabled = false
			end
		end
	else
		for g in hidden do
			if g.Parent then
				g.Enabled = true
			end
		end
		table.clear(hidden)
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, not hide)
	end)
end

local function buildOverlay()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CineCam"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Enabled = false
	for i, y in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0, y)
		bar.Position = UDim2.fromScale(0, y)
		bar.Size = UDim2.fromScale(1, 0.11)
		bar.Visible = false
		bar.Parent = gui
	end
	local label = Instance.new("TextLabel")
	label.Name = "Hint"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -18)
	label.Size = UDim2.fromOffset(620, 30)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.45
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	hint = label
	-- touch buttons
	if UserInputService.TouchEnabled then
		local row = Instance.new("Frame")
		row.Name = "Buttons"
		row.AnchorPoint = Vector2.new(1, 0)
		row.Position = UDim2.new(1, -12, 0, 12)
		row.Size = UDim2.fromOffset(4 * 58, 50)
		row.BackgroundTransparency = 1
		row.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 8)
		layout.Parent = row
		type Button = { Text: string, Press: () -> () }
		local buttons: { Button } = {
			{ Text = "◀", Press = function() setShot(shot - 1) end },
			{ Text = "▶", Press = function() setShot(shot + 1) end },
			{ Text = "▬", Press = function() CineCam.ToggleBars() end },
			{ Text = "✕", Press = function() CineCam.Toggle() end },
		}
		for _, b in buttons do
			local button = Instance.new("TextButton")
			button.Size = UDim2.fromOffset(50, 50)
			button.BackgroundColor3 = Color3.new(0, 0, 0)
			button.BackgroundTransparency = 0.4
			button.TextColor3 = Color3.new(1, 1, 1)
			button.Font = Enum.Font.GothamBold
			button.TextSize = 22
			button.Text = b.Text
			button.Parent = row
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 10)
			c.Parent = button
			button.Activated:Connect(b.Press)
		end
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	overlay = gui
end

function CineCam.ToggleBars()
	bars = not bars
	local gui = overlay
	if gui then
		for _, name in { "Bar1", "Bar2" } do
			local bar = gui:FindFirstChild(name)
			if bar and bar:IsA("Frame") then
				bar.Visible = bars
			end
		end
	end
end

function CineCam.Toggle()
	active = not active
	local camera = Workspace.CurrentCamera
	if not overlay then
		buildOverlay()
	end
	local gui = overlay :: ScreenGui
	gui.Enabled = active
	hideInterface(active)
	if active then
		camera.CameraType = Enum.CameraType.Scriptable
		camCF = nil
		tripod = nil
		if not dof then
			local effect = Instance.new("DepthOfFieldEffect")
			effect.Name = "CineFocus"
			effect.FarIntensity = 0.35
			effect.NearIntensity = 0.2
			effect.InFocusRadius = 18
			effect.Parent = Lighting
			dof = effect
		end
		;(dof :: DepthOfFieldEffect).Enabled = blur
		showHint()
	else
		if dof then
			dof.Enabled = false
		end
		camera.FieldOfView = 70
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if BikeController.Active then
			camera.CameraType = Enum.CameraType.Scriptable -- the bike camera carries on
		else
			camera.CameraType = Enum.CameraType.Custom
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
end

function CineCam.Active(): boolean
	return active
end

local function place(dt: number)
	local camera = Workspace.CurrentCamera
	local position, frame, velocity = subject()
	local speed = velocity.Magnitude
	local dir = if speed > 2 then flat(velocity) else flat(frame.LookVector)
	local right = dir:Cross(Vector3.yAxis)
	local name = SHOTS[shot]
	local target: CFrame
	local look = position + Vector3.new(0, 2, 0)
	if name == "Chase" then
		local want = position - dir * 13 + Vector3.new(0, 4, 0)
		local from = if camCF then camCF.Position:Lerp(want, ease(5, dt)) else want
		target = CFrame.lookAt(from, look + dir * 4)
	elseif name == "Wheel" then
		local from = position - dir * 3.5 + right * 2.6 + Vector3.new(0, 0.6, 0)
		target = CFrame.lookAt(from, position + dir * 6 + Vector3.new(0, 1, 0))
	elseif name == "Side" then
		local want = position + right * 12 + Vector3.new(0, 2.5, 0)
		local from = if camCF then camCF.Position:Lerp(want, ease(6, dt)) else want
		target = CFrame.lookAt(from, look)
	elseif name == "Tripod" then
		local spot = tripod
		if not spot or (spot - position).Magnitude > 75 or (speed > 4 and (spot - position):Dot(dir) < -45) then
			-- set up ahead of the rider, off to one side, low
			spot = position + dir * math.clamp(speed * 2.2, 25, 60) + right * 10 + Vector3.new(0, 2, 0)
			tripod = spot
		end
		target = CFrame.lookAt(spot :: Vector3, look)
	elseif name == "Drone" then
		orbit += dt * 0.35
		local around = Vector3.new(math.cos(orbit), 0, math.sin(orbit))
		local want = position + around * 26 + Vector3.new(0, 16, 0)
		local from = if camCF then camCF.Position:Lerp(want, ease(3, dt)) else want
		target = CFrame.lookAt(from, look)
	elseif name == "Helmet" then
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local eye = if head then head.CFrame * CFrame.new(0, 0.25, -0.75) else frame * CFrame.new(0, 5, -1)
		target = eye
	else
		-- free flight
		local move = Vector3.zero
		local function held(key: Enum.KeyCode): number
			return if UserInputService:IsKeyDown(key) then 1 else 0
		end
		move += Vector3.new(held(Enum.KeyCode.L) - held(Enum.KeyCode.J), held(Enum.KeyCode.O) - held(Enum.KeyCode.U), held(Enum.KeyCode.K) - held(Enum.KeyCode.I))
		freeCF = freeCF * CFrame.new(move * freeSpeed * dt)
		target = freeCF
	end
	camCF = target
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = target
	camera.FieldOfView = fov
	local effect = dof
	if effect then
		effect.Enabled = blur
		effect.FocusDistance = (target.Position - position).Magnitude
	end
end

function CineCam.Init()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.P then
			CineCam.Toggle()
			return
		end
		if not active then
			return
		end
		if key == Enum.KeyCode.RightBracket then
			setShot(shot + 1)
		elseif key == Enum.KeyCode.LeftBracket then
			setShot(shot - 1)
		elseif key == Enum.KeyCode.Comma then
			fov = math.clamp(fov + 5, 15, 110)
			showHint()
		elseif key == Enum.KeyCode.Period then
			fov = math.clamp(fov - 5, 15, 110)
			showHint()
		elseif key == Enum.KeyCode.Semicolon then
			CineCam.ToggleBars()
		elseif key == Enum.KeyCode.Quote then
			blur = not blur
		elseif key == Enum.KeyCode.Equals then
			freeSpeed = math.min(freeSpeed * 1.5, 400)
		elseif key == Enum.KeyCode.Minus then
			freeSpeed = math.max(freeSpeed / 1.5, 4)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if active and SHOTS[shot] == "Free" and input.UserInputType == Enum.UserInputType.MouseMovement and looking then
			local d = input.Delta
			local _, yaw, _ = freeCF:ToEulerAnglesYXZ()
			local pitch = math.asin(math.clamp(freeCF.LookVector.Y, -1, 1))
			yaw -= d.X * 0.004
			pitch = math.clamp(pitch - d.Y * 0.004, -1.45, 1.45)
			freeCF = CFrame.new(freeCF.Position) * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
		end
	end)
	-- touch: a 🎥 button to open it (the menus hide while filming; the overlay has its own buttons)
	if UserInputService.TouchEnabled then
		local gui = Instance.new("ScreenGui")
		gui.Name = "CineCamButton"
		gui.ResetOnSpawn = false
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -12, 0, 64)
		button.Size = UDim2.fromOffset(46, 46)
		button.BackgroundColor3 = Color3.new(0, 0, 0)
		button.BackgroundTransparency = 0.45
		button.Text = "🎥"
		button.TextSize = 24
		button.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = button
		button.Activated:Connect(CineCam.Toggle)
		gui.Parent = player:WaitForChild("PlayerGui")
	end
	-- after the bike camera (and Roblox's own), so this has the last word on the camera
	RunService:BindToRenderStep("EB_CineCam", Enum.RenderPriority.Camera.Value + 10, function(dt: number)
		if not active then
			return
		end
		if looking and SHOTS[shot] == "Free" then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		place(dt)
		local label = hint
		if label and os.clock() - hintAt > 4 then
			local fade = math.clamp((os.clock() - hintAt - 4) / 1, 0, 1)
			label.TextTransparency = fade
			label.BackgroundTransparency = 0.45 + 0.55 * fade
		end
	end)
end

return CineCam
