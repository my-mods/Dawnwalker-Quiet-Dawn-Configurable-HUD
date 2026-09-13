-- Quiet Dawn - Configurable HUD. MIT.
-- Build 25232147: these two static gameplay cues own only the Shredded Touch
-- slash presentation. The native OneShotEffect reader safely skips a null VFX.
local M = {}
function M.new(D, session, wake)
    local root='/Game/_Dawnwalker/Stats/GameplayCues/Shred/'
    local effects='/Game/_Dawnwalker/VFX/03_ShreddedTouch/'
    local entries={
        {name='GC_ShredBleedingInflicted', effect='NS_Shred_Slash'},
        {name='GC_ShredBleedingInflicted_Sword', effect='NS_Shred_Sword'},
    }
    local cursor=1
    local function valid(o) return o~=nil and o:IsValid() end
    local function matches(o, name)
        return valid(o) and o:GetFullName()==name
    end
    local function report(entry, message)
        if D.debugLogging and not entry.warned then
            entry.warned=true
            D.event('clawMarks','cue=%s %s',entry.name,message)
        end
    end
    local function apply(entry, object)
        -- Reject instances, missing members (truthy invalid UObjects), changed
        -- assets and recycled identities before writing the reflected field.
        if not matches(object,entry.fullName) then return false end
        local class=object:GetClass()
        if not matches(class,'BlueprintGeneratedClass '..entry.classPath) then return false end
        local classAddress=class:GetAddress()
        local effect=object.OneShotEffect
        if not matches(effect,'NiagaraSystem '..entry.effectPath) then return false end
        local function sameOwner()
            return matches(object,entry.fullName) and matches(object:GetClass(),
                'BlueprintGeneratedClass '..entry.classPath)
                and object:GetClass():GetAddress()==classAddress
        end
        -- Install cleanup before the write so even a failed readback can restore.
        -- Never resurrect a deleted/replaced cue or overwrite another mod's VFX.
        local owned=false
        session.onClose(function()
            if not owned or not sameOwner() or valid(object.OneShotEffect) then return end
            if not matches(effect,'NiagaraSystem '..entry.effectPath) then
                -- Lua UObject wrappers do not root assets. Reacquire the exact
                -- original only during cleanup if garbage collection removed it.
                effect=LoadAsset(entry.effectPath)
            end
            assert(matches(effect,'NiagaraSystem '..entry.effectPath),'Claw marks original effect unavailable')
            object.OneShotEffect=effect
            assert(matches(object.OneShotEffect,'NiagaraSystem '..entry.effectPath),'Claw marks restore failed')
            if D.debugLogging then D.count('clawMarkRestores') end
        end)
        owned=true -- cleanup also covers a setter/readback that fails after mutation
        local written,writeError=pcall(function()object.OneShotEffect=nil end)
        owned=not valid(object.OneShotEffect)
        assert(written,writeError)
        assert(owned,'Claw marks write readback failed')
        entry.applied=object
        if D.debugLogging then
            D.count('clawMarkWrites')
            D.event('clawMarks','cue=%s hidden',entry.name)
        end
        return true
    end
    for _,entry in ipairs(entries) do
        entry.classPath=root..entry.name..'.'..entry.name..'_C'
        entry.path=root..entry.name..'.Default__'..entry.name..'_C'
        entry.fullName=entry.name..'_C '..entry.path
        entry.effectPath=effects..entry.effect..'.'..entry.effect
        entry.lookup=true
        local ok=pcall(NotifyOnNewObject,entry.classPath,function(object)
            -- Construction may run on another thread. Only queue a wrapper;
            -- all identity/property operations use the shared game-thread worker.
            entry.candidate=object
            if not entry.pending then entry.attempts=0 end
            entry.pending=true
            wake()
        end)
        if not ok then report(entry,'construction notification unavailable') end
    end
    local self={}
    function self.pending()
        for _,entry in ipairs(entries) do if entry.lookup or entry.pending then return true end end
        return false
    end
    function self.step()
        for _=1,#entries do
            local entry=entries[cursor]
            cursor=cursor%#entries+1
            if entry.lookup then
                entry.lookup=false
                local object=StaticFindObject(entry.path)
                if valid(object) then entry.candidate=object;entry.pending=true;entry.attempts=0 end
                if D.debugLogging then D.count('clawMarkLookups') end
                return -- one lookup OR one cue per existing worker frame
            elseif entry.pending then
                entry.attempts=entry.attempts+1
                local object=entry.candidate
                if valid(entry.applied) and valid(object)
                    and object:GetAddress()==entry.applied:GetAddress()
                    and matches(object,entry.fullName) and not valid(object.OneShotEffect) then
                    entry.pending=false
                    return
                end
                local ok,done=pcall(apply,entry,object)
                if done==true and ok then entry.pending=false
                elseif entry.attempts>=8 then
                    entry.pending=false
                    if D.debugLogging then
                        report(entry,ok and 'effect not ready or changed; waiting for construction/save load'
                            or 'effect operation failed: '..tostring(done))
                    end
                end
                return
            end
        end
    end
    return self
end
return M
