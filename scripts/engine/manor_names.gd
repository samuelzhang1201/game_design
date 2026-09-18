class_name ManorNames
extends RefCounted
## The manor table's names (MANOR_SYSTEM.md §1): one proper, unique name per
## land cell. A cell with a burg is named after it ("Shole Manor"); every
## other cell gets a name forged in its culture's style by NameForge, seeded
## from the map seed and the cell id, so tools/import_azgaar.gd and
## tools/bake_manors.gd forge the same table from the same export. Pure.

## `specs`: [{cell_id, bank, burg_label, province_code, burg_code, culture_code}]
## in any order; `banks`: {bank key: {names: PackedStringArray, min, max}}.
## Returns rows sorted by cell id: [{cell_id, manor_code, label, ...}].
static func forge_table(map_seed: int, specs: Array, banks: Dictionary) -> Array:
	var ordered := specs.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["cell_id"]) < int(b["cell_id"]))
	var models: Dictionary = {}
	var taken: Dictionary = {}
	var rows: Array = []
	# Burg manors first: the town's name is spoken for before any forging.
	for spec: Dictionary in ordered:
		var burg := String(spec.get("burg_label", ""))
		if burg == "":
			continue
		var label := burg + " Manor"
		var n := 2
		while taken.has(label.to_lower()):
			label = "%s Manor %d" % [burg, n]
			n += 1
		taken[label.to_lower()] = true
		rows.append(_row(spec, label))
	for spec: Dictionary in ordered:
		if String(spec.get("burg_label", "")) != "":
			continue
		var key: Variant = spec.get("bank", 0)
		if not models.has(key):
			var bank: Dictionary = banks.get(key, {})
			models[key] = NameForge.chain(bank.get("names", PackedStringArray()))
		var bank_row: Dictionary = banks.get(key, {})
		var rng := RandomNumberGenerator.new()
		# Plain arithmetic, so the seed is the same on every platform.
		rng.seed = map_seed * 1000003 + int(spec["cell_id"])
		var label := NameForge.forge_unique(models[key], rng,
			int(bank_row.get("min", 5)), int(bank_row.get("max", 12)), taken)
		if label == "":
			label = "Manor %d" % int(spec["cell_id"])
		taken[label.to_lower()] = true
		rows.append(_row(spec, label))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["cell_id"]) < int(b["cell_id"]))
	_unique_codes(rows)
	return rows

static func _row(spec: Dictionary, label: String) -> Dictionary:
	return {"cell_id": int(spec["cell_id"]), "manor_code": NameForge.slug(label), "label": label,
		"province_code": String(spec.get("province_code", "")),
		"burg_code": String(spec.get("burg_code", "")),
		"culture_code": String(spec.get("culture_code", ""))}

## Two labels can slug alike ("Aldern-Wick" / "Aldern Wick"); the later one
## takes a numbered code, so a code always names one manor.
static func _unique_codes(rows: Array) -> void:
	var seen: Dictionary = {}
	for row: Dictionary in rows:
		var code := String(row["manor_code"])
		var n := 2
		while seen.has(code):
			code = "%s_%d" % [String(row["manor_code"]), n]
			n += 1
		row["manor_code"] = code
		seen[code] = true
