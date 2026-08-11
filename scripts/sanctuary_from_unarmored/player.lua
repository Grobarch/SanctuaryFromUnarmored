-- Unarmored progression from dodging.
--
-- In vanilla, Unarmored improves ONLY from being hit (Armor_HitByOpponent), so a mod that
-- makes you get hit less often slows down its own progression. This closes the loop: with
-- a non-zero bonus, an attack that misses trains the skill as well.
--
-- The onHit hook is used for READING ONLY - the `successful` field is never modified, so no
-- second, independent dodge roll appears alongside the engine's one.

local core = require('openmw.core')
local ui = require('openmw.ui')
local I = require('openmw.interfaces')

local config = require('scripts.sanctuary_from_unarmored.config')

I.Combat.addOnHitHandler(function(attack)
    if attack.successful then return end
    if not attack.attacker then return end

    local sourceType = attack.sourceType
    if sourceType ~= 'melee' and sourceType ~= 'ranged' then return end

    if not I.SanctuaryFromUnarmored or I.SanctuaryFromUnarmored.getBonus() <= 0 then return end

    -- Scale 0 means the option is off. This is not just convenience: on scale <= 0 Skill
    -- Evolution does `return false` (skills/handlers.lua:242), which cuts off the rest of ITS
    -- pipeline including the "final" handler that applies the gain - so there would be no
    -- progression anyway, just a log line on every dodge. Better not to send the event.
    local scale = config.get('dodgeXpScale')
    if scale <= 0 then return end

    if I.SkillProgression then
        I.SkillProgression.skillUsed('unarmored', {
            useType = I.SkillProgression.SKILL_USE_TYPES.Armor_HitByOpponent,
            scale = scale,
        })
    end
end)

return {
    eventHandlers = {
        -- Reported by the global script after the removal button was pressed, so the player
        -- gets told what happened instead of having to trust an unlabelled switch.
        SanctuaryFromUnarmored_Removed = function(data)
            ui.showMessage(core.l10n(config.L10N)('msg_removalDone', {
                count = (data and data.count) or 0,
            }))
        end,
    },
}
