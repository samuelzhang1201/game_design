class_name Map3DDuel
extends RefCounted
## Front-rank infantry duels (spec 2026-11-16-infantry-duel-animation-design.md;
## owner: 主要是要临场感，可以做成好看但和数字无关的表演). Pure: which figures pair,
## and each pair's hashed turns (Map3DMarchLag.unit), so a replay looks the same.
## View-only: the engine never sees it.


## `art`'s `contact`: clip -> the share of its length where the blade meets
## (a strike), the shield is fully up (BLOCK) or the jolt lands (HIT).
static func contact_of(art: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for part: String in String(art.get("contact", "")).split(";", false):
		var kv := part.split(":", false)
		if kv.size() == 2 and kv[1].strip_edges().is_valid_float():
			out[kv[0].strip_edges()] = float(kv[1])
	return out
