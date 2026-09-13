-- MIT. One-time, owner-scoped HUD transforms on the existing panel worker.
local M = {}
local pivots = {
    HumanStats={0,1}, VampireStats={0,1}, WBP_BuffContainer={0,1},
    WBP_HUD_FocusCharge_Bar={0,1}, XPBar={0,1}, WBP_ControlsLegend={0,1},
    WBP_HUD_Quickslots={1,1}, WBP_AA_Quickslots={1,1},
    WBP_HUD_Quickslots_ChangePrompt={1,1}, WBP_OpenFocusPrompt={1,1},
    WBP_HUD_AbilityCooldownsContainer={1,1}, WBP_HUD_SpecialAttackCooldown={1,1},
    WBP_HUD_QuestInfo={1,0}, WBP_HudTimer={1,0}, WBP_Compass={0.5,0},
    Crosshair={0.5,0.5}, CombatFocusPanel={0.5,0.5},
}
local function number(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function equal(a,b) return math.abs(a-b)<=1e-5*math.max(1,math.abs(a),math.abs(b)) end
local function read(o,kind)
    -- Copy scalars immediately; no borrowed transform/pivot survives this call.
    local x,y
    if kind=='scale' then x,y=o.RenderTransform.Scale.X,o.RenderTransform.Scale.Y
    else x,y=o.RenderTransformPivot.X,o.RenderTransformPivot.Y end
    assert(number(x) and number(y),'Panel transform unavailable')
    return x,y
end
local function write(s,kind,x,y,diagnostics)
    if kind=='scale' then s.object:SetRenderScale({X=x,Y=y})
    else s.object:SetRenderTransformPivot({X=x,Y=y}) end
    if diagnostics.debugLogging then diagnostics.count('panelScaleWrites') end
    local ax,ay=read(s.object,kind)
    assert(equal(ax,x) and equal(ay,y),'Panel transform readback failed')
end
function M.new(scales,diagnostics,session)
    local owners,ownerCount,generation,fullReported={},0,0,{}
    local function report(s,reason)
        if diagnostics.debugLogging then
            diagnostics.count('panelScaleFailures')
            diagnostics.event('panelScaleFailure','panel=%s reason=%s',s.name,tostring(reason))
        end
    end
    local function restore(s,kind)
        local last=s[kind..'Last']
        if not last or not s.same() then return end
        local x,y=read(s.object,kind)
        -- The pair is one property. Preserve a later external edit to either axis.
        if equal(x,last[1]) and equal(y,last[2]) then
            local base=s[kind..'Base']
            write(s,kind,base[1],base[2],diagnostics)
        end
        s[kind..'Last']=nil
    end
    local api={}
    function api.recover() generation=generation+1 end
    function api.pending(name,entry)
        if (scales[name] or 1)==1 then return false end
        if entry.scaleBindGeneration==generation and (entry.scaleBindTries or 0)>=8 then return false end
        local s=entry.panelScale
        if not s then return true end
        if s.done then return s.same~=nil and s.generation~=generation end
        return not s.failed or s.generation~=generation
    end
    function api.step(name,object,entry)
        local factor=scales[name] or 1
        if factor==1 then return true end
        if entry.scaleBindGeneration~=generation then entry.scaleBindTries=0;entry.scaleBindGeneration=generation end
        if (entry.scaleBindTries or 0)>=8 then return true end
        local s=entry.panelScale
        if s and s.done and s.generation~=generation and s.same then
            -- Lifecycle-only identity check; never inspect an unchanged transform.
            if s.same() then s.generation=generation
            else entry.panelScale=nil;s=nil end
        end
        if s and (s.done or (s.failed and s.generation==generation)) then return true end
        if not s then
            local bound,address,classAddress,fullName=pcall(function()
                local class=object:GetClass()
                assert(class:IsValid(),'Panel class unavailable')
                return object:GetAddress(),class:GetAddress(),object:GetFullName()
            end)
            if not bound then
                entry.scaleBindTries=(entry.scaleBindTries or 0)+1
                if entry.scaleBindTries>=8 then report({name=name},address);return true end
                return false
            end
            s=owners[address]
            if not s or not s.same() then
                -- Session cleanup also retains these owners; cap total retained work.
                if ownerCount>=256 then
                    if not fullReported[name] then report({name=name},'owner budget exhausted');fullReported[name]=true end
                    entry.panelScale={done=true}
                    return true
                end
                s={object=object,name=name,phase='capture',tries=0,generation=generation}
                s.same=function()
                    local ok,same=pcall(function()
                        if not object:IsValid() then return false end
                        local current=object:GetClass()
                        return current:IsValid() and current:GetAddress()==classAddress and object:GetFullName()==fullName
                    end)
                    return ok and same==true
                end
                owners[address]=s;ownerCount=ownerCount+1
            end
            entry.panelScale=s
            if s.name~=name then entry.panelScale={done=true};report(s,'shared scaling owner');return true end
            if s.done then return true end
        end
        if s.failed then
            if s.generation==generation then return true end
            s.failed,s.tries,s.generation=false,0,generation
            s.phase=s.scaleBase and 'pivot' or 'capture'
        end
        local ok,err=pcall(function()
            if not s.same() then s.done=true;return end
            if s.phase=='capture' then
                local sx,sy=read(object,'scale')
                local px,py=read(object,'pivot')
                s.scaleBase,s.pivotBase={sx,sy},{px,py}
                s.scaleTarget={sx*factor,sy*factor}
                -- Cleanup is reversed and yields between callbacks: scale then pivot.
                session.onClose(function() restore(s,'pivot') end)
                session.onClose(function() restore(s,'scale') end)
                s.phase='pivot'
            elseif s.phase=='pivot' or s.phase=='scale' then
                local kind=s.phase
                local target=kind=='pivot' and pivots[name] or s.scaleTarget
                local x,y=read(object,kind)
                if not equal(x,target[1]) or not equal(y,target[2]) then
                    s[kind..'Last']={target[1],target[2]}
                    write(s,kind,target[1],target[2],diagnostics)
                end
                if kind=='pivot' then s.phase='scale'
                else
                    s.done=true
                    if diagnostics.debugLogging then diagnostics.event('panelScale','panel=%s size=%.0f%%',name,factor*100) end
                end
            elseif s.phase=='rollbackScale' then restore(s,'scale');s.phase='rollbackPivot'
            elseif s.phase=='rollbackPivot' then restore(s,'pivot');s.failed=true;s.generation=generation end
        end)
        if not ok then
            if s.phase=='rollbackScale' or s.phase=='rollbackPivot' then
                -- Cleanup retains the failed restore for the next session transition.
                report(s,err)
                if s.phase=='rollbackScale' then s.phase='rollbackPivot'
                else s.failed=true;s.generation=generation end
            else
                s.tries=s.tries+1
                if s.tries>=8 then
                    report(s,err)
                    if s.scaleBase then s.phase='rollbackScale'
                    else s.failed=true;s.generation=generation end
                end
            end
        end
        return s.done or s.failed or false
    end
    return api
end
return M
