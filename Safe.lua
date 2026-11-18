local _, ns = ...

local InCombatLockdown = InCombatLockdown
local geterrorhandler = geterrorhandler
local select, unpack, xpcall = select, unpack, xpcall

-- Is an addon restriction active? kind: "Combat" (default), "Encounter",
-- "ChallengeMode", "PvPMatch", "Map", "Chat" (Enum.AddOnRestrictionType).
function ns.IsRestricted(kind)
	kind = kind or "Combat"
	if kind == "Combat" and InCombatLockdown() then
		return true
	end
	local restricted = C_RestrictedActions
	local types = Enum and Enum.AddOnRestrictionType
	if restricted and restricted.IsAddOnRestrictionActive and types and types[kind] ~= nil then
		return restricted.IsAddOnRestrictionActive(types[kind]) and true or false
	end
	return false
end

-- Call fn(...) and route any error to the error handler (BugSack) instead of
-- unwinding the caller. One broken handler must never break the others.
-- WoW's xpcall forwards extra arguments to fn.
function ns.SafeCall(fn, ...)
	return xpcall(fn, geterrorhandler(), ...)
end

-- Combat-safe deferral ------------------------------------------------------
-- Anything touching secure frames, attributes, bindings, SmartNavigation marks
-- or GamepadMode.FrameControlsManager goes through RunSafe.

local queue = {}
local keyed = {}

local function Enqueue(job)
	queue[#queue + 1] = job
	return job
end

-- Runs now if allowed, otherwise once combat ends.
function ns.RunSafe(fn, ...)
	if type(fn) ~= "function" then
		error("RunSafe: function expected", 2)
	end
	if not ns.IsRestricted("Combat") then
		ns.SafeCall(fn, ...)
		return true
	end
	Enqueue({ n = select("#", ...), fn = fn, ... })
	return false
end

-- Like RunSafe, but only the most recent request per key runs after combat
-- (e.g. "relayout" requested 50 times during a fight runs once).
function ns.RunSafeKeyed(key, fn, ...)
	if type(fn) ~= "function" then
		error("RunSafeKeyed: function expected", 2)
	end
	if not ns.IsRestricted("Combat") then
		ns.SafeCall(fn, ...)
		return true
	end
	local previous = keyed[key]
	if previous then
		previous.cancelled = true
	end
	keyed[key] = Enqueue({ n = select("#", ...), fn = fn, ... })
	return false
end

local queueFrame = CreateFrame("Frame")
queueFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
queueFrame:SetScript("OnEvent", function()
	local pending = queue
	queue = {}
	wipe(keyed)
	for i = 1, #pending do
		local job = pending[i]
		if not job.cancelled then
			if ns.IsRestricted("Combat") then
				Enqueue(job) -- combat started again mid-flush; wait for the next exit
			else
				ns.SafeCall(job.fn, unpack(job, 1, job.n))
			end
		end
	end
end)
