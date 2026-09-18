extends GutTest
## NameForge and ManorNames: every manor gets a proper, unique name in its
## culture's style, the same one every time the pack is imported.

const BANK := ["Achern", "Aichhalden", "Aitern", "Albbruck", "Alpirsbach", "Altensteig",
	"Appenweier", "Baden", "Bernau", "Blumberg", "Bräunlingen", "Buchenbach", "Calw",
	"Dettingen", "Donaueschingen", "Ehingen", "Emmendingen", "Endingen", "Freiburg",
	"Gengenbach", "Haslach", "Herrenberg", "Horb", "Kappel", "Kehl", "Kirchzarten"]

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_the_chain_records_what_follows_each_pair() -> void:
	var model := NameForge.chain(PackedStringArray(["abc", "abd", "xy"]))
	assert_eq(model["starts"], ["ab", "ab", "xy"])
	assert_eq(model["next"]["ab"], ["c", "d"])
	assert_eq(model["next"]["bc"], [NameForge.END])
	assert_eq(model["next"]["xy"], [NameForge.END], "a two-letter name ends at once")

func test_forged_names_use_only_the_banks_letters_and_lengths() -> void:
	var model := NameForge.chain(PackedStringArray(BANK))
	var letters: Dictionary = {}
	for bank_name in BANK:
		for ch in bank_name.to_lower():
			letters[ch] = true
	var rng := _rng(7)
	for i in 40:
		var s := NameForge.forge(model, rng, 5, 12)
		assert_between(s.length(), 5, 12, s)
		assert_eq(s[0], s[0].to_upper(), "capitalised: " + s)
		for ch in s.to_lower():
			assert_true(letters.has(ch), "'%s' in %s comes from the bank" % [ch, s])

func test_the_same_seed_forges_the_same_name() -> void:
	var model := NameForge.chain(PackedStringArray(BANK))
	var a := NameForge.forge(model, _rng(99), 5, 12)
	var b := NameForge.forge(model, _rng(99), 5, 12)
	assert_eq(a, b)
	assert_ne(a, NameForge.forge(model, _rng(100), 5, 12), "another seed, another name (almost surely)")

func test_forge_unique_never_repeats_and_lengthens_when_the_bank_runs_dry() -> void:
	# A bank of two names can only make a handful of short names: past them
	# the forge joins two words rather than repeat one.
	var model := NameForge.chain(PackedStringArray(["Aba", "Abb"]))
	var taken: Dictionary = {}
	var rng := _rng(3)
	for i in 6:
		var s := NameForge.forge_unique(model, rng, 3, 4, taken)
		assert_false(taken.has(s.to_lower()), "no repeat: " + s)
		taken[s.to_lower()] = true
	var joined := 0
	for s: String in taken:
		if s.contains(" "):
			joined += 1
	assert_gt(joined, 0, "some names had to become two words")

func test_pretty_and_slug() -> void:
	assert_eq(NameForge.pretty("aldern wick"), "Aldern Wick")
	assert_eq(NameForge.pretty("saint-ives"), "Saint-Ives")
	assert_eq(NameForge.slug("Aldern Wick"), "aldern_wick")
	assert_eq(NameForge.slug("Saint-Ives' Cross"), "saint_ives_cross")

## The table: burg cells are named after their burg and taken first, every
## other cell is forged in its bank, labels and codes are unique, rows come
## back in cell order, and the same seed makes the same table.
func test_forge_table_names_every_cell_once() -> void:
	var banks := {0: {"names": PackedStringArray(BANK), "min": 5, "max": 10}}
	var specs: Array = []
	for id in range(1, 41):
		specs.append({"cell_id": id, "bank": 0, "burg_label": "", "province_code": "p1",
			"burg_code": "", "culture_code": "merton"})
	specs[4]["burg_label"] = "Shole"
	specs[4]["burg_code"] = "shole"
	specs[9]["burg_label"] = "Shole"  # a second town of the same name
	var rows := ManorNames.forge_table(42, specs, banks)
	assert_eq(rows.size(), 40)
	var labels: Dictionary = {}
	var codes: Dictionary = {}
	for i in rows.size():
		var row: Dictionary = rows[i]
		assert_eq(int(row["cell_id"]), i + 1, "in cell order")
		assert_false(labels.has(String(row["label"]).to_lower()), "unique label: " + String(row["label"]))
		assert_false(codes.has(String(row["manor_code"])), "unique code: " + String(row["manor_code"]))
		labels[String(row["label"]).to_lower()] = true
		codes[String(row["manor_code"])] = true
		assert_eq(String(row["province_code"]), "p1")
	assert_eq(String(rows[4]["label"]), "Shole Manor")
	assert_eq(String(rows[4]["manor_code"]), "shole_manor")
	assert_eq(String(rows[4]["burg_code"]), "shole")
	assert_eq(String(rows[9]["label"]), "Shole Manor 2", "the second Shole is told apart")
	var again := ManorNames.forge_table(42, specs, banks)
	for i in rows.size():
		assert_eq(String(again[i]["label"]), String(rows[i]["label"]), "the same seed, the same table")
	var other := ManorNames.forge_table(43, specs, banks)
	var differ := 0
	for i in rows.size():
		if String(other[i]["label"]) != String(rows[i]["label"]):
			differ += 1
	assert_gt(differ, 20, "another seed forges other names")
