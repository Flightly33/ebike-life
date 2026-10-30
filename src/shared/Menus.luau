--[[
	Menus: what the shop counters sell (the walk-in shops, fast food and gas stations). Each counter
	part (`OrderCounter`, built by City/Interior) carries a `Menu` attribute naming one of these.
	Food and drinks give a short cash multiplier (stacks on a 2x boost, the best one counts while
	several run); the battery top-up fills the pack of the bike you rode in on.
]]

export type Item = {
	Id: string,
	Name: string,
	Icon: string,
	Price: number,
	Description: string,
	Cash: number?, -- cash multiplier while it lasts
	Minutes: number?,
	Charge: boolean?, -- fills your bike's battery
}

local Menus = {}

Menus.Lists = {
	Food = {
		{ Id = "fries", Name = "Fries & Shake", Icon = "🍟", Price = 60, Cash = 1.1, Minutes = 2, Description = "1.1x cash for 2 minutes" },
		{ Id = "combo", Name = "#1 Combo", Icon = "🍔", Price = 180, Cash = 1.25, Minutes = 3, Description = "1.25x cash for 3 minutes" },
		{ Id = "feast", Name = "Family Feast", Icon = "🍗", Price = 450, Cash = 1.5, Minutes = 4, Description = "1.5x cash for 4 minutes" },
	},
	Gas = {
		{ Id = "coffee", Name = "Cuban Coffee", Icon = "☕", Price = 50, Cash = 1.1, Minutes = 2, Description = "1.1x cash for 2 minutes" },
		{ Id = "energy", Name = "Volt Energy Drink", Icon = "⚡", Price = 200, Cash = 1.3, Minutes = 2, Description = "1.3x cash for 2 minutes" },
		{ Id = "topup", Name = "Battery Top-Up", Icon = "🔋", Price = 150, Charge = true, Description = "Fills your bike's battery (bring it to the store)" },
	},
	Shop = {
		{ Id = "water", Name = "Cold Water", Icon = "💧", Price = 30, Cash = 1.05, Minutes = 2, Description = "1.05x cash for 2 minutes" },
		{ Id = "smoothie", Name = "Mango Smoothie", Icon = "🥭", Price = 120, Cash = 1.2, Minutes = 3, Description = "1.2x cash for 3 minutes" },
		{ Id = "pastelito", Name = "Pastelitos", Icon = "🥐", Price = 90, Cash = 1.15, Minutes = 3, Description = "1.15x cash for 3 minutes" },
	},
} :: { [string]: { Item } }

function Menus.Get(menu: string, id: string): Item?
	local list = Menus.Lists[menu]
	if not list then
		return nil
	end
	for _, item in list do
		if item.Id == id then
			return item
		end
	end
	return nil
end

return Menus
