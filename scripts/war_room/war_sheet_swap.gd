class_name WarSheetSwap
extends RefCounted
## The roll-up that changes the laid sheet (spec 2026-10-01-war-room-design
## §2): the table's depth goes 1 -> 0 -> 1 over `total` seconds and the new
## sheet is laid at the midpoint. Pure timing; the view applies the scale.

var left := 0.0
var total := 0.6
var to := -1


func start(index: int, seconds: float) -> void:
	to = index
	total = maxf(seconds, 0.001)
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
	return maxf(absf(left / total - 0.5) * 2.0, 0.02)


func cancel() -> void:
	left = 0.0
