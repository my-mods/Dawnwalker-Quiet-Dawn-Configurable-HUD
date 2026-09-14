# Changelog

## 1.0

- Suppress Sprint/Haste prompts before they appear in human and vampire form, and hide existing running prompts when the option is enabled.
- Show the time panel when activities advance time, including shrine restoration, and preserve the reveal while an activity hides the HUD.
- Apply settings directly to active gameplay through Mod Setting Menu.
- Add independent size sliders for all 17 player panels, from 25% to 200% in 5% steps, with screen-edge alignment.
- Fix size changes getting stuck at partial opacity, including a compass set to 25% size and 40% opacity.
- Add Hide claw slash marks for the red Shredded Touch effects and sword variant, enabled by default while preserving damage, bleeding and ordinary blood effects.
- Organize settings into Player status, Combat, Exploration and Controls, keeping each panel's related controls together and Logging last.
- Correct the health hold tooltip to show the 0.2% healing threshold.

## 0.0.0

- Configurable opacity for 17 HUD panels with contextual resource alerts, quickslot reveals, time reveals and manual HUD peek.
- Hide enemy health bars, names, difficulty icons and running prompts; independently configure four combat cues and cue size.
- Support Framecore 2b with the bundled native HUD bridge and optional Mod Setting Menu or manual settings.ini configuration.
- Keep HUD visibility controls in one section and ignore minor blood fluctuations when refreshing health alerts.
- Lower the health and blood regeneration reveal threshold from 1% to 0.2% of the bar, so smaller gains show the panel and refresh its health alert timer.
- Add an independent Hide enemy health bars toggle to restore ordinary enemy and boss health bars, end caps and boss phase indicators while preserving separate name and difficulty-icon settings.

## Earlier development

- Add Hide enemy health bars, an independent setting to restore ordinary enemy and boss health bars, end caps and boss health-phase indicators. Names and difficulty icons retain their separate toggles.

- Lower the health and blood regeneration reveal threshold from 1% to 0.2% of the bar, so smaller gains show the panel and refresh its health alert timer.

- Group settings by HUD panel, keeping related opacity, threshold and duration controls together. Retain a separate Combat cues section for indicators, warnings, the lock icon and cue size.

- Clarify that Mod Setting Menu is optional, with fresh-install defaults and manual settings.ini configuration instructions.

- Rename the mod to Quiet Dawn - Configurable HUD.

- Add separate toggles for unblockable warnings, directional parry cues and the lock icon alongside counterattack directions. All four default to Off.
- Hide the center dot and suppress center lock icons while showing directions.
- Add a common combat cue size slider from 10% to 200% in 10% steps, defaulting to 100%.

- Fix counterattack directions remaining hidden when combat icon changes bypass the marker event wrapper.

- Fix sprint/haste prompt event handling with the Framecore 2b native bridge.
- Preserve meaningful blood-loss alerts when smaller fluctuations arrive in the same event burst.
- Continue hiding available enemy-HUD elements when another child widget is unavailable.

- Reveal health for meaningful healing and briefly show completed regeneration, while ignoring small regeneration ticks and repeated near-full fluctuations.

- Add Show counterattack direction to reveal the weak-spot attack direction during counterattack openings, including after a perfect parry, while ordinary directional warnings keep their configured behavior.

- Keep the Toggle abilities hint hidden through its Focus-mode animation and during HUD peek, while preserving ability switching and the prompt opacity setting.

- Hide Sprint and Haste running prompts by default, with a separate toggle in Mod Settings. Preserve other action prompts and support localized running labels.
- Limit all HUD timers to 0–10 seconds in 0.5-second steps. Zero disables the corresponding timed reveal; keep the existing defaults and independent health/stamina thresholds.

- Hide the quickslot switch hint through its combat animation, reveal item/ability quickslots briefly after switching with a configurable duration, and show the managed special-attack panel only while its cooldown is running. Prevent small blood fluctuations from endlessly renewing the health display.

- Hide the time-of-day panel by default and reveal it briefly when time advances. Add its 0–100% opacity slider in 5-point steps and a configurable reveal duration defaulting to 4 seconds after the last time change. Keep time reveals, health alerts and HUD peek independent.

- Add opacity sliders for all 16 managed player HUD panels, from 0% to 100% in 5-point steps. Zero retains Quiet Dawn's existing automatic behavior, including health and stamina alerts; positive values keep each panel shown at the selected opacity.

- Fix a crash during HUD hook initialization under Framecore 2b. Preserve object deletion and replacement checks without creating weak or soft references.

- Add a native HUD event bridge for Framecore 2b, supporting HUD hiding, resource alerts and manual peek with its Performance profile. Preserve brief resource drops, prioritize player alerts during event bursts, and refresh event bindings when HUD widgets are replaced.

- Include an optional one-click Blueprint hook setup script that edits only the required INI setting and backs up the original. Use the installed Framecore Performance template only when the active INI is missing.
- Include the exact hook-registration exception in Logging output once per hook per session.

- Restore HUD hiding after death-screen reloads when old HUD objects have been destroyed or replaced.

- Restore HUD and enemy-information hiding when loading notifications are missed or player attributes become ready after the first initialization attempt.

- Display compass opacity and visibility thresholds as percentages, explain when resource displays stay visible, and use direct On/Off visibility values.

- Simplify diagnostics to a single Logging switch at the end of Mod Settings.
- Clarify HUD hold durations and default controls. HUD visibility switches now show On for visible and Off for hidden; compass opacity alone controls compass visibility.

- Fix the Mod Settings "config key missing or ambiguous" error when opening Quiet Dawn before loading a save after an upgrade.

- Hide enemy names and difficulty icons by default. Add independent Mod Settings toggles to restore either, and preserve older settings files when adding the new defaults.

- Add a 3-second full player HUD peek on the existing Controls Legend hold gesture (Menu/Options on standard controller layouts). Refresh on another hold and restore automatic visibility afterward, keeping low health visible.

- Show health alerts at full opacity, including when the stat panels start transparent. Keep health visible below 50% and extend health/blood-loss reveals to 4 seconds; stamina retains its 20% threshold and 1.5-second delay.
- Follow the blood bar in vampire form and HP in human form. Handle overdrinking, form changes and blood-bar capacity changes.
- Listen to the stat widgets' actual update functions as well as resource event handlers, covering direct event-graph updates without polling.

- Replace periodic health/stamina checks with resource-change hooks and a cached-state hide deadline. Preserve rapid loss/recovery events and stop all resource timers after the hold settles.

- Read the actual Directional Indicator menu setting instead of the widget's separate internal display toggle. Refresh cached markers on setting changes so enabling indicators restores a previously hidden widget.

- Restore the shared marker/directional widget when directional indicators are enabled, including after changing the setting during play. Hide the neutral marker only while directions are disabled; preserve active combat cues.

- Set the optional Show Compass variant to 50 percent compass opacity.

- Compare Unreal object addresses instead of Lua wrapper identity throughout HUD ownership, marker ownership, panel caching, and player-state tracking. This fixes false world mismatches that prevented initialization.
- Separate HUD ownership acceptance from resource reads to keep their native work on separate frames.

- Fix HUD ownership retries stopping after the first unsuccessful attempt, leaving HUD and neutral marker hiding uninitialized.
- Retain early marker construction events until HUD initialization and retry delayed marker ownership with a finite budget. Add readiness diagnostics; preserve combat cues and difficulty rules.

- Hide the neutral enemy lock-on marker while preserving active cues on its shared widget.
- Add bounded event-driven marker updates to the existing worker; no new polling timer or difficulty override.

- Reduce resource show/hide updates to the two stat panels; reuse the event result and cache missing fields until lifecycle/preset changes.
- Keep pending panel updates progressing during resource-event bursts.
- Stop resource reads entirely when neither stat panel is configured.

- Keep general HUD hidden during combat, weapon draw, lock-on, and focus.
- Reveal the combined health/stamina panel after either resource drops for 1.5 seconds, or while either remains strictly below 20%.
- Preserve native enemy health and difficulty-controlled parry/attack indicators.
- Replace broad reveal controls with configurable resource thresholds and hold durations; remove F8 whole-HUD reveal.
- Add bounded 100 ms player-resource sampling, terminating on invalid contexts.

- Renamed display title to Quiet Dawn HUD - Auto-hide HUD.
- Added a complete optional Show Compass package that leaves compass visibility to the game.

- Initial standalone event-driven HUD implementation.
- Six optional persistent panels hidden while idle; combat, stance, lock-on, focus, and manual reveal support.
- Bounded initialization and panel updates, with no permanent worker after setup.

- Standardize the debug logging setting as `debugLogging`; retain existing configuration compatibility.
