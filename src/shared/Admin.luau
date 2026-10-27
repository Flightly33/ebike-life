--[[
	Admin: who gets the admin panel. The server decides (AdminService); the client only reads the
	player's "Admin" attribute to show the button.

	Admins are: anyone in Studio play-testing, the game's owner (the user who owns the place, or the
	owner of the group that does), and the user IDs listed below.
]]

local Admin = {}

-- Extra admins by Roblox user ID (find yours in your profile URL: roblox.com/users/<id>/profile)
Admin.UserIds = {} :: { number }

Admin.Places = { "Spawn", "Downtown", "Wynwood", "JumpPark", "Plaza", "Park", "Police", "Beach", "Countryside" }
Admin.MaxCash = 1e9

return Admin
