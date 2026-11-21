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

-- Hiding Blizzard's copy. UIErrorsFrame draws SYSMSG with a plain
-- CheckAddMessage(message, r, g, b, 1.0) (Blizzard_UIErrorsFrame/Mainline/
-- UIErrorsFrame.lua). With the option on, we take that one event over: UIErrorsFrame
-- stops listening to SYSMSG, and we pass every message on to it unchanged, except a
-- discovery our banner is about to show. Anything unexpected on our side (a secret
-- value, an error, the banner never showing) falls back to passing the message on.
local FALLBACK_DELAY = 4 -- longer than the banner queue (about 2 s) and the stash (3 s)
local takenOver = false

local function CanTakeOver(errors)
	return errors
		and type(errors.IsEventRegistered) == "function"
		and type(errors.RegisterEvent) == "function"
		and type(errors.UnregisterEvent) == "function"
		and type(errors.CheckAddMessage) == "function"
end

local function PassOn(message, r, g, b)
	local errors = UIErrorsFrame
	if errors and type(errors.CheckAddMessage) == "function" then
		errors:CheckAddMessage(message, r, g, b, 1.0)
	end
end

-- Call whenever an option changes. Takes SYSMSG over, or hands it back.
function Discovery.UpdateTakeover()
	local errors = UIErrorsFrame
	if not CanTakeOver(errors) then
		return
	end
	local profile = ns.db and ns.db.profile
	local want = (profile and profile.enabled and profile.showDiscovery and profile.hideBlizzardDiscovery) and true
		or false
	if want == takenOver then
		return
	end
	if want then
		if not errors:IsEventRegistered("SYSMSG") then
			return -- something else already changed it; leave it alone
		end
		errors:UnregisterEvent("SYSMSG")
	else
		errors:RegisterEvent("SYSMSG")
	end
	takenOver = want
end

function Discovery.IsTakenOver()
	return takenOver
end

-- Returns true if the message is a discovery handed to the banner. With `original`
-- (message, r, g, b), the caller swallowed Blizzard's copy, so it is passed on late
-- if the banner never shows it.
local function HandleMessage(event, message, original)
	if ns.Compat.IsSecret(message) then
		return false
	end
	local name, xp = Discovery.Parse(message)
	if ns.debug then
		ns.Print("%s: %s -> %s", event, tostring(message), name and "discovery" or "ignored")
	end
	local profile = ns.db and ns.db.profile
	if not (name and profile and profile.enabled and profile.showDiscovery) then
		return false
	end
	if not original then
		ns.Banner.AddDiscovery(name, Discovery.DetailText(xp))
		return true
	end
	local shown = false
	ns.Banner.AddDiscovery(name, Discovery.DetailText(xp), function()
		shown = true
	end)
	C_Timer.After(FALLBACK_DELAY, function()
		if not shown then
			PassOn(original[1], original[2], original[3], original[4])
		end
	end)
	return true
end

local function OnInfoMessage(event, _, message) -- (messageType, message)
	HandleMessage(event, message)
end

local function OnSystemMessage(event, message, r, g, b) -- (message, r, g, b)
	if not takenOver then
		HandleMessage(event, message)
		return
	end
	local ok, handled = pcall(HandleMessage, event, message, { message, r, g, b })
	if not (ok and handled) then
		PassOn(message, r, g, b)
	end
	if not ok then
		geterrorhandler()(handled)
	end
end

-- For tests and `/zonebanner test discovery`: feeds a message in as if it were SYSMSG.
function Discovery.Simulate(message, r, g, b)
	OnSystemMessage("SYSMSG", message, r, g, b)
end

function Discovery.Init()
	local fallback = Discovery.FALLBACK_FORMATS
	Discovery.SetFormats(ERR_ZONE_EXPLORED_XP, ERR_ZONE_EXPLORED, fallback[1], fallback[2])
	ns.On("UI_INFO_MESSAGE", OnInfoMessage)
	ns.On("SYSMSG", OnSystemMessage)
	Discovery.UpdateTakeover()
end
