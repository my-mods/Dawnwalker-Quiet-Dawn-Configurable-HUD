-- Quiet Dawn - Configurable HUD
-- Read once at startup. Restart the game after editing.
return {
    enabled = true,
    hideEnemyHealthBars = true,
    hideEnemyNames = true,
    hideEnemyDifficultyIcons = true,
    showCounterattackDirection = false,
    showUnblockableWarning = false,
    showDirectionalParry = false,
    showLockIcon = false,
    combatCueSize = 100,
    -- Both stat panels show together when either resource needs attention.
    healthThreshold = 0.50, -- strictly below 50 percent; vampire form uses blood
    staminaThreshold = 0.20,
    healthHoldSeconds = 4.0,
    staminaHoldSeconds = 1.5,
    -- Hold the game's Controls Legend button (Menu/Options on controller).
    manualPeek = true,
    manualPeekSeconds = 3.0,
    -- Other listed panels stay hidden, including during combat and focus.
    -- Enemy health bars are hidden separately; directional cues respect the menu setting.
    panels = {"HumanStats", "VampireStats", "WBP_Compass", "WBP_HUD_QuestInfo",
        "WBP_HUD_Quickslots", "Crosshair", "WBP_AA_Quickslots", "WBP_OpenFocusPrompt",
        "WBP_HUD_Quickslots_ChangePrompt", "WBP_ControlsLegend", "WBP_BuffContainer",
        "WBP_HUD_AbilityCooldownsContainer", "CombatFocusPanel", "WBP_HUD_FocusCharge_Bar",
        "WBP_HUD_SpecialAttackCooldown", "XPBar", "WBP_HudTimer"},
}
