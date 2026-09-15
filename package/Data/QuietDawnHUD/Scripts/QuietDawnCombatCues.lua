-- Independent combat marker presentation. Stock events supply the current state.
local M = {}
function M.new(config, diagnostics, session)
    local padlock
    local fields={"Reticle","FarAwayReticle","HardLockTarget","HardLockTarget_Outline",
        "LeftArrow","RightArrow","TopArrow","BottomArrow","Indicator"}
    local attack={[1]="RightArrow",[2]="LeftArrow",[3]="TopArrow",[4]="BottomArrow",
        [5]="RightArrow",[6]="LeftArrow",[7]="TopArrow",[8]="BottomArrow"}
    local counter={[10]="LeftArrow",[11]="RightArrow",[12]="BottomArrow",[13]="TopArrow"}
    local function valid(o) return o~=nil and o:IsValid() end
    local function method(o,name)
        local ok,fn=pcall(function()
            if not valid(o) then return end
            local value=o[name]
            if type(value)=='function' then return value end
            if type(value)=='userdata' and value:type()=='UFunction' and value:IsValid() then return value end
        end)
        return ok and fn or nil
    end
    local function cleanup(entry,callback)
        session.onClose(function()
            local ok,err=pcall(callback)
            if not ok and diagnostics.debugLogging and not entry.cueCleanupWarned then
                entry.cueCleanupWarned=true
                diagnostics.event('combatCueCleanup','expired or unavailable marker: %s',tostring(err))
            end
        end)
    end
    local function identity(o)
        local class=o:GetClass()
        local classAddress,name=class:GetAddress(),o:GetFullName()
        return function()
            local ok,same=pcall(function()
                if not valid(o) then return false end
                local current=o:GetClass()
                return valid(current) and current:GetAddress()==classAddress and o:GetFullName()==name
            end)
            return ok and same==true
        end
    end
    local function visibility(entry, name, o, value)
        local current=o:GetVisibility()
        local saved=entry.cueVisibility[name]
        if not saved and current==value then return end
        local address=o:GetAddress()
        if not saved or saved.address~=address then
            local same=identity(o)
            saved={address=address,original=current}
            entry.cueVisibility[name]=saved
            cleanup(entry,function()
                if not same() then return end
                local get,set=method(o,'GetVisibility'),method(o,'SetVisibility')
                if get and set and get(o)==saved.last then set(o,saved.original) end
            end)
        end
        if current~=saved.last then saved.original=current end
        if current~=value then
            o:SetVisibility(value)
            if diagnostics.debugLogging then diagnostics.count('cueVisibilityWrites') end
        end
        saved.last=value
    end
    local function scale(o,factor,saved)
        if factor==1 and not saved then return end
        local address=o:GetAddress()
        if saved and saved.address==address and saved.same() and saved.factor==factor then return saved end
        if not saved or saved.address~=address or not saved.same() then
            local x,y=o.RenderTransform.Scale.X,o.RenderTransform.Scale.Y
            saved={address=address,same=identity(o),x=x,y=y}
        end
        for _,axis in ipairs({'X','Y'}) do
            local target=(axis=='X' and saved.x or saved.y)*factor
            local key='cue-scale:'..tostring(address)..':'..axis
            if factor==1 then session.restore(key)
            else
                session.change(key,function()
                    if not saved.same() then return nil,false end
                    if session.active==false then
                        if saved.restoreUnavailable or not method(o,'SetRenderScale') then return nil,false end
                        local ok,value=pcall(function() return o.RenderTransform.Scale[axis] end)
                        if not ok or type(value)~='number' then return nil,false end
                        return value
                    end
                    return o.RenderTransform.Scale[axis]
                end,function(value)
                    if session.active==false then
                        local ok,err=pcall(function()
                            assert(saved.same(),'Combat cue scale owner changed')
                            local x,y=o.RenderTransform.Scale.X,o.RenderTransform.Scale.Y
                            o:SetRenderScale({X=axis=='X' and value or x,Y=axis=='Y' and value or y})
                            local actual=o.RenderTransform.Scale[axis]
                            assert(type(actual)=='number' and math.abs(actual-value)<=1e-5*math.max(1,math.abs(value)),'Combat cue scale restore failed')
                        end)
                        if not ok then
                            saved.restoreUnavailable=true
                            if diagnostics.debugLogging then diagnostics.event('combatCueCleanup','scale restore unavailable: %s',tostring(err)) end
                        end
                        return true
                    end
                    assert(saved.same(),'Combat cue scale owner changed')
                    local x,y=o.RenderTransform.Scale.X,o.RenderTransform.Scale.Y
                    o:SetRenderScale({X=axis=='X' and value or x,Y=axis=='Y' and value or y})
                    return true
                end,target)
            end
        end
        saved.factor=factor
        return saved
    end
    local function attach(object, entry)
        local children={}
        for _,name in ipairs(fields) do
            local child=object[name]
            if not valid(child) then return nil end
            children[name]=child
        end
        entry.cueVisibility=entry.cueVisibility or {}
        if not entry.cueCleanup then
            local same=identity(object)
            cleanup(entry,function()
                if not same() then return end
                -- Session hooks are detached before cleanup. Restore the game's
                -- current brush/color after our scalar visibility/scale journal.
                local icon=tonumber(object['Currently Displayed Icon Type'])
                if not icon or icon<0 or icon>13 or icon%1~=0 then return end
                local name=object['Hide Directions']==true and 'Display Icon State Non-Directionally'
                    or 'Display Icon State Directionally'
                local fn=method(object,name)
                if fn then fn(object,icon) end
            end)
            entry.cueCleanup=true
        end
        return children
    end
    return function(object,entry,icon)
        local children=attach(object,entry)
        if not children then return false end
        local known=type(icon)=='number' and icon>=0 and icon<=13 and icon%1==0
        if not known then return false end
        local arrow
        if config.showCounterattackDirection then arrow=counter[icon] end
        if not arrow and config.showDirectionalParry then arrow=attack[icon] end
        local unblockable=icon==9 and config.showUnblockableWarning
        local lock=config.showLockIcon and object.bHardLockEnabled==true and not arrow and not unblockable
        if lock and not valid(padlock) then
            padlock=StaticFindObject('/Game/_Dawnwalker/UI/_Unified/SharedTextures/General/Frames/T_Icon_Padlock.T_Icon_Padlock')
            if not valid(padlock) then return false end
        end
        -- Hide the center through visibility: its own opacity animations must
        -- not bring the dot/lock back during a directional cue.
        visibility(entry,"Reticle",children.Reticle,(unblockable or lock) and 4 or 1)
        visibility(entry,"FarAwayReticle",children.FarAwayReticle,lock and 4 or 1)
        visibility(entry,"HardLockTarget",children.HardLockTarget,1)
        visibility(entry,"HardLockTarget_Outline",children.HardLockTarget_Outline,1)
        for _,name in ipairs({'LeftArrow','RightArrow','TopArrow','BottomArrow'}) do
            visibility(entry,name,children[name],name==arrow and 4 or 1)
        end
        if arrow and attack[icon] then
            -- This unhooked styling helper sets only the selected image. The
            -- two hooked display helpers must never be called while active.
            object['Apply Attack Style To Arrow'](object,children[arrow])
            if icon>=5 then children[arrow]:SetColorAndOpacity(object['Parry Window Color']) end
        elseif lock then
            children.Reticle:SetBrushFromAtlasInterface(padlock,true)
            children.Reticle:SetColorAndOpacity({R=1,G=1,B=1,A=1})
            children.FarAwayReticle:SetBrushFromAtlasInterface(padlock,true)
        end
        local factor=(config.combatCueSize or 100)/100
        entry.cueScale=scale(children.Indicator,factor,entry.cueScale)
        entry.farCueScale=scale(children.FarAwayReticle,factor,entry.farCueScale)
        if diagnostics.debugLogging and (entry.cueIcon~=icon or entry.cueArrow~=arrow or entry.cueLock~=lock) then
            diagnostics.event('combatCue','icon=%s arrow=%s unblockable=%s lock=%s size=%s',
                tostring(icon),tostring(arrow),tostring(unblockable),tostring(lock),tostring(config.combatCueSize or 100))
        end
        entry.cueIcon,entry.cueArrow,entry.cueLock=icon,arrow,lock
        return true,arrow~=nil or unblockable or lock
    end
end
return M
