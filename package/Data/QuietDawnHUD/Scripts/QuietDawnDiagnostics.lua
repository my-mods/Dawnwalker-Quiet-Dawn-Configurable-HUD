-- MIT License. HUD-specific observations stay local; diagnostics are shared.
local cfg=require('MenuSettings')
local Diagnostics=require('UE4SSCommonDiagnostics')
local lastVisible,lastGameTime,lastHealth,lastStamina,gapMax
local function output(message) print("[Quiet Dawn - Configurable HUD][DEBUG] "..message) end
local function summary(s)
    local timings,counts,dropped=s.timings,s.counts,s.dropped
    local parts={string.format("summary interval=%.3fs suppressed=%d sampleGapMaxMs=%.3f",s.interval,dropped,gapMax or 0)}
    for _,name in ipairs({"worker","sample","marker","enemyHealth","directions","hook","clawMarks"}) do
        local t=timings[name]
        if t then parts[#parts+1]=string.format("%s calls=%d avgMs=%.3f maxMs=%.3f slow=%d",name,t.n,t.total/t.n,t.max,t.slow) end
    end
    local keys={};for name in pairs(counts) do keys[#keys+1]=name end;table.sort(keys)
    for _,name in ipairs(keys) do parts[#parts+1]=name.."="..counts[name] end
    if lastHealth then parts[#parts+1]=string.format("health=%.4f stamina=%.4f wanted=%s",lastHealth,lastStamina,tostring(lastVisible)) end
    output(table.concat(parts," | "))
    gapMax=0
end
local D=Diagnostics.new({mutable=true,debugLogging=cfg.debugLogging,prefix='',output=output,
    summarySeconds=math.max(5,math.min(120,cfg.SummarySeconds or 10)),
    slowCallbackMs=math.max(0.1,math.min(1000,cfg.SlowCallbackMs or 2)),
    maxEventsPerSecond=math.floor(math.max(1,math.min(20,cfg.MaxEventsPerSecond or 6))),
    onSummary=summary})
function D.vitals() end
function D.vitals(health,stamina,visible,gameTime,healthUntil,staminaUntil)
    if not D.debugLogging then return end
    if lastGameTime and gameTime>=lastGameTime then
        gapMax=math.max(gapMax or 0,(gameTime-lastGameTime)*1000)
    end
    lastGameTime,lastHealth,lastStamina=gameTime,health,stamina
    if lastVisible~=visible then
        lastVisible=visible
        D.event("vitals","wanted=%s health=%.4f stamina=%.4f gameTime=%.3f healthHold=%.3f staminaHold=%.3f",tostring(visible),health,stamina,gameTime,math.max(0,(healthUntil or 0)-gameTime),math.max(0,(staminaUntil or 0)-gameTime))
    end
end
if D.debugLogging then output(string.format("enabled build=diagnostics-common-1 ini=%s summarySeconds=%.1f slowMs=%.2f eventLimit=%d clock=os.clock; phase timings overlap and are not engine frame times",
    cfg.path or "unavailable",math.max(5,math.min(120,cfg.SummarySeconds or 10)),
    math.max(0.1,math.min(1000,cfg.SlowCallbackMs or 2)),math.floor(math.max(1,math.min(20,cfg.MaxEventsPerSecond or 6)))))
end
return D
