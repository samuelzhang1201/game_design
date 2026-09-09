# World Database, Order Costs, and Two-Part Orders — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import the Azgaar export's economic, military, political, and social data into five domain folders under the map pack; give the engine a schema-clamped world ledger the model's structured output can move; guarantee every order carries a cost; make a typed order return one narrative and one impact block that agree; and draw province seams on the map as light dashed lines.

**Architecture:** `tools/import_azgaar.gd` writes `data/maps/<id>/<domain>/*.csv`; `DataRepository.load_map` loads them into `world_tables[domain][area][code]`. `WorldLedger` (engine-pure) reads and writes fields by path over `GameState.world` overrides, clamped by `data/world_schema.csv`. `OrderCosts` enforces the cost rule inside `ActionSystem.execute` and for pure-impact orders. One LLM call (`Voicer.order`) returns `{narrative, impacts}`; `ResponseValidator.parse_order` validates, `OrderPipeline.apply_order` applies, and the screens print the narrative and the ledger lines. `MapOwnership.seams_of` feeds `WorldMapView`'s province view.

**Tech Stack:** Godot 4.x, typed GDScript, GUT. `./run_tests.sh` runs the whole suite headless.

**Spec:** `docs/superpowers/specs/2026-09-09-world-database-and-order-impacts-design.md`

## Global Constraints

- Typed GDScript everywhere. `snake_case` files/functions/vars, `PascalCase` classes, past-tense signals.
- Engine classes (`scripts/engine/`) are `RefCounted`, no Node/scene dependencies, no `Time.get_*`, no unseeded RNG. UI reads `Game.data`/`Game.state`, never mutates state directly.
- Design values live in CSVs, never in script constants.
- Every opinion, attribute, relationship, or world change carries a reason string at creation time.
- `data/maps/<id>/**/*.csv` and `assets/maps/<id>/*.png` are **generated** by `tools/import_azgaar.gd`; never hand-edit them. Re-run the importer after changing it: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/import_azgaar.gd` (exit 134 on macOS is normal).
- Godot registers a new `class_name` only after an import pass: after creating any `.gd` with `class_name`, run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` once (exit 134 is normal) before running GUT.
- One-selector test run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gselect=<substring>`; grep the output for `FAILED`/`Passing`.
- `./run_tests.sh` must end with `All tests passed!`, `Errors 2`, and exit 0 before every commit.
- Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_019HggsFraqfeKGW6RHNys5E`.
- Tests never name a kingdom, town, or province literally; derive them from `repo.resolve_realm("player_realm")` and the pack rows.
- Beria facts (from the export, for sanity while working, not for test literals): the player's realm binds to `kelvarn`, capital `walbover`; Kelvarn's economy row has treasury 717.72, poll_tax 0.14, sales_tax 0.05; its military totals are infantry 2677, archers 2173, cavalry 4285, artillery 48, fleet 7 across 7 regiments; the export has 7 kingdoms, 203 provinces, 686 burgs, 71 goods, 27 markets, 5 unit types, 4 cultures, 6 religions, 13 zones.

## File Structure

| File | Responsibility |
|---|---|
| `tools/import_azgaar.gd` (modify) | Domain folders, `.gdignore`, the new tables, extended columns |
| `data/maps/beria/<domain>/*.csv` (generated) | Starting values |
| `scripts/engine/data_repository.gd` (modify) | `world_tables`, `world_schema`, `metric_polarity`, `order_costs` |
| `data/world_schema.csv`, `data/metric_polarity.csv`, `data/order_costs.csv` (create) | Writable fields and caps; metric polarity; per-action costs |
| `data/balance.csv` (modify) | Seeding factors, prompt limits, province-view drawing values |
| `scripts/engine/world_ledger.gd` (create) | Path resolution, schema match, read, clamped write, log, prompt catalog, seeding |
| `scripts/engine/game_state.gd` (modify) | `world`, `world_log`, save version 3, seeding call |
| `scripts/engine/character.gd` (modify) | `change_attribute`, `attribute_log` |
| `scripts/engine/event_effects.gd` (modify) | `world:` and `attribute:` ops; optional reasons on `gold:`/`metric:` |
| `scripts/engine/order_costs.gd` (create) | Cost detection and charging |
| `scripts/engine/action_system.gd` (modify) | Opinion snapshot, cost guarantee, affordability incl. cost gold |
| `scripts/llm/openai_client.gd` (modify) | `model_order` tier |
| `scripts/llm/prompt_builder.gd` (modify) | `order_prompts` |
| `scripts/llm/response_validator.gd` (modify) | `parse_order` |
| `scripts/llm/voicer.gd` (modify) | `order` |
| `scripts/engine/order_pipeline.gd` (create) | Apply one order end to end; ledger lines |
| `scripts/ui/game.gd` (modify) | Speaker pre-selection, single call, result shape |
| `scripts/ui/court_screen.gd`, `scripts/ui/conversation_scene.gd`, `scripts/ui/info_screen.gd` (modify) | Print ledger lines; ledger rows in tabs |
| `scripts/engine/map_ownership.gd` (modify) | `seams_of` |
| `scripts/ui/world_map_view.gd` (modify) | Province view toggle, chip, key, drawing |
| `tests/engine/test_world_tables.gd`, `test_world_ledger.gd`, `test_order_costs.gd`, `test_order_pipeline.gd` (create); `test_map_data.gd`, `test_game_state.gd`, `test_event_effects.gd`, `test_action_system.gd`, `test_map_ownership.gd`, `tests/llm/test_llm_config.gd`, `test_prompt_builder.gd`, `test_response_validator.gd`, `test_voicer_fallback.gd`, `tests/ui/test_court_screen.gd`, `test_conversation_scene.gd`, `test_world_map_view.gd` (modify) | Tests |
| `CLAUDE.md`, `.env.example`, `PRD.md` (modify) | Layout, invariant amendment, config key |

---

### Task 1: Domain folders — importer, moves, loader, tests

**Files:**
- Modify: `tools/import_azgaar.gd`
- Move: `data/maps/beria/{biomes,rivers,markers,routes}.csv` → `geography/`; `{kingdoms,provinces,burgs,borders,province_borders}.csv` → `political/`
- Delete: the moved files' `.csv.import` and `*.translation` sidecars
- Modify: `scripts/engine/data_repository.gd`
- Test: `tests/engine/test_world_tables.gd` (create)
- Modify: `CLAUDE.md`

**Interfaces:**
- Produces: `DataRepository.world_tables: Dictionary` — `world_tables[domain][area][code] -> row: Dictionary`. Domains: `geography` (areas `biomes` int-keyed, `rivers`, `markers`, `routes`), `political` (`kingdoms`, `provinces`, `burgs`, `diplomacy` keyed `"<kingdom_code>><other_code>"`, `campaigns` keyed `"<kingdom_code>:<label>"`), `economy` (`kingdoms`, `provinces`, `burgs`, `goods`, `markets` keyed by `market_id` string, `market_goods` keyed `"<market_id>:<good_code>"`, `production` keyed `"<burg_code>:<good_code>"`), `military` (`kingdoms`, `regiments`, `unit_types`), `society` (`cultures`, `religions`, `zones`). The existing named fields (`kingdoms`, `provinces`, `burgs`, `routes`, `rivers`, `markers`, `biomes`) are the same Dictionary objects.
- Produces: `DataRepository.world_table(domain: String, area: String) -> Dictionary` (`{}` when absent) and `world_row(domain, area, code) -> Dictionary`.

- [ ] **Step 1: Write the failing tests**

`tests/engine/test_world_tables.gd`:

```gdscript
extends GutTest
## The Azgaar export's economic, military, political, and social data, imported
## into domain folders under the pack (spec 2026-09-09 §1). Nothing here names
## a kingdom: everything hangs off the realm the pack binds player_realm to.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	assert_not_null(repo, DataRepository.last_error)

func _player() -> String:
	return repo.resolve_realm("player_realm")

func test_every_domain_table_loads() -> void:
	for spec in [["geography", "biomes"], ["geography", "rivers"], ["geography", "markers"],
			["geography", "routes"], ["political", "kingdoms"], ["political", "provinces"],
			["political", "burgs"], ["political", "diplomacy"], ["political", "campaigns"],
			["economy", "kingdoms"], ["economy", "provinces"], ["economy", "burgs"],
			["economy", "goods"], ["economy", "markets"], ["economy", "market_goods"],
			["economy", "production"], ["military", "kingdoms"], ["military", "regiments"],
			["military", "unit_types"], ["society", "cultures"], ["society", "religions"],
			["society", "zones"]]:
		assert_gt(repo.world_table(spec[0], spec[1]).size(), 0,
			"%s/%s.csv loaded" % [spec[0], spec[1]])

## The old named fields and the domain store are one set of rows, not copies.
func test_named_tables_share_rows_with_world_tables() -> void:
	assert_true(is_same(repo.world_table("political", "kingdoms"), repo.kingdoms))
	assert_true(is_same(repo.world_table("political", "provinces"), repo.provinces))
	assert_true(is_same(repo.world_table("political", "burgs"), repo.burgs))
	assert_true(is_same(repo.world_table("geography", "routes"), repo.routes))
	assert_true(is_same(repo.world_table("geography", "rivers"), repo.rivers))
	assert_true(is_same(repo.world_table("geography", "markers"), repo.markers))
	assert_true(is_same(repo.world_table("geography", "biomes"), repo.biomes))

func test_kingdoms_carry_form_culture_and_religion() -> void:
	var k: Dictionary = repo.kingdoms[_player()]
	assert_ne(String(k["form"]), "", "government form")
	assert_ne(String(k["form_name"]), "", "form name")
	assert_true(repo.world_table("society", "cultures").has(String(k["culture_code"])),
		"culture resolves")
	assert_true(repo.world_table("society", "religions").has(String(k["religion_code"])),
		"majority religion resolves")

func test_economy_rows_reference_real_places() -> void:
	for code: String in repo.world_table("economy", "kingdoms"):
		assert_true(repo.kingdoms.has(code), "economy kingdom %s" % code)
	for code: String in repo.world_table("economy", "provinces"):
		assert_true(repo.provinces.has(code), "economy province %s" % code)
	for code: String in repo.world_table("economy", "burgs"):
		assert_true(repo.burgs.has(code), "economy burg %s" % code)
	var goods := repo.world_table("economy", "goods")
	for key: String in repo.world_table("economy", "production"):
		var row: Dictionary = repo.world_table("economy", "production")[key]
		assert_true(repo.burgs.has(String(row["burg_code"])), "production burg %s" % key)
		assert_true(goods.has(String(row["good_code"])), "production good %s" % key)
	for key: String in repo.world_table("economy", "market_goods"):
		var row: Dictionary = repo.world_table("economy", "market_goods")[key]
		assert_true(repo.world_table("economy", "markets").has(String(row["market_id"])),
			"market %s" % key)
		assert_true(goods.has(String(row["good_code"])), "market good %s" % key)

func test_player_realm_has_economy_and_military_rows() -> void:
	var e: Dictionary = repo.world_row("economy", "kingdoms", _player())
	assert_false(e.is_empty(), "economy row")
	assert_gt(float(e["treasury"]), 0.0)
	assert_gt(float(e["poll_tax"]), 0.0)
	assert_gt(int(e["rural_population"]), 0)
	var m: Dictionary = repo.world_row("military", "kingdoms", _player())
	assert_false(m.is_empty(), "military row")
	assert_gt(int(m["regiments"]), 0)
	assert_gt(float(m["strength"]), 0.0)

func test_military_totals_equal_the_sum_of_regiments() -> void:
	var units := repo.world_table("military", "unit_types").keys()
	assert_gt(units.size(), 0, "unit types imported")
	for code: String in repo.world_table("military", "kingdoms"):
		var row: Dictionary = repo.world_row("military", "kingdoms", code)
		var sums: Dictionary = {}
		var n := 0
		for rc: String in repo.world_table("military", "regiments"):
			var r: Dictionary = repo.world_row("military", "regiments", rc)
			if String(r["kingdom_code"]) != code:
				continue
			n += 1
			for u: String in units:
				sums[u] = int(sums.get(u, 0)) + int(r[u])
		assert_eq(int(row["regiments"]), n, "%s regiment count" % code)
		for u: String in units:
			assert_eq(int(row[u]), int(sums.get(u, 0)), "%s %s" % [code, u])

func test_diplomacy_lists_every_ordered_pair_once() -> void:
	var dip := repo.world_table("political", "diplomacy")
	var n := repo.kingdoms.size()
	assert_eq(dip.size(), n * (n - 1), "every ordered pair of kingdoms")
	for key: String in dip:
		var row: Dictionary = dip[key]
		assert_true(repo.kingdoms.has(String(row["kingdom_code"])))
		assert_true(repo.kingdoms.has(String(row["other_code"])))
		assert_ne(String(row["kingdom_code"]), String(row["other_code"]))
		assert_ne(String(row["stance"]), "")

func test_zones_name_real_provinces_and_kingdoms() -> void:
	for code: String in repo.world_table("society", "zones"):
		var z: Dictionary = repo.world_row("society", "zones", code)
		for p: String in String(z["province_codes"]).split("|", false):
			assert_true(repo.provinces.has(p), "zone %s province %s" % [code, p])
		for k: String in String(z["kingdom_codes"]).split("|", false):
			assert_true(repo.kingdoms.has(k), "zone %s kingdom %s" % [code, k])

func test_burgs_carry_group_and_culture() -> void:
	var realm: Dictionary = repo.kingdoms[_player()]
	var k: Dictionary = repo.burgs[String(realm["capital_burg"])]
	assert_eq(String(k["group"]), "capital")
	assert_true(repo.world_table("society", "cultures").has(String(k["culture_code"])))

func test_absent_table_reads_as_empty() -> void:
	assert_eq(repo.world_table("economy", "no_such_area"), {})
	assert_eq(repo.world_row("economy", "kingdoms", "no_such_kingdom"), {})
```

- [ ] **Step 2: Run the test to verify it fails**

Run the one-selector command with `-gselect=test_world_tables`. Expected: parse error / failures on `world_table` not found.

- [ ] **Step 3: Move the existing generated files and drop their sidecars**

```bash
cd data/maps/beria
mkdir -p geography political economy military society
for f in biomes rivers markers routes; do git mv $f.csv geography/$f.csv; done
for f in kingdoms provinces burgs borders province_borders; do git mv $f.csv political/$f.csv; done
git rm -q --cached *.csv.import *.translation 2>/dev/null; rm -f *.csv.import *.translation
# map_info.csv and realm_bindings.csv stay at the root with their sidecars
git checkout -- map_info.csv.import realm_bindings.csv.import map_info.value.translation realm_bindings.kingdom.translation realm_bindings.notes.translation
for d in geography political economy military society; do touch $d/.gdignore; done
```

(Only the moved tables lose their sidecars; the root files keep theirs.)

- [ ] **Step 4: Importer — domain folders and the new tables**

In `tools/import_azgaar.gd`, add near the constants:

```gdscript
## Pack tables are grouped by domain (spec 2026-09-09 §1.1). Each folder carries
## a .gdignore so Godot does not import game tables as translations; FileAccess
## reads them regardless. An export preset must include data/** explicitly.
const DOMAINS: Array[String] = ["geography", "political", "economy", "military", "society"]

func _ensure_domains(out_data: String) -> void:
	for d in DOMAINS:
		var dir := out_data + "/" + d
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		if not FileAccess.file_exists(dir + "/.gdignore"):
			_write_text(dir + "/.gdignore", "")

## Majority religion of a state's cells by rural population; ties go to the
## lower religion id so output is stable.
func _majority_religion(cells: Array, sid: int) -> int:
	var pop: Dictionary = {}
	for c: Dictionary in cells:
		if int(c.get("state", 0)) != sid:
			continue
		var rid := int(c.get("religion", 0))
		pop[rid] = float(pop.get(rid, 0.0)) + float(c.get("pop", 0))
	var best := 0
	var best_pop := -1.0
	var ids := pop.keys()
	ids.sort()
	for rid in ids:
		if float(pop[rid]) > best_pop:
			best_pop = float(pop[rid])
			best = int(rid)
	return best
```

Call `_ensure_domains(out_data)` right after the two `make_dir_recursive_absolute` calls in `_run`. Change the existing output paths: `kingdoms.csv`, `provinces.csv`, `burgs.csv`, `borders.csv`, `province_borders.csv` → `out_data + "/political/..."`; `routes.csv`, `rivers.csv`, `markers.csv`, `biomes.csv` → `out_data + "/geography/..."`. `map_info.csv` stays at the root.

Extend the kingdoms header and row (after `center_y`): `"form", "form_name", "full_name", "culture_code", "religion_code"` with values `String(s.get("form", ""))`, `String(s.get("formName", ""))`, `String(s.get("fullName", ""))`, `String(culture_code.get(int(s.get("culture", 0)), ""))`, `String(religion_code.get(_majority_religion(cells, int(s["i"])), ""))`. Extend provinces with `"form_name", "full_name", "color"` from `formName`, `fullName`, `color`. Extend burgs with `"group", "culture_code"` from `group` and `culture`.

Before `# --- kingdoms.csv` add the code tables:

```gdscript
	# --- codes for cultures, religions, goods ---------------------------
	var culture_code: Dictionary = {}
	var culture_slugs: Dictionary = {}
	for cu in _active(pack.get("cultures", [])):
		culture_code[int(cu["i"])] = _take_slug(culture_slugs, String(cu["name"]))
	var religion_code: Dictionary = {}
	var religion_slugs: Dictionary = {}
	for rl in _active(pack.get("religions", [])):
		religion_code[int(rl["i"])] = _take_slug(religion_slugs, String(rl["name"]))
	var good_code: Dictionary = {}
	var good_slugs: Dictionary = {}
	for g in _active(pack.get("goods", [])):
		good_code[int(g["i"])] = _take_slug(good_slugs, String(g["name"]))
	var unit_names: Array[String] = []
	for u in ((world["settings"] as Dictionary).get("options", {}) as Dictionary).get("military", []):
		if u is Dictionary:
			unit_names.append(String(u["name"]))
```

After `# --- province_borders.csv` (before routes) add the domain tables:

```gdscript
	# --- political/diplomacy.csv, political/campaigns.csv ----------------
	out = _csv_line(["kingdom_code", "other_code", "stance"])
	for s in states:
		var dip: Array = s.get("diplomacy", [])
		for j in dip.size():
			if j == int(s["i"]) or not state_code.has(j) or not (dip[j] is String):
				continue
			out += _csv_line([String(state_code[int(s["i"])]), String(state_code[j]), String(dip[j])])
	if not _write_text(out_data + "/political/diplomacy.csv", out):
		return 1
	out = _csv_line(["kingdom_code", "label", "start_year", "end_year", "attacker_code", "defender_code"])
	for s in states:
		for cp in (s.get("campaigns", []) as Array):
			if not cp is Dictionary:
				continue
			out += _csv_line([String(state_code[int(s["i"])]), String(cp.get("name", "")),
				str(int(cp.get("start", 0))), str(int(cp.get("end", 0))),
				String(state_code.get(int(cp.get("attacker", 0)), "")),
				String(state_code.get(int(cp.get("defender", 0)), ""))])
	if not _write_text(out_data + "/political/campaigns.csv", out):
		return 1

	# --- economy/* --------------------------------------------------------
	out = _csv_line(["kingdom_code", "treasury", "sales_tax", "poll_tax", "urban_population", "rural_population"])
	for s in states:
		out += _csv_line([String(state_code[int(s["i"])]), _num2(float(s.get("treasury", 0))),
			_num2(float(s.get("salesTax", 0))), _num2(float(s.get("pollTax", 0))),
			str(int(round(float(s.get("urban", 0)) * rate))),
			str(int(round(float(s.get("rural", 0)) * rate)))])
	if not _write_text(out_data + "/economy/kingdoms.csv", out):
		return 1
	out = _csv_line(["province_code", "urban_population", "rural_population"])
	for p in provinces:
		out += _csv_line([String(prov_code[int(p["i"])]),
			str(int(round(float(p.get("urban", 0)) * rate))),
			str(int(round(float(p.get("rural", 0)) * rate)))])
	if not _write_text(out_data + "/economy/provinces.csv", out):
		return 1
	out = _csv_line(["burg_code", "treasury", "product", "market_id"])
	var production := _csv_line(["burg_code", "good_code", "units"])
	for b in burgs:
		out += _csv_line([String(burg_code[int(b["i"])]), _num2(float(b.get("treasury", 0))),
			_num2(float(b.get("product", 0))), str(int(b.get("market", 0)))])
		for pe in (b.get("production", []) as Array):
			if pe is Dictionary and pe.has("goodId") and good_code.has(int(pe["goodId"])):
				production += _csv_line([String(burg_code[int(b["i"])]),
					String(good_code[int(pe["goodId"])]), _num2(float(pe.get("units", 0)))])
	if not _write_text(out_data + "/economy/burgs.csv", out):
		return 1
	if not _write_text(out_data + "/economy/production.csv", production):
		return 1
	out = _csv_line(["good_code", "good_id", "label", "value", "tags", "unit"])
	for g in _active(pack.get("goods", [])):
		var tags: Array[String] = []
		for t in (g.get("tags", []) as Array):
			tags.append(String(t))
		out += _csv_line([String(good_code[int(g["i"])]), str(int(g["i"])), String(g["name"]),
			_num2(float(g.get("value", 0))), "|".join(tags), String(g.get("unit", ""))])
	if not _write_text(out_data + "/economy/goods.csv", out):
		return 1
	out = _csv_line(["market_id", "center_burg"])
	var market_goods := _csv_line(["market_id", "good_code", "stock", "price"])
	for mk in _active(pack.get("markets", [])):
		out += _csv_line([str(int(mk["i"])), String(burg_code.get(int(mk.get("centerBurgId", 0)), ""))])
		var goods: Dictionary = mk.get("goods", {})
		var gids: Array = []
		for k in goods:
			gids.append(int(k))
		gids.sort()
		for gid in gids:
			if not good_code.has(gid):
				continue
			var entry: Dictionary = goods[str(gid)]
			market_goods += _csv_line([str(int(mk["i"])), String(good_code[gid]),
				_num2(float(entry.get("stock", 0))), _num2(float(entry.get("price", 0)))])
	if not _write_text(out_data + "/economy/markets.csv", out):
		return 1
	if not _write_text(out_data + "/economy/market_goods.csv", market_goods):
		return 1

	# --- military/* -------------------------------------------------------
	out = _csv_line(["unit_code", "label", "type", "rural_rate", "urban_rate", "crew", "power", "separate"])
	var unit_power: Dictionary = {}
	for u in ((world["settings"] as Dictionary).get("options", {}) as Dictionary).get("military", []):
		if not u is Dictionary:
			continue
		unit_power[String(u["name"])] = float(u.get("power", 1))
		out += _csv_line([String(u["name"]), String(u["name"]).capitalize(), String(u.get("type", "")),
			_num2(float(u.get("rural", 0))), _num2(float(u.get("urban", 0))),
			str(int(u.get("crew", 1))), _num2(float(u.get("power", 1))),
			"1" if u.get("separate") else "0"])
	if not _write_text(out_data + "/military/unit_types.csv", out):
		return 1
	var reg_header: Array[String] = ["regiment_code", "kingdom_code", "label", "x", "y"]
	reg_header.append_array(unit_names)
	reg_header.append("is_naval")
	out = _csv_line(reg_header)
	var king_header: Array[String] = ["kingdom_code"]
	king_header.append_array(unit_names)
	king_header.append_array(["regiments", "strength", "alert", "expansionism"])
	var military := _csv_line(king_header)
	var regiment_slugs: Dictionary = {}
	for s in states:
		var totals: Dictionary = {}
		var regs: Array = s.get("military", [])
		var strength := 0.0
		for rg in regs:
			if not rg is Dictionary:
				continue
			var units: Dictionary = rg.get("u", {})
			var fields: Array[String] = [_take_slug(regiment_slugs, "%s %s" % [String(s["name"]), String(rg.get("name", ""))]),
				String(state_code[int(s["i"])]), String(rg.get("name", "")),
				_num2(float(rg.get("x", 0))), _num2(float(rg.get("y", 0)))]
			for u in unit_names:
				var n := int(units.get(u, 0))
				fields.append(str(n))
				totals[u] = int(totals.get(u, 0)) + n
				strength += n * float(unit_power.get(u, 1.0))
			fields.append("1" if int(rg.get("n", 0)) == 1 else "0")
			out += _csv_line(fields)
		var kfields: Array[String] = [String(state_code[int(s["i"])])]
		for u in unit_names:
			kfields.append(str(int(totals.get(u, 0))))
		kfields.append_array([str(regs.size()), _num2(strength), _num2(float(s.get("alert", 0))),
			_num2(float(s.get("expansionism", 0)))])
		military += _csv_line(kfields)
	if not _write_text(out_data + "/military/regiments.csv", out):
		return 1
	if not _write_text(out_data + "/military/kingdoms.csv", military):
		return 1

	# --- society/* --------------------------------------------------------
	out = _csv_line(["culture_code", "culture_id", "label", "type", "expansionism", "color"])
	for cu in _active(pack.get("cultures", [])):
		out += _csv_line([String(culture_code[int(cu["i"])]), str(int(cu["i"])), String(cu["name"]),
			String(cu.get("type", "")), _num2(float(cu.get("expansionism", 0))), String(cu.get("color", ""))])
	if not _write_text(out_data + "/society/cultures.csv", out):
		return 1
	out = _csv_line(["religion_code", "religion_id", "label", "type", "form", "culture_code", "deity",
		"urban_population", "rural_population", "area"])
	for rl in _active(pack.get("religions", [])):
		out += _csv_line([String(religion_code[int(rl["i"])]), str(int(rl["i"])), String(rl["name"]),
			String(rl.get("type", "")), String(rl.get("form", "")),
			String(culture_code.get(int(rl.get("culture", -1)), "")), String(rl.get("deity", "")),
			str(int(round(float(rl.get("urban", 0)) * rate))),
			str(int(round(float(rl.get("rural", 0)) * rate))), str(int(rl.get("area", 0)))])
	if not _write_text(out_data + "/society/religions.csv", out):
		return 1
	out = _csv_line(["zone_code", "label", "type", "cells", "center_x", "center_y", "province_codes", "kingdom_codes"])
	var zone_slugs: Dictionary = {}
	for z in _active(pack.get("zones", [])):
		var zcells: Array = z.get("cells", [])
		var sx := 0.0
		var sy := 0.0
		var provs: Array[String] = []
		var kings: Array[String] = []
		for ci in zcells:
			var c: Dictionary = cells[int(ci)]
			sx += float((c["p"] as Array)[0])
			sy += float((c["p"] as Array)[1])
			var pc := String(prov_code.get(int(c.get("province", 0)), ""))
			if pc != "" and not provs.has(pc):
				provs.append(pc)
			var kc := String(state_code.get(int(c.get("state", 0)), ""))
			if kc != "" and not kings.has(kc):
				kings.append(kc)
		var n := maxi(zcells.size(), 1)
		out += _csv_line([_take_slug(zone_slugs, String(z.get("name", ""))), String(z.get("name", "")),
			String(z.get("type", "")), str(zcells.size()), _num2(sx / n), _num2(sy / n),
			"|".join(provs), "|".join(kings)])
	if not _write_text(out_data + "/society/zones.csv", out):
		return 1
```

Update the header comment's file list to the domain layout. Run the importer; confirm `git status` shows only the expected files under `data/maps/beria/`.

- [ ] **Step 5: Loader — `world_tables`**

In `scripts/engine/data_repository.gd` add the fields and spec:

```gdscript
## Every pack table by domain and area: world_tables[domain][area][code] -> row
## (spec 2026-09-09 §1). The named fields below (kingdoms, provinces, burgs,
## routes, rivers, markers, biomes) are the SAME Dictionary objects, so the
## old callers and the ledger see one set of rows.
var world_tables: Dictionary = {}

## [domain, area, required columns, key columns, key separator]. A table absent
## from a pack simply loads as {} (the ledger reads null for its paths).
const WORLD_TABLE_SPECS := [
	["political", "diplomacy", ["kingdom_code", "other_code", "stance"], ["kingdom_code", "other_code"], ">"],
	["political", "campaigns", ["kingdom_code", "label"], ["kingdom_code", "label"], ":"],
	["economy", "kingdoms", ["kingdom_code", "treasury", "sales_tax", "poll_tax"], ["kingdom_code"], ""],
	["economy", "provinces", ["province_code"], ["province_code"], ""],
	["economy", "burgs", ["burg_code"], ["burg_code"], ""],
	["economy", "goods", ["good_code", "label"], ["good_code"], ""],
	["economy", "markets", ["market_id", "center_burg"], ["market_id"], ""],
	["economy", "market_goods", ["market_id", "good_code"], ["market_id", "good_code"], ":"],
	["economy", "production", ["burg_code", "good_code"], ["burg_code", "good_code"], ":"],
	["military", "kingdoms", ["kingdom_code"], ["kingdom_code"], ""],
	["military", "regiments", ["regiment_code", "kingdom_code"], ["regiment_code"], ""],
	["military", "unit_types", ["unit_code"], ["unit_code"], ""],
	["society", "cultures", ["culture_code", "label"], ["culture_code"], ""],
	["society", "religions", ["religion_code", "label"], ["religion_code"], ""],
	["society", "zones", ["zone_code", "label", "type"], ["zone_code"], ""],
]

func world_table(domain: String, area: String) -> Dictionary:
	return (world_tables.get(domain, {}) as Dictionary).get(area, {})

func world_row(domain: String, area: String, code: String) -> Dictionary:
	return world_table(domain, area).get(code, {})

func _register_table(domain: String, area: String, table: Dictionary) -> void:
	if not world_tables.has(domain):
		world_tables[domain] = {}
	world_tables[domain][area] = table
```

In `load_map`: `world_tables.clear()` beside the other clears; change the paths to `dir + "/political/kingdoms.csv"` etc. and `dir + "/geography/routes.csv"` etc.; after the existing loads register the named tables (`_register_table("political", "kingdoms", kingdoms)` … `_register_table("geography", "biomes", biomes)`); then:

```gdscript
	for spec in WORLD_TABLE_SPECS:
		var table: Dictionary = {}
		var key_cols: Array = spec[3]
		var sep := String(spec[4])
		if not _load_if_present("%s/%s/%s.csv" % [dir, spec[0], spec[1]], spec[2],
				func(r: Dictionary) -> void:
					var parts: Array[String] = []
					for k in key_cols:
						parts.append(String(r[k]))
					table[sep.join(parts)] = r):
			return false
		_register_table(String(spec[0]), String(spec[1]), table)
```

- [ ] **Step 6: Run the new tests and the map tests**

Run with `-gselect=test_world_tables`, then `-gselect=test_map`. Expected: all pass. Fix any path the tests still expect at the root (`test_map_pack.gd` reads `res://data/maps.csv` only; `test_map_data.gd` reads through the repo).

- [ ] **Step 7: CLAUDE.md**

In the "Key documents" bullet, replace the flat list of map pack tables with: "the map pack tables under `data/maps/<id>/` — `map_info.csv`, `realm_bindings.csv` at the root and, by domain, `geography/` (`biomes`, `rivers`, `markers`, `routes`), `political/` (`kingdoms`, `provinces`, `burgs`, `borders`, `province_borders`, `diplomacy`, `campaigns`), `economy/` (`kingdoms`, `provinces`, `burgs`, `goods`, `markets`, `market_goods`, `production`), `military/` (`kingdoms`, `regiments`, `unit_types`), `society/` (`cultures`, `religions`, `zones`)". Add: "Each domain folder carries a `.gdignore` so Godot does not import game tables as translations; `FileAccess` reads them regardless, and a future export preset must include `data/**` explicitly."

- [ ] **Step 8: Full suite and commit**

```bash
./run_tests.sh
git add -A data/maps/beria tools/import_azgaar.gd scripts/engine/data_repository.gd tests/engine/test_world_tables.gd CLAUDE.md
git commit -m "feat(data): import the export's economy, military, politics, and society into domain folders"
```

---

### Task 2: World ledger — schema, state, reads, clamped writes

**Files:**
- Create: `data/world_schema.csv`
- Create: `scripts/engine/world_ledger.gd`
- Modify: `scripts/engine/data_repository.gd` (load `world_schema`)
- Modify: `scripts/engine/game_state.gd` (`world`, `world_log`, save v3)
- Modify: `scripts/engine/character.gd` (`change_attribute`, `attribute_log`)
- Test: `tests/engine/test_world_ledger.gd` (create), `tests/engine/test_game_state.gd` (round trip)

**Interfaces:**
- Consumes: `DataRepository.world_table/world_row`, `realm_bindings`, `bal`.
- Produces: `DataRepository.world_schema: Array[Dictionary]`; `GameState.world: Dictionary`, `GameState.world_log: Array`; `Character.change_attribute(name: String, delta: int, reason: String, tick: int) -> void`, `Character.attribute_log: Array`; `WorldLedger.resolve(data, path) -> String`, `schema_for(data, path) -> Dictionary`, `value_of(data, state, path) -> Variant`, `apply(data, state, path, delta: float, reason: String, source: String) -> Dictionary` (`{path, delta, value, reason, source}` or `{error}`), `set_enum(data, state, path, value: String, reason, source) -> Dictionary`, `polarity_of(data, path) -> int`, `llm_cap(data, path) -> float`, `belongs_to_player(data, state, path) -> bool`, `prompt_catalog(data, state) -> String`.

- [ ] **Step 1: The schema file**

`data/world_schema.csv` (the caps are the largest delta the model may move a field by in one order; `0` is engine-only):

```csv
path,type,min,max,enum_values,good_direction,llm_cap,alias_to,alias_scale_key,label,notes
metrics.treasury,float,-100000,100000,,1,60,,,Treasury,gold in the crown's chest
metrics.grain,float,0,100000,,1,30,,,Grain,stores in the royal granaries
metrics.unrest,float,0,100,,-1,5,,,Unrest,
metrics.legitimacy,float,0,100,,1,3,,,Legitimacy,
metrics.army_quality,float,0,100,,1,3,,,Army quality,
metrics.church_opinion,float,0,100,,1,3,,,Church opinion,
metrics.peasant_contentment,float,0,100,,1,5,,,Peasant contentment,
metrics.tax_rate,float,1,10,,0,0,,,Tax rate,engine-only: TAX_RATE_ADJUST moves it
metrics.tariff_rate,float,0,10,,0,0,,,Tariff rate,engine-only: TARIFF_ADJUST moves it
metrics.tax_income,float,-100000,100000,,1,0,,,Tax income,recomputed every tick
metrics.admin_capacity,float,0,1000,,1,0,,,Admin capacity,recomputed every tick
metrics.grain_capacity_bonus,float,0,100000,,1,0,,,Granary capacity,
metrics.road_income_bonus,float,0,100000,,1,0,,,Road income,
metrics.grain_ration,float,0,1,,0,0,,,Grain rationing,
opinion.*,int,-100,100,,1,3,,,Opinion of the ruler,the same cap as tone
attribute.*.health,int,0,100,,1,2,,,Health,
attribute.*.wealth,int,0,100,,1,2,,,Wealth,
attribute.*.prestige,int,0,100,,1,2,,,Prestige,
attribute.*.influence,int,0,100,,1,2,,,Influence,
economy.kingdoms.player_realm.treasury,float,-100000,100000,,1,60,metrics.treasury,,Treasury,the player's row IS the metric (one truth)
economy.kingdoms.player_realm.poll_tax,float,0,1,,0,0,metrics.tax_rate,tax_rate_per_poll_tax,Poll tax,derived from the tax rate
economy.kingdoms.player_realm.sales_tax,float,0,1,,0,0,metrics.tariff_rate,tariff_rate_per_sales_tax,Sales tax,derived from the tariff rate
economy.kingdoms.*.treasury,float,-100000,1000000,,1,0,,,Treasury,foreign treasuries are engine-only
economy.kingdoms.*.poll_tax,float,0,1,,0,0,,,Poll tax,
economy.kingdoms.*.sales_tax,float,0,1,,0,0,,,Sales tax,
economy.kingdoms.*.urban_population,int,0,100000000,,1,2000,,,Urban population,
economy.kingdoms.*.rural_population,int,0,100000000,,1,5000,,,Rural population,
economy.provinces.*.urban_population,int,0,100000000,,1,1000,,,Urban population,
economy.provinces.*.rural_population,int,0,100000000,,1,2000,,,Rural population,
economy.burgs.*.treasury,float,0,1000000,,1,20,,,Town treasury,
economy.burgs.*.product,float,0,1000000,,1,0,,,Town product,
political.provinces.*.kingdom_code,enum,,,,0,0,,,Owner,engine-only: MapOwnership.set_owner moves territory
political.diplomacy.*.stance,enum,,,Ally|Friendly|Neutral|Suspicion|Rival|Enemy|Vassal|Suzerain|Unknown,0,0,,,Stance,engine-only for now
military.kingdoms.*.infantry,int,0,10000000,,1,500,,,Infantry,
military.kingdoms.*.archers,int,0,10000000,,1,500,,,Archers,
military.kingdoms.*.cavalry,int,0,10000000,,1,300,,,Cavalry,
military.kingdoms.*.artillery,int,0,10000000,,1,10,,,Artillery,
military.kingdoms.*.fleet,int,0,10000000,,1,2,,,Fleet,
military.kingdoms.*.alert,float,0,10,,0,0,,,Alert,engine-only
society.religions.*.urban_population,int,0,100000000,,1,0,,,Urban faithful,
society.religions.*.rural_population,int,0,100000000,,1,0,,,Rural faithful,
```

Add to `data/balance.csv`:

```csv
pack_treasury_scale,1.0,gold per unit of the export's state treasury when seeding the player's realm
tax_rate_per_poll_tax,36,tax_rate (1-10) = round(export pollTax x this); also the alias scale for the player's poll_tax row
tariff_rate_per_sales_tax,60,tariff_rate (0-10) = round(export salesTax x this); also the alias scale for the player's sales_tax row
order_prompt_max_burgs,12,largest towns of the player's realm listed in the order prompt
order_narrative_max_chars,600,longest narrative the validator keeps from an order reply
```

Load them in `DataRepository._load` after `event_choices`:

```gdscript
	if not _load_if_present(dir + "/world_schema.csv", ["path", "type", "good_direction", "llm_cap"],
			func(r): world_schema.append(r)):
		return false
```

with `var world_schema: Array[Dictionary] = []` declared beside `signatures`.

- [ ] **Step 2: Write the failing tests**

`tests/engine/test_world_ledger.gd`:

```gdscript
extends GutTest
## The world ledger (spec 2026-09-09 §2): one addressable schema over the
## player's metrics, the court's opinions and attributes, and the pack's
## domain tables; every write clamped, reasoned, and logged.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func _player() -> String:
	return data.resolve_realm("player_realm")

func test_slots_resolve_to_the_bound_kingdom() -> void:
	assert_eq(WorldLedger.resolve(data, "economy.kingdoms.player_realm.treasury"),
		"economy.kingdoms.%s.treasury" % _player())
	assert_eq(WorldLedger.resolve(data, "metrics.grain"), "metrics.grain", "no slot, no change")

func test_the_most_specific_schema_row_wins() -> void:
	var mine := WorldLedger.schema_for(data, "economy.kingdoms.player_realm.treasury")
	assert_eq(String(mine["alias_to"]), "metrics.treasury", "the player's row aliases the metric")
	var other := ""
	for code: String in data.kingdoms:
		if code != _player():
			other = code
			break
	var theirs := WorldLedger.schema_for(data, "economy.kingdoms.%s.treasury" % other)
	assert_eq(String(theirs["alias_to"]), "", "a foreign treasury is its own field")
	assert_true(WorldLedger.schema_for(data, "no.such.path.here").is_empty())

func test_reads_fall_through_from_override_to_pack() -> void:
	var row: Dictionary = data.world_row("military", "kingdoms", _player())
	var path := "military.kingdoms.player_realm.infantry"
	assert_eq(int(WorldLedger.value_of(data, state, path)), int(row["infantry"]), "pack value")
	var out := WorldLedger.apply(data, state, path, -100.0, "a skirmish", "test")
	assert_false(out.has("error"), str(out))
	assert_eq(int(WorldLedger.value_of(data, state, path)), int(row["infantry"]) - 100, "override")
	assert_eq(state.world.size(), 1, "only the moved field is stored")
	assert_eq(String(state.world_log[0]["reason"]), "a skirmish")
	assert_eq(String(state.world_log[0]["source"]), "test")

func test_alias_reads_and_writes_the_metric() -> void:
	state.metrics["treasury"] = 300.0
	assert_eq(float(WorldLedger.value_of(data, state, "economy.kingdoms.player_realm.treasury")), 300.0)
	var out := WorldLedger.apply(data, state, "economy.kingdoms.player_realm.treasury", -40.0, "surveyors", "test")
	assert_eq(float(out["delta"]), -40.0)
	assert_eq(state.metrics["treasury"], 260.0, "the metric moved")
	assert_false(state.world.has("economy.kingdoms.%s.treasury" % _player()), "no shadow copy")
	# Scaled alias: poll_tax is the tax rate divided by the balance factor.
	state.metrics["tax_rate"] = 6.0
	assert_almost_eq(float(WorldLedger.value_of(data, state, "economy.kingdoms.player_realm.poll_tax")),
		6.0 / data.bal("tax_rate_per_poll_tax"), 0.0001)

func test_writes_clamp_to_the_schema_range() -> void:
	state.metrics["unrest"] = 98.0
	var out := WorldLedger.apply(data, state, "metrics.unrest", 10.0, "riots", "test")
	assert_eq(float(out["delta"]), 2.0, "clamped to the max")
	assert_eq(state.metrics["unrest"], 100.0)

func test_unlisted_path_and_empty_reason_are_refused() -> void:
	assert_true(WorldLedger.apply(data, state, "metrics.no_such", 1.0, "why", "test").has("error"))
	assert_true(WorldLedger.apply(data, state, "metrics.grain", 1.0, "  ", "test").has("error"))
	assert_true(WorldLedger.apply(data, state, "political.diplomacy.a>b.stance", 1.0, "why", "test").has("error"),
		"an enum is not numeric")
	assert_true(state.world_log.is_empty(), "nothing refused is logged")

func test_opinion_and_attribute_paths_go_through_the_character_logs() -> void:
	var before: int = state.characters["char_marshal"].opinion
	WorldLedger.apply(data, state, "opinion.char_marshal", 2.0, "a kind word", "test")
	var c: Character = state.characters["char_marshal"]
	assert_eq(c.opinion, before + 2)
	assert_eq(String(c.opinion_log[-1]["reason"]), "a kind word")
	var you: Character = state.characters["you"]
	var p: int = you.attributes["prestige"]
	WorldLedger.apply(data, state, "attribute.you.prestige", -1.0, "a slight", "test")
	assert_eq(int(you.attributes["prestige"]), p - 1)
	assert_eq(String(you.attribute_log[-1]["reason"]), "a slight")

func test_set_enum_accepts_only_listed_values() -> void:
	var other := ""
	for code: String in data.kingdoms:
		if code != _player():
			other = code
			break
	var path := "political.diplomacy.player_realm>%s.stance" % other
	assert_true(WorldLedger.set_enum(data, state, path, "Dragon", "why", "test").has("error"))
	var out := WorldLedger.set_enum(data, state, path, "Enemy", "a border raid", "test")
	assert_false(out.has("error"), str(out))
	assert_eq(String(WorldLedger.value_of(data, state, path)), "Enemy")

func test_polarity_and_caps_read_from_the_schema() -> void:
	assert_eq(WorldLedger.polarity_of(data, "metrics.unrest"), -1)
	assert_eq(WorldLedger.polarity_of(data, "metrics.treasury"), 1)
	assert_eq(WorldLedger.polarity_of(data, "metrics.tax_rate"), 0)
	assert_eq(WorldLedger.llm_cap(data, "opinion.char_marshal"), data.bal("tone_delta_cap"))
	assert_eq(WorldLedger.llm_cap(data, "metrics.tax_rate"), 0.0, "engine-only")

func test_only_the_players_own_land_belongs_to_them() -> void:
	assert_true(WorldLedger.belongs_to_player(data, state, "metrics.grain"))
	assert_true(WorldLedger.belongs_to_player(data, state, "economy.kingdoms.player_realm.rural_population"))
	assert_true(WorldLedger.belongs_to_player(data, state, "economy.kingdoms.%s.rural_population" % _player()))
	var mine := MapOwnership.provinces_of(data, state, _player())
	assert_true(WorldLedger.belongs_to_player(data, state, "economy.provinces.%s.rural_population" % mine[0]))
	var foreign := ""
	for code: String in data.provinces:
		if String(data.provinces[code]["kingdom_code"]) != _player():
			foreign = code
			break
	assert_false(WorldLedger.belongs_to_player(data, state, "economy.provinces.%s.rural_population" % foreign))
	assert_false(WorldLedger.belongs_to_player(data, state, "economy.kingdoms.raider_realm.rural_population"))

func test_overrides_survive_a_save_round_trip() -> void:
	WorldLedger.apply(data, state, "military.kingdoms.player_realm.cavalry", -50.0, "lost horses", "test")
	var back := GameState.from_dict(state.to_dict())
	assert_eq(int(WorldLedger.value_of(data, back, "military.kingdoms.player_realm.cavalry")),
		int(WorldLedger.value_of(data, state, "military.kingdoms.player_realm.cavalry")))
	assert_eq(back.world_log.size(), 1)

func test_prompt_catalog_lists_writable_fields_with_caps() -> void:
	var cat := WorldLedger.prompt_catalog(data, state)
	assert_string_contains(cat, "metrics.grain")
	assert_string_contains(cat, "economy.kingdoms.player_realm.rural_population")
	assert_string_contains(cat, "cap")
	assert_false(cat.contains("metrics.tax_rate"), "engine-only fields are not offered")
	assert_string_contains(cat, "Your provinces:")
```

- [ ] **Step 3: Run to verify it fails**

`-gselect=test_world_ledger` → parse error: `WorldLedger` not declared.

- [ ] **Step 4: Character and GameState**

`scripts/engine/character.gd`: add `var attribute_log: Array = []` and

```gdscript
## Role-level metrics (health, wealth, prestige, influence) move with a
## reason, like opinion: an attribute that changed without one is a number
## nobody can explain later.
func change_attribute(name: String, delta: int, reason: String, tick: int) -> void:
	attributes[name] = clampi(int(attributes.get(name, 50)) + delta, 0, 100)
	attribute_log.append({"tick": tick, "attribute": name, "delta": delta, "reason": reason})
```

Serialize it: `"attribute_log": GameState._encode_values(attribute_log.duplicate(true))` in `to_dict`, `c.attribute_log = GameState._decode_values(d.get("attribute_log", []))` in `from_dict`.

`scripts/engine/game_state.gd`: beside `province_owner` add

```gdscript
## The world ledger's overrides: resolved path -> value, holding ONLY fields
## that have moved (WorldLedger). An absent path still reads the pack's
## starting value. Read and write it through WorldLedger, never directly.
var world: Dictionary = {}
## One entry per ledger write: {tick, path, delta, reason, source}.
var world_log: Array = []
```

`SAVE_VERSION := 3`; in `to_dict` add `"world": _encode_values(world.duplicate())` and `"world_log": _encode_values(world_log.duplicate(true))`; in `from_dict` add `s.world = _decode_values(d.get("world", {}))` and `s.world_log = _decode_values(d.get("world_log", []))`.

- [ ] **Step 5: WorldLedger**

`scripts/engine/world_ledger.gd`:

```gdscript
class_name WorldLedger
extends RefCounted
## One addressable schema over everything the game can move (spec 2026-09-09
## §2): the player's metrics, the court's opinions and attributes, and the
## pack's domain tables. Paths read `metrics.<name>`, `opinion.<id>`,
## `attribute.<id>.<name>`, or `<domain>.<area>.<code>.<field>`; a code may be
## a realm slot. data/world_schema.csv says what each field is, its range,
## which way is good for the crown, and how far the model may move it.
##
## The pack ships starting values; GameState.world holds only what has moved
## (the province_owner pattern), and an aliased row (the player's treasury)
## has no copy at all — it reads and writes the metric. Engine-pure.

const SEP := "."
const WILDCARD := "*"

## Substitutes realm slots in any segment.
static func resolve(data: DataRepository, path: String) -> String:
	var parts := path.split(SEP)
	for i in parts.size():
		if data.realm_bindings.has(parts[i]):
			parts[i] = String(data.realm_bindings[parts[i]])
	return SEP.join(parts)

## The schema row governing a path: same segment count, every non-wildcard
## segment equal after slot resolution, fewest wildcards wins. {} if none.
static func schema_for(data: DataRepository, path: String) -> Dictionary:
	var parts := resolve(data, path).split(SEP)
	var best: Dictionary = {}
	var best_wild := 1 << 30
	for row: Dictionary in data.world_schema:
		var pat := resolve(data, String(row["path"])).split(SEP)
		if pat.size() != parts.size():
			continue
		var wild := 0
		var ok := true
		for i in parts.size():
			if pat[i] == WILDCARD:
				wild += 1
			elif pat[i] != parts[i]:
				ok = false
				break
		if ok and wild < best_wild:
			best = row
			best_wild = wild
	return best

static func polarity_of(data: DataRepository, path: String) -> int:
	return int(float(schema_for(data, path).get("good_direction", 0)))

static func llm_cap(data: DataRepository, path: String) -> float:
	return float(schema_for(data, path).get("llm_cap", 0))

## The field's current value: an alias reads its truth (scaled), an override
## wins over the pack, the pack row's column is parsed by type. null when the
## path has no schema row or no value behind it.
static func value_of(data: DataRepository, state: GameState, path: String) -> Variant:
	var resolved := resolve(data, path)
	var row := schema_for(data, resolved)
	if row.is_empty():
		return null
	var alias := String(row.get("alias_to", ""))
	if alias != "":
		var truth: Variant = value_of(data, state, alias)
		if truth == null:
			return null
		var key := String(row.get("alias_scale_key", ""))
		return float(truth) / data.bal(key) if key != "" else truth
	if state != null and state.world.has(resolved):
		return state.world[resolved]
	return _base_value(data, state, resolved, row)

static func _base_value(data: DataRepository, state: GameState, resolved: String,
		row: Dictionary) -> Variant:
	var p := resolved.split(SEP)
	match p[0]:
		"metrics":
			if state == null or not state.metrics.has(p[1]):
				return null
			return state.metrics[p[1]]
		"opinion":
			if state == null or not state.characters.has(p[1]):
				return null
			return (state.characters[p[1]] as Character).opinion
		"attribute":
			if state == null or p.size() < 3 or not state.characters.has(p[1]):
				return null
			var attrs: Dictionary = (state.characters[p[1]] as Character).attributes
			return attrs.get(p[2]) if attrs.has(p[2]) else null
	if p.size() != 4:
		return null
	var table_row: Dictionary = data.world_row(p[0], p[1], p[2])
	if table_row.is_empty() or not table_row.has(p[3]):
		return null
	var raw := String(table_row[p[3]])
	match String(row.get("type", "float")):
		"int":
			return int(float(raw))
		"enum":
			return raw
	return float(raw)

## Move a numeric field by delta, clamped to the schema range. Refuses an
## unlisted path, an enum, or an empty reason. Returns the applied change or
## {error}.
static func apply(data: DataRepository, state: GameState, path: String, delta: float,
		reason: String, source: String) -> Dictionary:
	var resolved := resolve(data, path)
	var row := schema_for(data, resolved)
	if row.is_empty():
		return {"error": "no such field: " + path}
	if reason.strip_edges() == "":
		return {"error": "a change needs a reason: " + path}
	var t := String(row.get("type", "float"))
	if t == "enum":
		return {"error": "%s is not numeric" % path}
	var alias := String(row.get("alias_to", ""))
	if alias != "":
		var key := String(row.get("alias_scale_key", ""))
		var scale := data.bal(key) if key != "" else 1.0
		var out := apply(data, state, alias, delta * scale, reason, source)
		if out.has("error"):
			return out
		out["path"] = resolved
		out["delta"] = float(out["delta"]) / scale
		out["value"] = float(out["value"]) / scale
		return out
	var current: Variant = value_of(data, state, resolved)
	if current == null:
		return {"error": "no value behind " + path}
	var lo := float(row["min"]) if String(row.get("min", "")) != "" else -INF
	var hi := float(row["max"]) if String(row.get("max", "")) != "" else INF
	var target := clampf(float(current) + delta, lo, hi)
	if t == "int":
		target = roundf(target)
	var applied := target - float(current)
	_write(data, state, resolved, target, applied, reason)
	state.world_log.append({"tick": state.tick, "path": resolved, "delta": applied,
		"reason": reason, "source": source})
	return {"path": resolved, "delta": applied, "value": target, "reason": reason, "source": source}

## Set an enum field to one of its listed values.
static func set_enum(data: DataRepository, state: GameState, path: String, value: String,
		reason: String, source: String) -> Dictionary:
	var resolved := resolve(data, path)
	var row := schema_for(data, resolved)
	if row.is_empty():
		return {"error": "no such field: " + path}
	if String(row.get("type", "")) != "enum":
		return {"error": "%s is not an enum" % path}
	if reason.strip_edges() == "":
		return {"error": "a change needs a reason: " + path}
	var legal := String(row.get("enum_values", "")).split("|", false)
	if not legal.is_empty() and not value in legal:
		return {"error": "%s is not a legal %s" % [value, path]}
	state.world[resolved] = value
	state.world_log.append({"tick": state.tick, "path": resolved, "delta": 0.0,
		"value": value, "reason": reason, "source": source})
	return {"path": resolved, "delta": 0.0, "value": value, "reason": reason, "source": source}

static func _write(data: DataRepository, state: GameState, resolved: String, target: float,
		applied: float, reason: String) -> void:
	var p := resolved.split(SEP)
	match p[0]:
		"metrics":
			state.metrics[p[1]] = target
		"opinion":
			(state.characters[p[1]] as Character).change_opinion(roundi(applied), reason, state.tick)
		"attribute":
			(state.characters[p[1]] as Character).change_attribute(p[2], roundi(applied), reason, state.tick)
		_:
			state.world[resolved] = target

## Whether the field is the player's to move: metrics, opinions, and attributes
## always are; a kingdom row must be the player's realm; a province or burg row
## must lie in land the player holds NOW (MapOwnership).
static func belongs_to_player(data: DataRepository, state: GameState, path: String) -> bool:
	var p := resolve(data, path).split(SEP)
	if p[0] in ["metrics", "opinion", "attribute"]:
		return true
	if p.size() != 4:
		return false
	var mine := data.resolve_realm("player_realm")
	match p[1]:
		"kingdoms":
			return p[2] == mine
		"provinces":
			return MapOwnership.owner_of(data, state, p[2]) == mine
		"burgs":
			var b: Dictionary = data.burgs.get(p[2], {})
			return MapOwnership.owner_of(data, state, String(b.get("province_code", ""))) == mine
	return false

## The model-writable fields for the order prompt: one line per field with
## its current value and cap, wildcard kingdom rows expanded for the player's
## realm, plus the codes the model may put in a province or burg path.
static func prompt_catalog(data: DataRepository, state: GameState) -> String:
	var lines: Array[String] = []
	for row: Dictionary in data.world_schema:
		var cap := float(row.get("llm_cap", 0))
		if cap <= 0.0:
			continue
		var pat := String(row["path"])
		var parts := pat.split(SEP)
		if parts.size() == 4 and parts[1] == "kingdoms" and parts[2] == WILDCARD:
			parts[2] = "player_realm"
			pat = SEP.join(parts)
		if pat.contains(WILDCARD):
			lines.append("- %s (cap %s)" % [pat.replace(WILDCARD, "<code>"), _fmt(cap)])
			continue
		var v: Variant = value_of(data, state, pat)
		if v == null:
			continue
		lines.append("- %s = %s (cap %s)" % [pat, _fmt(float(v)), _fmt(cap)])
	var mine := data.resolve_realm("player_realm")
	lines.append("Your provinces: " + ", ".join(MapOwnership.provinces_of(data, state, mine)))
	var towns: Array = []
	for code: String in data.burgs:
		var b: Dictionary = data.burgs[code]
		if MapOwnership.owner_of(data, state, String(b["province_code"])) == mine:
			towns.append(b)
	towns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(float(a["population"])) > int(float(b["population"])))
	var names: Array[String] = []
	for i in mini(towns.size(), int(data.bal("order_prompt_max_burgs"))):
		names.append(String(towns[i]["burg_code"]))
	lines.append("Your largest towns: " + ", ".join(names))
	lines.append("Character ids for opinion/attribute paths: " + ", ".join(state.characters.keys()))
	return "\n".join(lines)

static func _fmt(v: float) -> String:
	return str(int(v)) if v == floorf(v) else String.num(v, 2)
```

Run the import pass (new `class_name`), then `-gselect=test_world_ledger` and `-gselect=test_game_state`. Expected: pass.

- [ ] **Step 6: Commit**

```bash
./run_tests.sh
git add data/world_schema.csv data/balance.csv scripts/engine/world_ledger.gd scripts/engine/game_state.gd scripts/engine/character.gd scripts/engine/data_repository.gd tests/engine/test_world_ledger.gd
git commit -m "feat(engine): the world ledger — schema-clamped, reasoned writes over the pack's tables"
```

---

### Task 3: Seed the player's metrics from the pack; ledger ops for events

**Files:**
- Modify: `scripts/engine/world_ledger.gd` (`seed_metrics`), `scripts/engine/game_state.gd` (call it)
- Modify: `scripts/engine/event_effects.gd`
- Test: `tests/engine/test_game_state.gd`, `tests/engine/test_event_effects.gd`, `tests/engine/test_world_ledger.gd`

**Interfaces:**
- Produces: `WorldLedger.seed_metrics(data, state) -> void`; `EventEffects` ops `world:<path>:<delta>:<reason>`, `attribute:<who>:<name>:<delta>:<reason>`, and optional trailing reasons on `gold:<amount>[:<reason>]` and `metric:<name>:<delta>[:<reason>]`.

- [ ] **Step 1: Failing tests**

Replace `test_new_campaign_reads_balance` in `tests/engine/test_game_state.gd`:

```gdscript
## One truth (owner ruling 2026-09-09): the player's treasury and rates are
## seeded from the pack's economy row through balance factors; grain and the
## drift baselines still come from balance.csv.
func test_new_campaign_seeds_from_the_pack_and_balance() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(s.tick, 0)
	var row: Dictionary = data.world_row("economy", "kingdoms", data.resolve_realm("player_realm"))
	assert_false(row.is_empty(), "the pack has the player's economy row")
	assert_eq(s.metrics["treasury"], roundf(float(row["treasury"]) * data.bal("pack_treasury_scale")))
	assert_eq(s.metrics["tax_rate"],
		clampf(roundf(float(row["poll_tax"]) * data.bal("tax_rate_per_poll_tax")), 1.0, 10.0))
	assert_eq(s.metrics["tariff_rate"],
		clampf(roundf(float(row["sales_tax"]) * data.bal("tariff_rate_per_sales_tax")), 0.0, 10.0))
	assert_eq(s.metrics["grain"], data.bal("start_grain"))
	assert_eq(s.metrics["legitimacy"], data.bal("start_metric_default"))
	assert_true(s.world.is_empty(), "seeding writes the metric, not an override")

func test_a_pack_without_an_economy_row_falls_back_to_balance() -> void:
	var stripped := DataRepository.load_all("res://data")
	stripped.world_tables["economy"]["kingdoms"].clear()
	var s := GameState.new_campaign(stripped, 42)
	assert_eq(s.metrics["treasury"], stripped.bal("start_treasury"))
	assert_eq(s.metrics["tax_rate"], stripped.bal("start_tax_rate"))
```

Append to `tests/engine/test_event_effects.gd` (use its existing fixture names; if it builds `state` in `before_each`, reuse it):

```gdscript
func test_world_and_attribute_ops_go_through_the_ledger() -> void:
	var before := int(WorldLedger.value_of(data, state, "military.kingdoms.player_realm.infantry"))
	var results := EventEffects.apply(
		"world:military.kingdoms.player_realm.infantry:-200:a plague in the barracks;"
		+ "attribute:you:prestige:-1:the court whispers", state, data)
	assert_eq(int(WorldLedger.value_of(data, state, "military.kingdoms.player_realm.infantry")), before - 200)
	assert_eq(String(results[0]["kind"]), "world")
	assert_eq(String(results[0]["reason"]), "a plague in the barracks")
	assert_eq(String(results[1]["kind"]), "attribute")
	assert_eq(String(state.characters["you"].attribute_log[-1]["reason"]), "the court whispers")

func test_gold_and_metric_ops_take_an_optional_reason() -> void:
	var results := EventEffects.apply("gold:-5:the clerks;metric:grain:3:a gift", state, data)
	assert_eq(String(results[0]["reason"]), "the clerks")
	assert_eq(String(results[1]["reason"]), "a gift")
```

- [ ] **Step 2: Run to verify they fail** (`-gselect=test_game_state`, `-gselect=test_event_effects`).

- [ ] **Step 3: Implement**

`WorldLedger`:

```gdscript
## One truth (owner ruling 2026-09-09): the player's realm starts with the
## pack's own treasury and tax rates, converted by balance factors. A pack
## without an economy row leaves balance.csv's start values in place.
static func seed_metrics(data: DataRepository, state: GameState) -> void:
	var row: Dictionary = data.world_row("economy", "kingdoms", data.resolve_realm("player_realm"))
	if row.is_empty():
		return
	state.metrics["treasury"] = roundf(float(row["treasury"]) * data.bal("pack_treasury_scale"))
	state.metrics["tax_rate"] = clampf(roundf(float(row["poll_tax"]) * data.bal("tax_rate_per_poll_tax")), 1.0, 10.0)
	state.metrics["tariff_rate"] = clampf(roundf(float(row["sales_tax"]) * data.bal("tariff_rate_per_sales_tax")), 0.0, 10.0)
```

`GameState.new_campaign`: call `WorldLedger.seed_metrics(data, s)` right after the `metrics` literal.

`EventEffects.apply`: in `"metric"` use `if p.size() > 3: r["reason"] = p[3] elif reason_label != "": r["reason"] = reason_label`; in `"gold"` the same with `p[2]`; add:

```gdscript
			"world":
				# world:<path>:<delta>:<reason> — any ledger field (spec 2026-09-09 §2).
				var w := WorldLedger.apply(data, state, p[1], float(p[2]),
					p[3] if p.size() > 3 else reason_label, "event")
				if w.has("error"):
					push_error("EventEffects: " + String(w["error"]))
				else:
					results.append({"kind": "world", "path": w["path"], "delta": w["delta"],
						"reason": w["reason"]})
			"attribute":
				# attribute:<who>:<name>:<delta>:<reason>
				var who := _resolve(p[1], state)
				if who != "":
					state.characters[who].change_attribute(p[2], int(p[3]), p[4], state.tick)
					results.append({"kind": "attribute", "character_id": who, "attribute": p[2],
						"delta": int(p[3]), "reason": p[4]})
```

Grep the tests for other literal `500` treasury assumptions (`grep -rn "500" tests`) and switch any to `data.bal(...)`/state-derived values.

- [ ] **Step 4: Run, then commit**

```bash
./run_tests.sh
git add scripts/engine/world_ledger.gd scripts/engine/game_state.gd scripts/engine/event_effects.gd tests/engine/test_game_state.gd tests/engine/test_event_effects.gd
git commit -m "feat(engine): seed the player's realm from the pack; ledger ops for events"
```

---

### Task 4: Order costs

**Files:**
- Create: `data/metric_polarity.csv`, `data/order_costs.csv`
- Create: `scripts/engine/order_costs.gd`
- Modify: `scripts/engine/data_repository.gd` (load both), `scripts/engine/action_system.gd`
- Test: `tests/engine/test_order_costs.gd` (create), `tests/engine/test_action_system.gd`

**Interfaces:**
- Produces: `DataRepository.metric_polarity: Dictionary` (metric → int), `DataRepository.order_costs: Dictionary` (action_code → row `{action_code, cost, always, notes}`); `OrderCosts.snapshot_opinions(state) -> Dictionary`, `OrderCosts.has_cost(data, state, effects: Array, drift: Array, opinions_before: Dictionary) -> bool`, `OrderCosts.charge(data, state, action_code: String, target: String) -> Array` (EventEffects-shaped results with `reason`), `OrderCosts.ensure(data, state, effects: Array, drift: Array, opinions_before: Dictionary, action_code: String, target: String) -> Array` (the charged effects, already appended to `effects`), `OrderCosts.gold_of(data, action_code) -> float`.

- [ ] **Step 1: Data**

`data/metric_polarity.csv`:

```csv
metric,good_direction,notes
treasury,1,
tax_rate,0,a rate is neither good nor bad in itself
tariff_rate,0,
tax_income,1,
admin_capacity,1,
legitimacy,1,
unrest,-1,
grain,1,
army_quality,1,
church_opinion,1,
peasant_contentment,1,
grain_capacity_bonus,1,
road_income_bonus,1,
grain_ration,0,
```

`data/order_costs.csv` (`cost` is an EventEffects op string; `always` 1 applies every time, 0 only when the order carried no cost of its own; `none` marks an exempt action):

```csv
action_code,cost,always,notes
generic_order,gold:-5:the chancery's clerks and couriers,0,an order that executes no action and whose impacts carried no cost
TAX_RATE_ADJUST,opinion:steward:-2:re-cutting the tax rolls,0,
TARIFF_ADJUST,opinion:char_guildmaster_tessa:-2:the guilds re-price their wares,0,
LEVY_RAISE,world:economy.kingdoms.player_realm.rural_population:-2000:levies drawn from the villages,1,explicit population cost beside the gold
GRAIN_POLICY_SET,opinion:steward:-1:the granary clerks grumble at new orders,0,
CHURCH_POLICY,opinion:chaplain:-1:the church dislikes being managed,0,
JUSTICE_SEVERITY,opinion:chancellor:-1:the courts resent being retuned,0,
BUILD_ECONOMIC,opinion:steward:-1:the treasury frets over the outlay,0,
SPY_MISSION,attribute:you:prestige:-1:whispers about the crown's whisperers,0,
COUNCIL_CONSULT,none,0,a question is not an order
COUNCIL_DEBATE_RULE,attribute:you:influence:-1:a ruling spends the crown's authority,0,
RECRUIT_COURTIER,gold:-40:a courtier's retainer,0,formula_recruit_cost is not a real formula yet
CHARACTER_REWARD,attribute:you:wealth:-1:the privy purse thins,0,
CHARACTER_PUNISH,opinion:target:-2:the punished nurse the grudge,0,
CHARACTER_INVESTIGATE,gold:-15:the spymaster's informants are paid,0,formula_investigate is not a real formula yet
CHARACTER_CONFIDE,attribute:you:prestige:-1:a king who confides shows his need,0,
FACTION_NEGOTIATE,attribute:you:influence:-2:bargaining with subjects spends authority,0,
FACTION_SPLIT,gold:-30:silver for the waverers,0,
COURT_MARRIAGE,gold:-25:the dowry,0,
GUARD_ADJUST,gold:-10:the guard's wages,0,
EVENT_CHOICE,none,0,event choices carry their own authored effects
```

Load in `DataRepository._load` (fields `var metric_polarity: Dictionary = {}`, `var order_costs: Dictionary = {}`):

```gdscript
	if not _load_if_present(dir + "/metric_polarity.csv", ["metric", "good_direction"],
			func(r): metric_polarity[r["metric"]] = int(float(r["good_direction"]))):
		return false
	if not _load_if_present(dir + "/order_costs.csv", ["action_code", "cost", "always"],
			func(r): order_costs[r["action_code"]] = r):
		return false
```

- [ ] **Step 2: Failing tests**

`tests/engine/test_order_costs.gd`:

```gdscript
extends GutTest
## Every order carries a cost (owner rule 2026-09-09, spec §3): explicit
## (gold, grain, population) or hidden (opinion, relationship, attribute).

var data: DataRepository
var state: GameState
var sys: ActionSystem

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)
	sys = ActionSystem.new(data)

func test_every_catalog_action_has_a_cost_row() -> void:
	for code: String in data.actions:
		assert_true(data.order_costs.has(code), "%s has an order_costs.csv row" % code)
	assert_true(data.order_costs.has("generic_order"))
	assert_true(data.order_costs.has("EVENT_CHOICE"))

func test_polarity_covers_every_metric() -> void:
	for m: String in state.metrics:
		assert_true(data.metric_polarity.has(m), "metric_polarity.csv lists %s" % m)

func test_cost_detection_reads_polarity() -> void:
	assert_true(OrderCosts.has_cost(data, state, [{"metric": "treasury", "delta": -5.0, "reason": "x"}], [], {}))
	assert_true(OrderCosts.has_cost(data, state, [{"metric": "unrest", "delta": 2.0, "reason": "x"}], [], {}))
	assert_false(OrderCosts.has_cost(data, state, [{"metric": "grain", "delta": 20.0, "reason": "x"}], [], {}))
	assert_false(OrderCosts.has_cost(data, state, [{"metric": "tax_rate", "delta": -1.0, "reason": "x"}], [], {}),
		"a rate change is neutral in itself")
	assert_true(OrderCosts.has_cost(data, state, [], [{"character_id": "char_marshal", "delta": -3, "reason": "x"}], {}))
	assert_true(OrderCosts.has_cost(data, state,
		[{"kind": "world", "path": "economy.kingdoms.player_realm.rural_population", "delta": -100.0}], [], {}))
	assert_false(OrderCosts.has_cost(data, state,
		[{"kind": "world", "path": "economy.kingdoms.player_realm.rural_population", "delta": 100.0}], [], {}))

func test_direct_opinion_losses_count_through_the_snapshot() -> void:
	var before := OrderCosts.snapshot_opinions(state)
	state.characters["char_marshal"].change_opinion(-4, "test", 0)
	assert_true(OrderCosts.has_cost(data, state, [], [], before))

func test_charge_applies_the_row_with_its_reason() -> void:
	var p: int = state.characters["you"].attributes["prestige"]
	var charged := OrderCosts.charge(data, state, "CHARACTER_CONFIDE", "")
	assert_eq(charged.size(), 1)
	assert_eq(int(state.characters["you"].attributes["prestige"]), p - 1)
	assert_string_contains(String(charged[0]["reason"]), "confides")
	assert_true(OrderCosts.charge(data, state, "COUNCIL_CONSULT", "").is_empty(), "exempt")

func test_charge_resolves_target_for_punishments() -> void:
	var before: int = state.characters["char_marshal"].opinion
	OrderCosts.charge(data, state, "CHARACTER_PUNISH", "char_marshal")
	assert_eq(state.characters["char_marshal"].opinion, before - 2)

func test_ensure_charges_only_when_nothing_else_did() -> void:
	var effects: Array = [{"metric": "treasury", "delta": -30.0, "reason": "paid"}]
	var charged := OrderCosts.ensure(data, state, effects, [], OrderCosts.snapshot_opinions(state), "CHARACTER_CONFIDE", "")
	assert_true(charged.is_empty(), "the gold already was the cost")
	var free: Array = []
	charged = OrderCosts.ensure(data, state, free, [], OrderCosts.snapshot_opinions(state), "CHARACTER_CONFIDE", "")
	assert_eq(charged.size(), 1)
	assert_eq(free.size(), 1, "the charge rides on the outcome's effects")

func test_always_rows_apply_beside_intrinsic_costs() -> void:
	var pop_before := int(WorldLedger.value_of(data, state, "economy.kingdoms.player_realm.rural_population"))
	var out := sys.execute(ActionRequest.make("LEVY_RAISE"), state)
	assert_lt(int(WorldLedger.value_of(data, state, "economy.kingdoms.player_realm.rural_population")), pop_before,
		"levies draw down the villages every time")
	var seen := false
	for e in out["effects"]:
		if String(e.get("kind", "")) == "world":
			seen = true
	assert_true(seen, "the population cost is on the outcome")

## The guarantee itself: every handled action, executed from a fresh
## campaign, leaves a cost on the record.
func test_every_handled_action_leaves_a_cost() -> void:
	var cases := [
		ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}),
		ActionRequest.make("TARIFF_ADJUST", {"delta": -1}),
		ActionRequest.make("LEVY_RAISE"),
		ActionRequest.make("GRAIN_POLICY_SET", {"mode": "market"}),
		ActionRequest.make("CHURCH_POLICY", {"mode": "endow"}),
		ActionRequest.make("JUSTICE_SEVERITY", {"delta": -1}),
		ActionRequest.make("BUILD_ECONOMIC", {"project": "road"}),
		ActionRequest.make("SPY_MISSION"),
		ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_marshal"),
		ActionRequest.make("CHARACTER_PUNISH", {}, "char_marshal"),
		ActionRequest.make("CHARACTER_CONFIDE", {}, "char_marshal"),
		ActionRequest.make("RECRUIT_COURTIER", {}, "char_bard_corvin"),
		ActionRequest.make("GUARD_ADJUST"),
	]
	for req in cases:
		var s := GameState.new_campaign(data, 42)
		var before := OrderCosts.snapshot_opinions(s)
		assert_eq(sys.validate(req, s), "", req.action_code + " is legal on a fresh campaign")
		var out := sys.execute(req, s)
		assert_true(OrderCosts.has_cost(data, s, out["effects"], out["drift"], before),
			"%s left a cost" % req.action_code)

func test_affordability_counts_the_cost_rows_gold() -> void:
	state.metrics["treasury"] = 20.0
	assert_string_contains(sys.validate(ActionRequest.make("RECRUIT_COURTIER", {}, "char_bard_corvin"), state), "afford")
```

- [ ] **Step 3: Run to verify failure** (`-gselect=test_order_costs`).

- [ ] **Step 4: OrderCosts**

`scripts/engine/order_costs.gd`:

```gdscript
class_name OrderCosts
extends RefCounted
## Every order carries a cost (spec 2026-09-09 §3). A cost is a metric moved
## against its good direction, an opinion / relationship / attribute loss, or
## a world field moved against its good direction. Tone deltas and the kept
## promise pseudo-effect do not count. When an order carried none of its own,
## the action's row in data/order_costs.csv is charged. Engine-pure.

const EXEMPT := "none"

static func snapshot_opinions(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for id: String in state.characters:
		out[id] = (state.characters[id] as Character).opinion
	return out

static func has_cost(data: DataRepository, state: GameState, effects: Array, drift: Array,
		opinions_before: Dictionary) -> bool:
	for e in effects:
		var delta := float(e.get("delta", 0.0))
		match String(e.get("kind", "metric")):
			"metric":
				if int(data.metric_polarity.get(String(e.get("metric", "")), 0)) * delta < 0.0:
					return true
			"opinion", "relationship", "attribute":
				if delta < 0.0:
					return true
			"world":
				if WorldLedger.polarity_of(data, String(e.get("path", ""))) * delta < 0.0:
					return true
	for d in drift:
		if int(d.get("delta", 0)) < 0:
			return true
	for id in opinions_before:
		if state.characters.has(id) and (state.characters[id] as Character).opinion < int(opinions_before[id]):
			return true
	return false

## Gold an action's cost row would take, as a positive number (for affordability).
static func gold_of(data: DataRepository, action_code: String) -> float:
	var ops := _ops(data, action_code)
	var gold := 0.0
	for raw in ops.split(";", false):
		var p := raw.strip_edges().split(":")
		if p[0] == "gold" and p.size() > 1:
			gold += maxf(-float(p[1]), 0.0)
	return gold

static func _ops(data: DataRepository, action_code: String) -> String:
	var row: Dictionary = data.order_costs.get(action_code, {})
	var ops := String(row.get("cost", EXEMPT)).strip_edges()
	return "" if ops == EXEMPT or ops == "" else ops

static func always(data: DataRepository, action_code: String) -> bool:
	return String((data.order_costs.get(action_code, {}) as Dictionary).get("always", "0")) == "1"

## Apply the action's cost row; `target` replaces the literal "target" in an
## op so CHARACTER_PUNISH can charge the punished. [] for exempt actions.
static func charge(data: DataRepository, state: GameState, action_code: String, target: String) -> Array:
	var ops := _ops(data, action_code)
	if ops == "":
		return []
	if target != "":
		ops = ops.replace(":target:", ":%s:" % target)
	return EventEffects.apply(ops, state, data, "")

## The guarantee: charge the row when the order carried no cost of its own
## (always rows are charged by ActionSystem regardless). Charged results are
## appended to `effects` so narration prints them like any other effect.
static func ensure(data: DataRepository, state: GameState, effects: Array, drift: Array,
		opinions_before: Dictionary, action_code: String, target: String) -> Array:
	if has_cost(data, state, effects, drift, opinions_before):
		return []
	var charged := charge(data, state, action_code, target)
	effects.append_array(charged)
	return charged
```

`scripts/engine/action_system.gd`:
- `validate`: replace the affordability line with `if state.metrics["treasury"] < gold_cost(row) + OrderCosts.gold_of(data, req.action_code): return "Cannot afford %s (needs %d gold)" % [req.action_code, int(gold_cost(row) + OrderCosts.gold_of(data, req.action_code))]`.
- `execute`: first line after the assert: `var before := OrderCosts.snapshot_opinions(state)`. After the promise loop and before `state.event_state[...]`:

```gdscript
	# Every order carries a cost (spec 2026-09-09 §3): always-rows ride along
	# every time, the fallback row only when nothing above cost anything.
	if OrderCosts.always(data, req.action_code):
		effects.append_array(OrderCosts.charge(data, state, req.action_code, req.target))
	else:
		OrderCosts.ensure(data, state, effects, drift, before, req.action_code, req.target)
```

Run the import pass, then `-gselect=test_order_costs`, `-gselect=test_action_system`, `-gselect=test_concerns` (suggestions must still validate as affordable). Fix `test_action_system.gd` expectations only where an outcome now carries the extra cost entry.

- [ ] **Step 5: Commit**

```bash
./run_tests.sh
git add data/metric_polarity.csv data/order_costs.csv scripts/engine/order_costs.gd scripts/engine/action_system.gd scripts/engine/data_repository.gd tests/engine/test_order_costs.gd tests/engine/test_action_system.gd
git commit -m "feat(engine): every order carries a cost, explicit or hidden"
```

---

### Task 5: The two-part order call — config, prompt, validator, voicer

**Files:**
- Modify: `scripts/llm/openai_client.gd`, `.env.example`
- Modify: `scripts/llm/prompt_builder.gd`, `scripts/llm/response_validator.gd`, `scripts/llm/voicer.gd`
- Test: `tests/llm/test_llm_config.gd`, `test_prompt_builder.gd`, `test_response_validator.gd`, `test_voicer_fallback.gd`; `tests/fixtures/test_env`

**Interfaces:**
- Produces: config key `model_order` (`LLM_MODEL_ORDER`; `LLM_MODEL` sets it too; default `gpt-5.6-luna`); `PromptBuilder.order_prompts(player_text: String, speaker_id: String, report: TickReport, state: GameState, data: DataRepository) -> Dictionary {system, user}`; `ResponseValidator.parse_order(json_text: String, data: DataRepository, state: GameState) -> Dictionary {ok, error, narrative: String, actions: Array[ActionRequest], world: Array[{path, delta, reason, clamped}], world_rejected: Array[{path, error}], court_reaction}`; `Voicer.order(text, speaker_id, report, state, data, cb)`.

- [ ] **Step 1: Failing tests**

`tests/llm/test_llm_config.gd` — add `LLM_MODEL_ORDER=test-order-model` to `tests/fixtures/test_env` and:

```gdscript
func test_order_tier_reads_its_own_key_and_falls_back_to_llm_model() -> void:
	var cfg := OpenAIClient.load_config(FIXTURE_ENV, "user://does_not_exist.json")
	assert_eq(cfg["model_order"], "test-order-model")
	var bare := OpenAIClient.load_config("res://no_such.env", "user://no_such.json")
	assert_eq(bare["model_order"], bare["model_parse"], "defaults to the parse tier")
```

`tests/llm/test_prompt_builder.gd`:

```gdscript
func test_order_prompt_carries_persona_catalog_and_the_correlation_rule() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.order_prompts("raise the levies", "char_marshal", r, s, data)
	assert_string_contains(p["system"], "Ser Brandt of Harrow")
	assert_string_contains(p["system"], "LEVY_RAISE")
	assert_string_contains(p["system"], "\"narrative\"")
	assert_string_contains(p["system"], "\"impacts\"")
	assert_string_contains(p["system"], "metrics.grain")
	assert_string_contains(p["system"], "narrative claims no change")
	assert_eq(p["user"], "raise the levies")

func test_order_prompt_with_no_speaker_uses_the_herald() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.order_prompts("hm", "", r, s, data)
	assert_string_contains(p["system"], "herald")
```

`tests/llm/test_response_validator.gd`:

```gdscript
func _order(narrative: String, world: Array, actions: Array = []) -> String:
	return JSON.stringify({"narrative": narrative, "impacts": {"actions": actions, "world": world,
		"court_reaction": {"addressed": [], "tone": "neutral", "promises": []}}})

func test_order_parses_narrative_actions_and_world_impacts() -> void:
	var s := GameState.new_campaign(data, 42)
	var out := ResponseValidator.parse_order(_order("We march.",
		[{"path": "economy.kingdoms.player_realm.rural_population", "delta": -100, "reason": "levies"}],
		[{"action_code": "LEVY_RAISE", "params": {}, "target": ""}]), data, s)
	assert_true(out["ok"], out["error"])
	assert_eq(out["narrative"], "We march.")
	assert_eq(out["actions"][0].action_code, "LEVY_RAISE")
	assert_eq(out["world"].size(), 1)
	assert_eq(float(out["world"][0]["delta"]), -100.0)
	assert_false(out["world"][0]["clamped"])

func test_order_impacts_need_a_reason_a_listed_path_and_your_own_land() -> void:
	var s := GameState.new_campaign(data, 42)
	var foreign := ""
	for code: String in data.provinces:
		if String(data.provinces[code]["kingdom_code"]) != data.resolve_realm("player_realm"):
			foreign = code
			break
	var out := ResponseValidator.parse_order(_order("Words.", [
		{"path": "metrics.grain", "delta": 5},
		{"path": "metrics.no_such", "delta": 5, "reason": "x"},
		{"path": "metrics.tax_rate", "delta": 1, "reason": "x"},
		{"path": "economy.provinces.%s.rural_population" % foreign, "delta": -5, "reason": "x"},
		{"path": "metrics.grain", "delta": "lots", "reason": "x"},
	]), data, s)
	assert_true(out["ok"], "per-impact faults do not fail the reply")
	assert_eq(out["world"].size(), 0)
	assert_eq(out["world_rejected"].size(), 5)
	assert_string_contains(String(out["world_rejected"][0]["error"]), "reason")
	assert_string_contains(String(out["world_rejected"][2]["error"]), "engine")
	assert_string_contains(String(out["world_rejected"][3]["error"]), "yours")

func test_order_clamps_a_delta_beyond_the_cap() -> void:
	var s := GameState.new_campaign(data, 42)
	var out := ResponseValidator.parse_order(_order("Gold rains.",
		[{"path": "metrics.treasury", "delta": 5000, "reason": "a miracle"}]), data, s)
	assert_eq(float(out["world"][0]["delta"]), WorldLedger.llm_cap(data, "metrics.treasury"))
	assert_true(out["world"][0]["clamped"])

func test_order_narrative_is_required_unless_something_acts() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_false(ResponseValidator.parse_order(_order("", []), data, s)["ok"])
	assert_true(ResponseValidator.parse_order(_order("", [],
		[{"action_code": "SPY_MISSION", "params": {}, "target": ""}]), data, s)["ok"])
	var long := "x".repeat(2000)
	var out := ResponseValidator.parse_order(_order(long, []), data, s)
	assert_eq(out["narrative"].length(), int(data.bal("order_narrative_max_chars")))

## Older canned replies (and older tests) put actions at the top level; the
## validator still reads them so nothing regresses.
func test_order_accepts_the_flat_legacy_shape() -> void:
	var s := GameState.new_campaign(data, 42)
	var out := ResponseValidator.parse_order(JSON.stringify({"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"court_reaction": {"addressed": ["char_steward"], "tone": "respectful", "promises": []}}), data, s)
	assert_true(out["ok"])
	assert_eq(out["actions"][0].action_code, "TAX_RATE_ADJUST")
	assert_eq(out["court_reaction"]["tone"], "respectful")
```

`tests/llm/test_voicer_fallback.gd`:

```gdscript
func test_order_returns_both_parts_through_one_call() -> void:
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"narrative": "The rolls are cut.", "impacts": {"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"world": [], "court_reaction": {}}})
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	got = {}
	v.order("lower taxes", "char_steward", r, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_eq(fake.calls, 1, "one call carries narrative and impacts")
	assert_eq(got["narrative"], "The rolls are cut.")
	assert_eq(got["actions"][0].action_code, "TAX_RATE_ADJUST")
```

- [ ] **Step 2: Run to verify failure** (`-gselect=test_llm_config`, `test_prompt_builder`, `test_response_validator`, `test_voicer_fallback`).

- [ ] **Step 3: Implement**

`openai_client.gd`: default `"model_order": "gpt-5.6-luna"` in `load_config`'s cfg; in `_overlay_env` `"LLM_MODEL"` also sets `cfg["model_order"]`, add `"LLM_MODEL_ORDER": cfg["model_order"] = value`. Document the key in the `_overlay_env` comment and in `.env.example` (`#LLM_MODEL_ORDER=` under the per-tier overrides, "the two-part order call; defaults to the parse tier").

`prompt_builder.gd`:

```gdscript
## The single order call (spec 2026-09-09 §4): the engine-chosen speaker
## answers in character AND translates the words into impacts. Two parts,
## one reply, bound by the correlation rules below; the validator and the
## ledger clamp everything the model proposes.
static func order_prompts(player_text: String, speaker_id: String, report: TickReport,
		state: GameState, data: DataRepository) -> Dictionary:
	var persona := persona_context(speaker_id, state, data) if speaker_id != "" else \
		"the court herald — a neutral clerk who records the ruler's orders and answers plainly."
	var catalog := ""
	for code in data.actions:
		catalog += "- %s: %s\n" % [code, data.actions[code].get("notes", "")]
	var ids := ", ".join(state.characters.keys())
	var event_ctx := ""
	if not state.pending_event.is_empty():
		var choice_ids := []
		for ch in state.pending_event["choices"]:
			choice_ids.append("%s (%s)" % [ch["choice_id"], ch["label"]])
		event_ctx = ("\nAn event awaits a decision. To resolve it use action_code"
			+ " EVENT_CHOICE with params {\"choice_id\": one of: %s}.") % ", ".join(choice_ids)
	var system := """You roleplay one voice at a medieval royal court, speaking to the ruler. You are %s
The realm today (engine truth — quote these numbers, never invent others):
%s
You answer the ruler's words in character AND translate them into game effects.
Output ONLY a JSON object, no prose outside it, shaped exactly:
{"narrative": "1-3 sentences in your own voice",
 "impacts": {"actions": [{"action_code": "...", "params": {}, "target": ""}],
             "world": [{"path": "...", "delta": 0, "reason": "a few words"}],
             "court_reaction": {"addressed": [], "tone": "neutral", "promises": []}}}
Rules that bind the two parts together:
- Every world impact is something the narrative says happens; the narrative claims no change that is not in impacts.
- Prefer a legal action whenever one fits the order; use world impacts only for concrete consequences no action covers.
- Every impact carries a reason of a few words, in your voice.
- If the ruler only asks or converses, leave actions and world empty and let the narrative answer.
Legal action codes (use ONLY these):
%s
Fields you may move, with their caps (a delta beyond the cap is clamped; you may only move your own realm's fields):
%s
Character ids for target/addressed: %s
tone is one of respectful|neutral|curt|flattering|threatening|dismissive.%s
promise_code in promises MUST be one of the legal action codes above.
Current tick: %d.""" % [persona, realm_facts(state), catalog,
		WorldLedger.prompt_catalog(data, state), ids, event_ctx, report.tick]
	return {"system": system, "user": player_text}
```

`response_validator.gd`: refactor `parse` into `_parse_actions(raw_actions, data) -> Dictionary {ok, error, actions}` and `_parse_reaction(cr, data) -> Dictionary {ok, error, reaction}` (same checks as today; `parse` composes them and keeps its return shape). Add:

```gdscript
## The two-part order reply (spec 2026-09-09 §4). Per-impact faults are
## reported in world_rejected, never fatal; malformed JSON or an unknown
## action still fails the whole reply. The flat legacy shape (actions at the
## top level) is accepted so older canned replies keep working.
static func parse_order(json_text: String, data: DataRepository, state: GameState) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg, "narrative": "", "actions": [], "world": [],
			"world_rejected": [], "court_reaction": _neutral()}
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		return fail.call("not valid JSON")
	var impacts = parsed.get("impacts", parsed)
	if not impacts is Dictionary:
		return fail.call("impacts must be an object")
	var acts := _parse_actions(impacts.get("actions", []), data)
	if not acts["ok"]:
		return fail.call(acts["error"])
	var cr := _parse_reaction(impacts.get("court_reaction", null), data)
	if not cr["ok"]:
		return fail.call(cr["error"])
	var narrative := String(parsed.get("narrative", "")).strip_edges()
	var cap := int(data.bal("order_narrative_max_chars"))
	if narrative.length() > cap:
		narrative = narrative.substr(0, cap)
	var world: Array = []
	var world_rejected: Array = []
	var raw_world = impacts.get("world", [])
	if raw_world is Array:
		for imp in raw_world:
			var checked := _check_impact(imp, data, state)
			if checked.has("error"):
				world_rejected.append(checked)
			else:
				world.append(checked)
	if narrative == "" and acts["actions"].is_empty() and world.is_empty():
		return fail.call("an empty reply")
	return {"ok": true, "error": "", "narrative": narrative, "actions": acts["actions"],
		"world": world, "world_rejected": world_rejected, "court_reaction": cr["reaction"]}

static func _check_impact(imp, data: DataRepository, state: GameState) -> Dictionary:
	if not imp is Dictionary:
		return {"path": "", "error": "malformed impact"}
	var path := String(imp.get("path", ""))
	var reason := String(imp.get("reason", "")).strip_edges()
	if reason == "":
		return {"path": path, "error": "an impact needs a reason"}
	var raw_delta = imp.get("delta", null)
	if not (raw_delta is float or raw_delta is int):
		return {"path": path, "error": "delta must be a number"}
	var row := WorldLedger.schema_for(data, path)
	if row.is_empty():
		return {"path": path, "error": "no such field"}
	if String(row.get("type", "")) == "enum":
		return {"path": path, "error": "not a number the court can move"}
	var cap := WorldLedger.llm_cap(data, path)
	if cap <= 0.0:
		return {"path": path, "error": "engine-only field"}
	if not WorldLedger.belongs_to_player(data, state, path):
		return {"path": path, "error": "not yours to move"}
	var delta := float(raw_delta)
	var clamped := absf(delta) > cap
	return {"path": path, "delta": clampf(delta, -cap, cap), "reason": reason, "clamped": clamped}
```

`voicer.gd`:

```gdscript
## The two-part order call (spec 2026-09-09 §4): one request returns the
## speaker's narrative and the impacts. Busy or failing degrades exactly as
## the parse does — no state moves without a validated reply.
func order(text: String, speaker_id: String, report: TickReport, state: GameState,
		data: DataRepository, cb: Callable) -> void:
	if _busy:
		cb.call({"ok": false, "error": "voicer busy", "narrative": "", "actions": [],
			"world": [], "world_rejected": [], "court_reaction": {}, "degraded": true})
		return
	_busy = true
	var p := PromptBuilder.order_prompts(text, speaker_id, report, state, data)
	client.completed.connect(func(ok: bool, raw: String):
		_busy = false
		if not ok:
			cb.call({"ok": false, "error": "couriers unavailable", "narrative": "", "actions": [],
				"world": [], "world_rejected": [], "court_reaction": {}, "degraded": true})
			return
		var out := ResponseValidator.parse_order(raw, data, state)
		out["degraded"] = false
		cb.call(out),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"], String(_config["model_order"]), true)
```

- [ ] **Step 4: Run, then commit**

```bash
./run_tests.sh
git add scripts/llm .env.example tests/llm tests/fixtures/test_env
git commit -m "feat(llm): one order call returns a narrative and the impacts it describes"
```

---

### Task 6: OrderPipeline, Game, screens, tabs, docs

**Files:**
- Create: `scripts/engine/order_pipeline.gd`
- Modify: `scripts/ui/game.gd`, `scripts/ui/court_screen.gd`, `scripts/ui/conversation_scene.gd`, `scripts/ui/info_screen.gd`
- Modify: `CLAUDE.md`, `PRD.md`
- Test: `tests/engine/test_order_pipeline.gd` (create), `tests/ui/test_court_screen.gd`, `tests/ui/test_conversation_scene.gd`

**Interfaces:**
- Produces: `OrderPipeline.apply_order(data, state, engine: TickEngine, actions: Array, world: Array, court_reaction: Dictionary, source: String) -> Dictionary {executed, rejected, world_effects, world_rejected, cost_effects, ledger: Array[String]}`; `OrderPipeline.describe_effects(effects: Array, state) -> String`; `Game.submit_free_text` result gains `ledger: Array[String]`, `world_effects`, `world_rejected`, and `reply` is present whenever the narrative is non-empty.

- [ ] **Step 1: Failing tests**

`tests/engine/test_order_pipeline.gd`:

```gdscript
extends GutTest
## One order end to end (spec 2026-09-09 §4.3): actions, world impacts, the
## court reaction, the cost rule, and the ledger lines the screens print.

var data: DataRepository
var state: GameState
var engine: TickEngine

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)
	engine = TickEngine.new(data)
	engine.advance(state)

func test_actions_and_impacts_apply_and_print() -> void:
	var grain: float = state.metrics["grain"]
	var out := OrderPipeline.apply_order(data, state, engine,
		[ActionRequest.make("SPY_MISSION")],
		[{"path": "metrics.grain", "delta": 10.0, "reason": "a gift of grain", "clamped": false}],
		{"addressed": [], "tone": "neutral", "promises": []}, "order")
	assert_eq(out["executed"].size(), 1)
	assert_eq(state.metrics["grain"], grain + 10.0)
	assert_eq(out["world_effects"].size(), 1)
	assert_true(out["cost_effects"].is_empty(), "the action's own gold was the cost")
	var joined := "\n".join(out["ledger"])
	assert_string_contains(joined, "grain +10")
	assert_string_contains(joined, "a gift of grain")
	assert_string_contains(joined, "treasury")

func test_a_pure_impact_order_without_a_cost_is_charged_the_generic_cost() -> void:
	var gold: float = state.metrics["treasury"]
	var out := OrderPipeline.apply_order(data, state, engine, [],
		[{"path": "metrics.peasant_contentment", "delta": 2.0, "reason": "a feast", "clamped": false}],
		{"addressed": [], "tone": "neutral", "promises": []}, "order")
	assert_eq(out["cost_effects"].size(), 1)
	assert_lt(state.metrics["treasury"], gold)
	assert_string_contains("\n".join(out["ledger"]), "clerks")

func test_a_pure_impact_order_with_a_cost_is_not_charged_twice() -> void:
	var gold: float = state.metrics["treasury"]
	OrderPipeline.apply_order(data, state, engine, [],
		[{"path": "metrics.treasury", "delta": -20.0, "reason": "alms", "clamped": false}],
		{"addressed": [], "tone": "neutral", "promises": []}, "order")
	assert_eq(state.metrics["treasury"], gold - 20.0)

func test_rejected_impacts_and_actions_are_named_in_the_ledger() -> void:
	var out := OrderPipeline.apply_order(data, state, engine,
		[ActionRequest.make("TAX_RATE_ADJUST", {"delta": 9})],
		[{"path": "metrics.grain", "delta": 1.0, "reason": "", "clamped": false}],
		{"addressed": [], "tone": "neutral", "promises": []}, "order")
	assert_eq(out["rejected"].size(), 1)
	assert_eq(out["world_rejected"].size(), 1)
	assert_string_contains("\n".join(out["ledger"]), "struck")

func test_event_choice_rides_through_the_pipeline() -> void:
	engine.events._fire("ev_01", state)
	var choice: String = state.pending_event["choices"][0]["choice_id"]
	var out := OrderPipeline.apply_order(data, state, engine,
		[ActionRequest.make("EVENT_CHOICE", {"choice_id": choice})], [],
		{"addressed": [], "tone": "neutral", "promises": []}, "order")
	assert_eq(String(out["executed"][0]["action_code"]), "EVENT_CHOICE")
	assert_true(state.pending_event.is_empty())
```

`tests/ui/test_court_screen.gd` — add:

```gdscript
## The two-part order (spec 2026-09-09 §4): the speaker's narrative prints
## under their name, then the ledger lines that actually applied.
func test_free_text_prints_the_narrative_and_the_ledger() -> void:
	Game.start_campaign(42)
	var screen := _screen()
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"narrative": "The granaries open a crack.",
		"impacts": {"actions": [], "world": [{"path": "metrics.grain", "delta": 5,
		"reason": "a gift"}], "court_reaction": {}}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	var grain: float = Game.state.metrics["grain"]
	screen.free_text.text_submitted.emit("open the granaries a little")
	await wait_frames(3)
	assert_eq(Game.state.metrics["grain"], grain + 5.0)
	var texts: Array[String] = []
	for l in screen.log_box.get_children():
		texts.append((l as Label).text)
	var joined := "\n".join(texts)
	assert_string_contains(joined, "The granaries open a crack.")
	assert_string_contains(joined, "grain +5")
	assert_string_contains(joined, "clerks", "a gift with no cost is charged the generic cost")
```

Update the existing conversational test in `test_court_screen.gd` that expected a second (converse) call: with the single call, the canned reply's `narrative` is the spoken line; assert on it and on `fake.calls == 1`. Do the same in `tests/ui/test_conversation_scene.gd` for its free-text reply test (canned `{"narrative": "...", "impacts": {...}}`, expect `_say` to print the narrative under the speaker and the ledger lines under "Ledger").

- [ ] **Step 2: Run to verify failure** (`-gselect=test_order_pipeline`, `-gselect=test_court_screen`, `-gselect=test_conversation_scene`).

- [ ] **Step 3: OrderPipeline**

`scripts/engine/order_pipeline.gd`:

```gdscript
class_name OrderPipeline
extends RefCounted
## One order end to end (spec 2026-09-09 §4.3): execute the actions through
## ActionSystem, apply the validated world impacts through the ledger, apply
## the court reaction, charge the generic cost when a pure-impact order cost
## nothing, and write the ledger lines the screens print beneath the
## narrative — so what the court SAID and what the record SHOWS sit together.
## Engine-pure; the caller emits state_changed.

static func apply_order(data: DataRepository, state: GameState, engine: TickEngine,
		actions: Array, world: Array, court_reaction: Dictionary, source: String) -> Dictionary:
	var executed: Array = []
	var rejected: Array = []
	for req: ActionRequest in actions:
		if req.action_code == "EVENT_CHOICE":
			var ev_out := engine.events.apply_choice(String(req.params.get("choice_id", "")), state)
			if ev_out.is_empty():
				rejected.append({"request": req, "error": "no such choice awaits"})
			else:
				executed.append({"action_code": "EVENT_CHOICE", "ok": true,
					"effects": ev_out["effects"], "notes": String(ev_out["label"]),
					"drift": ev_out["drift"], "event_id": String(ev_out["event_id"]),
					"choice_id": String(ev_out["choice_id"])})
			continue
		var err := engine.actions.validate(req, state)
		if err != "":
			rejected.append({"request": req, "error": err})
		else:
			executed.append(engine.actions.execute(req, state))
	var world_effects: Array = []
	var world_rejected: Array = []
	for imp in world:
		var out := WorldLedger.apply(data, state, String(imp["path"]), float(imp["delta"]),
			String(imp["reason"]), source)
		if out.has("error"):
			world_rejected.append({"path": String(imp["path"]), "error": String(out["error"])})
		else:
			out["kind"] = "world"
			world_effects.append(out)
	engine.actions.apply_court_reaction(court_reaction, state)
	var cost_effects: Array = []
	if executed.is_empty() and not world_effects.is_empty() \
			and not OrderCosts.has_cost(data, state, world_effects, [], {}):
		cost_effects = OrderCosts.charge(data, state, "generic_order", "")
	var ledger: Array[String] = []
	for o in executed:
		var line := describe_effects(o["effects"], state)
		if line != "":
			ledger.append("%s: %s" % [String(o["notes"]), line])
	if not world_effects.is_empty():
		ledger.append(describe_effects(world_effects, state))
	if not cost_effects.is_empty():
		ledger.append(describe_effects(cost_effects, state))
	for r in rejected:
		ledger.append("the clerk struck %s (%s)" % [String(r["request"].action_code), String(r["error"])])
	for r in world_rejected:
		ledger.append("the clerk struck %s (%s)" % [String(r["path"]), String(r["error"])])
	return {"executed": executed, "rejected": rejected, "world_effects": world_effects,
		"world_rejected": world_rejected, "cost_effects": cost_effects, "ledger": ledger}

## "treasury −40: surveyors hired, grain +5: a gift" — every effect with its
## reason, whatever its kind, so the numbers and their causes read together.
static func describe_effects(effects: Array, state: GameState) -> String:
	var parts: Array[String] = []
	for e in effects:
		var delta := float(e.get("delta", 0.0))
		var what := ""
		match String(e.get("kind", "metric")):
			"metric":
				var m := String(e.get("metric", ""))
				if m == "promise":
					continue
				what = m.replace("_", " ")
			"opinion":
				what = _name(state, String(e.get("character_id", ""))) + " opinion"
			"attribute":
				what = "%s %s" % [_name(state, String(e.get("character_id", ""))), String(e.get("attribute", ""))]
			"relationship":
				what = "%s → %s" % [_name(state, String(e.get("from", ""))), _name(state, String(e.get("to", "")))]
			"world":
				what = String(e.get("path", "")).get_slice(".", 1) + " " \
					+ String(e.get("path", "")).get_slice(".", 3).replace("_", " ")
			_:
				continue
		var num := ("%+d" % roundi(delta)) if delta == floorf(delta) else ("%+.1f" % delta)
		var reason := String(e.get("reason", ""))
		parts.append("%s %s%s" % [what, num, (": " + reason) if reason != "" else ""])
	return ", ".join(parts)

static func _name(state: GameState, id: String) -> String:
	return (state.characters[id] as Character).display_name if state.characters.has(id) else id
```

- [ ] **Step 4: Game**

Replace the body of `submit_free_text` after the `AgentMemory` loop and `_ensure_llm()`:

```gdscript
	var speaker := _order_speaker(text, speaker_hint, heard_by)
	voicer.order(text, speaker, current_report, state, data,
		func(res: Dictionary):
			if not res["ok"]:
				cb.call({"ok": false, "executed": [], "rejected": [], "error": res["error"]})
				return
			var out := OrderPipeline.apply_order(data, state, engine, res["actions"],
				res["world"], res["court_reaction"], "order")
			state_changed.emit()
			var result := {"ok": true, "executed": out["executed"], "rejected": out["rejected"],
				"error": "", "ledger": out["ledger"], "world_effects": out["world_effects"],
				"world_rejected": out["world_rejected"]}
			var narrative := String(res.get("narrative", ""))
			if narrative != "":
				var reply := {"speaker": _speaker_name(speaker), "speaker_id": speaker,
					"text": narrative, "degraded": false}
				_remember_reply(reply, heard_by)
				result["reply"] = reply
			cb.call(result))
```

Add:

```gdscript
func _speaker_name(id: String) -> String:
	return (state.characters[id] as Character).display_name if state.characters.has(id) else "Herald"

## Who answers, chosen BEFORE the call so the model speaks in one persona:
## the character the player faces; else someone present whose name or seat
## the text mentions; else the Chancellor if present; else anyone present;
## else "" for the herald. Only someone at the player's location may answer
## (user ruling 2026-08-30).
func _order_speaker(text: String, hint: String, audience: Array) -> String:
	var present: Array = audience if not audience.is_empty() \
		else LocationSystem.occupants(data, state, state.current_location)
	if hint in present:
		return hint
	var lower := text.to_lower()
	for id in present:
		var c: Character = state.characters.get(String(id))
		if c == null or String(id) == "you":
			continue
		for token in c.display_name.split(" ", false):
			if token.length() > 3 and lower.contains(token.to_lower()):
				return String(id)
		if c.seat != "" and lower.contains(c.seat.to_lower()):
			return String(id)
	var chancellor := String(state.council.get("chancellor", ""))
	if chancellor in present:
		return chancellor
	return String(present[0]) if not present.is_empty() else ""
```

Delete `_converse_speaker` and `_consult_target` (the only callers were in the old body). Keep `_remember_reply`.

- [ ] **Step 5: Screens and tabs**

`court_screen.gd` `_on_free_text_submitted` callback: after the `rejected` loop, keep the `reply` print, then `for line in res.get("ledger", []): _log("Ledger", String(line))`. Drop the `for rej in res["rejected"]` loop (the ledger names them). `conversation_scene.gd` `_on_free_text` callback: after the reply print, `for line in res.get("ledger", []): _say("Ledger", String(line))`; keep the `elif spoken == "": _say("Herald", "So noted.")` fallback only when the ledger is also empty.

`info_screen.gd` `_rows_for`: in `"REALM"` append `["Urban population", str(int(WorldLedger.value_of(Game.data, Game.state, "economy.kingdoms.player_realm.urban_population")))]` and the rural line when the value is not null; in `"MILITARY"` append one row per unit in `Game.data.world_table("military", "unit_types")` reading `military.kingdoms.player_realm.<unit_code>` when not null.

- [ ] **Step 6: Docs**

`CLAUDE.md` invariants: amend 1 to end "…Never let the model invent actions. The model may also propose **world deltas**, but only on paths listed in `data/world_schema.csv`, each clamped to that path's `llm_cap` and carrying a reason (owner ruling 2026-09-09); the engine still picks the speaker and applies everything." Amend 2's last sentence to "LLM output enters the engine only as validated action codes, clamped enums (e.g. `tone` deltas capped at ±3), and schema-listed world deltas clamped to their caps." Add to the data list: `world_schema.csv`, `metric_polarity.csv`, `order_costs.csv`. Add a bullet under Architecture invariants: "**Every order carries a cost.** `OrderCosts` guarantees an explicit (gold, grain, population) or hidden (opinion, relationship, attribute) cost per executed order from `data/order_costs.csv`; `COUNCIL_CONSULT` and `EVENT_CHOICE` are the listed exemptions." `PRD.md` BG-4: "…parsed by LLM into `{narrative, impacts: {actions, world, court_reaction}}` against a strict schema; the engine validates every action and clamps every world delta to `world_schema.csv`". §8 table: the parse row becomes "Order (narrative + impacts)" on the order tier, replacing the parse and converse rows.

- [ ] **Step 7: Run, then commit**

```bash
./run_tests.sh
git add scripts/engine/order_pipeline.gd scripts/ui/game.gd scripts/ui/court_screen.gd scripts/ui/conversation_scene.gd scripts/ui/info_screen.gd tests/engine/test_order_pipeline.gd tests/ui/test_court_screen.gd tests/ui/test_conversation_scene.gd CLAUDE.md PRD.md
git commit -m "feat(order): narrative and ledger together — orders apply through one pipeline"
```

---

### Task 7: Province view

**Files:**
- Modify: `scripts/engine/map_ownership.gd`, `scripts/ui/world_map_view.gd`, `data/balance.csv`
- Test: `tests/engine/test_map_ownership.gd`, `tests/ui/test_world_map_view.gd`

**Interfaces:**
- Produces: `MapOwnership.seams_of(data, state, kingdom_code) -> Array` of two-point `PackedVector2Array`; `WorldMapView.show_provinces: bool`, `toggle_provinces() -> void`, `province_chip() -> Button` (test seam), `visible_seam_count() -> int` (test seam).

- [ ] **Step 1: Balance values**

```csv
map_province_min_scale,0.6,world map: screen px per native map px at/above which the province view draws seams
map_province_line_alpha,0.55,world map: opacity of province seams in the province view
map_province_line_width,1.0,world map: width of province seams in screen px
map_province_dash_px,4.0,world map: dash length of province seams in screen px
```

- [ ] **Step 2: Failing tests**

`tests/engine/test_map_ownership.gd`:

```gdscript
## Province seams (spec 2026-09-09 §5): the edges two held provinces share,
## and never an edge on the kingdom's outline.
func test_seams_are_shared_edges_inside_the_kingdom() -> void:
	var seams := MapOwnership.seams_of(data, state, _player())
	assert_gt(seams.size(), 0, "a kingdom with several provinces has seams")
	var outline_edges: Dictionary = {}
	for loop: PackedVector2Array in MapOwnership.outline_of(data, state, _player()):
		for i in loop.size():
			outline_edges[_edge_key(loop[i], loop[(i + 1) % loop.size()])] = true
	for seg: PackedVector2Array in seams:
		assert_eq(seg.size(), 2, "a seam is one segment")
		assert_false(outline_edges.has(_edge_key(seg[0], seg[1])), "seams are never outline edges")

func test_a_transfer_removes_the_moved_provinces_seams_from_the_old_owner() -> void:
	var before := MapOwnership.seams_of(data, state, _player()).size()
	var mine := MapOwnership.provinces_of(data, state, _player())
	MapOwnership.set_owner(data, state, mine[0], _raider(), "raid")
	assert_lt(MapOwnership.seams_of(data, state, _player()).size(), before)

func _edge_key(a: Vector2, b: Vector2) -> String:
	var ka := "%d,%d" % [roundi(a.x * 100.0), roundi(a.y * 100.0)]
	var kb := "%d,%d" % [roundi(b.x * 100.0), roundi(b.y * 100.0)]
	return ka + "|" + kb if ka < kb else kb + "|" + ka
```

`tests/ui/test_world_map_view.gd`:

```gdscript
## Province view (user request 2026-09-09): a toggle draws every kingdom's
## internal province seams as light dashed lines, above a minimum zoom.
func test_province_view_toggles_by_chip_and_key() -> void:
	var v := _view()
	await wait_frames(2)
	assert_false(v.show_provinces, "off by default")
	v.province_chip().pressed.emit()
	assert_true(v.show_provinces, "the chip turns it on")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_P
	v._gui_input(key)
	assert_false(v.show_provinces, "P turns it off again")

func test_province_seams_draw_only_when_zoomed_in_enough() -> void:
	var v := _view()
	await wait_frames(2)
	v.show_provinces = true
	v._zoom_at(v.size / 2.0, 0.00001)
	assert_eq(v.visible_seam_count(), 0, "zoomed out, no seams")
	v._zoom_at(v.size / 2.0, 1000.0)
	assert_gt(v.visible_seam_count(), 0, "zoomed in, seams on screen")
	v.show_provinces = false
	assert_eq(v.visible_seam_count(), 0, "off means none")
```

- [ ] **Step 3: Run to verify failure** (`-gselect=test_map_ownership`, `-gselect=test_world_map_view`).

- [ ] **Step 4: MapOwnership**

Refactor `_merge_loops` so the edge count is reusable:

```gdscript
static var _seam_cache: Dictionary = {}

## The seams inside a kingdom: every edge walked by exactly two of the loops
## of the provinces it holds now, as one two-point segment each. Cached with
## the outlines and dropped with them.
static func seams_of(data: DataRepository, state: GameState, kingdom_code: String) -> Array:
	var version := 0 if state == null else state.province_owner.size()
	if _cache_owner_version != version:
		_outline_cache.clear()
		_seam_cache.clear()
		_cache_owner_version = version
	if _seam_cache.has(kingdom_code):
		return _seam_cache[kingdom_code]
	var counted := _count_edges(_held_loops(data, state, kingdom_code))
	var out: Array = []
	for e in counted["order"]:
		if int(counted["count"][e]) == 2:
			out.append(PackedVector2Array([counted["point"][e[0]], counted["point"][e[1]]]))
	_seam_cache[kingdom_code] = out
	return out

static func _count_edges(loops: Array) -> Dictionary:
	var edge_count: Dictionary = {}
	var edge_order: Array = []
	var point_of: Dictionary = {}
	for loop: PackedVector2Array in loops:
		for i in loop.size():
			var a := _key(loop[i])
			var b := _key(loop[(i + 1) % loop.size()])
			if a == b:
				continue
			point_of[a] = loop[i]
			point_of[b] = loop[(i + 1) % loop.size()]
			var e := _edge(a, b)
			if edge_count.has(e):
				edge_count[e] = int(edge_count[e]) + 1
			else:
				edge_count[e] = 1
				edge_order.append(e)
	return {"count": edge_count, "order": edge_order, "point": point_of}
```

`_merge_loops` starts with `var counted := _count_edges(loops)` and reads `counted["count"]`, `counted["order"]`, `counted["point"]` in place of its own three locals. `invalidate()` also clears `_seam_cache`.

- [ ] **Step 5: WorldMapView**

Add after the constants:

```gdscript
## Province view (user request 2026-09-09): every kingdom's internal seams as
## light dashed lines, computed from the provinces it holds NOW, so they
## follow conquest where the render's printed dots cannot.
const DEV_PROVINCE_KEY := KEY_P
var show_provinces := false:
	set(v):
		show_provinces = v
		if _province_chip != null:
			_province_chip.button_pressed = v
		queue_redraw()
var _province_chip: Button
```

In `_ready` before `_build_tooltip()`:

```gdscript
	_province_chip = Button.new()
	_province_chip.name = "ProvinceChip"
	_province_chip.text = "PROVINCES"
	_province_chip.toggle_mode = true
	_province_chip.focus_mode = Control.FOCUS_NONE
	_province_chip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_province_chip.add_theme_font_size_override("font_size", 8)
	_province_chip.position = Vector2(6, 6)
	_province_chip.pressed.connect(toggle_provinces)
	add_child(_province_chip)
```

Public API and drawing:

```gdscript
func toggle_provinces() -> void:
	show_provinces = not show_provinces

func province_chip() -> Button:
	return _province_chip

## The seam segments the province view would draw right now.
func _visible_seams() -> Array:
	if not show_provinces or _map_texture == null \
			or view_scale() < Game.data.bal("map_province_min_scale"):
		return []
	var frame := Rect2(Vector2.ZERO, size)
	var out: Array = []
	for code: String in Game.data.kingdoms:
		for seg: PackedVector2Array in MapOwnership.seams_of(Game.data, Game.state, code):
			var a := map_to_screen(seg[0])
			var b := map_to_screen(seg[1])
			if frame.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(1.0)):
				out.append(PackedVector2Array([a, b]))
	return out

func visible_seam_count() -> int:
	return _visible_seams().size()

func _draw_province_seams() -> void:
	var color := UiPalette.GOLD
	color.a = Game.data.bal("map_province_line_alpha")
	var width := Game.data.bal("map_province_line_width")
	var dash := Game.data.bal("map_province_dash_px")
	for seg: PackedVector2Array in _visible_seams():
		draw_dashed_line(seg[0], seg[1], color, width, dash, true)
```

Call `_draw_province_seams()` in `_draw` after `_draw_territory_tint()`. In `_gui_input`, beside the T key: `if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == DEV_PROVINCE_KEY: toggle_provinces(); return`. The chip must not steal the map's mouse: `_province_chip.mouse_filter = Control.MOUSE_FILTER_STOP` is the default and correct (clicks on it go to it; the map underneath ignores them).

- [ ] **Step 6: Run, then commit**

```bash
./run_tests.sh
git add data/balance.csv scripts/engine/map_ownership.gd scripts/ui/world_map_view.gd tests/engine/test_map_ownership.gd tests/ui/test_world_map_view.gd
git commit -m "feat(map): province view — light dashed seams that follow conquest"
```

---

## Self-review

- **Spec coverage:** §1 layout, alignment, and engine alignment → Tasks 1 and 3; §2 ledger, schema, state, ops, attribute log → Tasks 2 and 3; §3 costs → Task 4; §4 output shape, correlation, pipeline, screens, tabs → Tasks 5 and 6; §5 province view → Task 7; balance additions split across Tasks 2, 7; docs → Tasks 1 and 6; tests listed per task.
- **Placeholders:** none; every step carries its code or its exact command.
- **Type consistency:** `world_table/world_row` (Task 1) used by Tasks 2–6; `WorldLedger.apply` returns `{path, delta, value, reason, source}` and OrderPipeline tags it `kind: "world"` before `describe_effects`; `OrderCosts.charge` returns EventEffects results (`kind`, `reason`); `parse_order` world entries carry `path, delta, reason, clamped`, which `apply_order` reads.
