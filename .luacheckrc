std = "lua51"
max_line_length = false
exclude_files = { "Libs/", ".release/" }

-- Globals this addon is allowed to WRITE. Keep this list tiny.
globals = {
	"ZoneBannerDB", -- SavedVariables
	"SLASH_ZONEBANNER1",
	"SlashCmdList",
	"ZoneBanner_OnAddonCompartmentClick",
	"UISpecialFrames", -- tinsert of our frame name
}

-- WoW globals this addon READS. This list doubles as documentation of every
-- API the addon depends on; add to it deliberately.
read_globals = {
	-- Lua extensions in WoW
	"strtrim", "tContains", "tinsert", "wipe", "hooksecurefunc",
	-- Core API
	"CreateFrame", "GetBuildInfo", "InCombatLockdown", "geterrorhandler",
	"GetUnitName", "UnitName", "GetAddOnMetadata", "GetContainerNumSlots",
	"issecretvalue", "canaccessvalue",
	"GetZoneText", "GetSubZoneText", "IsResting",
	-- Namespaces
	"C_AddOns", "C_Container", "C_Texture", "C_Timer", "C_EventUtils", "C_InputInterfaceStyle", "C_RestrictedActions",
	"Enum",
	-- Project ids
	"WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CAMELOT",
	-- FrameXML
	"UIParent", "Settings", "GamepadMode",
	"FadingFrame_Show", "ZoneTextFrame", "SubZoneTextFrame",
	"SmartNavigation_MarkFrameIgnored", "SmartNavigation_MarkFrameFocusable",
	-- Optional dependencies
	"ConsolePort",
}

files["tests/"] = {
	std = "+busted",
	globals = { "LoadAddonFile", "wipe", "geterrorhandler" },
}
