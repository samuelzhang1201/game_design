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
