extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The laws' one-shot effects (spec 2026-10-08-laws-tab-design §4.3, plan
## rulings R7 and R11): justice severity, church policy and the grain policy's
## ration and release pay the old order's realm-wide effect ONCE, province by
## province, as each courier changes the value in force there — the old total
## times the province's share of the realm's people.
##
## The share is a whole per mille: floor(people × 1000 / realm's people), the
## remainder to the province with the most people (ties to the lower code), so
## the shares sum to exactly 1000. A province's line is
## round(total × per_mille / 1000, one decimal) — one rounding, at the end.
## The expected figures below are computed by hand from the pack's people
## (rural plus urban, `RealmEconomy._figure`), never through LawEffects.
##
## Tolerance of a sum: each province's line is rounded to one decimal, so it is
## off its exact share by at most 0.05; over N provinces the sum is off the old
## total by at most 0.05 × N (the brief allows 0.1 a province; this holds the
## tighter half). The exact shares themselves sum to the total because the per
## milles sum to 1000.

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


## The per-mille shares by hand: floor, then the remainder to the most
## peopled (ties to the lower code).
func _hand_permille() -> Dictionary:
	var codes := _codes()
	var total := 0
	for code: String in codes:
		total += _people(code)
	assert_gt(total, 0, "the realm has people")
	var out := {}
	var given := 0
	var top: String = codes[0]
	for code: String in codes:
		out[code] = _people(code) * 1000 / total
		given += int(out[code])
		if _people(code) > _people(top):
			top = code
	out[top] = int(out[top]) + 1000 - given
	return out


## The line a province pays of an old total, by the rule.
func _share(total: float, permille: int) -> float:
	return roundf(total * float(permille) / 1000.0 * 10.0) / 10.0


## The most peopled province (the remainder's): its share is never zero.
func _big() -> String:
	var pm := _hand_permille()
	var best: String = _codes()[0]
	for code: String in _codes():
		if int(pm[code]) > int(pm[best]):
			best = code
	return best


## The courier a decree sent to a province.
func _courier_for(sent: Array, code: String) -> Dictionary:
	for c: Dictionary in sent:
		if String(c["order"]["scope_key"]) == LawSystem.PROVINCE_PREFIX + code:
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


func test_the_per_mille_shares_sum_to_a_thousand() -> void:
	var pm := LawEffects.people_permille(repo, s)
	var hand := _hand_permille()
	assert_eq(pm.keys().size(), _codes().size(), "one share a province of the realm")
	var sum := 0
	for code: String in _codes():
		assert_eq(int(pm[code]), int(hand[code]), code)
		sum += int(pm[code])
	assert_eq(sum, 1000)


func test_justice_effect_is_the_old_total_times_the_provinces_people_share() -> void:
	assert_eq(LawSystem.decreed(repo, s, "justice_severity"), "3", "the default")
	var code := _big()
	var pm := int(_hand_permille()[code])
	var sent := _decree("justice_severity", "4")
	var unrest := _m("unrest")
	var content := _m("peasant_contentment")
	LawSystem.deliver(repo, s, _courier_for(sent, code))
	# The old JUSTICE_SEVERITY order of +1: unrest and contentment each moved
	# by their per-point keys, at full realm.
	var want_unrest := _share(repo.bal("justice_unrest_per_point") * 1.0, pm)
	var want_content := _share(repo.bal("justice_contentment_per_point") * 1.0, pm)
	assert_ne(want_unrest, 0.0, "the biggest province pays something")
	assert_almost_eq(_m("unrest") - unrest, want_unrest, EPS, "unrest × %d‰" % pm)
	assert_almost_eq(_m("peasant_contentment") - content, want_content, EPS, "contentment × %d‰" % pm)
	var label := LawSystem.place_label(repo, s, LawSystem.PROVINCE_PREFIX + code)
	var unrest_lines := _lines().filter(func(l: Dictionary) -> bool: return String(l["metric"]) == "unrest")
	assert_eq(unrest_lines.size(), 1)
	var reason := String(unrest_lines[0]["reason"])
	assert_string_contains(reason, "severity of justice 3 → 4 reaches " + label)
	assert_string_contains(reason, "unrest −")
	assert_almost_eq(float(unrest_lines[0]["delta"]), want_unrest, EPS)
	# A province told nothing pays nothing: one province's share only.
	assert_eq(_lines().size(), 2, "one line each for unrest and contentment")


func test_delivered_everywhere_the_sum_is_the_old_effect() -> void:
	var n := _codes().size()
	var tol := 0.05 * float(n) + EPS
	var sent := _decree("justice_severity", "4")
	assert_eq(sent.size(), n)
	var unrest := _m("unrest")
	var content := _m("peasant_contentment")
	_deliver_all(sent)
	var pm := _hand_permille()
	var hand_unrest := 0.0
	for code: String in _codes():
		hand_unrest += _share(repo.bal("justice_unrest_per_point"), int(pm[code]))
	assert_almost_eq(_m("unrest") - unrest, hand_unrest, EPS, "the sum of the provinces' lines")
	assert_almost_eq(_m("unrest") - unrest, repo.bal("justice_unrest_per_point"), tol,
		"the old +1 order's unrest, within 0.05 × %d provinces" % n)
	assert_almost_eq(_m("peasant_contentment") - content, repo.bal("justice_contentment_per_point"), tol,
		"the old +1 order's contentment")
	# Two points of change pay twice the per-point total.
	unrest = _m("unrest")
	_deliver_all(_decree("justice_severity", "2"))
	assert_almost_eq(_m("unrest") - unrest, -2.0 * repo.bal("justice_unrest_per_point"), tol,
		"4 → 2 is two points the other way")


func test_church_endow_and_tithe_pay_their_old_numbers_in_shares() -> void:
	var n := _codes().size()
	var tol := 0.05 * float(n) + EPS
	var code := _big()
	var pm := int(_hand_permille()[code])
	var sent := _decree("church_policy", "endow")
	var gold := _m("treasury")
	var church := _m("church_opinion")
	LawSystem.deliver(repo, s, _courier_for(sent, code))
	assert_almost_eq(_m("treasury") - gold, _share(-repo.bal("church_endow_cost"), pm), EPS, "endow: the chest")
	assert_almost_eq(_m("church_opinion") - church, _share(repo.bal("church_endow_gain"), pm), EPS,
		"endow: the church")
	_deliver_all(sent)
	assert_almost_eq(_m("treasury") - gold, -repo.bal("church_endow_cost"), tol, "endowed everywhere")
	assert_almost_eq(_m("church_opinion") - church, repo.bal("church_endow_gain"), tol)
	gold = _m("treasury")
	church = _m("church_opinion")
	_deliver_all(_decree("church_policy", "tithe"))
	assert_almost_eq(_m("treasury") - gold, repo.bal("church_tithe_gain"), tol, "tithed everywhere")
	assert_almost_eq(_m("church_opinion") - church, repo.bal("church_tithe_opinion"), tol)
	# none pays nothing
	gold = _m("treasury")
	church = _m("church_opinion")
	_deliver_all(_decree("church_policy", "none"))
	assert_eq(_m("treasury"), gold, "none has no one-shot")
	assert_eq(_m("church_opinion"), church)


func test_release_pays_once_and_a_second_release_needs_a_change_between() -> void:
	var code := _big()
	var pm := int(_hand_permille()[code])
	var want_grain := _share(-repo.bal("grain_release_amount"), pm)
	var want_content := _share(repo.bal("grain_release_contentment"), pm)
	var sent := _decree("grain_ration", "release")
	var c1 := _courier_for(sent, code)
	var grain := _m("grain")
	var content := _m("peasant_contentment")
	LawSystem.deliver(repo, s, c1)
	assert_almost_eq(_m("grain") - grain, want_grain, EPS, "stores opened, × %d‰" % pm)
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
	assert_almost_eq(_m("grain") - grain, want_grain, EPS, "a change between, paid again")
	assert_almost_eq(_m("peasant_contentment") - content, want_content, EPS)
	# ration bites
	content = _m("peasant_contentment")
	LawSystem.deliver(repo, s, _courier_for(_decree("grain_ration", "ration"), code))
	assert_almost_eq(_m("peasant_contentment") - content, _share(repo.bal("grain_ration_contentment"), pm), EPS,
		"rationing bites")


func test_a_stale_courier_pays_nothing() -> void:
	var code := _big()
	var pm := int(_hand_permille()[code])
	var first := _courier_for(_decree("justice_severity", "4"), code)
	var second := _courier_for(_decree("justice_severity", "5"), code)
	var unrest := _m("unrest")
	LawSystem.deliver(repo, s, second)
	assert_almost_eq(_m("unrest") - unrest, _share(2.0 * repo.bal("justice_unrest_per_point"), pm), EPS,
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
	var pm := int(_hand_permille()[code])
	var sent := _decree("church_policy", "endow")
	var mine := _courier_for(sent, code)
	# every courier but this province's arrives; its courier is lost
	for c: Dictionary in sent:
		if c != mine:
			LawSystem.deliver(repo, s, c)
	s.couriers = s.couriers.filter(func(c: Dictionary) -> bool:
		return String((c.get("order", {}) as Dictionary).get("action_code", "")) != LawSystem.ACTION)
	assert_true(LawSystem.is_resend(repo, s, "church_policy", "endow"))
	var gold := _m("treasury")
	var church := _m("church_opinion")
	var resent := LawSystem.decree(repo, s, "church_policy", "endow")
	assert_eq(resent.size(), 1, "a re-send rides only for the missing province")
	assert_eq(int(resent[0]["order"]["decree_id"]), int(mine["order"]["decree_id"]), "the same decree")
	LawSystem.deliver(repo, s, resent[0])
	assert_almost_eq(_m("treasury") - gold, _share(-repo.bal("church_endow_cost"), pm), EPS,
		"the missing province pays its share once")
	assert_almost_eq(_m("church_opinion") - church, _share(repo.bal("church_endow_gain"), pm), EPS)
	# the re-sent courier, or the first, arriving where the value already is
	gold = _m("treasury")
	LawSystem.deliver(repo, s, resent[0])
	LawSystem.deliver(repo, s, mine)
	for c: Dictionary in sent:
		LawSystem.deliver(repo, s, c)
	assert_eq(_m("treasury"), gold, "a province that already has the value pays nothing")
