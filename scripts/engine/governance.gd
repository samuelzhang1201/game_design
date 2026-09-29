class_name Governance
extends RefCounted
## Who governs a flow and how (spec 2026-09-30-ledger-governors-design §2-3):
## the seat holder unless the flow was given to another councillor; his
## skill sets the ceiling, his opinion of the king how much he gives, his
## traits and integrity whether he skims. Pure; no RNG.


static func flows(repo: DataRepository) -> Array:
	var out: Array = repo.ledger_governance.keys()
	out.sort()
	return out


static func seat_label(repo: DataRepository, flow: String) -> String:
	var seat := String((repo.ledger_governance.get(flow, {}) as Dictionary).get("seat", ""))
	return String((repo.seats.get(seat, {}) as Dictionary).get("label", seat))


static func governor_of(repo: DataRepository, state: GameState, flow: String) -> String:
	var given := String(state.governors.get(flow, ""))
	# A governor given a flow who no longer sits on the council loses it
	# (controller ruling, Task 1 review): falls back to the seat holder,
	# same as a governor who never existed.
	if given != "" and state.characters.has(given) and given in state.council.values():
		return given
	var seat := String((repo.ledger_governance.get(flow, {}) as Dictionary).get("seat", ""))
	return String(state.council.get(seat, ""))


static func skim_of(repo: DataRepository, c: Character) -> int:
	var flags: Array = []
	for t in c.traits:
		flags.append(String((repo.traits.get(String(t), {}) as Dictionary).get("special_flag", "")))
	if "truthful_advice" in flags:
		return 0
	if "skims_treasury" in flags:
		return int(repo.bal("gov_skim_permille"))
	if int(c.attributes.get("integrity", 50)) < int(repo.bal("gov_skim_integrity_below")):
		return int(repo.bal("gov_skim_low_integrity_permille"))
	return 0


static func factors(repo: DataRepository, state: GameState, flow: String) -> Dictionary:
	var row: Dictionary = repo.ledger_governance.get(flow, {})
	var lo := int(row.get("min_permille", 1000))
	var hi := int(row.get("max_permille", 1000))
	var gid := governor_of(repo, state, flow)
	if gid == "":
		return {"governor": "", "skill": 0, "opinion": 0, "efficiency": lo, "skim": 0,
			"reasons": ["no one governs it"]}
	var c: Character = state.characters[gid]
	var skill := int(c.skills.get(String(row["skill"]), 0))
	var by_skill := (skill - int(row["skill_mid"])) * int(row["skill_step_permille"])
	var reasons: Array[String] = ["skill %d: %+d‰" % [skill, by_skill]]
	var eff := int(row["base_permille"]) + by_skill
	var coop := int(repo.bal("gov_opinion_cooperate"))
	if c.opinion < coop:
		var cut := (coop - c.opinion) * int(repo.bal("gov_opinion_step_permille"))
		eff -= cut
		reasons.append("opinion %d: −%d‰" % [c.opinion, cut])
	return {"governor": gid, "skill": skill, "opinion": c.opinion, "efficiency": clampi(eff, lo, hi),
		"skim": skim_of(repo, c), "reasons": reasons}


## A settled month's skim into each governor's own purse (GameState.skims,
## whole gold): every plan row carrying `governor` and `skimmed` (the
## workshops', the supply lines'). Nobody governs "", and a zero skim
## leaves no entry.
static func add_skims(state: GameState, rows: Array) -> void:
	for row: Dictionary in rows:
		var gid := String(row.get("governor", ""))
		var amount := int(row.get("skimmed", 0))
		if gid == "" or amount <= 0:
			continue
		state.skims[gid] = int(state.skims.get(gid, 0)) + amount
