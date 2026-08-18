--!strict
-- Merges the event content modules into one table and validates them at server
-- start. A content mistake is an authoring bug, not a runtime condition, so
-- these throw immediately and loudly rather than quietly dropping an entry that
-- would then never fire and never be missed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Delivery = require(ReplicatedStorage:WaitForChild("Delivery"))

local Cast = require(script.Parent.Cast)
local Flags = require(script.Parent.Flags)
local Jobs = require(script.Parent.Jobs)
local Props = require(script.Parent.Props)
local Ribbons = require(script.Parent.Ribbons)
local Subjects = require(script.Parent.Subjects)
local Ties = require(script.Parent.Ties)

type LifeEvent = Types.LifeEvent
type PropPlacement = Types.PropPlacement

local SOURCES: { { LifeEvent } } = {
	require(script.Childhood),
	require(script.School),
	require(script.Teen),
	require(script.Adult),
	require(script.Gym),
	require(script.Park),
	require(script.Ambient),
	require(script.Work),
	require(script.Debt),
	require(script.CareerBranch),
	require(script.Ties),
}

-- One option is not a choice.
local MIN_CHOICES = 2

local all: { LifeEvent } = {}
local byId: { [string]: LifeEvent } = {}

local function validate(event: LifeEvent)
	if byId[event.id] ~= nil then
		error(`[AGES content] duplicate event id "{event.id}"`)
	end
	if event.minAge > event.maxAge then
		error(`[AGES content] event "{event.id}" has minAge above maxAge`)
	end

	-- Cooldowns are real seconds; a negative or fractional value is the same
	-- kind of unit mistake a float below zero would be, and the upper bound
	-- catches a number authored in game minutes before it ever reaches the
	-- picker. Nil means 0 — the default is the same as today.
	local cooldown = event.cooldown
	if cooldown ~= nil then
		if cooldown < 1 or cooldown ~= math.floor(cooldown) or cooldown > Config.Events.MaxCooldownSeconds then
			error(
				`[AGES content] event "{event.id}" has cooldown {cooldown}; `
					.. `it must be a whole number between 1 and {Config.Events.MaxCooldownSeconds}`
			)
		end
	end

	if #event.choices < MIN_CHOICES then
		error(`[AGES content] event "{event.id}" needs at least {MIN_CHOICES} choices`)
	end

	-- Casting only means anything for a visitor, so an id on anything else is a
	-- copy-paste that would silently do nothing.
	if event.cast ~= nil then
		if event.delivery ~= "NPCApproach" then
			error(`[AGES content] event "{event.id}" casts "{event.cast}" but is delivered by {event.delivery}`)
		end
		if Cast.ById[event.cast] == nil then
			error(`[AGES content] event "{event.id}" casts "{event.cast}", who is not in the cast`)
		end
	end

	-- Deliberately the *only* check on a subject. Unlike cast, it is legal against
	-- every delivery and every resolution -- the dog turns up whether the event
	-- arrived on a birthday or off a doormat -- so a misspelled id is the one thing
	-- that could be wrong here, and it is the one thing a runtime warning would let
	-- ship as an event that quietly stopped being about anything.
	if event.subject ~= nil and Subjects.ById[event.subject] == nil then
		error(`[AGES content] event "{event.id}" is about "{event.subject}", which is not a subject`)
	end

	-- Escalations chain events: a follow-up fires when the prior one resolves,
	-- so the player can trace the thread. A chain to nothing is dead writing.
	-- A chain to the same id loops forever. A chain to an earlier age is a
	-- self-contradiction that the picker cannot resolve in order.
	local escalatesTo = event.escalatesTo
	if escalatesTo ~= nil then
		if escalatesTo == event.id then
			error(
				`[AGES content] event "{event.id}" escalates to itself; `
					.. `a chain must point at a different event`
			)
		elseif byId[escalatesTo] == nil then
			error(
				`[AGES content] event "{event.id}" escalates to "{escalatesTo}", `
					.. `which is not a declared event`
			)
		elseif byId[escalatesTo].minAge < event.minAge then
			error(
				`[AGES content] event "{event.id}" escalates to "{escalatesTo}", `
					.. `which starts at age {byId[escalatesTo].minAge}, below this event's {event.minAge}; `
					.. `a follow-up cannot precede its cause`
			)
		end
	end

	-- A lure is the words on the thing the player walks to, so it means something on
	-- exactly one route and nothing anywhere else. Both directions are refused: a
	-- wandered event without one is a blank pad in a room the player is meant to cross
	-- for it, and a lure on a letter is a line of writing that goes nowhere and reads,
	-- to whoever wrote it, as though it had been used.
	local wandered = Delivery.RouteOf(event.delivery) == "Wandered"
	if wandered and event.lure == nil then
		error(`[AGES content] wandered event "{event.id}" has no lure; there would be nothing written on it`)
	end
	if not wandered and event.lure ~= nil then
		error(
			`[AGES content] event "{event.id}" has a lure but is delivered "{event.delivery}", `
				.. `which puts nothing on the floor for it to be written on`
		)
	end

	-- Tags are opaque to the validator: they are picked up by the picker and
	-- the routing layer, not checked against a fixed registry. Unknown tags
	-- are ignored rather than refused, because a new tag that has no reader
	-- yet is content, not a fault. Empty lists are normalised to nil so the
	-- picker never has to think about the empty-list case.
	if event.tags ~= nil then
		if #event.tags == 0 then
			event.tags = nil
		else
			for _, tag in event.tags do
				if tag == "" then
					error(
						`[AGES content] event "{event.id}" has an empty tag; `
							.. `non-empty strings only`
					)
				end
			end
		end
	end

	-- An ambient event below this age could never fire, because the scheduler
	-- will not stage one there -- and it must not, since resolving an event at
	-- that age advances the year. Caught here rather than at runtime, where it
	-- would look like an event that simply never came up.
	if Delivery.RouteOf(event.delivery) == "Ambient" and event.minAge < Config.Ambient.MinAge then
		error(
			`[AGES content] ambient event "{event.id}" starts at age {event.minAge}, `
				.. `below Ambient.MinAge ({Config.Ambient.MinAge}); it could never be staged`
		)
	end

	-- A shift event below the youngest working age could never fire, because there
	-- is no job that would have you at that age and so no shift for it to fire
	-- during. The same shape of check as the ambient one above, and caught for the
	-- same reason: at runtime the symptom is an event that simply never comes up,
	-- which is indistinguishable from bad luck.
	local onShift = Delivery.RouteOf(event.delivery) == "Shift"
	if onShift then
		local workingAge = Jobs.MinimumWorkingAge()
		if event.minAge < workingAge then
			error(
				`[AGES content] shift event "{event.id}" starts at age {event.minAge}, `
					.. `below the youngest age any job can be held ({workingAge}); it could never fire`
			)
		end
	end

	-- Performance is all or nothing across an event's choices, on the same reasoning
	-- as stances and reactions: an event where two answers move your record and the
	-- third does not is indistinguishable, from the player's side, from one where the
	-- third answer was simply judged neutral -- and those are different sentences.
	-- Zero is how you say neutral, and saying it is the point.
	--
	-- Required on shift events, because a moment at work your job did not notice is
	-- exactly the thing having a record replaced. Refused everywhere else, because a
	-- performance weight off the clock has nothing to be recorded against and would
	-- be a copy-paste that silently does nothing.
	local scored = 0
	for _, choice in event.choices do
		if choice.performance ~= nil then
			scored += 1
		end
	end
	if onShift then
		if scored < #event.choices then
			error(
				`[AGES content] shift event "{event.id}" scores {scored} of its {#event.choices} `
					.. `choices; every answer at work must say what it does to your record, `
					.. `and 0 is how you say "nothing"`
			)
		end
	elseif scored > 0 then
		error(
			`[AGES content] event "{event.id}" scores its choices but is delivered by `
				.. `{event.delivery}, so there is no job to have an opinion`
		)
	end

	for _, choice in event.choices do
		-- Whole units, and inside the range a record can actually hold. A fractional
		-- weight would land the player on a standing no band boundary is written
		-- against; one larger than the whole scale would move them from the floor to
		-- the ceiling in a single answer, which no single answer should do.
		local performance = choice.performance
		if performance ~= nil then
			local span = Config.Work.Standing.Max - Config.Work.Standing.Min
			if performance ~= math.floor(performance) or math.abs(performance) > span then
				error(
					`[AGES content] event "{event.id}" choice "{choice.id}" scores {performance}; `
						.. `it must be a whole number no further from zero than the {span}-point record scale`
				)
			end
		end
	end

	-- Both limits apply to every event now, not only enacted ones, because every event
	-- ends up on the same panel: an enacted one is a banner plus a walk plus that panel.
	-- They used to be enacted-only because the choices used to become discs on the
	-- floor, and a room fits fewer of those than a list does.
	--
	-- What they mean now. Past MaxChoices a question stops being a decision and becomes
	-- a menu -- four things is the most a player will actually weigh against each other
	-- before picking whichever they read first. Past MaxLabelLength a row wraps to three
	-- lines and the list stops being readable at a glance, which is the one thing it has
	-- to be.
	--
	-- Caught here rather than at runtime, where the symptom would be an event that
	-- merely feels bad rather than one that is wrong -- exactly the kind of fault that
	-- ships.
	if #event.choices > Config.Enact.MaxChoices then
		error(
			`[AGES content] event "{event.id}" has {#event.choices} choices; more than `
				.. `{Config.Enact.MaxChoices} is a menu rather than a decision`
		)
	end
	for _, choice in event.choices do
		if #choice.label > Config.Enact.MaxLabelLength then
			error(
				`[AGES content] choice "{choice.id}" in event "{event.id}" has a `
					.. `{#choice.label}-character label; a panel row carries {Config.Enact.MaxLabelLength}`
			)
		end
	end

	-- Acts are all or nothing across an event's choices, and this is the strictest
	-- version of that rule in the file rather than the same one again. A performance
	-- or a reaction that only some answers carry is a writing mistake; an act that
	-- only some answers carry is an answer the player cannot reach at all, because a
	-- Handled event never opens a panel for the others to be rows on.
	local acted = 0
	for _, choice in event.choices do
		if choice.act ~= nil then
			acted += 1
		end
	end
	if acted > 0 and acted < #event.choices then
		error(
			`[AGES content] event "{event.id}" gives {acted} of its {#event.choices} choices `
				.. `something to do; acts are all or nothing, because the answers without one `
				.. `would have no panel left to appear on`
		)
	end
	if acted > 0 and event.resolution ~= "Handled" then
		error(
			`[AGES content] event "{event.id}" has acts but resolves "{event.resolution or "Panel"}"; `
				.. `answers made of objects are only reachable as "Handled"`
		)
	end
	if event.resolution == "Handled" and acted == 0 then
		error(
			`[AGES content] event "{event.id}" resolves "Handled" but no choice says what to do; `
				.. `it would fall back to a panel every time it fired`
		)
	end

	if acted > 0 then
		-- One prop id, one place in the room. The carried object of a Carry is declared
		-- by every answer that uses it, so repeats are expected and only have to agree:
		-- two spellings of where the cookie starts would place it at whichever the
		-- staging loop reached first, which is a bug that moves between events.
		local placedAt: { [string]: PropPlacement } = {}
		-- What touching each prop answers. A prop may be the trigger for exactly one
		-- choice, or the event resolves as whichever watch the tick happened to check
		-- first -- a coin flip the player cannot see, let alone influence.
		local triggers: { [string]: string } = {}
		local carried: { [string]: boolean } = {}
		-- The key for "answered where you already are", which is what a Stay with no
		-- prop is. Not a legal prop id, so it cannot collide with one.
		local HERE = "\0here"

		local function place(where: string, placement: PropPlacement)
			if Props.ById[placement.prop] == nil then
				error(`[AGES content] {where} names prop "{placement.prop}", which is not in Props`)
			end
			local first = placedAt[placement.prop]
			if first == nil then
				placedAt[placement.prop] = placement
				return
			end
			if first.distance ~= placement.distance or first.offsetDegrees ~= placement.offsetDegrees then
				error(
					`[AGES content] {where} puts "{placement.prop}" somewhere other than another answer `
						.. `in the same event does; one object cannot stand in two places`
				)
			end
		end

		for _, choice in event.choices do
			local act = choice.act
			if act == nil then
				continue
			end
			local where = `event "{event.id}" choice "{choice.id}"`

			-- Shorter than a panel row, because it is not one. It floats over an object
			-- a few studs away and has to be read while the player is moving.
			if #choice.label > Config.Props.MaxLabelLength then
				error(
					`[AGES content] {where} has a {#choice.label}-character label, and it is `
						.. `written over an object in the room rather than on a row; `
						.. `{Config.Props.MaxLabelLength} is what fits`
				)
			end

			if act.verb == "Carry" then
				if act.at == nil or act.to == nil then
					error(
						`[AGES content] {where} carries something, so it needs both the thing to `
							.. `pick up and somewhere to take it`
					)
				end
			else
				if act.to ~= nil then
					error(`[AGES content] {where} is a {act.verb} with a destination; only Carry goes somewhere`)
				end
				-- Stay is the one verb whose answer can be "here", with nothing in the
				-- room at all. Every other verb is a thing done to a thing.
				if act.at == nil and act.verb ~= "Stay" then
					error(`[AGES content] {where} is a {act.verb} with nothing to do it to`)
				end
			end

			local at = act.at
			local to = act.to
			if at ~= nil then
				place(where, at)
			end
			if to ~= nil then
				place(where, to)
			end
			if at ~= nil and to ~= nil and at.prop == to.prop then
				error(`[AGES content] {where} carries "{at.prop}" to itself, which is already where it is`)
			end

			-- Picking a thing up is not an answer, so a Carry is answered at its
			-- destination. Every other verb is answered at the thing itself.
			local trigger = if to ~= nil then to.prop elseif at ~= nil then at.prop else HERE
			local clash = triggers[trigger]
			if clash ~= nil then
				if trigger == HERE then
					error(
						`[AGES content] event "{event.id}" choices "{clash}" and "{choice.id}" are both `
							.. `answered by standing still where you already are, which is one answer`
					)
				end
				error(
					`[AGES content] event "{event.id}" choices "{clash}" and "{choice.id}" are both `
						.. `answered at "{trigger}"; whichever the tick reached first would win`
				)
			end
			triggers[trigger] = choice.id

			if at ~= nil and to ~= nil then
				carried[at.prop] = true
			end
		end

		-- Two Stays where one of them is given "here" is the trigger clash again, wearing
		-- a disguise the trigger check cannot see through. Their triggers really are
		-- different props, so nothing above catches it -- but a Stay with no prop is
		-- satisfied *wherever* the player is standing, including inside the other one's
		-- reach. A player holding still at the lamp is holding still at the lamp and
		-- holding still in general, both accumulate, and both finish on the same tick.
		local stayHere: string? = nil
		local stayAt: string? = nil
		for _, choice in event.choices do
			local act = choice.act
			if act == nil or act.verb ~= "Stay" then
				continue
			end
			if act.at == nil then
				stayHere = choice.id
			else
				stayAt = choice.id
			end
		end
		if stayHere ~= nil and stayAt ~= nil then
			error(
				`[AGES content] event "{event.id}" answers "{stayHere}" by holding still anywhere `
					.. `and "{stayAt}" by holding still at a prop; standing at that prop does both, `
					.. `and whichever the tick reached first would win`
			)
		end

		-- The carried object is the one prop the player touches without answering
		-- anything. If some other choice is answered by touching it, picking it up to
		-- take it somewhere would take that other answer instead, and the player would
		-- never get as far as choosing where.
		for propId in carried do
			local clash = triggers[propId]
			if clash ~= nil then
				error(
					`[AGES content] event "{event.id}" answers choice "{clash}" by reaching "{propId}", `
						.. `which another answer picks up and carries; picking it up would take the wrong answer`
				)
			end
		end
	end

	-- Reactions are all or nothing, and need a subject -- but deliberately *not*
	-- enactment. Watching the dog come to you is worth exactly as much when you
	-- answered on a panel, and tying the two together would mean an event silently
	-- lost half its ending every time the dots could not be hung.
	local reacting = 0
	for _, choice in event.choices do
		if choice.reaction ~= nil then
			reacting += 1
		end
	end
	if reacting > 0 then
		if reacting < #event.choices then
			error(
				`[AGES content] event "{event.id}" gives a reaction to {reacting} of its `
					.. `{#event.choices} choices; reactions are all or nothing`
			)
		end
		if event.subject == nil then
			error(`[AGES content] event "{event.id}" reacts to its choices but is not about anything`)
		end
	end

	-- At least one answer must be free. A priced choice the player cannot afford is
	-- refused -- on the panel and on the floor alike -- so an event whose every answer
	-- had a price would be unanswerable to a player who could not meet the cheapest
	-- of them, and the prompt would sit open forever with no way to clear it. Not a
	-- balance rule but a liveness one: there has to be a way to walk away.
	local priced = 0
	for _, choice in event.choices do
		if choice.cost ~= nil then
			priced += 1
		end
	end
	if priced > 0 and priced == #event.choices then
		error(
			`[AGES content] event "{event.id}" puts a price on all {priced} of its choices; `
				.. `at least one answer must be free, or a player with nothing cannot answer at all`
		)
	end

	-- Flags are the one field here whose mistakes have no runtime symptom at all. A
	-- misspelled subject spawns nothing and somebody notices; a misspelled `requires`
	-- produces an event that is simply never selected, which is indistinguishable from
	-- an event nobody has rolled yet. So every id is checked against the registry and
	-- an unsatisfiable pair is refused outright.
	Flags.AssertKnown(event.requires, `event "{event.id}"`)
	Flags.AssertKnown(event.forbids, `event "{event.id}"`)
	Flags.AssertSatisfiable(event.requires, event.forbids, `event "{event.id}"`)

	-- The standing and job gates exist so a shift event can name its own unlock.
	-- Only WorkService's moment picker reads them, so on any other delivery a gate
	-- is writing that silently never closes -- the same dead writing as a lure on
	-- a letter, and refused the same way. A gate that can never be met is refused
	-- too: a floor no standing reaches means the event never fires, which at
	-- runtime looks exactly like content nobody has rolled yet.
	local minStanding = event.minStanding
	if minStanding ~= nil then
		if event.delivery ~= "Shift" then
			error(
				`[AGES content] event "{event.id}" gates on standing but is delivered by `
					.. `{event.delivery}; only Shift events are ever gated`
			)
		end
		local standing = Config.Work.Standing
		if minStanding <= 0 or minStanding > standing.Max then
			error(
				`[AGES content] event "{event.id}" asks for standing {minStanding}; it must be `
					.. `above 0 and no more than the ceiling of {standing.Max}`
			)
		end
	end
	local jobs = event.jobs
	if jobs ~= nil then
		if event.delivery ~= "Shift" then
			error(
				`[AGES content] event "{event.id}" is gated to jobs but is delivered by `
					.. `{event.delivery}; only Shift events are ever gated`
			)
		end
		for _, jobId in jobs do
			if Jobs.ById[jobId] == nil then
				error(`[AGES content] event "{event.id}" is gated to "{jobId}", which is not a job`)
			end
		end
	end

	-- writesBack is mandatory. An event that does not alter durable state is
	-- a cutscene, and the design's named trap for this is "Events that change
	-- nothing". The list names what the event actually writes: stats, flags,
	-- ties, ribbons, standing, or money. Each name is checked against its
	-- registry; a misspelling is a content error caught at load, not a
	-- runtime no-op. Empty list is refused outright -- the event must write
	-- something.
	local writesBack = event.writesBack
	if writesBack == nil or #writesBack == 0 then
		error(
			`[AGES content] event "{event.id}" has no writesBack; `
				.. `every event must write at least one thing (stat, flag, tie, ribbon, standing, or money)`
		)
	end
	for _, entry in writesBack do
		-- Split "prefix:id" or bare "money".
		local colon = string.find(entry, ":", 1, true)
		if colon == nil then
			-- Bare name: only "money" is legal.
			if entry ~= "money" then
				error(
					`[AGES content] event "{event.id}" writesBack entry "{entry}" `
						.. `must be prefixed with "stat:", "flag:", "tie:", "ribbon:", or "standing:"`
				)
			end
			continue
		end
		local prefix = string.sub(entry, 1, colon - 1)
		local id = string.sub(entry, colon + 1)
		if id == "" then
			error(
				`[AGES content] event "{event.id}" writesBack entry "{entry}" `
					.. `has an empty id after the colon`
			)
		end
		if prefix == "stat" then
			-- StatName: "health", "happiness", "smarts", "looks".
			if entry ~= "stat:health" and entry ~= "stat:happiness"
				and entry ~= "stat:smarts" and entry ~= "stat:looks" then
				error(
					`[AGES content] event "{event.id}" writesBack stat "{id}", `
						.. `which is not one of health, happiness, smarts, looks`
				)
			end
		elseif prefix == "flag" then
			Flags.AssertKnown(id, `event "{event.id}" writesBack flag`)
		elseif prefix == "tie" then
			Ties.AssertKnown(id, `event "{event.id}" writesBack tie`)
		elseif prefix == "ribbon" then
			-- Ribbons is a flat array, not keyed. Linear scan is fine -- there
			-- are roughly 40 entries, and this check runs once at server start.
			local found = false
			for _, ribbon in Ribbons do
				if ribbon.id == id then
					found = true
					break
				end
			end
			if not found then
				error(
					`[AGES content] event "{event.id}" writesBack ribbon "{id}", `
						.. `which is not a declared ribbon`
				)
			end
		elseif prefix == "standing" then
			if Jobs.ById[id] == nil then
				error(
					`[AGES content] event "{event.id}" writesBack standing "{id}", `
						.. `which is not a job`
				)
			end
		else
			error(
				`[AGES content] event "{event.id}" writesBack entry "{entry}" `
					.. `has an unknown prefix "{prefix}"; use stat:, flag:, tie:, ribbon:, standing:, or money`
			)
		end
	end

	local seenChoiceIds: { [string]: boolean } = {}
	for _, choice in event.choices do
		if seenChoiceIds[choice.id] then
			error(`[AGES content] event "{event.id}" repeats choice id "{choice.id}"`)
		end
		seenChoiceIds[choice.id] = true

		-- Whole units above zero, both directions. Zero is rejected rather than
		-- treated as free because nil already means free and two spellings of the
		-- same thing is how a display ends up reading "$0". Fractions are rejected
		-- here rather than rounded downstream, so a price that was authored as 12.50
		-- is a load-time error instead of a silent 12 that nobody notices.
		local cost = choice.cost
		if cost ~= nil and (cost <= 0 or cost ~= math.floor(cost)) then
			error(
				`[AGES content] event "{event.id}" choice "{choice.id}" costs {cost}; `
					.. `a price must be a whole number above zero`
			)
		end
		local payout = choice.payout
		if payout ~= nil and (payout <= 0 or payout ~= math.floor(payout)) then
			error(
				`[AGES content] event "{event.id}" choice "{choice.id}" pays {payout}; `
					.. `a payout must be a whole number above zero`
			)
		end
		-- Both at once is refused rather than netted off, because only one of the two
		-- is shown before the answer is taken: a choice that costs 50 and pays 30 would
		-- advertise a price of 50 and be locked at a balance of 40, when what it really
		-- asks for is 20. Author the net figure and the label can say the rest.
		if cost ~= nil and payout ~= nil then
			error(
				`[AGES content] event "{event.id}" choice "{choice.id}" both costs and pays; `
					.. `author the net figure`
			)
		end

		-- Per the design spec: a choice that doesn't move a stat should be cut,
		-- because it gives the player nothing to weigh. Money counts as movement --
		-- paying for something you wanted, or being paid for an afternoon, is a real
		-- consequence even when no stat shifts, and a purchase with a price and no
		-- stat effect is a perfectly good choice to have to weigh.
		-- A record counts as movement too, on the same reasoning as money: an answer
		-- that changes nothing about you but changes what your employer thinks of you
		-- is a real consequence and a real thing to weigh. A performance of zero
		-- explicitly is not -- that is the spelling of "no opinion".
		local movesSomething = cost ~= nil or payout ~= nil or (choice.performance ~= nil and choice.performance ~= 0)
		if not movesSomething then
			for _, delta in choice.effects do
				if delta ~= 0 then
					movesSomething = true
					break
				end
			end
		end
		if not movesSomething then
			error(`[AGES content] choice "{choice.id}" in event "{event.id}" moves no stat and no money`)
		end

		local where = `event "{event.id}" choice "{choice.id}"`
		Flags.AssertKnown(choice.sets, where)
		Flags.AssertKnown(choice.clears, where)
		Flags.AssertNotBoth(choice.sets, choice.clears, where)

		-- An event that requires a flag and whose answer sets it again could only ever
		-- be reached by a life that already had it, so the set is dead writing -- and
		-- dead writing in a content file reads as an intention that was carried out.
		if choice.sets ~= nil and event.requires ~= nil then
			for _, setId in choice.sets do
				for _, requiredId in event.requires do
					if setId == requiredId then
						error(
							`[AGES content] {where} sets flag "{setId}", which its own event `
								.. `already requires; nothing could reach it without holding that flag`
						)
					end
				end
			end
		end
	end
end

for _, source in SOURCES do
	for _, event in source do
		validate(event)
		byId[event.id] = event
		table.insert(all, event)
	end
end

local LifeEvents = {
	All = all,
	ById = byId,
}

return LifeEvents
