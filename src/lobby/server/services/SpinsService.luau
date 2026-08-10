--!strict
-- Robux buys a spin, a spin lands on a perk, and a perk sits in the player's pocket until
-- they spend it on a new life. This file owns all three steps and the one thing that makes
-- the first of them safe: `ProcessReceipt` can be called more than once for the same
-- purchase, by Roblox's own retry system, and this is the file that makes a second call a
-- no-op instead of a second grant.
--
-- **Why this is a service and not part of `LobbySetupService`.** Buying and pulling happen
-- on their own page, on their own schedule, entirely independent of whether the player is
-- looking at a card -- a receipt can even arrive after the player has left, which is exactly
-- what `ProcessReceipt` returning `NotProcessedYet` is for. `LobbySetupService` only ever
-- reads what this file has already written (`profile.Data.perks`), the same way it only ever
-- read `profile.Data.slots` -- neither owns the other.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.Parent.shared.DataService)
local Perks = require(script.Parent.Parent.content.Perks)

type SpinsState = Types.SpinsState
type OwnedPerk = Types.OwnedPerk
type PerkOffer = Types.PerkOffer
type SpinProduct = Types.SpinProduct

local SpinsUpdatedRemote = Remotes.Get("SpinsUpdated")
local RequestBuySpinsRemote = Remotes.Get("RequestBuySpins")
local RequestSpinRemote = Remotes.Get("RequestSpin")
local SpinActionRefusedRemote = Remotes.Get("SpinActionRefused")
-- The general one-sentence channel, reused rather than a fifth remote of its own. A spin
-- landing and a purchase being granted are both exactly the thing `Notice` already exists
-- for: a line the server composes and the client only displays.
local NoticeRemote = Remotes.Get("Notice")

local SpinsService = {}

local function refuse(player: Player, reason: string)
	SpinActionRefusedRemote:FireClient(player, reason)
end

local function productById(id: string): { id: string, name: string, spins: number, robuxPrice: number, productId: number }?
	for _, product in Config.Spins.Products do
		if product.id == id then
			return product
		end
	end
	return nil
end

local function productByProductId(productId: number): { id: string, name: string, spins: number, robuxPrice: number, productId: number }?
	for _, product in Config.Spins.Products do
		if product.productId == productId then
			return product
		end
	end
	return nil
end

function SpinsService.StateFor(player: Player): SpinsState?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	local data = profile.Data

	local perksOwned: { OwnedPerk } = {}
	for _, perk in Perks.All do
		local count = data.perks[perk.id]
		if count ~= nil and count > 0 then
			table.insert(perksOwned, { id = perk.id, count = count })
		end
	end

	local odds = Perks.Odds()
	local catalog: { PerkOffer } = {}
	for _, perk in Perks.All do
		table.insert(catalog, {
			id = perk.id,
			name = perk.name,
			blurb = perk.blurb,
			rarity = perk.rarity,
			odds = odds[perk.id],
		})
	end

	local products: { SpinProduct } = {}
	for _, product in Config.Spins.Products do
		table.insert(products, {
			id = product.id,
			name = product.name,
			spins = product.spins,
			robuxPrice = product.robuxPrice,
			productId = product.productId,
		})
	end

	return {
		spinsAvailable = data.spinsAvailable,
		perksOwned = perksOwned,
		catalog = catalog,
		products = products,
	}
end

-- Push the whole state. Called on join and after anything that could change it -- a grant, a
-- spin -- the same "redraw everything, cheaply, rather than patch a field" rule the slot list
-- already follows.
function SpinsService.Push(player: Player)
	local state = SpinsService.StateFor(player)
	if state == nil then
		return
	end
	SpinsUpdatedRemote:FireClient(player, state)
end

-- "Open the purchase prompt for this product." Everything up to the prompt is checked here;
-- nothing here grants a spin. The grant is `ProcessReceipt`'s job alone, because that is the
-- only callback Roblox guarantees is honest about a purchase having actually happened.
function SpinsService.RequestBuy(player: Player, productListId: any)
	if typeof(productListId) ~= "string" then
		refuse(player, "That is not a product.")
		return
	end
	local product = productById(productListId)
	if product == nil then
		refuse(player, "That isn't something you can buy.")
		return
	end
	if product.productId == 0 then
		-- The same refuse-by-name pattern as `Config.Lobby.GamePlaceId`: a product only has an
		-- id once it has been created in the Creator Dashboard and pasted into Config, and there
		-- is no honest thing to prompt for before that.
		refuse(player, "This build has no Robux product wired up for that yet.")
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.productId)
end

-- One pull, paid for out of the balance already granted. No payload -- what it lands on is
-- decided entirely in here, so there is nothing on the request a client could have forged
-- the result of.
function SpinsService.RequestSpin(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		refuse(player, "Your save has not finished loading yet. Try again in a moment.")
		return
	end
	local data = profile.Data
	if data.spinsAvailable <= 0 then
		refuse(player, "You don't have a spin to use. Buy one first.")
		return
	end

	data.spinsAvailable -= 1
	local perk = Perks.Roll()
	data.perks[perk.id] = (data.perks[perk.id] or 0) + 1

	SpinsService.Push(player)
	NoticeRemote:FireClient(player, `You landed on {perk.name}. It's waiting in your perks for your next life.`)
end

-- Grant a purchase exactly once, no matter how many times Roblox calls this for it.
--
-- Every early return except the ledger check answers `NotProcessedYet` rather than a failure,
-- because that is the one response that tells Roblox "ask me again later" instead of "this
-- purchase is done" -- and a purchase Roblox believes is done because this callback lied
-- about it is money taken with nothing granted, the one outcome nothing here may ever cause.
local function onProcessReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		-- Not here right now -- rejoin, or Roblox retrying a purchase from a session that has
		-- since ended. Either way this server cannot grant it, and only this server can, because
		-- the grant is a write to a profile only the holder of its session lock may touch.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		-- The player is here but the profile has not finished loading. Vanishingly rare -- a
		-- purchase prompt cannot open before the profile has -- but not impossible if Roblox
		-- queued this receipt from an earlier session.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = profile.Data

	local purchaseId = receiptInfo.PurchaseId
	if data.processedReceipts[purchaseId] then
		-- Already granted. This is the whole of what makes the callback idempotent: Roblox is
		-- free to call this again for the same receipt, and the second call finds its answer
		-- already written rather than writing it a second time.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local product = productByProductId(receiptInfo.ProductId)
	if product == nil then
		-- A product Robux is charging for and this build no longer lists -- a stale entry
		-- removed from `Config.Spins.Products` after it shipped. Loud, because Robux was already
		-- paid and nothing was granted for it; a human has to see this and refund by hand. Marked
		-- granted anyway, because the one thing worse than nothing being granted is Roblox
		-- retrying this receipt forever with no build that will ever recognise it.
		warn(`[AGES] lobby: receipt for unknown developer product {receiptInfo.ProductId} (purchase {purchaseId}, player {player.Name}) -- nothing granted, needs a manual refund`)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	data.spinsAvailable += product.spins
	data.processedReceipts[purchaseId] = true

	SpinsService.Push(player)
	NoticeRemote:FireClient(player, `{product.name} added -- you have {data.spinsAvailable} spin{data.spinsAvailable == 1 and "" or "s"} to use.`)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onPlayerAdded(player: Player)
	task.spawn(function()
		local profile = DataService.WaitForProfile(player, Config.Lobby.ProfileWaitSeconds)
		if profile == nil or player.Parent ~= Players then
			return
		end
		SpinsService.Push(player)
	end)
end

function SpinsService:Init()
	MarketplaceService.ProcessReceipt = onProcessReceipt

	RequestBuySpinsRemote.OnServerEvent:Connect(function(player, productListId)
		SpinsService.RequestBuy(player, productListId)
	end)

	RequestSpinRemote.OnServerEvent:Connect(function(player)
		SpinsService.RequestSpin(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
end

function SpinsService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return SpinsService
