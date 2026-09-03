--!strict
-- Classroom desks: the drawer, the seat, and the lesson the seat starts.
--
-- Three tags, one subject:
--
--   DeskDrawer   a drawer that slides out and hands over a notebook
--   ClassroomDesk a Seat that fixes the camera on the chalkboard and starts a lesson
--   Chalkboard   the board the desk camera looks at
--
-- **The camera is not touched here.** ArenaCamera on the client owns it -- seat vantage and
-- impact shake compose there for the reason set out in its header -- so a desk asks for a
-- vantage through the same `SeatCamera` remote the gym benches use, and the whole restore-on-
-- stand, restore-on-death path comes for free. A second thing writing camera.CFrame is exactly
-- the bug that module exists to prevent.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Chalkboard = require(ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Chalkboard"))
local ChalkboardKey = require(script.Parent.ChalkboardKey)
local Drawer = require(script.Parent.Drawer)

local DRAWER_TAG = "DeskDrawer"
local DESK_TAG = "ClassroomDesk"
local BOARD_TAG = "Chalkboard"

-- **Replace these.** Until they are real ids the desks work silently, which looks exactly like
-- the sound system being broken.
local SOUND = {
	Rattle = "rbxassetid://0", -- wood on wood, a drawer on its runners
	Shut = "rbxassetid://0", -- the knock of it seating
	Correct = "rbxassetid://0", -- a short chalk tick
	Wrong = "rbxassetid://0",
}

local DESK: Drawer.Config = {
	-- 0.7, so it is visibly still in the desk. A drawer that comes all the way out reads as
	-- having fallen out.
	TravelShare = 0.7,
	OpenSeconds = 0.45,
	CloseSeconds = 0.6,
	AutoCloseSeconds = 6,
	OpenSound = SOUND.Rattle,
	ShutSound = SOUND.Shut,
}

-- A desk camera is a reading distance, not a wide shot. The arena's 78 would put half the
-- classroom in frame and make the board tiny.
local DESK_FOV = 58

local DeskService = {}

local wired: { [Instance]: true } = {}
local drawers: { [Instance]: Drawer.Slide } = {}
local lesson: { [Player]: { asked: { string }, index: number, score: number } } = {}
local lastAnswer: { [Player]: number } = {}

-- ---------------------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------------------

local function folderUnder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		return existing :: Folder
	end
	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = parent
	return made
end

local function remote(name: string): RemoteEvent
	local folder = folderUnder(folderUnder(ReplicatedStorage, "Showcase"), "Remotes")
	local existing = folder:FindFirstChild(name)
	if existing ~= nil then
		return existing :: RemoteEvent
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = folder
	return event
end

-- Reused on purpose: the desk is a seat, and ArenaCamera already knows how to sit at one.
local SeatCamera = remote("SeatCamera")
local ShowLesson = remote("ShowLesson") -- server -> client: here is a question, or the result
local AnswerLesson = remote("AnswerLesson") -- client -> server: I picked option n

-- ---------------------------------------------------------------------------------------
-- The notebook
-- ---------------------------------------------------------------------------------------

local TOOL_NAME = "Notebook"

local function notebookTemplate(): Tool
	local existing = ServerStorage:FindFirstChild(TOOL_NAME)
	if existing ~= nil then
		return existing :: Tool
	end
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.ToolTip = "Squared paper, mostly unused."
	tool.RequiresHandle = true
	-- False, or the classroom floor is a field of notebooks a minute after anyone finds
	-- backspace.
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(2.2, 0.35, 3)
	handle.Color = Color3.fromRGB(196, 190, 176)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	-- Massless, or picking it up changes how the character walks -- a bug nobody thinks to look
	-- for in a Tool.
	handle.Massless = true
	handle.Parent = tool

	tool.Grip = CFrame.new(0, -0.1, 0)
	tool.Parent = ServerStorage
	return tool
end

local function giveNotebook(player: Player): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack == nil or backpack:FindFirstChild(TOOL_NAME) ~= nil then
		return false
	end
	-- Also check the character: an equipped tool has been reparented out of the Backpack, so
	-- checking only there hands a second one to anyone already holding it.
	local character = player.Character
	if character ~= nil and character:FindFirstChild(TOOL_NAME) ~= nil then
		return false
	end
	notebookTemplate():Clone().Parent = backpack
	return true
end

-- ---------------------------------------------------------------------------------------
-- The lesson
-- ---------------------------------------------------------------------------------------

local function shuffled(): { string }
	local pool = {}
	for _, question in Chalkboard.Questions do
		table.insert(pool, question.Id)
	end
	for index = #pool, 2, -1 do
		local swap = math.random(index)
		pool[index], pool[swap] = pool[swap], pool[index]
	end
	return pool
end

local function ask(player: Player)
	local state = lesson[player]
	if state == nil then
		return
	end
	if state.index > Chalkboard.QuestionsPerLesson or state.index > #state.asked then
		ShowLesson:FireClient(player, nil, state.score, Chalkboard.QuestionsPerLesson)
		lesson[player] = nil
		return
	end
	ShowLesson:FireClient(player, state.asked[state.index], state.score, Chalkboard.QuestionsPerLesson)
end

local function startLesson(player: Player)
	lesson[player] = { asked = shuffled(), index = 1, score = 0 }
	ask(player)
end

local function endLesson(player: Player)
	if lesson[player] ~= nil then
		lesson[player] = nil
		ShowLesson:FireClient(player, nil, nil, nil)
	end
end

-- ---------------------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------------------

local function anchorOf(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function wireDrawer(instance: Instance)
	if wired[instance] or not instance:IsA("BasePart") then
		return
	end
	wired[instance] = true
	local part = instance :: BasePart
	local slide = Drawer.new(part, DESK)
	drawers[instance] = slide

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrawerPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Desk"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	-- False on purpose. A chair, another student, or the desk's own top all break line of sight,
	-- and a prompt that flickers as somebody walks past reads as broken.
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		slide:Toggle()
		if slide.isOpen then
			giveNotebook(player)
		end
	end)
end

-- The board this desk faces: the nearest tagged Chalkboard. Nearest rather than named, so a
-- classroom can have two boards and forty desks without anybody wiring pairs by hand.
local function boardFor(seat: BasePart): BasePart?
	local best, bestDistance = nil, math.huge
	for _, candidate in CollectionService:GetTagged(BOARD_TAG) do
		local part = anchorOf(candidate)
		if part ~= nil then
			local d = (part.Position - seat.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = part, d
			end
		end
	end
	return best
end

local function wireDesk(instance: Instance)
	if wired[instance] or not instance:IsA("Seat") then
		return
	end
	wired[instance] = true
	local seat = instance :: Seat

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant == nil then
			return
		end
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		if player == nil then
			return
		end

		local board = boardFor(seat)
		if board ~= nil then
			-- Behind and above the seat, looking at the board: a fixed shot rather than first
			-- person, because a maths panel you read with your own hands on the desk in frame is
			-- a classroom, and first person is a corridor with a UI in it.
			local eye = seat.Position + Vector3.new(0, 7, 0) + (seat.Position - board.Position).Unit * 9
			SeatCamera:FireClient(player, true, CFrame.lookAt(eye, board.Position + Vector3.new(0, 2, 0)), DESK_FOV)
		end
		startLesson(player)

		local released = false
		local function release()
			if released then
				return
			end
			released = true
			endLesson(player)
			if player.Parent ~= nil then
				SeatCamera:FireClient(player, false)
			end
		end

		local connection: RBXScriptConnection
		connection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if seat.Occupant ~= occupant then
				connection:Disconnect()
				release()
			end
		end)
		-- Standing covers the ordinary case; these two cover a character removed underneath the
		-- seat, which would otherwise leave the camera scriptable and the lesson running for
		-- somebody who is no longer sitting anywhere.
		occupant.Died:Once(release)
		occupant.AncestryChanged:Once(function(_, parent)
			if parent == nil then
				release()
			end
		end)
	end)
end

local function wireBoard(instance: Instance)
	-- Nothing to do but be findable. Kept as a bind so a board added at runtime is picked up by
	-- boardFor without any registration step.
	wired[instance] = true
end

-- ---------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------

local function bind(tag: string, wire: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		wire(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(wire)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		wired[instance] = nil
		drawers[instance] = nil
	end)
end

function DeskService.Start()
	bind(DRAWER_TAG, wireDrawer)
	bind(DESK_TAG, wireDesk)
	bind(BOARD_TAG, wireBoard)

	AnswerLesson.OnServerEvent:Connect(function(player: Player, chosen: unknown)
		-- Everything crossing this boundary is untrusted, including its type.
		if typeof(chosen) ~= "number" then
			return
		end
		local state = lesson[player]
		if state == nil then
			return
		end
		local last = lastAnswer[player]
		if last ~= nil and os.clock() - last < Chalkboard.AnswerCooldown then
			return
		end
		lastAnswer[player] = os.clock()

		local questionId = state.asked[state.index]
		if questionId == nil then
			return
		end
		-- The key is on the server and only on the server. The client sent an index; what that
		-- index was worth is decided here.
		if ChalkboardKey.IsCorrect(questionId, chosen :: number) then
			state.score += 1
		end
		state.index += 1
		ask(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lesson[player] = nil
		lastAnswer[player] = nil
	end)
end

return DeskService
