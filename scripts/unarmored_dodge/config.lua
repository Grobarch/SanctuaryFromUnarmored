-- Wspolny modul konfiguracji.
--
-- Wartosci zyja w globalnych sekcjach storage, dzieki czemu czytaja je zarowno skrypty
-- gracza, jak i skrypty lokalne NPC (storage.playerSection bylby niedostepny dla NPC).
-- Zapis idzie przez strone opcji; my tylko czytamy.
--
-- Trzy grupy: balans, pokrycie pancerzem i czestotliwosc odswiezania. Mapa
-- "klucz ustawienia -> sekcja storage" jest WYPROWADZANA z definicji grup, wiec nie da sie
-- jej rozjechac przy dodawaniu ustawien.

local storage = require('openmw.storage')

local M = {}

M.PAGE = 'UnarmoredDodgePage'
M.L10N = 'UnarmoredDodge'

M.GROUP = 'SettingsUnarmoredDodge'
M.ARMOUR_GROUP = 'SettingsUnarmoredDodgeArmour'
M.PERF_GROUP = 'SettingsUnarmoredDodgePerformance'

-- Wlasny renderer suwaka (rejestrowany przez slider.lua w kontekscie MENU).
M.SLIDER_RENDERER = 'UnarmoredDodgeSlider'

-- Sekcja z mapowaniem magnituda -> id dynamicznie utworzonego zaklecia.
M.SPELL_SECTION = 'UnarmoredDodgeSpells'

-- Wartosci wystrojone w grze (2026-07-27) i przyjete jako domyslne.
M.defaults = {
    -- balans
    maxSanctuary = 40,
    threshold = 20,
    rate = 0.4,
    npcFactor = 100,
    arMultiplier = 1.0,
    dodgeXpScale = 0.5,
    statsWindow = true,
    inventoryBar = true,
    -- pokrycie pancerzem
    keepLight = 60,
    keepMedium = 40,
    keepHeavy = 20,
    useArmorSkill = true,
    -- czestotliwosc
    refreshInterval = 1.0,
    npcPeriodicRefresh = true,
    npcRefreshInterval = 10.0,
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

-- Kazde ustawienie dostaje WLASNA kopie tabeli argumentow - `argument` jest zapisywany
-- do storage per klucz ustawienia, wiec wspoldzielenie jednej tabeli prosi sie o klopoty.
-- `preview` wskazuje scenariusz podgladu (funkcje trzyma slider.lua - do storage nie da sie
-- zapisac funkcji) oraz klucz, ktory ma zostac podmieniony na aktualnie ustawiana wartosc.
local function percent(scenario, key)
    return {
        min = 0, max = 100, step = 5, unit = '%', decimals = 0, width = 170,
        preview = { scenario = scenario, key = key },
    }
end

-- Definicje grup. Kolejnosc pol `order` decyduje o ukladzie strony.
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
        -- Tu zostaja pola liczbowe: zakres 0,1-300 s jest za szeroki na suwak, a te wartosci
        -- ustawia sie raz i chce sie wpisac konkret, nie trafiac w krok.
        key = M.PERF_GROUP,
        name = 'perfGroup',
        order = 2,
        settings = {
            number('refreshInterval', { min = 0.1, max = 60 }),
            checkbox('npcPeriodicRefresh'),
            number('npcRefreshInterval', { min = 0.1, max = 300 }),
        },
    },
}

-- klucz ustawienia -> nazwa sekcji storage
local groupOf = {}
for _, group in ipairs(GROUPS) do
    for _, entry in ipairs(group.settings) do
        groupOf[entry.key] = group.key
    end
end

-- Leniwie, bo skrypty MENU nie moga siegnac do globalnego storage przed startem gry.
local cache = {}
local function sectionByName(name)
    if not cache[name] then
        cache[name] = storage.globalSection(name)
    end
    return cache[name]
end

function M.get(key)
    local value = sectionByName(groupOf[key] or M.GROUP):get(key)
    if value == nil then
        return M.defaults[key]
    end
    return value
end

--- Caly zestaw ustawien jako zwykla tabela - wygodne do przekazania do formula.lua.
function M.all()
    local result = {}
    for key in pairs(M.defaults) do
        result[key] = M.get(key)
    end
    return result
end

--- Wszystkie sekcje storage - do subskrypcji zmian.
function M.sections()
    local result = {}
    for _, group in ipairs(GROUPS) do
        result[#result + 1] = sectionByName(group.key)
    end
    return result
end

--- Definicje grup gotowe dla I.Settings.registerGroup.
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
