extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The game's own arms (data/army/game_arms.csv, spec 2026-11-18-axemen-arm-design): arms the Azgaar
## export does not define. tools/import_azgaar.gd appends each to the pack's military/unit_types.csv
## and gives it a 0 column in regiments.csv and kingdoms.csv, so a re-import keeps them.

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
		for table: String in ["regiments", "kingdoms"]:
			for key: String in repo.world_table("military", table):
				var value: Variant = repo.world_table("military", table)[key].get(code, null)
				assert_true(value != null and int(float(value)) == 0, "%s %s has a 0 %s" % [table, key, code])
