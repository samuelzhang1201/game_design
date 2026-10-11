extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A decree's letters and its news (spec 2026-10-08-laws-tab-design §3 "News
## and letters"): the decree files a letter with its count of couriers at
## once; its last delivery, or its last courier's loss, files a second —
## "reached X of Y places in N days" — exactly once. The law letters keep a
## count of their own (missive_keep_law). The news bar says a decree ONCE as
## it is sent and ONCE when all have arrived, never courier by courier.

var repo: DataRepository
var s: GameState
var realm: String


func before_all() -> void:
	RoadGraph.forget()


func after_all() -> void:
	RoadGraph.forget()
	Weather.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	realm = repo.resolve_realm("player_realm")
	s.metrics["treasury"] = 5000.0
	s.missives = []
	Weather.forget()


## The law letters on the board, oldest first.
func _law_letters() -> Array:
	var out: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "law")
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


func _fact(m: Dictionary, key: String) -> Dictionary:
	for f: Dictionary in m["facts"]:
		if String(f["key"]) == key:
			return f
	return {}


## The reach letters (those with a `reached` fact).
func _reach_letters() -> Array:
	return _law_letters().filter(func(m: Dictionary) -> bool: return not _fact(m, "reached").is_empty())


## Ride every courier home; the events of every day.
func _ride_all() -> Array:
	var events: Array = []
	for i in int(repo.bal("courier_max_days")) + 2:
		if s.couriers.is_empty():
			break
		events.append_array(CourierSystem.ride_day(repo, s))
	return events


func test_a_decree_files_a_letter_with_its_courier_count() -> void:
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	assert_gt(sent.size(), 0)
	var letters := _law_letters()
	assert_eq(letters.size(), 1, "one letter, at once")
	var m: Dictionary = letters[0]
	assert_eq(String(m["column"]), "truth", "the crown's own decree: ground truth (owner 2026-10-10)")
	assert_eq(int(_fact(m, "couriers")["exact"]), sent.size(), "it counts the couriers")
	assert_string_contains(String(_fact(m, "decree")["text"]), "Tax rate")
	assert_string_contains(String(_fact(m, "decree")["text"]), "7")
	var home := MapManors.home_province(repo, s)
	assert_eq(String(m["subject"]["kind"]), "province")
	assert_eq(String(m["subject"]["code"]), home, "about the realm's home province")
	var at := LawSystem.province_px(repo, home)
	assert_eq(Vector2(float(m["subject"]["x"]), float(m["subject"]["y"])), Vector2(roundi(at.x), roundi(at.y)),
		"at its decree point")
	var last := 0
	for c: Dictionary in sent:
		last = maxi(last, CourierSystem.days_left(repo, s, c))
	assert_eq(int(_fact(m, "last_days")["exact"]), last, "and the longest ride")
	assert_true(_reach_letters().is_empty(), "nothing has arrived yet")


func test_the_last_delivery_files_the_reach_letter_once() -> void:
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	# ride day by day, the calendar turning after each day's end as
	# TickEngine.advance_day turns it
	var events: Array = []
	var rides := 0
	while not s.couriers.is_empty() and rides <= int(repo.bal("courier_max_days")):
		assert_lt(s.day, Calendar.DAYS_PER_TICK, "the ride ends inside the month")
		events.append_array(CourierSystem.ride_day(repo, s))
		rides += 1
		s.day += 1
	assert_true(s.couriers.is_empty(), "all home")
	var closing := events.filter(func(e: Dictionary) -> bool: return e.has("reach"))
	assert_eq(closing.size(), 1, "one event closes the decree")
	assert_eq(closing[0], events[events.size() - 1], "the last courier's")
	var reach := _reach_letters()
	assert_eq(reach.size(), 1, "one reach letter")
	var m: Dictionary = reach[0]
	assert_eq(int(_fact(m, "reached")["exact"]), sent.size())
	assert_eq(int(_fact(m, "total")["exact"]), sent.size())
	assert_eq(int(_fact(m, "days")["exact"]), rides,
		"the days from the decree's day to the last arrival's, both counted")
	assert_true(_fact(m, "not_reached").is_empty(), "nowhere left out")
	assert_true(String(m["title"]).begins_with("Decree in force"), String(m["title"]))
	# more days ride nothing and file nothing
	for i in 3:
		CourierSystem.ride_day(repo, s)
	assert_eq(_reach_letters().size(), 1, "exactly once")


func test_a_lost_last_courier_files_the_reach_letter_with_the_short_count() -> void:
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	assert_gt(sent.size(), 1, "a realm of more than one province")
	# every courier but the first has delivered; the first's fuse runs out
	var last: Dictionary = sent[0]
	for c: Dictionary in sent.slice(1):
		assert_eq(String(LawSystem.deliver(repo, s, c)["type"]), "delivered")
	s.couriers = [last]
	last["days"] = int(repo.bal("courier_max_days"))
	var events := CourierSystem.ride_day(repo, s)
	assert_eq(events.size(), 1)
	assert_eq(String(events[0]["type"]), "fuse")
	assert_eq(events[0]["reach"]["reached"], sent.size() - 1)
	assert_eq(events[0]["reach"]["total"], sent.size())
	var reach := _reach_letters()
	assert_eq(reach.size(), 1)
	var m: Dictionary = reach[0]
	assert_eq(int(_fact(m, "reached")["exact"]), sent.size() - 1, "the short count")
	assert_eq(int(_fact(m, "total")["exact"]), sent.size())
	assert_string_contains(String(m["title"]), "%d of %d" % [sent.size() - 1, sent.size()])
	assert_string_contains(String(_fact(m, "not_reached")["text"]),
		LawSystem.place_label(repo, s, String(last["target"])), "names the place left out")
	var lines := CourierSystem.news(repo, events)
	assert_eq(lines.size(), 2, "the lost courier once, the decree's reach once: %s" % [lines])
	assert_string_contains(String(lines[1]), "reached %d of %d places" % [sent.size() - 1, sent.size()])


func test_law_letters_are_kept_apart_from_the_rest() -> void:
	var subj := MissiveLog.subject("province", "x", -1, Vector2.ZERO)
	for i in 5:
		MissiveLog.add(repo, s, MissiveLog.make("receipt", "credible", 1, subj, "r%d" % i, []))
	for i in 3:
		MissiveLog.add(repo, s, MissiveLog.make("supply", "credible", 1, subj, "s%d" % i, []))
	var first := -1
	for i in 21:
		var id := MissiveLog.add(repo, s, MissiveLog.make("law", "credible", 1, subj, "l%d" % i, []))
		if first < 0:
			first = id
	assert_eq(int(repo.bal("missive_keep_law")), 20)
	assert_eq(_law_letters().size(), 20, "21 law letters keep 20")
	assert_true(MissiveLog.find(s, first).is_empty(), "the oldest law letter left")
	assert_eq(s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "receipt").size(), 5,
		"the receipts untouched")
	assert_eq(s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply").size(), 3,
		"the supply letters untouched")
	assert_eq(MissiveLog.keep_group("law"), "law")
	assert_eq(MissiveLog.keep_group("supply_month"), "supply")
	assert_eq(MissiveLog.keep_group("battle"), "battle")
	assert_eq(MissiveLog.keep_group("receipt"), "receipt")
	assert_eq(MissiveLog.keep_group("monthly"), "")


func test_the_news_bar_is_told_once_when_all_have_arrived() -> void:
	var sent := LawSystem.decree(repo, s, "tax_rate", "7")
	assert_gt(sent.size(), 1)
	var leaving := CourierSystem.setting_out(repo, s, 0)
	assert_eq(leaving.size(), sent.size(), "every courier sets out")
	var said := CourierSystem.news(repo, leaving)
	assert_eq(said, ["The decree on Tax rate is sent: %d couriers." % sent.size()], "ONE line as it is sent")
	var events := _ride_all()
	var lines := CourierSystem.news(repo, events)
	assert_eq(lines.size(), 1, "ONE line when all have arrived: %s" % [lines])
	var days := int(events.filter(func(e: Dictionary) -> bool: return e.has("reach"))[0]["reach"]["days"])
	assert_eq(String(lines[0]), "The decree on Tax rate is in force everywhere: %d of %d places in %d day%s." % [
		sent.size(), sent.size(), days, "" if days == 1 else "s"])
	# an ordinary courier is still said one by one beside a decree's
	var other := {"type": "delivered", "courier": 999, "regiment": "x", "weather": "", "town": ""}
	assert_eq(CourierSystem.news(repo, [other]), [CourierSystem.headline(repo, other)])


## A decree overtaken while its couriers ride (here the newer decree's
## couriers are home first): every older courier arrives set aside, closes
## nothing and files no reach letter, and the news says them as ONE counted
## line, never a line a courier.
func test_a_stale_courier_of_an_older_decree_closes_nothing() -> void:
	var old := LawSystem.decree(repo, s, "tax_rate", "7")
	s.law_cooldown.erase("tax_rate")
	var newer := LawSystem.decree(repo, s, "tax_rate", "4")
	assert_eq(newer.size(), old.size())
	assert_gt(old.size(), 1, "a realm of more than one province")
	# the newer decree's couriers are delivered first, where they rode
	var newer_id := int(CourierSystem.first_order(newer[0])["decree_id"])
	for c: Dictionary in newer:
		assert_eq(String(LawSystem.deliver(repo, s, c)["type"]), "delivered")
	s.couriers = s.couriers.filter(func(c: Dictionary) -> bool: return int(CourierSystem.first_order(c)["decree_id"]) != newer_id)
	assert_eq(s.couriers.size(), old.size(), "the older decree's couriers still ride")
	# the ride's own events (a weather delay, "slow", is said by no one here)
	var events := _ride_all().filter(func(e: Dictionary) -> bool: return String(e["type"]) != "slow")
	assert_eq(events.size(), old.size(), "every older courier arrives")
	for e: Dictionary in events:
		assert_eq(String(e["type"]), "stale", "set aside: a newer decree stands there")
		assert_false(e.has("reach"), "a courier of an older decree closes nothing")
	assert_true(_reach_letters().is_empty(), "and files no reach letter")
	for code: String in MapOwnership.provinces_of(repo, s, realm):
		assert_eq(LawSystem.value(repo, s, "tax_rate", code), "4", code + " keeps the newer decree")
	var lines := CourierSystem.news(repo, events)
	assert_eq(lines, ["%d couriers of the decree on Tax rate were set aside." % old.size()],
		"ONE counted line for the batch")


## An event's change of law over a decree still riding (ev_07's tariff step,
## LawSystem.impose): the riding couriers all arrive set aside, and a day's
## news says them as one line at most, counted when more than one.
func test_an_event_over_a_riding_decree_is_said_once_a_day() -> void:
	var was := int(LawSystem.decreed(repo, s, "tariff_rate"))
	var sent := LawSystem.decree(repo, s, "tariff_rate", str(was + 1 if was < 10 else was - 1))
	assert_gt(sent.size(), 1)
	EventEffects.apply("law:tariff_rate:+1", s, repo, "test")
	var label := String(LawSystem.def(repo, "tariff_rate")["label"])
	var stale := 0
	var crowded := false
	for i in int(repo.bal("courier_max_days")) + 2:
		if s.couriers.is_empty():
			break
		var day := CourierSystem.ride_day(repo, s)
		var set_aside := day.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "stale")
		stale += set_aside.size()
		var lines := CourierSystem.news(repo, day)
		assert_lte(lines.size(), 1, "one line a day at most: %s" % [lines])
		if set_aside.size() > 1:
			crowded = true
			assert_eq(lines, ["%d couriers of the decree on %s were set aside." % [set_aside.size(), label]])
	assert_eq(stale, sent.size(), "every riding courier is set aside")
	assert_true(crowded, "some day brought more than one home")
	# one courier alone is still said by name (headline)
	var one := CourierSystem._event("stale", sent[0])
	assert_eq(CourierSystem.news(repo, [one]), [CourierSystem.headline(repo, one)])
	# a batch of set-aside and lost couriers of one decree: one line
	var lost := CourierSystem._event("fuse", sent[1])
	assert_eq(CourierSystem.news(repo, [one, lost]),
		["2 couriers of the decree on %s were set aside or lost." % label])
