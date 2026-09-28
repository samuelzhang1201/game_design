class_name MissiveArt
extends RefCounted
## The Missive board's art pieces (library U-20..U-26, spec
## 2026-09-28-courier-art §5): missive_art.csv names a texture and its
## nine-slice margin in texture px; a piece with no texture, or one that does
## not load, keeps the caller's flat fallback — never a hole.


static func texture(repo: DataRepository, key: String) -> Texture2D:
	var path := String(repo.missive_art.get(key, ""))
	return UiPalette.load_art(path) if path != "" else null


static func style(repo: DataRepository, key: String, fallback: StyleBox) -> StyleBox:
	var tex := texture(repo, key)
	if tex == null:
		return fallback
	var s := StyleBoxTexture.new()
	s.texture = tex
	var m := float(int(repo.missive_margin.get(key, 0)))
	s.texture_margin_left = m
	s.texture_margin_top = m
	s.texture_margin_right = m
	s.texture_margin_bottom = m
	if fallback != null:  # keep the fallback's content margins so text sits where it did
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			s.set_content_margin(side, fallback.get_content_margin(side))
	return s
