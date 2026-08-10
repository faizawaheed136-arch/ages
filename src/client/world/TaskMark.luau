--!strict
-- The lit disc on the floor that is the thing you are currently being paid to do.
--
-- Deliberately the same gold breathing disc as the classroom door and the hiring
-- counter, and that is the whole design of the shift loop. Gold means one thing in
-- this game and only one: go here. Decisions are made on a panel, so a disc is never
-- asking anything -- it is a place, and a shift is just a place that keeps moving.
-- Nothing about working needed teaching, because walking is the verb they were taught
-- in the kitchen when they were six.
--
-- Drawn on the client, which is the third thing in this system to end up here and for
-- the same reason as the first two. A task is addressed to one person: two shop
-- assistants on the same floor would otherwise walk through each other's
-- instructions, each stepping on a mark that belongs to somebody else's clock.
--
-- Everything decided is decided on the server. This knows where the mark goes and
-- what it says because it was told; it does not know what happens when you reach it,
-- and deleting the disc by hand would remove the light and change nothing at all
-- about whether the task completes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ChoiceMarkers = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("ChoiceMarkers"))

local TaskMark = {}

-- One mark the player is being asked to walk to. `id` is the task's, so that two live
-- marks keep their identities between pushes rather than being told apart by their
-- position in a list that shortens from the middle.
export type Mark = {
	id: string,
	spot: Vector3,
	label: string,
}

export type Handle = {
	-- Every mark that should be lit right now. An empty list is "nothing to do", which
	-- is both the gap between tasks and the whole of the rest of a life.
	--
	-- The whole set every time, never one at a time, because that is the shape the
	-- server sends and anything else would need this to guess which of two marks a
	-- single update was about.
	Set: (marks: { Mark }) -> (),
	Destroy: () -> (),
}

type Drawn = {
	marker: ChoiceMarkers.ChoiceMarker,
	spot: Vector3,
	label: string,
}

function TaskMark.new(): Handle
	-- Parented to the workspace on the client, so it never reaches the server or
	-- another player. Same mechanism as the guide and the hiring posts.
	local folder = Instance.new("Folder")
	folder.Name = "AgesTaskMark"
	folder.Parent = workspace

	-- Keyed by task id rather than held in a list, and that is the whole reason this
	-- file changed. Two marks are lit at once for most of a shift, and they change
	-- independently -- one advances to its second mark while the other is untouched, or
	-- one finishes while the other is halfway through its clock. Anything positional
	-- would rebuild the wrong disc, and a disc rebuilt is a disc that restarts its
	-- pulse: the player would see the mark they were already walking to blink, for no
	-- reason connected to anything they did.
	local drawn: { [string]: Drawn } = {}

	local function destroy(id: string)
		local existing = drawn[id]
		if existing ~= nil then
			existing.marker.destroy()
			drawn[id] = nil
		end
	end

	local handle = {}

	function handle.Set(marks: { Mark })
		-- Anything no longer asked for goes first, so a shop floor never briefly holds
		-- more discs than the shift has tasks.
		local wanted: { [string]: true } = {}
		for _, mark in marks do
			wanted[mark.id] = true
		end
		for id in drawn do
			if not wanted[id] then
				destroy(id)
			end
		end

		for _, mark in marks do
			-- Left standing when nothing about it changed. The server pushes on its tick,
			-- four times a second, and a pad torn down and rebuilt at that rate would be a
			-- pad that never finishes one breath of its pulse -- it would read as a
			-- flickering fault rather than as something waiting for you.
			local existing = drawn[mark.id]
			if existing ~= nil and existing.spot == mark.spot and existing.label == mark.label then
				continue
			end

			destroy(mark.id)
			-- Never locked. A task mark is not an offer with terms attached: the shift you
			-- are already on is the only qualification it has, and by the time this is
			-- drawn you have it.
			drawn[mark.id] = {
				marker = ChoiceMarkers.Build(folder, mark.spot, Config.Work.Tasks.ReachStuds, {
					label = mark.label,
					locked = false,
				}),
				spot = mark.spot,
				label = mark.label,
			}
		end
	end

	function handle.Destroy()
		for id in drawn do
			destroy(id)
		end
		folder:Destroy()
	end

	return handle
end

return TaskMark
