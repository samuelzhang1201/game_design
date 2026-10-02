class_name MapCoords
extends RefCounted
## The pack's own graticule (owner 2026-10-02, spec 2026-10-02-war-room-v2
## §2.1): Azgaar's mapCoordinates — the latitudes and longitudes the map's
## edges stand at — imported into map_info.csv as lat_n / lat_s / lon_w /
## lon_e. Pack px run east and SOUTH; latitude north. A pack imported before
## the rows existed spans the whole globe (and warns once). Pure.

static var _warned := false


static func bounds(repo: DataRepository) -> Dictionary:
	var info: Dictionary = repo.map_info
	if not info.has("lat_n") and not _warned:
		_warned = true
		push_warning("map_info.csv has no lat_n / lat_s / lon_w / lon_e: the graticule spans the globe (re-import, tools/NEW_MAP.md)")
	return {"lat_n": float(info.get("lat_n", "90")), "lat_s": float(info.get("lat_s", "-90")),
		"lon_w": float(info.get("lon_w", "-180")), "lon_e": float(info.get("lon_e", "180")),
		"w": float(info.get("width", "1")), "h": float(info.get("height", "1"))}


static func px_per_deg(repo: DataRepository) -> Vector2:
	var b := bounds(repo)
	return Vector2(float(b["w"]) / maxf(float(b["lon_e"]) - float(b["lon_w"]), 0.0001),
		float(b["h"]) / maxf(float(b["lat_n"]) - float(b["lat_s"]), 0.0001))


## (longitude, latitude) of a pack px.
static func lon_lat(repo: DataRepository, px: Vector2) -> Vector2:
	var b := bounds(repo)
	var k := px_per_deg(repo)
	return Vector2(float(b["lon_w"]) + px.x / k.x, float(b["lat_n"]) - px.y / k.y)


static func px_of(repo: DataRepository, lon: float, lat: float) -> Vector2:
	var b := bounds(repo)
	var k := px_per_deg(repo)
	return Vector2((lon - float(b["lon_w"])) * k.x, (float(b["lat_n"]) - lat) * k.y)


## The `deg`-degree cell holding `px`, counted from the map's north-west corner.
static func cell_of(repo: DataRepository, px: Vector2, deg: float) -> Vector2i:
	var s := px_per_deg(repo) * deg
	return Vector2i(floori(px.x / s.x), floori(px.y / s.y))


static func cell_rect(repo: DataRepository, cell: Vector2i, deg: float) -> Rect2:
	var s := px_per_deg(repo) * deg
	return Rect2(Vector2(cell) * s, s)


## Columns and rows of `deg` cells over the map; a part cell at an edge counts.
static func grid_size(repo: DataRepository, deg: float) -> Vector2i:
	var b := bounds(repo)
	var s := px_per_deg(repo) * deg
	return Vector2i(ceili(float(b["w"]) / s.x - 0.0001), ceili(float(b["h"]) / s.y - 0.0001))


## "24°N 51°E": whole degrees, a hemisphere letter each (0 is N and E).
static func format(ll: Vector2) -> String:
	var lat := roundi(ll.y)
	var lon := roundi(ll.x)
	return "%d°%s %d°%s" % [absi(lat), "S" if lat < 0 else "N", absi(lon), "W" if lon < 0 else "E"]
