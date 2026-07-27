-- Test formula.lua poza gra.
--
-- Po refaktorze modul nie wymaga ZADNEGO pakietu silnika (sloty sa identyfikowane wlasnymi
-- kluczami), wiec nie ma tu juz zadnych stubow - wykonywany jest czysty kod moda.

package.path = MOD_ROOT .. '/?.lua;' .. package.path
local formula = require('scripts.unarmored_dodge.formula')

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
    print(('%s %-46s sanctuary=%-4d (oczekiwane %-4d)  AR=%.2f'):format(
        status, name, result.sanctuary, expectedSanctuary, result.armorComponent))
end

-- === krzywa bazowa ===
check(32, 65.0, run('goly, unarmored 100, gracz', { skills = { unarmored = 100 } }))
check(4, 5.85, run('goly, unarmored 30', { skills = { unarmored = 30 } }))
check(0, 2.6, run('goly, unarmored 20 (prog)', { skills = { unarmored = 20 } }))
check(0, 0.1625, run('goly, unarmored 5 (ponizej progu)', { skills = { unarmored = 5 } }))
check(16, 65.0, run('goly, unarmored 100, NPC', { skills = { unarmored = 100 }, isPlayer = false }))
check(40, 65.0, run('cap: rate 1.0, unarmored 100', {
    skills = { unarmored = 100 }, cfg = cfgWith({ rate = 1.0 }) }))

-- === pelne komplety pancerza ===
check(0, 0.0, run('pelny ciezki, heavy 100', {
    skills = { unarmored = 100, heavyarmor = 100 }, equipment = allSlots('heavyarmor') }))
check(13, 0.0, run('pelny lekki, light 100', {
    skills = { unarmored = 100, lightarmor = 100 }, equipment = allSlots('lightarmor') }))
check(6, 0.0, run('pelny sredni, medium 100', {
    skills = { unarmored = 100, mediumarmor = 100 }, equipment = allSlots('mediumarmor') }))
-- keepHeavy 50% dziala TYLKO wtedy, gdy jest z czego brac: Unarmored 100 -> 0.5 * 32 = 16.
check(16, 0.0, run('keepHeavy 50%, pelny ciezki, unarmored 100', {
    skills = { unarmored = 100, heavyarmor = 100 }, cfg = cfgWith({ keepHeavy = 50 }),
    equipment = allSlots('heavyarmor') }))
-- Bez Unarmored nawet Heavy Armor 100 i keepHeavy 50% daje zero - skill pancerza nie
-- generuje uniku samodzielnie.
check(0, 0.0, run('keepHeavy 50%, pelny ciezki, BEZ unarmored', {
    skills = { heavyarmor = 100 }, cfg = cfgWith({ keepHeavy = 50 }),
    equipment = allSlots('heavyarmor') }))

-- === pojedyncze sloty (waga kirysu = 0.30) ===
check(22, 45.5, run('sam kirys CIEZKI, reszta gola', {
    skills = { unarmored = 100, heavyarmor = 100 },
    equipment = { cuirass = armor('heavyarmor') } }))
-- Przyklad z opisu grupy "Armour coverage" w l10n - musi sie zgadzac co do punktu.
check(26, 45.5, run('sam kirys LEKKI, reszta gola (przyklad z l10n)', {
    skills = { unarmored = 100, lightarmor = 100 },
    equipment = { cuirass = armor('lightarmor') } }))

-- === useArmorSkill: skill pancerza MODULUJE bonus z Unarmored, nigdy go nie tworzy ===
-- ON, light 50 -> 40% z 32, przeskalowane bieglościa 0.5 = 6.4
check(6, 0.0, run('useArmorSkill ON, pelny lekki, light 50', {
    skills = { unarmored = 100, lightarmor = 50 }, equipment = allSlots('lightarmor') }))
-- OFF -> biegłosc pomijana, zostaje samo keep% = 12.8
check(13, 0.0, run('useArmorSkill OFF, pelny lekki, light 50', {
    skills = { unarmored = 100, lightarmor = 50 },
    cfg = cfgWith({ useArmorSkill = false }), equipment = allSlots('lightarmor') }))
-- Przy skillu pancerza 100 oba tryby musza dac to samo (biegłosc = 1.0).
check(13, 0.0, run('oba tryby zgodne przy light 100 (ON)', {
    skills = { unarmored = 100, lightarmor = 100 }, equipment = allSlots('lightarmor') }))
check(13, 0.0, run('oba tryby zgodne przy light 100 (OFF)', {
    skills = { unarmored = 100, lightarmor = 100 },
    cfg = cfgWith({ useArmorSkill = false }), equipment = allSlots('lightarmor') }))

-- === REGRESJA: opancerzony NPC bez Unarmored NIE MOZE unikac ===
-- Przypadek z gry: straznik TR_NarsisGuard, Unarmored 7, Medium Armor 64, pelny sredni
-- komplet poza tarcza. Dawny model liczyl slot ze skilla pancerza i dawal mu 6 punktow.
local guard = {}
for _, e in ipairs(formula.SLOT_WEIGHTS) do
    if e.key ~= 'shield' then guard[e.key] = armor('mediumarmor') end
end
check(0, nil, run('straznik: unarmored 7, medium 64, pelny sredni', {
    skills = { unarmored = 7, mediumarmor = 64 },
    cfg = cfgWith({ keepMedium = 40, npcFactor = 100 }), isPlayer = false,
    equipment = guard }))
check(0, nil, run('straznik, ten sam uklad, useArmorSkill OFF', {
    skills = { unarmored = 7, mediumarmor = 64 },
    cfg = cfgWith({ keepMedium = 40, npcFactor = 100, useArmorSkill = false }),
    isPlayer = false, equipment = guard }))
-- Za to postac z wysokim Unarmored w tym samym pancerzu dostaje juz cos.
check(11, nil, run('ten sam pancerz, ale unarmored 100', {
    skills = { unarmored = 100, mediumarmor = 64 },
    cfg = cfgWith({ keepMedium = 40, npcFactor = 100 }), isPlayer = false,
    equipment = guard }))

-- === scenariusze podgladow (ten sam kod, ktorego uzywa strona ustawien) ===
local function checkPreview(expected, name, result)
    local ok = result.sanctuary == expected
    if not ok then failures = failures + 1 end
    print(('%s %-46s sanctuary=%-4d (oczekiwane %-4d)'):format(
        ok and 'OK  ' or 'FAIL', name, result.sanctuary, expected))
end

checkPreview(32, 'podglad: bare', formula.preview(cfgWith(), 'bare'))
checkPreview(13, 'podglad: light', formula.preview(cfgWith(), 'light'))
checkPreview(6, 'podglad: medium', formula.preview(cfgWith(), 'medium'))
checkPreview(0, 'podglad: heavy', formula.preview(cfgWith(), 'heavy'))
checkPreview(16, 'podglad: bare dla NPC', formula.preview(cfgWith(), 'bare', { isPlayer = false }))

-- Podglad musi dawac to samo, co zwykle wyliczenie na tym samym ukladzie.
local _, manual = run('kontrola', { skills = { unarmored = 100, lightarmor = 100 },
    equipment = allSlots('lightarmor') })
if formula.preview(cfgWith(), 'light').sanctuary ~= manual.sanctuary then
    failures = failures + 1
    print('FAIL podglad "light" rozjechal sie ze zwyklym wyliczeniem')
else
    print('OK   podglad "light" zgodny ze zwyklym wyliczeniem')
end

-- Suma wag musi wynosic dokladnie 1.0, inaczej "caly goly" nie daje dodgeZeSkilla(unarmored).
local sum = 0
for _, e in ipairs(formula.SLOT_WEIGHTS) do sum = sum + e.weight end
if math.abs(sum - 1.0) > 1e-9 then
    failures = failures + 1
    print(('FAIL suma wag slotow = %.4f, oczekiwane 1.0'):format(sum))
else
    print(('OK   suma wag slotow = %.4f'):format(sum))
end

print(failures == 0 and '\nWSZYSTKIE TESTY PRZESZLY' or ('\nBLEDY: ' .. failures))
os.exit(failures == 0 and 0 or 1)
