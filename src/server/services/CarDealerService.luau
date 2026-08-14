--!strict
-- The car dealership queue. Customers line up at the showroom counter and the player
-- serves them whether they are working a shift there or just walking past.
--
-- This runs alongside WorkService's shift queue at auto_dealer. When a car_salesperson
-- shift is active, that queue takes priority and the walk-in queue pauses. When no
-- shift is running, the walk-in queue keeps the place feeling alive.
--
-- The queue uses Customers.Queue and WorkSpots.Line from the existing work system —
-- same arrival stagger, same spacing math, same thanks-on-depart. What changes is
-- the dialogue (car-buying lines instead of shop lines) and the trigger (distance to
-- the counter rather than a task mark).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Customers = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Customers"))
local Ground = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Ground"))
local MoneyService = require(script.Parent.MoneyService)
local PlaceService = require(script.Parent.PlaceService)
local WorkService = require(script.Parent.WorkService)

type LifeData = Types.LifeData
type Customer = Customers.Customer
type Visitor = Types.Visitor

local CarDealer = {}

local CAR_DEALER = Config.CarDealer
local carDealerUpdated = Remotes.Get("CarDealerUpdated")
local requestCarDealerServe = Remotes.Get("RequestCarDealerServe")

-- Which customer is at the front of the line right now. Kept so the service can
-- answer questions about the queue without rebuilding it from scratch.
type QueueMember = {
	customer: Customer,
	slots: { Vector3 },
	from: Vector3?,
	counter: Vector3,
	line: string,
}

-- Per-player queue state. A player can only interact with one dealership at a time
-- (there is only one anyway), so this is keyed by player.
type DealerState = {
	queue: QueueMember?,
	lastArrival: number,
}

local states: { [Player]: DealerState } = {}

-- What a waiting customer says when they step up to the counter. Drawn from a pool
-- so the same face does not repeat the same line twice in a row.
local GREETINGS = {
	"I've been waiting. Got the new models yet?",
	"My wife said I should look at something reliable.",
	"I'm ready to buy if the price is right.",
	"Do you have anything in blue? My daughter loves blue.",
	"I test-drove one last week. Want to see if it still runs.",
	"My friend said this place is the best in town. Let's see.",
	"I need something for the commute. Nothing fancy.",
	"Is this the place where you help people pick cars?",
}

local THANKS = {
	"Looks great, thanks for the help!",
	"I'll be back with my wife to pick it up!",
	"Thanks — she's gonna love this one.",
	"Appreciate it. Drive safe, everybody.",
	"Nice work. See you next time.",
}

local function randomFrom(t: { string }): string
	return t[math.random(#t)]
end

local function stateFor(player: Player): DealerState
	local mine = states[player]
	if mine == nil then
		mine = { queue = nil, lastArrival = 0 }
		states[player] = mine
	end
	return mine
end

-- Whether the player is currently working a shift at the auto_dealer. If so, the
-- shift queue owns the counter and the walk-in queue should not interfere.
local function isWorkingAtDealer(player: Player): boolean
	local profile = require(ReplicatedStorage:WaitForChild("DataService")).GetProfile(player)
	if profile == nil then
		return false
	end
	local data = require(ReplicatedStorage:WaitForChild("Lives")).Active(profile.Data)
	if not data.alive then
		return false
	end
	return WorkService.IsWorkingAt(player, "auto_dealer")
end

-- Find or refresh the queue for this player. Called on every tick and when the
-- player enters the area. Rebuilds the spots from the place point each time so
-- a rebuilt city does not leave stale queue positions.
local function ensureQueue(player: Player)
	local mine = stateFor(player)
	-- Shift queue owns the counter; clear any walk-in queue while working.
	if isWorkingAtDealer(player) then
		if mine.queue ~= nil then
			mine.queue.customer.destroy()
			mine.queue = nil
			carDealerUpdated:FireClient(player, { waiting = 0, counter = nil, greeting = nil, served = false })
		end
		return
	end
	local place = PlaceService.Find("auto_dealer")
	if place == nil then
		if mine.queue ~= nil then
			mine.queue.customer.destroy()
			mine.queue = nil
		end
		return
	end

	local station = place.part.Position
	-- The counter is the first spot across the mark from the station. We find it
	-- by fanning out from the station and taking the first reachable spot, then
	-- placing the queue behind it.
	local ignore = Ground.IgnoreList()
	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight

	-- Find a counter position: a few studs beyond the station, on the side the
	-- player would approach from (south, since the dealership faces the street).
	local counter: Vector3? = nil
	for _, bearing in Ground.Bearings(180, 8) do
		local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
		local candidate = station + direction * 5
		local floor = Ground.SpotAt(candidate, radius, height, ignore, station)
		if floor ~= nil then
			counter = floor
			break
		end
	end

	if counter == nil then
		if mine.queue ~= nil then
			mine.queue.customer.destroy()
			mine.queue = nil
		end
		return
	end

	-- Build the queue slots behind the counter.
	local count = math.min(CAR_DEALER.MaxQueue, 3)
	local slots: { Vector3 } = {}
	local away = Vector3.new(counter.X - station.X, 0, counter.Z - station.Z)
	local outward = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, -1)

	-- Front slot: across the counter from the station.
	local frontFloor = Ground.SpotAt(counter + outward * Config.Work.Customers.StandOffStuds, radius, height, ignore, counter)
	if frontFloor == nil then
		if mine.queue ~= nil then
			mine.queue.customer.destroy()
			mine.queue = nil
		end
		return
	end
	table.insert(slots, frontFloor)

	-- Behind slots.
	for index = 2, count do
		local behind = frontFloor + outward * (Config.Work.Customers.QueueSpacingStuds * (index - 1))
		local floor = Ground.SpotAt(behind, radius, height, ignore, slots[index - 1])
		if floor == nil then
			break
		end
		table.insert(slots, floor)
	end

	if #slots == 0 then
		if mine.queue ~= nil then
			mine.queue.customer.destroy()
			mine.queue = nil
		end
		return
	end

	-- Find where they walk in from.
	local last = slots[#slots]
	local fromFloor = Ground.SpotAt(last + outward * Config.Work.Customers.ArriveFromStuds, radius, height, ignore, last)

	-- Preserve the existing queue if it is still valid; otherwise replace it.
	local line = randomFrom(GREETINGS)
	if mine.queue ~= nil then
		local existing = mine.queue
		-- If the counter moved significantly, tear down and rebuild.
		if Ground.FlatDistance(existing.counter, counter) > 5 then
			existing.customer.destroy()
			mine.queue = nil
		end
	end

	if mine.queue == nil then
		local customer = Customers.Queue(player, slots, fromFloor, counter, line)
		mine.queue = {
			customer = customer,
			slots = slots,
			from = fromFloor,
			counter = counter,
			line = line,
		}
		mine.lastArrival = os.clock()
	else
		-- Update positions if the counter shifted.
		local existing = mine.queue
		if Ground.FlatDistance(existing.counter, counter) > 2 then
			existing.customer.destroy()
			local customer = Customers.Queue(player, slots, fromFloor, counter, line)
			existing.customer = customer
			existing.slots = slots
			existing.from = fromFloor
			existing.counter = counter
			existing.line = line
			mine.lastArrival = os.clock()
		end
	end

	-- Push the current state to the client.
	carDealerUpdated:FireClient(player, {
		waiting = mine.queue.customer.waiting(),
		counter = mine.queue.counter,
		greeting = mine.queue.line,
		served = false,
	})
end

-- Serve the front customer. Called when the player reaches the counter.
local function serveFront(player: Player)
	local mine = stateFor(player)
	if mine.queue == nil then
		return
	end

	local customer = mine.queue.customer
	local waiting = customer.waiting()
	if waiting == 0 then
		return
	end

	customer.serve()

	-- Pay a tip for the walk-in service.
	MoneyService.Add(player, CAR_DEALER.ServeTip, "car dealership tip")

	-- Say thanks.
	local thanks = randomFrom(THANKS)
	mine.queue.line = thanks

	-- Push update.
	carDealerUpdated:FireClient(player, {
		waiting = customer.waiting(),
		counter = mine.queue.counter,
		greeting = mine.queue.line,
		served = true,
	})
end

-- Schedule the next customer arrival if the queue has room.
local function maybeArrive(player: Player)
	local mine = stateFor(player)
	local now = os.clock()
	if now - mine.lastArrival < CAR_DEALER.CustomerGapSeconds then
		return
	end

	local place = PlaceService.Find("auto_dealer")
	if place == nil then
		return
	end

	local station = place.part.Position
	local ignore = Ground.IgnoreList()
	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight

	local away = Vector3.new(station.X, 0, station.Z)
	local outward = Vector3.new(0, 0, -1) -- face south, toward the street

	-- Find counter.
	local counter: Vector3? = nil
	for _, bearing in Ground.Bearings(180, 8) do
		local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
		local candidate = station + direction * 5
		local floor = Ground.SpotAt(candidate, radius, height, ignore, station)
		if floor ~= nil then
			counter = floor
			break
		end
	end

	if counter == nil then
		return
	end

	local slots: { Vector3 } = {}
	local frontFloor = Ground.SpotAt(counter + outward * Config.Work.Customers.StandOffStuds, radius, height, ignore, counter)
	if frontFloor ~= nil then
		table.insert(slots, frontFloor)
		for index = 2, CAR_DEALER.MaxQueue do
			local behind = frontFloor + outward * (Config.Work.Customers.QueueSpacingStuds * (index - 1))
			local floor = Ground.SpotAt(behind, radius, height, ignore, slots[index - 1])
			if floor == nil then
				break
			end
			table.insert(slots, floor)
		end
	end

	if #slots == 0 then
		return
	end

	local last = slots[#slots]
	local fromFloor = Ground.SpotAt(last + outward * Config.Work.Customers.ArriveFromStuds, radius, height, ignore, last)

	local line = randomFrom(GREETINGS)
	local customer = Customers.Queue(player, slots, fromFloor, counter, line)

	mine.queue = {
		customer = customer,
		slots = slots,
		from = fromFloor,
		counter = counter,
		line = line,
	}
	mine.lastArrival = now

	carDealerUpdated:FireClient(player, {
		waiting = customer.waiting(),
		counter = counter,
		greeting = line,
		served = false,
	})
end

function CarDealer:Init()
	requestCarDealerServe.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(serveFront, player)
		if not ok then
			warn(`[AGES] car dealer serve failed for {player.Name}: {err}`)
		end
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			ensureQueue(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local mine = states[player]
		if mine ~= nil and mine.queue ~= nil then
			mine.queue.customer.destroy()
		end
		states[player] = nil
	end)
end

function CarDealer:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			ensureQueue(player)
		end)
	end

	task.spawn(function()
		while true do
			task.wait(CAR_DEALER.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					-- Refresh queue spots in case the city was rebuilt.
					ensureQueue(player)
					-- Check for new arrivals.
					maybeArrive(player)
				end)
				if not ok then
					warn(`[AGES] car dealer tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return CarDealer
