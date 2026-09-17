# Relief Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the map's baked height field landforms of its own, so the hillshade reads as terrain instead of as smeared Voronoi cells.

**Architecture:** Three new pure functions on `MapIndex` (stamp polylines into a mask, generate a ridged-noise field, and add weighted detail inside `bake_relief`), wired together by the existing offline tool `tools/bake_relief.gd`. Rivers and coasts are stamped into masks and fed to the *existing* `distance_to_land` chamfer transform to produce suppression fields, so invented ridges never cut across real pack data. Nothing changes at runtime: `BiomeLayer` still loads the same texture path into the same shader sampler.

**Tech Stack:** Godot 4.x, typed GDScript, `FastNoiseLite`, GUT for tests. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-17-relief-detail-design.md`

## Global Constraints

- **Typed GDScript everywhere** — type hints on every var, param and return.
- **Design values live in CSVs, never hardcoded.** New numbers go in `data/balance.csv` as `key,value,notes` rows. Add rows; never embed constants in scripts.
- **`MapIndex` is pure and static.** No Node, no scene, no autoload access. It must stay unit-testable headless.
- **Determinism.** The detail's seed is data (`map_relief_detail_seed`). Two bakes with the same seed must be byte-identical. No unseeded `randi()`. `tools/bake_relief.gd` may read the clock — it is a tool reporting its own run time, not simulation.
- **Backward compatibility is a test, not a hope.** With `map_relief_detail_gain` at 0, `bake_relief` must produce exactly today's output. The two existing tests (`test_bake_relief_writes_cell_height_as_grey`, `test_bake_relief_smooths_across_cells`) call it with 4 arguments and must keep passing unchanged.
- **Test command:** `./run_tests.sh` (runs the whole GUT suite headless). The suite must report the **expected error count** — "Errors 2" while `addons/gdai-mcp-plugin-godot/gdai_mcp_plugin.gdextension` is present, 0 without it. **Any other count is a failure**, even if every test passes.
- **Commit messages** end with:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

**Pack facts you will need** (map `beria`):

| | |
|---|---|
| canvas | 2560 x 929 native px |
| `assets/maps/beria/world_relief.png` | currently 1280 x 465, L8 |
| `data/maps/beria/geography/rivers.csv` | `river_code,label,type,length,discharge,kingdom_codes,points` — 180 rivers; `points` is `"x y|x y|..."` in native px |
| `data/maps/beria/geography/coasts.csv` | `kind,feature_id,loop,points` — `kind` is `land` or `lake` |
| `data/maps/beria/geography/cells.csv` | `cell_id,vertex_ids,height,biome_id,water,neighbor_ids` — height is an int 1..100 |

---

### Task 1: Measure the current bake and pin the baseline

No code changes. The spec names bake cost as the top risk and says measuring it is step one; this task produces that number and proves the bake is deterministic before anything is altered.

**Files:**
- Modify: none
- Test: none (a measurement task)

**Interfaces:**
- Consumes: nothing
- Produces: a recorded baseline run time and the fact (or refutation) that re-baking leaves the pack PNGs byte-identical

- [ ] **Step 1: Confirm the working tree is clean for the pack**

```bash
git status --porcelain assets/maps/beria/
```

Expected: no output. If there is output, stop and ask — the bake overwrites these files and you must be able to tell your changes from pre-existing ones.

- [ ] **Step 2: Run the existing bake and record its time**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s tools/bake_relief.gd -- --map beria
```

Expected: a line of the form
`bake_relief: beria relief 1280x465 at 1/2 (radius 2), weights at 1/2 (radius 5), bands 45/62/72, blur 10 px, 4 images in NNNN ms`

Record `NNNN`. Call it `T_base`. This is the cost at **half** resolution; Task 6 raises the field to full resolution, which is 4x the pixels.

- [ ] **Step 3: Prove the bake is deterministic**

```bash
git status --porcelain assets/maps/beria/
```

Expected: no output — the re-bake reproduced the committed PNGs exactly. If files show as modified, the bake is **not** deterministic; stop and report, because the determinism test in Task 3 assumes it is.

- [ ] **Step 4: Record the baseline in the plan**

Write `T_base` and the observed resolution line into this file under Task 1 as a note, then commit.

```bash
git add docs/superpowers/plans/2026-09-17-relief-detail.md
git commit -m "docs(plan): record the relief bake baseline before adding detail

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

**Baseline recorded** (2026-09-17):
```
bake_relief: beria relief 1280x465 at 1/2 (radius 2), weights at 1/2 (radius 5), bands 45/62/72, blur 10 px, 4 images in 5740 ms
```
- **T_base = 5740 ms** (at half resolution; Task 6 raises field to 1:1, which is 4× pixels)
- **Determinism verified:** re-bake reproduced committed PNGs byte-identically (git status showed no changes)

---

### Task 2: `MapIndex.stamp_polylines`

Rivers and coasts are polylines, and the repo has no polyline rasteriser (`MapIndex.rasterize` fills polygons only). This adds one, so the existing `distance_to_land` chamfer transform can turn a stamped mask into a distance field with no new algorithm.

**Files:**
- Modify: `scripts/engine/map_index.gd` (add after `distance_to_land`, before the `bake_sea_distance` doc block)
- Test: `tests/engine/test_map_index.gd`

**Interfaces:**
- Consumes: nothing
- Produces: `static func stamp_polylines(w: int, h: int, lines: Array, radii: PackedFloat32Array) -> PackedByteArray` — one byte per pixel, row-major, 1 where a stamped line passes. Feed straight to `distance_to_land(mask, w, h)`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_map_index.gd`:

```gdscript
## stamp_polylines marks every pixel within a line's radius and nothing
## else, so the existing chamfer transform can measure distance from it.
## A zero radius still marks the pixels the segment itself crosses.
func test_stamp_polylines_marks_the_segment() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(3, 0)])
	var mask := MapIndex.stamp_polylines(5, 3, [line], PackedFloat32Array([0.0]))
	assert_eq(mask.size(), 15)
	assert_eq(mask[0], 1, "the start is stamped")
	assert_eq(mask[3], 1, "the end is stamped")
	assert_eq(mask[4], 0, "past the end is not")
	assert_eq(mask[5], 0, "the row below is not")

func test_stamp_polylines_honours_the_radius() -> void:
	var line := PackedVector2Array([Vector2(2, 1), Vector2(2, 1)])
	var mask := MapIndex.stamp_polylines(5, 3, [line], PackedFloat32Array([1.0]))
	assert_eq(mask[1 * 5 + 2], 1, "the point itself")
	assert_eq(mask[0 * 5 + 2], 1, "one pixel up is inside radius 1")
	assert_eq(mask[1 * 5 + 1], 1, "one pixel left is inside radius 1")
	assert_eq(mask[0 * 5 + 0], 0, "the diagonal is 1.41 away, outside radius 1")

func test_stamp_polylines_clips_to_the_field() -> void:
	var line := PackedVector2Array([Vector2(-5, 0), Vector2(1, 0)])
	var mask := MapIndex.stamp_polylines(3, 1, [line], PackedFloat32Array([0.0]))
	assert_eq(mask[0], 1, "the part inside the field is stamped")
	assert_eq(mask[2], 0, "and nothing beyond the line's end")
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

```bash
./run_tests.sh
```

Expected: FAIL, reporting that `stamp_polylines` is not a function of `MapIndex`.

- [ ] **Step 3: Write the implementation**

Add to `scripts/engine/map_index.gd`:

```gdscript
## --- Stamping polylines into a mask (2026-09-17) -----------------------------
## Every pixel within `radii[i]` px of line `i` becomes 1. `lines` holds
## PackedVector2Array courses in the MASK's own pixel space (divide native
## coordinates by the bake's scale before calling). Segments are walked at
## half-pixel steps so no pixel is skipped on a diagonal. The pack's 180
## river courses touch only a few thousand pixels, so this costs nothing
## next to the per-pixel passes around it. Pure; a bake step, never runtime.
static func stamp_polylines(w: int, h: int, lines: Array, radii: PackedFloat32Array) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	for i in lines.size():
		var pts: PackedVector2Array = lines[i]
		var r := 0.0 if i >= radii.size() else maxf(radii[i], 0.0)
		if pts.size() == 1:
			_stamp_disc(mask, w, h, pts[0], r)
			continue
		for s in maxi(pts.size() - 1, 0):
			var a := pts[s]
			var b := pts[s + 1]
			var steps := maxi(int(a.distance_to(b) * 2.0), 1)
			for t in steps + 1:
				_stamp_disc(mask, w, h, a.lerp(b, float(t) / float(steps)), r)
	return mask

static func _stamp_disc(mask: PackedByteArray, w: int, h: int, p: Vector2, r: float) -> void:
	var cx := int(round(p.x))
	var cy := int(round(p.y))
	var ri := int(ceil(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if Vector2(dx, dy).length() > r:
				continue
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and y >= 0 and x < w and y < h:
				mask[y * w + x] = 1
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
./run_tests.sh
```

Expected: PASS, with the expected error count (2 with the gdai extension present, else 0).

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/map_index.gd tests/engine/test_map_index.gd
git commit -m "feat(map): stamp polylines into a mask for the relief bake

Rivers and coasts are polylines and the repo only had a polygon fill, so
the existing distance_to_land chamfer had nothing to measure from.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `MapIndex.detail_field`

The ridged fractal noise the landforms are made of. Separated from `bake_relief` so its determinism and range can be tested on their own.

**Files:**
- Modify: `scripts/engine/map_index.gd` (add after `stamp_polylines`)
- Test: `tests/engine/test_map_index.gd`

**Interfaces:**
- Consumes: nothing
- Produces: `static func detail_field(w: int, h: int, seed_value: int, freq_px: float, octaves: int, warp_px: float) -> PackedFloat32Array` — row-major, every value in 0..1.

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_map_index.gd`:

```gdscript
## The detail is a LOOK, never simulation: its seed is data, so two bakes
## with the same seed are identical and a different seed is a different
## sheet. Values stay in 0..1 so bake_relief can scale them by a gain in
## height units.
func test_detail_field_is_deterministic() -> void:
	var a := MapIndex.detail_field(8, 8, 1234, 16.0, 3, 0.0)
	var b := MapIndex.detail_field(8, 8, 1234, 16.0, 3, 0.0)
	assert_eq(a.size(), 64)
	assert_eq(Array(a), Array(b), "the same seed gives the same field")

func test_detail_field_changes_with_the_seed() -> void:
	var a := MapIndex.detail_field(8, 8, 1234, 16.0, 3, 0.0)
	var b := MapIndex.detail_field(8, 8, 9999, 16.0, 3, 0.0)
	assert_ne(Array(a), Array(b), "a different seed is a different sheet")

func test_detail_field_stays_in_unit_range() -> void:
	var f := MapIndex.detail_field(16, 16, 7, 8.0, 4, 4.0)
	var lo := 2.0
	var hi := -1.0
	for v in f:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_gte(lo, 0.0, "never below 0")
	assert_lte(hi, 1.0, "never above 1")
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

```bash
./run_tests.sh
```

Expected: FAIL, reporting that `detail_field` is not a function of `MapIndex`.

- [ ] **Step 3: Write the implementation**

Add to `scripts/engine/map_index.gd`:

```gdscript
## --- The relief's synthesized detail (owner 2026-09-17, approach A) ----------
## Ridged fractal noise over the whole field, 0..1, row-major. The pack has
## ONE height per Voronoi cell (~26 native px across) and vertices.csv has
## no heights at all, so there is no finer truth to recover: the landforms
## below a cell are invented. Ridged, because a ridgeline is the feature a
## satellite view reads terrain by; domain-warped so the ridges run in
## coherent directions instead of as isotropic blobs. The seed is DATA
## (balance.csv map_relief_detail_seed) — a look, never simulation. Pure.
static func detail_field(w: int, h: int, seed_value: int, freq_px: float,
		octaves: int, warp_px: float) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = seed_value
	noise.frequency = 1.0 / maxf(freq_px, 1.0)
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = maxi(octaves, 1)
	if warp_px > 0.0:
		noise.domain_warp_enabled = true
		noise.domain_warp_amplitude = warp_px
		noise.domain_warp_frequency = 1.0 / maxf(freq_px * 2.0, 1.0)
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			out[y * w + x] = clampf(noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5, 0.0, 1.0)
	return out
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
./run_tests.sh
```

Expected: PASS with the expected error count.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/map_index.gd tests/engine/test_map_index.gd
git commit -m "feat(map): a seeded ridged-noise field for the relief's detail

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `bake_relief` adds weighted, suppressed detail

The join. Detail is scaled by a gain in height units, weighted by how high the ground already is, and held down near rivers and the coast.

**Files:**
- Modify: `scripts/engine/map_index.gd:227` (`bake_relief`)
- Test: `tests/engine/test_map_index.gd`

**Interfaces:**
- Consumes: `detail_field` (Task 3), `stamp_polylines` + `distance_to_land` (Task 2)
- Produces: `static func bake_relief(cells: Image, heights: PackedInt32Array, scale: int, radius: int, detail: PackedFloat32Array = PackedFloat32Array(), suppression: PackedFloat32Array = PackedFloat32Array(), gain: float = 0.0, floor_height: float = 0.0) -> Image` — `detail` and `suppression` are row-major at the **output** resolution (`ceil(w/scale) x ceil(h/scale)`).

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_map_index.gd`:

```gdscript
## The guard that protects every existing caller: with no gain the detail
## arguments are ignored entirely and the field is exactly what it was.
func test_bake_relief_without_gain_is_unchanged() -> void:
	var cells := Image.create_empty(3, 1, false, Image.FORMAT_RGB8)
	for x in 3:
		cells.set_pixel(x, 0, Color8(x, 0, 0))
	var heights := PackedInt32Array([0, 50, 100])
	var plain := MapIndex.bake_relief(cells, heights, 1, 0)
	var with_detail := MapIndex.bake_relief(cells, heights, 1, 0,
		PackedFloat32Array([1.0, 1.0, 1.0]), PackedFloat32Array([1.0, 1.0, 1.0]), 0.0, 0.0)
	for x in 3:
		assert_eq(with_detail.get_pixel(x, 0).r8, plain.get_pixel(x, 0).r8,
			"gain 0 leaves the field alone at x=%d" % x)

## Detail is added in HEIGHT units and weighted by how high the ground
## already is, so a plain stays flat while high ground grows ridges. Cell 1
## is at height 50 with floor 0, so h_norm is 0.5 and a gain of 20 at full
## detail adds 10: the height becomes 60, and the byte is written once from
## that, int(60 * 255 / 100 + 0.5) = 153. (Not 128 + 26 — the height is
## summed first and rounded once, so rounding the two parts separately is
## off by one.)
func test_bake_relief_adds_detail_weighted_by_height() -> void:
	var cells := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	cells.set_pixel(0, 0, Color8(0, 0, 0))
	cells.set_pixel(1, 0, Color8(1, 0, 0))
	var heights := PackedInt32Array([0, 50])
	var img := MapIndex.bake_relief(cells, heights, 1, 0,
		PackedFloat32Array([1.0, 1.0]), PackedFloat32Array([1.0, 1.0]), 20.0, 0.0)
	assert_eq(img.get_pixel(0, 0).r8, 0, "height 0 gets no detail at all")
	assert_eq(img.get_pixel(1, 0).r8, 153, "height 50 + 10 of detail = 60 -> 153 greys")

## Suppression is how rivers and the coast keep invented ridges out of
## their valleys: 0 holds the detail down completely, 1 lets it through.
func test_bake_relief_suppression_holds_detail_down() -> void:
	var cells := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	cells.set_pixel(0, 0, Color8(0, 0, 0))
	cells.set_pixel(1, 0, Color8(1, 0, 0))
	var heights := PackedInt32Array([100, 100])
	var img := MapIndex.bake_relief(cells, heights, 1, 0,
		PackedFloat32Array([1.0, 1.0]), PackedFloat32Array([0.0, 1.0]), 20.0, 0.0)
	assert_eq(img.get_pixel(0, 0).r8, 255, "suppressed: the plain height, clamped")
	assert_eq(img.get_pixel(1, 0).r8, 255, "unsuppressed would also clamp here")

func test_bake_relief_suppression_is_visible_below_the_clamp() -> void:
	var cells := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	cells.set_pixel(0, 0, Color8(0, 0, 0))
	cells.set_pixel(1, 0, Color8(1, 0, 0))
	var heights := PackedInt32Array([50, 50])
	var img := MapIndex.bake_relief(cells, heights, 1, 0,
		PackedFloat32Array([1.0, 1.0]), PackedFloat32Array([0.0, 1.0]), 20.0, 0.0)
	assert_eq(img.get_pixel(0, 0).r8, 128, "fully suppressed is the plain height")
	assert_gt(img.get_pixel(1, 0).r8, 128, "unsuppressed rose")
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

```bash
./run_tests.sh
```

Expected: FAIL — `bake_relief` takes 4 arguments, not 8.

- [ ] **Step 3: Write the implementation**

In `scripts/engine/map_index.gd`, change `bake_relief`'s signature and the final loop. The counting and smoothing above are untouched:

```gdscript
static func bake_relief(cells: Image, heights: PackedInt32Array, scale: int, radius: int,
		detail: PackedFloat32Array = PackedFloat32Array(),
		suppression: PackedFloat32Array = PackedFloat32Array(),
		gain: float = 0.0, floor_height: float = 0.0) -> Image:
```

and replace the byte-writing loop at the end with:

```gdscript
	var bytes := PackedByteArray()
	bytes.resize(n)
	var span := maxf(100.0 - floor_height, 1.0)
	for i in n:
		var v := 0.0
		if count[i] > 0.0:
			v = total[i] / count[i]
		# Synthesized landforms (owner 2026-09-17, approach A): added in
		# height units, weighted by how high the ground already is so a
		# plain stays flat, and held down near rivers and the coast so an
		# invented ridge never cuts across real pack data.
		if gain > 0.0 and i < detail.size():
			var h_norm := clampf((v - floor_height) / span, 0.0, 1.0)
			var sup := 1.0 if i >= suppression.size() else suppression[i]
			v += gain * h_norm * sup * detail[i]
		bytes[i] = clampi(int(v * 255.0 / 100.0 + 0.5), 0, 255)
	return Image.create_from_data(lw, lh, false, Image.FORMAT_L8, bytes)
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
./run_tests.sh
```

Expected: PASS. The two pre-existing `bake_relief` tests must still pass **unchanged** — if you edited them, revert and fix the defaults instead.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/map_index.gd tests/engine/test_map_index.gd
git commit -m "feat(map): bake_relief adds height-weighted, suppressed detail

Off by default: with gain 0 the field is byte-for-byte what it was.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `raise_high_ground` reads the detailed field

So rock and snow follow a synthesized ridge instead of the flat cell value. Optional, defaulting to today's per-cell behaviour.

**Files:**
- Modify: `scripts/engine/map_index.gd:194` (`raise_high_ground`)
- Test: `tests/engine/test_map_index.gd`

**Interfaces:**
- Consumes: the L8 image produced by `bake_relief` (Task 4)
- Produces: `static func raise_high_ground(biome: Image, cells: Image, heights: PackedInt32Array, hill: int, mountain: int, peak: int, detailed: Image = null) -> Image`

- [ ] **Step 1: Write the failing test**

Add to `tests/engine/test_map_index.gd`:

```gdscript
## With a detailed field the bands follow the SYNTHESIZED height, so a ridge
## invented between two cell centres still wears rock and snow. The cell
## says 30 (nothing), the detailed field says 90 (a peak).
func test_raise_high_ground_prefers_the_detailed_field() -> void:
	var biome := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	biome.set_pixel(0, 0, Color8(6, 0, 0))
	var cells := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	cells.set_pixel(0, 0, Color8(0, 0, 0))
	var detailed := Image.create_empty(1, 1, false, Image.FORMAT_L8)
	detailed.set_pixel(0, 0, Color(230.0 / 255.0, 0, 0))  # 230 grey = height 90
	var out := MapIndex.raise_high_ground(biome, cells, PackedInt32Array([30]),
		45, 62, 80, detailed)
	assert_eq(out.get_pixel(0, 0).r8, 15, "the detailed field made it a peak")

func test_raise_high_ground_without_a_field_uses_the_cell() -> void:
	var biome := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	biome.set_pixel(0, 0, Color8(6, 0, 0))
	var cells := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	cells.set_pixel(0, 0, Color8(0, 0, 0))
	var out := MapIndex.raise_high_ground(biome, cells, PackedInt32Array([30]), 45, 62, 80)
	assert_eq(out.get_pixel(0, 0).r8, 6, "height 30 is below the hill line")
```

- [ ] **Step 2: Run the suite to verify the new test fails**

```bash
./run_tests.sh
```

Expected: FAIL — `raise_high_ground` takes 6 arguments, not 7.

- [ ] **Step 3: Write the implementation**

In `scripts/engine/map_index.gd`, change the signature and how `height` is obtained:

```gdscript
static func raise_high_ground(biome: Image, cells: Image, heights: PackedInt32Array,
		hill: int, mountain: int, peak: int, detailed: Image = null) -> Image:
```

Replace the per-pixel height lookup inside the loop with:

```gdscript
			# The bands follow the DETAILED field when there is one (owner
			# 2026-09-17), so rock and snow sit on a synthesized ridge
			# rather than on the flat value of the cell it crosses.
			var height := heights[cell]
			if detailed != null:
				var dx := mini(x * detailed.get_width() / w, detailed.get_width() - 1)
				var dy := mini(y * detailed.get_height() / h, detailed.get_height() - 1)
				height = int(round(detailed.get_pixel(dx, dy).r8 * 100.0 / 255.0))
```

- [ ] **Step 4: Run the suite to verify it passes**

```bash
./run_tests.sh
```

Expected: PASS, with the three pre-existing `raise_high_ground` tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/map_index.gd tests/engine/test_map_index.gd
git commit -m "feat(map): high-ground bands follow the detailed relief field

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Wire it into the bake tool and the balance table

**Files:**
- Modify: `tools/bake_relief.gd`
- Modify: `data/balance.csv`
- Test: none new — the pure functions are covered by Tasks 2-5; this task's gate is that the suite stays green and the bake runs.

**Interfaces:**
- Consumes: `stamp_polylines`, `detail_field`, `bake_relief`, `raise_high_ground`
- Produces: a re-baked `assets/maps/beria/world_relief.png` at 2560 x 929

- [ ] **Step 1: Add the balance rows**

Append to `data/balance.csv` (keep the `key,value,notes` shape; quote any note containing a comma):

```
map_relief_detail_seed,954159497,"terrain: seed of the relief's synthesized detail (owner 2026-09-17, approach A). The map's own seed — a look, never simulation, so two bakes match"
map_relief_detail_freq_px,180,"terrain: wavelength of the coarsest octave of relief detail, in native px"
map_relief_detail_octaves,4,"terrain: octaves of ridged fractal in the relief detail"
map_relief_detail_gain,22,"terrain: amplitude of the relief detail in HEIGHT units (the pack's 0..100 scale). 0 = off, which reproduces the pre-2026-09-17 field exactly"
map_relief_detail_floor,25,"terrain: height below which the detail fades to nothing — plains stay flat, high ground grows ridges"
map_relief_detail_warp_px,60,"terrain: domain-warp amplitude of the detail noise in native px, so ridges run in coherent directions instead of isotropic blobs. 0 = no warp"
map_relief_detail_river_px,14,"terrain: how far from a river course the detail is held down, in native px — an invented ridge may not cut across a real river valley"
map_relief_detail_coast_px,10,"terrain: the same for the shoreline"
```

And change the **value** column of the existing `map_relief_scale` row from `2` to `1`, leaving its notes text alone.

- [ ] **Step 2: Add the course loader to the bake tool**

Add to `tools/bake_relief.gd`:

```gdscript
## The pack's river courses and land shores in native px, with the stamp
## radius each should wear. A river's radius grows with its discharge so a
## great river holds a wider valley clear than a brook does.
func _courses(map: String, scale: int, river_px: float, coast_px: float) -> Dictionary:
	var lines: Array = []
	var radii := PackedFloat32Array()
	var rivers := DataRepository.parse_csv("res://data/maps/%s/geography/rivers.csv" % map,
		["river_code", "label", "type", "length", "discharge", "kingdom_codes", "points"])
	var most := 1.0
	for row: Dictionary in rivers:
		most = maxf(most, float(row.get("discharge", 0)))
	for row: Dictionary in rivers:
		var pts := MapGeometry.parse_points(String(row.get("points", "")))
		if pts.size() < 2:
			continue
		lines.append(_scaled(pts, scale))
		var share := sqrt(float(row.get("discharge", 0)) / most)
		radii.append(maxf(river_px * share, 1.0) / float(scale))
	var coasts := DataRepository.parse_csv("res://data/maps/%s/geography/coasts.csv" % map,
		["kind", "feature_id", "loop", "points"])
	for row: Dictionary in coasts:
		if String(row.get("kind", "")) != "land":
			continue
		var pts := MapGeometry.parse_points(String(row.get("points", "")))
		if pts.size() < 2:
			continue
		lines.append(_scaled(pts, scale))
		radii.append(maxf(coast_px, 1.0) / float(scale))
	return {"lines": lines, "radii": radii}

func _scaled(pts: PackedVector2Array, scale: int) -> PackedVector2Array:
	if scale <= 1:
		return pts
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] / float(scale)
	return out
```

- [ ] **Step 3: Build the suppression field and pass the detail through**

In `tools/bake_relief.gd`'s `_init`, replace the single `bake_relief` call with:

```gdscript
	var r_scale := maxi(int(bal.get("map_relief_scale", 1.0)), 1)
	var r_radius := maxi(int(bal.get("map_relief_blur_px", 0.0)) / r_scale, 0)
	var lw := ceili(float(cells_img.get_width()) / float(r_scale))
	var lh := ceili(float(cells_img.get_height()) / float(r_scale))

	# Rivers and the coast hold the invented ridges down: stamp both into one
	# mask, then reuse the chamfer transform to measure distance from it.
	var river_px: float = bal.get("map_relief_detail_river_px", 0.0)
	var coast_px: float = bal.get("map_relief_detail_coast_px", 0.0)
	var courses := _courses(map, r_scale, river_px, coast_px)
	var mask := MapIndex.stamp_polylines(lw, lh, courses["lines"], courses["radii"])
	var dist := MapIndex.distance_to_land(mask, lw, lh)
	var reach := maxf(maxf(river_px, coast_px) / float(r_scale), 1.0)
	var suppression := PackedFloat32Array()
	suppression.resize(lw * lh)
	for i in lw * lh:
		suppression[i] = smoothstep(0.0, reach, dist[i])

	var detail := MapIndex.detail_field(lw, lh,
		int(bal.get("map_relief_detail_seed", 0.0)),
		bal.get("map_relief_detail_freq_px", 180.0) / float(r_scale),
		int(bal.get("map_relief_detail_octaves", 4.0)),
		bal.get("map_relief_detail_warp_px", 0.0) / float(r_scale))

	var relief := MapIndex.bake_relief(cells_img, heights, r_scale, r_radius,
		detail, suppression,
		bal.get("map_relief_detail_gain", 0.0),
		bal.get("map_relief_detail_floor", 0.0))
```

and pass the new field to the high-ground pass:

```gdscript
	var raised := MapIndex.raise_high_ground(biome_img, cells_img, heights,
		hill, mountain, peak, relief)
```

- [ ] **Step 4: Run the suite**

```bash
./run_tests.sh
```

Expected: PASS with the expected error count. (No new tests here — the logic is all in the tested pure functions.)

- [ ] **Step 5: Run the bake and compare the cost against Task 1**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s tools/bake_relief.gd -- --map beria
```

Expected: `relief 2560x929 at 1/1`. Record the run time and compare with `T_base`.

**If it is unacceptably slow**, the spec's named fallback is to keep the relief at 1:1 but leave `map_biome_weights_scale` at 2 (it already is) — and if that is still too slow, set `map_relief_scale` back to 2 and re-tune `map_relief_detail_freq_px` down by the same factor. Report the number either way; do not silently accept a multi-minute bake.

- [ ] **Step 6: Commit**

```bash
git add tools/bake_relief.gd data/balance.csv assets/maps/beria/world_relief.png \
  assets/maps/beria/world_biome_weights_0.png assets/maps/beria/world_biome_weights_1.png \
  assets/maps/beria/world_biome_weights_2.png assets/maps/beria/world_biome_weights_3.png
git commit -m "feat(map): bake the relief at full canvas with synthesized landforms

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Look at it, and retune the slope sampling

The spec says `map_relief_shade_px` (8 native px) was tuned against a blurred half-resolution field and should come down once the field has real detail. This is a judgement step with the owner, not a test.

**Files:**
- Modify: `data/balance.csv` (`map_relief_shade_px`, possibly `map_relief_shade`, `map_relief_gain`)
- Test: visual

**Interfaces:**
- Consumes: the re-baked field from Task 6
- Produces: tuned values, and snapshots for the owner

- [ ] **Step 1: Render the bright map at three zooms**

```bash
SP=/tmp/relief-check && mkdir -p $SP
for z in 1.0 2.0 4.0; do
  /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_map.tscn -- \
    --out "$SP/bright_z$z.png" --zoom $z --size 1600
done
```

- [ ] **Step 2: Render the dark spike at the same zooms**

The dark tactical mode was added to the snapshot tool during the spike and is the view that exposed the problem, so it is the sharpest test of whether the fix worked.

```bash
for z in 1.0 2.0 4.0; do
  /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_map.tscn -- \
    --out "$SP/dark_z$z.png" --zoom $z --size 1600 --dark 1
done
```

- [ ] **Step 3: Compare against the smeared baseline**

The spike's before-shots are in `assets/flux/out/settlements/compare/` as `DARK_z1.png`, `DARK_z2.png`, `DARK_z4.png`. Put the new shots beside them. What you are looking for: the broad diagonal smears should have become ridgelines, and the plains should still read as plains.

- [ ] **Step 4: Retune `map_relief_shade_px` and re-render**

Lower `map_relief_shade_px` from 8 toward 3-4 and re-render at z2. Too low and the hillshade picks up noise per texel; too high and it averages the new detail away. Pick by eye, record the reasoning in the balance note.

- [ ] **Step 5: Show the owner and commit the tuning**

Present the before/after pairs at all three zooms. Do not commit tuning values the owner has not seen.

```bash
git add data/balance.csv
git commit -m "tune(map): slope sampling for the detailed relief field

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage.** Pipeline step 1 (base at 1:1) → Task 6 step 1. Step 2 (suppression masks reusing `distance_to_land`) → Tasks 2 and 6. Step 3 (ridged, warped, seeded noise) → Task 3. Step 4 (height weighting, floor, clamp) → Task 4. Step 5 (`raise_high_ground` re-bands from the detailed field) → Task 5. All eight new balance keys → Task 6 step 1. Every test the spec lists → Tasks 2-5, with the `gain 0` guard in Task 4. The bake-cost risk → Task 1 (baseline) and Task 6 step 5 (comparison plus the spec's fallback). The `map_relief_shade_px` retune → Task 7. No spec requirement is unclaimed.

**Placeholder scan.** No TBD/TODO, no "handle edge cases", no "similar to Task N". Every code step carries the actual code; every test step carries the actual test.

**Type consistency.** `stamp_polylines(w, h, lines, radii) -> PackedByteArray` is produced in Task 2 and consumed in Task 6 with exactly those arguments. `detail_field(w, h, seed_value, freq_px, octaves, warp_px) -> PackedFloat32Array` matches between Tasks 3 and 6. `bake_relief`'s 8-parameter form in Task 4 matches the call in Task 6. `raise_high_ground`'s 7th parameter in Task 5 matches the call in Task 6. `distance_to_land(mask, w, h) -> PackedFloat32Array` is the existing signature at `map_index.gd:40`.

**One deliberate note:** Task 4's `test_bake_relief_suppression_holds_detail_down` asserts both pixels reach 255 because height 100 already clamps — it documents the clamp rather than the suppression, which is why the following test exercises suppression at height 50 where the difference is visible. Keep both.
