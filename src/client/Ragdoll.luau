--[[
	Ragdoll: the local rider goes limp and tumbles off the bike on a bail, then gets back up.

	Works on both kinds of R15 rig: Motor6D joints (classic) and AnimationConstraint joints (current
	avatars). Each joint gets a BallSocketConstraint with sensible twist limits and the original
	joint is switched off; Stop() switches them back on.

	Plain physics: the body leaves the bike with exactly the bike's velocity and nothing added. What
	makes Roblox ragdolls explode is parts that overlap pushing each other apart, so only the body
	parts themselves collide (never hats, hair or layered clothing), and the two parts of every joint
	ignore each other.
]]

local Players = game:GetService("Players")

local Ragdoll = {}

Ragdoll.Active = false

type Saved = {
	Made: { Instance },
	Joints: { [Instance]: boolean }, -- joint -> its Enabled before
	Collide: { [BasePart]: boolean },
	IK: { [IKControl]: boolean },
}

local saved: Saved? = nil

local function socket(name: string, a0: Attachment, a1: Attachment, parent: Instance): BallSocketConstraint
	local s = Instance.new("BallSocketConstraint")
	s.Name = "EB_Rag_" .. name
	s.Attachment0 = a0
	s.Attachment1 = a1
	s.LimitsEnabled = true
	s.TwistLimitsEnabled = true
	s.UpperAngle = if string.find(name, "Neck") then 35 else 60
	s.TwistLowerAngle = -35
	s.TwistUpperAngle = 35
	s.Parent = parent
	return s
end

local function noCollide(a: BasePart, b: BasePart, parent: Instance): NoCollisionConstraint
	local n = Instance.new("NoCollisionConstraint")
	n.Name = "EB_RagNC"
	n.Part0 = a
	n.Part1 = b
	n.Parent = parent
	return n
end

-- A body part (a limb, the torso, the head): straight inside the character, not an accessory
local function isBody(part: BasePart, character: Model): boolean
	return part.Parent == character and part.Name ~= "HumanoidRootPart"
end

function Ragdoll.Start(character: Model, velocity: Vector3)
	if Ragdoll.Active then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or not hrp:IsA("BasePart") then
		return
	end
	Ragdoll.Active = true
	local state: Saved = { Made = {}, Joints = {}, Collide = {}, IK = {} }
	saved = state

	-- off the seat right now (the server removes the weld too, a moment later)
	for _, d in hrp:GetJoints() do
		if d.Name == "SeatWeld" then
			d:Destroy()
		end
	end
	humanoid.Sit = false

	local function join(name: string, a0: Attachment, a1: Attachment, part0: BasePart, part1: BasePart)
		table.insert(state.Made, socket(name, a0, a1, part1))
		table.insert(state.Made, noCollide(part0, part1, part1))
	end
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			local part0, part1 = d.Part0, d.Part1
			if part0 and part1 and d.Name ~= "Root" and isBody(part0, character) and isBody(part1, character) then
				local a0 = Instance.new("Attachment")
				a0.Name = "EB_RagA0"
				a0.CFrame = d.C0
				a0.Parent = part0
				local a1 = Instance.new("Attachment")
				a1.Name = "EB_RagA1"
				a1.CFrame = d.C1
				a1.Parent = part1
				table.insert(state.Made, a0)
				table.insert(state.Made, a1)
				join(d.Name, a0, a1, part0, part1)
				state.Joints[d] = d.Enabled
				d.Enabled = false
			end
		elseif d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			local part0 = a0 and a0.Parent
			local part1 = a1 and a1.Parent
			if a0 and a1 and part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart") and isBody(part0, character) and isBody(part1, character) then
				join(d.Name, a0, a1, part0, part1)
				state.Joints[d] = d.Enabled
				d.Enabled = false
			end
		elseif d:IsA("IKControl") then
			state.IK[d] = d.Enabled
			d.Enabled = false
		end
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			state.Collide[d] = d.CanCollide
			d.CanCollide = isBody(d, character)
		end
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	-- carry on exactly as fast as the bike was going
	for part in state.Collide do
		part.AssemblyLinearVelocity = velocity
		part.AssemblyAngularVelocity = Vector3.zero
	end
end

function Ragdoll.Stop(character: Model?)
	local state = saved
	if not Ragdoll.Active or not state then
		return
	end
	Ragdoll.Active = false
	saved = nil
	for _, inst in state.Made do
		inst:Destroy()
	end
	for joint, enabled in state.Joints do
		if joint.Parent then
			(joint :: any).Enabled = enabled
		end
	end
	for part, collide in state.Collide do
		if part.Parent then
			part.CanCollide = collide
		end
	end
	for ik, enabled in state.IK do
		if ik.Parent then
			ik.Enabled = enabled
		end
	end
	local c = character or Players.LocalPlayer.Character
	local humanoid = c and c:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- Where the body is (for the camera while limp)
function Ragdoll.Focus(): Vector3?
	if not Ragdoll.Active then
		return nil
	end
	local character = Players.LocalPlayer.Character
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart"))
	return if torso and torso:IsA("BasePart") then torso.Position else nil
end

return Ragdoll
