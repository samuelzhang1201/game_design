extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The laws have one way in (spec 2026-10-08-laws-tab-design §2.3, §2.5, §7):
## `LawSystem.value`. The rate metrics (`tax_rate`, `tariff_rate`,
## `grain_ration`) only mirror the decree, so no script reads them as the
## rate in force; and no script reads `law_in_force` but the law layer and
## the save. A source scan of scripts/ and tools/.

## Files that may name the rate metrics: the law layer (it writes the
## mirror and falls back on it for a state with no law state, R8), the
## state (it seeds them) and the pack's seeding (WorldLedger.seed_metrics).
const RATE_FILES := ["res://scripts/engine/law_system.gd", "res://scripts/engine/law_effects.gd",
	"res://scripts/engine/game_state.gd", "res://scripts/engine/world_ledger.gd"]
## Files that may read law_in_force: the law layer and the save.
const FORCE_FILES := ["res://scripts/engine/law_system.gd", "res://scripts/engine/law_effects.gd",
	"res://scripts/engine/game_state.gd"]
## Functions elsewhere that may: path -> function names. The realm
## economy's cache signature hashes the laws in force (a courier's arrival
## turns it) and the rate metrics (a state with no law state reads them, R8);
## it reads no rate.
const FUNCTIONS := {"res://scripts/engine/realm_economy.gd": ["realm_signature"]}

const RATE_RX := '(metrics|\\bm)(\\.get\\(|\\[)"(tax_rate|tariff_rate|grain_ration)"|metrics\\.(tax_rate|tariff_rate|grain_ration)\\b'
const FORCE_RX := '\\blaw_in_force\\b'


func _scripts(dir: String) -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


## Every line of every script outside `allowed` matching `pattern`, as
## "path:line", the exempt functions' lines skipped. `scanned` receives the
## number of files read.
func _scan(pattern: String, allowed: Array, scanned: Array) -> Array:
	var rx := RegEx.create_from_string(pattern)
	var found: Array = []
	var files: Array = _scripts("res://scripts") + _scripts("res://tools")
	scanned.append(files.size())
	for path: String in files:
		if not path in allowed:
			found.append_array(_scan_text(path, FileAccess.get_file_as_string(path), rx, FUNCTIONS.get(path, [])))
	return found


## One script's matching lines ("path:line"), comment lines and the lines
## of the functions named in `exempt` skipped. A function runs from its
## `func` line to the next line that starts at the margin.
func _scan_text(path: String, text: String, rx: RegEx, exempt: Array) -> Array:
	var head_rx := RegEx.create_from_string("^(static\\s+)?func\\s+(\\w+)")
	var found: Array = []
	var in_func := ""
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		var head := head_rx.search(line)
		if head != null:
			in_func = head.get_string(2)
		elif line != "" and not line.begins_with("\t") and not line.begins_with(" ") and not line.begins_with("#"):
			in_func = ""
		if in_func in exempt or line.strip_edges().begins_with("#"):
			continue
		if rx.search(line) != null:
			found.append("%s:%d" % [path, i + 1])
	return found


func test_the_scan_reads_the_scripts() -> void:
	var n: Array = []
	_scan(RATE_RX, RATE_FILES, n)
	assert_gt(int(n[0]), 100, "the scan found the scripts")
	assert_true(FileAccess.file_exists("res://scripts/engine/realm_economy.gd"), "the exempt file exists")
	assert_true(FileAccess.get_file_as_string("res://scripts/engine/realm_economy.gd").contains("func realm_signature"),
		"and its exempt function")


func test_no_script_reads_the_rate_mirrors_as_the_rate_in_force() -> void:
	var n: Array = []
	var found := _scan(RATE_RX, RATE_FILES, n)
	assert_eq(found, [], "read the law in force (LawSystem.value), not the metric: %s" % [found])


func test_no_script_reads_law_in_force_but_the_law_layer() -> void:
	var n: Array = []
	var found := _scan(FORCE_RX, FORCE_FILES, n)
	assert_eq(found, [], "read a law through LawSystem.value: %s" % [found])


## The exemption is the function alone: the same read anywhere else in the
## file is caught.
func test_the_exemption_is_one_function() -> void:
	var rx := RegEx.create_from_string(RATE_RX)
	assert_not_null(rx.search('	var t := state.metrics.get("tax_rate", 0)'))
	assert_not_null(rx.search('	var t: float = m["tariff_rate"]'))
	assert_not_null(rx.search('	var t := state.metrics.grain_ration'))
	assert_null(rx.search('	var t := LawSystem.value(repo, state, "tax_rate", code)'))
	var text := "\n".join([
		"static func realm_signature(state: GameState) -> String:",
		"\treturn str(state.metrics.get(\"tax_rate\", 0))",
		"",
		"## a comment naming metrics[\"tax_rate\"]",
		"const X := 1",
		"static func income(state: GameState) -> int:",
		"\treturn int(state.metrics.get(\"tax_rate\", 0))",
	])
	assert_eq(_scan_text("f", text, rx, ["realm_signature"]), ["f:7"], "only the other function's read")
	assert_eq(_scan_text("f", text, rx, []), ["f:2", "f:7"], "both, with no exemption")


## A rate metric moves only with a decree (§2.5): an effect op
## `metric:tax_rate:…` would move the display mirror and no province's rate,
## so EventEffects refuses it — nothing applied, no result line (it pushes an
## error) — while any other metric still moves.
func test_a_metric_op_on_a_law_mirror_is_refused() -> void:
	var repo := SuiteData.repo()
	var s := SuiteData.campaign(repo, 42)
	for law: String in LawSystem.METRIC_OF:
		var metric := String(LawSystem.METRIC_OF[law])
		var before := float(s.metrics.get(metric, 0.0))
		var out := EventEffects.apply("metric:%s:1:a test" % metric, s, repo)
		assert_eq(float(s.metrics.get(metric, 0.0)), before, metric + " unmoved")
		assert_true(out.is_empty(), metric + ": no result line")
	var unrest := float(s.metrics.get("unrest", 0.0))
	assert_eq(EventEffects.apply("metric:unrest:1:a test", s, repo).size(), 1)
	assert_eq(float(s.metrics["unrest"]), unrest + 1.0, "another metric still moves")


## No data row's op names a rate mirror as a metric: the event choices (the
## chapter's too), the laws' cost ops and the order costs all speak the
## EventEffects grammar; a law changes by `law:<code>:<value>`.
func test_no_data_op_moves_a_law_mirror() -> void:
	var repo := SuiteData.repo()
	var sources: Array = []
	for c: Dictionary in repo.event_choices_all():
		sources.append(["%s/%s" % [c["event_id"], c["choice_id"]], String(c["effects"])])
	for law: String in repo.laws:
		sources.append(["laws.csv " + law, String(repo.laws[law].get("cost_ops", ""))])
	for code: String in repo.order_costs:
		sources.append(["order_costs.csv " + code, String(repo.order_costs[code].get("cost", ""))])
	assert_gt(sources.size(), 20, "the scan reads the tables")
	for src: Array in sources:
		for raw: String in String(src[1]).split(";", false):
			var p := raw.strip_edges().split(":")
			if p.size() > 1 and p[0] == "metric":
				assert_false(p[1] in LawSystem.METRIC_OF.values(),
					"%s moves the rate mirror %s: use law:<code>:<value>" % [src[0], p[1]])
