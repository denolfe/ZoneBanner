local _, ns = ...

-- Decides whether a zone change is worth a banner. Pure (no WoW API); unit-tested.
--
-- Travelling often produces "Wetlands", "Menethil Bay / Wetlands", "Wetlands" within
-- seconds: the last one only means you left the subzone, not that you arrived
-- anywhere new. Border walking does the same with two subzones. Two rules:
--   1. A zone-only banner is skipped if you are still in the zone you were last in.
--   2. A banner that was shown less than REPEAT_WINDOW seconds ago is skipped.

local AreaFilter = {}
ns.AreaFilter = AreaFilter

AreaFilter.REPEAT_WINDOW = 30

local lastZone
local recent = {} -- key -> time shown
local recentCount = 0

local function Prune(now)
	for key, shownAt in pairs(recent) do
		if now - shownAt >= AreaFilter.REPEAT_WINDOW then
			recent[key] = nil
			recentCount = recentCount - 1
		end
	end
end

local function Key(title, subtitle)
	return title .. " / " .. (subtitle or "")
end

-- title, subtitle as the banner would show them (subtitle = zone, or nil when the
-- title is the zone itself). Returns true to show, or false plus a reason.
-- Call once per zone change: it also remembers which zone you are in.
function AreaFilter.Check(title, subtitle, now)
	local zone = subtitle or title
	local previousZone = lastZone
	lastZone = zone

	if subtitle == nil and zone == previousZone then
		return false, "same zone"
	end
	local shownAt = recent[Key(title, subtitle)]
	if shownAt and now - shownAt < AreaFilter.REPEAT_WINDOW then
		return false, "shown recently"
	end
	return true
end

-- Call when a banner actually appears on screen. (A queued banner that gets dropped
-- never counts, so walking back into that area still shows it.)
function AreaFilter.MarkShown(title, subtitle, now)
	local key = Key(title, subtitle)
	if not recent[key] then
		recentCount = recentCount + 1
	end
	recent[key] = now
	if recentCount > 32 then
		Prune(now)
	end
end

function AreaFilter.Reset()
	lastZone = nil
	wipe(recent)
	recentCount = 0
end
