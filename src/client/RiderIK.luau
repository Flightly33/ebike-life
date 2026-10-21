--[[
	RiderIK: the maths of the rider pose, kept free of services so tests can run it.

	Joints follow Roblox's formula Part1 = Part0 * C0 * Transform * C1^-1 (Motor6D and
	AnimationConstraint alike).
]]

local Rig = require(script.Parent.Rig)

local RiderIK = {}

local function basis(x: Vector3, y: Vector3): CFrame
	local e1 = x.Unit
	local yy = y - e1 * y:Dot(e1)
	if yy.Magnitude < 1e-4 then
		yy = if math.abs(e1.Y) < 0.9 then Vector3.yAxis - e1 * e1.Y else Vector3.xAxis - e1 * e1.X
	end
	local e2 = yy.Unit
	return CFrame.fromMatrix(Vector3.zero, e1, e2, e1:Cross(e2))
end

-- Two-bone IK: the limb from `parent * j1.C0` reaching for `target`, bending toward `pole` (world).
-- `restBend` is the direction (in each bone's own space) its middle joint bends toward. Writes the
-- three joints; returns the world frame of the last bone.
function RiderIK.Limb(parent: CFrame, j1: Rig.Joint, j2: Rig.Joint, j3: Rig.Joint, target: Vector3, pole: Vector3, restBend: Vector3, endRotation: CFrame?)
	local pivot = (parent * j1.C0).Position
	local upperAxis = j2.C0.Position - j1.C1.Position
	local lowerAxis = j3.C0.Position - j2.C1.Position
	local a, b = upperAxis.Magnitude, lowerAxis.Magnitude
	local toTarget = target - pivot
	local u = if toTarget.Magnitude > 1e-4 then toTarget.Unit else -Vector3.yAxis
	local dist = math.clamp(toTarget.Magnitude, math.abs(a - b) + 0.05, a + b - 0.01)
	local w = pole - u * pole:Dot(u)
	w = if w.Magnitude > 1e-4 then w.Unit else basis(u, Vector3.yAxis).UpVector
	local cosA = math.clamp((a * a + dist * dist - b * b) / (2 * a * dist), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local middle = pivot + (u * cosA + w * sinA) * a
	local finish = pivot + u * dist
	local d1 = (middle - pivot).Unit
	local d2 = (finish - middle).Unit

	local upperRot = basis(d1, w) * basis(upperAxis, restBend):Inverse()
	local upper = CFrame.new(pivot) * upperRot * CFrame.new(-j1.C1.Position)
	Rig.Set(j1, (parent * j1.C0):Inverse() * upper * j1.C1)

	local lowerRot = basis(d2, w) * basis(lowerAxis, restBend):Inverse()
	local joint2 = upper * j2.C0
	local lower = CFrame.new(joint2.Position) * lowerRot * CFrame.new(-j2.C1.Position)
	Rig.Set(j2, joint2:Inverse() * lower * j2.C1)

	local joint3 = lower * j3.C0
	if endRotation then
		local last = CFrame.new(joint3.Position) * endRotation * CFrame.new(-j3.C1.Position)
		Rig.Set(j3, joint3:Inverse() * last * j3.C1)
	else
		Rig.Set(j3, CFrame.identity)
	end
end

-- Torso FK from the HumanoidRootPart's frame for a forward pitch (+ leans forward) and a roll: the
-- LowerTorso and UpperTorso frames and the two joints' Transforms (not written)
function RiderIK.Torso(rig: Rig.RigInfo, hrp: CFrame, pitch: number, roll: number): (CFrame, CFrame, CFrame, CFrame)
	local J = rig.Joints
	local rootT = Rig.ToTransform(J.Root, CFrame.Angles(-pitch * 0.35, 0, roll))
	local waistT = Rig.ToTransform(J.Waist, CFrame.Angles(-pitch * 0.65, 0, 0))
	local lower = hrp * J.Root.C0 * rootT * J.Root.C1:Inverse()
	local upper = lower * J.Waist.C0 * waistT * J.Waist.C1:Inverse()
	return lower, upper, rootT, waistT
end

return RiderIK
