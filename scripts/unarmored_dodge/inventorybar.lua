-- Wskaznik uniku na pasku informacyjnym Inventory Extender, tuz obok armor rating.
--
-- Miekka zaleznosc: bez IE ten plik nie robi nic. Wzorzec wziety z Crafting Framework
-- (CF_p.lua, funkcja "ie_button"), ktore w ten sam sposob dokłada mlotek do tego paska.
--
-- IE nie ma publicznego API "dodaj wpis w konkretnym miejscu" - `addInfoLayout` zawsze
-- DOPISUJE na koniec, a tam za rozpychaczem (grow=1) siedzi juz strefa upuszczania
-- przedmiotow. Zeby stanac obok pancerza, wstawiamy sie recznie do `infoBar.layout.content`
-- za wpisem o nazwie 'armorRating'.

local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')

local ENTRY_NAME = 'unarmoredDodge'
local ARMOR_ENTRY_NAME = 'armorRating'
local ICON_SIZE = 16

-- ⚠ Czas RZECZYWISTY, nie dt. Otwarty ekwipunek pauzuje gre, a onFrame dostaje wtedy dt = 0,
-- wiec licznik oparty na dt nigdy by nie ruszyl - czyli dokladnie wtedy, kiedy jest potrzebny.
local CHECK_INTERVAL = 0.25
local lastCheck = 0
-- Sygnatura ostatnio narysowanego stanu: wartosc bonusu ORAZ to, czy wpis jest wlaczony
-- (samo porownanie liczb nie zauwazyloby przelaczenia opcji).
local lastRendered = nil

local iconResource = nil

local function unarmoredIcon()
    if not iconResource then
        local record = core.stats.Skill.records.unarmored
        -- Bierzemy ikone z rekordu umiejetnosci, a nie ze sciezki na sztywno - dzieki temu
        -- dziala z zamiennikami ikon.
        iconResource = ui.texture({ path = record.icon })
    end
    return iconResource
end

local function buildEntry()
    if not config.get('inventoryBar') then
        -- Pusty layout = wpis znika z paska. ⚠ Nazwa MUSI zostac, inaczej wpis przestaje byc
        -- odnajdywalny i przy kazdym tyknieciu doklejalibysmy kolejna kopie.
        return { name = ENTRY_NAME }
    end

    local bonus = I.UnarmoredDodge and I.UnarmoredDodge.getBonus() or 0
    local BASE = I.InventoryExtender.Templates.BASE

    return {
        name = ENTRY_NAME,
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            arrange = ui.ALIGNMENT.Center,
        },
        content = ui.content({
            {
                type = ui.TYPE.Image,
                props = {
                    resource = unarmoredIcon(),
                    size = util.vector2(ICON_SIZE, ICON_SIZE),
                },
            },
            BASE.intervalH(4),
            {
                template = BASE.textNormal,
                props = { text = tostring(bonus) },
            },
        }),
    }
end

local function indexOfEntry(content, name)
    for i, child in ipairs(content) do
        local layout = child.layout or child
        if layout and layout.name == name then
            return i
        end
    end
    return nil
end

local function withUpdater(entry)
    entry.userData = { update = function() return buildEntry() end }
    return entry
end

--- Wstawia wpis, jesli paska jeszcze nie ma albo zostal przebudowany; poza tym odswieza
--- wartosc, gdy sie zmienila.
--
-- ⚠ Odswiezanie musi byc NASZE. IE przebudowuje pasek dopiero we wlasnym updateAll(),
-- ktore leci przy jego wlasnych akcjach - a nasza wartosc dojezdza chwile pozniej
-- (actor.lua ma wlasny throttle), wiec czekanie na IE zostawialoby staly, nieaktualny wynik.
local function ensureEntry()
    if not I.InventoryExtender or not I.InventoryExtender.getWindow then return end

    local window = I.InventoryExtender.getWindow('Inventory')
    if not window or not window.infoBar or not window.infoBar.layout then return end

    local content = window.infoBar.layout.content
    if not content then return end

    local bonus = I.UnarmoredDodge and I.UnarmoredDodge.getBonus() or 0
    local signature = tostring(config.get('inventoryBar')) .. ':' .. tostring(bonus)
    local index = indexOfEntry(content, ENTRY_NAME)

    if index then
        -- Jest juz na pasku - przerysowujemy tylko przy faktycznej zmianie stanu.
        if signature ~= lastRendered then
            content[index] = withUpdater(buildEntry())
            window.infoBar:update()
            lastRendered = signature
        end
        return
    end

    -- Czekamy na wpis pancerza. Pojawia sie dopiero po pierwszym updateAll() w
    -- Inventory:create, wiec przy zbyt wczesnym sprawdzeniu po prostu odpuszczamy
    -- i probujemy przy nastepnym tyknieciu - lepiej to, niz wladowac sie w zle miejsce paska.
    local armorIndex = indexOfEntry(content, ARMOR_ENTRY_NAME)
    if not armorIndex then return end

    local BASE = I.InventoryExtender.Templates.BASE
    content:insert(armorIndex + 1, BASE.intervalH(8))
    content:insert(armorIndex + 2, withUpdater(buildEntry()))
    window.infoBar:update()
    lastRendered = signature
end

return {
    engineHandlers = {
        onFrame = function()
            local now = core.getRealTime()
            if now - lastCheck < CHECK_INTERVAL then return end
            lastCheck = now
            ensureEntry()
        end,
    },
}
