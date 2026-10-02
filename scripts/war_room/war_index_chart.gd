class_name WarIndexChart
extends RefCounted
## The graticule index (owner 2026-10-02, spec 2026-10-02-war-room-v2 §2.3):
## the island as inked dots, every war_sheet_deg cell ruled faint, the sea's
## cells washed, the land's framed in rubric; a click on a land cell lays its
## sheet (after the war marker is tossed onto it). Pure: an Image and a pick
## (the letters and numbers are Label3Ds, WarRoomWall).


static func image(repo: DataRepository, px: int) -> Image:
	var w := float(repo.map_info.get("width", "1"))
	var h := float(repo.map_info.get("height", "1"))
	var ih := int(round(float(px) * h / w))
	var img := Image.create(px, ih, true, Image.FORMAT_RGBA8)
	var paper: Color = repo.war_palette["paper"]
	img.fill(paper)
	var k := float(px) / w
	var deg := repo.bal("war_sheet_deg")
	var g := MapCoords.grid_size(repo, deg)
	var sea := paper.darkened(repo.bal("war_chart_sea_shade"))
	var land_cells: Dictionary = {}
	for s: Dictionary in WarSheets.series(repo):
		land_cells[Vector2i(int(s["col"]), int(s["row"]))] = true
	var whole := Rect2i(0, 0, px, ih)
	for row in g.y:
		for col in g.x:
			if not land_cells.has(Vector2i(col, row)):
				var r := MapCoords.cell_rect(repo, Vector2i(col, row), deg)
				img.fill_rect(Rect2i(Vector2i(r.position * k), Vector2i(r.size * k) + Vector2i.ONE).intersection(whole), sea)
	var ink: Color = repo.war_palette["ink"]
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		var c := MapTerrain.cell_center(repo, cell) * k
		img.fill_rect(Rect2i(int(c.x), int(c.y), 2, 2).intersection(whole), ink)
	var faint: Color = repo.war_palette["ink_faint"]
	for col in g.x + 1:
		var x := clampi(int(MapCoords.cell_rect(repo, Vector2i(col, 0), deg).position.x * k), 0, px - 1)
		img.fill_rect(Rect2i(x, 0, 1, ih), faint)
	for row in g.y + 1:
		var y := clampi(int(MapCoords.cell_rect(repo, Vector2i(0, row), deg).position.y * k), 0, ih - 1)
		img.fill_rect(Rect2i(0, y, px, 1), faint)
	var rubric: Color = repo.war_palette["rubric"]
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["cell"]
		var a := Vector2i(r.position * k).clamp(Vector2i.ZERO, Vector2i(px - 1, ih - 1))
		var b := (Vector2i(r.end * k) - Vector2i(1, 1)).clamp(Vector2i.ZERO, Vector2i(px - 1, ih - 1))
		img.fill_rect(Rect2i(a.x, a.y, b.x - a.x + 1, 1), rubric)
		img.fill_rect(Rect2i(a.x, b.y, b.x - a.x + 1, 1), rubric)
		img.fill_rect(Rect2i(a.x, a.y, 1, b.y - a.y + 1), rubric)
		img.fill_rect(Rect2i(b.x, a.y, 1, b.y - a.y + 1), rubric)
	img.generate_mipmaps()
	return img


## The sheet whose cell holds a chart UV (0..1 across the map), -1 on a sea
## cell or off the map.
static func sheet_at_uv(repo: DataRepository, uv: Vector2) -> int:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return -1
	var p := uv * Vector2(float(repo.map_info.get("width", "1")), float(repo.map_info.get("height", "1")))
	var at := MapCoords.cell_of(repo, p, repo.bal("war_sheet_deg"))
	for s: Dictionary in WarSheets.series(repo):
		if int(s["col"]) == at.x and int(s["row"]) == at.y:
			return int(s["index"])
	return -1


## A sheet's cell over the map, in chart UV.
static func uv_of_cell(repo: DataRepository, sheet: Dictionary) -> Rect2:
	var size := Vector2(float(repo.map_info.get("width", "1")), float(repo.map_info.get("height", "1")))
	var c: Rect2 = sheet["cell"]
	return Rect2(c.position / size, c.size / size)
