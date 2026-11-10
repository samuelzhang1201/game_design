class_name BodyBattle
extends RefCounted
## Explicit detached contact enrollment. Ordinary daily dispatch remains unchanged.

static func _result(status: String, reason: String, candidate: GameState = null, plan: Dictionary = {}) -> Dictionary:
	return BodyBattleMotion._result(status, reason, candidate, plan)

static func _request_ok(request: Dictionary) -> bool:
	if request.get("kind") == "contacts": return BodyMotion._keys(request, ["kind"])
	if request.get("kind") == "merge":
		return BodyMotion._keys(request, ["kind", "first_id", "second_id"]) \
			and DayResolution._body_decimal(request.first_id) and request.first_id != "0" \
			and DayResolution._body_decimal(request.second_id) and int(request.first_id) < int(request.second_id)
	if request.get("kind") in ["end", "cancel"]:
		return BodyMotion._keys(request, ["kind", "battle_id", "reason"]) \
			and DayResolution._body_decimal(request.battle_id) and request.battle_id != "0" \
			and request.reason is String and not request.reason.strip_edges().is_empty()
	if request.get("kind") == "withdraw":
		return BodyMotion._keys(request, ["kind", "unit", "battle_id", "reason"]) \
			and request.unit is String and not request.unit.is_empty() \
			and DayResolution._body_decimal(request.battle_id) and request.battle_id != "0" \
			and request.reason is String and not request.reason.strip_edges().is_empty()
	return BodyMotion._keys(request, ["kind", "unit", "battle_id", "side"]) \
		and request.kind == "enter" and request.unit is String and not request.unit.is_empty() \
		and DayResolution._body_decimal(request.battle_id) and request.battle_id != "0" \
		and request.side in ["att", "def"]

static func _contact_boundary_ok(boundary: Dictionary) -> bool:
	if boundary.get("stage") != "contact": return false
	var move := boundary.duplicate(true)
	move.stage = "move"
	return BodyMotion._battle_boundary_ok(move)

static func _operation_boundary_ok(request: Dictionary, boundary: Dictionary) -> bool:
	if request.get("kind") not in ["withdraw", "end", "cancel"]: return _contact_boundary_ok(boundary)
	if boundary.get("stage") != "advance": return false
	var move := boundary.duplicate(true)
	move.stage = "move"
	return BodyMotion._battle_boundary_ok(move)

static func _contacts_ok(contacts: Array) -> bool:
	var previous: Array = []
	for pair: Variant in contacts:
		if not pair is Dictionary or not BodyMotion._keys(pair, ["unit", "slot", "target_unit", "target_slot", "count", "target_count", "kind", "reason"]): return false
		for field: String in ["unit", "target_unit", "reason"]:
			if not pair[field] is String or pair[field].is_empty(): return false
		if pair.kind != "melee": return false
		for field: String in ["slot", "target_slot", "count", "target_count"]:
			if not BodyMotion._loco_integer(pair[field]) or pair[field] < (1 if field in ["count", "target_count"] else 0): return false
		var identity: Array = [pair.unit, pair.slot, pair.target_unit, pair.target_slot]
		if not previous.is_empty() and not UnitBodies._battle_pair_less(previous, identity): return false
		previous = identity
	return true

static func _plan_ok(plan: Dictionary) -> bool:
	return BodyMotion._keys(plan, ["version", "request", "boundary", "basis", "motion", "contacts"]) \
		and BodyMotion._loco_integer(plan.version) and plan.version == 1 \
		and plan.request is Dictionary and _request_ok(plan.request) and plan.boundary is Dictionary and _operation_boundary_ok(plan.request, plan.boundary) \
		and plan.basis is Dictionary and BodyMotion._keys(plan.basis, ["source"]) \
		and plan.basis.source is String and BodyMotion._digest(plan.basis.source) \
		and plan.motion is Dictionary and plan.motion.is_empty() and plan.contacts is Array and _contacts_ok(plan.contacts) \
		and (plan.request.kind in ["contacts", "merge"] or plan.contacts.is_empty())

# Private stages retain the consumed receipt/cursor; only the final publisher consumes an operation.
static func _seal_private(repo: DataRepository, state: GameState) -> void:
	if state.military_migration.has("body_battle"):
		state.military_migration.body_battle.result = UnitBodies._battle_result_hash(repo, state)

static func _transfer(repo: DataRepository, state: GameState, unit: String, battle_id: int,
		side: String, boundary: Dictionary) -> Dictionary:
	_seal_private(repo, state)
	return UnitBodies.transfer_battle_candidate(repo, state, unit, 0, battle_id, side, boundary)

static func _pairs(repo: DataRepository, state: GameState, battle: Dictionary,
		unit: String, enemies: Array, boundary: Dictionary) -> Dictionary:
	_seal_private(repo, state)
	enemies.sort()
	return BodyBattleContact.query_candidate(repo, state, int(battle.id), unit, enemies, boundary)

static func _join(repo: DataRepository, source: GameState, unit: String, battle_id: int,
		side: String, boundary: Dictionary) -> Dictionary:
	var battle := UnitBodies._battle(source, battle_id)
	if battle.is_empty() or BattleSystem.canonical(source, battle_id) != battle_id \
		or UnitBodies._entry(source, unit).is_empty() or UnitBodies._naval(source, unit) \
		or not BattleSystem.battle_of(source, unit).is_empty() or BattleSystem._side_for(source, battle, unit) != side:
		return _result("error", "Invalid canonical enrollment or allegiance")
	if battle[side].size() >= int(repo.bal("battle_max_units")): return _result("deferred", "Battle side is full")
	var staged := UnitBodies._copy(source)
	var dst := UnitBodies._battle(staged, battle_id)
	BattleRules.freeze(repo, staged, dst)
	if dst.has("parley") and unit not in dst.parley.parties[side]: dst.parley.parties[side].append(unit)
	var transferred := _transfer(repo, staged, unit, battle_id, side, boundary)
	if transferred.status != "complete": return _result(transferred.status, transferred.reason)
	staged = transferred.candidate
	dst = UnitBodies._battle(staged, battle_id)
	var other: String = "def" if side == "att" else "att"
	var query := _pairs(repo, staged, dst, unit, dst[other].duplicate(), boundary)
	if query.status != "complete": return _result("error", query.reason)
	# Either side may lawfully initiate; a protected entrant does not gain outgoing attack.
	var contacts: Array = query.pairs.duplicate(true)
	for enemy: String in dst[other]:
		query = _pairs(repo, staged, dst, enemy, [unit], boundary)
		if query.status != "complete": return _result("error", query.reason)
		contacts.append_array(query.pairs)
	if contacts.is_empty(): return _result("deferred", "No lawful physical contact for enrollment")
	BattleReport.enroll(staged, dst, unit, side)
	if not dst.has("event_reinforcements"): dst.event_reinforcements = []
	dst.event_reinforcements.append(unit)
	if not dst.has("reinforcement_evidence"): dst.reinforcement_evidence = []
	dst.reinforcement_evidence.append({"unit": unit, "side": side, "day": staged.absolute_day(),
		"reason": "This regiment physically joined the existing battle."})
	BattleSystem._halt(staged, unit)
	staged.day_resolution.journal.battles.append({"kind": "join", "battle_id": battle_id, "code": unit, "side": side})
	return _result("complete", "Staged exact reinforcement", staged, {"contacts": contacts})

static func _start(repo: DataRepository, source: GameState, player: String, enemy: String,
		boundary: Dictionary) -> Dictionary:
	if not BodyMotion._loco_integer(source.foe_next_id) or source.foe_next_id < 0 \
		or source.foe_next_id >= BodyMotion.JSON_INTEGER_MAX: return _result("error", "Invalid next encounter ID")
	var staged := UnitBodies._copy(source)
	var town := BattleSystem.town_contact(repo, staged, ArmyGround.garrison_town(repo, staged, player), enemy)
	var besieged := BattleSystem.siege_town_of(repo, staged, enemy)
	if not besieged.is_empty() and ArmyGround.garrison_town(repo, staged, player) == besieged:
		return _result("deferred", "Besieged garrison waits for the assault")
	var at_town := BattleSystem._battle_at(staged, town) if not town.is_empty() else {}
	if not at_town.is_empty():
		var contacts: Array = []
		for unit: String in [enemy, player]:
			var joined := _join(repo, staged, unit, int(at_town.id), BattleSystem._side_for(staged, at_town, unit), boundary)
			if joined.status != "complete": return joined
			staged = joined.candidate
			at_town = UnitBodies._battle(staged, int(at_town.id))
			contacts.append_array(joined.plan.contacts)
		return _result("complete", "Joined the existing town battle", staged, {"contacts": contacts})
	var skeleton := BattleSystem.contact_skeleton_candidate(repo, staged, player, enemy, town)
	if town.is_empty():
		var defender := UnitBodies._entry(staged, skeleton.def[0])
		skeleton.place_x_m = int(defender.x_m)
		skeleton.place_y_m = int(defender.y_m)
	var sides := {player: BattleRules.side_of(skeleton, player), enemy: BattleRules.side_of(skeleton, enemy)}
	var battle_id: int = skeleton.id
	var founders: Array = [skeleton.att[0], skeleton.def[0]]
	if not UnitBodies._battle(staged, battle_id).is_empty() or staged.battle_aliases.has(str(battle_id)):
		return _result("error", "Encounter ID is already used")
	skeleton.att = []
	skeleton.def = []
	skeleton.groups = {}
	skeleton.body_version = 1
	skeleton.group_size_version = 2
	skeleton.group_size_men = int(repo.bal("battle_group_size"))
	staged.battles.append(skeleton)
	for unit: String in founders:
		var transfer := _transfer(repo, staged, unit, battle_id, sides[unit], boundary)
		if transfer.status != "complete": return _result(transfer.status, transfer.reason)
		staged = transfer.candidate
	var battle := UnitBodies._battle(staged, battle_id)
	var contacts: Array = []
	for unit: String in [player, enemy]:
		var query := _pairs(repo, staged, battle, unit, [enemy if unit == player else player], boundary)
		if query.status != "complete": return _result("error", query.reason)
		contacts.append_array(query.pairs)
	if contacts.is_empty(): return _result("deferred", "No lawful physical founder contact")
	BattleSystem._contact_doctrine(repo, staged, battle)
	staged.foe_next_id = battle_id
	for unit: String in [player, enemy]:
		BattleReport.enroll(staged, battle, unit, sides[unit])
		if not bool(UnitBodies._entry(staged, unit).get("battle_retreat", false)): BattleSystem._halt(staged, unit)
	staged.day_resolution.journal.battles.append({"kind": "start", "battle_id": battle_id,
		"att": battle.att.duplicate(), "def": battle.def.duplicate(), "town": town,
		"place_x_m": battle.place_x_m, "place_y_m": battle.place_y_m})
	return _result("complete", "Staged exact founders", staged, {"contacts": contacts, "new_id": battle_id})

## Lawful physical cross-field contact, both directions, on private staging.
static func _cross_pairs(repo: DataRepository, state: GameState, a: Dictionary, b: Dictionary,
		boundary: Dictionary) -> Dictionary:
	var contacts: Array = []
	for pair: Array in [[a, b], [b, a]]:
		for unit: String in BattleMerge._units(pair[0]):
			var enemies: Array = BattleMerge._units(pair[1]).filter(func(code: String) -> bool:
				return ArmySystem._body_enemies(repo, state, unit, code))
			if enemies.is_empty(): continue
			var query := _pairs(repo, state, pair[0], unit, enemies, boundary)
			if query.status != "complete": return _result("error", query.reason)
			contacts.append_array(query.pairs)
	return _result("complete", "Cross-field contacts", null, {"contacts": contacts})

## Field union: every absorbed store transfers by allegiance before the absorbed field is deleted.
static func _merge(repo: DataRepository, source: GameState, first_id: int, second_id: int,
		boundary: Dictionary) -> Dictionary:
	var a := UnitBodies._battle(source, first_id)
	var b := UnitBodies._battle(source, second_id)
	if a.is_empty() or b.is_empty() or first_id == second_id or BattleSystem.canonical(source, first_id) != first_id \
		or BattleSystem.canonical(source, second_id) != second_id: return _result("error", "Merge requires two canonical live fields")
	if String(a.get("town", "")) != "" and String(b.get("town", "")) != "": return _result("deferred", "Two town battles never merge")
	for battle: Dictionary in [a, b]:
		if not battle.get("pending_round", {}).is_empty() or battle.has("body_round"): return _result("deferred", "A pending round cannot merge")
		for side: String in BattleSystem.SIDES:
			if battle[side].is_empty(): return _result("deferred", "A field with an empty side cannot merge")
	if not BattleMerge._compatible(repo, source, a, b): return _result("deferred", "Incompatible allegiance union")
	var probe := UnitBodies._copy(source)
	var cross := _cross_pairs(repo, probe, UnitBodies._battle(probe, first_id), UnitBodies._battle(probe, second_id), boundary)
	if cross.status != "complete": return cross
	if cross.plan.contacts.is_empty():
		for battle: Dictionary in [a, b]:
			for unit: String in BattleMerge._units(battle):
				if BattleRanged.share(repo, source, unit) > 0 and BattleSystem.unit_action(repo, source, battle, unit).kind == "attack":
					return _result("deferred", "direct_fire_dependency")
		return _result("deferred", "No lawful physical cross-field contact")
	var staged := UnitBodies._copy(source)
	var sid := int(BattleMerge.survivor_of(a, b).id)
	var gid := first_id if sid == second_id else second_id
	var survivor := UnitBodies._battle(staged, sid)
	var gone := UnitBodies._battle(staged, gid)
	# Parties freeze from the members before any membership moves.
	BattleRules.ensure_parties(survivor)
	BattleRules.ensure_parties(gone)
	var side_map := BattleMerge.side_map_of(staged, survivor, gone)
	var moved := {}
	for side: String in BattleSystem.SIDES:
		for code: String in gone[side].duplicate():
			_seal_private(repo, staged)
			var transferred := UnitBodies.transfer_battle_candidate(repo, staged, code, gid, sid, side_map.get(side, ""), boundary)
			if transferred.status != "complete": return _result(transferred.status, transferred.reason)
			staged = transferred.candidate
			moved[code] = side
	survivor = UnitBodies._battle(staged, sid)
	gone = UnitBodies._battle(staged, gid)
	var event := BattleMerge.absorb(repo, staged, survivor, gone, side_map, moved)
	BattleReport.note(survivor, [event])
	staged.day_resolution.journal.battles.append(event.duplicate(true))
	return _result("complete", "Staged exact field union", staged, cross.plan)

static func _metadata_error(source: GameState) -> String:
	for code: String in source.regiments.keys() + source.foes.keys():
		if UnitBodies._naval(source, code): continue
		var entry := UnitBodies._entry(source, code)
		if not BodyMotion._loco_point([entry.get("x_m"), entry.get("y_m")]): return "Invalid raw encounter anchor"
		for field: String in ["facing_deg", "group_facing", "halt_day"]:
			if entry.has(field) and not BodyMotion._loco_integer(entry[field]): return "Invalid raw encounter metadata: " + field
	for battle: Dictionary in source.battles:
		if not UnitBodies._live(battle): continue
		if not BodyMotion._loco_integer(battle.get("last_resolved_day", -1)): return "Invalid raw resolved day"
		for facing: Variant in battle.get("group_facing", {}).values():
			if not BodyMotion._loco_integer(facing): return "Invalid raw body facing snapshot"
	return ""

static func _withdraw(repo: DataRepository, source: GameState, request: Dictionary, boundary: Dictionary) -> Dictionary:
	var battle := BattleSystem.battle_of(source, request.unit)
	if battle.is_empty() or int(battle.id) != int(request.battle_id) or BattleSystem.canonical(source, int(battle.id)) != int(battle.id):
		return _result("error", "Withdrawal requires its canonical sole owner")
	var route := BattleSystem._retreat_route_candidate(repo, source, int(battle.id), request.unit)
	if route.candidate == null: return _result("deferred", route.reason)
	var candidate: GameState = route.candidate
	battle = BattleSystem.battle_of(candidate, request.unit)
	var side := BattleRules.side_of(battle, request.unit)
	if not BattleSystem._separated(repo, candidate, request.unit, battle["def" if side == "att" else "att"]):
		return _result("deferred", "Withdrawal remains exposed inside actual encounter reach")
	_seal_private(repo, candidate)
	var transferred := UnitBodies.transfer_battle_candidate(repo, candidate, request.unit, int(battle.id), 0, "", boundary)
	if transferred.status != "complete": return _result(transferred.status, transferred.reason)
	candidate = transferred.candidate
	battle = UnitBodies._battle(candidate, int(request.battle_id))
	BattleReport.leave(candidate, battle, request.unit)
	var entry := UnitBodies._entry(candidate, request.unit)
	var cause: String = entry.get("withdrawal_cause", "retreat")
	entry.erase("battle_retreat")
	entry.erase("withdrawal_cause")
	entry.erase("withdrawal_reason")
	candidate.day_resolution.journal.battles.append({"kind": "withdrawal", "battle_id": int(request.battle_id),
		"code": request.unit, "side": side, "why": cause, "reason": request.reason})
	return _result("complete", "Staged exact separated withdrawal", candidate)

## Terminal release: every extant store transfers to owner zero before the report and deletion.
static func _terminate(repo: DataRepository, source: GameState, request: Dictionary, boundary: Dictionary) -> Dictionary:
	var id := int(request.battle_id)
	var battle := UnitBodies._battle(source, id)
	if battle.is_empty() or BattleSystem.canonical(source, id) != id: return _result("error", "Terminal release requires a canonical live field")
	var why := "called_off"
	if request.kind == "end":
		if not battle.att.is_empty() and not battle.def.is_empty(): return _result("deferred", "The battle has not ended")
		why = ("rout_" + ("attacker" if battle.routed_side == "att" else "defender")) if battle.has("routed_side") else "emptied"
	var staged := UnitBodies._copy(source)
	var members := {"att": battle.att.duplicate(), "def": battle.def.duplicate()}
	for side: String in BattleSystem.SIDES:
		for code: String in members[side]:
			_seal_private(repo, staged)
			var released := UnitBodies.transfer_battle_candidate(repo, staged, code, id, 0, "", boundary)
			if released.status != "complete": return _result(released.status, released.reason)
			staged = released.candidate
	var events: Array = []
	BattleSystem._end(repo, staged, UnitBodies._battle(staged, id), why, events, [], "", members)
	staged.battles = staged.battles.filter(func(b: Dictionary) -> bool: return int(b.id) != id)
	_unqueue(staged, id)
	var event: Dictionary = events[0].duplicate(true)
	event.reason = request.reason
	staged.day_resolution.journal.battles.append(event)
	return _result("complete", "Staged exact terminal release", staged)

## A deleted field leaves the exhausted advance queue; processed IDs stay as day history.
static func _unqueue(state: GameState, id: int) -> void:
	var tx := state.day_resolution
	var at: int = tx.battle_ids.find(id)
	if at < 0: return
	tx.battle_ids.remove_at(at)
	tx.body_battle.battle_ids.remove_at(at)
	tx.substep_battle_ids.erase(id)
	if at < tx.battle_index: tx.battle_index -= 1
	tx.body_battle.battle_index = str(tx.battle_index)

static func _stage(repo: DataRepository, source: GameState, request: Dictionary, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null or not _request_ok(request): return _result("error", "Unsupported or malformed enrollment request")
	var checked := UnitBodies.validate_battle_candidate(repo, source, boundary)
	if checked.status == "error": return _result("error", checked.reason)
	var metadata_error := _metadata_error(source)
	if not metadata_error.is_empty(): return _result("error", metadata_error)
	var retreat_error := BattleSystem._retreat_candidate_error(source)
	if not retreat_error.is_empty(): return _result("error", retreat_error)
	if checked.status != "complete": return _result(checked.status, checked.reason)
	if boundary.kind != "battle" or not _operation_boundary_ok(request, boundary): return _result("deferred", "Operation waits for its lifecycle stage")
	if not source.day_resolution.pending_decision.is_empty(): return _result("deferred", "Pending decision prevents lifecycle operation")
	if BodyBattleMotion._context(repo, source).is_empty(): return _result("error", "Missing accepted battle context")
	var candidate: GameState = checked.candidate
	if candidate.military_migration.has("body_motion"):
		var closed := BodyMotion.close_battle_locomotion_candidate(repo, candidate, boundary)
		if closed.status != "complete": return _result("error", closed.reason)
		candidate = closed.candidate
	var contacts: Array = []
	var starts: Array = []
	if request.kind in ["end", "cancel"]:
		var ended := _terminate(repo, candidate, request, boundary)
		if ended.status != "complete": return ended
		candidate = ended.candidate
	elif request.kind == "withdraw":
		var exited := _withdraw(repo, candidate, request, boundary)
		if exited.status != "complete": return exited
		candidate = exited.candidate
	elif request.kind == "merge":
		var merged := _merge(repo, candidate, int(request.first_id), int(request.second_id), boundary)
		if merged.status != "complete": return merged
		candidate = merged.candidate
		contacts = merged.plan.contacts
	elif request.kind == "enter":
		var joined := _join(repo, candidate, request.unit, int(request.battle_id), request.side, boundary)
		if joined.status != "complete": return joined
		candidate = joined.candidate
		contacts = []
	else:
		var mine: Array = candidate.regiments.keys()
		var foes: Array = candidate.foes.keys()
		mine.sort()
		foes.sort()
		for enemy: String in foes:
			for player: String in mine:
				if not BattleSystem._can_fight(repo, candidate, player) or not BattleSystem._can_fight(repo, candidate, enemy) \
					or not ArmySystem._body_enemies(repo, candidate, player, enemy): continue
				var own := BattleSystem.battle_of(candidate, player)
				var other := BattleSystem.battle_of(candidate, enemy)
				var result: Dictionary
				if own.is_empty() and other.is_empty():
					result = _start(repo, candidate, player, enemy, boundary)
				elif own.is_empty() or other.is_empty():
					var field: Dictionary = other if own.is_empty() else own
					var unit := player if own.is_empty() else enemy
					result = _join(repo, candidate, unit, int(field.id), BattleSystem._side_for(candidate, field, unit), boundary)
				elif own.id != other.id:
					result = _merge(repo, candidate, mini(int(own.id), int(other.id)), maxi(int(own.id), int(other.id)), boundary)
					if result.status == "deferred" and result.reason == "direct_fire_dependency": return result
				else: continue
				if result.status == "error": return result
				if result.status != "complete": continue
				if result.plan.has("new_id"): starts.append(result.plan.new_id)
				candidate = result.candidate
				contacts.append_array(result.plan.contacts)
		if request.kind == "contacts": _queue(candidate, starts)
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return UnitBodies._battle_pair_less([a.unit, a.slot, a.target_unit, a.target_slot], [b.unit, b.slot, b.target_unit, b.target_slot]))
	var plan := {"version": 1, "request": request.duplicate(true), "boundary": boundary.duplicate(true),
		"basis": {"source": BodyMotion._hash([source.to_dict(), request, boundary, BodyBattleMotion._context(repo, source)])},
		"motion": {}, "contacts": contacts}
	return _result("complete", "Planned physical enrollment", candidate, plan)

static func _queue(state: GameState, starts: Array) -> void:
	var tx := state.day_resolution
	var processed: Array = []
	for id: Variant in tx.processed_battle_ids:
		var canonical := BattleSystem.canonical(state, int(id))
		if canonical not in processed: processed.append(canonical)
	var queue: Array = []
	for battle: Dictionary in state.battles:
		if not UnitBodies._live(battle): continue
		var done: bool = int(battle.id) in processed or int(battle.get("last_resolved_day", -1)) == state.absolute_day()
		for code: String in battle.att + battle.def:
			if code in tx.body_battle.processed_units: done = true
		if done:
			if battle.id not in processed: processed.append(int(battle.id))
		else: queue.append(int(battle.id))
	processed.sort()
	queue.sort()
	tx.processed_battle_ids = processed
	tx.battle_ids = queue
	tx.battle_index = 0
	tx.battle_step = "fighting"
	tx.substep_battle_ids = starts.filter(func(id: int) -> bool: return id in queue)
	tx.substep_battle_ids.sort()
	tx.body_battle.battle_ids = queue.map(func(id: int) -> String: return str(id))
	tx.body_battle.battle_index = "0"
	tx.body_battle.stage = "round" if not queue.is_empty() else "advance"

static func plan_candidate(repo: DataRepository, source: GameState, request: Dictionary, boundary: Dictionary) -> Dictionary:
	var staged := _stage(repo, source, request, boundary)
	if staged.status != "complete": return staged
	return _result("complete", staged.reason, null, staged.plan)

static func commit_candidate(repo: DataRepository, source: GameState, proposed: Dictionary, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null or not _plan_ok(proposed) or BodyMotion._hash(proposed.boundary) != BodyMotion._hash(boundary):
		return _result("error", "Invalid enrollment plan/boundary")
	if not source.day_resolution.get("body_battle") is Dictionary: return _result("error", "Enrollment replay requires its saved day")
	var raw_error := UnitBodies._battle_raw_error(source)
	if not raw_error.is_empty(): return _result("error", raw_error)
	var receipt := BodyMotion._hash(proposed)
	var outer: Variant = source.military_migration.get("body_battle", {})
	if outer is Dictionary and outer.get("sequence") == boundary.get("sequence"):
		var checked := UnitBodies.validate_battle_candidate(repo, source, BodyBattleMotion._boundary(source))
		if checked.status != "complete" or not _metadata_error(source).is_empty() or outer.receipt != receipt \
			or boundary.abs_day != str(source.absolute_day()) \
			or boundary.substep != source.day_resolution.body_battle.next_substep \
			or source.day_resolution.body_battle.stage not in (["round", "advance"] if proposed.request.kind == "contacts" else (["advance"] if proposed.request.kind in ["withdraw", "end", "cancel"] else ["contact"])):
			return _result("error", "Invalid/stale enrollment replay")
		return _result("complete", "Already committed enrollment", checked.candidate, BodyMotion._canonical(proposed))
	var staged := _stage(repo, source, proposed.request, boundary)
	if staged.status != "complete": return staged
	if BodyMotion._hash(staged.plan) != receipt: return _result("error", "Stale or modified enrollment plan")
	var candidate: GameState = staged.candidate
	candidate.day_resolution.body_battle.sequence = str(int(boundary.sequence) + 1)
	candidate.military_migration.body_battle = {"version": "1", "sequence": boundary.sequence,
		"receipt": receipt, "result": "", "closed_motion": candidate.military_migration.get("body_battle", {}).get("closed_motion", {}).duplicate(true)}
	candidate.military_migration.body_battle.result = UnitBodies._battle_result_hash(repo, candidate)
	var final := UnitBodies.validate_battle_candidate(repo, candidate, BodyBattleMotion._boundary(candidate))
	if final.status != "complete": return _result("error", final.reason)
	return _result("complete", "Committed exact body enrollment", final.candidate, staged.plan)
