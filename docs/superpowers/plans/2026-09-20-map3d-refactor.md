# The 3D World Map Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Break up the 2,271-line `scripts/map3d/map3d_view.gd`, which does ~19 jobs, into one small script per job. They live under a scene authored in the editor, `scenes/map3d/world_map_3d.tscn`, so clicking a node in the editor shows the real picture. Every public name that screens, GameRoot, tools and tests use today stays the same. A new pack's 3D map is built by one command. Graphics-quality tiers (`low / medium / high / ultra`) with bench gates keep the frame budget on ordinary machines.

**Architecture:** `Map3DView` (a Control, `class_name` kept) becomes a coordinator of at most 450 lines: public API, forwarders, `_gui_input` / `_process` entry points. It owns one `Map3DContext` (RefCounted: repo, meta, camera, terrain, state getter, scales, quality row, cached ground points, one list of projected settlements per camera pose, the `camera_moved` signal). It hands that context to one script per job: layer nodes (`Map3DLayerSea`, `Map3DLayerRivers`, `Map3DLayerLines`, `Map3DLayerClouds`, `Map3DLayerSettlements`, `Map3DCameraRig`), layer builders (`Map3DLayerRoads`, `Map3DLayerBorders`, `Map3DLayerThemes`), controllers (`Map3DInput`, `Map3DPicker`, `Map3DSelection`) and HUD pieces (`Map3DHudLabels`, `…Badges`, `…Armies`, `…Landmarks`, `…HeatLegend`, `…ScaleBar`, `…Ruler`, `…Backdrop`, `…Needle`). The world is loaded by `Map3DWorldLoader`, which reports missing / stale / bad, and kept between screens by `Map3DWorldCache`. Tuned numbers stay in `data/*.csv`. Materials are `.tres` files (structure and textures only), with committed 512 px preview textures. `data/graphics_quality.csv` holds the tiers, read by `Map3DQuality`, which is pure.

**Tech Stack:** Godot 4.7 (GL Compatibility), typed GDScript, GUT, Terrain3D 1.0.2 (GDExtension), the gdai MCP editor plugin (port 3571), Python 3 (`bake_world.py`), POSIX `sh`.

**Spec:** docs/superpowers/specs/2026-09-20-map3d-refactor-design.md

## Global Constraints

- Typed GDScript everywhere: type hints on vars, params and returns; `snake_case` files and functions, `PascalCase` classes, past-tense signals.
- Design values live in `data/*.csv` (`balance.csv`, `terrain_palette.csv`, `political_palette.csv`, `map3d_settlements.csv`, the new `graphics_quality.csv`) and are bound at load. A `.tres` holds STRUCTURE and LOOK ASSETS only (shader, textures, samplers, render priority, and generator settings that were code literals before). No new tuned number goes in a script.
- Engine purity: nothing under `scripts/engine/` learns about `scripts/map3d/`. Layers never read the `Game` autoload. Only `Map3DView` (the coordinator) and the 2D helpers it shares (`CompassLayer`, `ScaleBar`, `MapRuler`) may.
- The public `Map3DView` API is kept for the whole plan: every name, argument count, signal and static pinned by `tests/map3d/test_map3d_api.gd` (Task 0). So are the node names tests and tools use: `Viewport`, `Viewport/Markers/<Group>`, `Viewport/Markers/Selected`, `Viewport/Clouds`, `Viewport/Clouds/Shadows`, `Viewport/Rivers`, `Viewport/Lines/<name>`, `Hud`, `Hud/Compass`, `Hud/Needle`, `Display`, `Notice`, `Tooltip`, the camera named `RigCamera`. `line_mesh(name)` returns `null` for an empty line. `Map3DView.create(repo, fixture_path)` works with bare `Node3D` fixtures carrying `map3d_world` meta.
- Tests: one file with `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/<path>.gd -gexit`; the suite with `./run_tests.sh`. After every step the suite must be green apart from the one known pre-existing failure `test_ui_rework.gd::test_campaign_opens_with_nameless_background_narration`, with "Errors 2" (the gdai GDExtension is installed). While the editor is open, prefix every headless Godot command with `GDAI_MCP_SERVER_PORT=3999`: the plugin's runtime server otherwise collides with the editor's 3571 and the process exits about 20 s in.
- A parse error counts as the red state: GUT prints `Ignoring script …` for a test file that references a class that does not exist yet. That line is the expected failure in a "run it (fails)" step.
- The bench is `tools/map3d/bench.gd`, run as `res://tools/map3d/bench.tscn`: `GDAI_MCP_SERVER_PORT=3999 /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/map3d/bench.tscn -- --size 3024x1964 --out tools/map3d/bench_runs.csv`. It stays within budget (WORST median ≤ 8.00 ms at 3024×1964) after every task that touches the view. Task 18 adds the medium (≤ 6 ms) and low (≤ 4 ms) gates at 1920×1080.
- Commits: one per task, message ending with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`. Stage explicit paths only (`git add <path> …`, never `-A` or `.`): other agents work in this tree.
- gdai MCP: the tools are deferred. Load them with `ToolSearch` query `"gdai"` (max_results 30). Port 3571 belongs to the editor's plugin, so the editor must be running. Call `open_scene` on a scene before editing it (the editor may hold a stale copy). Commit per task. Never leave generated preview children with an `owner`: nothing generated may be saved into a `.tscn`. After every MCP edit, run `get_godot_errors` and `get_scene_file_content`. Before committing, check that the scene loads headless (each MCP task gives the check).

---

## The file today (`scripts/map3d/map3d_view.gd`, 2,271 lines at HEAD `8839b6d`)

| Lines | Job | Functions | Goes to (task) |
|---|---|---|---|
| 1–217 | header, signals, consts (the render-priority table `PRIORITY_SEA` −1 … `PRIORITY_CLOUDS` 9, `PRIORITY_RING_BASE` 10), 60 member vars | — | `Map3DPriority` (3); vars follow their functions |
| 220–267 | statics, creation | `scene_path_for`, `has_scene`, `create`, `toggle_in` | stay on the view; `create` instances the scene (13); `scene_path_for` reads `map3d_dir` (15) |
| 269–353 | nodes, scale, show/hide | `_ready`, `_render_scale`, `_fit_viewport`, `activate`, `deactivate` | stay on the view; `_ready` binds authored nodes (13); the scale split (17) |
| 355–441 | world load, height | `_load`, `_state`, `_home`, `_burg_xz`, `_height_at` | `Map3DWorldLoader` (14), `Map3DContext` (1) |
| 443–505, 760–818 | settlements | `_place_markers`, `marker_px`, `_ring_material`, `_show_selected_ring`, `_sorted_burgs` | `Map3DLayerSettlements` (7), `Map3DContext.marked_burgs` (2) |
| 507–623, 750–757 | water | `water_normals`, `_build_rivers`, `_dress_sea`, `sea_material`, `river_material` | `Map3DLayerRivers`, `Map3DLayerSea`, `Map3DContext.water_normals` (4) |
| 626–642 | sun | `_apply_sun_shadow_look` | `Map3DEnvironment` (4, 14) |
| 645–747 | clouds | `_build_clouds`, `_cloud_material`, `_cloud_shadow_material`, `_visible_ground`, `_step_clouds` | `Map3DLayerClouds` (5) |
| 821–867 | borders | `refresh_borders` (band, halo, ink, seams) | `Map3DLayerBorders` (8) |
| 870–1029 | MANORS + HEIGHTS ground | `_prepare_ground_tint`, `load_field_map`, `set_manor_theme`, `manor_theme`, `_refresh_theme`, `heat_on`, `_build_lut`, `_build_manor_edges`, `cell_lut`, `lut_color` | `Map3DLayerThemes` (9) |
| 1032–1172 | roads, bridges | `_build_roads`, `bridge_rules`, `bridges`, `_texture_pair`, `_set_road`, `_build_bridges` | `Map3DLayerRoads` (6) |
| 1175–1248 | the ribbon host | `_set_lines` (13 params, `fade_power_key`), `_update_line_scale` | `Map3DLayerLines` + `Map3DLineStyle` (3) |
| 1251–1273 | selection outline | `_draw_selection` | `Map3DSelection` (11) |
| 1276–1442 | camera, input, frame | `_apply_camera`, `_metres_per_pixel`, `metres_per_pixel`, `_pan_by`, `_zoom_at`, `_gui_input`, `_process` | `Map3DCameraRig`, `Map3DInput` (10) |
| 1445–1477, 1868–1896 | ruler | `_ruler_click`, `draw_ruler`, `ruler_reading`, `map_units_per_metre`, `map_unit`, `ruler` | state and click stay; drawing → `Map3DHudRuler` (12) |
| 1480–1519 | kingdom names | `label_entries`, `draw_labels` | `Map3DHudLabels` (12) |
| 1522–1563, 1852–1860 | MANORS badges | `manor_badges`, `draw_badges`, `drawn_badge_count` | `Map3DHudBadges` (12) |
| 1566–1638, 1844–1849 | MILITARY | `set_military`, `military`, `army_badge_height`, `army_markers`, `_settlement_marks`, `draw_armies`, `drawn_army_count`, `selected_army` | `Map3DHudArmies` (12), `Map3DContext.settlement_rects` (2), `Map3DSelection` (11) |
| 1641–1841 | HEIGHTS HUD | `landmark_marks` (per-pose cache), `_cut_landmark_marks`, `draw_landmarks`, `heat_legend_rect`, `heat_legend_ticks`, `_heat_legend_area`, `heat_legend_yields`, `draw_heat_legend` | `Map3DHudLandmarks`, `Map3DHudHeatLegend` (12) |
| 1899–2096 | picking, hover | `ground_at`, `pick_at`, `_province_at`, `kingdom_of_pick`, `hover_pick`, `clear_hover`, `_draw_hover`, `hovered_kingdom`, `hover_tooltip`, `tooltip_rect`, `_cell_at` | `Map3DContext.ground_at` (1), `Map3DPicker` (11), `_draw_hover` → `Map3DLayerBorders` (8) |
| 2099–2177 | selection | `select_at`, `_set_selected_province`, `clear_selection` | `Map3DSelection` (11) |
| 2180–2271 | test seams | `is_loaded` … `marker_counts`, `layer_names`, `set_layer_visible`, `line_mesh` | stay (forwarders) |

`scripts/map3d/map3d_hud.gd` (191 lines) reads `Game.data` in `compass_rect`, `_hud_halo`, `_draw` and `_draw_needle`, and holds `NeedleLayer` as an inner class. Both change in Task 12.

## Rulings (the owner is asleep: every call below is the implementer's, logged for the owner to reverse)

1. **Ruling: `draw_labels` / `draw_badges` / `draw_armies` / `draw_landmarks` / `draw_heat_legend` / `draw_ruler` are HUD internals, not API.** They go away in Task 12, and Task 0 does not pin them. — Why: only `Map3DHud._draw` calls them (grep: no test, tool or screen does). Keeping forwarders would keep the HUD pieces coupled to the view. — Cost if wrong: re-adding a one-line forwarder each.
2. **Ruling: the priority table moves to `Map3DPriority` (a const-only class), and `Map3DView.PRIORITY_*` stay as aliases.** — Why: the layers need the table, and a layer that reads `Map3DView.PRIORITY_*` would depend on its coordinator. Tests read `Map3DView.PRIORITY_*`. — Cost if wrong: none (aliases).
3. **Ruling: `_render_scale()` (the test seam) returns the VIEWPORT px scale (design → SubViewport px). The design → window scale becomes `Map3DContext.window_scale()`.** — Why: every caller (`test_map3d_heights.gd` lines 197/258/260, the pick, the HUD) uses it to go between design px and camera projection. After the tier split (Task 17), that is `window_scale × render_scale`. — Cost if wrong: one test helper changes its divisor.
4. **Ruling: burg ground points are read eagerly at load. Cell and landmark ground points are memoised on first use, keyed by pack px.** — Why: the spec's "cached ONCE at load" for burgs (684 lookups, used every pose). Every land cell eagerly (the pack's whole cell table) would add load time for points only MANORS badges touch. Memoised points are also read once. — Cost if wrong: an eager fill later is a loop in `settle_ground`.
5. **Ruling: `graphics_quality.csv` gives the line / road / river steps as MULTIPLIERS of the existing `balance.csv` keys** (`map3d_line_step_m` 150, `map3d_road_step_m` 25, `map3d_river_mesh_step_m` 12). The spec's absolute metres come out exactly: low 2.0 / 2.0 / 2.5 = 300 / 50 / 30, medium 1.3333 / 1.4 / 1.5 = 200 / 35 / 18, high and ultra 1. — Why: one source per number (CLAUDE.md), and the tests that pass `bal("map3d_line_step_m")` stay exact at high. — Cost if wrong: rewriting four CSV cells as metres.
6. **Ruling: steps apply at the next build of the view's layers (the next screen); render scale, MSAA, anisotropy, shadows, clouds, the Terrain3D mesh and HUD Hz apply live.** — Why: rebuilding roads, rivers and bridges takes seconds, and a pause-menu click must not hitch. — Cost if wrong: a "rebuild now" call on `set_quality`.
7. **Ruling: the suite runs at tier `high`** (`Map3DQuality.forced = "high"` in `tests/pre_run.gd`). Quality tests set tiers themselves. — Why: every existing assertion was written against today's look, which the high row reproduces exactly. — Cost if wrong: none; a test can override it.
8. **Ruling: `detect("", "")` (headless, unknown adapter) is `high`.** It is the spec's "else high". — Cost if wrong: an unknown adapter starts one tier too high, and the pause menu fixes it.
9. **Ruling: the HUD keeps calling the 2D helpers `CompassLayer`, `ScaleBar` and `MapRuler`, which still read `Game.data` and `Game.clock_speed`.** "No `Game` in the HUD" means the `map3d_hud*.gd` scripts; a test greps them. — Why: those helpers are shared with `WorldMapView`, and changing their signatures is 2D work outside this spec. The HUD therefore gets no `@tool` preview. — Cost if wrong: passing `repo` through three 2D helpers later.
10. **Ruling: the Tooltip's chip style is authored as `scenes/map3d/tooltip_chip.tres`, saved FROM `UiPalette.chip_style()`, and `_ready` re-applies `UiPalette`.** A test fails if the two drift. — Why: the owner wants the editor to show it, but the dark theme's single source is `UiPalette`. — Cost if wrong: deleting a `.tres`.
11. **Ruling: environment, sky and sun numbers move out of `build_terrain.gd` into CSV** (new `balance.csv` `map3d_sun_*`, `map3d_ambient_*`, `map3d_fog_density`, `map3d_sky_sun_angle_max`; new `terrain_palette.csv` `map3d_sky_top`, `map3d_sky_ground`). The shared environment is `scenes/map3d/world_environment.tres`. — Why: those numbers were code literals in a tool. Now that the scene owns the look they must be data, bound by `Map3DEnvironment` at load and by the preview. — Cost if wrong: a few extra CSV rows.
12. **Ruling: a build without `manifest.json` (today's build and every test fixture) loads as `legacy` and warns once.** Only a manifest whose `format_version` or `meta` disagrees is `stale`. A `steps_hash` mismatch (for example `map3d_bake.csv` edited since the build) loads and warns once. — Why: blocking on a changed bake table would hide the dev's map on every tuning edit. — Cost if wrong: making the hash blocking is one line.
13. **Ruling: `Map3DWorldCache` holds at most ONE world, keyed by scene path, and hands it out only while no view holds it.** A second live view loads its own copy, with its own duplicated terrain material (the 2026-09-19 MANORS fix). — Why: a world is 44 MB, only one screen shows at a time, and handing a busy world out would share its patched material. — Cost if wrong: a keyed pool.
14. **Ruling: baked layer meshes are written per distinct step set** (`layers/<layer>_<k>.res`, where `k` is the tier's road and river multipliers × 100). The runtime uses them only when `Map3DLayerBake.key` matches the layers manifest. — Why: tiers step differently, and a low-tier machine is the one that most needs the bake. — Cost if wrong: disk (git-ignored), a few MB × 3.
15. **Ruling: preview textures are real (512 px) and replace today's flat fallback** on a checkout without `assets/map3d/textures/`. — Why: the spec commits them for the editor, and a fresh clone drawing textured roads is better than flat ones. — Cost if wrong: a fresh clone's roads are slightly blurrier up close than the dev build's.
16. **Ruling: `world.tscn`'s null `dual_scale_*` / `tri_scale_reduction` (spec §6) are NOT fixed here.** — Why: fixing them changes both look and cost, so they get their own visual review; this plan keeps the look unchanged. — Cost if wrong: dual scaling stays off until that review.
17. **Ruling: the view's paint order is kept exactly.** HUD children are ordered Labels, Landmarks, HeatLegend, Badges, Armies, Backdrop, ScaleBar, Ruler, Compass, Needle, which is today's `_draw` order followed by the wheel and needle drawn over it. — Why: a refactor must not change the picture. — Cost if wrong: none.
18. **Ruling: one seam, `component(key: String) -> Object`, exposes the inner parts to tests** (`"roads"`, `"borders"`, `"themes"`, `"input"`, `"rig"`, `"picker"`, `"selection"`). — Why: one accessor instead of eight getters on a view meant to shrink. — Cost if wrong: getters later.

---
### Task 0: The API safety net and the bench baseline

**Files:**
- Create: `tests/map3d/test_map3d_api.gd`
- Modify: `tools/map3d/bench.gd` (`--out FILE`, primitives column)
- Create: `tools/map3d/bench_baseline.csv` (the numbers of this run, committed)

**Interfaces:**
- Consumes: `Map3DView` as it is at HEAD.
- Produces: `tests/map3d/test_map3d_api.gd`, run by every later task. The bench flag `--out <path>` appends CSV rows `size,quality,label,median_ms,mean_ms,p95_ms,draw_calls,primitives`.

**Risk:** a safety net that pins too little lets a later move silently drop a name. **Catch:** the table below was built from a grep of every `v.` / `view.` / `hv.` / `v3.` / `_map3d.` call in `tests/`, `tools/` and `scripts/ui/`, plus the statics and constants the tests read.

- [ ] **Step 1: Write the test** (it passes at HEAD; this task is the net, not a behaviour change)

```gdscript
extends GutTest
## The 3D map refactor's safety net (spec 2026-09-20 §5 step 0): every name,
## argument count, static, signal, property and node path of Map3DView that
## the screens, GameRoot, tools and tests use — pinned BEFORE the view is
## split, and run after every task of the refactor. A name may move into a
## layer, but the view must keep a forwarder with the same shape.

const FIXTURE := "user://test_map3d_api_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}

## name -> argument count (defaults included). Underscored names are the
## private handlers and helpers the tests call directly.
const METHODS := {
	"scene_path_for": 1, "has_scene": 1, "create": 2, "toggle_in": 7, "marker_px": 1,
	"load_field_map": 1, "kingdom_of_pick": 3,
	"activate": 0, "deactivate": 0, "water_normals": 0, "sea_material": 0,
	"river_material": 0, "refresh_borders": 0, "set_manor_theme": 1, "manor_theme": 0,
	"heat_on": 0, "cell_lut": 0, "lut_color": 1, "bridge_rules": 0, "bridges": 0,
	"metres_per_pixel": 0, "label_entries": 0, "manor_badges": 0, "set_military": 1,
	"military": 0, "army_badge_height": 0, "army_markers": 0, "landmark_marks": 0,
	"heat_legend_rect": 0, "heat_legend_ticks": 0, "heat_legend_yields": 0,
	"drawn_army_count": 0, "selected_army": 0, "drawn_badge_count": 0, "drawn_labels": 0,
	"ruler_reading": 0, "map_units_per_metre": 0, "map_unit": 0, "ruler": 0,
	"ground_at": 1, "pick_at": 1, "hover_pick": 2, "clear_hover": 0, "hovered_kingdom": 0,
	"hover_tooltip": 0, "tooltip_rect": 0, "select_at": 1, "clear_selection": 0,
	"is_loaded": 0, "notice": 0, "viewport": 0, "camera": 0, "cloud_count": 0,
	"target": 0, "distance": 0, "yaw": 0, "selected_province": 0, "selected_burg": 0,
	"selected_manor": 0, "selected_ring_visible": 0, "look_at_pack": 2, "look_at_home": 1,
	"layer_names": 0, "set_layer_visible": 2, "line_mesh": 1, "marker_counts": 0,
	"_gui_input": 1, "_process": 1, "_render_scale": 0, "_burg_xz": 1, "_height_at": 1,
	"_pan_by": 1, "_zoom_at": 2, "_ruler_click": 1,
}
const STATICS := ["scene_path_for", "has_scene", "create", "toggle_in", "marker_px",
	"load_field_map", "kingdom_of_pick"]
const SIGNALS := {"object_selected": 1, "province_selected": 1, "country_hovered": 1}
const CONSTANTS := ["PRIORITY_SEA", "PRIORITY_RIVERS", "PRIORITY_ROADS",
	"PRIORITY_MANOR_EDGES", "PRIORITY_KINGDOM_BAND", "PRIORITY_SEAMS",
	"PRIORITY_KINGDOM_HALO", "PRIORITY_KINGDOMS", "PRIORITY_HOVER", "PRIORITY_SELECTION",
	"PRIORITY_CLOUDS", "PRIORITY_RING_BASE"]
## Paths under the view after activate() on the fixture (+ refresh_borders).
const PATHS := ["Viewport", "Display", "Notice", "Tooltip", "Hud", "Hud/Compass",
	"Hud/Needle", "Viewport/Markers", "Viewport/Markers/Selected", "Viewport/Markers/Capital",
	"Viewport/Clouds", "Viewport/Clouds/Shadows", "Viewport/Lines",
	"Viewport/Lines/Kingdoms", "Viewport/Lines/KingdomHalo", "Viewport/Lines/KingdomBand",
	"Viewport/Lines/Seams", "Viewport/Lines/Roads"]


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func _script_methods() -> Dictionary:
	var out: Dictionary = {}
	var script: Script = load("res://scripts/map3d/map3d_view.gd")
	for m: Dictionary in script.get_script_method_list():
		out[String(m["name"])] = m
	return out


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	v.refresh_borders()
	return v


func test_every_method_keeps_its_name_and_shape() -> void:
	var have := _script_methods()
	for name: String in METHODS:
		assert_true(have.has(name), "Map3DView.%s is kept" % name)
		if have.has(name):
			assert_eq((have[name]["args"] as Array).size(), int(METHODS[name]),
				"Map3DView.%s keeps %d argument(s)" % [name, METHODS[name]])


func test_the_statics_stay_static() -> void:
	var have := _script_methods()
	for name: String in STATICS:
		assert_true((int(have[name]["flags"]) & METHOD_FLAG_STATIC) != 0, name + " is static")


func test_the_signals_are_kept() -> void:
	var v := Map3DView.create(Game.data, FIXTURE)
	add_child_autofree(v)
	for name: String in SIGNALS:
		assert_true(v.has_signal(name), name)
		for s: Dictionary in v.get_signal_list():
			if String(s["name"]) == name:
				assert_eq((s["args"] as Array).size(), int(SIGNALS[name]), name + " arguments")


func test_the_constants_and_properties_are_kept() -> void:
	var consts: Dictionary = (load("res://scripts/map3d/map3d_view.gd") as Script).get_script_constant_map()
	for name: String in CONSTANTS:
		assert_true(consts.has(name), name)
	var v := Map3DView.create(Game.data, FIXTURE)
	add_child_autofree(v)
	assert_true("ruler_on" in v, "ruler_on (GameRoot sets it)")
	assert_true("_meta" in v, "_meta (test_map3d_heights reads it)")


func test_the_node_paths_tests_and_tools_use_are_kept() -> void:
	var v := _view()
	for path: String in PATHS:
		assert_not_null(v.get_node_or_null(path), path)
	assert_true(v.get_node("Viewport") is SubViewport)
	assert_true(v.get_node("Viewport/Clouds") is MultiMeshInstance3D)
	assert_true(v.get_node("Viewport/Markers/Capital") is MultiMeshInstance3D)
	assert_true(v.get_node("Hud") is Map3DHud)
	assert_eq(String(v.camera().name), "RigCamera")
	assert_true(v.viewport().is_ancestor_of(v.camera()))


func test_an_empty_line_has_no_mesh() -> void:
	var v := _view()
	assert_null(v.line_mesh("Selection"), "nothing selected: no mesh, not an empty one")
	assert_null(v.line_mesh("Hover"), "nothing hovered: no mesh")
	assert_null(v.line_mesh("NoSuchLine"))
	assert_not_null(v.line_mesh("Kingdoms"))


func test_create_takes_a_fixture_path() -> void:
	var v := _view()
	assert_true(v.is_loaded(), "a bare Node3D with map3d_world meta is a world")
	assert_eq(Map3DView.scene_path_for("no_such_pack"), "res://assets/map3d/no_such_pack/world.tscn")


func test_the_hud_statics_are_kept() -> void:
	assert_eq(Map3DHud.scale_bar_for(1.5, 220.0, "km")["text"], "200 km")
	assert_eq(Map3DHud.needle_angle(0.0), 0.0)
```

- [ ] **Step 2: Run it (it must PASS at HEAD)**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_api.gd -gexit`
Expected: all 8 tests pass. If `Viewport/Lines/Roads` is missing, the pack has no `roads` group: replace that path with `Viewport/Lines/Trails`, and say so in the commit.

- [ ] **Step 3: Give the bench `--out` and a primitives column.** In `tools/map3d/bench.gd`: add `var _out := ""` and `var _rows: Array = []`. In `_ready` after `--size`, parse `var oi := args.find("--out"); if oi >= 0 and oi + 1 < args.size(): _out = args[oi + 1]`. In `_measure`, next to `calls`, track `prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))`, add `primitives %8d` to the print, and append `[str(get_window().size.x) + "x" + str(get_window().size.y), "current", label, median, _mean(frame_ms), _percentile(frame_ms, 0.95), calls, prims]` to `_rows`. Before `quit`, call:

```gdscript
## Appends this run's rows to --out (CSV; a header when the file is new).
func _write_rows() -> void:
	if _out == "":
		return
	var path := _out if _out.is_absolute_path() else ProjectSettings.globalize_path("res://" + _out)
	var fresh := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if not fresh else FileAccess.WRITE)
	if f == null:
		push_error("bench: cannot write " + path)
		return
	f.seek_end()
	if fresh:
		f.store_line("size,quality,label,median_ms,mean_ms,p95_ms,draw_calls,primitives")
	for r: Array in _rows:
		f.store_line("%s,%s,\"%s\",%.3f,%.3f,%.3f,%d,%d" % r)
	f.close()
```

- [ ] **Step 4: Record the baseline.** With the editor closed or the port moved:
  `GDAI_MCP_SERVER_PORT=3999 /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/map3d/bench.tscn -- --size 3024x1964 --out tools/map3d/bench_baseline.csv`
  then `-- --size 1920x1080 --out tools/map3d/bench_baseline.csv`, then the same pair with `--layer manors` and with `--layer heights`. Expected: exit 0 each time, WORST ≤ 8.00 ms (the last known worst is 6.4 ms). Copy each run's WORST line into the commit message. If the 3D world is not built locally (`assets/map3d/<id>/world.tscn` missing), build it first with the README's steps 3–5.

- [ ] **Step 5: Run the suite** — `./run_tests.sh`. Expected: green apart from the one known failure, "Errors 2".

- [ ] **Step 6: Commit**

```bash
git add tests/map3d/test_map3d_api.gd tools/map3d/bench.gd tools/map3d/bench_baseline.csv
git commit -m "test(map3d): pin Map3DView's public API before the refactor; bench --out and primitives

<WORST lines of the four runs>

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 1: `Map3DContext`, the one thing the layers share

**Files:**
- Create: `scripts/map3d/map3d_context.gd`
- Modify: `scripts/map3d/map3d_view.gd` (`_load`, `_height_at`, `_burg_xz`, `_render_scale`, `_fit_viewport`, `_apply_camera`, `ground_at`, new `_window_scale`, new seam `context()`)
- Test: `tests/map3d/test_map3d_context.gd`

**Interfaces:**
- Consumes: `Map3DGeometry.pack_to_world / world_to_pack / world_bounds / ground_hit / metres_per_pixel`.
- Produces: `class_name Map3DContext extends RefCounted` with `signal camera_moved`; fields `repo: DataRepository`, `meta: Dictionary`, `bounds: Rect2`, `world: Node3D`, `terrain: Node`, `camera: Camera3D`, `viewport: SubViewport`, `view_size: Vector2`, `target: Vector2`, `distance: float`, `yaw: float`, `quality: Dictionary`, `state_fn: Callable`, `clock_fn: Callable`, `window_scale_fn: Callable`, `height_fn: Callable`; methods `state() -> GameState`, `clock_speed() -> int`, `window_scale() -> float`, `render_scale() -> float`, `viewport_px_scale() -> float`, `height_at(xz: Vector2) -> float`, `to_world(pack_px: Vector2) -> Vector2`, `to_pack(xz: Vector2) -> Vector2`, `ground_of_pack(pack_px: Vector2) -> Vector3`, `project(world_pos: Vector3) -> Variant` (a design-px `Vector2`, or null behind the camera), `ground_at(pos: Vector2) -> Variant`, `metres_per_pixel() -> float`, `px_per_dist() -> float`, `line_step() -> float`, `road_step() -> float`, `river_step() -> float`, `water_normals() -> Texture2D`. On the view: `context() -> Map3DContext`.

**Risk:** `_render_scale()` is called in `_fit_viewport` before any load, so it must still work with no context. **Catch:** `test_map3d_api.gd` and `test_map3d_view.gd` (sizes, picks) run unchanged. The new tests hold the round trips.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_context.gd`:

```gdscript
extends GutTest
## Map3DContext (spec 2026-09-20 §1): what every layer of the 3D map shares —
## the pack <-> world round trip, the ground under a point, the scales and the
## camera pose, with no Game autoload and no view.

const FIXTURE := "user://test_map3d_ctx_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_pack_and_world_round_trip() -> void:
	var c := Map3DContext.new(Game.data, WORLD)
	assert_eq(c.to_world(Vector2.ZERO), Vector2(-64000.0, -23220.0))
	var px := Vector2(1234.5, 456.25)
	var back := c.to_pack(c.to_world(px))
	assert_almost_eq(back.x, px.x, 0.001)
	assert_almost_eq(back.y, px.y, 0.001)


func test_without_terrain_the_ground_is_the_sea() -> void:
	assert_eq(Map3DContext.new(Game.data, WORLD).height_at(Vector2(100, 100)), 5.0)


func test_the_height_seam_replaces_the_terrain() -> void:
	var c := Map3DContext.new(Game.data, WORLD)
	c.height_fn = func(xz: Vector2) -> float: return xz.x * 0.5
	assert_eq(c.height_at(Vector2(10, 0)), 5.0)
	assert_eq(c.ground_of_pack(Vector2.ZERO), Vector3(-64000.0, -32000.0, -23220.0))


func test_the_scales_default_to_one() -> void:
	var c := Map3DContext.new(Game.data, WORLD)
	assert_eq(c.window_scale(), 1.0)
	assert_eq(c.render_scale(), 1.0)
	assert_eq(c.viewport_px_scale(), 1.0)


func test_the_steps_are_the_balance_values() -> void:
	var c := Map3DContext.new(Game.data, WORLD)
	assert_eq(c.line_step(), Game.data.bal("map3d_line_step_m"))
	assert_eq(c.road_step(), Game.data.bal("map3d_road_step_m"))
	assert_eq(c.river_step(), Game.data.bal("map3d_river_mesh_step_m"))


func test_the_view_hands_out_its_context() -> void:
	var v := _view()
	var c := v.context()
	assert_not_null(c)
	assert_eq(c.camera, v.camera())
	assert_eq(c.target, v.target())
	assert_eq(c.distance, v.distance())
	assert_eq(c.yaw, v.yaw())
	assert_eq(c.state(), Game.state)
	assert_eq(c.view_size, v.size)
	assert_eq(c.ground_at(v.size * 0.5), v.ground_at(v.size * 0.5))


func test_a_camera_move_is_announced() -> void:
	var v := _view()
	var c := v.context()
	watch_signals(c)
	v.look_at_home(5000.0)
	assert_signal_emitted(c, "camera_moved")
	assert_eq(c.distance, 5000.0)


func test_the_target_projects_to_the_middle_of_the_view() -> void:
	var v := _view()
	var c := v.context()
	var p: Variant = c.project(Vector3(c.target.x, c.height_at(c.target), c.target.y))
	assert_not_null(p)
	assert_almost_eq((p as Vector2).x, v.size.x * 0.5, 1.0)
	assert_almost_eq((p as Vector2).y, v.size.y * 0.5, 1.0)
	var hit: Variant = c.ground_at(p as Vector2)
	assert_almost_eq((hit as Vector3).x, c.target.x, 5.0)
	assert_almost_eq((hit as Vector3).z, c.target.y, 5.0)
```

- [ ] **Step 2: Run it (fails)** — `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_context.gd -gexit`. Expected: `Ignoring script … test_map3d_context.gd` (Map3DContext is not declared).

- [ ] **Step 3: Implement** — `scripts/map3d/map3d_context.gd`:

```gdscript
class_name Map3DContext
extends RefCounted
## What every piece of the 3D map shares (spec 2026-09-20 §1): the data, the
## built world's metadata, the camera and its pose, the terrain, the live
## state and the scales — so a layer never reaches for the Game autoload or
## for the view. Map3DView makes one at load; an editor preview (Task 22)
## makes one from the pack alone.

## The rig moved the camera; the HUD redraws on it.
signal camera_moved

var repo: DataRepository
## The build's root metadata `map3d_world`: {m_per_px, pack_origin, pack_px, sea_y}.
var meta: Dictionary = {}
var bounds := Rect2()
var world: Node3D
## The world's Terrain3D, or null (test fixtures, previews without terrain).
var terrain: Node
var camera: Camera3D
var viewport: SubViewport
## The view's size, design px (Map3DView keeps it current).
var view_size := Vector2.ONE
## The rig's pose: Map3DCameraRig writes these, then emits camera_moved.
var target := Vector2.ZERO
var distance := 1.0
var yaw := 0.0
## The graphics tier's row (Map3DQuality.row); {} reads as full quality.
var quality: Dictionary = {}
## -> GameState. The view passes Game.state's getter; a preview a blank state.
## Unset (the default), the state is null.
var state_fn: Callable = Callable()
## -> int, the clock's speed. Unset: 0 (paused).
var clock_fn: Callable = Callable()
## -> float, window px per design px (the canvas_items stretch). Unset: 1.
var window_scale_fn: Callable = Callable()
## Test seam: when valid, replaces the terrain lookup in height_at.
var height_fn: Callable = Callable()
var _water_normals: NoiseTexture2D


func _init(p_repo: DataRepository, p_meta: Dictionary, p_world: Node3D = null) -> void:
	repo = p_repo
	meta = p_meta
	bounds = Map3DGeometry.world_bounds(meta) if meta.has("pack_px") else Rect2()
	world = p_world
	if world != null:
		terrain = world.get_node_or_null("Terrain3D")


func state() -> GameState:
	return state_fn.call() if state_fn.is_valid() else null


func clock_speed() -> int:
	return int(clock_fn.call()) if clock_fn.is_valid() else 0


func window_scale() -> float:
	return float(window_scale_fn.call()) if window_scale_fn.is_valid() else 1.0


## The graphics tier's share of the window's pixels the 3D view renders at.
func render_scale() -> float:
	return float(quality.get("render_scale", 1.0))


## SubViewport px per design px: every projection, ray and px uniform uses it.
func viewport_px_scale() -> float:
	return window_scale() * render_scale()


## Ground height at a world XZ: the terrain's where it has data, never below
## the sea plane (was Map3DView._height_at).
func height_at(xz: Vector2) -> float:
	if height_fn.is_valid():
		return float(height_fn.call(xz))
	var sea := float(meta.get("sea_y", 0.0))
	if terrain == null or terrain.get("data") == null:
		return sea
	var y: float = terrain.data.get_height(Vector3(xz.x, 0.0, xz.y))
	return sea if is_nan(y) else maxf(y, sea)


func to_world(pack_px: Vector2) -> Vector2:
	return Map3DGeometry.pack_to_world(meta, pack_px)


func to_pack(xz: Vector2) -> Vector2:
	return Map3DGeometry.world_to_pack(meta, xz)


func ground_of_pack(pack_px: Vector2) -> Vector3:
	var xz := to_world(pack_px)
	return Vector3(xz.x, height_at(xz), xz.y)


## A world point in design px, or null behind the camera.
func project(world_pos: Vector3) -> Variant:
	if camera == null or camera.is_position_behind(world_pos):
		return null
	return camera.unproject_position(world_pos) / viewport_px_scale()


## The ground under a point of the view (design px), or null for the sky.
func ground_at(pos: Vector2) -> Variant:
	if camera == null:
		return null
	var px := pos * viewport_px_scale()
	return Map3DGeometry.ground_hit(camera.project_ray_origin(px),
		camera.project_ray_normal(px), height_at)


## Ground metres under one design px at the target (the scale bar's measure).
func metres_per_pixel() -> float:
	return Map3DGeometry.metres_per_pixel(distance, repo.bal("map3d_fov_deg"),
		maxf(view_size.y, 1.0))


## Metres per SubViewport px per metre of camera distance (every screen-constant shader).
func px_per_dist() -> float:
	var h := float(maxi(viewport.size.y, 1)) if viewport != null else 1.0
	return 2.0 * tan(deg_to_rad(repo.bal("map3d_fov_deg")) * 0.5) / h


func line_step() -> float:
	return repo.bal("map3d_line_step_m")


func road_step() -> float:
	return repo.bal("map3d_road_step_m")


func river_step() -> float:
	return repo.bal("map3d_river_mesh_step_m")


## The ripple normal map both waters share (was Map3DView.water_normals).
func water_normals() -> Texture2D:
	if _water_normals == null:
		var noise := FastNoiseLite.new()
		noise.seed = int(repo.bal("map3d_water_seed"))
		noise.frequency = 0.03
		noise.fractal_octaves = 3
		_water_normals = NoiseTexture2D.new()
		_water_normals.width = 256
		_water_normals.height = 256
		_water_normals.seamless = true
		_water_normals.as_normal_map = true
		_water_normals.bump_strength = 6.0
		_water_normals.generate_mipmaps = true
		_water_normals.noise = noise
	return _water_normals
```

Then in `map3d_view.gd`:
- Add `var _ctx: Map3DContext`.
- Rename the body of `_render_scale()` to a new `func _window_scale() -> float` (same body). `_render_scale()` becomes `return _ctx.viewport_px_scale() if _ctx != null else _window_scale()` (Ruling 3).
- In `_load`, right after `_bounds = …`: `_ctx = Map3DContext.new(_repo, _meta, _world)`, then set `_ctx.viewport = _viewport`, `_ctx.view_size = size`, `_ctx.state_fn = func() -> GameState: return Game.state`, `_ctx.clock_fn = func() -> int: return Game.clock_speed`, `_ctx.window_scale_fn = _window_scale`. After the camera exists: `_ctx.camera = _camera`.
- `_height_at(xz)` → `return _ctx.height_at(xz) if _ctx != null else float(_meta.get("sea_y", 0.0))`.
- `_burg_xz(burg)` → `return _ctx.to_world(Vector2(float(burg["x"]), float(burg["y"])))`.
- `ground_at(pos)` → `return _ctx.ground_at(pos) if _ctx != null else null`.
- `water_normals()` → `return _ctx.water_normals() if _ctx != null else null`; delete `_water_normals`.
- `_fit_viewport()`: after sizing, `if _ctx != null: _ctx.view_size = size`.
- `_apply_camera()`: after setting `_camera.transform`, `_ctx.target = _target; _ctx.distance = _distance; _ctx.yaw = _yaw; _ctx.camera_moved.emit()` (before the `_hud.refresh()`, which stays).
- `_metres_per_pixel()` → `return _ctx.metres_per_pixel() if _ctx != null else Map3DGeometry.metres_per_pixel(_distance, _repo.bal("map3d_fov_deg"), maxf(size.y, 1.0))`.
- In `_update_line_scale()`, replace the `per_dist` computation with `var per_dist := _ctx.px_per_dist() if _ctx != null else 2.0 * tan(deg_to_rad(_repo.bal("map3d_fov_deg")) * 0.5) / float(maxi(_viewport.size.y, 1))`.
- Add seam `func context() -> Map3DContext: return _ctx`.

- [ ] **Step 4: Run the new test, then the map3d folder** — the Step 2 command (expected: 8 passed), then `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/map3d -gexit` (expected: all pass).
- [ ] **Step 5: `./run_tests.sh`** — green apart from the known failure, "Errors 2".
- [ ] **Step 6: Commit** — `git add scripts/map3d/map3d_context.gd tests/map3d/test_map3d_context.gd scripts/map3d/map3d_view.gd` and commit `refactor(map3d): Map3DContext — the pose, the scales and the ground the layers share` with the trailer.

---

### Task 2: Ground points read once; one projected-settlement list per pose

**Files:**
- Modify: `scripts/map3d/map3d_context.gd` (`marked_burgs`, `settle_ground`, `burg_ground`, `cell_ground`, `pack_ground`, `projected_settlements`, `settlement_rects`)
- Modify: `scripts/map3d/map3d_view.gd` (`_sorted_burgs`, `_place_markers`, `_show_selected_ring`, `_settlement_marks`, `pick_at`, `manor_badges`, `_cut_landmark_marks`, `_load`)
- Test: `tests/map3d/test_map3d_context.gd` (append)

**Interfaces:**
- Produces on `Map3DContext`: `marked_burgs() -> Array` (codes, sorted), `settle_ground() -> void`, `burg_ground(code: String) -> Vector3`, `cell_ground(id: int) -> Vector3`, `pack_ground(pack_px: Vector2) -> Vector3` (memoised by pack px), `projected_settlements() -> Array` of `{code: String, spec: Dictionary, world: Vector3, screen: Vector2, behind: bool, shown: bool}` cut once per `[camera.global_transform, view_size, viewport_px_scale()]`, `settlement_rects() -> Array[Rect2]` (what counters and landmarks keep clear of).

**Risk:** a pose key that misses a change hands back a stale list. The key holds the camera transform, the view size and the px scale, the same inputs `landmark_marks` keys on today. Settlements never move. **Catch:** every pick, hover and military test in `tests/map3d/` still passes, and the new test proves no height lookup happens per settlement.

- [ ] **Step 1: Failing test** — append to `tests/map3d/test_map3d_context.gd`:

```gdscript
func test_settlement_ground_is_read_at_load_not_per_pose() -> void:
	var v := _view()
	var c := v.context()
	var calls := [0]
	c.height_fn = func(_xz: Vector2) -> float:
		calls[0] += 1
		return 5.0
	v.look_at_home(8000.0)
	calls[0] = 0
	var list := c.projected_settlements()
	assert_gt(list.size(), 0)
	assert_eq(calls[0], 0, "no terrain lookup per settlement")
	assert_true(is_same(c.projected_settlements(), list), "the same pose hands back the same list")
	v.look_at_home(9000.0)
	assert_false(is_same(c.projected_settlements(), list), "a new pose cuts a new one")


func test_the_projected_list_matches_the_marked_burgs() -> void:
	var v := _view()
	var c := v.context()
	var codes: Array = []
	for e: Dictionary in c.projected_settlements():
		codes.append(String(e["code"]))
	assert_eq(codes, c.marked_burgs())
	var capital := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
	var e: Dictionary = c.projected_settlements()[codes.find(capital)]
	assert_true(bool(e["shown"]), "the capital is shown at the opening zoom")
	assert_almost_eq((e["screen"] as Vector2).x, v.size.x * 0.5, 1.0)


func test_cells_are_memoised() -> void:
	var v := _view()
	var c := v.context()
	var id: int = Game.data.manors.keys()[0]
	var calls := [0]
	c.height_fn = func(_xz: Vector2) -> float:
		calls[0] += 1
		return 5.0
	c.cell_ground(id)
	c.cell_ground(id)
	assert_lte(calls[0], 1, "one lookup per cell, ever")
```

- [ ] **Step 2: Run it (fails)** — the Task 1 command. Expected: script ignored (`projected_settlements` and the others not found) or 3 failures.

- [ ] **Step 3: Implement** — add to `Map3DContext`:

```gdscript
var _marked: Array = []
var _burg_ground: Dictionary = {}
var _pack_ground: Dictionary = {}
var _proj_key: Array = []
var _proj: Array = []


## The burgs that get a marker (their group has a map3d_settlements row),
## sorted by code (was Map3DView._sorted_burgs).
func marked_burgs() -> Array:
	if _marked.is_empty():
		for code: String in repo.burgs:
			if repo.map3d_settlements.has(String(repo.burgs[code].get("group", ""))):
				_marked.append(code)
		_marked.sort()
	return _marked


## Every marked burg's ground point, read ONCE at load (spec §1: the data
## never moves, so nothing asks the terrain per frame).
func settle_ground() -> void:
	_burg_ground.clear()
	for code: String in marked_burgs():
		var b: Dictionary = repo.burgs[code]
		_burg_ground[code] = ground_of_pack(Vector2(float(b["x"]), float(b["y"])))
	_proj_key = []


func burg_ground(code: String) -> Vector3:
	if not _burg_ground.has(code):
		var b: Dictionary = repo.burgs[code]
		_burg_ground[code] = ground_of_pack(Vector2(float(b["x"]), float(b["y"])))
	return _burg_ground[code]


## A fixed pack point's ground, looked up once (cells, landmarks — Ruling 4).
func pack_ground(pack_px: Vector2) -> Vector3:
	if not _pack_ground.has(pack_px):
		_pack_ground[pack_px] = ground_of_pack(pack_px)
	return _pack_ground[pack_px]


func cell_ground(id: int) -> Vector3:
	return pack_ground(MapTerrain.cell_center(repo, repo.cells[id]))


## Every marked settlement as the camera sees it now, cut once per pose:
## {code, spec, world, screen (design px), behind, shown}. `shown` is what
## settlement_ring.gdshader still draws: before the camera and short of its
## tier's max_view_m x map3d_ring_fade_start (where the ring begins to fade).
func projected_settlements() -> Array:
	if camera == null:
		return []
	var key := [camera.global_transform, view_size, viewport_px_scale()]
	if key == _proj_key:
		return _proj
	var out: Array = []
	var s := viewport_px_scale()
	var eye := camera.global_position
	var fade_start := repo.bal("map3d_ring_fade_start")
	for code: String in marked_burgs():
		var spec: Dictionary = repo.map3d_settlements[String(repo.burgs[code].get("group", ""))]
		var w := burg_ground(code)
		var behind := camera.is_position_behind(w)
		out.append({"code": code, "spec": spec, "world": w,
			"screen": camera.unproject_position(w) / s, "behind": behind,
			"shown": not behind and eye.distance_to(w) < float(spec["max_view_m"]) * fade_start})
	_proj = out
	_proj_key = key
	return out


## The screen squares (design px) of every settlement dot shown now — what
## the counters and the landmarks keep clear of (was Map3DView._settlement_marks).
func settlement_rects() -> Array:
	var out: Array = []
	for e: Dictionary in projected_settlements():
		if not bool(e["shown"]):
			continue
		var r := Map3DView.marker_px(e["spec"]) * 0.5 + 2.0
		out.append(Rect2((e["screen"] as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	return out
```

(`Map3DView.marker_px` is replaced by `Map3DLayerSettlements.marker_px` in Task 7.)

In `map3d_view.gd`:
- `_load`: call `_ctx.settle_ground()` right before `_place_markers()`.
- `_sorted_burgs()` → `return _ctx.marked_burgs()`.
- `_place_markers()`: the point is `_ctx.burg_ground(code)` instead of `Vector3(xz.x, _height_at(xz), xz.y)`.
- `_show_selected_ring(code)`: the transform origin is `_ctx.burg_ground(code)`.
- `_settlement_marks()` → `return _ctx.settlement_rects()`.
- `pick_at(pos)`: replace the burg loop (`for code in _sorted_burgs(): …`) with:

```gdscript
	for e: Dictionary in _ctx.projected_settlements():
		if not bool(e["shown"]):
			continue
		var spec: Dictionary = e["spec"]
		var reach := maxf(marker_px(spec) * 0.5, _repo.bal("map3d_pick_px"))
		var d := (e["screen"] as Vector2).distance_to(pos)
		if d <= reach and d < best_d:
			best_d = d
			best = String(e["code"])
			best_dot = marker_px(spec) * 0.5 + 2.0
```
  The comparison now runs in design px (the old code scaled both sides by `s`, so the result is identical). Delete the now-unused `s`, `click_px`, `fade_start` and `eye` locals.
- `manor_badges()`: the ground is `_ctx.cell_ground(id)` instead of the `pack_to_world` + `_height_at` pair.
- `_cut_landmark_marks()`: the ground is `_ctx.pack_ground(m["pos"])`.

- [ ] **Step 4: Run** — the Task 1 command (expected: 11 passed), then the `-gdir=res://tests/map3d` run (all pass).
- [ ] **Step 5: Bench** — the Global Constraints command at 3024×1964 with `--layer military`. Expected: WORST ≤ 8.00 ms and no worse than the baseline's military row (the military hover's per-move re-projection is gone).
- [ ] **Step 6: `./run_tests.sh`**, then commit `perf(map3d): settlement ground read once; one projected list per camera pose` (`git add scripts/map3d/map3d_context.gd scripts/map3d/map3d_view.gd tests/map3d/test_map3d_context.gd`).

---

### Task 3: `Map3DLayerLines`, the ribbon host, with `Map3DLineStyle` and `Map3DPriority`

**Files:**
- Create: `scripts/map3d/map3d_priority.gd`, `scripts/map3d/map3d_line_style.gd`, `scripts/map3d/map3d_layer_lines.gd`
- Modify: `scripts/map3d/map3d_view.gd` (the `PRIORITY_*` consts become aliases; `_set_lines`, `_set_road`'s node handling, the `_lines` part of `_update_line_scale`, `line_mesh`, `_load`)
- Test: `tests/map3d/test_map3d_layer_lines.gd`

**Interfaces:**
- Produces: `class_name Map3DPriority` with consts `SEA := -1`, `RIVERS := 0`, `ROADS := 1`, `MANOR_EDGES := 2`, `KINGDOM_BAND := 3`, `SEAMS := 4`, `KINGDOM_HALO := 5`, `KINGDOMS := 6`, `HOVER := 7`, `SELECTION := 8`, `CLOUDS := 9`, `RING_BASE := 10`.
- `class_name Map3DLineStyle extends RefCounted`: fields `a: Color`, `b: Color`, `width_key: String`, `dash_key: String`, `gap_key: String`, `priority: int`, `edge_soft: float`, `one_sided: bool`, `colours: Array`, `fade_across: float`, `fade_power_key: String`; `static func solid(colour: Color, width_key: String, priority: int) -> Map3DLineStyle`; `static func dashed(a: Color, b: Color, width_key: String, dash_key: String, gap_key: String, priority: int) -> Map3DLineStyle`.
- `class_name Map3DLayerLines extends Node3D` (the node `Viewport/Lines`): `bind(p_ctx: Map3DContext) -> void`, `set_lines(line_name: String, lines: Array, style: Map3DLineStyle) -> void`, `put_mesh(line_name: String, arrays: Array, mat: ShaderMaterial) -> void`, `line_mesh(line_name: String) -> ArrayMesh`, `apply_scale() -> void`.

**Risk:** the last task that edited `_set_lines` added `fade_power_key` and vertex colours, so a missed argument would silently drop the realm band's fade. **Catch:** `test_map3d_view.gd::test_the_kingdom_border_is_band_halo_and_ink` (band vertex count equal to the ink's, halo and ink materials) and the new test's band parameters.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_layer_lines.gd`:

```gdscript
extends GutTest
## Map3DLayerLines (spec 2026-09-20 §1): every see-through ribbon of the 3D
## map — roads, trails, manor edges, seams, the kingdom band/halo/ink, the
## hover and the selection — lives under one Lines node, one MeshInstance3D
## per name, in border_line.gdshader at its row of the priority table.

const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)


func _lines() -> Map3DLayerLines:
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 450)
	add_child_autofree(vp)
	var ctx := Map3DContext.new(Game.data, WORLD)
	ctx.viewport = vp
	var lines := Map3DLayerLines.new()
	lines.name = "Lines"
	vp.add_child(lines)
	lines.bind(ctx)
	return lines


func _line() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(2000, 300)])


func test_an_empty_line_leaves_no_mesh() -> void:
	var lines := _lines()
	lines.set_lines("Kingdoms", [], Map3DLineStyle.solid(Color.BLACK,
		"map3d_border_width_px", Map3DPriority.KINGDOMS))
	assert_null(lines.line_mesh("Kingdoms"))
	assert_null(lines.get_node_or_null("Kingdoms"))


func test_a_dashed_line_is_one_mesh_at_its_priority() -> void:
	var lines := _lines()
	var seam := Color(0.2, 0.2, 0.2, 0.5)
	lines.set_lines("Seams", [_line()], Map3DLineStyle.dashed(seam, Color(seam, 0.0),
		"map3d_seam_width_px", "map3d_seam_dash_px", "map3d_seam_gap_px", Map3DPriority.SEAMS))
	var mesh := lines.line_mesh("Seams")
	assert_not_null(mesh)
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.render_priority, Map3DPriority.SEAMS)
	assert_eq(mat.get_shader_parameter("colour_a"), seam)
	assert_almost_eq(float(mat.get_shader_parameter("width_px")), Game.data.bal("map3d_seam_width_px"), 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter("dash_px")), Game.data.bal("map3d_seam_dash_px"), 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter("gap_px")), Game.data.bal("map3d_seam_gap_px"), 0.0001)


func test_the_band_style_reaches_the_shader() -> void:
	var lines := _lines()
	var style := Map3DLineStyle.solid(Color(1, 1, 1, 0.55), "map3d_border_band_px",
		Map3DPriority.KINGDOM_BAND)
	style.one_sided = true
	style.colours = [Color.RED]
	style.fade_across = 1.0
	style.fade_power_key = "map3d_border_band_fade_power"
	lines.set_lines("KingdomBand", [_line()], style)
	var mat := lines.line_mesh("KingdomBand").surface_get_material(0) as ShaderMaterial
	assert_eq(mat.get_shader_parameter("one_sided"), 1.0)
	assert_eq(mat.get_shader_parameter("use_vertex_colour"), 1.0)
	assert_eq(mat.get_shader_parameter("fade_across"), 1.0)
	assert_eq(mat.get_shader_parameter("fade_power"), Game.data.bal("map3d_border_band_fade_power"))


func test_setting_a_line_again_replaces_it() -> void:
	var lines := _lines()
	var style := Map3DLineStyle.solid(Color.BLACK, "map3d_border_width_px", Map3DPriority.KINGDOMS)
	lines.set_lines("Kingdoms", [_line()], style)
	var first := lines.line_mesh("Kingdoms")
	lines.set_lines("Kingdoms", [_line(), _line()], style)
	assert_ne(lines.line_mesh("Kingdoms"), first)
	lines.set_lines("Kingdoms", [], style)
	assert_null(lines.line_mesh("Kingdoms"), "an emptied line leaves nothing behind")


func test_the_priorities_keep_their_order() -> void:
	var order := [Map3DPriority.SEA, Map3DPriority.RIVERS, Map3DPriority.ROADS,
		Map3DPriority.MANOR_EDGES, Map3DPriority.KINGDOM_BAND, Map3DPriority.SEAMS,
		Map3DPriority.KINGDOM_HALO, Map3DPriority.KINGDOMS, Map3DPriority.HOVER,
		Map3DPriority.SELECTION, Map3DPriority.CLOUDS, Map3DPriority.RING_BASE]
	for i in range(1, order.size()):
		assert_lt(order[i - 1], order[i])
	assert_eq(Map3DView.PRIORITY_KINGDOMS, Map3DPriority.KINGDOMS)
```

- [ ] **Step 2: Run it (fails)** — `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_layer_lines.gd -gexit`. Expected: script ignored.

- [ ] **Step 3: Implement.**

`scripts/map3d/map3d_priority.gd`:

```gdscript
class_name Map3DPriority
extends RefCounted
## THE RENDER-PRIORITY TABLE (final review, owner 2026-09-18; the realm band
## and halo 2026-09-19) — the one place the see-through layers' draw order is
## set; higher draws over lower. The sea under everything; the river water
## under every line; the roads (a bridge over the water, under every border);
## the MANORS cell edges; the realm band, the seams, the kingdom border's pale
## halo, its ink, the hovered kingdom's outline, the clicked province's gold;
## then the CLOUDS — over the lines, under the settlement rings — then the
## rings by tier from RING_BASE up, and the gold selection ring over all.
const SEA := -1
const RIVERS := 0
const ROADS := 1
const MANOR_EDGES := 2
const KINGDOM_BAND := 3
const SEAMS := 4
const KINGDOM_HALO := 5
const KINGDOMS := 6
const HOVER := 7
const SELECTION := 8
const CLOUDS := 9
const RING_BASE := 10
```

`scripts/map3d/map3d_line_style.gd`:

```gdscript
class_name Map3DLineStyle
extends RefCounted
## How one ribbon of Map3DLayerLines is drawn (border_line.gdshader): its two
## colours (a dash and its gap), the balance.csv keys of its screen widths,
## its row of Map3DPriority, and the band's extras — a one-sided ribbon, a
## colour per line in place of a's rgb, a fade away from the line by the
## curve fade_power_key names ("" linear).

var a := Color.BLACK
var b := Color.BLACK
var width_key := ""
var dash_key := ""
var gap_key := ""
var priority := 0
var edge_soft := 0.0
var one_sided := false
var colours: Array = []
var fade_across := 0.0
var fade_power_key := ""


static func solid(colour: Color, p_width_key: String, p_priority: int) -> Map3DLineStyle:
	var s := Map3DLineStyle.new()
	s.a = colour
	s.b = colour
	s.width_key = p_width_key
	s.priority = p_priority
	return s


static func dashed(p_a: Color, p_b: Color, p_width_key: String, p_dash_key: String,
		p_gap_key: String, p_priority: int) -> Map3DLineStyle:
	var s := solid(p_a, p_width_key, p_priority)
	s.b = p_b
	s.dash_key = p_dash_key
	s.gap_key = p_gap_key
	return s
```

`scripts/map3d/map3d_layer_lines.gd`:

```gdscript
class_name Map3DLayerLines
extends Node3D
## The ribbon host (spec 2026-09-20 §1): Roads, Trails, ManorEdges, Seams,
## KingdomBand, KingdomHalo, Kingdoms, Hover and Selection, each ONE
## MeshInstance3D named for its line, draped on the relief
## (Map3DBorders.ribbon_arrays) and kept a constant SCREEN width by its shader.
## An empty line leaves no node, so line_mesh() is null for it.

const BORDER_SHADER := preload("res://scripts/map3d/border_line.gdshader")

var ctx: Map3DContext


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx


## One ribbon layer in border_line.gdshader, replacing any before.
func set_lines(line_name: String, lines: Array, style: Map3DLineStyle) -> void:
	var arrays := Map3DBorders.ribbon_arrays(lines, ctx.height_at, [], style.one_sided,
		style.colours)
	var mat := ShaderMaterial.new()
	mat.shader = BORDER_SHADER
	mat.render_priority = style.priority
	mat.set_shader_parameter("colour_a", style.a)
	mat.set_shader_parameter("colour_b", style.b)
	mat.set_shader_parameter("edge_soft", style.edge_soft)
	mat.set_shader_parameter("one_sided", 1.0 if style.one_sided else 0.0)
	mat.set_shader_parameter("use_vertex_colour", 1.0 if not style.colours.is_empty() else 0.0)
	mat.set_shader_parameter("fade_across", style.fade_across)
	mat.set_shader_parameter("fade_power",
		ctx.repo.bal(style.fade_power_key) if style.fade_power_key != "" else 1.0)
	mat.set_meta("width_key", style.width_key)
	mat.set_meta("dash_key", style.dash_key)
	mat.set_meta("gap_key", style.gap_key)
	put_mesh(line_name, arrays, mat)


## Any ribbon mesh (the roads bring their own material), replacing any
## before; nothing when `arrays` is empty.
func put_mesh(line_name: String, arrays: Array, mat: ShaderMaterial) -> void:
	var old := get_node_or_null(line_name)
	if old != null:
		remove_child(old)
		old.queue_free()
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = line_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lines are thin and long: never culled by a box the relief lift pushes them out of.
	mi.extra_cull_margin = 16384.0
	add_child(mi)
	_scale_material(mat)


func line_mesh(line_name: String) -> ArrayMesh:
	var mi := get_node_or_null(line_name) as MeshInstance3D
	return mi.mesh as ArrayMesh if mi != null else null


## Every line's screen-px values in SubViewport px (on load, resize, a tier change).
func apply_scale() -> void:
	for mi: MeshInstance3D in get_children():
		var mat := mi.mesh.surface_get_material(0) as ShaderMaterial
		if mat != null:
			_scale_material(mat)


func _scale_material(mat: ShaderMaterial) -> void:
	if ctx == null:
		return
	var s := ctx.viewport_px_scale()
	mat.set_shader_parameter("px_per_dist", ctx.px_per_dist())
	mat.set_shader_parameter("lift_px", ctx.repo.bal("map3d_line_lift_px") * s)
	mat.set_shader_parameter("width_px", ctx.repo.bal(String(mat.get_meta("width_key"))) * s)
	var dash_key := String(mat.get_meta("dash_key", ""))
	mat.set_shader_parameter("dash_px", ctx.repo.bal(dash_key) * s if dash_key != "" else 0.0)
	var gap_key := String(mat.get_meta("gap_key", ""))
	mat.set_shader_parameter("gap_px", ctx.repo.bal(gap_key) * s if gap_key != "" else 0.0)
```

In `map3d_view.gd`:
- Replace the twelve `const PRIORITY_* := <n>` with aliases, e.g. `const PRIORITY_SEA := Map3DPriority.SEA` … `const PRIORITY_RING_BASE := Map3DPriority.RING_BASE`. Move the table's comment to `Map3DPriority`.
- `var _lines: Map3DLayerLines`. In `_load`: `_lines = Map3DLayerLines.new(); _lines.name = "Lines"; _viewport.add_child(_lines); _lines.bind(_ctx)`.
- `_set_lines(...)` keeps its 13-parameter signature (callers are unchanged in this task) and becomes: build `var st := Map3DLineStyle.dashed(a, b, width_key, dash_key, gap_key, priority)`, then set `st.edge_soft`, `st.one_sided`, `st.colours`, `st.fade_across`, `st.fade_power_key` from its arguments, then `_lines.set_lines(line_name, lines, st)`.
- `_set_road(...)`: delete its old-node removal, `ArrayMesh`, `MeshInstance3D` and `_update_line_scale()` lines, and end with `_lines.put_mesh(line_name, arrays, mat)`. The `arrays.is_empty()` early return goes too, because `put_mesh` handles it.
- `_update_line_scale()`: replace its `if _lines != null: for mi …` block with `if _lines != null: _lines.apply_scale()`.
- `line_mesh(line_name)` → `return _lines.line_mesh(line_name) if _lines != null else null`.

- [ ] **Step 4: Run** — the Step 2 command (5 passed), then `-gdir=res://tests/map3d` (all pass, including `test_map3d_api.gd`).
- [ ] **Step 5: `./run_tests.sh`**; commit `refactor(map3d): Map3DLayerLines hosts every ribbon; the priority table in Map3DPriority` (`git add scripts/map3d/map3d_priority.gd scripts/map3d/map3d_line_style.gd scripts/map3d/map3d_layer_lines.gd scripts/map3d/map3d_view.gd tests/map3d/test_map3d_layer_lines.gd`).

---
### Task 4: Rivers, sea and sun leave the view

**Files:**
- Create: `scripts/map3d/map3d_layer_rivers.gd`, `scripts/map3d/map3d_layer_sea.gd`, `scripts/map3d/map3d_environment.gd`
- Modify: `scripts/map3d/map3d_view.gd` (delete `_build_rivers`, `_dress_sea`, `_apply_sun_shadow_look`, `_river_mat`, `_sea_mat`, `_river_courses`; forward `sea_material`, `river_material`; `layer_names` / `set_layer_visible` for `Sea`; the river part of `_update_line_scale`)
- Test: `tests/map3d/test_map3d_layers.gd` (new; Tasks 5–9 append to it)

**Interfaces:**
- Produces: `class_name Map3DLayerRivers extends MeshInstance3D` (node `Viewport/Rivers`): `build(p_ctx: Map3DContext, scene_path: String) -> void`, `material() -> ShaderMaterial`, `courses() -> Array`, `apply_scale() -> void`.
- `class_name Map3DLayerSea extends MeshInstance3D` (node `Viewport/Sea`): `build(p_ctx: Map3DContext) -> void` (dresses the build's `Sea` plane: takes its mesh and transform, hides the original), `material() -> ShaderMaterial`, `has_water() -> bool`.
- `class_name Map3DEnvironment extends RefCounted`: `static func apply_sun_look(repo: DataRepository, sun: DirectionalLight3D) -> void`.

**Risk:** the Rivers node now always exists (it holds no mesh when there is no `rivers.json`), and the build's Sea is hidden in favour of the layer's copy. `layer_names()` must keep listing a layer only when it has content. **Catch:** `test_rivers_beside_the_scene_become_the_rivers_layer`, `test_the_builds_sea_wears_the_banded_water`, `test_the_seas_band_colours_go_in_raw`, `test_the_rivers_colours_go_in_raw`, and the new tests below.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_layers.gd`:

```gdscript
extends GutTest
## The 3D map's layers, each its own script (spec 2026-09-20 §1, §5 step 4):
## the view builds them and forwards to them; these tests hold that each
## layer is the node the view's seams name, with the same look as before.

const FIXTURE := "user://test_map3d_layers_world.tscn"
const SEA_FIXTURE := "user://test_map3d_layers_sea.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()
	var sea_root := Node3D.new()
	sea_root.name = "SeaFixture"
	sea_root.set_meta("map3d_world", WORLD)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = PlaneMesh.new()
	sea.position = Vector3(0, 5.0, 0)
	sea_root.add_child(sea)
	sea.owner = sea_root
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sea_root.add_child(sun)
	sun.owner = sea_root
	var packed_sea := PackedScene.new()
	packed_sea.pack(sea_root)
	ResourceSaver.save(packed_sea, SEA_FIXTURE)
	sea_root.free()


func after_each() -> void:
	if FileAccess.file_exists("user://rivers.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rivers.json"))


func _view(path: String = FIXTURE) -> Map3DView:
	var v := Map3DView.create(Game.data, path)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_rivers_are_their_own_layer() -> void:
	var f := FileAccess.open("user://rivers.json", FileAccess.WRITE)
	f.store_string('{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [500, 0, 9, 40, 1]]}]}')
	f.close()
	var v := _view()
	var rivers := v.viewport().get_node("Rivers")
	assert_true(rivers is Map3DLayerRivers)
	assert_eq((rivers as Map3DLayerRivers).material(), v.river_material())
	assert_gt((rivers as Map3DLayerRivers).courses().size(), 0, "the bridges read the courses")
	assert_eq(v.river_material().render_priority, Map3DPriority.RIVERS)


func test_no_rivers_file_no_rivers_layer_listed() -> void:
	var v := _view()
	assert_false("Rivers" in v.layer_names())


func test_the_sea_layer_dresses_the_builds_plane() -> void:
	var v := _view(SEA_FIXTURE)
	var sea := v.viewport().get_node("Sea")
	assert_true(sea is Map3DLayerSea)
	assert_eq((sea as Map3DLayerSea).material_override, v.sea_material())
	assert_not_null((sea as Map3DLayerSea).mesh, "the build's plane, taken over")
	assert_eq(v.sea_material().render_priority, Map3DPriority.SEA)
	v.set_layer_visible("Sea", false)
	assert_false((sea as Node3D).visible)


func test_the_suns_shadow_look_is_data() -> void:
	var v := _view(SEA_FIXTURE)
	var suns := v.viewport().find_children("*", "DirectionalLight3D", true, false)
	assert_eq(suns.size(), 1)
	var sun := suns[0] as DirectionalLight3D
	assert_almost_eq(sun.shadow_opacity, Game.data.bal("map3d_sun_shadow_opacity"), 0.0001)
	assert_almost_eq(sun.shadow_blur, Game.data.bal("map3d_sun_shadow_blur"), 0.0001)
```

- [ ] **Step 2: Run it (fails)** — `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_layers.gd -gexit`. Expected: script ignored.

- [ ] **Step 3: Implement (mechanical moves).**
  - `Map3DLayerRivers`: `const RIVER_SHADER := preload("res://scripts/map3d/water_river.gdshader")`, `var ctx: Map3DContext`, `var _mat: ShaderMaterial`, `var _courses: Array = []`. `_ready()` sets `cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF` and `extra_cull_margin = 16384.0`. `build(p_ctx, scene_path)` is the body of `Map3DView._build_rivers` (lines 531–574). Changes: `_scene_path` → `scene_path`; `_repo` → `ctx.repo`; `_height_at` → `ctx.height_at`; `water_normals()` → `ctx.water_normals()`; `_repo.bal("map3d_river_mesh_step_m")` → `ctx.river_step()`; `_river_courses` → `_courses`; `_river_mat` → `_mat`. It ends with `self.mesh = mesh` in place of making a MeshInstance3D and adding it to the viewport; `PRIORITY_RIVERS` → `Map3DPriority.RIVERS`. `apply_scale()` is the `_river_mat` block of `_update_line_scale` (lines 1246–1248), with `s` = `ctx.viewport_px_scale()` and `per_dist` = `ctx.px_per_dist()`, skipped while `_mat == null`. `material()` returns `_mat`; `courses()` returns `_courses`.
  - `Map3DLayerSea`: `const SEA_SHADER := preload("res://scripts/map3d/water_sea.gdshader")`, `var ctx`, `var _mat`. `build(p_ctx)`: `var src := ctx.world.get_node_or_null("Sea") as MeshInstance3D if ctx.world != null else null`; if null, return (no water: `has_water()` is false). Otherwise `mesh = src.mesh; global_transform = src.global_transform; src.visible = false`, then the body of `_dress_sea` (lines 583–622) with `_repo` → `ctx.repo`, `_meta` → `ctx.meta`, `water_normals()` → `ctx.water_normals()`, `PRIORITY_SEA` → `Map3DPriority.SEA`, and a final `material_override = _mat` in place of `sea.material_override`. `has_water()` returns `mesh != null`.
  - `Map3DEnvironment.apply_sun_look(repo, sun)` is the body of `_apply_sun_shadow_look` (the two `shadow_*` lines), moving its doc comment with it.
  - View: `var _rivers: Map3DLayerRivers`, `var _sea: Map3DLayerSea`. In `_load`, replace `_build_rivers(); _dress_sea(); _apply_sun_shadow_look()` with:

```gdscript
	_sea = Map3DLayerSea.new()
	_sea.name = "Sea"
	_viewport.add_child(_sea)
	_sea.build(_ctx)
	_rivers = Map3DLayerRivers.new()
	_rivers.name = "Rivers"
	_viewport.add_child(_rivers)
	_rivers.build(_ctx, _scene_path)
	var sun := _world.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		Map3DEnvironment.apply_sun_look(_repo, sun)
```
  - `sea_material()` → `return _sea.material() if _sea != null else null`; `river_material()` → `return _rivers.material() if _rivers != null else null`; `_river_courses` reads become `_rivers.courses()` (in `_build_roads`).
  - `_update_line_scale()`: replace the `_river_mat` block with `if _rivers != null: _rivers.apply_scale()`.
  - `layer_names()`: `"Rivers"` only when `_rivers != null and _rivers.mesh != null`; `"Sea"` when `_sea != null and _sea.has_water()` (in place of the world's Sea). `set_layer_visible("Sea", on)` → `_sea.visible = on`.
- [ ] **Step 4: Run** — the Step 2 command (4 passed), then `-gdir=res://tests/map3d`.
- [ ] **Step 5: `./run_tests.sh`**, bench (the Global Constraints command; WORST ≤ 8.00 ms), then commit `refactor(map3d): rivers, sea and sun leave the view` with the three new scripts, the view and the test.

---

### Task 5: Clouds leave the view

**Files:**
- Create: `scripts/map3d/map3d_layer_clouds.gd`
- Modify: `scripts/map3d/map3d_view.gd` (delete `_build_clouds`, `_cloud_material`, `_cloud_shadow_material`, `_visible_ground`, `_step_clouds`, the six `_cloud_*` and six `_ground_cache_*` vars; forward `cloud_count`)
- Test: `tests/map3d/test_map3d_layers.gd` (append)

**Interfaces:**
- Produces: `class_name Map3DLayerClouds extends MultiMeshInstance3D` (node `Viewport/Clouds`, child `Shadows`): `build(p_ctx: Map3DContext) -> void`, `step(delta: float) -> void`, `count() -> int`, `set_quality(max_clouds: int, shadows: bool) -> void` (used from Task 17; until then `build` uses `map3d_cloud_max` and shadows on).

**Risk:** the cloud and shadow shaders must stay two files (the Compatibility alpha-scissor trap), and the twin must share the deck's MultiMesh. **Catch:** `test_clouds_come_with_play_and_go_with_pause`, `test_the_render_priority_table_orders_every_layer`, and the new test's twin assertions.

- [ ] **Step 1: Failing test** — append:

```gdscript
func test_the_clouds_are_their_own_layer_with_a_shadow_twin() -> void:
	var v := _view()
	var clouds := v.viewport().get_node("Clouds")
	assert_true(clouds is Map3DLayerClouds)
	var twin := clouds.get_node("Shadows") as MultiMeshInstance3D
	assert_eq(twin.multimesh, (clouds as MultiMeshInstance3D).multimesh, "one shape, one shadow")
	assert_eq(twin.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	var deck := (clouds as MultiMeshInstance3D).material_override as ShaderMaterial
	var shade := twin.material_override as ShaderMaterial
	assert_ne(deck.shader, shade.shader, "two shader files (the Compatibility trap)")
	Game.set_clock_speed(1)
	(clouds as Map3DLayerClouds).step(0.1)
	assert_eq((clouds as Map3DLayerClouds).count(), v.cloud_count())
	Game.set_clock_speed(0)
```

- [ ] **Step 2: Run it (fails)** — the Task 4 command.
- [ ] **Step 3: Implement.** `Map3DLayerClouds`: `const CLOUD_SHADER := preload("res://scripts/map3d/cloud_deck.gdshader")`, `const CLOUD_SHADOW_SHADER := preload("res://scripts/map3d/cloud_shadow.gdshader")`, `var ctx`, `var _field: Map3DCloudField`, `var _params: Dictionary`, `var _depth_ratio := 0.6`, and the six ground-cache vars. `build(p_ctx)` is the body of `_build_clouds` (lines 652–681) with `_repo` → `ctx.repo`, `_cloud_mm` → a local `mm` assigned to `self.multimesh`, the deck's settings on `self` (not on a new node), and the twin made as before and added as a child named `Shadows`. `_cloud_material` / `_cloud_shadow_material` move verbatim (`PRIORITY_CLOUDS` → `Map3DPriority.CLOUDS`). `_visible_ground()` moves with its cache: `_target` / `_distance` / `_yaw` / `size` / `ground_at` → `ctx.target` / `ctx.distance` / `ctx.yaw` / `ctx.view_size` / `ctx.ground_at`. `step(delta)` is `_step_clouds` with `Game.clock_speed` → `ctx.clock_speed()`, `_cloud_mm` → `multimesh`, `_cloud_field` → `_field`. `count()` returns `multimesh.visible_instance_count if multimesh != null else 0`. `set_quality(max_clouds, shadows)`: `_params["max"] = max_clouds; multimesh.instance_count = max_clouds; multimesh.visible_instance_count = mini(multimesh.visible_instance_count, max_clouds); get_node("Shadows").visible = shadows`. View: `var _clouds: Map3DLayerClouds`. In `_load`: `_clouds = Map3DLayerClouds.new(); _clouds.name = "Clouds"; _viewport.add_child(_clouds); _clouds.build(_ctx)`. `_process`: `if _clouds != null: _clouds.step(delta)`. `cloud_count()` → `return _clouds.count() if _clouds != null else 0`.
- [ ] **Step 4: Run** the file, then `-gdir=res://tests/map3d`; **Step 5:** `./run_tests.sh`, bench, commit `refactor(map3d): the clouds are their own layer` (`map3d_layer_clouds.gd`, the view, the test).

---

### Task 6: Roads and bridges leave the view

**Files:**
- Create: `scripts/map3d/map3d_layer_roads.gd`
- Modify: `scripts/map3d/map3d_view.gd` (delete `_build_roads`, `_texture_pair`, `_set_road`, `_build_bridges`, `_bridge_list`, `ROAD_SHADER`, `ROAD_TEXTURE`, `BRIDGE_TEXTURE`; forward `bridge_rules`, `bridges`; add `component`)
- Test: `tests/map3d/test_map3d_layers.gd` (append)

**Interfaces:**
- Produces: `class_name Map3DLayerRoads extends RefCounted`: `bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_viewport: SubViewport) -> void`, `build(courses: Array) -> void`, `bridge_rules() -> Dictionary`, `bridges() -> Array`, `static func texture_pair(base: String) -> Array`. It owns `Lines/Roads`, `Lines/Trails` (through `Map3DLayerLines.put_mesh`) and `Viewport/Bridges`.
- On the view: `component(key: String) -> Object` (Ruling 18), here answering `"roads"`.

**Risk:** the bridges read the river courses, so the roads must still be built after the rivers. **Catch:** a new test that the road ribbons exist at `Map3DPriority.ROADS` and that `bridges()` still equals the layer's list. `test_map3d_bridges.gd` covers the pure planner.

- [ ] **Step 1: Failing test** — append:

```gdscript
func test_the_roads_are_one_builder_writing_lines_and_bridges() -> void:
	var v := _view()
	assert_true(v.component("roads") is Map3DLayerRoads)
	var roads := v.line_mesh("Roads")
	assert_not_null(roads, "the pack's roads draped on the ground")
	var mat := roads.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.render_priority, Map3DPriority.ROADS)
	assert_eq(mat.get_shader_parameter("width_m"), Game.data.bal("map3d_road_width_m"))
	assert_eq(v.bridges(), (v.component("roads") as Map3DLayerRoads).bridges())
	assert_eq(v.bridge_rules()["abut_m"], Game.data.bal("map3d_bridge_abut_m"))
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement.** `Map3DLayerRoads` holds `const ROAD_SHADER := preload("res://scripts/map3d/road_line.gdshader")`, `const ROAD_TEXTURE := "res://assets/map3d/textures/rocky_trail_02"`, `const BRIDGE_TEXTURE := "res://assets/map3d/textures/medieval_blocks_03"`, `var ctx`, `var lines`, `var viewport`, `var _bridges: Array = []`. `build(courses)` is `_build_roads` (lines 1041–1056) with `_river_courses` → `courses`, `_height_at` → `ctx.height_at`, `_meta` → `ctx.meta`, `_repo.bal("map3d_road_step_m")` → `ctx.road_step()`; it calls the private `_set_road` (the body of `Map3DView._set_road`, ending in `lines.put_mesh(line_name, arrays, mat)`; `PRIORITY_ROADS` → `Map3DPriority.ROADS`; `_texture_pair` → `texture_pair`) and `_build_bridges` (the body of `Map3DView._build_bridges` with `_viewport` → `viewport`, `_bridge_list` → `_bridges`). `bridge_rules()` and `bridges()` move verbatim. View: `var _roads := Map3DLayerRoads.new()`; in `_load` after `_lines` exists: `_roads.bind(_ctx, _lines, _viewport); _roads.build(_rivers.courses())`. `bridge_rules()` → `return _roads.bridge_rules()`; `bridges()` → `return _roads.bridges()`. Add:

```gdscript
## Test seam (Ruling 18): the inner part named `key`, or null.
func component(key: String) -> Object:
	match key:
		"roads":
			return _roads
	return null
```
  Later tasks add their keys to this `match`.
- [ ] **Step 4–5:** run the file, then the folder, then `./run_tests.sh` and the bench; commit `refactor(map3d): roads and bridges are one builder` (`map3d_layer_roads.gd`, the view, the test).

---

### Task 7: Settlements leave the view

**Files:**
- Create: `scripts/map3d/map3d_layer_settlements.gd`
- Modify: `scripts/map3d/map3d_view.gd` (delete `_place_markers`, `_ring_material`, `_show_selected_ring`, `_sorted_burgs`, `_ring_mats`, `_selected_ring`, `_markers`, `RING_SHADER`; `marker_px`, `marker_counts`, `selected_ring_visible` become forwarders; `SELECTED_RING_ALWAYS_M` an alias), `scripts/map3d/map3d_context.gd` (`settlement_rects` calls `Map3DLayerSettlements.marker_px`)
- Test: `tests/map3d/test_map3d_layers.gd` (append)

**Interfaces:**
- Produces: `class_name Map3DLayerSettlements extends Node3D` (node `Viewport/Markers`): `bind(p_ctx: Map3DContext) -> void`, `build() -> void`, `show_selected(code: String) -> void`, `selected_visible() -> bool`, `counts() -> Dictionary`, `apply_scale() -> void`, `static func marker_px(spec: Dictionary) -> float`, `const SELECTED_RING_ALWAYS_M := 1000000.0`.

**Risk:** the per-tier render priorities (`RING_BASE + rank by marker_px`), and the gold ring's per-selection metas `ring_px` / `line_px` read by `apply_scale`. **Catch:** `test_ring_render_priority_rises_with_tier`, `test_rings_take_their_size_from_the_table`, `test_a_clicked_settlement_wears_the_gold_ring_until_cleared`, `test_settlements_are_black_dots_and_only_the_capital_is_ringed`, `test_every_settlement_gets_a_marker_by_group`.

- [ ] **Step 1: Failing test** — append:

```gdscript
func test_the_markers_are_their_own_layer() -> void:
	var v := _view()
	var markers := v.viewport().get_node("Markers")
	assert_true(markers is Map3DLayerSettlements)
	assert_eq((markers as Map3DLayerSettlements).counts(), v.marker_counts())
	var spec: Dictionary = Game.data.map3d_settlements["capital"]
	assert_eq(Map3DView.marker_px(spec), Map3DLayerSettlements.marker_px(spec))
	assert_eq(Map3DView.SELECTED_RING_ALWAYS_M, Map3DLayerSettlements.SELECTED_RING_ALWAYS_M)
	assert_false((markers as Map3DLayerSettlements).selected_visible())
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement.** Move `_place_markers` → `build()` (burg points from `ctx.marked_burgs()` / `ctx.burg_ground(code)`; `_markers.add_child` → `add_child`; `PRIORITY_RING_BASE` → `Map3DPriority.RING_BASE`; `MapPalette.named(_repo, …)` → `MapPalette.named(ctx.repo, …)`; the trailing `_update_line_scale()` → `apply_scale()`). Move `_ring_material` → private `_ring_material`, its `_ring_mats` with it. Move `_show_selected_ring` → `show_selected(code)` (point `ctx.burg_ground(code)`, then `apply_scale()`). Move the ring half of `_update_line_scale` (lines 1240–1245) → `apply_scale()` (`s` = `ctx.viewport_px_scale()`, `per_dist` = `ctx.px_per_dist()`). Move `marker_counts` → `counts()` (same loop over `get_children()`) and `marker_px` → a static on the layer. View: `var _markers: Map3DLayerSettlements`; in `_load`, `_markers = Map3DLayerSettlements.new(); _markers.name = "Markers"; _viewport.add_child(_markers); _markers.bind(_ctx); _markers.build()`. `static func marker_px(spec) -> float: return Map3DLayerSettlements.marker_px(spec)`; `const SELECTED_RING_ALWAYS_M := Map3DLayerSettlements.SELECTED_RING_ALWAYS_M`; `_show_selected_ring(code)` → `if _markers != null: _markers.show_selected(code)`; `selected_ring_visible()` → `return _markers != null and _markers.selected_visible()`; `marker_counts()` → `return _markers.counts() if _markers != null else {}`; `_update_line_scale()` → `if _markers != null: _markers.apply_scale()`. In `Map3DContext.settlement_rects`, use `Map3DLayerSettlements.marker_px`.
- [ ] **Step 4–5:** run, suite, bench, commit `refactor(map3d): the settlement markers are their own layer`.

---

### Task 8: Borders and the hover outline leave the view

**Files:**
- Create: `scripts/map3d/map3d_layer_borders.gd`
- Modify: `scripts/map3d/map3d_view.gd` (`refresh_borders` shrinks to orchestration; delete `_draw_hover`'s body, `_border_sig`, `_hover_lines`)
- Test: `tests/map3d/test_map3d_layers.gd` (append)

**Interfaces:**
- Produces: `class_name Map3DLayerBorders extends RefCounted`: `bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines) -> void`, `refresh() -> bool` (true when it rebuilt), `draw_hover(kingdom: String) -> void`, `hovered() -> String`.

**Risk:** the rebuild order and the realm band's one-sided vertex-colour ribbon with `map3d_border_band_fade_power`. **Catch:** `test_borders_and_seams_are_laid_from_the_live_outlines`, `test_the_kingdom_border_is_band_halo_and_ink`, `test_a_conquest_redraws_the_borders`, `test_map3d_hover.gd` (hover outline from the live outline, over the borders and under the selection).

- [ ] **Step 1: Failing test** — append:

```gdscript
func test_the_borders_rebuild_only_when_ownership_moves() -> void:
	var v := _view()
	var borders := v.component("borders") as Map3DLayerBorders
	assert_not_null(borders)
	v.refresh_borders()
	assert_false(borders.refresh(), "same owners: nothing rebuilt")
	var mine := Game.data.resolve_realm("player_realm")
	var raider := Game.data.resolve_realm("raider_realm")
	var province: String = MapOwnership.provinces_of(Game.data, Game.state, raider)[0]
	MapOwnership.set_owner(Game.data, Game.state, province, mine, "test: conquest")
	assert_true(borders.refresh(), "a conquest rebuilds")
	var band := v.line_mesh("KingdomBand").surface_get_material(0) as ShaderMaterial
	assert_eq(band.render_priority, Map3DPriority.KINGDOM_BAND)
	assert_eq(band.get_shader_parameter("fade_power"), Game.data.bal("map3d_border_band_fade_power"))
	borders.draw_hover(mine)
	assert_eq(borders.hovered(), mine)
	assert_not_null(v.line_mesh("Hover"))
	borders.draw_hover("")
	assert_null(v.line_mesh("Hover"))
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement.** `Map3DLayerBorders`: `var ctx`, `var lines`, `var _sig := 0`, `var _hover := ""`, `var _hover_lines: Dictionary = {}`. `refresh()`:

```gdscript
## Rebuild the realm band, the halo, the ink and the seams if ownership moved
## since they were built (the signature WorldMapView keys its rings on).
func refresh() -> bool:
	var st := ctx.state()
	var sig := 0 if st == null else hash([st.province_owner.hash(), st.manor_province.hash()])
	if sig == _sig and lines.line_mesh("Kingdoms") != null:
		return false
	_sig = sig
	_hover_lines.clear()
	draw_hover(_hover)
	_build(st)
	return true
```
  `_build(st)` is lines 838–866 of today's `refresh_borders`. Each `_set_lines(name, lines, a, b, width, dash, gap, prio, soft, one_sided, colours, fade, power_key)` becomes a `Map3DLineStyle` (`solid` or `dashed`) with the same values in the named fields, then `lines.set_lines(name, lines, style)`. `step` is `ctx.line_step()`, `_meta` is `ctx.meta`, and each `PRIORITY_X` is `Map3DPriority.X`. `draw_hover(kingdom)` is `_draw_hover` with `_hover_kingdom` → `kingdom` (stored in `_hover`), the lines cache kept in `_hover_lines`. View: `var _borders := Map3DLayerBorders.new()`, bound in `_load` after `_lines`. `refresh_borders()` becomes:

```gdscript
func refresh_borders() -> void:
	if not _loaded:
		return
	_refresh_theme()  # a manor bought or a province taken recolours the ground
	if _borders.refresh():
		if _hud != null:
			_hud.refresh()  # the names follow the land held
		_draw_selection()
```
  `_draw_hover()` → `if _loaded: _borders.draw_hover(_hover_kingdom)`. Add `"borders": return _borders` to `component`.
- [ ] **Step 4–5:** run, suite, bench, commit `refactor(map3d): the kingdom border and the hover outline are one layer`.

---

### Task 9: MANORS and HEIGHTS on the ground leave the view

**Files:**
- Create: `scripts/map3d/map3d_layer_themes.gd`
- Modify: `scripts/map3d/map3d_view.gd` (delete `_prepare_ground_tint`, `_refresh_theme`'s body, `_build_lut`, `_build_manor_edges`, `_theme`, `_heat`, `_theme_sig`, `_cell_lut`, `_lut_image`, `_tint_mat`, `_edges_built`, `FIELD_MAP_M_PER_TEXEL`'s body; `load_field_map`, `manor_theme`, `heat_on`, `cell_lut`, `lut_color` become forwarders)
- Test: `tests/map3d/test_map3d_layers.gd` (append)

**Interfaces:**
- Produces: `class_name Map3DLayerThemes extends RefCounted`: `bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines) -> void`, `prepare(scene_path: String) -> void` (the Terrain3D patch), `set_theme(theme_name: String) -> void`, `theme() -> String`, `heat_on() -> bool`, `refresh() -> void`, `cell_lut() -> ImageTexture`, `lut_color(id: int) -> Color`, `static func load_field_map(scene_path: String) -> Texture2D`, `const FIELD_MAP_M_PER_TEXEL := 40.0`.

**Risk:** `heat_on()` must work before any load (the theme is set before `_loaded`), and the patched material must be the world's own duplicate. **Catch:** `test_map3d_manor_themes.gd` (LUT, edges, picking), `test_map3d_heights.gd::test_heights_is_a_theme_of_its_own`, `test_map3d_tab.gd` (themes handed down by GameRoot), and the new test.

- [ ] **Step 1: Failing test** — append:

```gdscript
func test_the_themes_are_one_layer_that_works_before_load() -> void:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.set_manor_theme("heights")
	assert_true(v.heat_on(), "the theme holds before the world loads")
	var themes := v.component("themes") as Map3DLayerThemes
	assert_not_null(themes)
	assert_eq(themes.theme(), "heights")
	v.activate()
	v.set_manor_theme("manors")
	assert_false(v.heat_on())
	assert_not_null(v.cell_lut())
	assert_not_null(v.viewport().get_node_or_null("Lines/ManorEdges"))
	assert_eq(Map3DView.load_field_map("user://nowhere/world.tscn"), null)
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement.** Everything moves verbatim with `_repo` → `ctx.repo`, `_meta` → `ctx.meta`, `_world` → `ctx.world`, `_state()` → `ctx.state()`, `_set_lines("ManorEdges", …)` → `lines.set_lines("ManorEdges", pairs_lines, Map3DLineStyle.solid(ink, "map_manor_line_width", Map3DPriority.MANOR_EDGES))`, and `map3d_line_step_m` → `ctx.line_step()`: `_prepare_ground_tint` → `prepare(scene_path)`, `_build_lut` → `_build_lut`, `_build_manor_edges` → `_build_manor_edges`, the ground part of `_refresh_theme` → `refresh()`. `set_theme(name)` only stores it and sets `_heat = name == "heights"`; `refresh()` returns at once while `ctx == null` (unbound). View: `var _themes := Map3DLayerThemes.new()` is created at field initialisation, so it exists before `_ready`. It is bound in `_load` after `_lines` (`_themes.bind(_ctx, _lines); _themes.prepare(_scene_path)`), where `_prepare_ground_tint()` used to be. `set_manor_theme(name)`: keep the manor-forgetting block; replace `_theme = theme_name` with `_themes.set_theme(theme_name)`; the block's `_theme != "manors"` becomes `theme_name != "manors"`; then `_refresh_theme()`. `_refresh_theme()` → `if _loaded: _themes.refresh()` then `if _hud != null: _hud.refresh()`. Forwarders: `manor_theme()` → `_themes.theme()`, `heat_on()` → `_themes.heat_on()`, `cell_lut()` → `_themes.cell_lut()`, `lut_color(id)` → `_themes.lut_color(id)`, `static func load_field_map(p) -> Texture2D: return Map3DLayerThemes.load_field_map(p)`, `const FIELD_MAP_M_PER_TEXEL := Map3DLayerThemes.FIELD_MAP_M_PER_TEXEL`. The remaining reads of `_theme` (in `manor_badges`, `pick_at`) become `_themes.theme()`, and the reads of `_heat` (in `landmark_marks`, `heat_legend_rect`, `pick_at`) become `_themes.heat_on()`. Add `"themes": return _themes` to `component`.
- [ ] **Step 4–5:** run, folder, suite, bench `--layer manors` and `--layer heights`, commit `refactor(map3d): MANORS and HEIGHTS on the ground are one layer`.

---
### Task 10: The camera rig and the input leave the view

**Files:**
- Create: `scripts/map3d/map3d_camera_rig.gd`, `scripts/map3d/map3d_input.gd`
- Modify: `scripts/map3d/map3d_view.gd` (delete `_apply_camera`, `_target`, `_distance`, `_yaw`, `_north_t`, `_north_from`, `_press_pos`, `_dragging`, `_press_on_hud`, `_rpress_pos`, `_rdragged`, `_bounds`; `_gui_input`, `_process`, `_pan_by`, `_zoom_at`, `look_at_pack`, `look_at_home`, `target`, `distance`, `yaw`, `metres_per_pixel` become forwarders; new `request_hover`, `refresh_hud`, `compass_rect`)
- Test: `tests/map3d/test_map3d_rig.gd`

**Interfaces:**
- Produces: `class_name Map3DCameraRig extends Node3D` (node `Viewport/CameraRig`, child `RigCamera`): `bind(p_ctx: Map3DContext) -> void`, `camera() -> Camera3D`, `place(target_xz: Vector2, distance_m: float, yaw_deg: float) -> void`, `apply() -> void`, `pan_by(screen_delta: Vector2) -> void`, `zoom_at(pos: Vector2, new_distance: float) -> void`, `turn_by(dx_px: float) -> void`, `start_north() -> void`, `step(delta: float) -> void`.
- `class_name Map3DInput extends RefCounted`: `const CLICK_SLOP := 10.0`, `bind(p_view: Map3DView, p_rig: Map3DCameraRig, p_repo: DataRepository) -> void`, `handle(event: InputEvent) -> bool`, `key_pan(delta: float) -> bool`.
- On the view: `request_hover(pos: Vector2) -> void`, `refresh_hud() -> void`, `compass_rect() -> Rect2`; `component("input")`, `component("rig")`.

**Risk:** the event-acceptance rules (which branches `accept_event()` today): a wrongly accepted event swallows GUI input, and a missed one lets the map's drag leak. The camera now hangs one node deeper (`Viewport/CameraRig/RigCamera`); grep shows nobody reads that path. **Catch:** every `_gui_input` test in `test_map3d_view.gd` (wheel clamp, drag pans and turns, pinch and pan gestures, zoom under the pointer, the compass turns north, a compass press that moves does not pan, a drag is not a click), the ruler tests and the new tests.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_rig.gd`:

```gdscript
extends GutTest
## Map3DCameraRig and Map3DInput (spec 2026-09-20 §1): the pose lives in the
## context and the rig moves it; the input says which events the view takes.

const FIXTURE := "user://test_map3d_rig_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_camera_hangs_from_the_rig() -> void:
	var v := _view()
	var rig := v.viewport().get_node("CameraRig") as Map3DCameraRig
	assert_not_null(rig)
	assert_eq(rig.camera(), v.camera())
	assert_eq(String(v.camera().name), "RigCamera")
	assert_true(v.camera().current)
	assert_almost_eq(v.camera().fov, Game.data.bal("map3d_fov_deg"), 0.001)


func test_the_rig_pans_zooms_and_turns_through_the_context() -> void:
	var v := _view()
	var rig := v.component("rig") as Map3DCameraRig
	var c := v.context()
	watch_signals(c)
	var t0 := c.target
	rig.pan_by(Vector2(40, 0))
	assert_lt(c.target.x, t0.x, "the ground follows the mouse, the target goes the other way")
	assert_signal_emitted(c, "camera_moved")
	rig.zoom_at(v.size * 0.5, 5000.0)
	assert_almost_eq(c.distance, 5000.0, 0.01)
	var yaw0 := c.yaw
	rig.turn_by(10.0)
	assert_almost_eq(c.yaw, yaw0 - 10.0 * Game.data.bal("map3d_rotate_deg_per_px"), 0.0001)
	assert_eq(v.target(), c.target)
	assert_eq(v.distance(), c.distance)
	assert_eq(v.yaw(), c.yaw)


func test_the_north_ease_runs_on_step() -> void:
	var v := _view()
	var rig := v.component("rig") as Map3DCameraRig
	rig.turn_by(100.0)
	rig.start_north()
	rig.step(Game.data.bal("map3d_compass_reset_s") + 0.01)
	assert_eq(v.context().yaw, 0.0)


func test_the_input_says_which_events_the_view_takes() -> void:
	var v := _view()
	var input := v.component("input") as Map3DInput
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	assert_true(input.handle(wheel), "the wheel zooms")
	var rup := InputEventMouseButton.new()
	rup.button_index = MOUSE_BUTTON_RIGHT
	rup.pressed = false
	assert_false(input.handle(rup), "a right release is not taken, as before")
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(10, 10)
	assert_false(input.handle(hover), "a bare move is only recorded for the hover")
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = v.size * 0.5
	pinch.factor = 1.2
	assert_true(input.handle(pinch))
```

- [ ] **Step 2: Run it (fails)** — `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_rig.gd -gexit`. Expected: script ignored.

- [ ] **Step 3: Implement** — `scripts/map3d/map3d_camera_rig.gd`:

```gdscript
class_name Map3DCameraRig
extends Node3D
## The 3D map's camera (spec 2026-09-20 §1): a target on the ground, a
## distance, a yaw, and a tilt that follows the distance (Map3DGeometry). The
## pose lives in the context — every layer reads it there — and each move
## ends in ctx.camera_moved. A press on the compass eases the view back to
## north over map3d_compass_reset_s.

var ctx: Map3DContext
var _camera: Camera3D
var _north_t := -1.0
var _north_from := 0.0


func _ready() -> void:
	_camera = get_node_or_null("RigCamera") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "RigCamera"
		add_child(_camera)


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	_camera.fov = ctx.repo.bal("map3d_fov_deg")
	_camera.near = ctx.repo.bal("map3d_near_m")
	_camera.far = ctx.repo.bal("map3d_far_m")
	_camera.make_current()
	ctx.camera = _camera


func camera() -> Camera3D:
	return _camera


## Put the rig at a world XZ (clamped to the world), a distance and a yaw.
func place(target_xz: Vector2, distance_m: float, yaw_deg: float) -> void:
	ctx.target = Map3DGeometry.clamp_target(target_xz, ctx.bounds)
	ctx.distance = distance_m
	ctx.yaw = yaw_deg
	apply()


## The camera at the context's pose (was Map3DView._apply_camera).
func apply() -> void:
	var r := ctx.repo
	var pitch := Map3DGeometry.pitch_for(ctx.distance, r.bal("map3d_zoom_min_m"),
		r.bal("map3d_zoom_max_m"), r.bal("map3d_pitch_near_deg"), r.bal("map3d_pitch_far_deg"))
	var ground := Vector3(ctx.target.x, ctx.height_at(ctx.target), ctx.target.y)
	_camera.transform = Map3DGeometry.pose(ground, ctx.distance, ctx.yaw, pitch)
	ctx.camera_moved.emit()


func pan_by(screen_delta: Vector2) -> void:
	ctx.target = Map3DGeometry.clamp_target(
		ctx.target + Map3DGeometry.pan_delta(screen_delta, ctx.metres_per_pixel(), ctx.yaw), ctx.bounds)
	apply()


## Zoom to `new_distance` (clamped) keeping the ground under `pos` under it.
func zoom_at(pos: Vector2, new_distance: float) -> void:
	var anchor: Variant = ctx.ground_at(pos)
	var d := Map3DGeometry.zoomed_by(new_distance, 1.0, ctx.repo.bal("map3d_zoom_min_m"),
		ctx.repo.bal("map3d_zoom_max_m"))
	if anchor != null:
		var a := anchor as Vector3
		ctx.target = Map3DGeometry.clamp_target(
			Map3DGeometry.zoom_about(ctx.target, Vector2(a.x, a.z), ctx.distance, d), ctx.bounds)
	ctx.distance = d
	apply()


## A right-drag turn of `dx_px` screen px; it cancels a north ease.
func turn_by(dx_px: float) -> void:
	_north_t = -1.0
	ctx.yaw -= dx_px * ctx.repo.bal("map3d_rotate_deg_per_px")
	apply()


func start_north() -> void:
	_north_from = ctx.yaw
	_north_t = 0.0


## The compass's ease back to north, a frame at a time.
func step(delta: float) -> void:
	if _north_t < 0.0:
		return
	_north_t += delta / maxf(ctx.repo.bal("map3d_compass_reset_s"), 0.01)
	ctx.yaw = Map3DGeometry.ease_yaw(_north_from, _north_t)
	if _north_t >= 1.0:
		_north_t = -1.0
		ctx.yaw = 0.0
	apply()
```

`scripts/map3d/map3d_input.gd`:

```gdscript
class_name Map3DInput
extends RefCounted
## The 3D map's pointer and keys (spec 2026-09-20 §1; was Map3DView._gui_input
## and the key half of _process). Left or middle drag pans, right drag turns,
## the wheel and a trackpad pinch zoom about the pointer, a two-finger drag
## pans, WASD / arrows pan. A press on the compass eases north. With the
## ruler on, a left click measures and a right CLICK (not a turn) puts it
## away. handle() returns true exactly where the view used to accept_event().

## A press and release further apart than this is a drag (WorldMapView.CLICK_SLOP).
const CLICK_SLOP := 10.0

var view: Map3DView
var rig: Map3DCameraRig
var repo: DataRepository
var _press_pos := Vector2.ZERO
var _dragging := false
var _press_on_hud := false
var _rpress_pos := Vector2.ZERO
## Whether the right button has turned the view since it went down.
var _rdragged := false


func bind(p_view: Map3DView, p_rig: Map3DCameraRig, p_repo: DataRepository) -> void:
	view = p_view
	rig = p_rig
	repo = p_repo


func handle(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		var gain := repo.bal("map3d_pinch_zoom_gain")
		rig.zoom_at(mg.position, rig.ctx.distance / maxf(1.0 + (mg.factor - 1.0) * gain, 0.01))
		return true
	if event is InputEventPanGesture:
		rig.pan_by(-(event as InputEventPanGesture).delta * repo.bal("map3d_pan_gesture_px"))
		return true
	if event is InputEventMouseButton:
		return _button(event as InputEventMouseButton)
	if event is InputEventMouseMotion:
		return _motion(event as InputEventMouseMotion)
	return false


func _button(mb: InputEventMouseButton) -> bool:
	if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var steps := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		rig.zoom_at(mb.position, rig.ctx.distance * pow(repo.bal("map3d_zoom_factor"), steps))
		return true
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and view.compass_rect().has_point(mb.position):
			rig.start_north()
			_press_on_hud = true
			# in step with an ordinary press: a stale press point would let a
			# press-and-move on the compass pan from an old spot
			_press_pos = mb.position
			_dragging = false
			return true
		if not mb.pressed and _press_on_hud:
			_press_on_hud = false
			return true
		if mb.pressed:
			_press_pos = mb.position
			_dragging = false
		elif not _dragging:
			if view.ruler_on:
				view._ruler_click(mb.position)
			else:
				view.select_at(mb.position)
		return true
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_rpress_pos = mb.position
			_rdragged = false
		elif view.ruler_on and not _rdragged and view.ruler().cancel():
			view.refresh_hud()
	return false


func _motion(mm: InputEventMouseMotion) -> bool:
	if view.ruler_on and view.ruler().phase == MapRuler.Phase.STRETCHING:
		var hit: Variant = view.ground_at(mm.position)
		if hit != null and view.ruler().move(Vector2((hit as Vector3).x, (hit as Vector3).z)):
			view.refresh_hud()
	if mm.button_mask == 0:
		view.request_hover(mm.position)
	else:
		view.clear_hover()
	if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _press_on_hud:
			return true
		if not _dragging and _press_pos.distance_to(mm.position) > CLICK_SLOP:
			_dragging = true
		if _dragging:
			rig.pan_by(mm.relative)
		return true
	if mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		rig.pan_by(mm.relative)
		return true
	if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		if _rpress_pos.distance_to(mm.position) > CLICK_SLOP:
			_rdragged = true
		rig.turn_by(mm.relative.x)
		return true
	return false


## WASD / arrows move the VIEW, so the ground moves the other way from a
## drag; true when it moved (the hover re-picks under a still pointer).
func key_pan(delta: float) -> bool:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir == Vector2.ZERO:
		return false
	rig.pan_by(-dir.normalized() * view.size.y * repo.bal("map3d_key_pan_screens_per_s") * delta)
	return true
```

View changes:
- `var _rig: Map3DCameraRig`, `var _input := Map3DInput.new()`. In `_load`, replace the camera block (lines 382–388) with `_rig = Map3DCameraRig.new(); _rig.name = "CameraRig"; _viewport.add_child(_rig); _rig.bind(_ctx); _camera = _rig.camera()`, and `_input.bind(self, _rig, _repo)`. Replace lines 402–406 (`_target = …` through `_apply_camera()`) with `_rig.place(_home(), _repo.bal("map3d_zoom_start_m"), 0.0)` and set `_loaded = true` before it. Connect `_ctx.camera_moved.connect(refresh_hud)` right after the context is made; this replaces the `_hud.refresh()` that `_apply_camera` did.
- `_gui_input(event)` → `if not _loaded: return` then `if _input.handle(event): accept_event()`.
- `_process(delta)`:

```gdscript
func _process(delta: float) -> void:
	if _rig != null:
		_rig.step(delta)
	_border_clock += delta
	if _border_clock >= _repo.bal("map3d_border_refresh_s"):
		_border_clock = 0.0
		refresh_borders()
	if _clouds != null:
		_clouds.step(delta)
	if _hover_pending:
		_hover_pending = false
		hover_pick(pick_at(_hover_pos), _hover_pos)
	if not _hovered:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if _input.key_pan(delta):
		_hover_pending = true  # the ground moved under a still pointer
```
- New: `func request_hover(pos: Vector2) -> void: _hover_pos = pos; _hover_pending = true`; `func refresh_hud() -> void: if _hud != null: _hud.refresh()`; `func compass_rect() -> Rect2: return _hud.compass_rect() if _hud != null else Rect2()`.
- Forwarders: `_pan_by(d)` → `_rig.pan_by(d)`; `_zoom_at(pos, d)` → `_rig.zoom_at(pos, d)`; `_metres_per_pixel()` / `metres_per_pixel()` → `_ctx.metres_per_pixel()`; `target()` → `_ctx.target if _ctx != null else Vector2.ZERO`; `distance()` → `_ctx.distance if _ctx != null else 1.0`; `yaw()` → `_ctx.yaw if _ctx != null else 0.0`; `look_at_pack(pack_px, at_distance)` → `_rig.place(_ctx.to_world(pack_px), at_distance if at_distance > 0.0 else _ctx.distance, _ctx.yaw)`; `look_at_home(d)` → `_rig.place(_home(), d, _ctx.yaw)`; `camera()` → `return _rig.camera() if _rig != null else null`. `_home()` uses `_ctx.bounds.get_center()`. `component` gains `"input": return _input` and `"rig": return _rig`. `CLICK_SLOP` on the view becomes `const CLICK_SLOP := Map3DInput.CLICK_SLOP`.
- [ ] **Step 4–5:** run the new file, then `-gdir=res://tests/map3d`, then `./run_tests.sh`, then the bench. Commit `refactor(map3d): the camera rig and the input are their own scripts` (the two new scripts, the view, the test).

---

### Task 11: The picker and the selection leave the view

**Files:**
- Create: `scripts/map3d/map3d_picker.gd`, `scripts/map3d/map3d_selection.gd`
- Modify: `scripts/map3d/map3d_view.gd` (delete `pick_at`'s body, `_province_at`, `_cell_at`, `_province_image`, `_cell_image`, the hover vars, `_draw_selection`, the `select_at` body, `_set_selected_province`, the `clear_selection` body, `_selected_*`; all public names become forwarders)
- Test: `tests/map3d/test_map3d_picker.gd`

**Interfaces:**
- Produces: `class_name Map3DPicker extends RefCounted` with `signal kingdom_changed(code: String)`: `bind(p_ctx: Map3DContext, p_view: Map3DView, p_tooltip: Label, p_borders: Map3DLayerBorders) -> void`, `pick_at(pos: Vector2) -> Dictionary`, `province_at(pack_px: Vector2) -> String`, `cell_at(pack_px: Vector2) -> int`, `static func kingdom_of_pick(repo: DataRepository, state: GameState, picked: Dictionary) -> String`, `request(pos: Vector2) -> void`, `step() -> void`, `hover_pick(picked: Dictionary, pos: Vector2) -> void`, `clear_hover() -> void`, `hovered_kingdom() -> String`, `hover_tooltip() -> String`, `tooltip_rect() -> Rect2`, `const TOOLTIP_OFFSET := Vector2(20.0, 24.0)`.
- `class_name Map3DSelection extends RefCounted` with `signal object_selected(entry: Dictionary)` and `signal province_selected(province_code: String)`: `bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_markers: Map3DLayerSettlements, p_view: Map3DView) -> void`, `select(picked: Dictionary) -> void`, `clear() -> void`, `forget_manor() -> void`, `redraw() -> void`, and fields `province: String`, `burg: String`, `manor: int`, `army: String`.

**Risk:** the pick ranking (army rect > army reach > badge > ON a dot > landmark rect > within a settlement's reach > landmark grown > manor or province), the hover's once-a-frame pick, and the signal re-emission (screens connect to the VIEW's signals). **Catch:** every click, hover and selection test in `test_map3d_view.gd`, `test_map3d_hover.gd`, `test_map3d_military.gd`, `test_map3d_heights.gd`, `test_map3d_manor_themes.gd`, and `test_map3d_tab.gd::test_a_3d_selection_opens_the_card_in_the_left_column`.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_picker.gd`:

```gdscript
extends GutTest
## Map3DPicker and Map3DSelection (spec 2026-09-20 §1): the pick and the hover
## are one script, the selection another; the view re-emits their signals
## under its own names, so the screens change nothing.

const FIXTURE := "user://test_map3d_picker_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func _capital() -> String:
	return String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])


func test_the_picker_picks_what_the_view_picks() -> void:
	var v := _view()
	var picker := v.component("picker") as Map3DPicker
	assert_not_null(picker)
	var at := v.size * 0.5
	assert_eq(picker.pick_at(at), v.pick_at(at))
	assert_eq(picker.pick_at(at), {"kind": "burg", "code": _capital()}, "the capital sits mid-view")
	var pick := {"kind": "burg", "code": _capital()}
	assert_eq(Map3DPicker.kingdom_of_pick(Game.data, Game.state, pick),
		Map3DView.kingdom_of_pick(Game.data, Game.state, pick))


func test_the_selection_speaks_through_the_views_signals() -> void:
	var v := _view()
	var sel := v.component("selection") as Map3DSelection
	assert_not_null(sel)
	watch_signals(v)
	var province := String(Game.data.burgs[_capital()]["province_code"])
	sel.select({"kind": "province", "code": province})
	assert_signal_emitted_with_parameters(v, "province_selected", [province])
	assert_eq(v.selected_province(), province)
	assert_not_null(v.line_mesh("Selection"))
	v.clear_selection()
	assert_signal_emitted_with_parameters(v, "object_selected", [{}])
	assert_null(v.line_mesh("Selection"))


func test_the_hover_signals_through_the_view() -> void:
	var v := _view()
	watch_signals(v)
	v.hover_pick({"kind": "burg", "code": _capital()}, v.size * 0.5)
	assert_signal_emitted(v, "country_hovered")
	assert_ne(v.hover_tooltip(), "")
	assert_eq(v.hovered_kingdom(), (v.component("picker") as Map3DPicker).hovered_kingdom())
```

- [ ] **Step 2: Run it (fails)** — the Task 10 command with `test_map3d_picker.gd`.

- [ ] **Step 3: Implement (moves).**
  - `Map3DPicker`: `pick_at` is lines 1928–1989 with `ground_at` → `ctx.ground_at`, the burg loop already on `ctx.projected_settlements()` (Task 2), `army_markers()` / `manor_badges()` / `landmark_marks()` → `view.army_markers()` / `view.manor_badges()` / `view.landmark_marks()` (forwarders; the HUD pieces arrive in Task 12), `_heat` → `view.heat_on()`, `_theme` → `view.manor_theme()`, `_cell_at` / `_province_at` → `cell_at` / `province_at` (bodies moved verbatim with `_repo` → `ctx.repo`), and `Map3DGeometry.world_to_pack(_meta, xz)` → `ctx.to_pack(xz)`. `kingdom_of_pick` moves verbatim as a static. The hover: `_hover_pos`, `_hover_pending`, `_hover_kingdom`, `_hover_obj` move in. `request(pos)` stores the position and sets pending. `step()` does `if _pending: _pending = false; hover_pick(pick_at(_pos), _pos)`. `hover_pick` is lines 2030–2045 with `_tooltip` → `tooltip`, `size` → `ctx.view_size`, `_draw_hover()` → `borders.draw_hover(kingdom)`, and `country_hovered.emit` → `kingdom_changed.emit`. `clear_hover`, `hovered_kingdom`, `hover_tooltip` and `tooltip_rect` move verbatim.
  - `Map3DSelection`: `select(picked)` is the `match` of `select_at` (lines 2104–2153). Rewrites: `_selected_*` → `province` / `burg` / `manor` / `army`; `_show_selected_ring(x)` → `markers.show_selected(x)` when `markers != null`; `_set_selected_province(x)` → a private `_set_province(x)` (lines 2156–2162, `_loaded` → `ctx != null`); `_draw_selection()` → `redraw()` (lines 1253–1273, with `_set_lines("Selection", …)` → `lines.set_lines("Selection", ls, Map3DLineStyle.solid(gold, "map3d_selection_width_px", Map3DPriority.SELECTION))` and `map3d_line_step_m` → `ctx.line_step()`); `if _hud != null: _hud.refresh()` → `view.refresh_hud()`; `_state()` → `ctx.state()`; `object_selected.emit` / `province_selected.emit` → the selection's own signals. `clear()` is `clear_selection`'s body. `forget_manor()` is `set_manor_theme`'s block (`if manor >= 0: manor = -1; if ctx != null: redraw()`).
  - View: `var _picker := Map3DPicker.new()`, `var _selection := Map3DSelection.new()`, both made at field initialisation (they must exist before load: `clear_hover` and `clear_selection` run pre-load). In `_ready`, after the tooltip exists: `_picker.tooltip = _tooltip`, `_picker.kingdom_changed.connect(func(code: String) -> void: country_hovered.emit(code))`, `_selection.object_selected.connect(func(e: Dictionary) -> void: object_selected.emit(e))`, `_selection.province_selected.connect(func(c: String) -> void: province_selected.emit(c))`. In `_load`, after the layers: `_picker.bind(_ctx, self, _tooltip, _borders)` and `_selection.bind(_ctx, _lines, _markers, self)`. Forwarders: `pick_at(pos)` → `_picker.pick_at(pos) if _loaded else {}`; `static kingdom_of_pick(r, s, p)` → `Map3DPicker.kingdom_of_pick(r, s, p)`; `hover_pick`, `clear_hover`, `hovered_kingdom`, `hover_tooltip`, `tooltip_rect` → `_picker.*`; `request_hover(pos)` → `_picker.request(pos)`; `_process`'s hover lines → `_picker.step()`; `select_at(pos)` → `_selection.select(pick_at(pos))`; `clear_selection()` → `_selection.clear()`; `_draw_selection()` → `_selection.redraw()`; `selected_province/burg/manor/army()` → `_selection.province` / `.burg` / `.manor` / `.army`; `set_manor_theme`'s forgetting block → `if theme_name != "manors": _selection.forget_manor()`; `set_military(false)` with a selected army → `_selection.clear()`; `_draw_hover()` is deleted (the picker calls the borders). `TOOLTIP_OFFSET` on the view becomes an alias of `Map3DPicker.TOOLTIP_OFFSET`. `component` gains `"picker"` and `"selection"`.
- [ ] **Step 4–5:** run the new file, the folder, `./run_tests.sh`, the bench (`--layer military` and `--layer heights`), then commit `refactor(map3d): the picker and the selection are their own scripts`.

---

### Task 12: The HUD pieces, with no `Game` in the HUD

**Files:**
- Create: `scripts/map3d/map3d_hud_piece.gd`, `map3d_hud_labels.gd`, `map3d_hud_badges.gd`, `map3d_hud_armies.gd`, `map3d_hud_landmarks.gd`, `map3d_hud_heat_legend.gd`, `map3d_hud_scale_bar.gd`, `map3d_hud_ruler.gd`, `map3d_hud_backdrop.gd`, `map3d_hud_needle.gd` (all in `scripts/map3d/`)
- Modify: `scripts/map3d/map3d_hud.gd` (children, `bind`, no `Game`), `scripts/map3d/map3d_view.gd` (delete every `draw_*`, `label_entries`, `manor_badges`, `army_badge_height`, `army_markers`, `landmark_marks`, `_cut_landmark_marks`, `heat_legend_*`, `_heat_legend_area`, `_drawn_*`, `_landmark_*`; forwarders stay)
- Test: `tests/map3d/test_map3d_hud.gd` (append), `tests/map3d/test_map3d_shape.gd` (new: the size guard)

**Interfaces:**
- Produces: `class_name Map3DHudPiece extends Control` with `var ctx: Map3DContext`, `var view: Map3DView`, `bind(p_ctx: Map3DContext, p_view: Map3DView) -> void`. Subclasses:
  - `Map3DHudLabels`: `entries() -> Array`, `drawn() -> PackedStringArray`
  - `Map3DHudBadges`: `badges() -> Array`, `drawn_count() -> int`
  - `Map3DHudArmies`: `badge_height() -> float`, `markers() -> Array`, `drawn_count() -> int`
  - `Map3DHudLandmarks`: `marks() -> Array`
  - `Map3DHudHeatLegend`: `rect() -> Rect2`, `ticks() -> Array`, `yields() -> bool`
  - `Map3DHudScaleBar`, `Map3DHudRuler`, `Map3DHudBackdrop`: drawing only
  - `class_name Map3DHudNeedle extends Node2D` with `var hud: Map3DHud` (was the inner `NeedleLayer`).
- `Map3DHud`: `bind(p_ctx: Map3DContext, p_view: Map3DView) -> void`, `refresh() -> void`, `compass_rect() -> Rect2`, `piece(name: String) -> Map3DHudPiece`, `static func halo(repo: DataRepository) -> Color`, statics `scale_bar_for` and `needle_angle` unchanged.

**Risk:** the paint order (Ruling 17), the landmark cut's per-pose cache key (`[camera transform, size, scale, military, tick, day]`, a perf fix of 2026-09-19), and a piece drawing before it is bound. **Catch:** `test_map3d_labels.gd`, `test_map3d_military.gd::test_the_hud_draws_the_counters`, `test_map3d_heights.gd` (marks, legend, yields to the ruler), `test_map3d_hud.gd`, the new source-scan test, and the bench's `--layer heights` row.

- [ ] **Step 1: Failing tests.** Append to `tests/map3d/test_map3d_hud.gd`:

```gdscript
const HUD_FIXTURE := "user://test_map3d_hud_world.tscn"
const HUD_WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func _hud_view() -> Map3DView:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.set_meta("map3d_world", HUD_WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, HUD_FIXTURE)
	root.free()
	var v := Map3DView.create(Game.data, HUD_FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_hud_is_one_child_per_job_in_paint_order() -> void:
	var v := _hud_view()
	var names: Array = []
	for c: Node in v.get_node("Hud").get_children():
		names.append(String(c.name))
	assert_eq(names, ["Labels", "Landmarks", "HeatLegend", "Badges", "Armies", "Backdrop",
		"ScaleBar", "Ruler", "Compass", "Needle"])
	assert_true(v.get_node("Hud/Labels") is Map3DHudLabels)
	assert_true(v.get_node("Hud/Needle") is Map3DHudNeedle)


func test_the_views_seams_read_the_pieces() -> void:
	var v := _hud_view()
	var hud := v.get_node("Hud") as Map3DHud
	assert_eq(v.label_entries(), (hud.piece("Labels") as Map3DHudLabels).entries())
	assert_eq(v.army_markers(), (hud.piece("Armies") as Map3DHudArmies).markers())
	assert_eq(v.heat_legend_rect(), (hud.piece("HeatLegend") as Map3DHudHeatLegend).rect())


func test_no_hud_script_reads_the_game_autoload() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if f.begins_with("map3d_hud") and f.ends_with(".gd"):
			var text := FileAccess.get_file_as_string("res://scripts/map3d/" + f)
			assert_false(text.contains("Game."), f + " takes the context, not Game")
```

  Create `tests/map3d/test_map3d_shape.gd`:

```gdscript
extends GutTest
## The shape the owner asked for (spec 2026-09-20 §1): no script of the 3D
## map over ~250 lines apart from the pure helpers that were already there,
## and the view a coordinator.

const OLD_HELPERS := ["map3d_rivers.gd", "map3d_bridges.gd", "map3d_borders.gd"]


func _lines(path: String) -> int:
	return FileAccess.get_file_as_string(path).split("\n").size()


func test_the_view_is_a_coordinator() -> void:
	assert_lte(_lines("res://scripts/map3d/map3d_view.gd"), 450)


func test_every_other_script_is_small() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if not f.ends_with(".gd") or f == "map3d_view.gd" or f in OLD_HELPERS:
			continue
		assert_lte(_lines("res://scripts/map3d/" + f), 300, f)
```

  (`test_the_view_is_a_coordinator` can fail until Task 13 removes the node-building code from `_ready`/`_load`. Mark it `pending("until Task 13")` with an early `return` in this task; Task 13 removes the `pending`.)

- [ ] **Step 2: Run them (fail)** — `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_hud.gd -gexit` (script ignored: the piece classes do not exist).

- [ ] **Step 3: Implement.** `scripts/map3d/map3d_hud_piece.gd`:

```gdscript
class_name Map3DHudPiece
extends Control
## One job of the 3D map's HUD (spec 2026-09-20 §1): a full-rect,
## mouse-transparent layer drawn from the context the view hands down —
## never from the Game autoload. It draws nothing until bound.

var ctx: Map3DContext
var view: Map3DView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func bind(p_ctx: Map3DContext, p_view: Map3DView) -> void:
	ctx = p_ctx
	view = p_view
	queue_redraw()


func bound() -> bool:
	return ctx != null and ctx.camera != null
```

  Moves (each `_draw()` starts with `if not bound(): return`; `_repo` → `ctx.repo`, `_render_scale()` → `ctx.viewport_px_scale()`, `_camera` → `ctx.camera`, `size` → `ctx.view_size`, `_height_at` → `ctx.height_at`, `_state()` → `ctx.state()`, `_distance` → `ctx.distance`, `_metres_per_pixel()` → `ctx.metres_per_pixel()`, `_meta` → `ctx.meta`):
  - `Map3DHudLabels`: `label_entries` → `entries()`; `draw_labels` → `_draw()` (the `ci.` calls become `self` calls), filling `_drawn`; `drawn()`.
  - `Map3DHudBadges`: `manor_badges` → `badges()` (`_theme` → `view.manor_theme()`; ground via `ctx.cell_ground`); `draw_badges` → `_draw()`; `drawn_count()`.
  - `Map3DHudArmies`: `army_badge_height` → `badge_height()`; `army_markers` → `markers()` (`_military` → `view.military()`; the settlement squares are `ctx.settlement_rects()`); `draw_armies` → `_draw()` with `view.selected_army()`; `drawn_count()`.
  - `Map3DHudLandmarks`: `landmark_marks` → `marks()` (cache key unchanged: `_military` → `view.military()`, `_heat` → `view.heat_on()`; `army_markers()` → `(get_parent() as Map3DHud).piece("Armies").markers()`; `heat_legend_rect()` → `…piece("HeatLegend").rect()`); `_cut_landmark_marks` → `_cut()`; `draw_landmarks` → `_draw()`.
  - `Map3DHudHeatLegend`: `heat_legend_rect` → `rect()`, `heat_legend_ticks` → `ticks()`, `_heat_legend_area` → `_area()`, `heat_legend_yields` → `yields()` (`ruler_on` / `_ruler` → `view.ruler_on` / `view.ruler()`), `draw_heat_legend` → `_draw()`.
  - `Map3DHudScaleBar._draw()`: `ScaleBar.draw(self, Map3DHud.scale_bar_for(ctx.metres_per_pixel() * view.map_units_per_metre(), ctx.repo.bal("map_scale_bar_max_px"), view.map_unit()), size, Map3DHud.halo(ctx.repo))`.
  - `Map3DHudRuler._draw()`: the body of `draw_ruler` with `ci` → `self`.
  - `Map3DHudBackdrop._draw()`: the body of `_draw_compass_backdrop`, reading `(get_parent() as Map3DHud).compass_rect()` and `ctx.repo.bal("map3d_compass_backdrop_alpha")`.
  - `Map3DHudNeedle` (Node2D): the old `NeedleLayer` plus `_draw_needle`, `_draw_north_label`, `_offset_poly` moved from `Map3DHud`; `Game.data` → `hud.ctx.repo`; `view.yaw()` → `hud.ctx.yaw`.
  - `Map3DHud`: `_ready()` makes the children in Ruling 17's order if they are missing (Task 13 authors them), sets `_compass.box = compass_rect` and calls `_compass.setup()`. `bind(p_ctx, p_view)` stores `ctx` and `view`, binds every `Map3DHudPiece` child, sets the needle's `hud`, and connects `ctx.camera_moved.connect(refresh)`. `refresh()` does `queue_redraw()` on every child. `compass_rect()` reads `ctx.repo` (`Rect2()` while `ctx == null`). `static func halo(repo)` replaces `_hud_halo` and reads the repo passed in. `piece(name)` returns `get_node_or_null(name) as Map3DHudPiece`. `Map3DHud._draw()` is deleted.
  - View: in `_load`, `_hud = Map3DHud.new(); _hud.name = "Hud"; add_child(_hud); _hud.bind(_ctx, self)`. Delete `_hud.view = self` and the `camera_moved → refresh_hud` connection from Task 10 (the HUD connects itself). Forwarders, each returning its empty value while `_hud == null`: `label_entries()` → `_hud.piece("Labels").entries()`, `drawn_labels()`, `manor_badges()`, `drawn_badge_count()`, `army_badge_height()`, `army_markers()`, `drawn_army_count()`, `landmark_marks()`, `heat_legend_rect()`, `heat_legend_ticks()`, `heat_legend_yields()`. Every `draw_*` method is deleted (Ruling 1). The picker keeps calling the view's forwarders.
- [ ] **Step 4: Run** the HUD file, the shape file (the view test pending), `-gdir=res://tests/map3d`, `./run_tests.sh`.
- [ ] **Step 5: Bench** with `--layer heights`, `--layer manors`, `--layer military`: each within 8 ms and no row slower than baseline by more than 0.5 ms median.
- [ ] **Step 6: Commit** `refactor(map3d): the HUD is one piece per job and never reads Game` (all new `map3d_hud_*.gd`, `map3d_hud.gd`, the view, both tests).

---
### Task 13: The authored scene, built through the gdai MCP

**Files:**
- Create: `scenes/map3d/world_map_3d.tscn`, `scenes/map3d/tooltip_chip.tres`
- Modify: `scripts/map3d/map3d_view.gd` (`create` instances the scene; `_ready` binds the authored nodes; `_load` stops making nodes; the "is it loaded" guards read `_loaded`), `scripts/map3d/map3d_layer_roads.gd` (`_build_bridges` fills an existing `Bridges` node), `scripts/map3d/map3d_layer_clouds.gd` (`build` fills an existing `Shadows` child), `tests/map3d/test_map3d_shape.gd` (lift the `pending`)
- Test: `tests/map3d/test_map3d_scene.gd`

**Interfaces:**
- Produces: `const VIEW_SCENE := "res://scenes/map3d/world_map_3d.tscn"` on `Map3DView`; `create(repo, scene_path)` returns `load(VIEW_SCENE).instantiate()`. Node tree (the spec's §1, with the HUD children in Ruling 17's order):

```
Map3DView (Control, map3d_view.gd)
├─ Viewport (SubViewport)
│  ├─ WorldSlot (Node3D)
│  ├─ CameraRig (Node3D, map3d_camera_rig.gd) └ RigCamera (Camera3D)
│  ├─ Sea (MeshInstance3D, map3d_layer_sea.gd)
│  ├─ Rivers (MeshInstance3D, map3d_layer_rivers.gd)
│  ├─ Bridges (MeshInstance3D)
│  ├─ Lines (Node3D, map3d_layer_lines.gd)
│  ├─ Clouds (MultiMeshInstance3D, map3d_layer_clouds.gd) └ Shadows (MultiMeshInstance3D)
│  └─ Markers (Node3D, map3d_layer_settlements.gd)
├─ Display (TextureRect)
├─ Notice (Label)
├─ Hud (Control, map3d_hud.gd) └ Labels, Landmarks, HeatLegend, Badges, Armies, Backdrop,
│                                 ScaleBar, Ruler (Control, their map3d_hud_*.gd),
│                                 Compass (Node2D, scripts/ui/compass_layer.gd),
│                                 Needle (Node2D, map3d_hud_needle.gd)
└─ Tooltip (Label)
```

**Risk:** the editor holding a stale scene; a node generated at runtime being saved into the `.tscn`; `Hud` existing before load (an unbuilt map must still show only its notice); guards like `_hud != null` that meant "loaded". **Catch:** the new scene test (tree, flags, nothing generated saved), `test_an_unbuilt_map_says_how_to_build_it`, `test_nothing_loads_until_the_view_is_first_shown`, `test_map3d_api.gd`, `test_map3d_tab.gd`.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_scene.gd`:

```gdscript
extends GutTest
## The 3D map is an AUTHORED scene (spec 2026-09-20 §2, owner: "clicking a
## node in the editor shows the real picture"): the tree, flags and anchors
## live in scenes/map3d/world_map_3d.tscn; nothing generated at runtime is
## ever saved into it.

const FIXTURE := "user://test_map3d_scene_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
const TREE := ["Viewport", "Viewport/WorldSlot", "Viewport/CameraRig",
	"Viewport/CameraRig/RigCamera", "Viewport/Sea", "Viewport/Rivers", "Viewport/Bridges",
	"Viewport/Lines", "Viewport/Clouds", "Viewport/Clouds/Shadows", "Viewport/Markers",
	"Display", "Notice", "Hud", "Hud/Labels", "Hud/Landmarks", "Hud/HeatLegend", "Hud/Badges",
	"Hud/Armies", "Hud/Backdrop", "Hud/ScaleBar", "Hud/Ruler", "Hud/Compass", "Hud/Needle",
	"Tooltip"]


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func test_create_instances_the_authored_scene() -> void:
	var v := Map3DView.create(Game.data, FIXTURE)
	add_child_autofree(v)
	assert_eq(v.scene_file_path, Map3DView.VIEW_SCENE)
	for path: String in TREE:
		assert_not_null(v.get_node_or_null(path), path)
	var vp := v.get_node("Viewport") as SubViewport
	assert_true(vp.own_world_3d)
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	var display := v.get_node("Display") as TextureRect
	assert_eq(display.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(display.expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
	assert_eq((v.get_node("Viewport/Clouds/Shadows") as GeometryInstance3D).cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(v.get_child(v.get_child_count() - 1).name, &"Tooltip", "the name over everything")


func test_the_hud_waits_for_a_world() -> void:
	var v := Map3DView.create(Game.data, "res://no/such/world.tscn")
	add_child_autofree(v)
	v.activate()
	assert_false((v.get_node("Hud") as Control).visible, "an unbuilt map shows only its notice")
	assert_true(v.notice().visible)


func test_nothing_generated_is_saved_in_the_scene() -> void:
	var text := FileAccess.get_file_as_string(Map3DView.VIEW_SCENE)
	for word: String in ["ArrayMesh", "type=\"MultiMesh\"", "ImageTexture", "preview = true"]:
		assert_false(text.contains(word), "the scene holds no generated " + word)


func test_the_tooltip_chip_is_the_themes_own() -> void:
	var saved := load("res://scenes/map3d/tooltip_chip.tres") as StyleBoxFlat
	var live := UiPalette.chip_style()
	assert_eq(saved.bg_color, live.bg_color)
	assert_eq(saved.border_color, live.border_color)
	assert_eq(saved.corner_radius_top_left, live.corner_radius_top_left)
	assert_eq(saved.content_margin_left, live.content_margin_left)
	assert_eq(saved.content_margin_top, live.content_margin_top)
```

- [ ] **Step 2: Run it (fails)** — `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_scene.gd -gexit`. Expected: failures (`VIEW_SCENE` not declared, so the script is ignored).

- [ ] **Step 3: Author the scene through the gdai MCP.** Load the tools: `ToolSearch` query `"gdai"`, max_results 30. Read each tool's schema and map the arguments below onto its field names.
  1. `get_project_info` — expected: the project name. On an error or a timeout, the editor is not reachable: go to Step 3b (fallback).
  2. `execute_editor_script` with `ResourceSaver.save(UiPalette.chip_style(), "res://scenes/map3d/tooltip_chip.tres")`, which saves the chip `.tres` (Ruling 10).
  3. `create_scene` — path `res://scenes/map3d/world_map_3d.tscn`, root type `Control`, root name `Map3DView`. Then `open_scene` on the same path.
  4. `attach_script` — node `.`, script `res://scripts/map3d/map3d_view.gd`.
  5. `add_node` for each row (parent, type, name), then `attach_script` where a script is named:
     `.` SubViewport `Viewport` · `Viewport` Node3D `WorldSlot` · `Viewport` Node3D `CameraRig` (`map3d_camera_rig.gd`) · `Viewport/CameraRig` Camera3D `RigCamera` · `Viewport` MeshInstance3D `Sea` (`map3d_layer_sea.gd`) · `Viewport` MeshInstance3D `Rivers` (`map3d_layer_rivers.gd`) · `Viewport` MeshInstance3D `Bridges` · `Viewport` Node3D `Lines` (`map3d_layer_lines.gd`) · `Viewport` MultiMeshInstance3D `Clouds` (`map3d_layer_clouds.gd`) · `Viewport/Clouds` MultiMeshInstance3D `Shadows` · `Viewport` Node3D `Markers` (`map3d_layer_settlements.gd`) · `.` TextureRect `Display` · `.` Label `Notice` · `.` Control `Hud` (`map3d_hud.gd`) · `Hud` Control `Labels` (`map3d_hud_labels.gd`) · `Hud` Control `Landmarks` (`map3d_hud_landmarks.gd`) · `Hud` Control `HeatLegend` (`map3d_hud_heat_legend.gd`) · `Hud` Control `Badges` (`map3d_hud_badges.gd`) · `Hud` Control `Armies` (`map3d_hud_armies.gd`) · `Hud` Control `Backdrop` (`map3d_hud_backdrop.gd`) · `Hud` Control `ScaleBar` (`map3d_hud_scale_bar.gd`) · `Hud` Control `Ruler` (`map3d_hud_ruler.gd`) · `Hud` Node2D `Compass` (`res://scripts/ui/compass_layer.gd`) · `Hud` Node2D `Needle` (`map3d_hud_needle.gd`) · `.` Label `Tooltip`.
  6. `update_property` / `set_anchor_preset`:
     - `.`: anchor preset 15 (full rect), `clip_contents` true, `focus_mode` 1 (CLICK), `mouse_filter` 0 (STOP).
     - `Viewport`: `own_world_3d` true, `render_target_update_mode` 0 (DISABLED), `size` (800, 450) (refit at runtime).
     - `RigCamera`: `fov` 45, `near` 50, `far` 400000 (editor defaults only; the rig binds the `balance.csv` values).
     - `Sea`, `Rivers`, `Bridges`: `cast_shadow` 0 on Sea and Rivers (Bridges keep the default 1, they cast), `extra_cull_margin` 16384 on Rivers.
     - `Clouds`: `cast_shadow` 0, `extra_cull_margin` 16384. `Shadows`: `cast_shadow` 3 (SHADOWS_ONLY), `extra_cull_margin` 16384.
     - `Display`: preset 15, `expand_mode` 1 (IGNORE_SIZE), `stretch_mode` 0 (SCALE), `mouse_filter` 2 (IGNORE). If the MCP can add resources: `add_resource` of type `ViewportTexture` on `Display.texture` with `viewport_path` = `Viewport` and `resource_local_to_scene` = true, so the editor's Display shows the render. Otherwise skip it: `_ready` binds `_viewport.get_texture()` either way.
     - `Notice`: preset 15, `visible` false, `horizontal_alignment` 1, `vertical_alignment` 1, `autowrap_mode` 3 (WORD_SMART), `text` = `Map3DView.NOTICE_TEXT`.
     - `Hud`: preset 15, `mouse_filter` 2, `visible` false. Every Control child: preset 15, `mouse_filter` 2.
     - `Tooltip`: `mouse_filter` 2, `visible` false, `theme_override_font_sizes/font_size` 16, `theme_override_colors/font_color` = the value of `UiPalette.TEXT_SOFT` (read it with `execute_editor_script` `print(UiPalette.TEXT_SOFT)`), `theme_override_styles/normal` = `res://scenes/map3d/tooltip_chip.tres`.
  7. `get_scene_file_content` of the scene — check each node and property above is in the text. If the file on disk did not change, run `execute_editor_script` with `EditorInterface.save_scene()` and read it again. Then `get_godot_errors` (expected: none new) and `get_editor_screenshot` (look: the tree in the Scene dock).

- [ ] **Step 3b: Fallback (the editor or the MCP unreachable)** — write `scenes/map3d/world_map_3d.tscn` by hand, and write `tooltip_chip.tres` by a headless script: `GDAI_MCP_SERVER_PORT=3999 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s <scratchpad>/save_chip.gd`, where the script's `_init` saves `UiPalette.chip_style()` and quits. The scene text (`<TEXT_SOFT>` is `UiPalette.TEXT_SOFT` written as `Color(r, g, b, a)`):

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/map3d/map3d_view.gd" id="1_view"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_camera_rig.gd" id="2_rig"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_layer_sea.gd" id="3_sea"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_layer_rivers.gd" id="4_rivers"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_layer_lines.gd" id="5_lines"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_layer_clouds.gd" id="6_clouds"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_layer_settlements.gd" id="7_markers"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud.gd" id="8_hud"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_labels.gd" id="9_labels"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_landmarks.gd" id="10_landmarks"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_heat_legend.gd" id="11_legend"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_badges.gd" id="12_badges"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_armies.gd" id="13_armies"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_backdrop.gd" id="14_backdrop"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_scale_bar.gd" id="15_scale"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_ruler.gd" id="16_ruler"]
[ext_resource type="Script" path="res://scripts/ui/compass_layer.gd" id="17_compass"]
[ext_resource type="Script" path="res://scripts/map3d/map3d_hud_needle.gd" id="18_needle"]
[ext_resource type="StyleBox" path="res://scenes/map3d/tooltip_chip.tres" id="19_chip"]

[node name="Map3DView" type="Control"]
clip_contents = true
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
focus_mode = 1
script = ExtResource("1_view")

[node name="Viewport" type="SubViewport" parent="."]
own_world_3d = true
size = Vector2i(800, 450)
render_target_update_mode = 0

[node name="WorldSlot" type="Node3D" parent="Viewport"]

[node name="CameraRig" type="Node3D" parent="Viewport"]
script = ExtResource("2_rig")

[node name="RigCamera" type="Camera3D" parent="Viewport/CameraRig"]
fov = 45.0
near = 50.0
far = 400000.0

[node name="Sea" type="MeshInstance3D" parent="Viewport"]
cast_shadow = 0
script = ExtResource("3_sea")

[node name="Rivers" type="MeshInstance3D" parent="Viewport"]
cast_shadow = 0
extra_cull_margin = 16384.0
script = ExtResource("4_rivers")

[node name="Bridges" type="MeshInstance3D" parent="Viewport"]

[node name="Lines" type="Node3D" parent="Viewport"]
script = ExtResource("5_lines")

[node name="Clouds" type="MultiMeshInstance3D" parent="Viewport"]
cast_shadow = 0
extra_cull_margin = 16384.0
script = ExtResource("6_clouds")

[node name="Shadows" type="MultiMeshInstance3D" parent="Viewport/Clouds"]
cast_shadow = 3
extra_cull_margin = 16384.0

[node name="Markers" type="Node3D" parent="Viewport"]
script = ExtResource("7_markers")

[node name="Display" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
expand_mode = 1
stretch_mode = 0

[node name="Notice" type="Label" parent="."]
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
text = "The 3D map has not been built for this map.
Run tools/map3d (see tools/map3d/README.md)."
horizontal_alignment = 1
vertical_alignment = 1
autowrap_mode = 3

[node name="Hud" type="Control" parent="."]
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("8_hud")

[node name="Labels" type="Control" parent="Hud"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("9_labels")
```
  Repeat the `Labels` block for `Landmarks` (10), `HeatLegend` (11), `Badges` (12), `Armies` (13), `Backdrop` (14), `ScaleBar` (15) and `Ruler` (16), each with its own name and script id, in that order. Then:

```
[node name="Compass" type="Node2D" parent="Hud"]
script = ExtResource("17_compass")

[node name="Needle" type="Node2D" parent="Hud"]
script = ExtResource("18_needle")

[node name="Tooltip" type="Label" parent="."]
visible = false
mouse_filter = 2
theme_override_colors/font_color = <TEXT_SOFT>
theme_override_font_sizes/font_size = 16
theme_override_styles/normal = ExtResource("19_chip")
```
  Then run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` so the scene gets its uid.

- [ ] **Step 4: Bind the scene in the view.** Replace the node-making code:
  - `create()`: `var v := (load(VIEW_SCENE) as PackedScene).instantiate() as Map3DView`, then set the name, `_repo` and `_scene_path` as before.
  - Replace the `var _viewport`, `_display`, `_notice`, `_tooltip`, `_hud`, `_rig`, `_sea`, `_rivers`, `_lines`, `_clouds`, `_markers` declarations with `@onready var _viewport: SubViewport = $Viewport`, `@onready var _world_slot: Node3D = $Viewport/WorldSlot`, `@onready var _rig: Map3DCameraRig = $Viewport/CameraRig`, `@onready var _sea: Map3DLayerSea = $Viewport/Sea`, `@onready var _rivers: Map3DLayerRivers = $Viewport/Rivers`, `@onready var _lines: Map3DLayerLines = $Viewport/Lines`, `@onready var _clouds: Map3DLayerClouds = $Viewport/Clouds`, `@onready var _markers: Map3DLayerSettlements = $Viewport/Markers`, `@onready var _display: TextureRect = $Display`, `@onready var _notice: Label = $Notice`, `@onready var _hud: Map3DHud = $Hud`, `@onready var _tooltip: Label = $Tooltip`.
  - `_ready()` keeps only: `_display.texture = _viewport.get_texture()`; the tooltip's `UiPalette` overrides (the same three calls as today, Ruling 10); the picker and selection wiring from Task 11; `mouse_entered` / `mouse_exited`; `resized.connect(_fit_viewport)`; `_fit_viewport()`; `set_process(false)`.
  - `_load()`: `_world_slot.add_child(_world)` in place of `_viewport.add_child(_world)`. Delete every `X.new()` / `.name =` / `add_child` of a layer, rig or HUD; bind the authored ones in the same order as before. After binding, `_hud.visible = true`.
  - `Map3DLayerRoads._build_bridges`: `var mi := viewport.get_node_or_null("Bridges") as MeshInstance3D`. When it exists, set `mi.mesh` (null when there are no bridges) instead of freeing and remaking it. Keep the make-a-node path for a bare viewport.
  - `Map3DLayerClouds.build`: use `get_node_or_null("Shadows")` when present, and make it only when absent.
  - Guards: every `if _hud != null`, `_markers != null`, `_rivers != null`, `_clouds != null`, `_rig != null` that meant "the world is loaded" becomes `if _loaded` (grep `!= null` in the view and decide each by that rule). `layer_names()` lists `Markers`, `Lines`, `Clouds` and `Hud` only while `_loaded`, and `Shadows` while the build's Sun exists (Task 14 moves the Sun into the scene). `Rivers` needs a mesh; `Sea` needs `has_water()`.
  - `tests/map3d/test_map3d_shape.gd`: remove the `pending` / `return` from `test_the_view_is_a_coordinator`.
- [ ] **Step 5: Run** — the scene test (4 passed), the shape test (2 passed; the view ≤ 450 lines), `-gdir=res://tests/map3d`, `./run_tests.sh`, and the bench (3024×1964; WORST ≤ 8 ms).
- [ ] **Step 6: Look** — with the editor open: `open_scene` `res://scenes/map3d/world_map_3d.tscn`, then `get_editor_screenshot`. Expected: the full tree in the Scene dock, the Tooltip chip in the dark theme.
- [ ] **Step 7: Commit** — `git add scenes/map3d/world_map_3d.tscn scenes/map3d/world_map_3d.tscn.uid scenes/map3d/tooltip_chip.tres scripts/map3d/map3d_view.gd scripts/map3d/map3d_layer_roads.gd scripts/map3d/map3d_layer_clouds.gd tests/map3d/test_map3d_scene.gd tests/map3d/test_map3d_shape.gd` (add a `.uid` only if the import made one), then commit `feat(map3d): the 3D map is an authored scene (gdai MCP); create() instances it`.

---

### Task 14: Sun, sky and sea are the scene's; the build emits data only

**Files:**
- Create: `scripts/map3d/map3d_world_loader.gd`, `scenes/map3d/world_environment.tres`
- Modify: `scenes/map3d/world_map_3d.tscn` (add `Viewport/Environment` and `Viewport/Sun`), `scripts/map3d/map3d_environment.gd` (`apply_environment`, `apply_sun`, `make_sun`, `make_environment`), `scripts/map3d/map3d_layer_sea.gd` (makes its own plane), `scripts/map3d/map3d_view.gd` (`_load` uses the loader; `layer_names` / `set_layer_visible("Shadows")` use the authored Sun), `tools/map3d/build_terrain.gd` (drop Sea, Sun, Environment and the cameras), `tools/map3d/shoot.gd` (brings its own sun, sky and framing cameras), `data/balance.csv`, `data/terrain_palette.csv`, `tests/map3d/test_map3d_layers.gd`
- Test: `tests/map3d/test_map3d_scene.gd` (append)

**Interfaces:**
- Produces: `class_name Map3DWorldLoader extends RefCounted` with `const FORMAT_VERSION := 2`, `const OLD_BUILD_NODES := ["Sun", "Environment", "Sea", "Camera3D", "CameraMid", "CameraNear"]`, `static func instance(scene_path: String) -> Node3D` (null when missing or bad), `static func strip_old_build(world: Node3D) -> void`, `static func own_terrain_material(world: Node3D) -> void`.
- `Map3DEnvironment`: `const ENVIRONMENT := "res://scenes/map3d/world_environment.tres"`, `static func apply_environment(repo: DataRepository, env: Environment) -> void`, `static func apply_sun(repo: DataRepository, sun: DirectionalLight3D) -> void`, `static func make_sun(repo: DataRepository) -> DirectionalLight3D`, `static func make_environment(repo: DataRepository) -> WorldEnvironment`.
- `Map3DLayerSea.build(ctx)` makes a `PlaneMesh` of `pack_px × m_per_px × map3d_sea_plane_span` at `sea_y`.
- New CSV rows: `balance.csv` `map3d_sun_pitch_deg` −35, `map3d_sun_yaw_deg` 45, `map3d_sun_energy` 1.1, `map3d_sun_shadow_max_m` 60000, `map3d_ambient_energy` 0.35, `map3d_ambient_sky_share` 0.6, `map3d_fog_density` 0.0000008, `map3d_sky_sun_angle_max` 1.0, `map3d_sea_plane_span` 12. `terrain_palette.csv` `map3d_sky_top` `#2F5878`, `map3d_sky_ground` `#2E4A5C` (the horizon and fog reuse `map3d_sky` `#A9BFCC`, which is build_terrain's horizon hex).

**Risk:** two WorldEnvironments or two suns in one world when an old build still carries its own; a fresh clone's look changing. **Catch:** the new test (exactly one sun and one environment under the Viewport; the old build's nodes gone; the sea plane present), `test_the_suns_shadow_look_is_data`, and the sea tests. Every value is the one `build_terrain.gd` wrote before, so the picture must match. Do a visual check with `tools/snapshot_screen.gd` before and after (the visual-review skill).

- [ ] **Step 1: Failing test** — append to `tests/map3d/test_map3d_scene.gd`:

```gdscript
const OLD_BUILD := "user://test_map3d_old_build.tscn"


func _old_build() -> void:
	var root := Node3D.new()
	root.name = "OldBuild"
	root.set_meta("map3d_world", WORLD)
	for n: Node in [DirectionalLight3D.new(), WorldEnvironment.new(), MeshInstance3D.new(),
			Camera3D.new()]:
		n.name = {"DirectionalLight3D": "Sun", "WorldEnvironment": "Environment",
			"MeshInstance3D": "Sea", "Camera3D": "Camera3D"}[n.get_class()]
		root.add_child(n)
		n.owner = root
	(root.get_node("Sea") as MeshInstance3D).mesh = PlaneMesh.new()
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, OLD_BUILD)
	root.free()


func test_an_old_builds_sun_sky_sea_and_cameras_step_aside() -> void:
	_old_build()
	var v := Map3DView.create(Game.data, OLD_BUILD)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	var vp := v.viewport()
	assert_eq(vp.find_children("*", "DirectionalLight3D", true, false).size(), 1, "one sun")
	assert_eq(vp.find_children("*", "WorldEnvironment", true, false).size(), 1, "one sky")
	assert_eq(vp.find_children("*", "Camera3D", true, false).size(), 1, "the rig's camera only")
	var world := vp.get_node("WorldSlot").get_child(0)
	for n: String in Map3DWorldLoader.OLD_BUILD_NODES:
		assert_null(world.get_node_or_null(n), n + " of the old build is gone")
	assert_true("Sea" in v.layer_names())
	assert_true("Shadows" in v.layer_names())


func test_the_sky_and_sun_are_data() -> void:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	var env := (v.get_node("Viewport/Environment") as WorldEnvironment).environment
	assert_almost_eq(env.ambient_light_energy, Game.data.bal("map3d_ambient_energy"), 0.0001)
	assert_almost_eq(env.fog_density, Game.data.bal("map3d_fog_density"), 1e-9)
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_FILMIC)
	var sun := v.get_node("Viewport/Sun") as DirectionalLight3D
	assert_almost_eq(sun.light_energy, Game.data.bal("map3d_sun_energy"), 0.0001)
	assert_almost_eq(sun.rotation_degrees.x, Game.data.bal("map3d_sun_pitch_deg"), 0.01)
	var sea := v.get_node("Viewport/Sea") as MeshInstance3D
	assert_not_null(sea.mesh, "the sea plane is the scene's own")
	assert_almost_eq(sea.global_position.y, 5.0, 0.001)
```

- [ ] **Step 2: Run it (fails)** — the Task 13 command.
- [ ] **Step 3: Add the CSV rows** (Interfaces), each with a note quoting where the value came from (`tools/map3d/build_terrain.gd build_scene`, 2026-09-18).
- [ ] **Step 4: The environment resource.** With the MCP: `execute_editor_script` builds the Environment exactly as `build_terrain.gd` lines 232–251 do (ProceduralSkyMaterial with the four colours and `sun_angle_max`, `BG_SKY`, ambient from the sky at 0.35 / 0.6, `TONE_MAPPER_FILMIC`, fog on, fog light `#A9BFCC`, density 8e-7) and saves it with `ResourceSaver.save(e, "res://scenes/map3d/world_environment.tres")`. Then `open_scene` the view scene and `add_node` `Viewport` WorldEnvironment `Environment` with `update_property` `environment` = that `.tres`, and `add_node` `Viewport` DirectionalLight3D `Sun` with `rotation_degrees` (−35, 45, 0), `light_energy` 1.1, `shadow_enabled` true, `directional_shadow_max_distance` 60000. Check with `get_scene_file_content` and `get_godot_errors`. Fallback: write the same Environment from a headless `-s` script, and append to the `.tscn`:

```
[ext_resource type="Environment" path="res://scenes/map3d/world_environment.tres" id="20_env"]

[node name="Environment" type="WorldEnvironment" parent="Viewport"]
environment = ExtResource("20_env")

[node name="Sun" type="DirectionalLight3D" parent="Viewport"]
transform = Transform3D(0.707107, 0.405580, -0.579228, 0, 0.819152, 0.573576, 0.707107, -0.405580, 0.579228, 0, 0, 0)
light_energy = 1.1
shadow_enabled = true
directional_shadow_max_distance = 60000.0
```
  (The transform is `Basis.from_euler(Vector3(deg_to_rad(-35), deg_to_rad(45), 0))`. Print it headless and paste the exact numbers rather than trusting these.) The ext_resource line goes with the others at the top. The WorldEnvironment and the Sun sit under `Viewport`, after `WorldSlot`.
- [ ] **Step 5: Implement.**
  - `Map3DWorldLoader.instance(path)`: the load part of today's `_load` (lines 356–376): exists → load → instantiate → has meta, else free and return null. Then `strip_old_build(world)` (for each name in `OLD_BUILD_NODES`, `world.get_node_or_null(name)`; if found, `world.remove_child(n); n.free()`) and `own_terrain_material(world)` (the per-view duplicate loop, lines 373–376, with its comment).
  - `Map3DEnvironment.apply_environment(repo, env)`: sets the sky colours from `terrain_palette` (`map3d_sky_top`, `map3d_sky` ×2 for sky horizon and ground horizon, `map3d_sky_ground`), `sun_angle_max`, `ambient_light_energy`, `ambient_light_sky_contribution`, `fog_light_color` = `map3d_sky`, `fog_density`. `apply_sun(repo, sun)`: `rotation_degrees`, `light_energy`, `shadow_enabled = true`, `directional_shadow_max_distance`, then `apply_sun_look`. `make_sun` / `make_environment` build fresh nodes (for `shoot.gd`) and call the two above; `make_environment` loads `ENVIRONMENT` and duplicates it.
  - View `_load`: `_world = Map3DWorldLoader.instance(_scene_path)`, returning when null. After the context: `Map3DEnvironment.apply_environment(_repo, ($Viewport/Environment as WorldEnvironment).environment)` and `Map3DEnvironment.apply_sun(_repo, $Viewport/Sun)`. Delete the old sun lookup. `layer_names()` "Shadows" comes from `$Viewport/Sun` while loaded; `set_layer_visible("Shadows", on)` → `($Viewport/Sun as DirectionalLight3D).shadow_enabled = on`. Delete the "the build's own framing cameras" loop, because the loader strips them.
  - `Map3DLayerSea.build(ctx)`: make `var plane := PlaneMesh.new(); plane.size = Vector2(float(p[0]), float(p[1])) * float(ctx.meta["m_per_px"]) * ctx.repo.bal("map3d_sea_plane_span")` (the old build made its plane `span * 12.0` centred on the world origin); `mesh = plane; position = Vector3(0.0, float(ctx.meta.get("sea_y", 0.0)), 0.0)`; then the material as before. It no longer reads the world's Sea.
  - `tools/map3d/build_terrain.gd build_scene()`: delete the Sea, Sun, Environment and three `_camera(...)` blocks and the `_camera` helper. Its doc says the build is DATA: terrain, meta, rivers, fields.
  - `tools/map3d/shoot.gd`: after instancing the world, `var repo := DataRepository.load_all("res://data")` (and `load_map` for `--map`), then add `Map3DEnvironment.make_environment(repo)`, `Map3DEnvironment.make_sun(repo)` and one `Camera3D` from this framing table, moved from `build_terrain.gd`:

```gdscript
## The build's old framing shots (moved from build_terrain.gd, 2026-09-20):
## name -> [offset from the pivot (m), pitch, near, far]; the pivot is the world
## centre for Camera3D, the player's capital for the other two.
const FRAMES := {
	"Camera3D": [Vector3(0, 70000, 75000), -45.0, 50.0, 400000.0],
	"CameraMid": [Vector3(0, 14000, 16000), -40.0, 20.0, 200000.0],
	"CameraNear": [Vector3(0, 3000, 4200), -35.0, 5.0, 100000.0],
}
```
    with the capital's XZ from `BuildTerrain.capital_xz(BuildTerrain.world_info())` (preload `res://tools/map3d/build_terrain.gd` as `build_world.gd` does).
  - `tests/map3d/test_map3d_layers.gd::test_the_sea_layer_dresses_the_builds_plane`: rename it to `test_the_sea_layer_is_the_scenes_own_plane`. Keep its assertions; the "the build's plane, taken over" message becomes "the scene's own plane".
- [ ] **Step 6: Run** the scene test, the layers test, the folder, `./run_tests.sh`. Rebuild the local world (`GDAI_MCP_SERVER_PORT=3999 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/map3d/build_world.gd`) and bench it. Take a before/after snapshot (`tools/snapshot_screen.gd --screen court`) and compare them with the visual-review skill: expected identical.
- [ ] **Step 7: Commit** `feat(map3d): sun, sky and sea belong to the scene; the build emits data only` with the new scripts and `.tres`, the scene, `map3d_environment.gd`, `map3d_layer_sea.gd`, the view, both tools, both CSVs and both tests.

---

### Task 15: Pack plumbing — `map3d_dir`, the manifest, honest notices, `build_pack.sh`

**Files:**
- Modify: `data/maps.csv` (new column `map3d_dir`, empty for `beria`), `scripts/engine/data_repository.gd` (`map3d_dir`, static `map3d_dir_of`), `scripts/map3d/map3d_world_loader.gd` (`status`, `notice_text`, `steps_hash`, `warn_once`, the meta check), `scripts/map3d/map3d_view.gd` (`scene_path_for`, `_load` and the notice), `scripts/map3d/map3d_layer_rivers.gd`, `map3d_layer_themes.gd`, `map3d_layer_roads.gd`, `map3d_layer_sea.gd` (warn once about a missing optional input), `tools/map3d/build_world.gd` (writes `manifest.json`), `tools/map3d/build_terrain.gd` (`root()` reads `map3d_dir`), `tools/packs.py` (`map3d_dir`), `tools/map3d/bake_world.py` (`OUT` from `map3d_dir`), `tools/map3d/README.md`, `tools/NEW_MAP.md`, `CLAUDE.md` (the 3D-map paragraph: one line on `build_pack.sh` and `map3d_dir`)
- Create: `tools/map3d/build_pack.sh`
- Test: `tests/map3d/test_map3d_loader.gd`

**Interfaces:**
- `DataRepository.map3d_dir(id: String = "") -> String` (the row's `map3d_dir`, else `res://assets/map3d/<id>`; `""` means the loaded map), `static func map3d_dir_of(map_id: String, maps_csv: String = "res://data/maps.csv") -> String`.
- `Map3DWorldLoader`: `static func status(scene_path: String) -> Dictionary` → `{state: "ok"|"legacy"|"missing"|"stale"|"bad", why: String, manifest: Dictionary}`, `static func notice_text(state: String, map_id: String) -> String`, `static func steps_hash() -> String`, `static func same_meta(a: Dictionary, b: Dictionary) -> bool`, `static func warn_once(key: String, message: String) -> void`, `static func clear_warnings() -> void`.
- `Map3DView.scene_path_for(map_id)` → `Game.data.map3d_dir(map_id).path_join("world.tscn")` when `Game.data` is set, else `SCENE_PATTERN % map_id`.

**Risk:** a fixture without a manifest must still load (Ruling 12); fixtures all live in `user://`, so a test's `manifest.json` would sit beside every other fixture. **Catch:** the loader tests work in `user://loader_fixture/` and clean up after themselves; every existing fixture test keeps passing (no manifest, so `legacy`).

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_loader.gd`:

```gdscript
extends GutTest
## Swapping map data (spec 2026-09-20 §3): the build holds data plus a
## manifest; the game says honestly why there is no 3D map — missing, stale
## (rebuild), bad — and a pack can keep its 3D build anywhere (maps.csv
## map3d_dir).

const DIR := "user://loader_fixture"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_each() -> void:
	Game.start_campaign(42)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var root := Node3D.new()
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, DIR + "/world.tscn")
	root.free()


func after_each() -> void:
	for f: String in ["world.tscn", "manifest.json"]:
		if FileAccess.file_exists(DIR + "/" + f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	Map3DWorldLoader.clear_warnings()


func _manifest(text: String) -> void:
	var f := FileAccess.open(DIR + "/manifest.json", FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_no_scene_is_missing() -> void:
	assert_eq(Map3DWorldLoader.status("user://nowhere/world.tscn")["state"], "missing")


func test_no_manifest_is_a_legacy_build_that_loads() -> void:
	assert_eq(Map3DWorldLoader.status(DIR + "/world.tscn")["state"], "legacy")
	assert_not_null(Map3DWorldLoader.instance(DIR + "/world.tscn"))


func test_a_current_manifest_is_ok() -> void:
	_manifest(JSON.stringify({"format_version": Map3DWorldLoader.FORMAT_VERSION, "meta": WORLD,
		"steps_hash": Map3DWorldLoader.steps_hash()}))
	assert_eq(Map3DWorldLoader.status(DIR + "/world.tscn")["state"], "ok")


func test_an_older_pipeline_is_stale() -> void:
	_manifest(JSON.stringify({"format_version": 1, "meta": WORLD}))
	var st := Map3DWorldLoader.status(DIR + "/world.tscn")
	assert_eq(st["state"], "stale")
	assert_string_contains(String(st["why"]), "1")


func test_a_manifest_that_disagrees_with_the_scene_is_stale() -> void:
	var other := WORLD.duplicate()
	other["m_per_px"] = 40.0
	_manifest(JSON.stringify({"format_version": Map3DWorldLoader.FORMAT_VERSION, "meta": other}))
	assert_eq(Map3DWorldLoader.status(DIR + "/world.tscn")["state"], "stale")


func test_a_broken_manifest_is_bad() -> void:
	_manifest("{ not json")
	assert_eq(Map3DWorldLoader.status(DIR + "/world.tscn")["state"], "bad")


func test_json_numbers_still_match_the_meta() -> void:
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(WORLD))
	assert_true(Map3DWorldLoader.same_meta(WORLD, round_trip), "2560 and 2560.0 are one size")


func test_each_notice_says_what_to_run() -> void:
	for state: String in ["missing", "stale", "bad"]:
		var text := Map3DWorldLoader.notice_text(state, "beria")
		assert_string_contains(text, "tools/map3d")
		assert_string_contains(text, "build_pack.sh --map beria")


func test_a_stale_build_shows_its_notice_and_does_not_load() -> void:
	_manifest(JSON.stringify({"format_version": 1, "meta": WORLD}))
	var v := Map3DView.create(Game.data, DIR + "/world.tscn")
	add_child_autofree(v)
	v.activate()
	assert_false(v.is_loaded())
	assert_true(v.notice().visible)
	assert_string_contains(v.notice().text, "older")


func test_a_pack_can_keep_its_3d_build_elsewhere() -> void:
	var id := Game.data.map_id
	var row: Dictionary = Game.data.maps[id]
	var before := String(row.get("map3d_dir", ""))
	row["map3d_dir"] = "res://elsewhere/" + id
	assert_eq(Map3DView.scene_path_for(id), "res://elsewhere/%s/world.tscn" % id)
	row["map3d_dir"] = before
	assert_eq(Map3DView.scene_path_for(id), "res://assets/map3d/%s/world.tscn" % id)
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement** — add to `Map3DWorldLoader`:

```gdscript
const NOTICES := {
	"missing": "The 3D map has not been built for this map.\nRun tools/map3d/build_pack.sh --map %s (see tools/map3d/README.md).",
	"stale": "This 3D map was built by an older pipeline.\nRebuild it: tools/map3d/build_pack.sh --map %s",
	"bad": "This 3D map's build is damaged.\nRebuild it: tools/map3d/build_pack.sh --map %s",
}
static var _warned: Dictionary = {}


static func status(scene_path: String) -> Dictionary:
	if not ResourceLoader.exists(scene_path):
		return {"state": "missing", "why": scene_path + " is not built", "manifest": {}}
	var mpath := scene_path.get_base_dir().path_join("manifest.json")
	if not FileAccess.file_exists(mpath):
		warn_once("legacy:" + scene_path, "Map3DWorldLoader: %s has no manifest.json (a build from before 2026-09-20)" % scene_path)
		return {"state": "legacy", "why": "", "manifest": {}}
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	if not (m is Dictionary):
		return {"state": "bad", "why": "manifest.json is not JSON", "manifest": {}}
	var v := int((m as Dictionary).get("format_version", 0))
	if v != FORMAT_VERSION:
		return {"state": "stale", "why": "built by pipeline v%d; the game reads v%d" % [v, FORMAT_VERSION],
			"manifest": m}
	var sm := scene_meta(scene_path)
	if sm.is_empty():
		return {"state": "bad", "why": "the scene's root carries no map3d_world", "manifest": m}
	if not same_meta((m as Dictionary).get("meta", {}), sm):
		return {"state": "stale", "why": "manifest.json describes another world than the scene",
			"manifest": m}
	if String((m as Dictionary).get("steps_hash", "")) != steps_hash():
		warn_once("steps:" + scene_path, "Map3DWorldLoader: the bake tables changed since %s was built — rebuild to see them" % scene_path)
	return {"state": "ok", "why": "", "manifest": m}


## The root's map3d_world meta, read from the packed scene without instancing
## it (the load is cached; instance() reuses it).
static func scene_meta(scene_path: String) -> Dictionary:
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return {}
	var st := ps.get_state()
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == &"metadata/map3d_world":
			return st.get_node_property_value(0, i)
	return {}


static func notice_text(state: String, map_id: String) -> String:
	return String(NOTICES.get(state, NOTICES["bad"])) % map_id


## The bake inputs' fingerprint: data/map3d_bake.csv and data/map3d_fields.csv.
static func steps_hash() -> String:
	return (FileAccess.get_md5("res://data/map3d_bake.csv")
		+ FileAccess.get_md5("res://data/map3d_fields.csv")).md5_text()


## Two map3d_world metas describe the same world (JSON turns 2560 into 2560.0).
static func same_meta(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["m_per_px", "sea_y"]:
		if not is_equal_approx(float(a.get(key, 0.0)), float(b.get(key, 0.0))):
			return false
	for key: String in ["pack_origin", "pack_px"]:
		var x: Array = a.get(key, [])
		var y: Array = b.get(key, [])
		if x.size() != y.size():
			return false
		for i in x.size():
			if not is_equal_approx(float(x[i]), float(y[i])):
				return false
	return true


static func warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)


static func clear_warnings() -> void:
	_warned.clear()
```
  Add `static func scene_meta(scene_path: String) -> Dictionary` to the Interfaces list. `status` checks the manifest's meta against the scene's own (`scene_meta`), so `instance()` needs no second check.
  - View `_load`: `var st := Map3DWorldLoader.status(_scene_path)`; `_notice.text = Map3DWorldLoader.notice_text(String(st["state"]), _repo.map_id)`; return unless the state is `ok` or `legacy`; `_world = Map3DWorldLoader.instance(_scene_path)`; if null, `_notice.text = Map3DWorldLoader.notice_text("bad", _repo.map_id)` and return. `NOTICE_TEXT` stays as a constant (`Map3DWorldLoader.NOTICES["missing"]` cannot be a const expression with `%`, so keep the old literal for the scene's default text).
  - `scene_path_for(map_id)`: `if Game.data != null and Game.data.maps.has(map_id): return Game.data.map3d_dir(map_id).path_join("world.tscn")`, else `return SCENE_PATTERN % map_id`.
  - `DataRepository.map3d_dir(id)`: `var row: Dictionary = maps.get(id if id != "" else map_id, {}); var d := String(row.get("map3d_dir", "")); return d if d != "" else "res://assets/map3d/%s" % (id if id != "" else map_id)`. `map3d_dir_of` is the same over `parse_csv(maps_csv, ["map_id"])` (the `default_pack_id` pattern).
  - Optional inputs warn once: `Map3DLayerRivers.build` with no `rivers.json` (`"rivers:" + path`), `Map3DLayerThemes.prepare` with no `bake/fields.png`, `Map3DLayerRoads` with no packed textures, `Map3DLayerSea` with no `sea_texture_path`.
  - `tools/map3d/build_world.gd`: after the save succeeds, write `BuildTerrain.root() + "/manifest.json"` with `{"format_version": Map3DWorldLoader.FORMAT_VERSION, "meta": scene.get_meta("map3d_world"), "built_at": Time.get_datetime_string_from_system(true), "steps_hash": Map3DWorldLoader.steps_hash()}` (`JSON.stringify(…, "  ")`). `Time` is fine in a tool: this is not simulation code.
  - `tools/map3d/build_terrain.gd root()`: `return DataRepository.map3d_dir_of(map())`.
  - `tools/packs.py`: `def map3d_dir(map_id, maps_csv=…)` returning the row's `map3d_dir` (with `res://` mapped to `ROOT`) or `ROOT/assets/map3d/<id>`. `bake_world.py`: `OUT = os.path.join(map3d_dir(MAP), "bake")`.
  - `tools/map3d/build_pack.sh` (`chmod +x`):

```sh
#!/bin/sh
# Build one pack's 3D map, the whole chain (spec 2026-09-20 §3):
#   tools/map3d/build_pack.sh [--map ID]      (default: data/maps.csv is_default)
# export_manor_land -> bake_world.py -> build_world.gd. The textures
# (pack_textures.py, Blender) are shared by every pack and built once — see README.
set -e
cd "$(dirname "$0")/../.."
MAP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --map) MAP="$2"; shift 2 ;;
    *) echo "usage: $0 [--map ID]" >&2; exit 2 ;;
  esac
done
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
export GDAI_MCP_SERVER_PORT=3999
if [ -n "$MAP" ]; then
  "$GODOT" --headless --path . -s tools/map3d/export_manor_land.gd -- --map "$MAP"
  python3 tools/map3d/bake_world.py --map "$MAP"
  "$GODOT" --headless --path . -s tools/map3d/build_world.gd -- --map "$MAP"
else
  "$GODOT" --headless --path . -s tools/map3d/export_manor_land.gd
  python3 tools/map3d/bake_world.py
  "$GODOT" --headless --path . -s tools/map3d/build_world.gd
fi
echo "build_pack: done — assets/map3d/${MAP:-<default>}/manifest.json"
```
  - Docs: in `tools/map3d/README.md`, "Rebuilding" leads with `tools/map3d/build_pack.sh --map ID`, and new sections cover "The manifest" and "`map3d_dir`". `tools/NEW_MAP.md` gets one step: "3D map: `tools/map3d/build_pack.sh --map <id>`". In CLAUDE.md's "The 3D map is the default map" paragraph, add one sentence: the build holds data only plus `manifest.json`, `map3d_dir` in `maps.csv`, and `build_pack.sh`.
- [ ] **Step 4: Run** the loader test (10 passed), the folder, `./run_tests.sh`. Rebuild the local world with `tools/map3d/build_pack.sh` and check `assets/map3d/<id>/manifest.json` exists and the game loads it as `ok` (bench run: exit 0).
- [ ] **Step 5: Commit** `feat(map3d): a pack's 3D build is data plus a manifest; one command builds it` with every file listed above.

---
### Task 16: Quality tiers as data — `graphics_quality.csv` and `Map3DQuality`

**Files:**
- Create: `data/graphics_quality.csv`, `scripts/map3d/map3d_quality.gd`
- Modify: `scripts/engine/data_repository.gd` (load `graphics_quality`), `tests/pre_run.gd` (pin `high`, Ruling 7)
- Test: `tests/map3d/test_map3d_quality.gd`

**Interfaces:**
- `DataRepository.graphics_quality: Dictionary` (tier → row, string values as parsed).
- `class_name Map3DQuality extends RefCounted`: `const TIERS := ["low", "medium", "high", "ultra"]`, `const AUTO := "auto"`, `static var forced := ""`, `static func row(repo: DataRepository, tier: String) -> Dictionary`, `static func num(r: Dictionary, key: String, fallback: float = 1.0) -> float`, `static func detect(adapter: String, vendor: String) -> String`, `static func setting(path: String) -> String`, `static func save_setting(path: String, tier: String) -> void`, `static func resolve(settings_path: String, adapter: String, vendor: String) -> String`, `static func next_setting(current: String) -> String`.

**Risk:** a detection rule that sends a capable GPU to `low`. The Apple Pro/Max/Ultra, RX and Arc cases are covered. **Catch:** the table test below. The high row must reproduce today exactly (the consistency test).

- [ ] **Step 1: The data** — `data/graphics_quality.csv`:

```
tier,render_scale,msaa,aniso,sun_shadows,shadow_splits,shadow_max_m,shadow_atlas_px,cloud_shadows,clouds,terrain_mesh_size,terrain_mesh_lods,line_step_mul,road_step_mul,river_step_mul,hud_hz,world,bench_budget_ms,bench_size,notes
low,0.67,0,4,0,0,0,0,0,4,32,5,2.0,2.0,2.5,30,full,4,1920x1080,"3D MAP graphics tier (spec 2026-09-20 §4): Intel UHD/Iris/Xe, AMD APUs, software GL. Render at 0.67 of the window, no sun or cloud shadows, 4 clouds, a coarser Terrain3D mesh, lines 300 m / roads 50 m / rivers 30 m (x the balance.csv steps), the HUD at 30 Hz. world: 'lite' once the optional lite build exists (Task 23). Bench gate 4 ms at 1920x1080 on the dev machine (~8-10x headroom)."
medium,0.85,0,8,1,2,30000,2048,0,8,48,6,1.3333,1.4,1.5,60,full,6,1920x1080,"base Apple M-series, GTX <= 10xx, MX: 0.85 render scale, 2 shadow splits to 30 km at 2048, no cloud shadows, 8 clouds, lines 200 / roads 35 / rivers 18 m, HUD 60 Hz. Bench gate 6 ms at 1920x1080."
high,1.0,0,16,1,4,60000,4096,1,10,48,7,1.0,1.0,1.0,0,full,8,3024x1964,"everything else, and the look of 2026-09-19 exactly: full resolution, 4 splits to 60 km at 4096, cloud shadows, 10 clouds (balance map3d_cloud_max), Terrain3D's default mesh 48/7, the balance.csv steps, the HUD redrawn on every camera move (hud_hz 0 = unlimited). Bench gate 8 ms at 3024x1964."
ultra,1.0,2,16,1,4,60000,4096,1,10,64,8,1.0,1.0,1.0,0,full,8,3024x1964,"high plus MSAA 2x and a finer Terrain3D mesh (64/8)."
```

- [ ] **Step 2: Failing test** — `tests/map3d/test_map3d_quality.gd`:

```gdscript
extends GutTest
## Graphics tiers for ordinary machines (spec 2026-09-20 §4):
## data/graphics_quality.csv read by Map3DQuality — pure: the row, the GPU
## detection, the saved setting.

const CFG := "user://test_quality_settings.cfg"


func before_all() -> void:
	Game.start_campaign(42)


func after_each() -> void:
	if FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func test_every_tier_has_a_row() -> void:
	for tier: String in Map3DQuality.TIERS:
		assert_true(Game.data.graphics_quality.has(tier), tier)
	assert_eq(Map3DQuality.row(Game.data, "nonsense"), Map3DQuality.row(Game.data, "high"))


func test_high_is_todays_look() -> void:
	var r := Map3DQuality.row(Game.data, "high")
	assert_eq(Map3DQuality.num(r, "render_scale"), 1.0)
	assert_eq(Map3DQuality.num(r, "line_step_mul"), 1.0)
	assert_eq(Map3DQuality.num(r, "road_step_mul"), 1.0)
	assert_eq(Map3DQuality.num(r, "river_step_mul"), 1.0)
	assert_eq(Map3DQuality.num(r, "clouds"), Game.data.bal("map3d_cloud_max"))
	assert_eq(Map3DQuality.num(r, "shadow_max_m"), Game.data.bal("map3d_sun_shadow_max_m"))
	assert_eq(Map3DQuality.num(r, "hud_hz"), 0.0)


func test_the_spec_steps_come_out_in_metres() -> void:
	var low := Map3DQuality.row(Game.data, "low")
	assert_almost_eq(Game.data.bal("map3d_line_step_m") * Map3DQuality.num(low, "line_step_mul"), 300.0, 0.01)
	assert_almost_eq(Game.data.bal("map3d_road_step_m") * Map3DQuality.num(low, "road_step_mul"), 50.0, 0.01)
	assert_almost_eq(Game.data.bal("map3d_river_mesh_step_m") * Map3DQuality.num(low, "river_step_mul"), 30.0, 0.01)
	var med := Map3DQuality.row(Game.data, "medium")
	assert_almost_eq(Game.data.bal("map3d_line_step_m") * Map3DQuality.num(med, "line_step_mul"), 200.0, 0.01)
	assert_almost_eq(Game.data.bal("map3d_road_step_m") * Map3DQuality.num(med, "road_step_mul"), 35.0, 0.01)
	assert_almost_eq(Game.data.bal("map3d_river_mesh_step_m") * Map3DQuality.num(med, "river_step_mul"), 18.0, 0.01)


func test_detection_by_adapter_name() -> void:
	var cases := {
		["Intel(R) Iris(R) Xe Graphics", "Intel"]: "low",
		["Intel(R) UHD Graphics 620", "Intel"]: "low",
		["Intel(R) HD Graphics 520", "Intel"]: "low",
		["AMD Radeon(TM) Graphics", "AMD"]: "low",
		["AMD Radeon Vega 8 Graphics", "AMD"]: "low",
		["llvmpipe (LLVM 15.0.7, 256 bits)", "Mesa"]: "low",
		["Apple M1", "Apple"]: "medium",
		["Apple M3", "Apple"]: "medium",
		["NVIDIA GeForce GTX 1060 6GB", "NVIDIA"]: "medium",
		["NVIDIA GeForce MX450", "NVIDIA"]: "medium",
		["Apple M2 Pro", "Apple"]: "high",
		["Apple M5 Pro", "Apple"]: "high",
		["NVIDIA GeForce RTX 3060", "NVIDIA"]: "high",
		["NVIDIA GeForce GTX 1660 SUPER", "NVIDIA"]: "high",
		["AMD Radeon RX 6600", "AMD"]: "high",
		["AMD Radeon Pro 5500M", "AMD"]: "high",
		["Intel(R) Arc(TM) A770 Graphics", "Intel"]: "high",
		["", ""]: "high",
	}
	for k: Array in cases:
		assert_eq(Map3DQuality.detect(k[0], k[1]), cases[k], "%s" % k)


func test_the_setting_overrides_the_detection() -> void:
	assert_eq(Map3DQuality.setting(CFG), Map3DQuality.AUTO, "no file: auto")
	Map3DQuality.save_setting(CFG, "low")
	assert_eq(Map3DQuality.setting(CFG), "low")
	var was := Map3DQuality.forced
	Map3DQuality.forced = ""
	assert_eq(Map3DQuality.resolve(CFG, "Apple M5 Pro", "Apple"), "low")
	Map3DQuality.save_setting(CFG, Map3DQuality.AUTO)
	assert_eq(Map3DQuality.resolve(CFG, "Apple M1", "Apple"), "medium")
	Map3DQuality.forced = was


func test_the_menu_cycles_auto_then_each_tier() -> void:
	assert_eq(Map3DQuality.next_setting("auto"), "low")
	assert_eq(Map3DQuality.next_setting("ultra"), "auto")
```

- [ ] **Step 3: Run it (fails)** — `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_quality.gd -gexit`.
- [ ] **Step 4: Implement.** `DataRepository`: `var graphics_quality: Dictionary = {}` (doc comment: tiers by name, spec 2026-09-20 §4), cleared with the other global tables, loaded right after `map3d_settlements` with `_load_if_present("res://data/graphics_quality.csv", ["tier", "render_scale"], func(r): graphics_quality[String(r["tier"])] = r)`. `scripts/map3d/map3d_quality.gd`:

```gdscript
class_name Map3DQuality
extends RefCounted
## The 3D map's graphics tiers (spec 2026-09-20 §4): data/graphics_quality.csv
## rows low / medium / high / ultra. A first run picks one from the GPU's name
## (detect); user://settings.cfg [graphics] quality — the pause menu's choice —
## overrides it; "auto" defers to the detection. Pure: no scene, no autoload.

const TIERS := ["low", "medium", "high", "ultra"]
const AUTO := "auto"
const SECTION := "graphics"
const KEY := "quality"
## Test and bench seam: a tier forced over the setting and the detection ("" none).
static var forced := ""


static func row(repo: DataRepository, tier: String) -> Dictionary:
	if repo.graphics_quality.has(tier):
		return repo.graphics_quality[tier]
	return repo.graphics_quality.get("high", {})


## A row's number (the CSV parses as strings).
static func num(r: Dictionary, key: String, fallback: float = 1.0) -> float:
	return float(r[key]) if r.has(key) and String(r[key]) != "" else fallback


## The tier a GPU starts at (spec §4): integrated Intel, AMD APUs and software
## GL low; the base Apple M chips, GTX 10xx and older, and MX parts medium;
## everything else — and an unknown adapter — high.
static func detect(adapter: String, vendor: String) -> String:
	var a := (adapter + " " + vendor).to_lower().replace("(r)", "").replace("(tm)", "")
	if a.strip_edges() == "":
		return "high"
	for soft: String in ["llvmpipe", "swiftshader", "softpipe", "software", "basic render"]:
		if a.contains(soft):
			return "low"
	if a.contains("intel") and (a.contains("uhd") or a.contains("iris") or a.contains("hd graphics")
			or a.contains(" xe")):
		return "low"
	if a.contains("radeon") and not a.contains(" rx") and not a.contains(" pro") \
			and (a.contains("radeon graphics") or a.contains("vega")):
		return "low"
	if a.contains("apple m") and not (a.contains(" pro") or a.contains(" max") or a.contains(" ultra")):
		return "medium"
	var gtx := RegEx.create_from_string("gtx\\s*(\\d{3,4})").search(a)
	if gtx != null and int(gtx.get_string(1)) < 1100:
		return "medium"
	if RegEx.create_from_string("\\bmx\\s?\\d{3}").search(a) != null:
		return "medium"
	return "high"


static func setting(path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return AUTO
	var t := String(cfg.get_value(SECTION, KEY, AUTO))
	return t if t in TIERS else AUTO


static func save_setting(path: String, tier: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is a fresh one
	cfg.set_value(SECTION, KEY, tier)
	cfg.save(path)


static func resolve(settings_path: String, adapter: String, vendor: String) -> String:
	if forced in TIERS:
		return forced
	var t := setting(settings_path)
	return t if t != AUTO else detect(adapter, vendor)


## The pause menu's next choice: auto, then each tier, then auto again.
static func next_setting(current: String) -> String:
	var order: Array = [AUTO] + TIERS
	return String(order[(order.find(current) + 1) % order.size()])
```
  `tests/pre_run.gd`: add `Map3DQuality.forced = "high"` with the comment "the suite runs at high, today's look (Ruling 7)".
- [ ] **Step 5: Run** (6 passed), `./run_tests.sh`, commit `feat(map3d): graphics tiers as data; Map3DQuality detects and remembers` (`data/graphics_quality.csv scripts/map3d/map3d_quality.gd scripts/engine/data_repository.gd tests/pre_run.gd tests/map3d/test_map3d_quality.gd`).

---

### Task 17: The view wears its tier — render scale split, shadows, clouds, mesh, steps, HUD Hz, the pause menu

**Files:**
- Modify: `scripts/map3d/map3d_context.gd` (`q()`, `render_scale`, the steps), `scripts/map3d/map3d_view.gd` (`set_quality`, `quality_tier`, `_apply_quality`, tier resolved at load), `scripts/map3d/map3d_environment.gd` (`apply_quality`, `apply_terrain_quality`), `scripts/map3d/map3d_hud.gd` (`hz`, throttle, `redraws` seam), `scripts/map3d/map3d_layer_lines.gd` (`apply_scale` reads `material_override` first), `scripts/ui/game_root.gd` (pause-menu "Graphics" button)
- Test: `tests/map3d/test_map3d_quality.gd` (append)

**Interfaces:**
- `Map3DContext.q() -> Dictionary`; `render_scale()` = `Map3DQuality.num(q(), "render_scale")`; `line_step()` = `bal("map3d_line_step_m") × num(q(), "line_step_mul")`; `road_step()` and `river_step()` the same with their keys.
- `Map3DView.set_quality(tier: String, overrides: Dictionary = {}) -> void`, `quality_tier() -> String`.
- `Map3DEnvironment.apply_quality(sun: DirectionalLight3D, row: Dictionary) -> void`, `apply_terrain_quality(terrain: Node, row: Dictionary) -> void`.
- `Map3DHud.hz: float` (0 = unlimited), `Map3DHud.redraws: int` (test seam).
- `GameRoot`: a pause-menu button named `GraphicsQuality`; `quality_setting() -> String`.

**Risk:** the render-scale split is the likeliest pick bug (spec §6): a projection divided by the window scale where it needed the viewport scale. **Catch:** the round-trip tests below at render scale 0.67. Every projection goes through `ctx.project` / `ctx.ground_at` / `viewport_px_scale()`, so grep the map3d scripts for `unproject_position` and `project_ray_` and make sure each divides or multiplies by `viewport_px_scale()`.

- [ ] **Step 1: Failing test** — append:

```gdscript
const Q_FIXTURE := "user://test_map3d_quality_world.tscn"


func _q_view() -> Map3DView:
	var root := Node3D.new()
	root.set_meta("map3d_world", {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
		"pack_px": [2560, 929], "sea_y": 5.0})
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, Q_FIXTURE)
	root.free()
	var v := Map3DView.create(Game.data, Q_FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	v.refresh_borders()
	return v


func test_a_lower_render_scale_renders_fewer_pixels() -> void:
	var v := _q_view()
	assert_eq(v.quality_tier(), "high")
	assert_eq(v.viewport().size, Vector2i(800, 450))
	v.set_quality("low")
	assert_eq(v.viewport().size, Vector2i(int(800 * 0.67), int(450 * 0.67)))
	assert_almost_eq(v.context().viewport_px_scale(), 0.67, 0.0001)
	var ink := v.line_mesh("Kingdoms").surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(ink.get_shader_parameter("width_px")),
		Game.data.bal("map3d_border_width_px") * 0.67, 0.0001, "screen widths follow the pixels")


func test_picks_round_trip_at_any_render_scale() -> void:
	var v := _q_view()
	for tier: String in ["high", "low"]:
		v.set_quality(tier)
		var c := v.context()
		var checked := 0
		for e: Dictionary in c.projected_settlements():
			var p: Vector2 = e["screen"]
			if not bool(e["shown"]) or not Rect2(Vector2.ZERO, v.size).has_point(p):
				continue
			var hit: Variant = c.ground_at(p)
			assert_not_null(hit)
			var w: Vector3 = e["world"]
			assert_almost_eq((hit as Vector3).x, w.x, 1.0, "%s at %s" % [e["code"], tier])
			assert_almost_eq((hit as Vector3).z, w.z, 1.0)
			checked += 1
			if checked >= 8:
				break
		assert_gt(checked, 0)
		var capital := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
		assert_eq(v.pick_at(v.size * 0.5), {"kind": "burg", "code": capital}, tier)


func test_the_tier_reaches_clouds_steps_and_shadows() -> void:
	var v := _q_view()
	v.set_quality("low")
	var c := v.context()
	assert_almost_eq(c.line_step(), 300.0, 0.01)
	Game.set_clock_speed(1)
	v._process(0.1)
	assert_eq(v.cloud_count(), 4)
	Game.set_clock_speed(0)
	assert_false((v.get_node("Viewport/Clouds/Shadows") as Node3D).visible)
	assert_false((v.get_node("Viewport/Sun") as DirectionalLight3D).shadow_enabled)
	v.set_quality("ultra")
	assert_eq(v.viewport().msaa_3d, Viewport.MSAA_2X)
	assert_true((v.get_node("Viewport/Sun") as DirectionalLight3D).shadow_enabled)


func test_a_throttled_hud_redraws_at_most_at_its_rate() -> void:
	var v := _q_view()
	var hud := v.get_node("Hud") as Map3DHud
	hud.hz = 30.0
	var n := hud.redraws
	hud.refresh()
	hud.refresh()
	assert_eq(hud.redraws, n + 1, "two moves in one frame, one redraw")
	hud._process(0.05)
	assert_eq(hud.redraws, n + 2, "the pending redraw lands after 1/30 s")


func test_the_pause_menu_remembers_the_tier() -> void:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	var button := r.pause_menu().find_child("GraphicsQuality", true, false) as Button
	assert_not_null(button)
	var before := r.quality_setting()
	button.pressed.emit()
	assert_eq(r.quality_setting(), Map3DQuality.next_setting(before))
	assert_eq(Map3DQuality.setting(GameRoot.settings_path), r.quality_setting())
	assert_string_contains(button.text, "Graphics")
	Map3DQuality.save_setting(GameRoot.settings_path, Map3DQuality.AUTO)
```

- [ ] **Step 2: Run it (fails)** — the Task 16 command.
- [ ] **Step 3: Implement.**
  - `Map3DContext`: `func q() -> Dictionary: return quality if not quality.is_empty() else Map3DQuality.row(repo, "high")`; `render_scale()` → `Map3DQuality.num(q(), "render_scale")`; `line_step()` → `repo.bal("map3d_line_step_m") * Map3DQuality.num(q(), "line_step_mul")`, and `road_step()` / `river_step()` with `road_step_mul` / `river_step_mul`.
  - `Map3DEnvironment.apply_quality(sun, row)`: `sun.shadow_enabled = Map3DQuality.num(row, "sun_shadows", 1.0) > 0.0`; `sun.directional_shadow_mode` = `SHADOW_PARALLEL_4_SPLITS` for 4 splits, `SHADOW_PARALLEL_2_SPLITS` for 2, else `SHADOW_ORTHOGONAL`; `if num(row, "shadow_max_m", 0) > 0: sun.directional_shadow_max_distance = …`; `if num(row, "shadow_atlas_px", 0) > 0: RenderingServer.directional_shadow_atlas_set_size(int(…), true)`. `apply_terrain_quality(terrain, row)`: `if terrain == null: return`; for `["mesh_size", "terrain_mesh_size"]` and `["mesh_lods", "terrain_mesh_lods"]`, `if prop in terrain: terrain.set(prop, int(Map3DQuality.num(row, key)))`. First check with `ClassDB.class_get_property_list("Terrain3D")` in a scratch headless script that Terrain3D 1.0.2 names them `mesh_size` / `mesh_lods`; if not, use the names it prints and note them in the commit.
  - `Map3DView`: `var _tier := ""`. In `_load`, after the context: `if _tier == "": _tier = Map3DQuality.resolve(GameRoot.settings_path, RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor())`; `_ctx.quality = Map3DQuality.row(_repo, _tier)` BEFORE the layers are built (they read the steps). At the end of `_load`: `_apply_quality()`.

```gdscript
## Wear a graphics tier (Map3DQuality; `overrides` replaces single values —
## the bench's --render-scale). Render scale, MSAA, anisotropy, shadows,
## clouds, the terrain mesh and the HUD's rate apply now; the line, road and
## river steps at the next build of the layers (Ruling 6).
func set_quality(tier: String, overrides: Dictionary = {}) -> void:
	_tier = tier
	_overrides = overrides
	_apply_quality()


func quality_tier() -> String:
	return _tier


func _apply_quality() -> void:
	if _ctx == null:
		return
	var row: Dictionary = Map3DQuality.row(_repo, _tier).duplicate()
	row.merge(_overrides, true)
	_ctx.quality = row
	_fit_viewport()
	var msaa := int(Map3DQuality.num(row, "msaa", 0.0))
	_viewport.msaa_3d = Viewport.MSAA_2X if msaa == 2 else (Viewport.MSAA_4X if msaa == 4
		else (Viewport.MSAA_8X if msaa == 8 else Viewport.MSAA_DISABLED))
	if "anisotropic_filtering_level" in _viewport:
		var aniso := int(Map3DQuality.num(row, "aniso", 16.0))
		_viewport.set("anisotropic_filtering_level",
			{1: 0, 2: 1, 4: 2, 8: 3, 16: 4}.get(aniso, 4))
	Map3DEnvironment.apply_quality($Viewport/Sun as DirectionalLight3D, row)
	_clouds.set_quality(mini(int(_repo.bal("map3d_cloud_max")), int(Map3DQuality.num(row, "clouds"))),
		Map3DQuality.num(row, "cloud_shadows") > 0.0)
	Map3DEnvironment.apply_terrain_quality(_ctx.terrain, row)
	_hud.hz = Map3DQuality.num(row, "hud_hz", 0.0)
	_update_line_scale()
```
  with `var _overrides: Dictionary = {}`. `_fit_viewport()` already sizes by `_render_scale()` (= `viewport_px_scale()`, Ruling 3); it must then call `_update_line_scale()`, as it does today. Check that `Viewport.anisotropic_filtering_level` exists in 4.7 (`ClassDB.class_has_property("Viewport", "anisotropic_filtering_level")`). If it does not, the tier's `aniso` becomes a project setting that applies on restart; note that in the CSV's notes.
  - `Map3DLayerLines.apply_scale`: `var mat := (mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(0)) as ShaderMaterial` (baked meshes in Task 20 carry an override).
  - `Map3DHud`:

```gdscript
## Redraws per second at most (graphics_quality hud_hz; 0 = on every move).
var hz := 0.0
## Test seam: how many times the HUD has redrawn.
var redraws := 0
var _dirty := false
var _since := INF


func refresh() -> void:
	if hz <= 0.0 or _since >= 1.0 / hz:
		_redraw()
	else:
		_dirty = true
		set_process(true)


func _process(delta: float) -> void:
	_since += delta
	if _dirty and hz > 0.0 and _since >= 1.0 / hz:
		_redraw()
	if not _dirty:
		set_process(false)


func _redraw() -> void:
	_dirty = false
	_since = 0.0
	redraws += 1
	for c: Node in get_children():
		(c as CanvasItem).queue_redraw()
```
  - `GameRoot`: `var _quality_button: Button`. In `_build_pause_menu`, after the music button: `_quality_button = _menu_button(_quality_label(), _cycle_quality); _quality_button.name = "GraphicsQuality"; col.add_child(_quality_button)`. Add:

```gdscript
## The 3D map's graphics tier (spec 2026-09-20 §4), remembered in settings_path.
func quality_setting() -> String:
	return Map3DQuality.setting(settings_path)

func _quality_label() -> String:
	var s := quality_setting()
	return "Graphics: %s" % (s.capitalize() if s != Map3DQuality.AUTO else "Auto")

func _cycle_quality() -> void:
	Map3DQuality.save_setting(settings_path, Map3DQuality.next_setting(quality_setting()))
	_quality_button.text = _quality_label()
	if current_screen != null and current_screen.has_method("map3d_view"):
		var v: Map3DView = current_screen.map3d_view()
		if v != null:
			v.set_quality(Map3DQuality.resolve(settings_path,
				RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()))
```
- [ ] **Step 4: Run** (the quality file: 11 passed), the folder, `./run_tests.sh`.
- [ ] **Step 5: Bench** at high (3024×1964): the numbers must match the baseline, because nothing changed at high. Then run `--quality low` once by hand (Task 18 adds the flag; until then, set `Map3DQuality.forced` in a scratch copy of the bench) to see that it runs.
- [ ] **Step 6: Commit** `feat(map3d): the view wears its graphics tier; the render scale is split from the window's; a Graphics choice in the pause menu`.

---

### Task 18: Bench flags and gates

**Files:**
- Modify: `tools/map3d/bench.gd`, `tools/map3d/README.md` (a "Performance tiers" section)
- Test: none new (a tool). The gate runs are the test.

**Interfaces:**
- Bench flags: `--quality low|medium|high|ultra` (sets `Map3DQuality.forced` before GameRoot is made), `--render-scale X` (`v.set_quality(tier, {"render_scale": str(X)})`), `--out FILE` (Task 0), `--layer` (as before). Budget = the tier row's `bench_budget_ms`. A warning prints when `--size` differs from the row's `bench_size`. Exit 3 over budget.

**Risk:** the medium or low gate failing on the dev machine. **Catch/Remedy:** the per-layer rows ("- Clouds", "- Shadows", "- Lines" …) name the dearest layer. Tune only that tier's row in `graphics_quality.csv` (never high), re-run, and put the before/after numbers in the commit.

- [ ] **Step 1: Implement** — in `_ready`, before `Game.start_campaign`: `var qi := args.find("--quality"); var tier := args[qi + 1] if qi >= 0 and qi + 1 < args.size() else "high"; Map3DQuality.forced = tier`. After the view is found: `var ri := args.find("--render-scale"); if ri >= 0 and ri + 1 < args.size(): v.set_quality(tier, {"render_scale": args[ri + 1]})`. `var row := Map3DQuality.row(Game.data, tier); var budget := Map3DQuality.num(row, "bench_budget_ms", BUDGET_MS)`; `if "%dx%d" % [size.x, size.y] != String(row.get("bench_size", "")): print("WARNING: tier %s is gated at %s, not %s" % …)`. Print `tier %s render_scale %.2f` in the header line. The `_rows` quality column becomes `tier`. Keep `BUDGET_MS` only as the fallback. `quit(0 if worst <= budget else 3)`; `WORST … budget %.2f ms (%s)` names the tier.
- [ ] **Step 2: Run the three gates** (editor closed or the port moved):
  - `GDAI_MCP_SERVER_PORT=3999 /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/map3d/bench.tscn -- --size 3024x1964 --quality high --out tools/map3d/bench_runs.csv`, expected exit 0, WORST ≤ 8.00
  - `… -- --size 1920x1080 --quality medium --out tools/map3d/bench_runs.csv`, expected exit 0, WORST ≤ 6.00
  - `… -- --size 1920x1080 --quality low --out tools/map3d/bench_runs.csv`, expected exit 0, WORST ≤ 4.00
  - then the same three with `--layer manors` and `--layer heights`.
- [ ] **Step 3: README** — the gates table, and the spec's advice to do one real run on an integrated-GPU machine before shipping.
- [ ] **Step 4: Commit** `perf(map3d): the bench prices each tier and gates it` (`tools/map3d/bench.gd tools/map3d/README.md tools/map3d/bench_runs.csv`, plus `data/graphics_quality.csv` if a tier was tuned).

---

### Task 19: The world cache — a screen switch re-parents, never reloads

**Files:**
- Create: `scripts/map3d/map3d_world_cache.gd`, `tests/post_run.gd`
- Modify: `scripts/map3d/map3d_view.gd` (`_load` takes from the cache; `_notification(NOTIFICATION_PREDELETE)` gives back), `scripts/map3d/map3d_layer_themes.gd` (`prepare` reuses an already-patched material), `scripts/ui/game_root.gd` (`_exit_tree` clears the cache), `run_tests.sh` (`-gpost_run_script=res://tests/post_run.gd`)
- Test: `tests/map3d/test_map3d_world_cache.gd`

**Interfaces:**
- `class_name Map3DWorldCache extends RefCounted`: `static func take(scene_path: String) -> Node3D`, `static func adopt(scene_path: String, world: Node3D) -> void`, `static func give_back(scene_path: String, world: Node3D) -> void`, `static func clear() -> void`, `static func held() -> String`, `static func lent() -> bool`.

**Risk:** a patched terrain material shared by two live views (the MANORS regression of 2026-09-19), and Terrain3D surviving a re-parent into another SubViewport's World3D. **Catch:** the tests below hold that a world is never lent twice. The Terrain3D re-parent needs the real build, so Step 5 checks it by hand with the bench and a snapshot, and the loaded view's `cell_lut` test (`test_map3d_manor_themes.gd`) runs every suite.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_world_cache.gd`:

```gdscript
extends GutTest
## The world cache (spec 2026-09-20 §3): a screen switch frees the view but
## not its 44 MB world; the next view re-parents it. At most one world, lent
## to one view at a time (Ruling 13).

const FIXTURE := "user://test_map3d_cache_world.tscn"
const OTHER := "user://test_map3d_cache_other.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	for path: String in [FIXTURE, OTHER]:
		var root := Node3D.new()
		root.set_meta("map3d_world", WORLD)
		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, path)
		root.free()


func after_each() -> void:
	Map3DWorldCache.clear()


func _view(path: String = FIXTURE) -> Map3DView:
	var v := Map3DView.create(Game.data, path)
	v.size = Vector2(800, 450)
	add_child(v)
	v.activate()
	return v


func _world_of(v: Map3DView) -> Node:
	return v.viewport().get_node("WorldSlot").get_child(0)


func test_a_new_view_reuses_the_last_views_world() -> void:
	var v1 := _view()
	var w1 := _world_of(v1)
	v1.free()
	assert_eq(Map3DWorldCache.held(), FIXTURE)
	assert_false(Map3DWorldCache.lent())
	assert_true(is_instance_valid(w1), "kept, not freed")
	var v2 := _view()
	assert_true(is_same(_world_of(v2), w1), "re-parented, not reloaded")
	assert_true(Map3DWorldCache.lent())
	v2.free()


func test_a_second_live_view_gets_its_own_world() -> void:
	var v1 := _view()
	var v2 := _view()
	assert_false(is_same(_world_of(v1), _world_of(v2)), "never one world in two views")
	var w2 := _world_of(v2)
	v2.free()
	assert_false(is_instance_valid(w2), "the spare copy is dropped")
	assert_true(Map3DWorldCache.lent(), "v1 still holds the cached one")
	v1.free()


func test_another_pack_drops_the_old_world() -> void:
	var v1 := _view()
	var w1 := _world_of(v1)
	v1.free()
	var v2 := _view(OTHER)
	assert_false(is_instance_valid(w1), "one world at most")
	assert_eq(Map3DWorldCache.held(), OTHER)
	v2.free()
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement** — `scripts/map3d/map3d_world_cache.gd`:

```gdscript
class_name Map3DWorldCache
extends RefCounted
## One loaded 3D world kept between views (spec 2026-09-20 §3): a screen
## switch frees the view but hands its world back here, and the next view
## re-parents it instead of reloading 44 MB and recompiling the patched
## Terrain3D shader. At most ONE world, lent to one view at a time (Ruling
## 13): a second live view loads its own copy, with its own terrain material.

static var _path := ""
static var _world: Node3D = null
static var _lent := false


## The kept world for `scene_path`, now lent to the caller — or null (load it).
static func take(scene_path: String) -> Node3D:
	if _lent or _path != scene_path or _world == null or not is_instance_valid(_world):
		return null
	_lent = true
	return _world


## A freshly loaded world, lent to the view that loaded it — unless the kept
## one is lent elsewhere, in which case the fresh copy stays unkept.
static func adopt(scene_path: String, world: Node3D) -> void:
	if _lent:
		return
	_drop()
	_path = scene_path
	_world = world
	_lent = true


## A view is done with `world`: keep it detached, or drop it when it is not
## the kept one and the kept one is still lent.
static func give_back(scene_path: String, world: Node3D) -> void:
	if world == null or not is_instance_valid(world):
		return
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	if world == _world:
		_lent = false
		return
	if _lent:
		world.free()
		return
	_drop()
	_path = scene_path
	_world = world


static func clear() -> void:
	if not _lent:
		_drop()
	_path = ""
	_world = null
	_lent = false


static func held() -> String:
	return _path


static func lent() -> bool:
	return _lent


static func _drop() -> void:
	if _world != null and is_instance_valid(_world) and _world.get_parent() == null:
		_world.free()
	_world = null
```
  - View `_load`: `_world = Map3DWorldCache.take(_scene_path)`; `var fresh := _world == null`; if fresh, the status + `Map3DWorldLoader.instance` path from Task 15, then `Map3DWorldCache.adopt(_scene_path, _world)`. Add:

```gdscript
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _world != null:
		Map3DWorldCache.give_back(_scene_path, _world)
		_world = null
```
  - `Map3DLayerThemes.prepare`: when `Map3DGroundTint.is_patched(shader.code)`, skip the `shader.code = patched` rewrite (the kept world's material is already this view's own). Still set `_tint_mat` and the parameters.
  - `GameRoot._exit_tree()` (add it, or extend an existing one): `Map3DWorldCache.clear()`.
  - `tests/post_run.gd`: `extends GutHookScript` with `func run() -> void: Map3DWorldCache.clear()`. In `run_tests.sh`, add `-gpost_run_script=res://tests/post_run.gd` beside `-gpre_run_script`.
- [ ] **Step 4: Run** the cache test (3 passed), the folder, `./run_tests.sh` (still "Errors 2").
- [ ] **Step 5: The real world** — switch screens in the game several times and time it: add `print("map3d load %d ms" % …)` to a scratch copy of the bench around `_switch_to(COURT)` twice. Expected: the second switch shows no 44 MB load (well under the first). Take a MANORS snapshot after a switch (`tools/snapshot_screen.gd --screen court --layer manors`) and look at it with the visual-review skill: the ground must still be tinted.
- [ ] **Step 6: Commit** `perf(map3d): a screen switch re-parents the loaded world instead of reloading it`.

---
### Task 20: Baked rivers, roads and bridges

**Files:**
- Create: `scripts/map3d/map3d_layer_bake.gd`, `tools/map3d/bake_layers.gd`
- Modify: `scripts/map3d/map3d_layer_rivers.gd` (`static arrays_for`, `build_baked`; the material goes on `material_override`), `scripts/map3d/map3d_layer_roads.gd` (`static plan_for`, `static bridge_mesh`, `build_baked`), `scripts/map3d/map3d_layer_lines.gd` (`put_baked`), `scripts/map3d/map3d_view.gd` (`_load` prefers a matching bake), `tools/map3d/build_pack.sh` (the fourth step), `tools/map3d/README.md`
- Test: `tests/map3d/test_map3d_layer_bake.gd`

**Interfaces:**
- `class_name Map3DLayerBake extends RefCounted`: `const FORMAT := 1`, `const LAYERS := ["rivers", "roads", "trails", "bridges"]`, `const KEYS: Array` (the balance keys the geometry depends on: `map3d_road_step_m`, `map3d_river_mesh_step_m`, `map3d_river_split_rise_m`, `map3d_river_terrain_clear_m`, `map3d_river_end_fade_m`, `map3d_road_width_m`, `map3d_trail_width_m`, `map_route_smoothing_steps`, and every `map3d_bridge_*` key but `map3d_bridge_max_view_m`), `static func step_set(row: Dictionary) -> String`, `static func key(repo: DataRepository, scene_dir: String, row: Dictionary) -> String`, `static func file(scene_dir: String, layer: String, row: Dictionary) -> String`, `static func complete(scene_dir: String, row: Dictionary, bake_key: String) -> bool`, `static func load_all(scene_dir: String, row: Dictionary) -> Dictionary`, `static func save(scene_dir: String, row: Dictionary, bake_key: String, meshes: Dictionary) -> Error`, `static func mesh_of(arrays: Array) -> ArrayMesh`.
- `Map3DLayerRivers.arrays_for(ctx: Map3DContext, scene_dir: String) -> Dictionary` → `{arrays: Array, courses: Array}`; `build_baked(p_ctx: Map3DContext, baked: ArrayMesh) -> void`.
- `Map3DLayerRoads.plan_for(ctx: Map3DContext, courses: Array) -> Dictionary` → `{"Roads": Array, "Trails": Array, "bridges": Array}`; `bridge_mesh(ctx: Map3DContext, list: Array) -> ArrayMesh` (its meta `"bridges"` = the list); `build_baked(meshes: Dictionary) -> void`.
- `Map3DLayerLines.put_baked(line_name: String, mesh: ArrayMesh, mat: ShaderMaterial) -> void`.

**Risk:** a stale bake drawn over a changed input. The key covers the balance keys, `rivers.json`, the pack's `routes.csv`, the world's `built_at` and the step set. The set is used all or nothing (`complete`). **Catch:** the tests below (a changed bridge key rejects the bake), plus the bench on the real build before and after.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_layer_bake.gd`:

```gdscript
extends GutTest
## Static layers baked by the build (spec 2026-09-20 §2): rivers, roads,
## trails and bridges never move, so tools/map3d/bake_layers.gd saves their
## meshes per step set; the view uses them only when every input matches.

const DIR := "user://bake_fixture"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_each() -> void:
	Game.start_campaign(42)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/layers"))
	var root := Node3D.new()
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, DIR + "/world.tscn")
	root.free()
	var f := FileAccess.open(DIR + "/rivers.json", FileAccess.WRITE)
	f.store_string('{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [500, 0, 9, 40, 1]]}]}')
	f.close()


func after_each() -> void:
	Map3DWorldCache.clear()
	var abs := ProjectSettings.globalize_path(DIR)
	for f: String in DirAccess.get_files_at(abs + "/layers"):
		DirAccess.remove_absolute(abs + "/layers/" + f)
	for f: String in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs + "/" + f)


func _bake() -> void:
	var ctx := Map3DContext.new(Game.data, WORLD)
	var row := Map3DQuality.row(Game.data, "high")
	ctx.quality = row
	var rv := Map3DLayerRivers.arrays_for(ctx, DIR)
	var rd := Map3DLayerRoads.plan_for(ctx, rv["courses"])
	var meshes := {"rivers": Map3DLayerBake.mesh_of(rv["arrays"]),
		"roads": Map3DLayerBake.mesh_of(rd["Roads"]), "trails": Map3DLayerBake.mesh_of(rd["Trails"]),
		"bridges": Map3DLayerRoads.bridge_mesh(ctx, rd["bridges"])}
	assert_eq(Map3DLayerBake.save(DIR, row, Map3DLayerBake.key(Game.data, DIR, row), meshes), OK)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, DIR + "/world.tscn")
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_step_sets() -> void:
	assert_eq(Map3DLayerBake.step_set(Map3DQuality.row(Game.data, "high")), "r100_v100")
	assert_eq(Map3DLayerBake.step_set(Map3DQuality.row(Game.data, "medium")), "r140_v150")
	assert_eq(Map3DLayerBake.step_set(Map3DQuality.row(Game.data, "low")), "r200_v250")


func test_the_key_follows_its_inputs() -> void:
	var row := Map3DQuality.row(Game.data, "high")
	var k1 := Map3DLayerBake.key(Game.data, DIR, row)
	assert_eq(Map3DLayerBake.key(Game.data, DIR, row), k1, "stable")
	var was := Game.data.balance["map3d_bridge_abut_m"]
	Game.data.balance["map3d_bridge_abut_m"] = float(was) + 1.0
	assert_ne(Map3DLayerBake.key(Game.data, DIR, row), k1)
	Game.data.balance["map3d_bridge_abut_m"] = was
	assert_ne(Map3DLayerBake.key(Game.data, DIR, Map3DQuality.row(Game.data, "low")), k1)


func test_a_view_uses_a_matching_bake() -> void:
	_bake()
	var v := _view()
	var rivers := v.viewport().get_node("Rivers") as MeshInstance3D
	assert_true(rivers.mesh.resource_path.ends_with(".res"), "the baked rivers")
	assert_eq(rivers.material_override, v.river_material())
	assert_true(v.line_mesh("Roads").resource_path.ends_with(".res"), "the baked roads")


func test_a_stale_bake_is_ignored() -> void:
	_bake()
	var was := Game.data.balance["map3d_bridge_abut_m"]
	Game.data.balance["map3d_bridge_abut_m"] = float(was) + 1.0
	var v := _view()
	var rivers := v.viewport().get_node("Rivers") as MeshInstance3D
	assert_eq(rivers.mesh.resource_path, "", "built at runtime")
	Game.data.balance["map3d_bridge_abut_m"] = was
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement** — `scripts/map3d/map3d_layer_bake.gd`:

```gdscript
class_name Map3DLayerBake
extends RefCounted
## The build's baked static layers (spec 2026-09-20 §2): rivers, roads,
## trails and bridges never move, so tools/map3d/bake_layers.gd saves their
## ArrayMeshes beside the world, one set per distinct step set of
## data/graphics_quality.csv (Ruling 14), with layers/manifest.json naming the
## key each was baked under. The runtime uses a set only when it is complete
## and its key matches every input today; otherwise it builds as before.

const FORMAT := 1
const LAYERS := ["rivers", "roads", "trails", "bridges"]
const KEYS := ["map3d_road_step_m", "map3d_river_mesh_step_m", "map3d_river_split_rise_m",
	"map3d_river_terrain_clear_m", "map3d_river_end_fade_m", "map3d_road_width_m",
	"map3d_trail_width_m", "map_route_smoothing_steps", "map3d_bridge_abut_m",
	"map3d_bridge_clear_m", "map3d_bridge_clear_per_width", "map3d_bridge_hump_m",
	"map3d_bridge_min_sin", "map3d_bridge_merge_m", "map3d_bridge_deck_step_m",
	"map3d_bridge_deck_m", "map3d_bridge_extra_w_m", "map3d_bridge_parapet_h_m",
	"map3d_bridge_parapet_w_m", "map3d_bridge_arch_max_m", "map3d_bridge_pier_m",
	"map3d_bridge_tile_m", "map3d_bridge_end_over_water_m"]


static func step_set(row: Dictionary) -> String:
	return "r%d_v%d" % [roundi(Map3DQuality.num(row, "road_step_mul") * 100.0),
		roundi(Map3DQuality.num(row, "river_step_mul") * 100.0)]


static func key(repo: DataRepository, scene_dir: String, row: Dictionary) -> String:
	var parts: Array = [FORMAT, step_set(row)]
	for k: String in KEYS:
		parts.append(repo.bal(k))
	parts.append(FileAccess.get_md5(scene_dir.path_join("rivers.json")))
	var data_dir := String((repo.maps.get(repo.map_id, {}) as Dictionary).get("data_dir", ""))
	parts.append(FileAccess.get_md5(data_dir.path_join("geography/routes.csv")))
	var built := ""
	var man := scene_dir.path_join("manifest.json")
	if FileAccess.file_exists(man):
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(man))
		if m is Dictionary:
			built = String((m as Dictionary).get("built_at", ""))
	parts.append(built)
	return var_to_str(parts).md5_text()


static func file(scene_dir: String, layer: String, row: Dictionary) -> String:
	return scene_dir.path_join("layers/%s_%s.res" % [layer, step_set(row)])


static func _manifest(scene_dir: String) -> Dictionary:
	var path := scene_dir.path_join("layers/manifest.json")
	if not FileAccess.file_exists(path):
		return {}
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return m if m is Dictionary else {}


static func complete(scene_dir: String, row: Dictionary, bake_key: String) -> bool:
	if String(_manifest(scene_dir).get(step_set(row), "")) != bake_key:
		return false
	for layer: String in LAYERS:
		if not ResourceLoader.exists(file(scene_dir, layer, row)):
			return false
	return true


static func load_all(scene_dir: String, row: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for layer: String in LAYERS:
		out[layer] = load(file(scene_dir, layer, row)) as ArrayMesh
	return out


static func save(scene_dir: String, row: Dictionary, bake_key: String, meshes: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scene_dir.path_join("layers")))
	for layer: String in LAYERS:
		var mesh: ArrayMesh = meshes.get(layer, ArrayMesh.new())
		var err := ResourceSaver.save(mesh, file(scene_dir, layer, row))
		if err != OK:
			return err
	var m := _manifest(scene_dir)
	m[step_set(row)] = bake_key
	var f := FileAccess.open(scene_dir.path_join("layers/manifest.json"), FileAccess.WRITE)
	if f == null:
		return ERR_CANT_OPEN
	f.store_string(JSON.stringify(m, "  "))
	f.close()
	return OK


static func mesh_of(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not arrays.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
```
  - Split the builders so the tool and the runtime share them. `Map3DLayerRivers.arrays_for(ctx, scene_dir)` is `build`'s parse + `clear_terrain` + `ribbon_arrays` part, returning both. `build` calls it, then `mesh = Map3DLayerBake.mesh_of(arrays)` when non-empty, and the material is set as `material_override = _mat` in place of `surface_set_material` (the test seam `river_material()` is unchanged). `build_baked(ctx, baked)`: same material, `mesh = baked if baked.get_surface_count() > 0 else null`, `_courses = []`. `Map3DLayerRoads.plan_for(ctx, courses)` is `build`'s loop without `_set_road`: it returns the two groups' ribbon arrays (`Map3DBorders.ribbon_arrays(plan.lines, ctx.height_at, plan.heights)`) and every bridge with its `deck_w`. `bridge_mesh(ctx, list)` is `_build_bridges`' mesh part, with `mesh.set_meta("bridges", list)`. `build(courses)` = `plan_for` → `_set_road` ×2 (arrays already made) → `_place_bridges(bridge_mesh(...))`. `build_baked(meshes)`: `lines.put_baked("Roads", meshes["roads"], road_mat)`, the same for Trails, then `_place_bridges(meshes["bridges"])`, and `_bridges = meshes["bridges"].get_meta("bridges", [])`. `_place_bridges(mesh)` puts the mesh and the stone material (as `material_override`) on the `Bridges` node, or clears it when the mesh has no surface.
  - `Map3DLayerLines.put_baked(line_name, mesh, mat)`: `put_mesh`'s node code with `mi.mesh = mesh; mi.material_override = mat` (the loaded resource is shared, so it is never edited), nothing when `mesh.get_surface_count() == 0`. `line_mesh` returns `mi.mesh`, and `apply_scale` already reads the override first (Task 17).
  - View `_load`, in place of the rivers/roads build: `var dir := _scene_path.get_base_dir(); var bk := Map3DLayerBake.key(_repo, dir, _ctx.q())`; if `Map3DLayerBake.complete(dir, _ctx.q(), bk)`, `var m := Map3DLayerBake.load_all(dir, _ctx.q()); _rivers.build_baked(_ctx, m["rivers"]); _roads.build_baked(m)`; else `_rivers.build(_ctx, _scene_path); _roads.build(_rivers.courses())`.
  - `tools/map3d/bake_layers.gd`:

```gdscript
extends SceneTree
## Bake the 3D map's static layers (spec 2026-09-20 §2) — rivers, roads,
## trails, bridges — for every distinct step set in data/graphics_quality.csv,
## into <map3d_dir>/layers/. Run after build_world.gd (build_pack.sh does):
##   GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/bake_layers.gd [-- --map ID]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var repo := DataRepository.load_all("res://data")
	if repo == null:
		push_error("bake_layers: data failed to load: " + DataRepository.last_error)
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var at := args.find("--map")
	if at >= 0 and at + 1 < args.size() and not repo.load_map(args[at + 1]):
		push_error("bake_layers: no pack " + args[at + 1])
		quit(1)
		return
	var dir := repo.map3d_dir()
	var world := Map3DWorldLoader.instance(dir.path_join("world.tscn"))
	if world == null:
		push_error("bake_layers: no world at " + dir)
		quit(1)
		return
	root.add_child(world)
	await process_frame  # Terrain3D's data only exists in the tree
	var ctx := Map3DContext.new(repo, world.get_meta("map3d_world"), world)
	var done: Dictionary = {}
	for tier: String in Map3DQuality.TIERS:
		var row := Map3DQuality.row(repo, tier)
		var set_name := Map3DLayerBake.step_set(row)
		if done.has(set_name):
			continue
		done[set_name] = true
		ctx.quality = row
		var rv := Map3DLayerRivers.arrays_for(ctx, dir)
		var rd := Map3DLayerRoads.plan_for(ctx, rv["courses"])
		var meshes := {"rivers": Map3DLayerBake.mesh_of(rv["arrays"]),
			"roads": Map3DLayerBake.mesh_of(rd["Roads"]), "trails": Map3DLayerBake.mesh_of(rd["Trails"]),
			"bridges": Map3DLayerRoads.bridge_mesh(ctx, rd["bridges"])}
		var err := Map3DLayerBake.save(dir, row, Map3DLayerBake.key(repo, dir, row), meshes)
		print("bake_layers: %s %s" % [set_name, "ok" if err == OK else "err %d" % err])
	world.queue_free()
	await process_frame
	quit(0)
```
  - `build_pack.sh`: after `build_world.gd`, run `"$GODOT" --headless --path . -s tools/map3d/bake_layers.gd` (with `-- --map "$MAP"` when given). README: a "Baked layers" section.
- [ ] **Step 4: Run** the bake test (4 passed), the folder, `./run_tests.sh`. Then `tools/map3d/build_pack.sh` on the real pack and the bench at 3024×1964 (expected: the same frame times; a faster first load). Time the view's `_load` with and without `layers/` in a scratch script and put both numbers in the commit.
- [ ] **Step 5: Commit** `perf(map3d): the build bakes rivers, roads and bridges; the view uses them when every input matches`.

---

### Task 21: The look as `.tres` assets, with committed preview textures

**Files:**
- Create: `tools/map3d/make_previews.gd`; `assets/map3d_preview/rocky_trail_02_alb_ht.png`, `rocky_trail_02_nrm_rgh.png`, `medieval_blocks_03_alb_ht.png`, `medieval_blocks_03_nrm_rgh.png`, `cloud_shape.png` (512 px, with their `.import`); `scenes/map3d/materials/border_line.tres`, `road_line.tres`, `bridge_stone.tres`, `water_ripples.tres`, `water_river.tres`, `water_sea.tres`, `cloud_deck.tres`, `cloud_shadow.tres`, `settlement_ring.tres`, `selection_ring.tres`
- Modify: `map3d_layer_lines.gd`, `map3d_layer_roads.gd`, `map3d_layer_rivers.gd`, `map3d_layer_sea.gd`, `map3d_layer_clouds.gd`, `map3d_layer_settlements.gd`, `map3d_context.gd` (`water_normals` from the `.tres`), `scenes/map3d/world_map_3d.tscn` (the authored layers wear their materials, so the editor shows them)
- Test: `tests/map3d/test_map3d_look_assets.gd`

**Interfaces:**
- Each layer loads its `.tres` with `preload` and `duplicate()`s it per view (so no two views share a runtime-parameterised material), then binds every tuned number from CSV exactly as before. A full-resolution texture replaces the preview when `assets/map3d/textures/<name>_alb_ht.png` exists (`Map3DLayerRoads.texture_pair`); otherwise the preview stays (Ruling 15).
- `Map3DContext.water_normals()` = `(load("res://scenes/map3d/materials/water_ripples.tres") as NoiseTexture2D).duplicate(true)` with `noise.seed = int(repo.bal("map3d_water_seed"))`. The generator settings (frequency 0.03, 3 octaves, 256 px, bump 6) move into the `.tres` (Ruling 11's reasoning: they were code literals, and a `.tres` is data).

**Risk:** a `.tres` changing a number the CSV owned, and the Compatibility traps (the cloud shaders must be two files; raw colour uniforms). **Catch:** the test below reads each material's shader and checks that the CSV numbers still land (`test_the_seas_band_colours_go_in_raw`, `test_the_rivers_colours_go_in_raw` and the render-priority test keep running). The look is compared against a snapshot with the visual-review skill.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_look_assets.gd`:

```gdscript
extends GutTest
## The 3D map's look as editor-visible assets (spec 2026-09-20 §2): each
## material a .tres holding its shader, textures and render priority — never
## a tuned number, which stays in data/*.csv and is bound at load — with
## committed 512 px preview textures for a checkout without the git-ignored
## full-resolution ones.

const MATERIALS := {
	"border_line": "res://scripts/map3d/border_line.gdshader",
	"road_line": "res://scripts/map3d/road_line.gdshader",
	"water_river": "res://scripts/map3d/water_river.gdshader",
	"water_sea": "res://scripts/map3d/water_sea.gdshader",
	"cloud_deck": "res://scripts/map3d/cloud_deck.gdshader",
	"cloud_shadow": "res://scripts/map3d/cloud_shadow.gdshader",
	"settlement_ring": "res://scripts/map3d/settlement_ring.gdshader",
	"selection_ring": "res://scripts/map3d/settlement_ring.gdshader",
}
const PREVIEWS := ["rocky_trail_02_alb_ht", "rocky_trail_02_nrm_rgh", "medieval_blocks_03_alb_ht",
	"medieval_blocks_03_nrm_rgh", "cloud_shape"]


func test_each_material_is_its_shader() -> void:
	for name: String in MATERIALS:
		var mat := load("res://scenes/map3d/materials/%s.tres" % name) as ShaderMaterial
		assert_not_null(mat, name)
		assert_eq(mat.shader.resource_path, MATERIALS[name], name)
	assert_ne((load("res://scenes/map3d/materials/cloud_deck.tres") as ShaderMaterial).shader,
		(load("res://scenes/map3d/materials/cloud_shadow.tres") as ShaderMaterial).shader,
		"two cloud shaders, never one (the Compatibility alpha-scissor trap)")
	assert_true(load("res://scenes/map3d/materials/bridge_stone.tres") is StandardMaterial3D)


func test_the_previews_are_committed_and_small() -> void:
	for name: String in PREVIEWS:
		var tex := load("res://assets/map3d_preview/%s.png" % name) as Texture2D
		assert_not_null(tex, name)
		assert_lte(maxi(tex.get_width(), tex.get_height()), 512, name)


func test_the_road_material_carries_textures_but_no_tuned_number() -> void:
	var text := FileAccess.get_file_as_string("res://scenes/map3d/materials/road_line.tres")
	assert_true(text.contains("map3d_preview/rocky_trail_02_alb_ht.png"))
	for tuned: String in ["tile_m", "width_m", "near_mpp", "far_mpp", "fray", "colour"]:
		assert_false(text.contains("shader_parameter/" + tuned), tuned + " is CSV's")


func test_a_views_materials_are_its_own_copies() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.set_meta("map3d_world", {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
		"pack_px": [2560, 929], "sea_y": 5.0})
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "user://test_map3d_look_world.tscn")
	root.free()
	var a := Map3DView.create(Game.data, "user://test_map3d_look_world.tscn")
	var b := Map3DView.create(Game.data, "user://test_map3d_look_world.tscn")
	for v: Map3DView in [a, b]:
		v.size = Vector2(800, 450)
		add_child_autofree(v)
		v.activate()
	assert_ne(a.sea_material(), b.sea_material())
	assert_eq(a.sea_material().shader, b.sea_material().shader, "one compiled shader")
	var road := a.line_mesh("Roads").surface_get_material(0) as ShaderMaterial
	assert_eq(road.get_shader_parameter("tile_m"), Game.data.bal("map3d_road_tile_m"))
	assert_not_null(road.get_shader_parameter("surface"), "a texture always: full or preview")
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Previews** — `tools/map3d/make_previews.gd` (`extends SceneTree`). For each of the four packed PNGs in `res://assets/map3d/textures/`: `Image.load_from_file(ProjectSettings.globalize_path(src))`, `img.resize(512, 512, Image.INTERPOLATE_LANCZOS)`, `img.save_png(ProjectSettings.globalize_path("res://assets/map3d_preview/<name>.png"))`. Then `CloudLayer.cloud_texture(int(repo.bal("map3d_cloud_seed"))).get_image()` (repo from `DataRepository.load_all("res://data")`) resized to at most 512 and saved as `cloud_shape.png`; quit. Run it (`GDAI_MCP_SERVER_PORT=3999 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/map3d/make_previews.gd`), then `--import`. The previews take the project's default import (lossless, mipmaps on via `[importer_defaults]`), which is enough at 512 px.
- [ ] **Step 4: The `.tres` files through the gdai MCP** — `execute_editor_script` builds and saves each: a `ShaderMaterial` with `shader = load(<shader>)`, `render_priority` from `Map3DPriority` (border_line 0, bound per line at runtime; road_line `ROADS`; water_river `RIVERS`; water_sea `SEA`; cloud_deck `CLOUDS`; cloud_shadow 0; settlement_ring `RING_BASE`; selection_ring `RING_BASE`), and only these textures: road_line `surface` / `surface_nrm` = the rocky_trail previews plus `has_surface = true`; water_river and water_sea `ripples` = `water_ripples.tres`; cloud_deck and cloud_shadow `shape` = `cloud_shape.png`. `water_ripples.tres` is a `NoiseTexture2D` (256 × 256, seamless, as_normal_map, bump_strength 6, generate_mipmaps) over a `FastNoiseLite` (frequency 0.03, fractal_octaves 3). `bridge_stone.tres` is a `StandardMaterial3D` with `cull_mode` DISABLED, `roughness` 0.9, `albedo_texture` / `normal_enabled` / `normal_texture` = the medieval_blocks previews, `texture_filter` LINEAR_WITH_MIPMAPS_ANISOTROPIC, `distance_fade_mode` PIXEL_DITHER. Save each with `ResourceSaver.save(res, "res://scenes/map3d/materials/<name>.tres")`. Then `open_scene` the view scene and `update_property`: `Viewport/Rivers` `material_override` = `water_river.tres`, `Viewport/Sea` `material_override` = `water_sea.tres`, `Viewport/Clouds` `material_override` = `cloud_deck.tres`, `Viewport/Clouds/Shadows` `material_override` = `cloud_shadow.tres`, `Viewport/Bridges` `material_override` = `bridge_stone.tres`. Check with `get_scene_file_content` and `get_godot_errors`. Fallback: run the same code as a headless `-s` script, and add the five `material_override = ExtResource(...)` lines (with their `[ext_resource]` entries) to the `.tscn` by hand.
- [ ] **Step 5: Layers use them** — every `ShaderMaterial.new(); mat.shader = X_SHADER` becomes `var mat := (X_MAT as ShaderMaterial).duplicate() as ShaderMaterial` with `const X_MAT := preload("res://scenes/map3d/materials/<name>.tres")`, and the CSV binding lines stay exactly as they are. `Map3DLayerRoads._set_road`: when `texture_pair(ROAD_TEXTURE)` is non-empty, set `surface` / `surface_nrm` to the full ones; else keep the preview (`has_surface` stays true). The same for the bridge's `albedo_texture` / `normal_texture`. Clouds: `shape` is still set at runtime from `CloudLayer.cloud_texture(seed)` (the preview is the editor's). `Map3DContext.water_normals()` as in Interfaces. The now-unused `*_SHADER` preload constants are deleted.
- [ ] **Step 6: Run** the look test (4 passed), the folder, `./run_tests.sh`, and the bench. Snapshot the court on the real build (`tools/snapshot_screen.gd --screen court`), before (from Task 20's commit) and after, and compare them with the visual-review skill: expected identical, since full textures are present on the dev machine.
- [ ] **Step 7: Commit** — `git add tools/map3d/make_previews.gd assets/map3d_preview scenes/map3d/materials scenes/map3d/world_map_3d.tscn scripts/map3d/map3d_layer_lines.gd scripts/map3d/map3d_layer_roads.gd scripts/map3d/map3d_layer_rivers.gd scripts/map3d/map3d_layer_sea.gd scripts/map3d/map3d_layer_clouds.gd scripts/map3d/map3d_layer_settlements.gd scripts/map3d/map3d_context.gd tests/map3d/test_map3d_look_assets.gd`, then commit `feat(map3d): the look is .tres assets with committed previews; numbers stay in CSV`.

---

### Task 22: `@tool` previews — the editor shows the real picture

**Files:**
- Create: `scripts/map3d/map3d_preview.gd`
- Modify: `map3d_view.gd`, `map3d_camera_rig.gd`, `map3d_layer_sea.gd`, `map3d_layer_rivers.gd`, `map3d_layer_lines.gd`, `map3d_layer_clouds.gd`, `map3d_layer_settlements.gd` (each gets `@tool`, an editor guard, and `@export var preview := false`; the view gets `@export var preview_pack := ""` and `@export var preview_terrain := false`)
- Test: `tests/map3d/test_map3d_preview.gd`

**Interfaces:**
- `class_name Map3DPreview extends RefCounted`: `static func repo(pack_id: String) -> DataRepository` (cached; `DataRepository.load_all("res://data")`, then `load_map` when `pack_id != ""`), `static func meta_for(scene_dir: String) -> Dictionary` (the manifest's `meta`, else `Map3DWorldLoader.scene_meta`, else `{}`), `static func context(pack_id: String, with_terrain: bool = false) -> Map3DContext` (state = `GameState.new()`, the tier `high`; the world instanced only when `with_terrain`), `static func placeholder(mat: Material) -> Mesh` (a 4 km `PlaneMesh` in the layer's material, for a pack with no build).
- Every layer node: `@export var preview := false: set = set_preview` and `func preview_build(p_ctx: Map3DContext) -> void`, which builds the layer as at runtime and adds its children with no `owner`. `set_preview(on)` works only when `Engine.is_editor_hint()`: on builds from `Map3DPreview.context(root.preview_pack, root.preview_terrain)`, off frees the preview children and clears the mesh.

**Risk:** `@tool` code running in the editor. `_ready`, `_process` and `_gui_input` must do nothing there (a guard `if Engine.is_editor_hint(): return` at the top of each). Nothing may touch `Game` (the HUD stays non-tool, Ruling 9). Nothing generated may be saved (no `owner`). The terrain loads only behind `preview_terrain`. A non-tool script's instance in the editor is a placeholder, so every script a preview calls through a node must be `@tool` too. The static helpers (`Map3DGeometry`, `Map3DBorders`, `Map3DRivers`, `Map3DBridges`, `Map3DQuality`, `MapPalette`) are called statically, which works from tool code. **Catch:** the tests below (no owner, no Game, a placeholder with no build), `test_map3d_scene.gd::test_nothing_generated_is_saved_in_the_scene`, and an editor check through the MCP.

- [ ] **Step 1: Failing test** — `tests/map3d/test_map3d_preview.gd`:

```gdscript
extends GutTest
## Editor previews (spec 2026-09-20 §2): each layer node is @tool with a
## `preview` switch that loads the repo itself (no autoload), builds the
## layer as the game would, and adds its children WITHOUT an owner, so
## nothing generated is ever saved into the scene.

func test_a_preview_context_needs_no_game() -> void:
	var ctx := Map3DPreview.context("")
	assert_not_null(ctx.repo)
	assert_not_null(ctx.state(), "a blank state, not Game.state")
	assert_false(is_same(ctx.state(), Game.state))
	assert_eq(ctx.q(), Map3DQuality.row(ctx.repo, "high"))


func test_no_build_means_no_meta_and_a_placeholder() -> void:
	assert_eq(Map3DPreview.meta_for("user://no_such_build"), {})
	var mesh := Map3DPreview.placeholder(StandardMaterial3D.new())
	assert_not_null(mesh)


func test_the_borders_draw_from_a_blank_state() -> void:
	var ctx := Map3DPreview.context("")
	if ctx.meta.is_empty():
		ctx.meta = {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
			"pack_px": [2560, 929], "sea_y": 5.0}
	var code: String = ctx.repo.kingdoms.keys()[0]
	assert_gt(Map3DBorders.kingdom_lines(ctx.repo, ctx.state(), ctx.meta, code, ctx.line_step()).size(), 0)


func test_preview_children_have_no_owner() -> void:
	var ctx := Map3DPreview.context("")
	if ctx.meta.is_empty():
		ctx.meta = {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
			"pack_px": [2560, 929], "sea_y": 5.0}
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 450)
	add_child_autofree(vp)
	ctx.viewport = vp
	var lines := Map3DLayerLines.new()
	vp.add_child(lines)
	lines.preview_build(ctx)
	assert_gt(lines.get_child_count(), 0, "the kingdom border and the seams, previewed")
	for c: Node in lines.get_children():
		assert_null(c.owner, String(c.name) + " is never saved")
	var markers := Map3DLayerSettlements.new()
	vp.add_child(markers)
	markers.preview_build(ctx)
	for c: Node in markers.get_children():
		assert_null(c.owner)


func test_no_layer_script_reads_game() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if f.begins_with("map3d_layer") or f == "map3d_camera_rig.gd" or f == "map3d_preview.gd":
			assert_false(FileAccess.get_file_as_string("res://scripts/map3d/" + f).contains("Game."), f)
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement.**
  - `scripts/map3d/map3d_preview.gd` as in Interfaces. `context(pack_id, with_terrain)`: `var r := repo(pack_id); var dir := r.map3d_dir(); var meta := meta_for(dir); var world: Node3D = Map3DWorldLoader.instance(dir.path_join("world.tscn")) if with_terrain else null; var ctx := Map3DContext.new(r, meta, world); var blank := GameState.new(); ctx.state_fn = func() -> GameState: return blank; ctx.quality = Map3DQuality.row(r, "high"); return ctx`. `repo()` caches one `DataRepository` per pack id in a static Dictionary.
  - `preview_build(ctx)` on each layer: Lines builds the kingdom band, halo, ink and seams through a `Map3DLayerBorders` bound to itself, and the roads through `Map3DLayerRoads` (the Bridges node is its parent's sibling, so a Lines preview gets roads only). Settlements run `bind(ctx); build()`. Rivers run `build(ctx, dir.path_join("world.tscn"))`. Sea runs `build(ctx)`. Clouds run `build(ctx)` then one `step(0.1)` with a context whose `clock_fn` returns 1. The rig does `bind(ctx)` and `place(bounds.get_center(), bal("map3d_zoom_start_m"), 0)` with `make_current` skipped in the editor. Nodes are made the same way at runtime, and none gets an `owner` (runtime nodes never had one). With `ctx.meta` empty (no build), `preview_build` puts `Map3DPreview.placeholder(<the layer's .tres>)` on the layer instead (editor only).
  - The view root: `@tool`; `_ready`, `_process`, `_gui_input` and `_notification` return at once when `Engine.is_editor_hint()` (in `_ready`, after `_display.texture = _viewport.get_texture()`, so the editor's Display shows the SubViewport); `@export var preview_pack := ""`, `@export var preview_terrain := false`; in the editor the SubViewport's `render_target_update_mode` stays ALWAYS while any layer's `preview` is on.
- [ ] **Step 4: Run** the preview test (5 passed), the folder, `./run_tests.sh` ("Errors 2": a `@tool` script must not add parse errors headless).
- [ ] **Step 5: Check in the editor through the MCP** — `open_scene` `res://scenes/map3d/world_map_3d.tscn`; `update_property` `Viewport/Lines` `preview` = true; `get_editor_screenshot` (expected: the kingdom borders and seams in the viewport; on a machine without a build, the placeholder plane); `update_property` `Viewport/Markers` `preview` = true; `get_editor_screenshot`; `get_godot_errors` (expected: none new). Then set both back to false and `get_scene_file_content`: expected no `preview = true` and no generated mesh. The scene test enforces this as well.
- [ ] **Step 6: Commit** `feat(map3d): @tool previews — the editor shows the layers from the pack's data`.

---

### Task 23 (optional, last): A lite terrain build for the low tier

**Files:**
- Modify: `tools/map3d/bake_world.py` (`--vertex-m`, `--out-dir`), `tools/map3d/build_world.gd` and `build_terrain.gd` (`--lite` writes `<map3d_dir>/lite/`), `tools/map3d/build_pack.sh` (`--lite`), `scripts/map3d/map3d_world_loader.gd` (`variant_path`), `scripts/map3d/map3d_view.gd` (`_load` picks the variant), `data/graphics_quality.csv` (low `world` = `lite`), `tools/map3d/README.md`
- Test: `tests/map3d/test_map3d_loader.gd` (append)

**Interfaces:**
- `Map3DWorldLoader.variant_path(scene_path: String, world: String) -> String`: `scene_path.get_base_dir().path_join(world).path_join("world.tscn")` when `world != "full"` and that file exists, else `scene_path`.

**Risk:** a lite world whose `m_per_px` / `pack_origin` differ (they must not: only `vertex_m` changes, 40 m in place of 20, about ¼ of the memory). **Catch:** the test below, and the loader's `same_meta` check between the lite manifest and the scene.

- [ ] **Step 1: Failing test** — append to `tests/map3d/test_map3d_loader.gd`:

```gdscript
func test_a_lite_variant_is_used_only_when_built() -> void:
	var full := DIR + "/world.tscn"
	assert_eq(Map3DWorldLoader.variant_path(full, "lite"), full, "no lite build: the full one")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/lite"))
	var root := Node3D.new()
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, DIR + "/lite/world.tscn")
	root.free()
	assert_eq(Map3DWorldLoader.variant_path(full, "lite"), DIR + "/lite/world.tscn")
	assert_eq(Map3DWorldLoader.variant_path(full, "full"), full)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/lite/world.tscn"))
```

- [ ] **Step 2: Run it (fails).**
- [ ] **Step 3: Implement** — `variant_path` as in Interfaces. View `_load`: `var path := Map3DWorldLoader.variant_path(_scene_path, String(_ctx_row().get("world", "full")))`, where the tier row is resolved before the world loads. The world cache key is the resolved path. `bake_world.py`: `ap.add_argument("--vertex-m", type=float, default=VERTEX_M)` and `--out-dir` (default `<map3d_dir>/bake`); `FIELD_MAP_STEP` stays relative to vertices, so the lite fields map is 80 m a texel, and `Map3DLayerThemes.FIELD_MAP_M_PER_TEXEL` then becomes `vertex_m × 2`, read from `world.json` into the meta as `field_m_per_texel` with 40 as the fallback. `build_world.gd --lite` sets `BuildTerrain.variant = "lite"`, so `root()` returns `map3d_dir/lite`. `build_pack.sh --lite` runs `bake_world.py --vertex-m 40 --out-dir <dir>/lite/bake`, then `build_world.gd -- --lite`. `graphics_quality.csv` low `world` becomes `lite` only after a lite build has been benched (`--quality low`) and snapshotted with the visual-review skill.
- [ ] **Step 4: Run** the loader test, the folder, `./run_tests.sh`; build lite (`tools/map3d/build_pack.sh --lite`), then bench `--quality low --size 1920x1080` and compare against Task 18's low row. Look with the visual-review skill; the owner decides whether the low tier wears it.
- [ ] **Step 5: Commit** `feat(map3d): an optional lite terrain build for the low tier`.

---

## Self-review

### Spec coverage

| Spec section | Where |
|---|---|
| §0 Today: the 2,100-line view, ~19 jobs, per-move re-projection of 684 settlements, a world reloaded per screen | The file today (table); Tasks 1–12 (jobs out); Task 2 (per-pose list, ground once); Task 19 (the cache) |
| §1 Shape: one authored scene, class and API kept, ≤ ~250 lines per script, a 300–400-line root | Tasks 0 (API pinned), 3–12 (one script per job), 13 (the scene), 12 and 13 (`test_map3d_shape.gd`: view ≤ 450, others ≤ 300; Ruling note: the pre-existing pure helpers rivers 354 / bridges 318 are exempt) |
| §1 Node names kept (`Viewport`, `Markers/<Group>`, `Clouds`, `Rivers`, `Lines/<name>`, `Hud`) | Global Constraints; Task 0 `PATHS`; Tasks 4, 5, 7, 13 |
| §1 `Map3DContext` (repo, meta, camera, terrain, state, height, to_world/to_pack, project, ground_at, render_scale, viewport_px_scale, metres_per_pixel, quality, burg_ground, cell_ground, `camera_moved`) | Tasks 1, 2, 17 |
| §1 Layer scripts: WorldLoader, CameraRig, Input, Lines, Borders, Themes, Rivers, Sea, Roads, Settlements, Clouds, Picker, Selection; HUD Labels/Badges/Armies/Landmarks/Ruler | Tasks 14–15 (loader), 10, 3, 8, 9, 4, 6, 7, 5, 11, 12 (plus HeatLegend, ScaleBar, Backdrop, Needle) |
| §1 The view forwards every existing public call | Tasks 1–12 name each forwarder; Task 0 enforces it |
| §2 Editor authoring via the gdai MCP: tree, anchors, SubViewport flags, Display ViewportTexture, Notice, Tooltip StyleBox, Environment `.tres`, Sun, camera defaults, HUD children | Tasks 13 (tree, flags, Tooltip chip), 14 (Environment, Sun) |
| §2 Materials as `.tres` showing real textures (road, bridge, river, sea + NoiseTexture2D, cloud deck + shadow as two files, border line, rings) | Task 21 |
| §2 Ruling CSV vs inspector | Global Constraints; Task 21 test (`no tuned number` in road `.tres`); Ruling 11 |
| §2 Ruling git-ignored textures → committed 512 px previews, full-res swap | Task 21; Ruling 15 |
| §2 Runtime-generated content keeps a named node | Task 13 tree (Lines children, Markers, Clouds, Bridges) |
| §2 Rivers/roads/bridges baked to `.res` with a manifest hash; runtime prefers a matching bake | Task 20; Ruling 14 |
| §2 `@tool` layers with `preview`, `preview_pack`, repo via FileAccess, no owner, placeholder without a build | Task 22 |
| §3 Build holds data only + manifest (`format_version`, meta, built_at, steps hash); Sun/Environment/Sea leave the build; old builds and fixtures still load; framing cameras to `shoot.gd` | Tasks 14, 15; Ruling 12 |
| §3 `maps.csv` `map3d_dir` via DataRepository | Task 15 |
| §3 `build_pack.sh --map ID` | Tasks 15, 20 (bake_layers step), 23 (`--lite`) |
| §3 Notices missing / stale / bad; optional inputs warn once | Task 15 |
| §3 World cache keyed by scene path, cleared on a pack change, one patched material per world | Task 19; Ruling 13 |
| §4 `graphics_quality.csv` tiers with the table's values | Task 16 (Ruling 5: the steps as multipliers reproduce the table's metres, and a test holds it) |
| §4 `Map3DQuality` pure (`row`, `detect`), `settings.cfg graphics/quality`, a pause-menu option | Tasks 16, 17 |
| §4 Render scale through `ctx.viewport_px_scale()`, split from the design→window scale, round-trip tests | Tasks 1, 17; Ruling 3 |
| §4 CPU fixes: cached ground points, one projected list per pose, badges/counters skipped when off, the world cache | Tasks 2, 12 (pieces return [] when their layer is off, as today), 19 |
| §4 Bench `--quality`, `--render-scale`, draw calls and primitives, gates high ≤ 8 @ 3024×1964, medium ≤ 6 and low ≤ 4 @ 1920×1080; one real integrated-GPU run recommended | Tasks 0 (primitives, `--out`), 18 |
| §4 Optional lite build | Task 23 |
| §5 Order 0–14 | Tasks 0 · 1 · 2 · 3 · 4–9 · 10 · 11 · 12 · 13 · 14 · 15 · 16–18 · 19 · 20–22 · 23 |
| §6 Risks: private handlers and `line_mesh` null (Task 0), the render-scale split (17), a shared patched material (19), Compatibility traps (5, 21), `@tool` hazards (22), gdai stale scenes (Global Constraints, 13), `dual_scale_*` null (Ruling 16: out of scope, flagged) | as listed |

### Placeholder scan

Searched the plan for "TBD", "TODO", "handle edge cases", "similar to Task", "etc." and "…" inside code. Findings, each resolved:
- Task 0 Step 4: the commit message's `<WORST lines of the four runs>` is filled in at run time with the bench's printed values, not a gap in the plan.
- Task 13 Step 3b: `<TEXT_SOFT>` is a value read from `UiPalette` during the step, not a placeholder in the design. The step says how to read it.
- Task 14 Step 4: the Sun's transform literal is marked "print it headless and paste", with the exact expression given (`Basis.from_euler(...)`).
- Task 17: the anisotropy and Terrain3D mesh property names are guarded (`in` checks), with a stated verification step and fallback.
- Task 23 is marked optional by the spec, and the owner decides whether the low tier wears the lite build (a look decision, Step 3).
- No code block contains "…". Where prose uses "…", it abbreviates a command already given in full earlier in the same step (Task 18 Step 2).

### Type and name consistency

- `Map3DContext`: `viewport_px_scale()` is used by Lines (3), Rivers (4), Settlements (7), the HUD (12), the tier tests (17). `line_step()` / `road_step()` / `river_step()` are defined in Task 1 and multiplied in Task 17, and every layer reads them rather than `bal("map3d_*_step_m")`. `q()` is defined in Task 17 and used by Tasks 20 and 22. It is not called earlier: Tasks 1–16 use `quality.get("render_scale", 1.0)`, which Task 17 replaces.
- `Map3DPriority.*` is defined in Task 3 and used in Tasks 4–11 and 21; `Map3DView.PRIORITY_*` stay aliases, pinned by Task 0.
- `Map3DLineStyle.solid(colour, width_key, priority)` and `dashed(a, b, width_key, dash_key, gap_key, priority)` are used identically in Tasks 3, 8, 9, 11.
- `Map3DLayerLines`: `set_lines(name, lines, style)`, `put_mesh(name, arrays, mat)` (3), `put_baked(name, mesh, mat)` (20). `apply_scale` reads `material_override` first from Task 17 on, before Task 20 needs it.
- `Map3DLayerSettlements.marker_px` is static from Task 7. `Map3DContext.settlement_rects` switches to it in Task 7 (it used `Map3DView.marker_px` in Task 2, which still exists as a forwarder).
- `Map3DLayerRoads.bind(ctx, lines, viewport)` has the same signature from Task 6 on. Task 13 makes `_build_bridges` fill an existing `Bridges` node found through that viewport; Task 20 adds `plan_for`, `bridge_mesh` and `build_baked`.
- `Map3DWorldLoader`: `instance()` (14), `status()`, `notice_text()`, `scene_meta()`, `same_meta()`, `steps_hash()`, `warn_once()`, `clear_warnings()` (15), `variant_path()` (23). `FORMAT_VERSION := 2` is set in Task 14 and read by `build_world.gd` in Task 15.
- `Map3DQuality.num(row, key, fallback)` has the same signature in Tasks 16, 17, 18, 20. `Map3DQuality.forced` is set by `tests/pre_run.gd` (16) and the bench (18).
- The view's `component(key)` keys: `"roads"` (6), `"borders"` (8), `"themes"` (9), `"input"` and `"rig"` (10), `"picker"` and `"selection"` (11). This matches Ruling 18's list. An earlier draft also listed `"loader"`, which was dropped because `Map3DWorldLoader` is all static and has no instance to hand out.
- HUD piece names `Labels, Landmarks, HeatLegend, Badges, Armies, Backdrop, ScaleBar, Ruler, Compass, Needle` are the same in Task 12's test, Task 13's tree and its fallback `.tscn`, and Ruling 17.
- Test fixtures: every new test file writes its own `user://test_map3d_<name>_world.tscn`. The ones that need side files (`manifest.json`, `layers/`, `lite/`) work in their own `user://` subfolder (`loader_fixture`, `bake_fixture`), so no test's side file sits beside another test's fixture.
