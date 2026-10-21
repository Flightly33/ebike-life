--[[
	Rig: an R15 character's joints, read from the live character so the rider pose can drive them.

	Current Roblox avatars are jointed with AnimationConstraints (C0 / C1 are the constraint's two
	attachments); older rigs use Motor6Ds. Both take their pose through .Transform, where
		Part1 = Part0 * C0 * Transform * C1^-1
	Pose rotations given to ToTransform are in the parent part's frame (+X pitch, Root +X leans back);
	they're conjugated by the joint's C0 rotation so the same pose looks the same on every body.
]]

local Rig = {}

export type Joint = {
	Name: string,
	C0: CFrame,
	C1: CFrame,
	Q0: CFrame,
	Q0Inv: CFrame,
	Instance: Instance, -- the Motor6D or AnimationConstraint
}

export type RigInfo = {
	Joints: { [string]: Joint },
	Leg: number, -- hip pivot to ankle pivot, studs
	Arm: number, -- shoulder pivot to wrist pivot
	AnkleToSole: number,
}

-- joint name, the part it moves (Part1)
local JOINTS = {
	{ "Root", "LowerTorso" },
	{ "Waist", "UpperTorso" },
	{ "Neck", "Head" },
	{ "RightShoulder", "RightUpperArm" },
	{ "RightElbow", "RightLowerArm" },
	{ "RightWrist", "RightHand" },
	{ "LeftShoulder", "LeftUpperArm" },
	{ "LeftElbow", "LeftLowerArm" },
	{ "LeftWrist", "LeftHand" },
	{ "RightHip", "RightUpperLeg" },
	{ "RightKnee", "RightLowerLeg" },
	{ "RightAnkle", "RightFoot" },
	{ "LeftHip", "LeftUpperLeg" },
	{ "LeftKnee", "LeftLowerLeg" },
	{ "LeftAnkle", "LeftFoot" },
}
Rig.NAMES = {} :: { string }
for _, def in JOINTS do
	table.insert(Rig.NAMES, def[1])
end

local function frames(joint: Instance): (BasePart?, CFrame, CFrame)
	if joint:IsA("Motor6D") then
		return joint.Part1, joint.C0, joint.C1
	elseif joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		local p1 = a1 and a1.Parent
		if a0 and a1 and p1 and p1:IsA("BasePart") then
			return p1, a0.CFrame, a1.CFrame
		end
	end
	return nil, CFrame.identity, CFrame.identity
end

-- The joint that moves `part`: the one inside it named after the joint, else any joint whose Part1
-- it is (AnimationConstraints first)
local function findJoint(character: Model, part: BasePart, name: string): Instance?
	local direct = part:FindFirstChild(name)
	if direct and (direct:IsA("Motor6D") or direct:IsA("AnimationConstraint")) and frames(direct) == part then
		return direct
	end
	local fallback: Instance? = nil
	for _, d in character:GetDescendants() do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and frames(d) == part then
			if d:IsA("AnimationConstraint") then
				return d
			end
			fallback = fallback or d
		end
	end
	return fallback
end

-- nil for R6 bodies or a character that hasn't got all its joints yet
function Rig.FromCharacter(character: Model): RigInfo?
	local joints: { [string]: Joint } = {}
	for _, def in JOINTS do
		local name, partName = def[1], def[2]
		local part = character:FindFirstChild(partName)
		if not part or not part:IsA("BasePart") then
			return nil
		end
		local joint = findJoint(character, part, name)
		if not joint then
			return nil
		end
		local _, c0, c1 = frames(joint)
		local q0 = c0 - c0.Position
		joints[name] = { Name = name, C0 = c0, C1 = c1, Q0 = q0, Q0Inv = q0:Inverse(), Instance = joint }
	end
	local hip, knee, ankle = joints.RightHip, joints.RightKnee, joints.RightAnkle
	local shoulder, elbow, wrist = joints.RightShoulder, joints.RightElbow, joints.RightWrist
	local leg = (knee.C0.Position - hip.C1.Position).Magnitude + (ankle.C0.Position - knee.C1.Position).Magnitude
	local arm = (elbow.C0.Position - shoulder.C1.Position).Magnitude + (wrist.C0.Position - elbow.C1.Position).Magnitude
	local foot = character:FindFirstChild("RightFoot")
	local sole = if foot and foot:IsA("BasePart") then math.max(0.05, foot.Size.Y / 2 + ankle.C1.Position.Y) else 0.25
	return { Joints = joints, Leg = leg, Arm = arm, AnkleToSole = sole }
end

-- A pose rotation in the parent's frame -> the joint's Transform
function Rig.ToTransform(joint: Joint, rotation: CFrame): CFrame
	return joint.Q0Inv * rotation * joint.Q0
end

function Rig.Set(joint: Joint, transform: CFrame)
	(joint.Instance :: any).Transform = transform
end

return Rig
