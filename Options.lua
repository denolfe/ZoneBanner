local addonName, ns = ...
local L = ns.L

-- Native Settings panel (canvas layout). Standard templates are real Buttons,
-- so they are reachable by gamepad navigation. No typing required: toggles and
-- a -/+ stepper only.

local Options = {}
ns.Options = Options

local category

local CHECKBOXES = {
	{ key = "enabled", label = "Enable", tip = "Show zone names in the level-up banner style." },
	{ key = "citiesOnly", label = "Only in cities and towns", tip = "Only when you are in a rested area (cities, inns)." },
	{ key = "replaceBlizzard", label = "Hide the default zone text", tip = "Hide Blizzard's zone text when the banner shows." },
	{ key = "showDiscovery", label = "Show discoveries in the banner", tip = "Adds \"Discovered\" under the area name." },
	{
		key = "hideBlizzardDiscovery",
		label = "Hide Blizzard's discovery message",
		tip = "Stops the on-screen \"Discovered\" line. Other messages still show.",
	},
}

local HOLD_MIN, HOLD_MAX = 1, 10

local function BuildPanel()
	local panel = CreateFrame("Frame")

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(addonName)

	local anchor = title
	for _, info in ipairs(CHECKBOXES) do
		local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor == title and -16 or -4)
		check:SetSize(32, 32) -- generous hit target
		check.Text:SetText(L[info.label])

		-- Description shown inline, not only in a tooltip (gamepad users may have tooltips off).
		local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		note:SetPoint("LEFT", check.Text, "RIGHT", 8, 0)
		note:SetText(L[info.tip])

		check:SetScript("OnShow", function(self)
			self:SetChecked(ns.db.profile[info.key])
		end)
		check:SetScript("OnClick", function(self)
			ns.db.profile[info.key] = self:GetChecked() and true or false
			ns.Discovery.UpdateTakeover()
		end)
		anchor = check
	end

	-- Hold time stepper.
	local holdLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	holdLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -16)

	local function Refresh()
		holdLabel:SetText((L["Banner duration: %d s"]):format(ns.db.profile.holdTime))
	end

	local function Step(delta)
		local value = ns.db.profile.holdTime + delta
		ns.db.profile.holdTime = math.max(HOLD_MIN, math.min(HOLD_MAX, value))
		Refresh()
	end

	local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	minus:SetSize(36, 28)
	minus:SetPoint("LEFT", holdLabel, "RIGHT", 12, 0)
	minus:SetText("-")
	minus:SetScript("OnClick", function()
		Step(-1)
	end)

	local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	plus:SetSize(36, 28)
	plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	plus:SetText("+")
	plus:SetScript("OnClick", function()
		Step(1)
	end)

	local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	test:SetSize(160, 28)
	test:SetPoint("TOPLEFT", holdLabel, "BOTTOMLEFT", -4, -20)
	test:SetText(L["Show test banner"])
	test:SetScript("OnClick", function()
		ns.Banner.Test()
	end)

	panel:SetScript("OnShow", Refresh)
	return panel
end

function Options.Register()
	if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then
		return
	end
	category = Settings.RegisterCanvasLayoutCategory(BuildPanel(), addonName)
	Settings.RegisterAddOnCategory(category)
end

function Options.Open()
	if not category then
		return
	end
	if ns.IsRestricted("Combat") then
		ns.Print(L["Options are available after combat."])
		return
	end
	Settings.OpenToCategory(category:GetID())
end
