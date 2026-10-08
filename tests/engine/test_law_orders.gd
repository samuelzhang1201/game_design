extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## LAW_SET, the order that decrees a law (spec 2026-10-08-laws-tab-design §3):
## its refusals, the per-law cooldown, the re-send to places a courier missed
## (plan ruling R5) and its cost (R3: the order row, the law's own, one fee a
## courier), which LawSystem.preview must quote exactly.

var repo: DataRepository
var s: GameState
var actions: ActionSystem
var realm: String


func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	actions = ActionSystem.new(repo)
	realm = repo.resolve_realm("player_realm")
	s.metrics["treasury"] = 5000.0
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _law(law: String, value: Variant) -> ActionRequest:
	return ActionRequest.make("LAW_SET", {"law": law, "value": value})


## A tax rate other than the decreed one, inside the law's range.
func _other_tax() -> String:
	var now := int(LawSystem.decreed(repo, s, "tax_rate"))
	return str(now + 1 if now < 10 else now - 1)


func test_law_set_is_refused_for_an_unknown_law_value_or_unchanged_value() -> void:
	assert_eq(actions.validate(_law("nope", "1"), s), "No such law: nope")
	assert_eq(actions.validate(_law("tax_rate", "11"), s), "11 is not a value of Tax rate")
	assert_eq(actions.validate(_law("plunder", "sometimes"), s), "sometimes is not a value of Plunder")
	var now := LawSystem.decreed(repo, s, "tax_rate")
	assert_eq(actions.validate(_law("tax_rate", now), s), "Tax rate is already " + now)
	assert_eq(actions.validate(_law("plunder", "forbid"), s), "Plunder is already forbid")
	assert_eq(actions.validate(_law("tax_rate", _other_tax()), s), "", "a new value is legal")
	assert_eq(actions.validate(_law("tax_rate", int(_other_tax())), s), "", "a whole number is read as its digits")


func test_cooldown_is_per_law() -> void:
	var t0 := s.tick
	actions.execute(_law("tax_rate", _other_tax()), s)
	var back := str(int(_other_tax()) + 1) if int(_other_tax()) < 10 else str(int(_other_tax()) - 1)
	assert_eq(actions.validate(_law("tax_rate", back), s),
		"Tax rate is on cooldown until tick %d" % (t0 + 2))
	s.tick = t0 + 1
	assert_ne(actions.validate(_law("tax_rate", back), s), "", "still cooling a tick later")
	var tariff := int(LawSystem.decreed(repo, s, "tariff_rate"))
	assert_eq(actions.validate(_law("tariff_rate", str(tariff + 1 if tariff < 10 else tariff - 1)), s), "",
		"another law is free to change")
	s.tick = t0 + 2
	assert_eq(actions.validate(_law("tax_rate", back), s), "", "two ticks on, the tax may change again")


func test_an_unchanged_value_is_allowed_while_places_are_missing() -> void:
	var value := _other_tax()
	actions.execute(_law("tax_rate", value), s)
	var id := int(s.law_decree["tax_rate"]["decree_id"])
	assert_eq(actions.validate(_law("tax_rate", value), s), "Tax rate is already " + value,
		"every courier still rides: nothing is missing")
	# one province's courier is lost on the road
	var gone: Dictionary = s.couriers[0]
	s.couriers.remove_at(0)
	var missing: Array = LawSystem.delivery(repo, s, "tax_rate")["missing"]
	assert_eq(missing, [String(gone["order"]["scope_key"])])
	assert_eq(actions.validate(_law("tax_rate", value), s), "", "the same decree may ride again")
	var before := s.couriers.size()
	actions.execute(_law("tax_rate", value), s)
	assert_eq(s.couriers.size(), before + 1, "exactly one courier, to the missing place")
	var again: Dictionary = s.couriers[s.couriers.size() - 1]
	assert_eq(String(again["order"]["scope_key"]), String(gone["order"]["scope_key"]))
	assert_eq(int(again["order"]["decree_id"]), id, "the same decree, not a new one")
	assert_eq(int(s.law_decree["tax_rate"]["decree_id"]), id)


func test_the_cost_is_the_order_the_law_and_the_couriers() -> void:
	var value := _other_tax()
	var preview := LawSystem.preview(repo, s, "tax_rate", value)
	assert_eq(String(preview["refusal"]), "")
	var n := MapOwnership.provinces_of(repo, s, realm).size()
	assert_eq(int(preview["couriers"]), n)
	assert_eq(int(preview["fee"]), n * CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	assert_eq(int(preview["gold"]), int(OrderCosts.gold_of(repo, "LAW_SET"))
		+ int(LawSystem.def(repo, "tax_rate")["gold_cost"]))
	assert_gt(int(preview["max_days"]), 0)
	var before := float(s.metrics["treasury"])
	actions.execute(_law("tax_rate", value), s)
	var spent := before - float(s.metrics["treasury"])
	assert_eq(int(round(spent)), int(OrderCosts.gold_of(repo, "LAW_SET"))
		+ int(LawSystem.def(repo, "tax_rate")["gold_cost"]) + n * 2, "the order, the law and n fees")
	assert_eq(int(round(spent)), int(preview["gold"]) + int(preview["fee"]), "the preview quoted it exactly")


func test_the_preview_counts_a_military_laws_couriers() -> void:
	var preview := LawSystem.preview(repo, s, "plunder", "allow")
	assert_eq(int(preview["couriers"]), LawSystem.recipients(repo, s, "plunder").size())
	var before := float(s.metrics["treasury"])
	actions.execute(_law("plunder", "allow"), s)
	assert_eq(int(round(before - float(s.metrics["treasury"]))), int(preview["gold"]) + int(preview["fee"]))


func test_the_chest_must_pay_every_courier() -> void:
	var preview := LawSystem.preview(repo, s, "tax_rate", _other_tax())
	s.metrics["treasury"] = float(int(preview["gold"]) + int(preview["fee"]) - 1)
	assert_eq(actions.validate(_law("tax_rate", _other_tax()), s), "The chancery cannot pay the couriers")
	s.metrics["treasury"] = float(int(preview["gold"]) + int(preview["fee"]))
	assert_eq(actions.validate(_law("tax_rate", _other_tax()), s), "")


func test_a_decree_mirrors_its_metric_at_once() -> void:
	var value := _other_tax()
	actions.execute(_law("tax_rate", value), s)
	assert_eq(float(s.metrics["tax_rate"]), float(int(value)), "the display mirror (ruling P1)")
	assert_eq(LawSystem.decreed(repo, s, "tax_rate"), value)
	s.tick += 5
	actions.execute(_law("grain_ration", "ration"), s)
	assert_eq(float(s.metrics["grain_ration"]), 1.0)
	s.tick += 5
	actions.execute(_law("grain_ration", "release"), s)
	assert_eq(float(s.metrics["grain_ration"]), 0.0)


func test_the_outcome_says_what_was_decreed() -> void:
	var out := actions.execute(_law("tax_rate", _other_tax()), s)
	var said := false
	for e: Dictionary in out["effects"]:
		if String(e.get("metric", "")) == "law":
			said = String(e["reason"]).contains("Tax rate")
	assert_true(said, "a law line names the law")
	assert_true(OrderCosts.has_cost(repo, s, out["effects"], out["drift"], {}), "it carries a cost")


## Every law, decreed to a value other than its own on a fresh campaign,
## leaves a cost on the record (invariant 8).
func test_every_executed_law_set_leaves_a_cost() -> void:
	for law: String in repo.law_order:
		var c := SuiteData.campaign(repo, 42)
		c.metrics["treasury"] = 5000.0
		var d := LawSystem.def(repo, law)
		var now := LawSystem.decreed(repo, c, law)
		var value := ""
		if String(d["kind"]) == "range":
			value = str(int(now) + 1 if int(now) < int(d["values"][1]) else int(now) - 1)
		else:
			for v: String in d["values"]:
				if v != now:
					value = v
					break
		var req := _law(law, value)
		assert_eq(actions.validate(req, c), "", law)
		var before := OrderCosts.snapshot_opinions(c)
		var out := actions.execute(req, c)
		assert_true(OrderCosts.has_cost(repo, c, out["effects"], out["drift"], before), law + " left a cost")


func test_a_raised_tax_drifts_as_the_old_order_did() -> void:
	var now := int(LawSystem.decreed(repo, s, "tax_rate"))
	var up := {"law": "tax_rate", "value": str(now + 1), "delta": 1}
	# the old tax order's delta_pos / delta_neg rows and the tithe's
	# (test_law_migration holds every old row)
	var old_up := {"centralism": 10.0, "militarism": 0.0, "orthodoxy": 0.0, "tax_incidence": -30.0, "expansionism": 0.0}
	assert_eq(OpinionDrift.signature_for(repo, "LAW_SET", up), old_up)
	var old_down := {"centralism": -5.0, "militarism": 0.0, "orthodoxy": 0.0, "tax_incidence": 30.0, "expansionism": 0.0}
	assert_eq(OpinionDrift.signature_for(repo, "LAW_SET", {"law": "tax_rate", "value": "1", "delta": -1}), old_down)
	assert_eq(OpinionDrift.signature_for(repo, "LAW_SET", {"law": "church_policy", "value": "tithe"}),
		{"centralism": 10.0, "militarism": 0.0, "orthodoxy": -50.0, "tax_incidence": 0.0, "expansionism": 0.0})
	var plain := OpinionDrift.signature_for(repo, "LAW_SET", {"law": "plunder", "value": "allow"})
	for ax: String in plain:
		assert_eq(float(plain[ax]), 0.0, "a law with no old signature drifts no one")


## A re-send (R5) is no change of law: neither drift nor the law's cost ops
## move any opinion, for a choice law (whose signature row names its value)
## as for a range law (whose rows name a direction).
func _resend_moves_no_opinion(law: String, value: String) -> void:
	s.tick += 10
	assert_eq(actions.validate(_law(law, value), s), "", law + " decreed")
	actions.execute(_law(law, value), s)
	s.couriers.remove_at(0)
	assert_eq(actions.validate(_law(law, value), s), "", law + " may ride again")
	var before := OrderCosts.snapshot_opinions(s)
	var preview := LawSystem.preview(repo, s, law, value)
	var gold := float(s.metrics["treasury"])
	var out := actions.execute(_law(law, value), s)
	assert_eq((out["drift"] as Array).size(), 0, law + ": a re-send drifts no one")
	assert_eq(OrderCosts.snapshot_opinions(s), before, law + ": every councillor's opinion unchanged")
	assert_eq(int(round(gold - float(s.metrics["treasury"]))), int(preview["gold"]) + int(preview["fee"]),
		law + ": the preview quotes the re-send")
	assert_eq(int(preview["gold"]), int(OrderCosts.gold_of(repo, "LAW_SET")), "the order's row alone")


func test_a_resend_of_a_choice_law_drifts_no_one() -> void:
	_resend_moves_no_opinion("church_policy", "endow")


func test_a_resend_of_a_range_law_drifts_no_one() -> void:
	_resend_moves_no_opinion("tax_rate", _other_tax())


func test_a_wrong_typed_law_param_is_refused_not_a_crash() -> void:
	assert_eq(actions.validate(ActionRequest.make("LAW_SET", {"law": 5, "value": null}), s), "No such law: 5")
	assert_eq(actions.validate(ActionRequest.make("LAW_SET", {"law": null, "value": 3}), s), "No such law: <null>")
	assert_eq(actions.validate(ActionRequest.make("LAW_SET", {"value": "on"}), s), "No such law: ")
	assert_eq(actions.validate(_law("tax_rate", null), s), "<null> is not a value of Tax rate")
	assert_eq(actions.validate(_law("plunder", ["allow"]), s), "[\"allow\"] is not a value of Plunder")
	var out := OrderPipeline.apply_order(repo, s, TickEngine.new(repo),
		[ActionRequest.make("LAW_SET", {"law": 5, "value": null})], [],
		{"addressed": [], "tone": "neutral", "promises": []}, "order")
	assert_eq(out["executed"].size(), 0)
	assert_eq(out["rejected"].size(), 1)
	assert_eq(String(out["rejected"][0]["error"]), "No such law: 5")


func test_a_range_value_is_stored_in_plain_digits() -> void:
	var now := int(LawSystem.decreed(repo, s, "tax_rate"))
	var to := now + 1 if now < 9 else now - 1
	var padded := "0%d" % to
	assert_eq(actions.validate(_law("tax_rate", padded), s), "")
	actions.execute(_law("tax_rate", padded), s)
	assert_eq(String(s.law_decree["tax_rate"]["value"]), str(to), "stored as its digits")
	assert_eq(String(s.couriers[0]["order"]["value"]), str(to), "and carried so")
	assert_eq(actions.validate(_law("tax_rate", str(to)), s), "Tax rate is already %d" % to,
		"the plain digits are the same value")
	assert_eq(actions.validate(_law("tax_rate", "+%d" % to), s), "Tax rate is already %d" % to)
	assert_eq(LawSystem.decree(repo, s, "justice_severity", "04").size() > 0, true)
	assert_eq(String(s.law_decree["justice_severity"]["value"]), "4")
