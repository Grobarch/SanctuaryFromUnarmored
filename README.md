# Sanctuary From Unarmored

An OpenMW mod (Lua only) that gives the **Unarmored** skill a second axis of value: a scaled
**Sanctuary** effect — real evasion, instead of armour rating alone.

This repository is the mod's **source of truth** and at the same time the directory the game
mounts (`data=`), so there are no copies here that could drift apart.

## The problem

Vanilla Unarmored grants `0.0065 × skill²` armour rating per slot — at skill 30 that is 5.85,
so it does effectively nothing for the first ~60 skill levels, and never does anything
**beyond** AR.

The classic "fix" — raising the `fUnarmoredBase1/2` game settings — has a documented side
effect: NPCs stop putting on weak armour. This is **not** an MCP artefact; the engine does it
by itself in `mwworld/inventorystore.cpp` (`autoEquipArmor`), rejecting every piece of armour
worse than the `unarmoredRating` computed from exactly those game settings.

This mod **touches no game setting at all**, so the problem does not arise.

## What it does

The Unarmored skill is converted into Sanctuary points. In the engine, 1 point of Sanctuary is
1 percentage point off the chance to hit (`defenseTerm` in `mwmechanics/combat.cpp`), so the
bonus applies to melee blows and projectiles but **not** to spells — exactly as in vanilla.

Armour does **not** switch the bonus off, it trims it: every slot is scored against its own
skill (Light/Medium/Heavy Armor) with a configurable share. Unarmored **complements** the other
armour skills instead of competing with them.

**Evasion always comes from Unarmored.** Armour skills never produce it — they can only
modulate what Unarmored already gave. A character with no Unarmored training does not dodge,
even with Heavy Armor 100.

The **`Armour proficiency matters`** switch decides whether skill in the armour actually worn
scales the result on top of that:

| Case (at the default `keepLight` of 60%) | ON (default) | OFF |
|---|---|---|
| Unarmored 100, full light set, Light Armor 100 | 19 pts | 19 pts |
| Unarmored 100, full light set, Light Armor 50 | **10 pts** | **19 pts** |
| Unarmored 7, full medium set, Medium Armor 64 | **0 pts** | **0 pts** |

Per-slot formula: `weight × keep% × proficiency × dodgeFromSkill(unarmored)`, where proficiency
is `armour_skill / 100` when ON (clamped to 1.0) or 1.0 when OFF. An empty slot has proficiency
1.0 and the full `keep`.

NPCs get the bonus too (separate factor, 100% by default). The effect is passive, so it
naturally applies in NPC-versus-NPC fights as well. Creatures are out of scope — see
"Architecture".

## Requirements

- **OpenMW ≥ 0.51** — the mod uses the `I.Combat` interface (`getArmorSkill`,
  `addOnHitHandler`, `getArmorRating`), which arrived with the move of combat mechanics into
  Lua (commit `e978c230dc`, an ancestor of the `openmw-51-rc1` tag).
- No hard dependency on any other mod.

## Integrations (optional, detected at runtime)

| Mod | What you get |
|---|---|
| **Stats Window Extender** | a "Dodge" line in the character window plus a tooltip with the per-slot breakdown |
| **Inventory Extender** | the bonus next to armour rating on the inventory info bar |
| **Skill Evolution** | dodge progression goes through `I.SkillProgression.skillUsed`, so SE keeps setting the pace |

If none of them is present the mod works normally, with no error in the log.

### Verified compatibility

| Checked | Result |
|---|---|
| Other overrides of `I.Combat` | **none** — we are the only mod with `interfaceName = 'Combat'` |
| Other writes to Sanctuary | **none** |
| Overrides of the `fUnarmoredBase1/2` game settings | **none** |
| **Skill Evolution** | compatible. Our `skillUsed` passes through 9 SE handlers, so its multipliers (`Armor_HitByOpponent`, gain 1.25) stack on top of our scale. SE also reads Sanctuary in its own reconstruction of the hit chance, so it sees our bonus automatically |
| **Natural Character Growth** | compatible, but **not neutral** — see below |

⚠ **NCG changes how much the `dodgeXpScale` option weighs.** NCG grows attributes from skill
gains (`core/attributes.lua`, `getGrowth`), and Unarmored maps to **speed 3, agility 2,
endurance 1, personality 1**. So dodge progression does not stop at the skill — it also feeds
attributes and, through major/minor skills, level progress. Agility additionally goes into the
vanilla `defenseTerm`, which creates a gentle positive loop: more dodges → faster Unarmored →
more Agility → better dodging again. It is not a runaway, but it is worth keeping in mind when
tuning `dodgeXpScale`.

⚠ **`dodgeXpScale = 0` cannot send the event.** On `scale <= 0` Skill Evolution does
`return false` (`skills/handlers.lua:242-244`), and `false` from a handler **stops the rest of
the chain** (`openmw_aux/util.lua:119-128`).

What is lost: handlers run in **reverse registration order**, and SE registers its own as
`final, external, levelScaled, decay, magic, scaled, uses, capper, scale` — so `scale` runs
first and `final` last. A `false` from `scale` cuts out **the entire rest of SE's pipeline**,
including `final`, i.e. the only handler that actually applies the gain (`handlers.lua:87-96`).
The result: no skill gain at all, plus a `print` line in the log on **every** dodge.

What is **not** lost: mods that register directly with `I.SkillProgression` load **after** SE
in this installation (Reading is Good, Disenchanting, Toxicology, Bullseye, Fair Trade), so in
the reverse iteration they run *before* the `scale` handler and are untouched. Only a mod
hooked in through SE's own API (`addSkillUsedHandler`) would suffer — and there is none here;
HBFS and N'Garde use `addOnHitHandler`, which is a different chain.

So zero is treated as "option off" and no event is sent at all.

## Installation

Unpack the archive somewhere outside your Morrowind directory. Inside you will find a single
`SanctuaryFromUnarmored` folder — that folder is the data path.

**With the launcher (recommended)**

1. Launcher → *Data Files* → *Data Directories* → **Append** → point it at the `SanctuaryFromUnarmored`
   folder (the one containing `scripts/` and `sanctuary-from-unarmored.omwscripts`).
2. Still in *Data Files*, tick **`sanctuary-from-unarmored.omwscripts`** in the content list.
3. Play.

**By hand**, if you edit `openmw.cfg` yourself — add, with the launcher closed:

```
data="C:/path/to/SanctuaryFromUnarmored"
content=sanctuary-from-unarmored.omwscripts
```

Position in the load order does not matter: the mod does not depend on any other
`.omwscripts`, and it registers no records that could be overridden.

> **Users of momw-configurator / modding-openmw.com lists:** the mod is Lua only, so **no
> config regeneration is needed**. Put both lines into your customizations toml, with the
> `content=` line inserted *before* `delta-merged.omwaddon`, and mirror them in `openmw.cfg`.

Updating: replace the folder. Nothing has to be done to an existing save — but read
[Uninstalling](#uninstalling) before you remove the mod for good.

## Configuration

Options → Scripts → **Sanctuary From Unarmored**, three groups: **Balance**, **Armour coverage** and
**Update frequency**. Nothing is hard-coded — `formula.lua` reads only what the configuration
hands it. Changes take effect immediately, with no restart (player); NPCs catch up within
~10 s.

Defaults (tuned in game, not picked out of thin air):

| | | | |
|---|---|---|---|
| cap **40** | threshold **20** | points per level **0.4** | NPC share **100%** |
| light **60%** | medium **40%** | heavy **20%** | armour proficiency **ON** |
| AR multiplier **1.00x** | skill gain from dodging **0.5** | | |

With that set, bare Unarmored 100 yields **32 points**. For reference, the mods that inspired
this one (#51332, #55758) land around 40–60 at skill 100.

## Architecture

```
scripts/sanctuary_from_unarmored/
  config.lua       values plus the definitions of the 3 settings groups (global storage
                   sections, so that NPC scripts can read them too; the key->section map
                   is derived from the definitions, so it cannot drift)
  formula.lua      pure function: (equipment, skills) -> Sanctuary + AR component.
                   ⚠ ZERO dependencies on engine packages - slots have their own string
                   keys, because MENU scripts do not get `openmw.types` and the settings
                   previews could not be computed otherwise
  slider.lua       MENU   - our own slider renderer
  menu.lua         MENU   - registration of the options page (the global Settings
                            interface only exposes registerGroup)
  global.lua       GLOBAL - settings groups plus the lazy spell-record factory
  actor.lua        NPC,PLAYER - recalculation and application of the ability
  armor.lua        NPC,PLAYER - optional I.Combat.getArmorRating override
  player.lua       PLAYER - Unarmored progression from dodging
  statswindow.lua  PLAYER - Stats Window Extender integration
  inventorybar.lua PLAYER - Inventory Extender info-bar integration
```

**Creatures are deliberately out of scope** — they have no real Unarmored skill (the engine
derives their value from their specialisation) and get no vanilla armour rating out of it, so
there is nothing to scale. No `CREATURE` in the registration means zero cost on every creature
in the world.

### Sliders

The engine only ships `textLine`, `checkbox`, `number`, `select` and `color` — there is no
slider. `slider.lua` registers our own renderer in the MENU context. Sun's Dusk carries a
shared `SuperSlider4`, but **we do not make it a dependency**: a missing renderer breaks the
whole settings page (the "unknown renderer" symptom, the very one that took down Quest Markers
Plus).

Every balance value got a slider. The refresh intervals **stayed number fields** — a 0.1–300 s
range is too wide for a slider, and these are values you set once and want to type exactly,
rather than hit with a step.

### Interactive previews

Under the balance sliders runs a line with a **live-computed example** (e.g. "Full light
armour, skills 100 → 13 pts") instead of static text in the description. It works because
writing a value redraws the entire settings group (`menu.lua:361-371`), so the renderer
recomputes the example on every movement of the slider.

Two constraints shaped this solution:

- **A setting's `argument` ends up in storage**, so it cannot contain functions. The preview
  scenario is therefore named by a string key, and the functions live in `slider.lua`.
- **MENU scripts do not get `openmw.types`** (`luabindings.cpp`, `initMenuPackages`), hence
  `formula.lua` having no engine dependencies.

The previews use **the same code path as the game** (`formula.preview`), and the tests check
that a preview scenario produces the same result as a plain calculation on the same setup.

### When the bonus is recalculated

Never per frame — `onUpdate` only compares timestamps.

⚠ **We measure REAL time (`core.getRealTime()`), not `dt`.** Equipment changes while the
inventory window is open, and that window **pauses the game** — `onUpdate` then gets `dt = 0`,
so a `dt`-based throttle would stall at exactly the moment it is needed. Symptom: the value on
the Inventory Extender bar would not budge until you closed the inventory.

| Trigger | Player | NPC |
|---|---|---|
| Full recalculation — **configurable** | 1 s | 10 s |
| Equipment check — **derived** as ⅕ of the above | 0.2 s | 2 s |
| `onInit`, `onActive` (entering the active zone, loading a save) | always | always |
| A setting changed | immediately (player) | at the next recalculation |

The equipment-check interval **is not a setting**. Separating it from the full recalculation
only pays off with a long `refreshInterval`; at the default one second it would buy 0.8 s of
responsiveness at the price of two more sliders and of having to understand the difference
between two kinds of refresh.

**`Periodic updates for NPCs` = off** disables both intervals for NPCs: only `onInit` and
`onActive` remain, i.e. **zero per-frame work** in crowded places. NPC skills are static, so
the only thing lost is reacting to armour swapped mid-fight.

The intervals are not read from storage every frame — that would cost more than the work they
are limiting. They sit in a cache refreshed on every full recalculation and, for the player,
also immediately after a slider changes (a subscription to all three sections).

The engine has **no** handler for equipping or unequipping an item — the `EngineHandlerList` in
`localscripts.hpp` is `onActive` / `onInactive` / `onConsume` / `onActivated` / `onTeleported`
and nothing else. Hence the polling, but it is cheap: one `getEquipment` and nine identifiers
joined into a signature. A full recalculation only fires once the signature changes, and the
ability is only reapplied once the point total itself changes.

### Why spells rather than `activeEffects:modify()`

`modify()` writes a **permanent** magnitude change into the save and requires its own
bookkeeping in `onSave`/`onLoad`. That is exactly how the runaway Strength bug in Slay's
Assassin Mark came about: `onSave` stored zero and the modifier accumulated without end. An
ability takes its effect with it when removed and needs no bookkeeping — all that is left is
remembering which one is applied, so that loading a save does not add a second.

The spell records are created at runtime via `world.createRecord`, one per possible magnitude.
No ESP, no config regeneration.

## Uninstalling

Records created at runtime stay in the save, so **remove the ability before removing the mod**:
set `Maximum Sanctuary` to `0`, wait a moment (the player refreshes once a second), save the
game, and only then delete the `data=` and `content=` lines.

## Checking it in game

⚠ **The console prepends `return` by itself** (`omw/console/local.lua`,
`util.loadCode('return ' .. code)`). Your own `return` yields `return return ...`, a syntax
error — the console then quietly runs the code through a fallback path and **discards the
result**. Symptom: no output whatsoever, not even an error. Type the bare expression.
`require` is unnecessary too — the console environment already has `I`, `types`, `self`, `core`
and `view` as globals.

**Player** — console, `luap`:

```
I.SanctuaryFromUnarmored.getBonus()
types.Actor.activeEffects(self):getEffect('sanctuary').magnitude
view(I.SanctuaryFromUnarmored.getBreakdown(), 3)
```

**NPC** — click them in the console, then `luas` (local context on the selected object). The
same commands work: `openmw.interfaces` is one table per object shared by all of its scripts
(`components/lua/scriptscontainer.cpp:44-45`), so the console script sees our interface. The
spell list will confirm the applied ability as well:

```
for _, s in pairs(types.Actor.spells(self)) do print(s.id) end
```

**Who to pick:** clothing is **not armour**, so an NPC in robes has all nine slots bare and
gets the full bonus — a mage, a commoner, a beggar. An armoured NPC will give zero and prove
nothing. For the duration of the test it is worth raising `NPC share` to 100% and dropping
`Skill threshold` to 0.

⚠ In a combat test, hit a target that is **conscious and standing**: Sanctuary is skipped
entirely when the victim is knocked down, paralysed or unconscious (a sneak attack).

## Tests

`formula.lua` is a pure function and can be exercised outside the game:

```bash
cd tests && python runtest.py
```

Requires `lupa` (a real Lua interpreter inside Python). No stubs whatsoever — `formula.lua` has
no engine dependencies, so the **original** file of the mod is what gets executed. 27 cases:
the curve, full armour sets, single slots, `useArmorSkill` in both modes, the preview scenarios
and the agreement between a preview and a plain calculation.

A second validator checks the l10n against the settings definitions:

```bash
cd tests && python check_l10n.py
```

Requires `pyyaml`. It guards four things, each of which has already caught something: YAML
validity (an unquoted colon in a description breaks the **whole** file, and with it the options
page), a complete set of keys for settings and groups, the absence of orphaned keys, and
placeholder syntax — ICU uses `{name}`, whereas `%{name}` renders literally as `%32`.

## Credits and licence

Released under the [MIT licence](LICENSE) — patches, forks and redistribution are all fine,
just keep the copyright notice. Bug reports and pull requests are welcome at
<https://github.com/Grobarch/SanctuaryFromUnarmored>.

Thanks to the authors of the mods that set the reference point for the numbers here —
*Unarmored Dodge* by RogiVagel ([#51332](https://www.nexusmods.com/morrowind/mods/51332)) and
*Unarmored Makes You Dodge* by Seneb-Nelldrak
([#55758](https://www.nexusmods.com/morrowind/mods/55758)) — and to the OpenMW team, whose move
of combat into Lua made an approach that needs no game-setting edits possible in the first
place. No code is shared with either mod; this is an independent implementation.
