-- Tests for formula.lua, run outside the game.
--
-- The module requires NO engine package (slots are identified by our own string keys), so
-- there are no stubs here at all - the mod's real code is what gets executed.

package.path = MOD_ROOT .. '/?.lua;' .. package.path
local formula = require('scripts.unarmored_dodge.formula')

-- Fixed test baseline. Deliberately NOT the mod's shipped defaults: these tests pin down the
-- behaviour of the formula, and should not start failing because a default was retuned.
local defaults = {
    maxSanctuary = 40, threshold = 20, rate = 0.4,
    keepLight = 40, keepMedium = 20, keepHeavy = 0,
    useArmorSkill = true,
    npcFactor = 50, arMultiplier = 1.0,
}

local function cfgWith(over)
    local c = {}
    for k, v in pairs(defaults) do c[k] = v end
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

local function armor(klass) return { armorSkill = klass } end

local function allSlots(klass)
    local eq = {}
    for _, e in ipairs(formula.SLOT_WEIGHTS) do eq[e.key] = armor(klass) end
    return eq
end

local function run(name, opts)
    local skills = opts.skills
    local result = formula.compute({
        cfg = opts.cfg or cfgWith(),
        isPlayer = opts.isPlayer ~= false,
        equipment = opts.equipment or {},
        isArmor = function(item) return item ~= nil end,
        armorSkillOf = function(item) return item.armorSkill end,
        skillOf = function(id) return skills[id] or 0 end,
        unarmoredBase1 = 0.1,
        unarmoredBase2 = 0.065,
    })
    return name, result
end

local failures = 0
local function check(expectedSanctuary, expectedArmor, name, result)
    local okS = result.sanctuary == expectedSanctuary
    local okA = expectedArmor == nil or math.abs(result.armorComponent - expectedArmor) < 0.01
    local status = (okS and okA) and 'OK  ' or 'FAIL'
    if not (okS and okA) then failures = failures + 1 end
    print(('%s %-46s sanctuary=%-4d (expected %-4d)  AR=%.2f'):format(
        status, name, result.sanctuary, expectedSanctuary, result.armorComponent))
end

-- === base curve ===
check(32, 65.0, run('bare, unarmored 100, player', { skills = { unarmored = 100 } }))
check(4, 5.85, run('bare, unarmored 30', { skills = { unarmored = 30 } }))
check(0, 2.6, run('bare, unarmored 20 (at threshold)', { skills = { unarmored = 20 } }))
check(0, 0.1625, run('bare, unarmored 5 (below threshold)', { skills = { unarmored = 5 } }))
check(16, 65.0, run('bare, unarmored 100, NPC', { skills = { unarmored = 100 }, isPlayer = false }))
check(40, 65.0, run('cap: rate 1.0, unarmored 100', {
    skills = { unarmored = 100 }, cfg = cfgWith({ rate = 1.0 }) }))

-- === full armour sets ===
check(0, 0.0, run('full heavy, heavy 100', {
    skills = { unarmored = 100, heavyarmor = 100 }, equipment = allSlots('heavyarmor') }))
check(13, 0.0, run('full light, light 100', {
    skills = { unarmored = 100, lightarmor = 100 }, equipment = allSlots('lightarmor') }))
check(6, 0.0, run('full medium, medium 100', {
    skills = { unarmored = 100, mediumarmor = 100 }, equipment = allSlots('mediumarmor') }))
-- keepHeavy 50% only does something when there is something to take a share of:
-- Unarmored 100 -> 0.5 * 32 = 16.
check(16, 0.0, run('keepHeavy 50%, full heavy, unarmored 100', {
    skills = { unarmored = 100, heavyarmor = 100 }, cfg = cfgWith({ keepHeavy = 50 }),
    equipment = allSlots('heavyarmor') }))
-- Without Unarmored, even Heavy Armor 100 and keepHeavy 50% give zero - an armour skill
-- never produces evasion on its own.
check(0, 0.0, run('keepHeavy 50%, full heavy, NO unarmored', {
    skills = { heavyarmor = 100 }, cfg = cfgWith({ keepHeavy = 50 }),
    equipment = allSlots('heavyarmor') }))

-- === single slots (a cuirass is worth 0.30 of the whole) ===
check(22, 45.5, run('HEAVY cuirass only, rest bare', {
    skills = { unarmored = 100, heavyarmor = 100 },
    equipment = { cuirass = armor('heavyarmor') } }))
-- The worked example from the "Armour coverage" group description in l10n - must match exactly.
check(26, 45.5, run('LIGHT cuirass only, rest bare (l10n example)', {
    skills = { unarmored = 100, lightarmor = 100 },
    equipment = { cuirass = armor('lightarmor') } }))

-- === useArmorSkill: the armour skill MODULATES the Unarmored bonus, never creates it ===
-- ON, light 50 -> 40% of 32, scaled by a proficiency of 0.5 = 6.4
check(6, 0.0, run('useArmorSkill ON, full light, light 50', {
    skills = { unarmored = 100, lightarmor = 50 }, equipment = allSlots('lightarmor') }))
-- OFF -> proficiency ignored, only keep% remains = 12.8
check(13, 0.0, run('useArmorSkill OFF, full light, light 50', {
    skills = { unarmored = 100, lightarmor = 50 },
    cfg = cfgWith({ useArmorSkill = false }), equipment = allSlots('lightarmor') }))
-- At an armour skill of 100 both modes must agree (proficiency = 1.0).
check(13, 0.0, run('both modes agree at light 100 (ON)', {
    skills = { unarmored = 100, lightarmor = 100 }, equipment = allSlots('lightarmor') }))
check(13, 0.0, run('both modes agree at light 100 (OFF)', {
    skills = { unarmored = 100, lightarmor = 100 },
    cfg = cfgWith({ useArmorSkill = false }), equipment = allSlots('lightarmor') }))

-- === REGRESSION: an armoured NPC without Unarmored MUST NOT dodge ===
-- Case observed in game: TR_NarsisGuard, Unarmored 7, Medium Armor 64, full medium set except
-- the shield. The previous model scored the slot from the armour skill and gave him 6 points.
local guard = {}
for _, e in ipairs(formula.SLOT_WEIGHTS) do
    if e.key ~= 'shield' then guard[e.key] = armor('mediumarmor') end
end
check(0, nil, run('guard: unarmored 7, medium 64, full medium', {
    skills = { unarmored = 7, mediumarmor = 64 },
    cfg = cfgWith({ keepMedium = 40, npcFactor = 100 }), isPlayer = false,
    equipment = guard }))
check(0, nil, run('guard, same set, useArmorSkill OFF', {
    skills = { unarmored = 7, mediumarmor = 64 },
    cfg = cfgWith({ keepMedium = 40, npcFactor = 100, useArmorSkill = false }),
    isPlayer = false, equipment = guard }))
-- A character with a high Unarmored in that same armour does get something.
check(11, nil, run('same armour, but unarmored 100', {
    skills = { unarmored = 100, mediumarmor = 64 },
    cfg = cfgWith({ keepMedium = 40, npcFactor = 100 }), isPlayer = false,
    equipment = guard }))

-- === preview scenarios (the very code path used by the settings page) ===
local function checkPreview(expected, name, result)
    local ok = result.sanctuary == expected
    if not ok then failures = failures + 1 end
    print(('%s %-46s sanctuary=%-4d (expected %-4d)'):format(
        ok and 'OK  ' or 'FAIL', name, result.sanctuary, expected))
end

checkPreview(32, 'preview: bare', formula.preview(cfgWith(), 'bare'))
checkPreview(13, 'preview: light', formula.preview(cfgWith(), 'light'))
checkPreview(6, 'preview: medium', formula.preview(cfgWith(), 'medium'))
checkPreview(0, 'preview: heavy', formula.preview(cfgWith(), 'heavy'))
checkPreview(16, 'preview: bare for an NPC', formula.preview(cfgWith(), 'bare', { isPlayer = false }))

-- A preview must agree with a plain calculation on the same setup.
local _, manual = run('control', { skills = { unarmored = 100, lightarmor = 100 },
    equipment = allSlots('lightarmor') })
if formula.preview(cfgWith(), 'light').sanctuary ~= manual.sanctuary then
    failures = failures + 1
    print('FAIL preview "light" disagrees with the plain calculation')
else
    print('OK   preview "light" agrees with the plain calculation')
end

-- The weights must add up to exactly 1.0, otherwise a fully bare actor would not get
-- exactly dodgeFromSkill(unarmored).
local sum = 0
for _, e in ipairs(formula.SLOT_WEIGHTS) do sum = sum + e.weight end
if math.abs(sum - 1.0) > 1e-9 then
    failures = failures + 1
    print(('FAIL slot weights add up to %.4f, expected 1.0'):format(sum))
else
    print(('OK   slot weights add up to %.4f'):format(sum))
end

print(failures == 0 and '\nALL TESTS PASSED' or ('\nFAILURES: ' .. failures))
os.exit(failures == 0 and 0 or 1)
