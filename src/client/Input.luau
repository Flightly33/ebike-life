--[[
	Input: one riding input from keyboard, gamepad and touch.

	Keyboard (as on the reference HUD): W gas, S brake, A/D steer, Shift or Ctrl wheelie, C one hand,
	V no hands, Space get off (Roblox's own jump does that), plus Q bunny hop (hold to preload),
	M ride mode, 1-5 pick a mode, H bell, R drift (locks the rear brake), F first person.
	In the air: Z superman, X can-can, T nac-nac, G knee knocker, N no-footer (hold), Y barspin (tap).
	On the ground: brake + Shift = stoppie.
	Gamepad: RT gas, LT brake, left stick steer, X wheelie, Y hop, B drift, d-pad left/right one/no
	hands, RB/LB mode, R3 first person, A get off. Touch: the on-screen riding buttons (UI/TouchControls) and the thumbstick.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BikePhysics = require(Shared.BikePhysics)
local Signal = require(Shared.Signal)

local Input = {}

Input.Action = Signal.new() -- ("ModeUp" | "ModeDown" | "Mode" (index) | "Bell" | "Camera")

-- Held states set by the touch buttons
Input.Touch = {
	Gas = false,
	Brake = false,
	Wheelie = false,
	Hop = false,
	Drift = false,
	Trick = false,
	Barspin = false,
	OneHand = false,
	NoHands = false,
}

local controls: any = nil
local enabled = false
local airborne = false
local padDriftLatched = false -- B held from the air (a Can-Can) doesn't become a drift on landing

-- The bike is in the air: pad buttons switch to their trick meanings (BikeController, every frame)
function Input.SetAirborne(inAir: boolean)
	airborne = inAir
end

local function down(...: Enum.KeyCode): boolean
	for _, key in { ... } do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function gamepad(): (number, number, number, boolean, boolean, boolean, boolean)
	local gas, brake, steer = 0, 0, 0
	local wheelie, hop, oneHand, noHands = false, false, false, false
	if not UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		return gas, brake, steer, wheelie, hop, oneHand, noHands
	end
	for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		local key = state.KeyCode
		if key == Enum.KeyCode.ButtonR2 then
			gas = math.max(gas, state.Position.Z)
		elseif key == Enum.KeyCode.ButtonL2 then
			brake = math.max(brake, state.Position.Z)
		elseif key == Enum.KeyCode.Thumbstick1 then
			if math.abs(state.Position.X) > 0.15 then
				steer = state.Position.X
			end
		elseif key == Enum.KeyCode.ButtonX then
			wheelie = state.UserInputState == Enum.UserInputState.Begin or state.UserInputState == Enum.UserInputState.Change
		elseif key == Enum.KeyCode.ButtonY then
			hop = state.UserInputState == Enum.UserInputState.Begin or state.UserInputState == Enum.UserInputState.Change
		elseif key == Enum.KeyCode.DPadLeft then
			oneHand = state.UserInputState == Enum.UserInputState.Begin or state.UserInputState == Enum.UserInputState.Change
		elseif key == Enum.KeyCode.DPadRight then
			noHands = state.UserInputState == Enum.UserInputState.Begin or state.UserInputState == Enum.UserInputState.Change
		end
	end
	return gas, brake, steer, wheelie, hop, oneHand, noHands
end

local function gamepadDrift(): boolean
	if not UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		return false
	end
	return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB)
end

-- The riding input right now (focus in a text box ignores the keyboard)
function Input.Read(): BikePhysics.Input
	local input = BikePhysics.Idle()
	if UserInputService:GetFocusedTextBox() then
		return input
	end
	local kbGas = if down(Enum.KeyCode.W, Enum.KeyCode.Up) then 1 else 0
	local kbBrake = if down(Enum.KeyCode.S, Enum.KeyCode.Down) then 1 else 0
	local kbSteer = (if down(Enum.KeyCode.D, Enum.KeyCode.Right) then 1 else 0) - (if down(Enum.KeyCode.A, Enum.KeyCode.Left) then 1 else 0)
	local gpGas, gpBrake, gpSteer, gpWheelie, gpHop, gpOne, gpNo = gamepad()

	-- Touch thumbstick: X steers, pushing forward also works as gas
	local stickSteer, stickGas = 0, 0
	if UserInputService.TouchEnabled and controls then
		local ok, move = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(move) == "Vector3" then
			stickSteer = math.clamp(move.X, -1, 1)
			stickGas = math.clamp(-move.Z, 0, 1)
		end
	end

	local t = Input.Touch
	input.Throttle = math.max(kbGas, gpGas, if t.Gas then 1 else 0, stickGas)
	input.Brake = math.max(kbBrake, gpBrake, if t.Brake then 1 else 0)
	local steer = kbSteer
	if math.abs(gpSteer) > math.abs(steer) then
		steer = gpSteer
	end
	if math.abs(stickSteer) > math.abs(steer) then
		steer = stickSteer
	end
	input.Steer = math.clamp(steer, -1, 1)
	input.Wheelie = down(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl) or gpWheelie or t.Wheelie
	input.Hop = down(Enum.KeyCode.Q) or gpHop or t.Hop
	input.OneHand = down(Enum.KeyCode.C) or gpOne or t.OneHand
	input.NoHands = down(Enum.KeyCode.V) or gpNo or t.NoHands
	local padDrift = gamepadDrift()
	if padDrift and airborne then
		padDriftLatched = true
	elseif not padDrift then
		padDriftLatched = false
	end
	input.Drift = down(Enum.KeyCode.R) or (padDrift and not padDriftLatched) or t.Drift
	-- air tricks (the physics only uses them in the air)
	local pad = UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1)
	local function button(key: Enum.KeyCode): boolean
		return pad and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
	end
	if down(Enum.KeyCode.Z) or button(Enum.KeyCode.DPadUp) or t.Trick then
		input.Trick = "Superman"
	elseif down(Enum.KeyCode.X) or button(Enum.KeyCode.ButtonB) then
		input.Trick = "CanCan"
	elseif down(Enum.KeyCode.T) or (airborne and button(Enum.KeyCode.ButtonL1)) then
		input.Trick = "NacNac"
	elseif down(Enum.KeyCode.G) or button(Enum.KeyCode.DPadDown) then
		input.Trick = "KneeKnocker"
	elseif down(Enum.KeyCode.N) or (airborne and button(Enum.KeyCode.ButtonR1)) then
		input.Trick = "NoFooter"
	end
	input.Barspin = down(Enum.KeyCode.Y) or button(Enum.KeyCode.ButtonY) or t.Barspin
	return input
end

-- While riding, mode keys and the bell; Shift-lock would fight the wheelie key, so it's off
function Input.SetRiding(riding: boolean)
	enabled = riding
	if riding then
		ContextActionService:BindActionAtPriority("EB_Ride", function(_name: string, state: Enum.UserInputState, object: InputObject)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			local key = object.KeyCode
			if key == Enum.KeyCode.M or (key == Enum.KeyCode.ButtonR1 and not airborne) then
				Input.Action:Fire("ModeUp") -- (in the air the bumpers are Nac-Nac and No-Footer)
			elseif key == Enum.KeyCode.ButtonL1 and not airborne then
				Input.Action:Fire("ModeDown")
			elseif key == Enum.KeyCode.H then
				Input.Action:Fire("Bell")
			elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonR3 then
				Input.Action:Fire("Camera")
			else
				local index = table.find({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }, key)
				if index then
					Input.Action:Fire("Mode", index)
				end
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.M, Enum.KeyCode.H, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL1, Enum.KeyCode.F, Enum.KeyCode.ButtonR3)
	else
		ContextActionService:UnbindAction("EB_Ride")
		for key in Input.Touch do
			(Input.Touch :: any)[key] = false
		end
	end
end

function Input.Riding(): boolean
	return enabled
end

function Input.Init()
	task.spawn(function()
		local player = Players.LocalPlayer
		local scripts = player:WaitForChild("PlayerScripts")
		local module = scripts:WaitForChild("PlayerModule", 20)
		if module and module:IsA("ModuleScript") then
			local ok, playerModule = pcall(require, module)
			if ok and type(playerModule) == "table" then
				local getControls = (playerModule :: any).GetControls
				if type(getControls) == "function" then
					controls = getControls(playerModule)
				end
			end
		end
	end)
end

return Input
