# Notes for coding agents

ZoneBanner is a WoW: Forever addon (Interface 16001). It shows zone and subzone text
on a banner styled like the level-up banner. How it works and the in-game test plan
are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Priorities
In this order: never break the UI (no taint, no errors), survive patches, gamepad
parity, then features.

## Code
- Don't taint Blizzard frames. Use `hooksecurefunc` post-hooks, and only call
  `Hide()`/`Show()` on `ZoneTextFrame` and `SubZoneTextFrame`. Don't write fields or
  replace scripts on Blizzard frames.
- Guard values that may be secret with `ns.Compat.IsSecret`. Wrap risky handlers in
  `pcall`, and fall back to Blizzard's behaviour when something goes wrong.
- When the SavedVariables shape changes, add a migration in `DB.lua` and bump
  `CURRENT_VERSION`.
- Keep pure logic (such as `AreaFilter.lua` and the parsing in `Discovery.lua`) free of
  WoW API calls so it can be unit-tested.
- Add new WoW globals to `read_globals` in `.luacheckrc` on purpose. Keep `globals`
  (the ones the addon writes) tiny.
- `check_addon.py` ignore comments must be inline, on the same line.

## Checks
Run all of these before saying a change is done. `<skill>` is the
`wow-forever-addon-dev` skill's folder.

```bash
python <skill>/scripts/check_addon.py .
luacheck .
luajit <skill>/scripts/mini_busted.lua tests/wow_stubs.lua tests/*_spec.lua
luajit <skill>/scripts/smoke_load.lua
luajit <skill>/scripts/smoke_load.lua --gamepad
```

`mini_busted` has no `after_each`, `is_truthy` or `is_falsy`. Tests that create frames
reset shared stubs in `before_each`.

Passing tests don't mean it works in game. Say what hasn't been seen in game yet.

## Git
- Commit only when asked. When asked for granular commits, split by change.
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, ...) with a lowercase subject.
- The branch is `main`, pushed to `origin` (GitHub). Ask before pushing.
- When rewriting history, keep the original author and committer timestamps.

## Docs
- Keep `README.md` short and user-facing: a screenshot, features and the slash
  commands. Leave out internals and gamepad notes.
- Technical detail and the test plan go in `docs/DEVELOPMENT.md`. Update it when
  behaviour changes.
- `docs/`, `README.md` and `AGENTS.md` aren't shipped (see `.pkgmeta`).

## Local setup
The addon folder in the game's `AddOns` directory is a junction to this repo. Never
delete through it recursively; remove the junction with `rmdir`.
