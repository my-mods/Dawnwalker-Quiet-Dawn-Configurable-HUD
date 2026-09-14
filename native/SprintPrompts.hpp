// Quiet Dawn - Configurable HUD. MIT.
#pragma once
namespace RC::LuaMadeSimple { class Lua; }
namespace QuietDawn::SprintPrompts {
void registerLua(RC::LuaMadeSimple::Lua&);
void stop() noexcept;
void shutdown() noexcept;
}
