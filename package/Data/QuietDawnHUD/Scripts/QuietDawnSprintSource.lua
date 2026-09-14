-- Quiet Dawn - Configurable HUD. MIT.
-- Native source suppression is scoped to one ShowPrompt call. Its engine-owned
-- snapshot is restored before that call returns, including while settings change.
local M={}
function M.new(api,D,session)
    local enabled,logging,pending,attempts=false,false,false,0
    local available=type(api._QDNSprintConfigure)=='function' and type(api._QDNIsSprintPrompt)=='function'
    local ready=false
    local self={}
    function self.configure(value)
        enabled=value==true;logging=D.debugLogging==true;attempts=0
        pending=available
        if not enabled then
            ready=false
            if available then api._QDNSprintConfigure(false,logging);pending=false end
        end
    end
    function self.pending() return pending end
    function self.ready() return ready end
    function self.recover()
        if available and enabled and not ready then pending=true;attempts=0 end
    end
    function self.step()
        if not pending then return end
        attempts=attempts+1
        local ok,reason=pcall(api._QDNSprintConfigure,enabled,logging)
        if ok then
            ready=enabled;pending=false
            if D.debugLogging then D.event('sprintSource','source suppression=%s',tostring(enabled)) end
        elseif attempts>=8 then
            pending=false;ready=false
            if D.debugLogging then D.event('sprintSource','native source unavailable: %s',tostring(reason)) end
        end
    end
    function self.classify(object)
        if not ready then return nil end
        return api._QDNIsSprintPrompt(object:GetFullName(),object:GetAddress())
    end
    session.onClose(function()
        pending=false;ready=false
        if available then api._QDNSprintConfigure(false,D.debugLogging==true) end
    end)
    return self
end
return M
