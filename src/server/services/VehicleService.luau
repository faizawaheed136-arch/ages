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
local Workspace = game:GetService("Workspace")

local CarBody = require(ReplicatedStorage:WaitForChild("CarBody"))
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
local RequestCustomizeVehicleRemote = Remotes.Get("RequestCustomizeVehicle")
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

-- A line the panel should have shown, held for a player who was not standing in
-- the showroom when it happened.
--
-- There is exactly one way to get one: a car left empty long enough returns to the
-- lot on its own, and the sentence that says so is generated while the player is
-- somewhere else by definition. Every other notice in this file answers a button
-- that only exists on the panel, so the player is on the lot already.
--
-- Held rather than dropped because a dropped one is a silent failure of the kind
-- this project's rules name outright -- your car is gone, nothing ever said why, and
-- the next time you look for it you conclude the game lost it. Held rather than
-- shown through some other channel because a floating toast for this is a second
-- notification system built to carry one sentence.
local pendingNotice: { [Player]: string } = {}

local function dataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

-- Forward declaration -- push is defined below stateFor, which reads `spawned`
-- and `dataFor`, both already in scope. Declared here for the same reason
-- GangService declares `push` ahead of `checkEscape`: a name used with no
-- `local` in front of it compiles to a global read, which is legal Luau, builds
-- clean, and dies the first time anybody actually buys a car.
local push: (player: Player, notice: string?) -> ()

-- Meridian Motors' shop, once DealershipService is running: whether a player is standing at its buy
-- desk, and if so the ground a car they bring out should stand on -- a free test-drive bay, nose to
-- the road -- or nil when every bay is taken. Handed in through SetShop rather than required,
-- because DealershipService requires this file. The shop is a second way onto the lot: its car list
-- is this file's state, so a player at the desk is on the showroom as much as one at the
-- auto_dealer counter is.
local shopAt: ((player: Player) -> (boolean, CFrame?))? = nil

-- Whether this player is standing on the dealership's lot.
--
-- Asked on a loop, and `PlaceService.Find` is built for that -- it warns once per
-- missing id rather than once per call, and says so in its own header. If the
-- dealership is not in the world at all this returns false forever and the showroom
-- never opens, which is the honest answer: there is no dealership to be at.
--
-- Measured off `HumanoidRootPart` rather than off the model's pivot, because a
-- character being rebuilt has a pivot at the origin for a frame or two, and the
-- origin is a long way from the lot -- which would close the panel under a player
-- who had not moved.
local function atCounter(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	local place = PlaceService.Find(PLACE_ID)
	if place == nil then
		return false
	end
	return (root.Position - place.part.Position).Magnitude <= VEHICLES.ShowroomStuds
end

-- At Meridian's buy desk (see `shopAt`).
local function atShop(player: Player): boolean
	return shopAt ~= nil and (shopAt(player)) == true
end

local function atShowroom(player: Player): boolean
	return atCounter(player) or atShop(player)
end

-- The showroom as the client should see it, or nil for "there is no showroom here".
--
-- **The distance check is the whole of the fix for the panel that never went away.**
-- A nil state is what tells `VehicleUI` to stop existing, and before this there was
-- no path to nil for a living player: the panel was pushed on join and stayed up for
-- the rest of the life, advertising cars from inside a pram. Gating here rather than
-- in `push` means every caller gets it for free and none of them has to remember.
--
-- Deliberately *not* also gating `Buy`, `Sell`, `Spawn` and `Store`. Those are
-- server-authoritative already and the panel is the only thing that can reach them,
-- so a second check would add nothing except a race: walk off the lot while a buy is
-- in flight and the money is gone with no car to show for it. The gate is about what
-- is on screen, and it is kept to that.
local function stateFor(player: Player, notice: string?): VehicleState?
	local life = dataFor(player)
	if life == nil then
		return nil
	end
	local counter = atCounter(player)
	local shop = not counter and atShop(player)
	if not counter and not shop then
		return nil
	end
	return {
		atShop = if shop then true else nil,
		catalog = Vehicles.All,
		owned = life.vehicles.owned,
		active = life.vehicles.active,
		paint = life.vehicles.paint,
		rims = life.vehicles.rims,
		glow = life.vehicles.glow,
		busy = spawning[player] == true,
		notice = notice,
	}
end

function push(player: Player, notice: string?)
	local state = stateFor(player, notice)
	local digest: string
	if state == nil then
		-- Nowhere to show it right now. Keep the sentence rather than firing it into
		-- a hidden panel; the showroom tick hands it over the moment the player is
		-- back on the lot. Only the last one is kept -- these are statements about
		-- where your car is, and an older one is simply wrong by then.
		if notice ~= nil then
			pendingNotice[player] = notice
		end
		digest = "none"
	else
		local owned: { string } = {}
		for id in state.owned do
			table.insert(owned, id)
		end
		table.sort(owned)
		local paints: { string } = {}
		for tag, map in { p = state.paint, r = state.rims, g = state.glow } do
			for id, key in map or {} do
				table.insert(paints, `{tag}{id}={key}`)
			end
		end
		table.sort(paints)
		digest = `{table.concat(owned, ",")}|{table.concat(paints, ",")}|{tostring(state.active)}|{tostring(state.busy)}|{tostring(state.notice)}`
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
local function spawnActive(player: Player, vehicleId: string, drive: boolean?): boolean
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
	-- At Meridian's desk the car comes out on a test-drive bay; anywhere else, beside the
	-- auto_dealer counter as it always has.
	local atShop, bay = false, nil
	if shopAt ~= nil then
		atShop, bay = shopAt(player)
	end
	if atShop and bay == nil then
		push(player, "Both bays out front are taken. Try again in a moment.")
		return false
	end
	local place = PlaceService.Find(PLACE_ID)
	if bay == nil and place == nil then
		return false
	end

	spawning[player] = true
	push(player, nil)

	local spot = if bay then bay.Position else findParkSpot((place :: any).part.Position)
	if spot == nil then
		spawning[player] = false
		push(player, "There is nowhere to park it right now.")
		return false
	end

	-- Whatever was out comes in first, so there is never a moment with two of a
	-- life's cars standing in the world at once.
	despawn(player)

	local facing = if bay then bay.LookVector else (place :: any).part.Position - spot
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local look = if flat.Magnitude > 0.01 then flat.Unit else -Vector3.zAxis
	-- Its hull at the height it rides at, a hair over, so it settles onto its springs rather than
	-- dropping onto them.
	local lift = CarBody.Layout(kind).hullY + 0.1
	local cframe = CFrame.lookAt(spot + Vector3.new(0, lift, 0), spot + Vector3.new(0, lift, 0) + look)

	local vehicles = life.vehicles
	local look = CarBody.LookOf((vehicles.paint or {})[vehicleId], (vehicles.rims or {})[vehicleId], (vehicles.glow or {})[vehicleId])
	local chassis = VehicleChassis.Build(kind, cframe, nil, look)
	-- Into the world. Nothing did this: Build hands back an unparented model, so a bought car was
	-- paid for, recorded as owned and marked active, and never appeared anywhere.
	chassis.model.Parent = Workspace
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
	-- DRIVE from the shop: the player is put at the wheel, as a test drive puts them.
	if drive and bay then
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid and humanoid.Health > 0 then
			chassis.seatDriver(humanoid)
		end
	end
	return true
end

-- Keeps a car's chosen look -- CarBody paint, rim and underglow keys -- dropping any key the shop
-- does not offer, which leaves that part as the car came.
local function keepLook(life: LifeData, vehicleId: string, paintKey: string?, rimKey: string?, glowKey: string?)
	local vehicles = life.vehicles
	local paints, rims, glows = vehicles.paint or {}, vehicles.rims or {}, vehicles.glow or {}
	local paint, rim, glow = CarBody.Paint(paintKey), CarBody.Rim(rimKey), CarBody.Glow(glowKey)
	paints[vehicleId] = if paint then paint.key else nil
	rims[vehicleId] = if rim then rim.key else nil
	glows[vehicleId] = if glow then glow.key else nil
	vehicles.paint, vehicles.rims, vehicles.glow = paints, rims, glows
end

-- Buys a car outright, in the look the shop showed it in (CarBody paint, rim and underglow keys;
-- nil for as it came). Returns whether it happened; a refusal is always said in the pushed notice,
-- because a buy button that quietly did nothing is indistinguishable from the panel being broken.
function VehicleService.Buy(player: Player, vehicleId: string, paintKey: string?, rimKey: string?, glowKey: string?): boolean
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
	if not MoneyService.Spend(player, kind.price, `bought a {kind.name}`) then
		push(player, `{Money.Format(kind.price)} for the {kind.name}.`)
		return false
	end

	life.vehicles.owned[vehicleId] = true
	keepLook(life, vehicleId, paintKey, rimKey, glowKey)
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
	keepLook(life, vehicleId, nil, nil, nil)
	push(player, `Sold the {kind.name} for {Money.Format(refund)}.`)
	return true
end

-- Changes an owned car's look: the shop's CUSTOMIZE. Free -- the car is already paid for, and a
-- paint shop's bill is not a decision anybody enjoys making. If it is the car out on the road it is
-- rebuilt in its new look where the dealership parks cars.
function VehicleService.Customize(player: Player, vehicleId: string, paintKey: string?, rimKey: string?, glowKey: string?): boolean
	local life = dataFor(player)
	if life == nil or not life.alive or life.vehicles.owned[vehicleId] ~= true then
		return false
	end
	keepLook(life, vehicleId, paintKey, rimKey, glowKey)
	push(player, "New look saved.")
	if life.vehicles.active == vehicleId then
		task.spawn(spawnActive, player, vehicleId)
	end
	return true
end

-- Brings an owned car out of the garage.
function VehicleService.Spawn(player: Player, vehicleId: string): boolean
	if not enabled then
		return false
	end
	local ok = spawnActive(player, vehicleId, true)
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

-- Called by DealershipService once, at Init: see `shopAt`.
function VehicleService.SetShop(at: (player: Player) -> (boolean, CFrame?))
	shopAt = at
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
		"garage %d: %s | %s | %s",
		#owned,
		if #owned > 0 then table.concat(owned, ", ") else "empty",
		out,
		if enabled then "on" else "off"
	)
end

function VehicleService:Init()
	local function key(value: any): string?
		return if typeof(value) == "string" then value else nil
	end
	RequestBuyVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any, paintKey: any, rimKey: any, glowKey: any)
		if typeof(vehicleId) ~= "string" then
			return
		end
		VehicleService.Buy(player, vehicleId, key(paintKey), key(rimKey), key(glowKey))
	end)

	RequestCustomizeVehicleRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any, paintKey: any, rimKey: any, glowKey: any)
		if typeof(vehicleId) ~= "string" then
			return
		end
		VehicleService.Customize(player, vehicleId, key(paintKey), key(rimKey), key(glowKey))
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
		pendingNotice[player] = nil
	end)
end

function VehicleService:Start()
	-- Who is standing on the lot. Walking on and off is the only thing in this game
	-- that opens and closes the showroom, and neither is an event anything fires --
	-- so it is polled. Cheap by construction: `push` folds the state to a digest and
	-- sends nothing when it has not changed, so a server full of people nowhere near
	-- the dealership costs one distance test each and no network traffic at all.
	--
	-- Separate from the idle tick below rather than folded into it. That one runs
	-- every two seconds because a car's parking timer does not care, and two seconds
	-- of standing on a forecourt looking at nothing is exactly the lag that reads as
	-- the dealership being broken.
	task.spawn(function()
		while true do
			task.wait(VEHICLES.ShowroomTickSeconds)
			if not enabled then
				continue
			end
			for _, player in Players:GetPlayers() do
				local waiting = pendingNotice[player]
				if waiting ~= nil and atShowroom(player) then
					pendingNotice[player] = nil
					push(player, waiting)
				else
					push(player, nil)
				end
			end
		end
	end)

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
