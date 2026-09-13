# Settings

[Mod Setting Menu 1.0.5 or later](https://www.nexusmods.com/thebloodofdawnwalker/mods/271) is optional. To use it, open Main Menu > Mod Settings > All Mods, select Quiet Dawn, change settings, press Apply, then load a save. Restore discards unapplied changes; Reset selects this mod's defaults. The mod works and can be fully configured without this menu.

## Menu categories

Settings are grouped by HUD panel, with size immediately after opacity and related thresholds or reveal durations together. Health and stamina shares the controls used by the human and vampire stat panels; Time of day and Quickslots each include their reveal duration. Combat cues keeps the counterattack, unblockable, parry, lock-icon and size controls together. HUD peek has its own section, and Logging remains the final entry under Diagnostics.

| Category | Controls |
| --- | --- |
| General | Enabled |
| HUD peek | Show HUD on hold and its duration |
| Enemies | Enemy health bars, names, difficulty icons and claw slash marks |
| Combat cues | Counterattack directions, unblockable warnings, parry cues, lock icon and cue size |
| Health and stamina | Human and vampire panel opacity, health/blood and stamina thresholds, and their hold durations |
| Time of day | Panel opacity and reveal duration |
| Compass | Compass opacity |
| Quest tracker | Quest tracker opacity |
| Quickslots | Item and ability quickslot opacity, switch prompt opacity and switch reveal duration |
| Crosshair | Crosshair opacity |
| Combat focus | Combat focus panel opacity |
| Focus charge | Focus charge bar opacity |
| Focus activation prompt | Toggle abilities hint opacity |
| Controls legend | Controls legend opacity |
| Action prompts | Hide sprint/haste prompt |
| Active buffs | Active buffs opacity |
| Ability cooldowns | Ability cooldowns opacity |
| Special attack cooldown | Special attack cooldown opacity |
| Experience | Experience bar opacity |
| Diagnostics | Logging |

Each player-panel category also includes its size slider, directly after the matching opacity control. The 17 size sliders use 25% to 200%, in 5% steps, with a 100% default.

## Default behavior

On a fresh install with no saved or imported preferences, the mod is enabled and all 17 player HUD opacities start at 0% (automatic hiding and contextual reveals). All panel sizes start at 100%. Enemy health bars, enemy names, difficulty icons, claw slash marks, and sprint/haste prompts are hidden. All four combat cue toggles are Off; cue size is 100%. Health/blood below 50% or stamina below 20% keeps the stat panels visible. Health alerts hold for 4 seconds and stamina alerts for 1.5 seconds. Holding Controls Legend reveals the HUD for 3 seconds; switching quickslots reveals them for 3 seconds; time changes reveal the time panel for 4 seconds. Logging is Off. Existing saved or supported imported preferences take precedence over these defaults.

Older settings files receive missing panel size keys at 100%, preserving existing values, comments and prior backups. The current upgrade uses `settings.ini.before-claw-slash-marks`; older `settings.ini.before-panel-scaling` backups are retained. Existing malformed or duplicate values are rejected without replacing the file.

## Claw slash marks

**Hide claw slash marks** hides the red Shredded Touch slash effects on enemies, including the sword variant. It defaults to On and changes only these visuals; damage, bleeding and ordinary blood effects keep their game behavior. Turn it Off under **Enemies**, or set `hideClawSlashMarks = 0` in `settings.ini`, to show the marks again. Apply, then load a save.

Existing settings gain only the missing `hideClawSlashMarks = 1` entry, with a `settings.ini.before-claw-slash-marks` backup. Existing preferences, comments and older backups are preserved.

## Panel size

All 17 player panels have independent size sliders from 25% to 200% in 5% steps, defaulting to 100%. Edge panels grow inward and centered panels stay centered. Original layout spacing stays fixed, so large sizes can overlap nearby elements. Apply, then load a save. Scaling uses each panel's original proportions, including its text and icons. Size is independent of opacity and contextual visibility; 0% opacity still allows a scaled panel to appear during its normal reveal.

Only initialization, replacement and settings-load events apply transforms; there is no recurring size update. Returning to 100% or disabling the mod restores the original size and scaling origin.

## Manual configuration

1. Install Quiet Dawn through Vortex with its required UE4SS loader, then launch the game once. Quiet Dawn creates its own `settings.ini`; you can load a save and play immediately with the defaults.
2. Close the game and back up that generated file. Open `<game folder>/Dawnwalker/Binaries/Win64/ue4ss/Mods/QuietDawnHUD/settings.ini` in a text editor.
3. Edit the existing entries under `[Settings]`, keeping every other entry and the section header. Use `1` for On and `0` for Off, percentages such as `50` (not `0.5`), and seconds such as `1.5`. Keep the exact key names and use a decimal point. Do not add duplicate keys or replace the file with the example below.
4. Save the file, restart the game, and load a save. The next save load reads your values; settings are not polled during play.

Example edits to the matching existing lines (this is not a complete settings file):

```ini
compassOpacity = 50
scale_WBP_Compass = 75
opacity_Crosshair = 100
hideSprintPrompt = 0
hideEnemyHealthBars = 0
hideEnemyNames = 0
hideEnemyDifficultyIcons = 0
showCounterattackDirection = 1
showDirectionalParry = 1
```

This shows the compass at half opacity and 75% size and the crosshair at full opacity when the game permits, restores running prompts and enemy health bars/names/difficulty icons, and enables counterattack and parry directions. Other preferences stay as saved. Set any option back to its listed default to restore that behavior.

Edit `settings.ini`, not `mod_settings.ini` (the optional menu definition), `Scripts/QuietDawnDefaults.lua` (first-use defaults), or the old import-only files. The menu and manual editing use the same settings file, so adding or removing the menu does not require converting your preferences. Keep a backup before a Vortex reinstall.

The stable menu ID is `oOCamilleOo_QuietDawnHUD`. The mod generates `settings.ini` beside `mod_settings.ini` in its UE4SS mod folder. This generated file is the authoritative settings store and is not shipped in the ZIP. Existing supported preferences are imported on first use. After the new settings are saved and verified, the successfully imported legacy files are deleted if their contents are unchanged. Migration or save failures retain the originals. Cleanup failures are logged and do not prevent using the new settings. Files left by an earlier migration are not deleted automatically. Back up `settings.ini` before removing/reinstalling the mod or moving its folder. Restore that backup into the same runtime folder before launching. Do not restore an old INI over it.

Missing existing settings, duplicate or invalid settings stop configuration loading and are reported in `Dawnwalker/Binaries/Win64/ue4ss/UE4SS.log`. Preserve the file before correcting it. If a menu save fails, preserve its temporary/backup files and follow the menu’s recovery instructions. Startup prepares the settings file once, including any supported upgrade. Gameplay reads a fresh settings snapshot when a save loads. Waiting at the main menu performs no recurring settings work; travel and possession events use the current snapshot. Settings are never polled. `debugLogging` controls additional diagnostic logging; it defaults to Off. Panel size diagnostics report applied sizes, bounded readiness failures and transform-write counts through the existing worker timing summary.

| Group | Setting | Choices or range |
| --- | --- | --- |
| General | Enabled | Off, On |
| HUD peek | Show HUD on hold | Off, On |
| HUD peek | Show HUD duration | 0 to 10 seconds in 0.5-second steps |
| Enemies | Hide enemy health bars | Off, On (default On) |
| Enemies | Hide enemy names | Off, On |
| Enemies | Hide enemy difficulty icons | Off, On |
| Enemies | Hide claw slash marks | Off, On (default On) |
| Combat cues | Show counterattack direction | Off (default), On |
| Combat cues | Show unblockable warning | Off (default), On |
| Combat cues | Show directional parry cues | Off (default), On |
| Combat cues | Show lock icon | Off (default), On |
| Combat cues | Combat cue size | 10%–200%, step 10%; default 100% |
| Health and stamina | Human health and stamina opacity | 0% to 100% in 5-point steps |
| Health and stamina | Vampire blood and stamina opacity | 0% to 100% in 5-point steps |
| Health and stamina | Keep health visible below | 0% to 100% in 5-point steps (default 50%) |
| Health and stamina | Health / blood hold duration | 0 to 10 seconds in 0.5-second steps |
| Health and stamina | Keep stamina visible below | 0% to 100% in 5-point steps (default 20%) |
| Health and stamina | Stamina hold duration | 0 to 10 seconds in 0.5-second steps |
| Time of day | Time of day opacity | 0% to 100% in 5-point steps |
| Time of day | Time of day reveal duration | 0 to 10 seconds in 0.5-second steps (default 4 seconds) |
| Compass | Compass opacity | 0% to 100% in 5-point steps |
| Quest tracker | Quest tracker opacity | 0% to 100% in 5-point steps |
| Quickslots | Quickslots opacity | 0% to 100% in 5-point steps |
| Quickslots | Quickslot shortcuts opacity | 0% to 100% in 5-point steps |
| Quickslots | Switch quickslots prompt opacity | 0% to 100% in 5-point steps |
| Quickslots | Show quickslots after switching | 0 to 10 seconds in 0.5-second steps (default 3; 0 disables) |
| Crosshair | Crosshair opacity | 0% to 100% in 5-point steps |
| Combat focus | Combat focus opacity | 0% to 100% in 5-point steps |
| Focus charge | Focus charge opacity | 0% to 100% in 5-point steps |
| Focus activation prompt | Focus activation prompt opacity | 0% to 100% in 5-point steps |
| Controls legend | Controls legend opacity | 0% to 100% in 5-point steps |
| Action prompts | Hide sprint/haste prompt | Off, On (default On) |
| Active buffs | Active buffs opacity | 0% to 100% in 5-point steps |
| Ability cooldowns | Ability cooldowns opacity | 0% to 100% in 5-point steps |
| Special attack cooldown | Special attack cooldown opacity | 0% to 100% in 5-point steps |
| Experience | Experience bar opacity | 0% to 100% in 5-point steps |
| Diagnostics | Logging | Off, On |

Turn off **Hide enemy health bars** to restore ordinary enemy and boss health bars, end caps and boss health-phase indicators. Turn off **Hide enemy names** to restore name labels (boss names), or **Hide enemy difficulty icons** to restore difficulty indicators. All three choices are independent and restore the game's normal visibility for that information. Apply, then load a save. The player HUD peek keeps these choices in effect. At startup, older settings files receive any missing enemy-information options, set to On. Existing preferences and comments are preserved, with a backup before adding missing options.

The four Combat cues toggles work independently of the game's Directional Indicator option. Counterattack directions show the attack opening after a perfect parry; unblockable warnings show the skull; directional parry cues show the incoming direction and highlight its arrow during the parry window; the lock option shows a padlock on a hard-locked target between cues. The dot stays hidden and directions hide all center lock icons. All four toggles default to Off. Combat cue size scales the whole cue group from 10% to 200% in 10% steps, defaulting to 100%. Apply, then load a save. Existing counterattack choices are retained when adding the new controls. Logging reports the observed icon, selected arrow or warning, lock state, size and readiness failures in `Dawnwalker/Binaries/Win64/ue4ss/UE4SS.log`.

Console commands are not used to change settings.

Conditional rows and groups show relevant controls as you edit. Hidden options keep their saved values; hiding an option does not reset it. The optional interface uses toggles, labeled choices and sliders. For manual editing, use the exact numeric keys and values below.

When upgrading an older Quiet Dawn package, back up `Scripts/QuietDawnConfig.lua` before Vortex replaces/removes that package. Restore the backed-up file beside the new scripts before first launch to import its panel/compass choices. If it is absent, the mod uses QuietDawnDefaults.lua. Successfully imported legacy Lua and diagnostics files are removed after the new settings are saved and verified.

**HUD opacity:** all 17 player panels have 0% to 100% sliders in 5-point steps. At 0%, Quiet Dawn manages visibility through resource alerts, quickslot switching, special-attack cooldowns, time changes and manual peek. Positive opacity keeps the selected value while the game controls contextual visibility. HUD peek reveals other managed panels at 100%; the Focus hint, switch hint and special-attack panel retain their own rules.

**Show HUD** uses the game's **Toggle Controls Legend** action. Hold **Menu (Xbox)**, **Options (PlayStation)**, or **L (keyboard)** by default. To change the controller button, edit **Toggle Controls Legend** in Controller Tweaks and Remap. For keyboard, change the game's Controls Legend binding. Quiet Dawn follows the remapped action. Show HUD duration controls the time the HUD remains visible after activation.

**Logging** is the final optional menu setting and the only diagnostic control; manually set `debugLogging` to `0` (Off) or `1` (On). Leave it Off for normal play; On writes troubleshooting details to `Dawnwalker/Binaries/Win64/ue4ss/UE4SS.log`.

**Timers:** all five HUD durations range from 0 to 10 seconds in 0.5-second steps. Zero disables that timed reveal. Health and stamina thresholds and positive panel opacity still apply independently. Defaults remain 4 seconds for health/blood, 1.5 seconds for stamina, 3 seconds for HUD peek, 3 seconds for quickslot switching and 4 seconds for time of day. Older durations above 10 seconds are capped at 10; other fractional durations round to the nearest half-second. If an existing settings file needs this adjustment, the original is kept as `settings.ini.before-short-timers`, preserving all other preferences and comments.

**Visibility thresholds:** keep the health/stamina display visible while human health or vampire blood is below 50%, or stamina is below 20%, by default. Exactly the selected percentage does not trigger the threshold. Damage and stamina use can also reveal it for their hold durations, even above the thresholds. A 0% threshold disables that low-resource trigger. These rules apply when the corresponding panel opacity is 0%. Positive opacity keeps that panel shown without resource-driven hiding.

Older On/Off panel settings are imported into the new opacity controls: Off becomes 0% and On becomes 100%. The upgrade adds the new keys while preserving existing settings, unknown keys and comments; it retains the original file under a `settings.ini.before-*` name for the upgrade being applied (currently `settings.ini.before-combat-cues`). Earlier recovery backups are retained. Compass opacity remains unchanged. Keep recovery files if an upgrade error is reported.

Switching items/abilities briefly reveals panels set to 0%; positive opacity stays at its selected value. The switch hint remains at its own opacity, including during manual HUD peek. Set the special-attack panel to 0% to show it only while recharging; positive values show it normally at the chosen opacity. Both still respect the game's visibility restrictions. The reveal duration uses game time and pauses with the game.

Small blood fluctuations below 0.2% of bar capacity do not renew the health hold. Low-resource thresholds and human damage/stamina alerts remain unchanged. Existing opacity settings gain the new duration without changing selected values; keep the `settings.ini.before-hud-events` recovery copy.

**Time of day:** 0% opacity hides the complete time panel between time changes and HUD peeks. Time changes reveal it at 100% and restart the reveal duration, which defaults to 4 seconds. Pausing preserves the remaining duration. Set the duration to 0 seconds to disable automatic time-change reveals; HUD peek still works. Positive opacity keeps the panel shown and does not use the timer. Existing settings gain these two options without resetting other preferences.

**Hide sprint/haste prompt** is in the **Action prompts** section. It suppresses only the running prompts, including during manual HUD peek. Other action prompts retain game behavior. Apply, then load a save. Existing settings receive the new option set to On, with their preferences and comments preserved.

**Focus activation prompt opacity:** 0% keeps the Toggle abilities button and label hidden in Focus mode and during HUD peek. Positive values use the selected opacity when the game shows the prompt. Ability switching still works. Apply, then load a save.

**Healing and regeneration:** Health and blood gains of at least 0.2% of the bar reveal the stat panel and refresh the health hold duration (4 seconds by default). Repeated qualifying regeneration gains keep the panel visible until that duration expires after the last gain. Smaller gains stay quiet until the bar reaches full. That full-bar reveal rearms only after a deficit of at least 0.2%, preventing repeated near-full notifications. Positive panel opacity and low-resource thresholds keep their existing behavior. The health / blood hold duration also controls these healing reveals; 0 disables them. Small stamina recovery does not trigger a reveal.

## Manual setting reference

All entries below belong under `[Settings]`. Defaults apply to a fresh install without imported preferences. Leave unlisted diagnostic tuning entries at their generated values.

| Setting | INI key | Default | Supported manual values |
| --- | --- | --- | --- |
| Enabled | `enabled` | `1` | 0 = Off, 1 = On |
| Hide enemy health bars | `hideEnemyHealthBars` | `1` | 0 = Off, 1 = On |
| Hide enemy names | `hideEnemyNames` | `1` | 0 = Off, 1 = On |
| Hide enemy difficulty icons | `hideEnemyDifficultyIcons` | `1` | 0 = Off, 1 = On |
| Hide claw slash marks | `hideClawSlashMarks` | `1` | 0 = Off, 1 = On |
| Show counterattack direction | `showCounterattackDirection` | `0` | 0 = Off, 1 = On |
| Show unblockable warning | `showUnblockableWarning` | `0` | 0 = Off, 1 = On |
| Show directional parry cues | `showDirectionalParry` | `0` | 0 = Off, 1 = On |
| Show lock icon | `showLockIcon` | `0` | 0 = Off, 1 = On |
| Combat cue size | `combatCueSize` | `100` | 10 to 200, step 10 |
| Keep health visible below | `healthThreshold` | `50` | 0 to 100 percent; 5-point steps match the menu |
| Keep stamina visible below | `staminaThreshold` | `20` | 0 to 100 percent; 5-point steps match the menu |
| Health / blood hold duration | `healthHoldSeconds` | `4` | 0 to 10, step 0.5 |
| Stamina hold duration | `staminaHoldSeconds` | `1.5` | 0 to 10, step 0.5 |
| Show HUD duration | `manualPeekSeconds` | `3` | 0 to 10, step 0.5 |
| Show HUD on hold | `manualPeek` | `1` | 0 = Off, 1 = On |
| Hide sprint/haste prompt | `hideSprintPrompt` | `1` | 0 = Off, 1 = On |
| Time of day opacity | `opacity_WBP_HudTimer` | `0` | 0 to 100, step 5 |
| Time of day size | `scale_WBP_HudTimer` | `100` | 25 to 200, step 5 |
| Time of day reveal duration | `timeHoldSeconds` | `4` | 0 to 10, step 0.5 |
| Compass opacity | `compassOpacity` | `0` | 0 to 100 percent; 5-point steps match the menu |
| Compass size | `scale_WBP_Compass` | `100` | 25 to 200, step 5 |
| Human health and stamina opacity | `opacity_HumanStats` | `0` | 0 to 100, step 5 |
| Human health and stamina size | `scale_HumanStats` | `100` | 25 to 200, step 5 |
| Vampire blood and stamina opacity | `opacity_VampireStats` | `0` | 0 to 100, step 5 |
| Vampire blood and stamina size | `scale_VampireStats` | `100` | 25 to 200, step 5 |
| Quest tracker opacity | `opacity_WBP_HUD_QuestInfo` | `0` | 0 to 100, step 5 |
| Quest tracker size | `scale_WBP_HUD_QuestInfo` | `100` | 25 to 200, step 5 |
| Quickslots opacity | `opacity_WBP_HUD_Quickslots` | `0` | 0 to 100, step 5 |
| Quickslots size | `scale_WBP_HUD_Quickslots` | `100` | 25 to 200, step 5 |
| Crosshair opacity | `opacity_Crosshair` | `0` | 0 to 100, step 5 |
| Crosshair size | `scale_Crosshair` | `100` | 25 to 200, step 5 |
| Quickslot shortcuts opacity | `opacity_WBP_AA_Quickslots` | `0` | 0 to 100, step 5 |
| Quickslot shortcuts size | `scale_WBP_AA_Quickslots` | `100` | 25 to 200, step 5 |
| Focus activation prompt opacity | `opacity_WBP_OpenFocusPrompt` | `0` | 0 to 100, step 5 |
| Focus activation prompt size | `scale_WBP_OpenFocusPrompt` | `100` | 25 to 200, step 5 |
| Switch quickslots prompt opacity | `opacity_WBP_HUD_Quickslots_ChangePrompt` | `0` | 0 to 100, step 5 |
| Switch quickslots prompt size | `scale_WBP_HUD_Quickslots_ChangePrompt` | `100` | 25 to 200, step 5 |
| Controls legend opacity | `opacity_WBP_ControlsLegend` | `0` | 0 to 100, step 5 |
| Controls legend size | `scale_WBP_ControlsLegend` | `100` | 25 to 200, step 5 |
| Active buffs opacity | `opacity_WBP_BuffContainer` | `0` | 0 to 100, step 5 |
| Active buffs size | `scale_WBP_BuffContainer` | `100` | 25 to 200, step 5 |
| Ability cooldowns opacity | `opacity_WBP_HUD_AbilityCooldownsContainer` | `0` | 0 to 100, step 5 |
| Ability cooldowns size | `scale_WBP_HUD_AbilityCooldownsContainer` | `100` | 25 to 200, step 5 |
| Combat focus opacity | `opacity_CombatFocusPanel` | `0` | 0 to 100, step 5 |
| Combat focus size | `scale_CombatFocusPanel` | `100` | 25 to 200, step 5 |
| Focus charge opacity | `opacity_WBP_HUD_FocusCharge_Bar` | `0` | 0 to 100, step 5 |
| Focus charge size | `scale_WBP_HUD_FocusCharge_Bar` | `100` | 25 to 200, step 5 |
| Special attack cooldown opacity | `opacity_WBP_HUD_SpecialAttackCooldown` | `0` | 0 to 100, step 5 |
| Special attack cooldown size | `scale_WBP_HUD_SpecialAttackCooldown` | `100` | 25 to 200, step 5 |
| Experience bar opacity | `opacity_XPBar` | `0` | 0 to 100, step 5 |
| Experience bar size | `scale_XPBar` | `100` | 25 to 200, step 5 |
| Show quickslots after switching | `switchRevealSeconds` | `3` | 0 to 10, step 0.5 |
| Logging | `debugLogging` | `0` | 0 = Off, 1 = On |

A panel opacity of 0 retains automatic behavior; positive opacity keeps that panel at the chosen opacity subject to game visibility rules. Timers accept 0 to 10 seconds in 0.5-second steps; 0 disables that timed reveal without disabling independent low-resource triggers. Opacity and threshold percentages are stored on a 0 to 100 scale. Panel sizes accept 25 to 200 in 5-point steps. Combat cue size accepts 10 to 200 in 10-point steps.

If a value is malformed, duplicated, missing, or outside the supported range, the settings loader reports it in `Dawnwalker/Binaries/Win64/ue4ss/UE4SS.log`. Correct the existing line or restore your backup, then restart and load a save.
