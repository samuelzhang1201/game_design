class_name WarMarks
extends RefCounted
## The map's points of interest the WAR ROOM inks (spec
## 2026-10-07-war-room-p2-tactical-layer §1): a geography/markers.csv row whose
## type data/war_marks.csv lists, on the layer it names. Public geography: no
## intel gate. Pure; marks in code order.

## Every glyph the WAR ROOM can draw (WarMarkGlyph); data/war_marks.csv may
## name no other.
const GLYPHS := ["crossed_swords", "galley", "pick", "tankard", "pennon", "broken_column",
	"tower_light", "dot"]


static func km_per_px(repo: DataRepository) -> float:
	return float(ArmySystem.metres_per_pack_px(repo)) / 1000.0


## The inked marks on `layer` ("sheet", "fine", or "" for both), code order.
static func inked(repo: DataRepository, layer: String) -> Array:
	var out: Array = []
	var codes: Array = repo.markers.keys()
	codes.sort()
	for code: String in codes:
		var m: Dictionary = repo.markers[code]
		var row: Dictionary = repo.war_marks.get(String(m.get("type", "")), {})
		if row.is_empty() or (layer != "" and String(row["layer"]) != layer):
			continue
		out.append({"code": code, "label": String(m.get("label", code)), "type": String(m["type"]),
			"at": Vector2(float(m["x"]), float(m["y"])), "glyph": String(row["glyph"]),
			"note": String(row["note"]), "legend": String(m.get("legend", ""))})
	return out


## The inked marks within `km` of `at`, nearest first (ties in code order), at
## most `max_n`, each with its `distance_km`.
static func near(repo: DataRepository, at: Vector2, km: float, max_n: int) -> Array:
	var per_px := km_per_px(repo)
	var out: Array = []
	for m: Dictionary in inked(repo, ""):
		var d := (m["at"] as Vector2).distance_to(at) * per_px
		if d <= km:
			var e := m.duplicate()
			e["distance_km"] = d
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance_km"]) < float(b["distance_km"]) \
			or (float(a["distance_km"]) == float(b["distance_km"]) and String(a["code"]) < String(b["code"])))
	return out.slice(0, max_n)
