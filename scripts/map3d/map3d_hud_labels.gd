class_name Map3DHudLabels
extends Map3DHudPiece
## The kingdom names on the 3D map's HUD (owner 2026-09-18, the 2D map's
## lettering — MapLettering), under the compass, the scale bar and the ruler,
## and the player's capital named under its mark at the far view (owner
## 2026-10-12: 远景时让国都名字更突出 — capital_entry).

## The kingdoms lettered on the last draw (a test seam).
var _drawn: PackedStringArray = []
## Each kingdom's label point on the ground, {code: Vector3}, kept while the
## provinces' holders stand (perf 2026-10-02: label_anchor walks every
## province, once per kingdom per camera pose) ...
var _anchors: Dictionary = {}
var _anchors_key: Array = []
## ... and entries() and rects(), cut once per camera pose (the weather marks
## ask for rects() too).
var _entries: Array = []
var _rects: Array = []
var _pose_key: Array = []


## {code: ground point} of every kingdom's LIVE label anchor (MapOwnership.
## label_anchor), cut again when a province changes hands.
func _ground_anchors() -> Dictionary:
	var st := ctx.state()
	var key := [st.get_instance_id() if st != null else 0,
		st.province_owner.hash() if st != null else 0, ctx.repo.get_instance_id()]
	if key == _anchors_key:
		return _anchors
	_anchors = {}
	for code: String in ctx.repo.kingdoms:
		var xz := Map3DGeometry.pack_to_world(ctx.meta, MapOwnership.label_anchor(ctx.repo, st, code))
		_anchors[code] = Vector3(xz.x, ctx.height_at(xz), xz.y)
	_anchors_key = key
	return _anchors


## Whether entries() and rects() are still this pose's; marks them so.
func _same_pose() -> bool:
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(), _anchors_key]
	if key == _pose_key:
		return true
	_pose_key = key
	_entries = []
	_rects = []
	return false


## One entry {code, text, pos (design px), px, fade} per kingdom whose LIVE
## label anchor (MapOwnership.label_anchor) is ON SCREEN — a name is pinned to
## its ground and goes with it when the view leaves it (owner 2026-10-10: 国家
## 名不要总是跟随视角变动保持显示) — sized as a word map_label_scale_px pack px
## tall on the ground seen from its own distance (label_px), so it
## grows and shrinks with the land, and shown only at the far, strategic zoom:
## whole up to map_label_fade_from_px, fading out to nothing at
## map_label_hide_px (label_fade).
func entries() -> Array:
	if not bound():
		return []
	var anchors := _ground_anchors()
	if _same_pose() and not _entries.is_empty():
		return _entries
	var out: Array = []
	var repo := ctx.repo
	var camera := ctx.camera
	var s := ctx.viewport_px_scale()
	var height_m := repo.bal("map_label_scale_px") * float(ctx.meta.get("m_per_px", 0.0))
	var eye := camera.global_position
	var frame := Rect2(Vector2.ZERO, ctx.view_size)
	for code: String in repo.kingdoms:
		var ground: Vector3 = anchors[code]
		if camera.is_position_behind(ground):
			continue
		var pos := camera.unproject_position(ground) / s
		if not frame.has_point(pos):
			continue
		var mpp := Map3DGeometry.metres_per_pixel(eye.distance_to(ground),
			repo.bal("map3d_fov_deg"), maxf(ctx.view_size.y, 1.0))
		var px := label_px(height_m, mpp, repo.bal("map_label_min_px"))
		var fade := label_fade(px, repo.bal("map_label_fade_from_px"),
			repo.bal("map_label_hide_px"))
		if px <= 0.0 or fade <= 0.0:
			continue
		out.append({"code": code, "text": String(repo.kingdoms[code]["label"]), "pos": pos,
			"px": px, "fade": fade})
	_entries = out
	return out


## The player's capital named under its mark {code: "capital:<burg>", text,
## pos, px, fade}, or {} — while the realm still holds its province, its mark
## on screen and the view far enough out. Unlike a kingdom name it keeps ONE
## screen size, map_capital_label_px (a word the ground's size would be a
## giant at the opening view and a speck far out), and is the far view's
## lettering by the camera's metres per px: whole down to
## map_capital_label_fade_mpp, gone at map_capital_label_hide_mpp
## (capital_fade); set map_capital_label_drop of its own height off the mark
## (above it, clear of a fleet's counter in the harbour), or
## map_capital_label_drop_clear when a kingdom's name already stands there.
func capital_entry() -> Dictionary:
	if not bound():
		return {}
	var repo := ctx.repo
	var realm := repo.resolve_realm("player_realm")
	var burg: Dictionary = repo.burgs.get(String((repo.kingdoms.get(realm, {}) as Dictionary)
		.get("capital_burg", "")), {})
	if burg.is_empty() \
			or MapOwnership.owner_of(repo, ctx.state(), String(burg.get("province_code", ""))) != realm:
		return {}
	var xz := Map3DGeometry.pack_to_world(ctx.meta, Vector2(float(burg["x"]), float(burg["y"])))
	var ground := Vector3(xz.x, ctx.height_at(xz), xz.y)
	var camera := ctx.camera
	if camera.is_position_behind(ground):
		return {}
	var at := camera.unproject_position(ground) / ctx.viewport_px_scale()
	if not Rect2(Vector2.ZERO, ctx.view_size).has_point(at):
		return {}
	var mpp := Map3DGeometry.metres_per_pixel(camera.global_position.distance_to(ground),
		repo.bal("map3d_fov_deg"), maxf(ctx.view_size.y, 1.0))
	var px := repo.bal("map_capital_label_px")
	var fade := capital_fade(mpp, repo.bal("map_capital_label_fade_mpp"),
		repo.bal("map_capital_label_hide_mpp"))
	if px <= 0.0 or fade <= 0.0:
		return {}
	var text := String(burg["label"])
	var pos := at + Vector2(0.0, px * repo.bal("map_capital_label_drop"))
	var box := MapLettering.box_centred(repo, UiPalette.header_font(), text, pos, px)
	var font := UiPalette.map_label_font()
	for e: Dictionary in entries():
		if font != null and box.intersects(MapLettering.box_centred(repo, font, String(e["text"]),
				e["pos"], float(e["px"]))):
			pos = at + Vector2(0.0, px * repo.bal("map_capital_label_drop_clear"))
			break
	return {"code": "capital:" + String(burg["burg_code"]), "text": text, "pos": pos, "px": px,
		"fade": fade}


## How much of the capital's name shows with the camera at `m_per_px`: whole
## at or above `fade_mpp`, fading to nothing at `hide_mpp` as the view comes in.
static func capital_fade(m_per_px: float, fade_mpp: float, hide_mpp: float) -> float:
	if m_per_px >= fade_mpp:
		return 1.0
	if m_per_px <= hide_mpp or fade_mpp <= hide_mpp:
		return 0.0
	return (m_per_px - hide_mpp) / (fade_mpp - hide_mpp)


## A kingdom name's size in screen px: a word `height_m` tall on the ground
## seen at `m_per_px` — it scales with the ground, never held to one size —
## and 0 (hidden) below `min_px`.
static func label_px(height_m: float, m_per_px: float, min_px: float) -> float:
	var px := height_m / maxf(m_per_px, 0.0001)
	return 0.0 if px < min_px else px


## How much of a kingdom name shows at `px` (label_px): whole up to
## `fade_from_px`, fading out to nothing at `hide_px` — a name is the far,
## strategic view's lettering and is gone close in.
static func label_fade(px: float, fade_from_px: float, hide_px: float) -> float:
	if px >= hide_px:
		return 0.0
	if px <= fade_from_px or hide_px <= fade_from_px:
		return 1.0
	return (hide_px - px) / (hide_px - fade_from_px)


## The boxes the names are lettered in, in design px (the weather marks keep
## off them).
func rects() -> Array:
	if not bound():
		return []
	var list := entries()
	if not _rects.is_empty() or list.is_empty():
		return _rects
	var font := UiPalette.map_label_font()
	if font == null:
		return []
	for e: Dictionary in list:
		_rects.append(MapLettering.box_centred(ctx.repo, font, String(e["text"]), e["pos"], float(e["px"])))
	if capital_rect().has_area():
		_rects.append(capital_rect())
	return _rects


## The box the capital's name is lettered in, in design px, or an empty Rect2
## (a fleet's counter in its harbour keeps off it — Map3DHudArmies).
func capital_rect() -> Rect2:
	var cap := capital_entry()
	if cap.is_empty():
		return Rect2()
	return MapLettering.box_centred(ctx.repo, UiPalette.header_font(), String(cap["text"]),
		cap["pos"], float(cap["px"]))


func drawn() -> PackedStringArray:
	return _drawn


## Letter the names, upright and faint, the way the 2D map letters them.
func _draw() -> void:
	if not bound():
		return
	_drawn.clear()
	var font := UiPalette.map_label_font()
	if font == null:
		return
	var frame := Rect2(Vector2.ZERO, ctx.view_size)
	for e: Dictionary in entries():
		if MapLettering.draw_centred(self, ctx.repo, font, String(e["text"]), e["pos"],
				float(e["px"]), frame, float(e["fade"])):
			_drawn.append(String(e["code"]))
	# the capital in the names' small capitals, not the kingdoms' blackletter
	var cap := capital_entry()
	if not cap.is_empty() and MapLettering.draw_centred(self, ctx.repo, UiPalette.header_font(),
			String(cap["text"]), cap["pos"], float(cap["px"]), frame, float(cap["fade"])):
		_drawn.append(String(cap["code"]))
