-- MIT. Owned settings snapshots; all runtime capabilities are injected.
-- Construction is inert. Call start once from the persistent mod entry point.
local M = {}
local function copy(source)
    local target = {}
    for key,value in pairs(source or {}) do target[key]=value end
    return target
end
function M.new(options)
    local o=assert(options)
    local schema,ids={},{}
    for _,row in ipairs(assert(o.schema)) do
        assert(not schema[row.key], 'Duplicate settings key: '..row.key)
        schema[row.key]=row
    end
    for id,key in pairs(assert(o.ids)) do
        assert(schema[key], 'Unknown settings key: '..key)
        assert(not ids[key], 'Duplicate mapped settings key: '..key)
        ids[key]=id
    end
    local values,handler,ticket,started,unsubscribe=nil,nil,nil,false,nil
    local revision=0
    local failures,failureCount={},0
    local api={}
    local function report(err)
        local message=tostring(err)
        if failures[message] or failureCount>=64 then return end
        failures[message]=true;failureCount=failureCount+1
        if o.report then o.report('Live settings: '..message) end
    end
    local function validate(candidate)
        for key,row in pairs(schema) do
            local v=candidate[key]
            assert(type(v)=='number' and v==v and math.abs(v)<math.huge, 'Invalid setting: '..key)
            if row.values then
                local found=false
                for _,allowed in ipairs(row.values) do if v==allowed then found=true;break end end
                assert(found, 'Unsupported setting: '..key)
            else
                assert((not row.min or v>=row.min) and (not row.max or v<=row.max)
                    and (not row.integer or v%1==0), 'Out-of-range setting: '..key)
            end
        end
        return candidate
    end
    function api.snapshot() return values and copy(values) end
    function api.revision() return revision end
    -- Configuration boundaries supply a complete numeric snapshot. Never keep
    -- a caller-owned table: consumers may convert percentages or booleans.
    function api.seed(initial)
        values=validate(copy(initial)); revision=revision+1
        return copy(values)
    end
    local function notify(candidate)
        local changed={}
        for key,value in pairs(candidate) do
            local old=values and values[key]
            if old~=value then changed[key]={old=old,new=value} end
        end
        if not next(changed) then return false end
        values=candidate;revision=revision+1
        if handler then
            local ok,err=pcall(handler,copy(values),changed)
            if not ok then report(err) end
        end
        return true
    end
    -- Native settings confirmations use this after their own successful save.
    function api.commit(initial)
        local ok,result=pcall(function() return notify(validate(copy(initial))) end)
        if not ok then report(result);return false end
        return result
    end
    function api.accept(committed)
        local ok,result=pcall(function()
            assert(type(committed)=='table', 'Missing callback values')
            local candidate=copy(values)
            for key,row in pairs(schema) do
                if candidate[key]==nil then candidate[key]=row.default end
            end
            for id,key in pairs(o.ids) do
                assert(committed[id]~=nil, 'Missing callback setting: '..id)
                candidate[key]=committed[id]
            end
            if o.derive then o.derive(candidate) end
            return notify(validate(candidate))
        end)
        if not ok then report(result);return false end
        return result
    end
    function api.attach(callback)
        assert(type(callback)=='function')
        local own={};handler,ticket=callback,own
        return function() if ticket==own then handler,ticket=nil,nil end end
    end
    function api.start(subscribe)
        if started then return unsubscribe~=nil end
        started=true -- Partial native registration must never be retried.
        local ok,result=pcall(subscribe,assert(o.modId),api.accept)
        if not ok then report(result);return false end
        if type(result)~='function' then report('Settings subscription did not return an unsubscribe function');return false end
        unsubscribe=result
        return true
    end
    return api
end
return M
