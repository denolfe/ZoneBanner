local _, ns = ...

-- SavedVariables: defaults + ordered migrations.
-- This file touches no WoW API at load time so busted can load it directly.

local DB = {}
ns.DB = DB

local SV_NAME = "ZoneBannerDB" -- must match ## SavedVariables in the .toc

DB.CURRENT_VERSION = 3

-- Never put `version` here: its absence is how a fresh install is detected.
local defaults = {
	profile = {
		enabled = true,
		-- Only show the banner in rested areas (cities, towns with an inn).
		citiesOnly = false,
		-- Hide Blizzard's own zone/subzone text when the banner shows.
		replaceBlizzard = true,
		-- Fold Blizzard's "Discovered: X" message into the banner.
		showDiscovery = true,
		-- Stop Blizzard's on-screen copy (UIErrorsFrame) when the banner shows ours.
		hideBlizzardDiscovery = true,
		-- Seconds the banner stays fully visible.
		holdTime = 3,
	},
}

-- migrations[n] upgrades a version n-1 database to version n.
-- Write them defensively: any field may be missing or the wrong type.
local migrations = {
	[1] = function()
		-- version 1 was the first release; nothing to upgrade from.
	end,
	[2] = function(db)
		-- v1 defaulted citiesOnly to true; v2 shows the banner everywhere by default.
		-- No one had a UI way to pick true deliberately before the default
		-- changed, so reset it.
		local profile = db.profile
		if type(profile) == "table" and profile.citiesOnly == true then
			profile.citiesOnly = false
		end
	end,
	[3] = function(db)
		-- v3 hides Blizzard's on-screen discovery line by default. Until now it was
		-- off by default and the old version of it was unreliable, so turn it on.
		-- It can still be turned off in the options.
		local profile = db.profile
		if type(profile) == "table" then
			profile.hideBlizzardDiscovery = true
		end
	end,
}

-- Deep, type-aware merge: fills missing keys and replaces values whose type
-- doesn't match the default (self-heals corrupted/hand-edited files).
-- Never overwrites a valid saved value. Keys not in defaults are kept.
local function ApplyDefaults(src, dst)
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then
				dst[key] = {}
			end
			ApplyDefaults(value, dst[key])
		elseif dst[key] == nil or type(dst[key]) ~= type(value) then
			dst[key] = value
		end
	end
end
DB.ApplyDefaults = ApplyDefaults

-- Pure function: takes whatever was on disk, returns a usable db table.
function DB.Load(raw)
	local db = type(raw) == "table" and raw or {}

	if next(db) == nil then
		db.version = DB.CURRENT_VERSION -- fresh install: no migrations
	else
		local version = tonumber(db.version) or 0
		if version > DB.CURRENT_VERSION then
			-- Downgrade: data from a newer release. Don't migrate, don't strip.
			DB.fromFuture = true
		else
			for i = version + 1, DB.CURRENT_VERSION do
				migrations[i](db)
				db.version = i
			end
		end
	end

	ApplyDefaults(defaults, db)

	-- Clamp values a hand-edited file could make absurd.
	local profile = db.profile
	if profile.holdTime < 1 or profile.holdTime > 10 then
		profile.holdTime = defaults.profile.holdTime
	end
	return db
end

function DB.Init()
	local db = DB.Load(_G[SV_NAME])
	_G[SV_NAME] = db
	ns.db = db
	if DB.fromFuture and ns.Print then
		ns.Print("Saved settings come from a newer version of this addon; some settings may be ignored.")
	end
end
