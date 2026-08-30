--!strict
-- What something in the world looks like when it has something to say.
--
-- A badge on its chest: "E". You get near, it wakes up, you click it or press the
-- key and the options come up. That is the whole grammar and it is the same
-- grammar for a person, an animal and a lesson, because a player should have to
-- learn how to talk to this world exactly once.
--
-- Built on a real ProximityPrompt rather than a bare billboard and a distance
-- check. The prompt is doing three jobs that are all tedious to get right and all
-- invisible when they are right: it decides when the player is close enough, it
-- makes sure only one thing is offering itself at a time, and it turns a keyboard
-- press, a gamepad button and a screen tap into the same event. The last of those
-- is the one that matters most -- most people who play a Roblox game are holding a
-- phone -- and it is also the one that is easiest to forget until it is too late
-- to change.
--
-- The badge is a TextButton and not a decoration, which is why the tap works. On a
-- phone there is no key to press, so a custom-styled prompt that only listened for
-- one would be an object that is permanently unusable to most of the people looking
-- at it. Clicking the thing you can see is also simply the honest interface: the
-- player is told what the letter is and shown a thing shaped like it that can also
-- just be clicked, so a phone and a keyboard are reading the same object.
--
-- **The button is built here and connected in client/world/Prompts.luau, and it has
-- to be that way round.** Attach runs on the server for every NPC in the game, and a
-- connection made on the server to a GuiButton's Activated never fires -- clicking is
-- something that happens on one client, to that client's copy. Wiring it here would
-- look completely correct, replicate a button to everybody, and do nothing when
-- pressed, which is exactly the bug this comment exists to stop being written again.
--
-- Nothing here decides what the options are or what taking one does. This builds
-- the invitation and says who it came from; every caller keeps its own content.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local INTERACT = Config.Interact

-- Read by the client to decide who to ask about the options. An attribute rather
-- than a name so the prompt can be found by name alone, and so adding a fourth
-- kind of interactable never means parsing a string.
local KIND_ATTRIBUTE = "AgesInteractKind"
local ID_ATTRIBUTE = "AgesInteractId"

local PROMPT_NAME = "AgesInteract"
local DOTS_NAME = "AgesInteractDots"
local NAMEPLATE_NAME = "AgesInteractNameplate"

-- The clickable thing inside the badge billboard, and the badge frame itself. Named
-- constants rather than string literals at multiple call sites, because the client
-- has to find both by name across the server/client boundary and a typo in one of
-- them is a silent no-op rather than an error.
local DOTS_BUTTON_NAME = "Dots"
local BADGE_NAME = "Badge"

-- Cosmetic, and kept out of Config for the reason ChoiceMarkers gives: the size of
-- a badge is not a number anybody balances a life simulator with, and putting it
-- next to the numbers that are makes both harder to find.
local BADGE_SIZE = 0.7
-- The same gold ChoiceMarkers paints a choice pad and Interact's own panel style
-- paints its accent -- see PAD_COLOR in ChoiceMarkers.luau and DELIVERY_STYLES.Interact
-- in ChoicePanel.luau. Three different surfaces agreeing on one color is what makes it
-- read as "you can act on this" rather than as a badge that happens to be gold; a plain
-- off-white plate carried none of that meaning.
local BADGE_COLOR = Color3.fromRGB(245, 205, 120)
-- The gradient's lighter and darker ends, either side of BADGE_COLOR. Turns a flat
-- gold square into a struck coin -- light catching the top, the bottom falling into
-- its own shadow -- which is the cheapest read of "this is a raised, physical thing"
-- a Frame can give without a real light source.
local BADGE_COLOR_LIGHT = Color3.fromRGB(255, 234, 186)
local BADGE_COLOR_SHADOW = Color3.fromRGB(210, 164, 84)
local BADGE_STROKE = Color3.fromRGB(20, 18, 14)
local BADGE_TEXT_COLOR = Color3.fromRGB(20, 18, 14)

-- Asleep until you are near it. Dimmed rather than hidden, because a world where
-- interactable things are invisible until you are already touching them is a world
-- the player has to walk into wall-first to read.
local BADGE_FAR_TRANSPARENCY = 0.45
local BADGE_NEAR_TRANSPARENCY = 0
local BADGE_STROKE_FAR_TRANSPARENCY = 1
local BADGE_STROKE_NEAR_TRANSPARENCY = 0.1

-- The bob. One badge, one tween -- there is nothing left to stagger against.
local BADGE_BOB_SCALE = 0.08
local BADGE_BOB_SECONDS = 0.9

-- How much bigger the badge gets when the player is close enough to use it. Small
-- on purpose: this is a confirmation that the thing noticed you, not an animation
-- to sit and watch.
local NEAR_SCALE = 1.25

-- Where the badge sits on the thing's own height, measured up from its feet rather
-- than down from its head -- a toddler and a grown adult wear theirs at the same
-- fraction of themselves, which is what keeps it reading as "chest" on both. 0.62
-- rather than a plain half because a body's midpoint by bounding-box height sits
-- closer to the waist than the chest once legs are counted.
local CHEST_HEIGHT_FRACTION = 0.62

-- The nameplate sits above the badge, not in place of it, and is its own billboard
-- rather than another frame inside its. Two reasons, and the second is the one that
-- decided it: the badge goes dark when somebody has already given you their time this
-- year -- SetEnabled -- and their name must not go dark with it, because a person you
-- have already spoken to is still a person standing there with a name. Separate guis is
-- the whole of what it takes for those two to be turned off independently.
--
-- It also means nothing about the badge's own geometry moved to make room for the name.
local NAMEPLATE_LIFT = 0.95

local NAMEPLATE_NAME_COLOR = Color3.fromRGB(255, 252, 245)
local NAMEPLATE_DETAIL_COLOR = Color3.fromRGB(206, 198, 184)
local NAMEPLATE_STROKE = Color3.fromRGB(18, 16, 12)

-- The share of the plate the name takes when there is a second line under it. The rest
-- is that line, at the smaller size that says it is the second thing about somebody
-- rather than the first.
local NAMEPLATE_NAME_SHARE = 0.6

-- What joins an age to a relationship on that second line. A middle dot rather than a
-- comma because the two halves are not a list -- they are two separate facts sharing a
-- row, and a comma reads as one sentence that got cut short.
local NAMEPLATE_DETAIL_JOIN = " · "

local Interact = {}

Interact.PromptName = PROMPT_NAME
Interact.DotsName = DOTS_NAME
Interact.NameplateName = NAMEPLATE_NAME
Interact.DotsButtonName = DOTS_BUTTON_NAME
Interact.KindAttribute = KIND_ATTRIBUTE
Interact.IdAttribute = ID_ATTRIBUTE

-- Which system owns this thing, and therefore which one is asked what the options
-- are. Closed rather than a loose string: a kind the client has no branch for is a
-- thing the player can click that does nothing, and that failure is silent.
--
-- There is no Lesson here, and that is a decision rather than an omission. Dots mean
-- "there is a thing here, go to it". A lesson is not a thing in the room -- it is
-- something you are already inside, like a shift -- so its questions open themselves
-- and the walk is spent once, at the door. See SchoolService.
--
-- "Station" does not contradict that, and the distinction is the reason Science is a
-- different activity rather than a quiz in a nicer room. A question is not a thing in
-- the room; a balance is. The walk to the school is still spent once at the door, and
-- then the room itself is full of things to go to -- which is exactly the case dots
-- were built for. A station carries no price and offers no menu: clicking it is the
-- answer, and what it does is written on the board across the room rather than on the
-- station, because the whole verb is holding the order in your head while you cross.
--
-- "Till" is its own kind rather than a Station with a different id, and the reason is
-- that the client dispatches on kind alone: a till that called itself a Station would
-- send a lab step the first time anybody clicked it, which is a bug that would look
-- exactly like the theft system not being wired up. It also is not one -- a station is
-- answered by clicking, and clicking a till only ever puts you *at* it. What happens
-- next is held, not clicked, and is done from the panel the click opens.
--
-- "Vault" is separate from "Till" for the same dispatch reason and for a second one: they
-- open different panels because they are different activities. A till asks you not to be
-- seen; a bank takes it as given and asks how long you will stay. Sharing a kind would
-- have put a bank's alarm readout on a shop's panel, and the two rooms would have started
-- teaching each other's lesson.
--
-- Note that the bank's *alarm panel* is not on this list and never will be. Dots are how
-- you enter an activity; by the time the alarm matters the player is already inside one,
-- and a second prompt in the same room would spend the whole robbery fighting the vault's
-- for whichever is nearest while somebody runs between them.
-- "Boss" is a person and is deliberately not "Person". Dispatch is by kind alone, so a
-- gang boss registered as a Person would open the ordinary chat panel and be asked for a
-- tie -- and the offers a boss makes are not offers about a friendship. The two also have
-- different failure modes worth keeping apart: a Person can refuse you and that is content,
-- whereas a boss refusing to promote you is the ladder working and has to say which rung
-- and how far off you are.
-- "Fight" is a person too, and it is separate for the same reason "Boss" is: dispatch is by
-- kind alone, and what this one opens is not a conversation. It is on somebody who is stood
-- in the street waiting to be squared up to, and the only thing their dots can say is yes or
-- walk away. Keeping it off "Person" also keeps the two populations honest -- the people you
-- can befriend are not the people who want a fight, and a shopkeeper who could be challenged
-- from the same panel that sells you bread would make every tie in the game feel negotiable.
export type InteractKind = "Person" | "Event" | "Station" | "Till" | "Vault" | "Boss" | "Fight" | "Apartment" | "Fixture"

-- Who this is, written over their head. Nil on anything that is not a person: there is
-- no nameplate over a dog, a rug or a front door.
--
-- The parts are asked for separately rather than as one string because they are drawn
-- differently and because each can be absent on its own. An age of nil is not "age
-- nought" and it is not an error -- it is the game declining to claim a number it does
-- not model, which is what happens to anybody old enough that a world with no mortality
-- in it has stopped being able to say. See People.ShownAge.
export type Nameplate = {
	name: string,
	age: number?,
	-- What they are to the player, already turned into a word by the caller: "friend",
	-- "closest friend". Nil for almost everybody, which is the point -- a town where one
	-- head in thirty says something is a town you can read across a street, and one where
	-- all thirty say "nothing in particular" is a wall of text.
	--
	-- A word rather than a tie id, because this file is shared and knows nothing about
	-- content. It draws what it is handed.
	tie: string?,
}

export type InteractLook = {
	kind: InteractKind,
	-- Whatever the owning system needs to identify this when the click comes back:
	-- a person id, an event id. Never trusted on its own -- the server checks it
	-- against what it actually offered this player.
	id: string,
	-- The verb, not a sentence: "Talk", "Answer", "Decide".
	--
	-- Not drawn. A Custom-styled prompt renders nothing at all, so these two go to
	-- the Studio explorer and nowhere else -- which is worth the two lines, because
	-- without them a house mid-childhood is a dozen instances all named
	-- "AgesInteract" and no way to tell which one is the mother. They are also what
	-- the prompt would say the day this stops being Custom-styled, and a default
	-- style that announced every interactable as "Interact" would be a worse first
	-- day than one that already knew the words.
	actionText: string,
	-- Who or what this is: a person's name, an animal's, a subject's.
	objectText: string,
	-- Drawn above the dots, unlike the two fields above. Nil on anything that is not a
	-- person, which is most callers.
	nameplate: Nameplate?,
}

export type InteractHandle = {
	prompt: ProximityPrompt,
	SetEnabled: (enabled: boolean) -> (),
	-- Changes what the plate says, or takes it away with nil. Separate from SetEnabled
	-- because an age moves on a birthday and the dots do not, and because the dots going
	-- dark must never take a person's name with them.
	--
	-- A no-op on anything attached without a nameplate and never asked for one since --
	-- there is nothing over a prop's head to update.
	SetNameplate: (plate: Nameplate?) -> (),
	Destroy: () -> (),
}

-- A BillboardGui cannot adorn a Model, and the part it does adorn has to be one
-- that moves when the thing moves -- otherwise the dots stay behind in the doorway
-- while the dog walks over. A head is preferred purely so the lift below is
-- measured from somewhere stable on a rig that is animating underneath it.
local function adorneeFor(target: Model | BasePart): BasePart?
	if target:IsA("BasePart") then
		return target
	end
	local head = target:FindFirstChild("Head")
	if head ~= nil and head:IsA("BasePart") then
		return head
	end
	return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
end

-- How high the nameplate has to float to clear this particular thing, and where the
-- badge below it anchors from. A toddler, an adult and a dog are three very
-- different heights and all three have to wear their nameplate at the same visible
-- distance above them, so this is measured rather than set to a number that
-- happens to look right on one of the three.
local function liftFor(target: Model | BasePart, adornee: BasePart): number
	if target:IsA("BasePart") then
		return target.Size.Y / 2 + NAMEPLATE_LIFT
	end
	local box, size = target:GetBoundingBox()
	return (box.Position.Y + size.Y / 2) - adornee.Position.Y + NAMEPLATE_LIFT
end

-- Where the badge floats: not above the head but on the chest, at the same
-- fraction of the thing's own height regardless of how tall it is. Measured off
-- the model's bounding box for the same reason liftFor is -- a guess that happens
-- to look right on one body is wrong on every other one in the game.
local function chestOffsetFor(target: Model | BasePart, adornee: BasePart): number
	if target:IsA("BasePart") then
		return target.Size.Y * (CHEST_HEIGHT_FRACTION - 0.5)
	end
	local box, size = target:GetBoundingBox()
	local feet = box.Position.Y - size.Y / 2
	return (feet + size.Y * CHEST_HEIGHT_FRACTION) - adornee.Position.Y
end

-- The one badge: a rounded chip with the key printed on it, shown whether the
-- player is holding a keyboard or not. It used to only appear for keyboard players,
-- with a screen tap as the unadvertised alternative for everyone else -- but a
-- badge sitting on a person is the thing itself, not a hint about a bar at the
-- bottom of the screen, so there is no longer a device to detect before deciding
-- whether to show it.
local function buildBadge(parent: Instance): Frame
	local badge = Instance.new("Frame")
	badge.Name = BADGE_NAME
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.5, 0.5)
	badge.Size = UDim2.fromScale(BADGE_SIZE, BADGE_SIZE)
	badge.BackgroundColor3 = BADGE_COLOR
	badge.BorderSizePixel = 0
	badge.Parent = parent

	-- A full circle rather than a rounded square. A coin reads as a single, deliberate
	-- shape from across a room; a rounded square reads as "a label that got corners
	-- filed off" the moment you are close enough to see the difference.
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = badge

	-- Light at the top, the base gold in the middle, shadow at the bottom -- see
	-- BADGE_COLOR_LIGHT/BADGE_COLOR_SHADOW for why. Rotated 90 so the light comes from
	-- above rather than from the side, which is the direction every other lit surface
	-- in this game's rooms agrees a light source lives.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BADGE_COLOR_LIGHT),
		ColorSequenceKeypoint.new(0.55, BADGE_COLOR),
		ColorSequenceKeypoint.new(1, BADGE_COLOR_SHADOW),
	})
	gradient.Parent = badge

	-- Readable against a white wall and a night sky alike. Without it the badge
	-- disappears entirely in a bright room, which is most rooms. Thicker than the
	-- square plate wore, because a circle's edge has nothing else -- no corner, no
	-- flat side -- to catch the eye and say "this is a distinct object" for it.
	local stroke = Instance.new("UIStroke")
	stroke.Color = BADGE_STROKE
	stroke.Thickness = 2
	stroke.Transparency = BADGE_STROKE_FAR_TRANSPARENCY
	stroke.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "BadgeKey"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = INTERACT.KeyboardKey.Name
	label.TextColor3 = BADGE_TEXT_COLOR
	label.TextTransparency = 1
	label.TextScaled = true
	label.Parent = badge

	return badge
end

-- The two labels and the box they live in, kept together so that turning an age on and
-- off can move both without going looking for them by name.
type Plate = {
	gui: BillboardGui,
	name: TextLabel,
	-- The second line, and it is called this rather than `age` because it is no longer
	-- only an age: an age, or a relationship, or both joined. One line rather than three
	-- stacked labels because a nameplate is read from across a street while walking past,
	-- and a third row makes it a card.
	detail: TextLabel,
}

local function buildPlateLabel(name: string, parent: Instance, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = ""
	label.Parent = parent

	-- Same reason the dots have one: white text over a white wall is not text. This is
	-- worn by every person in the world at once, so it is the difference between a town
	-- and a town you can read.
	local stroke = Instance.new("UIStroke")
	stroke.Color = NAMEPLATE_STROKE
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = label

	return label
end

local function buildPlate(adornee: BasePart, lift: number): Plate
	local gui = Instance.new("BillboardGui")
	gui.Name = NAMEPLATE_NAME
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(6, 1.3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift + NAMEPLATE_LIFT, 0)
	-- Occluded, unlike the dots, and that is the one place these two billboards disagree
	-- about anything. Telling you there is somebody round the corner is the dots' job and
	-- they still draw through walls to do it; a *name* through a wall is a name belonging
	-- to somebody you cannot see, which is how a street ends up wearing a list of people
	-- who are not on it.
	gui.AlwaysOnTop = false
	gui.MaxDistance = INTERACT.ReachStuds * INTERACT.NameRangeMultiplier
	gui.Parent = adornee

	local nameLabel = buildPlateLabel("PersonName", gui, NAMEPLATE_NAME_COLOR)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Position = UDim2.fromScale(0.5, 0)

	local detailLabel = buildPlateLabel("PersonDetail", gui, NAMEPLATE_DETAIL_COLOR)
	detailLabel.Font = Enum.Font.GothamMedium

	return { gui = gui, name = nameLabel, detail = detailLabel }
end

local function applyPlate(plate: Plate, value: Nameplate)
	plate.name.Text = value.name

	-- Both halves are optional and independently so: a person too old for the game to
	-- claim a number for can still be your closest friend, and almost everybody has an
	-- age and is nobody in particular. Built as a list rather than as a chain of ifs so
	-- that a third fact -- if one is ever earned -- is one insert.
	local parts: { string } = {}
	local age = value.age
	if age ~= nil then
		-- Said in words rather than as a bare figure. A lone number under a name is the
		-- one thing on screen a player could read as a level or a score, and this is a
		-- game where that guess would be a reasonable one to make.
		table.insert(parts, `Age {age}`)
	end
	local tie = value.tie
	if tie ~= nil and tie ~= "" then
		table.insert(parts, tie)
	end

	if #parts == 0 then
		-- The name takes the whole box rather than sitting above a gap. A blank line where
		-- something should be reads as something that failed to load, and this case is not
		-- a failure -- it is a stranger, which is most people.
		plate.name.Size = UDim2.fromScale(1, 1)
		plate.detail.Visible = false
	else
		plate.name.Size = UDim2.fromScale(1, NAMEPLATE_NAME_SHARE)
		plate.detail.Position = UDim2.fromScale(0.5, NAMEPLATE_NAME_SHARE)
		plate.detail.Size = UDim2.fromScale(1, 1 - NAMEPLATE_NAME_SHARE)
		plate.detail.Text = table.concat(parts, NAMEPLATE_DETAIL_JOIN)
		plate.detail.Visible = true
	end

	plate.gui.Enabled = true
end

-- Attaches the invitation. `target` is the thing itself -- the person, the animal,
-- the sign -- and is borrowed, never owned: nothing here poses it, parents it or
-- takes it away, because whoever spawned it is very likely still moving it around.
-- Destroy removes exactly what was added and no more.
function Interact.Attach(target: Model | BasePart, look: InteractLook): InteractHandle?
	local adornee = adorneeFor(target)
	if adornee == nil then
		-- Genuinely possible: a model whose parts have not replicated yet. Refused
		-- rather than guessed at, because dots adorned to nothing are dots the
		-- player never sees and a thing they can never talk to, and that reads as
		-- the character being broken rather than the attachment failing.
		return nil
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = look.actionText
	prompt.ObjectText = look.objectText
	prompt.MaxActivationDistance = INTERACT.ReachStuds
	-- Pinned rather than left at whatever Roblox defaults to, because the hint beside
	-- the dots names this key and the two must not be able to disagree.
	prompt.KeyboardKeyCode = INTERACT.KeyboardKey
	-- Nothing is held down. Every choice in this game is reversible only by living
	-- with it, so a hold would be protecting the player from a mis-click on the
	-- dots rather than from the decision, and the decision is made on the panel.
	prompt.HoldDuration = 0
	-- Off deliberately. The check is a raycast from the camera, and this game puts
	-- the camera behind a toddler in a furnished room -- a mother standing behind a
	-- kitchen counter would flicker in and out of existence as the player walked.
	-- The distance is the honest test of whether you are near enough to talk.
	prompt.RequiresLineOfSight = false
	-- Roblox draws nothing; everything the player sees here is the dots below.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute(KIND_ATTRIBUTE, look.kind)
	prompt:SetAttribute(ID_ATTRIBUTE, look.id)
	prompt.Parent = adornee

	local billboard = Instance.new("BillboardGui")
	billboard.Name = DOTS_NAME
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromScale(0.9, 0.9)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, chestOffsetFor(target, adornee), 0)
	-- Seen through whatever it is standing behind. Somebody half-hidden by a sofa is
	-- exactly the moment knowing they are talkable-to matters most.
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = INTERACT.ReachStuds * INTERACT.DotsRangeMultiplier
	-- Without this a BillboardGui does not hand input to the buttons inside it, so the
	-- badge would draw, wake, bob and swallow nothing. Belt and braces next to the
	-- Activated connection on the client: either one missing gives the same symptom.
	billboard.Active = true
	billboard.Parent = adornee

	-- The badge is the button. This is what makes the whole thing work on a phone,
	-- where there is no key to press, and it is also just what the player has been
	-- told to do: click the badge.
	local button = Instance.new("TextButton")
	button.Name = DOTS_BUTTON_NAME
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button

	local badge = buildBadge(button)
	badge.BackgroundTransparency = BADGE_FAR_TRANSPARENCY

	-- Started here and never stopped. A tween with -1 repeats is cheap and the
	-- alternative -- starting it on approach and stopping it on leaving -- would
	-- mean a badge that is visibly frozen from across the room, which reads as
	-- something that has stopped working.
	local up = badge.Position + UDim2.fromScale(0, -BADGE_BOB_SCALE)
	local bob = TweenService:Create(
		badge,
		TweenInfo.new(BADGE_BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = up }
	)
	bob:Play()

	local destroyed = false

	-- Built on first use rather than up front, because most things wearing a badge in
	-- this world are not people -- a rug, a cupboard, a front door -- and a disabled
	-- billboard over every prop in the room would be two instances each for nothing.
	--
	-- `on` is a fresh non-optional local because the refinement that made `adornee` a
	-- BasePart above does not survive into a closure, and the same trick PlaceService uses
	-- is cheaper than an assertion the type checker would only take on trust.
	local on = adornee :: BasePart
	local plate: Plate? = nil
	local function setNameplate(value: Nameplate?)
		if destroyed then
			return
		end
		if value == nil then
			if plate ~= nil then
				plate.gui.Enabled = false
			end
			return
		end
		local current = plate
		if current == nil then
			current = buildPlate(on, liftFor(target, on))
			plate = current
		end
		applyPlate(current, value)
		-- Latent until somebody calls SetNameplate(nil) and then names them again, which
		-- nothing does yet -- but the nil branch above turns the gui off and this was the
		-- only path that could ever turn it back on, so without this the first caller to
		-- do that gets a person who is permanently anonymous and no error anywhere.
		current.gui.Enabled = true
	end

	setNameplate(look.nameplate)

	return {
		prompt = prompt,
		-- Turned off rather than torn down for the case that happens constantly:
		-- somebody who has already given you their time this year is still standing
		-- there and still worth walking up to, they just have nothing on offer. The
		-- badge going quiet says that better than the person vanishing does.
		SetEnabled = function(enabled: boolean)
			if destroyed then
				return
			end
			prompt.Enabled = enabled
			billboard.Enabled = enabled
		end,
		SetNameplate = setNameplate,
		Destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			bob:Cancel()
			prompt:Destroy()
			billboard:Destroy()
			if plate ~= nil then
				plate.gui:Destroy()
			end
		end,
	}
end

-- The look the client applies when the player is close enough to use this, and
-- takes away when they are not. Lives here rather than in the client module so that
-- the two halves of one animation -- how the badge rests and how it wakes -- are
-- written next to each other and cannot drift apart.
function Interact.SetNear(billboard: BillboardGui, near: boolean)
	local button = billboard:FindFirstChild(DOTS_BUTTON_NAME)
	if button == nil then
		return
	end

	local scale = button:FindFirstChildWhichIsA("UIScale")
	if scale ~= nil then
		TweenService:Create(
			scale,
			TweenInfo.new(INTERACT.WakeSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = if near then NEAR_SCALE else 1 }
		):Play()
	end

	local badge = button:FindFirstChild(BADGE_NAME)
	if badge == nil or not badge:IsA("Frame") then
		return
	end

	local info = TweenInfo.new(INTERACT.WakeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local backgroundTransparency = if near then BADGE_NEAR_TRANSPARENCY else BADGE_FAR_TRANSPARENCY
	TweenService:Create(badge, info, { BackgroundTransparency = backgroundTransparency }):Play()

	local stroke = badge:FindFirstChildWhichIsA("UIStroke")
	if stroke ~= nil then
		local strokeTransparency = if near then BADGE_STROKE_NEAR_TRANSPARENCY else BADGE_STROKE_FAR_TRANSPARENCY
		TweenService:Create(stroke, info, { Transparency = strokeTransparency }):Play()
	end

	local label = badge:FindFirstChild("BadgeKey")
	if label ~= nil and label:IsA("TextLabel") then
		TweenService:Create(label, info, { TextTransparency = backgroundTransparency }):Play()
	end
end

return Interact
