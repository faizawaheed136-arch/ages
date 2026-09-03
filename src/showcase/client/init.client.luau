--!strict
-- The showcase client.
--
-- Each panel builds its own ScreenGui on Start and then waits to be told something. None of
-- them poll, and none of them exist before the remotes do -- every module WaitForChilds its way
-- to ReplicatedStorage.Showcase.Remotes, which the server creates.

-- LightingZone first: it captures the place's own Lighting values at startup, and it should do
-- that before anything else has a chance to touch them.
for _, name in { "LightingZone", "WardrobeUI", "BannerUI", "ScoreboardUI", "ArenaCamera", "VendingUI", "ChalkboardUI" } do
	local module = script:FindFirstChild(name)
	if module == nil then
		warn(`[Showcase] {name} is missing`)
		continue
	end
	local ok, err = pcall(function()
		require(module :: ModuleScript).Start()
	end)
	if not ok then
		warn(`[Showcase] {name} failed to start: {err}`)
	end
end
