--!strict
-- The player's end of the badge. Interact.luau builds it; this notices it.
--
-- Two jobs, and both are what make the world feel like it is paying attention:
-- wake the badge when the player comes into range and settle it when they leave,
-- and turn a click into "open whatever this thing had to say".
--
-- Opening the panel is done here rather than asked of the server, and that is
-- worth stating plainly because it looks like a shortcut and is not. Everything
-- the panel needs has already been pushed to this client -- the offers a person
-- has, the choices an event carries, the answers to a question -- because the HUD
-- was already showing pieces of it. Asking the server to send it a second time
-- would mean the badge visibly waiting on a round trip before anything happened,
-- which on a bad connection is the difference between a game that responds and a
-- game that hesitates. Nothing is decided here: the moment the player picks
-- something it goes to the server, and the server checks it against what it
-- actually offered. This end can only ever open a menu.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))

type InteractKind = Interact.InteractKind

local Prompts = {}
Prompts.__index = Prompts

-- Set on a billboard once its button has been connected, so a rig that replicates in
-- pieces -- or a DescendantAdded that fires twice for the same instance, which happens
-- -- cannot end up with two connections and one click opening the panel twice.
local WIRED_ATTRIBUTE = "AgesDotsWired"

export type PromptsHandle = typeof(setmetatable(
	{} :: {
		-- One callback per kind of interactable, registered by the client bootstrap.
		-- A table rather than three fields so that adding a fourth kind is a line in
		-- Types and a line at the call site, and nothing in here changes at all.
		handlers: { [string]: (id: string) -> () },
	},
	Prompts
))

-- The dots that belong to a given prompt. They are siblings -- both parented to the
-- part they hang over -- rather than one inside the other, because a BillboardGui
-- inside a ProximityPrompt is not a thing Roblox renders.
local function dotsFor(prompt: ProximityPrompt): BillboardGui?
	local parent = prompt.Parent
	if parent == nil then
		return nil
	end
	local dots = parent:FindFirstChild(Interact.DotsName)
	if dots ~= nil and dots:IsA("BillboardGui") then
		return dots
	end
	return nil
end

local function isOurs(prompt: ProximityPrompt): boolean
	return prompt.Name == Interact.PromptName
end

-- The inverse of dotsFor. Same sibling relationship, read the other way round, because
-- a click arrives at the button and has to find the prompt that owns it.
local function promptFor(dots: BillboardGui): ProximityPrompt?
	local parent = dots.Parent
	if parent == nil then
		return nil
	end
	local prompt = parent:FindFirstChild(Interact.PromptName)
	if prompt ~= nil and prompt:IsA("ProximityPrompt") then
		return prompt
	end
	return nil
end

-- How far the player is from the thing wearing these dots, or nil when there is no body
-- to measure from -- which is a real state during a respawn, not an error.
local function studsTo(prompt: ProximityPrompt): number?
	local adornee = prompt.Parent
	if adornee == nil or not adornee:IsA("BasePart") then
		return nil
	end
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return (root.Position - adornee.Position).Magnitude
end

-- The moment of the last tap that landed on a dots button, stamped by wireDots below.
-- A tap on the dots also raycasts straight past them to whatever body is behind, so the
-- body-tap has to be able to tell "this is the same tap, seen twice" from "this is a
-- fresh tap on the person". Anything within a beat of a dots click is that click.
local lastDotsClick = 0

-- Opens whatever a dots billboard was promising. The checks that used to live in the
-- button's Activated live here now, because the body-tap below answers through the same
-- door and the two surfaces must not be able to disagree about whether somebody is
-- reachable. The extra argument is the out-of-range warning, which is a developer
-- message about a mis-click on a small target and does not belong to tapping a whole
-- person across the room.
local function triggerDots(dots: BillboardGui, warnOutOfRange: boolean)
	local prompt = promptFor(dots)
	if prompt == nil then
		warn(`AGES: dots with no prompt beside them ({dots:GetFullName()})`)
		return
	end
	if not prompt.Enabled then
		-- Somebody who has already given you their time this year. The dots are
		-- dark, so this is the player testing whether dark means anything.
		return
	end

	local distance = studsTo(prompt)
	if distance ~= nil and distance > prompt.MaxActivationDistance then
		if warnOutOfRange and RunService:IsStudio() then
			warn(
				`AGES: clicked dots at {math.round(distance)} studs, `
					.. `out of the {math.round(prompt.MaxActivationDistance)}-stud reach ({prompt:GetFullName()})`
			)
		end
		return
	end

	-- HoldDuration is 0, so beginning the hold is the whole interaction. Both halves
	-- are still sent because a prompt left mid-hold stays mid-hold, and the next
	-- press would be the one that gets swallowed.
	prompt:InputHoldBegin()
	prompt:InputHoldEnd()
end

-- Turns a tap on the dots into the same event a keypress raises.
--
-- This connection is the whole reason clicking works, and it has to be made on the
-- client: Interact.Attach builds the button on the server for every NPC in the game, and
-- a server-side Activated never fires for a click that happens in one player's session.
--
-- The range test is ours rather than the prompt's on purpose. The dots are deliberately
-- visible from two and a half times their own reach -- you are meant to be able to read
-- a room before crossing it -- so a click from the far side of that gap is an ordinary
-- thing a player will do, and InputHoldBegin answers it by silently doing nothing. The
-- dots being dimmed is the honest answer to the player; the warning below is the honest
-- answer to whoever is testing, who would otherwise be looking at a character that
-- appears to be broken.
local function wireDots(dots: BillboardGui)
	if dots:GetAttribute(WIRED_ATTRIBUTE) == true then
		return
	end

	local button = dots:FindFirstChild(Interact.DotsButtonName)
	if button == nil or not button:IsA("GuiButton") then
		-- Not a race: the button is parented before the billboard is, so by the time
		-- this billboard exists anywhere its button exists inside it. Reaching here
		-- means something built dots by hand instead of through Interact.Attach.
		warn(`AGES: dots with no "{Interact.DotsButtonName}" button ({dots:GetFullName()})`)
		return
	end

	dots:SetAttribute(WIRED_ATTRIBUTE, true)

	button.Activated:Connect(function()
		lastDotsClick = os.clock()
		triggerDots(dots, true)
	end)
end

-- Everything already in the world, and everything that arrives later. Both are needed:
-- the family is spawned before this module runs, and the town spawns and despawns for
-- the rest of the session.
local function watchForDots()
	for _, instance in Workspace:GetDescendants() do
		if instance.Name == Interact.DotsName and instance:IsA("BillboardGui") then
			wireDots(instance)
		end
	end

	-- The name test first, deliberately. This fires for every part of every rig that
	-- streams in, and a string compare that fails on the first character is the
	-- cheapest way to say no.
	Workspace.DescendantAdded:Connect(function(instance: Instance)
		if instance.Name == Interact.DotsName and instance:IsA("BillboardGui") then
			wireDots(instance)
		end
	end)
end

-- Whether a point on screen is over a clickable button. A tap that lands on the Age
-- Up button would otherwise raycast straight through it to whoever is standing behind
-- it and start a conversation nobody asked for, so anything that shares the tap point
-- with a GuiButton is not a tap on the world.
--
-- GuiService:GetGuiObjectsAtPosition is pcall'd because it is not the sort of call
-- this project makes anywhere else and a wrong assumption about it must degrade to
-- "treat the tap as a body-tap" rather than to an error that eats the whole feature.
local function overUiButton(x: number, y: number): boolean
	local ok, guis = pcall(GuiService.GetGuiObjectsAtPosition, GuiService, x, y)
	if not ok or type(guis) ~= "table" then
		return false
	end
	for _, gui in guis do
		if gui:IsA("GuiButton") then
			return true
		end
	end
	return false
end

-- A tap on a body, not on the dots. The dots are the honest surface -- small, above
-- the head, clickable on purpose -- and the body is what a player reaching for a
-- person actually hits, so the body answers too. A player who taps the person they are
-- standing next to gets the same conversation the dots give; a player who taps someone
-- across the street gets the same silence, because the reach test is the same one.
--
-- The double-fire guards are the two places this can see one tap twice. A tap on the
-- dots stamps `lastDotsClick` on its way into the button's Activated, and this handler
-- may fire before or after that; a tap on any other button is caught by overUiButton.
-- The input's own `processed` flag is deliberately not used, because on a desktop the
-- core click-to-move script consumes clicks on the world and would mark every one of
-- them processed, turning this whole path off for the machines most likely to use it.
local function wireBodyTap()
	local taps = {
		[Enum.UserInputType.MouseButton1] = true,
		[Enum.UserInputType.Touch] = true,
	}

	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end
		if not taps[input.UserInputType] then
			return
		end

		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local location = UserInputService:GetMouseLocation()
		if overUiButton(location.X, location.Y) then
			return
		end

		local ray = camera:ViewportPointToRay(location.X, location.Y)
		local character = Players.LocalPlayer.Character
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 120, params)
		if hit == nil or hit.Instance == nil then
			return
		end

		-- The dots live on the thing they advertise -- a person's head, an event's
		-- prop -- so they are found from whatever part the ray actually hit by walking
		-- up to the model and down to the billboard. A rig that is still streaming in
		-- can be hit before its head exists, in which case there are no dots to answer
		-- with yet and the tap is simply a tap.
		local dots: BillboardGui? = nil
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model ~= nil then
			local found = model:FindFirstChild(Interact.DotsName, true)
			if found ~= nil and found:IsA("BillboardGui") then
				dots = found
			end
		end
		if dots == nil then
			local found = hit.Instance:FindFirstChild(Interact.DotsName)
			if found ~= nil and found:IsA("BillboardGui") then
				dots = found
			end
		end
		if dots == nil then
			return
		end

		if os.clock() - lastDotsClick < 0.3 then
			return
		end

		wireDots(dots)
		triggerDots(dots, false)
	end)
end

function Prompts.new(): PromptsHandle
	local self = setmetatable({ handlers = {} }, Prompts)

	watchForDots()
	wireBodyTap()

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if not isOurs(prompt) then
			return
		end
		local dots = dotsFor(prompt)
		if dots ~= nil then
			-- Also wired here, not only in the watcher above. A billboard that streamed
			-- in while the player was already standing next to it can raise Shown before
			-- DescendantAdded has been serviced, and being wired twice costs nothing
			-- because wireDots refuses the second time.
			wireDots(dots)
			Interact.SetNear(dots, true)
		end
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if not isOurs(prompt) then
			return
		end
		local dots = dotsFor(prompt)
		if dots ~= nil then
			Interact.SetNear(dots, false)
		end
	end)

	-- Fires for a keyboard press, a gamepad button and the badge being clicked
	-- alike -- the last of those by way of wireDots above, because a Custom-styled
	-- prompt has no clickable surface of its own. That is the entire reason this is a
	-- ProximityPrompt and not a billboard with a distance check bolted to it.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if not isOurs(prompt) or player ~= Players.LocalPlayer then
			return
		end

		local kind = prompt:GetAttribute(Interact.KindAttribute)
		local id = prompt:GetAttribute(Interact.IdAttribute)
		if type(kind) ~= "string" or type(id) ~= "string" then
			-- Only reachable if something built a prompt by hand instead of going
			-- through Interact.Attach. Said out loud because the symptom otherwise
			-- is a thing the player can walk up to, click, and watch do nothing.
			warn(`AGES: interactable with no kind or id ({prompt:GetFullName()})`)
			return
		end

		local handler = self.handlers[kind]
		if handler == nil then
			warn(`AGES: nothing on the client knows how to open a "{kind}"`)
			return
		end
		handler(id)
	end)

	return self
end

-- Wiring the dots on a thing to the system that knows what that thing has to say.
function Prompts.On(self: PromptsHandle, kind: InteractKind, handler: (id: string) -> ())
	self.handlers[kind] = handler
end

-- Taps the dots without walking to them. The Studio harness for everything below
-- this line: without it, testing an interaction means being in the right place at
-- the right age with the right bond, and testing the panel means testing the walk.
function Prompts.Trigger(self: PromptsHandle, kind: InteractKind, id: string): boolean
	local handler = self.handlers[kind]
	if handler == nil then
		return false
	end
	handler(id)
	return true
end

return Prompts
