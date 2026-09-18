# ECONOMY and MANORS on the 3D Map — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With ECONOMY or MANORS lit the map stays 3D: the ground wears each manor's colour (the 2D map's own palette), the cell edges are ruled in, and a click on land opens the manor card.

**Architecture:** The 2D map's manor colours move into a pure `ManorPalette` both maps call. The 3D view patches Terrain3D's generated shader at runtime (`Map3DGroundTint.patch`) so the terrain's own ALBEDO mixes toward a per-cell colour looked up from `world_cell_index.png` and a small LUT texture the view rebuilds when ownership or theme changes. Edges are one more constant-width ribbon layer; picking reads the same cell index.

**Tech Stack:** Godot 4.7 (GL Compatibility), typed GDScript, Terrain3D (addon), GUT.

**Spec:** `docs/superpowers/specs/2026-09-19-map3d-manor-themes-design.md`

## Global Constraints

- Typed GDScript; design values in CSVs (`balance.csv` `map3d_manor_tint`; edges reuse `manor_line` / `map_manor_line_alpha` / `map_manor_line_width`).
- No test may depend on the git-ignored built scene; the fixture world has no Terrain3D, so the patch is skipped there.
- `./run_tests.sh` green apart from failures already present on the branch before this work (currently `test_ui_rework.gd`'s opening narration, caused by another session's deleted `game_story/background/game_start.md`).
- Other sessions edit this checkout: stage only this plan's files (`git add <paths>`), never `-A`.
- Commit messages end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

---

### Task 1: `ManorPalette` — one palette for both maps

**Files:**
- Create: `scripts/engine/manor_palette.gd`, `tests/engine/test_manor_palette.gd`
- Modify: `scripts/ui/world_map_view.gd` (`cell_province`, `cell_owner`, `manor_color`, `_province_shaded`, `house_manor_color`, `working_manor_color`, `manor_edges` become wrappers)

**Interfaces — Produces:**
`ManorPalette.province(repo, state, cell) -> String`, `.owner(repo, state, cell) -> String`, `.manor_color(repo, state, cell) -> Color`, `.working_color(repo, state, cell) -> Color`, `.house_color(repo, state, cell) -> Color`, `.theme_color(repo, state, cell, theme: String) -> Color` (theme "economy" | "manors"; economy uses `working_color` when `MapEconomy.manors(repo).has(cell)`), `.edges(repo) -> PackedVector2Array` (cached per repo).

- [ ] **Step 1: Check the province source.** Headless one-off (scratchpad, not committed): for every land cell of the default pack compare `MapManors.province_of(repo, id)` with the 2D map's `province_at(MapTerrain.cell_center(...))`. 0 mismatches → `ManorPalette.province` is `MapManors.province_of`. Otherwise move the centre-pixel lookup (province index image, cached in a static per repo) into `ManorPalette.province`.
- [ ] **Step 2: Failing tests** in `tests/engine/test_manor_palette.gd`: for a crown land cell, a foreign cell and a water cell, each `ManorPalette` colour equals a fresh `WorldMapView`'s same-named method BEFORE the move (record the expected colours by computing them through the formula in the test: `MapPalette.color_of`, `MapEconomy.land_value`, `MapObjects.hash01`, `MapManors.province_shades`/`shade` with the balance keys, exactly as the current bodies); water/unheld → `Color(0,0,0,0)`; a conquest (`MapOwnership.set_owner`) changes `manor_color`; `theme_color(...,"manors") == house_color`; `edges` has an even count and no duplicate edge.
- [ ] **Step 3:** Run `-gtest=res://tests/engine/test_manor_palette.gd` → fails (no class).
- [ ] **Step 4:** Create `ManorPalette` by moving the bodies verbatim, replacing `Game.data`→`repo`, `Game.state`→`state`, `cell_owner(id)`→`owner(repo, state, id)`, `_province_shaded`→`_shaded(repo, state, cell, c)`. `WorldMapView` wrappers: `func manor_color(cell_id: int) -> Color: return ManorPalette.manor_color(Game.data, Game.state, cell_id)` (same for the others), `manor_mesh` calls `ManorPalette.theme_color`.
- [ ] **Step 5:** `import`, then run `test_manor_palette.gd` and `tests/ui/test_world_map_view.gd` → all pass.
- [ ] **Step 6:** Commit `scripts/engine/manor_palette.gd(.uid) tests/engine/test_manor_palette.gd(.uid) scripts/ui/world_map_view.gd` — "refactor(map): ManorPalette — the manor colours both maps share".

### Task 2: `Map3DGroundTint.patch`

**Files:** Create `scripts/map3d/map3d_ground_tint.gd`, `tests/map3d/test_map3d_ground_tint.gd`.

**Interfaces — Produces:** `Map3DGroundTint.ALBEDO_LINE := "ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;"`, `Map3DGroundTint.patch(code: String) -> String` ("" when the line is missing), `Map3DGroundTint.lut_size(max_id: int) -> Vector2i` (128 × ceil((max_id+1)/128)).

- [ ] **Step 1: Failing tests:** sample `"shader_type spatial;\nuniform float x;\nvoid fragment() {\n\t" + ALBEDO_LINE + "\n}\n"` → result contains `uniform highp sampler2D cell_index`, `uniform highp sampler2D cell_lut`, `uniform float tint_mix`, `uniform vec2 pack_origin`, `uniform float m_per_px`, `uniform ivec2 lut_size`, `texelFetch(cell_index`, and no longer the bare ALBEDO line; uniforms placed after the `shader_type`/`render_mode` lines; a sample without the line → `""`; `lut_size(4832) == Vector2i(128, 38)`; REAL code: `var t := Terrain3D.new(); add_child_autofree(t); t.material.shader_override_enabled = true; await wait_process_frames(1)` then `t.material.shader_override.code` contains `ALBEDO_LINE` and `patch()` of it is non-empty.
- [ ] **Step 2:** run → fails.
- [ ] **Step 3: Implement.** Uniform block inserted after the first line starting `render_mode` (else after `shader_type`). Replacement:

```glsl
vec3 base_albedo = mat.albedo_height.rgb * color_map.rgb * macrov;
ivec2 tint_px = ivec2(floor((v_vertex.xz - pack_origin) / m_per_px));
vec4 tint = vec4(0.0);
ivec2 index_size = textureSize(cell_index, 0);
if (tint_mix > 0.0 && tint_px.x >= 0 && tint_px.y >= 0 && tint_px.x < index_size.x && tint_px.y < index_size.y) {
	vec3 c = texelFetch(cell_index, tint_px, 0).rgb;
	int id = int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
	if (id < lut_size.x * lut_size.y) {
		tint = texelFetch(cell_lut, ivec2(id % lut_size.x, id / lut_size.x), 0);
	}
}
ALBEDO = mix(base_albedo, tint.rgb, tint_mix * tint.a);
```
(white water decodes to 65535, beyond the LUT → no tint.)
- [ ] **Step 4:** run → pass. **Step 5:** commit — "feat(map3d): Map3DGroundTint patches Terrain3D's shader for a per-cell tint".

### Task 3: The theme on the 3D view — tint, LUT, edges, the rule

**Files:** Modify `scripts/map3d/map3d_view.gd`, `scripts/ui/game_root.gd`, `scripts/ui/court_screen.gd`, `scripts/ui/conversation_scene.gd`, `data/balance.csv`; tests `tests/map3d/test_map3d_manor_themes.gd`, `tests/map3d/test_map3d_tab.gd`.

**Interfaces — Produces:** `Map3DView.set_theme(theme: String)`, `theme() -> String`, `cell_lut() -> ImageTexture` (test seam), `PRIORITY_MANOR_EDGES` (between ROADS and SEAMS; later rows shift up by one), screens' `set_map3d_theme(theme)`.

- [ ] **Step 1: Failing tests** (fixture world as in `test_map3d_hover.gd`): `set_theme("economy")` → `cell_lut()` texel for a crown land cell == `ManorPalette.theme_color(...,"economy")` (compare with `is_equal_approx` after 8-bit quantisation, tolerance 1/255), water cell texel alpha 0; `set_theme("manors")` → texel == `house_color`; conquest + `refresh_borders()` → the texel changes; `line_mesh("ManorEdges")` non-null and its MeshInstance visible under a theme, hidden with `set_theme("")`; priority order test in `test_map3d_view.gd` gains `PRIORITY_MANOR_EDGES` between ROADS and SEAMS. In `test_map3d_tab.gd`: economy/manors on → `r.map3d_view()` stays true and `screen.map3d_view().theme()` is the theme; heights/army on → 2D as before (split the existing loop).
- [ ] **Step 2:** run → fail.
- [ ] **Step 3: balance row** after `map3d_hover_border_width_px`: `map3d_manor_tint,0.8,"3D MAP ECONOMY/MANORS (owner 2026-09-19): how far the ground's albedo mixes toward its manor's colour (ManorPalette) under a theme — Map3DGroundTint; 0 without a theme"`.
- [ ] **Step 4: view.** In `_load` after the world is added: find the first `Terrain3D` (`_world.find_children("*", "Terrain3D", true, false)`); if found: `mat.shader_override_enabled = true`, read `mat.shader_override.code`, `patched := Map3DGroundTint.patch(code)`; empty → `mat.shader_override_enabled = false` + `push_warning`; else `mat.shader_override.code = patched`, keep `_tint_mat = mat` and set `cell_index` (texture from `load(_repo.cell_texture_path)` image → `ImageTexture.create_from_image`), `pack_origin`, `m_per_px` via `mat.set_shader_param`. `set_theme(t)`: store; `_refresh_theme()`: LUT rebuilt when `hash([t, st.province_owner.hash(), st.manor_owner.hash(), st.manor_province.hash()])` changed (ids from `_repo.cells`, image `Image.create(lut.x, lut.y, false, Image.FORMAT_RGBA8)`, `set_pixel(id % w, id / w, ManorPalette.theme_color(...))` for land cells), `tint_mix` = `bal("map3d_manor_tint")` or 0, `lut_size`, `cell_lut`; `ManorEdges` built once from `ManorPalette.edges` (pairs → 2-point lines → world → `Map3DGeometry.resample`), colour `MapPalette.named(repo,"manor_line")` with `a = bal("map_manor_line_alpha")`, width key `map_manor_line_width`, visible = theme != "". `refresh_borders` calls `_refresh_theme()` when its signature turns. `_set_lines` gains nothing; visibility via the MeshInstance.
- [ ] **Step 5: rule.** `game_root.gd` `_sync_map_view`: 2D-only = `_height_view or _army_view`; then `current_screen.set_map3d_theme("manors" if _manor_view else ("economy" if _economy_view else ""))` if the screen has it. Screens: `func set_map3d_theme(theme: String) -> void: if _map3d != null: _map3d.set_theme(theme)` and apply the stored theme when `set_map3d_view` creates the view (store `_map3d_theme`).
- [ ] **Step 6:** tests pass; full `test_map3d_*` and `test_world_map_view` pass. Commit.

### Task 4: Picking and hovering manors

**Files:** Modify `scripts/map3d/map3d_view.gd`; tests in `tests/map3d/test_map3d_manor_themes.gd`.

- [ ] **Step 1: Failing tests:** under `set_theme("manors")`, `look_at_pack` an open-land pixel (`_open_land()` helper as in `test_map3d_view.gd`) at `map3d_zoom_min_m`, click centre → `object_selected` with `{"title": MapManors.label_of(repo, cell), "obj": {"kind": "manor", "cell": cell}}` where `cell` = `MapIndex.id_at(cell image, px)`, `line_mesh("Selection")` non-null; without a theme the same click emits `province_selected`; `hover_pick({"kind":"manor","cell":cell}, pos)` → tooltip = the manor's label, `hovered_kingdom()` = holder of `MapManors.province_of`; `kingdom_of_pick` for a manor.
- [ ] **Step 2:** fail. **Step 3: Implement:** `pick_at` after the ring loop: `if _theme != "": var cell := _cell_at(pack px); return {"kind":"manor","cell":cell} if cell >= 0 else {}` (`_cell_at` like `_province_at` on `cell_texture_path`, water = white → -1 when `!repo.cells.has(id)` or water); `select_at` "manor" branch → selection from the cell's vertex ring (`repo.cells[id]["vertex_ids"]` → `repo.vertices` → world, closed, resampled) drawn gold via a `_draw_selection_lines(lines)` split out of `_draw_selection`; `hover_pick` keeps manors as tooltip objects (`obj` kept for kind "burg" or "manor"); `kingdom_of_pick` "manor" → `MapManors.province_of(repo, cell, state)`.
- [ ] **Step 4:** pass. Commit.

### Task 5: Look, docs, verification

- [ ] **Step 1:** Full `./run_tests.sh` — only the pre-existing failure.
- [ ] **Step 2:** Real-window shots (`snapshot_screen --screen root --resolution 1600x900 --layer economy|manors`), and the tint at 0.6 / 0.8 / 1.0 (temporarily via a `--bal key=value` override — add that flag to `snapshot_screen.gd`: `Game.data.balance[key] = float(value)` after `start_campaign`) and a `--click3d` manor pick under MANORS.
- [ ] **Step 3:** CLAUDE.md per the spec's Documentation section. Commit tool + docs.
