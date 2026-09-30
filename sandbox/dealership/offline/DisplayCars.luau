--[[
	Stands a display car on every CarSlot in a dealership the exporter has just built -- for the
	sandbox copy only.

	In AGES this is DealershipService.stock's job, done when the server starts; the drop-in model
	carries no cars, or they would stand twice. The sandbox has no server to do it, and a showroom
	with nothing in it cannot be judged: the turntables, the hero podium and the lot are all
	composed around the cars on them. So the exporter does here what stock() does there, with the
	game's own VehicleChassis.BuildDisplay and content/Vehicles, and the same ground offset -- the
	sandbox shows exactly the cars the game will.

	Not a module: spliced by sandbox/dealership/export.py after Vehicles and VehicleChassis.
]]

local function stockDisplayCars(root)
	for _, slot in root:GetDescendants() do
		if slot.Name ~= "CarSlot" or not slot:IsA("BasePart") then
			continue
		end
		local id = slot:GetAttribute("VehicleId")
		local kind = Vehicles.Get(id)
		if kind == nil then
			error(`DisplayCars: a CarSlot asks for vehicle "{tostring(id)}", which content/Vehicles does not sell`)
		end
		-- A car drawn from a model (the GT-R) cannot be baked here: there is no model to draw it from
		-- offline. sandbox/dealership/BuildOnPlay stands it on its slot when the place is played.
		if kind.model ~= nil then
			continue
		end
		-- The slot sits a tenth of a stud above the floor it marks: as in DealershipService.stock.
		local car = VehicleChassis.BuildDisplay(kind, slot.CFrame * CFrame.new(0, -slot.Size.Y / 2, 0))
		car.Name = `Display_{kind.id}`
		car.Parent = slot.Parent
	end
end
