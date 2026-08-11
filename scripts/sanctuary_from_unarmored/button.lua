-- A button renderer for the settings page (MENU context), used by the removal switch.
--
-- The engine ships no button renderer, the same gap slider.lua fills for sliders. The value
-- behind it is an ordinary boolean setting, so pressing the button goes through the normal
-- settings write path - which is also how the global script hears about it (it subscribes to
-- the storage section). No separate MENU -> GLOBAL channel is needed, and MENU scripts could
-- not write to global storage anyway.
--
-- argument = {
--   offLabel - l10n key for the label shown while the setting is off (the action that turns
--              it on), e.g. "Remove this mod's effects"
--   onLabel  - l10n key for the label shown while it is on, i.e. the way back
--   onNote   - l10n key for an optional line under the button while the setting is on
-- }

local async = require('openmw.async')
local core = require('openmw.core')
local ui = require('openmw.ui')
local I = require('openmw.interfaces')

local config = require('scripts.sanctuary_from_unarmored.config')

local function translate(key)
    if not key then return nil end
    local ok, text = pcall(function()
        return core.l10n(config.L10N)(key)
    end)
    if not ok or type(text) ~= 'string' then return nil end
    return text
end

I.Settings.registerRenderer(config.BUTTON_RENDERER, function(value, set, argument)
    argument = argument or {}
    local on = value == true

    local caption = translate(on and argument.onLabel or argument.offLabel) or '...'

    local button = {
        template = I.MWUI.templates.box,
        events = {
            mouseClick = async:callback(function()
                set(not on)
            end),
        },
        content = ui.content({
            {
                template = I.MWUI.templates.textNormal,
                props = { text = ' ' .. caption .. ' ' },
            },
        }),
    }

    local note = on and translate(argument.onNote) or nil
    if not note then return button end

    -- While removal mode is on, the button alone would not say what is actually happening.
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = false, align = ui.ALIGNMENT.End },
        content = ui.content({
            button,
            {
                template = I.MWUI.templates.textNormal,
                props = { text = note, textSize = 14 },
            },
        }),
    }
end)
