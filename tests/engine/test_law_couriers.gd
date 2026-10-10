extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A law's couriers (spec 2026-10-08-laws-tab-design §3; plan rulings R5, R6,
## R10): one to each held province for an economy or political law; one to
## each camp and one to each land unit outside a camp for a military law;
## none to a fleet. A place courier rides for a fixed point and is never lost
## on his first day; delivery writes his place alone, a newer decree beats an
## older courier, a province lost meanwhile drops him.

var repo: DataRepository
var s: GameState
var realm: String


func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	realm = repo.resolve_realm("player_realm")
	s.metrics["treasury"] = 5000.0
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


## Ride every courier home; the events of every day.
func _ride_all() -> Array:
	var events: Array = []
	for i in int(repo.bal("courier_max_days")) + 2:
		if s.couriers.is_empty():
			break
		events.append_array(CourierSystem.ride_day(repo, s))
	return events


func _land_units() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, realm, s):
		if String(r.get("is_naval", "0")) != "1":
			out.append(String(r["regiment_code"]))
	return out


func _another_kingdom() -> String:
	var codes: Array = repo.kingdoms.keys()
	codes.sort()
	for k: String in codes:
		if k != realm:
			return k
	return ""


## A land unit sent marching to a land point beside it (it leaves its camp).
func _march_one() -> String:
	for code: String in _land_units():
		var reg := ArmySystem.regiment(repo, code, s)
		if ArmySystem.base_pace_km(repo, reg) <= 0:
			continue
		var home: Vector2 = ArmySystem.position_of(repo, s, reg)
		for i in range(20, 200, 5):
			var probe := home + Vector2(float(i), 0.0)
			if MapEconomy.cell_at(repo, probe) >= 0:
				ArmySystem.set_march(repo, s, code, probe)
				if ArmySystem.order_of(repo, s, code) == ArmySystem.ORDER_MARCH:
					return code
	return ""


func test_a_province_law_sends_one_courier_to_each_held_province() -> void:
	var held := MapOwnership.provinces_of(repo, s, realm)
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	assert_eq(sent.size(), held.size(), "one courier a province")
	var keys: Array = []
	for c: Dictionary in sent:
		assert_true(String(c["target"]).begins_with("province:"), "his target is the place")
		assert_eq(String(c["target"]), String(CourierSystem.first_order(c)["scope_key"]))
		assert_eq(String(c["kind"]), CourierSystem.ORDINARY)
		assert_eq(String(CourierSystem.first_order(c)["action_code"]), "LAW_SET")
		keys.append(String(c["target"]).trim_prefix("province:"))
	keys.sort()
	var want: Array = held.duplicate()
	want.sort()
	assert_eq(keys, want)
	var events := CourierSystem.ride_day(repo, s)
	for e: Dictionary in events:
		assert_ne(String(e["type"]), "lost", "a place courier is not lost on his first day")
	var delivered := events.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "delivered").size()
	assert_eq(s.couriers.size(), sent.size() - delivered, "every courier not home yet still rides")


func test_a_province_courier_ends_at_its_capital() -> void:
	for r: Dictionary in LawSystem.recipients(repo, s, "tax_rate"):
		var code := String(r["scope_key"]).trim_prefix("province:")
		var row: Dictionary = repo.provinces[code]
		var cap := String(row.get("capital_burg", ""))
		var want := Vector2(float(repo.burgs[cap]["x"]), float(repo.burgs[cap]["y"])) if repo.burgs.has(cap) \
			else Vector2(float(row["center_x"]), float(row["center_y"]))
		assert_eq(r["to_px"], want, code)
		assert_eq(String(r["kind"]), "province")


func test_a_camp_law_sends_one_per_camp_and_one_per_field_unit() -> void:
	var marcher := _march_one()
	assert_ne(marcher, "", "a unit takes the road")
	var towns := {}
	var field: Array = []
	for code: String in _land_units():
		var town := ArmyGround.camped_by(repo, s, code)
		if town != "":
			towns[town] = true
		else:
			field.append(code)
	assert_true(marcher in field, "a marching unit is in the field")
	assert_false(towns.is_empty(), "the realm has camps")
	var recips := LawSystem.recipients(repo, s, "plunder")
	assert_eq(recips.size(), towns.size() + field.size())
	var keys: Array = recips.map(func(r: Dictionary) -> String: return String(r["scope_key"]))
	var sorted_keys := keys.duplicate()
	sorted_keys.sort()
	assert_eq(keys, sorted_keys, "recipients come sorted by scope key")
	var sent := LawSystem.decree(repo, s, "plunder", "allow")
	assert_eq(sent.size(), recips.size())
	var to_marcher := sent.filter(func(c: Dictionary) -> bool: return String(c["target"]) == marcher)
	assert_eq(to_marcher.size(), 1, "the marching unit gets its own courier")
	assert_eq(String(CourierSystem.first_order(to_marcher[0])["scope_key"]), "unit:" + marcher)
	for c: Dictionary in sent:
		var t := String(c["target"])
		if t.begins_with("town:"):
			assert_true(towns.has(t.trim_prefix("town:")), t)
		else:
			assert_true(t in field, t)


func test_fleets_get_no_courier() -> void:
	var fleets: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, realm, s):
		if String(r.get("is_naval", "0")) == "1":
			fleets.append(String(r["regiment_code"]))
	assert_gt(fleets.size(), 0, "the realm has a fleet in its roster, or this test proves nothing")
	for c: Dictionary in LawSystem.decree(repo, s, "plunder", "allow"):
		assert_false(String(c["target"]) in fleets, "no courier rides for a fleet")
		assert_false(String(CourierSystem.first_order(c)["scope_key"]).trim_prefix("unit:") in fleets)


func test_delivery_writes_the_place_and_not_the_others() -> void:
	var was := LawSystem.decreed(repo, s, "tax_rate")
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	var one: Dictionary = sent[0]
	var place := String(one["target"]).trim_prefix("province:")
	s.couriers = [one]
	var events := _ride_all()
	assert_eq(String(events[events.size() - 1]["type"]), "delivered")
	assert_eq(LawSystem.value(repo, s, "tax_rate", place), "7", "his place follows the decree")
	for code: String in MapOwnership.provinces_of(repo, s, realm):
		if code != place:
			assert_eq(LawSystem.value(repo, s, "tax_rate", code), was, code + " still follows the old rate")
	var d := LawSystem.delivery(repo, s, "tax_rate")
	assert_eq(int(d["reached"]), 1)
	assert_eq(int(d["total"]), sent.size())
	assert_eq(int(d["riding"]), 0)
	assert_eq((d["missing"] as Array).size(), sent.size() - 1)
	assert_false(("province:" + place) in d["missing"])


func test_the_delivery_counts_riders_and_days() -> void:
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	var d := LawSystem.delivery(repo, s, "tax_rate")
	assert_eq(int(d["total"]), sent.size())
	assert_eq(int(d["riding"]), sent.size())
	assert_eq(int(d["reached"]), 0)
	assert_eq((d["missing"] as Array).size(), 0)
	var longest := 0
	for c: Dictionary in sent:
		longest = maxi(longest, CourierSystem.days_left(repo, s, c))
	assert_eq(int(d["last_days"]), longest)
	_ride_all()
	d = LawSystem.delivery(repo, s, "tax_rate")
	assert_eq(int(d["reached"]), sent.size(), "all home")
	assert_eq(int(d["riding"]), 0)


func test_a_newer_decree_beats_an_older_courier() -> void:
	var older := LawSystem.decree(repo, s, "tax_rate", "6")
	var newer := LawSystem.decree(repo, s, "tax_rate", "7")
	assert_eq(int(CourierSystem.first_order(newer[0])["decree_id"]), int(CourierSystem.first_order(older[0])["decree_id"]) + 1)
	# the newer couriers happen to arrive first; the older ones come after
	s.couriers = newer.duplicate()
	_ride_all()
	s.couriers = older.duplicate()
	var events := _ride_all()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "stale").size(),
		older.size(), "every older courier is set aside")
	for code: String in MapOwnership.provinces_of(repo, s, realm):
		assert_eq(LawSystem.value(repo, s, "tax_rate", code), "7", code)


func test_a_courier_to_a_lost_province_is_dropped() -> void:
	var was := LawSystem.decreed(repo, s, "tax_rate")
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	var one: Dictionary = sent[0]
	var place := String(one["target"]).trim_prefix("province:")
	assert_true(MapOwnership.set_owner(repo, s, place, _another_kingdom(), "test: the province falls"))
	s.couriers = [one]
	var events := _ride_all()
	assert_eq(String(events[events.size() - 1]["type"]), "lost")
	assert_eq(String(s.law_in_force["province:" + place]["tax_rate"]["value"]), was, "nothing written")
	assert_eq(int(s.law_in_force["province:" + place]["tax_rate"]["decree_id"]), 0)


func test_a_law_courier_never_moves_a_columns_arrival() -> void:
	var marcher := _march_one()
	assert_ne(marcher, "")
	var days := CourierSystem.days_to_arrival(repo, s, marcher)
	LawSystem.decree(repo, s, "plunder", "allow")
	assert_true(s.couriers.any(func(c: Dictionary) -> bool: return String(c["target"]) == marcher))
	assert_true(CourierSystem.pending_for(s, marcher).is_empty(), "a law courier is no march or halt")
	assert_eq(CourierSystem.days_to_arrival(repo, s, marcher), days)
	var order_id := int(s.regiments[marcher].get("order_id", 0))
	_ride_all()
	assert_eq(int(s.regiments[marcher].get("order_id", 0)), order_id, "a decree is no order to the column")
	assert_eq(String(s.law_in_force["unit:" + marcher]["plunder"]["value"]), "allow", "its own entry is written")


func test_no_recipients_is_refused() -> void:
	var other := _another_kingdom()
	for code: String in MapOwnership.provinces_of(repo, s, realm):
		MapOwnership.set_owner(repo, s, code, other, "test: the realm is lost")
	for code: String in s.army_roster:
		if String(s.army_roster[code]["kingdom_code"]) == realm:
			s.army_roster[code]["kingdom_code"] = other
	var actions := ActionSystem.new(repo)
	assert_eq(actions.validate(ActionRequest.make("LAW_SET", {"law": "tax_rate", "value": "7"}), s),
		"No place to send it to")
	assert_eq(actions.validate(ActionRequest.make("LAW_SET", {"law": "plunder", "value": "allow"}), s),
		"No place to send it to")
	assert_eq(String(LawSystem.preview(repo, s, "plunder", "allow")["refusal"]), "No place to send it to")


func test_the_headline_words_a_law_courier() -> void:
	var c: Dictionary = LawSystem.decree(repo, s, "tax_rate", "7")[0]
	for type: String in ["set_out", "delivered", "stale", "fuse", "lost"]:
		var line := CourierSystem.headline(repo, CourierSystem._event(type, c))
		assert_ne(line, "", type)
		assert_string_contains(line, "Tax rate", type)
		assert_false(line.contains("province:"), type + " names the place, not its key")
	var leaving := CourierSystem._event("set_out", c)
	leaving["capital"] = 1
	assert_string_contains(CourierSystem.headline(repo, leaving), "Tax rate")


func test_the_card_says_decree_not_stand_and_no_receipt_is_filed() -> void:
	var c: Dictionary = LawSystem.decree(repo, s, "tax_rate", "7")[0]
	var card := CourierCard.card(repo, s, int(c["id"]))
	assert_true(String(card["title"]).begins_with("Decree to "), String(card["title"]))
	assert_false(String(card["title"]).contains("province:"))
	var carrying := ""
	for f: Array in card["fields"]:
		if String(f[0]) == "Carrying":
			carrying = String(f[1])
	assert_string_contains(carrying, "Decree: Tax rate")
	assert_string_contains(carrying, "7")
	# a decree's courier files no receipt: the reach letter speaks for the
	# decree (LawSystem.close_rides), delivered or set aside
	s.missives = []
	assert_eq(String(CourierSystem._deliver(repo, s, c)["type"]), "delivered")
	assert_eq(String(CourierSystem._deliver(repo, s, c)["type"]), "stale")
	assert_true(s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "receipt").is_empty(),
		"no receipt for a decree's courier")
	var u_sent := LawSystem.decree(repo, s, "plunder", "allow")
	var unit: Array = u_sent.filter(func(x: Dictionary) -> bool: return not String(x["target"]).begins_with("town:"))
	if not unit.is_empty():
		var ucard := CourierCard.card(repo, s, int(unit[0]["id"]))
		assert_true(String(ucard["title"]).begins_with("Decree to "))


func test_law_couriers_round_trip_the_save() -> void:
	LawSystem.decree(repo, s, "tax_rate", "7")
	LawSystem.decree(repo, s, "plunder", "allow")
	var before := SaveLoad.state_hash(s)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var back := GameState.from_dict(d)
	assert_eq(SaveLoad.state_hash(back), before)
	assert_eq(back.couriers.size(), s.couriers.size())
	var o: Dictionary = CourierSystem.first_order(back.couriers[0])
	assert_eq(typeof(o["decree_id"]), TYPE_INT)
	assert_eq(typeof(o["value"]), TYPE_STRING)
	assert_eq(String(o["value"]), "7")
	# and they ride the same in the loaded state
	var a := CourierSystem.ride_day(repo, s)
	var b := CourierSystem.ride_day(repo, back)
	assert_eq(a.size(), b.size())
	assert_eq(SaveLoad.state_hash(back), SaveLoad.state_hash(s))


func test_a_law_courier_is_no_regiment_edge_in_the_ledger() -> void:
	LawSystem.decree(repo, s, "tax_rate", "7")
	for c: Dictionary in s.couriers:
		var links := LedgerResolvers._couriers(repo, s, "courier:%d" % int(c["id"]), false)
		assert_eq(links.size(), 0, "a courier to a province carries no orders to a regiment")


## The laws screen's count by kind of place (spec §5: "8 / 10 camps and 3 / 5
## units in the field"): a camp law's towns and field units counted apart, a
## province law's provinces.
func test_the_delivery_counts_each_kind_of_place_apart() -> void:
	var marcher := _march_one()
	assert_ne(marcher, "")
	var towns := 0
	var field := 0
	for r: Dictionary in LawSystem.recipients(repo, s, "plunder"):
		if String(r["kind"]) == "town":
			towns += 1
		else:
			field += 1
	assert_gt(towns, 0)
	assert_gt(field, 0)
	LawSystem.decree(repo, s, "plunder", "allow")
	var kinds: Dictionary = LawSystem.delivery(repo, s, "plunder")["kinds"]
	assert_eq(kinds["town"], {"reached": 0, "total": towns})
	assert_eq(kinds["unit"], {"reached": 0, "total": field})
	assert_false(kinds.has("province"))
	_ride_all()
	kinds = LawSystem.delivery(repo, s, "plunder")["kinds"]
	assert_eq(kinds["town"], {"reached": towns, "total": towns}, "every camp told")
	assert_eq(kinds["unit"], {"reached": field, "total": field}, "every unit in the field told")
	var n := MapOwnership.provinces_of(repo, s, realm).size()
	assert_eq(LawSystem.delivery(repo, s, "tax_rate")["kinds"], {"province": {"reached": n, "total": n}},
		"undecreed: every province follows the seeded value")


## The places not yet told (spec §5's list): each riding courier's place with
## the days he has left, each missing place marked lost (R5 sends it again),
## sorted by scope key; empty once every courier is home.
func test_the_untold_list_names_each_place_with_its_days_or_lost() -> void:
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	var gone_key := String(CourierSystem.first_order(sent[0])["scope_key"])
	s.couriers.remove_at(0)
	var days := {}
	for c: Dictionary in s.couriers:
		days[String(CourierSystem.first_order(c)["scope_key"])] = CourierSystem.days_left(repo, s, c)
	var rows := LawSystem.untold(repo, s, "tax_rate")
	assert_eq(rows.size(), sent.size(), "every place is untold: one lost, the rest ridden for")
	var keys: Array = rows.map(func(r: Dictionary) -> String: return String(r["scope_key"]))
	var sorted_keys := keys.duplicate()
	sorted_keys.sort()
	assert_eq(keys, sorted_keys)
	for r: Dictionary in rows:
		var key := String(r["scope_key"])
		assert_eq(String(r["label"]), LawSystem.place_label(repo, s, key))
		if key == gone_key:
			assert_true(bool(r["lost"]), key + " lost")
			assert_eq(int(r["days"]), -1)
		else:
			assert_false(bool(r["lost"]), key)
			assert_eq(int(r["days"]), int(days[key]), key + "'s courier's days left")
	_ride_all()
	rows = LawSystem.untold(repo, s, "tax_rate")
	assert_eq(rows.size(), 1, "only the lost place is left")
	assert_eq(String(rows[0]["scope_key"]), gone_key)


## A place gained since the decree is missing but was never sent to: not
## "lost" (its courier lost) but "not sent" — the decree keeps the places its
## couriers set out for (`sent`), a re-send adds to them, the save keeps them.
func test_a_place_gained_since_is_not_sent_not_lost() -> void:
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	var gone_key := String(CourierSystem.first_order(sent[0])["scope_key"])
	s.couriers.remove_at(0)
	var other := _another_kingdom()
	var gained := ""
	var codes: Array = repo.provinces.keys()
	codes.sort()
	for code: String in codes:
		if MapOwnership.owner_of(repo, s, code) == other:
			gained = code
			break
	assert_ne(gained, "")
	assert_true(MapOwnership.set_owner(repo, s, gained, realm, "test: the province comes over"))
	var d := LawSystem.delivery(repo, s, "tax_rate")
	assert_eq(int(d["lost"]), 1, "the courier lost on the road")
	assert_eq(int(d["not_sent"]), 1, "the province gained since")
	for u: Dictionary in LawSystem.untold(repo, s, "tax_rate"):
		var key := String(u["scope_key"])
		if key == "province:" + gained:
			assert_true(bool(u["lost"]) and not bool(u["sent"]), key + ": none set out for it")
		elif key == gone_key:
			assert_true(bool(u["lost"]) and bool(u["sent"]), key + ": its courier lost")
		else:
			assert_true(bool(u["sent"]) and not bool(u["lost"]), key)
	# the re-send rides for both, and both are then sent for
	LawSystem.decree(repo, s, "tax_rate", "7")
	assert_true("province:" + gained in s.law_decree["tax_rate"]["sent"])
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.law_decree["tax_rate"]["sent"], s.law_decree["tax_rate"]["sent"], "the save keeps them")
