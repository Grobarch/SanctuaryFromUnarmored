-- Local script on every actor: computes the bonus and maintains the applied ability.
--
-- Recalculation is event driven (entering the active zone, loading, a slow throttle) and
-- never per frame - onUpdate only compares timestamps.

local async = require('openmw.async')
local core = require('openmw.core')
local self = require('openmw.self')
local storage = require('openmw.storage')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local config = require('scripts.sanctuary_from_unarmored.config')
local formula = require('scripts.sanctuary_from_unarmored.formula')

local Actor = types.Actor
local Armor = types.Armor
local Player = types.Player

-- Maps formula.lua slot keys onto engine slots. It lives HERE rather than in formula.lua,
-- because that module is deliberately free of openmw.types (see its header).
local SLOT_OF = {
    cuirass = Actor.EQUIPMENT_SLOT.Cuirass,
    shield = Actor.EQUIPMENT_SLOT.CarriedLeft,
    helmet = Actor.EQUIPMENT_SLOT.Helmet,
    greaves = Actor.EQUIPMENT_SLOT.Greaves,
    boots = Actor.EQUIPMENT_SLOT.Boots,
    leftPauldron = Actor.EQUIPMENT_SLOT.LeftPauldron,
    rightPauldron = Actor.EQUIPMENT_SLOT.RightPauldron,
    leftGauntlet = Actor.EQUIPMENT_SLOT.LeftGauntlet,
    rightGauntlet = Actor.EQUIPMENT_SLOT.RightGauntlet,
}

--- Engine equipment -> the slot-key map that formula.lua expects.
local function bySlotKey(equipment)
    local result = {}
    for key, slot in pairs(SLOT_OF) do
        result[key] = equipment[slot]
    end
    return result
end

local isPlayer = Player.objectIsInstance(self)

local spellIds = storage.globalSection(config.SPELL_SECTION)

local applied = 0
local appliedSpellId = nil
local lastResult = nil
local lastSignature = nil
-- WARNING: REAL time stamps, not dt accumulators. Equipment changes while the inventory
-- window is open, and that window PAUSES the game - onUpdate then gets dt = 0, so a counter
-- based on dt would stall at exactly the moment it is needed.
local lastRefresh = 0
local lastEquipCheck = 0

-- The intervals are configurable, but we do NOT read them from storage every frame - that
-- would cost more than the work they are limiting. They are cached and refreshed on every
-- full recalculation (and, for the player, immediately after a setting changes).
--
-- refreshInterval    - full recalculation; catches SKILL changes (training, fortify, drain).
-- equipCheckInterval - EQUIPMENT check; the engine has no handler for equipping or removing
--   an item (EngineHandlerList in localscripts.hpp is onActive/onInactive/onConsume/
--   onActivated/onTeleported), so polling is the only option. It is cheap: one getEquipment
--   and nine ids joined into a signature; a full recalculation only fires when it changes.
--
-- nil refreshInterval = no periodic checking at all (an NPC with npcPeriodicRefresh off)
-- -> only onInit and onActive remain.
local refreshInterval = nil
local equipCheckInterval = nil

-- How much more often than a full recalculation the cheap equipment check runs. This is NOT
-- a setting: separating the two intervals only pays off with a long `refreshInterval`, and at
-- the default one second it would buy 0.8 s of responsiveness at the price of two more
-- sliders and of having to understand the difference between two kinds of refresh.
local EQUIP_CHECK_DIVISOR = 5

local function reloadIntervals(cfg)
    if isPlayer then
        refreshInterval = cfg.refreshInterval
    elseif cfg.npcPeriodicRefresh then
        refreshInterval = cfg.npcRefreshInterval
    else
        refreshInterval = nil
    end
    equipCheckInterval = refreshInterval and (refreshInterval / EQUIP_CHECK_DIVISOR) or nil
end

reloadIntervals(config.all())

local function getSkill(skillId)
    return types.NPC.stats.skills[skillId](self).modified
end

local function isArmor(item)
    return Armor.objectIsInstance(item)
end

local function armorSkillOf(item)
    return I.Combat.getArmorSkill(item)
end

--- A light signature of the nine armour slots, used only to detect a change.
local function equipmentSignature(equipment)
    local parts = {}
    for i, entry in ipairs(formula.SLOT_WEIGHTS) do
        local item = equipment[SLOT_OF[entry.key]]
        parts[i] = item and item.id or '-'
    end
    return table.concat(parts, '|')
end

local function compute(cfg, equipment)
    return formula.compute({
        cfg = cfg,
        isPlayer = isPlayer,
        equipment = bySlotKey(equipment),
        isArmor = isArmor,
        armorSkillOf = armorSkillOf,
        skillOf = getSkill,
        unarmoredBase1 = core.getGMST('fUnarmoredBase1'),
        unarmoredBase2 = core.getGMST('fUnarmoredBase2'),
    })
end

local function removeSpell(id)
    if not id then return end
    pcall(function()
        Actor.spells(self):remove(id)
    end)
end

local function applySanctuary(magnitude)
    if magnitude == applied then return end

    local newId = nil
    if magnitude > 0 then
        newId = spellIds:get(tostring(magnitude))
        if not newId then
            -- The record does not exist yet (e.g. the cap was raised in this very frame).
            -- Request it and try again on the next refresh.
            core.sendGlobalEvent('SanctuaryFromUnarmored_EnsureSpells', { upTo = magnitude })
            return
        end
    end

    removeSpell(appliedSpellId)
    if newId then
        Actor.spells(self):add(newId)
    end

    applied = magnitude
    appliedSpellId = newId
end

--- Takes off any ability of OURS that we do not believe is currently applied.
--
-- Self-healing, and the reason a stale bonus cannot outlive a visit: only a script that knows
-- the record id can remove an ability, so anything left behind by an earlier session (a crash,
-- or a version whose bookkeeping did not survive) would otherwise sit on the actor for good.
-- Runs on activation only, i.e. once per actor per visit.
local function purgeStrays()
    local ours = {}
    for _, id in pairs(spellIds:asTable()) do
        ours[id] = true
    end

    local doomed
    for _, spell in pairs(Actor.spells(self)) do
        if ours[spell.id] and spell.id ~= appliedSpellId then
            doomed = doomed or {}
            doomed[#doomed + 1] = spell.id
        end
    end
    if not doomed then return end

    -- Collected first: removing while iterating the actor's own spell list is asking for it.
    for _, id in ipairs(doomed) do
        removeSpell(id)
    end
end

-- `equipment` may be passed in when the caller already fetched it (the equipment check),
-- which avoids a second trip into C++ within the same frame.
local function refresh(equipment)
    local cfg = config.all()
    equipment = equipment or Actor.getEquipment(self)

    reloadIntervals(cfg)
    local now = core.getRealTime()
    lastRefresh = now
    lastEquipCheck = now
    lastSignature = equipmentSignature(equipment)
    lastResult = compute(cfg, equipment)
    applySanctuary(lastResult.sanctuary)
end

if isPlayer then
    -- Changing a setting must take effect without a restart. NPCs pick it up at their next
    -- recalculation (reloadIntervals inside refresh), or at onActive if periodic checking
    -- is disabled for them.
    local onSettingChanged = async:callback(function() refresh() end)
    for _, section in ipairs(config.sections()) do
        section:subscribe(onSettingChanged)
    end
end

return {
    interfaceName = 'SanctuaryFromUnarmored',
    interface = {
        version = 1,

        --- The Sanctuary bonus currently applied, in points.
        getBonus = function()
            return applied
        end,

        --- Per-slot breakdown of the contributions - the data source for the UI readouts.
        getBreakdown = function()
            return lastResult and lastResult.breakdown or {}
        end,

        --- The armour rating component coming from empty slots (used by armor.lua).
        getArmorComponent = function()
            return lastResult and lastResult.armorComponent or 0
        end,

        --- Forces a recalculation.
        refresh = function() refresh() end,
    },
    engineHandlers = {
        -- Wrapped, because the engine passes initData to onInit - without this it would
        -- land in the `equipment` parameter.
        onInit = function() purgeStrays() refresh() end,
        onActive = function() purgeStrays() refresh() end,
        -- The bonus is taken off on the way out, and that is what keeps it from spreading
        -- across the world: at any moment it exists only on actors inside the active grid.
        -- Nothing is lost by it - Sanctuary is read by the engine's hit chance calculation,
        -- and an inactive actor is not fighting anybody.
        --
        -- It also bounds what an uninstall can leave behind to exactly the set the removal
        -- button reaches (world.activeActors), instead of every NPC ever met.
        onInactive = function() applySanctuary(0) end,
        onUpdate = function()
            -- No interval = periodic checking disabled (an NPC without npcPeriodicRefresh).
            -- Only onInit and onActive remain; zero work per frame.
            if not refreshInterval then return end

            local now = core.getRealTime()

            if now - lastRefresh >= refreshInterval then
                refresh()
                return
            end

            if not equipCheckInterval or equipCheckInterval <= 0 then return end
            if now - lastEquipCheck < equipCheckInterval then return end
            lastEquipCheck = now

            local equipment = Actor.getEquipment(self)
            if equipmentSignature(equipment) ~= lastSignature then
                refresh(equipment)
            end
        end,
        onSave = function()
            return { applied = applied, spellId = appliedSpellId }
        end,
        onLoad = function(saved)
            if not saved then return end
            -- The ability survived in the save along with the actor's spell list, so we have
            -- to restore our knowledge of what is applied - otherwise we would add a second.
            applied = saved.applied or 0
            appliedSpellId = saved.spellId
        end,
    },
}
