extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The law tables, state and reads (spec 2026-10-08-laws-tab-design §2).

var repo: DataRepository
var s: GameState
var realm: String

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	realm = repo.resolve_realm("player_realm")
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_the_tables_load_seventeen_laws_in_three_pages() -> void:
	assert_eq(repo.law_order.size(), 17)
	assert_eq(LawSystem.codes_on(repo, "military").size(), 12)
	assert_eq(LawSystem.codes_on(repo, "economy").size(), 3)
	assert_eq(LawSystem.codes_on(repo, "politics").size(), 2)
	assert_eq(LawSystem.codes_on(repo, "economy"), ["tax_rate", "tariff_rate", "grain_ration"], "file order")
	assert_true(repo.law_words.has("page_military"))

## Every law_effects.csv row (R11) names a known law and one of its values —
## blank only for a range law's once-row, which is paid per point of change —
## a known timing and share, and an amount that is a number or a balance key.
func test_every_effect_row_names_a_law_and_an_allowed_value() -> void:
	assert_gt(repo.law_effects.size(), 0)
	for row: Dictionary in repo.law_effects:
		var law := String(row["law_code"])
		var d := LawSystem.def(repo, law)
		assert_false(d.is_empty(), "%s is a law" % law)
		if d.is_empty():
			continue
		var v := String(row["value"])
		if String(d["kind"]) == "range" and String(row["timing"]) == "once":
			assert_eq(v, "", "%s: a range's once-row is per point" % law)
		else:
			assert_true(LawSystem.allowed(repo, law, v), "%s: %s is a value of it" % [law, v])
		assert_true(String(row["timing"]) in ["monthly", "once"], "%s: timing" % law)
		assert_true(String(row["share"]) in ["army", "people", "unit", "flat"], "%s: share" % law)
		var amount := String(row["amount"]).strip_edges()
		if String(row["channel"]) == "flag":
			# a flag changes nothing: it has no amount (spec §4.1)
			assert_eq(amount, "", "%s: a flag carries no amount" % law)
			continue
		assert_true(amount.is_valid_float() or repo.balance.has(amount.trim_prefix("-")),
			"%s: %s is a number or a balance key" % [law, amount])
		assert_ne(String(row["reason"]), "", "%s: every line carries a reason" % law)
		if String(row["timing"]) == "once":
			assert_eq(String(row["share"]), "people", "%s: a one-shot is shared by people" % law)
			assert_true(s.metrics.has(String(row["channel"])), "%s: %s is a metric" % [law, row["channel"]])

func test_every_default_is_an_allowed_value() -> void:
	for law: String in repo.law_order:
		var d := LawSystem.def(repo, law)
		if String(d["kind"]) == "range":
			var v := int(d["default"])
			assert_true(v >= int(d["values"][0]) and v <= int(d["values"][1]), law)
		else:
			assert_true((d["values"] as Array).has(String(d["default"])), law)

## Every law's default, pinned against spec 2026-10-08-laws-tab-design §4.4
## ("Values (default first)": a law is a tool the crown imposes, so every
## toggle starts off) and the five old settings' starting values — a slip in
## laws.csv fails here by name.
func test_every_default_is_the_specs() -> void:
	var want := {
		"tax_rate": "5", "tariff_rate": "3", "grain_ration": "market",
		"justice_severity": "3", "church_policy": "none",
		"plunder": "forbid", "obey_command": "off", "protect_church": "off",
		"protect_women": "off", "no_havoc": "off", "register_prisoners": "off",
		"wear_badges": "off", "no_feuds": "off", "quarter": "give", "ransom": "ransom",
		"truce_days": "off", "envoys": "off"}
	assert_eq(repo.law_order.size(), want.size(), "seventeen laws")
	for law: String in repo.law_order:
		assert_true(want.has(law), "%s is a law of the spec" % law)
		assert_eq(String(LawSystem.def(repo, law)["default"]), String(want.get(law, "")), law)
		if String(LawSystem.def(repo, law)["kind"]) == "toggle":
			assert_eq(LawSystem.def(repo, law)["values"], ["off", "on"], "%s: off first" % law)

func test_a_fresh_campaign_follows_the_defaults_and_the_metrics() -> void:
	assert_eq(LawSystem.decreed(repo, s, "tax_rate"), str(int(s.metrics["tax_rate"])))
	assert_eq(LawSystem.decreed(repo, s, "tariff_rate"), str(int(s.metrics["tariff_rate"])))
	assert_eq(LawSystem.decreed(repo, s, "grain_ration"), "market")
	var held := MapOwnership.provinces_of(repo, s, realm)
	assert_false(held.is_empty())
	for code: String in held:
		assert_eq(LawSystem.value(repo, s, "tax_rate", code), str(int(s.metrics["tax_rate"])), code)
		assert_eq(LawSystem.number(repo, s, "tariff_rate", code), int(s.metrics["tariff_rate"]), code)
		assert_eq(LawSystem.value(repo, s, "justice_severity", code), "3", code)
		assert_eq(LawSystem.value(repo, s, "church_policy", code), "none", code)
	var unit := String(s.regiments.keys()[0]) if not s.regiments.is_empty() else "no_such_unit"
	assert_eq(LawSystem.value(repo, s, "plunder", unit), "forbid", "a military law reads its default")
	assert_eq(LawSystem.value(repo, s, "obey_command", unit), "off", "a toggle defaults to off")
	assert_eq(LawSystem.number(repo, s, "obey_command", unit), 0)
	for law: String in repo.law_order:
		assert_true(s.law_decree.has(law), law)
		assert_eq(int(s.law_decree[law]["decree_id"]), 0)

func test_value_falls_back_to_metrics_without_law_state() -> void:
	s.law_decree = {}
	s.law_in_force = {}
	s.metrics["tax_rate"] = 7.0
	s.metrics["grain_ration"] = 1.0
	var code: String = MapOwnership.provinces_of(repo, s, realm)[0]
	assert_eq(LawSystem.value(repo, s, "tax_rate", code), "7")
	assert_eq(LawSystem.decreed(repo, s, "tax_rate"), "7")
	assert_eq(LawSystem.value(repo, s, "grain_ration", code), "ration")
	assert_eq(LawSystem.value(repo, s, "justice_severity", code), "3", "no metric: the default")

func test_a_province_without_an_entry_reads_the_default() -> void:
	assert_eq(LawSystem.value(repo, s, "tax_rate", "no_such_province"), "5")

func test_the_law_state_round_trips_the_save() -> void:
	var code: String = MapOwnership.provinces_of(repo, s, realm)[0]
	s.law_decree["tax_rate"] = {"value": "8", "decree_id": 3, "day": 12}
	s.law_in_force[LawSystem.PROVINCE_PREFIX + code]["tax_rate"] = {"value": "8", "decree_id": 3}
	s.law_in_force[LawSystem.UNIT_PREFIX + "u1"] = {"plunder": {"value": "allow", "decree_id": 2}}
	s.law_cooldown["tax_rate"] = 9
	var before := SaveLoad.state_hash(s)
	var d: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	var back := GameState.from_dict(d)
	assert_eq(SaveLoad.state_hash(back), before)
	assert_eq(back.law_decree["tax_rate"]["decree_id"], 3)
	assert_eq(typeof(back.law_decree["tax_rate"]["decree_id"]), TYPE_INT)
	assert_eq(back.law_cooldown["tax_rate"], 9)
	assert_eq(LawSystem.value(repo, back, "tax_rate", code), "8")

func test_an_older_save_is_seeded_from_the_metrics() -> void:
	var d := s.to_dict()
	d.erase("law_decree")
	d.erase("law_in_force")
	d.erase("law_cooldown")
	var back := GameState.from_dict(d)
	assert_true(back.law_decree.is_empty())
	LawSystem.ensure(repo, back)
	assert_eq(LawSystem.decreed(repo, back, "tax_rate"), str(int(back.metrics["tax_rate"])))
	var code: String = MapOwnership.provinces_of(repo, back, realm)[0]
	assert_eq(LawSystem.value(repo, back, "tax_rate", code), str(int(back.metrics["tax_rate"])))
	# ensure leaves a state that already has laws alone
	back.law_decree["tax_rate"]["value"] = "9"
	LawSystem.ensure(repo, back)
	assert_eq(LawSystem.decreed(repo, back, "tax_rate"), "9")

func test_weighted_number_is_the_people_weighted_mean() -> void:
	var held := MapOwnership.provinces_of(repo, s, realm)
	var weighted := 0
	var people := 0
	for i in range(held.size()):
		var code: String = held[i]
		var v := 2 if i == 0 else 8
		s.law_in_force[LawSystem.PROVINCE_PREFIX + code]["tax_rate"]["value"] = str(v)
		var here := int(roundf(float(WorldLedger.value_of(repo, s, "economy.provinces.%s.rural_population" % code)))) \
			+ int(roundf(float(WorldLedger.value_of(repo, s, "economy.provinces.%s.urban_population" % code))))
		weighted += here * v
		people += here
	assert_gt(people, 0)
	assert_almost_eq(LawSystem.weighted_number(repo, s, "tax_rate"), float(weighted) / float(people), 0.00001)
	if held.size() > 1:
		var mean := LawSystem.weighted_number(repo, s, "tax_rate")
		assert_true(mean > 2.0 and mean < 8.0, "between the two values: %s" % mean)
	# one place alone: its own value
	if held.size() == 1:
		assert_eq(LawSystem.weighted_number(repo, s, "tax_rate"), 2.0)
