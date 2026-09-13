-- MIT. Persistent menu subscription; no work is performed when this module loads.
local M={}
function M.new(directory, report)
    local Adapter=dofile(directory..'UE4SSDawnwalkerSettings.lua')
    local schema=dofile(directory..'SettingsSchema.lua')
    local live=Adapter.new({modId="oOCamilleOo_QuietDawnHUD",schema=schema,report=report,
        ids={
        ["enabled"]="enabled",
        ["opacity_WBP_BuffContainer"]="opacity_WBP_BuffContainer",
        ["scale_WBP_BuffContainer"]="scale_WBP_BuffContainer",
        ["opacity_XPBar"]="opacity_XPBar",
        ["scale_XPBar"]="scale_XPBar",
        ["opacity_HumanStats"]="opacity_HumanStats",
        ["scale_HumanStats"]="scale_HumanStats",
        ["opacity_VampireStats"]="opacity_VampireStats",
        ["scale_VampireStats"]="scale_VampireStats",
        ["healthThreshold"]="healthThreshold",
        ["healthHoldSeconds"]="healthHoldSeconds",
        ["staminaThreshold"]="staminaThreshold",
        ["staminaHoldSeconds"]="staminaHoldSeconds",
        ["opacity_WBP_HUD_AbilityCooldownsContainer"]="opacity_WBP_HUD_AbilityCooldownsContainer",
        ["scale_WBP_HUD_AbilityCooldownsContainer"]="scale_WBP_HUD_AbilityCooldownsContainer",
        ["opacity_Crosshair"]="opacity_Crosshair",
        ["scale_Crosshair"]="scale_Crosshair",
        ["hideEnemyHealthBars"]="hideEnemyHealthBars",
        ["hideEnemyNames"]="hideEnemyNames",
        ["hideEnemyDifficultyIcons"]="hideEnemyDifficultyIcons",
        ["hideClawSlashMarks"]="hideClawSlashMarks",
        ["opacity_WBP_OpenFocusPrompt"]="opacity_WBP_OpenFocusPrompt",
        ["scale_WBP_OpenFocusPrompt"]="scale_WBP_OpenFocusPrompt",
        ["opacity_WBP_HUD_FocusCharge_Bar"]="opacity_WBP_HUD_FocusCharge_Bar",
        ["scale_WBP_HUD_FocusCharge_Bar"]="scale_WBP_HUD_FocusCharge_Bar",
        ["opacity_CombatFocusPanel"]="opacity_CombatFocusPanel",
        ["scale_CombatFocusPanel"]="scale_CombatFocusPanel",
        ["showCounterattackDirection"]="showCounterattackDirection",
        ["showUnblockableWarning"]="showUnblockableWarning",
        ["showDirectionalParry"]="showDirectionalParry",
        ["showLockIcon"]="showLockIcon",
        ["combatCueSize"]="combatCueSize",
        ["opacity_WBP_HUD_Quickslots"]="opacity_WBP_HUD_Quickslots",
        ["scale_WBP_HUD_Quickslots"]="scale_WBP_HUD_Quickslots",
        ["opacity_WBP_AA_Quickslots"]="opacity_WBP_AA_Quickslots",
        ["scale_WBP_AA_Quickslots"]="scale_WBP_AA_Quickslots",
        ["opacity_WBP_HUD_Quickslots_ChangePrompt"]="opacity_WBP_HUD_Quickslots_ChangePrompt",
        ["scale_WBP_HUD_Quickslots_ChangePrompt"]="scale_WBP_HUD_Quickslots_ChangePrompt",
        ["switchRevealSeconds"]="switchRevealSeconds",
        ["opacity_WBP_HUD_SpecialAttackCooldown"]="opacity_WBP_HUD_SpecialAttackCooldown",
        ["scale_WBP_HUD_SpecialAttackCooldown"]="scale_WBP_HUD_SpecialAttackCooldown",
        ["compassOpacity"]="compassOpacity",
        ["scale_WBP_Compass"]="scale_WBP_Compass",
        ["opacity_WBP_HUD_QuestInfo"]="opacity_WBP_HUD_QuestInfo",
        ["scale_WBP_HUD_QuestInfo"]="scale_WBP_HUD_QuestInfo",
        ["opacity_WBP_HudTimer"]="opacity_WBP_HudTimer",
        ["scale_WBP_HudTimer"]="scale_WBP_HudTimer",
        ["timeHoldSeconds"]="timeHoldSeconds",
        ["hideSprintPrompt"]="hideSprintPrompt",
        ["opacity_WBP_ControlsLegend"]="opacity_WBP_ControlsLegend",
        ["scale_WBP_ControlsLegend"]="scale_WBP_ControlsLegend",
        ["manualPeek"]="manualPeek",
        ["manualPeekSeconds"]="manualPeekSeconds",
        ["debugLogging"]="debugLogging"
        }})
    live.start(function(id,callback)
        return dofile(directory..'dmm_api.lua').subscribe(id,callback)
    end)
    return live
end
return M
