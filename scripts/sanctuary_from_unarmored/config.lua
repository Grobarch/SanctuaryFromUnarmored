-- Shared configuration module.
--
-- Values live in global storage sections so that both player scripts and NPC local scripts
-- can read them (storage.playerSection would not be reachable from an NPC). Writing is done
-- by the settings page; we only read.
--
-- Four groups: balance, armour coverage, update frequency and removal. The "setting key ->
-- storage section" map is DERIVED from the group definitions, so it cannot drift out of sync
-- when a setting is added.

local storage = require('openmw.storage')

local M = {}

M.PAGE = 'SanctuaryFromUnarmoredPage'
M.L10N = 'SanctuaryFromUnarmored'

M.GROUP = 'SettingsSanctuaryFromUnarmored'
M.ARMOUR_GROUP = 'SettingsSanctuaryFromUnarmoredArmour'
M.PERF_GROUP = 'SettingsSanctuaryFromUnarmoredPerformance'
M.REMOVAL_GROUP = 'SettingsSanctuaryFromUnarmoredRemoval'

-- Our own renderers (registered from MENU scripts: slider.lua, button.lua).
M.SLIDER_RENDERER = 'SanctuaryFromUnarmoredSlider'
M.BUTTON_RENDERER = 'SanctuaryFromUnarmoredButton'

-- Section holding the magnitude -> id map of the dynamically created spells.
M.SPELL_SECTION = 'SanctuaryFromUnarmoredSpells'

-- Values tuned in game (2026-07-27) and adopted as the defaults.
M.defaults = {
    -- balance
    maxSanctuary = 40,
    threshold = 20,
    rate = 0.4,
    npcFactor = 100,
    arMultiplier = 1.0,
    dodgeXpScale = 0.5,
    statsWindow = true,
    inventoryBar = true,
    -- armour coverage
    keepLight = 60,
    keepMedium = 40,
    keepHeavy = 20,
    useArmorSkill = true,
    -- update frequency
    refreshInterval = 1.0,
    npcPeriodicRefresh = true,
    npcRefreshInterval = 10.0,
    -- removal
    uninstallMode = false,
}

-- What removal mode forces, whatever the sliders say. Neutralising the settings is what
-- actually takes the ability off: actor.lua computes 0 points and removes it on its next
-- refresh, for the player and for every actor that is (or becomes) active.
--
-- This is deliberately done in config.get, the single place every consumer reads through,
-- rather than by patching each of them - one bypass and an actor would keep its ability.
local REMOVAL_OVERRIDES = {
    maxSanctuary = 0,   -- no bonus at all
    arMultiplier = 1.0, -- armour rating back to vanilla
    dodgeXpScale = 0,   -- stop feeding skill progression
}

local function setting(key, renderer, argument)
    return {
        key = key,
        name = key,
        description = key .. 'Description',
        default = M.defaults[key],
        renderer = renderer,
        argument = argument,
    }
end

local function number(key, argument)
    return setting(key, 'number', argument)
end

local function checkbox(key)
    return setting(key, 'checkbox', nil)
end

local function slider(key, argument)
    return setting(key, M.SLIDER_RENDERER, argument)
end

-- A boolean setting drawn as a button rather than a checkbox: the l10n keys name the label
-- for each state, so one setting covers both "remove" and "undo".
local function button(key, argument)
    return setting(key, M.BUTTON_RENDERER, argument)
end

-- Every setting gets its OWN copy of the argument table - `argument` is stored per setting
-- key, so sharing one table between settings is asking for trouble.
-- `preview` names the preview scenario (the functions live in slider.lua, because a function
-- cannot be written to storage) plus the key to substitute with the value being edited.
local function percent(scenario, key)
    return {
        min = 0, max = 100, step = 5, unit = '%', decimals = 0, width = 170,
        preview = { scenario = scenario, key = key },
    }
end

-- Group definitions. The `order` fields decide the layout of the page.
local GROUPS = {
    {
        key = M.GROUP,
        name = 'settingsGroup',
        order = 0,
        settings = {
            slider('maxSanctuary', { min = 0, max = 100, step = 1, decimals = 0, width = 170,
                preview = { scenario = 'bare', key = 'maxSanctuary' } }),
            slider('threshold', { min = 0, max = 100, step = 1, decimals = 0, width = 170,
                preview = { scenario = 'bare', key = 'threshold' } }),
            slider('rate', { min = 0, max = 2, step = 0.05, decimals = 2, width = 170,
                preview = { scenario = 'bare', key = 'rate' } }),
            slider('npcFactor', percent('npc', 'npcFactor')),
            slider('arMultiplier', { min = 0.5, max = 5, step = 0.05, unit = 'x', decimals = 2, width = 170,
                preview = { scenario = 'armorRating', key = 'arMultiplier' } }),
            slider('dodgeXpScale', { min = 0, max = 2, step = 0.05, decimals = 2, width = 170 }),
            checkbox('statsWindow'),
            checkbox('inventoryBar'),
        },
    },
    {
        key = M.ARMOUR_GROUP,
        name = 'armourGroup',
        order = 1,
        settings = {
            slider('keepLight', percent('light', 'keepLight')),
            slider('keepMedium', percent('medium', 'keepMedium')),
            slider('keepHeavy', percent('heavy', 'keepHeavy')),
            checkbox('useArmorSkill'),
        },
    },
    {
        -- These stay as number fields: a 0.1-300 s range is too wide for a slider, and these
        -- values are set once, where you want to type an exact figure rather than hit a step.
        key = M.PERF_GROUP,
        name = 'perfGroup',
        order = 2,
        settings = {
            number('refreshInterval', { min = 0.1, max = 60 }),
            checkbox('npcPeriodicRefresh'),
            number('npcRefreshInterval', { min = 0.1, max = 300 }),
        },
    },
    {
        key = M.REMOVAL_GROUP,
        name = 'removalGroup',
        order = 3,
        settings = {
            button('uninstallMode', {
                offLabel = 'uninstallModeOff',
                onLabel = 'uninstallModeOn',
                onNote = 'uninstallModeNote',
            }),
        },
    },
}

-- setting key -> storage section name
local groupOf = {}
for _, group in ipairs(GROUPS) do
    for _, entry in ipairs(group.settings) do
        groupOf[entry.key] = group.key
    end
end

-- Lazily, because MENU scripts cannot reach global storage before a game is running.
local cache = {}
local function sectionByName(name)
    if not cache[name] then
        cache[name] = storage.globalSection(name)
    end
    return cache[name]
end

local function rawGet(key)
    local value = sectionByName(groupOf[key] or M.GROUP):get(key)
    if value == nil then
        return M.defaults[key]
    end
    return value
end

--- True while the player has pressed the removal button and not undone it.
function M.isRemovalMode()
    return rawGet('uninstallMode') == true
end

function M.get(key)
    local override = REMOVAL_OVERRIDES[key]
    if override ~= nil and M.isRemovalMode() then
        return override
    end
    return rawGet(key)
end

--- The whole settings set as a plain table - convenient to hand over to formula.lua.
function M.all()
    local result = {}
    for key in pairs(M.defaults) do
        result[key] = M.get(key)
    end
    return result
end

--- All storage sections - used to subscribe to changes.
function M.sections()
    local result = {}
    for _, group in ipairs(GROUPS) do
        result[#result + 1] = sectionByName(group.key)
    end
    return result
end

--- Group definitions ready for I.Settings.registerGroup.
function M.groupOptions()
    local result = {}
    for i, group in ipairs(GROUPS) do
        result[i] = {
            key = group.key,
            page = M.PAGE,
            l10n = M.L10N,
            name = group.name,
            description = group.name .. 'Description',
            permanentStorage = true,
            order = group.order,
            settings = group.settings,
        }
    end
    return result
end

return M
