-- Progresja Unarmored za uniki.
--
-- Waniliowo Unarmored rosnie WYLACZNIE z obrywania (Armor_HitByOpponent), wiec mod, ktory
-- sprawia, ze obrywasz rzadziej, spowalnia wlasna progresje. Domykamy petle: kazde pudlo
-- przeciwnika, przy niezerowym bonusie, tez uczy.
--
-- Hook onHit jest tu uzywany WYLACZNIE do odczytu - nie zmieniamy pola `successful`,
-- wiec nie powstaje drugi, niezalezny rzut na unik obok silnikowego.

local I = require('openmw.interfaces')

local config = require('scripts.unarmored_dodge.config')

I.Combat.addOnHitHandler(function(attack)
    if attack.successful then return end
    if not attack.attacker then return end

    local sourceType = attack.sourceType
    if sourceType ~= 'melee' and sourceType ~= 'ranged' then return end

    if not I.UnarmoredDodge or I.UnarmoredDodge.getBonus() <= 0 then return end

    -- Skala 0 = opcja wylaczona. To nie tylko wygoda: Skill Evolution na scale <= 0 robi
    -- `return false` (skills/handlers.lua:242), co ucina reszte JEGO pipeline'u, w tym
    -- handler "final" naliczajacy przyrost - czyli i tak zero nauki, tylko z linia w logu
    -- przy kazdym uniku. Nie wysylamy wiec zdarzenia w ogole.
    local scale = config.get('dodgeXpScale')
    if scale <= 0 then return end

    if I.SkillProgression then
        I.SkillProgression.skillUsed('unarmored', {
            useType = I.SkillProgression.SKILL_USE_TYPES.Armor_HitByOpponent,
            scale = scale,
        })
    end
end)
