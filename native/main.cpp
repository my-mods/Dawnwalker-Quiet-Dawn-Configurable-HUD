// Quiet Dawn - Configurable HUD. MIT.
// SDK: RE-UE4SS 97b7e501c / UEPseudo eb40a05f. Framecore 2b only.
#include <Mod/CppUserModBase.hpp>
#include <Mod/LuaMod.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <DynamicOutput/Output.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UnrealInitializer.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <Unreal/UObjectArray.hpp>
#include <Unreal/Core/Windows/AllowWindowsPlatformTypes.hpp>
#include <Windows.h>
#include <bcrypt.h>
#include <array>
#include <atomic>
#include <fstream>
#include <mutex>
#include <cstring>
#include "EventQueue.hpp"

// Public exported declaration in LuaType/LuaUObject.hpp. Keep its heavy
// template implementation out of this translation unit; conversion belongs
// to the host DLL and its registered Lua state.
namespace RC::LuaType {
RC_UE4SS_API void auto_construct_object(const LuaMadeSimple::Lua&, Unreal::UObject*);
}
namespace {
using namespace RC;
using namespace RC::Unreal;
using Lua = LuaMadeSimple::Lua;
using QuietDawn::Event;

static_assert(offsetof(LuaMod,m_main_lua)==0x90 && offsetof(LuaMod,m_async_lua)==0x98);
static_assert(offsetof(LuaMod,m_pending_actions)==0xa0 && sizeof(LuaMod::AsyncAction)==24);
static_assert(sizeof(CppUserModBase)==192);
static_assert(offsetof(UnrealInitializer::Config,bHookProcessLocalScriptFunction)==0x3fa);
static_assert(sizeof(Hook::FCallbackOptions)==72);

enum class Kind { Context, Resource, Entry };
struct Spec { const wchar_t* path; Kind kind{Kind::Context}; int entry{}; };
#define HUD L"/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:"
#define HUMAN L"/Game/_Dawnwalker/UI/_Unified/HUD/PlayerStatPanel/WBP_HUD_HumanStats.WBP_HUD_HumanStats_C:"
#define VAMPIRE L"/Game/_Dawnwalker/UI/_Unified/HUD/PlayerStatPanel/WBP_HUD_VampireStats.WBP_HUD_VampireStats_C:"
#define MARKER L"/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C:"
#define ENEMY L"/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatCharacterBar.WBP_CombatCharacterBar_C:"
constexpr std::array specs{
    Spec{HUD L"Construct"}, Spec{HUD L"BP_OnActivated"}, Spec{HUD L"On Coen Form Changed"}, Spec{HUD L"Update Shown Stat Bar"},
    Spec{HUMAN L"On HP changed",Kind::Resource}, Spec{HUMAN L"UpdateHealthBar"},
    Spec{VAMPIRE L"On HP changed",Kind::Resource}, Spec{VAMPIRE L"On Stamina changed",Kind::Resource}, Spec{VAMPIRE L"Update Blood"},
    Spec{L"/Game/_Dawnwalker/UI/_Unified/HUD/ControlsLegend/WBP_ControlsLegend.WBP_ControlsLegend_C:ExecuteUbergraph_WBP_ControlsLegend",Kind::Entry,850},
    Spec{MARKER L"Construct"}, Spec{MARKER L"EnableHardLock"}, Spec{MARKER L"NotifyIndicatorCleared"},
    Spec{MARKER L"OnObservedStubIconTypeChanged"}, Spec{MARKER L"RefreshIndicatorsVisibility"}, Spec{MARKER L"ToggleShowOnlyMiddleIndicator"},
    Spec{ENEMY L"Construct"}, Spec{ENEMY L"UpdateTarget"},
    Spec{L"/Game/_Dawnwalker/UI/_Unified/Combat/WBP_Combat_BossBar.WBP_Combat_BossBar_C:Update Owner"},
    Spec{L"/Game/_Dawnwalker/UI/_Unified/HUD/Timer/WBP_HudTimer.WBP_HudTimer_C:ExecuteUbergraph_WBP_HudTimer",Kind::Entry,455},
    Spec{L"/Game/_Dawnwalker/UI/_Unified/HUD/AbilityCooldowns/WBP_HUD_SpecialAttackCooldown.WBP_HUD_SpecialAttackCooldown_C:SetupCooldownEffect"},
    Spec{L"/Game/_Dawnwalker/UI/_Unified/HUD/AbilityCooldowns/WBP_HUD_SpecialAttackCooldown.WBP_HUD_SpecialAttackCooldown_C:OnCooldownFinished"},
    Spec{HUD L"ExecuteUbergraph_WBP_GameHUD",Kind::Entry,4146},
    // The prompt worker reads the current HUD prompts after delivery. None of
    // this event's parameters are resource scalars or need to be captured.
    Spec{HUD L"OnSetInputPromptEnabled"},
    // Observe the icon render helpers as well as the event wrappers: native
    // graph dispatch can skip the wrappers. Lua must not call these helpers.
    Spec{MARKER L"Display Icon State Directionally"},
    Spec{MARKER L"Display Icon State Non-Directionally"}
};
struct Scalar { int offset{}, bytes{}; };
struct Binding { UFunction* node{}; QuietDawn::ObjectIdentity identity; std::array<Scalar,2> params{}; };
struct State final: FUObjectDeleteListener {
    std::mutex mutex;
    std::atomic_bool active{};
    bool debug{}, pending{};
    LuaMod* mod{};
    int actionRef{LUA_NOREF};
    Hook::GlobalCallbackId hook{Hook::ERROR_ID};
    std::array<Binding,specs.size()> bindings{};
    // Mutated/read only on the game thread. The inactive fast exit is atomic.
    std::array<int,64> table{};
    QuietDawn::EventQueue queue;
    QuietDawn::ObjectInterest bindingInterest;
    bool listening{};
    uint64_t matched{}, delivered{}, stale{}, failures{}, nanos{};
    void NotifyUObjectDeleted(const UObjectBase* object,int32 index) override {
        if (!active.load(std::memory_order_acquire) ||
            (!bindingInterest.contains(index) && !queue.mayContain(index))) return;
        // This callback can run during GC: compare owned values only. No Lua,
        // UObject access, allocation, reflection, logging, or object-array scan.
        std::lock_guard lock(mutex);
        const auto address=reinterpret_cast<uintptr_t>(object);
        for(auto& binding:bindings) if(binding.identity.invalidate(index,address)) {
            bindingInterest.remove(index);
            if(debug) ++stale;
        }
        const auto removed=queue.invalidate(index,address);
        if(debug) stale+=removed;
    }
    void OnUObjectArrayShutdown() override {
        active=false;
        detach();
        std::lock_guard lock(mutex);
        queue.clear();bindingInterest.clear();pending=false;
        for(auto& binding:bindings) binding.identity={};
    }
    void attach() {
        if(!listening) { FUObjectArray::AddUObjectDeleteListener(this);listening=true; }
    }
    void detach() {
        if(listening) { FUObjectArray::RemoveUObjectDeleteListener(this);listening=false; }
    }
};
std::shared_ptr<State> current;
void gameThread() { if (!IsInGameThread()) throw std::runtime_error("Quiet Dawn native operation requires the game thread"); }
QuietDawn::ObjectIdentity identify(UObject* object) {
    if(!object) return {};
    const auto index=object->GetInternalIndex();
    auto item=FUObjectArray::IndexToObject(index);
    if(!item || item->GetUObject()!=object || !FUObjectArray::IsValid(item,false)) return {};
    // Read an existing serial; never ask UE4SS to allocate one. Its allocation
    // fallback converts a soft reference and crashes on this runtime/game.
    return {reinterpret_cast<uintptr_t>(object),index,item->GetSerialNumber()};
}
UObject* resolve(const QuietDawn::ObjectIdentity& identity) {
    if(!identity.address) return nullptr;
    auto item=FUObjectArray::IndexToObject(identity.index);
    if(!item || !FUObjectArray::IsValid(item,false)) return nullptr;
    auto object=item->GetUObject();
    return identity.matches(reinterpret_cast<uintptr_t>(object),item->GetSerialNumber()) ? object : nullptr;
}
size_t bucket(UFunction* p) { auto n=reinterpret_cast<uintptr_t>(p)>>4; return (n^(n>>13))&63; }
double readScalar(const uint8_t* locals, Scalar s) {
    if (s.bytes==8) { double v; std::memcpy(&v,locals+s.offset,8); return v; }
    float v; std::memcpy(&v,locals+s.offset,4); return v;
}
void captureFailure(const std::shared_ptr<State>& state,int id,const char* reason) noexcept {
    state->active=false;
    try {
        bool debug;
        { std::lock_guard lock(state->mutex); ++state->failures; state->queue.clear(); state->pending=false; debug=state->debug; }
        if (debug) {
            StringType message=STR("[Quiet Dawn native] Capture stopped for ");
            message+=id ? specs[id-1].path : STR("dispatch");message+=STR(": ");
            message.append(reason,reason+std::strlen(reason));message+=STR("\n");
            Output::send(StringViewType(message));
        }
    } catch (...) {} // Error reporting must not unwind through the engine.
}
void capture(const std::shared_ptr<State>& state, UObject* object, FFrame& stack) noexcept {
    // No names, reflection, allocations, locks, or Lua calls on the miss path.
    if (!state->active.load(std::memory_order_acquire) || !IsInGameThreadRaw()) return;
    int id{};
    try {
    auto node=stack.Node();
    for (size_t n=0, at=bucket(node); n<state->table.size(); ++n,at=(at+1)&63) {
        const int slot=state->table[at];
        if (!slot) return;
        if (state->bindings[slot-1].node==node) { id=slot; break; }
    }
    if (!id) return;
        std::lock_guard lock(state->mutex);
        if (!state->active.load() || !state->mod || state->actionRef==LUA_NOREF) return;
        const auto start=state->debug ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
        const auto& binding=state->bindings[id-1];
        if (resolve(binding.identity)!=node || !object) { if (state->debug) ++state->stale; return; }
        auto kind=specs[id-1].kind;
        Event event; event.id=id; event.priority=id<=10 || id>=20;
        if (kind!=Kind::Context) {
            const auto locals=stack.Locals(); if (!locals) return;
            if (kind==Kind::Entry) {
                int entry; std::memcpy(&entry,locals+binding.params[0].offset,4);
                if (entry!=specs[id-1].entry) return;
                event.value=entry;
            } else {
                event.resource=true;
                event.value=readScalar(locals,binding.params[0]);
                event.previous=readScalar(locals,binding.params[1]);
                if (event.value==event.previous) return;
            }
        }
        const auto identity=identify(object);
        if(!identity.address) { if(state->debug) ++state->stale;return; }
        event.index=identity.index;event.serial=identity.serial;event.address=identity.address;
        state->queue.push(event);
        if (state->debug) ++state->matched;
        if (!state->pending) {
            // Same host-owned action queue used by ExecuteAsync. Never touch
            // Lua from a native detour or create another interpreter/thread.
            auto mod=state->mod;
            mod->actions_lock();
            try { mod->m_pending_actions.emplace_back(LuaMod::AsyncAction{state->actionRef,LuaMod::ActionType::Immediate}); }
            catch (...) { mod->actions_unlock(); throw; }
            mod->actions_unlock();
            state->pending=true;
        }
        if (state->debug) state->nanos+=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-start).count();
    } catch (const std::exception& error) { captureFailure(state,id,error.what()); }
    catch (...) { captureFailure(state,id,"non-standard native exception"); }
}
int bind(State& state, std::string_view path) {
    gameThread();
    const StringType wide(path.begin(),path.end());
    size_t id=0;
    for (;id<specs.size();++id) if (wide==specs[id].path) break;
    if (id==specs.size()) throw std::runtime_error("Blueprint function is outside Quiet Dawn's native hook list");
    auto& binding=state.bindings[id];
    if (binding.node && resolve(binding.identity)==binding.node) return static_cast<int>(id+1);
    auto node=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,wide);
    if (!node) throw std::runtime_error("Blueprint UFunction is not loaded");
    if (node->HasAnyFunctionFlags(EFunctionFlags::FUNC_Native)) throw std::runtime_error("Expected a Blueprint function");
    std::array<Scalar,2> params{};
    if (specs[id].kind!=Kind::Context) {
        size_t n=0, needed=specs[id].kind==Kind::Entry ? 1 : 2;
        for (auto prop:TFieldRange<FProperty>(node,EFieldIterationFlags::IncludeDeprecated)) {
            if (!prop->HasAnyPropertyFlags(EPropertyFlags::CPF_Parm) || prop->HasAnyPropertyFlags(EPropertyFlags::CPF_ReturnParm)) continue;
            if (n>=needed) break;
            if (prop->HasAnyPropertyFlags(EPropertyFlags::CPF_OutParm)) throw std::runtime_error("Unexpected output parameter in HUD event");
            const auto type=prop->GetClass().GetFName().ToString();
            const int bytes=type==STR("DoubleProperty") ? 8 : type==STR("FloatProperty") ? 4 : 0;
            if (specs[id].kind==Kind::Entry ? type!=STR("IntProperty") : !bytes) throw std::runtime_error("HUD parameter type differs from the supported signature");
            const int offset=prop->GetOffset_Internal(), width=specs[id].kind==Kind::Entry ? 4 : bytes;
            if (offset<0 || offset+width>node->GetParmsSize()) throw std::runtime_error("HUD parameter lies outside its parameter block");
            params[n++]={offset,width};
        }
        if (n!=needed) throw std::runtime_error("Missing HUD event parameters");
    }
    const auto identity=identify(node);
    if(!identity.address) throw std::runtime_error("Blueprint UFunction is no longer valid");
    if(binding.identity.address) state.bindingInterest.remove(binding.identity.index);
    binding={node,identity,params};
    state.bindingInterest.add(identity.index);
    // Rebuild this tiny pointer table only when binding a loaded function.
    state.table.fill(0);
    for (size_t n=0;n<state.bindings.size();++n) if (auto p=state.bindings[n].identity.address ? state.bindings[n].node : nullptr) {
        size_t at=bucket(p); while(state.table[at]) at=(at+1)&63;
        state.table[at]=static_cast<int>(n+1);
    }
    return static_cast<int>(id+1);
}
bool supportedRuntime() {
    wchar_t path[32768]; auto module=GetModuleHandleW(L"UE4SS.dll");
    auto length=GetModuleFileNameW(module,path,32768);
    if (!module || !length || length==32768) return false;
    std::ifstream file(std::filesystem::path(path),std::ios::binary);
    if (!file) return false;
    BCRYPT_ALG_HANDLE algorithm{}; BCRYPT_HASH_HANDLE hash{};
    if (BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)<0) return false;
    std::array<unsigned char,32> digest{}; bool ok=false;
    if (BCryptCreateHash(algorithm,&hash,nullptr,0,nullptr,0,0)>=0) {
        std::array<char,65536> data{}; bool valid=true;
        while (file.read(data.data(),data.size()) || file.gcount())
            if (BCryptHashData(hash,reinterpret_cast<PUCHAR>(data.data()),static_cast<ULONG>(file.gcount()),0)<0) {valid=false;break;}
        ok=valid && file.eof() && BCryptFinishHash(hash,digest.data(),digest.size(),0)>=0;
        BCryptDestroyHash(hash);
    }
    BCryptCloseAlgorithmProvider(algorithm,0);
    constexpr std::array<unsigned char,32> expected{0xfb,0x18,0x39,0xee,0x91,0xf7,0x1f,0x83,0xd5,0x08,0xd4,0x4a,0x27,0x63,0xa1,0x5a,0xc1,0xbb,0x0c,0x5f,0xb4,0xe5,0x04,0xac,0x0f,0xcf,0xca,0x64,0x37,0x6a,0x05,0x4a};
    return ok && digest==expected;
}
class QuietDawnMod final: public CppUserModBase {
    std::shared_ptr<State> state=std::make_shared<State>();
public:
    QuietDawnMod() { ModName=STR("Quiet Dawn native HUD bridge"); ModVersion=STR("1"); ModAuthors=STR("oOCamilleOo_"); }
    void on_lua_start(StringViewType name,Lua& lua,Lua&,Lua&,Lua*) override {
        if (name!=STR("QuietDawnHUD")) return;
        // Full-feature loader/profile: leave RegisterHook with its usual owner.
        if (!supportedRuntime() || UnrealInitializer::StaticStorage::GlobalConfig.bHookProcessLocalScriptFunction) return;
        auto s=state; current=s;
        s->mod=get_mod_ref(lua);
        lua.register_function("_QDNInit",[](const Lua& l) {
            auto s=current;
            if (!l.is_function()) throw std::runtime_error("Expected Quiet Dawn scheduler callback");
            std::lock_guard lock(s->mutex);
            if (s->actionRef!=LUA_NOREF) throw std::runtime_error("Native bridge already initialized");
            s->actionRef=l.registry().make_ref();
            return 0;
        });
        lua.register_function("_QDNBegin",[](const Lua& l) {
            auto s=current;
            gameThread(); const bool debug=l.get_bool();
            std::lock_guard lock(s->mutex);
            s->active=false; s->queue.clear(); s->pending=false; s->table.fill(0);
            s->bindingInterest.clear();
            for(auto& b:s->bindings) b=Binding{};
            s->attach();
            s->debug=debug; s->matched=s->delivered=s->stale=s->failures=s->nanos=0;
            s->queue.track=debug;
            s->queue.merged=s->queue.overflow=0;
            if (s->hook==Hook::ERROR_ID) {
                // Install the host's detour after its disabled Lua dispatcher
                // registration has already failed. This flag is restored even
                // on failure; no runtime INI or Framecore profile is edited.
                auto& flag=UnrealInitializer::StaticStorage::GlobalConfig.bHookProcessLocalScriptFunction;
                struct Restore { bool& flag; bool old; ~Restore(){flag=old;} } restore{flag,flag};
                flag=true;
                s->hook=Hook::RegisterProcessLocalScriptFunctionPostCallback(
                    [s](Hook::TCallbackIterationData<void>&,UObject* object,FFrame& stack,void*) { capture(s,object,stack); },
                    {false,true,STR("QuietDawnHUD"),STR("HUD events")});
                if (s->hook==Hook::ERROR_ID) throw std::runtime_error("Framecore could not install the native HUD dispatch hook");
            }
            s->active=true;
            return 0;
        });
        lua.register_function("_QDNSetLogging",[](const Lua& l) {
            gameThread();const bool debug=l.get_bool();auto s=current;
            std::lock_guard lock(s->mutex);
            if(s->debug!=debug) {
                s->debug=debug;s->queue.track=debug;
                s->matched=s->delivered=s->stale=s->failures=s->nanos=0;
                s->queue.merged=s->queue.overflow=0;
            }
            return 0;
        });
        lua.register_function("_QDNBind",[](const Lua& l) {
            auto s=current;
            gameThread(); const auto path=l.get_string();
            std::lock_guard lock(s->mutex); l.set_integer(bind(*s,path)); return 1;
        });
        lua.register_function("_QDNNext",[](const Lua& l) {
            auto s=current;
            gameThread(); Event event;
            { std::lock_guard lock(s->mutex); if (!s->active || !s->queue.pop(event)) return 0; }
            auto object=resolve({event.address,event.index,event.serial});
            { std::lock_guard lock(s->mutex); if (s->debug) {if(object) ++s->delivered;else ++s->stale;} }
            if (!object) { l.set_integer(0); return 1; }
            l.set_integer(event.id); LuaType::auto_construct_object(l,object);
            if (specs[event.id-1].kind==Kind::Context) { l.set_nil(); l.set_nil(); }
            else { l.set_number(event.value); l.set_number(event.previous); }
            return 4;
        });
        lua.register_function("_QDNMore",[](const Lua& l) {
            auto s=current;
            std::lock_guard lock(s->mutex);
            bool more=s->active && !s->queue.empty(); if (!more) s->pending=false;
            l.set_bool(more); return 1;
        });
        lua.register_function("_QDNStop",[](const Lua& l) {
            auto s=current;
            std::lock_guard lock(s->mutex); s->active=false; s->queue.clear(); s->pending=false;
            l.set_integer(s->matched); l.set_integer(s->delivered); l.set_integer(s->queue.merged);
            l.set_integer(s->queue.overflow); l.set_integer(s->stale); l.set_integer(s->failures); l.set_number(s->nanos/1e6);
            return 7;
        });
    }
    void on_lua_stop(StringViewType name,Lua&,Lua&,Lua&,Lua*) override {
        if (name!=STR("QuietDawnHUD")) return;
        std::lock_guard lock(state->mutex); state->active=false; state->mod=nullptr;
        state->actionRef=LUA_NOREF; state->queue.clear(); state->pending=false;
    }
    ~QuietDawnMod() override {
        state->active=false;
        if(state->hook!=Hook::ERROR_ID) Hook::UnregisterCallback(state->hook);
        state->detach();
    }
};
}
extern "C" __declspec(dllexport) RC::CppUserModBase* start_mod() { return new QuietDawnMod; }
extern "C" __declspec(dllexport) void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
