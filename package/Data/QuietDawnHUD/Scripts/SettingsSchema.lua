-- Settings contract shared by the loader and Mod Setting Menu. MIT License.
local function choices(maximum, step)
    local values = {}
    for value=0,maximum,step do values[#values+1]=value end
    return values
end
local durations = choices(10, 0.5)
local opacities = choices(100, 5)
local cueSizes = {}
for value=10,200,10 do cueSizes[#cueSizes+1]=value end
return {
    {key="hideSprintPrompt", default=1, values={0,1}},
    {key="enabled", default=1, values={0,1}},
    {key="hideEnemyHealthBars", default=1, values={0,1}},
    {key="hideEnemyNames", default=1, values={0,1}},
    {key="hideEnemyDifficultyIcons", default=1, values={0,1}},
    {key="showCounterattackDirection", default=0, values={0,1}},
    {key="showUnblockableWarning", default=0, values={0,1}},
    {key="showDirectionalParry", default=0, values={0,1}},
    {key="showLockIcon", default=0, values={0,1}},
    {key="combatCueSize", default=100, values=cueSizes},
    {key="healthThreshold", default=50, min=0, max=100, integer=false},
    {key="staminaThreshold", default=20, min=0, max=100, integer=false},
    {key="healthHoldSeconds", default=4, values=durations},
    {key="staminaHoldSeconds", default=1.5, values=durations},
    {key="manualPeekSeconds", default=3, values=durations},
    {key="switchRevealSeconds", default=3, values=durations},
    {key="manualPeek", default=1, values={0,1}},
    {key="compassOpacity", default=0, min=0, max=100, integer=false},
    {key="debugLogging", default=0, values={0,1}},
    {key="SummarySeconds", default=10, min=5, max=120, integer=false},
    {key="SlowCallbackMs", default=2, min=0.1, max=1000, integer=false},
    {key="MaxEventsPerSecond", default=6, min=1, max=20, integer=false},
    {key="opacity_HumanStats", default=0, values=opacities},
    {key="opacity_VampireStats", default=0, values=opacities},
    {key="opacity_WBP_HUD_QuestInfo", default=0, values=opacities},
    {key="opacity_WBP_HUD_Quickslots", default=0, values=opacities},
    {key="opacity_Crosshair", default=0, values=opacities},
    {key="opacity_WBP_AA_Quickslots", default=0, values=opacities},
    {key="opacity_WBP_OpenFocusPrompt", default=0, values=opacities},
    {key="opacity_WBP_HUD_Quickslots_ChangePrompt", default=0, values=opacities},
    {key="opacity_WBP_ControlsLegend", default=0, values=opacities},
    {key="opacity_WBP_BuffContainer", default=0, values=opacities},
    {key="opacity_WBP_HUD_AbilityCooldownsContainer", default=0, values=opacities},
    {key="opacity_CombatFocusPanel", default=0, values=opacities},
    {key="opacity_WBP_HUD_FocusCharge_Bar", default=0, values=opacities},
    {key="opacity_WBP_HUD_SpecialAttackCooldown", default=0, values=opacities},
    {key="timeHoldSeconds", default=4, values=durations},
    {key="opacity_WBP_HudTimer", default=0, values=opacities},
    {key="opacity_XPBar", default=0, values=opacities},
}
