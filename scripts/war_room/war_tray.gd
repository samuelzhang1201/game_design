class_name WarTray
extends RefCounted
## The war markers' tray beside the index chart (owner 2026-10-12, items 6-7): up
## to `war_tray_max` markers the player takes out and lays on cells of the chart,
## one cell each, and puts back. The strategic map covers the cells the markers
## stand on: `extent_cells` is the bounding box of those cells in cells and
## `zoom_factor` how many cells across the widest side of it runs, 1 for a lone
## marker. Pure (no node, no state saved); the slot a marker holds is stable, so
## the view keeps one node per slot.

var max_slots := 4
var _slots: Array = []   # slot -> sheet index, -1 free
var _order: Array = []   # slots in the order they were taken, oldest first


func _init(p_max: int = 4) -> void:
	max_slots = maxi(1, p_max)
	_slots.resize(max_slots)
	_slots.fill(-1)


static func of(repo: DataRepository) -> WarTray:
	return WarTray.new(int(repo.bal("war_tray_max")))


func count() -> int:
	return _order.size()


func full() -> bool:
	return _order.size() >= max_slots


## The slot holding `sheet`, -1 when none does.
func slot_of(sheet: int) -> int:
	return _slots.find(sheet)


func sheet_in(slot: int) -> int:
	return int(_slots[slot]) if slot >= 0 and slot < max_slots else -1


## The sheets held, oldest first.
func held() -> Array:
	var out: Array = []
	for s: int in _order:
		out.append(_slots[s])
	return out


## The most recently taken marker's sheet, -1 with none.
func newest() -> int:
	return -1 if _order.is_empty() else int(_slots[_order[-1]])


## Take a marker out for `sheet`: its slot, or -1 when the tray is empty of
## markers (full) or `sheet` already holds one.
func take(sheet: int) -> int:
	if full() or slot_of(sheet) >= 0:
		return -1
	var slot := _slots.find(-1)
	_slots[slot] = sheet
	_order.append(slot)
	return slot


## Put the marker on `sheet` back; false when none stands there or it is the
## last one out (the laid sheet always wears a marker).
func put_back(sheet: int) -> bool:
	var slot := slot_of(sheet)
	if slot < 0 or _order.size() <= 1:
		return false
	_slots[slot] = -1
	_order.erase(slot)
	return true


## `sheet` becomes held: already held, nothing; a free marker, taken; a full
## tray, the newest marker moved to it. Returns the slot.
func hold(sheet: int) -> int:
	var at := slot_of(sheet)
	if at >= 0:
		return at
	if not full():
		return take(sheet)
	var slot: int = _order[-1]
	_slots[slot] = sheet
	return slot


## The bounding box, in cells, of the cells (Vector2i col, row) the markers stand on.
static func extent_cells(cells: Array) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c: Vector2i in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return hi - lo + Vector2i.ONE


## The area that stays in view, in cells.
static func area_cells(cells: Array) -> int:
	var e := extent_cells(cells)
	return e.x * e.y


## How many cells across the covered area's widest side runs: the table's
## camera backs off by this factor (1 for one cell).
static func zoom_factor(cells: Array) -> float:
	var e := extent_cells(cells)
	return float(maxi(e.x, e.y))


## The cells (col, row) of sheets `sheets`.
static func cells_of(repo: DataRepository, sheets: Array) -> Array:
	var all := WarSheets.series(repo)
	var out: Array = []
	for i: int in sheets:
		if i >= 0 and i < all.size():
			out.append(Vector2i(int(all[i]["col"]), int(all[i]["row"])))
	return out


## The pack-px rect of the cells the markers stand on (their neat lines united).
static func span_rect(repo: DataRepository, sheets: Array) -> Rect2:
	var all := WarSheets.series(repo)
	var out := Rect2()
	var first := true
	for i: int in sheets:
		if i < 0 or i >= all.size():
			continue
		var r: Rect2 = all[i]["cell"]
		out = r if first else out.merge(r)
		first = false
	return out
