-- Global script: registers the settings groups and produces the spell records.
--
-- Why spells rather than activeEffects:modify() - modify writes a permanent magnitude change
-- into the save and needs its own bookkeeping in onSave/onLoad. That is exactly how the
-- runaway Strength bug in Slay's Assassin Mark happened. Removing an ability takes the effect
-- with it and needs no bookkeeping at all.

local async = require('openmw.async')
local core = require('openmw.core')
local storage = require('openmw.storage')
local world = require('openmw.world')
local I = require('openmw.interfaces')

local config = require('scripts.sanctuary_from_unarmored.config')

for _, group in ipairs(config.groupOptions()) do
    I.Settings.registerGroup(group)
end

local spells = storage.globalSection(config.SPELL_SECTION)

local function spellExists(id)
    return id ~= nil and core.magic.spells.records[id] ~= nil
end

--- Creates the missing records for magnitudes 1..cap. Called rarely (game start, cap change).
local function ensureSpells(cap)
    cap = math.floor(cap or 0)
    if cap < 1 then return end
    if cap > 100 then cap = 100 end

    for magnitude = 1, cap do
        local key = tostring(magnitude)
        if not spellExists(spells:get(key)) then
            local draft = core.magic.spells.createRecordDraft({
                -- Short on purpose: this is what shows in the magic window and in the active
                -- effects tooltip, next to a stats line already labelled "Dodge".
                name = 'Dodge',
                type = core.magic.SPELL_TYPE.Ability,
                cost = 0,
                isAutocalc = false,
                effects = {
                    {
                        id = core.magic.EFFECT_TYPE.Sanctuary,
                        range = core.magic.RANGE.Self,
                        area = 0,
                        duration = 0,
                        magnitudeMin = magnitude,
                        magnitudeMax = magnitude,
                    },
                },
            })
            local record = world.createRecord(draft)
            spells:set(key, record.id)
        end
    end
end

local function ensureFromConfig()
    ensureSpells(config.get('maxSanctuary'))
end

-- Raising the cap in the options has to create the missing records.
local onSettingChanged = async:callback(function(_, key)
    if key == nil or key == 'maxSanctuary' then
        ensureFromConfig()
    end
end)
for _, section in ipairs(config.sections()) do
    section:subscribe(onSettingChanged)
end

return {
    engineHandlers = {
        onInit = ensureFromConfig,
        -- Also fires when a save is loaded, which covers the cap being raised in another
        -- session or the storage section having been cleared.
        onPlayerAdded = ensureFromConfig,
    },
    eventHandlers = {
        -- Fallback request from a local script in case a record is missing.
        SanctuaryFromUnarmored_EnsureSpells = function(data)
            ensureSpells(data and data.upTo or config.get('maxSanctuary'))
        end,
    },
}
