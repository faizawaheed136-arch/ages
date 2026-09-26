--!strict
--[[
	The dealership shop in the open-space sandbox: pretend money, a pretend garage, real cars.

	In AGES the shop sells through VehicleService and the life's own balance. None of that exists
	here, so this stands in for it -- every player starts with STARTING_MONEY, buying takes it off,
	and DRIVE or TEST DRIVE builds the real car (world/VehicleChassis, drawn by shared/CarBody) on a
	test-drive bay in front of the showroom and sits the player in it. Nothing is saved.

	Talks to sandbox/dealership/ShopSandbox.client.luau over two remotes it makes itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CarBody = require(ReplicatedStorage:WaitForChild("CarBody"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local VehicleChassis = require(ServerStorage:WaitForChild("VehicleChassis"))
local Vehicles = require(ServerStorage:WaitForChild("Vehicles"))

type VehicleKind = Types.VehicleKind

-- Enough to buy most of the lot, not all of it: the price column should still mean something.
local STARTING_MONEY = 75000

local request = Instance.new("RemoteEvent")
request.Name = "SandboxShopRequest"
request.Parent = ReplicatedStorage
local stateRemote = Instance.new("RemoteEvent")
stateRemote.Name = "SandboxShopState"
stateRemote.Parent = ReplicatedStorage

type Garage = {
	money: number,
	owned: { [string]: boolean },
	paint: { [string]: string },
	active: string?,
	car: VehicleChassis.Chassis?,
}

local garages: { [Player]: Garage } = {}

local function garageOf(player: Player): Garage
	local garage = garages[player]
	if garage == nil then
		garage = { money = STARTING_MONEY, owned = {}, paint = {}, active = nil, car = nil }
		garages[player] = garage
	end
	return garage :: Garage
end

local function push(player: Player, notice: string?)
	local garage = garageOf(player)
	stateRemote:FireClient(player, {
		catalog = Vehicles.All,
		owned = garage.owned,
		paint = garage.paint,
		active = garage.active,
		money = garage.money,
		notice = notice,
	})
end

-- Builds `kind` on the first test-drive bay, nose to the road, and puts the player at the wheel.
local function roll(player: Player, kind: VehicleKind, paintKey: string?, name: string)
	local garage = garageOf(player)
	if garage.car then
		garage.car.destroy()
		garage.car = nil
	end
	local dealership = Workspace:FindFirstChild("Dealership")
	local bay = if dealership then dealership:FindFirstChild("TestDriveBay") else nil
	local ground = if bay and bay:IsA("BasePart") then bay.CFrame else CFrame.new()
	local paint = CarBody.Paint(paintKey)
	local chassis = VehicleChassis.Build(kind, ground * CFrame.new(0, CarBody.Layout(kind).hullY + 0.1, 0), if paint then paint.color else nil)
	chassis.model.Name = name
	chassis.model.Parent = Workspace
	garage.car = chassis
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		task.wait(0.2)
		chassis.seatDriver(humanoid)
	end
end

request.OnServerEvent:Connect(function(player: Player, action: any, vehicleId: any, paintKey: any)
	local garage = garageOf(player)
	if action == "hello" then
		push(player, nil)
		return
	end
	if typeof(vehicleId) ~= "string" then
		return
	end
	local kind = Vehicles.Get(vehicleId)
	if kind == nil then
		return
	end
	local paint = if typeof(paintKey) == "string" then paintKey else nil
	if action == "buy" then
		if garage.owned[kind.id] then
			push(player, "Already yours.")
		elseif garage.money < kind.price then
			push(player, "Not enough money for that one.")
		else
			garage.money -= kind.price
			garage.owned[kind.id] = true
			if CarBody.Paint(paint) then
				garage.paint[kind.id] = paint :: string
			end
			push(player, `Bought the {kind.name}.`)
		end
	elseif action == "drive" and garage.owned[kind.id] then
		garage.active = kind.id
		roll(player, kind, garage.paint[kind.id], `Vehicle_{player.Name}`)
		push(player, nil)
	elseif action == "test" then
		roll(player, kind, paint, `TestDrive_{player.Name}`)
		push(player, `Test drive: the {kind.name}. Take it out on the road!`)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local garage = garages[player]
	if garage and garage.car then
		garage.car.destroy()
	end
	garages[player] = nil
end)
