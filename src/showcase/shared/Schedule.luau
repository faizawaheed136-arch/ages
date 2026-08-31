--!strict
-- The academy day: what the periods are, and how to work out which one it is.
--
-- Shared, because the client needs the same answer the server has. If the client had to ask,
-- every countdown tick would be a remote call; instead both sides run `Schedule.At` against the
-- same synchronised clock and agree without talking.

export type Tone = "routine" | "alert"

export type Period = {
	Key: string,
	Name: string,
	Banner: string,
	Seconds: number,
	Tone: Tone,
	Rings: number,
}

local Schedule = {}

-- **The day, in order.** Total is the cycle; it repeats forever.
--
-- Durations are deliberately short for a showcase -- a real school period would put twenty
-- minutes between chimes and a visitor would never hear one. Nine minutes round the whole day,
-- so somebody who walks in at any moment sees a shift inside two.
--
-- `Rings` is how many times the bell strikes. It is the only part of a period a player can read
-- from anywhere in the building without a screen, and one strike for a routine change against
-- five for lockdown does more than any banner.
Schedule.Periods = {
	{
		Key = "assembly",
		Name = "Morning Assembly",
		Banner = "ATTENTION: MORNING ASSEMBLY. REPORT TO THE COURTYARD.",
		Seconds = 120,
		Tone = "routine",
		Rings = 3,
	},
	{
		Key = "training",
		Name = "Training Time",
		Banner = "ATTENTION: TRAINING TIME HAS BEGUN.",
		Seconds = 180,
		Tone = "routine",
		Rings = 2,
	},
	{
		Key = "free",
		Name = "Free Period",
		Banner = "FREE PERIOD. GROUNDS OPEN.",
		Seconds = 150,
		Tone = "routine",
		Rings = 1,
	},
	{
		Key = "lockdown",
		Name = "Lockdown",
		Banner = "LOCKDOWN. RETURN TO YOUR HALL IMMEDIATELY.",
		Seconds = 90,
		Tone = "alert",
		Rings = 5,
	},
} :: { Period }

Schedule.ByKey = {} :: { [string]: Period }
local total = 0
for _, period in Schedule.Periods do
	Schedule.ByKey[period.Key] = period
	total += period.Seconds
end

-- 540 seconds. Exposed because the client uses it to draw a progress ring.
Schedule.CycleSeconds = total

-- **Derive the period from the clock. Never count up to it.**
--
-- The obvious loop is `for each period do task.wait(period.Seconds) end`, and it is wrong in a
-- way that takes hours to show: task.wait overshoots by a frame or two every call, so the
-- schedule slides later and later, and after a long session the server's idea of the period has
-- drifted away from any wall clock you might want to line it up with.
--
-- Deriving from a monotonic clock cannot drift. It also answers the late-joiner question for
-- free -- a player arriving ninety seconds into Training Time gets Training Time and ninety
-- seconds of it, with no extra bookkeeping.
--
-- Returns the period, how long it has been running, and how long is left.
function Schedule.At(clock: number): (Period, number, number)
	local t = clock % Schedule.CycleSeconds
	for _, period in Schedule.Periods do
		if t < period.Seconds then
			return period, t, period.Seconds - t
		end
		t -= period.Seconds
	end
	-- Unreachable while CycleSeconds is the sum of the durations, but a modulo landing exactly
	-- on the boundary would otherwise fall out of the loop and return nil.
	local last = Schedule.Periods[#Schedule.Periods]
	return last, last.Seconds, 0
end

-- What follows a given period. Used by the client to name the next one under the countdown.
function Schedule.After(key: string): Period
	for index, period in Schedule.Periods do
		if period.Key == key then
			return Schedule.Periods[(index % #Schedule.Periods) + 1]
		end
	end
	return Schedule.Periods[1]
end

return Schedule
