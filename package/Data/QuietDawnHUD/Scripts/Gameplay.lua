local D = require("QuietDawnDiagnostics")
-- Quiet Dawn - Configurable HUD | MIT License
-- Event-driven panel opacity. No widget-tree walks, global object searches,
-- animation hooks, or Lua coroutines. Claw marks use two named cue defaults.
-- Resource reads run only on resource-change and HUD/player lifecycle events.
local ok, config = pcall(require, "MenuSettings")
if SaveLoadDiagnostics and ok and type(config)=="table" then
    SaveLoadDiagnostics.debugLogging = config.debugLogging == true
end
if not ok or type(config) ~= "table" then
    print("[Quiet Dawn - Configurable HUD] Invalid configuration; HUD left to the game.")
    return
end
local allowed = {HumanStats=true, VampireStats=true, WBP_Compass=true,
    WBP_HUD_QuestInfo=true, WBP_HUD_Quickslots=true, Crosshair=true,
    WBP_AA_Quickslots=true, WBP_OpenFocusPrompt=true,
    WBP_HUD_Quickslots_ChangePrompt=true, WBP_ControlsLegend=true,
    WBP_BuffContainer=true, WBP_HUD_AbilityCooldownsContainer=true,
    CombatFocusPanel=true, WBP_HUD_FocusCharge_Bar=true,
    WBP_HUD_SpecialAttackCooldown=true, XPBar=true, WBP_HudTimer=true}
local names, seen = {}, {}
if type(config.panels) ~= "table" then return end
for _, name in ipairs(config.panels) do
    if not allowed[name] or seen[name] then
        print("[Quiet Dawn - Configurable HUD] Unknown or duplicate panel; disabled.")
        return
    end
    seen[name] = true
    names[#names+1] = name
end
if type(config.enabled) ~= "boolean" then return end
if config.compassOpacity~=nil and (type(config.compassOpacity)~="number"
    or config.compassOpacity~=config.compassOpacity or config.compassOpacity<0 or config.compassOpacity>1) then
    print("[Quiet Dawn - Configurable HUD] Invalid compass opacity; disabled.")
    return
end
for _, key in ipairs({"healthThreshold", "staminaThreshold"}) do
    local value=config[key]
    if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
        print("[Quiet Dawn - Configurable HUD] Invalid threshold; disabled.")
        return
    end
end
if config.manualPeek==nil then config.manualPeek=true end
if config.manualPeekSeconds==nil then config.manualPeekSeconds=3.0 end
if config.timeHoldSeconds==nil then config.timeHoldSeconds=4.0 end
if config.switchRevealSeconds==nil then config.switchRevealSeconds=3 end
if type(config.manualPeek)~="boolean" then return end
for _, key in ipairs({"healthHoldSeconds", "staminaHoldSeconds", "manualPeekSeconds", "switchRevealSeconds", "timeHoldSeconds"}) do
    local value=config[key]
    if type(value) ~= "number" or value ~= value or value < 0 or value > 10 or value*2%1 ~= 0 then
        print("[Quiet Dawn - Configurable HUD] Invalid hold duration; disabled.")
        return
    end
end
local livePending,applyLiveSettings
local livePanels={}
Session.onSettings(function(values)
    if (values.enabled==1)~=config.enabled then Session.restart();return end
    D.setEnabled(values.debugLogging==1)
    if SaveLoadDiagnostics then SaveLoadDiagnostics.debugLogging=values.debugLogging==1 end
    if applyLiveSettings then
        livePending=values
        -- The persistent subscription only queues owned data.
        applyLiveSettings(false)
    end
end)
if not config.enabled then return end
local applyCombatCue=require("QuietDawnCombatCues").new(config,D,Session)
if QuietDawnNative then QuietDawnNative.begin(config.debugLogging) end
local sessionRegisterHook=RegisterHook
local function RegisterHook(path,...)
    -- Session guards persist; native UFunction identities refresh after travel.
    if QuietDawnNative then QuietDawnNative.prepare(path) end
    return sessionRegisterHook(path,...)
end
local statNames = {}
local dynamicPanels = config.dynamicPanels or {HumanStats=true, VampireStats=true}
local panelOpacities = config.panelOpacities or {}
local panelScales = config.panelScales or {}
local hasPanelScaling=false
for _, name in ipairs(names) do
    local scale=panelScales[name] or 1
    if type(scale)~="number" or scale~=scale or scale<0.25 or scale>2
        or math.abs(scale*20-math.floor(scale*20+0.5))>1e-6 then
        print("[Quiet Dawn - Configurable HUD] Invalid panel size; disabled.")
        return
    end
    if scale~=1 then hasPanelScaling=true end
    local value=panelOpacities[name]
    if value~=nil and (type(value)~="number" or value~=value or value<0 or value>1) then
        print("[Quiet Dawn - Configurable HUD] Invalid panel opacity; disabled.")
        return
    end
    if (name == "HumanStats" or name == "VampireStats") and dynamicPanels[name] then
        statNames[#statNames+1]=name
    end
end
local panelScaling=hasPanelScaling and require("QuietDawnPanelScale").new(panelScales,D,Session) or nil
local manualPeekEnabled=config.manualPeek and config.manualPeekSeconds>0 and #names>0
local timeRevealEnabled=seen.WBP_HudTimer and (panelOpacities.WBP_HudTimer or 0)==0 and config.timeHoldSeconds>0
if type(ExecuteInGameThreadWithDelay) ~= "function" or type(CancelDelayedAction) ~= "function" then
    print("[Quiet Dawn - Configurable HUD] Requires cancellable delayed game-thread callbacks; disabled.")
    return
end

if D.debugLogging then D.event("config","healthThreshold=%.3f staminaThreshold=%.3f healthHold=%.3fs staminaHold=%.3fs panels=%d",config.healthThreshold,config.staminaThreshold,config.healthHoldSeconds,config.staminaHoldSeconds,#names) end
local ROOT = "/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C"
local hud, candidate, controller, world
local hudAddress, controllerAddress
local worker, dirty, stateReady = false, false, false
local statsPending, expiryPending = false, false
local statsRefresh=true
local expiryHandle,expiryDue,expiryHUD,expiryController,expiryPawn
local healthDropped, staminaDropped = false, false
local statHookFailures, hookAttempt = false, 0
local failedHooks = {}
local timeRequested,timeDirty,timeVisible,timeUntil=false,false,false,0
local timeJobNames={"WBP_HudTimer"}
local timeWatcher=timeRevealEnabled and require("QuietDawnTime").new(D) or nil
local peekRequested,peekUntil,peekVisible=false,0,false
local switchRequested,switchUntil,switchVisible=false,0,false
local switchCursor=0
local switchJobNames={"WBP_HUD_Quickslots","WBP_AA_Quickslots"}
local peekWidgetAddress,peekControllerAddress
local lastPawnAddress, lastCombatAddress, lastBloodAddress, lastForm, previousHealth, previousStamina
local previousHealthAmount
local lastBloodCapacity
local fullRecoveryArmed=false
local HEALING_REVEAL_GAIN, FULL_REARM_GAP, FULL_EPSILON=0.002,0.002,0.000001
local healthUntil, staminaUntil = 0, 0
local panels = {}
local absent, jobNames, fullPending, fullJob = {}, names, false, true
local cursor, desired, attempts = 0, 1, 0
local hooks, hookIndex = {}, 1
local hookErrors = {}
local function reportHookError(path, success, pre, post)
    if not D.debugLogging or hookErrors[path] then return end
    hookErrors[path] = true
    -- Once per hook per session; preserve the exception even when ordinary
    -- diagnostic events have reached their rate limit.
    local reason = success and ("invalid hook IDs: "..tostring(pre)..", "..tostring(post)) or tostring(pre)
    print("[Quiet Dawn - Configurable HUD][DEBUG] Hook registration failed: "..path.." | "..reason)
end
local warned = false
local frameClock, lastFrame
local wake, armExpiry, clawMarks
local function valid(object)
    return object ~= nil and object:IsValid()
end
local function opacity(object, value)
    return Session.changeObject('opacity:'..tostring(object:GetAddress()), object,
        'GetRenderOpacity', 'SetRenderOpacity', value)
end
local function sameObject(left, right)
    -- Reflected calls can return different Lua wrappers for the same UObject.
    -- Revalidate both objects; compare native identity, never wrapper identity.
    return valid(left) and valid(right) and left:GetAddress()==right:GetAddress()
end
local function unwrap(param)
    if param == nil then return nil end
    return param:get()
end
-- These are actual Blueprint delegate handlers, not delegate signatures.
-- Stock OnInitialized binds VampireStats to OnStaminaChanged in both forms.
local STAT_ROOT = "/Game/_Dawnwalker/UI/_Unified/HUD/PlayerStatPanel/"
local function statEvent(kind, field)
    return function(context, newParam, oldParam)
        if #statNames==0 then return end
        if D.debugLogging then D.count("resourceCallbacks") end
        local object=unwrap(context)
        if not valid(hud) or not valid(object) or not sameObject(hud[field],object)
            or not valid(controller) or not sameObject(object:GetOwningPlayer(),controller)
            or not sameObject(object:GetWorld(),world) then
            if D.debugLogging then D.count("resourceOwnerRejected") end
            return
        end
        local new, old=tonumber(unwrap(newParam)),tonumber(unwrap(oldParam))
        if kind=="health" and lastForm~=nil and ((lastForm==0 and field=="VampireStats")
            or (lastForm==1 and field=="HumanStats")) then return end
        if new and old and new==old then return end
        -- Retain a drop even if a second event restores the value before the worker.
        if new and old and new<old then
            if kind=="health" then
                -- Tiny blood drain/regeneration cycles must not renew the hold.
                if field~="VampireStats" or old-new>=(lastBloodCapacity or math.abs(old))*0.002 then healthDropped=true end
            elseif kind=="stamina" then staminaDropped=true end
        end
        statsPending=true
        if D.debugLogging then D.count("resourceEvents") end
        wake("resource")
    end
end
-- Hook the real update functions as well as custom event stubs. Native
-- Blueprint event dispatch can enter the event graph without running a stub.
-- Both helpers are reached from resource/initialization events, never Tick.
local function statUpdate(field)
    return statEvent("refresh",field)
end
-- The stock Controls Legend action already handles the Menu/Options hold.
-- Its button click enters this graph at 850 (Steam build 25191761). Filter
-- before object access: entry activation/cinematic events must never reveal.
-- This widget has no Tick event; no button-state sampling or remapping is used.
local LEGEND="/Game/_Dawnwalker/UI/_Unified/HUD/ControlsLegend/WBP_ControlsLegend.WBP_ControlsLegend_C"
local function peekInput(context,entryParam)
    if not manualPeekEnabled then return end
    if tonumber(unwrap(entryParam))~=850 then return end
    local object=unwrap(context)
    -- The accepted HUD owns this cached widget. The worker revalidates the
    -- HUD/controller/world before using the request, keeping input work tiny.
    if peekControllerAddress~=controllerAddress or not valid(object)
        or object:GetAddress()~=peekWidgetAddress then return end
    peekRequested,statsPending=true,true
    if D.debugLogging then D.count("manualPeekRequests") end
    wake("resource")
end
-- The time graph can be bypassed by direct Blueprint dispatch. Observe its
-- display helper too; actual-time snapshots exclude initialization/previews.
local TIME="/Game/_Dawnwalker/UI/_Unified/HUD/Timer/WBP_HudTimer.WBP_HudTimer_C"
local function timeDisplayUpdated(context,confirmed)
    if not timeRevealEnabled or not timeWatcher then return end
    local object=unwrap(context)
    if not valid(hud) or not valid(controller) or not valid(object)
        or not sameObject(hud.WBP_HudTimer,object)
        or not sameObject(object:GetOwningPlayer(),controller)
        or not sameObject(object:GetWorld(),world) then return end
    timeWatcher.queue(confirmed==true)
    wake("time")
end
local function timeChanged(context,entryParam)
    if not timeRevealEnabled then return end
    if tonumber(unwrap(entryParam))~=455 then return end
    timeDisplayUpdated(context,true)
end
-- The game shares this widget between neutral lock-on, directions and cues.
-- Each cue category follows its own Quiet Dawn setting; the dot stays hidden.
local MARKER = "/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C"
local markerSpecs = {"Construct", "OnObservedStubIconTypeChanged",
    "NotifyIndicatorCleared", "EnableHardLock", "RefreshIndicatorsVisibility",
    "ToggleShowOnlyMiddleIndicator", "Display Icon State Directionally",
    "Display Icon State Non-Directionally"}
local markerHookIndex, markerHookAttempts, markerSeen = 1, 0, false
local markerQueue, markerPending, markerFirst, markerLast = {}, {}, 1, 0
local markerCache, markerSlots, markerCount, markerPrune = {}, {}, 0, 1
local markerCacheWorld, markerCacheController, markerTurn
-- Steam build 25129649: ERebelSetting::Game_Difficulty_CombatDirectionMarkers=71.
-- This menu setting is distinct from the widget's internal Hide Directions flag.
local settingsFactory, settingsObject, directionsEnabled
local settingsPending, settingsAttempts = true, 0
local function markersReady()
    -- Keep construction events queued until HUD ownership has been accepted.
    -- Missing HUD readiness sleeps until a lifecycle event, without polling.
    return markerFirst<=markerLast and candidate==nil and world~=nil and controller~=nil
end
local function queueMarker(object, retries)
    if object == nil then return end
    -- Capture only the wrapper here: construction may not be on the game
    -- thread. Pointer/property reads happen in the shared game-thread worker.
    local pending=markerPending[object]
    if pending then pending.object=object; if D.debugLogging then D.count("markerCoalesced") end; return end
    -- Excess objects remain under game control. No unbounded queues or scans.
    if markerLast-markerFirst+1 >= 64 then if D.debugLogging then D.count("markerQueueFull") end; return end
    local job={object=object, retries=retries or 0}
    markerLast=markerLast+1
    markerQueue[markerLast]=job
    markerPending[object]=job
    if wake then wake("marker") end
end
local function markerEvent(context)
    if D.debugLogging then D.count("markerEvents") end
    queueMarker(unwrap(context))
end
local function refreshSettings(context, setting)
    if setting and tonumber(unwrap(setting))~=71 then return end
    settingsObject=unwrap(context)
    settingsPending,settingsAttempts=true,0
    wake("settings")
end
local function settingsStep()
    settingsAttempts=settingsAttempts+1
    local success,value=pcall(function()
        if not valid(settingsFactory) then
            settingsFactory=StaticFindObject("/Script/RebelSettings.Default__RebelGameUserSettings")
            return nil
        end
        if not valid(settingsObject) then
            settingsObject=settingsFactory:Get()
            return nil
        end
        local out={}
        local found=settingsObject:GetSettingAsBool(71,out)
        if found and type(out.OutSettingBool)=="boolean" then return out.OutSettingBool end
    end)
    if success and type(value)=="boolean" then
        settingsPending=false
        if D.debugLogging then D.count(value and "directionReadsEnabled" or "directionReadsDisabled") end
    elseif settingsAttempts<8 then
        return
    else
        value=nil
        settingsPending=false
        if D.debugLogging then D.count("directionReadFailures") end
    end
    if directionsEnabled~=value then
        directionsEnabled=value
        -- Fixed-size plain Lua cache traversal; native work stays in marker slices.
        for _,entry in pairs(markerCache) do queueMarker(entry.object) end
    end
    if D.debugLogging then D.event("directions","menuEnabled=%s readSuccess=%s attempts=%d",tostring(value),tostring(success),settingsAttempts) end
end
settingsStep=D.wrap("directions",settingsStep)
local function markerHooksStep()
    local path=MARKER..":"..markerSpecs[markerHookIndex]
    local success, pre, post=pcall(RegisterHook, path, markerEvent)
    markerHookAttempts=markerHookAttempts+1
    if success and type(pre)=="number" and type(post)=="number" then
        hooks[path]={pre,post}
        markerHookIndex=markerHookIndex+1
        if D.debugLogging then D.event("hook","registered=%s",path) end
    else
        reportHookError(path, success, pre, post)
    end
end
local function markerStep()
    local job=markerQueue[markerFirst]
    markerQueue[markerFirst]=nil
    markerPending[job.object]=nil
    markerFirst=markerFirst+1
    if markerFirst>markerLast then markerFirst,markerLast=1,0 end
    if markerHookIndex<=#markerSpecs then return end -- fail open until hooks work
    local object=job.object
    if not valid(object) then return end
    job.address=object:GetAddress()
    if not valid(controller) or not valid(world) then return end
    local objectWorld, owner=object:GetWorld(), object:GetOwningPlayer()
    if not valid(objectWorld) or not valid(owner) then
        if D.debugLogging then
            D.count("markerNotReady")
            if job.retries==0 or job.retries==119 then
                D.event("marker","id=%s ownership not ready; attempt=%d/120",tostring(job.address),job.retries+1)
            end
        end
        if job.retries<119 then queueMarker(object,job.retries+1) end
        return
    end
    if not sameObject(objectWorld,world) or not sameObject(owner,controller) then
        if D.debugLogging then D.count("markerForeignOwner") end
        return
    end
    if not sameObject(controller:GetWorld(),world) then return end
    if not sameObject(markerCacheWorld,world) or not sameObject(markerCacheController,controller) then
        markerCache,markerSlots,markerCount,markerPrune={}, {}, 0, 1
        markerCacheWorld,markerCacheController=world,controller
    end
    local entry=markerCache[job.address]
    if not entry and markerCount>=64 then
        if D.debugLogging then D.count("markerCacheFull") end
        -- Inspect one old slot per frame, not the entire object cache.
        local slot=markerPrune
        markerPrune=markerPrune%64+1
        local old=markerSlots[slot]
        if not valid(old.object) then
            markerCache[old.address]=nil
            markerSlots[slot]=nil
            markerCount=markerCount-1
            queueMarker(object,job.retries+1)
        end
        return
    end
    local readable,icon=pcall(function() return tonumber(object["Currently Displayed Icon Type"]) end)
    local current=object:GetRenderOpacity()
    if not entry then
        entry={object=object,address=job.address,original=current}
        markerCache[job.address]=entry
        for slot=1,64 do if not markerSlots[slot] then markerSlots[slot]=entry;break end end
        markerCount=markerCount+1
    end
    local applied,shown=applyCombatCue(object,entry,readable and icon or nil)
    if not applied then
        if entry.lastOpacity~=nil and current==entry.lastOpacity then opacity(object,entry.original) end
        entry.lastOpacity=nil
        if job.retries<8 then queueMarker(object,job.retries+1) end
        if D.debugLogging and (job.retries==0 or job.retries==8) then
            D.event("combatCueReadiness","id=%s icon=%s attempt=%d/9",tostring(job.address),tostring(icon),job.retries+1)
        end
        return
    end
    if entry.lastOpacity==nil or current~=entry.lastOpacity then entry.original=current end
    local target=shown and 1 or 0
    if current~=target then
        opacity(object,target)
        if D.debugLogging then D.count("markerWrites") end
    end
    entry.lastOpacity=target
end
markerStep=D.wrap("marker",markerStep)
markerHooksStep=D.wrap("hook",markerHooksStep)
-- Enemy bars live outside WBP_GameHUD. Health, name and difficulty children
-- follow independent settings. Stamina, wounds and
-- combat warnings stay under game control.
-- Build 25232147: these named children and lifecycle functions are exported
-- by WBP_CombatCharacterBar and WBP_Combat_BossBar.
local healthTypes = {
    {path="/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatCharacterBar.WBP_CombatCharacterBar_C",
     fields=config.hideEnemyHealthBars and {"SegmentedHealthBar","HealthBarLeftCap","HealthBarRightCap"} or {},
     events={"Construct","UpdateTarget"}},
    {path="/Game/_Dawnwalker/UI/_Unified/Combat/WBP_Combat_BossBar.WBP_Combat_BossBar_C",
     fields=config.hideEnemyHealthBars and {"HealthBar","HealthBarLeftCap","HealthBarRightCap","IndicatorBox"} or {},
     events={"Update Owner"}},
}
-- The ordinary bar has no name label; boss names use BossNameLabel.
-- Hide the difficulty widget's parent so its internal icon animation cannot
-- reveal it. Never suppress the shared combat warning/lock-on widget here.
if config.hideEnemyNames then
    local boss = healthTypes[2]
    boss.fields[#boss.fields+1] = "BossNameLabel"
end
if config.hideEnemyDifficultyIcons then
    for _, spec in ipairs(healthTypes) do
        spec.fields[#spec.fields+1] = "LevelIndicator"
    end
end
local healthQueue, healthPending, healthFirst, healthLast = {}, {}, 1, 0
local function healthReady()
    return healthFirst<=healthLast and candidate==nil and valid(hud)
end
local function queueHealth(object, spec, requestedFields)
    if object==nil then return end
    spec.recent,spec.recentSet=spec.recent or {},spec.recentSet or {}
    if not spec.recentSet[object] then
        if #spec.recent>=64 then spec.recentSet[table.remove(spec.recent,1)]=nil end
        spec.recent[#spec.recent+1]=object;spec.recentSet[object]=true
    end
    local fields=requestedFields or spec.fields
    if #fields==0 then return end
    if healthPending[object] then
        local job=healthPending[object];job.again=true
        local merged,seenFields={},{}
        for _,list in ipairs({job.fields,job.nextFields or {},fields}) do
            for _,field in ipairs(list) do if not seenFields[field] then merged[#merged+1]=field;seenFields[field]=true end end
        end
        job.nextFields=merged
        return
    end
    if healthLast-healthFirst+1>=64 then
        if D.debugLogging then D.count("enemyHealthQueueFull") end
        return
    end
    local job={object=object,spec=spec,fields=fields,field=1,attempts=0}
    healthLast=healthLast+1;healthQueue[healthLast]=job;healthPending[object]=job
    wake("enemyHealth")
end
local function healthStep()
    local job=healthQueue[healthFirst]
    healthQueue[healthFirst]=nil;healthFirst=healthFirst+1
    if healthFirst>healthLast then healthFirst,healthLast=1,0 end
    local object,spec=job.object,job.spec
    local function retry()
        job.attempts=job.attempts+1
        if job.attempts>=120 then
            if D.debugLogging then D.event("enemyHealth","readiness exhausted: %s field=%s",spec.path,job.fields[job.field]) end
            return false
        end
        return true
    end
    local function nextField()
        job.field=job.field+1
        job.attempts=0
        if job.field<=#job.fields then return true end
        if job.again then job.field=1;job.fields=job.nextFields or spec.fields;job.nextFields=nil;job.again=false;return #job.fields>0 end
        return false
    end
    local keep=false
    local success,reason=pcall(function()
        if not valid(object) then return end
        local eventIndex=spec.eventIndex or 1
        if eventIndex<=#spec.events then
            local path=spec.path..":"..spec.events[eventIndex]
            if hooks[path] then spec.eventIndex=eventIndex+1;keep=true;return end
            local ok,pre,post=pcall(RegisterHook,path,function(context)
                queueHealth(unwrap(context),spec)
            end)
            spec.hookAttempts=(spec.hookAttempts or 0)+1
            if ok and type(pre)=="number" and type(post)=="number" then
                hooks[path]={pre,post};spec.eventIndex=eventIndex+1;spec.hookAttempts=0
            else
                reportHookError(path, ok, pre, post)
                if spec.hookAttempts>=12 then
                    spec.failedEvent=spec.failedEvent or eventIndex
                    spec.eventIndex=eventIndex+1;spec.hookAttempts=0
                    if D.debugLogging then D.event("enemyHealth","lifecycle hook unavailable: %s",path) end
                end
            end
            keep=true
            return
        end
        local ow,pc=object:GetWorld(),object:GetOwningPlayer()
        if not valid(ow) or not valid(pc) then keep=retry();return end
        if not sameObject(ow,world) or not sameObject(pc,controller)
            or not sameObject(controller:GetWorld(),world) then return end
        local field=job.fields[job.field]
        local child=object[field]
        if not valid(child) then
            -- A missing bar/label must not block independent children. Each
            -- field gets finite readiness, and later target events retry it.
            keep=retry() or nextField()
            return
        end
        local setting=field=='BossNameLabel' and 'hideEnemyNames' or (field=='LevelIndicator' and 'hideEnemyDifficultyIcons' or 'hideEnemyHealthBars')
        if config[setting] then
            if child:GetRenderOpacity()~=0 then
                opacity(child,0)
                if D.debugLogging then D.count('enemyHealthWrites') end
            end
        else Session.restore('opacity:'..tostring(child:GetAddress())) end
        keep=nextField()
    end)
    if not success then
        keep=retry()
        if D.debugLogging then D.event("enemyHealth","update failed: %s",tostring(reason)) end
    end
    if keep then healthLast=healthLast+1;healthQueue[healthLast]=job
    else healthPending[object]=nil end
end
healthStep=D.wrap("enemyHealth",healthStep)
local healthTurn=false
local sprintSource=require("QuietDawnSprintSource").new({
    _QDNSprintConfigure=_QDNSprintConfigure,_QDNIsSprintPrompt=_QDNIsSprintPrompt},D,Session)
sprintSource.configure(config.hideSprintPrompt)
local sprintPrompts=config.hideSprintPrompt and require("QuietDawnSprintPrompt").new({
    StaticFindObject=StaticFindObject,FName=FName,opacity=opacity,D=D,source=sprintSource}) or nil
local PROMPT_WIDGET="/Game/_Dawnwalker/UI/_Unified/Gameplay/InputPrompt/WBP_InputPrompt.WBP_InputPrompt_C"
local PROMPT_REFRESH=PROMPT_WIDGET..":UpdateWidget"
local promptTurn=false
local function promptsReady()
    return sprintPrompts and (hooks[ROOT..":OnSetInputPromptEnabled"] or hooks[PROMPT_REFRESH])
        and candidate==nil and valid(hud) and sprintPrompts.pending(hud)
end
local function promptEvent(context)
    local object=unwrap(context)
    if config.hideSprintPrompt and sprintPrompts and sameObject(object,hud) then
        if D.debugLogging then D.count("sprintPromptEvents") end
        sprintPrompts.queue(object)
        wake("sprintPrompt")
    end
end
local function promptRefreshed(context)
    if not config.hideSprintPrompt or not sprintPrompts or not valid(hud) then return end
    local object=unwrap(context)
    -- Native HUD dispatch can bypass its event wrapper. Observe the stock
    -- child refresh after it has assigned the text; accept only our two slots.
    if sameObject(object,hud.WBP_InputPrompt) or sameObject(object,hud.WBP_SecondInputPrompt) then
        if D.debugLogging then D.count("sprintPromptRefreshEvents") end
        sprintPrompts.queue(hud)
        wake("sprintPrompt")
    end
end
local function signal()
    if D.debugLogging then D.count("presetEvents") end
    if timeWatcher then timeWatcher.resume() end
    wake()
end
local function capture(context)
    sprintSource.recover()
    statsRefresh=true
    candidate = unwrap(context)
    wake()
end
local SPECIAL="/Game/_Dawnwalker/UI/_Unified/HUD/AbilityCooldowns/WBP_HUD_SpecialAttackCooldown.WBP_HUD_SpecialAttackCooldown_C"
local function currentPanelEvent(context,field)
    local object=unwrap(context)
    return valid(hud) and valid(controller) and sameObject(field and hud[field] or hud,object)
        and sameObject(object:GetOwningPlayer(),controller) and sameObject(object:GetWorld(),world)
end
local function cooldownEvent(context)
    if (panelOpacities.WBP_HUD_SpecialAttackCooldown or 0)~=0 then return end
    if not currentPanelEvent(context,"WBP_HUD_SpecialAttackCooldown") then return end
    -- Setup/finish update the stock Remaining Time before post delivery.
    -- The existing panel slice reads it, including during initial acquisition.
    fullPending=true
    absent.WBP_HUD_SpecialAttackCooldown=nil
    wake("cooldown")
end
local function switchedQuickslots(context,entryParam)
    -- Stock Toggle AA Quickslots delegate enters the graph at 4146.
    -- Observe that entry directly, also covering calls that bypass its stub.
    if tonumber(unwrap(entryParam))~=4146 then return end
    if config.switchRevealSeconds<=0 or not currentPanelEvent(context) then return end
    local focus=hud.CombatFocusPanel
    if valid(focus) and focus:IsActivated() then return end -- stock toggle guard
    switchRequested,statsPending=true,true
    wake("resource")
end
-- Blueprint paths verified against the stock WBP_GameHUD export table.
-- Native paths use an explicit post-hook; Blueprint callbacks are post-hooks.
local specs = {
    {path="/Script/DogwoodUI.HUDManagerSubsystem:PushHUDPreset", callback=signal, native=true},
    {path="/Script/DogwoodUI.HUDManagerSubsystem:PopHUDPreset", callback=signal, native=true},
    {path="/Script/Engine.PlayerController:ClientRestart", callback=function(context)
        local pc = unwrap(context)
        if valid(pc) and pc:IsLocalController() then
            statsRefresh=true
            controller = pc
            controllerAddress = pc:GetAddress()
            wake()
        end
    end, native=true},
    {path=ROOT..":Construct", callback=capture},
    {path=ROOT..":BP_OnActivated", callback=capture},
    {path=ROOT..":On Coen Form Changed", callback=capture},
    {path=ROOT..":Update Shown Stat Bar", callback=capture},
    {path="/Script/RebelSettings.RebelGameUserSettings:SetSetting", callback=refreshSettings, native=true},
    {path="/Script/RebelSettings.RebelGameUserSettings:SetSettingAsBool", callback=refreshSettings, native=true},
}
local function noop() end
local knownSpecs={}
for _,spec in ipairs(specs) do knownSpecs[spec.path]=true end
local function ensureFeatureSpecs()
    local first=#specs+1
if #statNames>0 then
    for _,entry in ipairs({
        {"WBP_HUD_HumanStats", "On HP changed", "health", "HumanStats"},
        {"WBP_HUD_VampireStats", "On HP changed", "health", "VampireStats"},
        {"WBP_HUD_VampireStats", "On Stamina changed", "stamina", "VampireStats"},
    }) do
        specs[#specs+1]={path=STAT_ROOT..entry[1].."."..entry[1].."_C:"..entry[2],
            callback=statEvent(entry[3],entry[4]), optional="resource"}
    end
    for _,entry in ipairs({
        {"WBP_HUD_HumanStats", "UpdateHealthBar", "HumanStats"},
        {"WBP_HUD_VampireStats", "Update Blood", "VampireStats"},
    }) do
        specs[#specs+1]={path=STAT_ROOT..entry[1].."."..entry[1].."_C:"..entry[2],
            callback=statUpdate(entry[3]), optional="resource"}
    end
end
if manualPeekEnabled then
    specs[#specs+1]={path=LEGEND..":ExecuteUbergraph_WBP_ControlsLegend", callback=peekInput, optional="peek"}
end
if sprintPrompts then
    specs[#specs+1]={path=ROOT..":OnSetInputPromptEnabled", callback=promptEvent, optional="prompt"}
    specs[#specs+1]={path=PROMPT_REFRESH, callback=promptRefreshed, optional="prompt"}
end
if timeRevealEnabled then
    specs[#specs+1]={path=TIME..":ExecuteUbergraph_WBP_HudTimer", callback=timeChanged, optional="time"}
    specs[#specs+1]={path=TIME..":Update Time Display", callback=timeDisplayUpdated, optional="time"}
end
if seen.WBP_HUD_SpecialAttackCooldown and (panelOpacities.WBP_HUD_SpecialAttackCooldown or 0)==0 then
    specs[#specs+1]={path=SPECIAL..":SetupCooldownEffect", callback=cooldownEvent, optional="panel"}
    specs[#specs+1]={path=SPECIAL..":OnCooldownFinished", callback=cooldownEvent, optional="panel"}
end
if config.switchRevealSeconds>0 and (seen.WBP_HUD_Quickslots or seen.WBP_AA_Quickslots) then
    specs[#specs+1]={path=ROOT..":ExecuteUbergraph_WBP_GameHUD", callback=switchedQuickslots, optional="panel"}
end
    local last=#specs
    local index=first
    for i=first,last do
        local spec=specs[i]
        if not knownSpecs[spec.path] then knownSpecs[spec.path]=true;specs[index]=spec;index=index+1 end
    end
    for i=index,last do specs[i]=nil end
end
ensureFeatureSpecs()
local function registerOne()
    if hookIndex > #specs then return true end
    local spec = specs[hookIndex]
    if hooks[spec.path] then hookIndex=hookIndex+1;return hookIndex>#specs end
    local success, pre, post
    if spec.native then
        success, pre, post = pcall(RegisterHook, spec.path, noop, spec.callback)
    else
        success, pre, post = pcall(RegisterHook, spec.path, spec.callback)
    end
    if success and type(pre) == "number" and type(post) == "number" then
        hooks[spec.path] = {pre, post}
        hookIndex = hookIndex + 1
        hookAttempt=0
        if D.debugLogging then D.event("hook","registered=%s",spec.path) end
        return hookIndex > #specs
    end
    reportHookError(spec.path, success, pre, post)
    if spec.optional then
        hookAttempt=hookAttempt+1
        if hookAttempt>=12 then
            failedHooks[spec.optional]=failedHooks[spec.optional] or hookIndex
            if spec.optional=="time" then
                print("[Quiet Dawn - Configurable HUD] Time-change hook unavailable; time panel keeps its configured opacity.")
            elseif spec.optional=="panel" then
                print("[Quiet Dawn - Configurable HUD] Panel event unavailable; other HUD controls remain active: "..spec.path)
            elseif spec.optional=="prompt" then
                if D.debugLogging then D.event("sprintPrompt","prompt hook unavailable: %s",spec.path) end
            elseif spec.optional=="peek" then
                print("[Quiet Dawn - Configurable HUD] Manual peek input unavailable; automatic health alerts remain enabled.")
            else
                statHookFailures=true
                print("[Quiet Dawn - Configurable HUD] Resource event hook unavailable; stat panels left to the game: "..spec.path)
            end
            hookIndex=hookIndex+1
            hookAttempt=0
        end
    end
    return hookIndex > #specs
end
registerOne=D.wrap("hook",registerOne)
local function accept(object)
    if not valid(object) then return false, "invalid HUD" end
    local pc = object:GetOwningPlayer()
    if not valid(pc) then return false, "missing owning player" end
    if not pc:IsLocalController() then return false, "non-local owning player" end
    local objectWorld = object:GetWorld()
    if not sameObject(objectWorld,pc:GetWorld()) then return false, "world mismatch" end
    if valid(controller) and not sameObject(controller,pc) then return false, "controller mismatch" end
    if not sameObject(object,hud) or not sameObject(objectWorld,world) then
        hud, world, panels, absent = object, objectWorld, {}, {}
        if timeWatcher then timeWatcher.reset() end
        lastPawnAddress, lastCombatAddress, previousHealth, previousStamina = nil, nil, nil, nil
        lastBloodAddress,lastForm=nil,nil
        lastBloodCapacity=nil
        previousHealthAmount=nil
        fullRecoveryArmed=false
        healthUntil, staminaUntil = 0, 0
        peekRequested,peekUntil,peekVisible=false,0,false
        timeRequested,timeDirty,timeVisible,timeUntil=false,false,false,0
        switchRequested,switchUntil,switchVisible=false,0,false
        switchCursor=0
        statsRefresh=true
        healthDropped,staminaDropped=false,false
        if D.debugLogging then D.event("lifecycle","HUD/world changed; cached state reset") end
    end
    controller = pc
    if timeWatcher then timeWatcher.resume() end
    hudAddress, controllerAddress = object:GetAddress(), pc:GetAddress()
    if sprintPrompts then sprintPrompts.queue(object) end
    if manualPeekEnabled then
        local legend=object.WBP_ControlsLegend
        peekWidgetAddress=valid(legend) and legend:GetAddress() or nil
        peekControllerAddress=controllerAddress
    end
    return true
end
local function snapshot()
    if not valid(hud) or not valid(controller) then return nil end
    if not sameObject(hud:GetWorld(),world) or not sameObject(controller:GetWorld(),world)
        or not sameObject(hud:GetOwningPlayer(),controller) then return nil end
    local pawn = controller.Pawn
    if not valid(pawn) or not sameObject(pawn:GetWorld(),world) then return nil end
    local now = frameClock:GetGameTimeInSeconds(controller)
    local pawnAddress=pawn:GetAddress()
    if lastPawnAddress~=pawnAddress then
        previousHealth,previousStamina,previousHealthAmount=nil,nil,nil
        fullRecoveryArmed=false
        lastBloodCapacity=nil
        lastCombatAddress=nil
        healthUntil,staminaUntil=0,0
        if peekVisible then fullPending,dirty=true,true end
        peekUntil,peekVisible=0,false
        if switchVisible then switchCursor=1 end
        switchUntil,switchVisible=0,false
        lastPawnAddress=pawnAddress
    end
    -- Peeking only needs a current player and the game clock. It also works
    -- with both dynamic panels disabled or unavailable resource readings.
    if peekRequested then
        peekUntil=now+config.manualPeekSeconds
        if not peekVisible then fullPending,dirty=true,true end
        peekVisible=true
        if D.debugLogging then D.event("manualPeek","player HUD visible for %.1fs",config.manualPeekSeconds) end
    end
    if switchRequested then
        switchUntil=now+config.switchRevealSeconds
        if not switchVisible then switchCursor=1 end
        switchVisible=true
        if D.debugLogging then D.event("quickslotReveal","visible for %.1fs",config.switchRevealSeconds) end
    end
    if #statNames==0 then return 0 end
    if statHookFailures then return nil end
    local combat = pawn.CombatComponent
    if not valid(combat) then return nil end
    -- Match the resource displayed by the game's active stat widget.
    -- Form 0/1 and PlayerState.BloodBar are verified in the stock HUD.
    local form=tonumber(pawn.Form)
    local health,bloodAddress,healthAmount
    local lossTolerance=0.000001
    local healingScale=1
    if form==0 then
        lastBloodCapacity=nil
        health=tonumber(combat:GetHealthPercentage())
        healthAmount=health
    elseif form==1 then
        local playerState=controller.PlayerState
        if not valid(playerState) then return nil end
        local blood=playerState.BloodBar
        if not valid(blood) then return nil end
        local amount=tonumber(blood:GetBlood())
        local capacity=tonumber(blood:GetBloodBarLength())
        if not amount or not capacity or amount~=amount or capacity~=capacity
            or amount<0 or amount==math.huge or capacity<=0 or capacity==math.huge then return nil end
        -- Overdrinking can exceed the normal bar; it is not invalid health.
        health=math.min(1,amount/capacity)
        healthAmount=amount
        -- A capacity change is a new baseline, not healing or completion.
        if lastBloodCapacity and lastBloodCapacity~=capacity then
            previousHealthAmount=nil
            fullRecoveryArmed=false
        end
        lastBloodCapacity=capacity
        healingScale=capacity
        lossTolerance=capacity*0.002 -- 0.2% blood jitter margin; thresholds remain exact
        bloodAddress=blood:GetAddress()
    else
        return nil -- unknown/transitional forms retain game control
    end
    local stamina = tonumber(combat:GetStaminaPercentage())
    if not health or not stamina or health ~= health or stamina ~= stamina
        or health < 0 or stamina < 0 or health > 1 or stamina > 1 then return nil end
    local combatAddress=combat:GetAddress()
    if lastCombatAddress~=combatAddress then
        previousHealth, previousStamina = nil, nil
        previousHealthAmount=nil
        fullRecoveryArmed=false
        healthUntil, staminaUntil = 0, 0
        lastCombatAddress = combatAddress
    end
    if lastForm~=form or lastBloodAddress~=bloodAddress then
        previousHealth=nil
        previousHealthAmount=nil
        fullRecoveryArmed=false
        healthUntil=0
        lastForm,lastBloodAddress=form,bloodAddress
        if D.debugLogging then D.event("resourceSource","form=%d source=%s",form,form==1 and "blood" or "health") end
    end
    -- The same resource events report losses and gains. Use the current
    -- resource snapshot: human events carry HP units, blood events carry blood.
    -- Gains of 0.2% renew the hold; smaller gains reveal only on full recovery.
    local gain=previousHealthAmount and healthAmount-previousHealthAmount or 0
    local healed=gain>0 and gain+healingScale*FULL_EPSILON>=healingScale*HEALING_REVEAL_GAIN
    local reachedFull=fullRecoveryArmed and health>=1-FULL_EPSILON
    if health<=1-FULL_REARM_GAP then fullRecoveryArmed=true
    elseif health>=1-FULL_EPSILON then fullRecoveryArmed=false end
    if healthDropped or (previousHealthAmount and healthAmount < previousHealthAmount - lossTolerance)
        or healed or reachedFull then
        healthUntil = now + config.healthHoldSeconds
        if D.debugLogging and (healed or reachedFull) then
            D.count(reachedFull and "fullRecoveryReveals" or "healingReveals")
            D.event("healthReveal","reason=%s gain=%.4f hold=%.1fs",
                reachedFull and "full" or "healing",gain/healingScale,config.healthHoldSeconds)
        end
    end
    if staminaDropped or (previousStamina and stamina < previousStamina - 0.000001) then
        staminaUntil = now + config.staminaHoldSeconds
    end
    healthDropped,staminaDropped=false,false
    previousHealth, previousStamina = health, stamina
    previousHealthAmount=healthAmount
    local needed = health < config.healthThreshold or stamina < config.staminaThreshold
        or now < healthUntil or now < staminaUntil or now < peekUntil
    if D.debugLogging then D.vitals(health,stamina,needed,now,healthUntil,staminaUntil) end
    return needed and 1 or 0
end
snapshot=D.wrap("sample",snapshot)
local function panelStep(name)
    -- Revalidate ownership inside every deferred operation, including a still
    -- valid HUD left over from the previous world.
    if valid(hud) and valid(controller) and sameObject(hud:GetWorld(),world)
        and sameObject(controller:GetWorld(),world) and sameObject(hud:GetOwningPlayer(),controller) then
        if absent[name] then return true end
        local widget = hud[name]
        local object = widget
        -- Use dedicated containers outside the game's widget fade tracks.
        -- Verified stock hierarchy: hint -> one-child attachment;
        -- WBP_SpecialAttack -> inner HorizontalBox_0;
        -- focus ButtonImage -> inner HorizontalBox_43 (button and label only).
        if valid(widget) then
            if name=="WBP_HUD_Quickslots_ChangePrompt" then object=widget:GetParent()
            elseif name=="WBP_HUD_SpecialAttackCooldown" then
                local content=widget.WBP_SpecialAttack
                object=valid(content) and content:GetParent() or nil
            elseif name=="WBP_OpenFocusPrompt" then
                -- Its Show animation writes the root opacity on entering Focus.
                local content=widget.ButtonImage
                object=valid(content) and content:GetParent() or nil
            end
        end
        if valid(object) then
            local current = object:GetRenderOpacity()
            local entry = panels[name]
            if not entry or not sameObject(entry.object,object) then
                entry = {object=object, original=current}
                panels[name]=entry
            end
            if manualPeekEnabled and name=="WBP_ControlsLegend" then
                peekWidgetAddress,peekControllerAddress=object:GetAddress(),controllerAddress
            end
            local isStats = name == "HumanStats" or name == "VampireStats"
            local target = panelOpacities[name] or 0
            if name=="WBP_Compass" and config.compassOpacity~=nil then target=config.compassOpacity end
            -- Zero opacity preserves resource-driven hiding and revealing.
            -- Missing readings retain the game's opacity.
            if isStats and dynamicPanels[name] then
                target = desired == 1 and (stateReady and 1 or entry.original) or 0
            end
            if name=="WBP_HudTimer" and timeVisible then target=1 end
            if name=="WBP_HUD_SpecialAttackCooldown" and target==0 then
                local display=widget.WBP_CooldownDisplay
                local remaining=valid(display) and tonumber(display["Remaining Time"]) or nil
                if not hooks[SPECIAL..":SetupCooldownEffect"] or not hooks[SPECIAL..":OnCooldownFinished"] then
                    target=entry.original -- unavailable events retain game control
                else target=remaining and remaining>0 and remaining<math.huge and 1 or 0 end
            end
            if switchVisible and target==0 and (name=="WBP_HUD_Quickslots" or name=="WBP_AA_Quickslots") then target=1 end
            if peekVisible and name~="WBP_HUD_Quickslots_ChangePrompt" and name~="WBP_HUD_SpecialAttackCooldown"
                and name~="WBP_OpenFocusPrompt" then target=1 end
            -- UWidget stores float opacity: e.g. 0.4 returns 0.400000006.
            -- Match the session journal's tolerance over the opacity range.
            local wroteOpacity=false
            if math.abs(current-target)>1e-5 then
                wroteOpacity=opacity(object, target)
                if wroteOpacity and D.debugLogging then D.count("panelWrites");D.event("panel","name=%s opacity=%.3f->%.3f",name,current,target) end
            end
            if panelScaling then
                -- Keep opacity and each transform phase in separate frame slices.
                if wroteOpacity and panelScaling.pending(name,entry) then return false end
                return panelScaling.step(name,object,entry)
            end
        elseif attempts < 120 then
            attempts=attempts+1
            return false
        else
            -- Missing fields stay absent until a lifecycle/preset event.
            -- Resource changes must not restart readiness retries.
            absent[name]=true
            if D.debugLogging then D.event("missing","panel=%s; retries exhausted",name) end
        end
    else
        hud, world, panels = nil, nil, {}
        hudAddress=nil
        peekWidgetAddress,peekControllerAddress=nil,nil
        timeRequested,timeDirty,timeVisible,timeUntil=false,false,false,0
    end
    return true
end
local timeTurn=false
local timeSampleTurn=false
local function step()
    if livePending then applyLiveSettings(true);return false end
    if sprintSource.pending() then sprintSource.step();return false end
    -- At most one hook registration OR one state snapshot OR one direct panel
    -- read/write per callback. 16 ms delay yields to a later game frame.
    if clawMarks and clawMarks.pending() then
        clawMarks.step()
        return false
    end
    if hookIndex <= #specs then
        if hookIndex > 3 and candidate == nil and not valid(hud) then
            worker=false
            return true
        end
        registerOne()
        attempts = attempts + 1
        if attempts >= 120 then
            if not warned then print("[Quiet Dawn - Configurable HUD] HUD hooks not ready; waiting for a lifecycle event."); warned=true end
            worker=false
            return true
        end
        return false
    end
    if markerSeen and markerHookIndex<=#markerSpecs and markerHookAttempts<12 then
        markerHooksStep()
        return false
    end
    if settingsPending and markerSeen then
        settingsStep()
        return false
    end
    promptTurn=not promptTurn
    if promptsReady() and promptTurn then
        if valid(controller) and sameObject(hud:GetWorld(),world) and sameObject(controller:GetWorld(),world)
            and sameObject(hud:GetOwningPlayer(),controller) then sprintPrompts.step(hud)
        else sprintPrompts.cancel() end
        return false
    end
    timeSampleTurn=not timeSampleTurn
    if timeSampleTurn and timeWatcher and timeWatcher.pending() and candidate==nil then
        if valid(hud) and valid(controller) and sameObject(hud:GetWorld(),world)
            and sameObject(controller:GetWorld(),world) and sameObject(hud:GetOwningPlayer(),controller) then
            if timeWatcher.step(hud,hud.WBP_HudTimer) then
                timeUntil=frameClock:GetGameTimeInSeconds(controller)+config.timeHoldSeconds
                timeRequested=true
                if D.debugLogging then D.count("timeChangeEvents") end
            end
        else timeWatcher.cancel() end
        return false -- subsystem reads get their own worker frame
    end
    -- A short time reveal must not wait behind a full quickslot/peek pass.
    -- Consume coalesced deadlines cheaply; only visibility changes take a
    -- panel slice. Alternate such slices so other jobs still make progress.
    if timeRequested and candidate==nil then
        timeRequested=false
        if valid(hud) and valid(controller) and sameObject(hud:GetWorld(),world)
            and sameObject(controller:GetWorld(),world) and sameObject(hud:GetOwningPlayer(),controller) then
            local showing=frameClock:GetGameTimeInSeconds(controller)<timeUntil
            if timeVisible~=showing then timeVisible,timeDirty=showing,true end
            if D.debugLogging then D.event("timeReveal","time panel visible for %.1fs",config.timeHoldSeconds) end
            armExpiry()
        end
    end
    timeTurn=not timeTurn
    if timeDirty and candidate==nil and timeTurn then
        if panelStep("WBP_HudTimer") then timeDirty=false end
        armExpiry()
        return false
    end
    -- Switching only changes these two panels. Share the priority slices
    -- with time changes instead of waiting behind all unrelated HUD panels.
    if switchCursor>0 and candidate==nil and timeTurn then
        local name=switchJobNames[switchCursor]
        if not seen[name] or panelStep(name) then switchCursor=switchCursor+1 end
        if switchCursor>#switchJobNames then switchCursor=0 end
        return false
    end
    -- Alternate with existing work: one health child operation per frame,
    -- sharing the same one-shot worker and its native frame gate.
    healthTurn=not healthTurn
    if healthReady() and (healthTurn or (cursor==0 and not dirty and not statsPending and not markersReady())) then
        healthStep()
        return false
    end
    -- Coalesce resource events; no timer requests resource reads.
    if statsPending and candidate==nil and cursor==0 and not dirty then
        statsPending=false
        local wasReady=stateReady
        local success,value=pcall(snapshot)
        peekRequested,switchRequested=false,false
        stateReady=success and value~=nil
        if not stateReady then healthDropped,staminaDropped=false,false end
        local target=stateReady and value or 1
        if target~=desired or wasReady~=stateReady then desired=target;dirty=true end
        armExpiry()
        return false
    end
    local changedPanel=next(livePanels)
    if changedPanel and candidate==nil then
        if panelStep(changedPanel) then livePanels[changedPanel]=nil end
        return false
    end
    markerTurn=not markerTurn
    if markersReady() and (markerTurn or (cursor==0 and not dirty)) then
        local success, reason=pcall(markerStep)
        if not success then print("[Quiet Dawn - Configurable HUD] Marker update skipped: "..tostring(reason)) end
        return false
    end
    if cursor==0 and not dirty and timeDirty then
        timeDirty=false
        jobNames=timeJobNames
        cursor=1
        return false
    end
    if cursor==0 and not dirty then
        if switchCursor>0 or timeRequested or (timeWatcher and timeWatcher.pending()) or markersReady() or healthReady() or promptsReady() then return false end
        worker=false
        armExpiry()
        return true
    end
    if cursor == 0 then
        dirty = false
        if candidate then
            local accepted, reason=accept(candidate)
            if accepted then
                candidate=nil
                dirty=true
                return false -- ownership acceptance and resource reads use separate frames
            else
                attempts=attempts+1
                if D.debugLogging then
                    D.count("hudNotReady")
                    if attempts==1 or attempts==120 then
                        D.event("lifecycle","HUD ownership not ready; reason=%s attempt=%d/120",reason,attempts)
                    end
                end
                -- Preserve the job while ownership becomes ready. Clearing
                -- dirty here used to terminate the worker after one attempt.
                if attempts < 120 then dirty=true; return false end
                candidate=nil
            end
        end
        fullJob, fullPending = fullPending, false
        if fullJob then timeDirty=false end
        jobNames = fullJob and names or statNames
        -- Resource events already supplied a fresh snapshot; only lifecycle jobs read again.
        if fullJob then
            if #statNames > 0 and statsRefresh then
                statsRefresh=false
                local success, value = pcall(snapshot)
                peekRequested,switchRequested=false,false
                stateReady = success and value ~= nil
                desired = stateReady and value or 1
            elseif #statNames==0 then
                stateReady, desired = false, 0
            end
        end
        cursor=1
        return false
    end
    if cursor <= #jobNames then
        if panelStep(jobNames[cursor]) then cursor=cursor+1 end
        return false
    end
    cursor=0
    if switchCursor>0 or dirty or statsPending or timeRequested or timeDirty or (timeWatcher and timeWatcher.pending()) or markersReady() or healthReady() or promptsReady() then return false end
    attempts=0
    worker=false
    armExpiry()
    return true -- the panel worker stops; no recurring resource worker remains
end
step=D.wrap("worker",step)
-- UE4SS repeating timers ignore return values. Chain one-shots explicitly.
local function repeatUntilDone(delay,fn)
    local function tick()
        if not fn() then ExecuteInGameThreadWithDelay(delay,tick) end
    end
    ExecuteInGameThreadWithDelay(delay,tick)
end
wake = function(statsOnly)
    if not statsOnly then
        if panelScaling then panelScaling.recover() end
        if failedHooks.resource then
            statHookFailures=false
            statsRefresh=true
        end
        for _,index in pairs(failedHooks) do hookIndex=math.min(hookIndex,index) end
        failedHooks={}
        fullPending=true
        absent={}
        settingsPending,settingsAttempts=true,0
    end
    if statsOnly~="marker" and statsOnly~="settings" and statsOnly~="resource" and statsOnly~="enemyHealth" and statsOnly~="time" and statsOnly~="sprintPrompt" and statsOnly~="clawMarks" and statsOnly~="liveSettings" then dirty=true end
    if worker then if D.debugLogging then D.count("workerCoalesced") end; return end
    worker=true
    if D.debugLogging then D.count("workerStarts") end
    attempts=0
    repeatUntilDone(16, function()
        local success, stop = pcall(function()
            if not valid(frameClock) then
                frameClock=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                if not valid(frameClock) then
                    worker=false
                    print("[Quiet Dawn - Configurable HUD] Frame clock unavailable; waiting for a lifecycle event.")
                    return true
                end
            end
            local frame=frameClock:GetFrameCount()
            if frame == lastFrame then return false end
            lastFrame=frame
            return step()
        end)
        if not success then
            worker=false
            cursor=0
            print("[Quiet Dawn - Configurable HUD] Update failed: "..tostring(stop))
            return true
        end
        return stop
    end)
end
applyLiveSettings=function(run)
    if not run then wake('liveSettings');return end
    local values=livePending;livePending=nil
    local updated=require('SettingsModel').convert(values)
    local changed={}
    for key,value in pairs(updated) do
        if type(value)~='table' and config[key]~=value then changed[key]=true end
    end
    for _,name in ipairs(names) do
        if panelOpacities[name]~=updated.panelOpacities[name] then livePanels[name]=true;absent[name]=nil end
        if panelScales[name]~=updated.panelScales[name] then
            if not panelScaling then panelScaling=require('QuietDawnPanelScale').new(panelScales,D,Session) end
            panelScaling.configure(name,updated.panelScales[name]);livePanels[name]=true;absent[name]=nil
        end
        panelOpacities[name]=updated.panelOpacities[name]
        panelScales[name]=updated.panelScales[name]
    end
    for key,value in pairs(updated) do if type(value)~='table' then config[key]=value end end
    dynamicPanels.HumanStats,dynamicPanels.VampireStats=updated.dynamicPanels.HumanStats,updated.dynamicPanels.VampireStats
    statNames={}
    for _,name in ipairs({'HumanStats','VampireStats'}) do if dynamicPanels[name] then statNames[#statNames+1]=name end end
    manualPeekEnabled=config.manualPeek and config.manualPeekSeconds>0 and #names>0
    timeRevealEnabled=seen.WBP_HudTimer and (panelOpacities.WBP_HudTimer or 0)==0 and config.timeHoldSeconds>0
    if changed.debugLogging and QuietDawnNative then QuietDawnNative.setLogging(config.debugLogging) end
    if changed.healthThreshold or changed.staminaThreshold or changed.healthHoldSeconds or changed.staminaHoldSeconds
        or changed.opacity_HumanStats or changed.opacity_VampireStats then
        healthUntil,staminaUntil=0,0
        statsPending,statsRefresh=true,true
        livePanels.HumanStats,livePanels.VampireStats=true,true
    end
    if changed.manualPeek or changed.manualPeekSeconds then
        if peekVisible then for _,name in ipairs(names) do livePanels[name]=true end end
        peekRequested,peekVisible,peekUntil=false,false,0
    end
    if changed.timeHoldSeconds or changed.opacity_WBP_HudTimer then
        timeWatcher=timeRevealEnabled and require("QuietDawnTime").new(D) or nil
        if timeWatcher then timeWatcher.reset() end
        timeRequested,timeVisible,timeUntil=false,false,0;livePanels.WBP_HudTimer=true
    end
    if changed.switchRevealSeconds then
        switchRequested,switchVisible,switchUntil=false,false,0
        livePanels.WBP_HUD_Quickslots,livePanels.WBP_AA_Quickslots=true,true
    end
    if changed.hideSprintPrompt then
        sprintSource.configure(config.hideSprintPrompt)
        if not sprintPrompts and config.hideSprintPrompt then
            sprintPrompts=require('QuietDawnSprintPrompt').new({StaticFindObject=StaticFindObject,FName=FName,opacity=opacity,D=D,source=sprintSource})
        end
        if sprintPrompts then sprintPrompts.setEnabled(config.hideSprintPrompt);sprintPrompts.queue(hud) end
    end
    if changed.debugLogging and not changed.hideSprintPrompt then sprintSource.configure(config.hideSprintPrompt) end
    if changed.hideClawSlashMarks then
        if not clawMarks and config.hideClawSlashMarks then
            clawMarks=require('QuietDawnClawMarks').new(D,Session,function()wake('clawMarks')end)
        end
        if clawMarks then clawMarks.configure(config.hideClawSlashMarks) end
    end
    if changed.hideEnemyHealthBars or changed.hideEnemyNames or changed.hideEnemyDifficultyIcons then
        local fields={{'SegmentedHealthBar','HealthBarLeftCap','HealthBarRightCap','LevelIndicator'},
            {'HealthBar','HealthBarLeftCap','HealthBarRightCap','IndicatorBox','BossNameLabel','LevelIndicator'}}
        for index,spec in ipairs(healthTypes) do
            local affected={};spec.fields={}
            for _,field in ipairs(fields[index]) do
                local setting=field=='BossNameLabel' and 'hideEnemyNames' or (field=='LevelIndicator' and 'hideEnemyDifficultyIcons' or 'hideEnemyHealthBars')
                if config[setting] then spec.fields[#spec.fields+1]=field end
                if changed[setting] then affected[#affected+1]=field end
            end
            for _,object in ipairs(spec.recent or {}) do queueHealth(object,spec,affected) end
        end
    end
    if changed.showCounterattackDirection or changed.showUnblockableWarning or changed.showDirectionalParry
        or changed.showLockIcon or changed.combatCueSize then
        for _,entry in pairs(markerCache) do queueMarker(entry.object) end
    end
    ensureFeatureSpecs()
    -- Existing reveal expiry owns its one deadline; changes cancel/rearm it.
    if changed.healthThreshold or changed.staminaThreshold or changed.healthHoldSeconds or changed.staminaHoldSeconds
        or changed.manualPeek or changed.manualPeekSeconds or changed.timeHoldSeconds or changed.switchRevealSeconds then armExpiry() end
end

if config.hideClawSlashMarks then
    clawMarks=require('QuietDawnClawMarks').new(D,Session,function()wake('clawMarks')end)
end
local subscribed = pcall(NotifyOnNewObject, ROOT, function(object)
    candidate=object -- construction is not readiness: defer all object reads
    sprintSource.recover()
    wake()
end)
if not subscribed then
    print("[Quiet Dawn - Configurable HUD] HUD lifecycle notification unavailable; disabled.")
    return
end
pcall(NotifyOnNewObject,PROMPT_WIDGET,function()
    -- Construction only wakes the existing finite worker/rebind window.
    -- It is not safe to inspect a newly constructed widget here.
    if config.hideSprintPrompt and sprintPrompts and hudAddress then
        candidate=candidate or hud
        wake()
    end
end)
if seen.WBP_HudTimer then
    local timeSubscribed=pcall(NotifyOnNewObject,TIME,function()
        -- Construction only wakes finite readiness/rebinding; it is not time passing.
        if timeWatcher then timeWatcher.recover() end
        if hudAddress then wake() end
    end)
    if not timeSubscribed then print("[Quiet Dawn - Configurable HUD] Time panel lifecycle notification unavailable.") end
end
local markerSubscribed=pcall(NotifyOnNewObject, MARKER, function(object)
    markerSeen=true
    markerHookAttempts=0
    queueMarker(object)
end)
if not markerSubscribed then
    print("[Quiet Dawn - Configurable HUD] Marker lifecycle notification unavailable; marker left to the game.")
end
for _,spec in ipairs(healthTypes) do
    do
        local subscribedHealth=pcall(NotifyOnNewObject,spec.path,function(object)
            if spec.failedEvent then
                spec.eventIndex=spec.failedEvent;spec.failedEvent=nil;spec.hookAttempts=0
            end
            queueHealth(object,spec)
        end)
        if not subscribedHealth then print("[Quiet Dawn - Configurable HUD] Enemy health notification unavailable: "..spec.path) end
    end
end
-- At most one outstanding hide deadline. It reads cached percentages and the
-- game clock only. A pause/extended hold reschedules its remaining delay; once
-- settled or below threshold there is no timer and no resource polling.
-- A full-HUD peek expires independently of low health, then the same deadline
-- can finish any longer damage/stamina hold without hiding the low-health bar.
armExpiry = function()
    local now=valid(frameClock) and valid(controller) and frameClock:GetGameTimeInSeconds(controller) or nil
    local eligible=now and stateReady and previousHealth and previousStamina
        and previousHealth>=config.healthThreshold and previousStamina>=config.staminaThreshold
    local remaining=eligible and math.max(healthUntil,staminaUntil)-now or 0
    -- One deadline serves resource alerts, manual peek and switching.
    for _,deadline in ipairs({peekVisible and peekUntil or false,switchVisible and switchUntil or false,timeVisible and timeUntil or false}) do
        if deadline and now then
            local delay=math.max(0.016,deadline-now)
            remaining=remaining>0 and math.min(remaining,delay) or delay
        end
    end
    if expiryPending then
        local sameOwner=expiryHUD==hudAddress and expiryController==controllerAddress and expiryPawn==lastPawnAddress
        if remaining>0 and sameOwner and expiryDue<=now+remaining then return end
        CancelDelayedAction(expiryHandle)
        expiryPending,expiryHandle=false,nil
    end
    if remaining<=0 then return end
    expiryPending=true
    expiryDue=now+remaining
    local ownedHUD,ownedController,ownedPawn=hudAddress,controllerAddress,lastPawnAddress
    expiryHUD,expiryController,expiryPawn=ownedHUD,ownedController,ownedPawn
    expiryHandle=ExecuteInGameThreadWithDelay(math.max(16,math.ceil(remaining*1000)),function()
        expiryPending,expiryHandle=false,nil
        if ownedHUD~=hudAddress or ownedController~=controllerAddress or ownedPawn~=lastPawnAddress then
            armExpiry()
            return
        end
        if not valid(hud) or not valid(controller) or not valid(frameClock)
            or not sameObject(hud:GetWorld(),world) or not sameObject(hud:GetOwningPlayer(),controller) then return end
        local now=frameClock:GetGameTimeInSeconds(controller)
        local endedTime=timeVisible and now>=timeUntil
        if endedTime then
            timeVisible=false
            timeDirty=true
            if D.debugLogging then D.event("timeReveal","time-change reveal ended") end
        end
        local endedPeek=peekVisible and now>=peekUntil
        if endedPeek then
            peekVisible=false
            fullPending=true
            if D.debugLogging then D.event("manualPeek","ended; automatic HUD visibility restored") end
        end
        local endedSwitch=switchVisible and now>=switchUntil
        if endedSwitch then
            switchVisible=false
            switchCursor=1
            if D.debugLogging then D.event("quickslotReveal","ended") end
        end
        local needed=not stateReady or (previousHealth and previousHealth<config.healthThreshold)
            or (previousStamina and previousStamina<config.staminaThreshold)
            or now<healthUntil or now<staminaUntil or peekVisible
        local target=needed and 1 or 0
        if endedPeek or endedSwitch or desired~=target then desired=target;wake(true)
        elseif endedTime then wake("time")
        else armExpiry() end
    end)
end
wake()
