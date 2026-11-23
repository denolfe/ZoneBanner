# ZoneBanner

Shows the area you walk into, such as **Trade District** under *Stormwind City*, in
the same style as the level-up banner: gold bars that sweep out from the centre, a dark
shadow, a big gold title and a smaller white line above it.

Built for WoW: Forever (Interface 16001). It should also work on retail Midnight.

## Usage
- `/zonebanner` opens the options (also in the Addon Compartment).
- `/zonebanner test` shows a test banner.
- `/zonebanner test discovery` shows a test banner and sends a fake "Discovered" message
  through the same path a real one takes.
- `/zonebanner debug` prints every system and info message to chat, marked as a discovery or
  ignored, until you run it again or reload. Use it if a discovery doesn't reach the banner.

Options:
- **Enable**
- **Only in cities and towns.** Off by default. Uses the rested state, so inns count too.
- **Hide the default zone text**
- **Show discoveries in the banner.** On by default. Adds a small "Discovered"
  line under the area name.
- **Hide Blizzard's discovery message.** On by default. Stops the on-screen "Discovered" line
  at the top of the screen. Other system messages still show as normal. If the banner
  doesn't show a discovery within 4 seconds, Blizzard's line is shown after all.
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
- Redundant banners are skipped. Leaving a subzone back into the zone itself
  (Wetlands, then Menethil Bay, then Wetlands) shows nothing the third time, because you
  never left Wetlands. A banner that showed in the last 30 seconds is also skipped, so
  walking along a border doesn't keep repeating it. The 30 seconds are counted per area,
  not across all banners. A discovery always gets its banner, even one these rules would
  skip. `/zonebanner debug` prints each skip.
- Discoveries are recognised by their text, matched against the localized
  `ERR_ZONE_EXPLORED` / `ERR_ZONE_EXPLORED_XP` strings (plus English fallbacks). On
  Forever the on-screen line arrives as `UI_INFO_MESSAGE` ("Discovered: Tranquil Gardens
  Cemetery"). `SYSMSG` is watched too. The chat copy with the XP is left alone. A
  discovery that arrives just before its banner waits up to
  3 seconds for it.
- Hiding Blizzard's discovery line works by taking over two events. `UIErrorsFrame` stops
  listening to `UI_INFO_MESSAGE` and `SYSMSG`, and the addon hands every one of those
  messages to `UIErrorsFrame`'s own event handler, so colour, sound and flashing stay
  Blizzard's. The only exception is a discovery the banner shows. Turning the option off
  gives the events back. One side effect: other addons that hook `UIErrorsFrame` for
  those events won't see them while the option is on.
- The banner is its own frame. It ignores the mouse and is skipped by gamepad focus.
- If a patch removes `FadingFrame_Show`, the addon falls back to the zone events. It then
  can't hide the default text.

## Development
```bash
python <skill>/scripts/check_addon.py .
luacheck .
luajit <skill>/scripts/mini_busted.lua tests/wow_stubs.lua tests/*_spec.lua
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
9. **Discovery:** walk into an area you haven't explored yet, using a low-level character
   or a fresh zone. The banner should show a "Discovered" line, and Blizzard's
   on-screen line should never appear. Other on-screen messages (for example accepting
   a quest, or `/afk`) should still show, with their sounds. Turn "Hide Blizzard's
   discovery message" off and try another undiscovered area: Blizzard's line shows again.
   If the discovery line never shows, run `/zonebanner debug`, walk into a new area, and
   send me the lines it prints.
10. **Repeats:** ride from the open Wetlands into Menethil Bay and back out. You should
    see "Wetlands" once and "Menethil Bay" once, with no second "Wetlands". Walk back and
    forth over the Menethil Bay border: no repeats for 30 seconds.
11. Afterwards, check `Logs/taint.log` for any `ZoneBanner` lines.
