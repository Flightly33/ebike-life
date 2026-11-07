--[[
	Route: where the rider is heading and the road route there, for the minimap, the full map and
	the beacon in the world. The target is the current objective's (ObjectiveService's ObjTarget),
	else the start line of a race lobby they're in (UI/Objective sets LobbyStart), else a waypoint
	they set by tapping the full map. The route follows the road graph (Layout.Path) from the crossing
	nearest the rider to the one nearest the target, worked out again whenever either changes.
	A waypoint clears once the rider gets there.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.City.Layout)

local Route = {}

Route.Waypoint = nil :: Vector3?
Route.LobbyStart = nil :: Vector3?
Route.Version = 0 -- goes up whenever the route's points change
Route.ARRIVE = 45 -- studs: a waypoint this close is reached

local points: { Vector3 } = {}
local lastFrom, lastTo = 0, 0
local lastTarget: Vector3? = nil
local onArrive: (() -> ())? = nil

local function riderPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- The target and what it is: "Objective", "Race" (a lobby's start line), "Waypoint", or nil
function Route.Target(): (Vector3?, string)
	local player = Players.LocalPlayer
	local at = player:GetAttribute("ObjTarget")
	if typeof(at) == "Vector3" then
		return at, "Objective"
	end
	local start = Route.LobbyStart
	if start and player:GetAttribute("RaceLobby") ~= nil then
		return start, "Race"
	end
	local waypoint = Route.Waypoint
	if waypoint then
		return waypoint, "Waypoint"
	end
	return nil, ""
end

function Route.SetWaypoint(at: Vector3?)
	Route.Waypoint = at
	lastTarget = nil
	Route.Update()
end

-- Called when a waypoint is reached (UI shows a toast)
function Route.OnArrive(callback: () -> ())
	onArrive = callback
end

function Route.Points(): { Vector3 }
	return points
end

function Route.Update()
	local target, kind = Route.Target()
	local position = riderPosition()
	if not target or not position then
		if #points > 0 then
			points = {}
			lastTarget = nil
			Route.Version += 1
		end
		return
	end
	local goal = target :: Vector3
	local here = position :: Vector3
	if kind == "Waypoint" and Vector3.new(here.X - goal.X, 0, here.Z - goal.Z).Magnitude < Route.ARRIVE then
		Route.Waypoint = nil
		points = {}
		lastTarget = nil
		Route.Version += 1
		local cb = onArrive
		if cb then
			cb()
		end
		return
	end
	local from, to = Layout.NearestNode(here), Layout.NearestNode(goal)
	if from == lastFrom and to == lastTo and lastTarget == goal then
		return
	end
	lastFrom, lastTo, lastTarget = from, to, goal
	local fresh: { Vector3 } = {}
	for _, node in Layout.Path(from, to) do
		table.insert(fresh, Layout.Nodes[node].Position)
	end
	table.insert(fresh, goal)
	points = fresh
	Route.Version += 1
end

function Route.Init()
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= 0.5 then
			since = 0
			Route.Update()
		end
	end)
end

return Route
