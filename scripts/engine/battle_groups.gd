class_name BattleGroups
extends RefCounted
## P4.4d1: a battle unit's fit personnel as representative groups of at most
## `battle_group_size`, each with a saved whole-metre position laid out by the
## unit's formation around its anchor. Nothing reads them yet (spec §6-§8).


## Group sizes for `n` people: full groups, the last one the remainder.
static func counts(n: int, size := 50) -> Array[int]:
	var out: Array[int] = []
	var left := maxi(0, n)
	while left > 0:
		out.append(mini(size, left))
		left -= size
	return out


## Whole-metre positions of `count` groups around `anchor`. Slot x runs across
## the front, slot y away from the enemy; facing is a WarFront angle (0 = +x,
## y down, degrees), so across = the facing turned +90 degrees and back = -facing.
## Each position is rounded to whole metres once.
static func layout(repo: DataRepository, formation: String, count: int, anchor: Vector2i,
		facing_deg: int) -> Array[Vector2i]:
	var face := WarFront.facing_vector(facing_deg)
	var across := Vector2(-face.y, face.x) * float(repo.bal("battle_group_spacing_m"))
	var back := -face * float(repo.bal("battle_group_depth_m"))
	var out: Array[Vector2i] = []
	for slot: Vector2 in BattleFormation.slots(formation, count):
		out.append(anchor + Vector2i((across * slot.x + back * slot.y).round()))
	return out


## Rebuilds the battle's groups and facings from the units' fit counts and
## anchors (both sides, sorted code order); a unit no longer in it loses its entry.
static func refresh(repo: DataRepository, state: GameState, battle: Dictionary) -> void:
	var groups := {}
	var facing := {}
	var anchors := {}
	for side: String in BattleSystem.SIDES:
		for code: String in battle[side]:
			anchors[code] = BattleSystem._at_m(repo, state, code)
	for side: String in BattleSystem.SIDES:
		var other: Array = battle["def" if side == "att" else "att"]
		var mean := Vector2i.ZERO
		for foe: String in other:
			mean += anchors[foe]
		var codes: Array = (battle[side] as Array).duplicate()
		codes.sort()
		for code: String in codes:
			var anchor: Vector2i = anchors[code]
			var face := 0
			if not other.is_empty():
				@warning_ignore("integer_division")
				face = WarFront.facing_deg(Vector2(mean / other.size() - anchor))
			var sizes := counts(ArmySystem.fit_count(repo, state, code), int(repo.bal("battle_group_size")))
			var at := layout(repo, BattleFormation.of_unit(state, code), sizes.size(), anchor, face)
			var slots := BattleFormation.slots(BattleFormation.of_unit(state, code), sizes.size())
			var front := 0.0
			for slot: Vector2 in slots:
				front = minf(front, slot.y)
			var rows: Array = []
			for i: int in sizes.size():
				rows.append({"count": sizes[i], "role": "front" if is_equal_approx(slots[i].y, front) else "reserve",
					"x_m": at[i].x, "y_m": at[i].y})
			groups[code] = rows
			facing[code] = face
	battle["groups"] = groups
	battle["group_facing"] = facing


## Every unit's target anchor on its side's deployment line (P4.4d2). The axis
## runs from the defenders' mean anchor toward the attackers' (+x when they
## coincide); each line centre is the battle place +- axis * gap / 2 (att on the
## + side); a side's units stand abreast in sorted code order, each as wide as
## its front groups, the side centred. Pure; each target rounded to metres once.
static func deployment(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	var means := {}
	for side: String in BattleSystem.SIDES:
		var sum := Vector2i.ZERO
		for code: String in battle[side]:
			sum += BattleSystem._at_m(repo, state, code)
		var n: int = maxi(1, (battle[side] as Array).size())
		@warning_ignore("integer_division")
		means[side] = sum / n
	var axis := Vector2(means["att"] - means["def"])
	axis = axis.normalized() if axis != Vector2.ZERO else Vector2.RIGHT
	var across := Vector2(-axis.y, axis.x)
	var place := Vector2(int(battle["place_x_m"]), int(battle["place_y_m"]))
	var spacing := float(repo.bal("battle_group_spacing_m"))
	var half_gap := float(repo.bal("battle_line_gap_m")) / 2.0
	var out := {}
	for side: String in BattleSystem.SIDES:
		var centre := place + axis * (half_gap if side == "att" else -half_gap)
		var codes: Array = (battle[side] as Array).duplicate()
		codes.sort()
		var widths := {}
		var total := 0.0
		for code: String in codes:
			var slots := BattleFormation.slots(BattleFormation.of_unit(state, code),
				counts(ArmySystem.fit_count(repo, state, code), int(repo.bal("battle_group_size"))).size())
			var front := 0.0
			for slot: Vector2 in slots:
				front = minf(front, slot.y)
			var n := 0
			for slot: Vector2 in slots:
				n += 1 if is_equal_approx(slot.y, front) else 0
			widths[code] = float(maxi(1, n)) * spacing
			total += float(widths[code])
		var at := -total / 2.0
		for code: String in codes:
			out[code] = Vector2i((centre + across * (at + float(widths[code]) / 2.0)).round())
			at += float(widths[code])
	return out


## True while any side is ordered to retreat or any of its units is withdrawing:
## the battle then goes to separation, so no unit closes the line any more.
static func withdrawing(state: GameState, battle: Dictionary) -> bool:
	for side: String in BattleSystem.SIDES:
		if BattleOrders.kind(battle, side) == "retreat":
			return true
		for code: String in battle[side]:
			var e := BattleSystem._stored(state, code)
			if bool(e.get("battle_retreat", false)) or e.has("disengaging"):
				return true
	return false


## One deployment step, once per absolute day (`battle.deployed_day`): every
## unit but a withdrawing, captured, fitless or town-seated one steps its anchor
## toward its target by at most `battle_deploy_step_m` whole metres. The groups
## are refreshed by the caller.
static func deploy_day(repo: DataRepository, state: GameState, battle: Dictionary) -> void:
	var today := state.absolute_day()
	if int(battle.get("deployed_day", -1)) == today or withdrawing(state, battle):
		return
	battle["deployed_day"] = today
	var targets := deployment(repo, state, battle)
	var step := float(repo.bal("battle_deploy_step_m"))
	for code: String in targets:
		var e := BattleSystem._stored(state, code)
		if e.is_empty() or bool(e.get("captured", false)) or ArmySystem.fit_count(repo, state, code) <= 0 \
				or ArmyGround.seated_in(repo, state, code) != "":
			continue
		var from := BattleSystem._at_m(repo, state, code)
		var to: Vector2i = targets[code]
		var d := Vector2(to - from)
		var moved := to if d.length() <= step else from + Vector2i((d.normalized() * step).round())
		e["x_m"] = moved.x
		e["y_m"] = moved.y
