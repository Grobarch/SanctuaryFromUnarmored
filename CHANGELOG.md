# Changelog

All notable changes to Sanctuary From Unarmored.

## 1.0.2

**Fixed: on a new game the bonus was missing until the save was reloaded.**

The ability could not be applied while its spell record did not exist yet. In that case the
actor script asked the global script to create the record and returned, intending to retry on
the next recalculation — but recalculation only ever runs when the actor initialises or
becomes active, and both had already happened. The record was created, and nothing ever looked
at it again.

The window is only open once, at character creation: record creation happens when the player is
added to the world, and that is not ordered against the player script's own initialisation.
On a loaded save the records are already in storage, which is why reloading appeared to fix it.

The actor now subscribes to the storage section holding the record ids, so whoever writes an id
wakes it up. This also covers the cap being raised in another session, and the section being
cleared by hand.

NPCs are deliberately not subscribed — they recalculate when they next become active anyway,
and one subscription per actor would cost far more than the fix is worth.

## 1.0.1

**Fixed: starting a new game logged an error and created no spell records.**

Record creation ran during script initialisation, which happens while the state manager is
still in `State_NoGame`. `world.createRecord` refuses to run that early. Creation was moved to
the point where the player is added to the world, which also covers loading a save — so a cap
raised in another session, or a cleared storage section, is picked up as well.

## 1.0.0

First release, renamed from *Unarmored Dodge*.

- Sanctuary scaled from the Unarmored skill, and to a lesser extent from Light, Medium and
  Heavy Armor.
- Settings page with a configurable cap.
- Removal button that takes the ability off every actor and stops the mod cleanly.
- Stray abilities left behind by an earlier session are cleaned up when an actor becomes
  active, so a bonus cannot outlive a visit.
- No creature support by design: creatures have no real Unarmored skill and gain no vanilla
  armour rating from it, so there is nothing to scale.
