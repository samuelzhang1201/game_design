class_name WarPieceSlip
extends RefCounted
## The slip a pointer resting on a WAR ROOM piece raises (owner 2026-10-07:
## 棋子的tooltip显示基本战斗数据): the unit the piece stands for (one piece a
## unit, spec 2026-10-07-army-split-and-ground §5.4; `lines` still lists several
## when given them) with its arm and heads, its defend and attack on the
## ground where it stands now (ArmySystem.power), its readiness and morale, and
## its supplies with the days they last ("Supplies 1,240 (≈ 18 days)") —
## and a supply line broken because its town lies ahead of it, its name in
## rubric (`SupplyLines.slip_words`, owner 2026-10-10). Pure and read-only; only the player's own regiments are pieces.


## One reading per regiment code, in the order given.
static func reading(repo: DataRepository, state: GameState, codes: Array) -> Array:
	var out: Array = []
	for c: Variant in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code, state)
		if reg.is_empty():
			continue
		var st := ArmySystem.state_of(repo, state, code)
		if st.is_empty():
			st = ArmySystem.starting_state(repo, reg)
		var heads := ArmySystem.headcount(repo, reg)
		var supplies := int(st.get("supplies", 0))
		var use := ArmySystem.supply_use(repo, reg, state)
		out.append({"code": code, "label": String(reg.get("label", code)),
			"arm": MapObjects.regiment_arm(repo, reg), "naval": String(reg.get("is_naval", "0")) == "1",
			"heads": heads, "fit": ArmySystem.fit_heads(heads, st),
			"defend": ArmySystem.power(repo, state, code, "defend"),
			"attack": ArmySystem.power(repo, state, code, "attack"),
			"readiness": ArmySystem.bars_of(repo, state, code).x,
			"morale": int(st.get("morale", 0)), "supplies": supplies,
			"days": ArmySystem.days_in_hand(supplies, use) if use > 0 else -1,
			"line_broken": SupplyLines.slip_words(repo, state, code)})
	return out


## The slip's lines (WarHoverSlip's kinds). One regiment: its name, then its
## arm and heads, its fighting figures, its readiness and morale, its stores.
## Several (a garrison): the garrison's name, then each regiment briefly.
static func lines(repo: DataRepository, readings: Array, town := "") -> Array:
	var out: Array = []
	if readings.size() == 1:
		var r: Dictionary = readings[0]
		out.append({"text": String(r["label"]), "kind": "title"})
		out.append({"text": _strength(repo, r), "kind": "sub"})
		out.append({"text": "Defend %s · Attack %s on its ground" % [Intel.num(int(r["defend"])), Intel.num(int(r["attack"]))],
			"kind": "line"})
		out.append({"text": _readiness(r), "kind": "line"})
		out.append({"text": supplies_text(r), "kind": "line"})
		var broken: Dictionary = r.get("line_broken", {})
		if not broken.is_empty():   # its supply town ahead of it (ruling 20 kept daily)
			out.append({"text": String(broken["title"]), "kind": "rubric"})
			out.append({"text": String(broken["text"]), "kind": "line"})
		return out
	var heads := 0
	for r: Dictionary in readings:
		heads += int(r["heads"])
	var where := String((repo.burgs.get(town, {}) as Dictionary).get("label", ""))
	out.append({"text": "Garrison of %s" % where if where != "" else "Garrison", "kind": "title"})
	out.append({"text": "%d regiments · %s men" % [readings.size(), Intel.num(heads)], "kind": "sub"})
	for r: Dictionary in readings:
		out.append({"text": "", "kind": "rule"})
		out.append({"text": String(r["label"]), "kind": "rubric"})
		out.append({"text": "%s · Defend %s · Attack %s" % [_strength(repo, r), Intel.num(int(r["defend"])),
			Intel.num(int(r["attack"]))], "kind": "line"})
		out.append({"text": "%s · %s" % [_readiness(r), supplies_text(r)], "kind": "line"})
		var broken: Dictionary = r.get("line_broken", {})
		if not broken.is_empty():
			out.append({"text": "%s: %s" % [broken["title"], broken["text"]], "kind": "line"})
	return out


## "Supplies 1,240 (≈ 18 days)" (the bracket's spaces unbreakable); a banner that eats nothing, the bare figure.
static func supplies_text(r: Dictionary) -> String:
	var text := "Supplies %s" % Intel.num(int(r["supplies"]))
	var days := int(r["days"])
	if days >= 0:
		text += " (≈\u00a0%d\u00a0day%s)" % [days, "" if days == 1 else "s"]   # never broken apart
	return text


## "Cavalry · 1,600 men (1,550 fit)"; a fleet counts its ships.
static func _strength(repo: DataRepository, r: Dictionary) -> String:
	var arm := String(r["arm"])
	var arm_label := String((repo.resource_icons.get(arm, {}) as Dictionary).get("label", arm.capitalize()))
	var text := "%s · %s %s" % [arm_label, Intel.num(int(r["heads"])), "ships" if bool(r["naval"]) else "men"]
	if int(r["fit"]) < int(r["heads"]):
		text += " (%s fit)" % Intel.num(int(r["fit"]))
	return text


## "Readiness 81% · Morale 75"
static func _readiness(r: Dictionary) -> String:
	@warning_ignore("integer_division")  # whole per cent
	return "Readiness %d%% · Morale %d" % [int(r["readiness"]) / 10, int(r["morale"])]
