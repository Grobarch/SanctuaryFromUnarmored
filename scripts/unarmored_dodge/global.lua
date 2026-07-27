-- Skrypt globalny: rejestruje grupe ustawien i produkuje rekordy zaklec.
--
-- Dlaczego zaklecia, a nie activeEffects:modify() - modify zapisuje trwala zmiane magnitudy
-- do sejwa i wymaga wlasnej ksiegowosci w onSave/onLoad. Dokladnie tak powstal runaway
-- Strength w Slay's Assassin Mark. Zdjecie ability usuwa efekt bez zadnej ksiegowosci.

local async = require('openmw.async')
local core = require('openmw.core')
local storage = require('openmw.storage')
local world = require('openmw.world')
local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')

for _, group in ipairs(config.groupOptions()) do
    I.Settings.registerGroup(group)
end

local spells = storage.globalSection(config.SPELL_SECTION)

local function spellExists(id)
    return id ~= nil and core.magic.spells.records[id] ~= nil
end

--- Tworzy brakujace rekordy dla magnitud 1..cap. Wywolywane rzadko (start gry, zmiana capa).
local function ensureSpells(cap)
    cap = math.floor(cap or 0)
    if cap < 1 then return end
    if cap > 100 then cap = 100 end

    for magnitude = 1, cap do
        local key = tostring(magnitude)
        if not spellExists(spells:get(key)) then
            local draft = core.magic.spells.createRecordDraft({
                name = 'Unarmored Dodge',
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

-- Podniesienie capa w opcjach musi dorobic brakujace rekordy.
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
        -- Odpalane tez przy wczytaniu sejwa - pokrywa przypadek, w ktorym cap podniesiono
        -- w innej sesji albo sekcja storage zostala wyczyszczona.
        onPlayerAdded = ensureFromConfig,
    },
    eventHandlers = {
        -- Awaryjne zadanie ze skryptu lokalnego, gdyby brakowalo rekordu.
        UnarmoredDodge_EnsureSpells = function(data)
            ensureSpells(data and data.upTo or config.get('maxSanctuary'))
        end,
    },
}
