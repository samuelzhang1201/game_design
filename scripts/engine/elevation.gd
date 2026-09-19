class_name Elevation
extends RefCounted
## Height as numbers (owner 2026-09-19, spec
## docs/superpowers/specs/2026-09-19-map3d-heights-design.md): the pack's
## CELL height in metres, the supply tier it falls in, and (§3) the named
## high and low points. Pure and deterministic; the 3D mesh's synthesized
## ridges are look only and never enter here. Caches are per pack, forgotten
## by DataRepository.load_map.

static var _landmarks: Array = []
static var _landmarks_map := ""


static func forget() -> void:
	_landmarks = []
	_landmarks_map = ""


## Whole metres above the waterline of an Azgaar height (negative under it).
static func metres_of_height(repo: DataRepository, height: float) -> int:
	return int(round((height - repo.bal("elevation_sea_level")) * repo.bal("elevation_m_per_unit")))


## A cell's metres; 0 for no cell.
static func metres_of_cell(repo: DataRepository, id: int) -> int:
	if not repo.cells.has(id):
		return 0
	return metres_of_height(repo, float(repo.cells[id]["height"]))


## {tier, supply_permille}: the first row of army_height_supply.csv, highest
## first, whose min_height the height reaches.
static func tier_of(repo: DataRepository, height: float) -> Dictionary:
	for r: Dictionary in repo.army_height_supply:
		if height >= float(r["min_height"]):
			return {"tier": String(r["tier"]), "supply_permille": int(r["supply_permille"])}
	return {"tier": "plains", "supply_permille": 1000}
