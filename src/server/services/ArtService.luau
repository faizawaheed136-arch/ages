--!strict
-- Art: the study. A small picture is pinned to the wall of the room and you copy it, cell
-- by cell, onto a canvas.
--
-- The one line this file exists to protect:
--
--   **Science hides the board and asks you to remember. Art shows you everything and
--   asks you to notice.**
--
-- The wall is always in the room. The canvas is always on screen. Neither is ever
-- annotated -- nothing in this file or the panel it pushes to ever marks a cell as wrong,
-- and the day something does, this subject stops existing and becomes a checklist with
-- paint on it. `stale` is a count and there is deliberately no list next to it: being told
-- you owe three cells and having to *find* them is the verb.
--
-- The rest of the loop, in the order it matters:
--
--   The picture moves. Part of every study is marked as free to shift -- the light turns,
--   somebody nudges the fruit -- and cells you have already painted quietly stop being
--   right. That single rule is where the second queue comes from: at any moment there is
--   something unpainted to paint and something painted to repair, they compete for the
--   same seconds, and neither is ever the obviously correct one.
--
--   Signing is a real commit, unlike the lab's. Your score is the canvas at the moment
--   you sign it, and the canvas rots while you hold it, so finishing early is a genuine
--   trade -- more coverage against keeping what you have. A player who paints twelve good
--   cells and signs beats one who paints sixteen and lets four go stale.
--
--   Paint runs out and the cupboard is behind you. What that trip costs is not the
--   seconds. It is sight of the wall -- see Studio for why the cupboard is where it is --
--   so the shift that happens while you are fetching is the one you have no idea about.
--
--   Mastery hands you tubes, not numbers. Rung one gives you the two colours the picture
--   is mostly made of; the rungs above give you the ones it is barely made of, which are
--   exactly the sail, the hull and the highlight. At two tubes a perfect copy only just
--   clears a pass; at the top there is slack in it for a corner you never reached. That
--   is progression widening the player's own tolerance inside the verb, and it is checked
--   against the content at require time below rather than hoped for.
--
-- What this file is deliberately not:
--
--   It is not a second school. The door, the yearly cap, the smarts payout and the
--   verdict shares are School's, read from Config.School through Report, and a lesson
--   that happens to be Art still spends one of the three lessons in the year.
--
--   It does not build the room, for the reason ScienceService does not build the lab.
--
--   It does not own the picture either, and that is the one structural difference from
--   Science worth stating up front: the study is *the wall's*, not the session's. A wall
--   can only hold one picture, so everybody painting at the same time is copying the same
--   thing and living with the same shifts. See `wall` below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Pigments = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Pigments"))
local Mastery = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Mastery"))
local Report = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Report"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local StatService = require(script.Parent.StatService)
local Ground = require(script.Parent.Parent.world.Ground)
local Studio = require(script.Parent.Parent.world.Studio)
local Studies = require(script.Parent.Parent.content.Studies)

type LifeData = Types.LifeData
type ArtState = Types.ArtState
type PaletteSwatch = Types.PaletteSwatch
type Pigment = Pigments.Pigment
type Study = Studies.Study

local ArtService = {}

local ArtUpdatedRemote = Remotes.Get("ArtUpdated")
local RequestArtPaintRemote = Remotes.Get("RequestArtPaint")
local RequestArtSignRemote = Remotes.Get("RequestArtSign")

local SCHOOL = Config.School
local ART = SCHOOL.Art

-- The subject id this service answers to. A constant rather than a parameter because
-- there is exactly one copying subject; the day there is a second, this becomes an
-- argument and nothing else here changes.
local SUBJECT_ID = "art"

local CELLS = Studies.CellCount

-- The two ladders have to be the same length, and this is the only place that can notice.
-- A sixth rung on one and not the other is a promotion the verb has no answer for -- the
-- player is told they levelled up and the palette does not change -- which is the
-- numbers-only progression this whole rebuild exists to remove, arriving by accident.
if #ART.PaletteByLevel ~= Mastery.Levels then
	error(
		`[AGES config] School.Art.PaletteByLevel has {#ART.PaletteByLevel} entries but School.Mastery.Levels`
			.. ` is {Mastery.Levels}. Every mastery rung has to say how many tubes it hands over, so the list`
			.. ` needs exactly one number per level. Add or remove one.`
	)
end

for level = 2, #ART.PaletteByLevel do
	if ART.PaletteByLevel[level] < ART.PaletteByLevel[level - 1] then
		error(
			`[AGES config] School.Art.PaletteByLevel goes from {ART.PaletteByLevel[level - 1]} tubes at level`
				.. ` {level - 1} down to {ART.PaletteByLevel[level]} at level {level}. Levelling up must never`
				.. ` take paint away -- a rung that makes the picture worse is a punishment for playing well.`
		)
	end
end

if ART.PaletteByLevel[1] < 2 then
	error(
		`[AGES config] School.Art.PaletteByLevel starts at {ART.PaletteByLevel[1]} tube(s). With fewer than`
			.. ` two there is nothing to choose between and painting is one button pressed sixteen times.`
	)
end

-- How many tubes this rung hands over, clamped to the ladder. Off the top of the list
-- rather than off the bottom, because a level above the ladder is a data problem and the
-- right thing to do with it is give the player everything rather than nothing.
local function tubeCountFor(level: number): number
	local rung = math.clamp(math.floor(level), 1, #ART.PaletteByLevel)
	return ART.PaletteByLevel[rung]
end

-- The tubes a study hands out at a given rung: its own colours, most-used first, cut to
-- the rung's count. Truncated to what the picture actually contains, so a topped-out
-- palette is "every colour in this study" rather than a row with three dead swatches on
-- the end of it.
local function paletteFor(study: Study, level: number): { Pigment }
	local want = math.min(tubeCountFor(level), #study.byUse)
	local out: { Pigment } = {}
	for index = 1, want do
		table.insert(out, study.byUse[index])
	end
	return out
end

-- The nearest tube in a palette to a colour on the wall. This is the best the player can
-- possibly do for that cell, which makes it two things at once: the ceiling the require
-- time check below measures, and the definition of a cell having gone stale.
--
-- Ties go to the earlier tube, which is the more-used one. Deterministic rather than
-- arbitrary because "which cells are stale" has to mean the same thing on two consecutive
-- ticks -- a tiebreak that wobbled would make the count flicker and send the player
-- hunting for a difference that was never there.
local function nearestTube(palette: { Pigment }, target: Pigment): (Pigment?, number)
	local best: Pigment? = nil
	local bestCloseness = -1
	for _, tube in palette do
		local closeness = Pigments.Closeness(tube, target)
		if closeness > bestCloseness then
			best = tube
			bestCloseness = closeness
		end
	end
	return best, math.max(bestCloseness, 0)
end

-- The best score a perfect painting could get at a given rung. Every cell painted with
-- the nearest tube available, and nothing missed.
local function ceilingFor(study: Study, level: number): number
	local palette = paletteFor(study, level)
	local total = 0
	for _, target in study.cells do
		local _, closeness = nearestTube(palette, target)
		total += closeness
	end
	return total / CELLS
end

-- Checked against the actual content at require time, and this is the guard the whole
-- ladder rests on. A first rung whose ceiling falls under GoodShare is a subject nobody
-- can ever pass their way out of: you need good lessons to climb, and you cannot have a
-- good lesson, and nothing in the game would say so -- the player would simply find that
-- Art never rewards them and conclude the game is broken, which it would be.
--
-- Loud rather than clamped for the reason Science's is: clamping hides it. The lesson
-- would run, the ladder would not, and no line anywhere would mention it.
for _, study in Studies.All do
	local ceiling = ceilingFor(study, 1)
	if ceiling < SCHOOL.GoodShare then
		error(
			`[AGES content] study "{study.id}" tops out at {string.format("%.3f", ceiling)} on the first`
				.. ` mastery rung, under School.GoodShare of {SCHOOL.GoodShare} -- a perfect copy of it could`
				.. ` not pass, so nobody starting Art could ever climb out of level one. Either give the`
				.. ` picture fewer or closer colours, or raise School.Art.PaletteByLevel[1].`
		)
	end
end

-- The picture currently on the wall.
--
-- Module state rather than session state, and it is the one place this verb's shape
-- differs structurally from the lab's. A wall holds one picture. Two players painting at
-- the same time are in one art class copying one still life and watching the same light
-- move, which is both the honest thing and the only thing the physical room can express.
--
-- `truth` drifts away from `study.cells` as the study shifts, and it is what everything is
-- scored against. `study.cells` stays as authored, which is what the palette is cut from:
-- the paint you were handed at the start does not change when the light does.
type Wall = {
	study: Study,
	truth: { Pigment },
	secondsToShift: number,
}

local wall: Wall? = nil

-- One player's canvas.
type Session = {
	-- Held so the palette and the score survive the wall being restudied out from under a
	-- session -- which cannot currently happen, and would be a silent regrade if it ever
	-- started to.
	study: Study,
	-- What the player has put down, one slot per cell. Sparse: nil is bare canvas.
	painted: { [number]: Pigment },
	palette: { Pigment },
	-- Index into `palette`, or nil before the first tube is picked up.
	held: number?,
	strokes: number,
	secondsLeft: number,
	level: number,
	passes: number,
	levelAtStart: number,
	atEasel: boolean,
	atCupboard: boolean,
	summary: string?,
	verdictLeft: number,
	notice: string?,
	noticeLeft: number,
}

local sessions: { [Player]: Session } = {}
local pushed: { [Player]: string } = {}

-- Off by default is wrong for a subject and off by command is right for a harness. Same
-- switch every other verb carries, and the reason it exists is that a broken activity
-- should be turn-off-able in a live session without a rebuild.
local enabled = true

local function levelOf(data: LifeData): number
	return Mastery.LevelOf(data, SUBJECT_ID)
end

local function passesOf(data: LifeData): number
	return Mastery.PassesOf(data, SUBJECT_ID)
end

-- Where the player's body is, or nil while there is not one. Nil is a real state -- a
-- respawning character has no root part for a few frames -- and every caller here treats
-- it as "do not know" rather than as "somewhere else".
local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- How close a painted cell is to the wall right now, 0-1. Unpainted is zero, which is the
-- whole reason coverage matters: an untouched cell is not a neutral cell, it is a wrong
-- one, and a canvas half-finished is a canvas half-right at best.
local function cellScore(session: Session, truth: { Pigment }, index: number): number
	local put = session.painted[index]
	if put == nil then
		return 0
	end
	local target = truth[index]
	if target == nil then
		return 0
	end
	return Pigments.Closeness(put, target)
end

local function canvasShare(session: Session, truth: { Pigment }): number
	local total = 0
	for index = 1, CELLS do
		total += cellScore(session, truth, index)
	end
	return math.clamp(total / CELLS, 0, 1)
end

-- How many painted cells are no longer the best this palette could do, and how many have
-- any paint on them at all.
--
-- "Stale" is defined against the palette rather than against the wall on purpose. A
-- player at two tubes who painted a red apple in ochre has done the best thing available
-- to them, and calling that cell stale would send them back to repaint it with the same
-- tube forever. What counts as owing work is *a cell where a better choice now exists*,
-- which is exactly what a shift creates.
local function tally(session: Session, truth: { Pigment }): (number, number)
	local stale = 0
	local filled = 0
	for index = 1, CELLS do
		local put = session.painted[index]
		if put == nil then
			continue
		end
		filled += 1
		local target = truth[index]
		if target == nil then
			continue
		end
		local best = nearestTube(session.palette, target)
		if best ~= nil and best.id ~= put.id then
			stale += 1
		end
	end
	return stale, filled
end

-- The truth to score against. The wall's if there is one, and the study as authored if
-- the wall has somehow gone -- which cannot happen while a session is live, and would
-- otherwise mean scoring a painting against nothing.
local function truthFor(session: Session): { Pigment }
	local current = wall
	if current ~= nil then
		return current.truth
	end
	return session.study.cells
end

local function stateFor(player: Player): ArtState?
	local session = sessions[player]
	if session == nil then
		return nil
	end

	local truth = truthFor(session)
	local stale, filled = tally(session, truth)

	local painted: { Color3? } = {}
	for index = 1, CELLS do
		local put = session.painted[index]
		painted[index] = if put ~= nil then put.color else nil
	end

	local palette: { PaletteSwatch } = {}
	for _, tube in session.palette do
		table.insert(palette, { id = tube.id, name = tube.name, color = tube.color })
	end

	return {
		columns = ART.Columns,
		rows = ART.Rows,
		painted = painted,
		title = session.study.name,
		palette = palette,
		held = session.held,
		strokes = session.strokes,
		strokesMax = ART.StrokesPerRefill,
		stale = stale,
		filled = filled,
		secondsLeft = math.max(0, session.secondsLeft),
		atEasel = session.atEasel,
		atCupboard = session.atCupboard,
		level = session.level,
		levelMax = Mastery.Levels,
		passes = session.passes,
		passesPerLevel = Mastery.PassesPerLevel,
		summary = session.summary,
		notice = session.notice,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	-- A digest rather than a deep compare, and it has to name every field that is drawn.
	--
	-- The canvas goes in cell by cell rather than as some cheaper summary, because a
	-- repaint that swaps one cell's colour for another moves nothing else in this payload:
	-- not the filled count, not the stale count when both tubes were equally wrong, and
	-- not the paint left when the correction was free. A digest that missed that case
	-- would leave the panel showing the colour the player just painted over.
	--
	-- Like the hunt's, it saves nothing while the clock is running -- the clock is in here
	-- at the tick's own resolution, so that term moves on every pass by construction. What
	-- it saves is the beats where the clock is deliberately stopped: the closing line, and
	-- the frames where the character has no position and the canvas is frozen mid-respawn.
	-- Both hold for seconds, and both would otherwise re-send an identical sixteen-cell
	-- snapshot four times a second for the whole of it.
	local digest: string
	if state == nil then
		digest = "none"
	else
		local cells: { string } = {}
		for index = 1, CELLS do
			local color = state.painted[index]
			cells[index] = if color == nil
				then "-"
				else `{math.floor(color.R * 255)},{math.floor(color.G * 255)},{math.floor(color.B * 255)}`
		end
		digest = `{table.concat(cells, "|")}#{#state.palette}/{tostring(state.held)}/{state.strokes}/`
			.. `{state.stale}/{state.filled}/{math.floor(state.secondsLeft * 4)}/`
			.. `{tostring(state.atEasel)}/{tostring(state.atCupboard)}/{state.level}/{state.passes}/`
			.. `{tostring(state.summary)}/{tostring(state.notice)}`
	end

	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	ArtUpdatedRemote:FireClient(player, state)
end

-- Says no out loud. A refusal is a reply to a click and never a state to sit in, so it
-- carries its own short clock and clears itself.
local function refuse(player: Player, session: Session, reason: string)
	session.notice = reason
	session.noticeLeft = SCHOOL.VerdictSeconds
	push(player)
end

local function forget(player: Player)
	sessions[player] = nil
	pushed[player] = nil
end

-- Takes the study down when the last painter has gone. Called from every path that ends a
-- session, because a picture left hanging is the next lesson's answer already on the wall
-- for anybody who walked past the room -- and because an art room with nobody in it should
-- look like an art room with nobody in it.
local function releaseWallIfEmpty()
	if wall == nil then
		return
	end
	for _, session in sessions do
		if session.summary == nil then
			return
		end
	end
	wall = nil
	Studio.Clear()
end

-- Puts a picture up, or joins the one already there. New only when the wall is free: two
-- players in the room copy the same study, because the wall is a physical object and can
-- only hold one.
local function claimWall(): Wall?
	local current = wall
	if current ~= nil then
		return current
	end
	if #Studies.All == 0 then
		return nil
	end

	local study = Studies.All[math.random(1, #Studies.All)]
	local truth: { Pigment } = table.clone(study.cells)
	local made: Wall = {
		study = study,
		truth = truth,
		secondsToShift = ART.ShiftSeconds,
	}
	wall = made
	Studio.Show(study.name, truth)
	return made
end

-- One square of the study changes. The whole of what a shift looks like from the world's
-- side: a part changes colour and nothing announces it -- see Studio.SetCell for why there
-- is no sound and no flash on this.
--
-- The replacement is drawn from the study's own colours rather than from the whole shelf,
-- so a harbour stays a harbour. A picture that could shift to any of eight pigments would
-- stop being a picture within a minute, and the player would be copying noise.
local function shiftOne(current: Wall)
	local movable = current.study.movable
	if #movable == 0 then
		return
	end
	local index = movable[math.random(1, #movable)]
	local was = current.truth[index]

	local choices: { Pigment } = {}
	for _, pigment in current.study.byUse do
		if was == nil or pigment.id ~= was.id then
			table.insert(choices, pigment)
		end
	end
	if #choices == 0 then
		-- Impossible: Studies refuses a study with fewer than two pigments in it at require
		-- time, so there is always something else to become. Guarded anyway rather than
		-- indexing an empty list, because the alternative failure is a whole tick loop
		-- dying on a picture nobody will think to look at.
		return
	end

	local now = choices[math.random(1, #choices)]
	current.truth[index] = now
	Studio.SetCell(index, now)
end

-- Ends the canvas and pays for it. `reason` changes the sentence and never the arithmetic:
-- a canvas walked away from is graded exactly as one that ran out of time, because leaving
-- early is a way of not having painted it.
local function finish(player: Player, data: LifeData, session: Session, reason: string)
	-- Decided before anything is written, which is the idempotency rule this codebase runs
	-- on: work the outcome out, then record it.
	local truth = truthFor(session)
	local share = canvasShare(session, truth)
	local _, filled = tally(session, truth)

	local band = Report.BandFor(share)
	local gained = Report.SmartsFor(band)

	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	-- Banked once on the whole canvas rather than per cell, for the reason Geography banks
	-- once on the whole errand: a canvas is one painting. Paying the ladder sixteen times
	-- would make Art climb at sixteen times every other subject's rate and top out inside a
	-- single afternoon.
	Mastery.Record(data, SUBJECT_ID, share)
	session.level = levelOf(data)
	session.passes = passesOf(data)

	-- Counted however it ended, including walked away from, for the reason a lesson is:
	-- otherwise a player could start, leave, and start again until the wall showed a study
	-- they liked the look of.
	data.lessonsThisYear += 1
	EventService.AwardAutonomy(player, 1)

	local level = levelOf(data)
	Report.RecordLesson(data, SUBJECT_ID, band, gained, if level > session.levelAtStart then level else nil)

	local percent = math.floor(share * 100 + 0.5)
	local reward = if gained > 0 then `. +{gained} smarts.` else "."
	local opening = if reason == "signed"
		then "Signed."
		elseif reason == "left" then "You walked away from it."
		else "Time -- brushes down."
	session.summary = `{opening} {filled} of {CELLS} cells painted, {percent}% of the study{reward}`
	session.verdictLeft = ART.VerdictSeconds
	session.notice = nil
	session.noticeLeft = 0
	push(player)
end

-- Why this player cannot paint right now, or nil if they can. Only the things Art itself
-- refuses -- the age, the yearly cap and the door are School's, checked before this is
-- ever called.
local function refusalFor(): string?
	if not enabled then
		return "The art room is closed."
	end
	if Studio.Room() == nil then
		return "The art room has not been built."
	end
	if #Studies.All == 0 then
		return "There is nothing up on the wall today."
	end
	return nil
end

-- Starts a canvas. Returns false with a reason worth saying out loud.
--
-- Takes no position, exactly as ScienceService.Begin does not: the wall and the cupboard
-- are real furniture in one place, and a session centred anywhere else would start with
-- the picture already outside the room the player is held in.
function ArtService.Begin(player: Player, data: LifeData): (boolean, string?)
	if sessions[player] ~= nil then
		return false, "You are already at the easel."
	end
	local refusal = refusalFor()
	if refusal ~= nil then
		return false, refusal
	end

	local current = claimWall()
	if current == nil then
		return false, "There is nothing up on the wall today."
	end

	local level = levelOf(data)
	local session: Session = {
		study = current.study,
		painted = {},
		palette = paletteFor(current.study, level),
		held = nil,
		strokes = ART.StrokesPerRefill,
		secondsLeft = ART.SecondsPerCanvas,
		level = level,
		passes = passesOf(data),
		levelAtStart = level,
		atEasel = false,
		atCupboard = false,
		summary = nil,
		verdictLeft = 0,
		notice = nil,
		noticeLeft = 0,
	}

	sessions[player] = session
	push(player)
	return true, nil
end

-- A cell painted. Everything about it is re-checked here rather than trusted, because the
-- client knows the palette, the pot and the easel radius and could lie about all three.
local function onPaintRequested(player: Player, cellIndex: unknown, pigmentId: unknown)
	if type(cellIndex) ~= "number" or type(pigmentId) ~= "string" then
		return
	end
	local session = sessions[player]
	if session == nil or session.summary ~= nil then
		return
	end

	local index = math.floor(cellIndex)
	if index < 1 or index > CELLS then
		-- A cell that is not on the canvas. Dropped silently rather than refused out loud:
		-- there is no way for a player to do this, so a message would be a message about a
		-- client bug shown to somebody who cannot act on it.
		return
	end

	-- The tube has to be one this rung was actually handed. Checked against the session's
	-- own palette rather than against the shelf, because the palette *is* the mastery
	-- reward -- a client that could name any pigment would hand itself the top rung.
	local tube: Pigment? = nil
	local slot: number? = nil
	for position, candidate in session.palette do
		if candidate.id == pigmentId then
			tube = candidate
			slot = position
			break
		end
	end
	if tube == nil or slot == nil then
		return
	end

	if not session.atEasel then
		refuse(player, session, "Go back to the easel.")
		return
	end

	-- Picking the tube up is free and always allowed, even with an empty pot. Which colour
	-- is in your hand is not a move, and a player who cannot even change brushes while
	-- walking to the cupboard is being charged for the walk twice.
	session.held = slot

	local already = session.painted[index]
	if already ~= nil and already.id == tube.id then
		-- The same paint on the same cell. A no-op that costs nothing, because a double
		-- click and a cell the player has forgotten they already did are the same input,
		-- and charging a stroke for it would make the pot a test of memory rather than a
		-- reason to walk.
		push(player)
		return
	end

	if session.strokes <= 0 then
		refuse(player, session, "Out of paint. The cupboard is behind you.")
		return
	end

	session.painted[index] = tube
	session.strokes -= 1
	session.notice = nil
	session.noticeLeft = 0
	push(player)
end

-- Signed. The commit, and the only irreversible act in the verb.
local function onSignRequested(player: Player)
	local session = sessions[player]
	if session == nil or session.summary ~= nil then
		return
	end
	if not session.atEasel then
		refuse(player, session, "You have to be at the easel to sign it.")
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	finish(player, Lives.Active(profile.Data), session, "signed")
	releaseWallIfEmpty()
end

-- Reads where the player is standing onto the session. Everything the click handlers
-- allow or refuse is decided from these two, worked out once a tick in one place rather
-- than re-probed per click.
local function readPosition(session: Session, position: Vector3)
	local room = Studio.Room()
	if room == nil then
		session.atEasel = false
		session.atCupboard = false
		return
	end
	session.atEasel = Ground.FlatDistance(position, room.easel) <= ART.EaselRadiusStuds
	session.atCupboard = Ground.FlatDistance(position, room.cupboard) <= ART.CupboardRadiusStuds
end

local function tickPlayer(player: Player, elapsed: number)
	local session = sessions[player]
	if session == nil then
		return
	end

	-- The closing line, held, and then the canvas is gone. First because everything below
	-- it is about a lesson that is still running, and this one is not.
	if session.summary ~= nil then
		session.verdictLeft -= elapsed
		if session.verdictLeft <= 0 then
			forget(player)
			ArtUpdatedRemote:FireClient(player, nil)
			releaseWallIfEmpty()
		end
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)

	if not data.alive or not enabled then
		finish(player, data, session, "left")
		return
	end

	local position = characterPosition(player)
	if position == nil then
		-- No body, so no clock. A character mid-respawn cannot paint and cannot walk to the
		-- cupboard, and running the canvas down through those frames would be charging the
		-- player for the engine. Death is caught by the branch above, so this cannot be
		-- held open on purpose.
		return
	end

	readPosition(session, position)

	local room = Studio.Room()
	if room ~= nil and Ground.FlatDistance(position, room.center) > ART.RoomRadiusStuds then
		finish(player, data, session, "left")
		return
	end

	-- Filling the pot is instant on arrival rather than held, which is the one place this
	-- deliberately parts company with the lab's cupboard. There a refill is a spot you
	-- stand in for two seconds; here the cost is already paid in full by the walk itself --
	-- the wall is behind you the whole way -- and charging a dwell on top would be pricing
	-- the same interruption twice.
	if session.atCupboard and session.strokes < ART.StrokesPerRefill then
		session.strokes = ART.StrokesPerRefill
		session.notice = nil
		session.noticeLeft = 0
	end

	if session.noticeLeft > 0 then
		session.noticeLeft -= elapsed
		if session.noticeLeft <= 0 then
			session.notice = nil
			session.noticeLeft = 0
		end
	end

	session.secondsLeft -= elapsed
	if session.secondsLeft <= 0 then
		session.secondsLeft = 0
		finish(player, data, session, "time")
		return
	end

	push(player)
end

-- The wall's own clock, run once per tick rather than once per player. The study is shared
-- furniture, so a shift is one event that everybody in the room sees -- ticking it per
-- session would shift the picture once per painter and make a class of three rot three
-- times as fast as a class of one.
local function tickWall(elapsed: number)
	local current = wall
	if current == nil then
		return
	end

	local painting = false
	for _, session in sessions do
		if session.summary == nil then
			painting = true
			break
		end
	end
	if not painting then
		-- The light does not move in an empty room. Not an optimisation: without this a
		-- study left up between lessons would drift into something nobody authored, and the
		-- first player through the door would be copying six minutes of random walk.
		return
	end

	current.secondsToShift -= elapsed
	if current.secondsToShift > 0 then
		return
	end
	current.secondsToShift = ART.ShiftSeconds
	for _ = 1, ART.ShiftCells do
		shiftOne(current)
	end
end

function ArtService.IsRunning(player: Player): boolean
	return sessions[player] ~= nil
end

-- A new life. Nobody inherits an education, and the mastery ladder is per life for the
-- same reason bonds and money are.
function ArtService.ResetForNewLife(player: Player)
	forget(player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		Mastery.Clear(Lives.Active(profile.Data), SUBJECT_ID)
	end
	releaseWallIfEmpty()
	ArtUpdatedRemote:FireClient(player, nil)
end

-- Studio harness: opens a canvas wherever the player is standing, skipping the walk to
-- school but nothing else. The room is still the built one, so the wall and the cupboard
-- are where they actually are -- a harness that also moved the furniture would be testing
-- a room that does not exist.
function ArtService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	return ArtService.Begin(player, Lives.Active(profile.Data))
end

-- Studio harness: signs the canvas from wherever the player is. Skips the easel check that
-- the real remote enforces, because the thing being tested is the scoring and not the
-- radius.
function ArtService.ForceSign(player: Player): boolean
	local session = sessions[player]
	if session == nil or session.summary ~= nil then
		return false
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	finish(player, Lives.Active(profile.Data), session, "signed")
	releaseWallIfEmpty()
	return true
end

-- Studio harness: moves the study now rather than waiting out the timer. The single most
-- useful command in this file -- the shift is the mechanic, and a tester who has to stand
-- around for eighteen seconds to see one will only ever see two of them.
function ArtService.ForceShift(): boolean
	local current = wall
	if current == nil then
		return false
	end
	shiftOne(current)
	for player in sessions do
		push(player)
	end
	return true
end

-- Studio harness: fills the pot without the walk. The trip is the point, so this exists to
-- take it *out* of the way while something else is being tested, not to make it optional.
function ArtService.Refill(player: Player): boolean
	local session = sessions[player]
	if session == nil or session.summary ~= nil then
		return false
	end
	session.strokes = ART.StrokesPerRefill
	push(player)
	return true
end

function ArtService.ForceEnd(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	local profile = DataService.GetProfile(player)
	if profile ~= nil and session.summary == nil then
		finish(player, Lives.Active(profile.Data), session, "left")
	end
	forget(player)
	ArtUpdatedRemote:FireClient(player, nil)
	releaseWallIfEmpty()
	return true
end

-- Studio harness: sets the rung directly. The whole ladder in two commands, which is the
-- only practical way to judge whether the palette reward reads as a reward -- and a live
-- session's palette is re-cut on the spot rather than at the next lesson, because a tester
-- who has to start a new canvas to see the change is comparing two different pictures.
function ArtService.SetLevel(player: Player, level: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local data = Lives.Active(profile.Data)
	Mastery.Set(data, SUBJECT_ID, level)

	local session = sessions[player]
	if session ~= nil then
		session.level = levelOf(data)
		session.passes = passesOf(data)
		session.palette = paletteFor(session.study, session.level)
		-- The tube in hand may have just been taken away by a level going down. Dropped
		-- rather than clamped: a held index that silently means a different colour is how a
		-- player ends up painting with something they did not choose.
		session.held = nil
		push(player)
	end
	return true
end

function ArtService.SetEnabled(value: boolean)
	enabled = value
end

function ArtService.IsEnabled(): boolean
	return enabled
end

-- One line of truth for the debug command, and it says the things that are otherwise
-- invisible: what is on the wall, how long until it moves, and how much of the canvas is
-- stale -- which is precisely the number the player is never shown a list for.
function ArtService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "art: no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local level = levelOf(data)

	local onWall = "nothing"
	local current = wall
	if current ~= nil then
		onWall = `"{current.study.name}" ({current.study.id}), {#current.study.movable} cells can move,`
			.. ` next shift in {string.format("%.1f", math.max(0, current.secondsToShift))}s`
	end

	local running = "no canvas"
	local session = sessions[player]
	if session ~= nil then
		local truth = truthFor(session)
		local stale, filled = tally(session, truth)
		local tubes: { string } = {}
		for _, tube in session.palette do
			table.insert(tubes, tube.id)
		end
		running = `canvas {string.format("%.0f", canvasShare(session, truth) * 100)}%,`
			.. ` {filled}/{CELLS} filled, {stale} stale, {session.strokes}/{ART.StrokesPerRefill} strokes,`
			.. ` {string.format("%.1f", math.max(0, session.secondsLeft))}s left,`
			.. ` palette [{table.concat(tubes, " ")}]`
			.. if session.summary ~= nil then ", closing" else ""
	end

	return string.format(
		"art: %s | wall: %s | mastery level %d/%d, %d/%d passes%s, ceiling %.3f | %s",
		if enabled then "enabled" else "DISABLED",
		onWall,
		level,
		Mastery.Levels,
		passesOf(data),
		Mastery.PassesPerLevel,
		if Mastery.IsTopped(data, SUBJECT_ID) then " (topped out -- can skip)" else "",
		if session ~= nil then ceilingFor(session.study, level) else 0,
		running
	)
end

function ArtService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		forget(player)
		releaseWallIfEmpty()
	end)

	RequestArtPaintRemote.OnServerEvent:Connect(function(player: Player, cellIndex: unknown, pigmentId: unknown)
		local ok, err = pcall(onPaintRequested, player, cellIndex, pigmentId)
		if not ok then
			warn(`[AGES] art paint failed for {player.Name}: {err}`)
		end
	end)

	RequestArtSignRemote.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(onSignRequested, player)
		if not ok then
			warn(`[AGES] art sign failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(ART.TickSeconds)
			-- The wall first, then the painters. Order matters by exactly one tick: a shift
			-- landing before the pushes means the stale count a player is shown already
			-- includes it, rather than arriving a quarter of a second after the square on
			-- the wall visibly changed.
			local ok, err = pcall(tickWall, elapsed)
			if not ok then
				warn(`[AGES] art wall tick failed: {err}`)
			end
			for _, player in Players:GetPlayers() do
				local fine, problem = pcall(tickPlayer, player, elapsed)
				if not fine then
					warn(`[AGES] art tick failed for {player.Name}: {problem}`)
				end
			end
		end
	end)
end

return ArtService
