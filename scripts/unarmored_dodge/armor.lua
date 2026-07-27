-- Opcjonalny wplyw na armor rating (suwak arMultiplier).
--
-- Nadpisujemy I.Combat.getArmorRating lancuchowo - wzorzec z vfs-mw/scripts/omw/combat/local.lua:
-- shallowCopy calego interfejsu, podmiana jednej funkcji, wolanie oryginalu w srodku.
-- Przy arMultiplier = 1.0 funkcja jest czystym przelotem.
--
-- Uwaga: ruszamy WYLACZNIE warstwe Lua. GMST-y fUnarmoredBase1/2 zostaja nietkniete,
-- wiec autoEquipArmor w C++ dziala waniliowo i NPC nie zaczna zdejmowac pancerzy.

local auxUtil = require('openmw_aux.util')
local self = require('openmw.self')
local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')

local base = auxUtil.shallowCopy(I.Combat)
local interface = auxUtil.shallowCopy(I.Combat)

local function isSelf(actor)
    if actor == nil or actor == self then
        return true
    end
    local ok, id = pcall(function() return actor.id end)
    return ok and id == self.object.id
end

interface.getArmorRating = function(actor)
    local rating = base.getArmorRating(actor)

    local multiplier = config.get('arMultiplier')
    if multiplier == 1.0 then
        return rating
    end
    -- Znamy skladowa tylko dla wlasnego aktora.
    if not isSelf(actor) then
        return rating
    end

    local component = 0
    if I.UnarmoredDodge then
        component = I.UnarmoredDodge.getArmorComponent()
    end

    return rating + (multiplier - 1.0) * component
end

return {
    interfaceName = 'Combat',
    interface = interface,
}
