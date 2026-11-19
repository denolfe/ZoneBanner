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
