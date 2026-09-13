# Building the native HUD bridge

Use Windows x64, Visual Studio 2022's MSVC v143 C++ tools, the Windows 10/11 SDK, Git, and CMake 3.25 or newer. Build **Release** with the shared C runtime (`/MD`). The reference build uses MSVC 19.44.35228 and Windows SDK 10.0.26100.0.

The engine headers require GitHub access to Re-UE4SS/UEPseudo through the linked Epic Games account. They are not included in this repository or the mod archive.

```bat
git clone https://github.com/UE4SS-RE/RE-UE4SS.git RE-UE4SS
git -C RE-UE4SS checkout 97b7e501c19d8b2b7c662feee73aaa0dc1f0a4d1
git -C RE-UE4SS submodule update --init deps/first/Unreal
cmake -S native -B .local/native-build -A x64 -DUE4SS_SDK=C:/path/to/RE-UE4SS
cmake --build .local/native-build --config Release
```

Run the CMake commands from the Quiet Dawn - Configurable HUD repository. CMake retrieves pinned public header dependencies. The output is `.local/native-build/Release/main.dll` with the Visual Studio generator, or `.local/native-build/main.dll` with Ninja. The package payload is `Data/QuietDawnHUD/dlls/main.dll`. Install the packaged mod through Vortex.

## Compatibility boundary

This bridge targets **UE4SS for BoD Framecore 2b**, DLL SHA-256 `fb1839ee91f71f83d508d44a2763a15ac1bb0c5fb4e504ac0fcfca64376a054a`. It checks the host DLL once before exposing its Lua adapter. It uses the regular Lua hook route when that profile already enables script dispatch, and does not activate its native route on another DLL hash.

The SDK pins RE-UE4SS `97b7e501c19d8b2b7c662feee73aaa0dc1f0a4d1` and UEPseudo `eb40a05f49509bdeb1ac39287032b60af585cca8`. `Framecore2b.def` lists only the host exports used by this bridge; it creates an import library, not a replacement UE4SS DLL. Update the source, ABI checks, import list and hash together when supporting another build. Matching export names alone is insufficient evidence of compatibility.

## Dispatch and lifetime

The helper registers one post-callback through UE4SS's own `ProcessLocalScriptFunction` detour after the disabled standard Lua dispatcher has failed registration. It temporarily enables the host's in-memory installation flag for that call and restores it immediately. No INI is written. The underlying engine interception still runs for Blueprint calls; the native pointer table rejects functions outside Quiet Dawn's fixed HUD list before acquiring a queue lock or entering Lua.

The prompt-enable event delivers only its HUD context; its parameters are never decoded as resource values. The allowlist includes the time widget's event graph. The native filter accepts only the time-change entry (455), excluding initialization, dialogue previews and animation updates before Lua delivery.

Matching events copy scalar parameters and object identities into a 128-event queue. The largest resource drop survives a coalesced recovery or subsequent smaller fluctuation; player HUD events take priority over enemy-widget bursts. One host async action schedules a game-thread delivery chain. It revalidates each object and dispatches at most four callbacks per frame. It uses the host's registered Lua states, object converter, action queue and action lock, and never calls Lua directly from a native detour.

Identities contain an opaque address, object index and the serial number already assigned by the engine. The bridge never allocates serial numbers or constructs UE4SS weak/soft references. A native object-deletion listener invalidates matching function identities and removes queued events before the address or index can be reused, including when the serial is zero. A small atomic interest filter rejects unrelated deletions; collisions receive an exact address/index check under the queue lock. Deletion callbacks perform no UObject reads, Lua calls or allocations. Game-thread delivery checks the indexed object, its validity flags and any captured nonzero serial before constructing a Lua wrapper. Shutdown removes the listener and clears pending identities.

Widget replacement triggers finite, coalesced function rebinding. A save/session change clears pending events and refreshes function identities. No background thread, continuous readiness timer, widget-tree walk or global UObject scan is added. The helper remains loaded until the game exits; live DLL/Lua reload is unsupported.

Logging uses Quiet Dawn's existing `debugLogging` setting. Session summaries include captured/delivered/coalesced/dropped events, stale identities, failures and aggregate native capture time. Frame-time impact must be measured in the game; counts and compilation do not measure FPS.

## Credits

The native integration uses [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), its UE adaptation headers, and Framecore's exported callback implementation. The build also uses fmt headers. License notices are included under `LICENSES/` in the mod repository and archive. ImGui, ImGuiColorTextEdit and Zydis/Zycore headers are required transitively by the UE4SS SDK; their implementations are not linked into this DLL.

The fixed allowlist has 27 functions. IDs 25 and 26 observe the combat marker's directional and non-directional icon render helpers, covering changes that bypass event wrappers. Gameplay reads the resulting icon state and applies the independent cue visibility, arrow styling and size settings in Lua. It never calls these hooked render helpers during an active session. After hooks detach, session cleanup can redraw the current stock icon to restore brush and color. ID 27 observes the timer's Update Time Display helper without decoding its DayTime parameter. Lua compares GetCurrentDay and GetCurrentDayTimeAsFloat from the cached TimeSystemImpl on HUD display events, retaining only numbers. The initial snapshot does not reveal the panel. Hidden-HUD reveals resume through existing preset/activation callbacks. Special-attack setup/finish use context-only events; the panel reads the stock cooldown display after delivery. Quickslot switching filters WBP_GameHUD graph entry 4146 before queueing; the Controls Legend filter remains entry 850. These entry offsets are verified in Steam build 25232147 assets and must be rechecked after asset changes. The Lua adapter bounds rebinding by the highest registered allowlist ID. No cooldown-update or Tick subscription is added.

## Live settings API

`_QDNSetLogging(enabled)` runs on the game thread and changes diagnostics under the existing queue mutex. It resets diagnostic counters when the flag changes while preserving queued events, event ownership, active hook bindings and delivery scheduling. The persistent Lua bridge uses this function for Logging Apply, without calling begin/stop.

Mod Setting Menu 1.0.6+ requires `HookProcessConsoleExec=1` in the loader profile. The mod archive does not supply that global INI.
