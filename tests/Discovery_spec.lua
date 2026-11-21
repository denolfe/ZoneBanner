describe("Discovery.Parse", function()
	local Discovery

	before_each(function()
		local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
		LoadAddonFile("Discovery.lua", ns)
		Discovery = ns.Discovery
		Discovery.SetFormats("Discovered %s: %d experience gained", "Discovered: %s")
	end)

	it("parses the XP form", function()
		local name, xp = Discovery.Parse("Discovered Goldshire: 120 experience gained")
		assert.are.equal("Goldshire", name)
		assert.are.equal(120, xp)
	end)

	it("parses the no-XP form", function()
		local name, xp = Discovery.Parse("Discovered: Trade District")
		assert.are.equal("Trade District", name)
		assert.is_nil(xp)
	end)

	it("keeps colons and punctuation inside area names", function()
		local name, xp = Discovery.Parse("Discovered Valley of Heroes (East): 1,250 experience gained")
		assert.are.equal("Valley of Heroes (East)", name)
		assert.are.equal(1250, xp)
	end)

	it("ignores unrelated messages", function()
		assert.is_nil(Discovery.Parse("Not enough mana"))
		assert.is_nil(Discovery.Parse("You are too far away! Discovered Goldshire: 1 experience gained"))
		assert.is_nil(Discovery.Parse(nil))
	end)

	it("handles positional format strings", function()
		Discovery.SetFormats("%2$d EP für Entdeckung: %1$s", nil)
		local name, xp = Discovery.Parse("85 EP für Entdeckung: Goldhain")
		assert.are.equal("Goldhain", name)
		assert.are.equal(85, xp)
	end)

	it("turns off cleanly when the strings are missing", function()
		Discovery.SetFormats(nil, nil)
		assert.is_nil(Discovery.Parse("Discovered Goldshire: 120 experience gained"))
	end)

	it("strips color codes and whitespace", function()
		local name = Discovery.Parse("  |cff20ff20Discovered: Some Place|r ")
		assert.are.equal("Some Place", name)
	end)

	it("falls back to English formats when the client strings are missing", function()
		local fb = Discovery.FALLBACK_FORMATS
		Discovery.SetFormats(nil, nil, fb[1], fb[2])
		assert.are.equal("Some Place", (Discovery.Parse("Discovered: Some Place")))
		local name, xp = Discovery.Parse("Discovered Goldshire: 120 experience gained")
		assert.are.equal("Goldshire", name)
		assert.are.equal(120, xp)
	end)

	it("ignores duplicate formats", function()
		Discovery.SetFormats("Discovered: %s", "Discovered: %s")
		assert.are.equal("X", (Discovery.Parse("Discovered: X")))
	end)

	it("builds detail text", function()
		assert.are.equal("Discovered · +120 XP", Discovery.DetailText(120))
		assert.are.equal("Discovered", Discovery.DetailText(nil))
	end)
end)

describe("Discovery takeover of Blizzard's SYSMSG line", function()
	local Discovery, ns, errors, timers, attached

	local function RunTimers()
		local list = timers
		timers = {}
		for _, fn in ipairs(list) do
			fn()
		end
	end

	before_each(function()
		timers, attached = {}, {}
		errors = { registered = { SYSMSG = true }, lines = {} }
		function errors:IsEventRegistered(e) return self.registered[e] or false end
		function errors:RegisterEvent(e) self.registered[e] = true end
		function errors:UnregisterEvent(e) self.registered[e] = nil end
		function errors:CheckAddMessage(m) self.lines[#self.lines + 1] = m end
		_G.UIErrorsFrame = errors
		_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

		ns = {
			L = setmetatable({}, { __index = function(_, k) return k end }),
			Compat = { IsSecret = function() return false end },
			On = function() return true end,
			db = { profile = { enabled = true, showDiscovery = true, hideBlizzardDiscovery = true } },
			Banner = {
				show = true,
				AddDiscovery = function(name, _, onShown)
					attached[#attached + 1] = name
					if ns.Banner.show and onShown then
						onShown()
					end
				end,
			},
		}
		LoadAddonFile("Discovery.lua", ns)
		Discovery = ns.Discovery
		Discovery.Init()
		Discovery.SetFormats("Discovered: %s")
	end)

	it("takes SYSMSG from UIErrorsFrame when the option is on", function()
		assert.is_true(Discovery.IsTakenOver())
		assert.is_nil(errors.registered.SYSMSG)
	end)

	it("swallows a discovery the banner shows", function()
		Discovery.Simulate("Discovered: Goldshire", 0, 1, 0)
		RunTimers()
		assert.are.same({ "Goldshire" }, attached)
		assert.are.same({}, errors.lines)
	end)

	it("passes other system messages straight on", function()
		Discovery.Simulate("You are now away.", 1, 1, 0)
		assert.are.same({ "You are now away." }, errors.lines)
	end)

	it("passes a discovery on late if the banner never shows it", function()
		ns.Banner.show = false
		Discovery.Simulate("Discovered: Goldshire", 0, 1, 0)
		assert.are.same({}, errors.lines)
		RunTimers()
		assert.are.same({ "Discovered: Goldshire" }, errors.lines)
	end)

	it("passes the message on if handling it errors", function()
		ns.Banner.AddDiscovery = function() error("boom") end
		local caught
		local old = _G.geterrorhandler
		_G.geterrorhandler = function() return function(e) caught = e end end
		Discovery.Simulate("Discovered: Goldshire", 0, 1, 0)
		_G.geterrorhandler = old
		assert.are.same({ "Discovered: Goldshire" }, errors.lines)
		assert.are.equal("string", type(caught))
	end)

	it("hands SYSMSG back when the option is turned off", function()
		ns.db.profile.hideBlizzardDiscovery = false
		Discovery.UpdateTakeover()
		assert.is_true(errors.registered.SYSMSG)
		assert.is_false(Discovery.IsTakenOver())
		Discovery.Simulate("Discovered: Goldshire", 0, 1, 0)
		assert.are.same({}, errors.lines) -- Blizzard draws it itself now
	end)

	it("leaves SYSMSG alone if something else already unregistered it", function()
		ns.db.profile.hideBlizzardDiscovery = false
		Discovery.UpdateTakeover()
		errors.registered.SYSMSG = nil
		ns.db.profile.hideBlizzardDiscovery = true
		Discovery.UpdateTakeover()
		assert.is_false(Discovery.IsTakenOver())
	end)
end)
