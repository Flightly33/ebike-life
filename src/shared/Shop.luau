--[[
	Shop: what the Shop menu sells. Boosts are bought with in-game cash; game passes with Robux once
	their ids are set in Shared/AssetIds (until then they show as "Coming soon").
]]

local Shop = {}

export type Boost = { Id: string, Name: string, Description: string, Price: number, Minutes: number }

Shop.Boosts = {
	{ Id = "cash2x_10", Name = "2x Cash", Description = "Double everything you earn for 10 minutes.", Price = 2500, Minutes = 10 },
	{ Id = "cash2x_30", Name = "2x Cash+", Description = "Double everything you earn for 30 minutes.", Price = 6500, Minutes = 30 },
} :: { Boost }

export type Pass = { Key: string, Name: string, Description: string }

Shop.Passes = {
	{ Key = "DoubleCash", Name = "Permanent 2x Cash", Description = "Double cash from riding and tricks, forever." },
	{ Key = "VIP", Name = "VIP", Description = "A VIP tag and every crate paint for your bikes." },
} :: { Pass }

function Shop.GetBoost(id: string): Boost?
	for _, boost in Shop.Boosts do
		if boost.Id == id then
			return boost
		end
	end
	return nil
end

return Shop
