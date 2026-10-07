class_name WarDetailInk
extends RefCounted
## The near-zoom detail patch's rules (spec 2026-10-07-war-room-scale-hover §2):
## its level by the camera's distance, the rect it covers, when it is redrawn.
## Pure; the view owns the viewport.


static func level(repo: DataRepository, distance_m: float) -> int:
	var t := repo.bal("war_detail_level_m")
	if distance_m >= t:
		return 0
	if distance_m >= t * 0.5:
		return 1
	if distance_m >= t * 0.25:
		return 2
	return 3


## The patch round `centre_px` over a view `view_px` wide (pack px), the view
## times war_detail_cover, its corner snapped to a grid of view x
## war_detail_inner so a small pan keeps it; held inside the sheet's rect.
static func patch_rect(repo: DataRepository, sheet_rect: Rect2, centre_px: Vector2, view_px: Vector2) -> Rect2:
	var size := view_px * repo.bal("war_detail_cover")
	var grid := view_px * repo.bal("war_detail_inner")
	var corner := centre_px - size * 0.5
	corner = Vector2(floorf(corner.x / grid.x) * grid.x, floorf(corner.y / grid.y) * grid.y)
	var r := Rect2(corner, size + grid)   # one grid step of slack so the centre stays inside after the snap
	r.size = r.size.min(sheet_rect.size)   # never past the sheet (leaning out, the view is wider than the table)
	r.position = r.position.clamp(sheet_rect.position, sheet_rect.end - r.size)
	return r


static func needs_redraw(old: Dictionary, now: Dictionary) -> bool:
	return int(old.get("level", -1)) != int(now.get("level", -1)) or old.get("rect") != now.get("rect") \
		or int(old.get("key", -1)) != int(now.get("key", -1))
