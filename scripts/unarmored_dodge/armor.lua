-- Optional effect on armour rating (the arMultiplier slider).
--
-- I.Combat.getArmorRating is overridden by chaining - the pattern used by
-- vfs-mw/scripts/omw/combat/local.lua: shallow-copy the whole interface, replace one
-- function, call the original inside it. At arMultiplier = 1.0 this is a pure pass-through.
--
-- Note: only the Lua layer is touched. The fUnarmoredBase1/2 game settings are left alone,
-- so autoEquipArmor in C++ behaves exactly as in vanilla and NPCs never strip their armour.

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
    -- We only know the unarmoured component for our own actor.
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
