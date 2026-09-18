extends GutTest
## HouseArms (docs/superpowers/specs/2026-09-15-house-arms-design.md): every
## house wears the generated arms of its seat — its first province's capital
## town — and every kingdom its state's; the crown keeps its arms when
## character creation renames it. Families and codes come from the pack.

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func _royal_family() -> String:
	var capital := String(data.kingdoms[data.resolve_realm("player_realm")]["capital_burg"])
	var family := MapObjects.house_name_of(data, String(data.burgs[capital]["province_code"]))
	assert_eq(HouseArms.royal_family(data), family)
	return family

func test_every_house_resolves_arms_that_exist() -> void:
	for code: String in data.provinces:
		var family := MapObjects.house_name_of(data, code)
		var key := HouseArms.key_of_house(data, null, family)
		assert_ne(key, "", "House %s has a seat" % family)
		assert_true(ResourceLoader.exists(HouseArms.path_of(data, key)), "%s: %s is installed" % [family, key])

func test_every_kingdom_resolves_arms_that_exist() -> void:
	for code: String in data.kingdoms:
		assert_true(ResourceLoader.exists(HouseArms.path_of(data, HouseArms.key_of_kingdom(code))), code)
		assert_not_null(HouseArms.texture_of_kingdom(data, code), code)

## A family bound to several provinces is seated in the one with the lowest
## province_id; its arms are that province's capital town's.
func test_a_house_is_seated_in_its_first_province() -> void:
	var provinces_of: Dictionary = {}
	for code: String in data.house_bindings:
		var family := String(data.house_bindings[code])
		provinces_of[family] = provinces_of.get(family, []) + [code]
	var checked := 0
	for family: String in provinces_of:
		var codes: Array = provinces_of[family]
		if codes.size() < 2:
			continue
		codes.sort_custom(func(a: String, b: String) -> bool:
			return int(data.provinces[a]["province_id"]) < int(data.provinces[b]["province_id"]))
		assert_eq(HouseArms.seat_province(data, null, family), String(codes[0]), family)
		assert_eq(HouseArms.key_of_house(data, null, family),
			"seat_" + String(data.provinces[codes[0]]["capital_burg"]), family)
		checked += 1
	assert_gt(checked, 0, "the pack binds some family to more than one province")

func test_a_province_without_a_town_keys_its_arms_by_its_code() -> void:
	var found := false
	for code: String in data.provinces:
		if String(data.provinces[code]["capital_burg"]) == "":
			assert_eq(HouseArms.key_of_province(data, code), "province_" + code)
			found = true
	assert_true(found, "the pack has a province with no capital town")

func test_the_crown_keeps_its_arms_when_renamed() -> void:
	var royal := _royal_family()
	var s := GameState.new()
	s.player_setup = {"first_name": "Anne", "family_name": "Aurel", "house_was": royal}
	assert_eq(HouseArms.key_of_house(data, s, "Aurel"), HouseArms.key_of_house(data, null, royal))
	assert_ne(HouseArms.key_of_house(data, s, "Aurel"), "")

func test_a_family_with_no_province_has_no_arms() -> void:
	assert_eq(HouseArms.key_of_house(data, null, "Nobody-of-Nowhere"), "")
	assert_null(HouseArms.texture_of_house(data, null, "Nobody-of-Nowhere"))
	assert_null(HouseArms.texture_of_house(data, null, ""))

func test_a_texture_is_loaded_once() -> void:
	var royal := _royal_family()
	var a := HouseArms.texture_of_house(data, null, royal)
	assert_not_null(a)
	assert_same(HouseArms.texture_of_house(data, null, royal), a)
