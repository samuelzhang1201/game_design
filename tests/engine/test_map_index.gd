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
