--!strict
-- Walking with somebody.
--
-- The answer to an offer that says "come with me" (see PersonOffer.walksTo). The
-- person sets off with you, trails the exact path you walk, and says something when
-- the place is reached. Nothing here knows about people or offers: PeopleService
-- hands in the visitor it already has stood up, the roam handle to pause, and the
-- line to say, and gets one callback when the walk is over. That is the whole
-- contract, and it is why any future NPC needs no new code -- anybody with a body
-- can be walked with.
--
-- The move is the pocket-money chase, unchanged in kind: a humanoid holds the last
-- destination it was given, so a moving target is a re-aim on a tick rather than
-- anything cleverer. The one thing that makes this a walk rather than a chase is
-- the aim point -- always just behind the player -- so the companion cuts no corners
-- and takes the same route the player does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local PlaceService = require(script.Parent.PlaceService)
local NPCService = require(script.Parent.NPCService)
local Ground = require(script.Parent.Parent.world.Ground)

type Visitor = NPCService.Visitor
type Place = Types.Place

-- The piece of a roamer that can be paused and resumed. Typed structurally rather
-- than by requiring Roam, so this module stays out of that require chain -- it only
-- ever needs these two calls, and Roam.Roam has both.
type RoamHandle = {
	pause: () -> (),
	resume: () -> (),
}

-- One walk. The state is small because the walk is: who is walking, where they are
-- headed, and how it ends.
type Companion = {
	visitor: Visitor,
	roam: RoamHandle?,
	place: Place,
	arrivalLine: string,
	sayName: string,
	onEnd: () -> (),
	stopped: boolean,
	finished: boolean,
}

local NoticeRemote = Remotes.Get("Notice")

local active: { [Player]: Companion } = {}

local CompanionService = {}

-- A walk that never starts because the world jumped sideways is not a walk that
-- ended. This is simply how far apart two people on the same street can be while
-- still meaning to be together; above it, something moved that is not walking.
local MAX_SEPARATION_STUDS = 60

-- The one way a walk leaves the world, so no path has to remember to tidy up.
-- Safe to call twice -- the second call is the loop noticing a stop it was already
-- told about, and it must not resume the roam or fire the callback again.
local function finish(player: Player)
	local companion = active[player]
	if companion == nil or companion.finished then
		return
	end
	companion.finished = true
	companion.stopped = true
	active[player] = nil

	if not companion.visitor.gone() then
		-- Let go of the held face before the roam takes them back, or they walk
		-- sideways until the next thing tells them which way is forward.
		companion.visitor.face(nil)
	end
	if companion.roam ~= nil then
		companion.roam.resume()
	end
	companion.onEnd()
end

local function follow(player: Player, companion: Companion)
	local cfg = Config.People.Companion
	local elapsed = 0

	while not companion.stopped do
		-- The rig went out from under the walk -- a sweep, a life ending. The person
		-- service's teardown already knows; there is nothing left here to tidy.
		if companion.visitor.gone() then
			finish(player)
			return
		end

		local character = player.Character
		local root = character ~= nil and character:FindFirstChild("HumanoidRootPart")
		if root == nil then
			-- No body to follow. Ending the walk is honest: it cannot continue, and
			-- the caller's teardown already knows the person is going away.
			finish(player)
			return
		end

		local here = companion.visitor.at()
		local you = root.Position

		-- The walk's one destination. Stopping there is the point of it.
		if Ground.FlatDistance(you, companion.place.part.Position) <= cfg.ArriveRadiusStuds then
			companion.visitor.halt()
			companion.visitor.face(you)
			if companion.arrivalLine ~= "" then
				NoticeRemote:FireClient(player, `{companion.sayName}: {companion.arrivalLine}`)
			end
			task.wait(Config.People.ReplySeconds)
			finish(player)
			return
		end

		-- The player teleported or the recovery harness snapped the world sideways.
		-- Nothing on the street bridges that, so the walk ends rather than re-aiming
		-- at a point across the map.
		if Ground.FlatDistance(here, you) > MAX_SEPARATION_STUDS then
			finish(player)
			return
		end

		-- Standing together. If the player is stopped and the companion is right
		-- behind them, wait with them instead of jittering in place; the moment the
		-- player moves again the next tick's re-aim takes over.
		local standingStill = root.AssemblyLinearVelocity.Magnitude < 0.5
		if standingStill and Ground.FlatDistance(here, you) <= cfg.FollowBehindStuds + 1 then
			companion.visitor.halt()
			companion.visitor.face(you)
		else
			local target = you - root.CFrame.LookVector * cfg.FollowBehindStuds
			companion.visitor.moveTo(Vector3.new(target.X, here.Y, target.Z))
		end

		elapsed += task.wait(cfg.FollowTickSeconds)
		if elapsed > cfg.MaxWalkSeconds then
			finish(player)
			return
		end
	end

	-- The loop only leaves on stopped, which is already finished.
	finish(player)
end

-- Start a person walking with the player to a place.
--
-- `visitor` is the person's own body -- the one the player was just talking to --
-- so no double of anybody is ever spawned and there is no ownership to hand back
-- when the walk ends. `roam` is their wander handle, paused for the walk and
-- resumed at the end. `onEnd` fires exactly once, however the walk ends: arrival,
-- timeout, the player talking to somebody, death, or a teleport.
function CompanionService.Start(
	player: Player,
	visitor: Visitor,
	roam: RoamHandle?,
	placeId: string,
	arrivalLine: string,
	sayName: string,
	onEnd: () -> ()
): boolean
	if active[player] ~= nil then
		return false
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local data = Lives.Active(profile.Data)
	if not data.alive then
		return false
	end
	-- Below the age the player takes the wheel, a life is driven by the safety net
	-- and does not walk itself anywhere. Companion offers author far above this, so
	-- the check is a backstop rather than a rule.
	if data.ageMonths < Config.ManualAgeUpMinAge * Config.Time.MonthsPerYear then
		return false
	end
	local place = PlaceService.Find(placeId)
	if place == nil then
		warn(`[AGES] companion walk to "{placeId}" found no place point`)
		return false
	end
	if visitor.gone() then
		return false
	end

	if roam ~= nil then
		roam.pause()
	end
	active[player] = {
		visitor = visitor,
		roam = roam,
		place = place,
		arrivalLine = arrivalLine,
		sayName = sayName,
		onEnd = onEnd,
		stopped = false,
		finished = false,
	}
	task.spawn(follow, player, active[player])
	return true
end

-- End the walk where it is. The companion is left standing where they stopped --
-- the roam resumes and they go back to their day -- and the callback fires once.
function CompanionService.Dismiss(player: Player)
	finish(player)
end

function CompanionService:Init()
	Players.PlayerRemoving:Connect(function(player)
		finish(player)
	end)
end

function CompanionService:Start() end

return CompanionService
