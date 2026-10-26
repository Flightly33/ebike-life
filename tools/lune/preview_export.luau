--[[
	Turns a built model into a flat JSON part list for tools/preview/render.mjs.
]]
local Preview = {}

function Preview.Export(root: any): { any }
	local parts = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local c = d.Color
			local shape = "Block"
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType.Name == "Sphere" then
				shape = "Ellipsoid" -- a sphere mesh fills the part's box, unlike a Ball part
			elseif d.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif d.ClassName == "Part" then
				shape = d.Shape.Name
			elseif d.ClassName == "Seat" or d.ClassName == "SpawnLocation" then
				shape = "Block"
			end
			local text = nil
			local gui = d:FindFirstChildOfClass("SurfaceGui")
			if gui then
				local label = gui:FindFirstChildOfClass("TextLabel")
				if label then
					text = { face = gui.Face.Name, text = label.Text, color = { label.TextColor3.R, label.TextColor3.G, label.TextColor3.B } }
				end
			end
			table.insert(parts, {
				cf = { d.CFrame:GetComponents() },
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				color = { c.R, c.G, c.B },
				material = d.Material.Name,
				shape = shape,
				transparency = d.Transparency,
				reflectance = d.Reflectance,
				text = text,
			})
		end
	end
	return parts
end

return Preview
