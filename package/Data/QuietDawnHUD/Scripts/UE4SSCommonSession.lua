-- MIT. Explicit session ownership; importing this module has no side effects.
local M = {}
function M.new(api, directory, report, options)
    local current, closing, queued, generation = nil, nil, nil, 0
    local notifications, hooks, maps = {}, {}, {}
    local deferredCleanup
    local canCleanup = options and options.canCleanup
    local settings = options and options.settings
    report = report or function() end
    local function guard(scope, fn)
        return function(...)
            if current == scope and scope.active then return fn(...) end
        end
    end
    local function watch(path)
        if notifications[path] then return notifications[path] end
        local slot = {recent={}}
        api.NotifyOnNewObject(path, function(object)
            -- No native reads on construction threads. Keep a bounded replay inbox.
            if #slot.recent >= 128 then table.remove(slot.recent, 1) end
            slot.recent[#slot.recent+1] = object
            if slot.callback then slot.callback(object) end
        end)
        notifications[path] = slot
        return slot
    end
    local manager = {watch=watch}
    function manager.resumeCleanup()
        if deferredCleanup then
            local callback = deferredCleanup
            deferredCleanup = nil
            api.ExecuteInGameThreadWithDelay(16, callback)
        end
    end
    function manager.pause()
        generation = generation + 1
        if current then current.active = false end
    end
    local function equal(a, b)
        if type(a)=='number' and type(b)=='number' then
            return math.abs(a-b) <= 1e-5 * math.max(1,math.abs(a),math.abs(b))
        end
        return a == b
    end
    local function launch(file, context)
        local scope = {active=true, timers={}, journal={}, order={}, cleanup={}}
        current = scope
        if settings then
            if context.settings==nil and options.loadSettings then
                local ok,values=pcall(options.loadSettings)
                if ok and type(values)=='table' then
                    local accepted,err=pcall(settings.seed,values)
                    if not accepted then report('Settings snapshot rejected: '..tostring(err)) end
                elseif not ok then report('Settings read failed: '..tostring(values)) end
            end
            context.settings=settings.snapshot()
        end
        local env = setmetatable({Session=scope, SaveLoadContext=context}, {__index=api})
        env._G = env
        local loaded = {}
        function env.dofile(path) return assert(api.loadfile(path, 't', env))() end
        function env.require(name)
            if loaded[name] == nil then
                local result = env.dofile(directory .. name .. '.lua')
                loaded[name] = result == nil and true or result
            end
            return loaded[name]
        end
        function env.ExecuteInGameThreadWithDelay(delay, callback)
            local id
            id = api.ExecuteInGameThreadWithDelay(delay, function()
                scope.timers[id] = nil
                if current == scope and scope.active then callback() end
            end)
            scope.timers[id] = true
            return id
        end
        function env.CancelDelayedAction(id)
            local result = api.CancelDelayedAction(id)
            scope.timers[id] = nil
            return result
        end
        function scope.onSettings(callback)
            assert(settings, 'Session has no settings adapter')
            scope.settingsHandler=callback
        end
        -- Whole-mod enable/disable only. Ordinary edits use onSettings in place.
        function scope.restart()
            if scope.restartPending then return end
            scope.restartPending=true
            env.ExecuteInGameThreadWithDelay(16,function()
                scope.restartPending=false
                if settings and context.settings and settings.snapshot()
                    and settings.snapshot().enabled==context.settings.enabled then return end
                manager.open(file,context)
            end)
        end
        function env.NotifyOnNewObject(path, callback)
            local slot = watch(path)
            slot.callback = guard(scope, callback)
            -- Replay wrappers only; consumers defer native reads themselves.
            for _, object in ipairs(slot.recent) do slot.callback(object) end
        end
        function env.RegisterHook(path, before, after)
            local slot = hooks[path]
            if not slot then
                slot = {}
                local function pre(...) if slot.before then return slot.before(...) end end
                local function post(...) if slot.after then return slot.after(...) end end
                if after then slot.pre, slot.post = api.RegisterHook(path, pre, post)
                else slot.pre, slot.post = api.RegisterHook(path, pre) end
                assert(slot.pre, 'Hook registration failed: '..path)
                slot.paired = after ~= nil
                hooks[path] = slot
            end
            assert(slot.paired == (after ~= nil), 'Conflicting hook signature: '..path)
            slot.before, slot.after = guard(scope, before), after and guard(scope, after)
            return slot.pre, slot.post
        end
        function env.UnregisterHook(path, pre, post)
            local slot = hooks[path]
            assert(slot and slot.pre == pre and slot.post == post, 'Unknown hook ownership')
            slot.before, slot.after = nil, nil
        end
        for _, name in ipairs({'RegisterLoadMapPreHook','RegisterLoadMapPostHook'}) do
            env[name] = function(callback)
                if not maps[name] then
                    local slot = {}
                    api[name](function(...) if slot.callback then return slot.callback(...) end end)
                    maps[name] = slot
                end
                maps[name].callback = guard(scope, callback)
            end
        end
        -- Getters/setters must reacquire borrowed fields and retain only owners/scalars.
        -- A false second getter result means the owner/field is no longer applicable.
        function scope.change(key, get, set, value)
            assert(scope.active, 'Inactive session')
            local old, valid = get()
            if valid == false or equal(old, value) then return false end
            local entry = scope.journal[key]
            if entry then
                local _, stillValid = entry.get()
                if stillValid == false then entry = nil end
            end
            if not entry then
                assert(#scope.order < 4096, 'Session change limit reached')
                entry = {get=get, set=set, original=old}
                scope.journal[key] = entry
                scope.order[#scope.order+1] = entry
            elseif not equal(old, entry.last) then entry.original = old end
            entry.last = value
            set(value)
            local actual, stillValid = get()
            assert(stillValid ~= false and equal(actual,value), 'Session write readback failed: '..tostring(key))
            return true
        end
        function scope.onClose(callback) scope.cleanup[#scope.cleanup+1] = callback end
        -- A consumer may release one owned field from its bounded live worker.
        -- Keep the journal entry so repeated toggles do not grow cleanup state.
        function scope.restore(key)
            assert(scope.active, 'Inactive session')
            local entry=scope.journal[key]
            if not entry then return false end
            local value,valid=entry.get()
            if valid==false or not equal(value,entry.last) or equal(value,entry.original) then return false end
            entry.set(entry.original)
            local restored,stillValid=entry.get()
            assert(stillValid==false or equal(restored,entry.original), 'Live restore readback failed: '..key)
            entry.last=entry.original
            return true
        end
        -- UObject methods can disappear while a retained wrapper still says valid.
        -- Keep an owned identity snapshot and check it before dispatching a method.
        -- Use for transient object values; scalar/global journals retain strict cleanup.
        function scope.changeObject(key, owner, getter, setter, value)
            local class = owner:GetClass()
            if not class:IsValid() then return false end
            local classAddress, name = class:GetAddress(), owner:GetFullName()
            local function method(which)
                if not owner:IsValid() then return end
                local currentClass = owner:GetClass()
                if not currentClass:IsValid() or currentClass:GetAddress() ~= classAddress
                    or owner:GetFullName() ~= name then return end
                local fn = owner[which]
                if type(fn) == 'function' then return fn end
                if type(fn) == 'userdata' then
                    -- TrivialObject placeholders need not expose UObject methods.
                    local ok, callable = pcall(function() return fn:type() == 'UFunction' and fn:IsValid() end)
                    if ok and callable then return fn end
                end
            end
            local changed = scope.change(key, function()
                local fn = method(getter)
                if not fn then return nil, false end
                return fn(owner)
            end, function(target)
                local fn = method(setter)
                assert(fn, 'Object setter unavailable: '..setter)
                fn(owner, target)
            end, value)
            local entry = scope.journal[key]
            if entry then entry.objectValue = true end
            return changed
        end
        local ok, err = pcall(env.dofile, file)
        if not ok then
            report('Session initialization failed: '..tostring(err))
            manager.close()
        end
    end
    function manager.close(done)
        if not done then generation = generation + 1 end
        if closing then queued = done or function() end; return end
        if not current then if done then done() end; return end
        local scope = current
        scope.active, current, closing = false, nil, true
        for id in pairs(scope.timers) do
            local ok, err = pcall(api.CancelDelayedAction, id)
            if not ok then report('Timer cancellation failed: '..tostring(err)) end
        end
        scope.timers = {}
        for _, slot in pairs(notifications) do slot.callback = nil end
        for _, slot in pairs(hooks) do slot.before, slot.after = nil, nil end
        for _, slot in pairs(maps) do slot.callback = nil end
        local index, cleanup = #scope.order, #scope.cleanup
        local failed, failedCleanup, firstError = {}, {}, nil
        local skippedObjects = 0
        local function step()
            if canCleanup and not canCleanup() then deferredCleanup = step; return end
            -- Small scalar restores can share a frame. A setter that rebuilds
            -- native state returns true to yield; custom cleanup always yields.
            local started = api.os.clock()
            local budget = 0
            for unit = 1,16 do
            if canCleanup and not canCleanup() then deferredCleanup = step; return end
            if unit > 1 and api.os.clock()-started >= 0.0005 then break end
            local cost = index > 0 and (scope.order[index].objectValue and 8 or 1) or 1
            if budget + cost > 16 then break end
            local entry, callback
            local yieldFrame = false
            local ok, err = pcall(function()
                if index > 0 then
                    entry = scope.order[index]; index = index - 1
                    budget = budget + cost
                    local value, valid = entry.get()
                    if valid ~= false and equal(value,entry.last) then
                        yieldFrame = entry.set(entry.original) == true
                        local restored, stillValid = entry.get()
                        assert(stillValid == false or equal(restored,entry.original), 'Restore readback failed')
                    elseif valid == false and entry.objectValue then
                        skippedObjects = skippedObjects + 1
                    end
                elseif cleanup > 0 then
                    callback = scope.cleanup[cleanup]; cleanup = cleanup - 1
                    callback()
                    yieldFrame = true
                end
            end)
            if not ok then
                firstError = firstError or tostring(err)
                if entry then failed[#failed+1] = entry else failedCleanup[#failedCleanup+1] = callback end
            end
            if not ok or yieldFrame or budget >= 16 or (index == 0 and cleanup == 0) then break end
            end
            if index > 0 or cleanup > 0 then api.ExecuteInGameThreadWithDelay(16, step)
            else
                closing = false
                local nextAction = queued or done; queued = nil
                if skippedObjects > 0 and api.SaveLoadDiagnostics and api.SaveLoadDiagnostics.debugLogging then
                    report('Session cleanup skipped '..skippedObjects..' unavailable or replaced object values')
                end
                if firstError then
                    scope.order, scope.cleanup = failed, failedCleanup
                    current = scope
                    report('Session cleanup failed ('..(#failed+#failedCleanup)..'); new settings withheld: '..firstError)
                elseif nextAction then nextAction() end
            end
        end
        if index > 0 or cleanup > 0 then api.ExecuteInGameThreadWithDelay(16, step)
        else closing = false; if done then done() end end
    end
    function manager.open(file, context)
        generation = generation + 1
        local ticket = generation
        manager.close(function() if ticket == generation then launch(file, context) end end)
    end
    if settings then
        settings.attach(function(values,changes)
            if current and current.active and current.settingsHandler then
                current.settingsHandler(values,changes)
            end
        end)
    end
    return manager
end
return M
