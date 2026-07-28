-- Dodge readout on Inventory Extender's info bar, right next to the armour rating.
--
-- Soft dependency: without IE this file does nothing. The approach is taken from Crafting
-- Framework (CF_p.lua, the "ie_button" function), which adds its hammer to the same bar.
--
-- IE has no public "add an entry at a given position" API - `addInfoLayout` always APPENDS,
-- and past the grow=1 spacer sits the item drop zone. To stand next to the armour rating we
-- insert ourselves into `infoBar.layout.content` manually, after the entry named
-- 'armorRating'.

local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')

local ENTRY_NAME = 'unarmoredDodge'
local ARMOR_ENTRY_NAME = 'armorRating'
local ICON_SIZE = 16

-- WARNING: REAL time, not dt. An open inventory pauses the game and onFrame then gets dt = 0,
-- so a dt-based counter would never advance - precisely when it is needed.
local CHECK_INTERVAL = 0.25
local lastCheck = 0
-- Signature of the last drawn state: the bonus value AND whether the entry is enabled
-- (comparing numbers alone would miss the option being toggled).
local lastRendered = nil

local iconResource = nil

local function unarmoredIcon()
    if not iconResource then
        local record = core.stats.Skill.records.unarmored
        -- The icon comes from the skill record rather than a hard-coded path, so icon
        -- replacer mods keep working.
        iconResource = ui.texture({ path = record.icon })
    end
    return iconResource
end

local function buildEntry()
    if not config.get('inventoryBar') then
        -- An empty layout removes the entry from the bar. WARNING: the name MUST stay, or the
        -- entry becomes unfindable and every tick would append another copy.
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

--- Inserts the entry when the bar is new or was rebuilt, and otherwise refreshes the value
--- whenever it changed.
--
-- WARNING: the refresh has to be OURS. IE only rebuilds the bar in its own updateAll(), which
-- runs on its own actions - while our value arrives slightly later (actor.lua has its own
-- throttle), so waiting for IE would leave a stale number on screen.
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
        -- Already on the bar - redraw only when the state actually changed.
        if signature ~= lastRendered then
            content[index] = withUpdater(buildEntry())
            window.infoBar:update()
            lastRendered = signature
        end
        return
    end

    -- Wait for the armour rating entry. It only appears after the first updateAll() inside
    -- Inventory:create, so if we look too early we simply give up and retry on the next tick -
    -- better that than inserting ourselves at the wrong place on the bar.
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
