# ZoneBanner

Shows the area you walk into, such as **Trade District** under *Stormwind City*, in
the same style as the level-up banner: gold bars that sweep out from the centre, a dark
shadow, a big gold title and a smaller white line above it.

Built for WoW: Forever (Interface 16001). It should also work on retail Midnight.

## Usage
- `/zonebanner` opens the options (also in the Addon Compartment).
- `/zonebanner test` shows a test banner.

Options:
- **Enable**
- **Only in cities and towns.** Off by default. Uses the rested state, so inns count too.
- **Hide the default zone text**
- **Banner duration**

## How it works
- It post-hooks Blizzard's `FadingFrame_Show` (`hooksecurefunc`), so the banner fires
  exactly when Blizzard would show zone text, and never on top of a level-up or other toast.
- The only thing it does to Blizzard frames is `Hide()`/`Show()` on `ZoneTextFrame` and
  `SubZoneTextFrame`. Those are plain, non-secure frames, so there are no field writes and
  no replaced scripts.
- Banners queue instead of overlapping. If you change areas while one is showing, it
  stays up for at least 1.5 seconds, fades out quickly, and then the next one shows.
  Only the latest area waits in the queue, and walking back into the area already on
  screen cancels it.
- The banner is its own frame. It ignores the mouse and is skipped by gamepad focus.
- If a patch removes `FadingFrame_Show`, the addon falls back to the zone events. It then
  can't hide the default text.

## Development
```bash
python <skill>/scripts/check_addon.py .
luacheck .
luajit <skill>/scripts/mini_busted.lua tests/wow_stubs.lua tests/DB_spec.lua
luajit <skill>/scripts/smoke_load.lua
```

## In-game test plan
1. Turn on BugSack and `/console taintLog 1`, then `/reload`.
2. **Fresh install:** walk around Stormwind or Orgrimmar. Each district should show a banner
   with the district in gold and the city above it. Blizzard's text should not show as well.
3. **Entering a city from outside:** the banner should show. If Blizzard's text shows
   instead, the rested flag lagged behind; tell me and I'll lengthen `EVALUATE_DELAY`.
4. **Outside cities:** every zone and subzone should get a banner. Turn on "Only in cities"
   and Blizzard's normal text should show out in the world, with no flicker.
5. **Combat:** pull something next to a district border and cross it. You should get no
   errors and no "action blocked" messages.
6. **Level up while crossing a zone:** the level-up toast should win, with no overlap.
7. **Gamepad:** switch input style. The banner must never take focus, and the options
   panel must be reachable with the d-pad.
8. **`/reload` mid-combat**, then **upgrade** (edit `ZoneBannerDB` in WTF to garbage values
   and reload). Settings should self-heal.
9. Afterwards, check `Logs/taint.log` for any `ZoneBanner` lines.
