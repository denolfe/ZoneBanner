-- Drives the real Banner.lua + AreaFilter.lua through Blizzard's FadingFrame_Show hook,
-- with a permissive stub frame (any method exists; Show/Hide/IsShown/SetText work).
describe("Banner with discoveries and the repeat filter", function()
	local ns, now, timers, hook, zone, subzone

	local function StubObject()
		local o = { shown = false, scripts = {} }
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
				elseif key == "SetAlpha" then
					return function(self, a) self.alpha = a end
				elseif key == "SetHeight" then
					return function(self, h) self.height = h end
				elseif key == "SetScript" then
					return function(self, name, fn) self.scripts[name] = fn end
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

	-- Advances the banner's OnUpdate by `seconds` in small steps.
	local function Tick(seconds)
		local f = _G.ZoneBannerFrameStub
		for _ = 1, math.floor(seconds / 0.05 + 0.5) do
			now = now + 0.05
			if f.shown then
				f.scripts.OnUpdate(f, 0.05)
			end
		end
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
			SafeCall = function(fn, ...) return fn(...) end,
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

	it("keeps the first copy's callback when a second copy updates a waiting discovery", function()
		zone, subzone = "Elsewhere", ""
		local ran = false
		ns.Banner.AddDiscovery("Menethil Bay", "Discovered", function() ran = true end)
		ns.Banner.AddDiscovery("Menethil Bay", "Discovered!")
		Enter("Wetlands", "Menethil Bay")
		local title, detail = OnScreen()
		assert.are.equal("Menethil Bay", title)
		assert.are.equal("Discovered!", detail)
		assert.is_true(ran)
	end)

	it("fades a late discovery line in instead of popping it", function()
		Enter("Duskwood", "Tranquil Gardens Cemetery")
		Tick(1)
		ns.Banner.AddDiscovery("Tranquil Gardens Cemetery", "Discovered")
		local f = _G.ZoneBannerFrameStub
		assert.are.equal(0, f.Detail.alpha)
		Tick(0.2)
		assert.is_true(f.Detail.alpha > 0 and f.Detail.alpha < 1)
		Tick(0.5)
		assert.are.equal(1, f.Detail.alpha)
	end)

	it("eases the banner to its new height", function()
		Enter("Duskwood", "Tranquil Gardens Cemetery")
		Tick(1)
		local f = _G.ZoneBannerFrameStub
		local before = f.height
		ns.Banner.AddDiscovery("Tranquil Gardens Cemetery", "Discovered")
		assert.are.equal(before, f.height)
		Tick(1)
		assert.is_true(f.height > before)
	end)

	it("keeps the banner up long enough to read a late line", function()
		Enter("Duskwood", "Tranquil Gardens Cemetery")
		Tick(0.5 + 3 + 0.5) -- fade in, hold, halfway through the fade-out
		ns.Banner.AddDiscovery("Tranquil Gardens Cemetery", "Discovered")
		Tick(2)
		assert.are.equal("Tranquil Gardens Cemetery", (OnScreen()))
		assert.are.equal(1, _G.ZoneBannerFrameStub.alpha)
		Tick(3)
		assert.is_false((OnScreen()) and true or false)
	end)

	it("doesn't fade the same line in twice", function()
		Enter("Duskwood", "Tranquil Gardens Cemetery")
		Tick(1)
		ns.Banner.AddDiscovery("Tranquil Gardens Cemetery", "Discovered")
		Tick(1)
		ns.Banner.AddDiscovery("Tranquil Gardens Cemetery", "Discovered")
		assert.are.equal(1, _G.ZoneBannerFrameStub.Detail.alpha)
	end)

	it("doesn't force a banner for a discovery somewhere else", function()
		zone, subzone = "Wetlands", ""
		ns.Banner.AddDiscovery("Thelgen Rock", "Discovered")
		assert.is_false((OnScreen()) and true or false)
	end)
end)
