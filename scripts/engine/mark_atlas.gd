class_name MarkAtlas
extends RefCounted
## One texture for many marks (owner 2026-09-13, the map's decor rework):
## the terrain symbols — and later the hamlets, fields and building icons —
## are packed into a single atlas at load, so a whole layer of thousands
## of marks can be ONE mesh drawn with ONE call (MarkMesh) instead of one
## draw_texture_rect per mark, which was ~7 ms a frame on the beria pack.
##
## Shelf packing: the images sorted tallest first, laid left to right in
## rows no wider than max_width, `pad` px of clear space around each so
## the mipmaps of one symbol never bleed into its neighbour. Pure data
## work on Images; the ImageTexture is made once at the end.

## The packed sheet with its mipmaps.
var texture: ImageTexture
## path -> Rect2 in 0..1 texture space.
var uv: Dictionary = {}
## path -> width / height of the source, so a mark drawn at a height keeps
## its shape.
var aspect: Dictionary = {}
## The sheet's pixel size.
var size := Vector2i.ZERO

## `textures` is path -> Texture2D (or Image). Textures that yield no image
## are left out (their marks draw nothing, as a missing PNG always has).
static func build(textures: Dictionary, pad: int = 4, max_width: int = 2048) -> MarkAtlas:
	var atlas := MarkAtlas.new()
	var images: Dictionary = {}
	for path: String in textures:
		var img := _image_of(textures[path])
		if img == null or img.get_width() <= 0 or img.get_height() <= 0:
			continue
		images[path] = img
	if images.is_empty():
		return atlas
	var order: Array = images.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		var ha: int = (images[a] as Image).get_height()
		var hb: int = (images[b] as Image).get_height()
		return ha > hb if ha != hb else a < b)
	# Shelves: [x, y, row height] as the cursor walks the rows.
	var placed: Dictionary = {}
	var x := pad
	var y := pad
	var row_h := 0
	var sheet_w := 0
	for path: String in order:
		var img: Image = images[path]
		var w := img.get_width()
		var h := img.get_height()
		if x + w + pad > max_width and x > pad:
			x = pad
			y += row_h + pad
			row_h = 0
		placed[path] = Vector2i(x, y)
		x += w + pad
		row_h = maxi(row_h, h)
		sheet_w = maxi(sheet_w, x)
	var sheet_h := y + row_h + pad
	var sheet := Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for path: String in placed:
		var img: Image = images[path]
		var at: Vector2i = placed[path]
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		atlas.uv[path] = Rect2(float(at.x) / sheet_w, float(at.y) / sheet_h,
			float(img.get_width()) / sheet_w, float(img.get_height()) / sheet_h)
		atlas.aspect[path] = float(img.get_width()) / float(img.get_height())
	sheet.generate_mipmaps()
	atlas.texture = ImageTexture.create_from_image(sheet)
	atlas.size = Vector2i(sheet_w, sheet_h)
	return atlas

## A source as an RGBA8 Image: a Texture2D's image (decompressed when the
## import compressed it) or an Image handed in directly.
static func _image_of(source: Variant) -> Image:
	var img: Image = null
	if source is Image:
		img = (source as Image).duplicate()
	elif source is Texture2D:
		img = (source as Texture2D).get_image()
	if img == null:
		return null
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img

func has(path: String) -> bool:
	return uv.has(path)
