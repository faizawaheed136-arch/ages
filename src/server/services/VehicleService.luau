--!strict
-- Owning a car, and driving one. The dealership's other half: CarDealerService is
-- the counter job -- customers, a queue, a tip -- and this is the showroom floor
-- behind it, where the same building sells something a life actually keeps.
--
-- Ownership is content, not a minigame: buy a car, and it is yours until you sell
-- it or a life ends. What is a minigame -- or as close as this game gets to one
-- outside school and work -- is the driving itself, and that lives in
-- world/VehicleChassis.luau. This file decides who owns what and where the car
-- physically stands; the chassis decides how it moves once it is standing there.
--
-- One car spawned per life at a time, on the same reasoning HouseService caps
-- ownership rather than letting a life sprawl across every suburb lot at once:
-- a garage of cars nobody is driving is a number, and a street with everybody's
-- whole fleet parked on it is a city that stops looking like anybody lives there.
-- Buying a second car does not spawn a second one -- it goes in the garage, and
-- switching which one is "active" despawns the old one before the new one
-- appears, so there is never more than one of your cars in the world.
--
-- No coordinates are ever written to the profile. A car is parked wherever
-- VehicleChassis.Build puts it this session, found fresh off the auto_dealer
-- place point every time -- the same rule HANDOVER.md states for everything
-- else in this game: place-point ids are stable, coordinates are not. A car
-- that remembered its own parking spot across a server restart would be a
-- Vector3 baked into a save file, which is exactly the thing this project's own
-- rules exist to prevent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)
local PlaceService = require(script.Parent.PlaceService)

local Ground = require(script.Parent.Parent.world.Ground)
local VehicleChassis = require(script.Parent.Parent.world.VehicleChassis)
local Vehicles = require(script.Parent.Parent.content.Vehicles)

type LifeData = Types.LifeData
type VehicleState = Types.VehicleState
type Chassis = VehicleChassis.Chassis

local VehicleService = {}

local VEHICLES = Config.Vehicles
local PLACE_ID = "auto_dealer"

-- How often the idle-despawn check runs. Unrelated to the chassis's own
-- per-frame drive tick -- see Config.Vehicles.TickSeconds -- this only ever
-- reads whether a seat is occupied, which does not need frame-rate resolution.
local IDLE_TICK_SECONDS = 2

local VehicleUpdatedRemote = Remotes.Get("VehicleUpdated")
local RequestBuyVehicleRemote = Remotes.Get("RequestBuyVehicle")
local RequestSellVehicleRemote = Remotes.Get("RequestSellVehicle")
local RequestSpawnVehicleRemote = Remotes.Get("RequestSpawnVehicle")
local RequestStoreVehicleRemote = Remotes.Get("RequestStoreVehicle")

-- One car standing in the world for one player, and how long it has stood there
-- with nobody in it. `idleFor` is what IdleDespawnSeconds is measured against;
-- it resets to zero the instant anybody sits down, so a car somebody is actively
-- driving can never time out from under them mid-drive.
type Spawned = {
	chassis: Chassis,
	idleFor: number,
}

local spawned: { [Player]: Spawned } = {}
local spawning: { [Player]: boolean } = {}
local pushed: { [Player]: string } = {}
local enabled = true

local function dataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

local function ownedCount(life: LifeData): number
	local count = 0
	for _ in life.vehicles.owned do
		count += 1
	end
	return count
end

-- Forward declaration -- push is defined below stateFor, which reads `spawned`
-- and `dataFor`, both already in scope. Declared here for the same reason
-- GangService declares `push` ahead of `checkEscape`: a name used with no
-- `local` in front of it compiles to a global read, which is legal Luau, builds
-- clean, and dies the first time anybody actually buys a car.
local push: (player: Player, notice: string?) -> ()

local function stateFor(player: Player, notice: string?): VehicleState?
	local life = dataFor(player)
	if life == nil then
		return nil
	end
	return {
		catalog = Vehicles.All,
		owned = life.vehicles.owned,
		active = life.vehicles.active,
		busy = spawning[player] == true,
		notice = notice,
	}
end

function push(player: Player, notice: string?)
	local state = stateFor(player, notice)
	local digest: string
	if state == nil then
		digest = "none"
	else
		local owned: { string } = {}
		for id in state.owned do
			table.insert(owned, id)
		end
		table.sort(owned)
		digest = `{table.concat(owned, ",")}|{tostring(state.active)}|{tostring(state.busy)}|{tostring(state.notice)}`
	end
	if pushed[player] == digest and notice == nil then
		-- Renotified pushes always go out -- a notice is a one-off line for the
		-- panel to show and clear, and suppressing a repeated one would mean a
		-- second identical refusal (buying the same car twice in a row) reads
		-- as the button having done nothing.
		return
	end
	pushed[player] = digest
	VehicleUpdatedRemote:FireClient(player, state)
end

-- Where to stand a car near the dealership. Searches a different arc from the
-- one CarDealerService's own queue search uses -- see the header on
-- CarDealerService for its own bearing, which is centred on world-south -- so a
-- parked car does not land in the middle of the customer line. Wider clearance
-- than a person's, because a car is bigger than a body.
local function findParkSpot(station: Vector3): Vector3?
	local ignore = Ground.IgnoreList()
	-- A car's own nominal footprint, not a body's -- see Ground.BodyRadius for
	-- why this is measured off the character elsewhere; there is no character
	-- to measure here, so the widest car on the lot stands in for one.
	local widest = 0
	for _, kind in Vehicles.All do
		widest = math.max(widest, kind.size.X, kind.size.Z)
	end
	local radius = widest / 2 + 1
	local height = 4

	local bearings = Ground.Bearings(VEHICLES.ParkArcDegrees, VEHICLES.ParkBearings)
	for _, out in { VEHICLES.ParkStuds, VEHICLES.ParkStuds * VEHICLES.ParkRetryScale } do
		for _, bearing in bearings do
			-- Offset ninety degrees from world-south, which is the centre of the
			-- queue's own arc -- see the header. A car parked to the side of the
			-- counter rather than in front of it.
			local direction = CFrame.Angles(0, math.rad(90 + bearing), 0) * Vector3.new(0, 0, -1)
			local spot = Ground.SpotAt(station + direction * out, radius, height, ignore, station)
			if spot ~= nil then
				return spot
			end
		end
	end
	return nil
end

local function despawn(player: Player)
	local current = spawned[player]
	if current == nil then
		return
	end
	spawned[player] = nil
	current.chassis.destroy()
end

-- Puts the active car away and clears which one is active, both at once -- the
-- two are the same fact seen from the profile's side and the world's side, and
-- writing one without the other is how a save ends up claiming a car is out
-- that nothing in the world can find.
local function storeActive(player: Player)
	despawn(player)
	local life = dataFor(player)
	if life ~= nil then
		life.vehicles.active = nil
	end
end

-- Builds and stands up a car the life already owns. Nothing in
-- VehicleChassis.Build yields today -- it is built from primitives, the same
-- reason PropModels and SubjectModels need nothing bought or uploaded to exist
-- -- but the day a real mesh is dropped in and loaded through something
-- web-backed, this stops being true without anybody having to remember to come
-- back here. The re-check below costs nothing while it is unnecessary and is
-- exactly what every other spawn in this game already does for the case where
-- it is not.
local function spawnActive(player: Player, vehicleId: string): boolean
	if spawning[player] then
		return false
	end
	local life = dataFor(player)
	if life == nil or not life.alive then
		return false
	end
	if life.vehicles.owned[vehicleId] ~= true then
		return false
	end
	local kind = Vehicles.Get(vehicleId)
	if kind == nil then
		return false
	end
	local place = PlaceService.Find(PLACE_ID)
	if place == nil then
		return false
	end

	spawning[player] = true
	push(player, nil)

	local spot = findParkSpot(place.part.Position)
	if spot == nil then
		spawning[player] = false
		push(player, "There is nowhere to park it right now.")
		return false
	end

	-- Whatever was out comes in first, so there is never a moment with two of a
	-- life's cars standing in the world at once.
	despawn(player)

	local facing = place.part.Position - spot
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local look = if flat.Magnitude > 0.01 then flat.Unit else -Vector3.zAxis
	local lift = kind.size.Y / 2 + VEHICLES.SuspensionLength + VEHICLES.WheelRadius + 0.5
	local cframe = CFrame.lookAt(spot + Vector3.new(0, lift, 0), spot + Vector3.new(0, lift, 0) + look)

	local chassis = VehicleChassis.Build(kind, cframe)
	spawning[player] = false

	-- Re-checked after the build: a life can end, sell the car, or request a
	-- different one to spawn while this ran.
	local stillWanted = life.alive and life.vehicles.owned[vehicleId] == true
	if not stillWanted then
		chassis.destroy()
		return false
	end

	spawned[player] = { chassis = chassis, idleFor = 0 }
	life.vehicles.active = vehicleId
	push(player, nil)
	return true
end

-- Buys a car outright. Returns whether it happened; a refusal is always said in
-- the pushed notice, because a buy button that quietly did nothing is
-- indistinguishable from the panel being broken.
function VehicleService.Buy(player: Player, vehicleId: string): boolean
	if not enabled then
		return false
	end
	local life = dataFor(player)
	if life == nil or not life.alive then
		return false
	end
	local kind = Vehicles.Get(vehicleId)
	if kind == nil then
		push(player, "That is not a car on this lot.")
		return false
	end
	if life.vehicles.owned[vehicleId] == true then
		push(player, "Already yours.")
		return false
	end
	if ownedCount(life) >= VEHICLES.MaxOwned then
		push(player, `The garage only holds {VEHICLES.MaxOwned}. Sell one first.`)
		return false
	end
	if not MoneyService.Spend(player, kind.price, `bought a {kind.name}`) then
		push(player, `{Money.Format(kind.price)} for the {kind.name}.`)
		return false
	end

	life.vehicles.owned[vehicleId] = true
	push(player, `Bought the {kind.name}.`)

	-- The first car a life owns is worth pulling straight out onto the forecourt
	-- rather than leaving the player to find the second remote that does it --
	-- the showroom floor is the world's own confirmation that the purchase
	-- landed. A second or third car goes in the garage and stays there until
	-- asked for, which is the ordinary case Spawn exists for.
	if life.vehicles.active == nil then
		task.spawn(spawnActive, player, vehicleId)
	end
	return true
end

-- Sells an owned car. Refuses the active one -- see Remotes.luau's note on why:
-- selling the car you might be about to be told to drive needs an answer for
-- what "active" now points at, and the honest UI move is to store it first.
function VehicleService.Sell(player: Player, vehicleId: string): boolean
	if not enabled then
		return false
	end
	local life = dataFor(player)
	if life == nil or not life.alive then
		return false
	end
	if life.vehicles.owned[vehicleId] ~= true then
		return false
	end
	if life.vehicles.active == vehicleId then
		push(player, "Put it away before you sell it.")
		return false
	end
	local kind = Vehicles.Get(vehicleId)
	if kind == nil then
		-- Content deleted out from under a save. Let it go for nothing rather
		-- than leaving a life permanently unable to clear a phantom entry.
		life.vehicles.owned[vehicleId] = nil
		push(player, "Sold.")
		return true
	end

	local refund = math.floor(kind.price * VEHICLES.ResaleFraction)
	MoneyService.Add(player, refund, `sold a {kind.name}`)
	life.vehicles.owned[vehicleId] = nil
	push(player, `Sold the {kind.name} for {Money.Format(refund)}.`)
	return true
end

-- Brings an owned car out of the garage.
function VehicleService.Spawn(player: Player, vehicleId: string): boolean
	if not enabled then
		return false
	end
	local ok = spawnActive(player, vehicleId)
	if not ok and spawning[player] ~= true then
		push(player, "Could not bring that one out.")
	end
	return ok
end

-- Puts the active car away by hand, ahead of the idle timeout.
function VehicleService.Store(player: Player): boolean
	local life = dataFor(player)
	if life == nil or life.vehicles.active == nil then
		return false
	end
	storeActive(player)
	push(player, "Parked.")
	return true
end

-- Whether this player's driver seat currently has a body in it. Read by the
-- idle tick, and the only reason a spawned car is ever left alone regardless of
-- IdleDespawnSeconds -- a car cannot time out from under the person driving it.
local function isOccupied(current: Spawned): boolean
	return current.chassis.seat.Occupant ~= nil
end

local function tickPlayer(player: Player, current: Spawned, elapsed: number)
	if current.chassis.model.Parent == nil then
		-- The model left the world some other way -- a hot reload, a server
		-- sweep. The table entry is stale either way and has to go, or the idle
		-- clock keeps counting against a car that is not there to time out.
		spawned[player] = nil
		local life = dataFor(player)
		if life ~= nil then
			life.vehicles.active = nil
		end
		return
	end

	if isOccupied(current) then
		current.idleFor = 0
		return
	end

	current.idleFor += elapsed
	if current.idleFor >= VEHICLES.IdleDespawnSeconds then
		storeActive(player)
		push(player, "Nobody was using it, so it went back to the lot.")
	end
end

-- Called by LifeService at both ends of a life for the reason every other
-- service with something standing in the world is called there: a car left
-- running through a death or a rebirth is the worst frame this teardown
-- discipline exists to prevent, one vehicle further out than the rest of it.
function VehicleService.ResetForNewLife(player: Player)
	despawn(player)
	spawning[player] = nil
	pushed[player] = nil
end

function VehicleService.SetEnabled(value: boolean)
	enabled = value
	if not value then
		for player in spawned do
			despawn(player)
		end
	end
end

function VehicleService.IsEnabled(): boolean
	return enabled
end

-- For the harness: the garage, what is out, and how it is doing.
function VehicleService.Describe(player: Player): string
	local life = dataFor(player)
	if life == nil then
		return "no profile loaded yet"
	end
	local owned: { string } = {}
	for id in life.vehicles.owned do
		table.insert(owned, id)
	end
	table.sort(owned)

	local current = spawned[player]
	local out = "nothing out"
	if current ~= nil then
		out = string.format(
			"%s out, %.1f studs/s, idle %.0fs%s",
			current.chassis.kind.name,
			VehicleChassis.SpeedOf(current.chassis.model.PrimaryPart :: BasePart),
			current.idleFor,
			if isOccupied(current) then " (occupied)" else ""
		)
	end
	return string.format(
		"garage %d/%d: %s | %s | %s",
		#owned,
		VEHICLES.MaxOwned,
		if #owned > 0 then table.concat(owned, ", ") else "empty",
		out,
		if enabled then "on" else "off"
	)
end

function VehicleService:Init()
	RequestBuyVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
		if typeof(vehicleId) ~= "string" then
			return
		end
		VehicleService.Buy(player, vehicleId)
	end)

	RequestSellVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
		if typeof(vehicleId) ~= "string" then
			return
		end
		VehicleService.Sell(player, vehicleId)
	end)

	RequestSpawnVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
		if typeof(vehicleId) ~= "string" then
			return
		end
		VehicleService.Spawn(player, vehicleId)
	end)

	RequestStoreVehicleRemote.OnServerEvent:Connect(function(player: Player)
		VehicleService.Store(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player)
			if profile ~= nil then
				push(player, nil)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		despawn(player)
		spawning[player] = nil
		pushed[player] = nil
	end)
end

function VehicleService:Start()
	task.spawn(function()
		while true do
			local elapsed = task.wait(IDLE_TICK_SECONDS)
			if enabled then
				for player, current in spawned do
					local ok, err = pcall(tickPlayer, player, current, elapsed)
					if not ok then
						warn(`[AGES] vehicle idle tick failed for {player.Name}: {err}`)
					end
				end
			end
		end
	end)
end

return VehicleService
