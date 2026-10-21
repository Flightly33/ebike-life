--[[
	Ragdoll: the local rider goes limp and tumbles off the bike on a bail, then gets back up.

	Works on both kinds of R15 rig: Motor6D joints (classic) and AnimationConstraint joints (current
	avatars). Each joint gets a BallSocketConstraint with sensible twist limits and the original
	joint is switched off; Stop() switches them back on. Limbs collide while limp so the body lands
	on the ground instead of falling through it (riding turns character collisions off).

	The body inherits part of the bike's velocity plus a small hop, capped, so a bail looks like a
	fall, not a launch.
]]

local Players = game:GetService("Players")

local Ragdoll = {}

Ragdoll.Active = false

local MAX_SPEED = 42 -- studs/s: a tumble, not a fling
local INHERIT = 0.55 -- of the bike's velocity

type Saved = {
	Sockets: { Instance },
	Joints: { [Instance]: boolean }, -- joint -> its Enabled before
	Collide: { [BasePart]: boolean },
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
	local state: Saved = { Sockets = {}, Joints = {}, Collide = {} }
	saved = state
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 and d.Name ~= "Root" then
			local a0 = Instance.new("Attachment")
			a0.Name = "EB_RagA0"
			a0.CFrame = d.C0
			a0.Parent = d.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "EB_RagA1"
			a1.CFrame = d.C1
			a1.Parent = d.Part1
			table.insert(state.Sockets, a0)
			table.insert(state.Sockets, a1)
			table.insert(state.Sockets, socket(d.Name, a0, a1, d.Part1))
			state.Joints[d] = d.Enabled
			d.Enabled = false
		elseif d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			local p1 = a1 and a1.Parent
			if a0 and a1 and p1 and p1.Name ~= "HumanoidRootPart" and a0.Parent and a0.Parent.Name ~= "HumanoidRootPart" then
				table.insert(state.Sockets, socket(d.Name, a0, a1, p1))
				state.Joints[d] = d.Enabled
				d.Enabled = false
			end
		elseif d:IsA("BasePart") then
			state.Collide[d] = d.CanCollide
			d.CanCollide = d.Name ~= "HumanoidRootPart"
		end
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	local v = velocity * INHERIT + Vector3.new(0, 9, 0)
	if v.Magnitude > MAX_SPEED then
		v = v.Unit * MAX_SPEED
	end
	for part in state.Collide do
		part.AssemblyLinearVelocity = v
		part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 3
	end
end

function Ragdoll.Stop(character: Model?)
	local state = saved
	if not Ragdoll.Active or not state then
		return
	end
	Ragdoll.Active = false
	saved = nil
	for _, inst in state.Sockets do
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
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart"))
	return if torso and torso:IsA("BasePart") then torso.Position else nil
end

return Ragdoll
