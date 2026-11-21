-- Drives the real Banner.lua + AreaFilter.lua through Blizzard's FadingFrame_Show hook,
-- with a permissive stub frame (any method exists; Show/Hide/IsShown/SetText work).
describe("Banner with discoveries and the repeat filter", function()
	local ns, now, timers, hook, zone, subzone

	local function StubObject()
		local o = { shown = false }
		return setmetatable(o, {
			__index = function(_, key)
				if key == "Show" then
					return function(self) self.shown = true end
				elseif key == "Hide" then
					return function(self) self.shown = false end
				elseif key == "IsShown" then
					return function(self) return self.shown end
				elseif key == "SetText" then
					return function(self, text) self.text = text end
				elseif key == "CreateTexture" or key == "CreateFontString" then
					return function() return StubObject() end
				end
				return function() end
			end,
		})
	end

	local function RunTimers()
		local list = timers
		timers = {}
		for _, fn in ipairs(list) do
			fn()
		end
	end

	-- Blizzard shows zone text, our hook fires, the 0.1 s evaluate runs.
	local function Enter(newZone, newSub)
		zone, subzone = newZone, newSub or ""
		hook(_G.SubZoneTextFrame)
		RunTimers()
	end

	local function OnScreen()
		local f = _G.ZoneBannerFrameStub
		return f and f.shown and f.Title.text, f and f.Detail.text
	end

	before_each(function()
		now, timers, zone, subzone = 1000, {}, "", ""
		_G.ZoneBannerFrameStub = nil
		_G.GetTime = function() return now end
		_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
		_G.UIParent = StubObject()
		_G.CreateFrame = function()
			local f = StubObject()
			_G.ZoneBannerFrameStub = f
			return f
		end
		_G.ZoneTextFrame, _G.SubZoneTextFrame = StubObject(), StubObject()
		_G.FadingFrame_Show = function() end
		_G.hooksecurefunc = function(_, fn) hook = fn end

		ns = {
			db = { profile = { enabled = true, citiesOnly = false, replaceBlizzard = true, holdTime = 3 } },
			Compat = {
				HasAtlas = function() return false end,
				IsInCity = function() return false end,
				GetZoneNames = function() return zone, subzone end,
			},
			Gamepad = { Ignore = function() end },
			Print = function() end,
		}
		LoadAddonFile("AreaFilter.lua", ns)
		LoadAddonFile("Banner.lua", ns)
		ns.Banner.Init()
	end)

	it("skips the zone after leaving one of its subzones", function()
		Enter("Wetlands")
		assert.are.equal("Wetlands", (OnScreen()))
		_G.ZoneBannerFrameStub:Hide()
		Enter("Wetlands", "Menethil Bay")
		assert.are.equal("Menethil Bay", (OnScreen()))
		_G.ZoneBannerFrameStub:Hide()
		Enter("Wetlands")
		assert.is_false((OnScreen()) and true or false)
	end)

	it("shows a skipped banner when its discovery arrived first", function()
		Enter("Wetlands", "Menethil Bay")
		_G.ZoneBannerFrameStub:Hide()
		now = now + 5
		ns.Banner.AddDiscovery("Menethil Bay", "Discovered") -- before Blizzard's zone text
		Enter("Wetlands", "Menethil Bay") -- would be "shown recently"
		local title, detail = OnScreen()
		assert.are.equal("Menethil Bay", title)
		assert.are.equal("Discovered", detail)
	end)

	it("shows the banner when a discovery arrives after the skip", function()
		Enter("Wetlands", "Menethil Bay")
		_G.ZoneBannerFrameStub:Hide()
		now = now + 5
		Enter("Wetlands", "Menethil Bay")
		assert.is_false((OnScreen()) and true or false)
		ns.Banner.AddDiscovery("Menethil Bay", "Discovered")
		local title, detail = OnScreen()
		assert.are.equal("Menethil Bay", title)
		assert.are.equal("Discovered", detail)
	end)

	it("doesn't force a banner for a discovery somewhere else", function()
		zone, subzone = "Wetlands", ""
		ns.Banner.AddDiscovery("Thelgen Rock", "Discovered")
		assert.is_false((OnScreen()) and true or false)
	end)
end)
