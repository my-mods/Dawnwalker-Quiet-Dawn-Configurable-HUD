// Quiet Dawn - Configurable HUD. MIT.
// Framecore 2b / game build 25232147. Reflected value operations preserve
// FText history and destroy array elements using the running engine's ABI.
#include "SprintPrompts.hpp"
#include "ObjectIdentity.hpp"
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <DynamicOutput/Output.hpp>
#include <Helpers/String.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObjectArray.hpp>
#include <Unreal/UnrealInitializer.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <Unreal/FString.hpp>
#include <array>
#include <atomic>
#include <chrono>
#include <mutex>
#include <algorithm>
#include <cstring>
#include <stdexcept>

namespace QuietDawn::SprintPrompts {
namespace {
using namespace RC;
using namespace RC::Unreal;
using Lua=LuaMadeSimple::Lua;
// Verified against Framecore 2b's callback-context constructor.
static_assert(sizeof(UnrealScriptFunctionCallableContext)==32);
static_assert(offsetof(UnrealScriptFunctionCallableContext,Context)==0);
static_assert(offsetof(UnrealScriptFunctionCallableContext,RESULT_DECL)==16);
static_assert(offsetof(UnrealScriptFunctionCallableContext,CallableId)==24);
constexpr std::array paths{
    L"/Game/_Dawnwalker/Player/Abilities/GA_OpenWorldSprint.GA_OpenWorldSprint_C",
    L"/Game/_Dawnwalker/Player/Abilities/GA_FastTravelHumanSprint.GA_FastTravelHumanSprint_C",
    L"/Game/_Dawnwalker/Player/Abilities/GA_FastTravelVampireSprint.GA_FastTravelVampireSprint_C"};
constexpr auto widgetPath=L"/Game/_Dawnwalker/UI/_Unified/Gameplay/InputPrompt/WBP_InputPrompt.WBP_InputPrompt_C";
constexpr auto inputTable=L"/Game/_Dawnwalker/Player/Input/ST_InputNames.ST_InputNames";

void require(bool condition,const char* message) { if(!condition) throw std::runtime_error(message); }
void gameThread() { require(IsInGameThread(),"Sprint prompt operation requires the game thread"); }
ObjectIdentity identify(UObject* object) {
    if(!object) return {};
    const auto index=object->GetInternalIndex();auto item=FUObjectArray::IndexToObject(index);
    if(!item || !FUObjectArray::IsValid(item,false) || item->GetUObject()!=object) return {};
    return {reinterpret_cast<uintptr_t>(object),index,item->GetSerialNumber()};
}
UObject* resolve(const ObjectIdentity& identity) {
    if(!identity.address) return nullptr;
    auto item=FUObjectArray::IndexToObject(identity.index);
    if(!item || !FUObjectArray::IsValid(item,false)) return nullptr;
    auto object=item->GetUObject();
    return identity.matches(reinterpret_cast<uintptr_t>(object),item->GetSerialNumber()) ? object : nullptr;
}
StringType type(FProperty* property) { return property ? property->GetClass().GetFName().ToString() : STR(""); }
FProperty* field(UStruct* owner,const wchar_t* name) {
    const FName wanted(name);
    for(auto property:TFieldRange<FProperty>(owner,EFieldIterationFlags::IncludeSuper | EFieldIterationFlags::IncludeDeprecated))
        if(property->GetFName()==wanted) return property;
    return nullptr;
}
void bounds(FProperty* property,int size) {
    require(property && property->GetArrayDim()==1 && property->GetSize()>0 &&
        property->GetOffset_Internal()>=0 && property->GetOffset_Internal()+property->GetSize()<=size,
        "Sprint prompt property lies outside its reflected owner");
}

    // Storage never leaves the synchronous pre/original/post call. No shallow
// TArray/FText copies, borrowed Lua values or saved raw game offsets.
struct Value {
    alignas(16) std::array<uint8_t,64> bytes{};
    FProperty* property{};
    void initialize(FProperty* p) {
        require(!property && p->GetSize()<=bytes.size() && p->GetMinAlignment()<=16,"Unsupported prompt value storage");
        p->InitializeValue(bytes.data());property=p;
    }
    void clear() {
        if(property) { property->DestroyValue(bytes.data());property=nullptr; }
    }
};
struct Frame {
    UObject* owner{};
    ObjectIdentity identity;
    int interestIndex{-1};
    FArrayProperty* property{};
    Value original,empty;
    bool changed{};
    bool finish() {
        // Another hook's replacement wins. Only undo our empty value.
        bool restored=false;
        if(changed && resolve(identity)==owner && property->Identical(property->ContainerPtrToValuePtr<void>(owner),empty.bytes.data(),0)) {
            property->CopyCompleteValue(property->ContainerPtrToValuePtr<void>(owner),original.bytes.data());
            require(property->Identical(property->ContainerPtrToValuePtr<void>(owner),original.bytes.data(),0),"Sprint prompt restoration readback failed");
            restored=true;
        }
        changed=false;original.clear();empty.clear();owner=nullptr;property=nullptr;identity={};
        return restored;
    }
};
struct State final:FUObjectDeleteListener {
    std::mutex mutex;
    std::atomic_bool enabled{},ready{},logging{};
    bool listening{},warned{};
    UFunction* show{};std::pair<int,int> hook{};
    FArrayProperty* array{};FBoolProperty* showFlag{};
    UFunction* query{};UObject* textLibrary{};
    std::array<FProperty*,4> queryFields{};
    FProperty *text{},*table{},*key{};FBoolProperty* result{};
    std::array<ObjectIdentity,4> owners{};
    ObjectInterest interest;
    std::array<Frame,8> frames{};size_t depth{},overflow{};
    uint64_t calls{},hidden{},restored{},failures{},nanos{};
    void NotifyUObjectDeleted(const UObjectBase* object,int32 index) override {
        if(!interest.contains(index)) return;
        std::lock_guard lock(mutex);
        for(auto& owner:owners) if(owner.invalidate(index,reinterpret_cast<uintptr_t>(object))) {
            ready=false;enabled=false;
        }
        for(auto& frame:frames) if(frame.identity.invalidate(index,reinterpret_cast<uintptr_t>(object))) {
            interest.remove(index);frame.interestIndex=-1;
        }
    }
    void OnUObjectArrayShutdown() override {
        enabled=false;ready=false;
        if(listening) { FUObjectArray::RemoveUObjectDeleteListener(this);listening=false; }
    }
    void fail(const char* reason) noexcept {
        enabled=false;
        if(!logging.load()) return;
        ++failures;
        if(warned) return;
        warned=true;
        try {
            StringType message=STR("[Quiet Dawn native] Sprint prompt suppression stopped: ");
            message.append(reason,reason+std::strlen(reason));message+=STR("\n");Output::send(StringViewType(message));
        } catch(...) {}
    }
} state;

void before(UnrealScriptFunctionCallableContext& context,void*) noexcept {
    if(!IsInGameThreadRaw()) return;
    if(!state.enabled.load() && state.depth==0) return;
    std::lock_guard lock(state.mutex);
    if(state.depth==state.frames.size() || state.overflow) { ++state.overflow;return; }
    auto& frame=state.frames[state.depth++];
    const bool track=state.logging.load();
    const auto start=track ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
    try {
        if(!state.enabled.load() || !state.ready.load()) return;
        if(track) ++state.calls;
        auto object=context.Context;
        const auto identity=identify(object);
        if(!identity.address || object->HasAnyFlags(static_cast<EObjectFlags>(RF_ClassDefaultObject | RF_ArchetypeObject))) return;
        if(!state.showFlag->GetPropertyValue(state.showFlag->ContainerPtrToValuePtr<void>(context.TheStack.Locals()))) return;
        const auto path=object->GetClassPrivate()->GetPathName();
        if(std::find(paths.begin(),paths.end(),path)==paths.end()) return;
        auto value=state.array->ContainerPtrToValuePtr<void>(object);
        FScriptArrayHelper array(state.array,value);
        const auto count=array.Num();
        require(count>=0 && count<=8,"Sprint prompt list exceeds the supported bound");
        if(!count) return;
        frame.owner=object;frame.identity=identity;frame.property=state.array;
        frame.interestIndex=identity.index;state.interest.add(identity.index);
        frame.original.initialize(state.array);frame.empty.initialize(state.array);
        state.array->CopyCompleteValue(frame.original.bytes.data(),value);
        require(state.array->Identical(frame.original.bytes.data(),value,0),"Sprint prompt snapshot readback failed");
        frame.changed=true; // Post cleanup covers a setter/readback exception.
        state.array->CopyCompleteValue(value,frame.empty.bytes.data());
        require(FScriptArrayHelper(state.array,value).Num()==0,"Sprint prompt suppression readback failed");
        if(track) ++state.hidden;
    } catch(const std::exception& error) { state.fail(error.what()); }
    catch(...) { state.fail("non-standard exception in prompt pre-callback"); }
    if(track) state.nanos+=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-start).count();
}
void after(UnrealScriptFunctionCallableContext&,void*) noexcept {
    if(!IsInGameThreadRaw()) return;
    if(!state.depth && !state.overflow) return;
    std::lock_guard lock(state.mutex);
    if(state.overflow) { --state.overflow;return; }
    if(!state.depth) return;
    auto& frame=state.frames[--state.depth];
    if(frame.interestIndex>=0) {state.interest.remove(frame.interestIndex);frame.interestIndex=-1;}
    try { const bool restored=frame.finish();if(restored && state.logging.load()) ++state.restored; }
    catch(const std::exception& error) { state.fail(error.what()); }
    catch(...) { state.fail("non-standard exception in prompt post-callback"); }
}

void prepare() {
    if(state.ready.load()) return;
    require(!state.show,"Sprint prompt metadata was invalidated; restart the game");
    auto owner=UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,STR("/Script/Dawnwalker.SprintAbility"));
    auto show=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,STR("/Script/Dawnwalker.SprintAbility:ShowPrompt"));
    auto query=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,STR("/Script/Engine.KismetTextLibrary:StringTableIdAndKeyFromText"));
    auto library=UObjectGlobals::StaticFindObject<UObject*>(nullptr,nullptr,STR("/Script/Engine.Default__KismetTextLibrary"));
    require(owner && show && query && library,"Native sprint prompt functions are not loaded");
    require(show->HasAnyFunctionFlags(FUNC_Native) && query->HasAnyFunctionFlags(FUNC_Native),"Expected native prompt functions");
    auto property=field(owner,L"PromptsArray");bounds(property,owner->GetPropertiesSize());
    require(type(property)==STR("ArrayProperty") && property->GetSize()==16,"Expected the sprint prompt array");
    auto array=static_cast<FArrayProperty*>(property);auto inner=array->GetInner();
    require(type(inner)==STR("StructProperty") && inner->GetElementSize()==0x58 && inner->GetArrayDim()==1,
        "Unexpected sprint prompt entry layout");
    auto structure=static_cast<FStructProperty*>(inner)->GetStruct();
    require(structure && structure->GetPathName()==STR("/Script/Dawnwalker.DWPromptQuery"),"Unexpected sprint prompt entry type");
    auto display=field(structure,L"DisplayText"),condition=field(structure,L"Query");
    bounds(display,structure->GetPropertiesSize());bounds(condition,structure->GetPropertiesSize());
    require(type(display)==STR("TextProperty") && type(condition)==STR("StructProperty"),"Unexpected sprint prompt members");
    auto conditionStructure=static_cast<FStructProperty*>(condition)->GetStruct();
    require(conditionStructure && display->GetSize()==16 && conditionStructure->GetPathName()==STR("/Script/GameplayTags.GameplayTagQuery"),
        "Unexpected sprint prompt text or condition type");
    FBoolProperty* flag{};int count=0;
    for(auto p:TFieldRange<FProperty>(show,EFieldIterationFlags::IncludeDeprecated)) if(p->HasAnyPropertyFlags(CPF_Parm)) {
        bounds(p,show->GetParmsSize());
        require(++count==1 && type(p)==STR("BoolProperty") && !p->HasAnyPropertyFlags(CPF_ReturnParm | CPF_OutParm),"Unexpected ShowPrompt signature");
        flag=static_cast<FBoolProperty*>(p);
    }
    require(flag,"Missing ShowPrompt enabled parameter");
    std::array<FProperty*,4> fields{};count=0;
    FProperty *text{},*table{},*key{};FBoolProperty* result{};
    require(query->GetParmsSize()>0 && query->GetParmsSize()<=256,"Unexpected text identity parameter block");
    for(auto p:TFieldRange<FProperty>(query,EFieldIterationFlags::IncludeDeprecated)) if(p->HasAnyPropertyFlags(CPF_Parm)) {
        require(count<fields.size(),"Unexpected text identity parameter count");bounds(p,query->GetParmsSize());
        fields[count++]=p;
        const auto kind=type(p);
        if(kind==STR("TextProperty") && !text) text=p;
        else if(kind==STR("NameProperty") && p->HasAnyPropertyFlags(CPF_OutParm) && !table) table=p;
        else if(kind==STR("StrProperty") && p->HasAnyPropertyFlags(CPF_OutParm) && !key) key=p;
        else if(kind==STR("BoolProperty") && p->HasAnyPropertyFlags(CPF_ReturnParm) && !result) result=static_cast<FBoolProperty*>(p);
        else throw std::runtime_error("Unexpected text identity signature");
    }
    require(count==4 && text && table && key && result && text->GetSize()==16 && table->GetSize()==sizeof(FName) && key->GetSize()==sizeof(FString),
        "Incomplete text identity signature");
    std::array<ObjectIdentity,4> identities{identify(owner),identify(show),identify(query),identify(library)};
    for(const auto& identity:identities) require(identity.address,"Native prompt metadata is invalid");
    if(!state.listening) { FUObjectArray::AddUObjectDeleteListener(&state);state.listening=true; }
    {
        std::lock_guard lock(state.mutex);
        state.owners=identities;state.interest.clear();for(const auto& identity:identities) state.interest.add(identity.index);
        state.array=array;state.showFlag=flag;state.query=query;state.textLibrary=library;
        state.queryFields=fields;state.text=text;state.table=table;state.key=key;state.result=result;
    }
    // This is a native UFunction hook, including native calls from Blueprint.
    // Neither the enabled argument nor the function's return is overwritten.
    state.hook=UObjectGlobals::RegisterHook(show,before,after,nullptr);
    state.show=show;state.ready=true;
}

bool match(std::string_view fullName,uintptr_t expectedAddress) {
    require(state.ready.load(),"Native prompt identity is not ready");
    const auto space=fullName.find(' ');require(space!=std::string_view::npos,"Expected full prompt object name");
    const auto path=fullName.substr(space+1);const StringType wide=to_wstring(path);
    auto widget=UObjectGlobals::StaticFindObject<UObject*>(nullptr,nullptr,wide);
    if(!identify(widget).address || reinterpret_cast<uintptr_t>(widget)!=expectedAddress) return false;
    if(widget->GetClassPrivate()->GetPathName()!=widgetPath) return false;
    auto property=field(widget->GetClassPrivate(),L"Prompt Text");bounds(property,widget->GetClassPrivate()->GetPropertiesSize());
    require(type(property)==STR("TextProperty") && property->GetSize()==state.text->GetSize(),"Unexpected widget prompt text layout");
    for(const auto& identity:state.owners) require(resolve(identity),"Native prompt metadata is no longer valid");
    alignas(16) std::array<uint8_t,256> params{};
    size_t initialized=0;
    const auto cleanup=[&] { while(initialized) { auto p=state.queryFields[--initialized];p->DestroyValue(p->ContainerPtrToValuePtr<void>(params.data())); } };
    try {
        for(auto p:state.queryFields) { p->InitializeValue(p->ContainerPtrToValuePtr<void>(params.data()));++initialized; }
        // Engine copy, not UE4SS's lossy Lua FText input pusher.
        state.text->CopyCompleteValue(state.text->ContainerPtrToValuePtr<void>(params.data()),property->ContainerPtrToValuePtr<void>(widget));
        state.textLibrary->ProcessEvent(state.query,params.data());
        bool found=false;
        if(state.result->GetPropertyValue(state.result->ContainerPtrToValuePtr<void>(params.data()))) {
            const auto table=state.table->ContainerPtrToValuePtr<FName>(params.data())->ToString();
            const auto& key=*state.key->ContainerPtrToValuePtr<FString>(params.data());
            const StringViewType keyView(*key);
            found=table==inputTable && (keyView==STR("Input_Sprint") || keyView==STR("Input_Haste"));
        }
        cleanup();return found;
    } catch(...) { cleanup();throw; }
}
}

void registerLua(RC::LuaMadeSimple::Lua& lua) {
    lua.register_function("_QDNSprintConfigure",[](const Lua& l) {
        gameThread();const bool enabled=l.get_bool();const bool logging=l.get_bool();
        state.logging=logging;
        if(enabled) prepare();
        state.enabled=enabled;
        if(!enabled && logging) {
            Output::send(STR("[Quiet Dawn native] Sprint prompts: calls={} suppressed={} restored={} failures={} preMs={}\n"),
                state.calls,state.hidden,state.restored,state.failures,state.nanos/1e6);
        }
        if(!enabled) { state.calls=state.hidden=state.restored=state.failures=state.nanos=0;state.warned=false; }
        return 0;
    });
    lua.register_function("_QDNIsSprintPrompt",[](const Lua& l) {
        gameThread();const auto name=l.get_string();const auto address=l.get_integer();
        l.set_bool(match(name,static_cast<uintptr_t>(address)));return 1;
    });
}
void stop() noexcept { state.enabled=false; }
void shutdown() noexcept {
    state.enabled=false;state.ready=false;
    // Native hooks remain registered across Lua sessions. Unhook only at DLL
    // shutdown while the indexed native function still exists.
    try { if(IsInGameThread() && resolve(state.owners[1])==state.show && state.show) UObjectGlobals::UnregisterHook(state.show,state.hook); } catch(...) {}
    if(state.listening) { FUObjectArray::RemoveUObjectDeleteListener(&state);state.listening=false; }
}
}
