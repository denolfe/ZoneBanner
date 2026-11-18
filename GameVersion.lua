local _, ns = ...

-- Computed once. Use these for CONTENT differences (zones, classes, systems that
-- exist). For API differences use feature detection in Compat.lua instead.

local toc = select(4, GetBuildInfo()) or 0

-- Big addons disagree on how to detect Forever (project-id constant vs interface
-- range), so accept either. Early builds may have reported the Mainline project id.
local isForever = (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)
	or (toc >= 16000 and toc < 17000)

local isRetail = (not isForever) and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local flags = {
	toc = toc,
	isForever = isForever,
	isRetail = isRetail,
	-- "Modern" = Mainline code family: Edit Mode, Settings API, Midnight restrictions.
	isModern = isForever or isRetail,
	isClassicFamily = not (isForever or isRetail),
}

-- Read-only proxy that errors on unknown keys, so a typo like ns.Game.isForver
-- fails loudly instead of silently evaluating to nil (pattern from Bartender4).
ns.Game = setmetatable({}, {
	__index = function(_, key)
		local value = flags[key]
		if value == nil then
			error(("ns.Game: unknown flag %q"):format(tostring(key)), 2)
		end
		return value
	end,
	__newindex = function()
		error("ns.Game is read-only", 2)
	end,
})
