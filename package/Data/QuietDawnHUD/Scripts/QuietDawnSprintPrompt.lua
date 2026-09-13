-- Quiet Dawn - Configurable HUD. MIT.
-- Build 25232147: sprint abilities use these ST_InputNames keys. Match the
-- text identity, never the translated label or a button shared with another action.
local M = {}
function M.new(api)
    local fields={"WBP_InputPrompt","WBP_SecondInputPrompt"}
    local tableId="/Game/_Dawnwalker/Player/Input/ST_InputNames.ST_InputNames"
    local entries,library,owner,cursor,attempts,again={},nil,nil,3,0,false
    local function valid(object) return object~=nil and object:IsValid() end
    local function same(a,b) return valid(a) and valid(b) and a:GetAddress()==b:GetAddress() end
    local function classify(object)
        -- The returned FName/FString are consumed in this callback. No borrowed
        -- text/struct storage survives the reflected call or the worker slice.
        local id,key={},{}
        if not library:StringTableIdAndKeyFromText(object["Prompt Text"],id,key) then return false end
        local name=key.OutKey:ToString()
        return id.OutTableId:ToString()==tableId and (name=="Input_Sprint" or name=="Input_Haste")
    end
    local self={}
    local enabled=true
    function self.setEnabled(value) enabled=value==true end
    function self.queue(hud)
        if not same(owner,hud) then entries={};owner=hud;cursor=3 end
        if cursor<=2 then again=true else cursor,attempts,again=1,0,false end
    end
    function self.cancel() cursor,again=3,false end
    function self.pending(hud) return cursor<=#fields and same(owner,hud) end
    function self.step(hud)
        if not self.pending(hud) then return end
        -- One lookup OR one named prompt per existing worker frame. Missing
        -- readiness gets eight attempts, then sleeps until another HUD event.
        if enabled and not valid(library) then
            attempts=attempts+1
            library=api.StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
            if attempts>=8 and not valid(library) then
                cursor=3
                if api.D.debugLogging then api.D.event("sprintPrompt","text library unavailable; waiting for HUD event") end
            end
            return
        end
        local field=fields[cursor]
        local object=hud[field]
        if not valid(object) then
            attempts=attempts+1
            if attempts<8 then return end
            cursor,attempts=cursor+1,0
            if cursor>2 and again then cursor,again=1,false end
            return
        end
        local entry=entries[field]
        if not entry or not same(entry.object,object) then
            entry={object=object,original=object:GetRenderOpacity(),hidden=false}
            entries[field]=entry
        end
        local ok,hide=true,false
        if enabled then ok,hide=pcall(classify,object) end
        if not ok then
            hide=false
            if api.D.debugLogging and not entry.warned then
                entry.warned=true;api.D.event("sprintPrompt","unreadable prompt identity: %s",field)
            end
        end
        local current=object:GetRenderOpacity()
        local wasHidden=entry.hidden
        -- FadeIn animates Border_676 inside this widget. Its root opacity is
        -- independent, so the fade cannot reveal a hidden running prompt.
        if hide then
            if not entry.hidden or current~=0 then entry.original=current end
            if current~=0 then api.opacity(object,0) end
            entry.hidden=true
        elseif entry.hidden then
            -- Preserve an external opacity change made after our suppression.
            if current==0 then api.opacity(object,entry.original) end
            entry.hidden=false
        else entry.original=current end
        if api.D.debugLogging then
            api.D.count("sprintPromptChecks")
            if wasHidden~=entry.hidden then api.D.event("sprintPrompt","field=%s hidden=%s",field,tostring(entry.hidden)) end
        end
        cursor,attempts=cursor+1,0
        if cursor>2 and again then cursor,again=1,false end
    end
    return self
end
return M
