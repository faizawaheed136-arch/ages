--!strict
-- The cars the dealership sells. Content data, not system code: the numbers here
-- are what a car *is*, and adding a sixth one to the lot should be a table entry
-- rather than a new build in Studio.
--
-- Sized and coloured rather than modelled, on the same reasoning Props.luau gives
-- at length: a car built from a block and two cylinders per wheel needs nothing
-- bought or uploaded, so the showroom exists and drives correctly on the day this
-- file is written rather than on the day somebody finishes five car meshes. A real
-- model dropped into the Studio folder under a matching name takes over -- see
-- world/VehicleChassis.luau -- and nothing here changes when it does.
--
-- Four cars, priced as a ladder against the same jobs a life is actually earning
-- from -- see content/Jobs.luau for the salaries this is read against. Up through
-- a car that means the manager's desk paid off, to one that is a statement rather
-- than a commute. Performance climbs with price, and it is the only thing that
-- does: there is no car here that is simply worse for the same money than another
-- one on the lot, because a strictly-dominated row is a row nobody would ever
-- choose and a showroom is not supposed to have those.
--
-- The cheapest rung -- a $2200 "Corner Runabout" a first job's wage could open --
-- used to sit below the sedan here and was cut on owner instruction ("i have no
-- clue what its for"): a starter car a player cannot tell apart from the one
-- above it in the showroom list is not doing its job as the bottom of a ladder,
-- and a confusing rung is worse than no rung.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleKind = Types.VehicleKind

local SOURCE: { VehicleKind } = {
	{
		id = "sedan",
		name = "Fairline Sedan",
		-- The car most lives actually own: nothing about it is the best on the
		-- lot, and nothing about it is the worst.
		price = 6400,
		size = Vector3.new(7.0, 2.8, 16.5),
		color = Color3.fromRGB(96, 110, 128),
		accentColor = Color3.fromRGB(24, 24, 26),
		topSpeedStuds = 80,
		acceleration = 11,
		steerDegrees = 30,
	},
	{
		id = "wagon",
		name = "Elmhurst Wagon",
		-- The longest body on the lot and the widest turning circle to go with
		-- it -- a family car should feel like one to drive, not just look like
		-- one parked.
		price = 8800,
		size = Vector3.new(7.2, 2.9, 18.5),
		color = Color3.fromRGB(150, 138, 108),
		accentColor = Color3.fromRGB(58, 52, 40),
		-- 81, not 76: the dominance check a few lines down refuses a car that
		-- costs more than a cheaper one without beating it on top speed or
		-- acceleration, and at 76 this lost to the $6400 sedan's 80 on both
		-- axes -- a strictly worse car nobody would ever buy, which threw at
		-- require time and took the whole server down with it (nothing after
		-- VehicleService in init.server.luau's boot order ever ran). One stud
		-- over the sedan is enough to clear the check without pretending a
		-- wagon this size outruns a coupe.
		topSpeedStuds = 81,
		acceleration = 10,
		steerDegrees = 26,
	},
	{
		id = "coupe",
		name = "Vantage Coupe",
		-- The manager's-desk car. Priced to want the second job's rung, not the
		-- first one, and the numbers say so before the colour does.
		price = 15500,
		size = Vector3.new(6.8, 2.3, 15.5),
		color = Color3.fromRGB(224, 200, 60),
		accentColor = Color3.fromRGB(30, 28, 24),
		topSpeedStuds = 100,
		acceleration = 15,
		steerDegrees = 36,
	},
	{
		id = "roadster",
		name = "Solari Roadster",
		-- The statement, and the top of the ladder deliberately: low, narrow,
		-- and the only car here whose steer rating is as sharp as the cheapest
		-- one on the lot at a third again the top speed. Nothing subtle about
		-- what this one is for.
		price = 28000,
		size = Vector3.new(6.6, 2.0, 14.8),
		color = Color3.fromRGB(200, 32, 44),
		accentColor = Color3.fromRGB(18, 18, 20),
		topSpeedStuds = 126,
		acceleration = 19,
		steerDegrees = 34,
	},
}

-- Loud at require time rather than at the moment somebody walks into the showroom,
-- which is the standing rule for content in this tree.
local byId: { [string]: VehicleKind } = {}
for _, vehicle in SOURCE do
	if byId[vehicle.id] ~= nil then
		error(`[AGES content] duplicate vehicle id "{vehicle.id}"`)
	end
	if vehicle.price <= 0 then
		error(`[AGES content] vehicle "{vehicle.id}" has a price of {vehicle.price}; a free car is not a sale`)
	end
	if vehicle.size.X <= 0 or vehicle.size.Y <= 0 or vehicle.size.Z <= 0 then
		error(`[AGES content] vehicle "{vehicle.id}" has a zero or negative size`)
	end
	if vehicle.topSpeedStuds <= 0 then
		error(`[AGES content] vehicle "{vehicle.id}" has a topSpeedStuds of {vehicle.topSpeedStuds}; it would never move`)
	end
	if vehicle.acceleration <= 0 then
		error(`[AGES content] vehicle "{vehicle.id}" has an acceleration of {vehicle.acceleration}; it would never reach its top speed`)
	end
	if vehicle.steerDegrees <= 0 or vehicle.steerDegrees > 60 then
		error(
			`[AGES content] vehicle "{vehicle.id}" has steerDegrees {vehicle.steerDegrees}, outside 0-60. `
				.. `Above 60 a chassis this length starts folding into itself on a full lock.`
		)
	end
	byId[vehicle.id] = vehicle
end

-- No two cars may cost the same and be strictly worse on both of the numbers a
-- player can actually feel -- see the header. Caught here rather than left to be
-- noticed in the showroom, because a dominated row is the one kind of content bug
-- that looks like a design choice until somebody buys the better car and never
-- looks back at the worse one.
for _, cheaper in SOURCE do
	for _, pricier in SOURCE do
		if pricier.price <= cheaper.price then
			continue
		end
		if pricier.topSpeedStuds <= cheaper.topSpeedStuds and pricier.acceleration <= cheaper.acceleration then
			error(
				`[AGES content] vehicle "{pricier.id}" costs more than "{cheaper.id}" but is not faster and does`
					.. ` not accelerate harder -- nobody would ever buy it. Raise one of its numbers in`
					.. ` content/Vehicles.luau or drop the price.`
			)
		end
	end
end

if #SOURCE == 0 then
	error("[AGES content] there are no vehicles, so the dealership has nothing to sell")
end

if #SOURCE > Config.Vehicles.MaxOwned * 3 then
	-- Not a hard rule, just a sanity check: a garage cap of two on a lot of fifteen
	-- cars would mean most of the lot can never be tried by anyone who already
	-- owns something, which is a worse showroom than a smaller one.
	warn(
		`[AGES content] {#SOURCE} vehicles on the lot against a garage cap of {Config.Vehicles.MaxOwned}; `
			.. `most of it will go untried by anyone who already owns two cars`
	)
end

local Vehicles = {}

Vehicles.All = SOURCE
Vehicles.ById = byId

-- Nil for an id nothing sells any more. Every caller handles that rather than
-- being handed a default -- a saved life can own a car this build no longer
-- lists, and erroring here would lock that life out of the garage entirely.
function Vehicles.Get(id: string): VehicleKind?
	return byId[id]
end

return Vehicles
