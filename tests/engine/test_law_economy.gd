extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The economy laws per province (spec 2026-10-08-laws-tab-design §4.3):
## each province's month reads the tax and tariff in force THERE, the unrest
## pressure the people-weighted tax, the court's bread the grain law where
## the court sits. A manor's tax is hand-computed from the formula
## round(people / 1000 x manor_tax_per_1000 x rate / tax_rate_base x
## (1 + Σ tax_bonus)); its tariff (unmoved by the tax) is added as its line
## gives it.

var data: DataRepository
var s: GameState
var realm: String

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
	realm = data.resolve_realm("player_realm")
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

## The realm's provinces that have manors, by code.
func _held() -> Array:
	var out: Array = []
	for code: String in MapOwnership.provinces_of(data, s, realm):
		if not MapManors.manors_of_province(data, code, s).is_empty():
			out.append(code)
	out.sort()
	return out

func _set_in_force(code: String, law: String, value: String) -> void:
	var key := LawSystem.PROVINCE_PREFIX + code
	var here: Dictionary = s.law_in_force.get(key, {})
	here[law] = {"value": value, "decree_id": int((s.law_decree[law] as Dictionary)["decree_id"])}
	s.law_in_force[key] = here

## A manor's tax at `rate`, by the formula, without its tariff.
func _hand_tax(cell: int, rate: int) -> int:
	var people := MapManors.people_of(data, s, cell)
	return int(roundf(float(people) / 1000.0 * data.bal("manor_tax_per_1000")
		* float(rate) / data.bal("tax_rate_base")
		* (1.0 + MapManors.building_bonus(data, s, cell, "tax_bonus"))))

## A province's month of tax at `rate`: its manors' hand taxes and tariffs.
func _province_tax(code: String, rate: int) -> int:
	var sum := 0
	for cell: int in MapManors.manors_of_province(data, code, s):
		sum += _hand_tax(cell, rate) + int(ManorEconomy.line_of(data, s, cell, s.tick)["tariff"])
	return sum

## The first manor of a province with people in it.
func _peopled_manor(code: String) -> int:
	for cell: int in MapManors.manors_of_province(data, code, s):
		if MapManors.people_of(data, s, cell) > 0:
			return cell
	return -1

func test_a_province_pays_its_own_rate() -> void:
	var held := _held()
	if held.size() < 3:
		pending("the realm holds fewer than three provinces with manors")
		return
	var a: String = held[0]
	var b: String = held[1]
	var c: String = held[2]
	for code: String in held:
		_set_in_force(code, "tax_rate", "8" if code == a else ("2" if code == b else "5"))
	# The mirror says something else: the economy must not read it.
	s.metrics["tax_rate"] = 3.0
	for pair: Array in [[a, 8], [b, 2], [c, 5]]:
		var cell := _peopled_manor(String(pair[0]))
		assert_gt(cell, -1, "a peopled manor in %s" % pair[0])
		var line := ManorEconomy.line_of(data, s, cell, s.tick)
		assert_eq(int(line["tax"]) - int(line["tariff"]), _hand_tax(cell, int(pair[1])),
			"a manor in %s pays at %d" % [pair[0], pair[1]])
	assert_ne(_hand_tax(_peopled_manor(a), 8), _hand_tax(_peopled_manor(a), 2), "the rates tell apart")
	var expected := 0
	for code: String in held:
		var p := RealmEconomy.province(data, s, code)
		var rate := 8 if code == a else (2 if code == b else 5)
		assert_eq(int(p["tax"]), _province_tax(code, rate), "province %s sums at %d" % [code, rate])
		expected += _province_tax(code, rate)
	assert_eq(int(RealmEconomy.realm(data, s)["realm"]["tax"]), expected, "the realm is the sum")

func test_the_first_month_after_a_change_mixes_rates() -> void:
	var held := _held()
	if held.size() < 3:
		pending("the realm holds fewer than three provinces with manors")
		return
	var old := int(LawSystem.decreed(data, s, "tax_rate"))
	var new_rate := 8 if old != 8 else 2
	RealmEconomy.realm(data, s)
	var sent := LawSystem.decree(data, s, "tax_rate", str(new_rate))
	assert_eq(sent.size(), MapOwnership.provinces_of(data, s, realm).size(), "a courier to each province")
	# Only two couriers ride home before the month closes: the crown's own
	# province's and one other.
	var home := MapManors.home_province(data, s)
	var other := ""
	for code: String in held:
		if code != home:
			other = code
			break
	var reached := [home, other]
	for courier: Dictionary in s.couriers.duplicate():
		var key := String((courier.get("order", {}) as Dictionary).get("scope_key", ""))
		if key.trim_prefix(LawSystem.PROVINCE_PREFIX) in reached:
			LawSystem.deliver(data, s, courier)
	s.couriers = s.couriers.filter(func(cc: Dictionary) -> bool:
		return String((cc.get("order", {}) as Dictionary).get("action_code", "")) != LawSystem.ACTION)
	assert_eq(float(s.metrics["tax_rate"]), float(new_rate), "the mirror moved at the decree")
	var mine := MapManors.controlled_provinces(data, s)
	var lord := 0
	var rest := 0
	for code: String in held:
		var rate := new_rate if code in reached else old
		if code in mine:
			lord += _province_tax(code, rate)
		else:
			rest += _province_tax(code, rate)
	var expected := lord + int(roundf(data.bal("crown_share_permille") / 1000.0 * float(rest)))
	var tick := TickEngine.new(data)
	tick._settle_economy(s, TickReport.new())
	assert_eq(int(s.metrics["tax_income"]), expected, "two provinces at %d, the rest at %d" % [new_rate, old])
	var all_old := 0
	for code: String in held:
		if code in mine:
			all_old += _province_tax(code, old)
	assert_ne(lord, all_old, "the crown's own province already pays the new rate")

func test_the_cache_key_follows_a_provinces_law() -> void:
	var held := _held()
	assert_gt(held.size(), 1)
	var a: String = held[0]
	var b: String = held[1]
	var key_a := RealmEconomy.province_key(data, s, a)
	var key_b := RealmEconomy.province_key(data, s, b)
	var sig := RealmEconomy.realm_signature(s)
	assert_eq(RealmEconomy.province_key(data, s, a), key_a, "no change, the same key")
	assert_eq(RealmEconomy.realm_signature(s), sig, "no change, the same signature")
	var was := LawSystem.number(data, s, "tax_rate", a)
	_set_in_force(a, "tax_rate", str(9 if was != 9 else 1))
	assert_ne(RealmEconomy.province_key(data, s, a), key_a, "the key sees the province's tax")
	assert_eq(RealmEconomy.province_key(data, s, b), key_b, "another province's key stays")
	assert_ne(RealmEconomy.realm_signature(s), sig, "the signature sees it")
	var key_a2 := RealmEconomy.province_key(data, s, a)
	var sig2 := RealmEconomy.realm_signature(s)
	var tariff := LawSystem.number(data, s, "tariff_rate", a)
	_set_in_force(a, "tariff_rate", str(tariff + 1 if tariff < 10 else tariff - 1))
	assert_ne(RealmEconomy.province_key(data, s, a), key_a2, "the key sees the province's tariff")
	assert_ne(RealmEconomy.realm_signature(s), sig2, "the signature sees the tariff")
	# the cached sums follow
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.check_full(data, s), [], "the cache agrees with a fresh count")

func test_the_unrest_pressure_reads_the_weighted_rate() -> void:
	var held := MapOwnership.provinces_of(data, s, realm)
	assert_gt(held.size(), 1)
	var weighted := 0
	var people := 0
	for i in range(held.size()):
		var code: String = held[i]
		var v := 2 if i == 0 else 8
		_set_in_force(code, "tax_rate", str(v))
		var here := int(roundf(float(WorldLedger.value_of(data, s, "economy.provinces.%s.rural_population" % code)))) \
			+ int(roundf(float(WorldLedger.value_of(data, s, "economy.provinces.%s.urban_population" % code))))
		weighted += here * v
		people += here
	s.metrics["tax_rate"] = 5.0  # the mirror says the pivot: it must not be read
	s.metrics["grain"] = 100.0  # no famine line
	var mean := float(weighted) / float(people)
	assert_true(mean > 2.0 and mean < 8.0, "a mixture: %s" % mean)
	var expected := (mean - data.bal("unrest_tax_pivot")) * data.bal("unrest_tax_pressure") - data.bal("unrest_decay")
	var r := TickReport.new()
	TickEngine.new(data)._drift(s, r)
	var found := false
	for d: Dictionary in r.metric_deltas:
		if String(d["reason"]) == "tax pressure and the mood of the villages":
			assert_almost_eq(float(d["delta"]), expected, 0.00001)
			found = true
	assert_true(found, "the pressure line is written")

func test_ration_halves_the_courts_bread_only_where_the_court_sits() -> void:
	var cap := String((data.kingdoms.get(realm, {}) as Dictionary).get("capital_burg", ""))
	var capital := String((data.burgs.get(cap, {}) as Dictionary).get("province_code", ""))
	assert_ne(capital, "", "the realm has a capital province")
	var held := MapOwnership.provinces_of(data, s, realm)
	assert_true(capital in held)
	var other := ""
	for code: String in held:
		if code != capital:
			other = code
			break
	assert_ne(other, "")
	var full := int(roundf(float(TickEngine.court_people(data, s)) / 1000.0 * data.bal("ration_gold_per_1000")))
	assert_gt(full, 1, "a ration that halving shows")
	for code: String in held:
		_set_in_force(code, "grain_ration", "market")
	_set_in_force(capital, "grain_ration", "ration")
	s.metrics["grain_ration"] = 0.0  # the mirror says market: it must not be read
	@warning_ignore("integer_division")
	assert_eq(TickEngine.ration_of(data, s), full / 2, "ration in the capital's province halves it")
	_set_in_force(capital, "grain_ration", "market")
	_set_in_force(other, "grain_ration", "ration")
	s.metrics["grain_ration"] = 1.0
	assert_eq(TickEngine.ration_of(data, s), full, "ration elsewhere leaves the court's bread")
	_set_in_force(capital, "grain_ration", "release")
	assert_eq(TickEngine.ration_of(data, s), full, "release is market for the court's bread")

## R8: a hand-built repository with no law tables and a state with no law
## state read the metrics, as before the laws. The repository is
## test_manor_economy.gd's: cell 1 (1 500 people, no town) pays
## round(1.5 x 20 x 5 / 5) = 30; cell 2 (2 500 people, Shole's 15 gold of
## goods) 50 + tariff round(15 x 3 x 2 / 100) = 1 -> 51. At tax 10: 60 and
## 100 + 1.
func test_older_fixtures_still_work() -> void:
	var r := _hand_repo()
	var st := GameState.new()
	st.rng = Rng.new(1)
	st.tick = 0
	st.metrics = {"tax_rate": 5.0, "tariff_rate": 3.0}
	st.player_setup = {"first_name": "Anne", "family_name": "Rex", "flag": ""}
	assert_true(r.laws.is_empty())
	assert_eq(ManorEconomy.line_of(r, st, 1, 0)["tax"], 30)
	assert_eq(ManorEconomy.line_of(r, st, 2, 0)["tax"], 51)
	assert_eq(ManorEconomy.line_of(r, st, 2, 0)["tariff"], 1)
	assert_eq(int(RealmEconomy.province(r, st, "p")["tax"]), 81)
	st.metrics["tax_rate"] = 10.0
	assert_eq(ManorEconomy.line_of(r, st, 1, 0)["tax"], 60)
	assert_eq(int(RealmEconomy.province(r, st, "p")["tax"]), 161, "the key follows the metric")
	st.metrics["tariff_rate"] = 0.0
	assert_eq(ManorEconomy.line_of(r, st, 2, 0)["tariff"], 0)
	MapManors.invalidate()
	MapEconomy.forget()
	ManorEconomy.forget()

## The rate metrics are the decree's display mirror: no engine formula reads
## them. Only the pack's seeding writes them (WorldLedger.seed_metrics) and
## the realm signature keeps them for a state with no law state (R8).
func test_no_engine_formula_reads_the_rate_mirrors() -> void:
	var allowed := {"world_ledger.gd": true, "realm_economy.gd": true}
	var rx := RegEx.create_from_string('(metrics|\\bm)(\\.get\\(|\\[)"(tax_rate|tariff_rate|grain_ration)"')
	var found: Array = []
	for path: String in _scripts("res://scripts/engine"):
		if allowed.has(path.get_file()):
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			if rx.search(lines[i]) != null:
				found.append("%s:%d" % [path, i + 1])
	assert_eq(found, [], "read the law in force (LawSystem), not the metric")

func _scripts(dir: String) -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out

func _hand_repo() -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"manor_tax_per_1000": 20.0, "tax_rate_base": 5.0, "tariff_per_sales_tax": 2.0,
		"manor_focus_high_height": 52.0, "manor_focus_peak_height": 63.0}
	r.biomes = {1: {"habitability": "80"}, 2: {"habitability": "40"}}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10), 3: Vector2(0, 10),
		4: Vector2(30, 0), 5: Vector2(30, 10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 30.0, "biome_id": 1,
			"water": "", "neighbor_ids": PackedInt32Array([2])},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 30.0, "biome_id": 2,
			"water": "", "neighbor_ids": PackedInt32Array([1])},
	}
	r.manors = {
		1: {"cell_id": 1, "manor_code": "ashcombe", "label": "Ashcombe", "province_code": "p",
			"burg_code": "", "culture_code": "c"},
		2: {"cell_id": 2, "manor_code": "shole_manor", "label": "Shole Manor", "province_code": "p",
			"burg_code": "shole", "culture_code": "c"},
	}
	for id: int in r.manors:
		r.manor_by_code[String(r.manors[id]["manor_code"])] = id
		r.manor_by_label[String(r.manors[id]["label"]).to_lower()] = id
	r.provinces = {"p": {"province_code": "p", "label": "Prov", "kingdom_code": "k", "capital_burg": "shole"}}
	r.burgs = {"shole": {"burg_code": "shole", "label": "Shole", "province_code": "p",
		"population": "1000", "x": "20", "y": "5"}}
	r.house_bindings = {"p": "Valorin"}
	r.manor_focus = {"grain": {"focus_code": "grain", "label": "Grain fields", "good_code": "grain",
		"biomes": "1", "coast": "0", "yield_per_1000": "12",
		"switch_cost_gold": "20", "transition_ticks": "2", "default_on": "1"}}
	r.goods_economy = {
		"grain": {"good_code": "grain", "pool": "civil", "price_gold": "1", "growth_permille": "2"},
		"wood": {"good_code": "wood", "pool": "civil", "price_gold": "1", "growth_permille": "3"},
		"iron": {"good_code": "iron", "pool": "strategic", "price_gold": "4", "growth_permille": "3"},
	}
	r.world_schema = [
		{"path": "economy.provinces.*.rural_population", "type": "int", "min": "0",
			"max": "100000000", "enum_values": "", "good_direction": "1", "llm_cap": "2000",
			"alias_to": "", "alias_scale_key": ""},
		{"path": "economy.provinces.*.urban_population", "type": "int", "min": "0",
			"max": "100000000", "enum_values": "", "good_direction": "1", "llm_cap": "1000",
			"alias_to": "", "alias_scale_key": ""},
	]
	r._register_table("economy", "provinces", {
		"p": {"province_code": "p", "rural_population": "3000", "urban_population": "1000"}})
	r._register_table("economy", "goods", {
		"grain": {"good_code": "grain", "label": "Grain", "tags": "food"},
		"wood": {"good_code": "wood", "label": "Wood", "tags": "construction|fuel"},
		"iron": {"good_code": "iron", "label": "Iron", "tags": "ore|military"}})
	r._register_table("economy", "production", {
		"shole:wood": {"burg_code": "shole", "good_code": "wood", "units": "7"},
		"shole:iron": {"burg_code": "shole", "good_code": "iron", "units": "2"}})
	MapManors.invalidate()
	MapEconomy.forget()
	ManorEconomy.forget()
	return r
