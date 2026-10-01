class_name WarIndexChart
extends RefCounted
## The sheet index on the war room's wall (spec 2026-10-01-war-room-design §2):
## the island as inked dots, every sheet's frame; a click on it lays that
## sheet. Pure: an Image and a pick (the numerals are Label3Ds, WarRoomWall).


static func image(repo: DataRepository, px: int) -> Image:
	var w := float(repo.map_info.get("width", "1"))
	var h := float(repo.map_info.get("height", "1"))
	var ih := int(round(float(px) * h / w))
	var img := Image.create(px, ih, true, Image.FORMAT_RGBA8)
	img.fill(repo.war_palette["paper"])
	var k := float(px) / w
	var ink: Color = repo.war_palette["ink"]
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		var c := MapTerrain.cell_center(repo, cell) * k
		img.fill_rect(Rect2i(int(c.x), int(c.y), 2, 2), ink)
	var rubric: Color = repo.war_palette["rubric"]
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["rect"]
		var a := Vector2i(r.position * k)
		var b := Vector2i(r.end * k) - Vector2i(1, 1)
		img.fill_rect(Rect2i(a.x, a.y, b.x - a.x, 2), rubric)
		img.fill_rect(Rect2i(a.x, b.y - 1, b.x - a.x, 2), rubric)
		img.fill_rect(Rect2i(a.x, a.y, 2, b.y - a.y), rubric)
		img.fill_rect(Rect2i(b.x - 1, a.y, 2, b.y - a.y), rubric)
	img.generate_mipmaps()
	return img


## The sheet under a chart UV (0..1 across the map), -1 off the map.
static func sheet_at_uv(repo: DataRepository, uv: Vector2) -> int:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return -1
	var p := uv * Vector2(float(repo.map_info.get("width", "1")), float(repo.map_info.get("height", "1")))
	return WarSheets.sheet_of(repo, p)
