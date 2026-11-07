--[[
	Writes blender/vehicles.json: every bike's rig points (metres, model space: -Z forward, +Y up)
	and spec, plus the car dimensions, for blender/build_vehicles.py.

	lune run tools/lune/export_vehicles.luau
]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")

local Bikes = Loader.Require("ReplicatedStorage.Shared.Bikes")
local BikeModel = Loader.Require("ReplicatedStorage.Shared.Models.BikeModel")
local CarModel = Loader.Require("ReplicatedStorage.Shared.Models.CarModel")

local function v(p: any): { number }
	return { p.X, p.Y, p.Z }
end
local function c(col: any): { number }
	return { col.R, col.G, col.B }
end

-- (the bus and the box van stay part-built for now: a generic Blender car shell would replace their
-- cargo box, doors and signs)
local cars = {}
for kind, dims in CarModel.Dims do
	if kind ~= "Bus" and kind ~= "BoxVan" then
		cars[kind] = dims
	end
end
local bikes = table.clone(Bikes.List)
table.insert(bikes, Bikes.PoliceMoto) -- the police units' moto (not for sale, modelled all the same)
local out = { Bikes = {}, Cars = cars, VisualStudsPerMeter = 0.8 / 0.28, CarScale = CarModel.SCALE }
for _, bike in bikes do
	local g = BikeModel.Geometry(bike)
	local geo = bike.Geometry
	table.insert(out.Bikes, {
		Id = bike.Id,
		Name = bike.Name,
		Style = geo.Style,
		Drive = bike.Drive,
		Pedals = bike.Pedals,
		Throttle = bike.Throttle,
		TireKind = bike.TireKind,
		Kit = geo.Kit or "Dirt",
		TireWidth = geo.TireWidth,
		BarWidth = geo.BarWidth,
		SeatHeight = geo.SeatHeight,
		Wheelbase = geo.Wheelbase,
		Rf = g.Rf,
		Rr = g.Rr,
		RearAxle = v(g.RearAxle),
		FrontAxle = v(g.FrontAxle),
		Axis = v(g.Axis),
		HB = v(g.HB),
		HT = v(g.HT),
		BB = v(g.BB),
		SeatTop = v(g.SeatTop),
		ST = v(g.ST),
		Bars = v(g.Bars),
		Pivot = v(g.Pivot),
		ShockTop = v(g.ShockTop),
		ShockBottom = v(g.ShockBottom),
		FrontTravel = geo.FrontTravel or 0.2,
		RearTravel = geo.RearTravel or 0.2,
		Colors = { Frame = c(bike.Colors.Frame), Accent = c(bike.Colors.Accent), Rims = c(bike.Colors.Rims) },
	})
end
fs.writeDir("blender")
fs.writeFile("blender/vehicles.json", serde.encode("json", out, true))
print("wrote blender/vehicles.json", #out.Bikes, "bikes")
