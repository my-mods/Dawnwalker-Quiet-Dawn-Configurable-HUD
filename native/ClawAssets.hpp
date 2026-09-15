// Quiet Dawn - Configurable HUD. MIT.
#pragma once
namespace RC::LuaMadeSimple { class Lua; }
namespace QuietDawn::ClawAssets {
void registerLua(RC::LuaMadeSimple::Lua&);
void shutdown() noexcept;
}
