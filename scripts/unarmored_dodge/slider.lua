-- Wlasny renderer suwaka dla strony opcji (kontekst MENU).
--
-- Silnik ma tylko textLine/checkbox/number/select/color - suwaka nie ma. Sun's Dusk wozi
-- wspoldzielony "SuperSlider4", ale NIE robimy z niego zaleznosci: gdy renderer o podanym
-- kluczu nie istnieje, psuje sie cala strona ustawien (objaw "unknown renderer", ten sam,
-- ktory wylozyl Quest Markers Plus). Wlasny klucz = zawsze zarejestrowany, zero zaleznosci.
--
-- argument = {
--   min, max, step   - zakres i skok (domyslnie 0 / 100 / 1)
--   width, thickness - rozmiar toru (domyslnie 200 / 15)
--   unit             - sufiks doklejany do wartosci, np. '%' albo 'x'
--   decimals         - miejsca po przecinku w odczycie (domyslnie z kroku)
-- }

local async = require('openmw.async')
local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')
local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')
local formula = require('scripts.unarmored_dodge.formula')

-- === Interaktywny podglad ===
--
-- Renderer jest wolany od nowa przy KAZDEJ zmianie wartosci (menu.lua:361-371 przerysowuje
-- cala grupe po zapisie do storage), wiec wystarczy policzyc przyklad tutaj, a odswiezy sie
-- sam przy przeciaganiu suwaka.
--
-- ⚠ `argument` ustawienia ladzie w storage (common.registerGroup -> argumentSection:set),
-- wiec NIE MOZE zawierac funkcji. Scenariusz podajemy wiec kluczem tekstowym, a same
-- funkcje trzymamy tutaj.
local previews = {
    -- Bez pancerza - dla ustawien opisujacych sama krzywa.
    bare = function(cfg)
        return 'preview_bare', { points = formula.preview(cfg, 'bare').sanctuary }
    end,
    light = function(cfg)
        return 'preview_light', { points = formula.preview(cfg, 'light').sanctuary }
    end,
    medium = function(cfg)
        return 'preview_medium', { points = formula.preview(cfg, 'medium').sanctuary }
    end,
    heavy = function(cfg)
        return 'preview_heavy', { points = formula.preview(cfg, 'heavy').sanctuary }
    end,
    npc = function(cfg)
        return 'preview_npc', {
            player = formula.preview(cfg, 'bare').sanctuary,
            npc = formula.preview(cfg, 'bare', { isPlayer = false }).sanctuary,
        }
    end,
    armorRating = function(cfg)
        local component = formula.preview(cfg, 'bare').armorComponent
        return 'preview_armorRating', {
            base = math.floor(component + 0.5),
            scaled = math.floor(component * cfg.arMultiplier + 0.5),
        }
    end,
}

--- Konfiguracja z podmieniona wartoscia edytowanego ustawienia.
-- W menu glownym (bez wczytanej gry) globalne storage jest niedostepne - wtedy
-- schodzimy na wartosci domyslne, zeby podglad dalej cos pokazywal.
local function previewConfig(key, value)
    local ok, cfg = pcall(config.all)
    if not ok or type(cfg) ~= 'table' then
        cfg = {}
        for k, v in pairs(config.defaults) do cfg[k] = v end
    end
    if key then cfg[key] = value end
    return cfg
end

local function previewLayout(argument, value, template)
    local spec = argument.preview
    if not spec then return nil end

    local builder = previews[spec.scenario]
    if not builder then return nil end

    local ok, key, params = pcall(builder, previewConfig(spec.key, value))
    if not ok or not key then return nil end

    local translated, text = pcall(function()
        return core.l10n(config.L10N)(key, params)
    end)
    if not translated or type(text) ~= 'string' then return nil end

    return {
        template = template,
        props = { text = text, textSize = 14 },
    }
end

local leftArrow = ui.texture({ path = 'textures/omw_menu_scroll_left.dds' })
local rightArrow = ui.texture({ path = 'textures/omw_menu_scroll_right.dds' })
local trackTexture = ui.texture({ path = 'textures/omw_menu_scroll_center_h.dds' })

local defaults = {
    min = 0,
    max = 100,
    step = 1,
    width = 200,
    thickness = 15,
    unit = '',
}

local function withDefaults(argument)
    local result = {}
    for key, value in pairs(defaults) do
        result[key] = value
    end
    for key, value in pairs(argument or {}) do
        result[key] = value
    end
    return result
end

local function decimalsFor(argument)
    if argument.decimals then return argument.decimals end
    if argument.step >= 1 then return 0 end
    if argument.step >= 0.1 then return 1 end
    return 2
end

local function snap(value, argument)
    local snapped = math.floor(value / argument.step + 0.5) * argument.step
    return util.clamp(snapped, argument.min, argument.max)
end

I.Settings.registerRenderer(config.SLIDER_RENDERER, function(value, set, rawArgument)
    local argument = withDefaults(rawArgument)
    local trackWidth = argument.width
    local trackHeight = argument.thickness
    local handleWidth = trackHeight + 2
    local handleHeight = math.max(trackHeight - 4, 4)
    local arrowSize = util.vector2(trackHeight, trackHeight)
    local span = argument.max - argument.min

    local function positionOf(val)
        if span == 0 then return 0 end
        return math.floor((val - argument.min) / span * (trackWidth - handleWidth) + 0.5)
    end

    local function valueAt(x)
        if trackWidth - handleWidth <= 0 then return argument.min end
        return snap(argument.min + (x / (trackWidth - handleWidth)) * span, argument)
    end

    local function stepBy(delta)
        return async:callback(function()
            local newValue = snap(value + delta * argument.step, argument)
            if newValue ~= value then set(newValue) end
        end)
    end

    local fromMouse = async:callback(function(event)
        if event.button ~= 1 then return end
        local x = util.clamp(event.offset.x - handleWidth / 2, 0, trackWidth - handleWidth)
        local newValue = valueAt(x)
        if newValue ~= value then set(newValue) end
    end)

    local function arrow(resource, onClick)
        return {
            template = I.MWUI.templates.box,
            content = ui.content({
                {
                    type = ui.TYPE.Image,
                    props = { resource = resource, size = arrowSize },
                    events = { mouseClick = onClick },
                },
            }),
        }
    end

    local track = {
        template = I.MWUI.templates.box,
        content = ui.content({
            {
                type = ui.TYPE.Widget,
                props = { size = util.vector2(trackWidth, trackHeight) },
                events = { mousePress = fromMouse, mouseMove = fromMouse },
                content = ui.content({
                    {
                        type = ui.TYPE.Widget,
                        props = {
                            position = util.vector2(positionOf(value), (trackHeight - handleHeight) / 2),
                            size = util.vector2(handleWidth, handleHeight),
                        },
                        content = ui.content({
                            {
                                type = ui.TYPE.Image,
                                props = {
                                    resource = trackTexture,
                                    size = util.vector2(handleWidth, handleHeight),
                                },
                            },
                        }),
                    },
                }),
            },
        }),
    }

    local text = string.format('%.' .. decimalsFor(argument) .. 'f%s', value, argument.unit)
    local readout = {
        template = I.MWUI.templates.box,
        content = ui.content({
            {
                template = I.MWUI.templates.textNormal,
                props = {
                    text = text,
                    size = util.vector2(46, trackHeight),
                    autoSize = false,
                    textSize = trackHeight,
                    textAlignH = ui.ALIGNMENT.Center,
                },
            },
        }),
    }

    local sliderRow = {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
        content = ui.content({
            arrow(leftArrow, stepBy(-1)),
            track,
            arrow(rightArrow, stepBy(1)),
            readout,
        }),
    }

    local layout = sliderRow
    local preview = previewLayout(argument, value, I.MWUI.templates.textNormal)
    if preview then
        -- Suwak plus linijka podgladu pod nim, wyrownana do prawej jak reszta wiersza.
        layout = {
            type = ui.TYPE.Flex,
            props = { horizontal = false, align = ui.ALIGNMENT.End },
            content = ui.content({ sliderRow, preview }),
        }
    end

    if argument.disabled then
        return {
            template = I.MWUI.templates.disabled,
            content = ui.content({ layout }),
        }
    end
    return layout
end)
