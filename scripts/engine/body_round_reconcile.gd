class_name BodyRoundReconcile
extends RefCounted
## CF06 D-RECONCILE, kept out of unit_bodies.gd: that file's SHA-256 is a pinned premise of the
## royal carrier proof (Map3DRoyalCarrierSource._SOURCES), so it is not edited for this step.

## CF06 D-RECONCILE: a frozen round's settled personnel losses reach its bodies. `proposed` is
## exactly {battle_id:int, round:int}; the source is the private settlement stage in which the
## round's personnel event `battle:<id>:round:<n>:personnel` has applied. Provenance is checked
## (round-stage boundary on the saved control, canonical live field, body_round and pending_round
## of that round with its receipt, the event touching only the round's participants). Each
## participant whose bodies exceed its fit keeps its first rows in stored order (the order the
## canonical counts follow) with identity and position, and canonical counts; the rest retire and the slot counter's high water stays.
## Growth, unrelated staged changes or any invalid world reject. The round stays open.
## Only the CF06 settlement may call this, on the stage it produced itself after proving the
## round's body_round.basis on its admitted pre-settlement world: "complete" certifies the
## personnel part, never a standalone provenance of arbitrary staged state. A retry and an
## unrelated change that happens to offset the round's numbers look alike here; only that
## basis proof separates them.
static func reconcile_round_candidate(repo: DataRepository, source: GameState, proposed: Dictionary, boundary: Dictionary) -> Dictionary:
	if repo == null or source == null: return UnitBodies._failure("Round reconciliation requires data and source")
	if not BodyMotion._keys(proposed, ["battle_id", "round"]) or not BodyMotion._loco_integer(proposed.battle_id) \
		or not BodyMotion._loco_integer(proposed.round) or int(proposed.battle_id) <= 0 or int(proposed.round) <= 0:
		return UnitBodies._failure("Invalid round reconciliation request")
	var raw_error := UnitBodies._battle_raw_error(source)
	if not raw_error.is_empty(): return UnitBodies._failure(raw_error)
	var control: Variant = source.day_resolution.get("body_battle")
	if not control is Dictionary or not BodyMotion._keys(boundary, ["version", "kind", "abs_day", "substep", "sequence", "stage"]) \
		or not BodyMotion._loco_integer(boundary.version) or boundary.version != 1 \
		or boundary.kind != "battle" or boundary.stage != "round" or boundary.stage != control.get("stage") \
		or boundary.abs_day != control.get("abs_day") or boundary.substep != control.get("next_substep") \
		or boundary.sequence != control.get("sequence") or int(boundary.abs_day) != source.absolute_day():
		return UnitBodies._failure("Round reconciliation requires its saved round boundary")
	var id := int(proposed.battle_id)
	var battle := UnitBodies._battle(source, id)
	if battle.is_empty() or BattleSystem.canonical(source, id) != id: return UnitBodies._failure("Round reconciliation requires a canonical live field")
	var round_error := UnitBodies._battle_round_error(battle)
	if not round_error.is_empty(): return UnitBodies._failure(round_error)
	var pending: Dictionary = battle.get("pending_round", {})
	if not battle.has("body_round") or pending.is_empty() or int(battle.body_round.round) != int(proposed.round) \
		or battle.body_round.abs_day != boundary.abs_day:
		return UnitBodies._failure("Round reconciliation requires that frozen round")
	var tx := source.day_resolution
	if int(tx.battle_index) >= tx.battle_ids.size() or int(tx.battle_ids[int(tx.battle_index)]) != id:
		return UnitBodies._failure("Round reconciliation requires the current queued field")
	var event: Variant = source.military_events.get("battle:%d:round:%d:personnel" % [id, int(proposed.round)])
	if not event is Dictionary or not event.get("request") is Dictionary or event.request.get("kind") != "transfer_units" \
		or not event.get("result") is Dictionary or event.result.get("status") != "applied" or not event.result.get("changes") is Array \
		or event.result.changes.is_empty():
		return UnitBodies._failure("Round reconciliation requires the round's applied personnel event")
	var participants: Array = pending.att + pending.def
	for change: Variant in event.result.changes:
		if not change is Dictionary or change.get("from") != "fit" or change.get("to") not in ["wounded", "dead", "captured_current"] \
			or not UnitBodies._whole(change.get("count")) or int(change.count) <= 0:
			return UnitBodies._failure("A round personnel change must move fit personnel to a casualty status")
		var cohort: Variant = source.military_cohorts.get(change.get("cohort_id"))
		if not cohort is Dictionary: return UnitBodies._failure("Round personnel change names no cohort")
		var unit: Variant = cohort.get("unit_code")
		if unit not in participants: return UnitBodies._failure("Round personnel event touches a non-participant")
	var size := int(repo.bal("battle_group_size"))
	var candidate := UnitBodies._copy(source)
	var index := UnitBodies._owners(candidate)
	if not index.error.is_empty(): return UnitBodies._failure(index.error)
	var ordered := participants.duplicate()
	ordered.sort()
	for code: String in ordered:
		var owner: Dictionary = index.owners.get(code, {})
		var entry := UnitBodies._entry(candidate, code)
		var store: Variant = entry.get("body_groups") if owner.is_empty() else owner.get("groups", {}).get(code)
		if not store is Array: return UnitBodies._failure("Round participant lacks bodies: " + code)
		var rows: Array = store.duplicate(true)   # stored order: the order the canonical counts follow
		var total := 0
		for row: Variant in rows:
			if not row is Dictionary or not UnitBodies._whole(row.get("count")) or not UnitBodies._whole(row.get("slot")): return UnitBodies._failure("Invalid round participant body: " + code)
			total += int(row.count)
		var fit := MilitaryRoster.fit(candidate, code)
		if fit > total: return UnitBodies._failure("Round settlement cannot grow bodies: " + code)
		if fit == total: continue   # already reconciled: a retry is a no-op
		# Otherwise the bodies must be exactly the fit before THIS round's event: no other staged loss.
		if total != UnitBodies._frozen_fit(candidate, code, battle): return UnitBodies._failure("Bodies do not match the round's own losses: " + code)
		var partition := BattleGroups.counts(fit, size)
		if partition.size() > rows.size(): return UnitBodies._failure("Round losses cannot add bodies: " + code)
		var kept: Array[Dictionary] = []
		for i: int in partition.size():
			var row: Dictionary = rows[i]
			if partition[i] > int(row.count): return UnitBodies._failure("A round loss cannot move personnel between bodies: " + code)
			row.count = partition[i]
			kept.append(row)
		if owner.is_empty(): entry.body_groups = kept
		else: owner.groups[code] = kept
	var final := UnitBodies._battle_world(repo, candidate)
	if final.status != "complete": return UnitBodies._failure("Reconciled world failed validation: " + final.reason)
	return UnitBodies._result("complete", "Reconciled frozen round losses without closing the round", candidate)
