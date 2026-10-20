class_name MarchPath
extends RefCounted
## The way round ground a land column cannot climb (owner 2026-10-10: 如果山坡
## 斜度超过一定限制，军队必须走最近的绕道; spec 2026-10-10-march-slope-detour).
##
## The grid is the pack's geography/march_grid.png (tools/map3d/
## bake_march_grid.py, from the heights the 3D world is built from): a cell
## every army_march_grid_px pack px holding the steepest rise per run in it, in
## hundredths, or WATER. A cell steeper than army_max_slope, or water, is
## CLOSED. A march whose straight line crosses no closed cell walks it as ever;
## one that does takes the SHORTEST way round them (最近的绕道: distance alone;
## the ground's pace is the march's own, day by day, never the choice): A*
## eight ways over the open cells, then the cells pulled taut into a few
## straight legs by line of sight. Every cost and estimate is a whole number,
## so the engine's float search adds them exactly: the same grid and ends give
## the same road on every machine. Cached per pack (forgotten by load_map); a
## grid's A* is built the first time a road is needed.

const WATER := 255
## A step's cost: straight, and diagonal (7 / 5 ~ the root of two). Whole
## and small, so the engine's float A* adds them exactly (far below 2^24).
const STEP := 5
const DIAGONAL := 7

var cols := 0
var rows := 0
var cell_m := 1          # metres of the pack's measure per cell
var closed := PackedByteArray()
var water := PackedByteArray()       # 1 per WATER cell (open to a courier's grid, closed to a column's)
var water_open := false              # true: water is no barrier (couriers and wagons), a scarp still is
var _snap := 0                       # army_march_snap_cells
var _astar: _Grid = null
var _piece := PackedInt32Array()     # per cell: its piece of open ground, -1 closed
var _found: Dictionary = {}          # "start,goal" cell ids -> Array of Vector2i cells

static var _cached: Dictionary = {}  # "map id:army_max_slope:open|land" -> MarchPath (null: no grid)


## A* over the cells, eight ways (a diagonal only past two open sides): a
## straight step costs STEP, a diagonal DIAGONAL (7 / 5 for the root of two),
## the estimate the octile distance in the same units — all whole numbers.
class _Grid extends AStarGrid2D:
	func _estimate_cost(a: Vector2i, b: Vector2i) -> float:
		var dx := absi(a.x - b.x)
		var dy := absi(a.y - b.y)
		return float(DIAGONAL * mini(dx, dy) + STEP * absi(dx - dy))

	func _compute_cost(a: Vector2i, b: Vector2i) -> float:
		return float(DIAGONAL if a.x != b.x and a.y != b.y else STEP)


static func forget() -> void:
	_cached.clear()


## The pack's grid, read once per pack and army_max_slope; null when the pack
## has none (a fresh pack before its build) or army_march_grid_px is 0 (open
## country: a test of the march's own mechanics) — every march then walks the
## straight line.
## `water_open` is the courier's and the supply wagon's grid (owner 2026-10-11:
## crossing water is fine; only a scarp turns them): water cells are open.
## Armies keep the land grid.
static func of_pack(repo: DataRepository, water_open := false) -> MarchPath:
	if int(repo.bal("army_march_grid_px")) <= 0:
		return null
	var key := _key(repo, water_open)
	if not _cached.has(key):
		_cached[key] = load_pack(repo, water_open)
	return _cached[key]


## Stand `grid` in for the pack's (tests: a grid built by hand). The courier
## road graph cached on the old grid is forgotten with it.
static func use(repo: DataRepository, grid: MarchPath, water_open := false) -> void:
	_cached[_key(repo, water_open)] = grid
	RoadGraph.forget()


static func _key(repo: DataRepository, water_open: bool) -> String:
	return "%s:%d:%s" % [repo.map_id, int(repo.bal("army_max_slope")), "open" if water_open else "land"]


static func load_pack(repo: DataRepository, water_open := false) -> MarchPath:
	var dir := String((repo.maps.get(repo.map_id, {}) as Dictionary).get("data_dir", ""))
	var path := dir + "/geography/march_grid.png"
	if dir == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	img.convert(Image.FORMAT_L8)
	var px := maxi(1, int(repo.bal("army_march_grid_px")))
	var w := int(ceil(float(repo.map_info.get("width", "0")) / float(px)))
	var h := int(ceil(float(repo.map_info.get("height", "0")) / float(px)))
	if img.get_width() != w or img.get_height() != h:
		push_warning("MarchPath: %s is %dx%d, the pack wants %dx%d — rerun bake_march_grid.py"
			% [path, img.get_width(), img.get_height(), w, h])
		return null
	return build(repo, w, h, px * ArmySystem.metres_per_pack_px(repo), img.get_data(), water_open)


## A grid of `cols` x `rows` cells of `cell_m` metres from its bytes (the
## bake's encoding, row-major; a test builds one by hand).
static func build(repo: DataRepository, cols_: int, rows_: int, cell_m_: int, slopes: PackedByteArray,
		water_open_ := false) -> MarchPath:
	var g := MarchPath.new()
	g.water_open = water_open_
	g.cols = cols_
	g.rows = rows_
	g.cell_m = maxi(1, cell_m_)
	g._snap = int(repo.bal("army_march_snap_cells"))
	@warning_ignore("integer_division")  # hundredths of rise per run against per mille
	var limit := int(repo.bal("army_max_slope")) / 10
	g.closed.resize(cols_ * rows_)
	g.water.resize(cols_ * rows_)
	for i in g.closed.size():
		var s := int(slopes[i]) if i < slopes.size() else WATER
		g.water[i] = 1 if s == WATER else 0
		if s == WATER:
			g.closed[i] = 0 if water_open_ else 1
		else:
			g.closed[i] = 1 if s > limit else 0
	return g


## The cell holding a point (whole metres), held to the grid.
func cell_of(m: Vector2i) -> Vector2i:
	var c := Vector2i(floori(float(m.x) / float(cell_m)), floori(float(m.y) / float(cell_m)))
	return Vector2i(clampi(c.x, 0, cols - 1), clampi(c.y, 0, rows - 1))


func is_closed(c: Vector2i) -> bool:
	return closed[c.y * cols + c.x] == 1


func is_water(c: Vector2i) -> bool:
	return water[c.y * cols + c.x] == 1


## A cell's centre in whole metres.
func centre_m(c: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(c.x * cell_m + cell_m / 2, c.y * cell_m + cell_m / 2)


## True when the straight line a -> b (whole metres) enters no closed cell but
## those in `open` (the ends' own: a column standing on a scarp may leave it,
## and one sent onto it may reach it). Every cell the line touches is walked
## (cells_on), corners included.
func clear(a: Vector2i, b: Vector2i, open: Array = []) -> bool:
	for c: Vector2i in cells_on(a, b):
		if is_closed(c) and not open.has(c):
			return false
	return true


## Every cell the straight line a -> b (whole metres) touches, in travel order
## (Amanatides and Woo), the ends' own included. Through a corner the two cells
## beside it come before the diagonal one: a line that grazes a corner is as
## blocked as one that crosses the cell. The one walk clear() and
## blocked_runs() share.
func cells_on(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x := float(a.x) / float(cell_m)
	var y := float(a.y) / float(cell_m)
	var dx := float(b.x - a.x) / float(cell_m)
	var dy := float(b.y - a.y) / float(cell_m)
	var c := cell_of(a)
	var end := cell_of(b)
	var sx := 1 if dx > 0.0 else -1
	var sy := 1 if dy > 0.0 else -1
	var t_dx := absf(1.0 / dx) if dx != 0.0 else INF
	var t_dy := absf(1.0 / dy) if dy != 0.0 else INF
	var t_x := ((floorf(x) + 1.0 - x) if dx > 0.0 else (x - floorf(x))) * t_dx if dx != 0.0 else INF
	var t_y := ((floorf(y) + 1.0 - y) if dy > 0.0 else (y - floorf(y))) * t_dy if dy != 0.0 else INF
	var guard := absi(end.x - c.x) + absi(end.y - c.y) + 2
	while true:
		if out.is_empty() or out[out.size() - 1] != c:
			out.append(c)
		if c == end or guard <= 0:
			return out
		guard -= 1
		if t_x < t_y:
			c.x += sx
			t_x += t_dx
		elif t_y < t_x:
			c.y += sy
			t_y += t_dy
		else:   # through a corner: both cells beside it count
			out.append(Vector2i(clampi(c.x + sx, 0, cols - 1), c.y))
			out.append(Vector2i(c.x, clampi(c.y + sy, 0, rows - 1)))
			c += Vector2i(sx, sy)
			t_x += t_dx
			t_y += t_dy
		c = Vector2i(clampi(c.x, 0, cols - 1), clampi(c.y, 0, rows - 1))
	return out


## The runs of SLOPE a march meets where the router goes round them, for the
## war room's barrier marks: [[entry cell, exit cell], ...] in travel order,
## each run the closed, dry cells met one after another on a leg that
## ArmySystem.route_m_of replaces by a detour (water is no scarp; the leg's own
## end cells never count, as in clear()). A leg the router walks straight (it
## is clear, or walled in with no way round) has none. `wps` and the ends are
## whole metres; empty without a grid.
static func blocked_runs(repo: DataRepository, from: Vector2i, wps: Array, to: Vector2i) -> Array:
	var out: Array = []
	var grid := of_pack(repo)
	if grid == null:
		return out
	var pts: Array = [from]
	pts.append_array(wps)
	pts.append(to)
	var ctrl := MarchRoute.distinct(pts)
	var legs: Array = []
	if ctrl.size() < 2:
		return out
	if wps.is_empty():
		legs = [[to]]
	else:
		legs = MarchRoute.legs(ctrl, int(repo.bal("army_route_sample_m")))
	for i in legs.size():
		var leg: Array = legs[i]
		if ArmySystem.leg_clear(grid, ctrl[i], leg):
			continue
		if grid.road(ctrl[i], ctrl[i + 1]) == [ctrl[i + 1]]:
			continue   # walled in: the column walks the straight line
		var ends := [grid.cell_of(ctrl[i]), grid.cell_of(leg[leg.size() - 1])]
		var run: Array = []
		var prev: Vector2i = ctrl[i]
		for p: Vector2i in leg:
			for c: Vector2i in grid.cells_on(prev, p):
				if grid.is_closed(c) and not grid.is_water(c) and not ends.has(c):
					if run.is_empty():
						run = [c, c]
					elif maxi(absi(c.x - run[1].x), absi(c.y - run[1].y)) <= 1:
						run[1] = c
					else:
						out.append(run)
						run = [c, c]
				elif not run.is_empty():
					out.append(run)
					run = []
			prev = p
		if not run.is_empty():
			out.append(run)
	return out


## The straight line a -> b cut into runs of one kind of ground:
## [[end point (whole metres), over water?], ...], the last ending on b. The
## same cell walk as clear(); a boundary is the point where the line leaves a
## cell of the other kind (rounded), and through a corner the diagonal cell
## decides. Zero-length runs are dropped.
func water_runs(a: Vector2i, b: Vector2i) -> Array:
	var x := float(a.x) / float(cell_m)
	var y := float(a.y) / float(cell_m)
	var dx := float(b.x - a.x) / float(cell_m)
	var dy := float(b.y - a.y) / float(cell_m)
	var c := cell_of(a)
	var end := cell_of(b)
	var sx := 1 if dx > 0.0 else -1
	var sy := 1 if dy > 0.0 else -1
	var t_dx := absf(1.0 / dx) if dx != 0.0 else INF
	var t_dy := absf(1.0 / dy) if dy != 0.0 else INF
	var t_x := ((floorf(x) + 1.0 - x) if dx > 0.0 else (x - floorf(x))) * t_dx if dx != 0.0 else INF
	var t_y := ((floorf(y) + 1.0 - y) if dy > 0.0 else (y - floorf(y))) * t_dy if dy != 0.0 else INF
	var out: Array = []
	var state := is_water(c)
	var guard := absi(end.x - c.x) + absi(end.y - c.y) + 2
	while c != end and guard > 0:
		guard -= 1
		var next := c
		var t_next := minf(t_x, t_y)
		if t_x < t_y:
			next.x += sx
			t_x += t_dx
		elif t_y < t_x:
			next.y += sy
			t_y += t_dy
		else:   # through a corner: the diagonal cell decides
			next += Vector2i(sx, sy)
			t_x += t_dx
			t_y += t_dy
		next = Vector2i(clampi(next.x, 0, cols - 1), clampi(next.y, 0, rows - 1))
		var now := is_water(next)
		if now != state:
			var p := Vector2i(roundi(float(a.x) + float(b.x - a.x) * minf(t_next, 1.0)),
				roundi(float(a.y) + float(b.y - a.y) * minf(t_next, 1.0)))
			out.append([p, state])
			state = now
		c = next
	out.append([b, state])
	# zero-length runs dropped (a boundary on the previous point or on b)
	var kept: Array = []
	var prev := a
	for i in out.size():
		var run: Array = out[i]
		if run[0] == prev and i < out.size() - 1:
			continue
		kept.append(run)
		prev = run[0]
	return kept


## The road from `from` to `to` (whole metres): the corners after `from`,
## ending exactly on `to`. [to] when the straight line is clear — and when
## there is no way round (an end walled in, another shore): the column then
## walks the straight line, as every march did before.
func road(from: Vector2i, to: Vector2i) -> Array:
	var fc := cell_of(from)
	var tc := cell_of(to)
	var ends := [fc, tc]
	if clear(from, to, ends):
		return [to]
	var s := nearest_open(fc)
	var g := nearest_open(tc)
	if s.x < 0 or g.x < 0:
		return [to]
	var cells := _cells(s, g)
	if cells.is_empty():
		return [to]
	var pts: Array = [from]
	for c: Vector2i in cells:
		pts.append(centre_m(c))
	pts.append(to)
	return _taut(pts, ends).slice(1)


## The nearest open cell to `c` (itself when open), ring by ring out to
## army_march_snap_cells, the nearest centre first and the lowest index on a
## tie; (-1, -1) when none.
func nearest_open(c: Vector2i) -> Vector2i:
	if not is_closed(c):
		return c
	for r in range(1, int(_snap) + 1):
		var best := Vector2i(-1, -1)
		var best_d := -1
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				if maxi(absi(x - c.x), absi(y - c.y)) != r or x < 0 or y < 0 or x >= cols or y >= rows:
					continue
				if is_closed(Vector2i(x, y)):
					continue
				var d := (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
				if best_d < 0 or d < best_d:
					best_d = d
					best = Vector2i(x, y)
		if best_d >= 0:
			return best
	return Vector2i(-1, -1)


## Whether a column can walk from point `a` to point `b` (whole metres): the
## cell holding `b` is open and in the same piece of open ground as `a`'s (the
## nearest open cell when `a` stands on a closed one). Search never aims at a
## cell this refuses.
func joins(a: Vector2i, b: Vector2i) -> bool:
	var g := cell_of(b)
	var s := nearest_open(cell_of(a))
	if is_closed(g) or s.x < 0:
		return false
	_ensure_astar()
	return _piece[s.y * cols + s.x] == _piece[g.y * cols + g.x]


## The A* cells from `s` to `g`, both open; [] when none joins them.
func _cells(s: Vector2i, g: Vector2i) -> Array:
	var key := "%d,%d" % [s.y * cols + s.x, g.y * cols + g.x]
	if _found.has(key):
		return _found[key]
	_ensure_astar()
	var out: Array = []
	if _piece[s.y * cols + s.x] != _piece[g.y * cols + g.x]:
		return out
	for c: Vector2i in _astar.get_id_path(s, g):
		out.append(c)
	if _found.size() >= 512:
		_found.clear()
	_found[key] = out
	return out


func _ensure_astar() -> void:
	if _astar != null:
		return
	_astar = _Grid.new()
	_astar.region = Rect2i(0, 0, cols, rows)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in rows:
		for x in cols:
			if closed[y * cols + x] == 1:
				_astar.set_point_solid(Vector2i(x, y), true)
	# the open cells' pieces (four ways: a diagonal needs both sides open, so
	# it joins nothing four ways do not), so a road to another piece is known
	# to be none without searching the whole of this one
	_piece.resize(cols * rows)
	_piece.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(cols * rows)
	var n := 0
	for i in cols * rows:
		if closed[i] == 1 or _piece[i] >= 0:
			continue
		_piece[i] = n
		var head := 0
		var tail := 1
		queue[0] = i
		while head < tail:
			var at := queue[head]
			head += 1
			var x := at % cols
			for j: int in [at - 1 if x > 0 else -1, at + 1 if x < cols - 1 else -1, at - cols, at + cols]:
				if j >= 0 and j < cols * rows and closed[j] == 0 and _piece[j] < 0:
					_piece[j] = n
					queue[tail] = j
					tail += 1
		n += 1


## `pts` pulled taut: from each corner kept, the farthest point still in a
## clear line (found by doubling, then halving), so a staircase of cells
## becomes a few straight legs. The first and last points stay.
func _taut(pts: Array, ends: Array) -> Array:
	var out: Array = [pts[0]]
	var at := 0
	var last := pts.size() - 1
	while at < last:
		var ok := at + 1
		var step := 1
		while ok + step <= last and clear(pts[at], pts[ok + step], ends):
			ok += step
			step *= 2
		var bad := mini(ok + step, last + 1)
		while bad - ok > 1:
			@warning_ignore("integer_division")
			var mid := (ok + bad) / 2
			if clear(pts[at], pts[mid], ends):
				ok = mid
			else:
				bad = mid
		out.append(pts[ok])
		at = ok
	return out
