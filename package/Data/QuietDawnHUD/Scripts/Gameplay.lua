-- Gameplay.lua
-- Quiet Dawn - Configurable HUD | MIT License
local D = require("QuietDawnDiagnostics")
-- Event-driven panel opacity. The normal path has no widget-tree walks,
-- animation hooks or Lua coroutines. A separately bounded Debug-only
-- Quickslot probe may inspect one known widget tree while discovering a stock
-- combat route. Claw marks discover two exact cue classes once per enablement.
-- Resource reads run only on resource-change and HUD/player lifecycle events.
local ok, config = pcall(require, "MenuSettings")
if SaveLoadDiagnostics and ok and type(config)=="table" then
    SaveLoadDiagnostics.debugLogging = config.debugLogging == true
    SaveLoadDiagnostics.logLevel = config.logLevel
end
if not ok or type(config) ~= "table" then
    D.logError("Invalid configuration; HUD left to the game.")
    return
end
local Modes=require("QuietDawnPanelModes")
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
        D.logError("Unknown or duplicate panel; disabled.")
        return
    end
    seen[name] = true
    names[#names+1] = name
end
if type(config.enabled) ~= "boolean" then return end
if config.compassOpacity~=nil and (type(config.compassOpacity)~="number"
    or config.compassOpacity~=config.compassOpacity or config.compassOpacity<0 or config.compassOpacity>1) then
    D.logError("Invalid compass opacity; disabled.")
    return
end
for _, key in ipairs({"healthThreshold", "staminaThreshold"}) do
    local value=config[key]
    if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
        D.logError("Invalid threshold; disabled.")
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
        D.logError("Invalid hold duration; disabled.")
        return
    end
end
local playerEffects,clawHits
local livePending,applyLiveSettings
local livePanels={}
Session.onSettings(function(values)
    if (values.enabled==1)~=config.enabled then Session.restart();return end
    D.setLevel(values.logLevel)
    if SaveLoadDiagnostics then SaveLoadDiagnostics.debugLogging=D.debugLogging;SaveLoadDiagnostics.logLevel=values.logLevel end
    if applyLiveSettings then
        livePending=values
        -- The persistent subscription only queues owned data.
        applyLiveSettings(false)
    end
end)
if not config.enabled then return end
local applyCombatCue=require("QuietDawnCombatCues").new(config,D,Session)
local combatGuard=require("QuietDawnCombatGuard").new(config,D,Session)
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
local panelModes = config.panelModes or {}
local panelScales = config.panelScales or {}
local hasPanelScaling=false
for _, name in ipairs(names) do
    if panelModes[name]~=Modes.VANILLA and panelModes[name]~=Modes.QUIET_DAWN
        and panelModes[name]~=Modes.FIXED_OPACITY and panelModes[name]~=Modes.ALWAYS_HIDDEN then
        D.logError("Invalid panel mode; disabled.")
        return
    end
    local scale=panelScales[name] or 1
    if type(scale)~="number" or scale~=scale or scale<0.25 or scale>2
        or math.abs(scale*20-math.floor(scale*20+0.5))>1e-6 then
        D.logError("Invalid panel size; disabled.")
        return
    end
    if scale~=1 then hasPanelScaling=true end
    local value=panelOpacities[name]
    if value~=nil and (type(value)~="number" or value~=value or value<0 or value>1) then
        D.logError("Invalid panel opacity; disabled.")
        return
    end
    if (name == "HumanStats" or name == "VampireStats") and dynamicPanels[name] then
        statNames[#statNames+1]=name
    end
end
local panelScaling=hasPanelScaling and require("QuietDawnPanelScale").new(panelScales,D,Session) or nil
local function hasPeekPanels()
    for _,name in ipairs(names) do
        local quietDawnIncluded=panelModes[name]==Modes.QUIET_DAWN and name~="CombatFocusPanel"
            and name~="WBP_HUD_Quickslots_ChangePrompt" and name~="WBP_HUD_SpecialAttackCooldown"
            and name~="WBP_OpenFocusPrompt"
            and (not config.showHUDPanels or config.showHUDPanels[name]~=false)
        local fixedRaise=panelModes[name]==Modes.FIXED_OPACITY
            and config.fixedPeekPanels and config.fixedPeekPanels[name]==true
        if quietDawnIncluded or fixedRaise then return true end
    end
    return false
end
local function hasSwitchPanels()
    return panelModes.WBP_HUD_Quickslots==Modes.QUIET_DAWN or panelModes.WBP_AA_Quickslots==Modes.QUIET_DAWN
end
-- A zero duration disables timed legend/exit holds, not the time the player
-- actively remains in Focus. Focus itself is an untimed stateful reveal.
local manualPeekEnabled=config.manualPeek and hasPeekPanels()
local timeRevealEnabled=seen.WBP_HudTimer and panelModes.WBP_HudTimer==Modes.QUIET_DAWN and config.timeHoldSeconds>0
if type(ExecuteInGameThreadWithDelay) ~= "function" or type(CancelDelayedAction) ~= "function" then
    D.logError("Requires cancellable delayed game-thread callbacks; disabled.")
    return
end

D.logInfo("active: managing %d panel(s), manual peek %s",#names,config.manualPeek and "on" or "off")
if D.debugLogging then D.event("config","healthThreshold=%.3f staminaThreshold=%.3f healthHold=%.3fs staminaHold=%.3fs panels=%d",config.healthThreshold,config.staminaThreshold,config.healthHoldSeconds,config.staminaHoldSeconds,#names) end
local ROOT = "/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C"
local hud, candidate, candidateSource, controller, world
local hudAddress, controllerAddress
local worker, dirty, stateReady = false, false, false
local statsPending, expiryPending = false, false
local statsRefresh=true
local statReassert=false
local expiryHandle,expiryDue,expiryHUD,expiryController,expiryPawn
local healthDropped, staminaDropped = false, false
local statHookFailures, hookAttempt = false, 0
local failedHooks = {}
local timeRequested,timeDirty,timeVisible,timeUntil=false,false,false,0
local timeJobNames={"WBP_HudTimer"}
local timeWatcher=timeRevealEnabled and require("QuietDawnTime").new(D) or nil
local peekRequested,peekUntil,peekVisible=false,0,false
local peekStartPending=false
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
local panelOpacity=require("QuietDawnPanelOpacity").new(Session,D)

local peekDirty,statDirty,refreshDirty=false,false,false
local panelRetries={}
local priorityTurn=0
local absent, jobNames, fullPending, fullJob = {}, names, false, true
local cursor, desired, attempts = 0, 1, 0
local hooks, hookIndex = {}, 1
local hookErrors = {}
local function reportHookError(path, success, pre, post)
    if hookErrors[path] then return end
    hookErrors[path] = true
    -- Once per hook per session; preserve the exception even when ordinary
    -- diagnostic events have reached their rate limit.
    local reason = success and ("invalid hook IDs: "..tostring(pre)..", "..tostring(post)) or tostring(pre)
    D.logWarning("Hook registration failed: %s | %s",path,reason)
end
local warned = false
local frameClock, lastFrame
-- Assorted worker state, sharing one table deliberately: this chunk sits at
-- Lua's hard limit of 200 locals per chunk, and every new flag used to want a
-- slot of its own. Extracting the worker into a module is the real fix.
--
-- panelsSettled -- startup ordering. The visible job on load is hiding the
-- panels the player asked to be hidden; everything else can wait a few frames.
--
-- Before this, the worker spent its first half second registering ~30 hooks
-- at one per frame and preloading claw mark assets (observed at up to 137 ms
-- a slice) while the HUD sat fully visible. Elements only disappeared at the
-- first refresh afterwards, which is exactly what it looked like.
local runtime = {panelsSettled = false, startupPanels = {}, peekSettled = {}}
-- Panels whose fade has been deferred so the whole group can start together.
-- See writePanel and the flush in step(). On the runtime table rather than as
-- locals because this file sits near Lua's 200-local ceiling.
runtime.fadeWave, runtime.fadeWaveSize = {}, 0
-- Verified by the Focus prompt probe in a live Steam build. Keep this exact
-- generated Blueprint path: it provides a Focus-entry wake without polling.
runtime.focusPromptGraph="/Game/_Dawnwalker/UI/_Unified/HUD/CombatFocus/WBP_OpenFocusPrompt.WBP_OpenFocusPrompt_C:ExecuteUbergraph_WBP_OpenFocusPrompt"
-- The readiness model is isolated so its form alternatives and no-timeout
-- contract are deterministic outside the game; Gameplay owns actual widgets,
-- diagnostics and the shared fade wave.
runtime.startupBarrierModel=require("QuietDawnStartupBarrier")
function runtime.newStartupBarrier(startedAt)
    return runtime.startupBarrierModel.new(panelModes,panelOpacities,startedAt)
end
function runtime.resolveStartupGroup(name, outcome)
    local barrier=runtime.startupBarrier
    local group=runtime.startupBarrierModel.resolve(barrier,name)
    if not group then return end
    if D.debugLogging then
        D.count(outcome=="arrived" and "startupBarrierPanels" or "startupBarrierUnavailable")
        -- This is at most one line per ordinary group, so do not put it behind
        -- Diagnostics' general event-rate limiter: arrival order is exactly
        -- what the startup investigation needs to retain.
        D.logInfo("Startup barrier %s: group=%d panel=%s remaining=%d",
            outcome,group,name,barrier.remaining)
    end
end
function runtime.observeStartupPanel(name)
    runtime.resolveStartupGroup(name,"arrived")
end
function runtime.skipStartupPanel(name)
    -- A verified missing field must not strand the visible baseline forever.
    -- This is a bounded readiness outcome, not a guessed time limit.
    runtime.resolveStartupGroup(name,"unavailable")
end
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
-- Focus is a pawn property, but its entry has not appeared on the already
-- observed GameHUD graph. Log the prompt's generated class once at Debug so a
-- future graph hook can use a verified function path rather than a guess.
function runtime.noteFocusPrompt(widget)
    if runtime.focusPromptProbed or not D.debugLogging or not valid(widget) then return end
    runtime.focusPromptProbed=true
    local className="unavailable"
    local classPath="unavailable"
    local named,full=pcall(function() return widget:GetClass():GetFullName() end)
    if named and full then className=tostring(full) end
    local pathed,path=pcall(function() return widget:GetClass():GetPathName() end)
    if pathed and path then classPath=tostring(path) end
    D.logInfo("Focus probe: promptClass=%s promptPath=%s; use this verified class path for the entry-hook probe",className,classPath)
end
-- Entry 3515 did not change the Quickslot Abilities root. Its fade may instead
-- belong to a child animation, so take a small, read-only visual-tree snapshot
-- around that candidate. This never searches global objects, registers a hook,
-- or writes a widget: it walks only this already-owned widget, at most 64 nodes
-- eight levels deep, and only during the explicitly bounded Debug probe.
function runtime.captureQuickslotProbeTree(widget,probe)
    if not probe.tree or not D.debugLogging or not valid(widget) then return end
    runtime.quickslotProbeTrees=runtime.quickslotProbeTrees or {}
    local prior=runtime.quickslotProbeTrees[probe.version]
    local treeState,seen={},{}
    local nodes,changed=0,0
    local function walk(node,path,depth)
        if not valid(node) or nodes>=64 or depth>8 then return end
        local address=node:GetAddress()
        if seen[address] then return end
        seen[address]=true
        nodes=nodes+1
        local className="unavailable"
        local visibility="unavailable"
        local opacityValue="unavailable"
        local readable,value=pcall(function() return node:GetClass():GetFullName() end)
        if readable and value then className=tostring(value) end
        readable,value=pcall(function() return node:GetVisibility() end)
        if readable and value~=nil then visibility=tostring(value) end
        readable,value=pcall(function() return node:GetRenderOpacity() end)
        if readable and type(value)=="number" then opacityValue=string.format("%.3f",value) end
        local state=path.."|"..className.."|"..visibility.."|"..opacityValue
        treeState[address]=state
        if not prior or prior[address]~=state then
            changed=changed+1
            D.logInfo("vanillaQuickslotsTree source=%s phase=%s node=%s path=%s class=%s visibility=%s opacity=%s",
                probe.source,probe.phase,tostring(address),path,className,visibility,opacityValue)
        end
        local treeOK,tree=pcall(function() return node.WidgetTree end)
        if treeOK and valid(tree) then
            local rootOK,root=pcall(function() return tree.RootWidget end)
            if rootOK then walk(root,path..".WidgetTree.RootWidget",depth+1) end
        end
        local countOK,count=pcall(function() return node:GetChildrenCount() end)
        if countOK and type(count)=="number" then
            for index=0,math.min(count,64)-1 do
                local childOK,child=pcall(function() return node:GetChildAt(index) end)
                if childOK then walk(child,path..".Child["..index.."]",depth+1) end
            end
        end
    end
    walk(widget,"QuickslotAbilities",0)
    if prior then
        for address in pairs(prior) do
            if not treeState[address] then
                changed=changed+1
                D.logInfo("vanillaQuickslotsTree source=%s phase=%s node=%s removed",probe.source,probe.phase,tostring(address))
            end
        end
    end
    runtime.quickslotProbeTrees[probe.version]=treeState
    D.logInfo("vanillaQuickslotsTree source=%s phase=%s nodes=%d changed=%d nodeLimit=64 depthLimit=8",
        probe.source,probe.phase,nodes,changed)
end
-- Fading resolves a show or hide target into a per frame opacity. It owns no
-- timer: the panel worker already ticks while work remains, and keeps itself
-- awake for as long as fade.pending() is true.
--
-- It is given GAME time, the same clock the peek and time-of-day holds use,
-- not the diagnostics clock. D.now() is os.clock -- processor time, coarse
-- and not proportional to wall time -- which makes a fade visibly stutter.
-- Game time also stops while the game is paused or alt-tabbed, so a fade
-- waits rather than finishing invisibly in the background.
local fade=require("QuietDawnFade").new(D,function()
    if not valid(frameClock) or not valid(controller) then return nil end
    return frameClock:GetGameTimeInSeconds(controller)
end)
fade.configure(config.fadeTransitions,config.fadeInSeconds,config.fadeOutSeconds)
-- Focus has no dedicated UFunction. Resource and HUD events already wake the
-- existing worker many times during normal play, so sample the pawn only while
-- Focus is selected as the peek trigger; no permanent Focus polling loop is
-- introduced. Entering holds the peek open, and leaving starts its duration.
runtime.focusPeekModel=require("QuietDawnFocusPeek")
function runtime.observeFocusPeek(pawn)
    if not manualPeekEnabled or not config.peekOnFocusMode then
        runtime.focusPeekActive=nil
        return
    end
    local readable,active=pcall(function() return pawn.bIsInFocusMode end)
    if not readable then return end
    local state,edge=runtime.focusPeekModel.transition(runtime.focusPeekActive,active)
    runtime.focusPeekActive=state
    if edge=="entered" then
        local changed=not peekVisible or peekStartPending
        peekVisible,peekStartPending,peekUntil=true,false,0
        -- A new visibility edge earns one configured fade. Once it lands,
        -- stock Focus refreshes reassert its target directly rather than
        -- starting the same wave over and over throughout the hold.
        if changed then
            runtime.peekSettled={}
            peekDirty=true
        end
        if D.debugLogging then D.count("focusPeekEntered") end
    elseif edge=="exited" and peekVisible then
        peekStartPending=true
        peekDirty=true
        if D.debugLogging then D.count("focusPeekExited") end
    end
    if armExpiry then armExpiry() end
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
        if kind=="refresh" and dynamicPanels[field] and panels[field] then
            -- This callback already validated the owned stat widget. Only
            -- queue a repair when a stock refresh actually changed opacity.
            local target=peekVisible and 1 or desired==1 and (stateReady and 1 or panels[field].original or 1) or 0
            local readable,current=pcall(function()return object:GetRenderOpacity()end)
            if not readable or type(current)~="number" or math.abs(current-target)>1e-5 then statReassert=true end
        end
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
-- Hunting aid for new Blueprint hooks, Debug level only.
--
-- A Blueprint class compiles its entire event graph into one function,
-- ExecuteUbergraph_<Class>, whose only argument is the bytecode offset to
-- jump to. Every event in that class is therefore reachable through a single
-- hook and told apart by that number -- which is how the 850 and 4146 below
-- were found, and the only practical way to reach an event the game exposes
-- no C++ UFunction for.
--
-- Nothing can look an offset up at runtime: you hook the graph, log the
-- numbers, perform the action in game, and read which number appeared at that
-- moment. Each number is reported once per session so the log stays short
-- enough to read by eye, and the whole thing costs nothing unless the log
-- level is Debug.
--
-- This chunk is at Lua's 200-locals ceiling, so the seen-set and its counter
-- share one table rather than taking a slot each.
local ubergraph = {seen = {}, count = 0}
-- ubergraph.limit: how many sightings of each entry are reported. One is
-- enough to discover a number; several are needed to tell what it means --
-- whether it fires on entering Focus or on leaving it, and whether it also
-- fires during unrelated HUD activity. That is how entry 4026 was confirmed.
ubergraph.limit = 8
local function noteUbergraphEntry(graph, entryParam)
    if not D.debugLogging or ubergraph.count >= 256 then return end
    local entry = tonumber(unwrap(entryParam))
    if entry == nil then return end
    local key = graph .. "#" .. tostring(entry)
    local seen = ubergraph.seen[key]
    if seen == nil then ubergraph.count = ubergraph.count + 1; seen = 0 end
    if seen >= ubergraph.limit then return end
    ubergraph.seen[key] = seen + 1

    -- Focus mode has no event to hook, only a property on the pawn. Sampling
    -- it right next to the entry number is what distinguishes "this fired on
    -- entering Focus" from "this fired on leaving it" -- a distinction no
    -- amount of staring at the number can settle.
    local focus = "?"
    if valid(controller) then
        -- Validate the pawn before reading through it. pcall catches a Lua
        -- error but not an access violation, and during a world teardown
        -- controller.Pawn can still be a pointer to freed memory.
        local got, pawn = pcall(function() return controller.Pawn end)
        if got and valid(pawn) then
            local read, flag = pcall(function() return pawn.bIsInFocusMode end)
            if read and flag ~= nil then focus = tostring(flag) end
        end
    end
    D.event("ubergraph", "%s entry=%s sighting=%d/%d focusMode=%s",
        graph, tostring(entry), seen + 1, ubergraph.limit, focus)
end
-- The stock Controls Legend action already handles the Menu/Options hold.
-- Its button click enters this graph at 850 (Steam build 25191761). Filter
-- before object access: entry activation/cinematic events must never reveal.
-- This widget has no Tick event; no button-state sampling or remapping is used.
local LEGEND="/Game/_Dawnwalker/UI/_Unified/HUD/ControlsLegend/WBP_ControlsLegend.WBP_ControlsLegend_C"
local function peekInput(context,entryParam)
    noteUbergraphEntry("WBP_ControlsLegend",entryParam)
    if not manualPeekEnabled or not config.peekOnLegendHold or config.manualPeekSeconds<=0 then return end
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
    "Display Icon State Non-Directionally", "ExecuteUbergraph_WBP_CombatTargetIndicator"}
-- Verified in a live controller run: this one graph entry occurs on both lock
-- and unlock. Every other entry is ignored in normal play.
local markerHardLockEntry=1370
local markerHookIndex, markerHookAttempts, markerSeen = 1, 0, false
local markerQueue, markerPending, markerFirst, markerLast = {}, {}, 1, 0
local markerCache, markerSlots, markerCount, markerPrune = {}, {}, 0, 1
local markerCacheWorld, markerCacheController, markerTurn, markerUrgent
local function combatCueRequested()
    return config.showCounterattackDirection or config.showUnblockableWarning
        or config.showDirectionalParry or config.showEnemyMarker or config.showLockIcon
end
-- Steam build 25129649: ERebelSetting::Game_Difficulty_CombatDirectionMarkers=71.
-- This menu setting is distinct from the widget's internal Hide Directions flag.
local settingsFactory, settingsObject, directionsEnabled
local settingsPending, settingsAttempts = true, 0
local function markersReady()
    -- Keep construction events queued until HUD ownership has been accepted.
    -- Missing HUD readiness sleeps until a lifecycle event, without polling.
    return markerFirst<=markerLast and candidate==nil and world~=nil and controller~=nil
end
local function rememberMarkerSource(job, source)
    if source==nil then return end
    job.sources=job.sources or {}
    if type(source)=="string" then
        job.sources[source]=true
    else
        for name in pairs(source) do job.sources[name]=true end
    end
end
local function markerSourceList(sources)
    if not sources then return "unknown" end
    local names={}
    for _,name in ipairs(markerSpecs) do
        if sources[name] then names[#names+1]=name end
    end
    for _,name in ipairs({"settings","lifecycle","HardLockToggle"}) do
        if sources[name] then names[#names+1]=name end
    end
    return #names>0 and table.concat(names," + ") or "internal"
end
local function queueMarker(object, retries, source)
    if object == nil then return end
    -- Capture only the wrapper here: construction may not be on the game
    -- thread. Pointer/property reads happen in the shared game-thread worker.
    local pending=markerPending[object]
    if pending then
        pending.object=object
        rememberMarkerSource(pending,source)
        if D.debugLogging then D.count("markerCoalesced") end
        return
    end
    -- Excess objects remain under game control. No unbounded queues or scans.
    if markerLast-markerFirst+1 >= 64 then if D.debugLogging then D.count("markerQueueFull") end; return end
    local job={object=object, retries=retries or 0}
    rememberMarkerSource(job,source)
    markerLast=markerLast+1
    markerQueue[markerLast]=job
    markerPending[object]=job
    if wake then wake("marker") end
end
local function markerEvent(context, source)
    if D.debugLogging then
        D.count("markerEvents")
        D.count("markerEvent_"..source)
    end
    queueMarker(unwrap(context),nil,source)
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
        for _,entry in pairs(markerCache) do queueMarker(entry.object,nil,"settings") end
    end
    if D.debugLogging then D.event("directions","menuEnabled=%s readSuccess=%s attempts=%d",tostring(value),tostring(success),settingsAttempts) end
end
settingsStep=D.wrap("directions",settingsStep)
local function markerHooksStep()
    local source=markerSpecs[markerHookIndex]
    local path=MARKER..":"..source
    -- The post-hook only records its source. UObject reads remain in the
    -- shared game-thread worker, where the coalesced job can safely inspect
    -- the final stock state produced by this Blueprint event.
    local success, pre, post=pcall(RegisterHook, path, function(context,entryParam)
        if source=="ExecuteUbergraph_WBP_CombatTargetIndicator" then
            -- The graph covers many ordinary indicator paths. Entry 1370 alone
            -- is the verified lock toggle, so ignore every other call before
            -- it can create marker work. Debug retains their entry evidence.
            if D.debugLogging then noteUbergraphEntry("WBP_CombatTargetIndicator",entryParam) end
            if tonumber(unwrap(entryParam))~=markerHardLockEntry then return end
            markerUrgent=true
            markerEvent(context,"HardLockToggle")
            return
        end
        markerEvent(context,source)
    end)
    markerHookAttempts=markerHookAttempts+1
    if success and type(pre)=="number" and type(post)=="number" then
        hooks[path]={pre,post}
        markerHookIndex=markerHookIndex+1
        if D.debugLogging then D.event("hook","registered=%s",path) end
    else
        reportHookError(path, success, pre, post)
    end
end
-- Debug-only, one-frame verification for the shared lock/dot indicator. This
-- distinguishes a stale post-hook state from stock UMG writing over our value
-- after the worker has applied it; it is intentionally not a recurring poll.
local function probeCombatCue(entry, object, job, icon, before, target, wrote)
    if not D.debugLogging then return end
    local sources=job.sources
    local source=markerSourceList(sources)
    local hardLock=entry.cueHardLock==true
    local hideDirections=entry.cueHideDirections==true
    local changed=entry.cueProbeIcon~=icon or entry.cueProbeHardLock~=hardLock
        or entry.cueProbeHideDirections~=hideDirections or entry.cueProbeTarget~=target
    entry.cueProbeIcon,entry.cueProbeHardLock=icon,hardLock
    entry.cueProbeHideDirections,entry.cueProbeTarget=hideDirections,target
    -- Discovery is complete. A stock display callback that left both its
    -- state and root opacity alone needs neither a log line nor a verifier.
    if not changed and not wrote then return end
    D.logInfo("combatCue probe event=%s icon=%s hardLock=%s hideDirections=%s beforeOpacity=%.3f targetOpacity=%d wrote=%s shown=%s arrow=%s lock=%s marker=%s",
        source,tostring(icon),tostring(hardLock),tostring(hideDirections),before,target,tostring(wrote),
        tostring(entry.cueShown),tostring(entry.cueArrow),tostring(entry.cueLock),tostring(entry.cueMarker))
    entry.cueProbeVersion=(entry.cueProbeVersion or 0)+1
    local version,address=entry.cueProbeVersion,entry.address
    pcall(ExecuteInGameThreadWithDelay,16,function()
        -- A later event supersedes this one. One final read is enough to catch
        -- a stock animation overwrite without turning combat cues into a tick.
        if not D.debugLogging or entry.cueProbeVersion~=version or not valid(object)
            or object:GetAddress()~=address then return end
        local ok,root,reticle,far,nowIcon,nowHardLock,reticleX,reticleY=pcall(function()
            local reticleWidget,farWidget=object.Reticle,object.FarAwayReticle
            return object:GetRenderOpacity(),
                valid(reticleWidget) and tostring(reticleWidget:GetVisibility()) or "unavailable",
                valid(farWidget) and tostring(farWidget:GetVisibility()) or "unavailable",
                tonumber(object["Currently Displayed Icon Type"]),object.bHardLockEnabled==true,
                valid(reticleWidget) and reticleWidget.Brush.ImageSize.X or nil,
                valid(reticleWidget) and reticleWidget.Brush.ImageSize.Y or nil
        end)
        if ok then
            D.logInfo("combatCue verify id=%s event=%s icon=%s hardLock=%s rootOpacity=%.3f reticleVisibility=%s farVisibility=%s reticleSize=%sx%s",
                tostring(address),source,tostring(nowIcon),tostring(nowHardLock),root,reticle,far,tostring(reticleX),tostring(reticleY))
        else
            D.event("combatCueProbe","verification unavailable: %s",tostring(root))
        end
    end)
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
    local objectWorld, owner=require('QuietDawnMarkerOwner').read(object)
    if not valid(objectWorld) or not valid(owner) then
        if D.debugLogging then
            D.count("markerNotReady")
            if job.retries==0 or job.retries==7 then
                D.event("marker","id=%s ownership unavailable; attempt=%d/8",tostring(job.address),job.retries+1)
            end
        end
        if job.retries<7 then queueMarker(object,job.retries+1,job.sources) end
        return
    end
    if not sameObject(objectWorld,world) or not sameObject(owner,controller) then
        if D.debugLogging then D.count("markerForeignOwner") end
        return
    end
    if not sameObject(controller:GetWorld(),world) then return end
    if not sameObject(markerCacheWorld,world) or not sameObject(markerCacheController,controller) then
        combatGuard.reset()
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
            queueMarker(object,job.retries+1,job.sources)
        end
        return
    end
    local current=object:GetRenderOpacity()
    if not entry then
        entry={object=object,address=job.address,original=current}
        markerCache[job.address]=entry
        for slot=1,64 do if not markerSlots[slot] then markerSlots[slot]=entry;break end end
        markerCount=markerCount+1
    end
    local guarded,guardShown=combatGuard.apply(object,entry)
    if guarded then
        -- The native drawing post callback owns presentation and its cleanup.
        -- Lua retains bounded scale discovery and diagnostics, without making
        -- the guard's own opacity writes look like new stock baselines.
        entry.lastOpacity=nil
        if not combatCueRequested() then return end
        local readable,icon=pcall(function()return tonumber(object['Currently Displayed Icon Type'])end)
        local applied=applyCombatCue(object,entry,readable and icon or nil,true)
        if not applied and job.retries<8 then queueMarker(object,job.retries+1,job.sources) end
        probeCombatCue(entry,object,job,icon,current,guardShown and 1 or 0,false)
        return
    end
    -- With every combat cue disabled, the only remaining responsibility is
    -- correcting a stock root-opacity write. Avoid child-widget reads,
    -- visibility updates, scale work and Debug probe timers on this hot path.
    if not combatCueRequested() then
        if entry.lastOpacity==nil or current~=entry.lastOpacity then entry.original=current end
        if current~=0 then
            opacity(object,0)
            if D.debugLogging then D.count("markerWrites") end
        end
        entry.lastOpacity=0
        if D.debugLogging then D.count("markerSuppressedOnly") end
        return
    end
    local readable,icon=pcall(function() return tonumber(object["Currently Displayed Icon Type"]) end)
    local applied,shown=applyCombatCue(object,entry,readable and icon or nil)
    if not applied then
        if entry.lastOpacity~=nil and current==entry.lastOpacity then opacity(object,entry.original) end
        entry.lastOpacity=nil
        if job.retries<8 then queueMarker(object,job.retries+1,job.sources) end
        if D.debugLogging and (job.retries==0 or job.retries==8) then
            D.event("combatCueReadiness","id=%s icon=%s attempt=%d/9",tostring(job.address),tostring(icon),job.retries+1)
        end
        return
    end
    if entry.lastOpacity==nil or current~=entry.lastOpacity then entry.original=current end
    local target=shown and 1 or 0
    local wrote=current~=target
    if wrote then
        opacity(object,target)
        if D.debugLogging then D.count("markerWrites") end
    end
    probeCombatCue(entry,object,job,icon,current,target,wrote)
    entry.lastOpacity=target
end
markerStep=D.wrap("marker",markerStep)
markerHooksStep=D.wrap("hook",markerHooksStep)
-- Enemy bars live outside WBP_GameHUD: they are spawned per enemy, come and
-- go constantly, and each named child follows its own setting, so they get
-- their own queue rather than riding the panel pass. QuietDawnEnemyBars owns
-- all of that. It is handed accessors rather than values for hud, world,
-- controller and idleness because those four are reassigned on every world
-- change, and a captured copy would quietly go stale.
local enemyBars = require("QuietDawnEnemyBars").new({
    D=D, config=config, Session=Session,
    valid=valid, sameObject=sameObject, unwrap=unwrap,
    opacity=opacity, hooks=hooks, reportHookError=reportHookError,
    registerHook=RegisterHook,
    wake=function(tag) return wake(tag) end,
    hud=function() return hud end,
    world=function() return world end,
    controller=function() return controller end,
    -- The panel pass is mid-flight while a HUD candidate is being adopted;
    -- enemy bars wait rather than read a half-bound world.
    idle=function() return candidate==nil end,
})
local healthTurn=false
local sprintSource=require("QuietDawnSprintSource").new({
    _QDNSprintConfigure=_QDNSprintConfigure,_QDNIsSprintPrompt=_QDNIsSprintPrompt,
    _QDNCachedSprintPrompt=_QDNCachedSprintPrompt},D,Session)
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
function runtime.enqueueQuickslotProbe(probe)
    runtime.quickslotProbeQueue=runtime.quickslotProbeQueue or {}
    if runtime.quickslotProbe then
        runtime.quickslotProbeQueue[#runtime.quickslotProbeQueue+1]=probe
    else
        runtime.quickslotProbe=probe
    end
    if wake then wake("quickslotProbe") end
end
local function queueVanillaQuickslotProbe(source,discoverWidget)
    -- Vanilla intentionally releases Quiet Dawn's opacity lease, so fading it
    -- needs the exact stock event that changes its target. Until that event is
    -- measured, record one post-hook sample and one next-frame verification;
    -- this is Debug-only and cannot become a poll.
    if not D.debugLogging or not config.fadeTransitions
        or panelModes.WBP_AA_Quickslots~=Modes.VANILLA then return end
    -- Entry 3515 is only correlated with combat transitions. Limit its
    -- detailed class/visual-tree capture to three sightings per HUD instance;
    -- an unproven graph entry must never turn into diagnostic event spam.
    if discoverWidget then
        local remaining=runtime.quickslotDiscoveryRemaining or 0
        if remaining<=0 then return end
        runtime.quickslotDiscoveryRemaining=remaining-1
    end
    runtime.quickslotProbeVersion=(runtime.quickslotProbeVersion or 0)+1
    local version=runtime.quickslotProbeVersion
    -- Supersede an unrelated older source so the post sample belongs to this
    -- graph entry. Later samples queue rather than overwrite each other when
    -- a busy worker takes more than one rendered frame to consume them.
    runtime.quickslotProbe={source=source,phase="post",tree=discoverWidget,version=version}
    runtime.quickslotProbeQueue={}
    if wake then wake("quickslotProbe") end
    local samples=discoverWidget and {{16,"nextFrame"},{96,"after100ms"},{240,"after250ms"}}
        or {{16,"nextFrame"}}
    for _,sample in ipairs(samples) do
        local delay,phase=sample[1],sample[2]
        pcall(ExecuteInGameThreadWithDelay,delay,function()
            if not D.debugLogging or runtime.quickslotProbeVersion~=version then return end
            runtime.enqueueQuickslotProbe({source=source,phase=phase,tree=discoverWidget,version=version})
        end)
    end
end
local function signal(source)
    if D.debugLogging then D.count("presetEvents") end
    if timeWatcher then timeWatcher.resume() end
    queueVanillaQuickslotProbe(source or "HUD preset")
    refreshDirty=true
    wake()
end
local function capture(context)
    sprintSource.recover()
    statsRefresh=true
    candidate = unwrap(context)
    candidateSource="GameHUD lifecycle hook"
    wake()
end
local SPECIAL="/Game/_Dawnwalker/UI/_Unified/HUD/AbilityCooldowns/WBP_HUD_SpecialAttackCooldown.WBP_HUD_SpecialAttackCooldown_C"
local function currentPanelEvent(context,field)
    local object=unwrap(context)
    return valid(hud) and valid(controller) and sameObject(field and hud[field] or hud,object)
        and sameObject(object:GetOwningPlayer(),controller) and sameObject(object:GetWorld(),world)
end
function runtime.focusPromptEvent(context,entryParam)
    noteUbergraphEntry("WBP_OpenFocusPrompt",entryParam)
    if not manualPeekEnabled or not config.peekOnFocusMode then return end
    -- Unlike GameHUD entry 4026, this graph also runs when Focus is entered.
    -- It only asks the existing snapshot to read the pawn's authoritative flag;
    -- the transition model remains the sole place that changes HUD visibility.
    if not currentPanelEvent(context,"WBP_OpenFocusPrompt") then return end
    statsPending=true
    if D.debugLogging then D.count("focusPromptWakes") end
    wake("resource")
end
local function cooldownEvent(context)
    if panelModes.WBP_HUD_SpecialAttackCooldown~=Modes.QUIET_DAWN then return end
    if not currentPanelEvent(context,"WBP_HUD_SpecialAttackCooldown") then return end
    -- Setup/finish update the stock Remaining Time before post delivery.
    -- The existing panel slice reads it, including during initial acquisition.
    fullPending=true
    absent.WBP_HUD_SpecialAttackCooldown=nil
    wake("cooldown")
end
local function switchedQuickslots(context,entryParam)
    noteUbergraphEntry("WBP_GameHUD",entryParam)
    local entry=tonumber(unwrap(entryParam))
    -- The latest combat probe recorded 3515 on both weapon draw and sheath.
    -- It is a candidate only: collect the same bounded opacity evidence before
    -- treating it as the stock Quickslot Abilities visibility route.
    if entry==3515 and panelModes.WBP_AA_Quickslots==Modes.VANILLA then
        queueVanillaQuickslotProbe("GameHUD graph 3515",true)
    end
    -- 4026 is a confirmed Focus-release graph entry. It does not decide the
    -- reveal itself: it only wakes the normal pawn snapshot, which reads the
    -- authoritative bIsInFocusMode transition and starts the hold if needed.
    if entry==2442 or entry==2657 or entry==4026 then
        if manualPeekEnabled and config.peekOnFocusMode and currentPanelEvent(context) then
            statsPending=true
            wake("resource")
        end
        return
    end
    -- Stock Toggle AA Quickslots delegate enters the graph at 4146. It is a
    -- known manual-toggle source, recorded separately from combat presets
    -- while the Vanilla-fade route is still being discovered.
    if entry~=4146 then return end
    if panelModes.WBP_AA_Quickslots==Modes.VANILLA then
        queueVanillaQuickslotProbe("Toggle AA Quickslots graph 4146")
    end
    if config.switchRevealSeconds<=0 or not hasSwitchPanels() or not currentPanelEvent(context) then return end
    local focus=hud.CombatFocusPanel
    if valid(focus) and focus:IsActivated() then return end -- stock toggle guard
    switchRequested,statsPending=true,true
    wake("resource")
end
-- Blueprint paths verified against the stock WBP_GameHUD export table.
-- Native paths use an explicit post-hook; Blueprint callbacks are post-hooks.
local specs = {
    {path="/Script/DogwoodUI.HUDManagerSubsystem:PushHUDPreset", callback=function()signal("PushHUDPreset")end, native=true},
    {path="/Script/DogwoodUI.HUDManagerSubsystem:PopHUDPreset", callback=function()signal("PopHUDPreset")end, native=true},
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
    {path=ROOT..":OnSetCrosshairTextEnabled", callback=function(context)
        if currentPanelEvent(context) then absent.Crosshair=nil;livePanels.Crosshair=true;wake("liveSettings") end
    end, optional="panel"},
    {path=ROOT..":Set AA Quickslots Showed", callback=function(context)
        if currentPanelEvent(context) then
            absent.WBP_HUD_Quickslots,absent.WBP_AA_Quickslots=nil,nil
            livePanels.WBP_HUD_Quickslots,livePanels.WBP_AA_Quickslots=true,true
            wake("liveSettings")
        end
    end, optional="panel"},
    {path="/Script/RebelSettings.RebelGameUserSettings:SetSetting", callback=refreshSettings, native=true},
    {path="/Script/RebelSettings.RebelGameUserSettings:SetSettingAsBool", callback=refreshSettings, native=true},
}
local function noop() end
local knownSpecs={}
for _,spec in ipairs(specs) do knownSpecs[spec.path]=true end
local function ensureFeatureSpecs()
    local first=#specs+1
    -- This line separates configuration eligibility from UE4SS registration in
    -- one durable Debug record. It is deliberately not rate-limited: hook
    -- registration runs only during startup or an Apply action, and a missing
    -- Focus entry wake must be diagnosable from a single session log.
    if D.debugLogging then
        local trigger=config.peekOnFocusMode and "Focus" or (config.peekOnLegendHold and "Legend hold" or "Off")
        local registration=hooks[runtime.focusPromptGraph] and "registered"
            or (manualPeekEnabled and (knownSpecs[runtime.focusPromptGraph] and "queued" or "will queue") or "not eligible")
        D.logInfo("Focus hook setup: Show HUD=%s manualPeek=%s eligible=%s registration=%s",
            trigger,tostring(config.manualPeek),tostring(manualPeekEnabled),registration)
    end
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
if #names>0 then
    specs[#specs+1]={path=LEGEND..":ExecuteUbergraph_WBP_ControlsLegend", callback=peekInput, optional="peek"}
end
if #names>0 then
    -- Register this verified graph for every enabled Show HUD configuration.
    -- The callback itself gates on Focus mode, so switching triggers live never
    -- leaves entry detection dependent on a fresh mod/game restart.
    specs[#specs+1]={path=runtime.focusPromptGraph, callback=runtime.focusPromptEvent, optional="focus"}
end
if sprintPrompts then
    specs[#specs+1]={path=ROOT..":OnSetInputPromptEnabled", callback=promptEvent, optional="prompt"}
    specs[#specs+1]={path=PROMPT_REFRESH, callback=promptRefreshed, optional="prompt"}
end
-- Keep observers available when a live setting later enables timed reveals.
if seen.WBP_HudTimer then
    specs[#specs+1]={path=TIME..":ExecuteUbergraph_WBP_HudTimer", callback=timeChanged, optional="time"}
    specs[#specs+1]={path=TIME..":Update Time Display", callback=timeDisplayUpdated, optional="time"}
end
if seen.WBP_HUD_SpecialAttackCooldown and panelModes.WBP_HUD_SpecialAttackCooldown==Modes.QUIET_DAWN then
    specs[#specs+1]={path=SPECIAL..":SetupCooldownEffect", callback=cooldownEvent, optional="panel"}
    specs[#specs+1]={path=SPECIAL..":OnCooldownFinished", callback=cooldownEvent, optional="panel"}
end
if (config.switchRevealSeconds>0 and hasSwitchPanels()) or (manualPeekEnabled and config.peekOnFocusMode)
    or (D.debugLogging and config.fadeTransitions and panelModes.WBP_AA_Quickslots==Modes.VANILLA) then
    -- The same graph provides quickslot switching, the Focus-release wake and
    -- one Debug-only Vanilla Quickslot Abilities route probe.
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
                D.logWarning("Time-change hook unavailable; time panel keeps its configured opacity.")
            elseif spec.optional=="panel" then
                D.logWarning("Panel event unavailable; other HUD controls remain active: %s",spec.path)
            elseif spec.optional=="prompt" then
                if D.debugLogging then D.event("sprintPrompt","prompt hook unavailable: %s",spec.path) end
            elseif spec.optional=="peek" then
                D.logWarning("Manual peek input unavailable; automatic health alerts remain enabled.")
            elseif spec.optional=="focus" then
                D.logWarning("Focus peek event unavailable; Focus entry will wait for another HUD update: %s",spec.path)
            else
                statHookFailures=true
                D.logWarning("Resource event hook unavailable; stat panels left to the game: %s",spec.path)
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
        -- A direct object notification and the GameHUD hook are preferred.
        -- Keep the fallback named too: a future lifecycle route must not turn
        -- this diagnostic into an unexplained "unknown" startup path.
        runtime.hudAdoptionSource=candidateSource or "fallback"
        runtime.startupImmediateNoted=nil
        runtime.quickslotProbe,runtime.quickslotProbeOpacity=nil,nil
        runtime.quickslotProbeQueue,runtime.quickslotProbeTrees={},{}
        runtime.quickslotDiscoveryRemaining=3
        panelRetries={}
        -- A newly adopted HUD should never wait for a decorative fade before
        -- honouring Quiet Dawn's baseline rules. Each managed panel stays in
        -- this set until its first successful write, so widgets the game
        -- constructs late during the same load also hide immediately.
        runtime.panelsSettled=false
        runtime.startupPanels={}
        for _,name in ipairs(names) do runtime.startupPanels[name]=true end
        local startedAt=valid(frameClock) and frameClock:GetGameTimeInSeconds(pc) or nil
        runtime.startupBarrier=runtime.newStartupBarrier(startedAt)
        -- Baseline panels stay visible until every ordinary group is ready,
        -- then fade in a single wave. Combat-only panels retain immediate
        -- baseline hiding during load.
        for name in pairs(runtime.startupBarrier.members) do runtime.startupPanels[name]=nil end
        fade.reset()
        if runtime.fadePacing then runtime.fadePacing.reset() end
        runtime.fadeWave,runtime.fadeWaveSize={},0
        runtime.fadeWaveLast,runtime.fadeWaveIdle=0,0
        runtime.fadeInFlight=false
        markerUrgent=false
        peekDirty,statDirty,refreshDirty=false,false,false
        if timeWatcher then timeWatcher.reset() end
        lastPawnAddress, lastCombatAddress, previousHealth, previousStamina = nil, nil, nil, nil
        lastBloodAddress,lastForm=nil,nil
        lastBloodCapacity=nil
        previousHealthAmount=nil
        fullRecoveryArmed=false
        healthUntil, staminaUntil = 0, 0
        peekRequested,peekUntil,peekVisible=false,0,false
        peekStartPending=false
        runtime.peekSettled={}
        runtime.focusPeekActive=nil
        runtime.focusPromptProbed=nil
        timeRequested,timeDirty,timeVisible,timeUntil=false,false,false,0
        switchRequested,switchUntil,switchVisible=false,0,false
        switchCursor=0
        statsRefresh=true
        healthDropped,staminaDropped=false,false
        if D.debugLogging then D.event("lifecycle","HUD/world changed; cached state reset") end
    else
        refreshDirty=true
    end
    controller = pc
    if playerEffects then playerEffects.recover() end
    if timeWatcher then timeWatcher.resume() end
    hudAddress, controllerAddress = object:GetAddress(), pc:GetAddress()
    if sprintPrompts then sprintPrompts.queue(object) end
    if config.peekOnLegendHold and config.manualPeekSeconds>0 then
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
        if peekVisible then peekDirty=true end
        peekUntil,peekVisible=0,false
        peekStartPending=false
        runtime.peekSettled={}
        runtime.focusPeekActive=nil
        if switchVisible then switchCursor=1 end
        switchUntil,switchVisible=0,false
        lastPawnAddress=pawnAddress
    end
    runtime.observeFocusPeek(pawn)
    -- Peeking only needs a current player and the game clock. It also works
    -- with both dynamic panels disabled or unavailable resource readings.
    if peekRequested then
        peekUntil=now+config.manualPeekSeconds
        if not peekVisible then
            runtime.peekSettled={}
            peekDirty,peekStartPending=true,true
        end
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
        or now < healthUntil or now < staminaUntil
    if D.debugLogging then D.vitals(health,stamina,needed,now,healthUntil,staminaUntil) end
    return needed and 1 or 0
end
snapshot=D.wrap("sample",snapshot)
local function panelTarget(name,entry,widget)
    if name=="WBP_BuffContainer" and config.hidePlayerEffectIcons then return 0 end
    local isStats = name == "HumanStats" or name == "VampireStats"
    local mode=panelModes[name]
    local target = panelOpacities[name] or 0
    -- Quiet Dawn mode always starts hidden, independently of its saved fixed opacity.
    -- Zero opacity preserves resource-driven hiding and revealing.
    -- Missing readings retain the game's opacity.
    if isStats and dynamicPanels[name] then
        target = desired == 1 and (stateReady and 1 or entry.original) or 0
    end
    if mode==Modes.QUIET_DAWN and name=="WBP_HudTimer" and timeVisible then target=1 end
    if mode==Modes.QUIET_DAWN and name=="WBP_HUD_SpecialAttackCooldown" then
        local display=widget.WBP_CooldownDisplay
        local remaining=valid(display) and tonumber(display["Remaining Time"]) or nil
        if not hooks[SPECIAL..":SetupCooldownEffect"] or not hooks[SPECIAL..":OnCooldownFinished"] then
            target=entry.original -- unavailable events retain game control
        else target=remaining and remaining>0 and remaining<math.huge and 1 or 0 end
    end
    if mode==Modes.QUIET_DAWN and switchVisible and (name=="WBP_HUD_Quickslots" or name=="WBP_AA_Quickslots") then target=1 end
    -- A Fixed Opacity panel changes only when its player explicitly asked HUD
    -- Peek to raise it. The default leaves the selected fixed level untouched.
    if mode==Modes.FIXED_OPACITY and peekVisible
        and config.fixedPeekPanels and config.fixedPeekPanels[name]==true then target=1 end
    -- The combat-focus radial selector keeps its own opacity setting;
    -- revealing it for a HUD peek overlays the ordinary player panels.
    if mode==Modes.QUIET_DAWN and peekVisible and name~="CombatFocusPanel" and name~="WBP_HUD_Quickslots_ChangePrompt" and name~="WBP_HUD_SpecialAttackCooldown"
        and name~="WBP_OpenFocusPrompt" and (not config.showHUDPanels or config.showHUDPanels[name]~=false) then target=1 end
    return target
end
local function peekPanel(name)
    if name=="WBP_BuffContainer" and config.hidePlayerEffectIcons then return false end
    if panelModes[name]==Modes.FIXED_OPACITY then
        return config.fixedPeekPanels and config.fixedPeekPanels[name]==true
    end
    return panelModes[name]==Modes.QUIET_DAWN and name~="CombatFocusPanel"
        and name~="WBP_HUD_Quickslots_ChangePrompt" and name~="WBP_HUD_SpecialAttackCooldown"
        and name~="WBP_OpenFocusPrompt"
        and (not config.showHUDPanels or config.showHUDPanels[name]~=false)
end
local function writePanel(name,entry,target)
    local barrier=runtime.startupBarrier
    if barrier and barrier.active and barrier.members[name] then
        -- The ordinary HUD is allowed to finish assembling before it moves.
        -- The release path below starts every collected baseline panel inside
        -- one worker call, so there is no per-widget dismissal cascade.
        if barrier.wave[name]==nil then
            barrier.wave[name]=true
            barrier.waveSize=barrier.waveSize+1
            if D.debugLogging then D.count("startupBarrierDeferred") end
        end
        return false
    end
    -- A HUD can keep constructing named panels after Quiet Dawn has accepted
    -- its root. Combat-only panels retain immediate baseline hiding on load;
    -- ordinary baseline panels are held by the barrier above. Normal reveals
    -- and all later visibility changes still fade.
    if runtime.startupPanels[name] then
        fade.forget(name)
        local wrote=panelOpacity.apply(entry.lease,target)
        runtime.startupPanels[name]=nil
        if wrote then
            entry.opacityOwned=true
            -- This is intentionally Info rather than Debug: a player can
            -- collect the real startup route without enabling per-event logs.
            if fade.enabled() and not runtime.startupImmediateNoted then
                runtime.startupImmediateNoted=true
                D.logInfo("Startup immediate baseline: source=%s panel=%s target=%.3f",
                    runtime.hudAdoptionSource or "fallback",name,target)
            end
            if D.debugLogging then
                D.count("startupPanelHides")
                D.count("panelWrites")
                if fade.enabled() then D.count("startupImmediateFadeBypass") end
            end
        end
        return wrote
    end
    -- Every Show HUD visibility edge gets one configured transition. Once the
    -- transition settles, stock HUD refreshes can write over the held target.
    -- Reassert only that settled panel directly: creating another fade wave
    -- made Focus and timed peeks pulse throughout the same held visibility.
    if peekVisible and runtime.peekSettled[name] and peekPanel(name) then
        fade.forget(name)
        local wrote=panelOpacity.apply(entry.lease,target)
        if wrote and D.debugLogging then D.count("panelWrites") end
        return wrote
    end
    -- Panels are visited one per worker call, so a transition started inline
    -- here would start at a different moment for every panel: on the last
    -- load they began about 50 ms apart and the HUD dissolved raggedly, one
    -- element at a time, instead of as a single movement. fade.forEach
    -- already advances everything in lockstep once transitions exist -- the
    -- missing half was that they never *began* together.
    --
    -- So the first write for a panel is deferred: record that it wants a
    -- transition and write nothing. Once the pass finishes, step() replays
    -- the whole group inside one worker call, so they share a start moment
    -- and move as one from then on. A transition already running is advanced
    -- normally, and with fading switched off nothing is deferred at all.
    if fade.enabled() and not fade.active(name) and not runtime.fadeFlushing then
        if runtime.fadeWave[name]==nil then
            runtime.fadeWave[name]=true
            runtime.fadeWaveSize=runtime.fadeWaveSize+1
            if D.debugLogging then D.count("panelFadeDeferred") end
        end
        return false
    end
    -- The fade turns the eventual target into this frame's value. With fading
    -- off, or on the frame a transition lands, that is the target itself.
    local value=target
    if fade.enabled() then value=fade.step(name,entry.object:GetRenderOpacity(),target) end
    local wrote=panelOpacity.apply(entry.lease,value)
    if peekVisible and peekPanel(name) and math.abs(value-target)<=1e-5 then
        runtime.peekSettled[name]=true
    end
    if wrote then
        entry.opacityOwned=true
        if D.debugLogging then
            D.count("panelWrites")
            -- Intermediate fade frames are counted, not narrated: at ~50 of
            -- them per second per panel they would drown the log and trip the
            -- events-per-second limiter. Only the settled value is reported.
            if math.abs(value-target)<=1e-5 then D.event("panel","name=%s opacity=%.3f",name,target)
            else D.count("panelFadeFrames") end
        end
    end
    return wrote
end
local function panelFailure(name,err)
    panels[name]=nil
    local tries=(panelRetries[name] or 0)+1
    if tries<8 then panelRetries[name]=tries
    else
        panelRetries[name]=nil
        absent[name]=true
        runtime.skipStartupPanel(name)
    end
    if D.debugLogging and (tries==1 or tries==8) then
        D.event("panelFailure","name=%s attempt=%d/8 error=%s",name,tries,tostring(err))
    end
end
-- At most 17 named, cached panels (13 for peek, two for resource alerts).
-- No discovery, hook registration, transforms or config I/O in this slice.
-- A single commit keeps visible transitions in the same rendered frame.
local function cachedVisibility(kind)
    if not valid(hud) or not valid(controller) or not sameObject(hud:GetWorld(),world)
        or not sameObject(controller:GetWorld(),world) or not sameObject(hud:GetOwningPlayer(),controller) then return end
    for _,name in ipairs(kind~="stats" and names or statNames) do
        if kind=="refresh" and panelScaling then
            local entry=panels[name]
            if not entry or panelScaling.pending(name,entry) then livePanels[name]=true end
        end
        local dedicated=name=="WBP_HUD_Quickslots_ChangePrompt" or name=="WBP_HUD_SpecialAttackCooldown" or name=="WBP_OpenFocusPrompt"
        if kind=="refresh" and dedicated then
            livePanels[name]=true -- reacquire replaceable inner opacity containers
        elseif panelModes[name]~=Modes.VANILLA and (kind~="peek" or peekPanel(name)) and not absent[name] then
            local entry=panels[name]
            local widget=hud[name]
            if entry and sameObject(entry.widget,widget) and valid(entry.object) then
                local target=panelTarget(name,entry,widget)
                -- Refresh callbacks arrive even while the game has left this
                -- panel exactly where its active rule wants it. Queuing a
                -- wave before checking that fact made every no-op refresh
                -- look like a new Focus fade in the Debug log.
                -- Without fades the opacity lease already skips unchanged
                -- writes; avoid an additional engine read before that check.
                if not fade.enabled() or math.abs(entry.object:GetRenderOpacity()-target)>1e-5 then
                    local ok,err=pcall(writePanel,name,entry,target)
                    if not ok then panelFailure(name,err) end
                elseif fade.active(name) then
                    -- The game has already reached the active target. Retire
                    -- the old transition instead of leaving it pending until
                    -- orphan cleanup; this neither writes nor snaps opacity.
                    fade.forget(name)
                    if D.debugLogging then D.count("panelFadeSatisfiedByStock") end
                end
            else
                -- Late/replaced fields are discovered separately. Never hold
                -- the visible cohort behind an unavailable widget.
                livePanels[name]=true
            end
        end
    end
    if kind=="refresh" and not statsRefresh then
        -- The cache covers this preset already. Keep missing-field, scaling,
        -- cue and time jobs, but do not repeat a full opacity discovery pass.
        fullPending,dirty,cursor=false,false,0
    end
    if D.debugLogging then D.count(kind.."Commits") end
end
cachedVisibility=D.wrap("visibility",cachedVisibility)
local function panelStep(name)
    -- Vanilla panels need no opacity reads once the previous override is
    -- released. Size remains an independent preference in every mode.
    if panelModes[name]==Modes.VANILLA and not panelScaling
        and not (panels[name] and panels[name].opacityOwned) then
        -- A Vanilla alternate form can satisfy the stats startup group even
        -- though Quiet Dawn never writes that form's opacity.
        local barrier=runtime.startupBarrier
        local widget=valid(hud) and hud[name] or nil
        if barrier and barrier.active and barrier.watchers[name] and valid(widget) then
            runtime.observeStartupPanel(name)
        end
        panelRetries[name]=nil
        return true
    end
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
                runtime.noteFocusPrompt(widget)
                local content=widget.ButtonImage
                object=valid(content) and content:GetParent() or nil
            end
        end
        if valid(object) then
            runtime.observeStartupPanel(name)
            local mode=panelModes[name]
            local entry = panels[name]
            if not entry or not sameObject(entry.object,object) then
                entry = {object=object, widget=widget, original=mode~=0 and object:GetRenderOpacity() or nil,
                    lease=panelOpacity.bind(object)}
                panels[name]=entry
            end
            if mode==Modes.VANILLA then
                runtime.startupPanels[name]=nil
                if entry.opacityOwned then
                    local restored=panelOpacity.restore(entry.lease)
                    entry.opacityOwned=false
                    entry.original=nil
                    if restored and panelScaling then return false end
                end
                if panelScaling then return panelScaling.step(name,object,entry) end
                panelRetries[name]=nil
                return true
            end
            local current=object:GetRenderOpacity()
            if entry.original==nil then entry.original=current end
            if config.peekOnLegendHold and config.manualPeekSeconds>0 and name=="WBP_ControlsLegend" then
                peekWidgetAddress,peekControllerAddress=object:GetAddress(),controllerAddress
            end
            local target=panelTarget(name,entry,widget)
            if runtime.startupPanels[name] and math.abs(current-target)<=1e-5 then
                -- The game already landed on this panel's initial target.
                runtime.startupPanels[name]=nil
            end
            -- UWidget stores float opacity: e.g. 0.4 returns 0.400000006.
            -- Match the session journal's tolerance over the opacity range.
            local wroteOpacity=false
            if math.abs(current-target)>1e-5 then
                wroteOpacity=writePanel(name,entry,target)
            end
            panelRetries[name]=nil
            if panelScaling then
                -- Keep opacity and each transform phase in separate frame slices.
                if wroteOpacity and panelScaling.pending(name,entry) then return false end
                return panelScaling.step(name,object,entry)
            end
        else
            local tries=(panelRetries[name] or 0)+1
            if tries<8 then panelRetries[name]=tries
            else
                panelRetries[name]=nil
                absent[name]=true
                runtime.skipStartupPanel(name)
                if D.debugLogging then D.event("missing","panel=%s; retries exhausted",name) end
            end
        end
    else
        hud, world, panels = nil, nil, {}
        -- The panels these transitions referred to are gone with the world.
        fade.reset()
        if runtime.fadePacing then runtime.fadePacing.reset() end
        runtime.fadeWave,runtime.fadeWaveSize={},0
        runtime.fadeInFlight=false
        runtime.startupBarrier=nil
        panelRetries,livePanels={},{}
        hudAddress=nil
        peekWidgetAddress,peekControllerAddress=nil,nil
        runtime.peekSettled={}
        runtime.focusPeekActive=nil
        timeRequested,timeDirty,timeVisible,timeUntil=false,false,false,0
    end
    return true
end
-- Start every panel that is waiting to fade, inside this one worker call, so
-- they share a start moment and move together from then on. Defined here
-- because it needs panelStep, which is declared just above.
function runtime.flushStartupBarrier()
    local barrier=runtime.startupBarrier
    if not barrier or not barrier.releasePending then return end
    barrier.active,barrier.releasePending=false,false
    local wave=barrier.wave
    barrier.wave,barrier.waveSize={},0
    runtime.fadeFlushing=true
    local started=0
    for name in pairs(wave) do
        if panels[name] then started=started+1 end
        pcall(panelStep,name)
    end
    runtime.fadeFlushing=false
    if D.debugLogging then
        local elapsedMs=nil
        if type(barrier.startedAt)=="number" and valid(frameClock) and valid(controller) then
            elapsedMs=math.max(0,(frameClock:GetGameTimeInSeconds(controller)-barrier.startedAt)*1000)
        end
        D.count("startupBarrierReleases")
        if elapsedMs then
            D.count("startupBarrierWaitMs",math.floor(elapsedMs+0.5))
            D.logInfo("Startup barrier released: groups=%d panels=%d waitMs=%.0f",barrier.groups,started,elapsedMs)
        else
            D.logInfo("Startup barrier released: groups=%d panels=%d waitMs=unavailable",barrier.groups,started)
        end
    end
end
function runtime.flushFadeWave()
    local wave=runtime.fadeWave
    runtime.fadeWave,runtime.fadeWaveSize={},0
    runtime.fadeWaveLast,runtime.fadeWaveIdle=0,0
    runtime.fadeFlushing=true
    local started=0
    for name in pairs(wave) do
        local wasActive=fade.active(name)
        pcall(panelStep,name)
        -- A queued name is not proof of a transition: stock code can land on
        -- the same target between the refresh callback and this batched pass.
        -- Count only the fade that panelStep really began.
        if not wasActive and fade.active(name) then started=started+1 end
    end
    runtime.fadeFlushing=false
    if D.debugLogging and started>0 then
        D.count("panelFadeWaves")
        D.event("panelFade","%d panel(s) began fading together",started)
    elseif D.debugLogging then
        D.count("panelFadeNoopWaves")
    end
end
do
    local updatePanel=panelStep
    panelStep=function(name)
        local ok,done=pcall(updatePanel,name)
        if ok then return done end
        panelFailure(name,done)
        return true -- a failed field never blocks the other panels
    end
end
local timeTurn=false
local timeSampleTurn=false
local function step()
    if livePending then applyLiveSettings(true);return false end
    -- One shared fade slice per rendered worker frame, independent of which
    -- subsystem gets the next ordinary slice. No panel work during a pause.
    if not runtime.fadeSuspended and fade.pending() then fade.forEach(panelStep) end
    if runtime.quickslotProbe then
        local probe=runtime.quickslotProbe
        local queue=runtime.quickslotProbeQueue or {}
        runtime.quickslotProbe=table.remove(queue,1)
        local widget=valid(hud) and hud.WBP_AA_Quickslots or nil
        if D.debugLogging and panelModes.WBP_AA_Quickslots==Modes.VANILLA and valid(widget)
            and valid(controller) and sameObject(widget:GetOwningPlayer(),controller)
            and sameObject(widget:GetWorld(),world) then
            local current=widget:GetRenderOpacity()
            local previous=runtime.quickslotProbeOpacity
            runtime.quickslotProbeOpacity=current
            runtime.quickslotProbeClass="unavailable"
            runtime.quickslotProbeVisibility="unavailable"
            do
                local readable,value=pcall(function() return widget:GetClass():GetFullName() end)
                if readable and value then runtime.quickslotProbeClass=tostring(value) end
            end
            do
                local readable,value=pcall(function() return widget:GetVisibility() end)
                if readable and value~=nil then runtime.quickslotProbeVisibility=tostring(value) end
            end
            -- This bounded route probe is Debug-only. Do not put decisive
            -- samples through the general per-second event limiter: a combat
            -- entry can legitimately emit many other graph sightings in the
            -- same frame, as seen in the session log.
            D.logInfo("vanillaQuickslots source=%s phase=%s class=%s rootVisibility=%s rootOpacity=%.3f previous=%s changed=%s",
                probe.source,probe.phase,runtime.quickslotProbeClass,runtime.quickslotProbeVisibility,current,
                previous and string.format("%.3f",previous) or "none",
                tostring(previous~=nil and math.abs(current-previous)>1e-5))
            runtime.captureQuickslotProbeTree(widget,probe)
        elseif D.debugLogging then
            D.logInfo("vanillaQuickslots source=%s phase=%s panel=unavailable",probe.source,probe.phase)
        end
        return false
    end
    if runtime.startupBarrier and runtime.startupBarrier.releasePending then
        runtime.flushStartupBarrier()
        return false
    end
    -- Start a deferred fade group once it has stopped growing.
    --
    -- This lives at the top of step() because the two previous flush sites
    -- were both inside the discovery pass, and a manual peek never runs that
    -- pass -- it has its own branch and returns early. So a peek deferred
    -- its panels, nothing ever started them, and the HUD stayed hidden for
    -- good. Flushing from here means no branch can swallow a group.
    --
    -- "Stopped growing" rather than a fixed delay: the whole point of
    -- batching is to catch every panel that belongs to the same visual
    -- change, and only the group itself knows when it is complete. A pass
    -- adds one panel per call, so the wave grows and waits; when a call adds
    -- nothing, the group is done and starts together on the next one.
    if runtime.fadeWaveSize>0 then
        if runtime.fadeWaveSize>(runtime.fadeWaveLast or 0) then
            runtime.fadeWaveLast,runtime.fadeWaveIdle=runtime.fadeWaveSize,0
        else
            runtime.fadeWaveIdle=(runtime.fadeWaveIdle or 0)+1
            if runtime.fadeWaveIdle>=2 then runtime.flushFadeWave() end
        end
    end
    priorityTurn=(priorityTurn+1)%3
    -- Coalesce resource events; no timer requests resource reads.
    if statsPending and candidate==nil and priorityTurn~=0 and not (peekDirty or statDirty) then
        statsPending=false
        local wasReady=stateReady
        local success,value=pcall(snapshot)
        peekRequested,switchRequested=false,false
        stateReady=success and value~=nil
        if not stateReady then healthDropped,staminaDropped=false,false end
        local target=stateReady and value or 1
        if target~=desired or wasReady~=stateReady or statReassert then desired=target;statDirty=true end
        statReassert=false
        armExpiry()
        return false
    end
    if candidate==nil and (peekDirty or (priorityTurn~=0 and (statDirty or refreshDirty))) then
        local kind=refreshDirty and "refresh" or peekDirty and "peek" or "stats"
        peekDirty,statDirty,refreshDirty=false,false,false
        cachedVisibility(kind)
        if peekVisible and peekStartPending then
            peekStartPending=false
            if config.manualPeekSeconds>0 then
                peekUntil=frameClock:GetGameTimeInSeconds(controller)+config.manualPeekSeconds
            else
                -- Focus still owns the active reveal at zero duration, but its
                -- post-exit hold is intentionally immediate.
                runtime.peekSettled={}
                peekVisible,peekUntil,peekDirty=false,0,true
            end
        end
        armExpiry()
        return false
    end
    if sprintSource.pending() then sprintSource.step();return false end
    -- Discovery, hook registration, state reads and transforms remain sliced.
    -- Every third slice is reserved for this work even under resource bursts.
    if runtime.panelsSettled and playerEffects and playerEffects.pending() then playerEffects.step();return false end
    if clawHits and clawHits.pending() then clawHits.step();return false end
    if runtime.panelsSettled and clawMarks and clawMarks.pending() then
        clawMarks.step()
        return false
    end
    if hookIndex <= #specs and (hookIndex <= 3 or runtime.panelsSettled or not valid(hud)) then
        if hookIndex > 3 and candidate == nil and not valid(hud) then
            worker=false
            return true
        end
        registerOne()
        attempts = attempts + 1
        if attempts >= 120 then
            if not warned then D.logWarning("HUD hooks not ready; waiting for a lifecycle event."); warned=true end
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
    -- A stock Display Icon event can temporarily restore the forbidden dot.
    -- Give one queued marker job the next fair worker slice, before prompts,
    -- time sampling and enemy bars, so it cannot sit visibly stale for many
    -- unrelated jobs. Alternation still gives every other subsystem a turn.
    markerTurn=not markerTurn
    if markersReady() and (markerUrgent or markerTurn or (cursor==0 and not dirty)) then
        -- A verified lock toggle is a presentation boundary: service it on
        -- the next rendered worker frame, without making ordinary cue traffic
        -- outrank every other subsystem.
        markerUrgent=false
        local success, reason=pcall(markerStep)
        if not success and D.debugLogging then
            D.count("markerFailures")
            D.event("markerFailure","Marker update skipped: %s",tostring(reason))
        end
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
    -- sharing the same one-shot worker and its native frame gate. A failed
    -- enemy field may still have its bounded readiness work queued; never let
    -- that background work take an intermediate frame away from an active
    -- player-HUD fade. The fade pass below advances it in this same worker
    -- call, so this changes priority rather than adding another tick.
    healthTurn=not healthTurn
    if (not fade.pending() or runtime.fadeSuspended) and enemyBars.ready()
        and (healthTurn or (cursor==0 and not dirty and not statsPending and not markersReady())) then
        enemyBars.step()
        return false
    end
    local changedPanel=next(livePanels)
    if changedPanel and candidate==nil then
        if panelStep(changedPanel) then livePanels[changedPanel]=nil end
        return false
    end
    if cursor==0 and not dirty and timeDirty then
        timeDirty=false
        jobNames=timeJobNames
        cursor=1
        return false
    end
    -- A transition in flight still owes frames. Advance every fading panel
    -- inside THIS call rather than one per call: a fade must not run at the
    -- worker's rate divided by the number of panels, and the panels have to
    -- move together. Panels that are not fading are left alone.
    if cursor==0 and not dirty and fade.pending() then
        return false
    end
    if cursor==0 and not dirty and next(panelRetries) then
        panelStep(next(panelRetries))
        return false
    end
    if cursor==0 and not dirty then
        -- A deferred fade wave needs two quiet worker calls to prove that no
        -- more panels are joining it, then a third to flush the whole group.
        -- Stopping here stranded a completed Focus peek: the next unrelated
        -- HUD event was the only thing that could restart the worker and hide it.
        if statsPending or peekDirty or statDirty or refreshDirty or switchCursor>0 or runtime.fadeWaveSize>0 or timeRequested or (timeWatcher and timeWatcher.pending()) or markersReady() or enemyBars.ready() or promptsReady() then return false end
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
            if statsRefresh and (#statNames > 0 or peekRequested or switchRequested or config.peekOnFocusMode) then
                statsRefresh=false
                local success, value = pcall(snapshot)
                peekRequested,switchRequested=false,false
                stateReady = success and value ~= nil
                desired = stateReady and value or 1
            elseif #statNames==0 then
                stateReady, desired = false, 0
                statsRefresh=false
            end
        end
        cursor=1
        return false
    end
    if cursor <= #jobNames then
        -- Advance every fading panel on THIS call, then take one step of the
        -- discovery pass. The lockstep branch above only runs once the pass
        -- has finished and nothing is dirty, and a lifecycle event
        -- sets dirty -- so during a load the fade was being driven by the
        -- pass instead: one panel per worker call, sixteen calls per visual
        -- frame. That is the stutter. The two jobs now share a call rather
        -- than taking turns.
        if panelStep(jobNames[cursor]) then cursor=cursor+1 end
        return false
    end
    cursor=0
    -- The panels have had a full pass, so the deferred startup work may run.
    -- Only a full job counts: the short stat-only sweeps do not hide
    -- everything and must not release the preloads early.
    if fullJob and valid(hud) then runtime.panelsSettled=true end
    if runtime.fadeWaveSize>0 then runtime.flushFadeWave(); return false end
    if runtime.panelsSettled and (hookIndex<=#specs
        or (clawMarks and clawMarks.pending()) or (playerEffects and playerEffects.pending())) then return false end
    if switchCursor>0 or dirty or statsPending or peekDirty or statDirty or refreshDirty or next(panelRetries) or runtime.fadeWaveSize>0 or timeRequested or timeDirty or (timeWatcher and timeWatcher.pending()) or markersReady() or enemyBars.ready() or promptsReady() or fade.pending() then return false end
    attempts=0
    worker=false
    armExpiry()
    return true -- the panel worker stops; no recurring resource worker remains
end
step=D.wrap("worker",step)
-- UE4SS repeating timers ignore return values. Chain one-shots explicitly.
--
-- `delay` is asked for again before every re-arm rather than captured once,
-- because the right pause depends on what the worker is currently doing.
-- Ordinary work is event driven and 16 ms is plenty. A fade is not: it needs
-- a sample on every frame the display actually draws, and a fixed 16 ms timer
-- samples at about 62 Hz. On a 75 Hz screen those two rates beat against each
-- other roughly 12 times a second -- some frames get two steps, some none --
-- which reads as judder no matter how smooth the easing curve is. While a
-- transition is outstanding we therefore re-arm as fast as the timer allows
-- and let the frame-count guard in the worker collapse the surplus wakeups,
-- so one rendered frame is one fade step at any refresh rate.
local function repeatUntilDone(delay,fn)
    local function tick()
        if not fn() then ExecuteInGameThreadWithDelay(delay(),tick) end
    end
    ExecuteInGameThreadWithDelay(delay(),tick)
end
-- On the runtime table rather than as locals: Gameplay.lua sits on Lua's
-- hard ceiling of 200 locals per chunk.
runtime.workerIdleMs, runtime.workerFadeMs, runtime.workerPausedFadeMs = 16, 1, 50
-- Consecutive wakeups that found the same frame before we stop believing
-- rendering is advancing. The same four-frame evidence also distinguishes a
-- real pause (frames advancing, game time frozen) from surplus 1 ms callbacks.
runtime.stalledFrameLimit = 4
runtime.fadePacing=require("QuietDawnFadePacing").new(runtime.stalledFrameLimit)
function runtime.workerDelay()
    -- A pause menu keeps drawing while game time is frozen. Keep one very
    -- small, temporary 50 ms heartbeat so the held transition resumes within
    -- a few visual frames after unpausing, but do not revisit panel opacity.
    if runtime.fadePacing.paused() then return runtime.workerPausedFadeMs end
    -- Frames can also stop altogether while the console is open or the window
    -- is backgrounded. This is likewise a dormant fade, never a 1 ms loop.
    if (runtime.sameFrameStreak or 0) >= runtime.stalledFrameLimit then
        if runtime.fadeInFlight and D.debugLogging then D.count("fadeFrameGateBackoffs") end
        return runtime.fadeInFlight and runtime.workerPausedFadeMs or runtime.workerIdleMs
    end
    -- A 1370 hard-lock transition has one queued presentation correction.
    -- Re-arm promptly until that finite job is consumed; the frame gate above
    -- still prevents a busy loop when rendering has stopped.
    if markerUrgent then return runtime.workerFadeMs end
    local ok,fading = pcall(fade.pending)
    runtime.fadeInFlight=ok and fading or false
    if not runtime.fadeInFlight then runtime.fadePacing.reset() end
    return runtime.fadeInFlight and runtime.workerFadeMs or runtime.workerIdleMs
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
        panelRetries={}
        settingsPending,settingsAttempts=true,0
    end
    if statsOnly~="marker" and statsOnly~="settings" and statsOnly~="resource" and statsOnly~="enemyHealth" and statsOnly~="time" and statsOnly~="sprintPrompt" and statsOnly~="clawMarks" and statsOnly~="playerEffects" and statsOnly~="liveSettings" and statsOnly~="quickslotProbe" then dirty=true end
    if worker then if D.debugLogging then D.count("workerCoalesced") end; return end
    worker=true
    if D.debugLogging then D.count("workerStarts") end
    attempts=0
    repeatUntilDone(runtime.workerDelay, function()
        local success, stop = pcall(function()
            if not valid(frameClock) then
                frameClock=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                if not valid(frameClock) then
                    worker=false
                    D.logWarning("Frame clock unavailable; waiting for a lifecycle event.")
                    return true
                end
            end
            local frame=frameClock:GetFrameCount()
            fade.expire(function(name,target)
                local entry=panels[name]
                if entry and valid(hud) and valid(controller) and valid(entry.object)
                    and sameObject(hud:GetWorld(),world) and sameObject(hud:GetOwningPlayer(),controller) then
                    panelOpacity.apply(entry.lease,target)
                end
            end,runtime.fadePacing.paused() and frame~=lastFrame)
            if frame == lastFrame then
                -- A paused renderer must not defer a committed settings edit.
                if livePending then applyLiveSettings(true) end
                -- A surplus wakeup during a fade is expected and is the
                -- mechanism, not waste: we deliberately over-arm the timer
                -- and let this guard collapse it down to one step per frame.
                --
                -- Unless frames have stopped entirely. Opening the console or
                -- backgrounding can freeze the frame counter, so a fade cannot
                -- advance. (The pause menu is different: it keeps rendering,
                -- and is handled by the game-time check below.) Count the
                -- streak so the re-arm uses the dormant-fade heartbeat rather
                -- than a busy 1 ms loop.
                runtime.sameFrameStreak=(runtime.sameFrameStreak or 0)+1
                if D.debugLogging then D.count("workerSameFrame") end
                if runtime.sameFrameStreak>=120 and not fade.pending() then
                    worker=false -- resume remaining work on the next owned event
                    return true
                end
                return false
            end
            runtime.sameFrameStreak=0
            runtime.fadeSuspended=false
            -- Frame count alone is not a pause detector: Dawnwalker's pause
            -- menu continues rendering. A frozen game clock across several
            -- *different* frames is the decisive signal. Preserve the fade's
            -- state, but avoid panel work until simulation moves again.
            if runtime.fadeInFlight and valid(controller) then
                local gameTime=frameClock:GetGameTimeInSeconds(controller)
                local wasPaused=runtime.fadePacing.paused()
                local pace=runtime.fadePacing.observe(frame,gameTime,true)
                if pace=="paused" then
                    lastFrame=frame
                    if not wasPaused and D.debugLogging then
                        D.count("fadeGameTimePaused")
                        D.event("fadePause","game time frozen while frames advanced; holding fade")
                    end
                    if D.debugLogging then D.count("fadePausedChecks") end
                    runtime.fadeSuspended=true
                elseif pace=="resumed" and D.debugLogging then
                    D.count("fadeGameTimeResumed")
                    D.event("fadePause","game time advanced; resuming held fade")
                end
            end
            -- Whether a fade is actually getting every frame is invisible
            -- from the outside, so measure it. steps == frames drawn means
            -- we are matching the display; a non-zero skip count means the
            -- timer is still coarser than the refresh rate.
            if D.debugLogging and lastFrame ~= nil and fade.pending() then
                D.count("fadeSteps")
                local skipped = frame - lastFrame - 1
                if skipped > 0 then
                    -- Keep exact aggregate evidence in the periodic summary.
                    -- A per-gap event would flood the rate-limited event log
                    -- during the very stutter this diagnostic investigates.
                    D.count("fadeFrameGaps")
                    D.count("fadeFramesSkipped",skipped)
                end
            end
            lastFrame=frame
            return step()
        end)
        if not success then
            worker=false
            cursor=0
            D.logError("Update failed: %s",tostring(stop))
            return true
        end
        return stop
    end)
end
-- Recovery is driven by construction, activation, presets, form changes
-- and the panel events below. No permanent opacity audit is scheduled.
applyLiveSettings=function(run)
    if not run then wake('liveSettings');return end
    local values=livePending;livePending=nil
    -- A menu Apply is a new visibility contract. Do not carry a settled
    -- target from the previous configuration into its first Show HUD pass.
    runtime.peekSettled={}
    if peekVisible then peekDirty=true end
    local updated=require('SettingsModel').convert(values)
    local changed={}
    for key,value in pairs(updated) do
        if type(value)~='table' and config[key]~=value then changed[key]=true end
    end
    local changedPanelCount=0
    for _,name in ipairs(names) do
        local panelChanged=panelModes[name]~=updated.panelModes[name]
            or panelOpacities[name]~=updated.panelOpacities[name]
            or panelScales[name]~=updated.panelScales[name]
        if panelChanged then
            changedPanelCount=changedPanelCount+1
            livePanels[name]=true
            absent[name]=nil
        end
        panelModes[name]=updated.panelModes[name]
        if panelScales[name]~=updated.panelScales[name] then
            if not panelScaling then panelScaling=require('QuietDawnPanelScale').new(panelScales,D,Session) end
            panelScaling.configure(name,updated.panelScales[name])
        end
        panelOpacities[name]=updated.panelOpacities[name]
        panelScales[name]=updated.panelScales[name]
    end
    local changedPeekPanelCount=0
    config.showHUDPanels=config.showHUDPanels or {}
    config.fixedPeekPanels=config.fixedPeekPanels or {}
    for name,include in pairs(updated.showHUDPanels or {}) do
        if config.showHUDPanels[name]~=include then
            config.showHUDPanels[name]=include
            changedPeekPanelCount=changedPeekPanelCount+1
        end
    end
    for name,raise in pairs(updated.fixedPeekPanels or {}) do
        if config.fixedPeekPanels[name]~=raise then
            config.fixedPeekPanels[name]=raise
            changedPeekPanelCount=changedPeekPanelCount+1
        end
    end
    for key,value in pairs(updated) do if type(value)~='table' then config[key]=value end end
    if changed.showCounterattackDirection or changed.showUnblockableWarning or changed.showDirectionalParry
        or changed.showEnemyMarker or changed.showLockIcon or changed.logLevel then combatGuard.configure() end
    if changed.fadeTransitions or changed.fadeInSeconds or changed.fadeOutSeconds then
        fade.configure(config.fadeTransitions,config.fadeInSeconds,config.fadeOutSeconds)
        runtime.fadePacing.reset()
    end
    dynamicPanels.HumanStats,dynamicPanels.VampireStats=updated.dynamicPanels.HumanStats,updated.dynamicPanels.VampireStats
    statNames={}
    for _,name in ipairs({'HumanStats','VampireStats'}) do if dynamicPanels[name] then statNames[#statNames+1]=name end end
    manualPeekEnabled=config.manualPeek and hasPeekPanels()
    timeRevealEnabled=seen.WBP_HudTimer and panelModes.WBP_HudTimer==Modes.QUIET_DAWN and config.timeHoldSeconds>0
    if changed.logLevel and QuietDawnNative then QuietDawnNative.setLogging(config.debugLogging) end
    if changed.healthThreshold or changed.staminaThreshold or changed.healthHoldSeconds or changed.staminaHoldSeconds
        or changed.mode_HumanStats or changed.mode_VampireStats
        or changed.opacity_HumanStats or changed.opacity_VampireStats then
        healthUntil,staminaUntil=0,0
        statsPending,statsRefresh=true,true
        livePanels.HumanStats,livePanels.VampireStats=true,true
    end
    if changed.manualPeek or changed.manualPeekSeconds or not manualPeekEnabled then
        if config.peekOnLegendHold and valid(hud) then
            local legend=hud.WBP_ControlsLegend
            peekWidgetAddress=valid(legend) and legend:GetAddress() or nil
            peekControllerAddress=controllerAddress
        end
        if peekVisible then peekDirty=true end
        peekRequested,peekVisible,peekUntil=false,false,0
        peekStartPending=false
        runtime.peekSettled={}
        runtime.focusPeekActive=nil
        -- Applying Focus mode while it is already held needs one immediate
        -- event-driven snapshot; it must not wait for a later resource change.
        if manualPeekEnabled and config.peekOnFocusMode then statsPending=true end
    elseif changedPeekPanelCount>0 and manualPeekEnabled and config.peekOnFocusMode then
        -- Re-including a panel while Focus is already active needs the same
        -- one-shot authoritative snapshot; no Focus polling is introduced.
        statsPending=true
    end
    if changed.timeHoldSeconds or changed.mode_WBP_HudTimer or changed.opacity_WBP_HudTimer then
        timeWatcher=timeRevealEnabled and require("QuietDawnTime").new(D) or nil
        if timeWatcher then timeWatcher.reset() end
        timeRequested,timeVisible,timeUntil=false,false,0;livePanels.WBP_HudTimer=true
    end
    if changed.switchRevealSeconds or not hasSwitchPanels() then
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
    if changed.logLevel and not changed.hideSprintPrompt then sprintSource.configure(config.hideSprintPrompt) end
    if changed.hidePlayerCombatEffects then
        if not playerEffects and config.hidePlayerCombatEffects then
            playerEffects=require('QuietDawnPlayerEffects').new(D,Session,function()wake('playerEffects')end,function()
                if valid(controller) and valid(world) then return controller.Pawn,world end
            end)
        end
        if playerEffects then playerEffects.configure(config.hidePlayerCombatEffects) end
    end
    if changed.hideClawSlashMarks then
        if not clawMarks and config.hideClawSlashMarks then
            clawMarks=require('QuietDawnClawMarks').new(D,Session,function()wake('clawMarks')end)
        end
        if clawMarks then clawMarks.configure(config.hideClawSlashMarks) end
    end
    if changed.hideVampireClawHitMarks then
        if not clawHits and config.hideVampireClawHitMarks then
            clawHits=require('QuietDawnClawHits').new(D,Session,function()
                if valid(controller) and valid(world) then return controller.Pawn,world end
            end)
        end
        if clawHits then clawHits.configure(config.hideVampireClawHitMarks) end
    end
    if changed.hideEnemyHealthBars or changed.hideEnemyNames or changed.hideEnemyDifficultyIcons or changed.showEnemyMarker or changed.hideEnemyEffectIcons then
        enemyBars.reconfigure(changed)
    end
    if changed.showCounterattackDirection or changed.showUnblockableWarning or changed.showDirectionalParry
        or changed.showEnemyMarker or changed.showLockIcon or changed.combatCueSize then
        for _,entry in pairs(markerCache) do queueMarker(entry.object,nil,"settings") end
    end
    ensureFeatureSpecs()
    -- A mode transition changes the interpretation of a cached opacity. Do one
    -- complete, ordered reconciliation after Apply instead of letting a stale
    -- dynamic-stat pass race the individual changed-panel jobs. This is vital
    -- when both stat panels become Fixed Opacity: they no longer have resource
    -- handlers to produce a later corrective pass.
    if changedPanelCount>0 or changedPeekPanelCount>0 then
        fullPending=true
        dirty=true
        if D.debugLogging then
            D.count("settingsPanelReconciliations")
            -- Apply is deliberate and infrequent, so preserve the exact mode
            -- and fixed-opacity values outside the ordinary event-rate limit.
            D.logInfo("Settings reconciliation: changedPanels=%d changedPeekPanels=%d human mode=%d opacity=%.2f vampire mode=%d opacity=%.2f",
                changedPanelCount,changedPeekPanelCount,panelModes.HumanStats,panelOpacities.HumanStats or 0,
                panelModes.VampireStats,panelOpacities.VampireStats or 0)
        end
    end
    -- Existing reveal expiry owns its one deadline; changes cancel/rearm it.
    if changed.healthThreshold or changed.staminaThreshold or changed.healthHoldSeconds or changed.staminaHoldSeconds
        or changed.manualPeek or changed.manualPeekSeconds or changed.timeHoldSeconds or changed.switchRevealSeconds
        or changed.mode_HumanStats or changed.mode_VampireStats or changed.mode_WBP_HudTimer
        or changed.mode_WBP_HUD_Quickslots or changed.mode_WBP_AA_Quickslots then armExpiry() end
end

if config.hidePlayerCombatEffects then
    playerEffects=require('QuietDawnPlayerEffects').new(D,Session,function()wake('playerEffects')end,function()
        if valid(controller) and valid(world) then return controller.Pawn,world end
    end)
end
if config.hideClawSlashMarks then
    clawMarks=require('QuietDawnClawMarks').new(D,Session,function()wake('clawMarks')end)
end
if config.hideVampireClawHitMarks then
    clawHits=require('QuietDawnClawHits').new(D,Session,function()
        if valid(controller) and valid(world) then return controller.Pawn,world end
    end)
end
local subscribed = pcall(NotifyOnNewObject, ROOT, function(object)
    candidate=object -- construction is not readiness: defer all object reads
    candidateSource="NotifyOnNewObject"
    sprintSource.recover()
    wake()
end)
if not subscribed then
    D.logError("HUD lifecycle notification unavailable; disabled.")
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
    if not timeSubscribed then D.logWarning("Time panel lifecycle notification unavailable.") end
end
local markerSubscribed=pcall(NotifyOnNewObject, MARKER, function(object)
    markerSeen=true
    markerHookAttempts=0
    queueMarker(object,nil,"lifecycle")
end)
if not markerSubscribed then
    D.logWarning("Marker lifecycle notification unavailable; marker left to the game.")
end
enemyBars.subscribe(NotifyOnNewObject)
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
    for _,deadline in ipairs({peekVisible and not peekStartPending and peekUntil>0 and peekUntil or false,switchVisible and switchUntil or false,timeVisible and timeUntil or false}) do
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
        local endedPeek=peekVisible and peekUntil>0 and now>=peekUntil
        if endedPeek then
            peekVisible=false
            runtime.peekSettled={}
            peekDirty=true
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
            or now<healthUntil or now<staminaUntil
        local target=needed and 1 or 0
        if endedPeek or endedSwitch or desired~=target then
            desired=target;statDirty=true;wake("resource")
        elseif endedTime then wake("time")
        else armExpiry() end
    end)
end
wake()
