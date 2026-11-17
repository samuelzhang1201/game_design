extends SceneTree
## Wall-clock cost of a pivot provider's `solve` (CPU only; renders nothing, so --headless is fine).
##   Godot --headless --path . -s res://tools/units3d/bench_pivot_solve.gd -- [--arm cavalry]
##       [--turn UDEG] [--calls N]
## Prints the first call (binding the figure and, where the provider caches per turn, that turn's
## precomputation) and the median / p95 / max of N warm calls at evenly spread phases of the same turn.
## The consumer makes one solve per (arm, clip, turn, phase) per frame, so the warm median is a
## frame's cost per pivoting arm.

const ARMS: Dictionary = {
	"cavalry": ["res://scenes/models/units/cavalry.tscn", "res://scripts/map3d/map3d_cavalry_locomotion.gd"],
	"royal": ["res://scenes/models/units/royal.tscn", "res://scripts/map3d/map3d_royal_pivot.gd"]}


func _initialize() -> void:
	var args: Dictionary = {"arm": "cavalry", "turn": "90000000", "calls": "64"}
	var user: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(0, user.size() - 1, 2):
		args[user[i].trim_prefix("--")] = user[i + 1]
	var arm: Array = ARMS[args.arm]
	var figure: Node = (load(arm[0]) as PackedScene).instantiate()
	root.add_child(figure)
	var player: AnimationPlayer = figure.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = figure.find_children("*", "Skeleton3D", true, false)[0]
	var provider: GDScript = load(arm[1])
	var turn: int = int(args.turn)
	var clip: String = "PIVOT_RIGHT" if turn > 0 else "PIVOT_LEFT"
	var calls: int = maxi(1, int(args.calls))
	var t0: int = Time.get_ticks_usec()
	var first: Dictionary = provider.solve(player, skeleton, clip, turn, 0.5)
	var first_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	var times: Array[float] = []
	for i: int in calls:
		var phase: float = (float(i) + 0.5) / float(calls)
		t0 = Time.get_ticks_usec()
		var out: Dictionary = provider.solve(player, skeleton, clip, turn, phase)
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		if not out.ok:
			push_error("solve failed at %f: %s" % [phase, out.reason])
	times.sort()
	print("PIVOT_SOLVE_BENCH arm=%s turn=%d ok=%s first=%.2fms warm median=%.3fms p95=%.3fms max=%.3fms n=%d" % [
		args.arm, turn, first.ok, first_ms, times[calls / 2], times[mini(calls - 1, int(calls * 0.95))],
		times[-1], calls])
	quit()
