# LEDGER Galaxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redraw the LEDGER as one galaxy — every object the crown knows of a small bright star in its tab's coloured cluster on a warm black night, links shading between clusters, the economy counted by province, with a flat 2D view — without changing what the LEDGER means, costs or orders.

**Architecture:** A pure engine read (`Ledger.galaxy`) turns the live state into one snapshot of the whole realm (instances by a worklist of egos, manors / buildings / towns folded into their provinces). A pure force layout (`LedgerGalaxyLayout`) places the stars by cluster anchors, warm-started and stepped a few passes a frame. The view draws the stars as one MultiMesh, the links as one camera-facing ribbon mesh (`LedgerLinkMesh` + `link.gdshader`), a haze per cluster and a procedural night sky, all in its own SubViewport environment with glow; the screen maps tabs to clusters, double-click opens a province, and a button lays the chart flat.

**Tech Stack:** Godot 4.7, typed GDScript, Forward+, GUT.

**Spec:** `docs/superpowers/specs/2026-09-30-ledger-galaxy-design.md` (and, for what the LEDGER means, `docs/superpowers/specs/2026-09-30-ledger-ontology-design.md`).

## Global Constraints

- Typed GDScript everywhere (type hints on vars, params, returns); `snake_case` files and functions, `PascalCase` classes.
- Nothing under `scripts/ledger3d/` names `Game.` (a test scans for it); the engine (`scripts/engine/`) stays pure `RefCounted`, no nodes, no clock, no RNG.
- Every look number is a `data/balance.csv` `ledger_*` row, every colour a `data/ledger_palette.csv` row; `.tres` materials hold a shader and nothing else — values are bound at load.
- Palette D, exactly: `sky_top #120E0B`, `sky_bottom #070605`, `nebula_a #3A2A1A`, `nebula_b #1A2230`, `stars #F0E2C4`, `cluster_economy #D4A24C`, `cluster_war #C24A3C`, `cluster_court #9066C0`, `cluster_intelligence #5E8CCB`.
- The economy's smallest unit is the PROVINCE: `manor`, `building`, `town` fold into their province (live state: `MapManors.province_of(repo, cell, state)`, `MarketSystem.province_of_burg(repo, state, burg)`) unless that province is OPENED.
- Every fade is PERCEIVED opacity: the alpha drawn is `ink × pow(fade, 2.2)` (Forward+ blends in linear light).
- A colour passed per VERTEX or per INSTANCE is sRGB and is turned linear in the shader (the `border_line.gdshader` formula).
- Snapshot ≤ 60 ms warm on the default pack after six months of play; the layout spends ≤ `ledger_galaxy_ms_per_frame` (4) ms a frame while settling and nothing once settled.
- Replies to the owner are Chinese; everything in the repo is English.
- One test file: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/<dir>/<file>.gd -gexit` (add `-gpre_run_script=res://tests/pre_run.gd` for `tests/ui/` and `tests/ledger3d/`). Full suite: `./run_tests.sh`; its only accepted failure is `tests/map3d/test_map3d_layers.gd::test_a_camera_move_refreshes_the_houses` (needs a git-ignored built world).
- After adding a `class_name`, run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` once so the class is registered.
- Never shoot a 3D screenshot with `--headless` (it hangs).
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; stage only the task's own files (never `project.godot`, `.claude/settings.local.json`, untracked `assets/`, `claude-skills/`, or `docs/superpowers/specs/2026-09-28-intelligence-layer-alignment.md`).

## Review Focus

1. A province changes hands or a manor is annexed while the LEDGER is open → the folded stars follow the live state on the next refresh (Task 2: `test_an_annexed_manor_folds_into_its_new_province`).
2. The selected star vanishes on a refresh (a courier arrives, a report ages out) → the selection clears, the left column's LEDGER card closes, nothing errors (Task 8: `test_a_vanished_selection_clears`; Task 9: `test_a_vanished_selection_takes_its_card`).
3. Folded manors of mixed Intel levels (a controlled province next to a province known only in words) → a merged figure never adds words to numbers; it becomes words at the worse level (Task 2: `test_flows_merge_only_within_one_level`).
4. Switching 2D ↔ 3D while the chart is still settling or a star is pinned → the pin survives and a click picks the star under the pointer in the orthographic view (Task 8: `test_a_star_is_picked_in_3d_and_in_2d`).
5. A fractional window scale → link widths are in real screen px (`px_per_dist` uses the SubViewport's own px height) and picks use `LedgerPick.screen_to_viewport` (Task 8: `test_link_width_uniform_follows_the_viewport`).

## Files

| File | Change | Responsibility |
|---|---|---|
| `data/ledger_object_types.csv` | modify | + `cluster`, `fold_to`, `star` columns |
| `data/ledger_link_types.csv` | modify | + `look` column |
| `data/ledger_static_nodes.csv`, `data/ledger_static_links.csv` | create (Task 3) | single nodes and edges written down (spec §3b) |
| `data/ledger_clusters.csv` | create | cluster → label, palette key, 3D and 2D anchors |
| `data/ledger_palette.csv` | modify | palette D keys; retire disc / sphere keys (Task 10) |
| `data/balance.csv` | modify | `ledger_galaxy_*`, `ledger_star_*`, `ledger_link_*`, `ledger_haze_*` …; retire disc / layer / thread keys (Task 10) |
| `scripts/engine/data_repository.gd` | modify | load the two new columns and `ledger_clusters` |
| `scripts/engine/ledger.gd` | modify | `galaxy()`, `_fold_target`, `_merge_into`; `validate` checks clusters |
| `scripts/engine/ledger_resolvers.gd` | modify | ONE house → manors index per memo |
| `scripts/ledger3d/ledger_galaxy_layout.gd` | create | pure force layout (Task 3) |
| `scripts/ledger3d/ledger_link_mesh.gd` | create | pure ribbon arrays (Task 4) |
| `scenes/ledger/link.gdshader`, `star.gdshader`, `sky.gdshader`, `haze.gdshader` | create | the look (Tasks 4–5) |
| `scenes/ledger/materials/*.tres` | create | shader-only materials |
| `scenes/ledger/ledger_view.tscn` | modify | environment with sky and glow; Stars / Links / Haze / Ring nodes |
| `scripts/ledger3d/ledger_view_3d.gd` | rewrite | the galaxy view (Task 6) |
| `scripts/ledger3d/ledger_hud.gd` | modify | cluster titles, name rules, star obstacles (Task 7) |
| `scripts/ui/ledger_screen.gd`, `scenes/ledger_screen.tscn` | modify | tabs → clusters, open a province, 2D/3D (Task 8) |
| `scripts/ui/game_root.gd` | modify | an audit letter lands on its flow's cluster |
| `tools/snapshot_screen.gd` | modify | `--ledger CLUSTER`, `--ledger-select ID`, `--ledger-open CODE`, `--ledger-mode 2d` |
| `scripts/ledger3d/ledger_layout.gd`, `scenes/ledger/disc.gdshader`, `scenes/ledger/thread.gdshader` | delete (Task 10) | retired |
| `CLAUDE.md`, ontology spec, `.claude/skills/visual-review/taste.md` | modify (Task 10) | the record |

---

### Task 1: Clusters and folding as data

**Files:**
- Modify: `data/ledger_object_types.csv`, `data/ledger_link_types.csv`, `data/ledger_palette.csv`, `data/balance.csv`, `scripts/engine/data_repository.gd`, `scripts/engine/ledger.gd` (`validate`)
- Create: `data/ledger_clusters.csv`
- Test: `tests/engine/test_ledger_schema.gd`

**Interfaces:**
- Produces: `repo.ledger_types` rows carry `cluster: String`, `fold_to: String` and `star: String` (`pool` | `instance`); `repo.ledger_links` rows carry `look: String` (`flow` | `tie` | `kin` | `structure`, spec §3b); `repo.ledger_clusters: Array` of `{cluster: String, label: String, colour: String (palette key), at: Vector3, at2: Vector3, lens: String}` in file order; palette keys of Global Constraints; the balance rows below.

- [ ] **Step 1: Write the failing tests** — append to `tests/engine/test_ledger_schema.gd`:

```gdscript
func test_every_type_has_a_known_cluster() -> void:
	var clusters := {}
	for c: Dictionary in data.ledger_clusters:
		clusters[String(c["cluster"])] = c
	assert_eq(clusters.keys().size(), 4, "economy, war, court, intelligence")
	for r: Dictionary in data.ledger_types:
		assert_true(clusters.has(String(r["cluster"])), "%s: cluster %s" % [r["type_id"], r["cluster"]])


func test_the_economy_folds_manors_buildings_and_towns_into_provinces() -> void:
	for r: Dictionary in data.ledger_types:
		var id := String(r["type_id"])
		var want := "province" if id in ["manor", "building", "town"] else ""
		assert_eq(String(r["fold_to"]), want, id)
	assert_eq(String(Ledger.type_row(data, "province")["cluster"]), "economy", "owner: economy by province")


func test_every_type_says_how_its_star_is_sized_and_every_link_how_it_is_drawn() -> void:
	for r: Dictionary in data.ledger_types:
		assert_true(String(r["star"]) in ["pool", "instance"], "%s: star %s" % [r["type_id"], r["star"]])
	for r: Dictionary in data.ledger_links:
		assert_true(String(r["look"]) in ["flow", "tie", "kin", "structure"], "%s: look %s" % [r["link_id"], r["look"]])
	assert_eq(String(Ledger.link_row(data, "kin")["look"]), "kin")
	assert_eq(String(Ledger.link_row(data, "rival")["look"]), "tie")
	assert_eq(String(Ledger.link_row(data, "yields_civil")["look"]), "flow")


func test_a_cluster_anchor_is_read_as_vectors() -> void:
	var c: Dictionary = data.ledger_clusters[0]
	assert_true(c["at"] is Vector3 and c["at2"] is Vector3)
	assert_eq((c["at2"] as Vector3).y, 0.0, "the 2D anchor lies in the plane")
	assert_true(data.ledger_palette.has(String(c["colour"])), "its colour is a palette key")


func test_validate_names_an_unknown_cluster() -> void:
	var r: Dictionary = data.ledger_types[0]
	var was := String(r["cluster"])
	r["cluster"] = "astrology"
	assert_has(Ledger.validate(data), "%s: unknown cluster astrology" % r["type_id"])
	r["cluster"] = was
```

(`test_ledger_schema.gd` already loads `data` in `before_each`; if its variable is named differently, use that name.)

- [ ] **Step 2: Run to see them fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_ledger_schema.gd -gexit`
Expected: FAIL — `ledger_clusters` is not a member / no `cluster` key.

- [ ] **Step 3: Add the data**

`data/ledger_object_types.csv` gains three trailing columns, `cluster,fold_to,star`. `star` is `pool` for `gold`, `civil_goods`, `strategic_goods` and every `planned` type (one fixed star for the whole type), `instance` for every other row. `cluster` and `fold_to` per `type_id`:

| type_id | cluster | fold_to |
|---|---|---|
| peasants, manor, province, town, building, civil_goods, gold, artisans, market, trade_route, workshop | economy | `province` for manor, town, building; else empty |
| strategic_goods, regiment, supply_line, enemy_host | war | |
| character, house, seat, faction | court | |
| source, report, courier | intelligence | |

`data/ledger_link_types.csv` gains a trailing `look` column (spec §3b — the view reads nothing else to decide how a link is drawn):

| look | link_id |
|---|---|
| `kin` | kin, marriage |
| `tie` | ally, rival, grudge, liege, envoy, patron, puppet, admires, acquaintance |
| `flow` | works, yields_civil, yields_strategic, taxed, trade_gold, rations, converts_in, converts_out, supplies_in, supplies_out, consumes, consumes_strategic, trades, trades_strategic, routes, skims, skims_supply, skims_trade, attacks |
| `structure` | every other row (part_of, stands_on, holds, member, sits, based_in, carries, spies_on, describes_*, garrisons, commands, builds, governs, governs_supply, governs_trade, governs_works, witnessed, contradicts, faction_governs) |

Create `data/ledger_clusters.csv`:

```csv
cluster,label,colour,x,y,z,x2,z2,lens,notes
economy,Economy,cluster_economy,-42,-6,8,-46,10,economy,the realm's goods and gold counted by province (owner 2026-09-30)
war,War,cluster_war,45,6,40,48,40,war,the host and what feeds it
court,Court,cluster_court,40,14,-45,46,-42,court,the people of the court and their ties
intelligence,Intelligence,cluster_intelligence,-10,38,-30,-18,-52,intelligence,who told the crown what
```

Append to `data/ledger_palette.csv`:

```csv
sky_top,#120E0B,the warm black night over the galaxy (palette D)
sky_bottom,#070605,the night's foot
nebula_a,#3A2A1A,faint warm dust in the sky
nebula_b,#1A2230,faint cool dust in the sky
stars,#F0E2C4,the background stars
cluster_economy,#D4A24C,brass: the economy's stars
cluster_war,#C24A3C,gules: the war's stars
cluster_court,#9066C0,purpure: the court's stars
cluster_intelligence,#5E8CCB,steel-azure: the intelligence's stars
```

Append to `data/balance.csv` (key,value,notes):

```csv
ledger_galaxy_repel,2,"LEDGER galaxy (spec 2026-09-30-ledger-galaxy-design §4): repulsion between two stars, scaled by their sizes"
ledger_galaxy_spring,0.05,LEDGER galaxy: a link's spring within a cluster
ledger_galaxy_cross_spring,0.15,LEDGER galaxy: a link's spring across clusters as a share of ledger_galaxy_spring
ledger_galaxy_rest_m,4,LEDGER galaxy: a link spring's rest length (metres)
ledger_galaxy_home,0.06,LEDGER galaxy: the pull of a star toward its cluster's anchor (an opened manor's toward its province)
ledger_galaxy_step_max_m,3,LEDGER galaxy: the most a star moves in one pass
ledger_galaxy_passes,150,LEDGER galaxy: passes that settle the chart after a snapshot
ledger_galaxy_ms_per_frame,4,LEDGER galaxy: milliseconds of layout a frame while settling
ledger_galaxy_mode_ease_s,0.6,LEDGER galaxy: seconds the stars ease between the 3D and 2D places
ledger_galaxy_fly_s,0.6,LEDGER galaxy: seconds the camera flies to a cluster
ledger_galaxy_other_fade,0.25,LEDGER galaxy: perceived opacity of the other clusters while one is chosen
ledger_cross_rest_fade,0.45,LEDGER galaxy: perceived opacity of a link crossing clusters while nothing is selected (outside the Court tab)
ledger_focus_width,1.5,LEDGER galaxy: how much wider the selected star's links are drawn
ledger_star_min,0.45,LEDGER galaxy: the smallest star's radius (metres)
ledger_star_max,2.8,LEDGER galaxy: the largest star's radius (metres)
ledger_star_pool,2.6,LEDGER galaxy: a goods pool's radius (gold / civil / strategic)
ledger_star_per_link,0.22,LEDGER galaxy: radius added per square root of a star's links
ledger_star_per_fold,0.27,LEDGER galaxy: radius added per square root of what a province folds
ledger_star_emit,1.4,LEDGER galaxy: a star's glow
ledger_star_rim,1.6,LEDGER galaxy: a star's rim light
ledger_star_metallic,0.35,LEDGER galaxy: a star's metallic
ledger_star_roughness,0.22,LEDGER galaxy: a star's roughness
ledger_haze_strength,0.075,LEDGER galaxy: a cluster haze's brightness
ledger_haze_scale,3.4,LEDGER galaxy: a cluster haze's size as a multiple of the cluster's mean radius
ledger_link_min_px,1,LEDGER galaxy: a link's width at no flow (screen px)
ledger_link_max_px,4,LEDGER galaxy: a link's width at ledger_thread_flow_ref and above (screen px)
ledger_link_vague_px,1.6,LEDGER galaxy: a link whose figure the crown only has in words (screen px)
ledger_tie_min_px,1,LEDGER galaxy: a court tie's width at no feeling (screen px)
ledger_tie_max_px,2.6,LEDGER galaxy: a court tie's width at ledger_tie_ref (screen px)
ledger_strand_gap_px,2,LEDGER galaxy: screen px between two strands' edges
ledger_pair_offset_px,3,LEDGER galaxy: screen px between two links joining the same stars both ways
ledger_link_edge_soft,0.35,LEDGER galaxy: share of a link's half-width over which its sides soften
ledger_dashes_per_m,0.5,LEDGER galaxy: dashes per metre along a planned link
ledger_glow_intensity,0.9,LEDGER galaxy: the view's glow intensity
ledger_glow_threshold,0.8,LEDGER galaxy: the view's glow HDR threshold
ledger_label_hubs,12,LEDGER galaxy: the largest stars in view that are always named
ledger_title_px,20,LEDGER galaxy: a cluster title's font size (design px)
ledger_ring_px,3,LEDGER galaxy: the selected star's ring width (screen px)
```

And change these existing rows' values (the chart is ~150 m across, not 25): `ledger_camera_distance` 160, `ledger_camera_max_m` 420, `ledger_camera_min_m` 20.

- [ ] **Step 4: Load it** — in `scripts/engine/data_repository.gd`:

Next to the other `ledger_*` members:

```gdscript
## data/ledger_clusters.csv, in file order: {cluster, label, colour (a
## ledger_palette.csv key), at (Vector3, the 3D anchor), at2 (Vector3 with
## y 0, the 2D anchor), lens (the lens chip it answers to)}.
var ledger_clusters: Array = []
```

Change the `ledger_object_types.csv` required columns to add `"cluster", "fold_to", "star"` and the `ledger_link_types.csv` ones to add `"look"`, and after the `ledger_lenses.csv` load add:

```gdscript
	if not _load_if_present(dir + "/ledger_clusters.csv", ["cluster", "label", "colour", "x", "y", "z", "x2", "z2", "lens"],
			func(r): ledger_clusters.append({"cluster": String(r["cluster"]), "label": String(r["label"]),
				"colour": String(r["colour"]), "lens": String(r["lens"]),
				"at": Vector3(float(r["x"]), float(r["y"]), float(r["z"])),
				"at2": Vector3(float(r["x2"]), 0.0, float(r["z2"]))})):
		return false
```

(`ledger_clusters` must be cleared wherever the other `ledger_*` arrays are cleared, if the repository clears them on reload — follow what `ledger_lenses` does.)

- [ ] **Step 5: Validate it** — in `Ledger.validate`, after the loop over `repo.ledger_types` builds `types`:

```gdscript
	var clusters := {}
	for c: Dictionary in repo.ledger_clusters:
		clusters[String(c["cluster"])] = true
	for r: Dictionary in repo.ledger_types:
		var id := String(r["type_id"])
		if not clusters.has(String(r.get("cluster", ""))):
			errors.append("%s: unknown cluster %s" % [id, r.get("cluster", "")])
		var fold := String(r.get("fold_to", ""))
		if fold != "" and not types.has(fold):
			errors.append("%s: folds into unknown type %s" % [id, fold])
		if not String(r.get("star", "")) in ["pool", "instance"]:
			errors.append("%s: unknown star %s" % [id, r.get("star", "")])
	for r: Dictionary in repo.ledger_links:
		if not String(r.get("look", "")) in ["flow", "tie", "kin", "structure"]:
			errors.append("%s: unknown look %s" % [r["link_id"], r.get("look", "")])
```

- [ ] **Step 6: Run the schema and data tests**

Run the Step 2 command, then `-gtest=res://tests/engine/test_ledger_data.gd`.
Expected: PASS (every existing test too — the old columns are untouched).

- [ ] **Step 7: Commit**

```bash
git add data/ledger_object_types.csv data/ledger_link_types.csv data/ledger_clusters.csv data/ledger_palette.csv data/balance.csv scripts/engine/data_repository.gd scripts/engine/ledger.gd tests/engine/test_ledger_schema.gd
git commit -m "feat(ledger): clusters and folding as data — palette D, galaxy balance rows

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The galaxy snapshot

**Files:**
- Modify: `scripts/engine/ledger.gd`, `scripts/engine/ledger_resolvers.gd`
- Create: `tests/engine/test_ledger_galaxy.gd`

**Interfaces:**
- Consumes: Task 1's `cluster` / `fold_to` columns.
- Produces: `static func galaxy(repo: DataRepository, state: GameState, opened: Dictionary) -> Dictionary` on `Ledger` — `{lens: "galaxy", focus_id: "", focus_lost: false, day: int, nodes: Array, links: Array, loops: Array}`; a node is `Ledger._node`'s dict plus `cluster: String`, and — on a province that folds anything — `folded: {type_id: int}`, and — on an unfolded manor / building / town — `home_id: String` (its province's node id); a link is `Ledger._believed`'s dict plus `count: int` (how many unfolded links it stands for). `opened` is a set: `{"<province code>": true}`. Nodes and links are sorted by id.
- Produces: `LedgerResolvers._manors_of_house(repo, state, family) -> Array` (memoised index).

- [ ] **Step 1: Write the failing tests** — create `tests/engine/test_ledger_galaxy.gd`:

```gdscript
# tests/engine/test_ledger_galaxy.gd
extends GutTest
## The realm as one galaxy (spec 2026-09-30-ledger-galaxy-design §3): every
## instance once, in its cluster; the economy counted by province.

var data: DataRepository
var s: GameState


func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()


func after_each() -> void:
	Intel.dev_all = false
	RealmEconomy.forget()


func _nodes(g: Dictionary) -> Dictionary:
	var out := {}
	for n: Dictionary in g["nodes"]:
		out[String(n["id"])] = n
	return out


func _links_of_type(g: Dictionary, t: String) -> Array:
	return (g["links"] as Array).filter(func(l: Dictionary) -> bool: return String(l["type"]) == t)


func test_every_listed_instance_stands_once_in_its_cluster() -> void:
	var g := Ledger.galaxy(data, s, {})
	var nodes := _nodes(g)
	assert_eq(nodes.size(), (g["nodes"] as Array).size(), "no star twice")
	for cid: String in s.characters:
		assert_eq(String(nodes["character:" + cid]["cluster"]), "court")
	for code: String in s.regiments:
		if nodes.has("regiment:" + code):
			assert_eq(String(nodes["regiment:" + code]["cluster"]), "war")
	assert_true(nodes.has("type:gold") and nodes.has("type:civil_goods"), "the pools stand as one star each")
	assert_eq(String(nodes["type:enemy_host"]["status"]), "planned", "a planned type is a ghost")


func test_no_manor_town_or_building_stands_unless_its_province_is_opened() -> void:
	var g := Ledger.galaxy(data, s, {})
	for n: Dictionary in g["nodes"]:
		assert_false(String(n["type"]) in ["manor", "town", "building"], String(n["id"]))
	var home := MapManors.home_province(data, s)
	var folded: Dictionary = _nodes(g)["province:" + home].get("folded", {})
	assert_eq(int(folded.get("manor", 0)), MapManors.manors_of_province(data, home, s).size(),
		"the home province folds every one of its manors")


func test_opening_a_province_shows_exactly_its_manors() -> void:
	var home := MapManors.home_province(data, s)
	var g := Ledger.galaxy(data, s, {home: true})
	var manors: Array = (g["nodes"] as Array).filter(func(n: Dictionary) -> bool:
		return String(n["type"]) == "manor")
	assert_eq(manors.size(), MapManors.manors_of_province(data, home, s).size())
	for n: Dictionary in manors:
		var cell := int(String(n["id"]).get_slice(":", 1))
		assert_eq(MapManors.province_of(data, cell, s), home)
		assert_eq(String(n["home_id"]), "province:" + home, "it settles round its province")


func test_a_merged_link_counts_what_it_stands_for() -> void:
	var g := Ledger.galaxy(data, s, {})
	var holds := _links_of_type(g, "holds")
	assert_false(holds.is_empty())
	for l: Dictionary in holds:
		var family := String(l["from"]).substr(6)
		var province := String(l["to"]).substr(9)
		var want := 0
		for cell: int in MapManors.manors_of_house(data, s, family):
			if MapManors.province_of(data, cell, s) == province:
				want += 1
		assert_eq(int(l["count"]), want, String(l["id"]))


func test_no_link_joins_a_star_to_itself() -> void:
	var g := Ledger.galaxy(data, s, {})
	for l: Dictionary in g["links"]:
		assert_ne(String(l["from"]), String(l["to"]), String(l["id"]))


func test_flows_merge_only_within_one_level() -> void:
	var g := Ledger.galaxy(data, s, {})
	var home := MapManors.home_province(data, s)
	for l: Dictionary in _links_of_type(g, "yields_civil"):
		var code := String(l["from"]).substr(9)
		if code == home:
			var want := 0
			for cell: int in MapManors.manors_of_province(data, home, s):
				want += int(RealmEconomy.line_of(data, s, cell)["civil"])
			assert_eq(int(l["flow"]), want, "the controlled province's civil yield is the sum of its manors'")
			assert_eq(String((l["accounts"] as Array)[0]["level"]), "full")
		elif String((l["accounts"] as Array)[0]["level"]) != "full":
			assert_null(l["flow"], "a province known in words sums to words, never a number")


func test_an_annexed_manor_folds_into_its_new_province() -> void:
	var home := MapManors.home_province(data, s)
	var cell := -1
	var to := ""
	for c: int in data.manors.keys():
		var t := MapManors.annex_target(data, s, c)
		if t != "" and MapManors.province_of(data, c, s) != t:
			cell = c
			to = t
			break
	assert_ne(cell, -1, "the pack has a manor that can be annexed")
	assert_true(MapManors.annex(data, s, cell, to, "test: annexed"))
	var g := Ledger.galaxy(data, s, {to: true})
	assert_true(_nodes(g).has("manor:%d" % cell), "opened, the annexed manor stands in its new province")
	assert_eq(String(_nodes(g)["manor:%d" % cell]["home_id"]), "province:" + to)


func test_every_unfolded_ego_link_is_in_the_galaxy() -> void:
	var g := Ledger.galaxy(data, s, {})
	var ids := {}
	for l: Dictionary in g["links"]:
		ids[String(l["id"])] = true
	var nodes := _nodes(g)
	for id: String in ["regiment:" + String(s.regiments.keys()[0]), "character:you",
			"province:" + MapManors.home_province(data, s)]:
		for lens: String in ["economy", "war", "court", "intelligence"]:
			var ego := Ledger.snapshot(data, s, lens, {"id": id})
			for l: Dictionary in ego["links"]:
				if nodes.has(String(l["from"])) and nodes.has(String(l["to"])) \
						and String(l["status"]) == "live":
					assert_true(ids.has(String(l["id"])), "%s in the galaxy" % l["id"])


func test_the_house_index_gives_the_scans_manors() -> void:
	LedgerResolvers.begin_memo()
	for fam: String in [(s.characters["you"] as Character).family_name,
			MapObjects.house_name_of(data, MapManors.home_province(data, s))]:
		assert_eq(LedgerResolvers._manors_of_house(data, s, fam), MapManors.manors_of_house(data, s, fam), fam)
	LedgerResolvers.end_memo()


func test_the_galaxy_is_read_within_its_budget() -> void:
	var engine := TickEngine.new(data)
	for m in 6:
		for d in 29:
			engine.advance_day(s)
		engine.advance(s)
	Ledger.galaxy(data, s, {})  # warm the economy's caches
	var t0 := Time.get_ticks_usec()
	var g := Ledger.galaxy(data, s, {})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	gut.p("galaxy: %d stars, %d links, %.1f ms" % [(g["nodes"] as Array).size(), (g["links"] as Array).size(), ms])
	assert_lt(ms, 60.0, "spec §3 budget")
```

(Engine tests may read the clock for a budget; the engine itself must not.)

- [ ] **Step 2: Run to see them fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_ledger_galaxy.gd -gexit`
Expected: FAIL — `galaxy` / `_manors_of_house` not found.

- [ ] **Step 3: The house index** — in `scripts/engine/ledger_resolvers.gd`, below `_workshop_plan`:

```gdscript
## A house's manors (MapManors.manors_of_house), from ONE index of every
## manor by its holder built per memo — the scan per house cost ~136 ms a
## galaxy (spec 2026-09-30-ledger-galaxy-design §3). Outside a memo, the scan.
static func _manors_of_house(repo: DataRepository, state: GameState, family: String) -> Array:
	if not _memo_on:
		return MapManors.manors_of_house(repo, state, family)
	if not _memo.has("house_manors"):
		var idx := {}
		var ids: Array = repo.manors.keys()
		ids.sort()
		for cell: int in ids:
			var owner := String(MapManors.owner_of(repo, state, cell))
			if owner != "":
				(idx.get_or_add(owner, []) as Array).append(cell)
		_memo["house_manors"] = idx
	return (_memo["house_manors"] as Dictionary).get(family, [])
```

and in `_holds`, replace `MapManors.manors_of_house(repo, state, _rest(id))` with `_manors_of_house(repo, state, _rest(id))`.

- [ ] **Step 4: The galaxy** — in `scripts/engine/ledger.gd`, after `snapshot`:

```gdscript
## The whole realm as ONE picture (spec 2026-09-30-ledger-galaxy-design
## §3): every listed instance, every pool, every planned type as a ghost,
## and the links that are the union of their egos — read by a worklist that
## expands every node it finds EXCEPT a foldable one (a manor, building or
## town) outside a controlled or opened province. Then the fold: each
## foldable node not in an opened province becomes its province's, its links
## re-pointed there and merged (counted; flows summed within one Intel
## level). `opened` is a set of province codes. Nodes and links by id.
static func galaxy(repo: DataRepository, state: GameState, opened: Dictionary) -> Dictionary:
	var out := {"lens": "galaxy", "focus_id": "", "focus_lost": false, "day": state.absolute_day(),
		"nodes": [], "links": [], "loops": []}
	LedgerResolvers.begin_memo()
	var controlled := {}
	for code: String in MapManors.controlled_provinces(repo, state):
		controlled[code] = true
	var nodes := {}
	var raw := {}
	var queue: Array = []
	for r: Dictionary in repo.ledger_types:
		var tid := String(r["type_id"])
		if String(r["status"]) == "planned":
			nodes["type:" + tid] = _galaxy_node(repo, state, "type:" + tid)
			continue
		var list := String(r["instances"])
		if list == "":
			if String(r["fold_to"]) == "":
				nodes["type:" + tid] = _galaxy_node(repo, state, "type:" + tid)
			continue
		for row: Dictionary in LedgerResolvers.instances(list, repo, state):
			var id := String(row["id"])
			if not nodes.has(id):
				nodes[id] = _galaxy_node(repo, state, id)
				queue.append(id)
	var i := 0
	while i < queue.size():
		var id: String = queue[i]
		i += 1
		var t := type_of(id)
		for r: Dictionary in repo.ledger_links:
			if String(r["status"]) != "live" or (String(r["from_type"]) != t and String(r["to_type"]) != t):
				continue
			for l: Dictionary in LedgerResolvers.run(r, repo, state, {"id": id}):
				var a := String(l["from"])
				var b := String(l["to"])
				if a != id and b != id:
					continue
				var bl := _believed(repo, state, r, l)
				raw[String(bl["id"])] = bl
				for e: String in [a, b]:
					if nodes.has(e):
						continue
					nodes[e] = _galaxy_node(repo, state, e)
					if _expands(repo, state, e, controlled, opened):
						queue.append(e)
	# a row between two types that have no instances (pool to pool) once
	for r: Dictionary in repo.ledger_links:
		if String(r["status"]) != "live":
			continue
		if not nodes.has("type:" + String(r["from_type"])) or not nodes.has("type:" + String(r["to_type"])):
			continue
		for l: Dictionary in LedgerResolvers.run(r, repo, state, {}):
			var bl := _believed(repo, state, r, l)
			raw[String(bl["id"])] = bl
	# the fold
	var fold := {}
	for id: String in nodes:
		var p := _fold_target(repo, state, id, opened)
		if p != "":
			fold[id] = p
	for id: String in fold:
		var pid := String(fold[id])
		if not nodes.has(pid):
			nodes[pid] = _galaxy_node(repo, state, pid)
		var f: Dictionary = nodes[pid].get("folded", {})
		f[type_of(id)] = int(f.get(type_of(id), 0)) + 1
		nodes[pid]["folded"] = f
	for id: String in nodes:
		var fold_to := String(type_row(repo, type_of(id)).get("fold_to", ""))
		if fold_to != "" and not fold.has(id):
			nodes[id]["home_id"] = "province:" + _province_code(repo, state, id)
	var merged := {}
	var keys: Array = raw.keys()
	keys.sort()
	for k: String in keys:
		var l: Dictionary = raw[k]
		var a := String(fold.get(String(l["from"]), String(l["from"])))
		var b := String(fold.get(String(l["to"]), String(l["to"])))
		if a == b:
			continue
		var mid := "%s|%s|%s" % [l["type"], a, b]
		if merged.has(mid):
			_merge_into(merged[mid], l)
		else:
			var m: Dictionary = l.duplicate(true)
			m["id"] = mid
			m["from"] = a
			m["to"] = b
			m["count"] = 1
			merged[mid] = m
	for id: String in fold:
		nodes.erase(id)
	var ids: Array = nodes.keys()
	ids.sort()
	for id: String in ids:
		out["nodes"].append(nodes[id])
	var lids: Array = merged.keys()
	lids.sort()
	for lid: String in lids:
		out["links"].append(merged[lid])
	_loops(repo, state, out)
	LedgerResolvers.end_memo()
	return out


static func _galaxy_node(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	var n := _node(repo, state, id)
	n["cluster"] = String(type_row(repo, type_of(id)).get("cluster", "economy"))
	return n


## Whether the worklist reads a node's own ego: a foldable node only inside a
## controlled or opened province (elsewhere it only folds); a pool never
## (its links come from the other end).
static func _expands(repo: DataRepository, state: GameState, id: String, controlled: Dictionary,
		opened: Dictionary) -> bool:
	if id.begins_with("type:") or id.begins_with("more:"):
		return false
	if String(type_row(repo, type_of(id)).get("fold_to", "")) == "":
		return true
	var code := _province_code(repo, state, id)
	return controlled.has(code) or opened.has(code)


## The province a foldable node stands in (live state), or "".
static func _province_code(repo: DataRepository, state: GameState, id: String) -> String:
	var rest := id.substr(id.get_slice(":", 0).length() + 1)
	match type_of(id):
		"manor":
			return MapManors.province_of(repo, int(rest), state)
		"building":
			return MapManors.province_of(repo, int(rest.get_slice(":", 0)), state)
		"town":
			return MarketSystem.province_of_burg(repo, state, rest)
	return ""


## The province node a node folds into, or "" (not foldable, no province,
## or its province is opened).
static func _fold_target(repo: DataRepository, state: GameState, id: String, opened: Dictionary) -> String:
	if String(type_row(repo, type_of(id)).get("fold_to", "")) == "":
		return ""
	var code := _province_code(repo, state, id)
	if code == "" or opened.has(code):
		return ""
	return "province:" + code


const _LEVELS := ["full", "general", "basic"]


## Adds a folded link into the one it merges with: one more counted; the
## flow sums only while both are figures at one Intel level — else the
## merged figure is words at the worse level (never words added to numbers).
static func _merge_into(m: Dictionary, l: Dictionary) -> void:
	m["count"] = int(m["count"]) + 1
	var ma: Dictionary = (m["accounts"] as Array)[0]
	var la: Dictionary = (l["accounts"] as Array)[0] if not (l["accounts"] as Array).is_empty() else ma
	var worse := String(ma["level"]) if _LEVELS.find(String(ma["level"])) >= _LEVELS.find(String(la["level"])) \
		else String(la["level"])
	var f: Variant = null
	if m["flow"] != null and l["flow"] != null and String(ma["level"]) == String(la["level"]):
		var a := int(m["flow"])
		var b := int(l["flow"])
		f = -1 if a < 0 and b < 0 else maxi(a, 0) + maxi(b, 0)
	m["flow"] = f
	var text := ""
	if f == null:
		text = String(ma["text"]) if String(ma["level"]) == worse else String(la["text"])
	elif int(f) >= 0:
		text = Intel.num(int(f))
	m["accounts"] = [{"value": f, "text": text, "source": String(ma["source"]),
		"day": mini(int(ma["day"]), int(la["day"])), "level": worse}]
```

- [ ] **Step 5: Run the galaxy tests, then every LEDGER engine test**

Run the Step 2 command, then each of `tests/engine/test_ledger_snapshot.gd`, `test_ledger_resolvers.gd`, `test_ledger_governors.gd`, `test_ledger_supply.gd`, `test_ledger_trade.gd`, `test_ledger_cards.gd`.
Expected: PASS; the budget test prints about 40 ms. If it is over 60 ms, profile per link row (time `LedgerResolvers.run` by `link_id`, as the spec's measurement did) and memoise the slowest reader the way Step 3 does — do not raise the budget.

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/ledger.gd scripts/engine/ledger_resolvers.gd tests/engine/test_ledger_galaxy.gd
git commit -m "feat(ledger): the galaxy snapshot — every instance once, the economy folded by province

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 3: Nodes and edges written down — the open schema

**Files:**
- Create: `data/ledger_static_nodes.csv`, `data/ledger_static_links.csv`, `tests/engine/test_ledger_open_schema.gd`
- Modify: `scripts/engine/data_repository.gd`, `scripts/engine/ledger_resolvers.gd`, `scripts/engine/ledger.gd` (`validate`, `galaxy`), `scripts/engine/ledger_cards.gd`

**Interfaces:**
- Consumes: Task 2's `Ledger.galaxy`.
- Produces: `repo.ledger_static_nodes: Array` of `{node_id, type_id, label, note}`; `repo.ledger_static_links: Array` of `{link_id, from, to, flow: int (-1 when blank), note}`; the instance list `static` and the reader `static` (both in `LedgerResolvers`); `LedgerResolvers.instances(name, repo, state, type_id := "")` (the `static` list needs the type); `LedgerResolvers.static_node(repo, id) -> Dictionary` ({} when none). The galaxy never draws a node whose label is "" (it no longer exists) nor any link to it.

- [ ] **Step 1: Write the failing contract test** — create `tests/engine/test_ledger_open_schema.gd`:

```gdscript
# tests/engine/test_ledger_open_schema.gd
extends GutTest
## The owner adds, changes or removes nodes and edges at any time, in data
## (spec 2026-09-30-ledger-galaxy-design §3b): a new type, a new link type,
## single nodes and edges written down — with no code.

var data: DataRepository
var s: GameState


func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()


func after_each() -> void:
	RealmEconomy.forget()


func _add_shrines() -> void:
	data.ledger_types.append({"type_id": "shrine", "layer": "things", "lenses": "economy|all", "label": "Shrines",
		"icon": "", "x": "0", "z": "0", "instances": "static", "status": "live", "milestone": "",
		"cluster": "court", "fold_to": "", "star": "instance"})
	data.ledger_links.append({"link_id": "venerates", "from_type": "character", "to_type": "shrine",
		"verb": "venerates", "lenses": "court|all", "status": "live", "resolver": "static", "governor_seat": "",
		"governor_kind": "", "milestone": "", "planned_note": "", "look": "tie"})
	data.ledger_static_nodes.append({"node_id": "shrine:saint_odo", "type_id": "shrine", "label": "Shrine of St Odo",
		"note": "Pilgrims leave coin here."})
	data.ledger_static_nodes.append({"node_id": "shrine:old_oak", "type_id": "shrine", "label": "The Old Oak",
		"note": "Older than the realm."})
	data.ledger_static_links.append({"link_id": "venerates", "from": "character:you", "to": "shrine:saint_odo",
		"flow": 40, "note": ""})


func _has(g: Dictionary, key: String, id: String) -> bool:
	for x: Dictionary in g[key]:
		if String(x["id"]) == id:
			return true
	return false


func test_a_type_and_its_nodes_written_down_appear_with_no_code() -> void:
	_add_shrines()
	assert_eq(Ledger.validate(data), [] as Array[String], "the added rows validate")
	var g := Ledger.galaxy(data, s, {})
	assert_true(_has(g, "nodes", "shrine:saint_odo") and _has(g, "nodes", "shrine:old_oak"))
	assert_true(_has(g, "links", "venerates|character:you|shrine:saint_odo"))
	for n: Dictionary in g["nodes"]:
		if String(n["id"]) == "shrine:saint_odo":
			assert_eq(String(n["cluster"]), "court")
			assert_eq(String(n["label"]), "Shrine of St Odo")


func test_changing_a_row_changes_the_node_and_the_edge() -> void:
	_add_shrines()
	data.ledger_static_nodes[-2]["label"] = "Shrine of St Odo the Younger"
	data.ledger_static_links[-1]["flow"] = 55
	var g := Ledger.galaxy(data, s, {})
	for n: Dictionary in g["nodes"]:
		if String(n["id"]) == "shrine:saint_odo":
			assert_eq(String(n["label"]), "Shrine of St Odo the Younger")
	for l: Dictionary in g["links"]:
		if String(l["id"]) == "venerates|character:you|shrine:saint_odo":
			assert_eq(int(l["flow"]), 55)


func test_removing_the_rows_removes_them() -> void:
	_add_shrines()
	data.ledger_static_links.pop_back()
	data.ledger_static_nodes.pop_back()
	var g := Ledger.galaxy(data, s, {})
	assert_false(_has(g, "links", "venerates|character:you|shrine:saint_odo"), "the edge's row is gone")
	assert_false(_has(g, "nodes", "shrine:old_oak"), "the node's row is gone")
	assert_true(_has(g, "nodes", "shrine:saint_odo"), "the other stays")


func test_an_edge_to_someone_who_no_longer_exists_is_not_drawn() -> void:
	_add_shrines()
	data.ledger_static_links.append({"link_id": "venerates", "from": "character:nobody", "to": "shrine:old_oak",
		"flow": 5, "note": ""})
	var g := Ledger.galaxy(data, s, {})
	assert_false(_has(g, "nodes", "character:nobody"))
	assert_false(_has(g, "links", "venerates|character:nobody|shrine:old_oak"))


func test_validate_names_a_row_pointing_at_nothing() -> void:
	data.ledger_static_nodes.append({"node_id": "idol:gold", "type_id": "idol", "label": "Idol", "note": ""})
	data.ledger_static_links.append({"link_id": "worships", "from": "character:you", "to": "idol:gold",
		"flow": -1, "note": ""})
	var errors := Ledger.validate(data)
	assert_has(errors, "static node idol:gold: unknown type idol")
	assert_has(errors, "static link worships: unknown link type")


func test_a_static_node_has_a_card() -> void:
	_add_shrines()
	var g := Ledger.galaxy(data, s, {})
	var card := LedgerCards.entry(data, s, "shrine:saint_odo", g)
	assert_eq(String(card["title"]), "Shrine of St Odo")
	assert_has(card["lines"], "Pilgrims leave coin here.")
```

- [ ] **Step 2: Run to see it fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_ledger_open_schema.gd -gexit`
Expected: FAIL — `ledger_static_nodes` is not a member.

- [ ] **Step 3: The two tables** — create them with headers only (the owner fills them):

`data/ledger_static_nodes.csv`:
```csv
node_id,type_id,label,note
```

`data/ledger_static_links.csv`:
```csv
link_id,from,to,flow,note
```

In `scripts/engine/data_repository.gd`, beside the other `ledger_*` members:

```gdscript
## data/ledger_static_nodes.csv (spec 2026-09-30-ledger-galaxy-design §3b):
## single nodes written down — {node_id, type_id, label, note}; the type's
## row names the instance list `static`.
var ledger_static_nodes: Array = []
## data/ledger_static_links.csv: single edges written down — {link_id, from,
## to, flow (-1 when blank), note}; the link type's row names the reader `static`.
var ledger_static_links: Array = []
```

and after the `ledger_clusters.csv` load:

```gdscript
	if not _load_if_present(dir + "/ledger_static_nodes.csv", ["node_id", "type_id", "label", "note"],
			func(r): ledger_static_nodes.append({"node_id": String(r["node_id"]), "type_id": String(r["type_id"]),
				"label": String(r["label"]), "note": String(r["note"])})):
		return false
	if not _load_if_present(dir + "/ledger_static_links.csv", ["link_id", "from", "to", "flow", "note"],
			func(r): ledger_static_links.append({"link_id": String(r["link_id"]), "from": String(r["from"]),
				"to": String(r["to"]), "flow": -1 if String(r["flow"]).strip_edges() == "" else int(r["flow"]),
				"note": String(r["note"])})):
		return false
```

- [ ] **Step 4: The generic list and reader** — in `scripts/engine/ledger_resolvers.gd`:

Add `"static"` to both `NAMES` and `INSTANCE_LISTS`. Give `instances` a trailing parameter and a branch:

```gdscript
static func instances(name: String, repo: DataRepository, state: GameState, type_id: String = "") -> Array:
```

```gdscript
		"static":
			for n: Dictionary in repo.ledger_static_nodes:
				if String(n["type_id"]) == type_id:
					out.append({"id": String(n["node_id"]), "strain": 0})
```

In `run`'s `match`:

```gdscript
		"static":
			return _static_links(row, repo, id, all)
```

and the reader and the lookup, after `_rest`:

```gdscript
## A link type whose links are written down (data/ledger_static_links.csv,
## spec 2026-09-30-ledger-galaxy-design §3b): the crown's own figure, no
## Intel subject. The type level is one link counting them.
static func _static_links(row: Dictionary, repo: DataRepository, id: String, all: bool) -> Array:
	var out: Array = []
	for l: Dictionary in repo.ledger_static_links:
		if String(l["link_id"]) != String(row["link_id"]):
			continue
		if all or id == "" or id == String(l["from"]) or id == String(l["to"]):
			out.append(_link(String(l["from"]), String(l["to"]), int(l["flow"]), "count"))
	if id == "" and not all:
		return [_type_link(String(row["from_type"]), String(row["to_type"]), out.size(), "count")] \
			if not out.is_empty() else []
	return out


## The written-down node `id` (data/ledger_static_nodes.csv), or {}.
static func static_node(repo: DataRepository, id: String) -> Dictionary:
	for n: Dictionary in repo.ledger_static_nodes:
		if String(n["node_id"]) == id:
			return n
	return {}
```

At the top of `label_of`, before its `match`:

```gdscript
	var written := static_node(repo, id)
	if not written.is_empty():
		return String(written["label"])
```

- [ ] **Step 5: The galaxy reads the list by type and drops what no longer exists** — in `Ledger.galaxy`:

Replace `LedgerResolvers.instances(list, repo, state)` with `LedgerResolvers.instances(list, repo, state, tid)`. In the worklist, before a link is kept, drop it when an end is a new node that does not exist:

```gdscript
				var gone := false
				for e: String in [a, b]:
					if not nodes.has(e) and not e.begins_with("type:") \
							and LedgerResolvers.label_of(repo, state, e) == "":
						gone = true
				if gone:
					continue
				var bl := _believed(repo, state, r, l)
```

(and the discovered-node loop below it stays as written in Task 2).

- [ ] **Step 6: Validate the tables** — in `Ledger.validate`, before `return errors`:

```gdscript
	for n: Dictionary in repo.ledger_static_nodes:
		var tid := String(n["type_id"])
		if not types.has(tid):
			errors.append("static node %s: unknown type %s" % [n["node_id"], tid])
		elif String(types[tid]["instances"]) != "static":
			errors.append("static node %s: type %s does not list static instances" % [n["node_id"], tid])
		elif type_of(String(n["node_id"])) != tid:
			errors.append("static node %s: its id must begin %s:" % [n["node_id"], tid])
	for l: Dictionary in repo.ledger_static_links:
		var lid := String(l["link_id"])
		if not links.has(lid):
			errors.append("static link %s: unknown link type" % lid)
			continue
		if String(links[lid]["resolver"]) != "static":
			errors.append("static link %s: its link type is not read from the table" % lid)
		for end: String in ["from", "to"]:
			var want := String(links[lid]["from_type" if end == "from" else "to_type"])
			if type_of(String(l[end])) != want:
				errors.append("static link %s: %s %s is not a %s" % [lid, end, l[end], want])
```

- [ ] **Step 7: A written-down node's card** — at the top of `LedgerCards.entry`:

```gdscript
	var written := LedgerResolvers.static_node(repo, node_id)
	if not written.is_empty():
		var lines: Array = []
		if String(written["note"]) != "":
			lines.append(String(written["note"]))
		return {"title": String(written["label"]), "lines": lines}
```

(If `entry`'s dictionary uses other keys for the title and lines, match them — read the function's existing `return` statements.)

- [ ] **Step 8: Run the contract test and every LEDGER engine test**

Run the Step 2 command; then `test_ledger_galaxy.gd`, `test_ledger_schema.gd`, `test_ledger_resolvers.gd`, `test_ledger_cards.gd`, `test_ledger_snapshot.gd`.
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add data/ledger_static_nodes.csv data/ledger_static_links.csv scripts/engine/data_repository.gd scripts/engine/ledger_resolvers.gd scripts/engine/ledger.gd scripts/engine/ledger_cards.gd tests/engine/test_ledger_open_schema.gd
git commit -m "feat(ledger): the open schema — nodes and edges written down, added, changed or removed in data

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The galaxy layout (pure)

**Files:**
- Create: `scripts/ledger3d/ledger_galaxy_layout.gd`, `tests/ledger3d/test_ledger_galaxy_layout.gd`

**Interfaces:**
- Consumes: a galaxy snapshot (Task 2); `repo.ledger_clusters` (Task 1).
- Produces: `class LedgerGalaxyLayout` — `var pos: Dictionary` (id → Vector3), `var pinned: Dictionary`, `var flat: bool`, `var passes_left: int`; `func setup(repo, snap, as_flat: bool) -> void`; `func step(passes: int) -> void`; `func settled() -> bool`; `func pin(id: String, at: Vector3) -> void`; `static func size_of(repo, node: Dictionary, degree: int) -> float`; `static func anchors(repo, as_flat: bool) -> Dictionary` (cluster → Vector3); `static func jitter(id: String, r: float, as_flat: bool) -> Vector3`.

- [ ] **Step 1: Write the failing tests** — create `tests/ledger3d/test_ledger_galaxy_layout.gd`:

```gdscript
# tests/ledger3d/test_ledger_galaxy_layout.gd
extends GutTest
## Where the galaxy's stars stand (spec 2026-09-30-ledger-galaxy-design §4).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")


func _snap() -> Dictionary:
	var nodes: Array = []
	for i in 6:
		nodes.append({"id": "character:c%d" % i, "type": "character", "cluster": "court"})
	for i in 4:
		nodes.append({"id": "regiment:r%d" % i, "type": "regiment", "cluster": "war"})
	nodes.append({"id": "province:p", "type": "province", "cluster": "economy", "folded": {"manor": 9}})
	nodes.append({"id": "manor:1", "type": "manor", "cluster": "economy", "home_id": "province:p"})
	var links: Array = [{"from": "character:c0", "to": "character:c1"}, {"from": "character:c1", "to": "regiment:r0"},
		{"from": "manor:1", "to": "province:p"}]
	return {"nodes": nodes, "links": links}


func test_one_snapshot_always_lays_out_the_same_way() -> void:
	var a := LedgerGalaxyLayout.new()
	var b := LedgerGalaxyLayout.new()
	a.setup(repo, _snap(), false)
	b.setup(repo, _snap(), false)
	a.step(40)
	b.step(40)
	for id: String in a.pos:
		assert_eq(a.pos[id], b.pos[id], id)


func test_a_star_keeps_its_place_across_a_snapshot() -> void:
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, _snap(), false)
	lay.step(lay.passes_left)
	var before: Dictionary = lay.pos.duplicate()
	lay.setup(repo, _snap(), false)
	for id: String in before:
		assert_eq(lay.pos[id], before[id], "kept: " + id)
	assert_gt(lay.passes_left, 0, "a new snapshot settles again")


func test_a_new_star_starts_round_its_home() -> void:
	var lay := LedgerGalaxyLayout.new()
	var snap := _snap()
	lay.setup(repo, snap, false)
	lay.step(lay.passes_left)
	snap["nodes"].append({"id": "manor:2", "type": "manor", "cluster": "economy", "home_id": "province:p"})
	lay.setup(repo, snap, false)
	var d := (lay.pos["manor:2"] as Vector3).distance_to(lay.pos["province:p"])
	assert_lt(d, 3.0 * repo.bal("ledger_galaxy_rest_m"), "a newly opened manor appears by its province")


func test_the_flat_chart_lies_in_the_plane() -> void:
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, _snap(), true)
	lay.step(30)
	for id: String in lay.pos:
		assert_eq((lay.pos[id] as Vector3).y, 0.0, id)


func test_a_pinned_star_stays_where_it_is_held() -> void:
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, _snap(), false)
	lay.pin("character:c0", Vector3(1, 2, 3))
	lay.step(20)
	assert_eq(lay.pos["character:c0"], Vector3(1, 2, 3))


func test_the_clusters_settle_apart() -> void:
	var s := GameState.new_campaign(repo, 42)
	var g := Ledger.galaxy(repo, s, {})
	var lay := LedgerGalaxyLayout.new()
	lay.setup(repo, g, false)
	lay.step(lay.passes_left)
	var sums := {}
	var counts := {}
	for n: Dictionary in g["nodes"]:
		var c := String(n["cluster"])
		sums[c] = (sums.get(c, Vector3.ZERO) as Vector3) + (lay.pos[String(n["id"])] as Vector3)
		counts[c] = int(counts.get(c, 0)) + 1
	var mid := {}
	for c: String in sums:
		mid[c] = (sums[c] as Vector3) / float(counts[c])
	var spread := {}
	for n: Dictionary in g["nodes"]:
		var c := String(n["cluster"])
		spread[c] = float(spread.get(c, 0.0)) + (lay.pos[String(n["id"])] as Vector3).distance_to(mid[c]) / float(counts[c])
	for a: String in mid:
		for b: String in mid:
			if a < b:
				assert_gt((mid[a] as Vector3).distance_to(mid[b]), float(spread[a]) + float(spread[b]) * 0.5,
					"%s and %s read as two clusters" % [a, b])
	assert_true(lay.settled())


func test_a_star_is_sized_by_its_kind() -> void:
	var pool := LedgerGalaxyLayout.size_of(repo, {"type": "gold"}, 30)
	assert_eq(pool, repo.bal("ledger_star_pool"), "a pool is one fixed size")
	var small := LedgerGalaxyLayout.size_of(repo, {"type": "character"}, 1)
	var big := LedgerGalaxyLayout.size_of(repo, {"type": "character"}, 16)
	assert_lt(small, big, "more links, a bigger star")
	var prov := LedgerGalaxyLayout.size_of(repo, {"type": "province", "folded": {"manor": 36}}, 1)
	assert_gt(prov, small, "a province grows with what it folds")
	assert_lte(LedgerGalaxyLayout.size_of(repo, {"type": "province", "folded": {"manor": 9999}}, 999),
		repo.bal("ledger_star_max"))
```

- [ ] **Step 2: Run to see it fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ledger3d/test_ledger_galaxy_layout.gd -gpre_run_script=res://tests/pre_run.gd -gexit`
Expected: FAIL — `LedgerGalaxyLayout` not found.

- [ ] **Step 3: Write the layout** — create `scripts/ledger3d/ledger_galaxy_layout.gd`:

```gdscript
# scripts/ledger3d/ledger_galaxy_layout.gd
class_name LedgerGalaxyLayout
extends RefCounted
## Where each star of the LEDGER's galaxy stands (spec 2026-09-30-ledger-
## galaxy-design §4). Every pair of stars repels by their sizes, a link is a
## spring (weaker across clusters), every star is pulled home to its
## cluster's anchor — an opened manor to its province's star. A new star's
## first place is hashed from its id (no RNG) and passes run over sorted ids,
## so one snapshot always lays out the same way; a star keeps its place
## across snapshots, and `step` runs a few passes at a time so the chart
## settles over some frames and then stops. The flat chart is the same model
## in the plane. Pure: no nodes, no clock.

var pos: Dictionary = {}        # node id -> Vector3, where it stands now
var pinned: Dictionary = {}     # node id -> true: held where the pointer put it (this viewing only)
var flat := false
var passes_left := 0

var _repo: DataRepository
var _ids: Array[String] = []
var _index: Dictionary = {}
var _size := PackedFloat32Array()
var _anchor: Array[Vector3] = []
var _home_of := PackedInt32Array()     # the index of the star it settles round, or -1
var _edges := PackedInt32Array()       # pairs of indices
var _edge_k := PackedFloat32Array()
var _total := 1


## A star's radius (metres): a pool one fixed size; any other kind grows with
## the square root of its links and, on a province, of what it folds.
static func size_of(repo: DataRepository, node: Dictionary, degree: int) -> float:
	var row := Ledger.type_row(repo, String(node["type"]))
	if String(row.get("star", "instance")) == "pool":
		return repo.bal("ledger_star_pool")
	var folded := 0
	for v: Variant in (node.get("folded", {}) as Dictionary).values():
		folded += int(v)
	var r := repo.bal("ledger_star_min") + repo.bal("ledger_star_per_link") * sqrt(float(degree)) \
		+ repo.bal("ledger_star_per_fold") * sqrt(float(folded))
	return clampf(r, repo.bal("ledger_star_min"), repo.bal("ledger_star_max"))


## cluster -> its anchor (data/ledger_clusters.csv), the 2D one when flat.
static func anchors(repo: DataRepository, as_flat: bool) -> Dictionary:
	var out := {}
	for c: Dictionary in repo.ledger_clusters:
		out[String(c["cluster"])] = c["at2"] if as_flat else c["at"]
	return out


## An offset of about `r` hashed from the id: where a new star first stands.
static func jitter(id: String, r: float, as_flat: bool) -> Vector3:
	var h := id.hash()
	var a := float(h & 0xFFFF) / 65535.0 * TAU
	var b := float((h >> 16) & 0xFFFF) / 65535.0
	var reach := r * (0.5 + 0.5 * b)
	return Vector3(cos(a) * reach, 0.0 if as_flat else (b - 0.5) * r, sin(a) * reach)


## Takes a snapshot: every star it already placed keeps its place (flattened
## when flat), a new one starts round its home star (or its cluster's
## anchor), a pin on a star no longer drawn is let go, and
## ledger_galaxy_passes are set to run.
func setup(repo: DataRepository, snap: Dictionary, as_flat: bool) -> void:
	_repo = repo
	flat = as_flat
	var at := anchors(repo, as_flat)
	var degree := {}
	for l: Dictionary in snap["links"]:
		for e: String in [String(l["from"]), String(l["to"])]:
			degree[e] = int(degree.get(e, 0)) + 1
	var by_id := {}
	_ids.clear()
	for n: Dictionary in snap["nodes"]:
		by_id[String(n["id"])] = n
		_ids.append(String(n["id"]))
	_ids.sort()
	_index.clear()
	for i in _ids.size():
		_index[_ids[i]] = i
	_size.resize(_ids.size())
	_home_of.resize(_ids.size())
	_anchor.clear()
	for i in _ids.size():
		var n: Dictionary = by_id[_ids[i]]
		_size[i] = size_of(repo, n, int(degree.get(_ids[i], 0)))
		_anchor.append(at.get(String(n.get("cluster", "")), Vector3.ZERO))
		_home_of[i] = int(_index.get(String(n.get("home_id", "")), -1))
	var kept := {}
	for id: String in _ids:
		if pos.has(id):
			kept[id] = _flat(pos[id])
	for i in _ids.size():
		if kept.has(_ids[i]):
			continue
		var h := _home_of[i]
		var base: Vector3 = _anchor[i]
		if h >= 0:
			base = kept.get(_ids[h], _anchor[h])
		kept[_ids[i]] = _flat(base + jitter(_ids[i], repo.bal("ledger_galaxy_rest_m") * 2.0, as_flat))
	pos = kept
	for id: String in pinned.keys():
		if not _index.has(id):
			pinned.erase(id)
	_edges.clear()
	_edge_k.clear()
	var k := repo.bal("ledger_galaxy_spring")
	for l: Dictionary in snap["links"]:
		var a := int(_index.get(String(l["from"]), -1))
		var b := int(_index.get(String(l["to"]), -1))
		if a < 0 or b < 0 or a == b:
			continue
		_edges.append(a)
		_edges.append(b)
		var same := String(by_id[_ids[a]].get("cluster", "")) == String(by_id[_ids[b]].get("cluster", ""))
		_edge_k.append(k if same else k * repo.bal("ledger_galaxy_cross_spring"))
	_total = int(repo.bal("ledger_galaxy_passes"))
	passes_left = _total


func settled() -> bool:
	return passes_left <= 0


## Holds a star where the pointer put it; the rest settle round it.
func pin(id: String, at: Vector3) -> void:
	if not _index.has(id):
		return
	pinned[id] = true
	pos[id] = _flat(at)
	if passes_left <= 0:
		passes_left = int(_total * 0.3)


## Runs up to `passes` passes, cooling as the chart settles.
func step(passes: int) -> void:
	var n := _ids.size()
	if n == 0:
		passes_left = 0
		return
	var p: Array[Vector3] = []
	for id: String in _ids:
		p.append(pos[id])
	var rep := _repo.bal("ledger_galaxy_repel")
	var home := _repo.bal("ledger_galaxy_home")
	var rest := _repo.bal("ledger_galaxy_rest_m")
	var cap := _repo.bal("ledger_galaxy_step_max_m")
	var f: Array[Vector3] = []
	f.resize(n)
	for _k in mini(passes, passes_left):
		for i in n:
			var h := _home_of[i]
			var target: Vector3 = p[h] if h >= 0 else _anchor[i]
			f[i] = (target - p[i]) * home
		for i in n:
			for j in range(i + 1, n):
				var d := p[i] - p[j]
				var push := d / (d.length_squared() + 0.5) * rep * (_size[i] + _size[j]) * 0.5
				f[i] += push
				f[j] -= push
		for e in range(0, _edges.size(), 2):
			var a := _edges[e]
			var b := _edges[e + 1]
			var dv := p[b] - p[a]
			var ln := dv.length() + 1e-6
			var pull := dv / ln * _edge_k[e >> 1] * (ln - rest)
			f[a] += pull
			f[b] -= pull
		var cool := 0.2 + 0.8 * float(passes_left) / float(maxi(_total, 1))
		for i in n:
			if pinned.has(_ids[i]):
				continue
			var s := (f[i] * cool).limit_length(cap)
			if flat:
				s.y = 0.0
			p[i] += s
		passes_left -= 1
	for i in n:
		pos[_ids[i]] = p[i]


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z) if flat else v
```

- [ ] **Step 4: Register the class and run the tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`, then the Step 2 command.
Expected: PASS. If `test_the_clusters_settle_apart` fails, raise `ledger_galaxy_home` or lower `ledger_galaxy_cross_spring` in `balance.csv` (never a constant in code) until it passes, and say so in the report.

- [ ] **Step 5: Commit**

```bash
git add scripts/ledger3d/ledger_galaxy_layout.gd scripts/ledger3d/ledger_galaxy_layout.gd.uid tests/ledger3d/test_ledger_galaxy_layout.gd tests/ledger3d/test_ledger_galaxy_layout.gd.uid data/balance.csv
git commit -m "feat(ledger): the galaxy layout — cluster anchors, warm, stepped, flat

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 5: The links as one ribbon mesh

**Files:**
- Create: `scripts/ledger3d/ledger_link_mesh.gd`, `scenes/ledger/link.gdshader`, `tests/ledger3d/test_ledger_link_mesh.gd`

**Interfaces:**
- Produces: `class LedgerLinkMesh` — `static func arrays(segments: Array) -> Array` (a `Mesh.ARRAY_MAX` array) and `static func mesh(segments: Array) -> ArrayMesh`, `const FORMAT` (the custom-channel flags). A SEGMENT is `{id: String, a: Vector3, b: Vector3, ca: Color, cb: Color, width_px: float, shift_px: float, dashed: bool, speed: float, glow: int}` — `ca` / `cb` sRGB with their alpha the drawn opacity (`ink × pow(fade, 2.2)`), `glow` 0 none, 1 a virtuous loop, 2 a vicious one. Per segment: 4 vertices (a-left, a-right, b-left, b-right) and 6 indices. `CUSTOM0` = (the OTHER end's position, side ±1 — flipped at `b` so both ends push the same way); `CUSTOM1` = (width_px, shift_px × end sign, glow, 0); `UV` = (0 at a / 1 at b, 0 left / 1 right); `UV2` = (speed, dashed 0/1).
- Produces: `scenes/ledger/link.gdshader` uniforms `px_per_dist` (2·tan(fov/2) / the SubViewport's px height), `ortho_m_per_px` (> 0 in the flat view), `pulses`, `dashes_per_m`, `edge_soft`, `glow_virtuous`, `glow_vicious` (source_color).

- [ ] **Step 1: Write the failing test** — create `tests/ledger3d/test_ledger_link_mesh.gd`:

```gdscript
# tests/ledger3d/test_ledger_link_mesh.gd
extends GutTest
## Every link of the galaxy is one quad of ONE mesh, widened on screen by
## link.gdshader (spec 2026-09-30-ledger-galaxy-design §5).

func _seg(a: Vector3, b: Vector3) -> Dictionary:
	return {"id": "x", "a": a, "b": b, "ca": Color(1, 0, 0, 0.5), "cb": Color(0, 0, 1, 0.5),
		"width_px": 3.0, "shift_px": 2.0, "dashed": true, "speed": 0.6, "glow": 2}


func test_a_link_is_one_quad_coloured_end_to_end() -> void:
	var arr := LedgerLinkMesh.arrays([_seg(Vector3.ZERO, Vector3(10, 0, 0)), _seg(Vector3(1, 1, 1), Vector3(2, 2, 2))])
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	assert_eq(v.size(), 8)
	assert_eq(idx.size(), 12)
	assert_eq(v[0], Vector3.ZERO)
	assert_eq(v[2], Vector3(10, 0, 0))
	assert_eq(c[0], Color(1, 0, 0, 0.5), "the source's end in its colour")
	assert_eq(c[3], Color(0, 0, 1, 0.5), "the far end in the other's")


func test_each_vertex_knows_the_other_end_and_its_side() -> void:
	var arr := LedgerLinkMesh.arrays([_seg(Vector3.ZERO, Vector3(10, 0, 0))])
	var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	assert_eq(Vector3(c0[0], c0[1], c0[2]), Vector3(10, 0, 0), "a's vertices point at b")
	assert_eq(Vector3(c0[8], c0[9], c0[10]), Vector3.ZERO, "b's vertices point at a")
	assert_eq([c0[3], c0[7]], [-1.0, 1.0], "a: left, right")
	assert_eq([c0[11], c0[15]], [1.0, -1.0], "b: flipped, so both ends push the same side")


func test_width_shift_speed_dash_and_glow_travel_with_the_vertex() -> void:
	var arr := LedgerLinkMesh.arrays([_seg(Vector3.ZERO, Vector3(10, 0, 0))])
	var c1: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM1]
	assert_eq([c1[0], c1[1], c1[2]], [3.0, 2.0, 2.0], "width, shift, glow at a")
	assert_eq(c1[9], -2.0, "the shift flips with the side at b")
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	assert_eq(uv2[0], Vector2(0.6, 1.0), "speed, dashed")


func test_the_mesh_carries_both_custom_channels() -> void:
	var m := LedgerLinkMesh.mesh([_seg(Vector3.ZERO, Vector3(10, 0, 0))])
	assert_eq(m.get_surface_count(), 1)
	assert_true(m.surface_get_format(0) & (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) != 0)
	assert_true(m.surface_get_format(0) & (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) != 0)


func test_no_segments_is_an_empty_mesh() -> void:
	assert_eq(LedgerLinkMesh.mesh([]).get_surface_count(), 0)
```

- [ ] **Step 2: Run to see it fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ledger3d/test_ledger_link_mesh.gd -gpre_run_script=res://tests/pre_run.gd -gexit`
Expected: FAIL — `LedgerLinkMesh` not found.

- [ ] **Step 3: Write the mesh builder** — create `scripts/ledger3d/ledger_link_mesh.gd`:

```gdscript
# scripts/ledger3d/ledger_link_mesh.gd
class_name LedgerLinkMesh
extends RefCounted
## The galaxy's links as ONE ribbon mesh (spec 2026-09-30-ledger-galaxy-
## design §5): a quad per link, its four vertices at the two ends; link.gdshader
## widens each quad across the view by its width in SCREEN px, so a link keeps
## its weight at every zoom. Colour runs from the source's end to the far end
## (the clusters' shading), its alpha the drawn opacity. Pure arrays.

const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)


static func arrays(segments: Array) -> Array:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	for s: Dictionary in segments:
		var base := verts.size()
		for end in 2:
			var here: Vector3 = s["a"] if end == 0 else s["b"]
			var there: Vector3 = s["b"] if end == 0 else s["a"]
			var end_sign := 1.0 if end == 0 else -1.0
			for k in 2:
				var side := -1.0 if k == 0 else 1.0
				verts.append(here)
				cols.append(s["ca"] if end == 0 else s["cb"])
				uvs.append(Vector2(float(end), float(k)))
				uv2.append(Vector2(float(s["speed"]), 1.0 if bool(s["dashed"]) else 0.0))
				c0.append_array([there.x, there.y, there.z, side * end_sign])
				c1.append_array([float(s["width_px"]), float(s["shift_px"]) * end_sign, float(s["glow"]), 0.0])
		idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


static func mesh(segments: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	if not segments.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(segments), [], {}, FORMAT)
	return m
```

- [ ] **Step 4: Write the shader** — create `scenes/ledger/link.gdshader`:

```glsl
// scenes/ledger/link.gdshader
// The galaxy's links (spec 2026-09-30-ledger-galaxy-design §5), from
// LedgerLinkMesh: each vertex sits at its end of the link and knows the other
// end (CUSTOM0.xyz) and its side (CUSTOM0.w); the vertex stage pushes it
// across the view by half the link's width in SCREEN px (CUSTOM1.x) plus its
// strand's shift (CUSTOM1.y), so a link keeps its weight at every zoom — the
// border_line.gdshader practice. COLOR is sRGB (turned linear here, Forward+
// blends in linear light), its alpha the drawn opacity; light runs along a
// flow at its speed (UV2.x), a planned link is dashed (UV2.y), a running
// loop glows (CUSTOM1.z: 1 virtuous, 2 vicious). Every number is a uniform.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled,
	world_vertex_coords;

uniform float px_per_dist = 0.001;
uniform float ortho_m_per_px = 0.0;
uniform float pulses = 4.0;
uniform float dashes_per_m = 0.5;
uniform float edge_soft = 0.35;
uniform vec4 glow_virtuous : source_color = vec4(0.95, 0.82, 0.48, 1.0);
uniform vec4 glow_vicious : source_color = vec4(0.69, 0.2, 0.16, 1.0);

varying float v_speed;
varying float v_dashed;
varying float v_glow;
varying float v_len;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 here = VERTEX;
	vec3 there = CUSTOM0.xyz;
	vec3 dir = there - here;
	v_len = length(dir);
	dir = v_len > 1e-5 ? dir / v_len : vec3(1.0, 0.0, 0.0);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - here);
	vec3 across = cross(dir, to_cam);
	across = length(across) < 1e-4 ? vec3(0.0, 1.0, 0.0) : normalize(across);
	float m_per_px = ortho_m_per_px > 0.0 ? ortho_m_per_px : length(here - CAMERA_POSITION_WORLD) * px_per_dist;
	VERTEX += across * (CUSTOM0.w * 0.5 * CUSTOM1.x + CUSTOM1.y) * m_per_px;
	v_speed = UV2.x;
	v_dashed = UV2.y;
	v_glow = CUSTOM1.z;
}

void fragment() {
	float along = UV.x;
	if (v_dashed > 0.5 && fract(along * v_len * dashes_per_m) > 0.5) {
		discard;
	}
	vec3 c = to_linear(COLOR.rgb);
	float light = 0.0;
	if (v_speed > 0.0) {
		light = smoothstep(0.8, 1.0, fract(along * pulses - TIME * v_speed));
		c = mix(c, vec3(1.0, 0.95, 0.82), light * 0.8);
	}
	if (v_glow > 0.5) {
		vec3 g = v_glow > 1.5 ? glow_vicious.rgb : glow_virtuous.rgb;
		c = mix(c, g, 0.55 + 0.45 * sin(TIME * 1.6));
	}
	float edge = 1.0 - abs(UV.y * 2.0 - 1.0);
	ALBEDO = c;
	ALPHA = clamp((COLOR.a + light * 0.3 * COLOR.a) * smoothstep(0.0, edge_soft, edge), 0.0, 1.0);
}
```

- [ ] **Step 5: Register and run**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`, then the Step 2 command.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/ledger3d/ledger_link_mesh.gd scripts/ledger3d/ledger_link_mesh.gd.uid scenes/ledger/link.gdshader scenes/ledger/link.gdshader.uid tests/ledger3d/test_ledger_link_mesh.gd tests/ledger3d/test_ledger_link_mesh.gd.uid
git commit -m "feat(ledger): the galaxy's links as one screen-width ribbon mesh

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(Stage a `.uid` only if Godot wrote one.)

---

### Task 6: The night sky, the stars and the cluster haze (shaders and materials)

**Files:**
- Create: `scenes/ledger/sky.gdshader`, `scenes/ledger/star.gdshader`, `scenes/ledger/haze.gdshader`, `scenes/ledger/materials/sky.tres`, `star.tres`, `haze.tres`, `link.tres`, `tests/ledger3d/test_ledger_look_assets.gd`

**Interfaces:**
- Produces: `sky.gdshader` uniforms `bg_top`, `bg_bottom`, `neb_a`, `neb_b`, `star_col` (source_color), `neb_gain`, `flat_mode`; `star.gdshader` uniforms `emit`, `rim_gain`, `metal`, `rough` — per instance COLOR (sRGB, its alpha a brightness factor read as perceived: `pow(a, 2.2)`); `haze.gdshader` uniforms `tint` (source_color), `strength`; four `.tres` materials that hold ONLY their shader (Task 8 binds every value from data).

- [ ] **Step 1: Write the failing test** — create `tests/ledger3d/test_ledger_look_assets.gd`:

```gdscript
# tests/ledger3d/test_ledger_look_assets.gd
extends GutTest
## The galaxy's look assets hold a shader and nothing else: every number is
## data (CLAUDE.md, the map's practice).

const MATERIALS := {
	"res://scenes/ledger/materials/sky.tres": "res://scenes/ledger/sky.gdshader",
	"res://scenes/ledger/materials/star.tres": "res://scenes/ledger/star.gdshader",
	"res://scenes/ledger/materials/haze.tres": "res://scenes/ledger/haze.gdshader",
	"res://scenes/ledger/materials/link.tres": "res://scenes/ledger/link.gdshader",
}


func test_each_material_is_its_shader_and_nothing_else() -> void:
	for path: String in MATERIALS:
		var m := load(path) as ShaderMaterial
		assert_not_null(m, path)
		assert_eq(m.shader.resource_path, MATERIALS[path], path)
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("shader_parameter/"), "no value saved in " + path)
```

- [ ] **Step 2: Run to see it fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ledger3d/test_ledger_look_assets.gd -gpre_run_script=res://tests/pre_run.gd -gexit`
Expected: FAIL — the materials do not exist.

- [ ] **Step 3: The sky** — create `scenes/ledger/sky.gdshader`:

```glsl
// scenes/ledger/sky.gdshader
// The galaxy's night (spec 2026-09-30-ledger-galaxy-design §5): a warm black
// from foot to top, faint dust by noise, and sparse stars of two sizes.
// Seen straight down (the flat chart, flat_mode 1) the sky is laid in
// SCREEN space, or the stars streak into rays toward the pole.
shader_type sky;

uniform vec3 bg_top : source_color;
uniform vec3 bg_bottom : source_color;
uniform vec3 neb_a : source_color;
uniform vec3 neb_b : source_color;
uniform vec3 star_col : source_color;
uniform float neb_gain = 1.0;
uniform float flat_mode = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 c = mix(bg_bottom, bg_top, d.y * 0.5 + 0.5);
	if (flat_mode > 0.5) {
		d = normalize(vec3(SCREEN_UV * vec2(1.6, 1.0) - vec2(0.8, 0.5), 0.9));
		c = mix(bg_bottom, bg_top, 0.35 + 0.3 * SCREEN_UV.y);
	}
	float n1 = fbm(d * 2.6);
	float n2 = fbm(d * 4.3 + 7.0);
	c += (neb_a * smoothstep(0.42, 0.85, n1) * 0.30 + neb_b * smoothstep(0.5, 0.9, n2) * 0.22) * neb_gain;
	vec3 g = d * 380.0;
	vec3 f = fract(g) - 0.5;
	float s = step(0.982, hash(floor(g))) * smoothstep(0.32, 0.0, length(f)) * (0.35 + 0.65 * hash(floor(g) + 3.1));
	vec3 g2 = d * 1200.0;
	vec3 f2 = fract(g2) - 0.5;
	float s2 = step(0.97, hash(floor(g2))) * smoothstep(0.3, 0.0, length(f2)) * 0.35;
	c += star_col * (s * 2.2 + s2);
	COLOR = c;
}
```

- [ ] **Step 4: The stars** — create `scenes/ledger/star.gdshader`:

```glsl
// scenes/ledger/star.gdshader
// A galaxy star (spec 2026-09-30-ledger-galaxy-design §5): one MultiMesh of
// spheres, each instance's COLOR its cluster's sRGB colour, its alpha a
// brightness factor read as the EYE reads it (pow 2.2). Emission plus a real
// specular and a rim, so close in a star reads as polished metal or glass and
// far out as a point of light under the view's glow.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform float emit = 1.4;
uniform float rim_gain = 1.6;
uniform float metal = 0.35;
uniform float rough = 0.22;

varying vec4 col;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	col = COLOR;
}

void fragment() {
	vec3 c = to_linear(col.rgb);
	float a = pow(clamp(col.a, 0.0, 1.0), 2.2);
	ALBEDO = c * 0.55 * a;
	METALLIC = metal;
	ROUGHNESS = rough;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	EMISSION = (c * emit + c * rim * rim_gain) * a;
}
```

- [ ] **Step 5: The haze** — create `scenes/ledger/haze.gdshader`:

```glsl
// scenes/ledger/haze.gdshader
// A cluster's haze (spec 2026-09-30-ledger-galaxy-design §5): a soft round
// glow of its colour behind it, a quad that always faces the camera, added
// to the sky — enough to name the cluster at a glance, never a wash.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.83, 0.64, 0.3, 1.0);
uniform float strength = 0.075;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float a = exp(-r * r * 3.2) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = tint.rgb * strength * a;
	ALPHA = 1.0;
}
```

- [ ] **Step 6: The materials** — create each `.tres` holding only its shader. `scenes/ledger/materials/sky.tres`:

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://scenes/ledger/sky.gdshader" id="1_shader"]

[resource]
shader = ExtResource("1_shader")
```

and the same three lines' shape for `star.tres` (`star.gdshader`), `haze.tres` (`haze.gdshader`) and `link.tres` (`link.gdshader`). Run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` so the shaders get their `.uid` files.

- [ ] **Step 7: Run the test**

Run the Step 2 command.
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add scenes/ledger/sky.gdshader scenes/ledger/star.gdshader scenes/ledger/haze.gdshader scenes/ledger/materials tests/ledger3d/test_ledger_look_assets.gd
git add scenes/ledger/*.gdshader.uid tests/ledger3d/*.uid
git commit -m "feat(ledger): the galaxy's night sky, stars and cluster haze

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Names — cluster titles, who is named, never over a star

**Files:**
- Modify: `scripts/ledger3d/ledger_hud.gd`, `tests/ledger3d/test_ledger_hud.gd`

**Interfaces:**
- Produces: `LedgerHud.show_entries(entries: Array, obstacles: Array = [])` — obstacles are `Rect2`s in the HUD's px (the stars' drawn discs); `static func cull(entries, font_px, font = null, gauge = DEFAULT_GAUGE, obstacles: Array = []) -> Array`. An entry may carry `px: float` (its own font size), `ink: Color` (its own colour), `title: bool` (drawn in the title font set by `style_title`), `ring: float` (a gold ring of that px radius round `ring_at`, drawn even when its name is culled). `func style_title(font: Font, px: float) -> void`; `func style_ring(colour: Color, width_px: float) -> void`.

- [ ] **Step 1: Write the failing tests** — append to `tests/ledger3d/test_ledger_hud.gd`:

```gdscript
func test_a_name_never_sits_on_a_star() -> void:
	var star := Rect2(Vector2(90, 90), Vector2(20, 20))
	var kept := LedgerHud.cull([{"text": "Walbover", "at": Vector2(100, 100), "strong": false}], 14.0, null,
		LedgerHud.DEFAULT_GAUGE, [star])
	assert_true(kept.is_empty(), "the only place covers the star")


func test_a_name_on_a_star_takes_its_other_place() -> void:
	var star := Rect2(Vector2(90, 90), Vector2(20, 20))
	var kept := LedgerHud.cull([{"text": "Walbover", "at": Vector2(100, 100), "alt": Vector2(100, 140),
		"strong": false}], 14.0, null, LedgerHud.DEFAULT_GAUGE, [star])
	assert_eq(kept.size(), 1)
	assert_eq(kept[0]["at"], Vector2(100, 140))


func test_an_entry_keeps_its_own_size_colour_and_ring() -> void:
	var kept := LedgerHud.cull([{"text": "Economy · 32", "at": Vector2(50, 50), "strong": true, "title": true,
		"px": 20.0, "ink": Color.GOLD, "ring": 9.0, "ring_at": Vector2(50, 80)}], 14.0)
	assert_eq(kept[0]["px"], 20.0)
	assert_eq(kept[0]["ink"], Color.GOLD)
	assert_eq(kept[0]["ring"], 9.0)


func test_a_bigger_name_takes_more_room() -> void:
	var small := LedgerHud.cull([{"text": "Economy", "at": Vector2(100, 100), "strong": false},
		{"text": "War", "at": Vector2(100, 122), "strong": false}], 14.0)
	var big := LedgerHud.cull([{"text": "Economy", "at": Vector2(100, 100), "strong": false, "px": 28.0},
		{"text": "War", "at": Vector2(100, 122), "strong": false}], 14.0)
	assert_eq(small.size(), 2)
	assert_eq(big.size(), 1, "the title's box reaches the name below it")
```

- [ ] **Step 2: Run to see them fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ledger3d/test_ledger_hud.gd -gpre_run_script=res://tests/pre_run.gd -gexit`
Expected: FAIL — `cull` takes no obstacles; `px` is ignored.

- [ ] **Step 3: Implement** — in `scripts/ledger3d/ledger_hud.gd`:

Members, beside `_font`:

```gdscript
var _title_font: Font
var _title_px := 20.0
var _ring := Color(0.88, 0.73, 0.42)
var _ring_w := 3.0
```

New styling:

```gdscript
func style_title(font: Font, px: float) -> void:
	_title_font = font
	_title_px = px


func style_ring(colour: Color, width_px: float) -> void:
	_ring = colour
	_ring_w = width_px
```

`show_entries` takes the obstacles and keeps every ring even when its name is culled:

```gdscript
func show_entries(entries: Array, obstacles: Array = []) -> void:
	_entries = cull(entries, _px, _font, _gauge, obstacles)
	_rings.clear()
	for e: Dictionary in entries:
		if e.has("ring"):
			_rings.append([e["ring_at"], float(e["ring"])])
	queue_redraw()
```

with `var _rings: Array = []` among the members. In `cull`, the signature gains `obstacles: Array = []`, the box list starts from them (`var boxes: Array[Rect2] = []` then `for o in obstacles: boxes.append(o)`), and an entry's own size is used: at the loop's start `var px := float(e.get("px", font_px))`, and every `font_px` below it in the loop body becomes `px` (the width estimate, the measured width with `int(px)`, and the box). In `_draw`, draw the rings first — `for r: Array in _rings: draw_arc(r[0], r[1], 0.0, TAU, 48, _ring, _ring_w, true)` — then for each entry use `var px := float(e.get("px", _px))`, `var font := _title_font if bool(e.get("title", false)) and _title_font != null else _font` and `var ink: Color = e.get("ink", _ink if bool(e["strong"]) else Color(_ink, 0.8))` in place of `_px`, `_font` and the ink expression.

- [ ] **Step 4: Run the HUD tests**

Run the Step 2 command.
Expected: PASS (the old seven and the new four).

- [ ] **Step 5: Commit**

```bash
git add scripts/ledger3d/ledger_hud.gd tests/ledger3d/test_ledger_hud.gd
git commit -m "feat(ledger): names never over a star; titles, own sizes and colours, the selection ring

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 8: The galaxy view

**Files:**
- Rewrite: `scripts/ledger3d/ledger_view_3d.gd`
- Modify: `scenes/ledger/ledger_view.tscn`
- Create: `tests/ledger3d/test_ledger_view_galaxy.gd`
- Rewrite: `tests/ledger3d/test_ledger_strands.gd`, `tests/ledger3d/test_ledger_court_look.gd`
- Delete: `tests/ledger3d/test_ledger_view_drag.gd` (its cases move into the new file); in `tests/ledger3d/test_ledger_math.gd` delete the five tests that name `LedgerLayout` (`test_type_spheres_stand_at_their_hand_set_places`, `test_an_ego_layout_is_deterministic_and_keeps_its_layers`, `test_a_crowded_layer_stays_on_its_disc`, `test_only_layers_holding_a_sphere_have_a_disc`, `test_a_disc_reaches_just_past_its_own_spheres`)

**Interfaces:**
- Consumes: `Ledger.galaxy` (Task 2), `LedgerGalaxyLayout` (Task 4), `LedgerLinkMesh` (Task 5), the four materials (Task 6), `LedgerHud.show_entries(entries, obstacles)` / `style_title` / `style_ring` (Task 7), `LedgerOrbit`, `LedgerPick` (unchanged).
- Produces (for Task 9 and the tests): signals `sphere_selected(id)`, `thread_selected(id)`, `drill_requested(id)`, `orders_requested(id, at)` (as today); `bind(repo)`, `set_active(on)`, `show_snapshot(snap, keep_camera)`, `select(id)`, `front_view()`, `focus_cluster(cluster: String)` ("all" or a cluster id), `frame_web(id)`, `set_flat(on: bool)`, `is_flat() -> bool`, `cluster() -> String`, `screen_pos_of(id) -> Variant`, `orbit() -> LedgerOrbit`, `static link_id_of(thread_id) -> String`; test seams `stars() -> Array[String]`, `drawn(id) -> Vector3`, `segments() -> Array` (each Task 5 segment plus `link: String`, `a_id`, `b_id`), `star_colour(id) -> Color`, `settle_now()`, `link_material() -> ShaderMaterial`, `camera() -> Camera3D`, `seg_ends(seg) -> Array` (its two ends in world space, the strand's screen shift applied).

- [ ] **Step 1: Write the failing tests** — create `tests/ledger3d/test_ledger_view_galaxy.gd`:

```gdscript
# tests/ledger3d/test_ledger_view_galaxy.gd
extends GutTest
## The galaxy view (spec 2026-09-30-ledger-galaxy-design §5-§6). Headless
## instancing is fine: the dummy renderer draws nothing, the scene, its nodes
## and its maths are all there.

var repo: DataRepository
var s: GameState
var view: LedgerView3D


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	s = GameState.new_campaign(repo, 42)
	RealmEconomy.forget()
	view = (load("res://scenes/ledger/ledger_view.tscn") as PackedScene).instantiate()
	add_child_autofree(view)
	view.size = Vector2(1000, 600)
	view.bind(repo)


func after_each() -> void:
	RealmEconomy.forget()


func _show(opened: Dictionary = {}) -> Dictionary:
	var g := Ledger.galaxy(repo, s, opened)
	view.show_snapshot(g, false)
	view.settle_now()
	return g


func _first(prefix: String) -> String:
	for id: String in view.stars():
		if id.begins_with(prefix):
			return id
	return ""


func test_every_node_is_one_star_and_every_link_is_drawn() -> void:
	var g := _show()
	assert_eq(view.stars().size(), (g["nodes"] as Array).size())
	var drawn := {}
	for seg: Dictionary in view.segments():
		drawn[String(seg["link"])] = true
	for l: Dictionary in g["links"]:
		assert_true(drawn.has(String(l["id"])), String(l["id"]))


func test_a_star_wears_its_clusters_colour() -> void:
	_show()
	var c := view.star_colour("character:you")
	var want: Color = repo.ledger_palette["cluster_court"]
	assert_eq(Color(c, 1.0), Color(want, 1.0))


func test_choosing_a_cluster_dims_the_others() -> void:
	_show()
	view.focus_cluster("court")
	assert_eq(view.cluster(), "court")
	assert_eq(view.star_colour("character:you").a, 1.0)
	assert_almost_eq(view.star_colour(_first("regiment:")).a, repo.bal("ledger_galaxy_other_fade"), 0.001)
	view.focus_cluster("all")
	assert_eq(view.star_colour(_first("regiment:")).a, 1.0, "All dims nothing")


func test_selecting_a_star_lights_its_web_and_fades_the_rest() -> void:
	_show()
	view.select("character:you")
	var lit := -1.0
	var faint := -1.0
	for seg: Dictionary in view.segments():
		var mine := String(seg["a_id"]) == "character:you" or String(seg["b_id"]) == "character:you"
		if mine:
			lit = maxf(lit, (seg["ca"] as Color).a)
		else:
			faint = maxf(faint, (seg["ca"] as Color).a)
	assert_gt(lit, faint, "his web stands out")
	assert_lte(faint, pow(repo.bal("ledger_focus_fade"), 2.2) + 0.001, "the rest at the focus fade, as the eye reads it")


func test_a_vanished_selection_clears() -> void:
	var g := _show()
	view.select("character:you")
	var g2: Dictionary = g.duplicate(true)
	g2["nodes"] = (g2["nodes"] as Array).filter(func(n: Dictionary) -> bool: return String(n["id"]) != "character:you")
	g2["links"] = (g2["links"] as Array).filter(func(l: Dictionary) -> bool:
		return String(l["from"]) != "character:you" and String(l["to"]) != "character:you")
	view.show_snapshot(g2, true)
	assert_eq(view._selected, "")


func test_a_star_is_picked_in_3d_and_in_2d() -> void:
	_show()
	var id := "character:you"
	assert_eq(view._pick(view.screen_pos_of(id) as Vector2), {"kind": "sphere", "id": id})
	view.set_flat(true)
	view.settle_now()
	assert_true(view.is_flat())
	assert_eq(view.camera().projection, Camera3D.PROJECTION_ORTHOGONAL)
	for sid: String in view.stars():
		assert_eq(view.drawn(sid).y, 0.0, sid)
	assert_eq(String(view._pick(view.screen_pos_of(id) as Vector2).get("id", "")), id, "picked in the flat chart")


func test_link_width_uniform_follows_the_viewport() -> void:
	_show()
	view.size = Vector2(800, 500)
	view._fit_viewport()
	view._update_link_uniforms()
	var h := float(view._viewport.size.y)
	assert_almost_eq(float(view.link_material().get_shader_parameter("px_per_dist")),
		2.0 * tan(deg_to_rad(view.camera().fov) * 0.5) / h, 1e-7)


func test_a_drag_pins_the_star_and_moves_only_its_links() -> void:
	_show()
	var id := "character:you"
	var before := {}
	for seg: Dictionary in view.segments():
		before[String(seg["id"])] = [seg["a"], seg["b"]]
	var at := view.screen_pos_of(id) as Vector2
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	var mm := InputEventMouseMotion.new()
	mm.position = at + Vector2(60, 0)
	mm.relative = Vector2(60, 0)
	view._gui_input(mm)
	var up := press.duplicate() as InputEventMouseButton
	up.pressed = false
	up.position = mm.position
	view._gui_input(up)
	assert_true(view._lay.pinned.has(id), "held where the pointer left it")
	for seg: Dictionary in view.segments():
		var mine := String(seg["a_id"]) == id or String(seg["b_id"]) == id
		var was: Array = before[String(seg["id"])]
		if not mine:
			assert_eq([seg["a"], seg["b"]], was, "untouched: " + String(seg["id"]))


func test_a_node_and_an_edge_written_down_are_drawn() -> void:
	repo.ledger_types.append({"type_id": "shrine", "layer": "things", "lenses": "court|all", "label": "Shrines",
		"icon": "", "x": "0", "z": "0", "instances": "static", "status": "live", "milestone": "",
		"cluster": "court", "fold_to": "", "star": "instance"})
	repo.ledger_links.append({"link_id": "venerates", "from_type": "character", "to_type": "shrine",
		"verb": "venerates", "lenses": "court|all", "status": "live", "resolver": "static", "governor_seat": "",
		"governor_kind": "", "milestone": "", "planned_note": "", "look": "tie"})
	repo.ledger_static_nodes.append({"node_id": "shrine:saint_odo", "type_id": "shrine", "label": "Shrine of St Odo",
		"note": ""})
	repo.ledger_static_links.append({"link_id": "venerates", "from": "character:you", "to": "shrine:saint_odo",
		"flow": 40, "note": ""})
	_show()
	assert_has(view.stars(), "shrine:saint_odo")
	assert_true(view.segments().any(func(seg: Dictionary) -> bool:
		return String(seg["link"]) == "venerates|character:you|shrine:saint_odo"))
```

- [ ] **Step 2: Rewrite the strand and court tests** — replace the body of `tests/ledger3d/test_ledger_strands.gd` below its `before_each` / `after_each` (keep the venal-marshal setup, drop the `view.size`-independent `_press` helper) with:

```gdscript
func _strands(g: Dictionary) -> Array:
	var link := ""
	for l: Dictionary in g["links"]:
		if String(l["type"]) == "supplies_out" and (l["accounts"] as Array).size() == 2:
			link = String(l["id"])
	return view.segments().filter(func(seg: Dictionary) -> bool: return String(seg["link"]) == link)


func test_two_accounts_are_two_strands_a_gap_apart() -> void:
	var g := Ledger.galaxy(repo, state, {})
	view.show_snapshot(g, false)
	view.settle_now()
	var st := _strands(g)
	assert_eq(st.size(), 2, "a venal marshal's word and the regiment's count")
	assert_true(String(st[0]["id"]).ends_with("#0") and String(st[1]["id"]).ends_with("#1"))
	var w0 := float(st[0]["width_px"])
	var w1 := float(st[1]["width_px"])
	assert_gt(w0, w1, "the claim is wider than what arrived")
	assert_almost_eq(absf(float(st[1]["shift_px"]) - float(st[0]["shift_px"])),
		(w0 + w1) * 0.5 + repo.bal("ledger_strand_gap_px") * view._window_scale(), 0.001, "edge to edge, a gap apart")


func test_a_strand_is_picked_by_its_own_id() -> void:
	var g := Ledger.galaxy(repo, state, {})
	view.show_snapshot(g, false)
	view.settle_now()
	var seg: Dictionary = _strands(g)[1]
	var ends := view.seg_ends(seg)
	var mid: Vector3 = ((ends[0] as Vector3) + (ends[1] as Vector3)) * 0.5
	var at := view.camera().unproject_position(mid) / view._window_scale()
	assert_eq(view._pick(at), {"kind": "thread", "id": String(seg["id"])})
```

Replace `tests/ledger3d/test_ledger_court_look.gd`'s tests (keep its header comment's first sentence, drop the disc sentence; `before_each` shows `Ledger.galaxy(repo, state, {})` and calls `view.settle_now()`):

```gdscript
func _ties() -> Array:
	return view.segments().filter(func(seg: Dictionary) -> bool:
		return String(Ledger.link_row(repo, String(seg["link"]).get_slice("|", 0))["look"]) in ["tie", "kin"])


func test_a_court_tie_is_a_thin_cord_by_its_feeling() -> void:
	for seg: Dictionary in _ties():
		var w := float(seg["width_px"]) / view._window_scale()
		assert_true(w >= repo.bal("ledger_tie_min_px") - 0.001 and w <= repo.bal("ledger_tie_max_px") + 0.001,
			String(seg["id"]))


func test_at_rest_the_players_ties_are_lit_and_the_rest_stand_back() -> void:
	var rest := pow(repo.bal("ledger_tie_rest_fade"), 2.2)
	for seg: Dictionary in _ties():
		var mine := String(seg["a_id"]) == LedgerView3D.EGO_AT_REST or String(seg["b_id"]) == LedgerView3D.EGO_AT_REST
		var a := (seg["ca"] as Color).a
		if mine:
			assert_gt(a, rest + 0.01, "the player's tie is lit: " + String(seg["id"]))
		else:
			assert_lte(a, rest + 0.001, "stands back: " + String(seg["id"]))


func test_selecting_someone_makes_them_the_lit_one() -> void:
	var other := ""
	for seg: Dictionary in _ties():
		if String(seg["a_id"]) != LedgerView3D.EGO_AT_REST and String(seg["b_id"]) != LedgerView3D.EGO_AT_REST:
			other = String(seg["a_id"])
			break
	view.select(other)
	for seg: Dictionary in _ties():
		if String(seg["a_id"]) == other or String(seg["b_id"]) == other:
			assert_gt((seg["ca"] as Color).a, pow(repo.bal("ledger_focus_fade"), 2.2) + 0.01, String(seg["id"]))
```

(`EGO_AT_REST`'s rule now holds in every tab, not the Court tab alone — a controller ruling recorded in Step 6's commit and in the spec §6 at Task 10.)

- [ ] **Step 3: Run to see them fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ledger3d/test_ledger_view_galaxy.gd -gpre_run_script=res://tests/pre_run.gd -gexit`
Expected: FAIL — `settle_now`, `stars`, `segments` not found.

- [ ] **Step 4: The scene** — replace `scenes/ledger/ledger_view.tscn` with:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/ledger3d/ledger_view_3d.gd" id="1_view"]
[ext_resource type="Script" path="res://scripts/ledger3d/ledger_hud.gd" id="2_hud"]
[ext_resource type="Material" path="res://scenes/ledger/materials/sky.tres" id="3_sky"]

[sub_resource type="Sky" id="Sky_ledger"]
sky_material = ExtResource("3_sky")

[sub_resource type="Environment" id="Environment_ledger"]
background_mode = 2
sky = SubResource("Sky_ledger")
ambient_light_source = 2
ambient_light_color = Color(0.62, 0.56, 0.48, 1)
ambient_light_energy = 0.4
tonemap_mode = 4
glow_enabled = true
glow_blend_mode = 1

[node name="LedgerView3D" type="Control"]
clip_contents = true
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_view")

[node name="Viewport" type="SubViewport" parent="."]
unique_name_in_owner = true
own_world_3d = true
msaa_3d = 2
render_target_update_mode = 0

[node name="Env" type="WorldEnvironment" parent="Viewport"]
unique_name_in_owner = true
environment = SubResource("Environment_ledger")

[node name="Sun" type="DirectionalLight3D" parent="Viewport"]
transform = Transform3D(0.866025, -0.353553, 0.353553, 0, 0.707107, 0.707107, -0.5, -0.612372, 0.612372, 0, 12, 0)
light_color = Color(1, 0.945, 0.84, 1)
light_energy = 1.6

[node name="Camera" type="Camera3D" parent="Viewport"]
unique_name_in_owner = true
fov = 45.0
far = 4000.0

[node name="Haze" type="Node3D" parent="Viewport"]
unique_name_in_owner = true

[node name="Links" type="MeshInstance3D" parent="Viewport"]
unique_name_in_owner = true
cast_shadow = 0

[node name="Stars" type="MultiMeshInstance3D" parent="Viewport"]
unique_name_in_owner = true
cast_shadow = 0

[node name="Display" type="TextureRect" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
expand_mode = 1

[node name="Hud" type="Control" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("2_hud")
```

(`background_mode = 2` is BG_SKY, `tonemap_mode = 4` AgX, `glow_blend_mode = 1` screen — verify each enum against Godot 4.7's `Environment` docs and correct the number if it differs. The glow's intensity and threshold, and every sky colour, are bound from data in `bind`.)

- [ ] **Step 5: The view** — replace `scripts/ledger3d/ledger_view_3d.gd` with:

```gdscript
# scripts/ledger3d/ledger_view_3d.gd
class_name LedgerView3D
extends Control
## The LEDGER's galaxy (spec 2026-09-30-ledger-galaxy-design §5-§6): every
## object the crown knows of is a small bright star in its tab's cluster, the
## links shade from one cluster's colour to the other's, on a warm black
## night. It draws a snapshot (Ledger.galaxy) and signals what the player did;
## it reads no autoload and changes no state. It renders into a SubViewport at
## WINDOW resolution shown by a TextureRect, and only while active. How a
## star or a link is drawn comes from its type's row alone (`cluster`, `star`,
## `look` — spec §3b): no type is named here, so a type or link type the owner
## adds in data is drawn with no change here.

signal sphere_selected(id: String)
signal thread_selected(id: String)
signal drill_requested(id: String)
signal orders_requested(id: String, at: Vector2)

const CLICK_SLOP := 10.0
const EGO_AT_REST := "character:you"  # the player, whose ties are lit while no one is selected
const FLAT_PITCH := -89.9
const STAR_MAT := preload("res://scenes/ledger/materials/star.tres")
const LINK_MAT := preload("res://scenes/ledger/materials/link.tres")
const HAZE_MAT := preload("res://scenes/ledger/materials/haze.tres")

@onready var _viewport: SubViewport = %Viewport
@onready var _display: TextureRect = %Display
@onready var _env: WorldEnvironment = %Env
@onready var _camera: Camera3D = %Camera
@onready var _stars: MultiMeshInstance3D = %Stars
@onready var _links: MeshInstance3D = %Links
@onready var _haze_root: Node3D = %Haze
@onready var _hud: LedgerHud = %Hud

var _repo: DataRepository
var _pal: Dictionary = {}
var _cluster_col: Dictionary = {}   # cluster -> Color
var _orbit := LedgerOrbit.new()
var _lay := LedgerGalaxyLayout.new()
var _snap: Dictionary = {}
var _nodes: Dictionary = {}
var _order: Array[String] = []
var _size: Dictionary = {}
var _drawn: Dictionary = {}
var _from: Dictionary = {}
var _mode_left := 0.0
var _flat := false
var _segs: Array = []
var _near: Dictionary = {}
var _star_mat: ShaderMaterial
var _link_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _haze: Dictionary = {}
var _cluster := "all"
var _selected := ""
var _hovered := ""
var _framed := false
var _button := 0
var _press_at := Vector2.ZERO
var _moved := false
var _drag_id := ""
var _fly_left := 0.0
var _fly_from: Array = []
var _fly_to: Array = []
var _last_pose := Transform3D()


func _ready() -> void:
	_display.texture = _viewport.get_texture()
	resized.connect(_fit_viewport)
	_fit_viewport()
	set_process(false)


func bind(repo: DataRepository) -> void:
	_repo = repo
	_pal = repo.ledger_palette
	for c: Dictionary in repo.ledger_clusters:
		_cluster_col[String(c["cluster"])] = _pal[String(c["colour"])]
	_orbit.distance = repo.bal("ledger_camera_distance")
	_orbit.pitch = repo.bal("ledger_camera_pitch_deg")
	_orbit.min_distance = repo.bal("ledger_camera_min_m")
	_orbit.max_distance = repo.bal("ledger_camera_max_m")
	var env := _env.environment
	env.glow_intensity = repo.bal("ledger_glow_intensity")
	env.glow_hdr_threshold = repo.bal("ledger_glow_threshold")
	_sky_mat = env.sky.sky_material.duplicate() as ShaderMaterial
	env.sky.sky_material = _sky_mat
	_sky_mat.set_shader_parameter("bg_top", _pal["sky_top"])
	_sky_mat.set_shader_parameter("bg_bottom", _pal["sky_bottom"])
	_sky_mat.set_shader_parameter("neb_a", _pal["nebula_a"])
	_sky_mat.set_shader_parameter("neb_b", _pal["nebula_b"])
	_sky_mat.set_shader_parameter("star_col", _pal["stars"])
	_star_mat = STAR_MAT.duplicate() as ShaderMaterial
	_star_mat.set_shader_parameter("emit", repo.bal("ledger_star_emit"))
	_star_mat.set_shader_parameter("rim_gain", repo.bal("ledger_star_rim"))
	_star_mat.set_shader_parameter("metal", repo.bal("ledger_star_metallic"))
	_star_mat.set_shader_parameter("rough", repo.bal("ledger_star_roughness"))
	_stars.material_override = _star_mat
	_link_mat = LINK_MAT.duplicate() as ShaderMaterial
	_link_mat.set_shader_parameter("pulses", repo.bal("ledger_light_pulses"))
	_link_mat.set_shader_parameter("dashes_per_m", repo.bal("ledger_dashes_per_m"))
	_link_mat.set_shader_parameter("edge_soft", repo.bal("ledger_link_edge_soft"))
	_link_mat.set_shader_parameter("glow_virtuous", _pal["loop_virtuous"])
	_link_mat.set_shader_parameter("glow_vicious", _pal["loop_vicious"])
	_links.material_override = _link_mat
	_hud.style(UiPalette.role_font("body"), repo.bal("ledger_label_px"), _pal["label_ink"], _pal["label_halo"],
		int(repo.bal("ledger_label_halo_px")))
	_hud.style_gauges(repo.bal("ledger_gauge_radius_px"), repo.bal("ledger_gauge_width_px"),
		repo.bal("ledger_gauge_gap_px"), repo.bal("ledger_gauge_caption_px"), _pal["gauge_fill"], _pal["gauge_track"])
	_hud.style_title(UiPalette.role_font("header"), repo.bal("ledger_title_px"))
	_hud.style_ring(_pal["focus_ring"], repo.bal("ledger_ring_px"))
	_apply_camera()


func _window_scale() -> float:
	return maxf(get_viewport().get_final_transform().get_scale().x, 1.0)


func _fit_viewport() -> void:
	var s := _window_scale()
	_viewport.size = Vector2i(maxi(1, int(size.x * s)), maxi(1, int(size.y * s)))
	if _framed and _repo != null and not _snap.is_empty():
		_frame_on(_cluster_ids(), true)
	if _repo != null:
		_update_link_uniforms()


func set_active(on: bool) -> void:
	visible = on
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	set_process(on)
	if on:
		_fit_viewport()


## Draw a snapshot. Stars already placed keep their places (the layout is
## warm); a star under a drag or the selection that is no longer drawn lets go.
func show_snapshot(snap: Dictionary, keep_camera: bool) -> void:
	_snap = snap
	_nodes.clear()
	var degree := {}
	for n: Dictionary in snap["nodes"]:
		_nodes[String(n["id"])] = n
	for l: Dictionary in snap["links"]:
		for e: String in [String(l["from"]), String(l["to"])]:
			degree[e] = int(degree.get(e, 0)) + 1
	_order.clear()
	for id: String in _nodes:
		_order.append(id)
	_order.sort()
	_size.clear()
	for id: String in _order:
		_size[id] = LedgerGalaxyLayout.size_of(_repo, _nodes[id], int(degree.get(id, 0)))
	_lay.setup(_repo, snap, _flat)
	for id: String in _drawn.keys():
		if not _nodes.has(id):
			_drawn.erase(id)
	if not _nodes.has(_selected):
		_selected = ""
	if not _nodes.has(_hovered):
		_hovered = ""
	if _drag_id != "" and not _nodes.has(_drag_id):
		_end_gesture()
	_sync_drawn()
	_build_stars()
	_build_haze()
	_restyle()
	if not keep_camera:
		_frame_on(_cluster_ids(), true)
	_update_hud()


func select(id: String) -> void:
	_selected = id if _nodes.has(id) else ""
	_restyle()
	_update_hud()


func front_view() -> void:
	_frame_on(_cluster_ids(), false)


## Choose a cluster ("all" for the whole galaxy): the camera flies to frame it
## and the other clusters dim (spec §6); nothing is hidden.
func focus_cluster(cluster_id: String) -> void:
	_cluster = cluster_id
	_restyle()
	_frame_on(_cluster_ids(), false)
	_update_hud()


## Frame a star and its neighbours.
func frame_web(id: String) -> void:
	if not _nodes.has(id):
		return
	var ids: Array = [id]
	for l: Dictionary in _snap.get("links", []):
		if String(l["from"]) == id:
			ids.append(String(l["to"]))
		elif String(l["to"]) == id:
			ids.append(String(l["from"]))
	_frame_on(ids, false)


## Lay the chart flat (2D, seen straight down) or stand it up again; the
## stars ease between their two places over ledger_galaxy_mode_ease_s.
func set_flat(on: bool) -> void:
	if on == _flat:
		return
	_flat = on
	_sky_mat.set_shader_parameter("flat_mode", 1.0 if on else 0.0)
	if _snap.is_empty():
		_orbit.pitch = FLAT_PITCH if on else _repo.bal("ledger_camera_pitch_deg")
		_apply_camera()
		return
	_from = _drawn.duplicate()
	_lay.setup(_repo, _snap, on)
	_mode_left = _repo.bal("ledger_galaxy_mode_ease_s")
	_orbit.yaw = 0.0
	_orbit.pitch = FLAT_PITCH if on else _repo.bal("ledger_camera_pitch_deg")
	_frame_on(_cluster_ids(), true)


func is_flat() -> bool:
	return _flat


func cluster() -> String:
	return _cluster


func orbit() -> LedgerOrbit:
	return _orbit


func camera() -> Camera3D:
	return _camera


func link_material() -> ShaderMaterial:
	return _link_mat


func stars() -> Array[String]:
	return _order


func drawn(id: String) -> Vector3:
	return _drawn.get(id, Vector3.ZERO)


func segments() -> Array:
	return _segs


func star_colour(id: String) -> Color:
	var i := _order.find(id)
	return _stars.multimesh.get_instance_color(i) if i >= 0 and _stars.multimesh != null else Color(0, 0, 0, 0)


## Settles the chart at once and ends any ease (tests and shots).
func settle_now() -> void:
	while not _lay.settled():
		_lay.step(10)
	_mode_left = 0.0
	_sync_drawn()
	_place_stars()
	_rebuild_links()
	_place_haze()
	if _framed:
		_frame_on(_cluster_ids(), true)
	elif not _fly_to.is_empty():
		_ease_camera(1.0)
	_fly_left = 0.0
	_apply_camera()
	_update_link_uniforms()
	_update_hud()


func screen_pos_of(id: String) -> Variant:
	if not _drawn.has(id) or _camera.is_position_behind(_drawn[id]):
		return null
	return _camera.unproject_position(_drawn[id]) / _window_scale()


# --- stars, links, haze ------------------------------------------------------

func _sync_drawn() -> void:
	var total := maxf(_repo.bal("ledger_galaxy_mode_ease_s"), 0.001)
	var t := 1.0 if _mode_left <= 0.0 else 1.0 - _mode_left / total
	for id: String in _order:
		var to: Vector3 = _lay.pos[id]
		_drawn[id] = (_from.get(id, to) as Vector3).lerp(to, t) if t < 1.0 else to


func _build_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	mm.mesh = sphere
	mm.instance_count = _order.size()
	_stars.multimesh = mm
	_place_stars()


func _place_stars() -> void:
	var mm := _stars.multimesh
	if mm == null:
		return
	for i in _order.size():
		var r := float(_size[_order[i]])
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(r, r, r)), _drawn[_order[i]]))


func _cluster_of(id: String) -> String:
	return String((_nodes.get(id, {}) as Dictionary).get("cluster", ""))


func _look(l: Dictionary) -> String:
	return String(Ledger.link_row(_repo, String(l["type"])).get("look", "flow"))


## Colours and fades from the selection and the chosen cluster, then the links.
func _restyle() -> void:
	_near.clear()
	if _selected != "":
		_near[_selected] = true
		for l: Dictionary in _snap.get("links", []):
			if String(l["from"]) == _selected or String(l["to"]) == _selected:
				_near[String(l["from"])] = true
				_near[String(l["to"])] = true
	var mm := _stars.multimesh
	if mm != null:
		for i in _order.size():
			mm.set_instance_color(i, _star_colour(_order[i]))
	_rebuild_links()
	_place_haze()


func _star_colour(id: String) -> Color:
	var n: Dictionary = _nodes[id]
	var c: Color = _pal["sphere_planned"] if String(n.get("status", "live")) == "planned" \
		else _cluster_col.get(_cluster_of(id), _pal["sphere_planned"])
	var f := 1.0
	if _selected != "" and not _near.has(id):
		f = minf(f, _repo.bal("ledger_focus_fade"))
	if _cluster != "all" and _cluster_of(id) != _cluster:
		f = minf(f, _repo.bal("ledger_galaxy_other_fade"))
	return Color(c, f)


func _rebuild_links() -> void:
	_segs = _segments()
	_links.mesh = LedgerLinkMesh.mesh(_segs)
	_update_link_uniforms()


func _update_link_uniforms() -> void:
	if _link_mat == null:
		return
	var h := float(maxi(_viewport.size.y, 1))
	_link_mat.set_shader_parameter("px_per_dist", 2.0 * tan(deg_to_rad(_camera.fov) * 0.5) / h)
	_link_mat.set_shader_parameter("ortho_m_per_px", _camera.size / h if _flat else 0.0)


func _running_links() -> Dictionary:
	var out := {}
	for lp: Dictionary in _snap.get("loops", []):
		if bool(lp["running"]):
			for t: String in lp["links"]:
				out[t] = String(lp["kind"])
	return out


func _pair_key(l: Dictionary) -> Array:
	var key := [String(l["from"]), String(l["to"])]
	key.sort()
	return key


func _segments() -> Array:
	var out: Array = []
	var pairs := {}
	for l: Dictionary in _snap.get("links", []):
		var key := _pair_key(l)
		pairs[key] = int(pairs.get(key, 0)) + 1
	var running := _running_links()
	var ws := _window_scale()
	for l: Dictionary in _snap.get("links", []):
		var a_id := String(l["from"])
		var b_id := String(l["to"])
		if not _drawn.has(a_id) or not _drawn.has(b_id):
			continue
		var a: Vector3 = _drawn[a_id]
		var b: Vector3 = _drawn[b_id]
		if a.is_equal_approx(b):
			continue
		var cols := _link_colours(l)
		var alpha := _ink(l) * pow(_link_fade(l), 2.2)
		var wide := _repo.bal("ledger_focus_width") if _selected != "" and (a_id == _selected or b_id == _selected) else 1.0
		var key := _pair_key(l)
		var pair_shift := 0.0
		if int(pairs[key]) > 1:
			pair_shift = _repo.bal("ledger_pair_offset_px") * (1.0 if a_id == key[0] else -1.0)
		var planned := String(l["status"]) == "planned" or bool(l.get("vacant", false))
		var speed := 0.0
		if not planned and _look(l) == "flow" and l["flow"] != null and int(l["flow"]) > 0:
			var t := inverse_lerp(_repo.bal("ledger_link_min_px"), _repo.bal("ledger_link_max_px"), _width_px(l))
			speed = _repo.bal("ledger_light_speed") * (0.4 + 0.6 * clampf(t, 0.0, 1.0))
		var glow := {"virtuous": 1, "vicious": 2}.get(String(running.get(String(l["type"]), "")), 0) as int
		for st: Array in _split(l):
			out.append({"id": String(st[0]), "link": String(l["id"]), "a_id": a_id, "b_id": b_id, "a": a, "b": b,
				"ca": Color(cols[0] as Color, alpha), "cb": Color(cols[1] as Color, alpha),
				"width_px": _width_px(st[1]) * wide * ws, "shift_px": (float(st[2]) + pair_shift) * ws,
				"dashed": planned, "speed": speed, "glow": glow})
	return out


## The strands a link is drawn as: itself while its accounts agree; one per
## account when they differ — "<link id>#<i>", each its own width, side by side
## ledger_strand_gap_px apart edge to edge, the bundle centred on the link.
## Each entry is [thread id, the link as that strand, its shift in px].
func _split(l: Dictionary) -> Array:
	var accs: Array = l.get("accounts", [])
	if accs.size() <= 1:
		return [[String(l["id"]), l, 0.0]]
	var items: Array = []
	var widths: Array[float] = []
	for acc: Dictionary in accs:
		var one := l.duplicate()
		one["flow"] = acc["value"]
		one["accounts"] = [acc]
		items.append(one)
		widths.append(_width_px(one))
	var gap := _repo.bal("ledger_strand_gap_px")
	var centres: Array[float] = [0.0]
	for i in range(1, items.size()):
		centres.append(centres[i - 1] + widths[i - 1] * 0.5 + gap + widths[i] * 0.5)
	var mid := (centres[0] - widths[0] * 0.5 + centres[-1] + widths[-1] * 0.5) * 0.5
	var out: Array = []
	for i in items.size():
		out.append(["%s#%d" % [l["id"], i], items[i], centres[i] - mid])
	return out


## The link a picked thread belongs to: a strand's id less its "#<i>".
static func link_id_of(thread_id: String) -> String:
	var at := thread_id.rfind("#")
	if at > 0 and thread_id.substr(at + 1).is_valid_int():
		return thread_id.substr(0, at)
	return thread_id


func _width_px(l: Dictionary) -> float:
	match _look(l):
		"tie", "kin":
			var feel := absf(float(l["flow"])) if l["flow"] != null else 0.0
			return lerpf(_repo.bal("ledger_tie_min_px"), _repo.bal("ledger_tie_max_px"),
				clampf(feel / _repo.bal("ledger_tie_ref"), 0.0, 1.0))
		"structure":
			return _repo.bal("ledger_link_min_px")
	if l["flow"] == null:
		return _repo.bal("ledger_link_vague_px")
	var f := float(l["flow"])
	if f <= 0.0:
		return _repo.bal("ledger_link_min_px")
	var t := clampf(log(1.0 + f) / log(1.0 + _repo.bal("ledger_thread_flow_ref")), 0.0, 1.0)
	return lerpf(_repo.bal("ledger_link_min_px"), _repo.bal("ledger_link_max_px"), t)


func _link_colours(l: Dictionary) -> Array:
	if String(l["status"]) == "planned" or bool(l.get("vacant", false)):
		return [_pal["thread_planned"], _pal["thread_planned"]]
	match _look(l):
		"kin":
			return [_pal["thread_kin"], _pal["thread_kin"]]
		"tie":
			var c: Color = _pal["thread_pos"] if int(l.get("sentiment", 0)) >= 0 else _pal["thread_neg"]
			return [c, c]
	var ca: Color = _cluster_col.get(_cluster_of(String(l["from"])), _pal["thread_live"])
	var cb: Color = _cluster_col.get(_cluster_of(String(l["to"])), _pal["thread_live"])
	var accs: Array = l["accounts"]
	if not accs.is_empty():
		var age := clampf(float(int(_snap["day"]) - int(accs[0]["day"])) / _repo.bal("ledger_age_full_days"), 0.0, 1.0)
		ca = ca.lerp(_pal["thread_aged"], age)
		cb = cb.lerp(_pal["thread_aged"], age)
	return [ca, cb]


func _ink(l: Dictionary) -> float:
	var accs: Array = l["accounts"]
	if accs.is_empty():
		return 1.0
	match String(accs[0]["level"]):
		"general":
			return _repo.bal("ledger_ink_general")
		"basic":
			return _repo.bal("ledger_ink_basic")
	return 1.0


## How much of a link shows, as the EYE reads it (spec §6): the selected
## star's web lit, the rest at ledger_focus_fade; at rest the court is read
## one person's web at a time (the player's ties lit, other ties at
## ledger_tie_rest_fade) and a link crossing clusters stands back at
## ledger_cross_rest_fade; a chosen cluster dims links that do not touch it.
func _link_fade(l: Dictionary) -> float:
	var a := String(l["from"])
	var b := String(l["to"])
	var f := 1.0
	if _selected != "":
		f = 1.0 if a == _selected or b == _selected else _repo.bal("ledger_focus_fade")
	elif _look(l) in ["tie", "kin"] and _nodes.has(EGO_AT_REST):
		if a != EGO_AT_REST and b != EGO_AT_REST:
			f = _repo.bal("ledger_tie_rest_fade")
	elif _cluster_of(a) != _cluster_of(b):
		f = _repo.bal("ledger_cross_rest_fade")
	if _cluster != "all" and _cluster_of(a) != _cluster and _cluster_of(b) != _cluster:
		f = minf(f, _repo.bal("ledger_galaxy_other_fade"))
	return f


func _build_haze() -> void:
	for c in _haze_root.get_children():
		c.queue_free()
	_haze.clear()
	for row: Dictionary in _repo.ledger_clusters:
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		var m := HAZE_MAT.duplicate() as ShaderMaterial
		m.set_shader_parameter("tint", _pal[String(row["colour"])])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_haze_root.add_child(mi)
		_haze[String(row["cluster"])] = mi
	_place_haze()


func _place_haze() -> void:
	for c: String in _haze:
		var mi: MeshInstance3D = _haze[c]
		var sum := Vector3.ZERO
		var n := 0
		for id: String in _order:
			if _cluster_of(id) == c:
				sum += _drawn[id]
				n += 1
		mi.visible = n > 0
		if n == 0:
			continue
		var mid := sum / float(n)
		var rad := 0.0
		for id: String in _order:
			if _cluster_of(id) == c:
				rad += (_drawn[id] as Vector3).distance_to(mid)
		rad = maxf(rad / float(n), 8.0)
		(mi.mesh as QuadMesh).size = Vector2.ONE * rad * _repo.bal("ledger_haze_scale")
		mi.position = mid
		var dim := _repo.bal("ledger_galaxy_other_fade") if _cluster != "all" and c != _cluster else 1.0
		(mi.material_override as ShaderMaterial).set_shader_parameter("strength", _repo.bal("ledger_haze_strength") * dim)


# --- camera ------------------------------------------------------------------

func _cluster_ids() -> Array:
	if _cluster == "all":
		return _order.duplicate()
	return _order.filter(func(id: String) -> bool: return _cluster_of(id) == _cluster)


func _frame_on(ids: Array, instant: bool) -> void:
	var points: Array[Vector3] = []
	for id: String in ids:
		if not _drawn.has(id):
			continue
		var r := float(_size.get(id, 1.0))
		points.append((_drawn[id] as Vector3) - Vector3(r, r, r))
		points.append((_drawn[id] as Vector3) + Vector3(r, r, r))
	if points.is_empty():
		return
	var sz := size if size.x >= 2.0 and size.y >= 2.0 else Vector2(1280, 720)
	var side := _repo.bal("ledger_frame_side_px") / sz.x
	var top := _repo.bal("ledger_frame_top_px") / sz.y
	var bottom := _repo.bal("ledger_frame_bottom_px") / sz.y
	var safe := Rect2(side, top, maxf(1.0 - 2.0 * side, 0.1), maxf(1.0 - top - bottom, 0.1))
	var pitch := FLAT_PITCH if _flat else _repo.bal("ledger_camera_pitch_deg")
	var f := LedgerOrbit.frame(points, 0.0, pitch, _camera.fov, sz.x / sz.y, safe)
	if f.is_empty():
		return
	_fly_from = [_orbit.target, _orbit.distance, _orbit.yaw, _orbit.pitch]
	_fly_to = [f["target"], clampf(float(f["distance"]), _orbit.min_distance, _orbit.max_distance), 0.0, pitch]
	_framed = true
	_fly_left = 0.0 if instant else _repo.bal("ledger_galaxy_fly_s")
	if _fly_left <= 0.0:
		_ease_camera(1.0)


func _ease_camera(t: float) -> void:
	var k := smoothstep(0.0, 1.0, t)
	_orbit.target = (_fly_from[0] as Vector3).lerp(_fly_to[0], k)
	_orbit.distance = lerpf(float(_fly_from[1]), float(_fly_to[1]), k)
	_orbit.yaw = lerpf(float(_fly_from[2]), float(_fly_to[2]), k)
	_orbit.pitch = lerpf(float(_fly_from[3]), float(_fly_to[3]), k)
	_apply_camera()


func _apply_camera() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if _flat else Camera3D.PROJECTION_PERSPECTIVE
	if _flat:
		_camera.size = _orbit.distance * 2.0 * tan(deg_to_rad(_camera.fov) * 0.5)
	_camera.transform = _orbit.pose()


func _process(delta: float) -> void:
	if _repo == null or _snap.is_empty():
		return
	var moved := false
	if not _lay.settled():
		var t0 := Time.get_ticks_usec()
		var budget := _repo.bal("ledger_galaxy_ms_per_frame") * 1000.0
		while not _lay.settled() and float(Time.get_ticks_usec() - t0) < budget:
			_lay.step(1)
		moved = true
	if _mode_left > 0.0:
		_mode_left = maxf(_mode_left - delta, 0.0)
		moved = true
	if moved:
		_sync_drawn()
		_place_stars()
		_rebuild_links()
		_place_haze()
	if _fly_left > 0.0:
		_fly_left = maxf(_fly_left - delta, 0.0)
		_ease_camera(1.0 - _fly_left / maxf(_repo.bal("ledger_galaxy_fly_s"), 0.001))
	if moved or not _camera.transform.is_equal_approx(_last_pose):
		_last_pose = _camera.transform
		_update_link_uniforms()
		_update_hud()


# --- names ---------------------------------------------------------------------

## Metres per SubViewport px at a point.
func _m_per_px_at(p: Vector3) -> float:
	var h := float(maxi(_viewport.size.y, 1))
	if _flat:
		return _camera.size / h
	return p.distance_to(_camera.global_position) * 2.0 * tan(deg_to_rad(_camera.fov) * 0.5) / h


func _screen_radius(id: String) -> float:
	return float(_size[id]) / _m_per_px_at(_drawn[id]) / _window_scale()


func _update_hud() -> void:
	if _repo == null:
		return
	var entries: Array = []
	var obstacles: Array = []
	var label_px := _repo.bal("ledger_label_px")
	var lift := _repo.bal("ledger_label_lift_px")
	for row: Dictionary in _repo.ledger_clusters:
		var c := String(row["cluster"])
		var n := 0
		var box := Rect2()
		for id: String in _order:
			if _cluster_of(id) != c:
				continue
			var at: Variant = screen_pos_of(id)
			if at == null:
				continue
			box = Rect2(at as Vector2, Vector2.ZERO) if n == 0 else box.expand(at as Vector2)
			n += 1
		if n == 0:
			continue
		var ink: Color = (_cluster_col[c] as Color).lerp(_pal["label_ink"], 0.45)
		if _cluster != "all" and c != _cluster:
			ink.a = _repo.bal("ledger_galaxy_other_fade")
		entries.append({"text": "%s  ·  %d" % [row["label"], n], "strong": true, "title": true,
			"px": _repo.bal("ledger_title_px"), "ink": ink,
			"at": Vector2(box.get_center().x, box.position.y - _repo.bal("ledger_title_px"))})
	var named: Array[String] = []
	if _selected != "":
		named.append(_selected)
		for id: String in _near:
			if id != _selected:
				named.append(id)
	if _hovered != "" and not named.has(_hovered):
		named.append(_hovered)
	var by_size := _order.duplicate()
	by_size.sort_custom(func(a: String, b: String) -> bool:
		return float(_size[a]) > float(_size[b]) if float(_size[a]) != float(_size[b]) else a < b)
	var hubs := 0
	for id: String in by_size:
		if hubs >= int(_repo.bal("ledger_label_hubs")):
			break
		if screen_pos_of(id) != null and not named.has(id):
			named.append(id)
			hubs += 1
	for id: String in _order:
		var at: Variant = screen_pos_of(id)
		if at == null:
			continue
		var r := _screen_radius(id)
		obstacles.append(Rect2((at as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	for id: String in named:
		var at: Variant = screen_pos_of(id)
		if at == null:
			continue
		var r := _screen_radius(id)
		var e := {"text": String(_nodes[id]["label"]), "at": (at as Vector2) - Vector2(0, r + lift),
			"alt": (at as Vector2) + Vector2(0, r + lift + label_px), "strong": id == _selected or _near.has(id),
			"props": _nodes[id].get("props", [])}
		if id == _selected:
			e["ring"] = r + _repo.bal("ledger_ring_px") * 2.0
			e["ring_at"] = at
		entries.append(e)
	_hud.show_entries(entries, obstacles)


# --- input ---------------------------------------------------------------------

func _ray(pos: Vector2) -> Array:
	var px := LedgerPick.screen_to_viewport(pos, _window_scale())
	return [_camera.project_ray_origin(px), _camera.project_ray_normal(px)]


## A segment's two ends in the world, its strand's screen shift applied (what
## link.gdshader draws, so what a click meets).
func seg_ends(seg: Dictionary) -> Array:
	var a: Vector3 = seg["a"]
	var b: Vector3 = seg["b"]
	var shift := float(seg["shift_px"])
	if shift == 0.0:
		return [a, b]
	var mid := (a + b) * 0.5
	var across := (b - a).cross(_camera.global_position - mid)
	if across.length_squared() < 1e-8:
		return [a, b]
	var off := across.normalized() * shift * _m_per_px_at(mid)
	return [a + off, b + off]


func _pick(pos: Vector2) -> Dictionary:
	var ray := _ray(pos)
	var spheres: Array = []
	for id: String in _order:
		spheres.append({"id": id, "pos": _drawn[id], "radius": float(_size[id])})
	var threads: Array = []
	for seg: Dictionary in _segs:
		var ends := seg_ends(seg)
		var mid: Vector3 = ((ends[0] as Vector3) + (ends[1] as Vector3)) * 0.5
		threads.append({"id": String(seg["id"]), "a": ends[0], "b": ends[1],
			"radius": maxf(float(seg["width_px"]) * 0.5 * _m_per_px_at(mid), _repo.bal("ledger_pick_radius_min_m"))})
	return LedgerPick.pick(ray[0], ray[1], spheres, threads)


func _gui_input(event: InputEvent) -> void:
	if _repo == null:
		return
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		if _button != 0:
			_on_drag(event as InputEventMouseMotion)
		else:
			_on_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMagnifyGesture:
		_framed = false
		_orbit.zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))
		_apply_camera()
		accept_event()
	elif event is InputEventPanGesture:
		_framed = false
		_orbit.pan(-(event as InputEventPanGesture).delta * _repo.bal("ledger_pan_gesture_px"), _pan_m_per_px())
		_apply_camera()
		accept_event()


func _pan_m_per_px() -> float:
	return _camera.size / maxf(size.y, 1.0) if _flat else _orbit.metres_per_px(_camera.fov, size.y)


## Hover names a star (it draws nothing: only a clicked object is ringed).
func _on_hover(pos: Vector2) -> void:
	var hit := _pick(pos)
	var id := String(hit["id"]) if String(hit.get("kind", "")) == "sphere" else ""
	if id == _hovered:
		return
	_hovered = id
	tooltip_text = String(_nodes[id]["label"]) if id != "" else ""
	_update_hud()


func _on_button(mb: InputEventMouseButton) -> void:
	if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var f := _repo.bal("ledger_zoom_factor")
		_framed = false
		_orbit.zoom(1.0 / f if mb.button_index == MOUSE_BUTTON_WHEEL_UP else f)
		_apply_camera()
		accept_event()
		return
	if mb.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	accept_event()
	if mb.pressed:
		_button = mb.button_index
		_press_at = mb.position
		_moved = false
		_drag_id = ""
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var pressed_on := _pick(mb.position)
			if String(pressed_on.get("kind", "")) == "sphere":
				_drag_id = String(pressed_on["id"])
				if mb.double_click:
					_button = 0
					drill_requested.emit(_drag_id)
		return
	if _button != mb.button_index:
		return
	var was := _button
	_button = 0
	if _moved:
		return
	var hit := _pick(mb.position)
	if was == MOUSE_BUTTON_RIGHT:
		if not hit.is_empty():
			orders_requested.emit(String(hit["id"]), mb.position)
		return
	match String(hit.get("kind", "")):
		"sphere":
			select(String(hit["id"]))
			sphere_selected.emit(String(hit["id"]))
		"thread":
			thread_selected.emit(String(hit["id"]))
		_:
			select("")
			sphere_selected.emit("")


func _end_gesture() -> void:
	_button = 0
	_drag_id = ""
	_moved = false


func _on_drag(mm: InputEventMouseMotion) -> void:
	if not _moved and mm.position.distance_to(_press_at) < CLICK_SLOP:
		return
	_moved = true
	if _drag_id == "":
		_framed = false
	if _button == MOUSE_BUTTON_RIGHT:
		if not _flat:
			_orbit.turn(mm.relative.x, mm.relative.y, _repo.bal("ledger_turn_deg_per_px"))
	elif _drag_id != "":
		_drag_to(_drag_id, mm.position)
	else:
		_orbit.pan(mm.relative, _pan_m_per_px())
	_apply_camera()
	accept_event()


## A dragged star slides in the plane through it facing the camera (in the
## flat chart, on the plane) and is PINNED there for this viewing; the rest
## settle round it.
func _drag_to(id: String, pos: Vector2) -> void:
	if not _drawn.has(id):
		_end_gesture()
		return
	var ray := _ray(pos)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var n := -_camera.global_transform.basis.z
	var denom := d.dot(n)
	if absf(denom) < 1e-5:
		return
	var t := ((_drawn[id] as Vector3) - o).dot(n) / denom
	if t <= 0.0:
		return
	var at := o + d * t
	if _flat:
		at.y = 0.0
	_lay.pin(id, at)
	_drawn[id] = _lay.pos[id]
	_place_stars()
	_rebuild_links()
	_update_hud()
```

- [ ] **Step 6: Delete the retired view test and the five layout tests, then run every view test**

Delete `tests/ledger3d/test_ledger_view_drag.gd` (and its `.uid`) and the five tests named in **Files** from `tests/ledger3d/test_ledger_math.gd`. Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`, then each of `test_ledger_view_galaxy.gd`, `test_ledger_strands.gd`, `test_ledger_court_look.gd`, `test_ledger_math.gd`, `test_ledger_hud.gd`, `test_ledger_galaxy_layout.gd`, `test_ledger_link_mesh.gd`, `test_ledger_look_assets.gd` (all with the `pre_run` script).
Expected: PASS. (`LedgerScreen` still calls `Ledger.snapshot` with a lens until Task 9; the screen's tests are Task 9's.)

- [ ] **Step 7: Commit**

```bash
git add scripts/ledger3d/ledger_view_3d.gd scenes/ledger/ledger_view.tscn tests/ledger3d/
git commit -m "feat(ledger): the galaxy view — stars, shaded links, cluster haze, night sky, flat chart

The player's web lit at rest now holds in every tab (controller ruling:
in All the court's 49 ties would otherwise tangle again).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 9: The screen — tabs are clusters, a province opens, the chart lies flat

**Files:**
- Modify: `scripts/ui/ledger_screen.gd`, `scenes/ledger_screen.tscn`, `scripts/ui/game_root.gd` (`_open_ledger_on`)
- Rewrite: `tests/ui/test_ledger_screen.gd`

**Interfaces:**
- Consumes: Task 8's view API; `Ledger.galaxy`.
- Produces: `LedgerScreen.set_lens(lens_id)` (a `ledger_lenses.csv` id; it chooses that lens's cluster, `all` the whole galaxy, and redraws nothing), `lens() -> String`, `drill(id)` (a province: open or close it; anything else: select it, frame its web, its card), `back()` (close the last opened province), `toggle_flat()`, `opened() -> Dictionary`, `snapshot()` (the galaxy), `_rebuilds` (test seam, as today).

- [ ] **Step 1: Write the failing tests** — replace `tests/ui/test_ledger_screen.gd` below its `_court()` helper with:

```gdscript
func _open(r: GameRoot) -> LedgerScreen:
	r.bottom_bar().button("LEDGER").pressed.emit()
	await wait_frames(2)
	return r.ledger_screen()


func test_the_ledger_opens_on_the_whole_galaxy() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	assert_eq(String(screen.snapshot()["lens"]), "galaxy")
	assert_eq(screen.lens(), "all")
	assert_eq(screen.view().cluster(), "all")
	assert_eq((screen.snapshot()["nodes"] as Array).size(),
		(Ledger.galaxy(Game.data, Game.state, {})["nodes"] as Array).size())


func test_a_tab_chooses_its_cluster_without_redrawing() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var before := screen._rebuilds
	screen.set_lens("court")
	assert_eq(screen.view().cluster(), "court")
	assert_eq(screen._rebuilds, before, "a tab flies the camera; it does not read the realm again")
	screen.set_lens("all")
	assert_eq(screen.view().cluster(), "all")


func test_a_double_clicked_province_opens_and_closes() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var home := MapManors.home_province(Game.data, Game.state)
	screen.view().drill_requested.emit("province:" + home)
	await wait_frames(1)
	var manors := (screen.snapshot()["nodes"] as Array).filter(func(n: Dictionary) -> bool:
		return String(n["type"]) == "manor")
	assert_eq(manors.size(), MapManors.manors_of_province(Game.data, home, Game.state).size(), "its manors stand")
	assert_true(screen.opened().has(home))
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_true(detail.has_content(), "the province's card")
	screen.back()
	assert_false(screen.opened().has(home), "back closes it")
	assert_true((screen.snapshot()["nodes"] as Array).all(func(n: Dictionary) -> bool:
		return String(n["type"]) != "manor"))


func test_a_double_clicked_person_opens_their_card_and_is_selected() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	screen.view().drill_requested.emit("character:you")
	await wait_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, LedgerResolvers.label_of(Game.data, Game.state, "character:you"))
	assert_eq(screen.view()._selected, "character:you")


func test_the_mode_button_lays_the_chart_flat() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	(screen.find_child("Mode", true, false) as Button).pressed.emit()
	assert_true(screen.view().is_flat())
	(screen.find_child("Mode", true, false) as Button).pressed.emit()
	assert_false(screen.view().is_flat())


func test_an_order_on_a_pool_runs_through_the_engine() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var before := float(Game.state.metrics["treasury"])
	var menu: LedgerOrderMenu = screen.find_child("Orders", true, false)
	screen.view().orders_requested.emit("type:civil_goods", Vector2(100, 100))
	await wait_frames(1)
	menu.hide()                      # PopupMenu hides BEFORE id_pressed, as for real
	menu.id_pressed.emit(0)          # the first row: Buy civil goods
	await wait_frames(1)
	assert_lt(float(Game.state.metrics["treasury"]), before, "the purchase was paid")


func test_refreshes_in_one_frame_rebuild_once() -> void:
	var r: GameRoot = await _court()
	var screen := await _open(r)
	var before := screen._rebuilds
	screen.refresh()
	screen.refresh()
	screen.refresh()
	assert_eq(screen._rebuilds, before, "nothing is drawn inside the calls")
	await wait_frames(2)
	assert_eq(screen._rebuilds, before + 1, "drawn once")


func test_a_vanished_selection_takes_its_card() -> void:
	var r: GameRoot = await _court()
	MissiveLog.add(Game.data, Game.state, MissiveWriter.monthly(Game.data, Game.state, Game.state.tick))
	var rid := int((Game.state.missives[Game.state.missives.size() - 1] as Dictionary)["id"])
	var screen := await _open(r)
	screen.drill("report:%d" % rid)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_true(detail.has_content(), "the report's card")
	Game.state.missives = Game.state.missives.filter(func(m: Dictionary) -> bool: return int(m["id"]) != rid)
	screen.refresh()
	await wait_frames(2)
	assert_eq(screen.view()._selected, "")
	assert_false(detail.has_content(), "the vanished star's card went with it")


func test_closing_keeps_a_card_the_ledger_did_not_put_there() -> void:
	var r: GameRoot = await _court()
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	detail.show_province(MapManors.home_province(Game.data, Game.state))
	var screen := await _open(r)
	screen.close()
	assert_true(detail.has_content(), "the player's own card stays")
	screen = await _open(r)
	screen.drill("character:you")
	assert_true(detail.has_content())
	screen.set_lens("economy")
	assert_false(detail.has_content(), "a new tab takes the old star's card away")
	screen.drill("character:you")
	screen.close()
	assert_false(detail.has_content(), "closing takes the LEDGER's own card")


func test_a_strand_opens_its_links_card() -> void:
	var r: GameRoot = await _court()
	var m: Character = Game.state.characters[String(Game.state.council["marshal"])]
	m.traits = ["venal"]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	Game.state.metrics["strategic"] = 1000000.0
	for c in Game.state.regiments.keys():
		Game.state.regiments[c]["supplies"] = 0
	var screen := await _open(r)
	var link: Dictionary = (screen.snapshot()["links"] as Array).filter(func(l: Dictionary) -> bool:
		return String(l["type"]) == "supplies_out" and (l["accounts"] as Array).size() == 2)[0]
	screen.view().thread_selected.emit(String(link["id"]) + "#1")
	await wait_frames(1)
	var detail: MapDetailPanel = r.current_screen.detail_panel()
	assert_eq(detail.title_label().text, LedgerCards.thread_entry(Game.data, Game.state, link)["title"])
```

- [ ] **Step 2: Run to see them fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ui/test_ledger_screen.gd -gpre_run_script=res://tests/pre_run.gd -gexit`
Expected: FAIL — `opened` not found, the lens is "economy", no `Mode` button.

- [ ] **Step 3: The scene** — in `scenes/ledger_screen.tscn`, add a `Mode` button between `Front` and `Close` in `Top`:

```
[node name="Mode" type="Button" parent="Top"]
unique_name_in_owner = true
layout_mode = 2
text = "2D"
```

- [ ] **Step 4: The screen** — in `scripts/ui/ledger_screen.gd`:

Members: `var _lens := "all"`; replace `var _focus_id := ""` with

```gdscript
var _opened: Dictionary = {}       # province code -> true: opened this viewing (never saved)
var _open_order: Array[String] = []
```

In `_ready`, after `%Front.pressed.connect(...)`:

```gdscript
	%Mode.pressed.connect(toggle_flat)
```

Replace `set_lens`, `drill`, `back`, `_rebuild` and `_on_sphere` with:

```gdscript
func opened() -> Dictionary:
	return _opened


## A tab chooses its cluster (data/ledger_clusters.csv `lens`); All is the
## whole galaxy. The camera flies; nothing is read again.
func set_lens(lens_id: String) -> void:
	_lens = lens_id
	for b: Node in %Lenses.get_children():
		(b as Button).set_pressed_no_signal(String(b.name) == "Lens_" + lens_id)
	_view.focus_cluster(_cluster_for(lens_id))
	_clear_card()  # the old tab's card names a star the camera has left
	_crumb()


func _cluster_for(lens_id: String) -> String:
	for c: Dictionary in Game.data.ledger_clusters:
		if String(c["lens"]) == lens_id:
			return String(c["cluster"])
	return "all"


## From the left column's list or a double click: a province opens (its
## manors, towns and buildings settle round it) or closes; any other star is
## selected, its web framed and its card put in the left column.
func drill(id: String) -> void:
	if id == "" or id.begins_with("more:"):
		return
	if id.begins_with("province:"):
		var code := id.substr(9)
		if _opened.has(code):
			_opened.erase(code)
			_open_order.erase(code)
		else:
			_opened[code] = true
			_open_order.append(code)
		_rebuild(true)
	else:
		_view.frame_web(id)
	_view.select(id)
	_show_card(LedgerCards.entry(Game.data, Game.state, id, _snap))


## Closes the last province opened.
func back() -> void:
	if _open_order.is_empty():
		return
	_opened.erase(_open_order.pop_back())
	_rebuild(true)


func toggle_flat() -> void:
	_view.set_flat(not _view.is_flat())
	%Mode.text = "3D" if _view.is_flat() else "2D"


func _rebuild(keep_camera: bool) -> void:
	_rebuilds += 1
	var selected := _view._selected
	_snap = Ledger.galaxy(Game.data, Game.state, _opened)
	_view.show_snapshot(_snap, keep_camera)
	if selected != "" and _view._selected == "":
		_clear_card()  # the selected star is gone (a courier arrived, a report aged out)
	_crumb()


func _crumb() -> void:
	var parts: Array[String] = ["Realm"]
	for c: Dictionary in Game.data.ledger_clusters:
		if String(c["cluster"]) == _view.cluster():
			parts.append(String(c["label"]))
	for code: String in _open_order:
		parts.append(LedgerResolvers.label_of(Game.data, Game.state, "province:" + code))
	%Crumb.text = " › ".join(parts)
	%Back.visible = not _open_order.is_empty()


## A star's card in the left column; empty sky closes it.
func _on_sphere(id: String) -> void:
	if not _has_detail():
		return
	if id == "" or id.begins_with("more:"):
		_clear_card()
		return
	_show_card(LedgerCards.entry(Game.data, Game.state, id, _snap))
```

In `open(...)`, after the `_rebuild(false)` call, add `set_lens(_lens)` so the chips and the view agree. `%Back`'s text becomes "‹ Close" in the scene (it now closes a province). Every other reference to `_focus_id` in the file goes with it.

- [ ] **Step 5: An audit letter lands on its flow's cluster** — in `scripts/ui/game_root.gd`, replace `_open_ledger_on`'s body after the visibility checks:

```gdscript
	var cluster := String(Ledger.type_row(Game.data, flow).get("cluster", ""))
	for c: Dictionary in Game.data.ledger_clusters:
		if String(c["cluster"]) == cluster:
			_ledger_screen.set_lens(String(c["lens"]))
```

(The existing Missive test expects `lens() == "war"` for `supply_line`: its cluster is `war`, whose chip is `war`.)

- [ ] **Step 6: Run the screen, missive and view tests**

Run the Step 2 command, then `tests/ui/test_missive_screen.gd` and `tests/ledger3d/test_ledger_view_galaxy.gd` (with the `pre_run` script).
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/ledger_screen.gd scenes/ledger_screen.tscn scripts/ui/game_root.gd tests/ui/test_ledger_screen.gd
git commit -m "feat(ledger): tabs are clusters, a province opens, the chart lies flat

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Tools, retirement and the record

**Files:**
- Modify: `tools/snapshot_screen.gd`, `data/balance.csv`, `data/ledger_palette.csv`, `CLAUDE.md`, `docs/superpowers/specs/2026-09-30-ledger-ontology-design.md`, `docs/superpowers/specs/2026-09-30-ledger-galaxy-design.md`, `.claude/skills/visual-review/taste.md`
- Delete: `scripts/ledger3d/ledger_layout.gd`, `scenes/ledger/disc.gdshader`, `scenes/ledger/thread.gdshader` (and their `.uid` files)

**Interfaces:**
- Produces: `snapshot_screen.gd` flags `--ledger CLUSTER_OR_LENS`, `--ledger-select ID`, `--ledger-open PROVINCE_CODE`, `--ledger-mode 2d` (all with `--screen root --shot-on ledger`), each driven through the real screen (its tab, chip, `drill`, `Mode` button).

- [ ] **Step 1: The shot tool** — in `tools/snapshot_screen.gd`, replace the `--ledger` doc comment and the members `_ledger_focus`, `_ledger_row` with:

```gdscript
## --ledger LENS (with --screen root): the LEDGER through real clicks — its
## tab, then the lens chip (a ledger_lenses.csv id: all, economy, war, court,
## intelligence). --ledger-open CODE then opens that province (a double click
## on its star), --ledger-select ID double-clicks that star (selected, its web
## framed), --ledger-mode 2d presses Mode. The moment is `ledger`, once the
## chart has settled.
var _ledger := ""
var _ledger_open := ""
var _ledger_select := ""
var _ledger_mode := ""
```

replace the two `--ledger-focus` / `--ledger-row` branches of the argument loop with:

```gdscript
		elif args[i] == "--ledger-open":
			_ledger_open = args[i + 1]
		elif args[i] == "--ledger-select":
			_ledger_select = args[i + 1]
		elif args[i] == "--ledger-mode":
			_ledger_mode = args[i + 1]
```

and replace `_ledger_step` (with its doc comment) by:

```gdscript
## --ledger LENS [--ledger-open CODE] [--ledger-select ID] [--ledger-mode 2d]:
## the LEDGER through its own controls, then the moment `ledger`.
func _ledger_step() -> void:
	var start := 30
	var screen := _root.ledger_screen()
	if _frames == start:
		var tab := _root.bottom_bar().button("LEDGER")
		_real_click(tab, tab.size * 0.5)
		print("ledger: open=%s" % screen.visible)
	elif _frames == start + 6:
		var chip := screen.find_child("Lens_" + _ledger, true, false) as Button
		if chip == null:
			push_error("ledger: no lens chip Lens_" + _ledger)
			return
		_real_click(chip, chip.size * 0.5)
		print("ledger: lens=%s cluster=%s stars=%d links=%d" % [screen.lens(), screen.view().cluster(),
			(screen.snapshot()["nodes"] as Array).size(), (screen.snapshot()["links"] as Array).size()])
	elif _frames == start + 10 and _ledger_open != "":
		screen.view().drill_requested.emit("province:" + _ledger_open)
		print("ledger: opened %s -> stars=%d" % [_ledger_open, (screen.snapshot()["nodes"] as Array).size()])
	elif _frames == start + 14 and _ledger_select != "":
		screen.view().drill_requested.emit(_ledger_select)
		print("ledger: selected %s" % screen.view()._selected)
	elif _frames == start + 16 and _ledger_mode == "2d":
		var mode := screen.find_child("Mode", true, false) as Button
		_real_click(mode, mode.size * 0.5)
		print("ledger: flat=%s" % screen.view().is_flat())
	elif _frames == start + 20:
		screen.view().settle_now()
	elif _frames == start + 40:
		_moment("ledger")
```

(`drill_requested` is what a real double click on the star emits; emitting it is the one step taken without a pointer, because the star's place is only known once the chart has settled.)

- [ ] **Step 2: Retire what nothing calls** — run

```bash
grep -rn "LedgerLayout\|disc.gdshader\|thread.gdshader\|ledger_disc_\|ledger_layer_gap_m\|ledger_sphere_radius_\|ledger_orb_\|ledger_thread_width_\|ledger_thread_vague_width\|ledger_strand_gap_m\|ledger_pair_offset_m\|ledger_layout_\|ledger_ego_ring_m\|ledger_tie_width_\|ledger_frame_rim_samples\|ledger_front_ease_s\|disc_things\|disc_people\|disc_know\|sphere_things\|sphere_people\|sphere_know\|\"background\"" scripts tests tools
```

Every hit must be in a file this plan already rewrote or in the three files deleted here; fix any other hit to the galaxy's equivalent. Then delete the three files and their `.uid`s, and remove from `data/balance.csv` the rows `ledger_layer_gap_m`, `ledger_disc_radius_m`, `ledger_disc_pad_m`, `ledger_disc_min_m`, `ledger_disc_fade_m`, `ledger_disc_fade_max_share`, `ledger_disc_offset_m`, `ledger_sphere_radius_type`, `ledger_sphere_radius_instance`, `ledger_orb_metallic`, `ledger_orb_roughness`, `ledger_orb_glass_alpha`, `ledger_thread_width_min`, `ledger_thread_width_max`, `ledger_thread_vague_width`, `ledger_tie_width_min`, `ledger_tie_width_max`, `ledger_strand_gap_m`, `ledger_pair_offset_m`, `ledger_ego_ring_m`, `ledger_layout_iterations`, `ledger_layout_repel`, `ledger_layout_spring`, `ledger_layout_margin_m`, `ledger_front_ease_s`, `ledger_frame_rim_samples`, and from `data/ledger_palette.csv` the rows `background`, `disc_things`, `disc_people`, `disc_know`, `sphere_things`, `sphere_people`, `sphere_know`, `thread_live` stays (the fallback link colour), `sphere_planned` stays (the ghosts). Keep `ledger_thread_flow_ref`, `ledger_tie_ref`, `ledger_tie_rest_fade`, `ledger_focus_fade`, `ledger_light_*`, `ledger_ink_*`, `ledger_age_full_days`, `ledger_dashes` (unused now: remove it too), the camera, label, gauge, frame and pick keys. `Ledger.snapshot` and the `x` / `z` columns STAY: the engine tests and `LedgerCards` still read lens snapshots.

- [ ] **Step 3: The record** — in `CLAUDE.md`'s LEDGER paragraph, replace the sentence that begins "The view is `scripts/ledger3d/` + `scenes/ledger/ledger_view.tscn` (three discs KNOW / PEOPLE / THINGS, brass and glass spheres, gold threads with running light)" with one describing the galaxy: `Ledger.galaxy` (the realm as one picture, the economy folded by province, opened provinces unfolded), `LedgerGalaxyLayout`, the stars / links (`LedgerLinkMesh`, `link.gdshader`) / haze / night sky in palette D, tabs as clusters, double-click opens a province, the `Mode` button's flat chart, the open schema (`cluster` / `fold_to` / `star` / `look` columns, `ledger_static_nodes.csv` / `ledger_static_links.csv`, spec §3b), and `snapshot_screen --ledger CLUSTER [--ledger-open CODE] [--ledger-select ID] [--ledger-mode 2d]`. In the ontology spec's §6.2–6.3 add one line at the top of each: "Superseded for the view by `2026-09-30-ledger-galaxy-design.md` (the galaxy)". In the galaxy spec §6 change "At rest in the Court tab the player's own web is lit" to "At rest the player's own web of ties is lit in every tab (a controller ruling of Task 8: in All the court's ties would otherwise tangle again)". In `taste.md`, replace the bullet "**The LEDGER is an orrery of brass and glass, read one web at a time**" with the galaxy spec §11 ruling, keeping its last sentence about perceived fades.

- [ ] **Step 4: Run the full suite**

Run: `./run_tests.sh`
Expected: only `test_map3d_layers.gd::test_a_camera_move_refreshes_the_houses` fails; no SCRIPT ERROR outside the allow-list.

- [ ] **Step 5: Commit**

```bash
git add -A tools/snapshot_screen.gd data/balance.csv data/ledger_palette.csv CLAUDE.md docs/superpowers/specs .claude/skills/visual-review/taste.md scripts/ledger3d scenes/ledger
git commit -m "chore(ledger): the orrery retired; the galaxy in the shot tool and the record

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`git add -A` on those paths only: it records the deletions; never add `project.godot` or untracked assets.)

---

### Task 11: The look pass and the budget

**Files:**
- Modify: `data/balance.csv`, `data/ledger_palette.csv` (values only)
- Create (scratch, not committed): shots and contact sheets in the session scratchpad

**Interfaces:** none new — values only.

- [ ] **Step 1: Shoot through the real window** (never `--headless`), at 2560×1600:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- --screen root --resolution 2560x1600 --shot-on ledger --ledger all --out <scratchpad>/all.png
```

and the same with `--ledger economy`, `--ledger court`, `--ledger court --ledger-select character:you`, `--ledger economy --ledger-open <the home province's code>`, `--ledger all --ledger-mode 2d`. (Read the home province's code with a one-line probe or from `data/maps/<pack>/house_bindings.csv`.)

- [ ] **Step 2: Follow the visual-review skill** (`.claude/skills/visual-review/SKILL.md`): bracket the look values that matter most — `ledger_haze_strength` (0.05 / 0.075 / 0.1), `ledger_star_emit` (1.1 / 1.4 / 1.8), `ledger_link_max_px` (3 / 4 / 5), `ledger_label_hubs` (8 / 12 / 16) — with `--bal key=value`; build contact sheets with a zoomed crop; dispatch ONE independent critic with the sheets, `taste.md` and the rubric; fix what breaks a principle; re-shoot. Stop when the critic finds no defect that breaks a principle.

- [ ] **Step 3: The budget** — with six months of play (a probe like Task 2's budget test, or `snapshot_screen --play-days 180` if it plays through the LEDGER), measure: `Ledger.galaxy` warm ≤ 60 ms; while settling, ≤ `ledger_galaxy_ms_per_frame` of layout a frame; the settled view with three provinces opened holding the display refresh at 1920×1080 on the `high` tier. A miss is fixed (fewer passes a frame, a repulsion cut-off, a memoised reader) — never waived.

- [ ] **Step 4: Commit the tuned values**

```bash
git add data/balance.csv data/ledger_palette.csv
git commit -m "look(ledger): the galaxy's values after the visual review

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand the owner the before/after sheet** with which principle each change serves and what is still open.
