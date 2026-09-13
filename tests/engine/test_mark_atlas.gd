extends GutTest
## MarkAtlas (owner 2026-09-13, the decor rework): many small images packed
## into one sheet with padding, each findable again by its uv rectangle.

func _img(w: int, h: int, c: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img

func test_every_image_lands_on_the_sheet_without_touching_another() -> void:
	var atlas := MarkAtlas.build({
		"a": _img(64, 32, Color.RED), "b": _img(16, 16, Color.GREEN),
		"c": _img(40, 20, Color.BLUE), "d": ImageTexture.create_from_image(_img(8, 48, Color.YELLOW))},
		4, 96)
	assert_not_null(atlas.texture)
	assert_eq(atlas.uv.size(), 4)
	assert_almost_eq(float(atlas.aspect["a"]), 2.0, 0.001)
	assert_almost_eq(float(atlas.aspect["d"]), 8.0 / 48.0, 0.001)
	var sheet := atlas.texture.get_image()
	assert_eq(sheet.get_width(), atlas.size.x)
	var rects: Array = []
	for path: String in atlas.uv:
		var r: Rect2 = atlas.uv[path]
		assert_true(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= 1.0 and r.end.y <= 1.0,
			"%s inside the sheet" % path)
		for other: Rect2 in rects:
			assert_false(r.intersects(other), "%s does not touch another" % path)
		rects.append(r)
	# The rectangle finds its own pixels back.
	var ra: Rect2 = atlas.uv["a"]
	var centre := Vector2i(int((ra.position.x + ra.size.x * 0.5) * sheet.get_width()),
		int((ra.position.y + ra.size.y * 0.5) * sheet.get_height()))
	assert_eq(sheet.get_pixelv(centre), Color.RED)
	var rd: Rect2 = atlas.uv["d"]
	assert_almost_eq(rd.size.x * sheet.get_width(), 8.0, 0.01, "d keeps its width")
	assert_almost_eq(rd.size.y * sheet.get_height(), 48.0, 0.01)
	# Padding: the sheet is wider than the images alone, and the second row
	# (96 max width) starts below the first.
	# Row 1: d (48 high) and a; c (40 wide) would pass 96, so row 2 starts
	# at 4 + 48 + 4 = 56 and holds c and b: 56 + 20 + 4 = 80.
	assert_eq(atlas.size.y, 80, "two rows")
	assert_almost_eq((atlas.uv["c"] as Rect2).position.y * 80.0, 56.0, 0.01, "c on the second row")

func test_an_empty_or_useless_set_builds_nothing() -> void:
	var none := MarkAtlas.build({})
	assert_null(none.texture)
	assert_true(none.uv.is_empty())
	var bad := MarkAtlas.build({"x": null, "y": 3})
	assert_null(bad.texture)
	assert_false(bad.has("x"))
