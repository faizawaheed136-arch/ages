--!strict
-- The cars the dealership sells. Content data, not system code: the numbers here
-- are what a car *is*, and adding a sixth one to the lot should be a table entry
-- rather than a new build in Studio.
--
-- Sized and styled rather than modelled, on the same reasoning Props.luau gives at
-- length: shared/CarBody draws every car from parts, from its `style` and `size`,
-- so nothing is bought or uploaded and the car in the shop, on the floor and at
-- the kerb is one drawing.
--
-- Eight cars, priced as a ladder against the same jobs a life is actually earning
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

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleKind = Types.VehicleKind

-- Eight cars from four makers, two each, on one price ladder: every car costs more than the one
-- below it and beats every cheaper car on top speed or acceleration (checked below). `size` is the
-- car's whole outline -- width (X), roof height above the road (Y), length (Z) -- and `style` is the
-- body shared/CarBody draws inside it; the two are drawn for each other, so a new car picks an
-- existing style and that style's outline. Names are the dealership's own: no maker's badge or
-- model name from outside this game.
local SOURCE: { VehicleKind } = {
	{
		id = "sedan",
		name = "Fairline Arden",
		brand = "Fairline",
		year = 2023,
		style = "sedan",
		drivetrain = "FWD",
		seats = 5,
		-- The car most lives actually own: nothing about it is the best on the lot, and nothing
		-- about it is the worst.
		price = 6400,
		size = Vector3.new(7.0, 5.3, 16.5),
		color = Color3.fromRGB(96, 110, 128),
		accentColor = Color3.fromRGB(24, 24, 26),
		topSpeedStuds = 80,
		acceleration = 11,
		steerDegrees = 30,
	},
	{
		id = "wagon",
		name = "Elmhurst Wayfarer",
		brand = "Elmhurst",
		year = 2021,
		style = "wagon",
		drivetrain = "AWD",
		seats = 5,
		-- The longest roof on the lot and the widest turning circle to go with it -- a family car
		-- should feel like one to drive, not just look like one parked. 81, not 76: at 76 it lost
		-- to the cheaper sedan on both numbers, a car nobody would buy, and the check below threw
		-- at require time and took the server down with it.
		price = 8800,
		size = Vector3.new(7.2, 5.5, 17.8),
		color = Color3.fromRGB(150, 138, 108),
		accentColor = Color3.fromRGB(58, 52, 40),
		topSpeedStuds = 81,
		acceleration = 10,
		steerDegrees = 26,
	},
	{
		id = "pickup",
		name = "Fairline Hauler",
		brand = "Fairline",
		year = 2022,
		style = "pickup",
		drivetrain = "4WD",
		seats = 5,
		-- A working truck: a shade quicker than the family cars, a turning circle like a bus.
		price = 10900,
		size = Vector3.new(7.4, 6.1, 18.5),
		color = Color3.fromRGB(176, 40, 36),
		accentColor = Color3.fromRGB(30, 30, 32),
		topSpeedStuds = 84,
		acceleration = 11.5,
		steerDegrees = 25,
	},
	{
		id = "suv",
		name = "Elmhurst Summit",
		brand = "Elmhurst",
		year = 2024,
		style = "suv",
		drivetrain = "AWD",
		seats = 7,
		isNew = true,
		-- Seven seats on a raised ride, and the power to carry them.
		price = 12500,
		size = Vector3.new(7.4, 6.3, 17.2),
		color = Color3.fromRGB(34, 44, 58),
		accentColor = Color3.fromRGB(26, 26, 28),
		topSpeedStuds = 86,
		acceleration = 12,
		steerDegrees = 27,
	},
	{
		id = "coupe",
		name = "Castellan Rapier",
		brand = "Castellan",
		year = 2022,
		style = "coupe",
		drivetrain = "RWD",
		seats = 4,
		-- The manager's-desk car. Priced to want the second job's rung, not the first one, and the
		-- numbers say so before the colour does.
		price = 15500,
		size = Vector3.new(7.0, 4.7, 15.6),
		color = Color3.fromRGB(224, 200, 60),
		accentColor = Color3.fromRGB(30, 28, 24),
		topSpeedStuds = 100,
		acceleration = 15,
		steerDegrees = 36,
	},
	{
		id = "gt",
		name = "Castellan Sabre GT",
		brand = "Castellan",
		year = 2025,
		style = "gt",
		drivetrain = "RWD",
		seats = 4,
		isNew = true,
		-- A long-legged tourer: faster than the coupe everywhere, a touch less nimble.
		price = 21000,
		size = Vector3.new(7.2, 4.6, 16.6),
		color = Color3.fromRGB(28, 72, 150),
		accentColor = Color3.fromRGB(22, 22, 24),
		topSpeedStuds = 112,
		acceleration = 16.5,
		steerDegrees = 34,
	},
	{
		id = "roadster",
		name = "Solari Spyder",
		brand = "Solari",
		year = 2024,
		style = "roadster",
		drivetrain = "RWD",
		seats = 2,
		-- The statement, and the top of the everyday ladder: low, narrow, open, and as sharp to
		-- steer as anything on the lot at a third again the sedan's top speed.
		price = 28000,
		size = Vector3.new(6.8, 4.2, 14.8),
		color = Color3.fromRGB(200, 32, 44),
		accentColor = Color3.fromRGB(18, 18, 20),
		topSpeedStuds = 126,
		acceleration = 19,
		steerDegrees = 34,
	},
	{
		id = "supercar",
		name = "Solari Vento",
		brand = "Solari",
		year = 2026,
		style = "supercar",
		drivetrain = "AWD",
		seats = 2,
		isNew = true,
		-- The dream on the turntable: the fastest thing in the game, at the top of every range.
		price = 60000,
		size = Vector3.new(7.6, 4.5, 16.2),
		color = Color3.fromRGB(236, 236, 232),
		accentColor = Color3.fromRGB(16, 16, 18),
		topSpeedStuds = 140,
		acceleration = 20,
		steerDegrees = 33,
	},
	{
		id = "gtr",
		name = "Nakamura GT-R Nismo",
		brand = "Nakamura",
		year = 2026,
		style = "gt",
		-- Drawn from the modelled car in ReplicatedStorage.CarModels, and driven on the numbers of the
		-- real one (shared/CarSpec): 0-100 km/h in 2.9 s, 100-0 in 31 m, 315 km/h.
		model = "GTR",
		drivetrain = "AWD",
		seats = 4,
		isNew = true,
		-- Above the Vento: the one car here that is quicker than the price says.
		price = 95000,
		scale = 1.25,
		size = Vector3.new(8.93, 6.16, 21.06),
		color = Color3.fromRGB(30, 62, 150),
		accentColor = Color3.fromRGB(16, 16, 18),
		-- Drawn 1.25 times life size, so a metre of it is 1.25/0.28 studs: 315 km/h (87.5 m/s) is 390
		-- studs a second, and 0-100 km/h in 2.9 s (9.6 m/s^2) is 43 studs a second squared -- the
		-- numbers the real car puts up, for the shop's bars.
		topSpeedStuds = 390,
		acceleration = 43,
		steerDegrees = 32,
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
