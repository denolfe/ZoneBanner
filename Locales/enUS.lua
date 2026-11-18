local _, ns = ...

-- Missing keys return the key itself, so an untranslated string never errors.
-- Write keys in English; other locales go in Locales/<locale>.lua guarded by
-- `if GetLocale() ~= "deDE" then return end` and fill ns.L.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
