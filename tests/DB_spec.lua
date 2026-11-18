describe("DB", function()
	local DB

	before_each(function()
		local ns = LoadAddonFile("DB.lua", {})
		DB = ns.DB
	end)

	it("stamps a fresh install at the current version without migrating", function()
		local db = DB.Load(nil)
		assert.are.equal(DB.CURRENT_VERSION, db.version)
		assert.is_true(db.profile.enabled)
		assert.is_false(db.profile.citiesOnly)
		assert.is_true(db.profile.replaceBlizzard)
		assert.are.equal(3, db.profile.holdTime)
	end)

	it("treats a versionless table as version 0 and migrates it", function()
		local db = DB.Load({ profile = { enabled = false } })
		assert.are.equal(DB.CURRENT_VERSION, db.version)
		assert.is_false(db.profile.enabled)
	end)

	it("migrates v1 citiesOnly=true to show everywhere", function()
		local db = DB.Load({ version = 1, profile = { citiesOnly = true, enabled = false } })
		assert.are.equal(2, db.version)
		assert.is_false(db.profile.citiesOnly)
		assert.is_false(db.profile.enabled)
	end)

	it("keeps valid saved values over defaults", function()
		local db = DB.Load({ version = DB.CURRENT_VERSION, profile = { citiesOnly = true, holdTime = 5 } })
		assert.is_true(db.profile.citiesOnly)
		assert.are.equal(5, db.profile.holdTime)
	end)

	it("self-heals values of the wrong type", function()
		local db = DB.Load({ version = DB.CURRENT_VERSION, profile = { enabled = "yes", holdTime = "long" } })
		assert.is_true(db.profile.enabled)
		assert.are.equal(3, db.profile.holdTime)
	end)

	it("clamps an out-of-range hold time", function()
		local db = DB.Load({ version = DB.CURRENT_VERSION, profile = { holdTime = 999 } })
		assert.are.equal(3, db.profile.holdTime)
	end)

	it("keeps unknown keys", function()
		local db = DB.Load({ version = DB.CURRENT_VERSION, profile = { futureThing = 1 } })
		assert.are.equal(1, db.profile.futureThing)
	end)

	it("leaves data from a newer version unmigrated and flags it", function()
		local db = DB.Load({ version = DB.CURRENT_VERSION + 1, profile = { oldThing = 3 } })
		assert.are.equal(DB.CURRENT_VERSION + 1, db.version)
		assert.are.equal(3, db.profile.oldThing)
		assert.is_true(DB.fromFuture)
	end)

	it("replaces a non-table saved variable", function()
		local db = DB.Load("garbage")
		assert.are.equal(DB.CURRENT_VERSION, db.version)
	end)
end)
