--!strict
-- Somebody going about their day.
--
-- A townsperson who stands on a ring around the shop forever is a shop fitting. The
-- difference between a world with people in it and a world with statues in it is
-- almost entirely this file, and it is a small file: walk somewhere, stand there for a
-- bit, walk somewhere else. What makes it read as a person rather than as a patrol is
-- the standing still. A town that never stops moving is a town of couriers.
--
-- Knows nothing about who is walking. It takes a body, the wander that body is partway
-- through, and control of neither -- pause and resume are the caller's, because the
-- reason to stop is always something this file cannot see, and so far that reason is
-- always "you are talking to them".
--
-- **Two things live here, and the split is the important part.** `NextLeg` decides where
-- a townsperson goes next and is the only thing that does; `Start` drives a rig along
-- whatever `NextLeg` says. They are separate because *most townsfolk have no rig*. A
-- person out of the player's range is a position advancing along the same route, stepped
-- by PeopleService rather than walked by Roblox, and when the player comes near enough
-- for a body to be built it picks up the same wander mid-stride. One brain, two ways of
-- moving the legs -- which is what stops a person teleporting when they come into view.
--
-- **Where they can go.** Two tiers, and the first one is optional:
--
--   Town points    A graph of the parts tagged Config.World.TownPointTag; see Routes.
--                  When there is one in reach it wins outright, because a spot somebody
--                  put on a path is a better place to walk to than a spot the arithmetic
--                  found on a lawn. This is what turns wandering into people using the
--                  streets that were actually built.
--   Probed spots   A bearing and a distance off the place they belong to, floor-probed
--                  and clearance-checked before it is walked to. Needs nothing tagged in
--                  Studio and works in a bare world, which is why it is the floor rather
--                  than the fallback -- but it is a much smaller world, bounded by
--                  RoamStuds instead of RangeStuds, because open ground is not a path
--                  and walking a hundred studs of it goes through the flowerbeds.
--
-- **Why the randomness is not seeded.** The town itself is fixed forever -- who exists,
-- what they look like, how old they are -- because bonds are saved against them. Where
-- one of them happens to be standing this second is not that, and must not be: a seeded
-- roam would have thirty people walking the same loop on every server, in step, which
-- is a parade.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local NPCService = require(script.Parent.Parent.services.NPCService)
local Ground = require(script.Parent.Ground)
local Routes = require(script.Parent.Routes)

type Visitor = NPCService.Visitor

local Roam = {}

local TOWN = Config.Town

-- How finely a rest is sliced. Only bounds how quickly a stop or a teardown is
-- noticed while somebody is standing still, so it can be coarse -- but not so coarse
-- that a rig outlives the roster by a visible beat.
local REST_SLICE_SECONDS = 0.25

-- Studio harness switch, and the one thing that tells a walking bug apart from a
-- bonding one. Module-level rather than per walker because "nobody in the town moves"
-- is the question being asked, and asking it of each of them separately would leave
-- whoever was mid-stride still striding.
local enabled = true


-- One townsperson's journey, held by whoever owns them rather than by this file, because
-- it has to outlive their body. A rig is built and destroyed every time the player walks
-- past; the wander is the same wander either side of that, which is the whole reason
-- somebody followed down a street stays where they were going.
export type Wander = {
	-- Which node of the route graph they are heading for, and the one before it. Nil
	-- while they are off the graph entirely, which is where everybody starts and where
	-- everybody stays in a world with nothing tagged.
	node: number?,
	previous: number?,
	-- The place they belong to. The anchor for the leash and for probed spots alike, so
	-- a person can be far from it without ever being unmoored from it.
	home: Vector3,
	rng: Random,
}

-- A probed spot near home. The floor of the whole system: needs nothing tagged and works
-- in a bare world, at the cost of a much smaller world, because a bearing and a distance
-- off a point is only a path by accident.
--
-- The distance floor is doing real work. Without it somebody standing near home picks a
-- spot about where they already are and spends the afternoon deciding to stay put, which
-- looks far more broken than standing still does.
local function probedSpot(home: Vector3, at: Vector3, rng: Random): Vector3?
	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight
	for _ = 1, TOWN.RoamAttempts do
		local bearing = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(TOWN.MinLegStuds, TOWN.RoamStuds)
		local candidate = home + Vector3.new(math.cos(bearing) * distance, 0, math.sin(bearing) * distance)
		if Ground.FlatDistance(candidate, at) < TOWN.MinLegStuds then
			continue
		end

		-- The same probes every system here runs before putting a body somewhere. Cheap,
		-- and the alternative is asking PathfindingService for a route to the inside of a
		-- wall and taking the refusal as an answer about the walker.
		--
		-- No reachability, deliberately: a roamer walking to the next leg of its wander
		-- is going to be pathfound there anyway, and the pathfinder is the better judge
		-- of a route than one straight line ever is. The two probes here are only asking
		-- whether the destination is a real place, not how to get to it.
		local ignore = Ground.IgnoreList()
		local floor = Ground.SpotAt(candidate, radius, height, ignore)
		if floor == nil then
			continue
		end
		return floor
	end

	return nil
end

-- Somewhere worth walking to from where they are now, or nil if nothing was found and
-- the rest should simply run again. Advances the wander as a side effect, which is why
-- both the bodied and the bodiless call this rather than each keeping their own idea of
-- where somebody had got to.
function Roam.NextLeg(wander: Wander, at: Vector3): Vector3?
	local node, target = Routes.Step(wander.node, wander.previous, at, wander.home, wander.rng)
	if target ~= nil then
		wander.previous = wander.node
		wander.node = node
		return target
	end

	-- No graph in reach. Off the graph they go, so that the next leg re-joins it at
	-- whatever is nearest rather than resuming from a node they have since walked away
	-- from -- which is what makes tagging a point mid-session take effect.
	wander.previous = nil
	wander.node = nil
	return probedSpot(wander.home, at, wander.rng)
end

-- One walker's wandering, and every way it can be interrupted.
export type Roam = {
	-- Stop where you stand and start nothing new. What being spoken to does. Does not
	-- turn them -- that is the caller's, because only the caller knows who to turn to.
	pause: () -> (),
	resume: () -> (),
	-- For good. The body is the caller's to destroy; this only stops the loop asking it
	-- to walk, which has to happen first or the next leg is issued against a rig that
	-- is halfway through being taken down.
	stop: () -> (),
	-- What they are doing right now, for the harness. A word rather than a set of
	-- booleans, because the question `/town` is asking is "why is this one not moving"
	-- and every answer to it is one of these.
	state: () -> string,
}

-- `resume` is the leg they were already on when the body was built, and passing it is what
-- makes coming into view seamless rather than merely non-teleporting. Without it the loop
-- below opens with a rest, so somebody who has been walking across town for a minute stops
-- dead for up to eleven seconds at the exact moment the player can first see them -- which
-- is a worse artefact than the one this whole system was built to remove. Nil for anybody
-- who was standing still anyway, and for the very first body of a session.
function Roam.Start(visitor: Visitor, wander: Wander, resume: Vector3?): Roam
	local rng = wander.rng
	local stopped = false
	local paused = false
	local walking = false

	visitor.setSpeed(TOWN.WalkSpeed)

	local function shouldStop(): boolean
		return stopped or paused or not enabled or visitor.gone()
	end

	local function state(): string
		if stopped then
			return "stopped"
		end
		if visitor.gone() then
			return "gone"
		end
		if not enabled then
			return "off"
		end
		if paused then
			return "held"
		end
		return if walking then "walking" else "resting"
	end

	task.spawn(function()
		-- Set only for the first pass, so a resumed walker skips the rest and carries on.
		-- Every pass after that finds it nil and rests first, which is the ordinary rhythm.
		local pending = resume
		while not stopped and not visitor.gone() do
			if pending == nil then
				-- Standing about. Sliced rather than waited out in one go so a teardown
				-- lands within a quarter second instead of within eleven.
				local rest = rng:NextNumber(TOWN.PauseMinSeconds, TOWN.PauseMaxSeconds)
				local waited = 0
				while waited < rest and not stopped and not visitor.gone() do
					waited += task.wait(REST_SLICE_SECONDS)
				end
				if stopped or visitor.gone() then
					break
				end

				-- Held, or switched off. The rest simply runs again: somebody who is being
				-- spoken to should not be counting down to walking away from you, and the
				-- loop coming back around is what makes resuming cost nothing.
				if paused or not enabled then
					continue
				end

				pending = Roam.NextLeg(wander, visitor.at())
			end

			-- Taken out of `pending` before the walk rather than after, so a leg that gets
			-- called off partway is not retried forever: the answer to a failed walk is a
			-- rest and somewhere else, not the same doorway again.
			local leg = pending
			pending = nil
			if leg == nil then
				continue
			end

			walking = true
			-- The result is deliberately ignored. A walk that was called off, or that
			-- ran into something, is not a failure worth doing anything about -- the
			-- answer to both is to stand still for a bit and then try somewhere else,
			-- which is what the top of this loop already does.
			visitor.pathTo(leg, shouldStop)
			walking = false
		end
		walking = false
	end)

	return {
		pause = function()
			paused = true
			visitor.halt()
		end,
		resume = function()
			paused = false
		end,
		stop = function()
			stopped = true
		end,
		state = state,
	}
end

function Roam.SetEnabled(value: boolean)
	enabled = value
end

function Roam.IsEnabled(): boolean
	return enabled
end

return Roam
