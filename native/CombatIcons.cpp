// Quiet Dawn - Configurable HUD. MIT.
// Synchronous presentation after the stock marker's drawing functions. No Lua
// calls, discovery, configuration I/O or delayed work in the native callback.
#include "CombatIcons.hpp"
#include "CombatIconPolicy.hpp"
#include "ObjectIdentity.hpp"
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <DynamicOutput/Output.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObjectArray.hpp>
#include <Unreal/UnrealInitializer.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <atomic>
#include <chrono>
#include <mutex>
#include <string>

namespace QuietDawn::CombatIcons {
namespace {
using namespace RC;
using namespace RC::Unreal;
using Lua=LuaMadeSimple::Lua;
constexpr auto markerPath=L"/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C";
constexpr std::array childNames{L"Reticle",L"FarAwayReticle",L"HardLockTarget",L"HardLockTarget_Outline",
    L"LeftArrow",L"RightArrow",L"TopArrow",L"BottomArrow"};
constexpr std::array drawNames{L"Display Icon State Directionally",L"Display Icon State Non-Directionally",
    L"Display Unblockable Icon State",L"EnableHardLock",L"RefreshIndicatorsVisibility",
    L"ToggleShowOnlyMiddleIndicator",L"NotifyIndicatorCleared",L"OnMinimumScaleChanged",
    L"OnObservedStubIconTypeChanged",L"ExecuteUbergraph_WBP_CombatTargetIndicator"};
constexpr std::array spritePaths{L"",
    L"/Game/_Dawnwalker/UI/_Unified/Combat/Atlas/Frames/T_Combat_Icon_Diamond.T_Combat_Icon_Diamond",
    L"/Game/_Dawnwalker/UI/_Unified/SharedTextures/General/Frames/T_Icon_Padlock.T_Icon_Padlock",
    L"/Game/_Dawnwalker/UI/_Unified/Combat/Atlas/Frames/T_Combat_Icon_SkullRed.T_Combat_Icon_SkullRed"};
void require(bool value,const char* why) { if(!value) throw std::runtime_error(why); }
void gameThread() { require(IsInGameThread(),"Combat icon guard requires the game thread"); }
ObjectIdentity identify(UObject* object) {
    if(!object) return {};
    const auto index=object->GetInternalIndex();auto item=FUObjectArray::IndexToObject(index);
    if(!item || item->GetUObject()!=object || !FUObjectArray::IsValid(item,false)) return {};
    return {reinterpret_cast<uintptr_t>(object),index,item->GetSerialNumber()};
}
UObject* resolve(const ObjectIdentity& id) {
    if(!id.address) return nullptr;
    auto item=FUObjectArray::IndexToObject(id.index);
    if(!item || !FUObjectArray::IsValid(item,false)) return nullptr;
    auto object=item->GetUObject();return id.matches(reinterpret_cast<uintptr_t>(object),item->GetSerialNumber())?object:nullptr;
}
template<class T> T read(const void* object,int offset) {
    T value;std::memcpy(&value,static_cast<const uint8_t*>(object)+offset,sizeof value);return value;
}
template<class T> void write(void* object,int offset,const T& value) {
    std::memcpy(static_cast<uint8_t*>(object)+offset,&value,sizeof value);
}
struct Bit {int offset{};uint8_t mask{};bool get(const void* o) const {return (read<uint8_t>(o,offset)&mask)!=0;} };
struct Vector {Span x,y;};
struct Color {std::array<Span,4> channels{};};
struct Call {ObjectIdentity function;int size{};std::array<int,2> offsets{};Bit flag{};Color color{};};
struct ImageLayout {int resource{},visibility{};Vector size;Color color;};
struct Lease {
    ObjectIdentity owner;
    uint64_t token{};
    std::array<ObjectIdentity,8> children{};
    std::array<uint8_t,8> originalVisibility{},lastVisibility{};
    std::array<bool,8> visibilityOwned{};
    float originalRoot{},lastRoot{};bool rootOwned{},warningActive{},full{},suspended{};
};
struct Asset {ObjectIdentity object;double x{},y{};};
struct State final:FUObjectDeleteListener {
    std::recursive_mutex mutex;
    std::atomic_bool enabled{},ready{},busy{};
    std::atomic_int level{2};
    unsigned options{},styleReady{};bool listening{},warned{},fullReady{};
    uint64_t nextToken{};
    Hook::GlobalCallbackId hook{Hook::ERROR_ID};
    std::array<ObjectIdentity,64> dependencies{};size_t dependencyCount{};
    ObjectInterest interest;
    std::array<Lease,64> leases{};
    ObjectIdentity markerClass,imageClass;
    std::array<ObjectIdentity,drawNames.size()> draws{};
    std::array<int,32> drawTable{};
    std::array<int,8> childOffsets{};
    Span opacity{};int iconOffset{},animationOffset{},entryOffset{};
    Bit hardLock,hideDirections;
    Color parryColor;
    ImageLayout image;
    Call visibility,setOpacity,atlas,setColor,invalidate,attackStyle,weakStyle,stopAnimation,directional,nonDirectional;
    std::array<Asset,4> assets{};
    uint64_t events{},paints{},writes{},repairs{},failures{},stale{},nanos{},setupNanos{};
    void retain(ObjectIdentity id) {
        require(id.address!=0,"Combat icon dependency is no longer alive");
        for(size_t i=0;i<dependencyCount;++i) if(dependencies[i].address==id.address) return;
        require(dependencyCount<dependencies.size(),"Combat icon dependency capacity exceeded");
        dependencies[dependencyCount++]=id;interest.add(id.index);
    }
    void forget(Lease& lease) {
        if(lease.owner.address) interest.remove(lease.owner.index);
        for(auto& child:lease.children) if(child.address) interest.remove(child.index);
        lease={};
    }
    void NotifyUObjectDeleted(const UObjectBase* object,int32 index) override {
        if(!interest.contains(index)) return;
        std::lock_guard lock(mutex);
        const auto address=reinterpret_cast<uintptr_t>(object);
        // Owned scalar identities only: no dereferences, reflection, allocation
        // or output while GC is deleting an object, including zero-serial reuse.
        for(size_t i=0;i<dependencyCount;++i) if(dependencies[i].invalidate(index,address)) {
            interest.remove(index);ready=false;
        }
        for(auto& lease:leases) {
            bool hit=lease.owner.address==address && lease.owner.index==index;
            for(const auto& child:lease.children) hit|=child.address==address && child.index==index;
            if(hit) {forget(lease);if(level==4) ++stale;}
        }
    }
    void OnUObjectArrayShutdown() override {
        enabled=false;ready=false;
        if(listening) {FUObjectArray::RemoveUObjectDeleteListener(this);listening=false;}
    }
    void clear() {
        ready=false;fullReady=false;styleReady=0;dependencyCount=0;dependencies={};assets={};leases={};draws={};drawTable={};interest.clear();
    }
    void failure(const char* why) noexcept {
        if(level==4) ++failures;
        if(warned || level<1) return;
        warned=true;
        try {
            StringType text=STR("[Quiet Dawn][ERROR] Same-frame combat icon presentation unavailable: ");
            text.append(why,why+std::strlen(why));text+=STR(". Deferred HUD recovery remains available.\n");
            Output::send(StringViewType(text));
        } catch(...) {}
    }
} state;

StringType type(FProperty* p) {return p?p->GetClass().GetFName().ToString():STR("");}
FProperty* field(UStruct* owner,const wchar_t* name) {
    const FName wanted(name);FProperty* found{};
    for(auto p:TFieldRange<FProperty>(owner,EFieldIterationFlags::IncludeSuper | EFieldIterationFlags::IncludeDeprecated))
        if(p->GetFName()==wanted) {require(!found,"Combat icon field name is ambiguous");found=p;}
    if(!found) {
        std::string narrow;for(auto p=name;*p;++p) narrow.push_back(*p<=127?static_cast<char>(*p):'?');
        throw std::runtime_error("Combat icon field missing: "+narrow);
    }
    require(found->GetArrayDim()==1 && fits({found->GetOffset_Internal(),found->GetSize()},owner->GetPropertiesSize()),
        "Combat icon field lies outside its reflected owner");
    return found;
}
Span numericField(UStruct* owner,const wchar_t* name,int base=0) {
    auto p=field(owner,name);const auto t=type(p);Span span{p->GetOffset_Internal(),p->GetSize()};
    require((t==STR("FloatProperty") && span.width==4) || (t==STR("DoubleProperty") && span.width==8),
        "Combat icon numeric field requires float or double storage");
    span.offset+=base;return span;
}
int objectField(UStruct* owner,const wchar_t* name) {
    auto p=field(owner,name);require(type(p)==STR("ObjectProperty") && p->GetSize()==sizeof(void*),
        "Combat icon object field requires an object pointer");return p->GetOffset_Internal();
}
int byteField(UStruct* owner,const wchar_t* name) {
    auto p=field(owner,name);auto t=type(p);
    require((t==STR("ByteProperty") || t==STR("EnumProperty")) && p->GetSize()==1,
        "Combat icon enum requires one-byte storage");return p->GetOffset_Internal();
}
Bit boolField(UStruct* owner,const wchar_t* name) {
    auto p=field(owner,name);require(type(p)==STR("BoolProperty"),"Combat icon flag requires a Boolean property");
    auto b=static_cast<FBoolProperty*>(p);
    const auto mask=b->GetFieldMask();
    require(b->GetByteOffset()<p->GetSize() && (mask==255 || (mask && !(mask&(mask-1)))),"Combat icon Boolean mask is invalid");
    return {p->GetOffset_Internal()+b->GetByteOffset(),b->GetFieldMask()};
}
std::pair<UScriptStruct*,int> structure(UStruct* owner,const wchar_t* name) {
    auto p=field(owner,name);require(type(p)==STR("StructProperty"),"Combat icon value requires reflected struct storage");
    auto s=static_cast<FStructProperty*>(p)->GetStruct().Get();
    require(s && s->GetPropertiesSize()<=p->GetSize(),"Combat icon struct exceeds its property storage");
    state.retain(identify(s));return {s,p->GetOffset_Internal()};
}
Vector vector(UStruct* owner,const wchar_t* name,int base=0) {
    auto [s,offset]=structure(owner,name);return {numericField(s,L"X",base+offset),numericField(s,L"Y",base+offset)};
}
Color color(UStruct* owner,const wchar_t* name,int base=0) {
    auto [s,offset]=structure(owner,name);
    return {{{numericField(s,L"R",base+offset),numericField(s,L"G",base+offset),
        numericField(s,L"B",base+offset),numericField(s,L"A",base+offset)}}};
}
UFunction* function(const StringType& path,std::initializer_list<const wchar_t*> parameters) {
    auto fn=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,path);
    if(!fn) {
        std::string narrow;for(auto c:path) narrow.push_back(c<=127?static_cast<char>(c):'?');
        throw std::runtime_error("Combat icon presentation function is not loaded: "+narrow);
    }
    int count=0;
    for(auto p:TFieldRange<FProperty>(fn,EFieldIterationFlags::IncludeDeprecated)) if(p->HasAnyPropertyFlags(EPropertyFlags::CPF_Parm)) {
        require(!p->HasAnyPropertyFlags(EPropertyFlags::CPF_OutParm | EPropertyFlags::CPF_ReturnParm),
            "Combat icon setter unexpectedly has output parameters");
        require(p->GetArrayDim()==1 && fits({p->GetOffset_Internal(),p->GetSize()},fn->GetParmsSize()),
            "Combat icon parameter lies outside its call storage");++count;
    }
    require(count==parameters.size() && fn->GetParmsSize()<=128,"Combat icon setter parameter contract is unsupported");
    std::array<Span,2> inputs{};size_t used=0;
    for(auto name:parameters) {
        auto p=field(fn,name);
        require(p->HasAnyPropertyFlags(EPropertyFlags::CPF_Parm),"Combat icon input name refers to a local, not a parameter");
        Span span{p->GetOffset_Internal(),p->GetSize()};
        for(size_t i=0;i<used;++i) require(span.offset>=inputs[i].offset+inputs[i].width || inputs[i].offset>=span.offset+span.width,
            "Combat icon input storage overlaps");
        require(used<inputs.size(),"Combat icon input capacity exceeded");inputs[used++]=span;
    }
    state.retain(identify(fn));return fn;
}
Call call(const StringType& path,std::initializer_list<const wchar_t*> parameters) {
    auto fn=function(path,parameters);return {identify(fn),fn->GetParmsSize()};
}
UFunction* node(const Call& call) {
    auto fn=static_cast<UFunction*>(resolve(call.function));require(fn!=nullptr,"Combat icon setter was replaced");return fn;
}
using Args=std::array<uint8_t,128>;
void invoke(UObject* object,const Call& call,Args& args) {
    require(state.ready && object,"Combat icon object or metadata expired during presentation");
    object->ProcessEvent(node(call),args.data());
    if(state.level==4) ++state.writes;
}
void invoke(UObject* object,const Call& call) {Args args{};invoke(object,call,args);}

void prepareFull() {
    if(state.fullReady) return;
    auto cls=static_cast<UClass*>(resolve(state.markerClass));require(cls,"Combat marker class expired");
    auto image=UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,STR("/Script/UMG.Image"));
    require(image,"Combat icon UImage class is unavailable");state.imageClass=identify(image);state.retain(state.imageClass);
    for(size_t i=0;i<childNames.size();++i) state.childOffsets[i]=objectField(cls,childNames[i]);
    state.iconOffset=byteField(cls,L"Currently Displayed Icon Type");state.hardLock=boolField(cls,L"bHardLockEnabled");
    state.hideDirections=boolField(cls,L"Hide Directions");
    state.animationOffset=objectField(cls,L"UnblockableAttack");
    state.image.visibility=byteField(image,L"Visibility");state.image.color=color(image,L"ColorAndOpacity");
    auto [brush,brushOffset]=structure(image,L"Brush");
    state.image.resource=brushOffset+objectField(brush,L"ResourceObject");state.image.size=vector(brush,L"ImageSize",brushOffset);
    state.visibility=call(STR("/Script/UMG.Widget:SetVisibility"),{L"InVisibility"});
    state.visibility.offsets[0]=byteField(node(state.visibility),L"InVisibility");
    state.atlas=call(STR("/Script/UMG.Image:SetBrushFromAtlasInterface"),{L"AtlasRegion",L"bMatchSize"});
    auto atlas=field(node(state.atlas),L"AtlasRegion");
    require(type(atlas)==STR("InterfaceProperty") && atlas->GetSize()==2*sizeof(void*),
        "Combat atlas setter requires the two-pointer interface parameter");
    state.atlas.offsets[0]=atlas->GetOffset_Internal();state.atlas.flag=boolField(node(state.atlas),L"bMatchSize");
    state.setColor=call(STR("/Script/UMG.Image:SetColorAndOpacity"),{L"InColorAndOpacity"});
    state.setColor.color=color(node(state.setColor),L"InColorAndOpacity");
    state.invalidate=call(STR("/Script/UMG.Widget:InvalidateLayoutAndVolatility"),{});
    const StringType root=StringType(markerPath)+STR(":");
    state.stopAnimation=call(STR("/Script/UMG.UserWidget:StopAnimation"),{L"InAnimation"});
    state.stopAnimation.offsets[0]=objectField(node(state.stopAnimation),L"InAnimation");
    state.directional=call(root+drawNames[0],{L"Icon State"});state.directional.offsets[0]=byteField(node(state.directional),L"Icon State");
    state.nonDirectional=call(root+drawNames[1],{L"Icon State"});state.nonDirectional.offsets[0]=byteField(node(state.nonDirectional),L"Icon State");
    state.fullReady=true;
}
void prepareStyles() {
    const StringType root=StringType(markerPath)+STR(":");
    if((state.options&Direction) && !(state.styleReady&Direction)) {
        state.attackStyle=call(root+L"Apply Attack Style To Arrow",{L"Arrow"});state.attackStyle.offsets[0]=objectField(node(state.attackStyle),L"Arrow");
        state.parryColor=color(static_cast<UClass*>(resolve(state.markerClass)),L"Parry Window Color");state.styleReady|=Direction;
    }
    if((state.options&Counter) && !(state.styleReady&Counter)) {
        state.weakStyle=call(root+L"Apply Weak Spot Style To Arrow",{L"Arrow"});state.weakStyle.offsets[0]=objectField(node(state.weakStyle),L"Arrow");state.styleReady|=Counter;
    }
}
bool derives(UClass* cls,UObject* parent) {
    for(auto current=static_cast<UStruct*>(cls);current;current=current->GetSuperStruct()) if(current==parent) return true;
    return false;
}
size_t bucket(UFunction* fn) {auto value=reinterpret_cast<uintptr_t>(fn)>>4;return (value^(value>>13))&31;}
void prepareMetadata(UObject* object) {
    if(state.ready) return;
    state.clear();
    if(!state.listening) {FUObjectArray::AddUObjectDeleteListener(&state);state.listening=true;}
    auto cls=UObjectGlobals::StaticFindObject<UClass*>(nullptr,nullptr,markerPath);
    require(cls && derives(object->GetClassPrivate(),cls),"Combat icon owner is not a combat target widget");
    state.markerClass=identify(cls);state.retain(state.markerClass);
    state.opacity=numericField(cls,L"RenderOpacity");
    require(state.opacity.width==4,"Combat icon opacity requires float storage");
    state.setOpacity=call(STR("/Script/UMG.Widget:SetRenderOpacity"),{L"InOpacity"});
    auto p=numericField(node(state.setOpacity),L"InOpacity");require(p.width==4,"Combat opacity setter requires float input");
    state.setOpacity.offsets[0]=p.offset;
    const StringType root=StringType(markerPath)+STR(":");
    for(size_t i=0;i<drawNames.size();++i) {
        auto fn=UObjectGlobals::StaticFindObject<UFunction*>(nullptr,nullptr,root+drawNames[i]);
        // Optional event wrappers may disappear while the actual render
        // helpers remain. An absent wrapper cannot perform a stock redraw.
        if(!fn && i>=3 && i<drawNames.size()-1) continue;
        require(fn && !fn->HasAnyFunctionFlags(EFunctionFlags::FUNC_Native),"Combat drawing observer requires its Blueprint function");
        state.draws[i]=identify(fn);state.retain(state.draws[i]);
        auto at=bucket(fn);while(state.drawTable[at]) at=(at+1)&31;state.drawTable[at]=static_cast<int>(i+1);
        if(i==drawNames.size()-1) {
            auto entry=field(fn,L"EntryPoint");
            require(entry->HasAnyPropertyFlags(EPropertyFlags::CPF_Parm) && type(entry)==STR("IntProperty") && entry->GetSize()==4 && fits({entry->GetOffset_Internal(),4},fn->GetParmsSize()),
                "Combat graph observer requires a bounded int EntryPoint parameter");state.entryOffset=entry->GetOffset_Internal();
        }
    }
    state.ready=true;
}
void asset(Sprite sprite) {
    auto& a=state.assets[static_cast<size_t>(sprite)];
    if(resolve(a.object)) return;
    auto object=UObjectGlobals::StaticFindObject<UObject*>(nullptr,nullptr,spritePaths[static_cast<size_t>(sprite)]);
    require(object,"Combat icon's selected cooked sprite is unavailable");
    auto size=vector(object->GetClassPrivate(),L"BakedSourceDimension");
    const auto x=number(object,size.x),y=number(object,size.y);
    require(dimension(x)&&dimension(y),"Combat sprite has invalid cooked dimensions");
    a={identify(object),x,y};state.retain(a.object);
}
void watchChildren(Lease& lease) {
    auto object=resolve(lease.owner);require(object,"Combat marker expired");
    std::array<ObjectIdentity,8> current{};
    for(size_t i=0;i<current.size();++i) {
        auto child=read<UObject*>(object,state.childOffsets[i]);
        current[i]=identify(child);
        require(current[i].address && derives(child->GetClassPrivate(),resolve(state.imageClass)),"Combat marker child is not an available UImage");
    }
    for(size_t i=0;i<current.size();++i) if(lease.children[i].address!=current[i].address) {
        if(lease.children[i].address) state.interest.remove(lease.children[i].index);
        lease.children[i]=current[i];state.interest.add(current[i].index);lease.visibilityOwned[i]=false;
    }
    lease.full=true;
}

struct Painter {
    Lease& lease;
    bool discovery{};
    UObject* owner() {auto p=resolve(lease.owner);require(p,"Combat marker expired during drawing");return p;}
    UObject* image(int index) {
        auto p=resolve(lease.children[index]);require(p,"Combat marker child expired during drawing");
        require(read<UObject*>(owner(),state.childOffsets[index])==p,"Combat marker child was replaced; waiting for bounded recovery");return p;
    }
    void prepare(const Plan& plan) {
        if(discovery) {prepareFull();watchChildren(lease);if(plan.center!=Sprite::None) asset(plan.center);}
        require(state.fullReady && lease.full,"Combat marker presentation has not been prepared");
        for(int i=0;i<8;++i) image(i);
        if(plan.center!=Sprite::None) require(resolve(state.assets[static_cast<size_t>(plan.center)].object),"Combat sprite expired; waiting for bounded recovery");
    }
    void root(float value) {
        auto object=owner();const auto current=static_cast<float>(number(object,state.opacity));
        if(lease.rootOwned && !near(current,lease.lastRoot)) lease.originalRoot=current;
        if(!near(current,value)) {Args args{};write(args.data(),state.setOpacity.offsets[0],value);invoke(object,state.setOpacity,args);}
        lease.lastRoot=value;lease.rootOwned=true;
    }
    void visible(int index,bool shown) {
        auto object=image(index);const uint8_t value=shown?4:1,current=read<uint8_t>(object,state.image.visibility);
        if(!lease.visibilityOwned[index] || current!=lease.lastVisibility[index]) lease.originalVisibility[index]=current;
        if(current!=value) {Args args{};write(args.data(),state.visibility.offsets[0],value);invoke(object,state.visibility,args);}
        lease.lastVisibility[index]=value;lease.visibilityOwned[index]=true;
    }
    void tint(int index,const std::array<double,4>& values) {
        auto object=image(index);bool same=true;
        for(int i=0;i<4;++i) same&=near(number(object,state.image.color.channels[i]),values[i]);
        if(same) return;
        Args args{};for(int i=0;i<4;++i) number(args.data(),state.setColor.color.channels[i],values[i]);
        invoke(object,state.setColor,args);
    }
    void white(int index) {tint(index,{1,1,1,1});}
    void sprite(int index,Sprite sprite) {
        auto object=image(index);const auto& a=state.assets[static_cast<size_t>(sprite)];auto resource=resolve(a.object);
        require(resource,"Combat atlas sprite expired during drawing");
        if(read<UObject*>(object,state.image.resource)!=resource) {
            Args args{};write(args.data(),state.atlas.offsets[0],resource);
            // Interface pointer and bMatchSize remain zero. Explicit cooked
            // dimensions avoid both incomplete-interface sizing and 0x0 reuse.
            invoke(object,state.atlas,args);
        }
        const auto x=number(object,state.image.size.x),y=number(object,state.image.size.y);
        if(!near(x,a.x)||!near(y,a.y)) {
            number(object,state.image.size.x,a.x);number(object,state.image.size.y,a.y);invoke(object,state.invalidate);
            require(near(number(object,state.image.size.x),a.x)&&near(number(object,state.image.size.y),a.y),"Combat atlas dimensions did not apply");
            if(state.level==4) ++state.repairs;
        }
    }
    void arrowStyle(int arrow,bool counter,bool parry) {
        const auto& fn=counter?state.weakStyle:state.attackStyle;Args args{};
        write(args.data(),fn.offsets[0],image(arrow+4));invoke(owner(),fn,args);
        if(parry) {
            std::array<double,4> values{};auto object=owner();
            for(int i=0;i<4;++i) values[i]=number(object,state.parryColor.channels[i]);
            tint(arrow+4,values);
        }
    }
    void warningAnimation(bool allowed,bool started) {
        lease.warningActive|=started;
        if(allowed || !lease.warningActive) return;
        auto object=owner();auto animation=read<UObject*>(object,state.animationOffset);
        if(identify(animation).address) {Args args{};write(args.data(),state.stopAnimation.offsets[0],animation);invoke(object,state.stopAnimation,args);}
        lease.warningActive=false;
    }
};
Lease* find(UObject* object) {
    const auto address=reinterpret_cast<uintptr_t>(object);
    for(auto& lease:state.leases) if(lease.owner.address==address && resolve(lease.owner)==object) return &lease;
    return nullptr;
}
bool paint(Lease& lease,bool discovery,bool warningStarted=false) {
    Painter painter{lease,discovery};auto object=painter.owner();
    if(state.options && discovery) {
        prepareFull();prepareStyles();
        // Warm only enabled alternatives during bounded worker discovery;
        // switching icon/lock state never starts an asset lookup in a hook.
        if(state.options&Dot) asset(Sprite::Diamond);
        if(state.options&Lock) asset(Sprite::Padlock);
        if(state.options&Warning) asset(Sprite::Skull);
    }
    const auto icon=state.options?read<uint8_t>(object,state.iconOffset):0;
    const auto locked=state.options && state.hardLock.get(object);
    // A marker can first be discovered while the stock warning is playing.
    // Later paints only stop a warning whose start we actually observed.
    if(state.options && !lease.full && icon==9) lease.warningActive=true;
    lease.warningActive|=warningStarted;
    return render(painter,state.options,icon,locked,warningStarted);
}
void after(Hook::TCallbackIterationData<void>&,UObject* object,FFrame& stack,void*) noexcept {
    if(!state.enabled.load(std::memory_order_acquire) || !state.ready.load(std::memory_order_acquire)
        || state.busy.load(std::memory_order_relaxed) || !IsInGameThreadRaw()) return;
    const auto fn=stack.Node();size_t match=drawNames.size();
    for(size_t n=0,at=bucket(fn);n<state.drawTable.size();++n,at=(at+1)&31) {
        const auto slot=state.drawTable[at];if(!slot) return;
        if(state.draws[slot-1].address==reinterpret_cast<uintptr_t>(fn)) {match=slot-1;break;}
    }
    if(match==drawNames.size()) return;
    std::lock_guard lock(state.mutex);
    if(!state.ready || !state.enabled || state.busy || resolve(state.draws[match])!=fn) return;
    if(match==drawNames.size()-1) {
        auto locals=stack.Locals();if(!locals) return;const int entry=read<int>(locals,state.entryOffset);
        // State change/latent redraw, lock, clear, and distance transition only.
        // The marker graph is not a Tick hook or permanent readiness worker.
        if(entry!=1448 && entry!=1030 && entry!=80 && entry!=617 && entry!=91) return;
    }
    auto lease=find(object);if(!lease || lease->suspended) return;
    state.busy=true;struct Busy {~Busy(){state.busy=false;}} busy;
    const auto start=state.level==4?std::chrono::steady_clock::now():std::chrono::steady_clock::time_point{};
    try {if(state.level==4) ++state.events;paint(*lease,false,match==2);if(state.level==4) ++state.paints;}
    catch(const std::exception& error) {lease->suspended=true;state.failure(error.what());}
    catch(...) {lease->suspended=true;state.failure("native presentation exception");}
    if(state.level==4) state.nanos+=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-start).count();
}
void install() {
    if(state.hook!=Hook::ERROR_ID) return;
    auto& flag=UnrealInitializer::StaticStorage::GlobalConfig.bHookProcessLocalScriptFunction;
    struct Restore {bool& flag;bool value;~Restore(){flag=value;}} restore{flag,flag};flag=true;
    state.hook=Hook::RegisterProcessLocalScriptFunctionPostCallback(after,{false,true,STR("QuietDawnHUD"),STR("Combat icon presentation")});
    require(state.hook!=Hook::ERROR_ID,"UE4SS cannot install the combat drawing post callback");
}
void release(uintptr_t address,uint64_t token) {
    for(auto& lease:state.leases) if(lease.owner.address==address && lease.token==token) {
        auto copy=lease;state.forget(lease); // No observer may restyle this owner during its stock redraw.
        auto object=resolve(copy.owner);if(!object || !state.ready) return;
        state.busy=true;struct Busy {~Busy(){state.busy=false;}} busy;
        if(copy.rootOwned && near(number(object,state.opacity),copy.lastRoot)) {
            Args args{};write(args.data(),state.setOpacity.offsets[0],copy.originalRoot);invoke(object,state.setOpacity,args);
        }
        if(!copy.full || !state.fullReady) return;
        Painter painter{copy,false};
        for(int i=0;i<8;++i) {
            auto child=resolve(copy.children[i]);
            if(child && read<UObject*>(object,state.childOffsets[i])==child && copy.visibilityOwned[i]
                && read<uint8_t>(child,state.image.visibility)==copy.lastVisibility[i]) {
                Args args{};write(args.data(),state.visibility.offsets[0],copy.originalVisibility[i]);invoke(child,state.visibility,args);
            }
        }
        auto icon=read<uint8_t>(object,state.iconOffset);
        if(icon<=13) {const auto& fn=state.hideDirections.get(object)?state.nonDirectional:state.directional;
            Args args{};write(args.data(),fn.offsets[0],icon);invoke(object,fn,args);}
        auto sprite=state.hardLock.get(object)?Sprite::Padlock:Sprite::Diamond;
        // Cleanup runs as one existing Session cleanup slice per marker.
        asset(sprite);painter.sprite(1,sprite);
        return;
    }
}
} // namespace

void registerLua(const RC::LuaMadeSimple::Lua& lua) {
    lua.register_function("_QDNCuesVersion",[](const Lua& l){l.set_integer(1);return 1;});
    lua.register_function("_QDNCuesConfigure",[](const Lua& l){
        gameThread();const auto options=l.get_integer(1),level=l.get_integer(1);
        require(options>=0 && options<=31 && level>=0 && level<=4,"Invalid combat icon policy or logging level");
        std::lock_guard lock(state.mutex);state.options=static_cast<unsigned>(options);state.level=static_cast<int>(level);
        state.enabled=true;state.warned=false;
        if(state.ready && state.options) {
            // Settings are an explicit, bounded discovery event, never a
            // reason to perform a sprite/metadata lookup inside a draw hook.
            prepareFull();prepareStyles();
            if(state.options&Dot) asset(Sprite::Diamond);
            if(state.options&Lock) asset(Sprite::Padlock);
            if(state.options&Warning) asset(Sprite::Skull);
        }
        return 0;
    });
    lua.register_function("_QDNCuesApply",[](const Lua& l){
        gameThread();auto object=reinterpret_cast<UObject*>(l.get_integer(1));const auto original=l.get_number(1);
        require(std::isfinite(original) && original>=0 && original<=1,"Invalid original combat marker opacity");
        std::lock_guard lock(state.mutex);
        const auto start=state.level==4?std::chrono::steady_clock::now():std::chrono::steady_clock::time_point{};
        require(state.enabled && identify(object).address,"Combat icon guard is inactive or owner expired");
        prepareMetadata(object);require(derives(object->GetClassPrivate(),resolve(state.markerClass)),"Foreign combat icon class");install();
        auto lease=find(object);const bool created=!lease;
        if(!lease) {
            for(auto& item:state.leases) if(!item.owner.address) {lease=&item;break;}
            require(lease,"Combat icon guard capacity reached");
            lease->owner=identify(object);lease->token=++state.nextToken;state.interest.add(lease->owner.index);lease->originalRoot=static_cast<float>(original);
        }
        state.busy=true;struct Busy {~Busy(){state.busy=false;}} busy;
        bool shown;
        try {shown=paint(*lease,true);lease->suspended=false;}
        catch(...) {
            lease->suspended=true;
            // A failed first paint has not returned its cleanup token to Lua.
            // Release partial ownership now instead of orphaning a lease.
            if(created) {try {release(lease->owner.address,lease->token);} catch(...) {}}
            throw;
        }
        if(state.level==4) {++state.paints;state.setupNanos+=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-start).count();}
        l.set_bool(true);l.set_bool(shown);l.set_integer(lease->token);return 3;
    });
    lua.register_function("_QDNCuesRelease",[](const Lua& l){
        gameThread();const auto address=static_cast<uintptr_t>(l.get_integer(1));const auto token=static_cast<uint64_t>(l.get_integer(1));std::lock_guard lock(state.mutex);
        try {release(address,token);} catch(const std::exception& error) {state.failure(error.what());}return 0;
    });
    lua.register_function("_QDNCuesStats",[](const Lua& l){
        gameThread();std::lock_guard lock(state.mutex);
        l.set_integer(state.events);l.set_integer(state.paints);l.set_integer(state.writes);l.set_integer(state.repairs);
        l.set_integer(state.failures);l.set_integer(state.stale);l.set_number(state.nanos/1e6);l.set_number(state.setupNanos/1e6);return 8;
    });
    lua.register_function("_QDNCuesStop",[](const Lua&){stop();return 0;});
}
void stop() {
    state.enabled=false;std::lock_guard lock(state.mutex);state.clear();state.warned=false;
    state.events=state.paints=state.writes=state.repairs=state.failures=state.stale=state.nanos=state.setupNanos=0;
}
void shutdown() {
    stop();if(state.hook!=Hook::ERROR_ID) {Hook::UnregisterCallback(state.hook);state.hook=Hook::ERROR_ID;}
    if(state.listening) {FUObjectArray::RemoveUObjectDeleteListener(&state);state.listening=false;}
}
}
