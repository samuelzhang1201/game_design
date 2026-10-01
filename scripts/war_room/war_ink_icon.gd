class_name WarInkIcon
extends RefCounted
## A coloured still-life icon redrawn as sepia ink on clear (owner ruling
## 2026-10-01, spec §4: the folio's arms are small ink drawings): the icon's own
## alpha keeps its outline, and its light areas let the vellum through, so only
## its darks are inked. Pure; the caller passes the ink and how much of the
## lightest areas to keep.

static func inked(tex: Texture2D, ink: Color, light_keep: float) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()   # an imported icon carries its own colour mip levels, which a small draw would show
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			img.set_pixel(x, y, Color(ink, c.a * lerpf(1.0, light_keep, lum)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
