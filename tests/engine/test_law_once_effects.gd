extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const RunDir := preload("res://tests/run_dir.gd")
## The laws' one-shot effects (spec 2026-10-08-laws-tab-design §4.3, plan
## rulings R7 and R11): justice severity, church policy and the grain policy's
## ration and release pay the old order's realm-wide effect ONCE, province by
## province, as each courier changes the value in force there — the old total
## times the province's share of the realm's people.
##
## The old total is apportioned over the realm's provinces (sorted codes) by
## their people (rural plus urban, `RealmEconomy._figure`), largest remainder,
## ties to the code that sorts first — in whole units for the whole pools
## (treasury, grain: root invariant 11) and tenths for the other channels — so
## delivered everywhere the provinces pay the old total EXACTLY, in any order.
## The expected figures below are computed by hand here, never through
## LawEffects. (Float sums of tenths are compared to 1e-6.)

const EPS := 0.000001

var repo: DataRepository
var s: GameState
var realm: String


func before_all() -> void:
	RoadGraph.forget()


func after_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	realm = repo.resolve_realm("player_realm")
	RealmEconomy.forget()
	Weather.forget()
	s.recent_outcomes = []


func after_each() -> void:
	RealmEconomy.forget()


## A province's people, by the pack's figures.
func _people(code: String) -> int:
	return RealmEconomy._figure(repo, s, "economy.provinces.%s.rural_population" % code) \
		+ RealmEconomy._figure(repo, s, "economy.provinces.%s.urban_population" % code)


## The realm's provinces, sorted.
func _codes() -> Array:
	var out: Array = []
	for code: String in MapOwnership.provinces_of(repo, s, realm):
		out.append(code)
	out.sort()
	return out


## A whole `units` split over the realm's provinces by people, by hand:
## floor, then one more unit each to the largest remainders (ties to the
## lower code).
func _hand_split(units: int) -> Dictionary:
	var codes := _codes()
	var total := 0
	for code: String in codes:
		total += _people(code)
	assert_gt(total, 0, "the realm has people")
	var out := {}
	var given := 0
	var rems: Array = []
	for code: String in codes:
		out[code] = units * _people(code) / total
		given += int(out[code])
		rems.append([units * _people(code) % total, code])
	rems.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and String(a[1]) < String(b[1])))
	for i in range(units - given):
		out[rems[i][1]] = int(out[rems[i][1]]) + 1
	return out


## A province's part of an old realm total of `metric`, by hand: whole units
## for treasury and grain, tenths otherwise.
func _share(metric: String, total: float, code: String) -> float:
	var scale := 1 if metric in ["treasury", "grain"] else 10
	var units := roundi(absf(total) * scale)
	var dir := -1.0 if total < 0.0 else 1.0
	return dir * float(int(_hand_split(units)[code])) / float(scale)


## The most peopled province (ties to the lower code): its part is never zero.
func _big() -> String:
	var best: String = _codes()[0]
	for code: String in _codes():
		if _people(code) > _people(best):
			best = code
	return best


## The courier a decree sent to a province.
func _courier_for(sent: Array, code: String) -> Dictionary:
	for c: Dictionary in sent:
		if String(CourierSystem.first_order(c)["scope_key"]) == LawSystem.PROVINCE_PREFIX + code:
			return c
	return {}


## Decree `value` of `law` with no cooldown in the way; the couriers sent.
func _decree(law: String, value: String) -> Array:
	s.law_cooldown.erase(law)
	return LawSystem.decree(repo, s, law, value)


func _m(metric: String) -> float:
	return float(s.metrics[metric])


## Every effect line the deliveries left in recent_outcomes.
func _lines() -> Array:
	var out: Array = []
	for o: Dictionary in s.recent_outcomes:
		out.append_array(o["effects"])
	return out


func _deliver_all(sent: Array) -> void:
	for c: Dictionary in sent:
		LawSystem.deliver(repo, s, c)


## Whether every treasury and grain line is a whole number (invariant 11).
func _whole_pools_whole() -> bool:
	for l: Dictionary in _lines():
		if String(l["metric"]) in ["treasury", "grain"] and float(l["delta"]) != roundf(float(l["delta"])):
			return false
	return true


func test_the_shares_sum_to_the_old_total_exactly() -> void:
	for pair: Array in [["treasury", -repo.bal("church_endow_cost")], ["church_opinion", repo.bal("church_endow_gain")],
			["treasury", repo.bal("church_tithe_gain")], ["church_opinion", repo.bal("church_tithe_opinion")],
			["grain", -repo.bal("grain_release_amount")], ["unrest", repo.bal("justice_unrest_per_point")],
			["peasant_contentment", repo.bal("grain_ration_contentment")]]:
		var metric: String = pair[0]
		var total: float = pair[1]
		var parts := LawEffects.apportion(repo, s, metric, total)
		assert_eq(parts.keys().size(), _codes().size(), "a part for every province of the realm")
		var sum := 0.0
		for code: String in _codes():
			assert_almost_eq(float(parts[code]), _share(metric, total, code), EPS, "%s %s" % [metric, code])
			sum += float(parts[code])
			if metric in ["treasury", "grain"]:
				assert_eq(float(parts[code]), roundf(float(parts[code])), "%s is whole" % metric)
		assert_almost_eq(sum, total, EPS, "%s %.1f apportioned exactly" % [metric, total])


## Two literal cases, worked by hand: three equal weights share 100 tenths
## as 34 / 33 / 33 (the one left over to the code that sorts first), the
## sign re-applied; a realm where no one lives splits evenly.
func test_the_apportionment_by_literal_weights() -> void:
	assert_eq(LawEffects.apportion_by("treasury", 100.0, {"a": 1, "b": 1, "c": 1}),
		{"a": 34.0, "b": 33.0, "c": 33.0})
	assert_eq(LawEffects.apportion_by("treasury", -100.0, {"c": 1, "b": 1, "a": 1}),
		{"a": -34.0, "b": -33.0, "c": -33.0})
	var tenths := LawEffects.apportion_by("unrest", 10.0, {"a": 1, "b": 1, "c": 1})
	assert_almost_eq(float(tenths["a"]), 3.4, EPS)
	assert_almost_eq(float(tenths["b"]), 3.3, EPS)
	assert_almost_eq(float(tenths["c"]), 3.3, EPS)
	assert_eq(LawEffects.apportion_by("grain", 10.0, {"a": 0, "b": 0}), {"a": 5.0, "b": 5.0},
		"no people anywhere: an even split")
	assert_eq(LawEffects.apportion_by("grain", 3.0, {"a": 0, "b": 0}), {"a": 2.0, "b": 1.0},
		"an odd unit to the code that sorts first")


func test_justice_effect_is_the_old_total_times_the_provinces_people_share() -> void:
	assert_eq(LawSystem.decreed(repo, s, "justice_severity"), "3", "the default")
	var code := _big()
	var sent := _decree("justice_severity", "4")
	var unrest := _m("unrest")
	var content := _m("peasant_contentment")
	LawSystem.deliver(repo, s, _courier_for(sent, code))
	# The old JUSTICE_SEVERITY order of +1: unrest and contentment each moved
	# by their per-point keys, at full realm.
	var want_unrest := _share("unrest", repo.bal("justice_unrest_per_point"), code)
	var want_content := _share("peasant_contentment", repo.bal("justice_contentment_per_point"), code)
	assert_ne(want_unrest, 0.0, "the biggest province pays something")
	assert_almost_eq(_m("unrest") - unrest, want_unrest, EPS, "unrest, its people's part")
	assert_almost_eq(_m("peasant_contentment") - content, want_content, EPS, "contentment, its people's part")
	var label := LawSystem.place_label(repo, s, LawSystem.PROVINCE_PREFIX + code)
	var unrest_lines := _lines().filter(func(l: Dictionary) -> bool: return String(l["metric"]) == "unrest")
	assert_eq(unrest_lines.size(), 1)
	var reason := String(unrest_lines[0]["reason"])
	assert_string_contains(reason, "severity of justice 3 → 4 reaches " + label)
	assert_string_contains(reason, "unrest −")
	assert_almost_eq(float(unrest_lines[0]["delta"]), want_unrest, EPS)
	# A province told nothing pays nothing: one province's part only.
	assert_eq(_lines().size(), 2, "one line each for unrest and contentment")


func test_delivered_everywhere_the_sum_is_the_old_effect() -> void:
	var sent := _decree("justice_severity", "4")
	assert_eq(sent.size(), _codes().size())
	var unrest := _m("unrest")
	var content := _m("peasant_contentment")
	# in reverse order: the parts do not depend on who is told first
	var backwards := sent.duplicate()
	backwards.reverse()
	_deliver_all(backwards)
	assert_almost_eq(_m("unrest") - unrest, repo.bal("justice_unrest_per_point"), EPS,
		"the old +1 order's unrest, exactly")
	assert_almost_eq(_m("peasant_contentment") - content, repo.bal("justice_contentment_per_point"), EPS,
		"the old +1 order's contentment, exactly")
	# Two points of change pay twice the per-point total.
	unrest = _m("unrest")
	_deliver_all(_decree("justice_severity", "2"))
	assert_almost_eq(_m("unrest") - unrest, -2.0 * repo.bal("justice_unrest_per_point"), EPS,
		"4 → 2 is two points the other way")


func test_church_endow_and_tithe_pay_their_old_numbers_in_shares() -> void:
	var code := _big()
	var sent := _decree("church_policy", "endow")
	var gold := _m("treasury")
	var church := _m("church_opinion")
	LawSystem.deliver(repo, s, _courier_for(sent, code))
	assert_eq(_m("treasury") - gold, _share("treasury", -repo.bal("church_endow_cost"), code), "endow: the chest")
	assert_almost_eq(_m("church_opinion") - church, _share("church_opinion", repo.bal("church_endow_gain"), code),
		EPS, "endow: the church")
	_deliver_all(sent)
	assert_eq(_m("treasury") - gold, -repo.bal("church_endow_cost"), "endowed everywhere: the old gold exactly")
	assert_almost_eq(_m("church_opinion") - church, repo.bal("church_endow_gain"), EPS)
	gold = _m("treasury")
	church = _m("church_opinion")
	_deliver_all(_decree("church_policy", "tithe"))
	assert_eq(_m("treasury") - gold, repo.bal("church_tithe_gain"), "tithed everywhere")
	assert_almost_eq(_m("church_opinion") - church, repo.bal("church_tithe_opinion"), EPS)
	assert_true(_whole_pools_whole(), "every treasury line is whole gold")
	# none pays nothing
	gold = _m("treasury")
	church = _m("church_opinion")
	_deliver_all(_decree("church_policy", "none"))
	assert_eq(_m("treasury"), gold, "none has no one-shot")
	assert_eq(_m("church_opinion"), church)


func test_release_pays_once_and_a_second_release_needs_a_change_between() -> void:
	var code := _big()
	var want_grain := _share("grain", -repo.bal("grain_release_amount"), code)
	var want_content := _share("peasant_contentment", repo.bal("grain_release_contentment"), code)
	var sent := _decree("grain_ration", "release")
	var c1 := _courier_for(sent, code)
	var grain := _m("grain")
	var content := _m("peasant_contentment")
	LawSystem.deliver(repo, s, c1)
	assert_eq(_m("grain") - grain, want_grain, "stores opened, its people's part, whole")
	assert_almost_eq(_m("peasant_contentment") - content, want_content, EPS)
	# the same courier again pays nothing
	grain = _m("grain")
	LawSystem.deliver(repo, s, c1)
	assert_eq(_m("grain"), grain, "a courier arriving twice pays once")
	# market, lost on the road to this province; release again reaches it:
	# its value there never changed, so nothing is paid
	_decree("grain_ration", "market")
	var again := _decree("grain_ration", "release")
	LawSystem.deliver(repo, s, _courier_for(again, code))
	assert_eq(_m("grain"), grain, "release → release is no change")
	# market reaches it, then release again: paid again
	var back := _decree("grain_ration", "market")
	LawSystem.deliver(repo, s, _courier_for(back, code))
	assert_eq(_m("grain"), grain, "market has no one-shot")
	content = _m("peasant_contentment")
	LawSystem.deliver(repo, s, _courier_for(_decree("grain_ration", "release"), code))
	assert_eq(_m("grain") - grain, want_grain, "a change between, paid again")
	assert_almost_eq(_m("peasant_contentment") - content, want_content, EPS)
	# ration bites
	content = _m("peasant_contentment")
	LawSystem.deliver(repo, s, _courier_for(_decree("grain_ration", "ration"), code))
	assert_almost_eq(_m("peasant_contentment") - content,
		_share("peasant_contentment", repo.bal("grain_ration_contentment"), code), EPS, "rationing bites")
	assert_true(_whole_pools_whole(), "every grain line is whole")


func test_a_stale_courier_pays_nothing() -> void:
	var code := _big()
	var first := _courier_for(_decree("justice_severity", "4"), code)
	var second := _courier_for(_decree("justice_severity", "5"), code)
	var unrest := _m("unrest")
	LawSystem.deliver(repo, s, second)
	assert_almost_eq(_m("unrest") - unrest, _share("unrest", 2.0 * repo.bal("justice_unrest_per_point"), code), EPS,
		"3 → 5 here: two points")
	unrest = _m("unrest")
	var lines := _lines().size()
	assert_eq(String(LawSystem.deliver(repo, s, first)["type"]), "stale")
	assert_eq(_m("unrest"), unrest, "the older decree pays nothing")
	assert_eq(_lines().size(), lines, "and writes no line")
	# a lost province pays nothing
	var other := _codes().filter(func(c: String) -> bool: return c != code)
	if other.is_empty():
		pending("the realm holds one province")
		return
	var lost: String = other[0]
	var to_lost := _courier_for(_decree("justice_severity", "1"), lost)
	var kingdoms: Array = repo.kingdoms.keys()
	kingdoms.sort()
	var foe: String = kingdoms.filter(func(k: String) -> bool: return k != realm)[0]
	assert_true(MapOwnership.set_owner(repo, s, lost, foe, "test: the province falls"))
	unrest = _m("unrest")
	var content := _m("peasant_contentment")
	assert_eq(String(LawSystem.deliver(repo, s, to_lost)["type"]), "lost")
	assert_eq(_m("unrest"), unrest, "a lost province pays nothing")
	assert_eq(_m("peasant_contentment"), content)


func test_a_resend_pays_nothing_for_a_province_that_already_has_the_value() -> void:
	var code := _big()
	var sent := _decree("church_policy", "endow")
	var mine := _courier_for(sent, code)
	# every courier but this province's arrives; its courier is lost
	for c: Dictionary in sent:
		if c != mine:
			LawSystem.deliver(repo, s, c)
	s.couriers = s.couriers.filter(func(c: Dictionary) -> bool:
		return String(CourierSystem.first_order(c).get("action_code", "")) != LawSystem.ACTION)
	assert_true(LawSystem.is_resend(repo, s, "church_policy", "endow"))
	var gold := _m("treasury")
	var church := _m("church_opinion")
	var resent := LawSystem.decree(repo, s, "church_policy", "endow")
	assert_eq(resent.size(), 1, "a re-send rides only for the missing province")
	assert_eq(int(CourierSystem.first_order(resent[0])["decree_id"]), int(CourierSystem.first_order(mine)["decree_id"]), "the same decree")
	LawSystem.deliver(repo, s, resent[0])
	assert_eq(_m("treasury") - gold, _share("treasury", -repo.bal("church_endow_cost"), code),
		"the missing province pays its part once")
	assert_almost_eq(_m("church_opinion") - church, _share("church_opinion", repo.bal("church_endow_gain"), code), EPS)
	# the re-sent courier, or the first, arriving where the value already is
	gold = _m("treasury")
	LawSystem.deliver(repo, s, resent[0])
	LawSystem.deliver(repo, s, mine)
	for c: Dictionary in sent:
		LawSystem.deliver(repo, s, c)
	assert_eq(_m("treasury"), gold, "a province that already has the value pays nothing")


func test_a_month_of_law_effects_survives_a_save() -> void:
	_deliver_all(_decree("church_policy", "endow"))
	_deliver_all(_decree("justice_severity", "4"))
	assert_eq(s.recent_outcomes.size(), 1, "one LAW_EFFECTS outcome gathers the month")
	assert_eq(String(s.recent_outcomes[0]["action_code"]), LawEffects.OUTCOME)
	var path := RunDir.dir("law_once_effects").path_join("save.json")
	assert_true(SaveLoad.save_game(s, path))
	var loaded := SaveLoad.load_game(path)
	assert_not_null(loaded)
	assert_eq(loaded.recent_outcomes, s.recent_outcomes, "the outcome and its lines come back as they were")
	assert_eq(loaded.metrics["treasury"], s.metrics["treasury"])
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(s))


func test_a_law_with_no_once_row_pays_nothing() -> void:
	var before := s.metrics.duplicate()
	var now := int(LawSystem.decreed(repo, s, "tax_rate"))
	_deliver_all(_decree("tax_rate", str(now + 1 if now < 10 else now - 1)))
	assert_eq(_lines().size(), 0, "a tax courier pays no one-shot")
	assert_eq(LawEffects.once_lines(repo, s, "tax_rate", "5", "6", _big()), [])
	assert_eq(s.metrics["unrest"], before["unrest"])
