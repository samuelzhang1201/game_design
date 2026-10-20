class_name TaskCoverage
extends RefCounted
## The search coverage of an area task (P6.1a, spec 2026-10-16 battle-system §13.2):
## the map is cut into square cells of balance `task_cell_m` whole metres, and a
## coverage Dictionary maps "x:y" to the newest day the cell was searched. Pure
## integers; geometric coverage never means "no enemy there".


static func _cell_m(repo: DataRepository) -> int:
	return maxi(1, int(repo.bal("task_cell_m")))


static func _floor_div(a: int, b: int) -> int:
	return a / b - (1 if a % b < 0 else 0)


static func cell_of(repo: DataRepository, at_m: Vector2i) -> Vector2i:
	var c: int = _cell_m(repo)
	return Vector2i(_floor_div(at_m.x, c), _floor_div(at_m.y, c))


## Every cell whose CENTRE is within radius_m of center_m (inclusive), by (y, x).
static func cells_in_circle(repo: DataRepository, center_m: Vector2i, radius_m: int) -> Array[Vector2i]:
	var c: int = _cell_m(repo)
	var out: Array[Vector2i] = []
	if radius_m < 0:
		return out
	var lo: Vector2i = cell_of(repo, center_m - Vector2i(radius_m, radius_m))
	var hi: Vector2i = cell_of(repo, center_m + Vector2i(radius_m, radius_m))
	var r2: int = radius_m * radius_m
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var dx: int = cx * c + c / 2 - center_m.x
			var dy: int = cy * c + c / 2 - center_m.y
			if dx * dx + dy * dy <= r2:
				out.append(Vector2i(cx, cy))
	return out


static func _key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


static func mark(coverage: Dictionary, cells: Array[Vector2i], day: int) -> void:
	for cell in cells:
		var k: String = _key(cell)
		coverage[k] = maxi(int(coverage.get(k, -1)), day)


static func searched_cells(coverage: Dictionary) -> int:
	return coverage.size()


static func last_searched(coverage: Dictionary, cell: Vector2i) -> int:
	return int(coverage.get(_key(cell), -1))
