-- MIT. Optional Framecore 2b adapter. Native captures contain owned scalar
-- values and deletion-checked identities; delivery uses a UE4SS-created game-thread state.
local M = {}
function M.attach(api, report)
    if type(api._QDNInit)~='function' then return end
    local callbacks, timer, active, logging, frameClock, lastFrame = {}, nil, false, false, nil, nil
    local paths, classes, refresh, refreshCursor, warned = {}, {}, {}, 1, {}
    local highestId=0
    local originalHook=api.RegisterHook
    local function wrap(value) return {get=function() return value end} end
    local stop, schedule, drain
    stop=function()
        active=false
        if timer then api.CancelDelayedAction(timer);timer=nil end
        local matched,delivered,merged,overflow,stale,failures,ms=api._QDNStop()
        if logging then
            report(string.format('Native HUD events: captured=%d delivered=%d merged=%d overflow=%d stale=%d failures=%d captureMs=%.3f',
                matched,delivered,merged,overflow,stale,failures,ms))
        end
        logging=false;frameClock=nil;lastFrame=nil;refresh={};refreshCursor=1;warned={}
    end
    drain=function()
        timer=nil
        if not active then return end
        local ok,err=pcall(function()
            local frame=frameClock:GetFrameCount()
            if frame==lastFrame then schedule();return end
            lastFrame=frame
            -- Rebind one invalid function at a time after widget replacement.
            -- A class construction burst shares a finite, coalesced retry set.
            for offset=0,highestId-1 do
                local id=(refreshCursor+offset-1)%highestId+1
                if refresh[id] then
                    local ready,reason=pcall(api._QDNBind,paths[id])
                    refresh[id]=not ready and refresh[id]<12 and refresh[id]+1 or nil
                    refreshCursor=id%highestId+1
                    if not ready and not refresh[id] and logging and not warned[id] then
                        warned[id]=true;report('Native HUD rebind failed: '..paths[id]..': '..tostring(reason))
                    end
                    break
                end
            end
            -- Four small event callbacks per frame; Gameplay's existing
            -- worker still spreads all panel discovery and writes over frames.
            for _=1,4 do
                local id,object,value,previous=api._QDNNext()
                if not id then break end
                if id~=0 and callbacks[id] then
                    local success,reason=pcall(callbacks[id],wrap(object),wrap(value),wrap(previous))
                    if not success and logging and not warned[id] then
                        warned[id]=true;report('Native HUD callback failed: '..tostring(reason))
                    end
                end
            end
            if api._QDNMore() or next(refresh) then schedule() end
        end)
        if not ok then
            stop()
            report('Native HUD delivery stopped: '..tostring(err))
        end
    end
    schedule=function()
        if active and not timer then timer=api.ExecuteInGameThreadWithDelay(16,drain) end
    end
    -- The host executes this through its existing async action queue. It does
    -- no UObject access; all conversion and callback work happens in drain.
    api._QDNInit(function()
        local ok,err=pcall(schedule)
        if not ok then
            api._QDNStop();active=false
            report('Native HUD scheduling failed: '..tostring(err))
        end
    end)
    local bridge={stop=stop}
    function bridge.begin(debugLogging)
        stop()
        frameClock=api.StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
        assert(frameClock and frameClock:IsValid(),'Native HUD frame clock unavailable')
        api._QDNBegin(debugLogging==true)
        logging=debugLogging==true;active=true
        if logging then report('Native HUD bridge active (Framecore 2b; deletion tracking).') end
    end
    function bridge.setLogging(enabled)
        enabled=enabled==true
        if logging==enabled then return end
        api._QDNSetLogging(enabled)
        logging=enabled
    end
    function bridge.prepare(path)
        if path:sub(1,6)=='/Game/' then return api._QDNBind(path) end
    end
    function api.RegisterHook(path,before,after)
        local id=bridge.prepare(path)
        if not id then
            if after then return originalHook(path,before,after) end
            return originalHook(path,before)
        end
        assert(not after,'Native HUD Blueprint callbacks support post delivery only')
        callbacks[id]=before
        highestId=math.max(highestId,id)
        paths[id]=path;classes[id]=path:match('^(.*):[^:]+$')
        return id,id
    end
    local originalNotify=api.NotifyOnNewObject
    function api.NotifyOnNewObject(path,callback)
        return originalNotify(path,function(object)
            if active then
                for id,class in pairs(classes) do
                    if path==class or path=='/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C' then
                        refresh[id]=refresh[id] or 1
                    end
                end
                if next(refresh) then schedule() end
            end
            callback(object)
        end)
    end
    api.QuietDawnNative=bridge
    return bridge
end
return M
