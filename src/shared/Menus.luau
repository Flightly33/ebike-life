--[[
	Menus: what the shop counters sell. Every walk-in shop has a theme (`Menus.ThemeOf`, from the
	building kind and the shop's name), and each theme its own menu, its own fit-out
	(Client/ShopFit) and its own greeting. The counter part (`OrderCounter`, City/Interior) carries
	the theme as its `Menu` attribute.

	Effects (OrderService applies them; the server never trusts the client):
	  Cash = x  cash multiplier for `Minutes` (of several, the best one counts; it multiplies a 2x boost)
	  Xp = x    XP multiplier for `Minutes` (same rule)
	  Charge    fills the battery of your bike, if it's parked by the shop
	  Heat = n  takes n wanted stars off (a disguise; once every `HeatCooldown` seconds)
	Every item has a 3D model of the same id (Shared/Models/ItemModel), shown on the menu, held in the
	hand when bought, and on display in the shops.
]]

export type Item = {
	Id: string,
	Name: string,
	Icon: string,
	Category: string, -- "Food", "Drinks", "Treats", "Gear"
	Price: number,
	Description: string,
	Cash: number?,
	Xp: number?,
	Minutes: number?,
	Charge: boolean?,
	Heat: number?,
	Eat: boolean?, -- eaten in bites (otherwise sipped or worn)
}

export type Theme = {
	Id: string,
	Title: string,
	Greeting: string,
	Items: { Item },
}

local Menus = {}

Menus.HeatCooldown = 180

local function item(id: string, name: string, icon: string, category: string, price: number, fx: { [string]: any }): Item
	local it: Item = {
		Id = id,
		Name = name,
		Icon = icon,
		Category = category,
		Price = price,
		Description = "",
		Cash = fx.Cash,
		Xp = fx.Xp,
		Minutes = fx.Minutes,
		Charge = fx.Charge,
		Heat = fx.Heat,
		Eat = fx.Eat,
	}
	local parts = {}
	if it.Cash then
		table.insert(parts, string.format("%gx cash", it.Cash))
	end
	if it.Xp then
		table.insert(parts, string.format("%gx XP", it.Xp))
	end
	local text = table.concat(parts, " + ")
	if it.Minutes and text ~= "" then
		text ..= string.format(" for %d min", it.Minutes)
	end
	if it.Charge then
		text = "Fills your bike's battery (park it by the shop)"
	end
	if it.Heat then
		text = string.format("Lose %d wanted star%s: the cops lose track of you", it.Heat, if it.Heat > 1 then "s" else "")
	end
	it.Description = fx.Text or text
	return it
end

Menus.Themes = {
	Food = {
		Id = "Food",
		Title = "Fast Food",
		Greeting = "Welcome in! What can I get you?",
		Items = {
			item("fries", "Fries", "🍟", "Food", 60, { Cash = 1.1, Minutes = 2, Eat = true }),
			item("burger", "Bay Burger", "🍔", "Food", 140, { Cash = 1.2, Minutes = 3, Eat = true }),
			item("combo", "#1 Combo", "🍔", "Food", 220, { Cash = 1.25, Xp = 1.1, Minutes = 4, Eat = true }),
			item("bucket", "Family Bucket", "🍗", "Food", 480, { Cash = 1.5, Minutes = 4, Eat = true }),
			item("soda", "Fountain Soda", "🥤", "Drinks", 40, { Xp = 1.1, Minutes = 2 }),
			item("shake", "Strawberry Shake", "🥤", "Drinks", 90, { Xp = 1.2, Minutes = 3 }),
			item("cone", "Soft Serve", "🍦", "Treats", 50, { Cash = 1.1, Minutes = 2, Eat = true }),
		},
	},
	Gas = {
		Id = "Gas",
		Title = "Sunfuel Mart",
		Greeting = "Hey! Need a charge?",
		Items = {
			item("hotdog", "Roller Hot Dog", "🌭", "Food", 70, { Cash = 1.15, Minutes = 2, Eat = true }),
			item("chips", "Plantain Chips", "🥔", "Food", 40, { Cash = 1.05, Minutes = 2, Eat = true }),
			item("coffee", "Coffee To Go", "☕", "Drinks", 50, { Xp = 1.1, Minutes = 3 }),
			item("slushie", "Blue Slushie", "🧊", "Drinks", 80, { Xp = 1.15, Minutes = 3 }),
			item("energy", "Volt Energy", "⚡", "Drinks", 200, { Cash = 1.3, Xp = 1.1, Minutes = 2 }),
			item("battery", "Battery Top-Up", "🔋", "Gear", 150, { Charge = true }),
			item("cap", "Trucker Cap", "🧢", "Gear", 900, { Heat = 1 }),
		},
	},
	Cafe = {
		Id = "Cafe",
		Title = "Café",
		Greeting = "¡Buenas! Un cafecito?",
		Items = {
			item("cafecito", "Cafecito", "☕", "Drinks", 30, { Xp = 1.15, Minutes = 3 }),
			item("latte", "Iced Latte", "🧋", "Drinks", 90, { Xp = 1.25, Minutes = 3 }),
			item("pastelito", "Guava Pastelito", "🥐", "Treats", 60, { Cash = 1.15, Minutes = 3, Eat = true }),
			item("croqueta", "Croquetas", "🥖", "Food", 70, { Cash = 1.15, Minutes = 3, Eat = true }),
			item("donut", "Glazed Donut", "🍩", "Treats", 45, { Cash = 1.1, Minutes = 2, Eat = true }),
			item("gelato", "Mango Gelato", "🍨", "Treats", 110, { Cash = 1.2, Xp = 1.1, Minutes = 3, Eat = true }),
		},
	},
	Market = {
		Id = "Market",
		Title = "Market",
		Greeting = "Fresh today, take a look!",
		Items = {
			item("water", "Cold Water", "💧", "Drinks", 25, { Xp = 1.05, Minutes = 3 }),
			item("coconut", "Fresh Coconut", "🥥", "Drinks", 80, { Xp = 1.2, Minutes = 3 }),
			item("smoothie", "Mango Smoothie", "🥭", "Drinks", 110, { Cash = 1.2, Minutes = 3 }),
			item("fruitcup", "Fruit Cup", "🍉", "Food", 60, { Cash = 1.1, Xp = 1.1, Minutes = 3, Eat = true }),
			item("chips", "Plantain Chips", "🥔", "Food", 40, { Cash = 1.05, Minutes = 2, Eat = true }),
			item("battery", "Spare Cell Top-Up", "🔋", "Gear", 170, { Charge = true }),
		},
	},
	Eatery = {
		Id = "Eatery",
		Title = "Kitchen",
		Greeting = "Take a seat, the kitchen's hot!",
		Items = {
			item("taco", "Street Tacos", "🌮", "Food", 90, { Cash = 1.2, Minutes = 3, Eat = true }),
			item("cubano", "Cubano Sandwich", "🥪", "Food", 150, { Cash = 1.25, Minutes = 4, Eat = true }),
			item("noodles", "Noodle Bowl", "🍜", "Food", 160, { Cash = 1.2, Xp = 1.15, Minutes = 4, Eat = true }),
			item("sushi", "Sushi Board", "🍣", "Food", 260, { Cash = 1.35, Minutes = 4, Eat = true }),
			item("soda", "Fountain Soda", "🥤", "Drinks", 40, { Xp = 1.1, Minutes = 2 }),
		},
	},
	Gear = {
		Id = "Gear",
		Title = "Rider Gear",
		Greeting = "Gear up! Riders get the good stuff.",
		Items = {
			item("gel", "Energy Gel", "⚡", "Food", 60, { Xp = 1.2, Minutes = 2, Eat = true }),
			item("battery", "Power Cell", "🔋", "Gear", 130, { Charge = true }),
			item("shades", "Sport Shades", "🕶", "Gear", 400, { Xp = 1.3, Minutes = 5 }),
			item("hoodie", "Plain Hoodie", "🧥", "Gear", 1200, { Heat = 1 }),
			item("helmetcam", "Helmet Cam", "📷", "Gear", 1500, { Cash = 1.3, Xp = 1.3, Minutes = 5 }),
		},
	},
	Boutique = {
		Id = "Boutique",
		Title = "Boutique",
		Greeting = "Hi! Looking for something fresh?",
		Items = {
			item("shades", "Designer Shades", "🕶", "Gear", 450, { Xp = 1.3, Minutes = 5 }),
			item("chain", "Gold Chain", "📿", "Gear", 1800, { Cash = 1.4, Minutes = 6 }),
			item("bucket_hat", "Bucket Hat", "👒", "Gear", 1000, { Heat = 1 }),
			item("flowers", "Flower Bunch", "💐", "Gear", 120, { Xp = 1.15, Minutes = 4 }),
			item("water", "Cold Water", "💧", "Drinks", 25, { Xp = 1.05, Minutes = 3 }),
		},
	},
} :: { [string]: Theme }

-- Shop names to themes (first keyword found in the lower-cased name wins)
local KEYWORDS: { { string } } = {
	{ "cafe", "Cafe" }, { "bakery", "Cafe" }, { "panader", "Cafe" }, { "ventanita", "Cafe" }, { "dulcer", "Cafe" }, { "gelato", "Cafe" },
	{ "fruter", "Market" }, { "bodega", "Market" }, { "farmacia", "Market" }, { "lavand", "Market" },
	{ "taco", "Eatery" }, { "noodle", "Eatery" }, { "sushi", "Eatery" }, { "sabor", "Eatery" },
	{ "surf", "Gear" }, { "bike", "Gear" }, { "hardware", "Gear" }, { "gadget", "Gear" }, { "phone", "Gear" }, { "game", "Gear" },
}

function Menus.ThemeOf(kind: string, name: string): string
	if kind == "Food" or kind == "Gas" then
		return kind
	end
	local lower = string.lower(name)
	for _, pair in KEYWORDS do
		if string.find(lower, pair[1], 1, true) then
			return pair[2]
		end
	end
	return "Boutique"
end

function Menus.Get(theme: string, id: string): Item?
	local t = Menus.Themes[theme]
	if not t then
		return nil
	end
	for _, it in t.Items do
		if it.Id == id then
			return it
		end
	end
	return nil
end

return Menus
