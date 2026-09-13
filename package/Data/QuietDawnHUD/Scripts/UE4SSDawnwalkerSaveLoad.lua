-- MIT. Dawnwalker build 25232147: save requests and player readiness events.
-- Importing this adapter does nothing. Native APIs are injected by start().
local M = {}
function M.start(api, session, file, report, diagnostics, options)
    report = report or function() end
    diagnostics = diagnostics or {}
    local requireLoadComplete = options and options.requireLoadComplete == true
    local enabled, initialized, requested, completed = false, false, false, false
    local loading, window = false, nil
    local engine, gameplay, previousPawn, previousWorld
    local restartController, restartPawn
    local function valid(object) return object and object:IsValid() end
    local function unwrap(value)
        if type(value) == 'number' or type(value) == 'boolean' then return value end
        return value and value:get()
    end
    local function eligible() return not initialized or requested end
    local function trace(message)
        if diagnostics.debugLogging then report('[activation] '..message) end
    end
    local function stop()
        local old = window
        window = nil
        if old and old.handle then api.CancelDelayedAction(old.handle) end
    end
    local function ready(job)
        if requireLoadComplete and (loading or not completed) then return nil, 'waiting for loading completion' end
        -- Cache absence for this finite window too: at most two global lookups.
        if not valid(engine) and not job.engineLookup then
            job.engineLookup = true; engine = api.FindFirstOf('Engine')
        end
        if not valid(gameplay) and not job.gameplayLookup then
            job.gameplayLookup = true; gameplay = api.StaticFindObject('/Script/Engine.Default__GameplayStatics')
        end
        if not valid(engine) or not valid(gameplay) then return nil, 'engine services unavailable' end
        local viewport = engine.GameViewport
        if not valid(viewport) then return nil, 'viewport unavailable' end
        local world = viewport:GetWorld()
        if not valid(world) then return nil, 'world unavailable' end
        local pawn = gameplay:GetPlayerPawn(world, 0)
        if not valid(pawn) or not pawn:IsLocallyControlled() then return nil, 'local player unavailable' end
        local pawnWorld = pawn:GetWorld()
        if not valid(pawnWorld) or pawnWorld:GetAddress() ~= world:GetAddress() then
            return nil, 'player belongs to another world'
        end
        if not valid(pawn.CharDevAttributeSet) then return nil, 'player attributes unavailable' end
        local pawnAddress, worldAddress = pawn:GetAddress(), world:GetAddress()
        local restarted = false
        if valid(restartController) and valid(restartPawn) and restartController:IsLocalController() then
            local ownerWorld, ownerPawn = restartController:GetWorld(), restartController.Pawn
            restarted = valid(ownerWorld) and ownerWorld:GetAddress() == worldAddress
                and valid(ownerPawn) and ownerPawn:GetAddress() == pawnAddress
                and restartPawn:GetAddress() == pawnAddress
        end
        -- A request alone must not snapshot settings against the outgoing pawn.
        -- Same-owner reloads need completion or a matching ClientRestart post-hook.
        if initialized and not completed and not restarted
            and previousPawn == pawnAddress and previousWorld == worldAddress then
            return nil, 'waiting for save completion or a new player'
        end
        return {pawn=pawn, world=world}, nil, pawnAddress, worldAddress
    end
    local function wake(reason)
        if not enabled or not eligible() or window then return end
        -- Attribute-changing consumers must not treat construction as restored
        -- gameplay state. Completion wakes readiness; no timer waits for it.
        if requireLoadComplete and (loading or not completed) then return end
        local job = {attempts=0, source=reason}
        window = job
        local function step()
            job.handle = nil
            if window ~= job or not eligible() then return end
            job.attempts = job.attempts + 1
            if diagnostics.debugLogging and job.attempts == 1 then
                trace('readiness started; source='..job.source..' requested='..tostring(requested)..' loading='..tostring(loading))
            end
            local started = diagnostics.debugLogging and api.os and api.os.clock()
            local ok, context, why, pawnAddress, worldAddress = pcall(ready, job)
            if started then job.ms = (job.ms or 0)+(api.os.clock()-started)*1000 end
            if not ok then why = tostring(context); context = nil end
            if window ~= job then return end -- native calls can dispatch a newer event
            if context then
                window = nil
                initialized, requested, completed = true, false, false
                previousPawn, previousWorld = pawnAddress, worldAddress
                restartController, restartPawn = nil, nil
                session.open(file, context)
                if diagnostics.debugLogging then
                    trace('session requested; source='..job.source..' attempts='..job.attempts
                        ..' lookups='..((job.engineLookup and 1 or 0)+(job.gameplayLookup and 1 or 0))
                        ..' readinessCpuMs='..string.format('%.3f',job.ms or 0))
                end
                return
            end
            -- Forty one-shots over <10 seconds; no idle or settings polling.
            -- A lifecycle event after exhaustion opens a new finite window.
            if job.attempts >= 40 then
                window = nil
                if diagnostics.debugLogging then trace('readiness exhausted; source='..job.source..' attempts=40 readinessCpuMs='..string.format('%.3f',job.ms or 0)..' reason='..why) end
                return
            end
            job.handle = api.ExecuteInGameThreadWithDelay(250, step)
        end
        -- Logging stays in a registered game-thread callback, including construction wakes.
        job.handle = api.ExecuteInGameThreadWithDelay(16, step)
    end
    local function request()
        if not enabled then return end
        stop()
        requested, completed = true, false
        restartController, restartPawn = nil, nil
    end
    local failures = {}
    local function hook(path, pre, post)
        local ok, err = pcall(api.RegisterHook, path, pre, post)
        if not ok then failures[#failures+1] = path..': '..tostring(err) end
    end
    hook('/Script/DogwoodUI.SaveWindowBase:RequestLoadSave', request, function() end)
    for _, path in ipairs({
        '/Script/Persistency.SaveSystemBlueprintFunctionLibrary:LoadLastSave',
        '/Script/Persistency.SaveSystemBlueprintFunctionLibrary:TryQuickload',
    }) do
        -- Native bool result. A refused quickload must not reload settings on travel.
        hook(path, function()
            if enabled then
                stop(); requested, completed = false, false
                restartController, restartPawn = nil, nil
            end
        end, function(_, result)
            if not enabled then return end
            requested = unwrap(result) == true
            if requested then
                if loading then session.pause() end
                wake('accepted save request')
            end
        end)
    end
    hook('/Script/DogwoodCombat.CombatSubsystem:OnLoadingScreenStateChanged',
        function() end, function(_, state)
            if not enabled then return end
            local value = tonumber(unwrap(state))
            if value == 0 then
                loading, completed = false, true
                wake('loading complete') -- Idle can be the first notification.
            elseif value and value >= 1 and value <= 4 then
                loading = true
                if requireLoadComplete then
                    completed = false
                    stop() -- Invalidate even a worker currently inside a native read.
                end
                if requested then session.pause() end
            end
        end)
    hook('/Script/Engine.PlayerController:ClientRestart', function() end, function(context, pawn)
        if not enabled or not eligible() then return end
        -- Unwrap while native parameters are alive; defer UObject property reads.
        restartController, restartPawn = unwrap(context), unwrap(pawn)
        wake('player restart')
    end)
    for _, path in ipairs({'/Script/Dawnwalker.DawnwalkerPlayerCharacter','/Script/DogwoodStats.CharDevAttributeSet'}) do
        local ok, err = pcall(api.NotifyOnNewObject, path, function()
            wake('player construction') -- no native property reads on construction threads
        end)
        if not ok then failures[#failures+1] = path..': '..tostring(err) end
    end
    enabled = true
    if #failures > 0 then report('Some save-load events unavailable: '..table.concat(failures, '; ')) end
end
return M
