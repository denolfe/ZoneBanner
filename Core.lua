local addonName, ns = ...

-- Event dispatch ----------------------------------------------------------------
-- One frame, a table of handlers per event, every handler error-isolated.

local eventFrame = CreateFrame("Frame")
local handlers = {}

local function IsValidEvent(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		return C_EventUtils.IsEventValid(event)
	end
	return true
end

-- Returns false (instead of erroring) if the event doesn't exist on this client,
-- so a removed/renamed event degrades a feature rather than breaking load.
function ns.On(event, fn)
	if type(fn) ~= "function" then
		error("ns.On: function expected", 2)
	end
	if not IsValidEvent(event) then
		return false
	end
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		eventFrame:RegisterEvent(event)
	end
	list[#list + 1] = fn
	return true
end

function ns.Off(event, fn)
	local list = handlers[event]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == fn then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	-- Iterate a snapshot length; handlers that call ns.Off on themselves are fine.
	for i = 1, #list do
		local fn = list[i]
		if fn then
			ns.SafeCall(fn, event, ...)
		end
	end
end)

-- Output ------------------------------------------------------------------------

function ns.Print(message, ...)
	if select("#", ...) > 0 then
		message = message:format(...)
	end
	print(("|cff33ff99%s|r: %s"):format(addonName, message))
end

-- Startup -----------------------------------------------------------------------

local function OnAddonLoaded(_, loadedName)
	if loadedName ~= addonName then
		return
	end
	ns.Off("ADDON_LOADED", OnAddonLoaded)
	ns.DB.Init()
end
ns.On("ADDON_LOADED", OnAddonLoaded)

ns.On("PLAYER_LOGIN", function()
	ns.Gamepad.Init()
	ns.Banner.Init()
	ns.Discovery.Init()
	ns.Options.Register()
end)

-- Entry points --------------------------------------------------------------------

local function HandleSlash(input)
	local command = strtrim(input or ""):lower()
	if command == "test" then
		ns.Banner.Test()
	elseif command == "test discovery" then
		-- Runs the whole path: a fake client message through the parser, then the banner.
		local area = ns.Banner.Test()
		ns.Discovery.Simulate((ERR_ZONE_EXPLORED or "Discovered: %s"):format(area), 0, 1, 0)
	elseif command == "debug" then
		ns.debug = not ns.debug -- session only, not saved
		ns.Print(ns.debug and "Debug on: zone and discovery messages are printed to chat." or "Debug off.")
	else
		ns.Options.Open()
	end
end

-- Slash commands and the compartment handler are the accepted global writes.
SLASH_ZONEBANNER1 = "/zonebanner" -- allow-global
SlashCmdList.ZONEBANNER = HandleSlash

function ZoneBanner_OnAddonCompartmentClick() -- allow-global
	ns.Options.Open()
end
