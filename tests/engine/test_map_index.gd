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
