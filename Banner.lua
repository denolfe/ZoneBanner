local _, ns = ...

-- The banner: zone/subzone names drawn like the level-up toast
-- (EventToastManagerFrame in Blizzard_FrameXML/EventToastManager.xml, forever branch):
-- gold bars top and bottom, a dark shadow behind, GameFont_Gigantic title with a
-- SystemFont_Shadow_Large line above it.
--
-- How it hooks in: Blizzard's ZoneText_OnEvent calls FadingFrame_Show(ZoneTextFrame /
-- SubZoneTextFrame) exactly when it would show zone text. We post-hook that global
-- (hooksecurefunc, never a replacement), so we follow Blizzard's own "did the zone
-- really change" logic and its "don't show during a toast" rule for free.
-- The only thing we do to Blizzard frames is call :Hide()/:Show() on those two
-- plain, non-secure, non-Edit-Mode frames. No field writes, no SetScript.

local Banner = {}
ns.Banner = Banner

local C_Timer, CreateFrame, GetTime, UIParent = C_Timer, CreateFrame, GetTime, UIParent
local min, max = math.min, math.max

local WIDTH = 418 -- EventToastManagerFrame fixedWidth
local TOP_OFFSET = -190 -- EventToastManagerFrame anchor
local PADDING = 14
local MIN_HEIGHT = 64 -- EventToastManager's fixedHeight for the level-up toast
local SUB_GAP, DETAIL_GAP = 3, 4
-- The title font's line box includes room for descenders, which most area names don't
-- use, so mathematically centred caps look high. Nudge the text block down a little.
local OPTICAL_NUDGE = 2
local FADE_IN, FADE_OUT, GROW = 0.5, 1.0, 0.5
-- Queueing: when a new banner arrives while one is showing, the current one stays
-- readable for at least MIN_VISIBLE seconds, then fades out quickly (HANDOFF_FADE)
-- and the newest pending banner takes over. Only the latest request is kept, so
-- walking back and forth over a border never builds a backlog of stale names.
local MIN_VISIBLE = 1.5
local HANDOFF_FADE = 0.4
-- A discovery usually lands a moment after its banner. Instead of popping in, the
-- line fades in while the banner eases to its new size, and the banner stays up long
-- enough to read it (rewinding a fade-out smoothly if it had already started).
local DETAIL_FADE, RESIZE = 0.4, 0.3
local DETAIL_MIN_VISIBLE = 2
-- IsResting() can lag the zone event by a moment when you first enter a city.
local EVALUATE_DELAY = 0.1

local TITLE_R, TITLE_G, TITLE_B = 1, 0.82, 0 -- level-up gold
local SUB_R, SUB_G, SUB_B = 1, 1, 1
local DETAIL_R, DETAIL_G, DETAIL_B = 1, 0.93, 0.76 -- Blizzard's default zone-text cream

local frame
local elapsedTotal, holdTime, fadeOut = 0, 3, FADE_OUT
local grown = false -- the bars finished sweeping out
-- Late-detail animation: frame height and title offset ease from -> to.
local currentHeight, currentOffset = 0, 0
local resizeFrom, resizeTo, offsetFrom, offsetTo, resizeElapsed
local detailElapsed
local lineWidth, shadowHeight = WIDTH, 80

-- What is on screen now, and the one waiting (latest wins).
-- detail = optional small line under the title (e.g. "Discovered");
-- onDetailShown = callback run once that detail is actually on screen.
local currentTitle, currentSub, currentDetail
local pendingTitle, pendingSub, pendingDetail, pendingDetailShown

-- A discovery that arrived before its banner (the usual order: the server's
-- explore message lands before our zone evaluation). Matched by area name.
local STASH_SECONDS = 3
local stashName, stashDetail, stashShown, stashTime

local Display -- forward declaration (OnUpdate hands off to the next banner)

-- Building ----------------------------------------------------------------------

local function FontOrFallback(fontString, preferred, fallback)
	local object = _G[preferred]
	if type(object) ~= "table" then
		object = _G[fallback]
	end
	if object then
		fontString:SetFontObject(object)
	end
end

local function AtlasOrColor(texture, atlas, r, g, b, a, width, height)
	if ns.Compat.HasAtlas(atlas) then
		texture:SetAtlas(atlas, true) -- true = use atlas size
	else
		texture:SetColorTexture(r, g, b, a)
		texture:SetSize(width, height)
	end
end

-- Eased 0..1 progress, like the toast's grow animation.
local function EaseOut(p)
	p = 1 - p
	return 1 - p * p
end

-- Sets the banner height and the title's offset from the centre together.
local function ApplySize(height, offset)
	currentHeight, currentOffset = height, offset
	frame:SetHeight(height)
	frame.Title:ClearAllPoints()
	frame.Title:SetPoint("CENTER", frame, "CENTER", 0, offset)
end

local function OnUpdate(self, elapsed)
	elapsedTotal = elapsedTotal + elapsed
	local fadeOutStart = FADE_IN + holdTime

	-- Something is waiting: once this one has been readable long enough, cut the
	-- hold short and start a quick fade-out (from the current alpha, no pop).
	if pendingTitle and elapsedTotal < fadeOutStart and elapsedTotal >= MIN_VISIBLE then
		holdTime = max(0, elapsedTotal - FADE_IN)
		fadeOutStart = FADE_IN + holdTime
		fadeOut = HANDOFF_FADE
	end

	local t = elapsedTotal
	if t >= fadeOutStart + fadeOut then
		if pendingTitle then
			local title, subtitle, detail, onShown = pendingTitle, pendingSub, pendingDetail, pendingDetailShown
			pendingTitle, pendingSub, pendingDetail, pendingDetailShown = nil, nil, nil, nil
			Display(title, subtitle, detail, onShown)
		else
			currentTitle, currentSub, currentDetail = nil, nil, nil
			self:Hide()
		end
		return
	end

	if t < FADE_IN then
		self:SetAlpha(t / FADE_IN)
	elseif t < fadeOutStart then
		self:SetAlpha(1)
	else
		self:SetAlpha(1 - (t - fadeOutStart) / fadeOut)
	end

	if not grown then
		local p = EaseOut(min(1, t / GROW))
		local w = max(1, lineWidth * p)
		self.TopLine:SetWidth(w)
		self.BottomLine:SetWidth(w)
		self.Shadow:SetHeight(max(1, shadowHeight * p))
		grown = p >= 1
	end

	if resizeElapsed then
		resizeElapsed = resizeElapsed + elapsed
		local p = EaseOut(min(1, resizeElapsed / RESIZE))
		ApplySize(resizeFrom + (resizeTo - resizeFrom) * p, offsetFrom + (offsetTo - offsetFrom) * p)
		if p >= 1 then
			resizeElapsed = nil
		end
	end
	if detailElapsed then
		detailElapsed = detailElapsed + elapsed
		local p = min(1, detailElapsed / DETAIL_FADE)
		self.Detail:SetAlpha(p)
		if p >= 1 then
			detailElapsed = nil
		end
	end
end

local function Build()
	-- Named so /fstack and taint logs say whose frame this is.
	local f = CreateFrame("Frame", "ZoneBannerFrame", UIParent)
	f:SetSize(WIDTH, 72)
	f:SetPoint("TOP", UIParent, "TOP", 0, TOP_OFFSET)
	f:SetFrameStrata("HIGH")
	f:EnableMouse(false) -- purely visual; never steals clicks
	f:Hide()

	f.Shadow = f:CreateTexture(nil, "BACKGROUND", nil, 0)
	f.Shadow:SetPoint("BOTTOM")
	AtlasOrColor(f.Shadow, "levelup-shadow-upper", 0, 0, 0, 1, WIDTH, 80)
	f.Shadow:SetAlpha(0.6)

	f.TopLine = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.TopLine:SetPoint("TOP")
	AtlasOrColor(f.TopLine, "levelup-bar-gold", TITLE_R, TITLE_G, TITLE_B, 0.9, WIDTH, 2)

	f.BottomLine = f:CreateTexture(nil, "BACKGROUND", nil, 2)
	f.BottomLine:SetPoint("BOTTOM")
	AtlasOrColor(f.BottomLine, "levelup-bar-gold", TITLE_R, TITLE_G, TITLE_B, 0.9, WIDTH, 2)

	f.SubTitle = f:CreateFontString(nil, "ARTWORK")
	FontOrFallback(f.SubTitle, "SystemFont_Shadow_Large", "GameFontHighlightLarge")
	f.SubTitle:SetTextColor(SUB_R, SUB_G, SUB_B)
	f.SubTitle:SetJustifyH("CENTER")

	f.Title = f:CreateFontString(nil, "ARTWORK")
	FontOrFallback(f.Title, "GameFont_Gigantic", "GameFontNormalHuge")
	f.Title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)
	f.Title:SetJustifyH("CENTER")

	f.Detail = f:CreateFontString(nil, "ARTWORK")
	FontOrFallback(f.Detail, "SystemFont_Shadow_Med1", "GameFontHighlight")
	f.Detail:SetTextColor(DETAIL_R, DETAIL_G, DETAIL_B)
	f.Detail:SetJustifyH("CENTER")

	-- Natural sizes, captured once so the grow animation knows where to stop.
	lineWidth = f.TopLine:GetWidth() or WIDTH
	shadowHeight = f.Shadow:GetHeight() or 80

	f:SetScript("OnUpdate", OnUpdate) -- only runs while shown

	ns.Gamepad.Ignore(f) -- never a gamepad focus target
	return f
end

-- Showing -----------------------------------------------------------------------

local function Normalize(subtitle)
	if type(subtitle) == "string" and subtitle ~= "" then
		return subtitle
	end
	return nil
end

local function MatchesArea(name, title, subtitle)
	return name ~= nil and (name == title or name == subtitle)
end

-- Returns the stashed discovery detail for this banner, if it is fresh and matches.
local function TakeStash(title, subtitle)
	if stashName and GetTime() - stashTime <= STASH_SECONDS and MatchesArea(stashName, title, subtitle) then
		local detail, onShown = stashDetail, stashShown
		stashName, stashDetail, stashShown, stashTime = nil, nil, nil, nil
		return detail, onShown
	end
	return nil
end

-- Sets the texts and stacks subtitle / title / detail, centred between the bars.
-- The title is anchored to the frame's centre, so a single line is centred no matter
-- what GetStringHeight reports; measured heights only shift it for the extra lines.
-- Returns the banner height and title offset; the caller applies them (at once, or
-- eased when a line arrives late).
local function Layout(subtitle, title, detail)
	local hasSub = subtitle ~= nil
	local hasDetail = detail ~= nil
	frame.SubTitle:ClearAllPoints()
	frame.Detail:ClearAllPoints()
	frame.SubTitle:SetText(subtitle or "")
	frame.SubTitle:SetShown(hasSub)
	frame.Title:SetText(title)
	frame.Detail:SetText(detail or "")
	frame.Detail:SetShown(hasDetail)

	local titleHeight = frame.Title:GetStringHeight() or 0
	if titleHeight <= 0 then
		titleHeight = 32
	end
	local above, below = 0, 0
	if hasSub then
		local h = frame.SubTitle:GetStringHeight() or 0
		above = (h > 0 and h or 18) + SUB_GAP
		frame.SubTitle:SetPoint("BOTTOM", frame.Title, "TOP", 0, SUB_GAP)
	end
	if hasDetail then
		local h = frame.Detail:GetStringHeight() or 0
		below = (h > 0 and h or 14) + DETAIL_GAP
		frame.Detail:SetPoint("TOP", frame.Title, "BOTTOM", 0, -DETAIL_GAP)
	end
	-- Centre the whole block: shift the title by half the difference above vs below.
	local offset = (below - above) / 2 - OPTICAL_NUDGE
	return max(MIN_HEIGHT, titleHeight + above + below + PADDING * 2), offset
end

-- Adds a detail line to the banner already on screen: the line fades in, the banner
-- eases to its new size, and it stays up long enough to read the line.
local function AddDetailToShown(detail)
	if detail == currentDetail then
		return -- the same line again (a second copy): nothing to animate
	end
	currentDetail = detail
	local fromHeight, fromOffset = currentHeight, currentOffset
	local toHeight, toOffset = Layout(currentSub, currentTitle, detail)
	resizeFrom, resizeTo, offsetFrom, offsetTo = fromHeight, toHeight, fromOffset, toOffset
	resizeElapsed = 0
	ApplySize(fromHeight, fromOffset)
	frame.Detail:SetAlpha(0)
	detailElapsed = 0

	local fadeOutStart = FADE_IN + holdTime
	if elapsedTotal >= fadeOutStart then
		-- Already fading out: rewind to the point in the fade-in with the same alpha.
		local alpha = max(0, 1 - (elapsedTotal - fadeOutStart) / fadeOut)
		elapsedTotal = alpha * FADE_IN
		fadeOut = FADE_OUT
		holdTime = DETAIL_MIN_VISIBLE
	else
		holdTime = max(holdTime, elapsedTotal - FADE_IN + DETAIL_MIN_VISIBLE)
	end
end

local function RunShown(onShown)
	if type(onShown) == "function" then
		ns.SafeCall(onShown)
	end
end

-- Puts a banner on screen immediately, restarting the animation.
-- Assigns the forward-declared `local Display` above; luacheck confirms it is local.
Display = function(title, subtitle, detail, onDetailShown) -- check-ignore: global-write forward-declared local
	frame = frame or Build()
	currentTitle, currentSub, currentDetail = title, subtitle, detail
	ns.AreaFilter.MarkShown(title, subtitle, GetTime())
	ApplySize(Layout(subtitle, title, detail))
	resizeElapsed, detailElapsed = nil, nil
	frame.Detail:SetAlpha(1)
	grown = false
	if detail then
		RunShown(onDetailShown)
	end

	holdTime = (ns.db and ns.db.profile.holdTime) or 3
	fadeOut = FADE_OUT
	elapsedTotal = 0
	frame.TopLine:SetWidth(1)
	frame.BottomLine:SetWidth(1)
	frame.Shadow:SetHeight(1)
	frame:SetAlpha(0)
	frame:Show()
end

-- title: big gold line. subtitle: optional smaller white line above it.
-- Queue-aware: never interrupts a banner that is on screen.
function Banner.Show(title, subtitle)
	if type(title) ~= "string" or title == "" then
		return
	end
	subtitle = Normalize(subtitle)

	if not (frame and frame:IsShown() and currentTitle) then
		pendingTitle, pendingSub, pendingDetail, pendingDetailShown = nil, nil, nil, nil
		Display(title, subtitle, TakeStash(title, subtitle))
		return
	end

	if title == currentTitle and subtitle == currentSub then
		-- Back where the current banner says you are: drop whatever was waiting.
		pendingTitle, pendingSub, pendingDetail, pendingDetailShown = nil, nil, nil, nil
		return
	end

	-- Latest wins.
	pendingTitle, pendingSub = title, subtitle
	pendingDetail, pendingDetailShown = TakeStash(title, subtitle)
end

-- Returns title, subtitle for the current location, or nil if no banner should show.
local function CurrentBanner()
	local profile = ns.db and ns.db.profile
	if not (profile and profile.enabled) then
		return nil
	end
	if profile.citiesOnly and not ns.Compat.IsInCity() then
		return nil
	end
	local zone, subzone = ns.Compat.GetZoneNames()
	if not zone or zone == "" then
		return nil
	end
	if subzone ~= "" and subzone ~= zone then
		return subzone, zone
	end
	return zone, nil
end

-- A banner for where you are was skipped as redundant: anything still waiting in the
-- queue is for a place you already left, so drop it (unless it is for right here).
function Banner.DropPending(title, subtitle)
	if pendingTitle == title and pendingSub == subtitle then
		return
	end
	pendingTitle, pendingSub, pendingDetail, pendingDetailShown = nil, nil, nil, nil
end

-- True if a fresh discovery is waiting for this banner.
function Banner.HasStash(title, subtitle)
	return stashName ~= nil and GetTime() - stashTime <= STASH_SECONDS and MatchesArea(stashName, title, subtitle)
end

-- Attach a discovery line ("Discovered") to the banner for `name`.
-- onShown runs once the line is actually on screen (used to hide Blizzard's copy).
-- If no banner for that area exists yet, it waits a few seconds for one.
function Banner.AddDiscovery(name, detail, onShown)
	if type(name) ~= "string" or name == "" or type(detail) ~= "string" then
		return
	end
	if frame and frame:IsShown() and MatchesArea(name, currentTitle, currentSub) then
		AddDetailToShown(detail)
		RunShown(onShown)
	elseif pendingTitle and MatchesArea(name, pendingTitle, pendingSub) then
		-- A second copy of the same discovery (say, on another event) must not lose
		-- the first copy's callback.
		pendingDetail, pendingDetailShown = detail, onShown or pendingDetailShown
	else
		if stashName == name and not onShown then
			onShown = stashShown
		end
		stashName, stashDetail, stashShown, stashTime = name, detail, onShown, GetTime()
		-- A discovery is a first visit, so it always earns a banner, even one the
		-- repeat filter skipped or one Blizzard never asked for. If we are already
		-- standing in that area, show it now (it picks up the stash).
		local title, subtitle = CurrentBanner()
		if title and MatchesArea(name, title, subtitle) then
			Banner.Show(title, subtitle)
		end
	end
end

function Banner.Test()
	local zone, subzone = ns.Compat.GetZoneNames()
	if zone and subzone ~= "" and subzone ~= zone then
		Banner.Show(subzone, zone)
		return subzone
	end
	Banner.Show("Trade District", "Stormwind City")
	return "Trade District"
end

-- Deciding ------------------------------------------------------------------------

local pending = false
local suppressed = {} -- Blizzard frames we hid while deciding

local function RestoreBlizzard()
	for blizzardFrame in pairs(suppressed) do
		blizzardFrame:Show() -- its own OnUpdate resumes the fade where it was
	end
	wipe(suppressed)
end

local function Evaluate()
	pending = false
	local title, subtitle = CurrentBanner()
	if title then
		wipe(suppressed) -- keep Blizzard's text hidden; ours replaces it
		local show, reason = ns.AreaFilter.Check(title, subtitle, GetTime())
		if show or Banner.HasStash(title, subtitle) then
			Banner.Show(title, subtitle) -- a waiting discovery overrides the filter
		else
			if ns.debug then
				ns.Print("Skipped %s (%s)", title, reason)
			end
			Banner.DropPending(title, subtitle)
		end
	else
		RestoreBlizzard()
	end
end

local function Schedule()
	if not pending then
		pending = true
		C_Timer.After(EVALUATE_DELAY, Evaluate)
	end
end

-- Post-hook on Blizzard's FadingFrame_Show. Read-only except Hide() on the
-- two zone-text frames, which are plain non-secure frames.
local function OnFadingFrameShow(fadingFrame)
	if fadingFrame == nil or (fadingFrame ~= ZoneTextFrame and fadingFrame ~= SubZoneTextFrame) then
		return
	end
	local profile = ns.db and ns.db.profile
	if not (profile and profile.enabled) then
		return
	end
	if profile.replaceBlizzard then
		-- Hide now (it is still at alpha 0) so there is no flash; Evaluate puts it
		-- back if we decide not to show our banner.
		fadingFrame:Hide()
		suppressed[fadingFrame] = true
	end
	Schedule()
end

-- Fallback if a patch removes FadingFrame_Show: listen to the zone events
-- ourselves (no Blizzard text suppression, and we dedupe repeats).
local lastKey
local function OnZoneEvent()
	local zone, subzone = ns.Compat.GetZoneNames()
	if not zone then
		return
	end
	local key = zone .. "\0" .. subzone
	if key ~= lastKey then
		lastKey = key
		Schedule()
	end
end

local initialized = false
function Banner.Init()
	if initialized then
		return
	end
	initialized = true

	if type(FadingFrame_Show) == "function" then
		hooksecurefunc("FadingFrame_Show", OnFadingFrameShow)
	else
		ns.On("ZONE_CHANGED", OnZoneEvent)
		ns.On("ZONE_CHANGED_INDOORS", OnZoneEvent)
		ns.On("ZONE_CHANGED_NEW_AREA", OnZoneEvent)
	end
end
