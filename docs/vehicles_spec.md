# AGES vehicles — decided spec (2026-08-19)

Cars, sold at the dealership already in the game (`auto_dealer`, the `car_salesperson`
job, and CarDealerService's counter queue). Researched against Jailbreak and the wider
field of Roblox driving games -- see [`top_games_architecture.md`](top_games_architecture.md)
for the general engine-architecture pass this grew out of -- before anything was built,
per the standing rule that a feature gets agreed before it gets implemented.

## What exists now

- `content/Vehicles.luau` -- five cars, priced as a ladder against the same jobs
  `content/Jobs.luau` already prices a life against: a beater a first job's wage can
  reach, up through a manager's-desk car, to a statement piece nobody needs.
- `world/VehicleChassis.luau` -- the physics. Raycast suspension, not a physical wheel.
- `services/VehicleService.luau` -- ownership, buy/sell, and where a car stands in the
  world.
- `client/ui/VehicleUI.luau` -- the showroom/garage panel (top-left, the one corner
  StatsUI/CarDealerUI/HouseUI/GangUI leave alone) and a speedometer that appears only
  while seated in a VehicleSeat.

## Why raycast suspension over a physical wheel

The chassis research (see `top_games_architecture.md` and the streaming section of
`roblox_engineering.md`) landed on the same answer for two independent reasons:

1. **This city is built out of kerbs.** `MAP_PLAN.md`'s whole history is edges --
   pavement lips, road bands, kerb geometry -- and a `HingeConstraint` wheel is a
   cylinder that can physically catch on any of them. A raycast wheel never touches the
   road; it measures the distance to it and pushes back with a spring. There is nothing
   for a kerb to snag.
2. **It is what the field actually uses now.** VehicleSeat + hinge-motored wheels is
   the decade-old default and it is still what most beginner tutorials show, but the
   raycast approach -- the damped spring `F = kx - cv` per corner, applied through a
   `VectorForce` -- is what current open-source chassis kits (A-Chassis's successors,
   OpenChassis, and the March-2026 DevForum deep-dive this was built from) have moved to,
   for exactly the kerb-catching reason above plus far more tunable handling.

## Why this needed no Server Authority migration

`roblox_engineering.md` already decided sports gets its own place with
`AuthorityMode = Server`, specifically because a shared physics ball has no natural
single owner and Roblox's ordinary network-ownership model breaks down on it. A car does
not have that problem: it has exactly one driver at a time. `VehicleChassis.Build` hands
network ownership to the driver explicitly the instant they sit down and back to the
server the instant they stand up -- the fix the research names for the one place default
ownership actually misbehaves (a passenger who sits before the driver keeps ownership
and the driver's own input lags). There is no passenger seat in this file, on purpose:
one seat removes the whole class of bug rather than working around it.

The physics *decision* -- how much force, from what throttle -- is still made by a
server Script every tick, reading `VehicleSeat.Throttle`/`.Steer`, which Roblox already
replicates driver-to-server as part of what a VehicleSeat is. The *resolution* of that
force happens on the driver's own machine because they own it. That split is the entire
reason this stayed inside the existing game place instead of needing a third one.

## Why one car spawned at a time

The garage holds up to `Config.Vehicles.MaxOwned` (2), but only one is ever standing in
the world. Buying a second does not double-park it next to the first -- it goes in the
garage, and pulling a different one out despawns whichever was active first. Same
reasoning `Config.House.MaxPerPlayer` gives for property: a fleet nobody is driving is a
number, not a feature, and a street where every life's whole garage is parked on it stops
looking like anybody lives there.

## Why no world coordinates are ever saved

A car's parking spot is found fresh every time, off the `auto_dealer` place point, using
the same `Ground.SpotAt`/`Ground.Bearings` search every other placement system in this
game already uses. Nothing about where a car is standing is written to the profile.
This is `HANDOVER.md`'s own rule for the whole codebase -- place-point ids are stable,
coordinates are not -- applied to a system that did not exist when the rule was written.

## What is deliberately not here

- **Multiple cars driven at once**, or a passenger seat. One seat is what makes the
  network-ownership handoff unconditionally correct; a second seat reopens the exact bug
  the research names.
- **Real car meshes.** Every car is built from primitives and two colours, on the same
  convention `content/Props.luau` and `content/Cast.luau` already establish -- a model
  dropped into the Studio folder under a matching name takes over without a line of this
  system moving. Nobody has modelled one yet.
- **Fuel, damage, or repair.** Ownership and driving are the whole of this pass. If a
  fuel loop is ever wanted, it is a `WorkSpots`-style errand at a gas station place
  point, not a change to the chassis.
- **Police involvement.** `BountyService`/`PoliceService` know nothing about a player
  being in a car. A chase on foot and a chase in a car currently look identical to the
  pursuit system, which is correct for now and worth revisiting only once there is a
  reason cars and crime need to talk to each other.
- **A `SetVehicle` row on StatsUI**, matching the one `HouseUpdated`/`CarDealerUpdated`
  already have. Skipped this pass rather than touched blind -- StatsUI is a large,
  central file and the dedicated panel already carries the whole feature on its own.
