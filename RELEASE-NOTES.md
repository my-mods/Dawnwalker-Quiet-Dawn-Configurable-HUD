# Quiet Dawn - Configurable HUD

- Add independent size sliders for all 17 player HUD panels: 25% to 200% in 5% steps, default 100%, with screen-edge alignment.

- Correct the health hold tooltip to show the 0.2% healing threshold.

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

Reveal health for meaningful healing and briefly show completed regeneration, while ignoring small regeneration ticks and repeated near-full fluctuations.

- Add Show counterattack direction to reveal the weak-spot attack direction during counterattack openings, including after a perfect parry, while ordinary directional warnings keep their configured behavior.

- Keep the Toggle abilities hint hidden through its Focus-mode animation and during HUD peek, while preserving ability switching and the prompt opacity setting.

- Hide Sprint and Haste running prompts by default. A separate Mod Settings toggle restores them; other action prompts retain game behavior.

Limit all HUD timers to 0–10 seconds in 0.5-second steps. Zero disables the corresponding timed reveal; keep the existing defaults and independent health/stamina thresholds.

Hide the quickslot switch hint through its combat animation, reveal item/ability quickslots briefly after switching with a configurable duration, and show the managed special-attack panel only while its cooldown is running. Prevent small blood fluctuations from endlessly renewing the health display.

Hide the time-of-day panel by default and reveal it briefly when time advances. Add its 0–100% opacity slider in 5-point steps and a configurable reveal duration defaulting to 4 seconds after the last time change. Keep time reveals, health alerts and HUD peek independent.

Add opacity sliders for all 16 managed player HUD panels, from 0% to 100% in 5-point steps. Zero retains Quiet Dawn's existing automatic behavior, including health and stamina alerts; positive values keep each panel shown at the selected opacity.

Add a native HUD event bridge for Framecore 2b's Performance profile. HUD hiding, resource alerts and manual peek use filtered native events, with player alerts preserved during enemy-widget bursts and event bindings refreshed after widget replacement.

Fix the crash during native HUD hook initialization when an object has no serial number. Preserve deletion and replacement handling without constructing weak or soft references.

Include an optional one-click Blueprint hook setup script that changes only the required INI setting and backs up the original. Logging now reports the exact hook-registration exception once per hook per session.

Fix HUD visibility after choosing Load last save on the death screen when the previous HUD has been destroyed or replaced.

Restore HUD and enemy-information hiding after loads with missing loading notifications or delayed player initialization.

Enemy names and difficulty icons are now hidden by default. Separate Mod Settings toggles let you restore either independently.

Health and stamina now respond to resource-change events and the stat widgets' update functions without recurring stat checks. Alerts remain readable when stat panels were transparent during initialization. A cached-state deadline preserves the hide delay and rapid loss/recovery events.

Hold the Controls Legend button (Menu/Options on standard controller layouts) for a 3-second full player HUD peek. Repeating the gesture refreshes the timer. The peek restores automatic hiding afterward while retaining low-health alerts and the configured enemy HUD behavior.

The optional Show Compass variant displays the compass at 50% opacity. Standard and optional variants share the same HUD behavior and runtime code.

Combat, weapon draw, lock-on, and focus keep the general HUD hidden. Health and stamina appear together at full opacity for 4 seconds after health/blood loss or 1.5 seconds after stamina use. Health below 50% or stamina below 20% keeps them visible. Vampire alerts follow blood-bar fill, including after changing form or blood-bar capacity.

The neutral enemy lock-on marker hides when directional indicators are disabled. Enabling directions restores the shared widget immediately after the setting change is processed. Attack and parry-direction cues stay hidden while directional indicators are disabled. Unblockable and weak-spot cues retain game visibility rules. Enemy and boss health bars, end caps and boss health-phase indicators are hidden by default and can be restored with Hide enemy health bars.

Object-address comparisons correct false world mismatches during HUD initialization. Bounded readiness retries retain early marker events until player ownership is ready. Resource updates touch only the stat panels, and pending panel updates take priority over sampling at low frame rates.

Optional personal INI diagnostics use the debugLogging setting and report visibility changes and bounded timing summaries. Completed workers stop through explicitly chained one-shot callbacks.

Directional indicator restoration now follows the actual menu setting and refreshes cached markers on setting changes. The widget's internal display toggle no longer overrides the menu choice.
