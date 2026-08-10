--!strict
-- What a workplace looks like when it is hiring *you*.
--
-- A job used to be invisible. The place point existed, WorkService knew a job was
-- attached to it, and the player knew nothing at all: you were hired by walking
-- within a few studs of an unremarkable part, silently, and the first news of it was
-- a job title appearing on the HUD. Everything the game knew, it kept to itself.
--
-- So a post is two objects, and they answer two different questions:
--
--   The sign answers "is there work here, and could it ever be for me?" from far
--   enough away to decide whether to walk over.
--
--   The pad answers "how do I take it?" It is a choice marker, deliberately the
--   same gold breathing disc used by the classroom door and the shift mark, because
--   the disc now says exactly one thing everywhere it appears: go here. Choices are
--   made on a panel, so nothing gold is ever a question -- it is always a place.
--   Taking a job is not a new verb; it is a walk, which is the first verb they
--   learned.
--
-- Drawn on the client, and that is the whole reason this file moved here from the
-- server. A post is not scenery, it is an offer, and an offer is addressed to
-- somebody: the one thing a hiring sign must do is stop existing for the person who
-- accepted it. Standing behind your own counter for the rest of your life with NOW
-- HIRING over your head and a gold "take the job" disc under your feet is the game
-- failing to notice you did the thing it asked.
--
-- One shared object in the workspace physically cannot do that, so the server sends
-- each player the posts *they* should see and this builds them. Nothing here decides
-- anything; every word on the sign was chosen by WorkService.
--
-- The second thing being per-player buys is that the pad can now be honest. A shared
-- pad had to invite everyone, because it had no idea who was looking at it. This one
-- knows, so a job you are too young for is a grey, still mark that says why -- the
-- same locked state every unaffordable choice in the game already uses, so the
-- player has to learn nothing new to read it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local ChoiceMarkers = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("ChoiceMarkers"))

type JobPostState = Types.JobPostState

local JobPosts = {}

-- Cosmetic, and kept out of Config for the reason ChoiceMarkers gives: nobody
-- balances the game by changing how big the word "HIRING" is. The two numbers here
-- that are balanced -- how high the sign floats and how far off it can be read --
-- are Config.Work.Hiring's, and they are read below.
local SIGN_WIDTH_STUDS = 11
local SIGN_HEIGHT_STUDS = 3.2

local HEADLINE_TEXT_SIZE = 13
local TITLE_TEXT_SIZE = 20
local TERM_TEXT_SIZE = 13

-- The headline is the smallest text on a sign whose whole job is to be read from
-- far away, which looks backwards written down and is right in practice: at fifty
-- studs you are reading the shape of the thing, and "Shop assistant" in large type
-- over two small lines reads as a sign at a glance. "NOW HIRING" in large type would
-- shout the one word that is the same on every sign in the game.
local HEADLINE_COLOR = Color3.fromRGB(150, 220, 160)
local TITLE_COLOR = Color3.fromRGB(255, 250, 240)
local TERM_COLOR = Color3.fromRGB(214, 208, 196)
local STROKE_COLOR = Color3.fromRGB(20, 18, 14)
local STROKE_THICKNESS = 2

-- A post for a job the player cannot take yet is still worth standing there -- it is
-- how a twelve-year-old learns the shop exists -- but it should not shout. Muted to
-- match the grey the locked pad below it wears, so the sign and the mark agree.
local HEADLINE_LOCKED_COLOR = Color3.fromRGB(150, 148, 142)
local TITLE_LOCKED_COLOR = Color3.fromRGB(200, 196, 188)

-- Vertical shares of the sign. The title gets the most because it is the only line
-- that has to survive being read at distance.
local HEADLINE_HEIGHT = 0.22
local TITLE_HEIGHT = 0.44
local TERMS_HEIGHT = 0.34

-- Everything built for one job, kept only so it can be taken down again.
type Post = {
	anchor: Part,
	pad: ChoiceMarkers.ChoiceMarker,
}

export type Board = {
	-- The posts the player should be looking at, in full. A whole list each time
	-- rather than a diff, for the reason every other push in this game is a whole
	-- snapshot: a dropped message is corrected by the next one instead of leaving a
	-- sign standing over a job the player took ten minutes ago.
	Set: (states: { JobPostState }) -> (),
	Destroy: () -> (),
}

local function outline(into: Instance)
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Thickness = STROKE_THICKNESS
	stroke.Parent = into
end

local function line(
	into: BillboardGui,
	name: string,
	text: string,
	size: number,
	color: Color3,
	font: Enum.Font,
	height: number,
	offset: number
)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, height, 0)
	label.Position = UDim2.new(0, 0, offset, 0)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextWrapped = true
	label.Text = text
	label.Parent = into
	outline(label)
end

-- `state.position` is the job's place point -- the floor at the counter. The sign
-- floats above it and the pad is painted on it, so moving the part in Studio moves
-- the whole post and nothing in code needs to know where the shop is.
local function build(parent: Instance, state: JobPostState): Post
	local hiring = Config.Work.Hiring

	-- An anchor for the sign rather than hanging it off the pad, because the two are
	-- independent: the pad is a choice marker built by machinery that knows nothing
	-- about signs, and a later post may want a sign with no pad under it at all --
	-- a workplace advertising a job that is not open to anybody yet.
	local anchor = Instance.new("Part")
	anchor.Name = `JobPost_{state.jobId}`
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(state.position + Vector3.new(0, hiring.SignLiftStuds, 0))
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
	billboard.Size = UDim2.new(SIGN_WIDTH_STUDS, 0, SIGN_HEIGHT_STUDS, 0)
	-- Drawn through the building it is inside. This is the one piece of world text
	-- where seeing it through a wall is the entire point rather than a compromise: a
	-- sign you can only read once you have found the counter is a sign for people who
	-- did not need it. Discovery is the job.
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = hiring.SignMaxDistanceStuds
	billboard.Parent = anchor

	local locked = state.padLocked
	line(
		billboard,
		"Headline",
		state.headline,
		HEADLINE_TEXT_SIZE,
		if locked then HEADLINE_LOCKED_COLOR else HEADLINE_COLOR,
		Enum.Font.GothamBold,
		HEADLINE_HEIGHT,
		0
	)
	line(
		billboard,
		"Title",
		state.title,
		TITLE_TEXT_SIZE,
		if locked then TITLE_LOCKED_COLOR else TITLE_COLOR,
		Enum.Font.GothamBold,
		TITLE_HEIGHT,
		HEADLINE_HEIGHT
	)
	line(
		billboard,
		"Terms",
		table.concat(state.terms, "  ·  "),
		TERM_TEXT_SIZE,
		TERM_COLOR,
		Enum.Font.GothamMedium,
		TERMS_HEIGHT,
		HEADLINE_HEIGHT + TITLE_HEIGHT
	)

	-- Locked when the server says this player would be turned away. The mark is still
	-- painted -- you should be able to see the job you are two years short of and go
	-- and get older -- but it holds its breath instead of breathing, which among the
	-- gold pads elsewhere in the game is unmistakable.
	--
	-- No cost, ever: a job is the one choice in this game you are paid for rather than
	-- charged for, and putting a price under it would read as a fee to apply.
	local pad = ChoiceMarkers.Build(parent, state.position, hiring.PadRadiusStuds, {
		label = state.padLabel,
		locked = locked,
	})

	return { anchor = anchor, pad = pad }
end

-- What would have to change for a standing post to be wrong. Compared rather than
-- rebuilt on every push, because the server pushes on a tick and a sign that is torn
-- down and put back up four times a second is a sign that flickers.
local function signature(state: JobPostState): string
	return table.concat({
		state.headline,
		state.title,
		table.concat(state.terms, "|"),
		state.padLabel,
		tostring(state.padLocked),
		tostring(state.position),
	}, "\30")
end

function JobPosts.Board(): Board
	-- Parented to the workspace on the *client*, which never reaches the server or
	-- any other player. That is the entire privacy mechanism and it is worth being
	-- explicit about: nothing here is replicated because nothing here was made by
	-- anyone but this player's own machine.
	local folder = Instance.new("Folder")
	folder.Name = "AgesJobPosts"
	folder.Parent = workspace

	local built: { [string]: Post } = {}
	local signatures: { [string]: string } = {}

	local function remove(jobId: string)
		local post = built[jobId]
		if post == nil then
			return
		end
		post.pad.destroy()
		post.anchor:Destroy()
		built[jobId] = nil
		signatures[jobId] = nil
	end

	local board = {}

	function board.Set(states: { JobPostState })
		local wanted: { [string]: true } = {}

		for _, state in states do
			wanted[state.jobId] = true
			local want = signature(state)
			if signatures[state.jobId] == want then
				continue
			end
			-- Rebuilt rather than edited in place. A post has four pieces of text, a
			-- colour scheme and a pad state, and the number of times any of them change
			-- in one life is small enough that a targeted update would be more code than
			-- it saves -- and it is the kind of code that goes subtly stale the moment a
			-- fifth piece is added.
			remove(state.jobId)
			built[state.jobId] = build(folder, state)
			signatures[state.jobId] = want
		end

		for jobId in built do
			if not wanted[jobId] then
				-- Taken, or no longer offered. This is the line the whole move to the
				-- client was for.
				remove(jobId)
			end
		end
	end

	function board.Destroy()
		for jobId in built do
			remove(jobId)
		end
		folder:Destroy()
	end

	return board
end

return JobPosts
