--[[
	BikeService: takes bikes out of the garage (My Rides -> Spawn), puts riders on them and hands the
	rider's client control of the physics.

	A spawned bike sits next to its owner with an "Enter" prompt (only the owner can use it), parked
	and anchored. Sitting on it unanchors it and makes the rider its network owner; the client's
	BikeController then drives it (Shared/BikePhysics) and reports what the rider is doing through
	the BikeState remote. The server copies the bits other players need to see (steering, pedalling,
	hands, crashes) onto the bike's attributes, and keeps its own clock on wheelies so the payout
	can't be inflated.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bikes = require(Shared.Bikes)
local BikeStats = require(Shared.BikeStats)
local Config = require(Shared.Config)
local Modes = require(Shared.Modes)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Upgrades = require(Shared.Upgrades)
local BikeModel = require(Shared.Models.BikeModel)

local DataService = require(script.Parent.DataService)
local RiderLook = require(script.Parent.RiderLook)

local BikeService = {}

local BAIL_GRACE = 9 -- seconds a bailed rider has to get back on

export type ClientState = {
	Wheelie: boolean,
	WheelieTime: number,
	Hands: number,
	Mode: string,
	Battery: number, -- 0..1
	Steer: number,
	Cadence: number,
	Power: number, -- 0..1 of the motor's peak
	Air: boolean,
	Surface: string,
	Crash: boolean,
	Kmh: number,
	Drift: boolean,
	Slip: number,
	Trick: string,
	Barspin: boolean,
	Stoppie: boolean,
}

export type Ride = {
	Player: Player,
	Bike: Bikes.Bike,
	Spec: BikeStats.Spec,
	Model: Model,
	Root: BasePart,
	Seat: Seat,
	Prompt: ProximityPrompt,
	Riding: boolean,
	State: ClientState,
	StateAt: number,
	WheelieSince: number?,
	DriftSince: number?,
	BailedAt: number?,
	AirSince: number?, -- the client's been airborne since (server clock)
	LastAirAt: number?, -- the rider fell off and is getting back on
	ParkedAt: number,
	Connections: { RBXScriptConnection },
}

local rides: { [Player]: Ride } = {}
local lastSpawn: { [Player]: number } = {}
local folder: Folder

BikeService.RideChanged = Signal.new() -- (player, riding: boolean)
BikeService.Despawned = Signal.new() -- (player)

local function idleState(battery: number): ClientState
	return {
		Wheelie = false,
		WheelieTime = 0,
		Hands = 0,
		Mode = "TOUR",
		Battery = battery,
		Steer = 0,
		Cadence = 0,
		Power = 0,
		Air = false,
		Surface = "Road",
		Crash = false,
		Kmh = 0,
		Drift = false,
		Slip = 0,
		Trick = "",
		Barspin = false,
		Stoppie = false,
	}
end

function BikeService.Get(player: Player): Ride?
	return rides[player]
end

function BikeService.Rides(): { [Player]: Ride }
	return rides
end

function BikeService.IsRiding(player: Player): boolean
	local ride = rides[player]
	return ride ~= nil and ride.Riding
end

-- Wheelie seconds the server believes (the client's figure, capped by the server's own clock)
function BikeService.WheelieTime(ride: Ride): number
	if not ride.State.Wheelie or not ride.WheelieSince then
		return 0
	end
	return math.min(ride.State.WheelieTime, os.clock() - ride.WheelieSince + 0.6)
end

-- Speed the server sees (from the replicated physics), clamped to what the bike can do
function BikeService.Kmh(ride: Ride): number
	local v = ride.Root.AssemblyLinearVelocity
	local kmh = Vector3.new(v.X, 0, v.Z).Magnitude * Config.KMH_PER_STUD_PER_SECOND
	return math.min(kmh, ride.Spec.CutoffKmh * 1.15 + 15)
end

local function groundBelow(position: Vector3, exclude: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(position + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), params)
	if hit then
		return hit.Position
	end
	return Vector3.new(position.X, 0.7, position.Z)
end

-- A character's leg length in studs, hip joint to ankle joint (a default R15 avatar: ~1.76)
local function legLength(character: Model): number
	local function joint(partName: string, attachmentName: string): Vector3?
		local part = character:FindFirstChild(partName)
		local a = part and part:FindFirstChild(attachmentName)
		return if a and a:IsA("Attachment") then a.WorldPosition else nil
	end
	local hip = joint("LowerTorso", "LeftHipRigAttachment")
	local knee = joint("LeftUpperLeg", "LeftKneeRigAttachment")
	local ankle = joint("LeftLowerLeg", "LeftAnkleRigAttachment")
	if hip and knee and ankle then
		-- along the bones, so a bent knee doesn't shorten it
		return math.clamp((knee - hip).Magnitude + (ankle - knee).Magnitude, 0.8, 6)
	end
	local leg = character:FindFirstChild("Left Leg") -- R6
	if leg and leg:IsA("BasePart") then
		return math.clamp(leg.Size.Y * 0.88, 0.8, 6)
	end
	return 1.76
end

-- Parks the bike: stood upright on the ground under it, or (`asItLies`, after a crash) left just as
-- it came to rest, on its side or upside down; it's stood up when its rider gets back on
local function park(ride: Ride, asItLies: boolean?)
	local root = ride.Root
	if asItLies then
		root.Anchored = true
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		return
	end
	local cf = root.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	local exclude: { Instance } = { folder }
	local character = ride.Player.Character
	if character then
		table.insert(exclude, character)
	end
	local ground = groundBelow(cf.Position, exclude)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	ride.Model:PivotTo(CFrame.lookAt(ground, ground + look.Unit))
end

local function setAttribute(model: Model, name: string, value: any)
	if model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

local function mount(ride: Ride)
	if ride.Riding then
		return
	end
	ride.Riding = true
	ride.Prompt.Enabled = false
	ride.Root.Anchored = false
	pcall(function()
		ride.Root:SetNetworkOwner(ride.Player)
	end)
	ride.Model:SetAttribute("Rider", ride.Player.UserId)
	ride.Player:SetAttribute("Riding", true)
	local character = ride.Player.Character
	if character then
		RiderLook.Apply(character, ride.Bike.Effects)
	end
	ride.State = idleState(ride.State.Battery)
	ride.WheelieSince = nil
	BikeService.RideChanged:Fire(ride.Player, true)
end

local function dismount(ride: Ride, asItLies: boolean?)
	if not ride.Riding then
		return
	end
	ride.Riding = false
	ride.ParkedAt = os.clock()
	ride.WheelieSince = nil
	ride.State.Wheelie = false
	ride.Model:SetAttribute("Rider", nil)
	ride.Model:SetAttribute("Steer", 0)
	ride.Model:SetAttribute("Cadence", 0)
	ride.Model:SetAttribute("Hands", 0)
	ride.Model:SetAttribute("Crash", false)
	ride.Player:SetAttribute("Riding", false)
	local character = ride.Player.Character
	if character then
		RiderLook.Clear(character)
	end
	park(ride, asItLies)
	if ride.Model.Parent then
		ride.Prompt.Enabled = true
	end
	BikeService.RideChanged:Fire(ride.Player, false)
end

function BikeService.Despawn(player: Player)
	local ride = rides[player]
	if not ride then
		return
	end
	rides[player] = nil
	if ride.Riding then
		ride.Riding = false
		player:SetAttribute("Riding", false)
		BikeService.RideChanged:Fire(player, false)
	end
	for _, c in ride.Connections do
		c:Disconnect()
	end
	-- Get the rider off before the bike goes
	local weld = ride.Seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	ride.Model:Destroy()
	player:SetAttribute("BikeId", "")
	BikeService.Despawned:Fire(player)
end

function BikeService.Spawn(player: Player, bikeId: string): (boolean, string)
	local data = DataService.Get(player)
	local bike = Bikes.Get(bikeId)
	if not data or not bike then
		return false, "Unknown bike"
	end
	if not data.Owned[bikeId] then
		return false, "Buy it at " .. Config.DEALERSHIP .. " first"
	end
	local now = os.clock()
	if lastSpawn[player] and now - lastSpawn[player] < 2 then
		return false, "Slow down!"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false, "Respawn first"
	end
	lastSpawn[player] = now
	BikeService.Despawn(player)

	-- fitted once CharacterService has scaled the character to the standard height (BodyHeight)
	if Config.Avatar.Height > 0 and character:GetAttribute("BodyHeight") == nil then
		local ok, loaded = pcall(function()
			return player:HasAppearanceLoaded()
		end)
		if ok then
			local since = os.clock()
			while character.Parent and character:GetAttribute("BodyHeight") == nil and os.clock() - since < (if loaded then 1.5 else 4) do
				task.wait(0.1)
			end
		end
	end

	-- drawn to fit this rider: their legs, hip joint to ankle joint, as they stand
	local size = BikeModel.FitScale(bike, legLength(character))
	local levels = Profile.Levels(data, bikeId)
	local spec = BikeStats.Scaled(BikeStats.Compute(bike, levels), size)
	local model = BikeModel.Build(bike, data.Paint[bikeId], { Scale = size })
	model.Name = "Bike_" .. player.UserId
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("BikeId", bikeId)
	for _, slot in Upgrades.Slots do
		model:SetAttribute("Up_" .. slot.Name, Upgrades.Level(levels, slot.Name))
	end
	local bikeRoot = model.PrimaryPart :: BasePart
	local seat = model:FindFirstChildOfClass("Seat") :: Seat

	-- Beside the player, facing the way they face
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	local spot = root.Position + look * 5 + right * 3
	local ground = groundBelow(spot, { character, folder })
	model:PivotTo(CFrame.lookAt(ground, ground + look))

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Enter"
	prompt.ObjectText = Bikes.FullName(bike)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = bikeRoot

	model.Parent = folder

	local ride: Ride = {
		Player = player,
		Bike = bike,
		Spec = spec,
		Model = model,
		Root = bikeRoot,
		Seat = seat,
		Prompt = prompt,
		Riding = false,
		State = idleState(1),
		StateAt = 0,
		WheelieSince = nil,
		DriftSince = nil,
		BailedAt = nil,
		AirSince = nil,
		LastAirAt = nil,
		ParkedAt = os.clock(),
		Connections = {},
	}
	rides[player] = ride
	player:SetAttribute("BikeId", bikeId)
	data.Equipped = bikeId
	DataService.Changed(player)

	table.insert(ride.Connections, prompt.Triggered:Connect(function(who: Player)
		if who ~= player then
			return
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not hum.SeatPart then
			-- pick the bike up first if it's lying where it crashed
			if ride.Root.CFrame.UpVector.Y < 0.95 then
				park(ride)
			end
			seat:Sit(hum)
		end
	end))
	table.insert(ride.Connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant then
			local owner = Players:GetPlayerFromCharacter(occupant.Parent)
			if owner ~= player then
				-- Not yours: off you get
				local weld = seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
				return
			end
			ride.BailedAt = nil
			mount(ride)
		elseif ride.BailedAt and os.clock() - ride.BailedAt < BAIL_GRACE then
			-- fell off: the ride stays theirs while they ragdoll and climb back on
		else
			dismount(ride)
		end
	end))
	return true, "Spawned " .. Bikes.FullName(bike)
end

-- Tuning changed while the bike is out: new numbers for the server and (via attributes) the rider
function BikeService.Refresh(player: Player)
	local ride = rides[player]
	local data = DataService.Get(player)
	if not ride or not data then
		return
	end
	local levels = Profile.Levels(data, ride.Bike.Id)
	ride.Spec = BikeStats.Scaled(BikeStats.Compute(ride.Bike, levels), ride.Spec.Scale)
	for _, slot in Upgrades.Slots do
		ride.Model:SetAttribute("Up_" .. slot.Name, Upgrades.Level(levels, slot.Name))
	end
	BikeModel.ApplyPaint(ride.Model, ride.Bike, data.Paint[ride.Bike.Id])
end

-- The bike's root moved by the server (teleports, busts): tell the rider's controller
function BikeService.Teleport(player: Player, target: CFrame)
	local ride = rides[player]
	if ride and ride.Riding then
		Remotes.Event("Teleport"):FireClient(player, target)
	end
end

-- A charging station was used: top the battery up if the player's bike is close
function BikeService.Charge(player: Player, position: Vector3, range: number?): boolean
	local ride = rides[player]
	if not ride then
		return false
	end
	if (ride.Root.Position - position).Magnitude > (range or 45) then
		return false
	end
	ride.State.Battery = 1
	Remotes.Event("Charge"):FireClient(player, 1)
	return true
end

-- The rider fell off: take them out of the seat but keep the ride (bike, battery, ownership)
local function bail(player: Player)
	local ride = rides[player]
	if not ride or not ride.Riding or ride.BailedAt then
		return
	end
	ride.BailedAt = os.clock()
	local weld = ride.Seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	task.delay(BAIL_GRACE, function()
		if ride.BailedAt and rides[player] == ride and not ride.Seat.Occupant then
			ride.BailedAt = nil
			dismount(ride, true)
		end
	end)
end

-- Up after the ragdoll: the bike parks where it slid to, for the rider to walk back and get on
local function gotUp(player: Player)
	local ride = rides[player]
	if not ride or not ride.BailedAt then
		return
	end
	ride.BailedAt = nil
	dismount(ride, true)
end

function BikeService.Bailed(player: Player): boolean
	local ride = rides[player]
	return ride ~= nil and ride.BailedAt ~= nil
end

local function readState(raw: any): ClientState?
	if type(raw) ~= "table" then
		return nil
	end
	local function n(value: any, min: number, max: number): number
		local x = tonumber(value)
		if x == nil or x ~= x then
			return min
		end
		return math.clamp(x, min, max)
	end
	return {
		Wheelie = raw.W == true,
		WheelieTime = n(raw.Wt, 0, 600),
		Hands = math.floor(n(raw.H, 0, 2)),
		Mode = if Modes.IsMode(raw.M) then raw.M else "TOUR",
		Battery = n(raw.B, 0, 1),
		Steer = n(raw.S, -1, 1),
		Cadence = n(raw.C, 0, 130),
		Power = n(raw.P, 0, 1),
		Air = raw.A == true,
		Surface = if type(raw.Sf) == "string" and #raw.Sf < 16 then raw.Sf else "Road",
		Crash = raw.Cr == true,
		Kmh = n(raw.K, 0, 200),
		Drift = raw.D == true,
		Trick = if type(raw.Tr) == "string" and #raw.Tr < 16 then raw.Tr else "",
		Barspin = raw.Bs == true,
		Stoppie = raw.St == true,
		Slip = n(raw.Sl, -1.6, 1.6),
	}
end

function BikeService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Bikes"
	folder.Parent = Workspace

	Remotes.Event("SpawnBike").OnServerEvent:Connect(function(player: Player, bikeId: any)
		if type(bikeId) ~= "string" then
			return
		end
		local ok, message = BikeService.Spawn(player, bikeId)
		Remotes.Event("Notify"):FireClient(player, if ok then "Info" else "Error", message)
	end)
	Remotes.Event("DespawnBike").OnServerEvent:Connect(function(player: Player)
		BikeService.Despawn(player)
	end)
	Remotes.Event("Bail").OnServerEvent:Connect(bail)
	Remotes.Event("GotUp").OnServerEvent:Connect(gotUp)
	Remotes.Unreliable("BikeState").OnServerEvent:Connect(function(player: Player, raw: any)
		local ride = rides[player]
		if not ride or not ride.Riding then
			return
		end
		local now = os.clock()
		if now - ride.StateAt < 0.04 then
			return -- more than 25 a second: ignore the extras
		end
		local state = readState(raw)
		if not state then
			return
		end
		ride.StateAt = now
		if state.Wheelie and not ride.WheelieSince then
			ride.WheelieSince = now
		elseif not state.Wheelie then
			ride.WheelieSince = nil
		end
		ride.State = state
		local model = ride.Model
		setAttribute(model, "Steer", math.floor(state.Steer * 20 + 0.5) / 20)
		setAttribute(model, "Cadence", math.floor(state.Cadence / 5 + 0.5) * 5)
		setAttribute(model, "Hands", state.Hands)
		setAttribute(model, "Crash", state.Crash)
		setAttribute(model, "Power", math.floor(state.Power * 10 + 0.5) / 10)
		setAttribute(model, "Wheelie", state.Wheelie)
		setAttribute(model, "Trick", state.Trick)
		setAttribute(model, "Barspin", state.Barspin)
		setAttribute(model, "Stoppie", state.Stoppie)
		if state.Air then
			ride.AirSince = ride.AirSince or now
			ride.LastAirAt = now
		else
			ride.AirSince = nil
		end
		setAttribute(model, "Drift", if state.Drift then math.floor(state.Slip * 10 + 0.5) / 10 else 0)
		if state.Drift and not ride.DriftSince then
			ride.DriftSince = now
		elseif not state.Drift then
			ride.DriftSince = nil
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		BikeService.Despawn(player)
		lastSpawn[player] = nil
	end)
	-- Bikes left behind go back to the garage
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for player, ride in rides do
				if not ride.Riding then
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					local far = root == nil or not root:IsA("BasePart") or (root.Position - ride.Root.Position).Magnitude > Config.Bikes.DespawnDistance
					if far or now - ride.ParkedAt > Config.Bikes.IdleDespawn then
						BikeService.Despawn(player)
					end
				elseif ride.Root.Position.Y < -200 then
					-- fell out of the world
					BikeService.Despawn(player)
				end
			end
		end
	end)
end

return BikeService
