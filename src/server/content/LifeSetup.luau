--!strict
-- The rules of choosing a life: what a menu may offer, and what an answer must look like.
--
-- **Why this file exists at all.** The menu that picks a life moved out of the game place
-- and into the lobby, where it belongs -- you choose who you are about to be *before* you
-- load into a world, not on a card drawn over one already running. But three things still
-- need these rules in the game place: the debug harness's `/setup skip`, which starts a life
-- without a lobby, and `NameOf`/`CountryOf`, which every sentence naming a life goes through.
-- Two copies of "what is a valid name" is exactly the kind of thing that drifts, so there is
-- one copy and both places require it.
--
-- **Why it is here, next to Countries, rather than in `src/shared`.** It needs the country
-- list, and that list is server-side in both places -- the client never requires it, it
-- receives the countries it may pick inside `SetupOptions`. `Countries.luau` is mapped into
-- the lobby by path (see `lobby.project.json`), and this file is mapped alongside it, so
-- `script.Parent.Countries` resolves in the game place and in the lobby both. Moving either
-- file without the other breaks that, which is why they are siblings on purpose.
--
-- **Everything here is checked twice on purpose.** The options payload is built from the
-- same Config and content the validator reads, so a well-behaved menu cannot offer a spend
-- that will then be refused -- and a badly-behaved one is refused with a reason rather than
-- obeyed. The client is a convenience; this file is the rule.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Countries = require(script.Parent.Countries)

type Gender = Types.Gender
type Country = Types.Country
type Era = Types.Era
type LifeData = Types.LifeData
type LifeSetupData = Types.LifeSetup
type SetupOptions = Types.SetupOptions
type SetupRequest = Types.SetupRequest
type StatName = Types.StatName

local SETUP = Config.Setup

-- The four stats, in the order the menu draws them, written down once. `Config.Stats.
-- Starting` is a map and map order is whatever the hash says, so a menu built by
-- iterating it would reorder its own rows between runs.
local STAT_ORDER: { StatName } = { "health", "happiness", "smarts", "looks" }

local LifeSetup = {}

LifeSetup.StatOrder = STAT_ORDER

-- Every era the menu is allowed to show, including the ones it is not allowed to pick.
-- Read straight off Config: a second list here is a second thing to keep in step.
local function eras(): { Era }
	return SETUP.Eras :: { Era }
end

local function eraById(id: string): Era?
	for _, era in eras() do
		if era.id == id then
			return era
		end
	end
	return nil
end

-- The era a menu opens on. The first *available* one rather than the first one, so that
-- putting an unreleased era at the top of the Config list -- which is where a shiny new
-- one wants to go -- cannot open every player's menu on a row they cannot use.
function LifeSetup.DefaultEraId(): string?
	for _, era in eras() do
		if era.available then
			return era.id
		end
	end
	return nil
end

-- Everything the menu needs to draw itself and nothing it does not.
--
-- Rebuilt per call rather than cached, because it carries `lifeNumber`, which changes
-- every death -- and a cache whose only volatile field is the one the player reads first
-- is a cache that will be wrong in exactly the visible place.
--
-- Takes the account counter rather than reading it off the life, because `lifeNumber` is
-- the one field here that is a fact about the *player* -- lives finished across every save
-- slot -- and a life cannot know it.
function LifeSetup.Options(livesLived: number): SetupOptions
	return {
		lifeNumber = livesLived + 1,
		statPoints = SETUP.StatPoints,
		minPerStat = SETUP.MinPerStat,
		maxPerStat = SETUP.MaxPerStat,
		maxNameLength = SETUP.MaxNameLength,
		startingStats = Config.Stats.Starting,
		countries = Countries.All,
		defaultCountryId = Countries.DefaultId,
		eras = eras(),
	}
end

-- Trim, collapse runs of whitespace, and reject anything that is not a plain name.
--
-- Runs *before* TextService, because a web call per keystroke-length string of punctuation
-- is a web call spent on something that was never going to be accepted, and because the
-- filter's job is profanity rather than shape. Letters, spaces, apostrophes and hyphens:
-- enough for O'Brien and Anne-Marie, and not enough for a name made of brackets.
local function cleanName(raw: string): string?
	local trimmed = string.gsub(raw, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	trimmed = string.gsub(trimmed, "%s+", " ")
	if trimmed == "" then
		return nil
	end
	if utf8.len(trimmed) == nil then
		-- Not valid UTF-8 at all, which no keyboard produces and every hand-rolled
		-- packet eventually does.
		return nil
	end
	local length = utf8.len(trimmed) :: number
	if length > SETUP.MaxNameLength then
		return nil
	end
	if string.match(trimmed, "^[%a][%a%s'%-]*$") == nil then
		return nil
	end
	return trimmed
end

-- Roblox's filter, applied to a name that will be shown to other players.
--
-- Returns nil rather than the unfiltered text on any failure, and the caller refuses.
-- That is the whole point: `FilterStringAsync` is a yielding web call that throws when
-- the service is unreachable, and the tempting `pcall(...) or raw` fallback would mean an
-- outage is also the moment the filter stops running. A player told to try again is a
-- much smaller problem than an unfiltered name on a nameplate.
function LifeSetup.FilterName(player: Player, name: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(result) ~= "string" or result == "" then
		return nil
	end
	return result
end

-- Read one stat delta out of whatever the client sent. Deliberately tolerant of an absent
-- key -- a menu that left a stat alone has nothing to say about it -- and deliberately
-- intolerant of everything else.
local function readDelta(raw: any, statName: StatName): number?
	if raw == nil then
		return 0
	end
	if typeof(raw) ~= "table" then
		return nil
	end
	local value = (raw :: { [string]: any })[statName]
	if value == nil then
		return 0
	end
	if typeof(value) ~= "number" or value ~= value or value % 1 ~= 0 then
		-- NaN fails the equality test; a fraction fails the modulo. Both would otherwise
		-- sail through a bounds check and land in a stat.
		return nil
	end
	return value
end

-- Turn the payload into a request, or say in one sentence why it is not one.
--
-- Returns the reason as a *player-facing* string rather than a code, because the only
-- consumer is a line of text under the Create button. A hostile client gets a sentence it
-- has no use for, which is the correct amount of information to give it.
--
-- Pure: no player, no profile, no yielding. That is what lets it run in the lobby without
-- either place needing to know the other exists.
function LifeSetup.Parse(payload: any): (SetupRequest?, string?)
	if typeof(payload) ~= "table" then
		return nil, "Something went wrong reading that. Try again."
	end
	local fields = payload :: { [string]: any }

	local gender = fields.gender
	if gender ~= "male" and gender ~= "female" then
		return nil, "Pick a gender to continue."
	end

	local countryId = fields.countryId
	if typeof(countryId) ~= "string" or Countries.ById[countryId] == nil then
		return nil, "That country isn't one of the options."
	end

	local eraId = fields.eraId
	if typeof(eraId) ~= "string" then
		return nil, "Pick an era to continue."
	end
	local era = eraById(eraId)
	if era == nil then
		return nil, "That era isn't one of the options."
	end
	-- The reason locked eras are entries rather than decoration: the greying-out is the
	-- menu being polite, and this is the game actually refusing.
	if not era.available then
		return nil, `{era.name} isn't ready to play yet.`
	end

	if typeof(fields.firstName) ~= "string" or typeof(fields.lastName) ~= "string" then
		return nil, "Enter a first and last name."
	end
	local firstName = cleanName(fields.firstName)
	local lastName = cleanName(fields.lastName)
	if firstName == nil or lastName == nil then
		return nil, `Names need to be letters, up to {SETUP.MaxNameLength} characters. Try again or press Shuffle.`
	end

	local deltas: { [string]: number } = {}
	local spent = 0
	for _, statName in STAT_ORDER do
		local delta = readDelta(fields.statDeltas, statName)
		if delta == nil then
			return nil, "Something went wrong reading your stats. Try again."
		end
		if delta > SETUP.MaxPerStat or delta < SETUP.MinPerStat then
			return nil, `No stat can move more than +{SETUP.MaxPerStat} or {SETUP.MinPerStat}.`
		end
		deltas[statName] = delta
		spent += delta
	end
	-- Summed rather than counted per stat, so that taking points out of one stat really
	-- does pay for another. Under budget is allowed and over is not: leaving points
	-- unspent is the player's business, and the menu says how many are left.
	if spent > SETUP.StatPoints then
		return nil, `That spends {spent} points and you have {SETUP.StatPoints}.`
	end

	return {
		gender = gender :: Gender,
		firstName = firstName,
		lastName = lastName,
		countryId = countryId,
		eraId = eraId,
		statDeltas = deltas,
	},
		nil
end

-- A whole valid setup, rolled. Used by the debug harness to skip the menu, and by the
-- create page's Shuffle button by way of the names it was sent.
function LifeSetup.Roll(gender: Gender): LifeSetupData
	local country = Countries.ById[Countries.DefaultId]
	local firstName, lastName = Countries.RollName(country, gender)
	return {
		firstName = firstName,
		lastName = lastName,
		countryId = country.id,
		eraId = LifeSetup.DefaultEraId() or "modern",
	}
end

-- What the game calls this life, for anywhere a life needs naming. Falls back to the
-- player's Roblox name rather than to an empty string, because every caller of this is
-- putting it in a sentence.
function LifeSetup.NameOf(data: LifeData, fallback: string): string
	local setup = data.setup
	if setup == nil then
		return fallback
	end
	return `{setup.firstName} {setup.lastName}`
end

-- The country this life began in, or nil if it has not begun. Public because the debug
-- harness and anything later that wants to vary content by country should ask for the
-- record rather than re-look-up an id off the profile.
function LifeSetup.CountryOf(data: LifeData): Country?
	local setup = data.setup
	if setup == nil then
		return nil
	end
	return Countries.ById[setup.countryId]
end

-- The starting stats a life begins with, plus whatever the menu spent, clamped.
--
-- Here rather than in the service that commits, because both places commit: the lobby when
-- a player fills a card, and the game place when `/setup skip` rolls one. The clamp is the
-- same one StatService applies on every later change -- a menu is not allowed to put a
-- number on a profile that the rest of the game would consider impossible.
function LifeSetup.StartingStats(deltas: { [string]: number }?): Types.Stats
	local stats: Types.Stats = table.clone(Config.Stats.Starting)
	if deltas == nil then
		return stats
	end
	for _, statName in STAT_ORDER do
		local delta = deltas[statName]
		if delta ~= nil and delta ~= 0 then
			local value = stats[statName] + delta
			stats[statName] = math.clamp(value, Config.Stats.Min, Config.Stats.Max)
		end
	end
	return stats
end

-- Checked at boot rather than discovered when the first player presses Create on a card
-- with no pickable row on it. Called by whichever service owns setup in this place.
function LifeSetup.AssertPlayable()
	if LifeSetup.DefaultEraId() == nil then
		error("[AGES content] no era in Config.Setup.Eras is available, so no life could ever be started")
	end
end

return LifeSetup
