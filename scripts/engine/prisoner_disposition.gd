class_name PrisonerDisposition
extends RefCounted
## A proposal freezes the exact custody and terms. Consent is separate from
## fulfillment; only the latter moves money or releases civilian personnel.

static func propose(repo: DataRepository, state: GameState, raw: Dictionary) -> Dictionary:
	var request := _normalize(raw)
	if request.has("error"):
		return request
	var id := String(request.id)
	if state.prisoner_proposals.has(id):
		var old: Dictionary = state.prisoner_proposals[id]
		return old.proposal_result.duplicate(true) if old.request == request else {"error": "Proposal ID already freezes different terms."}
	var checked := _inspect(repo, state, request)
	if checked.has("error"):
		return checked
	var valuation := _valuation(repo, state, request, checked)
	if valuation.has("error"):
		return valuation
	var consents := {request.parties.proposer: true}
	var status := "accepted" if checked.required_parties.size() == 1 else "proposed"
	var result := {"id": id, "status": status, "required_parties": checked.required_parties.duplicate(), "valuation": valuation}
	state.prisoner_proposals[id] = {"request": request.duplicate(true), "frozen": checked,
		"consents": consents, "status": status, "proposal_result": result.duplicate(true)}
	return result

static func respond(_repo: DataRepository, state: GameState, id: String, party: String, accepted: bool) -> Dictionary:
	if not state.prisoner_proposals.has(id):
		return {"error": "No such prisoner proposal."}
	var proposal: Dictionary = state.prisoner_proposals[id]
	if not party in proposal.frozen.required_parties:
		return {"error": "This realm is not a party to the proposal."}
	if proposal.consents.has(party):
		if proposal.consents[party] != accepted:
			return {"error": "A recorded response cannot be changed."}
		return {"id": id, "status": proposal.status}
	if proposal.status in ["rejected", "fulfilled"]:
		return {"error": "The proposal is already terminal."}
	proposal.consents[party] = accepted
	proposal.status = "rejected" if not accepted else "accepted" if proposal.consents.size() == proposal.frozen.required_parties.size() else "proposed"
	return {"id": id, "status": proposal.status}

static func settle(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	if not state.prisoner_proposals.has(id):
		return {"error": "No such prisoner proposal."}
	var proposal: Dictionary = state.prisoner_proposals[id]
	if proposal.status == "fulfilled":
		return proposal.result.duplicate(true)
	if proposal.status != "accepted":
		return {"error": "Every required party must accept before fulfillment."}
	var request: Dictionary = proposal.request
	var checked := _inspect(repo, state, request)
	if checked.has("error"):
		return checked
	if checked != proposal.frozen:
		return {"error": "Custody or received terms changed; negotiate a new proposal."}
	var candidate := GameState.from_dict(state.to_dict(), false)
	var effects: Array = []
	var payments: Array = []
	if request.kind == "ransom":
		var payer := String(request.parties.payer)
		var money := int(request.money)
		var path := _treasury(repo, payer)
		var funds: Variant = WorldLedger.value_of(repo, candidate, path)
		if funds == null or float(funds) < money \
				or (payer == repo.resolve_realm("player_realm") and BattleOrders.available_gold(candidate) < money):
			return {"error": "The payer cannot afford the entire ransom."}
		var debit := _pay(repo, candidate, path, -money, request.reason, id)
		if debit.has("error"):
			return debit
		effects.append(debit)
		var holders: Array = checked.holders.keys()
		holders.sort()
		var weights: Array = []
		for holder: String in holders:
			weights.append(checked.holders[holder].count)
		var gross := BattleSystem.apportion(weights, money)
		for i: int in holders.size():
			var holder := String(holders[i])
			var received: Dictionary = checked.holders[holder]
			@warning_ignore("integer_division")
			var prize := int(gross[i]) * int(received.share) / 1000
			var crown := int(gross[i]) - prize
			var credit := _pay(repo, candidate, _treasury(repo, received.realm), crown, request.reason, id)
			if credit.has("error"):
				return credit
			effects.append(credit)
			candidate.unit_prize_gold[holder] = int(candidate.unit_prize_gold.get(holder, 0)) + prize
			payments.append({"holder_code": holder, "realm": received.realm, "gross": int(gross[i]),
				"captor_gold": prize, "crown_gold": crown, "share_permille": received.share, "reason": request.reason})
	var released := PrisonerSystem.release(repo, candidate, "disposition:" + id, request.batches, request.reason)
	if released.has("error"):
		return released
	var family_changes: Array = []
	var families := {}
	var evidence: Array = []
	for selection: Dictionary in request.batches:
		var original: Dictionary = checked.batches[selection.batch_id]
		var cohort: Dictionary = candidate.military_cohorts[original.source_cohort]
		if request.terms.has("no_fighting_until_day"):
			if not cohort.has("civilian_promises"):
				cohort["civilian_promises"] = []
			cohort.civilian_promises.append({"count": int(selection.count), "until_day": int(request.terms.no_fighting_until_day),
				"reason": request.reason + ": agreed not to fight", "proposal_id": id})
		var family := String(cohort.get("family_name", ""))
		if family != "":
			if not families.has(family):
				families[family] = {}
			if not families[family].has(original.origin_realm):
				families[family][original.origin_realm] = {}
			families[family][original.origin_realm][ArmySystem.realm_of(repo, original.holder_code, candidate)] = true
		evidence.append({"batch_id": selection.batch_id, "source_cohort": original.source_cohort,
			"origin_realm": original.origin_realm, "source_province": cohort.source_province,
			"source_population_field": cohort.source_population_field,
			"owner_now": MapOwnership.owner_of(repo, candidate, cohort.source_province),
			"capture_id": original.capture_id, "captor_code": PrisonerSystem.captor_of(original),
			"holder_code": original.holder_code, "count": int(selection.count), "wounded_count": int(selection.wounded_count),
			"named_ids": selection.named_ids.duplicate(), "civilian": true, "reason": request.reason,
			"released_total": int(candidate.prisoner_batches[selection.batch_id].get("released_count", 0)),
			"remaining_count": int(candidate.prisoner_batches[selection.batch_id].commoners) + int(candidate.prisoner_batches[selection.batch_id].nobles),
			"remaining_wounded": int(candidate.prisoner_batches[selection.batch_id].wounded_subset)})
	var row: Dictionary = repo.prisoner_terms[request.kind]
	var person_ids := candidate.characters.keys()
	person_ids.sort()
	for person: String in person_ids:
		var character: Character = candidate.characters[person]
		if not families.has(character.family_name) or not families[character.family_name].has(character.kingdom):
			continue
		var realms: Array = families[character.family_name][character.kingdom].keys()
		realms.sort()
		for realm: String in realms:
			var reason := String(row.reason) + " " + String(request.reason)
			if realm == repo.resolve_realm("player_realm"):
				var old := character.opinion
				character.change_opinion(int(row.family_opinion), reason, candidate.tick)
				family_changes.append({"character_id": person, "delta": character.opinion - old, "reason": reason})
			else:
				var ruler := DevelopmentSystem.ruler_of(repo, candidate, realm)
				if ruler != null and ruler.id != person:
					RelationshipGraph.adjust(candidate, person, ruler.id, int(row.family_opinion), reason, candidate.tick)
					family_changes.append({"character_id": person, "to": ruler.id, "delta": int(row.family_opinion), "reason": reason})

	var result := {"id": id, "status": "fulfilled", "day": state.absolute_day(), "released": int(released.released),
		"payments": payments, "effects": effects, "family_changes": family_changes, "civilians": evidence,
		"reason": request.reason, "forgone_ransom": request.kind == "release"}
	candidate.prisoner_proposals[id].status = "fulfilled"
	candidate.prisoner_proposals[id]["result"] = result.duplicate(true)
	for field: String in ["prisoner_batches", "prisoner_events", "prisoner_proposals", "unit_prize_gold",
			"military_cohorts", "military_rosters", "military_events", "metrics", "world", "world_log", "relationships"]:
		state.set(field, candidate.get(field))
	# Retain character object identity for callers holding references.
	for person: String in person_ids:
		(state.characters[person] as Character).opinion = (candidate.characters[person] as Character).opinion
		(state.characters[person] as Character).opinion_log = (candidate.characters[person] as Character).opinion_log
	return result.duplicate(true)

## The reference informs negotiation; a consensual price remains independent.
static func _valuation(repo: DataRepository, state: GameState, request: Dictionary, checked: Dictionary) -> Dictionary:
	if request.kind != "ransom":
		return {}
	var row: Dictionary = repo.prisoner_terms.ransom
	for key: String in ["base_gold", "wealth_gold_per_point", "unnamed_wealth"]:
		if not _whole(row.get(key)):
			return {"error": "Ransom valuation needs nonnegative whole data: " + key}
	var asking := 0
	for selection: Dictionary in request.batches:
		var batch: Dictionary = checked.batches[selection.batch_id]
		var wealth := int(row.unnamed_wealth)
		if not batch.named_ids.is_empty():
			var person: Character = state.characters.get(batch.named_ids[0]) as Character
			if person == null:
				return {"error": "The named captive has no character for valuation."}
			wealth = int(person.attributes.get("wealth", wealth))
		asking += int(selection.count) * (int(row.base_gold) + wealth * int(row.wealth_gold_per_point))
	var payer := String(request.parties.payer)
	var funds: Variant = WorldLedger.value_of(repo, state, _treasury(repo, payer))
	if funds == null:
		return {"error": "The payer has no treasury account."}
	var available := BattleOrders.available_gold(state) if payer == repo.resolve_realm("player_realm") else int(funds)
	return {"asking_gold": asking, "affordable_gold": mini(asking, maxi(0, int(available)))}

static func _treasury(repo: DataRepository, realm: String) -> String:
	return "metrics.treasury" if realm == repo.resolve_realm("player_realm") else "economy.kingdoms.%s.treasury" % realm

static func _pay(repo: DataRepository, state: GameState, path: String, amount: int, reason: String, id: String) -> Dictionary:
	var line := WorldLedger.apply(repo, state, path, amount, reason, "prisoner:" + id)
	if line.has("error") or float(line.get("delta", 0)) != amount:
		return {"error": "The complete transfer cannot fit its treasury account."}
	return {"kind": "world", "path": line.path, "delta": amount, "reason": reason}

static func _normalize(raw: Dictionary) -> Dictionary:
	for key: String in ["id", "kind", "reason"]:
		if not raw.get(key) is String or String(raw[key]).strip_edges().is_empty():
			return {"error": "A proposal needs an ID, kind and reason."}
	if not raw.kind in ["ransom", "exchange", "release"] or not raw.get("batches") is Array \
			or raw.batches.is_empty() or not raw.get("parties") is Dictionary or not raw.get("terms", {}) is Dictionary:
		return {"error": "A proposal needs supported terms, parties and prisoner selections."}
	for key: String in ["proposer", "payer"]:
		if not raw.parties.get(key, "") is String:
			return {"error": "Proposal parties must be realm codes."}
	var money: Variant = raw.get("money", 0)
	if not _whole(money) or (int(money) <= 0 if raw.kind == "ransom" else int(money) != 0):
		return {"error": "Only a ransom has a positive whole-gold price."}
	var batches: Array = []
	var seen := {}
	for selection: Variant in raw.batches:
		if not selection is Dictionary or not selection.get("batch_id") is String \
				or seen.has(selection.batch_id) or not _whole(selection.get("count")) or int(selection.count) <= 0 \
				or not _whole(selection.get("wounded_count", 0)) or not selection.get("named_ids", []) is Array:
			return {"error": "Select unique batches with whole personnel and wound counts."}
		var names: Array = selection.get("named_ids", []).duplicate()
		for name: Variant in names:
			if not name is String:
				return {"error": "Named selections require person IDs."}
		names.sort()
		seen[selection.batch_id] = true
		batches.append({"batch_id": selection.batch_id, "count": int(selection.count),
			"wounded_count": int(selection.get("wounded_count", 0)), "named_ids": names})
	batches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.batch_id < b.batch_id)
	var terms: Dictionary = raw.get("terms", {}).duplicate(true)
	for key: Variant in terms:
		if key != "no_fighting_until_day" or not _whole(terms[key]):
			return {"error": "Unsupported or invalid release promise."}
		terms[key] = int(terms[key])
	return {"id": raw.id, "kind": raw.kind, "reason": raw.reason, "batches": batches, "money": int(money),
		"parties": {"proposer": raw.parties.get("proposer", ""), "payer": raw.parties.get("payer", "")}, "terms": terms}

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value == floor(value)

static func _inspect(repo: DataRepository, state: GameState, request: Dictionary) -> Dictionary:
	if not repo.prisoner_terms.has(request.kind):
		return {"error": "No prisoner terms are configured for this disposition."}
	if request.terms.has("no_fighting_until_day") and int(request.terms.no_fighting_until_day) > 0 \
			and int(request.terms.no_fighting_until_day) < state.absolute_day():
		return {"error": "A newly agreed promise cannot already have expired."}
	var frozen := {"batches": {}, "holders": {}, "required_parties": []}
	var holders := {}
	var origins := {}
	for selection: Dictionary in request.batches:
		var batch: Dictionary = state.prisoner_batches.get(selection.batch_id, {})
		var count := int(selection.count)
		var wounds := int(selection.wounded_count)
		var held := int(batch.get("commoners", 0)) + int(batch.get("nobles", 0))
		if batch.get("disposition", "") != "held" or count > held or wounds > count \
				or wounds > int(batch.get("wounded_subset", 0)) or count - wounds > held - int(batch.get("wounded_subset", 0)):
			return {"error": "Selected people are no longer held with those wound counts."}
		var names: Array = batch.get("named_ids", []).duplicate()
		names.sort()
		if names != selection.named_ids or (not names.is_empty() and (count != held or count != names.size())):
			return {"error": "A named captive must be selected explicitly and exactly once."}
		var source: Dictionary = state.military_cohorts.get(batch.get("source_cohort", ""), {})
		if source.is_empty() or int(source.get("captured_current", 0)) < count:
			return {"error": "The captured source personnel are no longer available."}
		var holder := String(batch.get("holder_code", ""))
		if not PrisonerSystem._live_holder(repo, state, holder):
			return {"error": "The current holder cannot fulfill this agreement."}
		var realm := ArmySystem.realm_of(repo, holder, state)
		var origin := String(batch.get("origin_realm", ""))
		if not repo.kingdoms.has(realm) or not repo.kingdoms.has(origin) or realm == origin:
			return {"error": "Negotiation needs opposing holding and original realms."}
		var refusal := LawSystem.prisoner_refusal(repo, state, batch, request.kind)
		if refusal != "":
			return {"error": refusal}
		var share := LawSystem.prisoner_share(repo, state, holder)
		if share.has("error"):
			return share
		frozen.batches[selection.batch_id] = batch.duplicate(true)
		if not frozen.holders.has(holder):
			frozen.holders[holder] = {"realm": realm, "share": int(share.permille), "count": 0}
		frozen.holders[holder].count += count
		holders[realm] = true
		origins[origin] = true
	var required := holders.duplicate()
	if request.kind == "ransom":
		if origins.size() != 1 or not origins.has(request.parties.payer):
			return {"error": "The ransom payer must represent the selected prisoners' original realm."}
		required[request.parties.payer] = true
	elif request.parties.payer != "":
		return {"error": "Exchange and free release do not have a payer."}
	if request.kind == "exchange":
		if holders.size() != 2 or holders != origins:
			return {"error": "An exchange needs reciprocal prisoners from both releasing realms."}
		required.merge(origins)
	if request.terms.has("no_fighting_until_day"):
		required.merge(origins)
	if not holders.has(request.parties.proposer):
		return {"error": "Only a holding realm can propose this disposition."}
	frozen.required_parties = required.keys()
	frozen.required_parties.sort()
	return frozen
