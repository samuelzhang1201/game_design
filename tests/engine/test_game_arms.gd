extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The game's own arms (data/army/game_arms.csv, spec 2026-11-18-axemen-arm-design): arms the Azgaar
## export does not define. tools/import_azgaar.gd appends each to the pack's military/unit_types.csv
## and gives it a column in regiments.csv and kingdoms.csv, 0 in every export regiment, so a
## re-import keeps them; an arm with opening regiments (game_arm_starts.csv) holds men only in those
## (test_army_starts.gd).

const COLUMNS := ["unit_code", "label", "type", "rural_rate", "urban_rate", "crew", "power", "separate"]


func test_game_arms_are_in_the_pack() -> void:
	var repo := SuiteData.repo()
	var rows := DataRepository.parse_csv("res://data/army/game_arms.csv", COLUMNS)
	assert_gt(rows.size(), 0, "game_arms.csv has rows")
	var types := repo.world_table("military", "unit_types")
	for row: Dictionary in rows:
		var code := String(row["unit_code"])
		assert_true(types.has(code), code + " is in the pack's unit_types")
		if not types.has(code):
			continue
		for column: String in COLUMNS:
			assert_eq(str(types[code].get(column, "")), str(row[column]), "%s %s" % [code, column])
		var starts := DataRepository.parse_csv(DataRepository.table_path("res://data", "game_arm_starts"), ["arm"])
		var opens := starts.any(func(r: Dictionary) -> bool: return String(r["arm"]) == code)
		for table: String in ["regiments", "kingdoms"]:
			for key: String in repo.world_table("military", table):
				var value: Variant = repo.world_table("military", table)[key].get(code, null)
				assert_true(value != null, "%s %s has a %s column" % [table, key, code])
				if value != null and not opens:
					assert_eq(int(float(value)), 0, "%s %s has a 0 %s" % [table, key, code])


func test_importer_reads_the_game_arms_or_fails() -> void:
	var importer: Script = load("res://tools/import_azgaar.gd")
	var defs: Dictionary = importer.call("game_arm_defs", "res://data")
	assert_false(defs.has("error"), str(defs))
	var axemen: Array = (defs.get("defs", []) as Array).filter(func(d: Dictionary) -> bool: return d["name"] == "axemen")
	assert_eq(axemen.size(), 1)
	if axemen.size() == 1:
		assert_eq(axemen[0], {"name": "axemen", "label": "Axemen", "type": "melee", "rural": 0.3, "urban": 0.05,
			"crew": 1, "power": 1.0, "separate": false})
	var heavy: Array = (defs.get("defs", []) as Array).filter(func(d: Dictionary) -> bool: return d["name"] == "heavy_infantry")
	assert_eq(heavy.size(), 1)
	if heavy.size() == 1:
		assert_eq(heavy[0], {"name": "heavy_infantry", "label": "Heavy infantry", "type": "melee", "rural": 0.05,
			"urban": 0.15, "crew": 1, "power": 1.0, "separate": false})
	var militia: Array = (defs.get("defs", []) as Array).filter(func(d: Dictionary) -> bool: return d["name"] == "militia")
	assert_eq(militia.size(), 1)
	if militia.size() == 1:
		assert_eq(militia[0], {"name": "militia", "label": "Militia", "type": "melee", "rural": 0.2,
			"urban": 0.15, "crew": 1, "power": 1.0, "separate": false})
	var missing: Dictionary = importer.call("game_arm_defs", "res://tests/fixtures/no_such_data")
	assert_true(missing.has("error"), "a missing game_arms table fails the import")
