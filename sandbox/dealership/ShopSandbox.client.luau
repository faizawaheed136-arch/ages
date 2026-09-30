--!strict
--[[
	The dealership shop in the open-space sandbox, client side: the game's own shop
	(world/DealershipShop, ui/DealershipShopUI, world/ShopStage) run against ShopSandbox.server's
	pretend money instead of the game's. Also spins the turntables, drives the car the player sits in
	and turns every car's wheels, as the game's client does.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local client = ReplicatedStorage:WaitForChild("ShopClient")
local CarDriver = require(client:WaitForChild("CarDriver") :: ModuleScript)
local CarWheels = require(client:WaitForChild("CarWheels") :: ModuleScript)
local CarSound = require(client:WaitForChild("CarSound") :: ModuleScript)
local DriveHUD = require(client:WaitForChild("DriveHUD") :: ModuleScript)
local DealershipShop = require(client:WaitForChild("DealershipShop") :: ModuleScript)
local DealershipShopUI = require(client:WaitForChild("DealershipShopUI") :: ModuleScript)
local DealershipTurntables = require(client:WaitForChild("DealershipTurntables") :: ModuleScript)
local ShopStage = require(client:WaitForChild("ShopStage") :: ModuleScript)

local request = ReplicatedStorage:WaitForChild("SandboxShopRequest") :: RemoteEvent
local stateRemote = ReplicatedStorage:WaitForChild("SandboxShopState") :: RemoteEvent

local onState: { (any, any, any, any) -> () } = {}
local onMoney: { (number) -> () } = {}
local onNotice: { (string) -> () } = {}

stateRemote.OnClientEvent:Connect(function(state: any)
	for _, callback in onState do
		callback(state.catalog, state.owned, { paint = state.paint, rims = state.rims, glow = state.glow }, state.active)
	end
	for _, callback in onMoney do
		callback(state.money)
	end
	if state.notice then
		for _, callback in onNotice do
			callback(state.notice)
		end
	end
end)

DealershipTurntables.Start()
CarDriver.Start(DriveHUD)
CarWheels.Start()
CarSound.Start()
DealershipShop.Start(DealershipShopUI, ShopStage, {
	onState = function(callback)
		table.insert(onState, callback)
	end,
	onMoney = function(callback)
		table.insert(onMoney, callback)
	end,
	onNotice = function(callback)
		table.insert(onNotice, callback)
	end,
	buy = function(vehicleId: string, look: any)
		request:FireServer("buy", vehicleId, look.paint, look.rims, look.glow)
	end,
	customize = function(vehicleId: string, look: any)
		request:FireServer("customize", vehicleId, look.paint, look.rims, look.glow)
	end,
	drive = function(vehicleId: string)
		request:FireServer("drive", vehicleId)
	end,
	testDrive = function(vehicleId: string, paintKey: string?)
		request:FireServer("test", vehicleId, paintKey)
	end,
})
request:FireServer("hello")
