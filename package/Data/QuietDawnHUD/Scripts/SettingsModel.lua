-- Shared startup snapshot for gameplay and diagnostics. MIT.
local directory = assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
local Store = dofile(directory .. 'SettingsStore.lua')
local schema = dofile(directory .. 'SettingsSchema.lua')
local Timers = dofile(directory .. 'QuietDawnTimers.lua')
local compatibleSchema = Timers.compatibleSchema(schema)
local panels = {"HumanStats","VampireStats","WBP_Compass","WBP_HUD_QuestInfo","WBP_HUD_Quickslots","Crosshair","WBP_AA_Quickslots","WBP_OpenFocusPrompt","WBP_HUD_Quickslots_ChangePrompt","WBP_ControlsLegend","WBP_BuffContainer","WBP_HUD_AbilityCooldownsContainer","CombatFocusPanel","WBP_HUD_FocusCharge_Bar","WBP_HUD_SpecialAttackCooldown","XPBar","WBP_HudTimer"}
local M={}
function M.load()
local values, err = Store.load(directory, compatibleSchema, function()
    local legacyPath = directory .. 'QuietDawnConfig.lua'
    local legacy, le, lc = Store.read(legacyPath)
    local sources = legacy and {{path=legacyPath, text=legacy}} or {}
    if not legacy and lc ~= 2 then return nil, le end
    local ok, cfg
    if legacy then
        local chunk, ce = load(legacy, '@' .. directory .. 'QuietDawnConfig.lua', 't', {})
        if not chunk then return nil, ce end
        ok, cfg = pcall(chunk)
    else
        ok, cfg = pcall(dofile, directory .. 'QuietDawnDefaults.lua')
    end
    if not ok or type(cfg) ~= 'table' or type(cfg.panels) ~= 'table' then return nil, 'Invalid legacy QuietDawnConfig.lua' end
    local result = {}
    for _, key in ipairs({'enabled','healthThreshold','staminaThreshold','healthHoldSeconds','staminaHoldSeconds','manualPeek','manualPeekSeconds','compassOpacity'}) do
        local v = cfg[key]; if type(v)=='boolean' then v=v and 1 or 0 end; result[key]=v
    end
    -- Published Lua configs list hidden panels and use fractional resource values.
    for _, key in ipairs({'healthThreshold','staminaThreshold','compassOpacity'}) do
        if result[key]~=nil then result[key]=result[key]*100 end
    end
    local known = {};for _, p in ipairs(panels) do known[p]=true;if p~='WBP_Compass' then result['opacity_'..p]=100 end end
    local seen = {}
    for _, p in ipairs(cfg.panels) do
        if not known[p] or seen[p] then return nil, 'Unknown or duplicate legacy panel' end
        seen[p]=true;if p~='WBP_Compass' then result['opacity_'..p]=0 end
    end
    -- The time panel was not configurable in published Lua files.
    result.opacity_WBP_HudTimer=0
    local base=os.getenv('LOCALAPPDATA')
    if not base then return nil, 'LOCALAPPDATA unavailable for legacy migration' end
    local diagnosticsPath=base..'/Dawnwalker/Saved/Config/QuietDawnHUD.ini'
    local text, e, code=Store.read(diagnosticsPath)
    if text then sources[#sources+1]={path=diagnosticsPath, text=text} end
    if not text and code~=2 then return nil,e end
    local section, canonical, legacy='',nil,nil
    for line in (text or ''):gmatch('[^\r\n]+') do
        line=line:gsub('^\239\187\191',''):gsub('[;#].*$',''):match('^%s*(.-)%s*$')
        local header=line:match('^%[([^%]]+)%]$');if header then section=header:lower() end
        local key,value=line:match('^([%w_]+)%s*=%s*(.-)%s*$')
        if key and section=='debug' then
            key=key:lower();value=value:lower()
            local b=({['true']=1,['false']=0,['1']=1,['0']=0,on=1,off=0,yes=1,no=0})[value]
            if key=='debuglogging' or key=='enabled' then
                if b==nil then return nil,'Invalid legacy debug toggle' end
                if key=='debuglogging' then canonical=b else legacy=b end
            else
                local name=({summaryseconds='SummarySeconds',slowcallbackms='SlowCallbackMs',maxeventspersecond='MaxEventsPerSecond'})[key]
                if name then result[name]=tonumber(value);if not result[name] then return nil,'Invalid legacy diagnostics value' end end
            end
        end
    end
    result.debugLogging=canonical or legacy or 0
    Timers.normalize(result)
    return result, nil, sources
end)
if not values and err and err:match('^Missing setting:') then
    local defaults={hideClawSlashMarks=1,hideEnemyHealthBars=1,showUnblockableWarning=0,showDirectionalParry=0,showLockIcon=0,combatCueSize=100,showCounterattackDirection=0,hideSprintPrompt=1,hideEnemyNames=1, hideEnemyDifficultyIcons=1, opacity_WBP_HudTimer=0, timeHoldSeconds=4, switchRevealSeconds=3}
    for _, p in ipairs(panels) do defaults['scale_'..p]=100 end
    local path=Store.path(directory)
    local text=Store.read(path)
    -- New keys avoid interpreting an old On=1 switch as 1% opacity. Require
    -- all old panel switches before deriving preferences; malformed input is
    -- rejected without replacing the original file.
    local legacySchema={}
    for _, row in ipairs(compatibleSchema) do
        if not row.key:match('^scale_') and not row.key:match('^opacity_') and row.key~='timeHoldSeconds' and row.key~='switchRevealSeconds' and row.key~='hideSprintPrompt'
            and row.key~='showCounterattackDirection' and row.key~='showUnblockableWarning'
            and row.key~='showDirectionalParry' and row.key~='showLockIcon' and row.key~='combatCueSize'
            and row.key~='hideClawSlashMarks' and not row.key:match('^hideEnemy') then legacySchema[#legacySchema+1]=row end
    end
    for _, p in ipairs(panels) do
        if p~='WBP_Compass' and p~='WBP_HudTimer' then legacySchema[#legacySchema+1]={key='panel_'..p,values={0,1}} end
    end
    local legacy=text and Store.parse(text,legacySchema)
    if legacy then
        for _, p in ipairs(panels) do
            if p~='WBP_Compass' and p~='WBP_HudTimer' then defaults['opacity_'..p]=legacy['panel_'..p]*100 end
        end
    end
    values, err = dofile(directory..'UE4SSCommonSettingsUpgrade.lua').ensure(
        Store, path, compatibleSchema, defaults, 'claw-slash-marks')
end
if values then
    local needsUpgrade=false
    for _, key in ipairs({'healthHoldSeconds','staminaHoldSeconds','manualPeekSeconds','timeHoldSeconds','switchRevealSeconds'}) do
        if values[key]>10 or values[key]*2%1~=0 then needsUpgrade=true;break end
    end
    if needsUpgrade then values,err=Timers.ensure(Store,Store.path(directory),schema) end
end
if not values then error('Quiet Dawn settings rejected: '..tostring(err)) end
return values

end
function M.convert(numeric)
local values={}
for key,value in pairs(numeric) do values[key]=value end
values.enabled=values.enabled==1;values.manualPeek=values.manualPeek==1;values.debugLogging=values.debugLogging==1
values.hideEnemyHealthBars=values.hideEnemyHealthBars==1
values.hideClawSlashMarks=values.hideClawSlashMarks==1
values.hideEnemyNames=values.hideEnemyNames==1
values.hideEnemyDifficultyIcons=values.hideEnemyDifficultyIcons==1
values.showCounterattackDirection=values.showCounterattackDirection==1
values.showUnblockableWarning=values.showUnblockableWarning==1
values.showDirectionalParry=values.showDirectionalParry==1
values.showLockIcon=values.showLockIcon==1
values.hideSprintPrompt=values.hideSprintPrompt==1
-- Menu percentages become fractions only at the gameplay boundary.
for _, key in ipairs({'healthThreshold','staminaThreshold','compassOpacity'}) do values[key]=values[key]/100 end
-- All named panels have opacity controls. Zero preserves Quiet Dawn
-- management; positive values keep a fixed opacity. The game's form/preset visibility restrictions remain intact.
values.panels=panels
values.panelOpacities={}
values.panelScales={}
for _, p in ipairs(panels) do
    values.panelScales[p]=values['scale_'..p]/100
    values.panelOpacities[p]=p=='WBP_Compass' and values.compassOpacity or values['opacity_'..p]/100
end
values.dynamicPanels={HumanStats=values.opacity_HumanStats==0,VampireStats=values.opacity_VampireStats==0}
values.path=Store.path(directory)
return values

end
return M
