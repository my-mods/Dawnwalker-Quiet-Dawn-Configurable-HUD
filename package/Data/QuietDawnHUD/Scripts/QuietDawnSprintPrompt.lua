-- Quiet Dawn - Configurable HUD. MIT.
-- Build 25232147: resolve the game's localized Sprint/Haste labels directly.
-- UE4SS flattens FText inputs, so passing text back to an identity query loses
-- its string-table history. Never hard-code English labels or shared buttons.
local M = {}
function M.new(api)
    local fields={"WBP_InputPrompt","WBP_SecondInputPrompt"}
    local tableId="/Game/_Dawnwalker/Player/Input/ST_InputNames.ST_InputNames"
    local entries,library,owner,cursor,attempts,again={},nil,nil,3,0,false
    local tableLibrary,tableName
    local keys={"Input_Sprint","Input_Haste"}
    local function valid(object) return object~=nil and object:IsValid() end
    local function same(a,b) return valid(a) and valid(b) and a:GetAddress()==b:GetAddress() end
    local function classify(object)
        local label=object["Prompt Text"]:ToString()
        if type(label)~="string" or label=="" then return false,"" end
        -- Consume return text immediately; retain no FText/borrowed return
        -- buffer. Resolving on prompt events also follows language changes.
        for _,key in ipairs(keys) do
            if tableLibrary:IsRegisteredTableEntry(tableName,key)==true then
                local expected=library:TextFromStringTable(tableName,key):ToString()
                if type(expected)=="string" and expected~="" and label==expected then return true,label,key end
            end
        end
        return false,label
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
        if enabled and not tableName then tableName=api.FName(tableId);return end
        if enabled and (not valid(library) or not valid(tableLibrary)) then
            attempts=attempts+1
            local found
            if not valid(library) then
                library=api.StaticFindObject("/Script/Engine.Default__KismetTextLibrary");found=valid(library)
            else
                tableLibrary=api.StaticFindObject("/Script/Engine.Default__KismetStringTableLibrary");found=valid(tableLibrary)
            end
            if found then attempts=0
            elseif attempts>=8 then
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
        local ok,hide,label,key=true,false,nil,nil
        if enabled then ok,hide,label,key=pcall(classify,object) end
        if not ok then
            hide=false
            if api.D.debugLogging and not entry.warned then
                entry.warned=true;api.D.event("sprintPrompt","unreadable prompt text: %s",field)
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
            if wasHidden~=entry.hidden or entry.label~=label then
                entry.label=label
                api.D.event("sprintPrompt","field=%s label=%s match=%s hidden=%s",field,(label or ""):sub(1,80),key or "-",tostring(entry.hidden))
            end
        end
        cursor,attempts=cursor+1,0
        if cursor>2 and again then cursor,again=1,false end
    end
    return self
end
return M
