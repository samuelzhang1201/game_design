class_name Map3DPicker
extends RefCounted
## What a point of the 3D view names, and the hover (spec 2026-09-20 §1): the
## pick ranking of the click and the hover, the index bitmaps under the ground,
## and the hover's name beside the cursor and the hovered kingdom. The view
## re-emits kingdom_changed as its own country_hovered.

signal kingdom_changed(code: String)

const TOOLTIP_OFFSET := Vector2(20.0, 24.0)

var ctx: Map3DContext
var view: Map3DView
var tooltip: Label
var borders: Map3DLayerBorders
var _province_image: Image
var _cell_image: Image
var _hover_pos := Vector2.ZERO
var _hover_pending := false
var _hover_kingdom := ""
var _hover_obj: Dictionary = {}


func bind(p_ctx: Map3DContext, p_view: Map3DView, p_tooltip: Label,
		p_borders: Map3DLayerBorders) -> void:
	ctx = p_ctx
	view = p_view
	tooltip = p_tooltip
	borders = p_borders


## What a click at `pos` picks: {"kind": "burg", "code"} for a settlement
## within map3d_pick_px of it (or on its ring), {"kind": "province", "code"}
## for the province under it, {} for the sea or the sky.
##
## Only a SHOWN ring is picked (final review, owner 2026-09-18): a burg whose
## camera distance has reached its tier's max_view_m x map3d_ring_fade_start
## — where settlement_ring.gdshader begins to fade it — is skipped, so a
## click on a thinned village's empty spot names the province under it.
##
## The burg distance is measured in SCREEN px (the camera's own projection of
## each burg's ground point), not by unprojecting the click to world XZ and
## comparing world distances: at a steep near-zoom grazing angle a small
## terrain-height error swings the raycast's XZ landing point by far more
## than the ring's own on-screen radius, so a world-space reach either picked
## nothing (fix round 1, owner 2026-09-18) or had to be absurdly generous.
## Screen space matches what the player is actually aiming at, a ring of
## constant screen size, and needs no distance conversion at all.
func pick_at(pos: Vector2) -> Dictionary:
	var hit: Variant = ctx.ground_at(pos)
	if hit == null:
		return {}
	var p := hit as Vector3
	var xz := Vector2(p.x, p.z)
	var best := ""
	var best_d := INF
	# A regiment is picked first, as on the 2D map. Its 3D PIECE comes before
	# its counter: the piece is the big thing the player is aiming at, and
	# under MILITARY the counter has shrunk to a headcount chip over its head.
	for code: String in view.unit_rects():
		if (view.unit_rects()[code] as Rect2).has_point(pos):
			return {"kind": "army", "code": code}
	# ...anywhere on the counter, or within map_army_pick_px of its point.
	var armies := view.army_markers()
	for i in range(armies.size() - 1, -1, -1):
		if (armies[i]["rect"] as Rect2).has_point(pos):
			return {"kind": "army", "code": String(armies[i]["code"])}
	for i in range(armies.size() - 1, -1, -1):
		if (armies[i]["pos"] as Vector2).distance_to(pos) <= ctx.repo.bal("map_army_pick_px"):
			return {"kind": "army", "code": String(armies[i]["code"])}
	# An output badge names the settlement whose output it shows (as on the
	# 2D map), over whatever lies under it.
	for b: Dictionary in view.manor_badges():
		if (b["rect"] as Rect2).has_point(pos):
			return {"kind": "burg", "code": String(b["burg"])}
	for e: Dictionary in ctx.projected_settlements():
		if not bool(e["shown"]):
			continue
		var code := String(e["code"])
		var dist_m := ctx.camera.global_position.distance_to(e["world"] as Vector3)
		var reach := ctx.pick_reach_px(code, e["spec"], dist_m)
		var d := (e["screen"] as Vector2).distance_to(pos)
		if d <= reach and d < best_d:
			best_d = d
			best = code
	# Under HEIGHTS a high or low point (spec 2026-09-19-map3d-heights), ranked
	# against the settlements (Task 7; simplified owner 2026-09-20, change 3:
	# pick_reach_px is now the settlement's ONE click geometry, no longer a
	# tighter "exact dot" inside a looser "click floor" — a settlement within
	# reach always beats a mark, a mark's own box beats its grown rect).
	if best != "":
		return {"kind": "burg", "code": best}
	var marks := view.landmark_marks() if view.heat_on() else []
	for mk: Dictionary in marks:
		if (mk["rect"] as Rect2).has_point(pos):
			return {"kind": "landmark", "cell": int(mk["cell"])}
	var grow := ctx.repo.bal("map3d_pick_px") * 0.5
	for mk: Dictionary in marks:
		if (mk["rect"] as Rect2).grow(grow).has_point(pos):
			return {"kind": "landmark", "cell": int(mk["cell"])}
	# Under MANORS the land means its MANOR, as on the 2D map.
	if view.manor_theme() == "manors":
		var cell := cell_at(ctx.to_pack(xz))
		return {"kind": "manor", "cell": cell} if cell >= 0 else {}
	var province := province_at(ctx.to_pack(xz))
	return {"kind": "province", "code": province} if province != "" else {}


## The province at a pack pixel (the province index bitmap), "" off the land.
func province_at(pack_px: Vector2) -> String:
	if _province_image == null:
		var path := ctx.repo.province_texture_path
		if path == "" or not ResourceLoader.exists(path):
			return ""
		_province_image = (load(path) as Texture2D).get_image()
	var p := Vector2i(pack_px.floor())
	if p.x < 0 or p.y < 0 or p.x >= _province_image.get_width() or p.y >= _province_image.get_height():
		return ""
	return String(ctx.repo.province_by_id(MapIndex.id_at(_province_image, p)).get("province_code", ""))


## The manor at a pack pixel (world_cell_index.png), or -1 for water, the
## map's edge or land no manor covers.
func cell_at(pack_px: Vector2) -> int:
	if _cell_image == null:
		var path := ctx.repo.cell_texture_path
		if path == "" or not ResourceLoader.exists(path):
			return -1
		_cell_image = (load(path) as Texture2D).get_image()
	var p := Vector2i(pack_px.floor())
	if p.x < 0 or p.y < 0 or p.x >= _cell_image.get_width() or p.y >= _cell_image.get_height():
		return -1
	var id := MapIndex.id_at(_cell_image, p)
	return id if ctx.repo.manors.has(id) else -1


## The kingdom holding what a pick names, NOW (MapOwnership, so a conquest
## moves it): a settlement's province's holder, a province's holder, "" for
## the sea or the sky — WorldMapView._state_of's rule.
static func kingdom_of_pick(repo: DataRepository, state: GameState, picked: Dictionary) -> String:
	var province := ""
	match String(picked.get("kind", "")):
		"burg":
			province = String((repo.burgs.get(String(picked["code"]), {}) as Dictionary)
				.get("province_code", ""))
		"province":
			province = String(picked["code"])
		"manor", "landmark":
			province = MapManors.province_of(repo, int(picked["cell"]), state)
		"army":
			var k := String(ArmySystem.regiment(repo, String(picked["code"])).get("kingdom_code", ""))
			return k if repo.kingdoms.has(k) else ""
	if province == "":
		return ""
	var holder := MapOwnership.owner_of(repo, state, province)
	return holder if repo.kingdoms.has(holder) else ""


## Pick the hover at `pos` on the next step().
func request(pos: Vector2) -> void:
	_hover_pos = pos
	_hover_pending = true


## Pick the hover again at the last position on the next step(): the ground
## moved under a still pointer.
func repick() -> void:
	_hover_pending = true


## Once a frame: the pending hover, picked.
func step() -> void:
	if _hover_pending:
		_hover_pending = false
		hover_pick(pick_at(_hover_pos), _hover_pos)


## A pick at `pos` (design px) as the hover: the settlement's name beside the
## cursor, and — only when it changes — the kingdom's wider outline and
## kingdom_changed. Public: tests drive it without a ray.
func hover_pick(picked: Dictionary, pos: Vector2) -> void:
	# Before bind there is no repo to name a pick with (the view clears the
	# hover before its world loads): only the empty pick, which needs none.
	if ctx == null and not picked.is_empty():
		return
	var repo: DataRepository = ctx.repo if ctx != null else null
	var state: GameState = ctx.state() if ctx != null else null
	var obj: Dictionary = picked if String(picked.get("kind", "")) in ["burg", "manor", "army", "landmark"] else {}
	if obj != _hover_obj:
		_hover_obj = obj
		var label := MapObjects.label_of(repo, obj, state)
		tooltip.text = label
		tooltip.visible = label != ""
	if tooltip.visible:
		var tip := tooltip.get_combined_minimum_size()
		tooltip.size = tip
		var room := ctx.view_size if ctx != null else Vector2.ZERO
		tooltip.position = (pos + TOOLTIP_OFFSET).clamp(Vector2.ZERO, (room - tip).max(Vector2.ZERO))
	var kingdom := kingdom_of_pick(repo, state, picked)
	if kingdom == _hover_kingdom:
		return
	_hover_kingdom = kingdom
	if borders != null and ctx != null:
		borders.draw_hover(kingdom)
	kingdom_changed.emit(kingdom)


## No hover: the pointer left, a drag began, or the view was hidden.
func clear_hover() -> void:
	_hover_pending = false
	if tooltip != null:
		hover_pick({}, Vector2.ZERO)


func hovered_kingdom() -> String:
	return _hover_kingdom


## The tooltip's text while a settlement is hovered ("" otherwise).
func hover_tooltip() -> String:
	return tooltip.text if tooltip.visible else ""


## Test seam: where the tooltip sits, in view coordinates.
func tooltip_rect() -> Rect2:
	return Rect2(tooltip.position, tooltip.get_combined_minimum_size())
