-- Copyright (c) 2026 CamilleBC. MIT License; see LICENSE.
local M = {}
local function noop() end
local function format(message, ...)
    if select('#', ...) == 0 then return tostring(message) end
    local ok, text = pcall(string.format, message, ...)
    return ok and text or tostring(message)
end
function M.new(options)
    local o = options or {}
    if o.mutable then
        local configuration={}
        for key,value in pairs(o) do if key~='mutable' then configuration[key]=value end end
        local proxy,wrapped={},{}
        function proxy.setEnabled(enabled)
            enabled=enabled==true
            if proxy.debugLogging==enabled then return end
            configuration.debugLogging=enabled
            local implementation=M.new(configuration)
            proxy.debugLogging=enabled
            for _,name in ipairs({'log','error','debug','event','count','sample','flush','now','snapshot'}) do
                proxy[name]=implementation[name]
            end
            for _,record in ipairs(wrapped) do record.call=implementation.wrap(record.name,record.fn) end
            proxy._implementation=implementation
        end
        function proxy.wrap(name,fn)
            local record={name=name,fn=fn,call=proxy._implementation.wrap(name,fn)}
            wrapped[#wrapped+1]=record
            return function(...) return record.call(...) end
        end
        proxy.setEnabled(o.debugLogging==true)
        return proxy
    end
    local D = {debugLogging = o.debugLogging == true}
    local output, prefix = o.output or print, o.prefix or ''
    function D.log(message, ...) output(prefix .. format(message, ...)) end
    D.error = D.log
    D.debug, D.event, D.count, D.sample, D.flush = noop, noop, noop, noop, noop
    D.now = noop
    function D.wrap(_, fn) return fn end
    function D.snapshot() return nil end
    if not D.debugLogging then return D end
    local clock = o.clock or os.clock
    local interval, limit, slow = o.summarySeconds or 10, o.maxEventsPerSecond or 6, o.slowCallbackMs or 2
    assert(interval > 0 and limit >= 1 and slow >= 0, 'Invalid diagnostics limits')
    local lastClock, window, lastSummary, events, dropped, depth = nil, nil, nil, 0, 0, 0
    local counts, timings, clockWarning = {}, {}, false
    function D.now()
        local ok, now = pcall(clock)
        if not ok or type(now) ~= 'number' or now ~= now or math.abs(now) == math.huge
            or now < 0 or (lastClock and now < lastClock) then
            if not clockWarning then D.log('Clock unavailable or moved backwards; timing sample discarded.'); clockWarning = true end
            return nil
        end
        lastClock = now
        if not lastSummary then lastSummary = now end
        return now
    end
    function D.debug(message, ...) D.log(message, ...) end
    function D.count(key, amount) counts[key] = (counts[key] or 0) + (amount or 1) end
    function D.event(kind, message, ...)
        local now = D.now(); if not now then return end
        if not window or now - window >= 1 then window, events = now, 0 end
        if events >= limit then dropped = dropped + 1; return end
        events = events + 1
        D.log(kind .. ' ' .. format(message, ...))
    end
    function D.sample(name, ms)
        if type(ms) ~= 'number' or ms ~= ms or ms < 0 or ms == math.huge then return end
        local t = timings[name]
        if not t then t = {n=0, total=0, max=0, slow=0}; timings[name] = t end
        t.n, t.total, t.max = t.n + 1, t.total + ms, math.max(t.max, ms)
        if ms >= slow then t.slow = t.slow + 1 end
    end
    function D.snapshot()
        local copy = {counts={}, timings={}, dropped=dropped}
        for k,v in pairs(counts) do copy.counts[k] = v end
        for k,v in pairs(timings) do copy.timings[k] = {n=v.n,total=v.total,max=v.max,slow=v.slow} end
        return copy
    end
    function D.flush(force)
        if depth > 0 then return false end
        local now = D.now(); if not now then return false end
        if not force and now - lastSummary < interval then return false end
        local s = D.snapshot(); s.interval = now - lastSummary
        if o.onSummary then o.onSummary(s)
        else
            local parts = {string.format('summary interval=%.3fs suppressed=%d', s.interval, s.dropped)}
            local names = {}; for name in pairs(s.timings) do names[#names+1] = name end; table.sort(names)
            for _,name in ipairs(names) do
                local t = s.timings[name]
                parts[#parts+1] = string.format('%s calls=%d avgMs=%.3f maxMs=%.3f slow=%d',name,t.n,t.total/t.n,t.max,t.slow)
            end
            names = {}; for name in pairs(s.counts) do names[#names+1] = name end; table.sort(names)
            for _,name in ipairs(names) do parts[#parts+1] = name .. '=' .. tostring(s.counts[name]) end
            D.log(table.concat(parts, ' | '))
        end
        counts, timings, dropped, lastSummary = {}, {}, 0, now
        return true
    end
    function D.wrap(name, fn)
        return function(...)
            depth = depth + 1
            local started = D.now()
            local result = table.pack(pcall(fn, ...))
            local measured, measurementError = pcall(function()
                local finished = D.now()
                if started and finished and finished >= started then
                    local ms = (finished - started) * 1000
                    D.sample(name, ms)
                    if ms >= slow then D.event('slow','phase=%s elapsedMs=%.3f',name,ms) end
                end
                if not result[1] then D.event('error','phase=%s error=%s',name,tostring(result[2])) end
            end)
            depth = depth - 1
            if not result[1] then error(result[2], 0) end
            if not measured then error(measurementError, 0) end
            -- Never replace the original callback error with a summary error.
            if depth == 0 then
                local ok, err = pcall(D.flush, false)
                if not ok and result[1] then error(err, 0) end
            end
            return table.unpack(result, 2, result.n)
        end
    end
    return D
end
return M
