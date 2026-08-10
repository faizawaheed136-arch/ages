--!strict
-- How money is written down. Nothing here moves a balance -- that is
-- MoneyService, and this is to that what Delivery.luau is to DeliveryService: the
-- shared facts about a thing, on the client's side of the fence as well as the
-- server's.
--
-- Shared because the same amount is read in three places that do not otherwise
-- know about each other: the HUD, a priced choice on a panel, and a label floating
-- over a marker on the floor. A balance that formats one way on the HUD and
-- another way in the room reads as two different currencies, and the player has to
-- work out for themselves that it isn't.

local Money = {}

-- US dollars, matching the US English the events are already written in. One
-- constant rather than a Config entry: this is not a number anyone tunes, and a
-- currency that could be switched at runtime would need every authored price
-- rewritten to mean anything.
local SYMBOL = "$"

-- Thousands separators. Below four digits nothing here does anything at all, which
-- is most of childhood -- but an adult's savings are exactly the number the player
-- most needs to read at a glance, and "184000" is not readable at a glance.
local GROUP_SIZE = 3
local GROUP_SEPARATOR = ","

-- Groups the digits from the right, which is the only direction that works: the
-- separators fall every three digits counting back from the units, so a number of
-- unknown length cannot be grouped by walking forward through it.
local function grouped(digits: string): string
	local out = ""
	local sinceBreak = 0
	for index = #digits, 1, -1 do
		out = string.sub(digits, index, index) .. out
		sinceBreak += 1
		-- The `index > 1` is what stops a leading separator on an exact multiple of
		-- three: without it 100 formats as ",100".
		if sinceBreak == GROUP_SIZE and index > 1 then
			out = GROUP_SEPARATOR .. out
			sinceBreak = 0
		end
	end
	return out
end

-- An amount as the player reads it. Truncated rather than rounded, because every
-- amount in the game is authored whole and reaches here whole -- if a fraction ever
-- does arrive, showing the smaller figure is the honest way to be wrong about
-- someone's balance.
--
-- Negatives are formatted rather than clamped. MoneyService guarantees a balance
-- never goes below zero, so a minus sign on screen would be a bug -- and one worth
-- being able to see, rather than one hidden by the thing that displays it.
function Money.Format(amount: number): string
	local sign = if amount < 0 then "-" else ""
	local whole = math.floor(math.abs(amount))
	return `{sign}{SYMBOL}{grouped(tostring(whole))}`
end

return Money
