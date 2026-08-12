--!strict
-- What something in the world looks like when it has something to say.
--
-- Three dots over its head. You get near, they wake up, you click them and the
-- options come up. That is the whole grammar and it is the same grammar for a
-- person, an animal and a lesson, because a player should have to learn how to
-- talk to this world exactly once.
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
-- The dots are a TextButton and not a decoration, which is why the tap works. On a
-- phone there is no key to press, so a custom-styled prompt that only listened for
-- one would be an object that is permanently unusable to most of the people looking
-- at it. Clicking the thing you can see is also simply the honest interface: the
-- player is told to click the dots, so the dots are what is clickable.
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

-- The clickable thing inside the dots billboard, and the label beside it. Named
-- constants rather than string literals at four call sites, because the client has
-- to find both by name across the server/client boundary and a typo in one of them
-- is a silent no-op rather than an error.
local DOTS_BUTTON_NAME = "Dots"
local KEY_HINT_NAME = "KeyHint"

-- Cosmetic, and kept out of Config for the reason ChoiceMarkers gives: the radius
-- of a dot is not a number anybody balances a life simulator with, and putting it
-- next to the numbers that are makes both harder to find.
local DOT_COUNT = 3
local DOT_SIZE = 0.28
local DOT_GAP = 0.16
local DOT_COLOR = Color3.fromRGB(255, 250, 240)
local DOT_STROKE = Color3.fromRGB(20, 18, 14)

-- Asleep until you are near it. Dimmed rather than hidden, because a world where
-- interactable things are invisible until you are already touching them is a world
-- the player has to walk into wall-first to read.
local DOTS_FAR_TRANSPARENCY = 0.45
local DOTS_NEAR_TRANSPARENCY = 0

-- The bob. Staggered so the three dots read as one thing thinking rather than
-- three things blinking, which is the difference between "there is something here"
-- and "there is an error here".
local BOB_STUDS = 0.1
local BOB_SECONDS = 0.75
local BOB_STAGGER = 0.16

-- How much bigger the dots get when the player is close enough to use them. Small
-- on purpose: this is a confirmation that the thing noticed you, not an animation
-- to sit and watch.
local NEAR_SCALE = 1.25

-- How far above the top of the thing the dots float. Measured off the model's own
-- box rather than guessed, so a dog and a grown adult both wear theirs clear of
-- their head by the same visible margin.
local DOTS_LIFT = 1.1

-- The nameplate sits above the dots, not in place of them, and is its own billboard
-- rather than another frame inside theirs. Two reasons, and the second is the one that
-- decided it: the dots go dark when somebody has already given you their time this year
-- -- SetEnabled -- and their name must not go dark with them, because a person you have
-- already spoken to is still a person standing there with a name. Separate guis is the
-- whole of what it takes for those two to be turned off independently.
--
-- It also means nothing about the dots' geometry moved to make room, which matters more
-- than it sounds: the dots are laid out in scale against their own billboard, so
-- resizing that box would have quietly reshaped all three of them.
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
export type InteractKind = "Person" | "Event" | "Station" | "Till"

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

-- How high the dots have to float to clear this particular thing. A toddler, an
-- adult and a dog are three very different heights and all three have to wear
-- their dots at the same visible distance above them, so this is measured rather
-- than set to a number that happens to look right on one of the three.
local function liftFor(target: Model | BasePart, adornee: BasePart): number
	if target:IsA("BasePart") then
		return target.Size.Y / 2 + DOTS_LIFT
	end
	local box, size = target:GetBoundingBox()
	return (box.Position.Y + size.Y / 2) - adornee.Position.Y + DOTS_LIFT
end

local function buildDot(index: number, parent: Instance): Frame
	local dot = Instance.new("Frame")
	dot.Name = `Dot{index}`
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromScale(DOT_SIZE, DOT_SIZE)
	-- Laid out by hand rather than with a UIListLayout, because each one has to be
	-- tweened independently for the stagger and a layout would fight every tween.
	local span = DOT_COUNT * DOT_SIZE + (DOT_COUNT - 1) * DOT_GAP
	local step = DOT_SIZE + DOT_GAP
	dot.Position = UDim2.fromScale(0.5 - span / 2 + step * (index - 1) + DOT_SIZE / 2, 0.5)
	dot.BackgroundColor3 = DOT_COLOR
	dot.BorderSizePixel = 0
	dot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	-- Readable against a white wall and a night sky alike. Without it the dots
	-- disappear entirely in a bright room, which is most rooms.
	local stroke = Instance.new("UIStroke")
	stroke.Color = DOT_STROKE
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = dot

	return dot
end

-- The keyboard alternative to clicking, drawn beside the dots. Starts hidden: only the
-- client knows whether this player is on a keyboard at all, and a phone showing a key
-- that does not exist is worse than a phone showing nothing.
local function buildKeyHint(parent: Instance)
	local hint = Instance.new("TextLabel")
	hint.Name = KEY_HINT_NAME
	hint.AnchorPoint = Vector2.new(0, 0.5)
	hint.Position = UDim2.fromScale(0.5 + INTERACT.KeyHintOffset, 0.5)
	hint.Size = UDim2.fromScale(DOT_SIZE * 1.6, DOT_SIZE * 1.6)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextScaled = true
	hint.TextColor3 = DOT_COLOR
	hint.Text = INTERACT.KeyboardKey.Name
	hint.Visible = false
	hint.Parent = parent

	-- The same outline the dots wear, for the same reason: unreadable against a bright
	-- wall otherwise, and most rooms in this game are bright.
	local stroke = Instance.new("UIStroke")
	stroke.Color = DOT_STROKE
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = hint
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
	billboard.Size = UDim2.fromScale(2.4, 0.9)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, liftFor(target, adornee), 0)
	-- Seen through whatever it is standing behind. Somebody half-hidden by a sofa is
	-- exactly the moment knowing they are talkable-to matters most.
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = INTERACT.ReachStuds * INTERACT.DotsRangeMultiplier
	-- Without this a BillboardGui does not hand input to the buttons inside it, so the
	-- dots would draw, wake, bob and swallow nothing. Belt and braces next to the
	-- Activated connection on the client: either one missing gives the same symptom.
	billboard.Active = true
	billboard.Parent = adornee

	-- The dots are the button. This is what makes the whole thing work on a phone,
	-- where there is no key to press, and it is also just what the player has been
	-- told to do: click the dots.
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

	local dots: { Frame } = {}
	for index = 1, DOT_COUNT do
		local dot = buildDot(index, button)
		dot.BackgroundTransparency = DOTS_FAR_TRANSPARENCY
		table.insert(dots, dot)
	end

	-- The key, for the people holding a keyboard. Hidden here and shown by the client,
	-- because whether there is a keyboard in the room is a fact about one player and
	-- this instance is replicated to all of them.
	--
	-- Worth the label at all because a Custom-styled prompt draws nothing: without it
	-- the key works and no part of the game has ever said so, which is the same as it
	-- not working for everybody who does not think to try.
	buildKeyHint(button)

	-- Started here and never stopped. A tween with -1 repeats is cheap and the
	-- alternative -- starting it on approach and stopping it on leaving -- would
	-- mean three dots that are visibly frozen from across the room, which reads as
	-- something that has stopped working.
	local bobs: { Tween } = {}
	for index, dot in dots do
		local up = dot.Position + UDim2.fromScale(0, -BOB_STUDS)
		local tween = TweenService:Create(
			dot,
			TweenInfo.new(
				BOB_SECONDS,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true,
				BOB_STAGGER * (index - 1)
			),
			{ Position = up }
		)
		tween:Play()
		table.insert(bobs, tween)
	end

	local destroyed = false

	-- Built on first use rather than up front, because most things wearing dots in this
	-- world are not people -- a rug, a cupboard, a front door -- and a disabled billboard
	-- over every prop in the room would be two instances each for nothing.
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
		-- dots going quiet says that better than the person vanishing does.
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
			for _, tween in bobs do
				tween:Cancel()
			end
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
-- the two halves of one animation -- how the dots rest and how they wake -- are
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

	local transparency = if near then DOTS_NEAR_TRANSPARENCY else DOTS_FAR_TRANSPARENCY
	for _, dot in button:GetChildren() do
		if dot:IsA("Frame") then
			TweenService:Create(
				dot,
				TweenInfo.new(INTERACT.WakeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundTransparency = transparency }
			):Play()
		end
	end
end

-- Whether to name the key beside the dots. Driven entirely by the client, which is the
-- only end that knows what the player is holding, and called alongside SetNear rather
-- than folded into it: the hint follows the input device, the dots follow the distance,
-- and the day those two stop changing together this stays correct.
function Interact.SetKeyHint(billboard: BillboardGui, visible: boolean)
	local button = billboard:FindFirstChild(DOTS_BUTTON_NAME)
	if button == nil then
		return
	end
	local hint = button:FindFirstChild(KEY_HINT_NAME)
	if hint ~= nil and hint:IsA("TextLabel") then
		hint.Visible = visible
	end
end

return Interact
