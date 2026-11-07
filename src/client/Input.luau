--[[
	Input: one riding input from keyboard, gamepad and touch.

	Keyboard (as on the reference HUD, and rebindable in Menus > Controls: Shared/Controls, saved in
	Settings.Keys): W gas, S brake, A/D steer (the arrow keys too), Shift or Ctrl wheelie, C one
	hand, V no hands, Q bunny hop (hold to preload), M ride mode, H bell, R drift (locks the rear
	brake), F first person. In the air: Z superman, X can-can, T nac-nac, G knee knocker, N no-footer
	(hold), Y barspin (tap). On the ground: brake + wheelie = stoppie. Fixed: Space gets off (Roblox's
	own jump does that), 1-5 pick a mode, P is the video camera (Client/CineCam).
	Gamepad: RT gas, LT brake, left stick steer, X wheelie, Y hop, B drift, d-pad left/right one/no
	hands, RB/LB mode, R3 first person, A get off. Touch: the on-screen riding buttons (UI/TouchControls) and the thumbstick.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BikePhysics = require(Shared.BikePhysics)
local Controls = require(Shared.Controls)
local Signal = require(Shared.Signal)

local State = require(script.Parent.State)

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
local bound: { [string]: { Enum.KeyCode } } = {} -- action id -> the keys that do it
local bindRide: () -> ()

local function keyCode(name: string): Enum.KeyCode?
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok and code ~= nil then code :: Enum.KeyCode else nil
end

-- Use these key bindings (Settings.Keys; nil for the defaults)
function Input.Bind(keys: Controls.Keys?)
	for _, action in Controls.List do
		local codes = {}
		for _, name in Controls.Keys(keys, action.Id) do
			local code = keyCode(name)
			if code then
				table.insert(codes, code)
			end
		end
		bound[action.Id] = codes
	end
	if enabled then
		bindRide()
	end
end

-- The bike is in the air: pad buttons switch to their trick meanings (BikeController, every frame)
function Input.SetAirborne(inAir: boolean)
	airborne = inAir
end

-- One of the keys bound to this action is held
local function held(id: string): boolean
	local keys: { Enum.KeyCode } = bound[id] or {}
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function has(id: string, key: Enum.KeyCode): boolean
	return table.find(bound[id] or {}, key) ~= nil
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
	local kbGas = if held("Gas") then 1 else 0
	local kbBrake = if held("Brake") then 1 else 0
	local kbSteer = (if held("Right") then 1 else 0) - (if held("Left") then 1 else 0)
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
	input.Wheelie = held("Wheelie") or gpWheelie or t.Wheelie
	input.Hop = held("Hop") or gpHop or t.Hop
	input.OneHand = held("OneHand") or gpOne or t.OneHand
	input.NoHands = held("NoHands") or gpNo or t.NoHands
	local padDrift = gamepadDrift()
	if padDrift and airborne then
		padDriftLatched = true
	elseif not padDrift then
		padDriftLatched = false
	end
	input.Drift = held("Drift") or (padDrift and not padDriftLatched) or t.Drift
	-- air tricks (the physics only uses them in the air)
	local pad = UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1)
	local function button(key: Enum.KeyCode): boolean
		return pad and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
	end
	if held("Superman") or button(Enum.KeyCode.DPadUp) or t.Trick then
		input.Trick = "Superman"
	elseif held("CanCan") or button(Enum.KeyCode.ButtonB) then
		input.Trick = "CanCan"
	elseif held("NacNac") or (airborne and button(Enum.KeyCode.ButtonL1)) then
		input.Trick = "NacNac"
	elseif held("KneeKnocker") or button(Enum.KeyCode.DPadDown) then
		input.Trick = "KneeKnocker"
	elseif held("NoFooter") or (airborne and button(Enum.KeyCode.ButtonR1)) then
		input.Trick = "NoFooter"
	end
	input.Barspin = held("Barspin") or button(Enum.KeyCode.ButtonY) or t.Barspin
	return input
end

local MODE_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

local function onRideKey(_name: string, state: Enum.UserInputState, object: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	local key = object.KeyCode
	if has("Mode", key) or (key == Enum.KeyCode.ButtonR1 and not airborne) then
		Input.Action:Fire("ModeUp") -- (in the air the bumpers are Nac-Nac and No-Footer)
	elseif key == Enum.KeyCode.ButtonL1 and not airborne then
		Input.Action:Fire("ModeDown")
	elseif has("Bell", key) then
		Input.Action:Fire("Bell")
	elseif has("Camera", key) or key == Enum.KeyCode.ButtonR3 then
		Input.Action:Fire("Camera")
	else
		local index = table.find(MODE_KEYS, key)
		if index then
			Input.Action:Fire("Mode", index)
		end
	end
	return Enum.ContextActionResult.Pass
end

-- (re)binds the riding keys: the mode, bell and camera keys the player chose, 1-5, the pad's
bindRide = function()
	ContextActionService:UnbindAction("EB_Ride")
	local keys = table.clone(MODE_KEYS)
	for _, key in { Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR3 } do
		table.insert(keys, key)
	end
	for _, id in { "Mode", "Bell", "Camera" } do
		local extra: { Enum.KeyCode } = bound[id] or {}
		for _, key in extra do
			table.insert(keys, key)
		end
	end
	ContextActionService:BindActionAtPriority("EB_Ride", onRideKey, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
end

-- While riding, mode keys and the bell; Shift-lock would fight the wheelie key, so it's off
function Input.SetRiding(riding: boolean)
	enabled = riding
	if riding then
		bindRide()
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
	Input.Bind(State.Settings().Keys)
	State.SettingsChanged:Connect(function(settings: any)
		Input.Bind(if type(settings) == "table" then settings.Keys else nil)
	end)
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

Input.Bind(nil) -- the defaults until the save's settings arrive

return Input
