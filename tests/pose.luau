--[[
	Rider pose maths (Client/RiderIK) on a default R15 body: the limbs reach their targets, knees bend
	forward and elbows back, and leaning forward moves the shoulders forward. Uses Roblox's joint
	formula Part1 = Part0 * C0 * Transform * C1^-1, the same one the engine uses.

	lune run tests/pose.luau
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("../tools/lune/loader")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local Rig = Loader.Require("StarterPlayer.StarterPlayerScripts.Client.Rig")
local RiderIK = Loader.Require("StarterPlayer.StarterPlayerScripts.Client.RiderIK")

local failures = 0
local function check(ok: boolean, message: string)
	print((if ok then "  ok   " else "  FAIL ") .. message)
	if not ok then
		failures += 1
	end
end

-- A default R15 body (rig attachment positions of the standard avatar)
local SPEC = {
	{ "Root", "HumanoidRootPart", "LowerTorso", CFrame.new(0, -1, 0), CFrame.new(0, -0.2, 0) },
	{ "Waist", "LowerTorso", "UpperTorso", CFrame.new(0, 0.2, 0), CFrame.new(0, -0.8, 0) },
	{ "Neck", "UpperTorso", "Head", CFrame.new(0, 0.8, 0), CFrame.new(0, -0.5, 0) },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", CFrame.new(1, 0.56, 0), CFrame.new(-0.5, 0.42, 0) },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", CFrame.new(0, -0.42, 0), CFrame.new(0, 0.35, 0) },
	{ "RightWrist", "RightLowerArm", "RightHand", CFrame.new(0, -0.5, 0), CFrame.new(0, 0.12, 0) },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", CFrame.new(-1, 0.56, 0), CFrame.new(0.5, 0.42, 0) },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", CFrame.new(0, -0.42, 0), CFrame.new(0, 0.35, 0) },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", CFrame.new(0, -0.5, 0), CFrame.new(0, 0.12, 0) },
	{ "RightHip", "LowerTorso", "RightUpperLeg", CFrame.new(0.5, -0.2, 0), CFrame.new(0, 0.42, 0) },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", CFrame.new(0, -0.42, 0), CFrame.new(0, 0.42, 0) },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", CFrame.new(0, -0.5, 0), CFrame.new(0, 0.09, 0) },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", CFrame.new(-0.5, -0.2, 0), CFrame.new(0, 0.42, 0) },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", CFrame.new(0, -0.42, 0), CFrame.new(0, 0.42, 0) },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", CFrame.new(0, -0.5, 0), CFrame.new(0, 0.09, 0) },
}

-- `rotated` turns every rig attachment (some avatar packages do), which must not change the result
local function makeRig(rotated: boolean): any
	local joints = {}
	local turn = if rotated then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity
	for _, def in SPEC do
		local c0, c1 = def[4] * turn, def[5] * turn
		local q0 = c0 - c0.Position
		joints[def[1]] = { Name = def[1], Part0 = def[2], Part1 = def[3], C0 = c0, C1 = c1, Q0 = q0, Q0Inv = q0:Inverse(), Instance = { Transform = CFrame.identity } }
	end
	local J = joints
	local leg = (J.RightKnee.C0.Position - J.RightHip.C1.Position).Magnitude + (J.RightAnkle.C0.Position - J.RightKnee.C1.Position).Magnitude
	local arm = (J.RightElbow.C0.Position - J.RightShoulder.C1.Position).Magnitude + (J.RightWrist.C0.Position - J.RightElbow.C1.Position).Magnitude
	return { Joints = joints, Leg = leg, Arm = arm, AnkleToSole = 0.24 }
end

-- every part's world frame from the root's, through the written Transforms
local function solve(rig: any, hrp: any): { [string]: any }
	local parts = { HumanoidRootPart = hrp }
	for _, def in SPEC do
		local j = rig.Joints[def[1]]
		parts[def[3]] = parts[def[2]] * j.C0 * j.Instance.Transform * j.C1:Inverse()
	end
	return parts
end

for _, rotated in { false, true } do
	print(string.format("== %s rig attachments", if rotated then "rotated" else "standard"))
	local rig = makeRig(rotated)
	local J = rig.Joints
	local hrp = CFrame.new(10, 5, 3) * CFrame.Angles(0, math.rad(30), 0)
	local look, up, right = hrp.LookVector, hrp.UpVector, hrp.RightVector

	-- leaning forward moves the shoulders forward and down
	local _, upright = RiderIK.Torso(rig, hrp, 0, 0)
	local _, leant, rootT, waistT = RiderIK.Torso(rig, hrp, 0.8, 0)
	local s0 = (upright * J.RightShoulder.C0).Position
	local s1 = (leant * J.RightShoulder.C0).Position
	check((s1 - s0):Dot(look) > 0.4 and (s1 - s0):Dot(up) < 0, "leaning forward brings the shoulders forward and down")
	J.Root.Instance.Transform = rootT
	J.Waist.Instance.Transform = waistT
	local lower, upper = RiderIK.Torso(rig, hrp, 0.8, 0)

	-- a reachable hand target: ahead and below the shoulder
	local shoulder = (upper * J.RightShoulder.C0).Position
	local grip = shoulder + look * 1.2 - up * 0.6 + right * 0.2
	RiderIK.Limb(upper, J.RightShoulder, J.RightElbow, J.RightWrist, grip, -look * 0.5 + right * 0.9 - up * 0.4, Vector3.new(0, 0, 1), nil)
	local parts = solve(rig, hrp)
	local wrist = (parts.RightLowerArm * J.RightWrist.C0).Position
	local elbow = (parts.RightUpperArm * J.RightElbow.C0).Position
	check((wrist - grip).Magnitude < 0.02, string.format("the wrist reaches the grip (off by %.3f)", (wrist - grip).Magnitude))
	local mid = (shoulder + grip) / 2
	check((elbow - mid):Dot(right) > 0 or (elbow - mid):Dot(-look) > 0, "the elbow bends out / back, not forward")

	-- a reachable foot target: below and a little ahead of the hip
	local hip = (lower * J.RightHip.C0).Position
	local pedal = hip + look * 0.6 - up * 1.4 + right * 0.1
	RiderIK.Limb(lower, J.RightHip, J.RightKnee, J.RightAnkle, pedal, look + up * 0.35 + right * 0.2, Vector3.new(0, 0, -1), hrp - hrp.Position)
	parts = solve(rig, hrp)
	local ankle = (parts.RightLowerLeg * J.RightAnkle.C0).Position
	local knee = (parts.RightUpperLeg * J.RightKnee.C0).Position
	check((ankle - pedal).Magnitude < 0.02, string.format("the ankle reaches the pedal (off by %.3f)", (ankle - pedal).Magnitude))
	check((knee - (hip + pedal) / 2):Dot(look) > 0.1, "the knee bends forward")
	local footUp = parts.RightFoot.UpVector
	check(footUp:Dot(up) > 0.98, "the foot stays level with the bike")

	-- out of reach: the leg points straight at the target, no NaNs
	local far = hip + look * 0.3 - up * 6
	RiderIK.Limb(lower, J.RightHip, J.RightKnee, J.RightAnkle, far, look, Vector3.new(0, 0, -1), nil)
	parts = solve(rig, hrp)
	ankle = (parts.RightLowerLeg * J.RightAnkle.C0).Position
	local toward = (ankle - hip).Unit:Dot((far - hip).Unit)
	check(toward > 0.99 and ankle.X == ankle.X, "an out-of-reach pedal: the leg points straight at it")
end

if failures > 0 then
	print(string.format("%d failure(s)", failures))
	process.exit(1)
end
print("pose checks passed")
