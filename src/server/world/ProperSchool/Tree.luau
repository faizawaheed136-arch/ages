--!strict
-- The folder tree everything in the new school is parented into.
--
-- **Idempotent, and that is the entire point of the file.** This runs against a live Workspace
-- that may already be holding a half-built school -- from a previous run, a Rojo sync, or a
-- plugin insert -- and a second run has to *adopt* what is already there rather than lay a
-- second copy beside it. Duplicated roots are the single most expensive mistake in a build
-- pipeline like this one: every later lookup finds one of the two at random, half the building
-- ends up in the orphan, and nothing errors.
--
-- `FindFirstChild` before `Instance.new` is the whole of that guarantee.

local PLAN: { [string]: { string } } = {
	-- Split by storey rather than by trade, because the thing you most often want to hide,
	-- reload or measure in isolation is one floor.
	Architecture = { "Exterior", "Floor1", "Floor2", "Floor3" },
	Furniture = {},
	Lighting = {},
	Props = {},
}

local ROOT_NAME = "ProperSchool"

export type Tree = {
	Root: Folder,
	Architecture: Folder,
	Exterior: Folder,
	Floor1: Folder,
	Floor2: Folder,
	Floor3: Folder,
	Furniture: Folder,
	Lighting: Folder,
	Props: Folder,
}

local Tree = {}

-- One folder, created or adopted.
--
-- Errors rather than guesses when the name is taken by something that is not a Folder. The
-- alternatives are both worse: renaming somebody else's instance is destructive, and quietly
-- parenting the school into a Part produces a build that looks fine until it does not.
local function ensure(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("Folder") then
			return existing
		end
		error(
			`[AGES ProperSchool] {parent:GetFullName()}.{name} exists and is a {existing.ClassName}, not a Folder.`
				.. ` Rename or remove it -- this script will not overwrite an instance it did not create.`
		)
	end

	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = parent
	return made
end

-- Builds the tree under `parent` (Workspace by default) and hands back every folder by name.
--
-- Returned flat rather than nested: the storey names are unique across the whole plan, so a
-- flat table is both shorter to write against (`tree.Floor2`) and impossible to get wrong by
-- reaching into the wrong branch.
function Tree.Build(parent: Instance?): Tree
	local into = parent or workspace
	local root = ensure(ROOT_NAME, into)

	local built: { [string]: Folder } = { Root = root }
	for branch, leaves in PLAN do
		local folder = ensure(branch, root)
		built[branch] = folder
		for _, leaf in leaves do
			built[leaf] = ensure(leaf, folder)
		end
	end

	return built :: any
end

-- Removes the tree. Separate from Build so a rebuild is an explicit choice rather than a side
-- effect of running the builder again -- see the note at the top about adopting.
function Tree.Clear(parent: Instance?): ()
	local existing = (parent or workspace):FindFirstChild(ROOT_NAME)
	if existing ~= nil then
		existing:Destroy()
	end
end

return Tree
