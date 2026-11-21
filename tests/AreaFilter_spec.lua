describe("AreaFilter", function()
	local F

	-- Mimics Evaluate + Display: check, and mark shown when allowed.
	local function Visit(title, subtitle, now)
		local show = F.Check(title, subtitle, now)
		if show then
			F.MarkShown(title, subtitle, now)
		end
		return show
	end

	before_each(function()
		local ns = LoadAddonFile("AreaFilter.lua", {})
		F = ns.AreaFilter
		F.Reset()
	end)

	it("skips the zone again after leaving one of its subzones", function()
		assert.is_true(Visit("Wetlands", nil, 0))
		assert.is_true(Visit("Menethil Bay", "Wetlands", 5))
		assert.is_false(Visit("Wetlands", nil, 10))
	end)

	it("skips the zone even long after, as long as you never left it", function()
		Visit("Wetlands", nil, 0)
		Visit("Menethil Bay", "Wetlands", 5)
		assert.is_false(Visit("Wetlands", nil, 500))
	end)

	it("shows a new zone", function()
		Visit("Wetlands", nil, 0)
		assert.is_true(Visit("Arathi Highlands", nil, 100))
	end)

	it("skips a subzone shown moments ago when walking a border", function()
		Visit("Menethil Bay", "Wetlands", 0)
		Visit("Wetlands", nil, 2)
		assert.is_false(Visit("Menethil Bay", "Wetlands", 4))
	end)

	it("skips bouncing back across a zone border", function()
		Visit("Wetlands", nil, 0)
		Visit("Arathi Highlands", nil, 3)
		local show, reason = F.Check("Wetlands", nil, 6)
		assert.is_false(show)
		assert.are.equal("shown recently", reason)
	end)

	it("shows a repeat once the window has passed", function()
		Visit("Menethil Bay", "Wetlands", 0)
		Visit("Wetlands", nil, 2)
		assert.is_true(Visit("Menethil Bay", "Wetlands", F.REPEAT_WINDOW + 1))
	end)

	it("doesn't count a banner that was queued but never shown", function()
		F.Check("Menethil Bay", "Wetlands", 0) -- allowed, but dropped before showing
		assert.is_true(Visit("Menethil Bay", "Wetlands", 2))
	end)

	it("shows the first banner after login", function()
		assert.is_true(Visit("Stormwind City", nil, 0))
	end)
end)
