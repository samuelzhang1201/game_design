class_name WarTray
extends RefCounted
## The war markers' tray beside the index chart (owner 2026-10-12, items 6-7;
## R11 owner-approved): a marker a slot, each standing on one cell of the chart
## (a sheet index), the held cells laid as ONE sheet (WarSheets.union). The
## bounding box of the held cells never spans more than `max_cells` cells
## (2x2, 1x3, 1x4); a toss that would widen it is refused. Pure (no node, no
## state saved): `cells` maps each sheet index to its Vector2i(col, row); the
## slot a marker holds is stable, so the view keeps one node per slot.

var max_slots := 1
var max_cells := 4
var _slots: Array = []   # slot -> sheet index, -1 free
var _order: Array = []   # slots in the order they were placed, oldest first
var _cells: Dictionary = {}   # sheet index -> Vector2i
var _sheets: Dictionary = {}  # Vector2i -> sheet index


func _init(p_slots: int = 1, p_max_cells: int = 4, cells: Dictionary = {}) -> void:
	max_slots = maxi(1, p_slots)
	max_cells = maxi(1, p_max_cells)
	_slots.resize(max_slots)
	_slots.fill(-1)
	_cells = cells
	for s: int in cells:
		_sheets[cells[s]] = s


## A tray of `slots` markers (the nodes the scene holds, at most war_tray_max)
## over the pack's sheets.
static func of(repo: DataRepository, slots: int) -> WarTray:
	var cells: Dictionary = {}
	for s: Dictionary in WarSheets.series(repo):
		cells[int(s["index"])] = Vector2i(int(s["col"]), int(s["row"]))
	var most := maxi(1, int(repo.bal("war_tray_max")))
	return WarTray.new(clampi(slots, 1, most), most, cells)


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


## The most recently placed marker's sheet, -1 with none.
func newest() -> int:
	return -1 if _order.is_empty() else int(_slots[_order[-1]])


## True when `sheets` (indices) span at most max_cells cells of bounding box.
func fits(sheets: Array) -> bool:
	var cells: Array = []
	for s: int in sheets:
		if _cells.has(s):
			cells.append(_cells[s])
	return area_cells(cells) <= max_cells


## The slot a toss onto `sheet` takes, -1 refused: a free marker when the box
## still fits; with none free, the newest marker is picked up again when the
## box fits without it (one marker: it always moves, as before the tray).
## Nothing is changed; `place` puts it there.
func toss_slot(sheet: int) -> int:
	if slot_of(sheet) >= 0 or not _cells.has(sheet):
		return -1
	var with := held()
	with.append(sheet)
	if not full():
		return _slots.find(-1) if fits(with) else -1
	var without := held()
	without.pop_back()
	without.append(sheet)
	return int(_order[-1]) if fits(without) else -1


## Place the marker of `slot` on `sheet` (it becomes the newest).
func place(slot: int, sheet: int) -> void:
	if slot < 0 or slot >= max_slots:
		return
	_slots[slot] = sheet
	_order.erase(slot)
	_order.append(slot)


## A toss onto `sheet`: its slot, placed now, or -1 refused (`toss_slot`).
func take(sheet: int) -> int:
	var slot := toss_slot(sheet)
	if slot >= 0:
		place(slot, sheet)
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


## `sheet` becomes held without a toss (the first lay, a margin row, the Tab's
## home sheet, the snapshot tool): already held, nothing; else every marker
## goes back but the newest, which stands on it — only a TOSS adds a cell to the
## laid union (R11), so a second lay supersedes the first. Its slot.
func hold(sheet: int) -> int:
	var at := slot_of(sheet)
	if at >= 0 or not _cells.has(sheet):
		return at
	var keep: int = _order[-1] if not _order.is_empty() else 0
	_slots.fill(-1)
	_order.clear()
	place(keep, sheet)
	return keep


## True when every held cell moved one cell by `dir` (an edge arrow) still
## stands on a sheet (not a sea cell, not off the map).
func can_shift(dir: Vector2i) -> bool:
	if _order.is_empty():
		return false
	for s: int in held():
		if not _sheets.has((_cells[s] as Vector2i) + dir):
			return false
	return true


## Every held marker moves one cell by `dir`; false and nothing changed when
## `can_shift` says no. The count of markers never changes.
func shift(dir: Vector2i) -> bool:
	if not can_shift(dir):
		return false
	for slot: int in _order:
		_slots[slot] = int(_sheets[(_cells[_slots[slot]] as Vector2i) + dir])
	return true


## The held sheets after a shift by `dir` (oldest first), [] when it cannot.
func shifted(dir: Vector2i) -> Array:
	if not can_shift(dir):
		return []
	return held().map(func(s: int) -> int: return int(_sheets[(_cells[s] as Vector2i) + dir]))


## The cell (col, row) of sheet `sheet`, (-1, -1) for none.
func cell_of(sheet: int) -> Vector2i:
	return _cells.get(sheet, Vector2i(-1, -1))


## The bounding box, in cells, of `cells` (Vector2i col, row).
static func extent_cells(cells: Array) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c: Vector2i in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return hi - lo + Vector2i.ONE


static func area_cells(cells: Array) -> int:
	var e := extent_cells(cells)
	return e.x * e.y
