local _, ns = ...

-- The ONLY file that branches on whether an API exists. Everything else calls
-- ns.Compat.*. When a patch moves or removes an API, this is the one place to fix.

local Compat = {}
ns.Compat = Compat

-- AddOn metadata moved to C_AddOns in 10.x.
Compat.GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- Bag APIs moved to C_Container.
Compat.GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots

-- Forever: DBM switched to GetUnitName for player names; keep one code path.
function Compat.GetUnitName(unit)
	if GetUnitName then
		return GetUnitName(unit, false)
	end
	return (UnitName(unit))
end

-- Secret values (Midnight restrictions, active on Forever). Comparing, doing math,
-- boolean-testing, indexing or concatenating a secret throws. Check first.
function Compat.IsSecret(value)
	if issecretvalue then
		return issecretvalue(value) and true or false
	end
	return false
end

-- True if this code may freely operate on the value.
function Compat.CanAccess(value)
	if canaccessvalue then
		return canaccessvalue(value) and true or false
	end
	return not Compat.IsSecret(value)
end

-- Zone names ------------------------------------------------------------------
-- Returns zone, subzone as plain strings, or nil if the client handed us a
-- secret (Midnight restrictions) or nothing usable. Callers then skip the banner.
function Compat.GetZoneNames()
	if not (GetZoneText and GetSubZoneText) then
		return nil
	end
	local zone, subzone = GetZoneText(), GetSubZoneText()
	if Compat.IsSecret(zone) or Compat.IsSecret(subzone) then
		return nil
	end
	if type(zone) ~= "string" then
		return nil
	end
	if type(subzone) ~= "string" then
		subzone = ""
	end
	return zone, subzone
end

-- "Rested" covers capital cities and towns with an inn.
function Compat.IsInCity()
	if IsResting then
		return IsResting() and true or false
	end
	return true -- unknown: don't filter
end

-- True if the given atlas exists on this client (falls back to "assume yes").
function Compat.HasAtlas(atlas)
	if C_Texture and C_Texture.GetAtlasInfo then
		return C_Texture.GetAtlasInfo(atlas) ~= nil
	end
	return true
end
