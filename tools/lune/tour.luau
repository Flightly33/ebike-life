--[[
	A tour of the city in the simulator, for the bug sweep and the performance pass: boots the game
	(server and client), then takes the player to every named place and a stop in each district,
	by day and by night in turn, a few seconds each with the client's systems running (street and
	home detail, pedestrians, shops, billboards, lights, the radio). Reports any runtime error
	(exits 1 on one), what the client built round each stop, and how much frame time each
	per-frame handler took (tools/sim/Signal.Profile), worst first. The simulator's instances are
	slower than Roblox's, so the times are for comparing systems, not a frame rate.

	rojo sourcemap default.project.json -o sourcemap.json && lune run tools/lune/tour.luau [seconds]
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local World = require("../sim/World")
local Sim = require("../sim/Instance")
local Signal = require("../sim/Signal")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local stay = tonumber(process.args[1]) or 3
local root = process.cwd
if string.sub(root, -1) ~= "/" then
	root ..= "/"
end
local world = World.new(root)
local RS = world.Services.ReplicatedStorage
local SSS = world.Services.ServerScriptService
local WS = world.Services.Workspace

print("== booting server")
local server = world:Context("server", true, nil)
server.Run(SSS:WaitForChild("Server"))
world:Run(3)
local Shared = RS:WaitForChild("Shared")
local Layout = server.Require(Shared:WaitForChild("City"):WaitForChild("Layout"))
local DayNight = server.Require(Shared:WaitForChild("DayNight"))
local Config = server.Require(Shared:WaitForChild("Config"))

print("== booting client")
local player = world:AddPlayer("Tourist", 1, true)
local rig = world:BuildRig()
Sim.States[rig].Name = "Tourist"
rig:FindFirstChildOfClass("Humanoid").RigType = roblox.Enum.HumanoidRigType.R15
rig:PivotTo(CFrame.new(Layout.Places.Spawn + Vector3.new(0, 3, 0)))
rig.Parent = WS
player.Character = rig
local client = world:Context("client", false, player)
local Client = world.Services.StarterPlayer.StarterPlayerScripts:WaitForChild("Client")
client.Run(Client)
world:Run(4)
client.Require(Client:WaitForChild("UI"):WaitForChild("GraphicsPrompt")).Choose("Ultra")
world:Run(1)
local bootErrors = #world.Errors

-- the stops: every named place, and the middle of a block in each district
type Stop = { Name: string, At: any }
local stops: { Stop } = {}
for name, at in Layout.Places do
	table.insert(stops, { Name = name, At = at })
end
for _, district in { "Suburb", "Midtown", "Brickell", "Edgewater", "ArtDeco", "Mansion", "Grove", "KeyHomes", "Havana", "FastFood", "Gables", "Condo" } do
	local block = Layout.FindDistrict(district)
	if block then
		table.insert(stops, { Name = "~" .. district, At = Vector3.new((block.MinX + block.MaxX) / 2, Layout.CURB_Y, (block.MinZ + block.MaxZ) / 2) })
	end
end
table.sort(stops, function(a, b)
	return a.Name < b.Name
end)

-- the clock to a given hour (ReplicatedStorage's ClockOffset, as the admin time command sets it)
local function setHour(hour: number)
	local cfg = Config.DayNight
	local base = (WS:GetServerTimeNow() / cfg.DaySeconds + cfg.StartFraction) % 1
	RS:SetAttribute("ClockOffset", (DayNight.FractionAt(hour) - base) % 1)
end

local function parts(folderName: string): number
	local f = WS:FindFirstChild(folderName)
	if not f then
		return 0
	end
	local n = 0
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

print(string.format("== touring %d stops, %g s each", #stops, stay))
Signal.Profile = {}
local frames = 0
local worst = { Name = "", Detail = 0 }
for i, stop in stops do
	local night = i % 2 == 0
	setHour(if night then 22 else 13)
	rig:PivotTo(CFrame.new(stop.At + Vector3.new(0, 4, 0)))
	local before = #world.Errors
	local t0 = os.clock()
	world:Run(stay)
	frames += math.floor(stay * 60 + 0.5)
	local detail = parts("CityDetail")
	if detail > worst.Detail then
		worst = { Name = stop.Name, Detail = detail }
	end
	print(string.format("%-16s %s  detail %5d  people %4d  shops %4d  %5.1f s  %s", stop.Name, if night then "night" else "day  ", detail, parts("Ambient"), parts("ShopFit"), os.clock() - t0, if #world.Errors > before then "ERROR" else ""))
end

-- the frame-event handlers, by time per frame
type Row = { Key: string, Ms: number, Calls: number }
local rows: { Row } = {}
local total = 0
for key, entry in Signal.Profile :: any do
	local ms = entry.Time / frames * 1000
	total += ms
	table.insert(rows, { Key = key, Ms = ms, Calls = entry.Calls })
end
table.sort(rows, function(a, b)
	return a.Ms > b.Ms
end)
print(string.format("== per-frame handlers (%d frames, %.2f ms a frame in all; the simulator's instances are slow, compare, don't read as a frame rate)", frames, total))
for i = 1, math.min(30, #rows) do
	local r = rows[i]
	local short = string.gsub(r.Key, "^.-/src/", "")
	print(string.format("%7.3f ms  %s", r.Ms, short))
end
print(string.format("== most client detail at one stop: %s (%d parts)", worst.Name, worst.Detail))

-- the errors, once each
local seen: { [string]: boolean } = {}
local errors = 0
for i, err in world.Errors do
	local head = string.match(err, "^[^\n]*") or err
	if not seen[head] then
		seen[head] = true
		errors += 1
		print(string.format("[error]%s %s", if i <= bootErrors then " (boot)" else "", err))
	end
end
for _, w in world.Warnings do
	if not seen[w] then
		seen[w] = true
		print("[warn] " .. w)
	end
end
print(if errors == 0 then "tour passed" else string.format("tour: %d error(s)", errors))
process.exit(if errors == 0 then 0 else 1)
