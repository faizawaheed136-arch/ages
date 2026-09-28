--!strict
--[[
	Opens the dealership shop when the local player steps into the BUY CARS! circle, and wires it to
	whatever sells the cars.

	THE CIRCLE. world/DealershipBuild lays it as `BuyStation.Apron`, a disc on the showroom floor
	round the salesman's desk. Standing on it opens the shop (client/ui/DealershipShopUI); closing
	the shop leaves it shut until the player has stepped off and back on, so walking away from the
	desk does not reopen it on the way out. While the shop is open the character stands still and
	the world behind the list is blurred.

	THE BACKEND is handed in, not required, so the same shop runs in the game -- against
	VehicleService's remotes and the real balance, wired in init.client -- and in the dealership's
	open-space sandbox, against a stand-in with pretend money. It pushes the catalog, what is owned
	and in what paint, the balance and notices in; the shop's buttons go out through it.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleKind = Types.VehicleKind

-- A car's look as keys (CarBody.Paints, Rims, Glows), and every owned car's.
export type LookKeys = { paint: string?, rims: string?, glow: string? }
export type Looks = { paint: { [string]: string }?, rims: { [string]: string }?, glow: { [string]: string }? }

export type Backend = {
	-- Called with (catalog, owned, looks, active) whenever any of them changes.
	onState: ((catalog: { VehicleKind }, owned: { [string]: boolean }, looks: Looks, active: string?) -> ()) -> (),
	onMoney: ((balance: number) -> ()) -> (),
	onNotice: ((message: string) -> ()) -> (),
	buy: (vehicleId: string, look: LookKeys) -> (),
	drive: (vehicleId: string) -> (),
	testDrive: (vehicleId: string, paintKey: string?) -> (),
	customize: (vehicleId: string, look: LookKeys) -> (),
	-- Told when the shop opens (true) and closes (false), for anything else on screen that
	-- should step aside while it is up. Optional.
	onOpen: ((open: boolean) -> ())?,
}

-- How often the circle is checked, and how far above or below its floor still counts as on it.
local CHECK_SECONDS = 0.2
local CIRCLE_HEIGHT = 8
-- How far past the circle's edge a player must step before it will open the shop again.
local REARM_STUDS = 3
local BLUR = 14

local DealershipShop = {}

local function circle(): BasePart?
	local dealership = Workspace:FindFirstChild("Dealership")
	local station = if dealership then dealership:FindFirstChild("BuyStation", true) else nil
	local apron = if station then station:FindFirstChild("Apron") else nil
	if apron and apron:IsA("BasePart") then
		return apron
	end
	return nil
end

-- Freezes or frees the local character's own controls.
local function setControls(enabled: boolean)
	local player = Players.LocalPlayer
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = if scripts then scripts:FindFirstChild("PlayerModule") else nil
	if module and module:IsA("ModuleScript") then
		local ok, playerModule = pcall(require, module)
		if ok and typeof(playerModule) == "table" then
			local controls = (playerModule :: any):GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end
end

--[[
	Starts watching the circle. `ui` is client/ui/DealershipShopUI, `stage` world/ShopStage; both
	handed in so the sandbox can supply them from wherever it keeps them.
]]
function DealershipShop.Start(ui: any, stage: any, backend: Backend, title: string?)
	local shop = ui.new(stage.new(), title or "Meridian Motors")

	local blur = Instance.new("BlurEffect")
	blur.Name = "DealershipShopBlur"
	blur.Size = 0
	blur.Parent = Lighting

	local armed = true
	local function close()
		blur.Size = 0
		setControls(true)
		if backend.onOpen then
			backend.onOpen(false)
		end
	end
	shop:OnClose(close)

	backend.onState(function(catalog, owned, looks, active)
		if #catalog ~= #shop.catalog then
			shop:SetCatalog(catalog)
		end
		shop:SetOwned(owned, looks, active)
	end)
	backend.onMoney(function(balance)
		shop:SetMoney(balance)
	end)
	backend.onNotice(function(message)
		if shop:IsOpen() then
			shop:Notice(message)
		end
	end)
	shop:OnBuy(function(id: string, look: LookKeys)
		backend.buy(id, look)
	end)
	shop:OnCustomize(function(id: string, look: LookKeys)
		backend.customize(id, look)
	end)
	-- Driving and test drives leave the shop: the car is out on the forecourt, and the player is
	-- put in it.
	shop:OnDrive(function(id: string)
		shop:Close()
		backend.drive(id)
	end)
	shop:OnTestDrive(function(id: string, paintKey: string?)
		shop:Close()
		backend.testDrive(id, paintKey)
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local character = Players.LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			local disc = circle()
			if root == nil or disc == nil or not root:IsA("BasePart") then
				continue
			end
			-- A cylinder lying flat: its diameter is its Y and Z size.
			local radius = disc.Size.Y / 2
			local offset = root.Position - disc.Position
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			local on = flat <= radius and math.abs(offset.Y) <= CIRCLE_HEIGHT
			if shop:IsOpen() then
				blur.Size = if shop:IsViewing() then 0 else BLUR
			elseif on and armed then
				armed = false
				setControls(false)
				blur.Size = BLUR
				shop:Open()
				if backend.onOpen then
					backend.onOpen(true)
				end
			elseif not on and flat > radius + REARM_STUDS then
				armed = true
			end
		end
	end)
	return shop
end

return DealershipShop
