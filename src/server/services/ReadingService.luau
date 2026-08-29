--!strict
-- Reading: the lesson where the answer is built rather than picked.
--
-- Two words stand on the board with letters missing, and there is one tray of tiles between
-- them. That is the whole design. It is almost always obvious *which letter* goes in a gap
-- -- that is not the question and was never meant to be -- and the question the player is
-- actually answering, forty times a lesson, is **which word to spend it on**.
--
-- Two queues at half load each, which the activity law says is far more engaging than one
-- at full, bought with one shared tray rather than with a second minigame. One target would
-- be a conveyor belt: every placement forced, no decision anywhere in it.
--
-- The technique nothing teaches and nothing shows: fill the word that needs the rarer
-- letters first. A player who has not noticed still finishes most lessons; a player who has
-- finishes more. That is the shape a discovered optimum is supposed to have, and it is why
-- the tray carries decoys and a little slack rather than exactly the letters required.
--
-- What mastery buys is takebacks, and nothing else. Not shorter words, not more time, not a
-- bigger tray -- the number of times you may pull a placed tile back out, counted on screen.
-- Requirement six of the activity law is that progression must widen the player\'s own
-- tolerance somewhere they can *see*, and a hidden multiplier or a wage would be invisible
-- inside the verb. Difficulty comes from the age band instead and lives entirely in
-- content/Words.luau.
--
-- Failure is soft everywhere. A word can be handed in half-built and scores the letters
-- that are right; the lesson can be walked away from and scores what came back. Nothing
-- here can take away a rung already earned, and there is no state a player has to wait
-- their way out of.
--
-- Split three ways like the rest of school: ReadingRoom lays the desk and the shelf,
-- content/Words.luau is the bank, and this file is the only thing that knows how a board is
-- dealt or scored. It pays the ladder and the year itself, exactly as Science, Geography
-- and Art do, because SchoolService deliberately does not know how any verb is graded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Mastery = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Mastery"))
local Report = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Report"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlaceService = require(script.Parent.PlaceService)
local SkillService = require(script.Parent.SkillService)
local StatService = require(script.Parent.StatService)
local ReadingRoom = require(script.Parent.Parent.world.ReadingRoom)
local School = require(script.Parent.Parent.world.School)
local Words = require(script.Parent.Parent.content.Words)

type LifeData = Types.LifeData
type ReadingState = Types.ReadingState
type WordCell = Types.WordCell
type WordTarget = Types.WordTarget
type TrayTile = Types.TrayTile
type Word = Words.Word

local ReadingService = {}

local ReadingUpdatedRemote = Remotes.Get("ReadingUpdated")
local RequestReadingPlaceRemote = Remotes.Get("RequestReadingPlace")
local RequestReadingSubmitRemote = Remotes.Get("RequestReadingSubmit")

local READING = Config.School.Reading
local TRAY = READING.Tray

-- The subject id this service answers to. A constant rather than a parameter because there
-- is exactly one building subject; the day there is a second, this becomes an argument and
-- nothing else here changes.
local SUBJECT_ID = "reading"

-- The place id the room answers to, the same one the lessons and the corridor use.
local PLACE_ID = "school"

-- The two ladders have to be the same length, and this is the only place that can notice. A
-- sixth rung on one and not the other is a promotion the verb has no answer for -- the
-- player is told they levelled up and the takeback count does not change -- which is the
-- numbers-only progression this rebuild exists to remove, arriving by accident. Art keeps
-- the same guard on its palette for the same reason.
if #READING.TakebacksByLevel ~= Mastery.Levels then
	error(
		`[AGES config] Config.School.Reading.TakebacksByLevel has {#READING.TakebacksByLevel} entries`
			.. ` but the mastery ladder has {Mastery.Levels} rungs. Every rung has to buy something`
			.. ` here, or a level-up is a message with nothing behind it.`
	)
end

-- One word on the board, server side. Holds the truth, which is the one thing the pushed
-- shape must never carry: the client is sent the gaps and the tray, and what goes in which
-- gap is the lesson.
type LiveTarget = {
	word: Word,
	cells: { WordCell },
	done: boolean,
}

type Session = {
	targets: { LiveTarget },
	tray: { TrayTile },
	-- The tile in hand, by id, or nil. Held here rather than on the client because the
	-- placement is scored server side, and a tile the client believed it was holding would be
	-- a placement refused for no visible reason.
	held: string?,
	takebacks: number,
	-- The words still to be dealt onto the board, in order.
	pool: { Word },
	wordsDone: number,
	-- Fixed the moment the lesson is dealt: every gap in every word the lesson intends to
	-- ask, including the ones never reached. The denominator, so walking out early scores
	-- what came back rather than what was attempted -- the same rule Art scores a canvas by.
	gapsTotal: number,
	gapsCorrect: number,
	endsAt: number,
	levelAtStart: number,
	atDesk: boolean,
	atShelf: boolean,
	line: string,
	nextId: number,
}

local sessions: { [Player]: Session } = {}
local pushed: { [Player]: string } = {}
local notices: { [Player]: { text: string, until_: number } } = {}
local enabled = true
local roomBuilt = false

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil then
		return nil
	end
	return root.Position
end

local function ageYearsOf(data: LifeData): number
	return math.floor(data.ageMonths / Config.Time.MonthsPerYear)
end

local function levelOf(data: LifeData): number
	return Mastery.LevelOf(data, SUBJECT_ID)
end

-- Lays the room once the school has streamed in. Retried rather than given up on, for the
-- reason SchoolService retries its own: the building may still be arriving.
local function ensureRoom(): boolean
	if roomBuilt then
		return ReadingRoom.Room() ~= nil
	end
	local place = PlaceService.Find(PLACE_ID)
	if place == nil then
		return false
	end
	roomBuilt = true
	-- Raises the building if nobody has yet. Idempotent, and called from here as well as from
	-- SchoolService so that a Reading lesson forced from the debug console before anybody has
	-- walked to school still finds a room to stand in.
	School.Build(place.part.Position)
	return ReadingRoom.Build(School.RoomAt("reading") or place.part.Position) ~= nil
end

local function notice(player: Player, text: string)
	notices[player] = { text = text, until_ = os.clock() + Config.UI.NoticeSeconds }
end

-- Fisher-Yates, in place. Written out rather than reached for because there is no shuffle in
-- the standard library and a sort with a random comparator is not one -- it biases, and the
-- bias here would show up as the same letter always landing in the same corner of the tray.
local function shuffle<T>(list: { T })
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Cuts a word into cells with `gaps` of its letters taken out.
--
-- Never takes the first letter. A word missing its opening letter is materially harder to
-- recognise than one missing any other, which would make the difficulty depend on which
-- position the shuffle happened to pick rather than on the age band -- and two lessons of
-- the same word would not be the same lesson.
local function cutWord(word: Word): { WordCell }
	local letters = string.split(word.word, "")
	local positions: { number } = {}
	for index = 2, #letters do
		table.insert(positions, index)
	end
	shuffle(positions)

	local hidden: { [number]: boolean } = {}
	for index = 1, math.min(word.gaps, #positions) do
		hidden[positions[index]] = true
	end

	local cells: { WordCell } = {}
	for index, letter in letters do
		if hidden[index] then
			table.insert(cells, { letter = "", placed = false, gap = true })
		else
			table.insert(cells, { letter = letter, placed = false, gap = false })
		end
	end
	return cells
end

-- Every letter the board is currently short of, across both words.
local function neededLetters(session: Session): { string }
	local out: { string } = {}
	for _, target in session.targets do
		if not target.done then
			local letters = string.split(target.word.word, "")
			for index, cell in target.cells do
				if cell.gap then
					table.insert(out, letters[index])
				end
			end
		end
	end
	return out
end

local function nextId(session: Session): string
	session.nextId += 1
	return `t{session.nextId}`
end

-- Tops the tray back up to size: every letter the board is short of that is not already
-- sitting unspent in the tray, plus decoys, shuffled.
--
-- **Spent tiles are replaced and unspent ones are kept.** That is what makes a trip to the
-- shelf a refill rather than a reroll: a player who does not like the tray they were dealt
-- cannot walk over and ask for a different one, they can only replace what they have
-- already used. Without that the allocation this whole subject is built on is optional.
local function fillTray(session: Session)
	local kept: { TrayTile } = {}
	for _, tile in session.tray do
		if not tile.spent then
			table.insert(kept, tile)
		end
	end

	-- What the board still needs, minus what is already in hand on the tray.
	local have: { [string]: number } = {}
	for _, tile in kept do
		have[tile.letter] = (have[tile.letter] or 0) + 1
	end

	local wanted: { string } = {}
	for _, letter in neededLetters(session) do
		local spare = have[letter] or 0
		if spare > 0 then
			have[letter] = spare - 1
		else
			table.insert(wanted, letter)
		end
	end

	local fresh: { TrayTile } = {}
	for _, letter in wanted do
		if #kept + #fresh >= TRAY.Size then
			break
		end
		table.insert(fresh, { id = nextId(session), letter = letter, spent = false })
	end

	-- Decoys, and everything left over after the needed letters are covered. Drawn from the
	-- alphabet rather than from the words on the board, because a decoy that is always a
	-- letter one of the two words wants is not a decoy, it is a spare.
	local alphabet = string.split("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "")
	while #kept + #fresh < TRAY.Size do
		table.insert(fresh, { id = nextId(session), letter = alphabet[math.random(1, #alphabet)], spent = false })
	end

	local tray: { TrayTile } = {}
	for _, tile in kept do
		table.insert(tray, tile)
	end
	for _, tile in fresh do
		table.insert(tray, tile)
	end
	shuffle(tray)
	session.tray = tray
end

-- Puts the next word from the pool onto the board in the slot that just came free. Leaves
-- the slot showing the finished word when the pool is empty, which is what "the lesson ran
-- out of words" should look like -- not a blank square.
local function dealNext(session: Session, slot: number)
	local word = table.remove(session.pool, 1)
	if word == nil then
		return
	end
	session.targets[slot] = { word = word, cells = cutWord(word), done = false }
end

local function tileById(session: Session, id: string): TrayTile?
	for _, tile in session.tray do
		if tile.id == id then
			return tile
		end
	end
	return nil
end

-- What the client is shown. Built fresh and compared as a string before sending, the same
-- throttle every other school channel uses.
local function stateFor(player: Player): ReadingState
	local session = sessions[player]
	if session == nil then
		local held = notices[player]
		local line = ""
		if held ~= nil and os.clock() < held.until_ then
			line = held.text
		else
			notices[player] = nil
		end
		return {
			active = false,
			line = line,
			targets = {},
			tray = {},
			heldTileId = nil,
			takebacks = 0,
			wordsDone = 0,
			wordsTarget = READING.WordsPerLesson,
			secondsLeft = 0,
			atDesk = false,
			atShelf = false,
			masteryLevel = 1,
		}
	end

	local targets: { WordTarget } = {}
	for index, target in session.targets do
		local cells: { WordCell } = {}
		for _, cell in target.cells do
			table.insert(cells, { letter = cell.letter, placed = cell.placed, gap = cell.gap })
		end
		table.insert(targets, { id = `w{index}`, cells = cells, done = target.done })
	end

	local profile = DataService.GetProfile(player)
	local level = if profile ~= nil then levelOf(Lives.Active(profile.Data)) else 1

	return {
		active = true,
		line = session.line,
		targets = targets,
		tray = session.tray,
		heldTileId = session.held,
		takebacks = session.takebacks,
		wordsDone = session.wordsDone,
		wordsTarget = READING.WordsPerLesson,
		secondsLeft = math.max(session.endsAt - os.clock(), 0),
		atDesk = session.atDesk,
		atShelf = session.atShelf,
		masteryLevel = level,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	local parts = { tostring(state.active), state.line, tostring(state.takebacks), tostring(state.wordsDone) }
	table.insert(parts, tostring(state.heldTileId))
	table.insert(parts, tostring(state.atDesk))
	table.insert(parts, tostring(state.atShelf))
	-- Whole seconds only. A clock compared to the millisecond counts as a change every tick
	-- and the throttle would do nothing at all.
	table.insert(parts, tostring(math.floor(state.secondsLeft)))
	for _, target in state.targets do
		for _, cell in target.cells do
			table.insert(parts, if cell.gap then "_" else cell.letter)
		end
		table.insert(parts, tostring(target.done))
	end
	for _, tile in state.tray do
		table.insert(parts, `{tile.letter}{if tile.spent then "-" else "+"}`)
	end

	local signature = table.concat(parts, "|")
	if pushed[player] == signature then
		return
	end
	pushed[player] = signature
	ReadingUpdatedRemote:FireClient(player, state)
end

-- Scores a word as it stands and banks the letters that are right. Called by handing one in
-- and by the clock running out, so an unfinished board is scored the same way a finished one
-- is -- there is no second calculation here to disagree with the first.
local function scoreTarget(session: Session, target: LiveTarget)
	if target.done then
		return
	end
	local letters = string.split(target.word.word, "")
	for index, cell in target.cells do
		if cell.placed and cell.letter == letters[index] then
			session.gapsCorrect += 1
		end
	end
	target.done = true
end

local function finish(player: Player, data: LifeData, session: Session, reason: string)
	-- Decided before anything is written, which is the idempotency rule this codebase runs
	-- on: work the outcome out, then record it.
	for _, target in session.targets do
		scoreTarget(session, target)
	end

	local share = if session.gapsTotal > 0 then session.gapsCorrect / session.gapsTotal else 0
	local band = Report.BandFor(share)
	local gained = Report.SmartsFor(band)

	sessions[player] = nil

	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	-- Banked once on the whole board rather than per word, for the reason Art banks once per
	-- canvas: a lesson is a lesson. Paying the ladder six times would make Reading climb at
	-- six times every other subject\'s rate and top out inside a single afternoon.
	Mastery.Record(data, SUBJECT_ID, share)

	local earned = math.floor(Config.Skills.Awards.WordBuilt * session.wordsDone)
	if earned > 0 then
		SkillService.Award(player, "academics", earned, "finished a word")
	end

	-- Counted however it ended, including walked away from, for the reason every other
	-- lesson is: otherwise a player could start, look at the board, leave, and start again
	-- until they were dealt words they liked.
	data.lessonsThisYear += 1
	EventService.AwardAutonomy(player, 1)

	local level = levelOf(data)
	Report.RecordLesson(data, SUBJECT_ID, band, gained, if level > session.levelAtStart then level else nil)

	local percent = math.floor(share * 100 + 0.5)
	local opening = if reason == "handed"
		then "You handed the board in."
		elseif reason == "left" then "You walked away from it."
		else "Time."
	local reward = if gained > 0 then `. +{gained} smarts.` else "."
	notice(player, `{opening} {session.wordsDone} of {READING.WordsPerLesson} words, {percent}%{reward}`)
	push(player)
end

-- Takes a tile, puts the one in hand into a gap, or pulls a placed one back out.
--
-- One entry point for all three because they are one verb with a target, and splitting them
-- would mean three remotes that can disagree about what is in the player\'s hand.
local function onPlaceRequested(player: Player, targetIndex: unknown, cellIndex: unknown)
	local session = sessions[player]
	if session == nil then
		return
	end
	if not session.atDesk then
		notice(player, "You have to be at the desk.")
		push(player)
		return
	end

	-- A tile id rather than a board position: picking up.
	if typeof(targetIndex) == "string" then
		local tile = tileById(session, targetIndex)
		if tile == nil or tile.spent then
			return
		end
		-- Tapping the tile already in hand puts it down, which is the only way to change your
		-- mind without spending a takeback.
		session.held = if session.held == targetIndex then nil else targetIndex
		push(player)
		return
	end

	if typeof(targetIndex) ~= "number" or typeof(cellIndex) ~= "number" then
		return
	end
	local target = session.targets[targetIndex]
	if target == nil or target.done then
		return
	end
	local cell = target.cells[cellIndex]
	if cell == nil then
		return
	end

	-- A filled gap: the takeback. Free until they run out, and the tile comes back unspent --
	-- that is what makes it a takeback rather than an apology.
	if cell.placed then
		if session.takebacks <= 0 then
			notice(player, "No takebacks left.")
			push(player)
			return
		end
		for _, tile in session.tray do
			if tile.spent and tile.letter == cell.letter then
				tile.spent = false
				break
			end
		end
		session.takebacks -= 1
		cell.letter = ""
		cell.placed = false
		cell.gap = true
		push(player)
		return
	end

	if not cell.gap then
		-- One of the word\'s own letters. Not an error worth a line: the player tapped a
		-- square that was never theirs to fill.
		return
	end

	local heldId = session.held
	if heldId == nil then
		return
	end
	local tile = tileById(session, heldId)
	if tile == nil or tile.spent then
		session.held = nil
		push(player)
		return
	end

	-- The placement. Not scored here and deliberately not told to the player either: a gap
	-- that turned green on a right letter would do the reading for them, and the subject is
	-- looking at the word and seeing what it is missing.
	cell.letter = tile.letter
	cell.placed = true
	cell.gap = false
	tile.spent = true
	session.held = nil
	push(player)
end

-- Hands a word in. The commit, and the only irreversible act in the lesson.
local function onSubmitRequested(player: Player, targetIndex: unknown)
	local session = sessions[player]
	if session == nil or typeof(targetIndex) ~= "number" then
		return
	end
	if not session.atDesk then
		notice(player, "You have to be at the desk.")
		push(player)
		return
	end
	local target = session.targets[targetIndex]
	if target == nil or target.done then
		return
	end

	scoreTarget(session, target)
	session.wordsDone += 1
	dealNext(session, targetIndex)
	fillTray(session)
	push(player)

	if session.wordsDone >= READING.WordsPerLesson then
		local profile = DataService.GetProfile(player)
		if profile ~= nil then
			finish(player, Lives.Active(profile.Data), session, "handed")
		end
	end
end

local function tickPlayer(player: Player, _dt: number)
	local session = sessions[player]
	if session == nil then
		push(player)
		return
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end

	local position = characterPosition(player)
	local room = ReadingRoom.Room()
	if position ~= nil and room ~= nil then
		session.atDesk = (position - room.desk).Magnitude <= TRAY.ReachStuds
		local atShelf = (position - room.shelf).Magnitude <= TRAY.ReachStuds
		-- Arriving at the shelf is what draws tiles, not standing at it. Otherwise a player
		-- who parked there would be handed a fresh tray every tick, which is the reroll the
		-- refill rule exists to prevent.
		if atShelf and not session.atShelf then
			fillTray(session)
			notice(player, "You took a fresh handful.")
		end
		session.atShelf = atShelf
	end

	if os.clock() >= session.endsAt then
		finish(player, Lives.Active(profile.Data), session, "time")
		return
	end
	push(player)
end

-- Starts a lesson. The contract SchoolService dispatches against, and the same one Science,
-- Geography and Art hold: refuse with a line worth saying out loud, or take the afternoon.
function ReadingService.Begin(player: Player, data: LifeData): (boolean, string?)
	if sessions[player] ~= nil then
		return false, "You are already at the desk."
	end
	if not enabled then
		return false, "There is no reading today."
	end
	if not ensureRoom() then
		return false, "The reading room is closed today."
	end

	local pool = Words.ForAge(ageYearsOf(data))
	if #pool < READING.WordsPerLesson then
		-- Impossible if the content file loaded, which checks every age has enough. Reachable
		-- only if the bank is thinned without the check being updated, and the honest thing is
		-- to say so rather than deal a board with nothing on it.
		return false, "There is nothing on the board today."
	end

	local chosen: { Word } = {}
	for _, word in pool do
		table.insert(chosen, word)
	end
	shuffle(chosen)
	while #chosen > READING.WordsPerLesson do
		table.remove(chosen)
	end

	local gapsTotal = 0
	for _, word in chosen do
		gapsTotal += word.gaps
	end

	local level = levelOf(data)
	local session: Session = {
		targets = {},
		tray = {},
		held = nil,
		takebacks = READING.TakebacksByLevel[level],
		pool = chosen,
		wordsDone = 0,
		gapsTotal = gapsTotal,
		gapsCorrect = 0,
		endsAt = os.clock() + READING.SecondsPerLesson,
		levelAtStart = level,
		atDesk = false,
		atShelf = false,
		line = "Two words. One tray. Spend it well.",
		nextId = 0,
	}

	for slot = 1, READING.TargetsAtOnce do
		dealNext(session, slot)
	end
	fillTray(session)

	sessions[player] = session
	notices[player] = nil
	push(player)
	return true
end

local function forget(player: Player)
	sessions[player] = nil
	notices[player] = nil
	pushed[player] = nil
end

function ReadingService.ResetForNewLife(player: Player)
	forget(player)
	push(player)
end

-- Debug: start a lesson from where the player stands.
function ReadingService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	return ReadingService.Begin(player, Lives.Active(profile.Data))
end

-- Debug: grade the board where it stands, the way walking out does.
function ReadingService.ForceEnd(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	finish(player, Lives.Active(profile.Data), session, "left")
	return true
end

-- Debug: fill every gap on the board correctly, so the scoring and the hand-in can be
-- reached without spelling six words by hand.
function ReadingService.Solve(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	for _, target in session.targets do
		if not target.done then
			local letters = string.split(target.word.word, "")
			for index, cell in target.cells do
				if cell.gap then
					cell.letter = letters[index]
					cell.placed = true
					cell.gap = false
				end
			end
		end
	end
	push(player)
	return true
end

function ReadingService.SetEnabled(value: boolean)
	enabled = value
end

function ReadingService.IsEnabled(): boolean
	return enabled
end

function ReadingService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local room = ReadingRoom.Room()
	local lines = {
		`enabled: {enabled}`,
		`mastery: {levelOf(data)}/{Mastery.Levels}  takebacks at that level: {READING.TakebacksByLevel[levelOf(data)]}`,
		`room: {if room ~= nil then "laid" else "not laid yet"}`,
	}
	local session = sessions[player]
	if session == nil then
		table.insert(lines, "no lesson running")
	else
		table.insert(
			lines,
			`words {session.wordsDone}/{READING.WordsPerLesson}`
				.. `  gaps {session.gapsCorrect}/{session.gapsTotal}`
				.. `  takebacks {session.takebacks}`
				.. `  {math.floor(math.max(session.endsAt - os.clock(), 0))}s left`
				.. `  desk={session.atDesk} shelf={session.atShelf}`
		)
		for index, target in session.targets do
			local shown = {}
			for _, cell in target.cells do
				table.insert(shown, if cell.gap then "_" else cell.letter)
			end
			table.insert(lines, `  {index}: {table.concat(shown, "")}  (answer {target.word.word}) done={target.done}`)
		end
	end
	return table.concat(lines, "\n")
end

function ReadingService:Start()
	Players.PlayerRemoving:Connect(forget)

	RequestReadingPlaceRemote.OnServerEvent:Connect(function(player: Player, targetIndex: unknown, cellIndex: unknown)
		local ok, err = pcall(onPlaceRequested, player, targetIndex, cellIndex)
		if not ok then
			warn(`[AGES] reading place failed for {player.Name}: {err}`)
		end
	end)

	RequestReadingSubmitRemote.OnServerEvent:Connect(function(player: Player, targetIndex: unknown)
		local ok, err = pcall(onSubmitRequested, player, targetIndex)
		if not ok then
			warn(`[AGES] reading submit failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(READING.TickSeconds)
			ensureRoom()
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] reading tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return ReadingService
