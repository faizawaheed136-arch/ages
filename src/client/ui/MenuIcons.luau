--!strict
-- The pictures on the menu rail, drawn out of Frames.
--
-- **Why drawn and not uploaded.** An image asset has to be uploaded, moderated and
-- referenced by a number, and until all three have happened it renders as nothing. That
-- is a rail of seven blank squares on somebody else's machine, on the one surface that
-- has to be legible before a player has learned anything -- and it fails silently, which
-- is the failure this codebase likes least. A rounded rectangle always renders.
--
-- The rail used to carry a single capital letter per tab for exactly this reason, and it
-- was honest but it read as a debug build. This is the same trade made properly: no
-- assets, no moderation queue, no numbers to lose, and a shape a player can recognise
-- from across the screen.
--
-- **Everything here is built out of gaps, never out of holes.** Two ink shapes that
-- overlap merge into one silhouette, so the obvious way to draw a knob on a slider or a
-- head over a shoulder is to punch a hole in the shape underneath in the background
-- colour -- and a hole is a shape that has to be repainted every time the tile it sits on
-- changes colour, which on this rail is on every hover. So no icon here overlaps itself.
-- Where two parts would touch, they are moved apart and the gap does the drawing. That is
-- the constraint that makes `Paint` a one-line walk instead of a bookkeeping problem.
--
-- Coordinates are all scale, inside a square. An icon is therefore correct at 18 pixels
-- on a phone and at 40 on a monitor with no second set of numbers, and `UICorner` in
-- scale means a circle stays a circle rather than becoming a rounded square when the rail
-- is scaled up.

local MenuIcons = {}

-- A filled shape. `radius` is a fraction of the shape's shorter side, so 0.5 is a circle.
local function ink(parent: Instance, x: number, y: number, w: number, h: number, radius: number): Frame
	local part = Instance.new("Frame")
	part.AnchorPoint = Vector2.new(0, 0)
	part.Position = UDim2.fromScale(x, y)
	part.Size = UDim2.fromScale(w, h)
	part.BackgroundColor3 = Color3.new(1, 1, 1)
	part.BorderSizePixel = 0
	part.Parent = parent

	if radius > 0 then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(radius, 0)
		corner.Parent = part
	end
	return part
end

-- An outlined shape: no fill, just the stroke. Used where a ring has to read as a ring --
-- a coin, the bow of a key -- and where a filled circle would read as a dot.
local function outline(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	radius: number,
	thickness: number
): Frame
	local part = ink(parent, x, y, w, h, radius)
	part.BackgroundTransparency = 1

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = thickness
	stroke.Parent = part
	return part
end

-- A shape turned about its own centre. The only way to get a diagonal out of a Frame, and
-- the shield's point is the one thing in this file that needs one.
local function tilted(parent: Instance, x: number, y: number, w: number, h: number, radius: number, degrees: number): Frame
	local part = ink(parent, x, y, w, h, radius)
	part.Rotation = degrees
	return part
end

-- One builder per tab id. Keyed rather than branched so that the set of ids this module
-- knows is a value the caller can check against, and so `Draw` can say which ones exist
-- when it is handed one that does not.
local BUILDERS: { [string]: (root: Frame, unit: number) -> () } = {
	-- A briefcase: the handle is an outline so that the body drawn over its lower edge
	-- reads as a handle going behind a case rather than as a box with a lump on it.
	jobs = function(root: Frame, unit: number)
		outline(root, 0.30, 0.02, 0.40, 0.28, 0.18, unit * 0.09)
		ink(root, 0.00, 0.26, 1.00, 0.62, 0.12)
	end,

	-- A coin, ring and centre. The gap between the two is the whole icon: closed up, this
	-- is a filled circle and could be anything.
	money = function(root: Frame, unit: number)
		outline(root, 0.02, 0.02, 0.96, 0.96, 0.5, unit * 0.10)
		ink(root, 0.36, 0.36, 0.28, 0.28, 0.5)
	end,

	-- Two people, side by side rather than one behind the other. Overlapping them is the
	-- version that looks better on paper and merges into a blob at rail size.
	relationships = function(root: Frame, _unit: number)
		ink(root, 0.02, 0.08, 0.40, 0.40, 0.5)
		ink(root, 0.00, 0.56, 0.44, 0.36, 0.22)
		ink(root, 0.58, 0.08, 0.40, 0.40, 0.5)
		ink(root, 0.56, 0.56, 0.44, 0.36, 0.22)
	end,

	-- A shield. The two parts are meant to merge -- this is the one icon that is a single
	-- silhouette, and the tilted square is only a way of getting a point on the bottom of
	-- a rectangle.
	gangs = function(root: Frame, _unit: number)
		ink(root, 0.08, 0.06, 0.84, 0.42, 0.10)
		tilted(root, 0.20, 0.25, 0.60, 0.60, 0.08, 45)
	end,

	-- Three bars climbing. The one icon everybody already knows, and skills is the pane
	-- where being instantly readable matters most -- it is the one a player opens to ask a
	-- question rather than to do something.
	skills = function(root: Frame, _unit: number)
		ink(root, 0.06, 0.56, 0.22, 0.36, 0.2)
		ink(root, 0.39, 0.32, 0.22, 0.60, 0.2)
		ink(root, 0.72, 0.08, 0.22, 0.84, 0.2)
	end,

	-- A map pin: a round head merged into a tilted-square point, the same trick the
	-- shield above uses to get a point on the bottom of a rectangle. The universal "go
	-- here" mark on every map this game is competing with, which is exactly the pane
	-- behind this tile -- a list of places, each one pointing the guide arrows at itself.
	locations = function(root: Frame, _unit: number)
		ink(root, 0.20, 0.04, 0.60, 0.60, 0.5)
		tilted(root, 0.32, 0.40, 0.36, 0.36, 0.06, 45)
	end,

	-- Two sliders, one pushed right and one pushed left. A gear is the usual picture and a
	-- gear is a ring with eight teeth through the middle of it, which at twenty-four pixels
	-- is a grey smudge. This is also the truer picture: the pane behind it is a list of
	-- switches, not a machine.
	settings = function(root: Frame, _unit: number)
		ink(root, 0.05, 0.22, 0.40, 0.13, 0.5)
		ink(root, 0.51, 0.15, 0.18, 0.27, 0.5)
		ink(root, 0.75, 0.22, 0.20, 0.13, 0.5)

		ink(root, 0.05, 0.65, 0.14, 0.13, 0.5)
		ink(root, 0.25, 0.58, 0.18, 0.27, 0.5)
		ink(root, 0.49, 0.65, 0.46, 0.13, 0.5)
	end,
}

-- Every part of an already-drawn icon, recoloured.
--
-- Cheap enough to call on a hover tween because an icon is at most six instances, and it
-- is a walk rather than a stored list so that nothing has to be kept in sync with what
-- `Draw` happened to build. That only works because no part of an icon is a hole -- see
-- the header.
function MenuIcons.Paint(root: Frame, color: Color3)
	for _, part in root:GetDescendants() do
		if part:IsA("GuiObject") then
			part.BackgroundColor3 = color
		elseif part:IsA("UIStroke") then
			part.Color = color
		end
	end
end

-- Draw one icon, square, centred in whatever it is parented to.
--
-- Errors on an id it has no picture for, rather than returning an empty frame. A tab in
-- `Config.UI.Menu.Tabs` with nothing drawn for it would otherwise be a blank square in the
-- rail -- which looks exactly like an icon that failed to load, and would send whoever
-- found it looking for a missing asset in a file that has none.
function MenuIcons.Draw(parent: Instance, id: string, pixels: number, color: Color3): Frame
	local build = BUILDERS[id]
	if build == nil then
		local known: { string } = {}
		for name in BUILDERS do
			table.insert(known, name)
		end
		table.sort(known)
		error(
			`MenuIcons: nothing drawn for "{id}". Add a builder to MenuIcons or remove the tab from `
				.. `Config.UI.Menu.Tabs. Known: {table.concat(known, ", ")}.`
		)
	end

	local root = Instance.new("Frame")
	root.Name = `Icon_{id}`
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(pixels, pixels)
	root.BackgroundTransparency = 1
	-- Above the tile it sits on. Set here rather than left to child order, because the
	-- tile also carries a selection pip and a full-size press target, and which of the
	-- three happens to be created last is not a thing to draw a rail on top of.
	root.ZIndex = 2
	root.Parent = parent

	-- Stroke thickness is the one measurement that cannot be expressed in scale, so it is
	-- passed through as a fraction of the icon's size and each builder multiplies. A fixed
	-- two pixels would be a hairline at forty and a blob at eighteen.
	build(root, pixels)
	MenuIcons.Paint(root, color)
	return root
end

return MenuIcons
