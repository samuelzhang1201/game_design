class_name DefeatSystem
extends RefCounted
## What a lost town costs the crown (spec docs/superpowers/specs/2026-10-07-
## enemy-ai-and-battle-design.md §6) — never a Game Over: the campaign plays on.
## SiegeSystem.capture calls on_town_lost once the town's manors have moved.
##
##  1. the treasury: battle_defeat_treasury_permille of a POSITIVE treasury,
##     whole gold rounded down (treasury x permille / 1000), one ledger line
##     (WorldLedger.apply, source "defeat", reason "lost <town> to <host>");
##     an empty or indebted treasury loses nothing more, and a share of a
##     positive one never makes it negative;
##  2. the people: battle_defeat_morale points of metrics.peasant_contentment
##     (WorldLedger, clamped by the schema, reason "−N: lost <town> to the
##     raiders");
##  3. the council: each seat's opinion moves by
##     −round(battle_defeat_opinion x (1 + OpinionDrift.weight(BATTLE_LOST, seat)))
##     — the existing drift weight (ideology alignment x policy_sensitivity x
##     (1 − pragmatism)) of the BATTLE_LOST signature (data/action_signatures.csv),
##     so a seat that prizes arms and reach takes it harder; never a gain;
##     reason in OpinionDrift's form "lost <town> to the raiders (opposes, <axis>)";
##  4. the beat: the fixed-prose chapter beat EVENT_ID is scheduled for the
##     next roll (event_state.scheduled, as a chain's `schedule:` op does),
##     unless one already waits there.
##
## Once per loss: GameState.town_losses keeps {town, host, day}; the same key
## again does nothing. Taking the town back (liberation) calls nothing here, so
## nothing is refunded. Whole numbers but the drift weight, no random number.

const EVENT_ID := "war_01"
const SIGNATURE := "BATTLE_LOST"
const SOURCE := "defeat"


## The loss of `town_code` to `host_code` today: the four costs above. Returns
## [] for a loss already paid, else one event {kind "defeat_town_lost", town,
## host, day, gold (taken from the treasury), morale (points taken), opinion
## [{character_id, delta, reason}], event_id (the beat scheduled, "" if one
## already waited)}.
static func on_town_lost(repo: DataRepository, state: GameState, town_code: String, host_code: String) -> Array:
	var day := state.absolute_day()
	for l: Dictionary in state.town_losses:
		if String(l["town"]) == town_code and String(l["host"]) == host_code and int(l["day"]) == day:
			return []
	state.town_losses.append({"town": town_code, "host": host_code, "day": day})
	var label := String((repo.burgs.get(town_code, {}) as Dictionary).get("label", town_code))
	return [{"kind": "defeat_town_lost", "town": town_code, "host": host_code, "day": state.absolute_day(),
		"gold": _treasury(repo, state, label, host_code),
		"morale": _morale(repo, state, label),
		"opinion": _council(repo, state, label),
		"event_id": _schedule(state)}]


## The gold a loss takes from `treasury`: permille of it, rounded down; 0 for
## an empty or indebted treasury.
static func treasury_loss(treasury: int, permille: int) -> int:
	if treasury <= 0 or permille <= 0:
		return 0
	@warning_ignore("integer_division")  # whole gold, rounded down
	return treasury * mini(permille, 1000) / 1000


## One seat's blow: −round(base x (1 + weight)), weight in −1..1, so 0..−2 x base.
static func opinion_loss(base: int, w: float) -> int:
	return -roundi(float(base) * (1.0 + clampf(w, -1.0, 1.0)))


## --- inside ------------------------------------------------------------------

static func _treasury(repo: DataRepository, state: GameState, label: String, host_code: String) -> int:
	var gold := treasury_loss(int(state.metrics.get("treasury", 0)), int(repo.bal("battle_defeat_treasury_permille")))
	if gold <= 0:
		return 0
	var out := WorldLedger.apply(repo, state, "metrics.treasury", -float(gold),
		"lost %s to %s" % [label, SiegeSystem.host_label(repo, host_code)], SOURCE)
	return 0 if out.has("error") else -int(float(out["delta"]))


static func _morale(repo: DataRepository, state: GameState, label: String) -> int:
	var points := int(repo.bal("battle_defeat_morale"))
	if points <= 0:
		return 0
	var out := WorldLedger.apply(repo, state, "metrics.peasant_contentment", -float(points),
		"−%d: lost %s to the raiders" % [points, label], SOURCE)
	return 0 if out.has("error") else -int(float(out["delta"]))


static func _council(repo: DataRepository, state: GameState, label: String) -> Array:
	var out: Array = []
	var sig := OpinionDrift.signature_for(repo, SIGNATURE, {})
	var base := int(repo.bal("battle_defeat_opinion"))
	var what := "lost %s to the raiders" % label
	var seats: Array = state.council.keys()
	seats.sort()
	for seat: String in seats:
		var id := String(state.council[seat])
		var c: Character = state.characters.get(id)
		if c == null:
			continue
		var delta := opinion_loss(base, OpinionDrift.weight(sig, c) if not sig.is_empty() else 0.0)
		if delta == 0:
			continue
		var axis := OpinionDrift.dominant_axis(sig, c.ideology) if not sig.is_empty() else "the realm"
		var reason := "%s (opposes, %s)" % [what, axis]
		c.change_opinion(delta, reason, state.tick)
		out.append({"character_id": id, "delta": delta, "reason": reason})
	return out


static func _schedule(state: GameState) -> String:
	for sc: Dictionary in state.event_state["scheduled"]:
		if String(sc["event_id"]) == EVENT_ID:
			return ""
	state.event_state["scheduled"].append({"event_id": EVENT_ID, "due_tick": state.tick})
	return EVENT_ID
