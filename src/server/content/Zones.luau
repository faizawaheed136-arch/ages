--!strict
-- Named zones in the world. A zone is a named region of the house — the gym,
-- the backyard, the school lab — and this table is the index that maps a
-- string id to the zone record so the proximity layer can report "you are in
-- the gym" rather than "you are standing near a tagged part".
--
-- Zones are authoring-time objects: they are populated in Studio by tagging
-- parts and reading the AgesZoneId attribute, not built at runtime. The table
-- lives here so the rest of the server has one place to ask "what zone is
-- this id?" without re-deriving the name from the geometry.
--
-- Empty at baseline. The first zones ship with the gym floor and the school
-- lab; everything else is filled in when the corresponding building exists.

--!strict
-- Named zones in the world. A zone is a named region of the house -- the gym,
-- the backyard, the school lab -- and this table is the index that maps a
-- string id to the zone record so the proximity layer can report "you are in
-- the gym" rather than "you are standing near a tagged part".
--
-- Zones are authoring-time objects: they are populated in Studio by tagging
-- parts and reading the AgesZoneId attribute, not built at runtime. The table
-- lives here so the rest of the server has one place to ask "what zone is
-- this id?" without re-deriving the name from the geometry.
--
-- Empty at baseline. The first zones ship with the gym floor and the school
-- lab; everything else is filled in when the corresponding building exists.

local Zones: { [string]: { tag: string } } = {}

return Zones
