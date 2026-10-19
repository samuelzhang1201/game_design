class_name ActionSystem
extends RefCounted

var data: DataRepository

## gold cost formula name -> balance key (formulas beyond flat keys come later)
const COST_KEYS := {
	"levy_cost": "levy_cost", "build_cost": "build_cost", "spy_cost": "spy_cost",
	"formula_reward_cost": "reward_gold_cost",
}

const TONE_DELTAS := {
	"respectful": 2, "neutral": 0, "curt": -2, "flattering": 2,
	"threatening": -3, "dismissive": -3,
}

## The realm's merchants speak through their guildmaster (TRADE_ROUTE_SET):
## no roles.csv column names the guild — his row has no seat and the
## `celebrity` category — so the id is named here, and a campaign without
## him simply has no one to anger.
const GUILDMASTER := "char_guildmaster_tessa"

func _init(d: DataRepository) -> void:
	data = d

func gold_cost(row: Dictionary) -> float:
	var formula: String = row.get("gold_cost_formula", "none")
	if formula == "none" or formula == "":
		return 0.0
	if COST_KEYS.has(formula):
		return data.bal(COST_KEYS[formula])
	return 0.0  # unknown formulas are free in slice 1; slice 2 adds real formulas

func validate(req: ActionRequest, state: GameState) -> String:
	if not data.actions.has(req.action_code):
		return "Unknown action: " + req.action_code
	if req.action_code in ["PRISONER_PROPOSE", "PRISONER_RESPOND", "PRISONER_SETTLE"]:
		return String(_prisoner_action(req, state, false).get("error", ""))
	if req.action_code in ["BATTLE_TASK", "BATTLE_TASK_CANCEL"]:
		var previous := _task_replay(req, state)
		if not previous.is_empty():
			return String(previous.get("error", ""))
	if req.action_code == "BATTLE_ORDER":
		var previous := _battle_replay(req, state)
		if not previous.is_empty():
			return String(previous.get("error", ""))
	if req.action_code == "ARMY_RECRUIT":
		if req.target != "":
			return "Recruitment has no separate target character."
		var previous := RecruitmentSystem.replay(state, req.params)
		if not previous.is_empty():
			return String(previous.get("error", ""))
	var row: Dictionary = data.actions[req.action_code]
	var regiment := String(req.params.get("regiment", ""))
	if bool(state.regiments.get(regiment, {}).get("captured", false)):
		return "This regiment has surrendered and is no longer yours to command."
	if state.cooldowns.get(req.action_code, 0) > state.tick:
		return "%s is on cooldown until tick %d" % [req.action_code, state.cooldowns[req.action_code]]
	# The cost row's gold counts too (RECRUIT_COURTIER's retainer, the dowry...),
	# so an order never leaves the chest below zero.
	var needs := gold_cost(row) + OrderCosts.gold_of(data, req.action_code)
	if req.action_code == "BATTLE_ORDER" and req.params.get("kind", "") == "surrender":
		needs = 0
	if needs > 0 and BattleOrders.available_gold(state) < needs:
		return "Cannot afford %s (needs %d gold)" % [req.action_code, int(needs)]
	# A pool the cost row draws on cannot be spent below empty (the levy's
	# baggage train, spec §5): EventEffects adds the row straight into
	# metrics, so the refusal has to happen here.
	for pool: String in ["strategic", "civil"]:
		var metric := pool_metric(pool)
		var pool_needs := OrderCosts.metric_cost_of(data, req.action_code, metric)
		var stock := float(state.metrics.get(metric, 0.0))
		if pool_needs > stock:
			return "Cannot afford %s (needs %d %s goods, the stores hold %d)" % [
				req.action_code, int(pool_needs), pool, int(stock)]
	if row.get("target_type", "none") == "character" and not state.characters.has(req.target):
		return "No such target character for " + req.action_code
	match req.action_code:
		"KING_MOVE":
			return _validate_king_move(req)
		"KING_FOLLOW":
			return _validate_king_follow(req, state)
		"KING_SAFE_DEPARTURE":
			return _validate_king_safe_departure(req, state)
		"ARMY_RECRUIT":
			if req.target != "":
				return "Recruitment has no separate target character."
			var offer := RecruitmentSystem.quote(data, state, req.params)
			if BattleOrders.available_gold(state) < int(offer.get("gold", 0)):
				return "The recruitment price would spend reserved battlefield rewards."
			return String(offer.get("error", ""))
		"BUILD_ECONOMIC":
			if not req.params.get("project", "") in ["granary", "road"]:
				return "project must be granary|road"
		"CHARACTER_REWARD":
			if not req.params.get("mode", "gold") in ["gold"]:
				return "mode must be gold (slice 1)"
		"MANOR_BUY", "MANOR_SELL", "MANOR_BUILD", "MANOR_SEIZE", "MANOR_FOCUS", "MANOR_DEMOLISH", "MANOR_RUSH", "WORKSHOP_RATE":
			return _validate_manor(req, state, needs)
		"ARMY_MARCH", "ARMY_GARRISON", "ARMY_SEAT":
			return _validate_army(req, state)
		"BATTLE_ORDER":
			return _validate_battle_order(req, state)
		"BATTLE_TASK", "BATTLE_TASK_CANCEL":
			return _validate_task(req, state)
		"BATTLE_FORMATION":
			return _validate_formation(req, state)
		"ARMY_STANCE":
			return _validate_stance(req, state)
		"SUPPLY_POINT_SET", "SUPPLY_POINT_CLEAR", "SUPPLY_CARRY_SET":
			return _validate_supply(req, state)
		"LAW_SET":
			return _validate_law(req, state)
		"GOVERNOR_SET":
			var flow := String(req.params.get("flow", ""))
			if not data.ledger_governance.has(flow):
				return "No such flow: " + flow
			var who := String(req.params.get("character", ""))
			if not who in state.council.values() or not state.characters.has(who):
				return "Only a councillor can govern %s" % String(data.ledger_governance[flow]["label"])
			if who == Governance.governor_of(data, state, flow):
				return "He already governs %s" % String(data.ledger_governance[flow]["label"])
		"LEDGER_AUDIT":
			var flow := String(req.params.get("flow", ""))
			if not data.ledger_governance.has(flow):
				return "No such flow: " + flow
			var label := String(data.ledger_governance[flow]["label"])
			# The building works keep no books (M5 ruling): nothing to audit
			# until their master has a skim to hide.
			if not Governance.keeps_books(data, flow):
				return "%s keeps no books to audit" % (label.left(1).to_upper() + label.substr(1))
			if Governance.governor_of(data, state, flow) == "":
				return "No one governs %s: there are no books to audit" % label
		"TRADE_ROUTE_SET":
			var k := str(req.params.get("kingdom", ""))
			# A missing or unknown kingdom is refused on its own (final fix
			# wave, I2b): the "no trade route to %s" wording below is for a
			# REAL kingdom the realm merely has no route to, and reads oddly
			# ("to " with nothing after it) for an empty or made-up code.
			if k == "" or not data.kingdoms.has(k):
				return "No such kingdom" if k == "" else "No such kingdom: " + k
			var route := {}
			for r: Dictionary in MarketSystem.routes(data, state):
				if String(r["kingdom"]) == k:
					route = r
			if route.is_empty():
				return "The realm has no trade route to %s" % MarketSystem.label_of(data, k)
			# open must be exactly 0/1 or "0"/"1" (final fix wave, I2b): a
			# stray value must never fall through int()'s own leniency
			# (int("abc") is 0, which would silently CLOSE the route).
			var open_raw: Variant = req.params.get("open")
			var open := -1
			if (open_raw is int or open_raw is float) and int(open_raw) in [0, 1]:
				open = int(open_raw)
			elif open_raw is String and String(open_raw) in ["0", "1"]:
				open = int(String(open_raw))
			if open == -1:
				return "open must be 0 or 1"
			if bool(route["open"]) == (open == 1):
				return "The trade with %s is already %s" % [MarketSystem.label_of(data, k),
					"open" if open == 1 else "closed"]
		"GOODS_BUY", "GOODS_SELL":
			var pool := String(req.params.get("pool", ""))
			if not pool in ["strategic", "civil"]:
				return "pool must be strategic|civil"
			var gold := int(req.params.get("gold", 0))
			if gold <= 0:
				return "gold must be a whole number above zero"
			# At a market (M6): only one the realm holds now.
			if req.params.has("market") and not MarketSystem.is_realm_market(data, state, req.params["market"]):
				return "No market of the realm is market %s" % MarketSystem.market_key(req.params["market"])
			if req.action_code == "GOODS_BUY":
				var price := goods_trade_gold(req, state)
				if BattleOrders.available_gold(state) < price + needs:
					# A market's price is its own basket, not the factor's flat
					# rate (final fix wave, Minor9): the refusal must not name
					# a cut the market never takes.
					if req.params.has("market"):
						return "Cannot afford %d gold of %s goods%s (%d gold)" % [gold, pool, _at_market(req), price]
					return "Cannot afford %d gold of %s goods (%d with the factor's cut)" % [gold, pool, price]
			else:
				var have := int(state.metrics.get(pool_metric(pool), 0.0))
				if have < gold:
					return "The %s stock holds only %d gold of goods" % [pool, have]
		"SPY_SEND":
			var to := Vector2(float(req.params.get("x", -1.0)), float(req.params.get("y", -1.0)))
			var w := float(data.map_info.get("width", "0"))
			var h := float(data.map_info.get("height", "0"))
			if to.x < 0.0 or to.y < 0.0 or (w > 0.0 and to.x > w) or (h > 0.0 and to.y > h):
				return "That is off the map"
			if data.bal("spy_refuse_controlled") > 0.0 and SpySystem.is_controlled(data, state, to):
				return "The crown's own lands need no spy"
			if BattleOrders.available_gold(state) < needs + float(CourierSystem.fee_gold(data, CourierSystem.SPY)):
				return "The chancery cannot pay a spy to ride"
			# A spy out past the fuse is lost with his fee (final review M15):
			# refuse the ride he could never finish.
			var days := CourierSystem.spy_eta_days(data, state, to)
			if days > int(data.bal("courier_max_days")):
				return "No spy could get there within %d days (about %d)" % [
					int(data.bal("courier_max_days")), days]
	return ""

## ARMY_MARCH / ARMY_GARRISON (owner 2026-09-22). Both name a regiment of
## the player's own realm; a march also names where, and that place has to be
## ground the regiment can stand on — land for a column, the sea for a fleet.
## A banner with nobody under arms is refused outright rather than left
## crawling toward a place it can never reach, because day_step_m is 0 for it
## and march_day would carry the order forever.
## An army order's PLACE alone — whose regiment, whether it can march, where
## to — never the purse: a war-room draft costs nothing until it is sealed
## (spec 2026-10-02-war-room-v2 §3.1), so a pencil is refused only for a
## place no seal could ever send it to.
func validate_place(req: ActionRequest, state: GameState) -> String:
	return _validate_army(req, state, false)


func _validate_king_move(req: ActionRequest) -> String:
	if not req.params.has("x_m") or not req.params.has("y_m"):
		return "KING_MOVE needs whole metre x_m and y_m coordinates"
	for key: String in ["x_m", "y_m"]:
		var value: Variant = req.params[key]
		if not value is int:
			return "%s must be a whole metre coordinate" % key
	var route: Array = req.params.get("route_m", [])
	if route.size() > int(data.bal("army_march_waypoints_max")) + 1:
		return "The king's route has too many waypoints"
	var points: Array = route.duplicate()
	if points.is_empty() or points.back() != Vector2i(int(req.params["x_m"]), int(req.params["y_m"])):
		points.append(Vector2i(int(req.params["x_m"]), int(req.params["y_m"])))
	for p: Variant in points:
		if not p is Vector2i:
			return "King route points must be whole metre coordinates"
		var px := ArmySystem.metres_to_pack(data, p)
		if px.x < 0.0 or px.y < 0.0 or px.x >= float(data.map_info.get("width", 0)) \
				or px.y >= float(data.map_info.get("height", 0)):
			return "The king's route leaves the map"
	return ""


func _validate_king_follow(req: ActionRequest, state: GameState) -> String:
	var code := String(req.params.get("regiment", ""))
	var reg := ArmySystem.regiment(data, code, state)
	if reg.is_empty() or ArmySystem.is_foe(state, code) \
			or String(reg.get("kingdom_code", "")) != data.resolve_realm("player_realm"):
		return "The king can only follow a friendly regiment"
	var live_entry: Dictionary = state.regiments.get(code, {})
	if not state.army_roster.has(code) or String(live_entry.get("camp_town", reg.get("camp_town", ""))) != "":
		return "The king can only follow a regiment in the field"
	if ArmySystem.base_pace_km(data, reg) <= 0:
		return "A regiment without troops cannot be followed"
	return ""


func _validate_king_safe_departure(req: ActionRequest, state: GameState) -> String:
	var battle_id := int(req.params.get("battle_id", -1))
	return "The king is not present at that battle" if not KingSystem.present(data, state, battle_id) else ""


func _validate_army(req: ActionRequest, state: GameState, check_purse := true) -> String:
	var code := String(req.params.get("regiment", ""))
	var reg := ArmySystem.regiment(data, code, state)
	if reg.is_empty():
		return "No such regiment: " + code
	if ArmySystem.is_foe(state, code) or String(reg["kingdom_code"]) != data.resolve_realm("player_realm"):
		return "%s is not yours to command" % String(reg["label"])
	# The order rides by courier (owner 2026-09-27): his fee is paid from the
	# crown's chest ON TOP of the order's own always-charged cost (fix round 1:
	# the two were checked independently against the same treasury, so an
	# order could still drive it negative — MANOR_BUY's own pattern, gold_of
	# summed with the extra spend, is the fix), so an order the chest cannot
	# cover in full is refused, not sent into the red.
	if check_purse and CourierSystem.carries_orders(reg) and BattleOrders.available_gold(state) \
			< OrderCosts.gold_of(data, req.action_code) + float(_fee_for(state, code)):
		return "The chancery cannot pay a courier to ride for %s" % String(reg["label"])
	if req.action_code == "ARMY_SEAT":
		if not CourierSystem.carries_orders(reg):
			return "%s has no town to enter" % String(reg["label"])
		var town := ArmyGround.camped_by(data, state, code)
		if town == "":
			return "%s does not camp by a town of the realm" % String(reg["label"])
		if ArmyGround.seat_of(data, state, town) == code:
			return "%s already holds %s" % [String(reg["label"]), String(data.burgs[town].get("label", town))]
		return ""
	if req.action_code == "ARMY_GARRISON":
		return ""
	if state.military_rosters.has(code):
		var commander := String(state.military_rosters.get(code, {}).get("commander_id", ""))
		if commander == "" or not MilitaryCommanders.eligible_for_unit(data, state, code, commander):
			return "%s needs an eligible commander before departure" % String(reg["label"])
	if ArmySystem.base_pace_km(data, reg) <= 0:
		return "%s has no one under arms to march" % String(reg["label"])
	var dest := Vector2(float(req.params.get("x", -1.0)), float(req.params.get("y", -1.0)))
	var why := _place_refusal(reg, dest, "That is off the map", "%s cannot march into the sea")
	if why != "":
		return why
	# its waypoints, each checked as the end is (spec 2026-10-07-march-waypoints ruling 3)
	var wps := waypoints_of(req)
	if wps.size() > int(data.bal("army_march_waypoints_max")):
		return "A march takes at most %d waypoints" % int(data.bal("army_march_waypoints_max"))
	for wp: Vector2 in wps:
		why = _place_refusal(reg, wp, "That waypoint is off the map", "%s cannot march through the sea")
		if why != "":
			return why
	if wps.is_empty() and ArmySystem.position_of(data, state, reg).distance_to(dest) < 1.0:
		return "%s is already there" % String(reg["label"])
	return ""


## Why `reg` cannot be sent to `at` (pack px): off the map, or ground it
## cannot stand on — land for a column, the sea for a fleet. "" when it can.
func _place_refusal(reg: Dictionary, at: Vector2, off_map: String, into_sea: String) -> String:
	var w := float(data.map_info.get("width", "0"))
	var h := float(data.map_info.get("height", "0"))
	if at.x < 0.0 or at.y < 0.0 or (w > 0.0 and at.x > w) or (h > 0.0 and at.y > h):
		return off_map
	var naval := String(reg.get("is_naval", "0")) == "1"
	# Columns retain the settlement shoreline tolerance; fleets need the
	# exact boundary so a port's nearby sea remains a legal destination.
	var on_land := MapEconomy.contains_land(data, at) if naval else MapEconomy.cell_at(data, at) >= 0
	if naval and on_land:
		return "%s is a fleet and cannot be sent inland" % String(reg["label"])
	if not naval and not on_land:
		return into_sea % String(reg["label"])
	return ""

func _task_warrant(req: ActionRequest) -> Dictionary:
	return {"id": req.params.get("request_id", ""), "unit": req.params.get("regiment", ""),
		"battle_id": req.params.get("battle_id", -1),
		"task": "cancel" if req.action_code == "BATTLE_TASK_CANCEL" else req.params.get("task", ""),
		"formation": req.params.get("formation", "") if req.action_code == "BATTLE_TASK" else "",
		"target_unit": req.params.get("target_unit", ""), "source": "player", "issuer": "",
		"max_route_m": req.params.get("max_route_m", 0) if req.action_code == "BATTLE_TASK" else 0,
		"region": req.params.get("region", "") if req.action_code == "BATTLE_TASK" else ""}

func _task_replay(req: ActionRequest, state: GameState) -> Dictionary:
	if not req.params.get("request_id", "") is String:
		return {"error": "A unit task request id must be text."}
	var record := BattleTaskSystem._find(state, String(req.params.get("request_id", "")))
	if record.is_empty():
		return {}
	if req.target != "" or not record.has("action_params") or record["action_params"] != req.params \
			or record["action_outcome"]["action_code"] != req.action_code:
		return {"error": "This request id already names another unit task."}
	return {"outcome": record["action_outcome"].duplicate(true)}

func _validate_task(req: ActionRequest, state: GameState) -> String:
	if req.target != "":
		return "A unit task has no separate character target."
	var fields := ["request_id", "regiment", "battle_id"]
	if req.action_code == "BATTLE_TASK":
		fields.append_array(["task", "target_unit", "formation", "max_route_m", "region"])
		if req.params.get("task", "") == "cancel":
			return "Use BATTLE_TASK_CANCEL to cancel a unit task."
	for field: Variant in req.params:
		if not field in fields:
			return "Unknown unit task parameter."
	var why := BattleTaskSystem.refusal_of(data, state, _task_warrant(req))
	if why != "":
		return why
	var code := String(req.params["regiment"])
	var reg := ArmySystem.regiment(data, code, state)
	if ArmySystem.realm_of(data, code, state) != data.resolve_realm("player_realm") \
			or not CourierSystem.carries_orders(reg):
		return "This field unit is not yours to command."
	if BattleOrders.available_gold(state) < OrderCosts.gold_of(data, req.action_code) + _fee_for(state, code):
		return "The chancery cannot pay for this unit task."
	return ""


func _battle_warrant(req: ActionRequest, state: GameState) -> Dictionary:
	var battle := BattleSystem.battle_by_id(state, int(req.params.get("battle_id", -1)))
	return {"id": String(req.params.get("request_id", "")), "battle_id": int(req.params.get("battle_id", -1)),
		"side": BattleRules.side_of(battle, String(req.params.get("regiment", ""))),
		"kind": String(req.params.get("kind", "")), "issued_day": state.absolute_day(),
		"params": req.params.duplicate(true)}

func _battle_replay(req: ActionRequest, state: GameState) -> Dictionary:
	var id := String(req.params.get("request_id", ""))
	if not state.battle_orders.has(id):
		return {}
	var record: Dictionary = state.battle_orders[id]
	if req.target != "" or record["request"]["params"] != req.params:
		return {"error": "This request id already names another battlefield warrant."}
	return {"outcome": record.get("action_outcome", {}).duplicate(true)}

func _validate_battle_order(req: ActionRequest, state: GameState) -> String:
	if req.target != "":
		return "A battlefield warrant has no separate character target."
	var code := String(req.params.get("regiment", ""))
	var reg := ArmySystem.regiment(data, code, state)
	if reg.is_empty() or not state.regiments.has(code) or ArmySystem.is_foe(state, code) or ArmySystem.realm_of(data, code, state) != data.resolve_realm("player_realm"):
		return "This army is not yours to command."
	if not CourierSystem.carries_orders(reg):
		return "A fleet cannot receive a field battle warrant."
	var quote := BattleOrders.preview(data, state, _battle_warrant(req, state))
	if quote["reason"] != "":
		return String(quote["reason"])
	var fee := _fee_for(state, code)
	var reserve := int(quote["reserved_gold"])
	var filing := OrderCosts.gold_of(data, req.action_code) if fee == 0 and reserve == 0 and req.params.get("kind", "") != "surrender" else 0.0
	if reserve + fee + filing > 0 and BattleOrders.available_gold(state) < reserve + fee + filing:
		return "The treasury cannot pay this warrant and reserve its battlefield reward."
	return ""

func _validate_formation(req: ActionRequest, state: GameState) -> String:
	var code := String(req.params.get("regiment", ""))
	var reg := ArmySystem.regiment(data, code, state)
	if reg.is_empty() or not state.regiments.has(code) or ArmySystem.is_foe(state, code) \
			or String(reg.get("kingdom_code", "")) != data.resolve_realm("player_realm"):
		return "This army is not yours to command."
	var id := int(req.params.get("battle_id", -1))
	var battle := BattleSystem.battle_by_id(state, id)
	var side := BattleRules.side_of(battle, code)
	var why := BattleFormation.refusal(data, state, id, side, String(req.params.get("formation", "")))
	if why != "":
		return why
	if BattleOrders.available_gold(state) < OrderCosts.gold_of(data, req.action_code) + _fee_for(state, code):
		return "The chancery cannot pay for this formation order."
	return ""


## ARMY_STANCE (spec 2026-10-07-enemy-ai-and-battle §4.4): a land regiment
## of the realm (never a foe), a courier the chest can pay, and a stance of
## data/battle/battle_stances.csv.
func _validate_stance(req: ActionRequest, state: GameState) -> String:
	var code := String(req.params.get("regiment", ""))
	var reg := ArmySystem.regiment(data, code, state)
	if reg.is_empty():
		return "No such regiment: " + code
	if ArmySystem.is_foe(state, code) or String(reg["kingdom_code"]) != data.resolve_realm("player_realm"):
		return "%s is not yours to command" % String(reg["label"])
	if not CourierSystem.carries_orders(reg):
		return "%s is a fleet: it takes no battle stance" % String(reg["label"])
	var stance := String(req.params.get("stance", ""))
	if not data.battle_stances.has(stance):
		return "No such stance: " + stance
	if req.params.has("facing") and (int(req.params["facing"]) < 0 or int(req.params["facing"]) > 359):
		return "No such facing: %s" % str(req.params["facing"])   # a whole degree 0..359 (WarFront)
	if BattleOrders.available_gold(state) < OrderCosts.gold_of(data, req.action_code) \
			+ float(_fee_for(state, code)):
		return "The chancery cannot pay a courier to ride for %s" % String(reg["label"])
	return ""



## An ARMY_MARCH's waypoints in pack px, in order: params.waypoints as
## [[x, y], …] (or Vector2s); [] for none.
static func waypoints_of(req: ActionRequest) -> Array:
	var out: Array = []
	for w: Variant in req.params.get("waypoints", []):
		if w is Vector2:
			out.append(w)
		elif w is Array and (w as Array).size() >= 2:
			out.append(Vector2(float(w[0]), float(w[1])))
	return out

## The supply orders (spec 2026-10-07-army-supply-lines §4): a land regiment
## of the realm, a courier the chest can pay, and a point / rate / load the
## tables allow.
func _validate_supply(req: ActionRequest, state: GameState) -> String:
	var code := String(req.params.get("regiment", ""))
	var reg := ArmySystem.regiment(data, code, state)
	if reg.is_empty():
		return "No such regiment: " + code
	if ArmySystem.is_foe(state, code) or String(reg["kingdom_code"]) != data.resolve_realm("player_realm"):
		return "%s is not yours to command" % String(reg["label"])
	if String(reg.get("is_naval", "0")) == "1":
		return "%s is a fleet: it carries no supply train" % String(reg["label"])
	var local_ok := (req.action_code == "SUPPLY_CARRY_SET" or (req.action_code == "SUPPLY_POINT_SET"
		and bool(req.params.get("with_column", false)))) and KingSystem.can_command(data, state, code)
	if BattleOrders.available_gold(state) < OrderCosts.gold_of(data, req.action_code) \
			+ float(_fee_for(state, code, local_ok)):
		return "The chancery cannot pay a courier to ride for %s" % String(reg["label"])
	match req.action_code:
		"SUPPLY_POINT_SET":
			var rate := int(req.params.get("rate", 0))
			if not rate in SupplyLines.RATES:
				return "The wagons run at 0.8×, 1× or 1.2×"
			var town := String(req.params.get("town", ""))
			# never a town AHEAD of the column where it stands as the order is
			# run (ruling 20; a stale draft or a column that has moved since the
			# pick): such a line would break the day it flowed
			var why := String(SupplyLines.mark_ahead(data, state, code,
				SupplyLines.eligibility(data, state, code)).get(town, "That is no town of the realm"))
			if why != "":
				return why
		"SUPPLY_POINT_CLEAR":
			if SupplyLines.line(state, code).is_empty():
				return "%s has no supply point" % String(reg["label"])
		"SUPPLY_CARRY_SET":
			var days := int(req.params.get("days", 0))
			if not data.army_carry_loads.any(func(r: Dictionary) -> bool: return int(r["days"]) == days):
				return "A train carries 10, 15, 20, 25 or 30 days"
	return ""

## LAW_SET (spec 2026-10-08-laws-tab-design §3): a law, one of its values,
## not the decreed one (unless places still miss it, plan ruling R5), off
## cooldown, somewhere to send it, and a chest that pays every courier —
## LawSystem.refusal, the screen's preview's own words.
func _validate_law(req: ActionRequest, state: GameState) -> String:
	# str(), not String(): a model may send a number or null for either
	var law := str(req.params.get("law", ""))
	var value := LawSystem.canonical(data, law, req.params.get("value", ""))
	var why := LawSystem.refusal(data, state, law, value)
	if why != "":
		return why
	var quote := LawSystem.preview(data, state, law, value)
	if BattleOrders.available_gold(state) < int(quote.get("gold", 0)) + int(quote.get("fee", 0)):
		return "The treasury cannot spend the reserved battlefield rewards on this decree."
	return ""

## The manor an order names: params.manor (a code, a label in any case, or
## a cell id) or params.cell. -1 for none.
func manor_of(req: ActionRequest) -> int:
	var named := str(req.params.get("manor", req.params.get("cell", "")))
	return MapManors.find(data, named)

## The metric that holds a pool: strategic -> strategic, civil -> grain
## (the civil pool's key, kept for its readers; spec §5).
## The treasury's side of a GOODS_BUY (what it pays) or GOODS_SELL (what it
## gets), whole gold: at a realm market (`market`, M6) that market's price
## (MarketSystem.buy_price / sell_price), else the flat factor's spread.
func goods_trade_gold(req: ActionRequest, state: GameState) -> int:
	var pool := String(req.params.get("pool", ""))
	var gold := int(req.params.get("gold", 0))
	var buying := req.action_code == "GOODS_BUY"
	if req.params.has("market"):
		var id := MarketSystem.market_key(req.params["market"])
		return MarketSystem.buy_price(data, id, pool, gold) if buying \
			else MarketSystem.sell_price(data, state, id, pool, gold)
	var spread := data.bal("goods_trade_spread")
	return int(roundf(float(gold) * (1.0 + spread if buying else 1.0 - spread)))

## " at <the market's town>" for a trade at a market, else "".
func _at_market(req: ActionRequest) -> String:
	if not req.params.has("market"):
		return ""
	var id := MarketSystem.market_key(req.params["market"])
	var burg := String((data.world_table("economy", "markets").get(id, {}) as Dictionary).get("center_burg", ""))
	return " at the market of " + String((data.burgs.get(burg, {}) as Dictionary).get("label", burg))

static func pool_metric(pool: String) -> String:
	return "strategic" if pool == "strategic" else "grain"

## MANOR_SYSTEM.md §5: a manor must exist and lie in the crown's realm; the
## crown buys or seizes what it does not hold and sells or builds on what it
## does; a purchase or a building must be affordable on top of the order's
## own cost; seizing is gated by manor_seize_enabled until the military
## system can resolve it.
func _validate_manor(req: ActionRequest, state: GameState, needs: float) -> String:
	var cell := manor_of(req)
	if cell < 0:
		return "No such manor: %s" % str(req.params.get("manor", req.params.get("cell", "")))
	var label := MapManors.label_of(data, cell)
	var realm := data.resolve_realm("player_realm")
	var crowns := MapManors.is_crowns(data, state, cell)
	# Buying has its own map (owner 2026-09-14): your own province and the
	# realm's provinces bordering it from your own purse; a manor touching
	# the realm from across the border from the crown's treasury.
	if req.action_code == "MANOR_BUY":
		if crowns:
			return "The crown already holds %s" % label
		var how := MapManors.purchase_kind(data, state, cell)
		if String(how["kind"]) == "":
			return String(how["error"])
		var price := MapManors.price_of(data, state, cell)
		var asks := "House %s asks %d gold" % [MapManors.owner_of(data, state, cell), int(price)]
		if String(how["kind"]) == "foreign":
			if BattleOrders.available_gold(state) < price + needs:
				return "The crown's treasury cannot afford %s (%s)" % [label, asks]
		elif float(state.metrics.get("lord_gold", 0.0)) < price:
			return "Your own purse cannot afford %s (%s)" % [label, asks]
		return ""
	if MapOwnership.owner_of(data, state, MapManors.province_of(data, cell, state)) != realm:
		return "%s lies outside the realm" % label
	match req.action_code:
		"MANOR_SEIZE":
			if data.bal("manor_seize_enabled") <= 0.0:
				return "Seizing manors is not permitted"
			if crowns:
				return "The crown already holds %s" % label
		"MANOR_SELL":
			if not crowns:
				return "The crown does not hold %s" % label
			var buyer := MapManors.default_owner(data, state, cell)
			if buyer == "" or buyer == MapManors.crown(state):
				return "No house to sell %s to" % label
		"MANOR_BUILD":
			if not crowns:
				return "The crown does not hold %s" % label
			# Building needs the province, not just the manor (owner 2026-09-13):
			# the crown improves the land it controls.
			if not MapManors.crown_controls(data, state, MapManors.province_of(data, cell, state)):
				return "%s lies in a province the crown does not control" % label
			var building := String(req.params.get("building", ""))
			if not data.manor_buildings.has(building):
				return "No such building: " + building
			# The ground and the buildings it needs come first (owner 2026-09-14).
			var blocked := MapManors.building_blocked(data, state, cell, building)
			if blocked != "":
				return blocked
			if MapManors.has_building(state, cell, building):
				return "%s already has a %s" % [label, String(data.manor_buildings[building]["label"]).to_lower()]
			if MapManors.is_building(state, cell, building):
				return "A %s is already being built at %s" % [String(data.manor_buildings[building]["label"]).to_lower(), label]
			if MapManors.free_slots(data, state, cell) <= 0:
				return "%s has no room: %d of %d slots taken" % [label, MapManors.slots_used(state, cell),
					MapManors.slots_of(data, cell)]
			var civil := int(float(data.manor_buildings[String(req.params.get("building", ""))].get("civil_cost", 0)))
			if int(state.metrics.get("lord_civil", 0.0)) < civil:
				return "Not enough of your own civil goods for a %s at %s (%d needed)" % [
					String(data.manor_buildings[String(req.params.get("building", ""))]["label"]).to_lower(), label, civil]
		"MANOR_RUSH":
			if not crowns:
				return "%s is not the crown's" % label
			var building_r := String(req.params.get("building", ""))
			# 0 is a work whose days are up but which the day step has not
			# turned into a building yet: there is nothing left to hurry.
			if MapManors.work_days_left(data, state, cell, building_r) <= 0:
				return "There is no work left on a %s at %s" % [building_r, label]
			var days := int(req.params.get("days", 0))
			if days <= 0:
				return "days must be a whole number above zero"
			var price := days * int(data.bal("build_rush_gold_per_day"))
			if float(state.metrics.get("lord_gold", 0.0)) < price:
				return "Your own purse cannot afford to hurry %s by %d days (%d gold)" % [label, days, price]
		"MANOR_DEMOLISH":
			if not crowns:
				return "The crown does not hold %s" % label
			var building := String(req.params.get("building", ""))
			if not data.manor_buildings.has(building):
				return "No such building: " + building
			if not MapManors.has_building(state, cell, building) and not MapManors.is_building(state, cell, building):
				return "There is no %s at %s" % [String(data.manor_buildings[building]["label"]).to_lower(), label]
		"MANOR_FOCUS":
			if not crowns:
				return "The crown does not hold %s" % label
			if not MapManors.crown_controls(data, state, MapManors.province_of(data, cell, state)):
				return "%s lies in a province the crown does not control" % label
			var focus := String(req.params.get("focus", ""))
			if not data.manor_focus.has(focus):
				return "No such focus: " + focus
			var name := String(data.manor_focus[focus]["label"]).to_lower()
			if not MapManors.focus_allowed(data, cell, focus):
				return "%s cannot work %s on its land" % [label, name]
			if MapManors.focus_of(data, state, cell) == focus:
				return "%s already works %s" % [label, name]
			var fee := float(data.manor_focus[focus]["switch_cost_gold"])
			if float(state.metrics.get("lord_gold", 0.0)) < fee:
				return "Your own purse cannot afford to turn %s to %s (%d gold)" % [label, name, int(fee)]
		"WORKSHOP_RATE":
			if not crowns:
				return "The crown does not hold %s" % label
			if not WorkshopSystem.BUILDING in MapManors.buildings_of(state, cell):
				return "%s has no war workshop" % label
			var rate := int(req.params.get("rate", -1))
			if not rate in WorkshopSystem.rates(data):
				var words: Array = []
				for r: int in WorkshopSystem.rates(data):
					words.append(WorkshopSystem.rate_word(data, r))
				return "A war workshop runs " + ", ".join(words)
			if rate == WorkshopSystem.rate_of(state, cell):
				return "The war workshop at %s already runs %s" % [label, WorkshopSystem.rate_word(data, rate)]
	return ""

## Fee and negotiated transfers commit together; paid retries return before all action side effects.
func _prisoner_action(req: ActionRequest, state: GameState, commit: bool) -> Dictionary:
	var failed := {"action_code": req.action_code, "ok": false}
	var command := req.action_code.trim_prefix("PRISONER_").to_lower()
	var id: Variant = req.params.get("id" if command == "propose" else "proposal_id")
	if not data.actions.has(req.action_code) or req.target != "" or not id is String or String(id).is_empty():
		failed["error"] = "Prisoner commands need a proposal ID and no character target."
		return failed
	var player := data.resolve_realm("player_realm")
	if command == "propose":
		if not req.params.get("parties") is Dictionary or req.params.parties.get("proposer") != player:
			failed["error"] = "Only the player's realm can propose its prisoner disposition."
			return failed
	else:
		if not state.prisoner_proposals.has(id) or not player in state.prisoner_proposals[id].frozen.required_parties:
			failed["error"] = "The player's realm is not a party to this proposal."
			return failed
		if command == "respond" and not req.params.get("accepted") is bool:
			failed["error"] = "A prisoner response needs a boolean acceptance."
			return failed
	var previous: Dictionary = state.prisoner_proposals.get(id, {}).get("action_outcomes", {}).get(command, {})
	if not previous.is_empty():
		if previous.request != req.to_dict():
			failed["error"] = "This proposal command already freezes a different request."
			return failed
		return previous.outcome.duplicate(true)
	var fee := int(OrderCosts.gold_of(data, req.action_code))
	if BattleOrders.available_gold(state) < fee:
		failed["error"] = "The treasury cannot afford the prisoner clerk's fee."
		return failed
	var candidate := GameState.from_dict(state.to_dict(), false)
	var reason := String(data.order_costs[req.action_code].cost).split(":", true, 2)[2]
	var paid := WorldLedger.apply(data, candidate, "metrics.treasury", -fee, reason, req.action_code)
	if paid.has("error") or float(paid.get("delta", 0)) != -fee:
		failed["error"] = "The complete prisoner clerk's fee could not be paid."
		return failed
	var result: Dictionary
	match command:
		"propose": result = PrisonerCommunications.propose(data, candidate, req.params)
		"respond": result = PrisonerDisposition.respond(data, candidate, id, player, req.params.accepted)
		"settle": result = PrisonerCommunications.fulfill(data, candidate, id)
	if result.has("error"):
		failed["error"] = result.error
		return failed
	if command == "respond" and candidate.prisoner_proposals[id].has("communications"):
		var communication: Dictionary = candidate.prisoner_proposals[id].communications
		if communication.visible_status in ["proposed", "accepted"] and result.status in ["proposed", "accepted", "rejected"]:
			communication.visible_status = result.status
		result.status = PrisonerCommunications.projection(candidate, id).status
	var effects: Array = [{"kind": "world", "path": "metrics.treasury", "delta": -fee, "reason": reason}]
	effects.append_array(result.get("effects", []))
	var outcome := GameState._whole({"action_code": req.action_code, "ok": true, "effects": effects,
		"notes": data.actions[req.action_code].label, "target": req.target, "params": req.params.duplicate(true),
		"drift": [], "prisoner_result": result}) as Dictionary
	if not candidate.prisoner_proposals[id].has("action_outcomes"):
		candidate.prisoner_proposals[id]["action_outcomes"] = {}
	candidate.prisoner_proposals[id].action_outcomes[command] = {"request": req.to_dict().duplicate(true), "outcome": outcome.duplicate(true)}
	if not commit:
		return outcome
	for field: String in ["prisoner_batches", "prisoner_events", "prisoner_proposals", "unit_prize_gold",
			"military_cohorts", "military_rosters", "military_events", "metrics", "world", "world_log", "relationships",
			"couriers", "next_courier_id"]:
		state.set(field, candidate.get(field))
	for person: String in state.characters:
		(state.characters[person] as Character).opinion = (candidate.characters[person] as Character).opinion
		(state.characters[person] as Character).opinion_log = (candidate.characters[person] as Character).opinion_log
	if not state.event_state.has("last_action_tick"):
		state.event_state["last_action_tick"] = {}
	state.event_state.last_action_tick[req.action_code] = state.tick
	state.recent_outcomes.append(outcome.duplicate(true))
	return outcome

func execute(req: ActionRequest, state: GameState) -> Dictionary:
	if req.action_code in ["PRISONER_PROPOSE", "PRISONER_RESPOND", "PRISONER_SETTLE"]:
		return _prisoner_action(req, state, true)
	if req.action_code in ["BATTLE_TASK", "BATTLE_TASK_CANCEL"]:
		var replay := _task_replay(req, state)
		if replay.has("error"):
			return {"action_code": req.action_code, "ok": false, "error": replay["error"]}
		if not replay.is_empty():
			return replay["outcome"]
	if req.action_code == "BATTLE_ORDER":
		var replay := _battle_replay(req, state)
		if replay.has("error"):
			return {"action_code": req.action_code, "ok": false, "error": replay["error"]}
		if not replay.is_empty():
			return replay["outcome"]
	# A paid retry must not replay opinion drift, promises, history or fallback fees.
	if req.action_code == "ARMY_RECRUIT" and req.target == "":
		var previous := RecruitmentSystem.replay(state, req.params)
		if previous.has("error"):
			return {"action_code": req.action_code, "ok": false, "error": previous["error"]}
		if not previous.is_empty():
			var id := String(req.params["request_id"])
			return (state.recruitment_projects[id]["action_outcome"] as Dictionary).duplicate(true) \
				if state.recruitment_projects[id].has("action_outcome") else previous
	var err := validate(req, state)
	if req.action_code in ["ARMY_RECRUIT", "BATTLE_ORDER", "BATTLE_TASK", "BATTLE_TASK_CANCEL"] and err != "":
		return {"action_code": req.action_code, "ok": false, "error": err}
	assert(err == "", "execute called with invalid request: " + err)
	var row: Dictionary = data.actions[req.action_code]
	# Opinions before, so a direct loss (a punishment) counts as this order's
	# cost without changing the effects shape (OrderCosts).
	var before := OrderCosts.snapshot_opinions(state)
	var effects: Array = []
	var cost := gold_cost(row)
	if cost > 0.0:
		_apply(state, effects, "treasury", -cost, "paid for " + String(row["label"]))
	# what the opinion drift reads: the request's params, a law's with its
	# direction (LAW_SET's signature variants, data/realm/action_signatures.csv)
	var sig_params := req.params
	match req.action_code:
		"KING_MOVE":
			var route: Array = req.params.get("route_m", []).duplicate()
			var destination := Vector2i(int(req.params["x_m"]), int(req.params["y_m"]))
			if route.is_empty() or route.back() != destination:
				route.append(destination)
			KingSystem.set_route(data, state, route, "the king's movement order")
			effects.append({"metric": "army", "delta": 0.0, "reason": "the king begins a journey from his present position"})
		"KING_FOLLOW":
			var follow_result := KingSystem.follow(data, state, String(req.params["regiment"]))
			if follow_result.get("status") != "ok":
				return {"action_code": req.action_code, "ok": false,
					"error": String(follow_result.get("error", "The king cannot follow that regiment."))}
			effects.append({"metric": "army", "delta": 0.0, "reason": "the king rides to join %s" % String(req.params["regiment"])})
		"KING_SAFE_DEPARTURE":
			var departure_result := KingSystem.safe_departure(data, state, int(req.params["battle_id"]))
			if departure_result.get("status") != "ok":
				return {"action_code": req.action_code, "ok": false,
					"error": String(departure_result.get("error", "The king cannot leave safely."))}
			effects.append({"metric": "army", "delta": 0.0, "reason": "the king withdraws safely; the battle continues unchanged"})
		"ARMY_RECRUIT":
			var paid := RecruitmentSystem.recruit(data, state, req.params)
			if paid.has("error"):
				return {"action_code": req.action_code, "ok": false, "error": paid["error"]}
			effects.append_array(paid["effects"])
		"LEVY_RAISE":
			_apply(state, effects, "army_quality", data.bal("levy_army_gain"), "fresh levies drilled")
			_apply(state, effects, "unrest", data.bal("levy_unrest"), "villages resent the levy")
		"BUILD_ECONOMIC":
			if req.params["project"] == "granary":
				_apply(state, effects, "grain", data.bal("granary_civil_gain"), "a royal granary stocked")
			else:
				_apply(state, effects, "road_income_bonus", data.bal("road_income_gain"), "road improves trade")
		"SPY_MISSION":
			_apply(state, effects, "legitimacy", data.bal("spy_legitimacy_gain"), "rumors quietly answered")
		"COUNCIL_CONSULT":
			pass  # outcome record only; the Voicer renders the consult
		"CHARACTER_REWARD":
			var c: Character = state.characters[req.target]
			var gain := int(data.bal("reward_opinion"))
			if "vain" in c.traits:
				gain += int(data.bal("reward_opinion_vain_bonus"))
			c.change_opinion(gain, "rewarded with gold", state.tick)
		"CHARACTER_PUNISH":
			state.characters[req.target].change_opinion(
				int(data.bal("punish_opinion")), "publicly reprimanded", state.tick)
		"CHARACTER_CONFIDE":
			state.characters[req.target].change_opinion(
				int(data.bal("confide_opinion")), "you confided in them", state.tick)
		"MANOR_BUY":
			var cell := manor_of(req)
			var label := MapManors.label_of(data, cell)
			var seller := MapManors.owner_of(data, state, cell)
			var price := MapManors.price_of(data, state, cell)
			var how := MapManors.purchase_kind(data, state, cell)
			if String(how["kind"]) == "foreign":
				# Across the border (owner 2026-09-14): the crown's treasury pays,
				# the manor joins the richest province of the realm it touches, and
				# that province's house holds it.
				var into := String(how["province"])
				var into_label := String((data.provinces.get(into, {}) as Dictionary).get("label", into))
				_apply(state, effects, "treasury", -price, "bought %s across the border from House %s" % [label, seller])
				MapManors.annex(data, state, cell, into, "bought across the border for %d gold" % int(price))
				var holder := MapManors.default_owner(data, state, cell)
				MapManors.set_owner(data, state, cell, holder,
					"bought from House %s for %d gold and joined to %s" % [seller, int(price), into_label])
				effects.append({"metric": "manor", "delta": 1.0,
					"reason": "%s joins %s under %s, bought from House %s" % [label, into_label,
						"the crown" if holder == MapManors.crown(state) else "House " + holder, seller]})
			else:
				_apply(state, effects, "lord_gold", -price, "bought %s from House %s" % [label, seller])
				MapManors.set_owner(data, state, cell, MapManors.crown(state),
					"bought from House %s for %d gold" % [seller, int(price)])
				effects.append({"metric": "manor", "delta": 1.0,
					"reason": "%s is the crown's, bought from House %s" % [label, seller]})
			# A house paid well thinks better of the crown, and its councillor
			# is the richer for it.
			for c: Character in _house_members(state, seller):
				c.change_opinion(int(data.bal("manor_trade_goodwill")),
					"the crown paid well for %s" % label, state.tick)
				if state.council.values().has(c.id):
					c.change_attribute("wealth", int(data.bal("manor_trade_wealth")),
						"sold %s to the crown" % label, state.tick)
		"MANOR_SELL":
			var cell := manor_of(req)
			var label := MapManors.label_of(data, cell)
			var buyer := MapManors.default_owner(data, state, cell)
			var price := MapManors.sell_price_of(data, state, cell)
			_apply(state, effects, "lord_gold", price, "sold %s to House %s" % [label, buyer])
			MapManors.set_owner(data, state, cell, buyer, "sold to House %s for %d gold" % [buyer, int(price)])
			effects.append({"metric": "manor", "delta": -1.0,
				"reason": "%s passed to House %s" % [label, buyer]})
		"MANOR_BUILD":
			var cell := manor_of(req)
			var building := String(req.params["building"])
			var row_b: Dictionary = data.manor_buildings[building]
			var label := MapManors.label_of(data, cell)
			_apply(state, effects, "lord_civil", -float(int(float(row_b.get("civil_cost", 0)))),
				"timber and stone for a %s at %s" % [String(row_b["label"]).to_lower(), label])
			MapManors.start_work(data, state, cell, building, "begun by the crown")
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": "a %s is begun at %s, %d days' work" % [String(row_b["label"]).to_lower(), label,
					int(float(row_b.get("build_days", 0)))]})
		"MANOR_RUSH":
			var cell := manor_of(req)
			var building := String(req.params["building"])
			var days := int(req.params["days"])
			var label := MapManors.label_of(data, cell)
			var cut := MapManors.rush_work(data, state, cell, building, days, "hurried by the crown")
			_apply(state, effects, "lord_gold", -float(cut * int(data.bal("build_rush_gold_per_day"))),
				"hurried the %s at %s by %d days" % [building, label, cut])
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": "the %s at %s is %d days nearer done" % [building, label, cut]})
		"MANOR_DEMOLISH":
			var cell := manor_of(req)
			var building := String(req.params["building"])
			var row_d: Dictionary = data.manor_buildings[building]
			var label := MapManors.label_of(data, cell)
			var stood := MapManors.has_building(state, cell, building)
			var refund := MapManors.demolish(data, state, cell, building,
				"pulled down by the crown" if stood else "the work stopped by the crown")
			# A build is bought with civil goods: what comes back is goods.
			_apply(state, effects, "lord_civil", maxf(refund, 0.0),
				"the timber and stone of the %s at %s" % [String(row_d["label"]).to_lower(), label])
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": ("the %s at %s is pulled down" if stood else "the %s at %s is left unbuilt") % [
					String(row_d["label"]).to_lower(), label]})
		"MANOR_FOCUS":
			var cell := manor_of(req)
			var focus := String(req.params["focus"])
			var row_f: Dictionary = data.manor_focus[focus]
			var label := MapManors.label_of(data, cell)
			var was := String((data.manor_focus.get(MapManors.focus_of(data, state, cell), {}) as Dictionary).get("label", "nothing")).to_lower()
			_apply(state, effects, "lord_gold", -float(row_f["switch_cost_gold"]),
				"turned %s to %s" % [label, String(row_f["label"]).to_lower()])
			MapManors.set_focus(data, state, cell, focus, "turned from %s to %s by the crown" % [was, String(row_f["label"]).to_lower()])
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": "%s turns to %s; %d ticks to settle in" % [label, String(row_f["label"]).to_lower(), int(float(row_f["transition_ticks"]))]})
		"WORKSHOP_RATE":
			var cell := manor_of(req)
			var rate := int(req.params["rate"])
			WorkshopSystem.set_rate(state, cell, rate)
			effects.append({"metric": "manor", "delta": 0.0, "reason": "the war workshop at %s now runs %s"
				% [MapManors.label_of(data, cell), WorkshopSystem.rate_word(data, rate)]})
		"MANOR_SEIZE":
			# The skeleton (MANOR_SYSTEM.md §5): the outcome is automatic success
			# until the military system can roll defence against the host.
			var cell := manor_of(req)
			var label := MapManors.label_of(data, cell)
			var victim := MapManors.owner_of(data, state, cell)
			MapManors.set_owner(data, state, cell, MapManors.crown(state),
				"seized by force from House %s" % victim)
			_apply(state, effects, "legitimacy", -data.bal("manor_seize_legitimacy"),
				"took %s by force" % label)
			_apply(state, effects, "unrest", data.bal("manor_seize_unrest"),
				"the seizure of %s" % label)
			for c: Character in _house_members(state, victim):
				c.change_opinion(-int(data.bal("manor_seize_outrage")),
					"the crown seized %s from their house" % label, state.tick)
			effects.append({"metric": "manor", "delta": 1.0,
				"reason": "%s taken from House %s by force" % [label, victim]})
		"ARMY_MARCH":
			var code := String(req.params["regiment"])
			var reg := ArmySystem.regiment(data, code, state)
			if state.war_drafts.erase(code):
				effects.append({"metric": "war_draft", "delta": 0.0,
					"reason": "%s's draft in the war room is set aside" % String(reg["label"])})
			var dest := Vector2(float(req.params["x"]), float(req.params["y"]))
			var wps := waypoints_of(req)
			if CourierSystem.carries_orders(reg):
				var m := ArmySystem.pack_to_metres(data, dest)
				var order := {"action_code": "ARMY_MARCH", "dest_x_m": m.x, "dest_y_m": m.y}
				if not wps.is_empty():
					var wm: Array = []
					for wp: Vector2 in wps:
						wm.append(ArmySystem.pack_to_metres(data, wp))
					order["waypoints_m"] = MarchRoute.to_pairs(wm)
				_send_courier(state, effects, code, order, "with orders to march")
			else:
				ArmySystem.set_march(data, state, code, dest, wps)
				var days := ArmySystem.days_out(data, state, code)
				effects.append({"metric": "army", "delta": 0.0,
					"reason": "%s takes the road; %d day%s' march" % [
						String(reg["label"]), days, "" if days == 1 else "s"]})
		"ARMY_GARRISON":
			var code := String(req.params["regiment"])
			var reg := ArmySystem.regiment(data, code, state)
			if state.war_drafts.erase(code):
				effects.append({"metric": "war_draft", "delta": 0.0,
					"reason": "%s's draft in the war room is set aside" % String(reg["label"])})
			if CourierSystem.carries_orders(reg):
				_send_courier(state, effects, code, {"action_code": "ARMY_GARRISON"}, "with orders to stand")
			else:
				var was := ArmySystem.order_of(data, state, code)
				ArmySystem.set_garrison(data, state, code)
				effects.append({"metric": "army", "delta": 0.0,
					"reason": ("%s halts and takes up quarters" if was == ArmySystem.ORDER_MARCH
						else "%s stands to its post") % String(reg["label"])})
		"BATTLE_ORDER":
			var warrant := _battle_warrant(req, state)
			var issued := BattleOrders.issue(data, state, warrant)
			assert(issued["status"] == "pending")
			var c := _send_courier(state, effects, String(req.params["regiment"]),
				{"action_code": "BATTLE_ORDER", "battle_order_id": String(warrant["id"])},
				"with a battlefield warrant to " + String(req.params["kind"]))
			if bool(c.get("local_delivered", false)):
				effects.append_array(state.battle_orders[String(warrant["id"])].get("result", {}).get("effects", []))
		"BATTLE_TASK", "BATTLE_TASK_CANCEL":
			var warrant := _task_warrant(req)
			var issued := BattleTaskSystem.issue_task(data, state, warrant)
			assert(issued["status"] == "pending")
			_send_courier(state, effects, String(req.params["regiment"]),
				{"action_code": "BATTLE_TASK", "unit_task_id": String(warrant["id"])},
				"with a unit task cancellation" if req.action_code == "BATTLE_TASK_CANCEL" else \
				"with a unit task to " + String(req.params["task"]))
		"BATTLE_FORMATION":
			var code := String(req.params["regiment"])
			var formation := String(req.params["formation"])
			_send_courier(state, effects, code, {"action_code": "BATTLE_FORMATION",
				"battle_id": int(req.params["battle_id"]), "formation": formation},
				"to form " + String(data.battle_formations[formation]["label"]))
		"ARMY_STANCE":
			var code := String(req.params["regiment"])
			var stance := String(req.params["stance"])
			var order := {"action_code": "ARMY_STANCE", "stance": stance}
			var what := "with a new battle stance (%s)" % String(data.battle_stances[stance]["label"])
			if req.params.has("facing"):   # a front's post (spec 2026-10-11-war-room-front-line-design §1)
				order["facing"] = int(req.params["facing"])
				what = "to hold %sfacing %s" % ["where it arrives, " if bool(req.params.get("on_arrival", false)) else "",
					WarFront.compass_words(int(req.params["facing"]))]
			if bool(req.params.get("on_arrival", false)):
				order["on_arrival"] = true
			_send_courier(state, effects, code, order, what)
		"ARMY_SEAT":
			var code := String(req.params["regiment"])
			_send_courier(state, effects, code, {"action_code": "ARMY_SEAT"}, "with orders to take the seat")
		"SUPPLY_POINT_SET":
			var code := String(req.params["regiment"])
			var town := String(req.params["town"])
			var order := {"action_code": "SUPPLY_POINT_SET", "town": town, "rate": int(req.params["rate"])}
			var c := _send_supply(state, effects, code, order, town, bool(req.params.get("with_column", false)),
				"with a supply warrant from %s" % String(data.burgs[town]["label"]),
				"to %s with a supply warrant" % String(data.burgs[town]["label"]))
			if not bool(c.get("local_delivered", false)):
				SupplyLines.order_set(state, code, town, int(req.params["rate"]), int(c["id"]))
			elif String(c.get("order_result", {}).get("type", "")) == "delivered":
				var set_out: Dictionary = c["order_result"].get("set_out", {})
				if not set_out.is_empty():
					effects.append({"metric": "army", "delta": 0.0,
						"reason": "%s's wagons leave %s and need %d days" % [String(ArmySystem.regiment(data, code, state)["label"]),
							String(data.burgs[town]["label"]), int(set_out["days"])]})
		"SUPPLY_POINT_CLEAR":
			var code := String(req.params["regiment"])
			var town := String(SupplyLines.line(state, code)["town"])
			var c := _send_supply(state, effects, code, {"action_code": "SUPPLY_POINT_CLEAR", "town": town},
				town, false, "with orders to stop the wagons from %s" % String(data.burgs[town]["label"]),
				"to %s to stop the wagons" % String(data.burgs[town]["label"]))
			SupplyLines.line(state, code)["order_id"] = int(c["id"])
		"SUPPLY_CARRY_SET":
			var code := String(req.params["regiment"])
			_send_courier(state, effects, code, {"action_code": "SUPPLY_CARRY_SET",
				"days": int(req.params["days"])}, "with orders to carry %d days" % int(req.params["days"]))
		"LAW_SET":
			sig_params = _decree(state, effects, req)
		"SPY_SEND":
			var to := Vector2(float(req.params["x"]), float(req.params["y"]))
			var place := Intel.place_label(data, state, to)
			var c := CourierSystem.dispatch_spy(data, state, to)
			_apply(state, effects, "treasury", -float(CourierSystem.fee_gold(data, CourierSystem.SPY)),
				"a spy rides for " + place)
			var days := CourierSystem.days_left(data, state, c)
			effects.append({"metric": "intel", "delta": 0.0,
				"reason": "A spy rides for %s; about %d day%s" % [place, days, "" if days == 1 else "s"]})
		"GOVERNOR_SET":
			var flow := String(req.params["flow"])
			var label := String(data.ledger_governance[flow]["label"])
			var was := Governance.governor_of(data, state, flow)
			var who := String(req.params["character"])
			var seat_holder := String(state.council.get(String(data.ledger_governance[flow]["seat"]), ""))
			if who == seat_holder:
				state.governors.erase(flow)
			else:
				state.governors[flow] = who
			if was != "" and state.characters.has(was):
				(state.characters[was] as Character).change_opinion(int(data.bal("gov_passed_over_opinion")),
					"passed over: %s given to another" % label, state.tick)
			(state.characters[who] as Character).change_opinion(int(data.bal("gov_new_governor_opinion")),
				"given %s to govern" % label, state.tick)
			effects.append({"metric": "council", "delta": 0.0, "reason": "%s now governs %s"
				% [(state.characters[who] as Character).display_name, label]})
		"LEDGER_AUDIT":
			var flow := String(req.params["flow"])
			var label := String(data.ledger_governance[flow]["label"])
			var gid := Governance.governor_of(data, state, flow)
			var c: Character = state.characters[gid]
			# The opinions move FIRST and the letter is written LAST — after the
			# order's own drift and costs too, at the end of execute (fix round
			# 1 of M3 Task 4): his opinion sets how well he runs the flow, so on
			# the audit day the letter's figures are the live projection.
			c.change_opinion(int(data.bal("gov_audited_opinion")),
				"the crown's clerks went through his books on %s" % label, state.tick)
			# The books are the FLOW's (final review I1): the audit finds every
			# man's uncaught skim on this flow, the governor now or one the flow
			# was taken from.
			var found := Governance.skimmers_of(state, flow)
			for who: String in found:
				_catch(state, effects, who, flow, label)
			if found.is_empty():
				effects.append({"metric": "council", "delta": 0.0, "reason": "The books on %s are in order"
					% label})
		"TRADE_ROUTE_SET":
			var k := str(req.params["kingdom"])
			var label := MarketSystem.label_of(data, k)
			if int(req.params["open"]) == 1:
				state.closed_routes.erase(k)
				effects.append({"metric": "trade", "delta": 0.0, "reason": "the trade with %s is open again" % label})
			else:
				state.closed_routes.append(k)
				state.closed_routes.sort()
				effects.append({"metric": "trade", "delta": 0.0,
					"reason": "the trade with %s is closed; its tolls are forgone" % label})
				# The merchants' goodwill (spec M6); the kingdom's own
				# relationship waits for diplomacy to be state (a no-op hook).
				if state.characters.has(GUILDMASTER):
					(state.characters[GUILDMASTER] as Character).change_opinion(
						int(data.bal("trade_close_opinion")), "the crown closed the trade with " + label, state.tick)
		"GOODS_BUY":
			var pool := String(req.params["pool"])
			var gold := int(req.params["gold"])
			var price := goods_trade_gold(req, state)
			_apply(state, effects, "treasury", float(-price), "bought %d gold of %s goods%s" % [gold, pool, _at_market(req)])
			_apply(state, effects, pool_metric(pool), float(gold), "%s goods bought" % pool)
		"GOODS_SELL":
			var pool := String(req.params["pool"])
			var gold := int(req.params["gold"])
			var paid := goods_trade_gold(req, state)
			_apply(state, effects, pool_metric(pool), float(-gold), "%s goods sold" % pool)
			_apply(state, effects, "treasury", float(paid), "sold %d gold of %s goods%s" % [gold, pool, _at_market(req)])
	var cd := int(row.get("cooldown_ticks", 0))
	if cd > 0:
		state.cooldowns[req.action_code] = state.tick + cd
	var drift := OpinionDrift.apply(data, state,
		OpinionDrift.signature_for(data, req.action_code, sig_params),
		String(row["label"]))
	if req.action_code == "LAW_SET" and not sig_params.has("resend"):
		drift.append_array(DevelopmentSystem.decree_opinions(data, state,
			String(sig_params["law"]), String(sig_params["value"])))
	for pr in state.promises:
		if String(pr["status"]) != "open":
			continue
		if String(pr["promise_code"]) != req.action_code:
			continue
		if req.target != "" and req.target != String(pr["character_id"]):
			continue
		pr["status"] = "kept"
		var who: String = String(pr["character_id"])
		if state.characters.has(who):
			state.characters[who].change_opinion(int(data.bal("promise_kept_opinion")),
				"a promise kept: " + String(row["label"]), state.tick)
			# Kept promises apply the opinion delta above but, unlike every
			# other opinion-affecting branch here, had no corresponding entry
			# in `effects` — so the effects-driven narration path (both
			# ConversationScene and CourtScreen's own _promise_kept_suffix)
			# never voiced it and the promise_kept template row went
			# unreachable. This pseudo-effect
			# isn't a real metric mutation (nothing named "promise" lives in
			# state.metrics); it exists solely so the existing effects-driven
			# narration path picks it up for free.
			effects.append({"metric": "promise", "delta": data.bal("promise_kept_opinion"),
				"reason": "a promise kept: " + String(row["label"])})
	# Every order carries a cost (spec 2026-09-09 §3): always-rows ride along
	# every time, the fallback row only when nothing above cost anything.
	if OrderCosts.always(data, req.action_code):
		effects.append_array(OrderCosts.charge(data, state, req.action_code, req.target))
	elif not (req.action_code == "BATTLE_ORDER" and req.params.get("kind", "") == "surrender"):
		OrderCosts.ensure(data, state, effects, drift, before, req.action_code, req.target)
	if req.action_code == "LEDGER_AUDIT":
		_file_audit(state, String(req.params["flow"]))
	state.event_state["last_action_tick"][req.action_code] = state.tick
	var outcome := {"action_code": req.action_code, "ok": true, "effects": effects,
		"notes": String(row["label"]), "target": req.target, "params": req.params.duplicate(),
		"drift": drift}
	if req.action_code in ["BATTLE_ORDER", "BATTLE_TASK", "BATTLE_TASK_CANCEL"]:
		outcome = GameState._whole(outcome)
	state.recent_outcomes.append(outcome)
	if req.action_code == "BATTLE_ORDER":
		state.battle_orders[String(req.params["request_id"])]["action_outcome"] = outcome.duplicate(true)
	if req.action_code in ["BATTLE_TASK", "BATTLE_TASK_CANCEL"]:
		var record := BattleTaskSystem._find(state, String(req.params["request_id"]))
		record["action_params"] = req.params.duplicate(true)
		record["action_outcome"] = outcome.duplicate(true)
	if req.action_code == "ARMY_RECRUIT":
		state.recruitment_projects[String(req.params["request_id"])]["action_outcome"] = outcome.duplicate(true)
	return outcome

## An audit's letter, filed LAST, once every opinion the order moves has
## moved: its figures are then the flow as it now runs. An audit is a
## snapshot of ITS month — the LEDGER counts it only while state.tick is the
## `tick` it was filed in (Ledger._audit_figure; controller ruling, M3 Task 4
## fix round 1).
func _file_audit(state: GameState, flow: String) -> void:
	var label := String(data.ledger_governance[flow]["label"])
	# the crown's own audit of its own flow: ground truth (owner 2026-10-10)
	var letter := MissiveLog.make("audit", "truth", state.absolute_day(),
		MissiveLog.subject("ledger", flow, -1, Vector2.ZERO), "Audit — " + label.capitalize(),
		AuditWriter.facts(data, state, flow))
	letter["tick"] = state.tick
	MissiveLog.add(data, state, letter)

## One man caught skimming `flow` by its audit: his `caught` entry, his
## record line and the opinion it costs him (with its reason); his count
## on that flow starts again.
func _catch(state: GameState, effects: Array, who: String, flow: String, label: String) -> void:
	var amount := Governance.skimmed_on(state, who, flow)
	if not state.caught.has(who):
		state.caught[who] = []
	state.caught[who].append({"flow": flow, "day": state.absolute_day(), "amount": amount})
	if not state.records.has(who):
		state.records[who] = []
	state.records[who].append("Caught skimming %s, %s of year %d (%d gold)"
		% [label, state.season(), state.year(), amount])
	var his: Dictionary = state.skims[who]
	his.erase(flow)
	if his.is_empty():
		state.skims.erase(who)
	var name := who
	if state.characters.has(who):
		var c: Character = state.characters[who]
		name = c.display_name
		c.change_opinion(int(data.bal("gov_caught_opinion")), "caught skimming %s" % label, state.tick)
	effects.append({"metric": "council", "delta": 0.0, "reason": "%s caught skimming %s (%d gold)"
		% [name, label, amount]})

## Every character of a house, for a trade's goodwill or a seizure's outrage.
func _house_members(state: GameState, family: String) -> Array:
	var out: Array = []
	if family == "":
		return out
	for id in state.characters:
		var c: Character = state.characters[id]
		if c.family_name == family:
			out.append(c)
	return out

func _apply(state: GameState, effects: Array, metric: String, delta: float, reason: String) -> void:
	state.metrics[metric] = state.metrics[metric] + delta
	effects.append({"metric": metric, "delta": delta, "reason": reason})

## An order that rides (owner 2026-09-27, spec 2026-09-27-courier-core): one
## courier from the capital, his fee a ledger line, and the army line saying
## when he should get there. The regiment is untouched until he does.
## An order for a regiment whose courier has not yet set out rides WITH him
## (owner 2026-10-10, CourierSystem.joinable): no second fee, and the army
## line says he carries it too.
func _send_courier(state: GameState, effects: Array, code: String, order: Dictionary, what: String) -> Dictionary:
	var label := String(ArmySystem.regiment(data, code, state)["label"])
	if KingSystem.can_command(data, state, code):
		var delivered := CourierSystem.deliver_local(data, state, code, order)
		effects.append({"metric": "army", "delta": 0.0,
			"reason": "The king gives %s the order directly, %s" % [label, what]})
		return delivered
	var before := state.next_courier_id
	var c := CourierSystem.dispatch(data, state, CourierSystem.ORDINARY, code, order)
	var days := CourierSystem.days_left(data, state, c)
	if state.next_courier_id == before:
		effects.append({"metric": "army", "delta": 0.0, "reason": "The courier for %s carries this too, %s; about %d day%s" % [
			label, what, days, "" if days == 1 else "s"]})
		return c
	_apply(state, effects, "treasury", -float(CourierSystem.fee_gold(data, CourierSystem.ORDINARY)),
		"a courier rides for " + label)
	effects.append({"metric": "army", "delta": 0.0, "reason": "A courier rides for %s %s; about %d day%s" % [
		label, what, days, "" if days == 1 else "s"]})
	return c

## A supply order's courier (owner 2026-10-10): with the column's own when one
## waits to set out for it (CourierSystem.joinable) or `with_column` asks for
## one (the march's confirm and the war room's drafts: the warrant rides with
## the march to the regiment, and the wagons leave the town when he arrives);
## else to the supply TOWN as the order's own courier (spec
## 2026-10-07-army-supply-lines §4).
func _send_supply(state: GameState, effects: Array, code: String, order: Dictionary, town: String,
		with_column: bool, to_column: String, to_town: String) -> Dictionary:
	if with_column or not CourierSystem.joinable(state, CourierSystem.ORDINARY, code, order).is_empty():
		return _send_courier(state, effects, code, order, to_column)
	var o := order.duplicate()
	o["to_town"] = town
	var c := CourierSystem.dispatch_to(data, state, CourierSystem.ORDINARY, code, o,
		Vector2(float(data.burgs[town]["x"]), float(data.burgs[town]["y"])))
	_courier_fee(state, effects, c, to_town)
	return c

## The fee an order for `code` would pay its courier now: none when it would
## ride with one already waiting to set out (CourierSystem.joinable).
func _fee_for(state: GameState, code: String, local_ok := true) -> int:
	if local_ok and KingSystem.can_command(data, state, code):
		return 0
	if not CourierSystem.joinable(state, CourierSystem.ORDINARY, code, {}).is_empty():
		return 0
	return CourierSystem.fee_gold(data, CourierSystem.ORDINARY)

## LAW_SET: the law's own gold and cost ops, the decree and its couriers
## (LawSystem.decree), one ordinary fee a courier as one ledger line, and a
## "law" line saying how many ride and how long the last takes. Returns the
## params the opinion drift reads: a range law's `delta` (new − old) beside
## the law and value, so its signature variant knows the direction. A
## re-send (R5) changes no law: it pays neither the law's gold nor its cost
## ops, and its drift params match no variant but the blank, drift-free row.
func _decree(state: GameState, effects: Array, req: ActionRequest) -> Dictionary:
	var law := str(req.params["law"])
	var value := LawSystem.canonical(data, law, req.params["value"])
	var d := LawSystem.def(data, law)
	var label := String(d["label"])
	var was := LawSystem.decreed(data, state, law)
	var again := LawSystem.is_resend(data, state, law, value)
	if int(d["gold_cost"]) > 0 and not again:
		_apply(state, effects, "treasury", -float(int(d["gold_cost"])), "the decree on " + label.to_lower())
	if String(d["cost_ops"]) != "" and not again:
		effects.append_array(EventEffects.apply(String(d["cost_ops"]), state, data, "the decree on " + label.to_lower()))
	var sent := LawSystem.decree(data, state, law, value)
	var n := sent.size()
	_apply(state, effects, "treasury", -float(n * CourierSystem.fee_gold(data, CourierSystem.ORDINARY)),
		"%d courier%s ride%s with the decree on %s" % [n, "" if n == 1 else "s", "s" if n == 1 else "",
			label.to_lower()])
	var last := 0
	for c: Dictionary in sent:
		last = maxi(last, CourierSystem.days_left(data, state, c))
	effects.append({"metric": "law", "delta": 0.0, "reason": "%s %s %s: %d courier%s, the last in about %d day%s" % [
		label, "sent again as" if again else "decreed", LawSystem.value_label(data, value).to_lower(),
		n, "" if n == 1 else "s", last, "" if last == 1 else "s"]})
	if again:
		return {"law": law, "resend": 1}
	var out := {"law": law, "value": value}
	if String(d["kind"]) == "range":
		out["delta"] = int(value) - int(was)
	return out

## A supply courier's fee and the army line saying when he gets there.
func _courier_fee(state: GameState, effects: Array, c: Dictionary, what: String) -> void:
	_apply(state, effects, "treasury", -float(CourierSystem.fee_gold(data, CourierSystem.ORDINARY)),
		"a courier rides " + what)
	var days := CourierSystem.days_left(data, state, c)
	effects.append({"metric": "army", "delta": 0.0, "reason": "A courier rides %s; about %d day%s" % [
		what, days, "" if days == 1 else "s"]})

func apply_court_reaction(cr: Dictionary, state: GameState) -> void:
	var cap := int(data.bal("tone_delta_cap"))
	var delta: int = clampi(TONE_DELTAS.get(cr.get("tone", "neutral"), 0), -cap, cap)
	for id in cr.get("addressed", []):
		if state.characters.has(id) and delta != 0:
			state.characters[id].change_opinion(delta, "tone: " + cr["tone"], state.tick)
	for p in cr.get("promises", []):
		var due := int(p["tick_due"])
		if due <= 0:
			due = state.tick + int(data.bal("promise_default_ticks"))
		state.promises.append({"character_id": p["character_id"],
			"promise_code": p["promise_code"], "made_tick": state.tick,
			"tick_due": due, "status": "open"})
