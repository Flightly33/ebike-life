# E-Bike Life: project memory

A Roblox open-world e-bike game: ride Flightly e-bikes around a city, earn money while riding (more for
wheelies, air time and tricks), and get chased by police for wheelies and stunts near cops. Bikes are
bought at the Flighty Mechanics dealership. It's a Rojo project in Luau, modelled on the owner's
reference videos (a Roblox e-scooter game): its HUD, menus, money loop and police chase.

## Working rules (from the owner)
- After every finished change, rebuild `EbikeLife.rbxl` (`rojo build default.project.json -o EbikeLife.rbxl`) and send the file to the user.
- Don't write README text.
- Develop and push on branch `claude/great-fermat-1koovo`. Don't open a PR unless asked.
- Push back when something isn't the best approach, and ask when an answer depends on details you don't have.
- Never invent Roblox asset or sound IDs. Sounds come from `AssetService:SearchAudioAsync` at runtime or from IDs the owner puts in `AssetIds`.
- Bikes are real e-bike types with real-world specs (motor power, battery Wh, assist class, weight, tyres).

## Open issues (not yet confirmed in Studio)
Everything below passes the simulator, but nothing has been played in Studio yet.
1. The bike is kinematic and client-owned: the client runs `BikePhysics.Step` every frame and writes the root CFrame and velocity (an anti-gravity VectorForce holds it up). Replication to other players, network ownership hand-off on mount, and the seat weld need checking.
2. Rider pose is procedural (`src/client/RiderPose.luau`, maths in `RiderIK.luau`, joints via `Rig.luau`): every client writes every rider's joint Transforms in `RunService.PreSimulation` (after Roblox's animation step), sets the SeatWeld locally so the hips sit on the seat, leans the torso until the hands reach the grips, and solves two-bone IK to `GripL/R` and `PedalL/R` / `PegL/R`. Pedalling leans in, wheelies pull back, tricks have full-body poses. The bike root has `RootPriority` 100 so its frame is what replicates. At `BIKE_SIZE` 1.8 a default avatar's legs (~2 studs) can't reach the pedals (seat to pedal 2.4-3.3 studs). Unverified in Studio.
3. Police and traffic cars are server-owned, unanchored, driven kinematically by `CarDriver` along the road graph. Check they don't jitter or sink.
4. Audio search needs "Allow HTTP / Studio API access" and may return nothing in an unpublished place; the game falls back to `rbxasset://` sounds.
5. DataStores need Studio API access; without it DataService runs from an in-memory profile.
6. Game pass IDs in `AssetIds.GamePasses` are 0 (passes disabled).
7. Bails ragdoll the rider on the client (`src/client/Ragdoll.luau`: BallSocketConstraints over Motor6D or AnimationConstraint joints, the bike's exact velocity, only body parts collide, NoCollisionConstraints across each joint, the SeatWeld cut locally), then the Remount remote puts them back; the server keeps the ride for `BAIL_GRACE`. Unverified in Studio.
8. On-foot officers (`src/server/Officer.luau`, part-built R6 rigs in `Workspace.Officers`) walk with `Humanoid:MoveTo`; check they path around cars and kerbs.
If any of these fail in Studio, ask the user for the Output window's errors and warnings.

## Layout
- `src/shared`: Config (all tuning: units, physics, wheelie, battery, economy, police, traffic, lights), Bikes (14 Flightly bikes, the last being the Deathrider (Cursed rarity, `Effects = "Hellfire"`: exhaust fire in BikeModel, burning skull rider via `src/server/RiderLook.luau`) with specs and prices), Modes (OFF/ECO/TOUR/SPORT/TURBO assist modes, owner-customisable), Upgrades, Paints (paints and crates), BikeStats (spec + upgrades -> physics stats), Economy (money per second, multiplier, trick payouts, XP), Heat (police offences and stars), BikePhysics (the ride model), Profile (save data), Shop, Remotes, AssetIds, AudioCatalog, PartKit (part builders), Models/ (BikeModel, CarModel), City/ (Layout: road grid, graph, places, chargers; Builder and the district builders; Detail: windows, shopfronts, fire escapes, roof clutter, street furniture, garden bits, trucks, wind turbines).
- `src/server`: DataService (DataStore, attributes Cash/Level/Xp), BikeService (spawn/park/mount, validates BikeState), EconomyService (pay loop, tricks, combos, levels), ShopService (dealership, upgrades, paints, crates, boosts, teleports, modes), PoliceService (sight, heat, dispatch, bust, escape; roles Lead/Flank/Intercept/Roadblock, PIT knocks the rider off via the Knocked remote, spike strips flatten tyres, officers deploy on foot and the bust meter fills only with an officer in `ArrestRange` of a helpless rider), Officer (on-foot police), RiderLook, TrafficService, CarDriver (car AI, `Hold` for roadblocks), CityService (builds the city if the baked map is missing, charger prompts), CharacterService, AudioService.
- `src/client`: BikeController (local ride, events -> Trick remote; bail/ragdoll/remount), Ragdoll, FX (drift smoke, skids, sparks, landing dust), BikeCamera, Input (keyboard, gamepad, touch), Visuals (wheels, cranks, motor/siren sound, police lights, traffic lights), RiderPose (procedural rider pose), RiderIK, Rig, World (ray/blockcast adapter), Sound, Music, State, UI/ (Hud, Speedometer, Minimap, TrickHud, WantedHud, Toasts, Rides (My Rides + dealership), Tuning, Store, MainMenu, TouchControls).
- `map/City.rbxm`: baked city (~60k parts; Workspace streaming is on, vehicles are Atomic models). `tools/lune/preview_scene.luau` renders street spots with an avatar-sized dummy, a bike and a car for scale checks.
- `map/City.rbxm`, rebaking: Rebake with `lune run tools/lune/bake_city.luau` after any change to City/ or the bike and car models (the dealership and police station hold static copies).
- `tools/preview`: offline three.js renders of the map and models (`node render.mjs`, Playwright Chromium).
- `blender/`: `build_vehicles.py` (with `meshkit.py`) models every bike and car in Blender and writes `blender/out/Vehicles.fbx` and `src/shared/Models/MeshManifest.luau`. Run `lune run tools/lune/export_vehicles.luau` first (rig points from BikeModel.Geometry, car dims), then `/root/tools/blendenv/bin/python blender/build_vehicles.py [--render all|id,id] [--only id,id]`. bpy 5.2 (pip, Python 3.13 venv at /root/tools/blendenv), Cycles on CPU. Meshes are split as `<Group>__<Slot>` (group = the joint it rides on, slot = colour/material, MeshKit.Slots).
- The owner imports Vehicles.fbx in Studio (File > Import 3D) into ReplicatedStorage as `VehicleMeshes`. MeshKit swaps those in for the part-built visuals (joints, seat, attachments, lamps, signs stay) and falls back to parts when they're missing or imported rotated. The rbxl built here does not contain them (they need uploading from Studio).
- Turning (`Config.Turning`) copies the owner's reference scooter game: above walking pace the bars set a turn rate (~85 degrees a second at 60 km/h), not tyre grip; the lean is half the physical lean, capped at 34 degrees. Surfaces steeper than `Physics.MaxRidePitch` launch you along them, and a quarter-pipe launch turns you round at the top (`Fakie`). Ramp faces (hit normal Y > 0.3) never count as walls.
- Tricks: air tricks (Z Superman, X Can-Can, T Nac-Nac, G Knee Knocker, N No-Footer; Y barspin), stoppie (brake+Shift), drift (R), loops (`LoopEntry` plates with `LoopRadius`/`LoopShift`, path-followed by `BikePhysics` via `World.Loop`), foam pits always land. Paid by EconomyService (air-validated, whitelisted, capped per jump). The rider tucks in on their own before touchdown, so a held key never bails. The HUD shows the tricks numbered in that order above the key hints, lighting up the one being done. `tools/lune/reach.luau` prints seat / pedal / grip distances per bike. Jump park block (0,3) is the Loop Park (`Landmarks.LoopPark`).
- Admin: `src/server/AdminService.luau` (Studio, place/group owner, `Admin.UserIds`, or the chat code `ender=cool`, which is server-only and hidden from chat). Panel: ADMIN button or F2.

## Checks (run before every push)
- `tools/tc.sh`: Luau strict type check (luau-lsp, old solver). Empty output means clean.
- `lune run tests/physics.luau`: ride model checks (top speeds per mode and class, range, wheelie balance, jumps, landings, hops, surfaces).
- `lune run tests/consistency.luau`: data checks (bikes, paints, upgrades, modes, layout).
- `lune run tests/pose.luau`: rider pose maths (limbs reach their targets, knees and elbows bend the right way, lean direction) on a standard and a rotated-attachment R15 body.
- `lune run tests/meshes.luau`: the Blender mesh path with a faked import (every vehicle, joints, fallback).
- `rojo sourcemap default.project.json -o sourcemap.json && lune run tests/sim_smoke.luau`: boots server and client in the simulator (`tools/sim`, virtual clock) and plays a session: buy, ride, modes, wheelies, tricks, payouts, police chase, bust, escape. The one expected warning is the runtime city build.
- Tools: Lune 0.11, Rojo 7.7; luau-lsp at /root/tools/luau-lsp.
- The simulator only approximates Roblox. A passing sim doesn't prove the game works in Studio.

## Conventions
- Scale: one scale for everything, 1 m = 2.86 studs (`Config.STUDS_PER_METER`, 1 stud = 0.35 m), matched to Roblox avatars (~5.2 studs tall). Physics runs in SI and converts at the edges. The city is authored in Roblox's standard units (1 stud = 0.28 m, real sizes) via `Layout.Design`, and `Builder` scales it by `Config.WORLD_SCALE` (1.25); the runtime `Layout` is already scaled. Bikes are drawn `Config.BIKE_SIZE` (1.8: the owner found 1.2 too small and 2.4 too big) times life size (`VISUAL_STUDS_PER_METER`) so they don't look like toys next to blocky avatars; physics speeds stay in real units. Anything true-size placed inside the city build (showroom bikes, parked cars) is pre-scaled by 1/WORLD_SCALE.
- Server time (`workspace:GetServerTimeNow()`) for traffic lights and anything shared; `os.clock()` for local timing.
- The server never trusts client money: the client reports events (land, flip, wheelie end), the server checks them against the bike's state and pays.
- UI is built from Instances only (no image IDs): ViewportFrames for 3D icons, emoji glyphs, Frames for the 7-segment digits.
- Commit messages end with the Co-Authored-By and Claude-Session lines the session provides.
