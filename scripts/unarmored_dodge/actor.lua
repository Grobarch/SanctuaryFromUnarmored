-- Skrypt lokalny kazdego aktora: liczy bonus i utrzymuje nalozona zdolnosc.
--
-- Przeliczanie jest zdarzeniowe (wejscie w aktywna strefe, wczytanie, rzadki throttle),
-- nigdy co klatke - onUpdate tylko porownuje znaczniki czasu.

local async = require('openmw.async')
local core = require('openmw.core')
local self = require('openmw.self')
local storage = require('openmw.storage')
local types = require('openmw.types')
local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')
local formula = require('scripts.unarmored_dodge.formula')

local Actor = types.Actor
local Armor = types.Armor
local Player = types.Player

-- Mapowanie kluczy slotow formula.lua na sloty silnika. Siedzi TU, a nie w formula.lua,
-- bo tamten modul jest celowo wolny od openmw.types (patrz naglowek formula.lua).
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

--- Ekwipunek silnika -> mapa kluczy slotow, ktorej oczekuje formula.lua.
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
-- ⚠ Znaczniki czasu RZECZYWISTEGO, nie akumulatory dt. Ekwipunek zmienia sie przy otwartym
-- oknie, ktore PAUZUJE gre - onUpdate dostaje wtedy dt = 0, wiec licznik oparty na dt stalby
-- dokladnie w momencie, w ktorym jest potrzebny.
local lastRefresh = 0
local lastEquipCheck = 0

-- Interwaly sa konfigurowalne, ale NIE czytamy ich ze storage co klatke - to byloby
-- drozsze niz sama praca, ktora ograniczaja. Trzymamy je w cache'u odswiezanym przy
-- kazdym pelnym przeliczeniu (a u gracza dodatkowo natychmiast po zmianie suwaka).
--
-- refreshInterval  - pelne przeliczenie; lapie zmiany UMIEJETNOSCI (trening, fortify/drain).
-- equipCheckInterval - kontrola EKWIPUNKU; silnik nie ma handlera na zalozenie/zdjecie
--   przedmiotu (EngineHandlerList w localscripts.hpp to onActive/onInactive/onConsume/
--   onActivated/onTeleported), wiec zostaje polling. Jest tani: jedno getEquipment
--   i sklejenie 9 identyfikatorow; pelne przeliczenie odpala sie dopiero przy zmianie podpisu.
--
-- nil w refreshInterval = brak okresowego sprawdzania (NPC z wylaczonym npcPeriodicRefresh)
-- -> zostaja wylacznie onInit i onActive.
local refreshInterval = nil
local equipCheckInterval = nil

-- Ile razy czesciej niz pelne przeliczenie robimy tani zwiad ekwipunku. NIE jest to
-- ustawienie: rozdzielenie obu interwalow ma sens dopiero przy dlugim `refreshInterval`,
-- a przy domyslnej sekundzie kupowaloby 0,8 s responsywnosci kosztem dwoch suwakow
-- i koniecznosci rozumienia roznicy miedzy dwoma rodzajami odswiezania.
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

--- Lekki podpis stanu 9 slotow pancerza - tylko po to, zeby wykryc zmiane.
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
            -- Rekord jeszcze nie istnieje (np. podniesiono cap w tej samej klatce).
            -- Poprosimy o niego i sprobujemy przy nastepnym odswiezeniu.
            core.sendGlobalEvent('UnarmoredDodge_EnsureSpells', { upTo = magnitude })
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

-- `equipment` mozna podac, gdy wolajacy juz je pobral (kontrola ekwipunku) - unika
-- drugiego przejscia do C++ w tej samej klatce.
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
    -- Zmiana suwaka ma dzialac bez restartu. NPC podchwytuja przy najblizszym
    -- przeliczeniu (reloadIntervals w refresh), a jesli maja wylaczone okresowe
    -- sprawdzanie - dopiero przy onActive.
    local onSettingChanged = async:callback(function() refresh() end)
    for _, section in ipairs(config.sections()) do
        section:subscribe(onSettingChanged)
    end
end

return {
    interfaceName = 'UnarmoredDodge',
    interface = {
        version = 1,

        --- Aktualnie nalozony bonus Sanctuary (punkty).
        getBonus = function()
            return applied
        end,

        --- Rozbicie na wklady poszczegolnych slotow - zrodlo danych dla podgladu w UI.
        getBreakdown = function()
            return lastResult and lastResult.breakdown or {}
        end,

        --- Skladowa armor rating pochodzaca z pustych slotow (uzywa jej armor.lua).
        getArmorComponent = function()
            return lastResult and lastResult.armorComponent or 0
        end,

        --- Wymuszenie przeliczenia.
        refresh = function() refresh() end,
    },
    engineHandlers = {
        -- Opakowane, bo silnik przekazuje do onInit initData - bez tego trafiloby
        -- ono do parametru `equipment`.
        onInit = function() refresh() end,
        onActive = function() refresh() end,
        onUpdate = function()
            -- Brak interwalu = okresowe sprawdzanie wylaczone (NPC bez npcPeriodicRefresh).
            -- Zostaja onInit i onActive; zero pracy na klatke.
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
            -- Zdolnosc przetrwala w sejwie razem z lista zaklec aktora, wiec musimy
            -- odtworzyc wiedze o tym, co jest nalozone - inaczej dolozylibysmy druga.
            applied = saved.applied or 0
            appliedSpellId = saved.spellId
        end,
    },
}
