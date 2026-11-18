-- Minimal WoW API stand-ins for unit tests. Each stub is an assumption about the
-- real API: keep them few, and only for modules under test.

_G.wipe = _G.wipe or function(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end

_G.geterrorhandler = _G.geterrorhandler or function()
	return function(err)
		error(err, 0)
	end
end

-- Load an addon file the way WoW does: as a chunk receiving (addonName, ns).
function _G.LoadAddonFile(path, ns, addonName)
	local chunk = assert(loadfile(path))
	chunk(addonName or "ZoneBanner", ns)
	return ns
end
