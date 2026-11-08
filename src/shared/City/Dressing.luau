--[[
	Dressing: the detail pass's named materials (PartKit.NAMED, the realism pack's second import)
	put on the finished city by role and district, in one walk over its parts. Builder runs it last,
	before it scales the city. Every pick comes from where the part is (PartKit.Hash), never the
	builders' random streams, so the city they make doesn't change; PartKit.Dress keeps each part
	the kind of ground it was to the bike and the police. Without the pack's second import the
	parts just show their base materials.

	  roads       about half the side streets and most country roads are worn and patched; the
	              freeway decks, ramps, the port's yard and the airport's apron are concrete; every
	              painted line, crossing, stop bar and arrow wears chipped road paint
	  pavements   clay pavers in Brickell, Edgewater, the Plaza, the Grove, half of Downtown and
	              (pink) along Ocean Drive; coral keystone in Coral Gables
	  lots        car parks worn; deco hotel terraces terrazzo; pool decks coral keystone; planting
	              beds mulched; hedges leafy
	  walls       warehouses in painted block; a share of stucco rain-streaked; bungalows in lap
	              siding, and half the Grove's and Key Biscayne's houses; yard walls coral rock in
	              the leafy districts or stucco
	  roofs       flat roofs in white membrane or gravel; metal roofs on bungalows and some houses
	  water       seawalls and quay walls in marine concrete; the surf's edge wet sand; docks,
	              boardwalks and the Everglades' tower in weathered boards; containers corrugated
]]

local LayoutModule = require(script.Parent.Layout)
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local PartKit = require(script.Parent.Parent.PartKit)

local Dressing = {}

local CELL = 400
local index: { [number]: { LayoutModule.Block } }? = nil

local function key(x: number, z: number): number
	return math.floor(x / CELL) * 100003 + math.floor(z / CELL)
end

-- The block a point lies in (its whole area, pavements included), from a coarse grid of blocks
local function blockAt(p: Vector3): LayoutModule.Block?
	local grid = index
	if not grid then
		local built: { [number]: { LayoutModule.Block } } = {}
		for _, block in Layout.Blocks do
			for gx = math.floor(block.MinX / CELL), math.floor(block.MaxX / CELL) do
				for gz = math.floor(block.MinZ / CELL), math.floor(block.MaxZ / CELL) do
					local k = gx * 100003 + gz
					local list = built[k] or {}
					table.insert(list, block)
					built[k] = list
				end
			end
		end
		index = built
		grid = built
	end
	for _, block in (grid :: any)[key(p.X, p.Z)] or {} do
		if p.X >= block.MinX and p.X <= block.MaxX and p.Z >= block.MinZ and p.Z <= block.MaxZ then
			return block
		end
	end
	return nil
end

local PAINT_NAMES = { Line = true, Crosswalk = true, StopLine = true, ArrowShaft = true, ArrowHead = true, ArrowBend = true }
local PAVERS = Color3.fromRGB(172, 110, 86)
local PINK_PAVERS = Color3.fromRGB(204, 150, 136)
local KEYSTONE = Color3.fromRGB(224, 212, 186)
local DECK = Color3.fromRGB(150, 150, 146)
local MEMBRANE = Color3.fromRGB(214, 214, 210)
local GRAVEL = Color3.fromRGB(168, 164, 156)
local TERRAZZO = Color3.fromRGB(236, 232, 222)

-- Boards and seams run across the long side of a deck (a top face maps the part's X and Z)
local function acrossLong(part: BasePart): boolean
	return part.Size.X > part.Size.Z
end

-- A sloping roof slab's seams run down the slope: the turned copy when the slope runs along X
local function slopeAlongX(part: BasePart): boolean
	local cf = part.CFrame
	return math.abs(cf.RightVector.Y) > math.abs(cf.LookVector.Y)
end

local function ownerName(part: BasePart): string
	local model = part:FindFirstAncestorWhichIsA("Model")
	return if model then model.Name else ""
end

-- Dresses one part by its name, material, folder and district. Returns true if it changed it.
local function dress(part: BasePart, folder: string): boolean
	local name = part.Name
	local material = part.Material
	local at = part.CFrame.Position
	local h = PartKit.Hash(at, #name)
	if PAINT_NAMES[name] and material == Enum.Material.SmoothPlastic then
		PartKit.Dress(part, "RealRoadPaint")
		return true
	end
	if folder == "Roads" then
		if name == "Road" and material == Enum.Material.Asphalt then
			-- a street (not an avenue: those are fresh)
			if math.min(part.Size.X, part.Size.Z) <= Layout.STREET_WIDTH + 1 and h < 0.5 then
				PartKit.Dress(part, "RealAsphaltWorn")
				return true
			end
		elseif name == "CountryRoad" and h < 0.75 then
			PartKit.Dress(part, "RealAsphaltWorn")
			return true
		elseif name == "Intersection" and math.max(part.Size.X, part.Size.Z) <= Layout.STREET_WIDTH + 1 and h < 0.4 then
			PartKit.Dress(part, "RealAsphaltWorn")
			return true
		end
		return false
	end
	if folder == "Freeways" then
		if (name == "Deck" or name == "RampRoad") and material == Enum.Material.Asphalt then
			PartKit.Dress(part, "RealConcreteDeck", DECK)
			return true
		end
		return false
	end
	if folder == "Pads" then
		if name == "Pavement" then
			local block = blockAt(at)
			local district = if block then block.District else ""
			if district == "Brickell" or district == "Edgewater" or district == "Plaza" or (district == "Downtown" and h < 0.5) or (district == "Grove" and h < 0.6) then
				PartKit.Dress(part, "RealBrickPavers", PAVERS)
				return true
			elseif district == "ArtDeco" then
				PartKit.Dress(part, "RealBrickPavers", PINK_PAVERS)
				return true
			elseif district == "Gables" or district == "GablesHotel" then
				PartKit.Dress(part, "RealCoralStone", KEYSTONE)
				return true
			end
		end
		return false
	end
	if folder == "Shore" then
		if name == "Seawall" or name == "QuayWall" then
			PartKit.Dress(part, "RealMarineConcrete")
			return true
		elseif name == "Shelf" and material == Enum.Material.Sand then
			PartKit.Dress(part, "RealWetSand")
			return true
		elseif name == "Paving" and material == Enum.Material.Brick then
			PartKit.Dress(part, "RealBrickPavers")
			return true
		elseif material == Enum.Material.WoodPlanks then
			PartKit.Dress(part, "RealPlanksWeathered", nil, acrossLong(part))
			return true
		end
		return false
	end
	if folder == "Port" then
		if name == "Container" then
			PartKit.Dress(part, "RealContainerPaint")
			return true
		elseif name == "Yard" then
			PartKit.Dress(part, "RealConcreteDeck")
			return true
		end
		return false
	end
	if folder == "Everglades" then
		if material == Enum.Material.WoodPlanks and (name == "Boardwalk" or name == "BoardwalkRamp" or name == "TowerDeck" or name == "Deck") then
			PartKit.Dress(part, "RealPlanksWeathered", nil, acrossLong(part))
			return true
		end
		return false
	end
	if folder == "Airport" then
		local parent = part.Parent
		if parent and parent.Name == "Apron" and (material == Enum.Material.Concrete or material == Enum.Material.Asphalt) then
			PartKit.Dress(part, "RealConcreteDeck")
			return true
		end
		return false
	end
	-- blocks and everything else on the lots
	if name == "Hedge" and material == Enum.Material.Grass then
		PartKit.Dress(part, "RealHedge")
		return true
	elseif name == "Bed" and material == Enum.Material.Ground then
		PartKit.Dress(part, "RealMulch")
		return true
	elseif (name == "Lot" or name == "Asphalt" or name == "Yard" or name == "CarPark") and material == Enum.Material.Asphalt and h < 0.8 then
		PartKit.Dress(part, "RealAsphaltWorn")
		return true
	elseif name == "Fence" and material == Enum.Material.SmoothPlastic then
		-- yard walls: coral rock in the leafy districts, stucco elsewhere now and then
		local block = blockAt(at)
		local district = if block then block.District else ""
		local leafy = district == "Gables" or district == "Grove" or district == "Suburb" or district == "KeyHomes"
		if leafy and h < 0.35 then
			PartKit.Dress(part, "RealCoralRubble", Color3.fromRGB(214, 204, 180))
			return true
		elseif h < 0.6 then
			PartKit.Dress(part, "RealStucco")
			return true
		end
		return false
	elseif name == "PoolDeck" and material == Enum.Material.Pavement then
		-- (coral keystone round the pools, the Miami way)
		PartKit.Dress(part, "RealCoralStone", KEYSTONE)
		return true
	elseif (name == "Paving" or name == "Terrace" or name == "Step") and material == Enum.Material.Pavement and ownerName(part) == "Plaza" then
		-- the City Plaza: terrazzo underfoot, the Miami way
		PartKit.Dress(part, "RealTerrazzo", if name == "Paving" then Color3.fromRGB(226, 216, 200) else TERRAZZO)
		return true
	elseif name == "Terrace" and material == Enum.Material.Pavement and ownerName(part) == "Hotel" then
		PartKit.Dress(part, "RealTerrazzo", TERRAZZO)
		return true
	elseif name == "Roof" and material == Enum.Material.DiamondPlate then
		if h < 0.6 then
			PartKit.Dress(part, "RealRoofMembrane", MEMBRANE)
		else
			PartKit.Dress(part, "RealGravel", GRAVEL)
		end
		return true
	elseif name == "RoofCap" then
		if h < 0.55 then
			PartKit.Dress(part, "RealRoofMembrane", MEMBRANE)
			return true
		elseif h < 0.85 then
			PartKit.Dress(part, "RealGravel", GRAVEL)
			return true
		end
		return false
	elseif name == "RoofSlab" and h < 0.7 then
		PartKit.Dress(part, "RealRoofMembrane", MEMBRANE)
		return true
	elseif name == "Plinth" and material == Enum.Material.Granite then
		PartKit.Dress(part, "RealGraniteCladding")
		return true
	elseif name == "Walls" or name == "Body" then
		local owner = ownerName(part)
		if owner == "Warehouse" and material == Enum.Material.Concrete and h < 0.75 then
			PartKit.Dress(part, "RealPaintedBlock")
			return true
		elseif owner == "Bungalow" and material == Enum.Material.WoodPlanks then
			PartKit.Dress(part, "RealWoodSiding")
			return true
		elseif material == Enum.Material.Plaster and part.MaterialVariant == "" then
			local block = blockAt(at)
			local district = if block then block.District else ""
			if owner == "House" and (district == "Grove" or district == "KeyHomes") and h < 0.5 then
				PartKit.Dress(part, "RealWoodSiding")
				return true
			elseif h < 0.3 then
				PartKit.Dress(part, "RealStuccoStreaked")
				return true
			end
		end
		return false
	elseif name == "Roof" and (material == Enum.Material.RoofShingles or material == Enum.Material.ClayRoofTiles) then
		local owner = ownerName(part)
		local block = blockAt(at)
		local district = if block then block.District else ""
		if (owner == "Bungalow" and h < 0.5) or (owner == "House" and (district == "Grove" or district == "KeyHomes") and h < 0.35) then
			PartKit.Dress(part, "RealMetalRoof", Color3.fromRGB(176, 180, 184), slopeAlongX(part))
			return true
		end
		return false
	end
	return false
end

-- Dresses the whole city; returns how many parts it changed, by variant
function Dressing.Apply(city: Instance): (number, { [string]: number })
	local count = 0
	local byVariant: { [string]: number } = {}
	for _, top in city:GetChildren() do
		local folder = top.Name
		for _, d in top:GetDescendants() do
			if d:IsA("BasePart") and dress(d, folder) then
				count += 1
				byVariant[d.MaterialVariant] = (byVariant[d.MaterialVariant] or 0) + 1
			end
		end
	end
	return count, byVariant
end

return Dressing
