# Chapter 0 — Beats the war fires

Status: Built — the entry below is live (`data/story/chapter_events.csv`, `data/story/chapter_event_choices.csv`, `EventSystem`, `DefeatSystem`). Design: `docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md` §6.

**This file is loaded at runtime.** `StorySource` reads each `### W-NN` heading (id `war_NN`) — the title after the `·` and the prose after the `**Scene:**` label on the Trigger line — and the game shows both verbatim. Keep the headings and the labels intact. The `**Choices:**` line is design description only; the implemented choices are the CSV's.

These are chapter beats like the prologue's (`chapter_0_events.md`): fixed authored prose, never model-written, never sampled by the random roll (`trigger` `never`). They differ in one thing: no choice of the chain schedules them — the ENGINE does, when the war calls for it. `DefeatSystem.on_town_lost` (a siege took a town, `SiegeSystem.capture`) puts `war_01` on the event queue for the next month's roll, one at a time; a prologue beat due the same month goes first (the chain keeps its calendar), and the war beat waits for a month with none. Nothing here names a kingdom: `{raider_realm}` and `{player_realm}` are filled at load.

---

### W-01 · A Town Lost — `chapter · template`
**Trigger:** a siege has taken one of the crown's towns (`DefeatSystem.on_town_lost`); played at the next month's roll. **Scene:** The rider who brings it has not stopped to wash, and the council hears him standing. The town held as long as its walls did; then the gate went, and now {raider_realm}'s banners hang from them and its manors answer to another house. The crown's chest is lighter for it, and in the market squares of every town that still flies {player_realm}'s colours men are asking what the crown means to do. The Marshal has a map open on the table before you are seated. The Steward has a figure, and it is worse than the map. Everyone in the room is waiting to hear whose fault it was.
**Choices:** ① Rally the council — the towns that stand will be held (gold for riders and pay; the Marshal +4; legitimacy +1; a `centralism`/`militarism` signature). ② Blame the Marshal for the fall (the Marshal −12; legitimacy −1; a `centralism` signature against `militarism`).
