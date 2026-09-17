extends GutTest
## MapIndex decodes tools/import_azgaar.gd's state-index bitmap:
## state id = R | (G << 8); pure white = water / no state.

func test_decode_small_id() -> void:
	assert_eq(MapIndex.decode(Color8(7, 0, 0)), 7)

func test_decode_two_byte_id() -> void:
	assert_eq(MapIndex.decode(Color8(3, 1, 0)), 259)

func test_decode_white_is_no_state() -> void:
	assert_eq(MapIndex.decode(Color8(255, 255, 255)), -1)

func test_state_at_samples_and_bounds_checks() -> void:
	var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color8(5, 0, 0))
	img.set_pixel(1, 0, Color8(255, 255, 255))
	assert_eq(MapIndex.state_at(img, Vector2i(0, 0)), 5)
	assert_eq(MapIndex.state_at(img, Vector2i(1, 0)), -1)
	assert_eq(MapIndex.state_at(img, Vector2i(2, 0)), -1, "x out of bounds")
	assert_eq(MapIndex.state_at(img, Vector2i(0, -1)), -1, "y out of bounds")
	assert_eq(MapIndex.state_at(null, Vector2i(0, 0)), -1, "nil image")

## The province bitmap reuses the state encoding; the biome bitmap keeps its
## id in the red channel only. Both treat pure white as "nothing here".
func test_id_at_is_the_generic_two_byte_decoder() -> void:
	var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color8(3, 1, 0))
	img.set_pixel(1, 0, Color8(255, 255, 255))
	assert_eq(MapIndex.id_at(img, Vector2i(0, 0)), 259)
	assert_eq(MapIndex.id_at(img, Vector2i(1, 0)), -1)
	assert_eq(MapIndex.id_at(null, Vector2i(0, 0)), -1, "nil image")

func test_biome_at_reads_the_red_channel() -> void:
	var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color8(6, 0, 0))
	img.set_pixel(1, 0, Color8(255, 255, 255))
	assert_eq(MapIndex.biome_at(img, Vector2i(0, 0)), 6)
	assert_eq(MapIndex.biome_at(img, Vector2i(1, 0)), -1, "white is water/none")
	assert_eq(MapIndex.biome_at(img, Vector2i(5, 0)), -1, "out of bounds")

## The sea's distance field (owner 2026-09-13): a chamfer with 1 across and
## sqrt 2 diagonal, 0 on land. One land pixel at the top-left of a 3x3.
func test_distance_to_land_is_a_chamfer_from_the_land() -> void:
	var land := PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0, 0])
	var d := MapIndex.distance_to_land(land, 3, 3)
	assert_eq(d[0], 0.0, "land is 0")
	assert_almost_eq(d[1], 1.0, 0.0001)
	assert_almost_eq(d[2], 2.0, 0.0001)
	assert_almost_eq(d[3], 1.0, 0.0001)
	assert_almost_eq(d[4], 1.41421, 0.0001, "one diagonal")
	assert_almost_eq(d[5], 2.41421, 0.0001, "a diagonal and a step")
	assert_almost_eq(d[8], 2.82843, 0.0001, "two diagonals")

## Baked from the biome index: land (a biome id) is 0, water counts up from
## it, capped at 255 in an L8 image the shader can read.
func test_bake_sea_distance_writes_capped_bytes() -> void:
	var img := Image.create_empty(300, 1, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	img.set_pixel(0, 0, Color8(5, 0, 0))
	var baked := MapIndex.bake_sea_distance(img)
	assert_eq(baked.get_format(), Image.FORMAT_L8)
	assert_eq(baked.get_width(), 300)
	assert_eq(baked.get_pixel(0, 0).r8, 0, "land")
	assert_eq(baked.get_pixel(1, 0).r8, 1)
	assert_eq(baked.get_pixel(2, 0).r8, 2)
	assert_eq(baked.get_pixel(255, 0).r8, 255)
	assert_eq(baked.get_pixel(299, 0).r8, 255, "capped")

## BIOMES LAYER (experiment 2026-09-14). box_sum over a 4-wide row with
## radius 1, clipped at the edges: [1,2,3,4] -> [3,6,9,7].
func test_box_sum_is_the_clipped_window_sum() -> void:
	var out := MapIndex.box_sum(PackedFloat32Array([1, 2, 3, 4]), 4, 1, 1)
	assert_eq(out, PackedFloat32Array([3, 6, 9, 7]))
	assert_eq(MapIndex.box_sum(PackedFloat32Array([1, 2]), 2, 1, 0), PackedFloat32Array([1, 2]),
		"radius 0 is a copy")

## An 8x1 index, biome 1 on the left half and 2 on the right, at scale 1
## with radius 1 — two box passes. Land after one pass: [2,3,3,3,3,3,3,2],
## biome 1: [2,3,3,2,1,0,0,0]; after two: land [5,8,9,9,9,9,8,5], biome 1
## [5,8,8,6,3,1,0,0]. Biome 1's share: 1, 1, 8/9, 6/9, 3/9, 1/9, 0, 0 —
## a ramp across the seam; biome 2 is the rest, so the two sum to one.
func test_bake_biome_weights_ramps_one_biome_into_the_next() -> void:
	var img := Image.create_empty(8, 1, false, Image.FORMAT_RGB8)
	for x in 8:
		img.set_pixel(x, 0, Color8(1 if x < 4 else 2, 0, 0))
	var baked := MapIndex.bake_biome_weights(img, 1, 1, 2)
	assert_eq(baked.size(), 1, "two biomes fit one RGBA image")
	var w := baked[0]
	assert_eq(w.get_format(), Image.FORMAT_RGBA8)
	assert_eq(w.get_width(), 8)
	var expect := [255, 255, 227, 170, 85, 28, 0, 0]
	for x in 8:
		assert_eq(w.get_pixel(x, 0).r8, expect[x], "biome 1 at x=%d" % x)
		assert_eq(w.get_pixel(x, 0).g8, 255 - expect[x], "biome 2 at x=%d" % x)
		assert_eq(w.get_pixel(x, 0).b8, 0, "no third biome")

## Water (white) is not land: it neither counts nor dilutes. A biome pixel
## beside two water pixels keeps a whole tile right up to and over the
## shore (the land mesh clips it there) — at radius 1 every point's only
## land within reach is biome 1, so every share is 1.
func test_bake_biome_weights_normalises_over_land_only() -> void:
	var img := Image.create_empty(3, 1, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	img.set_pixel(0, 0, Color8(1, 0, 0))
	var w := MapIndex.bake_biome_weights(img, 1, 1, 1)[0]
	assert_eq(w.get_pixel(0, 0).r8, 255)
	assert_eq(w.get_pixel(1, 0).r8, 255)
	assert_eq(w.get_pixel(2, 0).r8, 255)
	var dry := MapIndex.bake_biome_weights(img, 1, 0, 1)[0]
	assert_eq(dry.get_pixel(1, 0).r8, 0, "with no blur the sea has no land near it")

## scale 2 halves the resolution: a 4x2 index becomes 2x1, each cell the
## count of its 2x2 block — a block of three biome-1 and one biome-2 pixels
## is 3/4 and 1/4.
func test_bake_biome_weights_counts_blocks_at_scale() -> void:
	var img := Image.create_empty(4, 2, false, Image.FORMAT_RGB8)
	img.fill(Color8(1, 0, 0))
	img.set_pixel(1, 1, Color8(2, 0, 0))
	img.set_pixel(2, 0, Color8(2, 0, 0))
	img.set_pixel(3, 0, Color8(2, 0, 0))
	img.set_pixel(2, 1, Color8(2, 0, 0))
	img.set_pixel(3, 1, Color8(2, 0, 0))
	var w := MapIndex.bake_biome_weights(img, 2, 0, 2)[0]
	assert_eq(w.get_width(), 2)
	assert_eq(w.get_height(), 1)
	assert_eq(w.get_pixel(0, 0).r8, 191, "3 of 4")
	assert_eq(w.get_pixel(0, 0).g8, 64, "1 of 4")
	assert_eq(w.get_pixel(1, 0).g8, 255, "all biome 2")

## rasterize: a polygon filled with its id in the two-byte encoding, the
## rest white, decodable by id_at — the importer's own fill, so a baked
## bitmap matches an imported one. A 4x4 square from (1,1) to (5,5) on an
## 8x8 canvas covers pixels 1..4 on each axis (centre sampling).
func test_rasterize_fills_a_polygon_with_its_id() -> void:
	var square := PackedVector2Array([Vector2(1, 1), Vector2(5, 1), Vector2(5, 5), Vector2(1, 5)])
	var img := MapIndex.rasterize([square], PackedInt32Array([300]), 8, 8)
	assert_eq(img.get_width(), 8)
	assert_eq(MapIndex.id_at(img, Vector2i(0, 0)), -1, "outside is white")
	assert_eq(MapIndex.id_at(img, Vector2i(1, 1)), 300)
	assert_eq(MapIndex.id_at(img, Vector2i(4, 4)), 300)
	assert_eq(MapIndex.id_at(img, Vector2i(5, 5)), -1, "the far edge is exclusive")
	assert_eq(MapIndex.id_at(img, Vector2i(3, 6)), -1)
	assert_eq(img.get_pixel(2, 2).g8, 1, "300 = 44 | 1 << 8")
	assert_eq(img.get_pixel(2, 2).r8, 44)


## --- High ground and relief (owner 2026-09-17: the satellite ground needs
## mountains, and they are not a biome — they are HEIGHT) -------------------
## raise_high_ground rewrites a land pixel's biome id by the height of the
## CELL it falls in: at/above peak it is 15, mountain 14, hill 13, and below
## that it keeps the biome the pack gave it. Three cells of height 10, 50
## and 90 against hill 45 / mountain 62 / peak 80: the first keeps biome 4,
## the second is a hill, the third a peak.
func test_raise_high_ground_promotes_a_pixel_by_its_cell_height() -> void:
	var biome := Image.create_empty(3, 1, false, Image.FORMAT_RGB8)
	for x in 3:
		biome.set_pixel(x, 0, Color8(4, 0, 0))
	var cells := Image.create_empty(3, 1, false, Image.FORMAT_RGB8)
	for x in 3:
		cells.set_pixel(x, 0, Color8(x, 0, 0))
	var heights := PackedInt32Array([10, 50, 90])
	var out := MapIndex.raise_high_ground(biome, cells, heights, 45, 62, 80)
	assert_eq(out.get_pixel(0, 0).r8, 4, "lowland keeps its biome")
	assert_eq(out.get_pixel(1, 0).r8, 13, "50 is a hill")
	assert_eq(out.get_pixel(2, 0).r8, 15, "90 is a peak")

## Water carries no cell (white in the cell index), so it stays exactly as
## the biome index had it — white — and never becomes a mountain.
func test_raise_high_ground_leaves_water_alone() -> void:
	var biome := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	biome.fill(Color.WHITE)
	biome.set_pixel(0, 0, Color8(6, 0, 0))
	var cells := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	cells.fill(Color.WHITE)
	cells.set_pixel(0, 0, Color8(0, 0, 0))
	var out := MapIndex.raise_high_ground(biome, cells, PackedInt32Array([90]), 45, 62, 80)
	assert_eq(out.get_pixel(0, 0).r8, 15, "the land pixel rose")
	assert_eq(out.get_pixel(1, 0).r8, 255, "the sea is untouched")

## bake_relief lays each cell's height over its pixels and smooths it, so
## the shader can read a slope without the cell edges showing. Heights are
## 0..100 and the image is L8, so a height of 100 is 255. At scale 1 and
## radius 0 there is no smoothing: each pixel is its own cell's height.
func test_bake_relief_writes_cell_height_as_grey() -> void:
	var cells := Image.create_empty(3, 1, false, Image.FORMAT_RGB8)
	for x in 3:
		cells.set_pixel(x, 0, Color8(x, 0, 0))
	var img := MapIndex.bake_relief(cells, PackedInt32Array([0, 50, 100]), 1, 0)
	assert_eq(img.get_format(), Image.FORMAT_L8)
	assert_eq(img.get_width(), 3)
	assert_eq(img.get_pixel(0, 0).r8, 0)
	assert_eq(img.get_pixel(1, 0).r8, 128, "50 of 100 is half of 255, rounded")
	assert_eq(img.get_pixel(2, 0).r8, 255)

## Two box passes at radius 1 over [0, 0, 100] (one pass: [0, 100, 100]
## summed over the window, divided by the window's own count of cells —
## the same clipped-window average the biome weights take) leave a ramp
## rather than a step, so a cell edge never reads as a cliff.
func test_bake_relief_smooths_across_cells() -> void:
	var cells := Image.create_empty(3, 1, false, Image.FORMAT_RGB8)
	for x in 3:
		cells.set_pixel(x, 0, Color8(x, 0, 0))
	var img := MapIndex.bake_relief(cells, PackedInt32Array([0, 0, 100]), 1, 1)
	var a := img.get_pixel(0, 0).r8
	var b := img.get_pixel(1, 0).r8
	var c := img.get_pixel(2, 0).r8
	assert_lt(a, b, "the low end rises toward the high one")
	assert_lt(b, c, "and keeps rising")
	assert_gt(a, 0, "smoothing carried some height into the flat end")

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

## Suppression must hold the detail down even where the UNsuppressed value
## would saturate the byte — the case a clamp would otherwise hide. At height
## 99 the plain byte is int(99 * 255 / 100 + 0.5) = 252, while 99 plus 19.8 of
## detail exceeds 100 and clamps to 255, so the two pixels are distinguishable:
## an implementation that ignored suppression would read 255 on both.
func test_bake_relief_suppression_holds_detail_down() -> void:
	var cells := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	cells.set_pixel(0, 0, Color8(0, 0, 0))
	cells.set_pixel(1, 0, Color8(1, 0, 0))
	var heights := PackedInt32Array([99, 99])
	var img := MapIndex.bake_relief(cells, heights, 1, 0,
		PackedFloat32Array([1.0, 1.0]), PackedFloat32Array([0.0, 1.0]), 20.0, 0.0)
	assert_eq(img.get_pixel(0, 0).r8, 252, "suppressed: the plain height of 99")
	assert_eq(img.get_pixel(1, 0).r8, 255, "unsuppressed: 99 + 19.8 of detail, clamped")

func test_bake_relief_suppression_is_visible_below_the_clamp() -> void:
	var cells := Image.create_empty(2, 1, false, Image.FORMAT_RGB8)
	cells.set_pixel(0, 0, Color8(0, 0, 0))
	cells.set_pixel(1, 0, Color8(1, 0, 0))
	var heights := PackedInt32Array([50, 50])
	var img := MapIndex.bake_relief(cells, heights, 1, 0,
		PackedFloat32Array([1.0, 1.0]), PackedFloat32Array([0.0, 1.0]), 20.0, 0.0)
	assert_eq(img.get_pixel(0, 0).r8, 128, "fully suppressed is the plain height")
	assert_gt(img.get_pixel(1, 0).r8, 128, "unsuppressed rose")

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

## The range assertion alone CANNOT FAIL — detail_field clamps to 0..1 on the
## way out — so it is paired with two checks that the generator is actually
## alive: the field must vary, and the clamp must not be doing the work. A
## broken normalisation would saturate the sheet onto its bounds, which a bare
## range check would happily pass.
func test_detail_field_stays_in_unit_range() -> void:
	var f := MapIndex.detail_field(32, 32, 7, 8.0, 4, 4.0)
	assert_eq(f.size(), 1024, "the field is w * h")
	var lo := 2.0
	var hi := -1.0
	var interior := 0
	for v in f:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		if v > 0.0 and v < 1.0:
			interior += 1
	assert_gte(lo, 0.0, "never below 0")
	assert_lte(hi, 1.0, "never above 1")
	assert_gt(hi, lo, "the field varies — a dead generator would read flat")
	assert_gt(interior, f.size() / 10, "a good share of the sheet lies strictly inside the bounds, so the clamp is not hiding a broken normalisation")

## Domain warp has to perturb the sampling, not merely be switched on: the same
## seed with and without warp must give different fields.
func test_detail_field_domain_warp_changes_the_field() -> void:
	var plain := MapIndex.detail_field(16, 16, 7, 8.0, 4, 0.0)
	var warped := MapIndex.detail_field(16, 16, 7, 8.0, 4, 8.0)
	assert_ne(Array(plain), Array(warped), "domain warp changes the sampling")
