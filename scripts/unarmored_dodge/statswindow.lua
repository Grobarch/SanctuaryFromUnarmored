-- Optional Stats Window Extender integration.
--
-- Soft dependency: without SWE this file does nothing and logs no error.
-- Registration happens from onActive rather than from the file body, because the script load
-- order relative to SWE is not guaranteed - by onActive all interfaces already exist.

local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')

local SLOT_LABELS = {
    cuirass = 'Cuirass',
    shield = 'Shield',
    helmet = 'Helmet',
    greaves = 'Greaves',
    boots = 'Boots',
    leftPauldron = 'Left pauldron',
    rightPauldron = 'Right pauldron',
    leftGauntlet = 'Left gauntlet',
    rightGauntlet = 'Right gauntlet',
}

local SKILL_LABELS = {
    unarmored = 'unarmored',
    lightarmor = 'light',
    mediumarmor = 'medium',
    heavyarmor = 'heavy',
}

local LINE_ID = 'unarmoredDodge'

local registered = false

local function buildTooltipText()
    local bonus = I.UnarmoredDodge and I.UnarmoredDodge.getBonus() or 0
    local breakdown = I.UnarmoredDodge and I.UnarmoredDodge.getBreakdown() or {}

    local lines = {
        ('Sanctuary from Unarmored: %d point(s).'):format(bonus),
        'Each point lowers an attacker\'s chance to hit by one percentage point.',
        '',
        'Contribution per slot:',
    }

    for _, entry in ipairs(breakdown) do
        local slotLabel = SLOT_LABELS[entry.key] or '?'

        if entry.skill == 'unarmored' then
            lines[#lines + 1] = ('  %s - bare  ->  %.1f'):format(slotLabel, entry.contribution)
        else
            -- Armoured slot: show the armour class and the proficiency that scaled the result.
            lines[#lines + 1] = ('  %s - %s %d (%d%% proficiency)  ->  %.1f'):format(
                slotLabel,
                SKILL_LABELS[entry.skill] or entry.skill,
                math.floor((entry.armorSkillValue or 0) + 0.5),
                math.floor(entry.proficiency * 100 + 0.5),
                entry.contribution)
        end
    end

    return table.concat(lines, '\n')
end

local function register()
    if registered then return end
    if not I.StatsWindow then return end
    if not I.UnarmoredDodge then return end

    local C = I.StatsWindow.Constants

    I.StatsWindow.addLineToSection(LINE_ID, C.DefaultSections.HEALTH_STATS, {
        label = 'Dodge',
        labelColor = C.Colors.DEFAULT_LIGHT,
        visibleFn = function()
            return config.get('statsWindow')
        end,
        value = function()
            return { string = tostring(I.UnarmoredDodge.getBonus()) }
        end,
        tooltip = function()
            return I.StatsWindow.TooltipBuilders.TEXT({ text = buildTooltipText(), width = 340 })
        end,
    })

    registered = true
end

return {
    engineHandlers = {
        onActive = register,
    },
}
