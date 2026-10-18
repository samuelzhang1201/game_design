class_name PrisonerCommunications
extends RefCounted
## Negotiation and fulfillment letters disclose only what has reached the king.
const ACTION := "PRISONER_LETTER"

static func is_letter(c: Dictionary) -> bool:
	return String(CourierSystem.first_order(c).get("action_code", "")) == ACTION

static func projection(state: GameState, id: String) -> Dictionary:
	var p: Dictionary = state.prisoner_proposals.get(id, {})
	if p.is_empty():
		return {}
	var comm: Dictionary = p.get("communications", {})
	if comm.is_empty():
		return {"status": p.status, "consents": p.consents.duplicate(true),
			"result": p.get("result", {}).duplicate(true), "reason": p.request.reason}
	var consents := {p.request.parties.proposer: true}
	for realm: String in p.consents:
		if not comm.offers.has(realm) or comm.offers[realm].phase == "received":
			consents[realm] = p.consents[realm]
	return {"status": comm.visible_status, "consents": consents,
		"result": comm.received_result.duplicate(true), "reason": comm.get("received_reason", p.request.reason)}

static func propose(repo: DataRepository, state: GameState, raw: Dictionary) -> Dictionary:
	var result := PrisonerDisposition.propose(repo, state, raw)
	if result.has("error"):
		return result
	var p: Dictionary = state.prisoner_proposals[raw.id]
	var comm := {"offers": {}, "fulfillment": {}, "visible_status": p.status,
		"received_result": {}, "received_reason": p.request.reason}
	p["communications"] = comm
	var effects: Array = []
	for realm: String in p.frozen.required_parties:
		if p.consents.has(realm):
			continue
		var destination := _capital(repo, state, realm)
		if destination.has("error"):
			return destination
		var letter := _letter(String(raw.id), "offer")
		letter["realm"] = realm
		var sent := _send(repo, state, "realm:" + realm, Vector2i(destination.x_m, destination.y_m), letter)
		if sent.has("error"):
			return sent
		effects.append_array(sent.effects)
		comm.offers[realm] = {"phase": "riding", "courier_id": sent.id,
			"reason": p.request.reason, "decision": null, "received_day": 0}
	result["effects"] = effects
	return result

static func fulfill(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	var p: Dictionary = state.prisoner_proposals[id]
	# Validate the entire candidate before issuing any command or postage.
	var trial := GameState.from_dict(state.to_dict(), false)
	var valid := PrisonerDisposition.settle(repo, trial, id)
	if valid.has("error"):
		return valid
	var holders: Array = p.frozen.holders.keys()
	holders.sort()
	var remote: Array = []
	var delivered: Array = []
	for holder: String in holders:
		if KingSystem.can_command(repo, state, holder):
			delivered.append(holder)
		else:
			remote.append(holder)
	if remote.is_empty():
		var result := PrisonerDisposition.settle(repo, state, id)
		if p.has("communications") and not result.has("error"):
			p = state.prisoner_proposals[id]
			p.communications.visible_status = "fulfilled"
			p.communications.received_result = result.duplicate(true)
		return result
	if not p.has("communications"):
		p["communications"] = {"offers": {}, "fulfillment": {}, "visible_status": p.status,
			"received_result": {}, "received_reason": p.request.reason}
	var fulfillment := {"phase": "riding", "holders": holders, "delivered": delivered,
		"courier_ids": [], "reason": p.request.reason}
	p.communications.fulfillment = fulfillment
	p.communications.visible_status = "fulfilling"
	p.communications.received_reason = "Fulfillment commands are riding; await the returned receipt."
	var effects: Array = []
	for holder: String in remote:
		var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, holder, state)))
		var sent := _send(repo, state, holder, at, _letter(id, "fulfill"))
		if sent.has("error"):
			return sent
		effects.append_array(sent.effects)
		fulfillment.courier_ids.append(sent.id)
	fulfillment.courier_ids.sort()
	# Postage cannot borrow money reserved for the ransom.
	trial = GameState.from_dict(state.to_dict(), false)
	valid = PrisonerDisposition.settle(repo, trial, id)
	if valid.has("error"):
		return valid
	return {"id": id, "status": "riding", "effects": effects}

static func _capital(repo: DataRepository, state: GameState, realm: String) -> Dictionary:
	var code := String((repo.kingdoms.get(realm, {}) as Dictionary).get("capital_burg", ""))
	var town: Dictionary = repo.burgs.get(code, {})
	if town.is_empty() or MapOwnership.owner_of(repo, state, String(town.get("province_code", ""))) != realm:
		return {"error": "The recipient has no held bound capital for this offer."}
	var at := ArmySystem.pack_to_metres(repo, Vector2(float(town.x), float(town.y)))
	return {"x_m": at.x, "y_m": at.y}

static func _letter(id: String, phase: String) -> Dictionary:
	return {"action_code": ACTION, "proposal_id": id, "phase": phase}

static func _send(repo: DataRepository, state: GameState, target: String, at: Vector2i, letter: Dictionary) -> Dictionary:
	for c: Dictionary in state.couriers:
		if is_letter(c) and c.target == target and int(c.days) == 0 and int(c.issued) == state.absolute_day() \
				and String(CourierSystem.first_order(c).phase) == letter.phase:
			c.orders.append(letter)
			return {"id": c.id, "effects": []}
	var fee := CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)
	if BattleOrders.available_gold(state) < fee:
		return {"error": "The treasury cannot afford the prisoner's ordinary courier."}
	var reason := "Postage for prisoner agreement " + String(letter.proposal_id)
	var paid := WorldLedger.apply(repo, state, "metrics.treasury", -fee, reason, ACTION)
	if paid.has("error") or float(paid.get("delta", 0)) != -fee:
		return {"error": "The prisoner's entire postage could not be paid."}
	var from := ArmySystem.pack_to_metres(repo, CourierSystem.origin(repo, state))
	state.next_courier_id += 1
	var c := {"id": state.next_courier_id, "kind": CourierSystem.ORDINARY,
		"x_m": from.x, "y_m": from.y, "target": target, "orders": [letter],
		"path": [], "aim_x_m": at.x, "aim_y_m": at.y, "issued": state.absolute_day(),
		"days": 0, "day_m": 0, "slow_spell": -1}
	_route(repo, c, at)
	state.couriers.append(c)
	return {"id": c.id, "effects": [{"kind": "world", "path": "metrics.treasury", "delta": -fee, "reason": reason}]}

static func _route(repo: DataRepository, c: Dictionary, at: Vector2i) -> void:
	c.aim_x_m = at.x
	c.aim_y_m = at.y
	c.path = CourierSystem.path_between(repo, ArmySystem.metres_to_pack(repo, Vector2i(c.x_m, c.y_m)),
		ArmySystem.metres_to_pack(repo, at))

## Empty on a lost holder; responses and receipts always follow the king.
static func prepare(repo: DataRepository, state: GameState, c: Dictionary) -> String:
	var phase := String(CourierSystem.first_order(c).phase)
	if phase in ["response", "offer_failure", "receipt"]:
		var king := KingSystem.position(state)
		if king != Vector2i(c.aim_x_m, c.aim_y_m):
			_route(repo, c, king)
	elif phase == "fulfill":
		var holder := String(c.target)
		if not PrisonerSystem._live_holder(repo, state, holder):
			return "The frozen prisoner holder is no longer available."
		var reg := ArmySystem.regiment(repo, holder, state)
		CourierSystem._reaim(repo, state, c, reg)
	return ""

static func ride(repo: DataRepository, state: GameState, c: Dictionary, today: int, events: Array) -> bool:
	var failure := prepare(repo, state, c)
	c.days = int(c.days) + 1
	if int(c.days) > int(repo.bal("courier_max_days")):
		failure = "The prisoner courier exceeded the delivery deadline."
	if failure == "":
		CourierSystem._advance(repo, state, c, today, events)
		if not (c.path as Array).is_empty():
			return true
	if failure != "" and String(CourierSystem.first_order(c).phase) in ["response", "offer_failure", "receipt"]:
		# A lost return leg cannot tell the king the decision or execution result.
		for order: Dictionary in CourierSystem.orders_of(c):
			var p: Dictionary = state.prisoner_proposals.get(order.proposal_id, {})
			if not p.is_empty():
				p.communications.visible_status = "unconfirmed"
				p.communications.received_reason = "The courier is overdue; the outcome is unconfirmed. A new agreement is needed."
				if order.phase in ["response", "offer_failure"]:
					p.communications.offers[order.realm].phase = "failed"
				else:
					p.communications.fulfillment.phase = "failed"
		events.append(CourierSystem._event("fuse", c))
		return false
	var returning: Array = []
	for order: Dictionary in CourierSystem.orders_of(c):
		var reply := _arrive(repo, state, c, order, failure)
		if not reply.is_empty():
			returning.append(reply)
	events.append(CourierSystem._event("delivered", c))
	if returning.is_empty():
		return false
	c.orders = returning
	c.target = "king"
	c.days = 0
	c.day_m = 0
	_route(repo, c, KingSystem.position(state))
	return true

static func _decision(repo: DataRepository, state: GameState, p: Dictionary, realm: String) -> Dictionary:
	var checked := PrisonerDisposition._inspect(repo, state, p.request)
	if checked.has("error") or checked != p.frozen:
		return {"accepted": false, "reason": String(checked.get("error", "The frozen custody or terms changed."))}
	var capital := _capital(repo, state, realm)
	if capital.has("error"):
		return {"accepted": false, "reason": capital.error}
	if p.request.kind == "ransom":
		var payer := String(p.request.parties.payer)
		var funds: Variant = WorldLedger.value_of(repo, state, PrisonerDisposition._treasury(repo, payer))
		if payer == repo.resolve_realm("player_realm"):
			funds = BattleOrders.available_gold(state)
		if int(p.request.money) > int(p.proposal_result.valuation.asking_gold) or funds == null or int(funds) < int(p.request.money):
			return {"accepted": false, "reason": "The ransom exceeds the frozen asking price or current funds."}
	elif p.request.kind == "exchange":
		var counts := {}
		for holder: String in checked.holders:
			var owner := String(checked.holders[holder].realm)
			counts[owner] = int(counts.get(owner, 0)) + int(checked.holders[holder].count)
		var amounts: Array = counts.values()
		if amounts.size() != 2 or int(amounts[0]) != int(amounts[1]):
			return {"accepted": false, "reason": "Only equal reciprocal prisoner counts are accepted."}
	return {"accepted": true, "reason": "The lawful prisoner terms are accepted."}

static func _arrive(repo: DataRepository, state: GameState, c: Dictionary, order: Dictionary, failure: String) -> Dictionary:
	var id := String(order.proposal_id)
	if not state.prisoner_proposals.has(id):
		return {}
	var p: Dictionary = state.prisoner_proposals[id]
	var comm: Dictionary = p.communications
	match String(order.phase):
		"offer":
			var destination := _capital(repo, state, order.realm)
			if destination.has("error") and failure == "":
				failure = String(destination.error)
			if failure != "":
				comm.offers[order.realm].phase = "returning"
				comm.offers[order.realm].reason = failure
				var undelivered := _letter(id, "offer_failure")
				undelivered["realm"] = order.realm
				undelivered["reason"] = failure
				return undelivered
			var decision := _decision(repo, state, p, order.realm)
			var offer: Dictionary = comm.offers[order.realm]
			offer.phase = "returning"
			offer.decision = decision.accepted
			offer.reason = decision.reason
			var response := _letter(id, "response")
			response["realm"] = order.realm
			response["decision"] = decision
			return response
		"offer_failure":
			comm.offers[order.realm].phase = "failed"
			comm.offers[order.realm].received_day = state.absolute_day()
			comm.visible_status = "unconfirmed"
			comm.received_reason = "The offer was not delivered: " + String(order.reason) + " A new agreement is needed."
		"response":
			var offer: Dictionary = comm.offers[order.realm]
			offer.phase = "received"
			offer.received_day = state.absolute_day()
			var response := PrisonerDisposition.respond(repo, state, id, order.realm, bool(order.decision.accepted))
			if comm.visible_status != "unconfirmed":
				comm.visible_status = p.status
				comm.received_reason = String(response.get("error", order.decision.reason))
		"fulfill":
			var fulfillment: Dictionary = comm.fulfillment
			if fulfillment.phase != "riding":
				return {}
			if failure == "":
				var checked := PrisonerDisposition._inspect(repo, state, p.request)
				if checked.has("error") or checked != p.frozen:
					failure = String(checked.get("error", "The frozen custody or terms changed."))
			if failure == "":
				if not String(c.target) in fulfillment.delivered:
					fulfillment.delivered.append(String(c.target))
					fulfillment.delivered.sort()
				if fulfillment.delivered.size() != fulfillment.holders.size():
					return {}
			var result := PrisonerDisposition.settle(repo, state, id) if failure == "" else {"error": failure}
			p = state.prisoner_proposals[id]
			p.communications.fulfillment.phase = "failed" if result.has("error") else "executed"
			p.communications.fulfillment.reason = String(result.get("error", p.request.reason))
			var receipt := _letter(id, "receipt")
			receipt["result"] = result.duplicate(true)
			return receipt
		"receipt":
			comm.fulfillment.phase = "received"
			comm.fulfillment.received_day = state.absolute_day()
			comm.received_result = order.result.duplicate(true)
			comm.visible_status = "failed" if order.result.has("error") else "fulfilled"
			comm.received_reason = String(order.result.get("error", p.request.reason))
	return {}
