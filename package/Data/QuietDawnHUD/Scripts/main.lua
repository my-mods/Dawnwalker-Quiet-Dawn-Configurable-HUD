-- Prepare the menu file once at startup; gameplay snapshots still wait for a save load.
local directory = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])'))
local function report(message) print('[Save Settings] '..message..'\n') end
-- Discard this snapshot so menu edits are read afresh by the save-load session.
local model=dofile(directory..'SettingsModel.lua')
local live=dofile(directory..'LiveSettings.lua').new(directory,report)
local prepared,prepareError=pcall(model.load)
if prepared then live.seed(prepareError) end
if not prepared then report('Menu settings preparation failed: '..tostring(prepareError)) end
local diagnostics = {debugLogging=prepared and type(prepareError)=='table' and prepareError.debugLogging==1}
local api = setmetatable({SaveLoadDiagnostics=diagnostics}, {__index=_G})
local bridge=dofile(directory..'QuietDawnNative.lua').attach(api,report)
local session = dofile(directory..'UE4SSCommonSession.lua').new(api, directory, report,{settings=live,loadSettings=model.load})
if bridge then
    for _,name in ipairs({'pause','close'}) do
        local original=session[name]
        session[name]=function(...) bridge.stop();return original(...) end
    end
end
session.watch('/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C')
session.watch('/Game/_Dawnwalker/UI/_Unified/HUD/Timer/WBP_HudTimer.WBP_HudTimer_C')
session.watch('/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C')
session.watch('/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatCharacterBar.WBP_CombatCharacterBar_C')
session.watch('/Game/_Dawnwalker/UI/_Unified/Combat/WBP_Combat_BossBar.WBP_Combat_BossBar_C')
local ok, err = pcall(function()
    dofile(directory..'UE4SSDawnwalkerSaveLoad.lua').start(api, session, directory..'Gameplay.lua', report, diagnostics)
end)
if not ok then report('Save-load hooks unavailable: '..tostring(err)) end
