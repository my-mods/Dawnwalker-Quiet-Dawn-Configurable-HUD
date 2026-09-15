// Quiet Dawn - Configurable HUD. MIT.
// Retain only the two validated cue defaults and their original VFX. No hooks,
// asset loading, property writes, object scans or weak-reference construction.
#include "ClawAssets.hpp"
#include "ObjectIdentity.hpp"
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <DynamicOutput/Output.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObjectArray.hpp>
#include <Unreal/UnrealInitializer.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <array>
#include <mutex>
#include <stdexcept>

namespace QuietDawn::ClawAssets {
namespace {
using namespace RC;
using namespace RC::Unreal;
using Lua=LuaMadeSimple::Lua;
constexpr std::array cuePaths{
 L"/Game/_Dawnwalker/Stats/GameplayCues/Shred/GC_ShredBleedingInflicted.Default__GC_ShredBleedingInflicted_C",
 L"/Game/_Dawnwalker/Stats/GameplayCues/Shred/GC_ShredBleedingInflicted_Sword.Default__GC_ShredBleedingInflicted_Sword_C"};
constexpr std::array classPaths{
 L"/Game/_Dawnwalker/Stats/GameplayCues/Shred/GC_ShredBleedingInflicted.GC_ShredBleedingInflicted_C",
 L"/Game/_Dawnwalker/Stats/GameplayCues/Shred/GC_ShredBleedingInflicted_Sword.GC_ShredBleedingInflicted_Sword_C"};
constexpr std::array effectPaths{
 L"/Game/_Dawnwalker/VFX/03_ShreddedTouch/NS_Shred_Slash.NS_Shred_Slash",
 L"/Game/_Dawnwalker/VFX/03_ShreddedTouch/NS_Shred_Sword.NS_Shred_Sword"};
void require(bool value,const char* reason) { if(!value) throw std::runtime_error(reason); }
ObjectIdentity identify(UObject* object) {
 if(!object) return {};
 const auto index=object->GetInternalIndex();auto item=FUObjectArray::IndexToObject(index);
 if(!item || !FUObjectArray::IsValid(item,false) || item->GetUObject()!=object) return {};
 return {reinterpret_cast<uintptr_t>(object),index,item->GetSerialNumber()};
}
FUObjectItem* resolve(const ObjectIdentity& id) {
 if(!id.address) return nullptr;
 auto item=FUObjectArray::IndexToObject(id.index);
 return item && FUObjectArray::IsValid(item,false) &&
   id.matches(reinterpret_cast<uintptr_t>(item->GetUObject()),item->GetSerialNumber()) ? item : nullptr;
}
struct Pin { ObjectIdentity id; bool added{}; };
struct Lease { std::array<Pin,2> pins{}; int64_t token{}; };
struct State final: FUObjectDeleteListener {
 std::recursive_mutex mutex;
 std::array<Lease,2> leases{};
 ObjectInterest interest;
 int64_t sequence{};
 bool listening{};
 void detachIfUnused() {
  if(listening && !leases[0].token && !leases[1].token) {
   FUObjectArray::RemoveUObjectDeleteListener(this);listening=false;
  }
 }
 void NotifyUObjectDeleted(const UObjectBase* object,int32 index) override {
  if(!interest.contains(index)) return;
  std::lock_guard lock(mutex);
  for(auto& lease:leases) for(auto& pin:lease.pins)
   if(pin.id.invalidate(index,reinterpret_cast<uintptr_t>(object))) {interest.remove(index);pin.added=false;}
 }
 void OnUObjectArrayShutdown() override {
  std::lock_guard lock(mutex);leases={};interest.clear();
  if(listening) {FUObjectArray::RemoveUObjectDeleteListener(this);listening=false;}
 }
 void release(Lease& lease) {
  for(auto& pin:lease.pins) {
   if(auto item=resolve(pin.id);item && pin.added) item->UnsetRootSet();
   if(pin.id.address) interest.remove(pin.id.index);
   pin={};
  }
  lease.token=0;
 }
} state;
int64_t retain(int slot,uintptr_t cueAddress,uintptr_t effectAddress) {
 require(slot>=1 && slot<=2,"Unknown claw asset slot");
 std::lock_guard lock(state.mutex);auto& lease=state.leases[slot-1];
 if(lease.token && resolve(lease.pins[0].id) && resolve(lease.pins[1].id)) {
  require(lease.pins[0].id.address==cueAddress && lease.pins[1].id.address==effectAddress,"Claw asset lease already owned");
  return lease.token;
 }
 // Resolve trusted constant paths before comparing caller-provided addresses.
 auto cue=UObjectGlobals::StaticFindObject<UObject*>(nullptr,nullptr,cuePaths[slot-1]);
 auto effect=UObjectGlobals::StaticFindObject<UObject*>(nullptr,nullptr,effectPaths[slot-1]);
 std::array ids{identify(cue),identify(effect)};
 require(ids[0].address && ids[1].address && ids[0].address==cueAddress && ids[1].address==effectAddress,"Claw asset identity changed");
 require(cue->HasAnyFlags(RF_ClassDefaultObject) && cue->GetClassPrivate()->GetPathName()==classPaths[slot-1]
   && effect->GetClassPrivate()->GetPathName()==STR("/Script/Niagara.NiagaraSystem"),"Unexpected claw asset type");
 if(!state.listening) {FUObjectArray::AddUObjectDeleteListener(&state);state.listening=true;}
 state.release(lease);
 try {
  for(size_t i=0;i<ids.size();++i) {
   auto item=resolve(ids[i]);require(item,"Claw asset expired before retention");
   lease.pins[i]={ids[i],!item->IsRootSet()};state.interest.add(ids[i].index);
   if(lease.pins[i].added) item->SetRootSet();
   require(item->IsRootSet(),"Claw asset retention failed");
  }
  lease.token=++state.sequence;return lease.token;
 } catch(...) {state.release(lease);state.detachIfUnused();throw;}
}
}
void registerLua(RC::LuaMadeSimple::Lua& lua) {
 lua.register_function("_QDNClawRetain",[](const Lua& l) {
  require(IsInGameThread(),"Claw asset retention requires the game thread");
  const auto slot=l.get_integer();const auto cue=l.get_integer();const auto effect=l.get_integer();
  require(slot>=1 && slot<=2,"Unknown claw asset slot");
  l.set_integer(retain(static_cast<int>(slot),static_cast<uintptr_t>(cue),static_cast<uintptr_t>(effect)));return 1;
 });
 lua.register_function("_QDNClawRelease",[](const Lua& l) {
  require(IsInGameThread(),"Claw asset release requires the game thread");
  const auto slot=l.get_integer();const auto token=l.get_integer();
  require(slot>=1 && slot<=2,"Unknown claw asset slot");
  std::lock_guard lock(state.mutex);auto& lease=state.leases[slot-1];
  if(token && lease.token==token) state.release(lease);
  state.detachIfUnused();
  return 0;
 });
}
void shutdown() noexcept {
 // Normal session cleanup releases each lease after restoring its field.
 // During process teardown never dereference game objects from another thread.
 std::lock_guard lock(state.mutex);
 if(IsInGameThread()) for(auto& lease:state.leases) state.release(lease);
 if(state.listening) {FUObjectArray::RemoveUObjectDeleteListener(&state);state.listening=false;}
 state.leases={};state.interest.clear();
}
}
