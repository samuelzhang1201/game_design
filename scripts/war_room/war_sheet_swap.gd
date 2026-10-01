class_name WarSheetSwap
extends RefCounted
## The roll-up that changes the laid sheet (spec 2026-10-01-war-room-design
## §2): the table's depth goes 1 -> 0 -> 1 over `total` seconds and the new
## sheet is laid at the midpoint. Pure timing; the view applies the scale.

var left := 0.0
var total := 0.0
var floor_scale := 0.0
var to := -1


func start(index: int, repo: DataRepository) -> void:
	to = index
	total = maxf(repo.bal("war_sheet_swap_s"), 0.001)
	floor_scale = repo.bal("war_roll_floor")
	left = total


func active() -> bool:
	return left > 0.0


## Advance by `delta`; true on the step that crosses the midpoint.
func step(delta: float) -> bool:
	var before := left
	left = maxf(0.0, left - delta)
	return before > total * 0.5 and left <= total * 0.5


## The table's depth scale now: 1 at the ends, a sliver at the midpoint.
func z_scale() -> float:
	if left <= 0.0:
		return 1.0
	return maxf(absf(left / total - 0.5) * 2.0, floor_scale)


func cancel() -> void:
	left = 0.0
