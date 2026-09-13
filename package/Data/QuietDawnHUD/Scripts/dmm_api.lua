-- Copy this file into your mod's Scripts folder to use subscribe().
-- Each mod keeps its own Lua callback. UE4SS delivers the named command.
local M={version=1}
local subscriptions={}
local owner=tostring({}):gsub('%W','')
local prefix='DMM_SettingsApplied_v1_'
local function hex(value)
    assert(type(value)=='string' and #value>0 and #value<=128,'invalid settings Id')
    return (value:gsub('.',function(c) return string.format('%02x',c:byte()) end))
end
local function unhex(value)
    assert(#value>0 and #value<=256 and #value%2==0 and not value:find('[^%da-f]'),'invalid encoded Id')
    return (value:gsub('..',function(c) return string.char(tonumber(c,16)) end))
end
local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<=1000000000
end
local function revision(payload)
    return type(payload)=='string' and tonumber(payload:match('^(%d+)\n')) or 0
end
local function read(payload)
    assert(type(payload)=='string' and #payload<=98304,'invalid settings notification')
    local rev=revision(payload)
    assert(rev and rev>=1 and rev<=9007199254740991,'invalid notification revision')
    local values,changes,count={},{},0
    for line in payload:sub(assert(payload:find('\n',1,true))+1):gmatch('[^\n]+') do
        local key,old,new=line:match('^(%x+) ([^ ]+) ([^ ]+)$')
        assert(key,'invalid settings notification row')
        key=unhex(key); old,new=tonumber(old),tonumber(new)
        assert(finite(old) and finite(new) and values[key]==nil,'invalid notification value')
        count=count+1; assert(count<=256,'too many notification values')
        values[key]=new
        if old~=new then changes[key]={old=old,new=new} end
    end
    assert(count>0,'empty settings notification')
    return rev,values,changes
end
local function setCallback(record,callback)
    local ticket={}
    record.callback,record.ticket=callback,ticket
    return function() if record.ticket==ticket then record.callback=nil end end
end

function M.subscribe(modId,callback)
    assert(type(callback)=='function','settings callback must be a function')
    local command=prefix..hex(modId)
    local existing=subscriptions[command]
    if existing then return setCallback(existing,callback) end
    assert(ModRef and type(RegisterConsoleCommandHandler)=='function','UE4SS notification API unavailable')
    local claim=command..'.owner'
    assert(ModRef:GetSharedVariable(claim)==nil,'this Mod Id already has a subscriber; fully restart after script reloads')
    local record={callback=callback,last=revision(ModRef:GetSharedVariable(command..'.data')) or 0}
    -- One native registration per Mod Id. Never move callbacks between Lua states.
    ModRef:SetSharedVariable(claim,owner)
    local ok,err=pcall(RegisterConsoleCommandHandler,command,function()
        local success,message=pcall(function()
            local rev,values,changes=read(ModRef:GetSharedVariable(command..'.data'))
            if rev<=record.last then return end
            record.last=rev
            if record.callback then record.callback(values,changes) end
        end)
        if not success then print('[DMM API] Settings callback failed for '..modId..': '..tostring(message)..'\n') end
        return true
    end)
    if not ok then
        -- Keep the claim after a partial registration. A retry must not register twice.
        error(tostring(err),0)
    end
    subscriptions[command]=record
    return setCallback(record,callback)
end

function M.publish(modId,event,pc,log)
    local ok,err=pcall(function()
        if not ModRef then return end -- Existing file-only integrations need no callback.
        local command=prefix..hex(modId)
        if not ModRef:GetSharedVariable(command..'.owner') then return end
        local previous=revision(ModRef:GetSharedVariable(command..'.data')) or 0
        assert(previous>=0 and previous<9007199254740991,'notification revision exhausted')
        local lines={string.format('%.0f',previous+1)}
        local count=0
        for key,value in pairs(event.values) do
            local change=event.changes[key]
            local old=change and change.old or value
            assert(finite(value) and finite(old),'invalid settings notification value')
            count=count+1; assert(count<=256,'too many notification values')
            lines[#lines+1]=hex(key)..' '..string.format('%.17g',old)..' '..string.format('%.17g',value)
        end
        assert(count>0,'empty settings notification')
        local payload=table.concat(lines,'\n')..'\n'
        assert(#payload<=98304,'settings notification exceeds bounds')
        assert(pc and pc:IsValid(),'settings player unavailable')
        local player=pc.Player
        assert(player and player:IsValid(),'local player unavailable')
        local viewport=player.ViewportClient
        assert(viewport and viewport:IsValid() and viewport:IsA('/Script/Engine.GameViewportClient'),'game viewport unavailable')
        ModRef:SetSharedVariable(command..'.data',payload)
        assert(viewport:ProcessConsoleExec(command,nil,pc)==true,'settings notification was not handled')
    end)
    -- Config is already saved. A listener failure must not turn Apply into a failed save.
    if not ok then log('NOTIFY_FAILED',modId..': '..tostring(err)) end
    return ok
end
return M
