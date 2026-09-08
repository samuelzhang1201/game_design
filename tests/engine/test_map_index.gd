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
