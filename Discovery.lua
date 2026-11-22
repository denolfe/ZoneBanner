local _, ns = ...
local L = ns.L

-- Folds Blizzard's "Discovered: Goldshire" message into the banner as a small
-- "Discovered" line under the area name (with the XP when the message has it).
--
-- What Forever sends (seen in game with /zonebanner debug):
--   UI_INFO_MESSAGE  "Discovered: Tranquil Gardens Cemetery"   (on screen, UIErrorsFrame)
--   CHAT_MSG_SYSTEM  "Discovered Tranquil Gardens Cemetery: 230 experience gained"
-- Only the on-screen copy is used; the chat copy is left alone.
-- Detection is by message text, built from the localized ERR_ZONE_EXPLORED /
-- ERR_ZONE_EXPLORED_XP format strings (plus English fallbacks), so it doesn't depend
-- on numeric message-type constants. SYSMSG is watched too, in case it moves there.

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

-- Hiding Blizzard's copy. On Forever the on-screen line arrives as UI_INFO_MESSAGE
-- (seen in game with /zonebanner debug); SYSMSG is covered too in case another
-- client or locale routes it there. With the option on, UIErrorsFrame stops
-- listening to those two events, and we hand every message back to UIErrorsFrame's
-- own OnEvent script, so colour, sound and flashing stay exactly Blizzard's. The
-- only exception is a discovery our banner shows. Anything unexpected on our side (a
-- secret value, an error, the banner never showing) falls back to passing it on.
local TAKEN_EVENTS = { "UI_INFO_MESSAGE", "SYSMSG" }
local FALLBACK_DELAY = 4 -- longer than the banner queue (about 2 s) and the stash (3 s)
local taken = {} -- event -> true while UIErrorsFrame doesn't get it directly

local function BlizzardHandler(errors)
	local handler = errors and type(errors.GetScript) == "function" and errors:GetScript("OnEvent")
	return type(handler) == "function" and handler or nil
end

local function CanTakeOver(errors)
	return BlizzardHandler(errors)
		and type(errors.IsEventRegistered) == "function"
		and type(errors.RegisterEvent) == "function"
		and type(errors.UnregisterEvent) == "function"
end

-- Runs Blizzard's own handler, as if UIErrorsFrame had received the event itself.
local function PassOn(event, ...)
	local errors = UIErrorsFrame
	local handler = BlizzardHandler(errors)
	if handler then
		handler(errors, event, ...)
	end
end

-- Call whenever an option changes. Takes the events over, or hands them back.
function Discovery.UpdateTakeover()
	local errors = UIErrorsFrame
	if not CanTakeOver(errors) then
		return
	end
	local profile = ns.db and ns.db.profile
	local want = profile and profile.enabled and profile.showDiscovery and profile.hideBlizzardDiscovery
	for _, event in ipairs(TAKEN_EVENTS) do
		if want and not taken[event] then
			-- Only if Blizzard still has it; if something else changed it, leave it alone.
			if errors:IsEventRegistered(event) then
				errors:UnregisterEvent(event)
				taken[event] = true
			end
		elseif not want and taken[event] then
			errors:RegisterEvent(event)
			taken[event] = nil
		end
	end
end

function Discovery.IsTakenOver(event)
	return taken[event] or false
end

-- Returns true if the message is a discovery handed to the banner. With `passOn`,
-- the caller swallowed Blizzard's copy; it is called late if the banner never shows it.
local function HandleMessage(event, message, passOn)
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
	if not passOn then
		ns.Banner.AddDiscovery(name, Discovery.DetailText(xp))
		return true
	end
	local shown = false
	ns.Banner.AddDiscovery(name, Discovery.DetailText(xp), function()
		shown = true
	end)
	C_Timer.After(FALLBACK_DELAY, function()
		if not shown then
			passOn()
		end
	end)
	return true
end

-- UI_INFO_MESSAGE is (messageType, message); SYSMSG is (message, r, g, b).
local function OnErrorsFrameEvent(event, ...)
	local message
	if event == "UI_INFO_MESSAGE" then
		message = select(2, ...)
	else
		message = ...
	end
	if not taken[event] then
		HandleMessage(event, message)
		return
	end
	local args = { n = select("#", ...), ... }
	local function passOn()
		PassOn(event, unpack(args, 1, args.n))
	end
	local ok, handled = pcall(HandleMessage, event, message, passOn)
	if not (ok and handled) then
		passOn()
	end
	if not ok then
		geterrorhandler()(handled)
	end
end

-- For tests and `/zonebanner test discovery`: feeds a message in the way Forever
-- sends it (UI_INFO_MESSAGE).
function Discovery.Simulate(message)
	OnErrorsFrameEvent("UI_INFO_MESSAGE", 0, message)
end

function Discovery.Init()
	local fallback = Discovery.FALLBACK_FORMATS
	Discovery.SetFormats(ERR_ZONE_EXPLORED_XP, ERR_ZONE_EXPLORED, fallback[1], fallback[2])
	for _, event in ipairs(TAKEN_EVENTS) do
		ns.On(event, OnErrorsFrameEvent)
	end
	Discovery.UpdateTakeover()
end
