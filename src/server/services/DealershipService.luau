--!strict
--[[
	Meridian Motors, at runtime: the cars on the floor, what they cost, and the two things you can
	do at one -- buy it, or take it for a test drive.

	THE CARS ARE BUILT HERE, NOT BAKED. world/DealershipBuild lays the building and a `CarSlot`
	for every display spot, each naming a vehicle id. This service stands the real car on each
	one when the server starts, from content/Vehicles through VehicleChassis.BuildDisplay -- the
	same body the chassis drives away with. So the price on the tag is the price VehicleService
	charges and the car on the turntable is the car you get, by construction: nothing here holds
	a copy of either.

	BUYING GOES THROUGH VehicleService.Buy, which owns the money, the garage and parking the
	first car. This file adds nothing to that path but a sentence: the showroom panel that
	VehicleService speaks through only shows within Config.Vehicles.ShowroomStuds of the counter,
	and the lot runs further than that, so every outcome is also said as a Notice -- a buy button
	that did nothing visible is indistinguishable from a broken one. The checks before the call
	exist only to say *why*; Buy repeats all of them and is the one that decides.

	A TEST DRIVE is a real chassis on a test-drive bay with the player put in its seat, for
	Config.Dealership.TestDriveSeconds. It ends on the clock (the driver is set back down at the
	dealership), when the driver has been out of it too long (left where they are), or when they
	leave. It is never saved: a test car is a loan for this session, not a car the life owns.
	Buying has no age line -- VehicleService never had one -- but driving does.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local VehicleService = require(script.Parent.VehicleService)

local DealershipBuild = require(script.Parent.Parent.world.DealershipBuild)
local DealershipDressing = require(script.Parent.Parent.world.DealershipDressing)
local DealershipProps = require(script.Parent.Parent.content.DealershipProps)
local VehicleChassis = require(script.Parent.Parent.world.VehicleChassis)
local Vehicles = require(script.Parent.Parent.content.Vehicles)

type LifeData = Types.LifeData
type VehicleKind = Types.VehicleKind
type Chassis = VehicleChassis.Chassis

local DEALER = Config.Dealership
local VEHICLES = Config.Vehicles

local NoticeRemote = Remotes.Get("Notice")

-- The price tag's palette: the showroom's own navy and gold, so a tag reads as the building's.
local TAG_BACKGROUND = Color3.fromRGB(20, 30, 54)
local TAG_GOLD = Color3.fromRGB(222, 178, 86)
local TAG_WHITE = Color3.fromRGB(245, 245, 240)

type Drive = {
	chassis: Chassis,
	kind: VehicleKind,
	endsAt: number,
	warned: boolean,
	bay: BasePart?,
	outOfSeatSince: number?,
}

local DealershipService = {}

local drives: { [Player]: Drive } = {}
local lastDriveAt: { [Player]: number } = {}
local bayHolder: { [BasePart]: Player } = {}
local dealership: Model? = nil

local function say(player: Player, text: string)
	NoticeRemote:FireClient(player, text)
end

local function lifeOf(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

local function ownedCount(life: LifeData): number
	local count = 0
	for _ in life.vehicles.owned do
		count += 1
	end
	return count
end

local function humanoidOf(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return nil, nil
	end
	return humanoid, root
end

-- ---------------------------------------------------------------------------------------------
-- Buying
-- ---------------------------------------------------------------------------------------------
local function buy(player: Player, kind: VehicleKind)
	local life = lifeOf(player)
	if life == nil or not life.alive then
		return
	end
	if not VehicleService.IsEnabled() then
		say(player, "The dealership isn't selling right now.")
		return
	end
	if life.vehicles.owned[kind.id] == true then
		say(player, `You already own the {kind.name}.`)
		return
	end
	if ownedCount(life) >= VEHICLES.MaxOwned then
		say(player, `Your garage holds {VEHICLES.MaxOwned} cars. Sell one at the sales counter first.`)
		return
	end
	if life.money < kind.price then
		say(player, `The {kind.name} is {Money.Format(kind.price)}. You have {Money.Format(life.money)}.`)
		return
	end
	-- Read before the buy: Buy only parks the car when nothing else is out.
	local parksNow = life.vehicles.active == nil
	if not VehicleService.Buy(player, kind.id) then
		say(player, `The sale of the {kind.name} didn't go through.`)
		return
	end
	say(
		player,
		if parksNow
			then `You bought the {kind.name}! It's waiting in the pickup lane.`
			else `You bought the {kind.name}! It's in your garage -- bring it out at the sales counter.`
	)
end

-- ---------------------------------------------------------------------------------------------
-- Test drives
-- ---------------------------------------------------------------------------------------------
local function markers(name: string): { BasePart }
	local found: { BasePart } = {}
	local model = dealership
	if model == nil then
		return found
	end
	for _, child in model:GetChildren() do
		if child.Name == name and child:IsA("BasePart") then
			table.insert(found, child)
		end
	end
	return found
end

local function releaseBay(drive: Drive)
	local bay = drive.bay
	if bay ~= nil then
		bayHolder[bay] = nil
		drive.bay = nil
	end
end

--[[
	End a test drive. `bringBack` sets a driver who is still in the car down at the dealership:
	the clock ran out on them mid-drive, possibly across the city, and leaving them standing in
	the road where the car vanished is the test drive ending as a punishment.
]]
local function finish(player: Player, message: string?, bringBack: boolean)
	local drive = drives[player]
	if drive == nil then
		return
	end
	drives[player] = nil
	releaseBay(drive)

	local humanoid, root = humanoidOf(player)
	local seated = humanoid ~= nil and humanoid.SeatPart == drive.chassis.seat
	if seated and humanoid then
		humanoid.Sit = false
	end
	drive.chassis.destroy()

	local back = markers("TestDriveReturn")[1]
	local character = player.Character
	if bringBack and seated and root and back and character then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(back.CFrame + Vector3.new(0, DEALER.ReturnLiftStuds, 0))
	end
	if message then
		say(player, message)
	end
end

local function freeBay(): BasePart?
	for _, bay in markers("TestDriveBay") do
		if bayHolder[bay] == nil then
			return bay
		end
	end
	return nil
end

local function testDrive(player: Player, kind: VehicleKind)
	if drives[player] ~= nil then
		say(player, "You're already out on a test drive.")
		return
	end
	local life = lifeOf(player)
	if life == nil or not life.alive then
		return
	end
	if life.ageMonths < DEALER.TestDriveMinAgeYears * 12 then
		say(player, `You have to be {DEALER.TestDriveMinAgeYears} to take a car out.`)
		return
	end
	local last = lastDriveAt[player]
	local cooling = if last then DEALER.TestDriveCooldownSeconds - (os.clock() - last) else 0
	if cooling > 0 then
		say(player, `Give it {math.ceil(cooling)} seconds before your next test drive.`)
		return
	end
	local humanoid = humanoidOf(player)
	if humanoid == nil then
		return
	end
	local bay = freeBay()
	if bay == nil then
		say(player, "Both test-drive bays are busy. Try again in a moment.")
		return
	end

	-- Dropped from the same height VehicleService spawns a bought car from, so it settles onto
	-- its suspension the same way rather than landing on its wheels from nowhere.
	local lift = kind.size.Y / 2 + VEHICLES.SuspensionLength + VEHICLES.WheelRadius + 0.5
	local chassis = VehicleChassis.Build(kind, bay.CFrame * CFrame.new(0, lift, 0))
	chassis.model.Name = `TestDrive_{player.Name}`
	chassis.model:SetAttribute("TestDriveFor", player.UserId)
	chassis.model.Parent = Workspace

	bayHolder[bay] = player
	lastDriveAt[player] = os.clock()
	drives[player] = {
		chassis = chassis,
		kind = kind,
		endsAt = os.clock() + DEALER.TestDriveSeconds,
		warned = false,
		bay = bay,
		outOfSeatSince = nil,
	}
	chassis.seat:Sit(humanoid)
	say(player, `Test drive: {DEALER.TestDriveSeconds} seconds in the {kind.name}. Take it out on the road!`)
end

local function tickDrives()
	local now = os.clock()
	for player, drive in drives do
		local model = drive.chassis.model
		if model.Parent == nil then
			finish(player, nil, false)
			continue
		end

		-- The bay is free once the car has left it, not only when the drive ends.
		local bay = drive.bay
		local body = model.PrimaryPart
		if bay and body and (body.Position - bay.Position).Magnitude > DEALER.BayClearStuds then
			releaseBay(drive)
		end

		local humanoid = humanoidOf(player)
		local seated = humanoid ~= nil and humanoid.SeatPart == drive.chassis.seat
		if seated then
			drive.outOfSeatSince = nil
		elseif drive.outOfSeatSince == nil then
			drive.outOfSeatSince = now
		elseif now - (drive.outOfSeatSince :: number) >= DEALER.TestDriveAbandonSeconds then
			finish(player, `The {drive.kind.name} has gone back to the dealership.`, false)
			continue
		end

		local left = drive.endsAt - now
		if left <= 0 then
			finish(player, `Test drive over. Like the {drive.kind.name}? It's {Money.Format(drive.kind.price)} at Meridian Motors.`, true)
		elseif not drive.warned and left <= DEALER.TestDriveWarnSeconds then
			drive.warned = true
			say(player, `{math.ceil(left)} seconds left on your test drive.`)
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- The cars on the floor
-- ---------------------------------------------------------------------------------------------
local function label(parent: Instance, text: string, color: Color3, y: number, height: number, font: Enum.Font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromScale(0.05, y)
	l.Size = UDim2.fromScale(0.9, height)
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = font
	l.Parent = parent
end

-- The name and price over a car, readable from across the lot.
local function priceTag(part: BasePart, kind: VehicleKind, display: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PriceTag"
	gui.Size = UDim2.fromScale(DEALER.TagWidthStuds, DEALER.TagWidthStuds * 0.38)
	gui.StudsOffsetWorldSpace = Vector3.new(0, kind.size.Y * 1.5 + DEALER.TagLiftStuds, 0)
	gui.MaxDistance = DEALER.TagStuds
	gui.LightInfluence = 0
	gui.Parent = part

	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = TAG_BACKGROUND
	card.BackgroundTransparency = 0.08
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = TAG_GOLD
	stroke.Thickness = 2
	stroke.Parent = card

	label(card, if display == "Lot" then "EVERYDAY" else "LUXURY", TAG_GOLD, 0.06, 0.22, Enum.Font.GothamBold)
	label(card, kind.name, TAG_WHITE, 0.28, 0.34, Enum.Font.GothamBold)
	label(card, Money.Format(kind.price), TAG_GOLD, 0.62, 0.32, Enum.Font.GothamBlack)
end

local function prompt(part: BasePart, name: string, action: string, kind: VehicleKind, key: Enum.KeyCode, pad: Enum.KeyCode, hold: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = kind.name
	p.KeyboardKeyCode = key
	p.GamepadKeyCode = pad
	p.HoldDuration = hold
	p.MaxActivationDistance = DEALER.PromptStuds
	p.RequiresLineOfSight = false
	p.Parent = part
	return p
end

local function stock(model: Model)
	for _, slot in CollectionService:GetTagged(DealershipBuild.SlotTag) do
		if not slot:IsDescendantOf(model) or not slot:IsA("BasePart") then
			continue
		end
		local id = slot:GetAttribute("VehicleId")
		local kind = if typeof(id) == "string" then Vehicles.Get(id) else nil
		if kind == nil then
			error(
				`[AGES dealership] {slot:GetFullName()} asks for vehicle "{tostring(id)}", which content/Vehicles does not sell. `
					.. `Set its VehicleId attribute to one of the ids in content/Vehicles.luau.`
			)
		end
		local display = slot:GetAttribute("Display")

		-- The slot sits a tenth of a stud above the floor it marks.
		local car = VehicleChassis.BuildDisplay(kind, slot.CFrame * CFrame.new(0, -slot.Size.Y / 2, 0))
		car.Name = `Display_{kind.id}`
		car.Parent = slot.Parent
		slot.Transparency = 1

		local body = car.PrimaryPart :: BasePart
		priceTag(body, kind, if typeof(display) == "string" then display else "Lot")
		local buyPrompt = prompt(body, "Buy", `Buy  {Money.Format(kind.price)}`, kind, Enum.KeyCode.E, Enum.KeyCode.ButtonX, DEALER.BuyHoldSeconds)
		-- R, not F: F is Guard in the fight controls, and one key must not do two things at once.
		local drivePrompt = prompt(body, "TestDrive", "Test drive", kind, Enum.KeyCode.R, Enum.KeyCode.ButtonY, 0)
		buyPrompt.Triggered:Connect(function(player: Player)
			buy(player, kind)
		end)
		drivePrompt.Triggered:Connect(function(player: Player)
			testDrive(player, kind)
		end)
	end
end

-- For the harness: what is on the floor and who is out driving.
function DealershipService.Describe(): string
	local count = 0
	for _ in drives do
		count += 1
	end
	local cars = 0
	if dealership then
		for _, d in dealership:GetDescendants() do
			if d:IsA("Model") and string.sub(d.Name, 1, 8) == "Display_" then
				cars += 1
			end
		end
	end
	return `dealership {if dealership then "open" else "missing"}: {cars} cars on show, {count} test drives out`
end

function DealershipService:Init()
	Players.PlayerRemoving:Connect(function(player: Player)
		finish(player, nil, false)
		lastDriveAt[player] = nil
	end)
end

function DealershipService:Start()
	local model = Workspace:FindFirstChild(DealershipBuild.ModelName)
	if model == nil or not model:IsA("Model") then
		warn(
			`[AGES dealership] no Workspace.{DealershipBuild.ModelName}, so nothing is on sale. `
				.. `Build it in Studio: require(ServerScriptService.Server.world.DealershipBuild).Build(corner, workspace).`
		)
		return
	end
	dealership = model
	stock(model)
	-- The props: the Sketchfab models content/DealershipProps names, in place of the builder's
	-- block stand-ins, wherever one is uploaded. Off the start path, because loading an asset
	-- waits on the network and nothing else here should wait for a chair.
	task.spawn(function()
		local swapped, kept = DealershipDressing.Dress(model, DealershipProps)
		if kept > 0 and swapped > 0 then
			print(`[AGES dealership] {swapped} props placed, {kept} still block stand-ins`)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(DEALER.TickSeconds)
			local ok, err = pcall(tickDrives)
			if not ok then
				warn(`[AGES dealership] test drive tick failed: {err}`)
			end
		end
	end)
end

return DealershipService
