--!strict
-- What the courtyard machine sells.
--
-- Same shape as Uniforms: shared so the UI can draw the list, but the client sends a **key** and
-- the server looks it up. A remote that takes an asset id or a model name from the client is one
-- that will eventually be handed something that is not a can.

export type Drink = {
	Key: string,
	Name: string,
	Blurb: string,
	-- Body and lid colours. The can is built from parts rather than a mesh, so the whole
	-- catalogue costs nothing to add to -- see VendingService.buildCan.
	Body: Color3,
	Lid: Color3,
	-- How many sips empty it. Fewer sips means each one has to visibly move the level, which is
	-- what makes drinking read as drinking rather than as a cooldown.
	Sips: number,
}

local Drinks = {}

Drinks.Catalogue = {
	{
		Key = "energy",
		Name = "VOLT",
		Blurb = "Energy drink. Tastes industrial, which is the point.",
		Body = Color3.fromRGB(196, 172, 44),
		Lid = Color3.fromRGB(178, 182, 190),
		Sips = 4,
	},
	{
		Key = "water",
		Name = "Canned Water",
		Blurb = "Still. Cold. Nothing added.",
		Body = Color3.fromRGB(150, 172, 192),
		Lid = Color3.fromRGB(178, 182, 190),
		Sips = 5,
	},
} :: { Drink }

Drinks.ByKey = {} :: { [string]: Drink }
for _, drink in Drinks.Catalogue do
	Drinks.ByKey[drink.Key] = drink
end

-- Seconds between sips. Slightly longer than the sip sound, so holding the button reads as
-- steady drinking rather than as a stutter of overlapping samples.
Drinks.SipCooldown = 0.7

return Drinks
