-- MIT. Observe actual time only after stock HUD updates and lifecycle events.
-- Cache the game-instance subsystem; retain owned numbers, never return structs.
local M = {}
function M.new(D)
    local library, class, system, day, clock
    local requested, confirmed, waiting, lookupTried = false, false, false, false
    local attempts, warned = 0, false
    local function valid(object) return object~=nil and object:IsValid() end
    local function finite(value) return type(value)=='number' and value==value and math.abs(value)<math.huge end
    local function sample(hud)
        if not valid(system) then
            if not lookupTried then
                lookupTried=true
                library=StaticFindObject('/Script/Engine.Default__SubsystemBlueprintLibrary')
                class=StaticFindObject('/Script/DogwoodSystem.TimeSystemImpl')
            end
            if not valid(library) or not valid(class) then return end
            system=library:GetGameInstanceSubsystem(hud,class)
            if not valid(system) then return end
            -- A replacement subsystem starts a new baseline.
            day,clock=nil,nil
        end
        local currentDay=system:GetCurrentDay()
        local currentTime=system:GetCurrentDayTimeAsFloat()
        if not finite(currentDay) or not finite(currentTime) then return end
        local advanced=day~=nil and (currentDay>day or (currentDay==day and currentTime>clock+0.000001))
        day,clock=currentDay,currentTime
        return advanced
    end
    local api={}
    function api.reset()
        system,day,clock=nil,nil,nil
        requested,confirmed,waiting,lookupTried=true,false,false,false
        attempts,warned=0,false
    end
    function api.queue(isConfirmed)
        requested=true
        confirmed=confirmed or isConfirmed==true
    end
    function api.pending() return requested end
    function api.resume() if waiting or day==nil then requested=true end end
    function api.cancel()
        api.reset()
        requested=false
    end
    function api.recover()
        attempts,lookupTried=0,false
        requested=true
    end
    function api.step(hud,widget)
        if not requested then return false end
        requested=false
        if not valid(widget) then
            attempts=attempts+1;requested=attempts<8
            return false
        end
        if attempts<8 then
            local ok,advanced=pcall(sample,hud)
            if ok and advanced~=nil then
                attempts=0
                if advanced then
                    waiting=true
                    if D.debugLogging then D.count('timeDisplayChanges') end
                end
            else
                attempts=attempts+1
                requested=attempts<8
                if D.debugLogging and not warned then
                    warned=true
                    D.event('timeDisplay','actual-time read unavailable; waiting for a later HUD event')
                end
            end
        end
        if confirmed then waiting=true;confirmed=false end
        if not waiting then return false end
        -- Presets can hide the HUD during an activity. Keep the request dormant
        -- until a stock preset/activation event makes the timer visible again.
        if hud:IsVisible()~=true or widget:IsVisible()~=true then return false end
        waiting=false
        return true
    end
    return api
end
return M
