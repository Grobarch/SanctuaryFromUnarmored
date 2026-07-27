-- Czysty modul obliczeniowy: dostaje opis aktora, zwraca liczby.
--
-- ⚠ ZERO zaleznosci od pakietow silnika - swiadomie. Skrypty MENU dostaja tylko
-- openmw.core/ambient/ui/menu/input (luabindings.cpp, initMenuPackages), wiec gdyby ten plik
-- wymagal openmw.types, nie dalby sie zaladowac w rendererze strony ustawien i interaktywne
-- podglady bylyby niemozliwe. Sloty sa wiec identyfikowane wlasnymi kluczami tekstowymi,
-- a mapowanie na Actor.EQUIPMENT_SLOT siedzi w actor.lua, ktory typy ma.
--
-- Efekt uboczny: modul da sie odpalic poza gra (patrz tests/).

local M = {}

-- Wagi slotow przepisane z silnika (vfs-mw/scripts/omw/combat/local.lua, getArmorRating).
-- Sumuja sie do 1.0, wiec "caly goly" daje dokladnie dodgeZeSkilla(unarmored).
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

--- Ile punktow uniku daje dany poziom umiejetnosci.
function M.dodgeFromSkill(skillValue, cfg)
    return math.max(0, (skillValue - cfg.threshold) * cfg.rate)
end

--- Jaka czesc bonusu przezywa noszenie pancerza danej klasy (0..1).
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

--- Glowne wyliczenie.
-- @param params tabela:
--   cfg            - ustawienia (config.all())
--   isPlayer       - boolean
--   equipment      - mapa KLUCZ SLOTU (patrz SLOT_WEIGHTS) -> przedmiot; puste sloty pominiete
--   isArmor        - function(item) -> boolean
--   armorSkillOf   - function(item) -> 'lightarmor' | 'mediumarmor' | 'heavyarmor' | 'unarmored'
--   skillOf        - function(skillId) -> number
--   unarmoredBase1 - GMST fUnarmoredBase1
--   unarmoredBase2 - GMST fUnarmoredBase2
-- @return tabela: sanctuary (int), raw, armorComponent, breakdown (lista)
function M.compute(params)
    local cfg = params.cfg
    local equipment = params.equipment or {}

    local total = 0
    local armorComponent = 0
    local breakdown = {}

    local unarmored = params.skillOf('unarmored') or 0
    local unarmoredPerSlot = (params.unarmoredBase1 * unarmored) * (params.unarmoredBase2 * unarmored)

    -- KAZDY slot punktuje sie z Unarmored. Umiejetnosci pancerza NIGDY nie generuja uniku
    -- same z siebie - moga go tylko modulowac, i to dopiero wtedy, gdy Unarmored cos daje.
    -- Postac z Unarmored 7 i Medium Armor 64 dostaje zero, bo zero razy cokolwiek to zero.
    local baseDodge = M.dodgeFromSkill(unarmored, cfg)

    for _, entry in ipairs(M.SLOT_WEIGHTS) do
        local item = equipment[entry.key]
        local skillId = 'unarmored'
        if item and params.isArmor(item) then
            skillId = params.armorSkillOf(item) or 'unarmored'
        end

        -- Biegłosc w noszonym pancerzu: 0 przy skillu 0, pelna przy 100. Przy useArmorSkill
        -- = false w ogole jej nie liczymy - wtedy pancerz tlumi bonus wylacznie przez keep%.
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
            skill = skillId,                 -- czym slot jest pokryty
            skillValue = unarmored,          -- unik zawsze liczy sie z Unarmored
            armorSkillValue = armorSkillValue, -- poziom skilla noszonego pancerza (nil = slot pusty)
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

--- Gotowe scenariusze do podgladow w ustawieniach i do testow.
-- Zwracaja pare (equipment, skills) opisana KLUCZAMI slotow, wiec nie potrzebuja silnika.
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

--- Uruchomienie scenariusza - jedno miejsce, z ktorego korzystaja podglady i testy.
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
