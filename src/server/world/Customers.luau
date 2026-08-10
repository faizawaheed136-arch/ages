--!strict
-- Somebody waiting on you. Sometimes four of them, one behind the other.
--
-- None of the rules change here: the same marks, the same clock, the same tip. What
-- changes is that "Serve the customer at the till" stops being a sentence on a HUD and
-- becomes a person who walks in, stands across the mark, and looks at you while the
-- clock runs. That look is doing most of the work and it costs nothing -- NPCService
-- has been tracking heads since the first delivery, with no animation uploaded and no
-- asset id filled in.
--
-- Everything about being a person is NPCService's. Everything here is about being a
-- customer, which turns out to be four facts:
--
--   They arrive on their own. Queue() cannot yield, because it is called from the
--   shift tick, and building an avatar is a web-backed call. So it hands back a handle
--   immediately and the people turn up a moment later, one at a time, which is also
--   how it reads: the task appears, and then somebody walks in for it.
--
--   They can be dismissed before they exist. Every yield below is a place the task can
--   be finished, missed or abandoned under us -- an eleven-second clock against a
--   network round trip is not a race worth assuming the outcome of -- so the verdict is
--   recorded per person and each arrival coroutine obeys whatever it finds when it
--   gets there.
--
--   They leave differently depending on how it went, and that difference is the only
--   feedback in this game the player gets from another face. Served: a word and a beat
--   before turning. Missed: they just go.
--
--   A queue has a front. Only the front is being served and only the front says
--   anything, and when they leave the line steps up. That step is the entire progress
--   display for a rush: four people become three become two, and the player never has
--   to look at the HUD to know how they are doing.
--
-- One person is a queue of one. There is deliberately no separate path for the
-- ordinary case -- the till and the rush run the same code, so the shape that gets
-- played once a shift and the shape that gets played every shift are tested together.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local NPCService = require(script.Parent.Parent.services.NPCService)
local Public = require(script.Parent.Parent.content.Public)

type CastMember = Types.CastMember
type Visitor = NPCService.Visitor

local Customers = {}

-- What one person in the line is holding out for. "waiting" is the only state the
-- player can change; the other two are terminal and the first one to be set wins, so
-- somebody served on the same tick the clock expired cannot be sent off twice.
type Verdict = "waiting" | "served" | "left"

type Member = {
	person: Visitor?,
	verdict: Verdict,
	-- Claimed by whichever thread is walking them out. Not tidiness: serving somebody
	-- while they are still walking in sets the verdict from the shift tick *and* wakes
	-- their arrival coroutine on the far side of its walk, and both are then holding a
	-- person to send home.
	departing: boolean,
	-- Where in the line they are standing now, from 1. Changes when the person in
	-- front of them is served, which is the only reason anybody in a queue moves.
	slot: number,
}

export type Customer = {
	-- The front of the line, served in time. They say something and take a beat before
	-- leaving, because vanishing the instant you reach them would undo the reason they
	-- walked in. Everybody behind steps up.
	serve: () -> (),
	-- The clock ran out, or the shift did. Everybody still here goes, with no word and
	-- no beat -- somebody who waited and gave up does not thank you for it, and that
	-- silence is the point.
	giveUp: () -> (),
	-- Gone now, wherever they are in the walk. For a shift ending under them: nobody is
	-- owed an exit animation at the moment the world stops caring.
	destroy: () -> (),
	-- How many are still standing there. The shift loop reads this every tick to put a
	-- number on the HUD row, so it must not yield and must be cheap.
	waiting: () -> number,
}

local SPEECH_TEXT_COLOR = Color3.fromRGB(240, 236, 226)
local SPEECH_STROKE_COLOR = Color3.fromRGB(20, 20, 26)

-- What they say on the way out, having been served.
--
-- Here rather than authored per task, and that is a decision rather than laziness:
-- this line is on screen for ServedBeatSeconds and says nothing about which task it
-- was, so writing ten of them would double the authoring of every customer to vary a
-- word nobody is reading twice. What it has to do is exist, which is the whole point
-- of it -- `talk()` plays an animation clip, and every animation id in this game is
-- still an empty string until the group exists to upload one to. Without a line here,
-- being served and being given up on look exactly the same from across a shop.
local THANKS = { "Thanks!", "Cheers.", "Thank you.", "Ta." }

-- The line floats over them rather than sitting on the mark, so that reading it means
-- looking at the person. Sized in offsets rather than scale: a customer twelve studs
-- away and one across the shop should be equally legible, which is what a shift spent
-- glancing up mid-walk actually needs.
--
-- Returns the whole billboard rather than the label, because every use of it here is
-- short-lived -- the queue's line moves to a new head, the thank-you outlives the
-- person it belongs to by a second and a half -- and destroying and rebuilding is
-- honest where editing text in place would leave one label being passed between two
-- people who are saying different things.
local function speak(visitor: Visitor, line: string): BillboardGui?
	local head = visitor.model:FindFirstChild("Head") :: BasePart?
	if head == nil then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AgesCustomerLine"
	billboard.Size = UDim2.new(0, 220, 0, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, Config.Work.Customers.SpeechHeightStuds, 0)
	billboard.MaxDistance = Config.Work.Customers.SpeechRangeStuds
	billboard.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = SPEECH_TEXT_COLOR
	label.TextStrokeColor3 = SPEECH_STROKE_COLOR
	label.TextStrokeTransparency = 0.2
	label.TextWrapped = true
	label.Text = line
	label.Parent = billboard

	billboard.Parent = head
	return billboard
end

-- Brings a line of people to a task and hands back the ways it can end. Never yields
-- and never fails: if an avatar cannot be built, the handle is still valid and every
-- call on it quietly does nothing, because a task with nobody in it is the task this
-- game shipped with and is not a fault.
--
-- `slots` is where they stand, front first, and its length is how many people there
-- are -- an empty list is a legitimate answer meaning the room had no space, and gives
-- back a handle that does nothing at all. `from` is where they walk in from, nil
-- meaning there was nowhere to come from and they simply appear, and `facing` is the
-- mark, so they are turned toward the player's side of the counter from the first
-- frame.
function Customers.Queue(player: Player, slots: { Vector3 }, from: Vector3?, facing: Vector3, line: string): Customer
	local customers = Config.Work.Customers

	local members: { Member } = {}
	for index = 1, #slots do
		table.insert(members, { person = nil, verdict = "waiting" :: Verdict, departing = false, slot = index })
	end

	-- The queue's one spoken line, and whose head it is currently over. Only the front
	-- says anything: three people all announcing "Just these, thanks" at once is a
	-- chorus, and a queue is not a chorus -- the people behind are waiting, which is a
	-- thing you do silently and is legible precisely because it is silent.
	local lineGui: BillboardGui? = nil
	local lineOwner: Member? = nil

	local function firstWaiting(): Member?
		for _, member in members do
			if member.verdict == "waiting" then
				return member
			end
		end
		return nil
	end

	local function clearLine()
		if lineGui ~= nil then
			lineGui:Destroy()
			lineGui = nil
		end
		lineOwner = nil
	end

	-- Moves the spoken line to whoever is at the front now. Called after a serve and
	-- also at the end of every arrival, because the front of the queue is frequently
	-- somebody who did not exist yet the last time this was asked.
	local function refreshFront()
		local front = firstWaiting()
		if front == lineOwner then
			return
		end
		clearLine()
		if front == nil then
			return
		end
		local person = front.person
		if person == nil or person.gone() then
			return
		end
		lineGui = speak(person, line)
		lineOwner = front
	end

	-- Walks one person out. Yields, so it is always called on its own thread.
	local function depart(member: Member, served: boolean)
		if member.departing then
			return
		end
		member.departing = true

		local person = member.person
		if person == nil then
			return
		end

		if served then
			person.talk()
			-- Their own label, made after the queue's line has already moved on to the
			-- person behind them. Two billboards, briefly, over two different heads,
			-- saying two different things -- which is what a till sounds like.
			local thanks = speak(person, THANKS[math.random(#THANKS)])
			task.wait(customers.ServedBeatSeconds)
			if thanks ~= nil then
				-- Cleared before the walk out. A "Cheers." trailing somebody through the
				-- door is the shop's one chance to look unfinished.
				thanks:Destroy()
			end
		end

		if person.gone() then
			return
		end
		if from ~= nil then
			person.walkTo(from)
		end
		person.destroy()
	end

	-- The queue steps up. Everybody still waiting takes the slot of the person who was
	-- in front of them, which is the whole visual language of a rush: the line is the
	-- progress bar, and it is one nobody has to look away from the room to read.
	local function advance()
		local rank = 0
		for _, member in members do
			if member.verdict ~= "waiting" then
				continue
			end
			rank += 1
			if member.slot == rank then
				continue
			end
			member.slot = rank

			local person = member.person
			if person ~= nil and not person.gone() then
				-- Aimed rather than walked, because this is two and a half studs and the
				-- thread that asked for it is the shift tick. A yielding walk here would
				-- put the length of a shuffle between reaching a mark and the game
				-- noticing you had.
				person.moveTo(slots[rank])
			end
		end

		refreshFront()
	end

	for index, member in members do
		task.spawn(function()
			-- Staggered, so the queue is seen forming rather than found already there.
			-- Also spreads the avatar builds out: four web-backed calls in one frame is
			-- the one place this could be felt as a hitch.
			if index > 1 then
				task.wait(customers.QueueArriveGapSeconds * (index - 1))
			end
			if member.verdict ~= "waiting" then
				return
			end

			local castMember: CastMember = Public.Someone()

			-- Lifted to hip height for the reason PocketMoneyService gives: an R15 model's
			-- pivot is its root part, and putting that on the floor buries them to the
			-- waist. Erring high costs a drop the humanoid absorbs on the first frame.
			local origin = (from or slots[member.slot]) + Vector3.new(0, Config.NPC.BodyHeight / 2, 0)
			local toward = Vector3.new(facing.X - origin.X, 0, facing.Z - origin.Z)
			local pose = if toward.Magnitude > 0.1
				then CFrame.lookAt(origin, origin + toward.Unit)
				else CFrame.new(origin)

			local visitor = NPCService.Spawn(player, castMember, pose)
			if visitor == nil then
				return
			end
			local person = visitor :: Visitor
			-- Handed over before the verdict is read, and the two lines must stay
			-- adjacent. Neither yields, so no other thread can run between them -- which
			-- is the only reason a verdict set in this instant cannot fall down the gap
			-- between a handle that has nobody to dismiss and a coroutine that has
			-- stopped checking.
			member.person = person

			-- Spawn yielded, and the yield is long enough to lose an eleven-second task
			-- inside. Whatever was decided while they were being built is what happens.
			if member.verdict ~= "waiting" then
				depart(member, member.verdict == "served")
				return
			end

			-- Name tags off. The cast wear theirs because knowing it is Mom is the entire
			-- content of that scene; a stranger in a shop wearing "Customer" over their
			-- head is a label on a prop, and the line they say does the same job better.
			local humanoid = person.model:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end

			refreshFront()

			if from ~= nil then
				-- Read at the moment of walking, never captured earlier: somebody ahead of
				-- them may have been served while they were being built, in which case the
				-- place they are heading for has already moved up the line.
				person.walkTo(slots[member.slot])
			end

			-- Checked again on the far side of the walk, which is seconds long and is the
			-- likeliest place of all to be dismissed: a quick player clears the queue
			-- before the back of it has finished crossing the room.
			if member.verdict ~= "waiting" then
				depart(member, member.verdict == "served")
				return
			end

			person.greet()
			-- Again, because the walk yielded and the front may have changed twice while
			-- they were crossing the floor.
			refreshFront()
		end)
	end

	local function settle(member: Member, outcome: Verdict)
		if member.verdict ~= "waiting" then
			return
		end
		member.verdict = outcome

		if member.person == nil then
			-- Still being built. Their arrival coroutine will find this verdict and see
			-- them straight back out, so there is nothing to do here.
			return
		end
		task.spawn(depart, member, outcome == "served")
	end

	return {
		serve = function()
			local front = firstWaiting()
			if front == nil then
				return
			end
			-- Their line goes with them, and it goes first: the person behind is the
			-- front of the queue from this instant, and leaving the old line hanging over
			-- a departing head for a beat and a half would say the queue had not moved.
			if lineOwner == front then
				clearLine()
			end
			settle(front, "served")
			advance()
		end,
		giveUp = function()
			clearLine()
			-- Backwards, so the person at the till leaves last. A queue that empties from
			-- the back is a queue giving up on you, which is exactly what happened.
			for index = #members, 1, -1 do
				settle(members[index], "left")
			end
		end,
		destroy = function()
			clearLine()
			for _, member in members do
				member.verdict = if member.verdict == "waiting" then "left" else member.verdict
				-- Claims the departure as well as the verdict, so a walk-out already under
				-- way on another thread stops where it is rather than finishing a stroll
				-- out of a shop that no longer has anybody working in it.
				member.departing = true

				local person = member.person
				if person ~= nil then
					member.person = nil
					person.destroy()
				end
			end
		end,
		waiting = function(): number
			local left = 0
			for _, member in members do
				if member.verdict == "waiting" then
					left += 1
				end
			end
			return left
		end,
	}
end

return Customers
