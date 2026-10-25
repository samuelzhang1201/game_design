extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var subject: Script

func before_each() -> void:
	repo = SuiteData.repo()
	if ResourceLoader.exists("res://scripts/engine/cluster_layout.gd"):
		subject = load("res://scripts/engine/cluster_layout.gd")

func _units(arms: Array) -> Array:
	var out: Array = []
	for i: int in arms.size():
		out.append({"unit": "u%02d" % i, "arm": arms[i], "controllable": true,
			"fit": 100, "footprint": Vector2i(10, 6)})
	return out

func _option(code: String, units: Array) -> Dictionary:
	for row: Dictionary in subject.options(repo, units):
		if row.formation == code:
			return row
	return {}

func test_eight_recipes_exact_missing_and_extra() -> void:
	assert_not_null(subject, "ClusterLayout pure query is implemented")
	if subject == null:
		return
	var cases: Dictionary = {
		"steady_line": ["infantry", "infantry", "archers"],
		"archer_infantry": ["infantry", "archers", "archers"],
		"double_envelopment": ["infantry", "cavalry", "cavalry"],
		"cavalry_charge": ["cavalry", "cavalry", "cavalry"],
		"depth_defence": ["infantry", "infantry", "archers"],
		"strong_wing": ["infantry", "infantry", "infantry"],
		"lure_counter": ["infantry", "archers", "cavalry"],
		"artillery_hold": ["infantry", "infantry", "artillery"]}
	assert_eq(subject.options(repo, []).size(), 8)
	for code: String in cases:
		var units: Array = _units(cases[code])
		assert_true(_option(code, units).eligible, code)
		units.append(_units(["artillery"])[0].merged({"unit": "extra"}, true))
		assert_true(_option(code, units).eligible, code + " extra")
		units.remove_at(0)
		assert_false(_option(code, units).eligible, code + " missing arm")
	assert_true(_option("cavalry_charge", _units(["cavalry", "cavalry", "infantry"])).eligible)
	assert_true(_option("depth_defence", _units(["infantry", "infantry", "artillery"])).eligible)
	var denied: Dictionary = _option("double_envelopment", _units(["infantry", "archers", "cavalry"]))
	assert_eq(denied.missing, {"cavalry": 1})
	assert_eq(denied.reason, "缺1支骑兵")

func test_only_distinct_controlled_fit_military_units_count() -> void:
	assert_not_null(subject)
	if subject == null:
		return
	var units: Array = _units(["infantry", "infantry"])
	for arm: String in ["king", "courier", "civilian"]:
		assert_false(_option("steady_line", units + _units([arm])).eligible)
	for patch: Dictionary in [{"fit": 0}, {"controllable": false}]:
		var third: Dictionary = _units(["cavalry"])[0].merged({"unit": "third"}, true).merged(patch, true)
		assert_false(_option("steady_line", units + [third]).eligible)
	assert_false(_option("steady_line", units + [units[0]]).eligible)
	var options: Array = subject.options(repo, _units(["infantry", "archers", "cavalry"]))
	var refused: bool = false
	for row: Dictionary in options:
		if not row.eligible:
			refused = true
		else:
			assert_false(refused, "eligible choices sort first")

func test_layout_is_stable_pure_and_uses_only_projection() -> void:
	assert_not_null(subject)
	if subject == null:
		return
	var units: Array = _units(["infantry", "infantry", "archers", "cavalry", "artillery", "infantry"])
	var original: Array = units.duplicate(true)
	var a: Dictionary = subject.layout(repo, "steady_line", units, Vector2i(100, 200), 0, "left")
	units.reverse()
	assert_eq(subject.layout(repo, "steady_line", units, Vector2i(100, 200), 0, "left"), a)
	units.reverse()
	assert_eq(units, original, "query never mutates projection")
	assert_eq(a.slots.size(), 6)
	assert_eq(a.roles.u00, "front")
	assert_eq(a.roles.u02, "ranged")
	for code: String in a.slots:
		if code != "u04":
			assert_ne(a.slots[code].y, a.slots.u04.y,
				"steady line artillery has an authored forward fire lane")
	assert_lt(a.slots.u02.x, a.slots.u00.x, "rear is negative forward depth; facing +x")
	for code: String in a.slots:
		for other: String in a.slots:
			if code != other:
				assert_ne(a.slots[code], a.slots[other])
	var before: Dictionary = subject.layout(repo, "steady_line", units, Vector2i.ZERO, 0, "")
	var hidden: Dictionary = {"unit": "hidden_enemy", "arm": "cavalry", "controllable": false, "fit": 1000}
	assert_eq(subject.layout(repo, "steady_line", units + [hidden], Vector2i.ZERO, 0, ""), before)
	hidden["fit"] = 1
	hidden["arm"] = "artillery"
	assert_eq(subject.layout(repo, "steady_line", units + [hidden], Vector2i.ZERO, 0, ""), before)
	for unit: Dictionary in units:
		unit["fit"] = 1
	assert_eq(subject.layout(repo, "steady_line", units, Vector2i.ZERO, 0, ""), before,
		"exact fit personnel never scales a fixed unit footprint")

func test_roles_for_all_eight_and_surplus() -> void:
	assert_not_null(subject)
	if subject == null:
		return
	var units: Array = _units(["infantry", "infantry", "infantry", "archers", "cavalry", "cavalry", "cavalry", "artillery"])
	var expected: Dictionary = {
		"steady_line": ["front", "ranged", "wing_guard", "fire_lane"],
		"archer_infantry": ["intercept", "ranged", "outer_guard", "rear_fire"],
		"double_envelopment": ["pin", "rear_fire", "envelop", "rear_fire"],
		"cavalry_charge": ["follow", "clear_charge_lane", "charge", "clear_charge_lane"],
		"depth_defence": ["front", "rear_fire", "wing_guard", "rear_fire"],
		"strong_wing": ["strong_front", "support", "strong_outer", "support"],
		"lure_counter": ["receive", "lure", "counter_flank", "rear_fire"],
		"artillery_hold": ["protect", "side_rear", "outer_guard", "battery"]}
	for code: String in expected:
		var view: Dictionary = subject.layout(repo, code, units, Vector2i.ZERO, 0, "left")
		assert_eq(view.slots.size(), units.size(), code)
		for index: int in [0, 3, 4, 7]:
			var role_index: int = [0, 3, 4, 7].find(index)
			assert_eq(view.roles[units[index].unit], expected[code][role_index], code)
	var depth: Dictionary = subject.layout(repo, "depth_defence", units, Vector2i.ZERO, 0, "")
	assert_eq(depth.roles.u01, "reserve")
	var wing: Dictionary = subject.layout(repo, "strong_wing", units, Vector2i.ZERO, 0, "left")
	assert_eq(wing.roles.u01, "strong_front")
	assert_eq(wing.roles.u02, "weak_rear")
	var envelope: Dictionary = subject.layout(repo, "double_envelopment", units, Vector2i.ZERO, 0, "")
	assert_lt(envelope.slots.u04.y, 0)
	assert_gt(envelope.slots.u05.y, 0)

func test_mirror_rotation_spacing_and_unplaced() -> void:
	assert_not_null(subject)
	if subject == null:
		return
	var units: Array = _units(["infantry", "infantry", "infantry", "archers", "cavalry"])
	var left: Dictionary = subject.layout(repo, "strong_wing", units, Vector2i.ZERO, 0, "left")
	var right: Dictionary = subject.layout(repo, "strong_wing", units, Vector2i.ZERO, 0, "right")
	assert_eq(subject.layout(repo, "strong_wing", units, Vector2i.ZERO, 0, ""), left, "tie defaults left")
	for code: String in left.slots:
		assert_eq(right.slots[code], Vector2i(left.slots[code].x, -left.slots[code].y))
	var turned: Dictionary = subject.layout(repo, "strong_wing", units, Vector2i.ZERO, 90, "left")
	assert_eq(turned.slots.u00, Vector2i(-left.slots.u00.y, left.slots.u00.x))
	# width 10, depth 6: pitch 20 x 12 leaves a full footprint as a corridor.
	assert_eq(left.slots.u00, Vector2i(0, -20))
	units[0].erase("footprint")
	var blocked: Dictionary = subject.layout(repo, "strong_wing", units, Vector2i.ZERO, 0, "left")
	assert_false(blocked.slots.has("u00"), "no invented footprint or effective attack position")
	assert_true(blocked.blocked.has("u00"))
	assert_false(blocked.reason.is_empty())
	var rejected: Dictionary = subject.layout(repo, "unknown", units, Vector2i.ZERO, 0, "")
	assert_eq(rejected.slots, {})

func test_authored_tables_and_large_surplus_have_no_duplicate_positions() -> void:
	assert_not_null(subject)
	if subject == null:
		return
	assert_eq(repo.cluster_formations.size(), 8)
	var arms: Array = []
	for i: int in 12:
		arms.append_array(["infantry", "archers", "cavalry", "artillery"])
	var units: Array = _units(arms)
	for code: String in repo.cluster_formations:
		var row: Dictionary = repo.cluster_formations[code]
		assert_false(String(row.label).is_empty())
		assert_false(String(row.behavior).is_empty())
		var priorities: Dictionary = {}
		for slot: Dictionary in repo.cluster_slots:
			if slot.formation != code:
				continue
			for field: String in ["lateral", "depth", "priority"]:
				assert_typeof(slot[field], TYPE_INT)
			var key: String = "%s:%d" % [slot.arm, int(slot.priority)]
			assert_false(priorities.has(key), "unique role priority: " + code + key)
			priorities[key] = true
		var view: Dictionary = subject.layout(repo, code, units, Vector2i.ZERO, 17, "")
		assert_eq(view.slots.size(), units.size())
		assert_eq(view.blocked, {})
		var seen: Dictionary = {}
		for point: Vector2i in view.slots.values():
			assert_false(seen.has(point), code + " unique surplus position")
			seen[point] = true
		assert_false(view.has("damage"), "query creates no combat benefit")
