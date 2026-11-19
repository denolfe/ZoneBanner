local _, ns = ...
local L = ns.L

-- Folds Blizzard's "Discovered Goldshire: 120 experience gained" info message into
-- the banner as a small detail line.
--
-- The message arrives as UI_INFO_MESSAGE (messageType, message) and is drawn by
-- UIErrorsFrame (Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua, forever branch).
-- Detection is by message text, built from the localized ERR_ZONE_EXPLORED /
-- ERR_ZONE_EXPLORED_XP format strings, so it works in every locale and doesn't
-- depend on the numeric message-type constants (unverified on Forever).
--
-- The text is not built anywhere in Blizzard's Lua (checked the forever branch):
-- it comes from the client. In game on Forever it shows green above the banner,
-- which matches UIErrorsFrame's SYSMSG path (message, r, g, b), so we parse both
-- SYSMSG and UI_INFO_MESSAGE. `/zonebanner debug` prints what actually arrives.

local Discovery = {}
ns.Discovery = Discovery

-- Parsing (pure; unit-tested) ------------------------------------------------------

-- Turns a format string like "Discovered %s: %d experience gained" into an
-- anchored Lua pattern with captures. Handles positional forms (%1$s) too.
function Discovery.BuildPattern(format)
	if type(format) ~= "string" or format == "" then
		return nil
	end
	local order = {}
	local pattern = format:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
	-- After escaping, "%s" is still "%s" and "%1$s" has become "%1%$s".
	pattern = pattern:gsub("%%(%d?)%%?%$?([sd])", function(position, kind)
		order[#order + 1] = { tonumber(position) or (#order + 1), kind }
		return kind == "d" and "([%d,%.]+)" or "(.+)"
	end)
	return "^" .. pattern .. "$", order
end

local patterns = {}

-- English fallbacks, used in addition to the client's strings in case a global is
-- missing or worded differently on Forever. In other locales they simply never match.
Discovery.FALLBACK_FORMATS = {
	"Discovered %s: %d experience gained",
	"Discovered: %s",
}

-- Accepts any number of format strings (nils skipped, duplicates ignored).
function Discovery.SetFormats(...)
	wipe(patterns)
	local seen = {}
	for i = 1, select("#", ...) do
		local format = select(i, ...)
		local pattern, order = Discovery.BuildPattern(format)
		if pattern and not seen[pattern] then
			seen[pattern] = true
			patterns[#patterns + 1] = { pattern = pattern, order = order }
		end
	end
end

-- Removes color codes and surrounding whitespace before matching.
local function Clean(message)
	message = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (message:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns areaName, xp (number or nil) if the message is a discovery, else nil.
function Discovery.Parse(message)
	if type(message) ~= "string" then
		return nil
	end
	message = Clean(message)
	for i = 1, #patterns do
		local entry = patterns[i]
		local captures = { message:match(entry.pattern) }
		if captures[1] then
			local name, xp
			for j, slot in ipairs(entry.order) do
				local value = captures[j]
				if slot[2] == "s" and slot[1] == 1 then
					name = value
				elseif slot[2] == "d" then
					xp = tonumber((value:gsub("[,%.]", "")))
				end
			end
			name = name or captures[1]
			return name, xp
		end
	end
	return nil
end

-- Text for the banner's detail line.
function Discovery.DetailText(xp)
	if xp and xp > 0 then
		return (L["Discovered · +%d XP"]):format(xp)
	end
	return L["Discovered"]
end

-- Live wiring ------------------------------------------------------------------------

-- UIErrorsFrame (a C MessageFrame) can't remove a single line, so hiding Blizzard's
-- copy means Clear(). To avoid wiping a real error, we only clear when the
-- discovery was the only message the frame received recently.
local QUIET_WINDOW = 3 -- UIErrorsFrame displayDuration 2 + fadeDuration 0.5, plus margin
local lastOtherMessage = -math.huge
local GetTime = GetTime

local function MaybeHideBlizzardLine()
	local profile = ns.db and ns.db.profile
	if not (profile and profile.hideBlizzardDiscovery) then
		return
	end
	local errors = UIErrorsFrame
	if not (errors and errors.Clear) then
		return
	end
	-- Defer a frame: UIErrorsFrame may handle this same event after us.
	C_Timer.After(0, function()
		if GetTime() - lastOtherMessage >= QUIET_WINDOW then
			errors:Clear()
		end
	end)
end

local function HandleMessage(event, message)
	if ns.Compat.IsSecret(message) then
		return
	end
	if ns.debug then
		ns.Print("%s: %s -> %s", event, tostring(message), Discovery.Parse(message) and "discovery" or "ignored")
	end
	local profile = ns.db and ns.db.profile
	local name, xp = Discovery.Parse(message)
	if not name then
		lastOtherMessage = GetTime()
		return
	end
	if not (profile and profile.enabled and profile.showDiscovery) then
		return
	end
	-- MaybeHideBlizzardLine runs only once our copy is actually on screen.
	ns.Banner.AddDiscovery(name, Discovery.DetailText(xp), MaybeHideBlizzardLine)
end

local function OnInfoMessage(event, _, message) -- (messageType, message)
	HandleMessage(event, message)
end

local function OnSystemMessage(event, message) -- (message, r, g, b)
	HandleMessage(event, message)
end

local function OnErrorMessage(event, _, message)
	if ns.debug and not ns.Compat.IsSecret(message) then
		ns.Print("%s: %s -> ignored", event, tostring(message))
	end
	lastOtherMessage = GetTime()
end

function Discovery.Init()
	local fallback = Discovery.FALLBACK_FORMATS
	Discovery.SetFormats(ERR_ZONE_EXPLORED_XP, ERR_ZONE_EXPLORED, fallback[1], fallback[2])
	ns.On("UI_INFO_MESSAGE", OnInfoMessage)
	ns.On("SYSMSG", OnSystemMessage)
	ns.On("UI_ERROR_MESSAGE", OnErrorMessage)
end
