# Plater-v576a → WoW 3.3.5a backport (FrostmourneRebuffed)

Handoff notes for any agent continuing this port. Read this before editing.

## Target

- Client: WoW 3.3.5a (Lua 5.1, interface 30300), private server "FrostmourneRebuffed" (Whitemane launcher).
- The client ships `rebuffed.dll`, which provides an awesome_wotlk-style `C_NamePlate` (GetNamePlates, GetNamePlateForUnit, `nameplateN` unit tokens, NAME_PLATE_UNIT_ADDED/REMOVED).
- Source: retail Plater-v576a. Loaded via `Plater.toc` (`## Interface: 30300`). `Plater_Wrath.toc`, `Plater_Mainline.toc`, `Plater_Vanilla.toc` are retail leftovers and are not used by this client.
- **Self-contained**: must not depend on `!!!ClassicAPI` or any other shim addon.
- User tests in game and pastes BugGrabber errors; fix iteratively. Errors usually look like `Plater-Plater-v576a-335\File.lua:LINE: ...`.

## Architecture

- `Plater_335Compat.lua` (first file in the toc) builds `PLATER335_ENV`, a private environment whose `__index` is `_G`. **Every Plater/DF/lib source file starts with `setfenv(1, PLATER335_ENV);`** — keep that line when adding files.
  - `env.X = ...` defines a retail API privately for Plater only; never pollute `_G` (other addons on this client break).
  - The env's `__newindex` (pass Plater's own globals through to `_G`) is installed at the end of the compat file.
  - Only *missing* widget methods are added to shared metatables (e.g. Texture:SetMask noop, StatusBar:SetReverseFill noop, animation SetToAlpha/SetScaleFrom/SetScaleTo/SetToFinalAlpha).
  - Bump `PLATER335_VERSION` when changing the compat layer.
  - Sections: game flavor (WOW_PROJECT_ID = 11, Wrath), mixins/pools, C_Timer, Enum, Unit/Spell/Aura APIs in 3.4 format (AuraUtil, C_UnitAuras, UnitGetTotalAbsorbs→0), cast spellId lookup from combat log (3.3.5 casts have no spellId), CombatLogGetCurrentEventInfo in 3.4 layout, C_ namespaces, hex GUIDs, event aliasing/synthesized unit events for nameplate tokens, SetAtlas fallback, retail-template dropping, nameplate driver (hides native regions while Plater owns a plate), nil-unit guards for Unit* APIs.
  - Power type 4 is remapped to combo points (`UnitPower`/`UnitPowerMax`); 3.3.5 power types: 0 mana, 1 rage, 2 focus, 3 energy, 4 happiness, 5 runes, 6 runic power.
- `Plater_WotlkData.lua`: WotLK npc/spell seed data (generated from installed DBM WotLK modules) for the Npc Colors, Cast Colors and Spell List panels.
- `Plater_WotlkMods.lua`: WotLK Plater **mods** (hook_data) seeded into each profile, and retail cleanup. Controlled by `SEED_VERSION` (bump it to re-run on every profile). Currently:
  - Mods: "Totem Icons [WotLK]", "Healer Markers [WotLK]", "Interrupt Ready [WotLK]", "Abbreviate NPC Names [WotLK]".
  - Removes retail-only scripts (Explosion Affix M+, M+ Spiteful, Countdown, Aura is Shield, Cast - Shield Interrupt) from profiles and from `PlaterScriptLibrary`, and strips trigger SpellIds > 80864 / NpcIDs > 40500.
  - Features are added as mods/scripts, **not** as separate plugin addons (user preference).
- `Plater_Comms.lua` `Plater.DecompressData`: reads old Plater strings (AceSerializer + LibDeflate print), `!PLATER:N!` + LibSerialize, and retail `!PLATER:2!` (= base64 → raw deflate → CBOR, decoded by local `decodeBase64` / `decodeCBOR`).
- `Plater.lua` `Plater.RefreshDBUpvalues()` backfills keys missing from profiles imported from newer Plater versions.

## Rules of thumb

- Retail APIs: check whether the compat layer already shims it before touching call sites; prefer adding a shim in the env over editing many call sites.
- Script/mod code strings run through Plater's compiler inside the same env, so shims apply to them too.
- LibStub: highest minor wins. Retail LibSharedMedia (12000002) copies in other addons (`NaowhUI_Media`, `EUIStandaloneDamageMeters`, `EllesmereUI`) were patched at line ~240: `C_UIFileAsset and C_UIFileAsset.IsKnownFile or function() return true end`. Those patches live outside this repo; re-apply if those addons update.
- Lua 5.1 only: no `goto`, no `//`, no bit ops syntax, `xpcall` extra args are shimmed.
- Shell is PowerShell on Windows. SavedVariables: `WTF\Account\<ACCOUNT>\SavedVariables\Plater.lua` (outside this repo; never commit them).
- Don't edit SavedVariables while the game is running; do data migrations in Lua (see `Plater_WotlkMods.lua` seed pattern).

## Status / open items

- All BugGrabber errors reported so far are fixed; still in in-game error rounds.
- Untested in game yet: retail `!PLATER:2!` profile import (CBOR decoder), "Abbreviate NPC Names" mod, retail script cleanup, health/cast/aura synthesis accuracy, target highlight, threat colors.
- Retail-trigger scripts kept as generic templates; could be refilled with WotLK spell IDs from `Plater_WotlkData.lua`.
