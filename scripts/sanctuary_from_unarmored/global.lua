-- Global script: registers the settings groups and produces the spell records.
--
-- Why spells rather than activeEffects:modify() - modify writes a permanent magnitude change
-- into the save and needs its own bookkeeping in onSave/onLoad. That is exactly how the
-- runaway Strength bug in Slay's Assassin Mark happened. Removing an ability takes the effect
-- with it and needs no bookkeeping at all.

local async = require('openmw.async')
local core = require('openmw.core')
local storage = require('openmw.storage')
local types = require('openmw.types')
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

local removalWasOn = false

local function ensureFromConfig()
    ensureSpells(config.get('maxSanctuary'))
    -- Sync the removal flag on start and on load, so that a save made in removal mode does
    -- not look like the button was just pressed.
    removalWasOn = config.isRemovalMode()
end

--- Takes our ability off every actor that is currently active. Returns how many it removed.
--
-- Only a GLOBAL script can do this to somebody else - spells:remove() throws for a local
-- script holding another actor's object (magicbindings.cpp, "Local scripts can modify only
-- spells of the actor they are attached to").
--
-- Active actors are the whole population by design: actor.lua takes the ability off in
-- onInactive, so nobody outside the active grid is carrying one. This sweep only saves the
-- player from waiting out a refresh cycle.
--
-- WARNING: do NOT be tempted to walk world.cells "to be thorough". Reading an actor's spells
-- builds its CustomData, RefData::setCustomData sets mChanged, and writeReferenceCollection
-- skips only unchanged references - so every NPC in the game would be serialised into the
-- save for good. Actors that are already active cost nothing extra; they are instantiated
-- anyway.
local function sweepActiveActors()
    local ids = {}
    for _, id in pairs(spells:asTable()) do
        ids[#ids + 1] = id
    end

    local removed = 0
    for _, actor in ipairs(world.activeActors) do
        local known = types.Actor.spells(actor)
        for _, id in ipairs(ids) do
            if known[id] then
                known:remove(id)
                removed = removed + 1
            end
        end
    end
    return removed
end

-- Raising the cap in the options has to create the missing records; switching removal mode on
-- has to strip what is already applied.
local onSettingChanged = async:callback(function(_, key)
    if key == nil or key == 'maxSanctuary' then
        ensureFromConfig()
    end

    if key ~= nil and key ~= 'uninstallMode' then return end

    local removalIsOn = config.isRemovalMode()
    if removalIsOn and not removalWasOn then
        -- Neutralised settings alone would clear this within a refresh cycle (up to 10 s for
        -- an NPC); the sweep makes it immediate, so the player can leave straight away.
        local removed = sweepActiveActors()
        for _, player in ipairs(world.players) do
            player:sendEvent('SanctuaryFromUnarmored_Removed', { count = removed })
        end
    end
    removalWasOn = removalIsOn
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
