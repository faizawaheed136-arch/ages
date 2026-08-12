--!strict
-- Where the police think you are, drawn on the street.
--
-- This is the signature mechanic of the whole crime system and it is worth being blunt
-- about why. A pursuit where the officers always know where you are is a race, and a
-- race against a slower opponent is not a game. What makes hiding a *decision* is that
-- the police work from a last known position -- see BountyService, which never once
-- reads where the player actually is -- and what makes that decision playable is being
-- able to see the wrong answer they are working from. A player who can see the ring
-- sitting over the alley they left ninety seconds ago knows two things at once: that
-- the last corner worked, and exactly which direction is about to get expensive.
--
-- So this is deliberately the opposite of HuntUI's rule. Geography refuses to put a
-- marker in the world because there the finding is the activity. Here the finding is
-- the *opponent's* activity, and showing the player their opponent's belief is showing
-- them the state of the game -- the same reason a chess board is not hidden.
--
-- Drawn on the client, like the guide, the hiring posts and the task marks, and for the
-- same reason: this is one person's manhunt. Two players robbing the same street would
-- otherwise stand in each other's search rings.
--
-- Nothing here decides anything. Deleting every part in the folder by hand would blind
-- the player and change nothing whatsoever about where the officers walk.

local Workspace = game:GetService("Workspace")

local SearchRing = {}

-- Cosmetic dimensions, kept out of Config for the reason ChoiceMarkers gives: the
-- thickness of a dash is not a number anyone balances the game with. The one number that
-- *is* balanced -- how wide the search actually is -- is passed in, because it belongs to
-- Config.Crime.Tiers where the rest of the difficulty lives.
local SEGMENTS = 36
-- Share of each segment's arc that is drawn rather than left as a gap. A broken ring
-- rather than a solid one, because a solid circle of light around a street corner reads
-- as a force field -- something you cannot cross -- and this is the opposite: a line you
-- are very much able to walk over, at a price.
local DASH_SHARE = 0.62
local DASH_THICKNESS = 0.9
local DASH_HEIGHT = 0.35
-- The sighting position is roughly a standing player's centre, so the ring drops to about
-- where their feet were. Approximate on purpose: the alternative is a raycast per segment
-- every time the radius changes, to place a decoration.
local GROUND_DROP = 2.6

-- Amber while they are guessing, red while they are not. The two states of this whole
-- system in one colour, readable from across a street with no text attached.
local SEARCH_COLOR = Color3.fromRGB(238, 176, 74)
local SEEN_COLOR = Color3.fromRGB(226, 78, 74)

local RING_TRANSPARENCY = 0.35
local PIN_TRANSPARENCY = 0.5

-- The pin at the centre. Tall and thin, so it is findable over a low wall, and topped
-- with a billboard that is AlwaysOnTop -- the one piece of this that shows through
-- geometry, which it has to: the entire point is knowing where they are looking *from
-- inside the building you are hiding in*. The ring itself is honest scenery and occludes
-- normally, so at street level you see the line and indoors you see the pin.
local PIN_HEIGHT = 7
local PIN_THICKNESS = 0.5
local LABEL_LIFT = 2
local LABEL_WIDTH_STUDS = 12
local LABEL_HEIGHT_STUDS = 2
local LABEL_TEXT_SIZE = 15
local LABEL_STROKE = Color3.fromRGB(18, 14, 12)
local LABEL_STROKE_THICKNESS = 2

export type Handle = {
	-- The whole belief in one call: where they think you are, how far they will spread
	-- around it, and whether they are still guessing. Nil takes it off the street, which
	-- is both "no heat" and -- much more interestingly -- "nobody has any idea".
	Set: (lastKnown: Vector3?, radiusStuds: number, seen: boolean) -> (),
	Destroy: () -> (),
}

local function makePart(parent: Instance, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	-- Out of every ignore list in the game by construction. An officer's line of sight is
	-- a raycast, and a decoration that could block one would let the player hide behind
	-- their own HUD.
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Parent = parent
	return part
end

function SearchRing.new(): Handle
	local folder = Instance.new("Folder")
	folder.Name = "AgesSearchRing"
	folder.Parent = Workspace

	-- Everything is built hidden and at the origin. Building it visible would put a
	-- thirty-six part ring around the middle of the map for the frame between joining and
	-- the first push, which for a life that never commits a crime is every frame it has.
	local dashes: { Part } = {}
	for i = 1, SEGMENTS do
		local dash = makePart(folder, `Dash{i}`)
		dash.Transparency = 1
		dash.Color = SEARCH_COLOR
		dashes[i] = dash
	end

	local pin = makePart(folder, "Pin")
	pin.Size = Vector3.new(PIN_THICKNESS, PIN_HEIGHT, PIN_THICKNESS)
	pin.Transparency = 1
	pin.Color = SEARCH_COLOR

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PinLabel"
	billboard.Size = UDim2.new(LABEL_WIDTH_STUDS, 0, LABEL_HEIGHT_STUDS, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, PIN_HEIGHT / 2 + LABEL_LIFT, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Parent = pin

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = SEARCH_COLOR
	label.Text = "Last seen"
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = LABEL_STROKE
	stroke.Thickness = LABEL_STROKE_THICKNESS
	stroke.Parent = label

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = LABEL_TEXT_SIZE
	constraint.Parent = label

	-- What is currently drawn, so a ring that has not moved is left alone. The server
	-- pushes on a digest and the position is quantised to whole studs, but the radius and
	-- the colour change on their own schedule and rebuilding thirty-six parts because a
	-- boolean flipped is thirty-six parts of nothing.
	local shownAt: Vector3? = nil
	local shownRadius = -1
	local shownSeen = false
	local visible = false

	local handle = {}

	local function setVisible(on: boolean)
		if visible == on then
			return
		end
		visible = on
		for _, dash in dashes do
			dash.Transparency = if on then RING_TRANSPARENCY else 1
		end
		pin.Transparency = if on then PIN_TRANSPARENCY else 1
		billboard.Enabled = on
	end

	function handle.Set(lastKnown: Vector3?, radiusStuds: number, seen: boolean)
		if lastKnown == nil or radiusStuds <= 0 then
			setVisible(false)
			shownAt = nil
			shownRadius = -1
			return
		end

		setVisible(true)

		if seen ~= shownSeen then
			shownSeen = seen
			local color = if seen then SEEN_COLOR else SEARCH_COLOR
			for _, dash in dashes do
				dash.Color = color
			end
			pin.Color = color
			label.TextColor3 = color
			-- The word changes with it, because "last seen" is a lie while they are
			-- looking straight at you -- and being told so is the feedback that teaches
			-- the player what breaking line of sight is worth.
			label.Text = if seen then "They see you" else "Last seen"
		end

		local ground = Vector3.new(lastKnown.X, lastKnown.Y - GROUND_DROP, lastKnown.Z)
		if shownAt == ground and shownRadius == radiusStuds then
			return
		end
		shownAt = ground
		shownRadius = radiusStuds

		pin.CFrame = CFrame.new(ground + Vector3.new(0, PIN_HEIGHT / 2, 0))

		-- Arc length per segment, so the dashes stay in proportion as the radius grows
		-- with the tier. A fixed dash length would read as a dotted line at forty studs
		-- and as a solid circle at a hundred and sixty.
		local arc = (2 * math.pi * radiusStuds) / SEGMENTS
		local dashLength = math.max(arc * DASH_SHARE, DASH_THICKNESS)
		for i, dash in dashes do
			local angle = (i - 1) * (2 * math.pi / SEGMENTS)
			local offset = Vector3.new(math.cos(angle) * radiusStuds, 0, math.sin(angle) * radiusStuds)
			-- Turned to face the centre, which puts the part's own X axis along the
			-- tangent -- so the long dimension is X and not Z, which is the one thing in
			-- this file that looks like a typo and is not.
			dash.Size = Vector3.new(dashLength, DASH_HEIGHT, DASH_THICKNESS)
			dash.CFrame = CFrame.new(ground + offset, ground)
		end
	end

	function handle.Destroy()
		folder:Destroy()
	end

	return handle
end

return SearchRing
