--[[
	Ads: what the billboards, rooftop boards, LED screens and bus shelter panels show
	(Client/Billboards draws them). Every brand is made up. Layouts:
	  Hero     a big emoji in a ring on one side, headline, line and a call-out pill on the other
	  Bold     huge headline over a gradient, an emoji row and a price burst
	  Product  the item itself, turning in 3D (Shared/Models/ItemModel), with the headline
	  Bike     a Flighty e-moto in 3D (Shared/Models/BikeModel), with the headline
	The owner's own images (AssetIds.Billboards) are shown in turn with these.
]]

export type Ad = {
	Id: string,
	Brand: string,
	Headline: string,
	Line: string,
	Emoji: string,
	Badge: string?, -- the burst or pill (a price, "NEW!")
	Top: Color3, -- gradient, top to bottom
	Bottom: Color3,
	Ink: Color3, -- the headline's colour
	Accent: Color3,
	Layout: string,
	Item: string?, -- ItemModel id for Product
	Bike: string?, -- Bikes id for Bike
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local WHITE = rgb(255, 255, 255)
local INK = rgb(24, 24, 28)

local Ads = {}

Ads.List = {
	{ Id = "burgerbay", Brand = "BURGER BAY", Headline = "STACKED. SAUCED. SOLD.", Line = "The Bay Burger, flame-grilled on the beach since never", Emoji = "🍔", Badge = "2 FOR $5", Top = rgb(220, 40, 36), Bottom = rgb(150, 18, 20), Ink = rgb(255, 210, 40), Accent = rgb(255, 210, 40), Layout = "Product", Item = "burger" },
	{ Id = "cluck", Brand = "CLUCK SHACK", Headline = "FEED THE WHOLE CREW", Line = "The Family Bucket: 12 pieces, 0 regrets", Emoji = "🍗", Badge = "$9.99", Top = rgb(200, 30, 40), Bottom = rgb(250, 250, 245), Ink = WHITE, Accent = rgb(250, 200, 40), Layout = "Product", Item = "bucket" },
	{ Id = "tacoola", Brand = "TACO OLA", Headline = "TACO TUESDAY, EVERY DAY", Line = "Street tacos, three for the price of a cafecito", Emoji = "🌮", Badge = "3 x $4", Top = rgb(0, 160, 160), Bottom = rgb(0, 90, 110), Ink = rgb(255, 150, 50), Accent = rgb(255, 150, 50), Layout = "Hero" },
	{ Id = "pizzapalma", Brand = "PIZZA PALMA", Headline = "HOT SLICE. COLD BREEZE.", Line = "Wood-fired by the bay, delivered by e-moto", Emoji = "🍕", Top = rgb(30, 130, 60), Bottom = rgb(16, 70, 34), Ink = WHITE, Accent = rgb(230, 50, 40), Layout = "Hero" },
	{ Id = "frosty", Brand = "FROSTY SWIRL", Headline = "BEAT THE HEAT", Line = "Soft serve so cold it's basically air con", Emoji = "🍦", Badge = "$1 CONES", Top = rgb(255, 170, 205), Bottom = rgb(255, 230, 240), Ink = rgb(200, 40, 110), Accent = rgb(60, 180, 230), Layout = "Product", Item = "cone" },
	{ Id = "flamingo", Brand = "FLAMINGO FRIES", Headline = "PINK BOX. GOLD FRIES.", Line = "Crispy outside, fluffy inside, Miami all over", Emoji = "🍟", Top = rgb(255, 110, 170), Bottom = rgb(255, 200, 90), Ink = WHITE, Accent = rgb(255, 230, 60), Layout = "Product", Item = "fries" },
	{ Id = "gator", Brand = "GATOR BITES", Headline = "SNAP IT UP", Line = "Everglades-style wings, 6 flavours of heat", Emoji = "🐊", Badge = "NEW!", Top = rgb(70, 130, 46), Bottom = rgb(30, 60, 20), Ink = rgb(250, 214, 40), Accent = rgb(250, 214, 40), Layout = "Bold" },
	{ Id = "mangowave", Brand = "MANGO WAVE", Headline = "RIDE THE WAVE", Line = "Fresh mango smoothies, blended to order", Emoji = "🥭", Top = rgb(255, 150, 0), Bottom = rgb(255, 90, 40), Ink = WHITE, Accent = rgb(70, 170, 70), Layout = "Product", Item = "smoothie" },
	{ Id = "cubancorner", Brand = "CUBAN CORNER", Headline = "PRESSED TO PERFECTION", Line = "The Cubano: ham, pork, swiss, pickles, mustard. That's it.", Emoji = "🥪", Top = rgb(30, 80, 160), Bottom = rgb(16, 40, 90), Ink = WHITE, Accent = rgb(230, 40, 40), Layout = "Product", Item = "cubano" },
	{ Id = "cafecito", Brand = "CAFECITO EXPRESS", Headline = "TINY CUP. HUGE ENERGY.", Line = "Cuban coffee at the ventanita, 24/7", Emoji = "☕", Badge = "30¢", Top = rgb(120, 76, 44), Bottom = rgb(60, 36, 20), Ink = rgb(250, 230, 200), Accent = rgb(250, 200, 120), Layout = "Product", Item = "cafecito" },
	{ Id = "sunfuel", Brand = "SUNFUEL", Headline = "CHARGED IN A FLASH", Line = "Free EV charging at every station. Slushies extra.", Emoji = "⚡", Badge = "FREE", Top = rgb(255, 140, 20), Bottom = rgb(255, 200, 60), Ink = WHITE, Accent = rgb(30, 30, 34), Layout = "Bold" },
	{ Id = "volt", Brand = "VOLT ENERGY", Headline = "ZERO TO WHEELIE", Line = "Volt Energy. Now in Neon Lime.", Emoji = "⚡", Top = rgb(20, 20, 24), Bottom = rgb(40, 60, 20), Ink = rgb(140, 255, 60), Accent = rgb(140, 255, 60), Layout = "Product", Item = "energy" },
	{ Id = "flighty1", Brand = "FLIGHTY MECHANICS", Headline = "THE STORM X IS HERE", Line = "Louvred shrouds, long-travel forks, 12 kW. Test ride today.", Emoji = "🏍", Badge = "NEW", Top = rgb(20, 24, 30), Bottom = rgb(40, 60, 90), Ink = WHITE, Accent = rgb(255, 120, 20), Layout = "Bike", Bike = "storm_x" },
	{ Id = "flighty2", Brand = "FLIGHTY MECHANICS", Headline = "BUILT FOR MIAMI", Line = "E-motos from youth pit bikes to 25 kW monsters", Emoji = "🏍", Top = rgb(255, 120, 20), Bottom = rgb(200, 60, 10), Ink = WHITE, Accent = rgb(20, 24, 30), Layout = "Bike", Bike = "halo_gt" },
	{ Id = "flighty3", Brand = "FLIGHTY MECHANICS", Headline = "DARE TO RIDE CURSED", Line = "The Deathrider. Hellfire not included. Actually, it is.", Emoji = "💀", Top = rgb(30, 10, 10), Bottom = rgb(120, 20, 10), Ink = rgb(255, 120, 40), Accent = rgb(255, 60, 20), Layout = "Bike", Bike = "deathrider" },
	{ Id = "tip_wheelie", Brand = "RIDE FLIGHTLY", Headline = "WHEELIES PAY MORE", Line = "Air, tricks and wheelies boost your cash. Mind the cops.", Emoji = "💵", Top = rgb(40, 170, 70), Bottom = rgb(20, 100, 40), Ink = WHITE, Accent = rgb(255, 230, 60), Layout = "Bold", Badge = "x2" },
	{ Id = "tip_cops", Brand = "MIAMI-DADE PD", Headline = "STUNTS NEAR COPS = ★", Line = "This is a public service announcement. Probably.", Emoji = "🚓", Top = rgb(20, 40, 100), Bottom = rgb(10, 20, 50), Ink = WHITE, Accent = rgb(230, 40, 40), Layout = "Hero" },
	{ Id = "lawyer", Brand = "SAL BIGGS, ATTORNEY", Headline = "FELL OFF YOUR E-MOTO?", Line = "Call 1-800-FLIP-OUT. Se habla español.", Emoji = "⚖️", Badge = "24/7", Top = rgb(250, 220, 40), Bottom = rgb(250, 190, 20), Ink = INK, Accent = rgb(200, 30, 30), Layout = "Hero" },
	{ Id = "radio", Brand = "WAVE 104.5 FM", Headline = "MIAMI'S HOTTEST HITS", Line = "All summer. All day. Turn it up.", Emoji = "📻", Top = rgb(130, 40, 200), Bottom = rgb(240, 60, 150), Ink = WHITE, Accent = rgb(80, 230, 255), Layout = "Bold" },
	{ Id = "bank", Brand = "BISCAYNE BANK", Headline = "SAVE LIKE A LOCAL", Line = "4.2% on savings. Palm trees not included.", Emoji = "🏦", Top = rgb(240, 244, 248), Bottom = rgb(200, 214, 230), Ink = rgb(20, 60, 120), Accent = rgb(20, 120, 90), Layout = "Hero" },
	{ Id = "hotel", Brand = "PALMERA GRAND", Headline = "STAY GOLDEN", Line = "Oceanfront suites in Coconut Grove", Emoji = "🌴", Top = rgb(250, 200, 140), Bottom = rgb(240, 120, 90), Ink = WHITE, Accent = rgb(40, 140, 150), Layout = "Hero" },
	{ Id = "cruise", Brand = "SUNSET CRUISES", Headline = "SAIL THE BAY TONIGHT", Line = "Dinner, DJ and the skyline from the water", Emoji = "🛳", Badge = "$49", Top = rgb(250, 120, 60), Bottom = rgb(60, 40, 120), Ink = WHITE, Accent = rgb(255, 210, 90), Layout = "Hero" },
	{ Id = "airline", Brand = "CORAL AIR", Headline = "FLY THE SUNNY WAY", Line = "Daily flights from Miami to everywhere warm", Emoji = "✈️", Top = rgb(40, 150, 220), Bottom = rgb(120, 210, 250), Ink = WHITE, Accent = rgb(250, 110, 90), Layout = "Bold" },
	{ Id = "airboat", Brand = "GLADES AIRBOATS", Headline = "MEET A GATOR", Line = "Airboat tours on the Tamiami Trail", Emoji = "🐊", Badge = "TOURS", Top = rgb(60, 110, 60), Bottom = rgb(140, 170, 90), Ink = WHITE, Accent = rgb(250, 200, 60), Layout = "Hero" },
	{ Id = "gym", Brand = "IRON PALM GYM", Headline = "BEACH BODY? SURE.", Line = "First month free. Leave the e-moto at the door.", Emoji = "💪", Top = rgb(30, 30, 34), Bottom = rgb(70, 70, 80), Ink = rgb(255, 80, 60), Accent = rgb(255, 80, 60), Layout = "Bold" },
	{ Id = "gadget", Brand = "GADGET HUB", Headline = "SEE EVERY TRICK", Line = "Helmet cams from $99. Record your best runs.", Emoji = "📷", Top = rgb(20, 120, 220), Bottom = rgb(10, 50, 110), Ink = WHITE, Accent = rgb(255, 230, 60), Layout = "Product", Item = "helmetcam" },
	{ Id = "shades", Brand = "SOLAR SHADE CO.", Headline = "LOOK COOL AT 80", Line = "Polarised. Shatterproof. Very Miami.", Emoji = "🕶", Top = rgb(255, 230, 120), Bottom = rgb(255, 170, 60), Ink = INK, Accent = rgb(220, 50, 120), Layout = "Product", Item = "shades" },
} :: { Ad }

-- The news ticker on the LED screens
Ads.Ticker = {
	"BREAKING: local rider holds a wheelie the length of the Rickenbacker",
	"WEATHER: hot, sunny, chance of afternoon storms",
	"TRAFFIC: I-95 northbound moving well, watch for police past the turnpike",
	"SPORTS: Biscayne Links hosts the Granada Cup this weekend",
	"FLIGHTY MECHANICS: new paints in the crates",
	"PORT OF MIAMI: three cruise ships in today",
	"EVERGLADES: gators sunbathing on the Tamiami Trail, ride slow",
	"WAVE 104.5: tonight's sunset at 7:58 PM",
}

return Ads
