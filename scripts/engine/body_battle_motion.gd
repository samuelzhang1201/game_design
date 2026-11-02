class_name BodyBattleMotion
extends RefCounted
## Isolated union transaction. Tactical providers are explicit pure contributions.

static func _result(status: String, reason: String, candidate: GameState = null, plan: Dictionary = {}) -> Dictionary:
	return {"status": status, "reason": reason, "error": reason if status == "error" else "", "candidate": candidate, "plan": plan}

static func _boundary(state: GameState) -> Dictionary:
	var c: Dictionary = state.day_resolution.body_battle
	return {"version": 1, "kind": "battle", "abs_day": c.abs_day, "substep": c.next_substep, "sequence": c.sequence, "stage": c.stage}

static func _context(repo: DataRepository, state: GameState) -> Array:
	var policies := {}
	for code: String in state.regiments.keys() + state.foes.keys():
		if UnitBodies._naval(state, code): continue
		var piece := MapObjects.army_piece(repo, state.army_roster[code])
		var policy := BodyMotion._loco_policy(repo, piece)
		if policy.is_empty(): return []
		policies[piece] = policy
	var grid := MarchPath.of_pack(repo)
	if not BodyMotion._loco_grid_ok(grid): return []
	var context := BodyMotion._loco_context(repo, grid, policies, {})
	context.remove_at(3)
	return context

@warning_ignore("integer_division")
static func _share(daily: int, count: int, slice: int) -> int:
	return daily / count + (1 if slice < daily % count else 0)

static func _source_error(repo: DataRepository, source: GameState, boundary: Dictionary) -> String:
	var checked := UnitBodies.validate_battle_candidate(repo, source, boundary)
	if checked.status != "complete": return checked.reason
	if not BodyMotion._battle_boundary_ok(boundary): return "Movement requires the explicit move stage"
	if source.military_migration.has("body_motion"): return "Previous movement requires explicit closure"
	var tx := source.day_resolution
	var codes: Array = source.regiments.keys() + source.foes.keys()
	var land: Array = []
	for code: String in codes:
		if UnitBodies._naval(source, code): continue
		land.append(code)
		if not ArmySystem._body_entry_ok(ArmySystem._entry_of(source, code)): return "Invalid current entry: " + code
		if not BodyMotion._loco_integer(tx.march_budgets.get(code)) or tx.march_budgets[code] < 0 or tx.march_budgets[code] > BodyMotion.LOCAL_LIMIT:
			return "Missing/invalid frozen daily budget: " + code
		if tx.march_entries.has(code) and (not tx.march_entries[code] is Dictionary or not ArmySystem._body_entry_ok(tx.march_entries[code])):
			return "Invalid frozen received route: " + code
		var ledger: Variant = source.unit_tasks.get(code, {})
		if not ledger is Dictionary or not ledger.get("orders", {}) is Dictionary or not ledger.get("current_id", "") is String: return "Invalid task ledger"
		var id: String = ledger.get("current_id", "")
		if not id.is_empty():
			var task: Variant = ledger.orders.get(id)
			if not task is Dictionary or not task.get("request") is Dictionary or not task.get("status") is String: return "Missing received task"
			var request: Dictionary = task.request
			if not BodyMotion._keys(request, ["id", "unit", "battle_id", "task", "formation", "target_unit", "source", "issuer", "max_route_m", "region"]): return "Incomplete received task"
			for key: String in ["id", "unit", "task", "formation", "target_unit", "source", "issuer", "region"]:
				if not request[key] is String: return "Invalid received task text"
			for key: String in ["battle_id", "max_route_m"]:
				if not BodyMotion._loco_integer(request[key]) or request[key] < 0: return "Invalid received task number"
			if request.unit != code or request.id != id or not repo.battle_behaviors.has(request.task) or request.source not in ["player", "general"] \
				or task.status not in ["received", "bounded", "search_failed", "completed"]: return "Contradictory received task"
			if not BodyMotion._loco_integer(task.get("sequence")) or task.sequence <= 0 \
				or not BodyMotion._loco_integer(ledger.get("received_sequence")) or ledger.received_sequence != task.sequence: return "Task lacks received sequence"
			if task.has("pursuit"):
				if not task.pursuit is Dictionary or not BodyMotion._loco_integer(task.pursuit.get("route_m")) or task.pursuit.route_m < 0: return "Invalid pursuit credit"
			var owner := BattleSystem.battle_of(source, code)
			if not owner.is_empty() and BattleSystem.canonical(source, int(request.battle_id)) != int(owner.id): return "Task names another battlefield"
	land.sort()
	var budget_codes: Array = tx.march_budgets.keys()
	budget_codes.sort()
	if land != budget_codes: return "Daily budgets must cover every land unit exactly once"
	var seen := {}
	for code: String in tx.marching_codes:
		if seen.has(code) or not tx.march_entries.has(code) or code not in land: return "Invalid received march membership"
		seen[code] = true
	if seen.size() != tx.march_entries.size(): return "Frozen route membership mismatch"
	if not BodyMotion._loco_integer(repo.balance.get("battle_deploy_step_m")) or repo.balance.battle_deploy_step_m < 0 or repo.balance.battle_deploy_step_m > BodyMotion.LOCAL_LIMIT:
		return "Invalid daily tactical cap"
	if _context(repo, source).is_empty(): return "Unsupported locomotion policy or terrain"
	return ArmySystem._body_terrain_error(repo, source, [])

static func _writer(repo: DataRepository, state: GameState, code: String, battle: Dictionary) -> String:
	var entry := ArmySystem._entry_of(state, code)
	var task := BattleTaskSystem.current(state, code)
	var request: Dictionary = task.get("request", {})
	var received: bool = task.get("status", "") in ["received", "bounded"]
	var action: String = str(repo.battle_behaviors.get(request.get("task", ""), {}).get("legal_action", "")) if received else ""
	var side := BattleRules.side_of(battle, code)
	if not battle.is_empty() and (bool(entry.get("battle_retreat", false)) or battle.get("routed_side", "") == side or BattleOrders.kind(battle, side) == "retreat" or action == "retreat"):
		return "withdrawal"
	if state.day_resolution.march_entries.has(code) and (int(entry.get("disengaging", 0)) == 1 or (received and (task.has("pursuit") or action == "pursue"))): return "pursuit_march"
	if task.get("status", "") in ["received", "bounded", "search_failed", "completed"] and request.get("task") == "flank": return "flank"
	if action == "charge" or (not battle.is_empty() and BattleOrders.kind(battle, side) == "charge"): return "charge"
	if not battle.is_empty(): return "deployment"
	if state.day_resolution.march_entries.has(code) and state.day_resolution.march_entries[code].order == ArmySystem.ORDER_MARCH: return "march"
	return "hold"

static func _collect(repo: DataRepository, source: GameState, boundary: Dictionary, providers: Dictionary) -> Dictionary:
	var error := _source_error(repo, source, boundary)
	if not error.is_empty(): return {"error": error}
	for key: Variant in providers:
		if key not in ["withdrawal", "flank", "charge", "deployment"] or not providers[key] is Callable or not providers[key].is_valid(): return {"error": "Invalid tactical provider"}
	var staged := UnitBodies._copy(source)
	var tx := staged.day_resolution
	var count := int(tx.substep_count)
	var slice := int(boundary.substep)
	var codes: Array = tx.march_budgets.keys()
	codes.sort()
	var intents: Array = []
	var units: Array = []
	var limits := {}
	for code: String in codes:
		var entry := ArmySystem._entry_of(staged, code)
		var battle := BattleSystem.battle_of(staged, code)
		var writer := _writer(repo, staged, code, battle)
		var tactical := writer in ["withdrawal", "flank", "charge", "deployment"]
		if tactical and not providers.has(writer): return {"error": "Unavailable tactical provider: " + writer}
		var budget := _share(int(tx.march_budgets[code]), count, slice)
		var here: Array = [int(entry.x_m), int(entry.y_m)]
		if not battle.is_empty() and battle.get("group_anchor_m", {}).has(code): here = battle.group_anchor_m[code].duplicate()
		var held := writer == "hold" or bool(entry.get("captured", false)) or not CampSystem.can_march_entry(entry, source.absolute_day()) or MilitaryRoster.fit(staged, code) <= 0
		if BattleTaskSystem.current(staged, code).get("status", "") in ["bounded", "search_failed", "completed"]: held = true
		if not battle.is_empty() and writer in ["withdrawal", "pursuit_march", "flank", "charge"]:
			var required: String = {"withdrawal": "retreat", "pursuit_march": "pursue", "flank": "attack", "charge": "charge"}[writer]
			var target: String = BattleTaskSystem.current(staged, code).get("request", {}).get("target_unit", "")
			if required not in BattleRules.legal_actions(repo, staged, int(battle.id), BattleRules.side_of(battle, code), code, target): held = true
		if held: budget = 0
		else:
			UnitGait.refresh(repo, staged, code, entry)
			if budget > 0 and UnitGait.pays_run(repo, staged, code, entry, count): budget = UnitGait.run_step_m(repo, budget)
		if tactical: budget = mini(budget, _share(int(repo.balance.battle_deploy_step_m), count, slice))
		if budget < 0 or budget > BodyMotion.LOCAL_LIMIT: return {"error": "Unsafe union slice budget"}
		var contribution := {"status": "complete", "reason": "Waiting for movement capability" if held else "", "error": "", "unit": code, "path_m": [here]}
		if not held:
			if tactical:
				# A provider sees a private clone; reject all side effects, including RNG.
				var isolated := UnitBodies._copy(staged)
				var before := BodyMotion._hash(isolated.to_dict())
				var raw: Variant = providers[writer].call(repo, isolated, int(battle.get("id", 0)), code, budget)
				if not raw is Dictionary or BodyMotion._hash(isolated.to_dict()) != before: return {"error": "Tactical provider mutated its source or returned invalid contribution"}
				contribution = raw
			else: contribution = ArmySystem.march_intent_candidate(repo, staged, code, budget)
		if not BodyMotion._keys(contribution, ["status", "reason", "error", "unit", "path_m"]) \
			or contribution.status not in ["complete", "error"] or not contribution.reason is String or not contribution.error is String \
			or contribution.unit != code or not contribution.path_m is Array: return {"error": "Invalid contribution schema"}
		if contribution.status == "error": return {"error": contribution.error if not contribution.error.is_empty() else "Provider rejected movement"}
		var path: Array = contribution.path_m
		if not contribution.error.is_empty() or path.is_empty() or path[0] != here or (path.size() == 1 and contribution.reason.is_empty()): return {"error": "Invalid contribution start/hold"}
		for point: Variant in path:
			if not BodyMotion._loco_point(point): return {"error": "Noninteger contribution path"}
			for axis: int in 2:
				if absf(BodyMotion._difference(point[axis], here[axis])) > BodyMotion.LOCAL_LIMIT: return {"error": "Contribution exceeds local arithmetic bounds"}
		if not tactical and not contribution.reason.is_empty(): limits[code] = {"at": path.back(), "reason": contribution.reason}
		for row: Dictionary in UnitBodies.rows(repo, staged, code):
			var translated: Array = []
			for point: Array in path: translated.append([int(point[0]) + int(row.x_m) - int(here[0]), int(point[1]) + int(row.y_m) - int(here[1])])
			translated = ArmySystem._body_locomotion_slice(repo, staged, code, row, translated, budget)
			if translated.is_empty(): return {"error": "Unsafe timed contribution prefix"}
			var piece := MapObjects.army_piece(repo, staged.army_roster[code])
			if not ArmySystem._body_path_terrain(MarchPath.of_pack(repo), translated, int(repo.unit_footprints[piece].radius_m)).is_empty(): return {"error": "Desired timed slice crosses forbidden terrain"}
			intents.append({"unit": code, "slot": int(row.slot), "path_m": translated, "budget_m": budget, "hostile": writer == "charge"})
		units.append({"unit": code, "writer": writer, "budget_m": budget, "anchor_path_m": path.duplicate(true)})
	return {"candidate": staged, "intents": intents, "units": units, "limits": limits}

static func collect_candidate(repo: DataRepository, source: GameState, boundary: Dictionary, providers: Dictionary = {}) -> Dictionary:
	var collected := _collect(repo, source, boundary, providers)
	var error: String = collected.get("error", "")
	return {"status": "complete" if error.is_empty() else "error", "reason": "Collected exclusive unit contributions" if error.is_empty() else error,
		"error": error, "intents": collected.get("intents", []), "units": collected.get("units", [])}

static func _stage(repo: DataRepository, source: GameState, boundary: Dictionary, providers: Dictionary) -> Dictionary:
	var collected := _collect(repo, source, boundary, providers)
	if collected.has("error"): return collected
	var motion := BodyMotion.plan_battle_locomotion_candidate(repo, collected.candidate, collected.intents, boundary)
	if not BodyMotion._loco_plan_ok(motion, true): return {"error": str(motion.get("reasons", {}).get("error", "Invalid union motion"))}
	collected.plan = {"version": 1, "request": {"kind": "move"}, "boundary": boundary.duplicate(true),
		"basis": {"source": BodyMotion._hash([source.to_dict(), {"kind": "move"}, boundary, _context(repo, source)])}, "motion": motion, "contacts": []}
	return collected

static func plan_candidate(repo: DataRepository, source: GameState, boundary: Dictionary, providers: Dictionary = {}) -> Dictionary:
	var staged := _stage(repo, source, boundary, providers)
	return _result("error", staged.error) if staged.has("error") else _result("complete", "Planned shared paid movement", null, staged.plan)

static func _plan_ok(plan: Dictionary) -> bool:
	return BodyMotion._keys(plan, ["version", "request", "boundary", "basis", "motion", "contacts"]) \
		and BodyMotion._loco_integer(plan.version) and plan.version == 1 and plan.request is Dictionary and plan.request == {"kind": "move"} \
		and plan.boundary is Dictionary and BodyMotion._battle_boundary_ok(plan.boundary) \
		and plan.basis is Dictionary and BodyMotion._keys(plan.basis, ["source"]) and plan.basis.source is String and BodyMotion._digest(plan.basis.source) \
		and BodyMotion._loco_plan_ok(plan.motion, true) and plan.contacts is Array and plan.contacts.is_empty() \
		and BodyMotion._hash(plan.motion.cursor.boundary) == BodyMotion._hash(plan.boundary)

static func commit_candidate(repo: DataRepository, source: GameState, proposed: Dictionary, boundary: Dictionary, providers: Dictionary = {}) -> Dictionary:
	if repo == null or source == null or not _plan_ok(proposed) or BodyMotion._hash(proposed.boundary) != BodyMotion._hash(boundary): return _result("error", "Invalid battle move plan/boundary")
	var receipt := BodyMotion._hash(proposed)
	var outer: Variant = source.military_migration.get("body_battle", {})
	if outer is Dictionary and outer.get("sequence") == boundary.sequence:
		var replay_boundary := boundary.duplicate(true)
		replay_boundary.stage = "contact"
		replay_boundary.sequence = str(int(boundary.sequence) + 1)
		var checked := UnitBodies.validate_battle_candidate(repo, source, replay_boundary)
		if checked.status != "complete" or outer.receipt != receipt \
			or source.military_migration.get("body_motion", {}).get("receipt") != BodyMotion._hash(proposed.motion) \
			or BodyMotion._hash(source.military_migration.body_motion.plan) != BodyMotion._hash(proposed.motion): return _result("error", "Invalid/stale battle move replay")
		return _result("complete", "Already committed", checked.candidate, BodyMotion._canonical(proposed))
	var staged := _stage(repo, source, boundary, providers)
	if staged.has("error"): return _result("error", staged.error)
	if receipt != BodyMotion._hash(staged.plan): return _result("error", "Stale or modified union plan")
	var moved := BodyMotion.commit_battle_locomotion_candidate(repo, staged.candidate, staged.plan.motion, boundary)
	if moved.status != "complete": return _result("error", moved.reason)
	var candidate: GameState = moved.candidate
	var arrivals: Array[String] = []
	for unit: Dictionary in staged.units:
		var code: String = unit.unit
		var path: Array = unit.anchor_path_m
		var common: Array = [path[0]]
		var minimum := BodyMotion.LOCAL_LIMIT + 1
		var used := 0
		for move: Dictionary in staged.plan.motion.moves:
			if move.unit != code: continue
			used = maxi(used, int(move.used_m))
			var intent: Dictionary = {}
			for item: Dictionary in staged.intents:
				if item.unit == code and item.slot == move.slot: intent = item
			var reference: Array = []
			for point: Array in intent.path_m: reference.append([int(path[0][0]) + int(point[0]) - int(move.start[0]), int(path[0][1]) + int(point[1]) - int(move.start[1])])
			var prefix := ArmySystem._body_route_prefix(reference, BodyMotion._loco_path(move), true)
			var length := BodyMotion._length(prefix)
			if length < minimum:
				minimum = length
				common = prefix
		if not ArmySystem._body_path_terrain(MarchPath.of_pack(repo), common, 0).is_empty(): return _result("error", "Invalid committed anchor terrain")
		var entry := ArmySystem._entry_of(candidate, code)
		if unit.writer in ["march", "pursuit_march"]:
			var saved: Dictionary = candidate.day_resolution.march_entries[code]
			var full: Array = [path[0]]
			for point: Vector2i in ArmySystem._path_of(saved): full.append([point.x, point.y])
			var row := {"unit": code, "saved_entry_after": saved, "used_m": used, "step_budget_m": unit.budget_m}
			ArmySystem._body_settle_route(repo, candidate, row, full, common, boundary, staged.limits.get(code, {}), arrivals, true)
		else:
			entry.x_m = int(common.back()[0])
			entry.y_m = int(common.back()[1])
			if used > 0:
				entry.moved_day = int(boundary.abs_day)
				ArmySystem._release_camp_on_movement(entry)
		var owner := BattleSystem.battle_of(candidate, code)
		if not owner.is_empty():
			if not owner.has("group_anchor_m"): owner.group_anchor_m = {}
			owner.group_anchor_m[code] = common.back().duplicate()
	candidate.day_resolution.journal.arrivals.append_array(arrivals)
	candidate.day_resolution.body_battle.stage = "contact"
	candidate.day_resolution.body_battle.sequence = str(int(boundary.sequence) + 1)
	candidate.military_migration.body_battle = {"version": "1", "sequence": boundary.sequence, "receipt": receipt,
		"result": "", "closed_motion": source.military_migration.get("body_battle", {}).get("closed_motion", {}).duplicate(true)}
	candidate.military_migration.body_battle.result = UnitBodies._battle_result_hash(repo, candidate)
	var final := UnitBodies.validate_battle_candidate(repo, candidate, _boundary(candidate))
	if final.status != "complete": return _result("error", "Final union validation: " + final.reason)
	if candidate.rng.to_dict() != source.rng.to_dict() or candidate.military_cohorts != source.military_cohorts: return _result("error", "Union movement changed RNG/personnel")
	return _result("complete", "Committed shared paid movement", final.candidate, staged.plan)
