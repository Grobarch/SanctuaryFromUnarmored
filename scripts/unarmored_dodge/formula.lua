-- Pure calculation module: takes a description of an actor, returns numbers.
--
-- WARNING: ZERO dependencies on engine packages, deliberately. MENU scripts only get
-- openmw.core/ambient/ui/menu/input (luabindings.cpp, initMenuPackages), so if this file
-- required openmw.types it could not be loaded by the settings page renderer and the
-- interactive previews would be impossible. Slots are therefore identified by our own string
-- keys, and the mapping onto Actor.EQUIPMENT_SLOT lives in actor.lua, which does have types.
--
-- Side benefit: the module can be run outside the game (see tests/).

local M = {}

-- Slot weights copied from the engine (vfs-mw/scripts/omw/combat/local.lua, getArmorRating).
-- They add up to 1.0, so a fully bare actor gets exactly dodgeFromSkill(unarmored).
M.SLOT_WEIGHTS = {
    { key = 'cuirass',       weight = 0.30 },
    { key = 'shield',        weight = 0.10 },
    { key = 'helmet',        weight = 0.10 },
    { key = 'greaves',       weight = 0.10 },
    { key = 'boots',         weight = 0.10 },
    { key = 'leftPauldron',  weight = 0.10 },
    { key = 'rightPauldron', weight = 0.10 },
    { key = 'leftGauntlet',  weight = 0.05 },
    { key = 'rightGauntlet', weight = 0.05 },
}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

--- How many dodge points a given skill level is worth.
function M.dodgeFromSkill(skillValue, cfg)
    return math.max(0, (skillValue - cfg.threshold) * cfg.rate)
end

--- What share of the bonus survives wearing armour of the given class (0..1).
function M.keepFactor(skillId, cfg)
    if skillId == 'lightarmor' then
        return cfg.keepLight / 100
    elseif skillId == 'mediumarmor' then
        return cfg.keepMedium / 100
    elseif skillId == 'heavyarmor' then
        return cfg.keepHeavy / 100
    end
    return 1.0
end

--- The main calculation.
-- @param params table:
--   cfg            - settings (config.all())
--   isPlayer       - boolean
--   equipment      - map of SLOT KEY (see SLOT_WEIGHTS) -> item; empty slots simply omitted
--   isArmor        - function(item) -> boolean
--   armorSkillOf   - function(item) -> 'lightarmor' | 'mediumarmor' | 'heavyarmor' | 'unarmored'
--   skillOf        - function(skillId) -> number
--   unarmoredBase1 - fUnarmoredBase1 game setting
--   unarmoredBase2 - fUnarmoredBase2 game setting
-- @return table: sanctuary (int), raw, armorComponent, breakdown (list)
function M.compute(params)
    local cfg = params.cfg
    local equipment = params.equipment or {}

    local total = 0
    local armorComponent = 0
    local breakdown = {}

    local unarmored = params.skillOf('unarmored') or 0
    local unarmoredPerSlot = (params.unarmoredBase1 * unarmored) * (params.unarmoredBase2 * unarmored)

    -- EVERY slot is scored from Unarmored. Armour skills NEVER produce evasion on their own -
    -- they can only modulate what Unarmored already gave. A character with Unarmored 7 and
    -- Medium Armor 64 gets nothing, because zero times anything is still zero.
    local baseDodge = M.dodgeFromSkill(unarmored, cfg)

    for _, entry in ipairs(M.SLOT_WEIGHTS) do
        local item = equipment[entry.key]
        local skillId = 'unarmored'
        if item and params.isArmor(item) then
            skillId = params.armorSkillOf(item) or 'unarmored'
        end

        -- Proficiency in the armour worn: 0 at skill 0, full at 100. With useArmorSkill off
        -- it is not computed at all, and armour then trims the bonus purely through keep%.
        local proficiency = 1
        local armorSkillValue = nil
        if skillId ~= 'unarmored' then
            armorSkillValue = params.skillOf(skillId) or 0
            if cfg.useArmorSkill then
                proficiency = clamp(armorSkillValue / 100, 0, 1)
            end
        end

        local keep = M.keepFactor(skillId, cfg)
        local contribution = entry.weight * keep * proficiency * baseDodge
        total = total + contribution

        if skillId == 'unarmored' then
            armorComponent = armorComponent + entry.weight * unarmoredPerSlot
        end

        breakdown[#breakdown + 1] = {
            key = entry.key,
            weight = entry.weight,
            skill = skillId,                 -- what covers the slot
            skillValue = unarmored,          -- evasion is always scored from Unarmored
            armorSkillValue = armorSkillValue, -- level of the armour skill worn (nil = empty slot)
            proficiency = proficiency,
            contribution = contribution,
        }
    end

    if not params.isPlayer then
        total = total * (cfg.npcFactor / 100)
    end

    local sanctuary = math.floor(clamp(total, 0, cfg.maxSanctuary) + 0.5)

    return {
        sanctuary = sanctuary,
        raw = total,
        armorComponent = armorComponent,
        breakdown = breakdown,
    }
end

--- Ready-made scenarios for the settings previews and for the tests.
-- They return an (equipment, skills) pair described by slot KEYS, so no engine is needed.
function M.scenario(kind, skillLevel)
    skillLevel = skillLevel or 100
    local equipment = {}
    local skills = { unarmored = skillLevel }

    local armorSkill = nil
    if kind == 'light' then armorSkill = 'lightarmor'
    elseif kind == 'medium' then armorSkill = 'mediumarmor'
    elseif kind == 'heavy' then armorSkill = 'heavyarmor' end

    if armorSkill then
        skills[armorSkill] = skillLevel
        for _, entry in ipairs(M.SLOT_WEIGHTS) do
            equipment[entry.key] = { armorSkill = armorSkill }
        end
    end

    return equipment, skills
end

--- Runs a scenario - the single code path shared by the previews and the tests.
function M.preview(cfg, kind, opts)
    opts = opts or {}
    local equipment, skills = M.scenario(kind, opts.skillLevel)
    return M.compute({
        cfg = cfg,
        isPlayer = opts.isPlayer ~= false,
        equipment = equipment,
        isArmor = function(item) return item ~= nil end,
        armorSkillOf = function(item) return item.armorSkill end,
        skillOf = function(id) return skills[id] or 0 end,
        unarmoredBase1 = opts.unarmoredBase1 or 0.1,
        unarmoredBase2 = opts.unarmoredBase2 or 0.065,
    })
end

return M
