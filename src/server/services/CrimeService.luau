--!strict
-- CrimeService owns the narrative layer of the crime system. The mechanical side
-- — theft sessions, bounty heat, police pursuit, gang standing — lives in its own
-- services. This file connects that machinery to the life event engine so the
-- player's choices around crime have consequences that persist beyond the mini-game.
--
-- Two things it does:
--  1. Listens for arrests (via BountyService.SetArrestedHandler) and sets / clears
--     the flags that life events gate on.
--  2. Listens for crime event answers (via EventService.OnAnswered) and updates
--     flags so later events can branch off what the player chose.
--
-- Nothing here touches money, heat, or officers. If a crime event wants to award
-- or take money, it writes that into the choice itself; this service only keeps
-- the flag ledger in sync with reality.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local BountyService = require(script.Parent.BountyService)
-- The alias below reads `Types.LifeData` and this require was missing. A type alias is
-- erased before the file runs, so unlike the four sibling cases this one never threw --
-- it just quietly made `LifeData` resolve to nothing, which turns every annotation in
-- this file into `any` and switches off the `--!strict` checking it looks like it has.
local Types = require(ReplicatedStorage:WaitForChild("Types"))


type LifeData = Types.LifeData
type Player = Players.Player

local CrimeService = {}

-- Called the instant the conviction is written, before custody ages the life
-- forward. We set `convicted` here so the very next event tick can read it and
-- fire the post-arrest content that belongs to that life moment.
local function onArrested(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	if data == nil then
		return
	end
	data.flags["convicted"] = data.ageMonths
	-- Busted is a fresh-wound flag: once the conviction lands, the moment has
	-- passed and the stigma is what matters instead.
	data.flags["busted"] = nil
end

-- When a crime event is answered, update the flag ledger. A choice that sets
-- `first_crime` is the first time the life has stolen; a choice that sets
-- `busted` is the first time they were caught; a choice that sets `gang_recruited`
-- is the first time a gang took notice. All three are single-use memories.
local function onAnswered(player: Player, event: Types.LifeEvent, choice: Types.EventChoice)
	if choice.sets == nil then
		return
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	if data == nil then
		return
	end
	for _, flagId in choice.sets do
		if data.flags[flagId] == nil then
			-- Same age semantics as everywhere else: the flag carries the age
			-- the life was when they first did this thing.
			local ageYears = data.ageMonths // Config.Time.MonthsPerYear
			data.flags[flagId] = ageYears
		end
	end
end

function CrimeService:Init()
	BountyService.SetArrestedHandler(onArrested)
	EventService.OnAnswered(onAnswered)
end

function CrimeService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		-- Re-establish flags from current state on join, in case the life already
		-- has convictions or a busted flag when they reconnect.
		local profile = DataService.GetProfile(player)
		if profile == nil then
			return
		end
		local data = Lives.Active(profile.Data)
		if data == nil then
			return
		end
		-- Busted is only meaningful while the arrest is fresh; once the player
		-- is out of custody it becomes `convicted` instead. Both coexist for a
		-- window so the right event fires at the right moment.
		if data.convictions > 0 and data.flags["convicted"] == nil then
			data.flags["convicted"] = data.ageMonths
		end
		if data.flags["busted"] ~= nil then
			-- Keep busted alive while custody is running; clear it when the
			-- player walks out the door.
			local tierIndex = 1
			for i, tier in Config.Crime.Tiers do
				if data.bounty >= tier.atLeast then
					tierIndex = i
				end
			end
			local years = Config.Crime.CustodyYearsByTier[tierIndex] or 0
			if data.ageMonths >= (data.flags["busted"] :: number) + years * 12 then
				data.flags["busted"] = nil
			end
		end
		-- On-parole window is 24 months after release. Cleared by the first
		-- event that writes a new flag, or explicitly by a parole event.
		if data.flags["on_parole"] ~= nil then
			local releaseAge = data.flags["on_parole"] :: number
			if data.ageMonths >= releaseAge + 24 then
				data.flags["on_parole"] = nil
			end
		end
	end)
end

return CrimeService
