class_name EnvelopeFlight
extends Control
## A wax-sealed envelope flying to the Missive tab (owner 2026-09-28, spec
## 2026-09-28 §2): it shrinks from `from` toward an envelope over
## missive_seal_s, then rides a quadratic arc to `to` over missive_fly_s,
## turning missive_fly_turns times, and frees itself. The project's first Tween.

signal landed

const ENVELOPE_PX := Vector2(36, 26)
const SMALL_PX := Vector2(22, 16)
## A technical margin, not a design value (fix round 2): GUT's wait_for_signal
## only confirms its own bookkeeping a couple of process frames after `landed`
## fires (addons/gut/awaiter.gd), so freeing right on emit can race it. Kept
## as a Tween step (below) rather than an awaited coroutine so the delay dies
## with the node instead of trying to resume on a freed one.
const FREE_DELAY_S := 0.1

var _from: Vector2
var _to: Vector2
var _lift: Vector2


static func fly(host: Control, from: Rect2, to: Rect2, big: bool, repo: DataRepository) -> EnvelopeFlight:
	var f := EnvelopeFlight.new()
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.top_level = true
	host.add_child(f)
	f._start(from, to, big, repo)
	return f


## The wax-sealed envelope that flies to the tab (library U-26).
const ENVELOPE := preload("res://assets/2D/ui/missive_board/envelope.png")

func _start(from: Rect2, to: Rect2, big: bool, repo: DataRepository) -> void:
	var env := ENVELOPE_PX if big else SMALL_PX
	size = from.size if big else env
	position = from.position if big else from.get_center() - env * 0.5
	pivot_offset = size * 0.5
	_from = position
	_to = to.get_center() - env * 0.5
	_lift = (_from + _to) * 0.5 + Vector2(0, -160)
	# create_tween() binds the tween to self (Node.create_tween's own
	# behaviour), so the tween is killed automatically if this node is freed
	# mid-flight — the host dying under it can never leak a running tween.
	var t := create_tween()
	if big:
		t.tween_property(self, "size", env, repo.bal("missive_seal_s"))
		t.parallel().tween_property(self, "position", from.get_center() - env * 0.5, repo.bal("missive_seal_s"))
		t.tween_callback(func() -> void:
			_from = position
			pivot_offset = env * 0.5)
	t.tween_method(_arc, 0.0, 1.0, repo.bal("missive_fly_s"))
	t.parallel().tween_property(self, "rotation", TAU * repo.bal("missive_fly_turns"), repo.bal("missive_fly_s"))
	t.tween_callback(func() -> void: landed.emit())
	# The free waits one more Tween step (FREE_DELAY_S) rather than happening
	# in the same callback as the emit (fix round 2): the Tween is bound to
	# this node (create_tween's own behaviour), so it simply dies with the
	# node if something else frees it first — nothing ever resumes on a freed
	# instance, unlike the awaited coroutine this replaced.
	t.tween_interval(FREE_DELAY_S)
	t.tween_callback(queue_free)


func _arc(k: float) -> void:
	position = _from.lerp(_lift, k).lerp(_lift.lerp(_to, k), k)


## The shrink phase animates size/position via tween_property, which does not
## invalidate a custom _draw on its own; redraw every frame while flying.
func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var tex: Texture2D = ENVELOPE
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		return
	draw_rect(Rect2(Vector2.ZERO, size), MapPalette.named(Game.data, "envelope_paper"))
	draw_polyline(PackedVector2Array([Vector2.ZERO, size * Vector2(0.5, 0.55), Vector2(size.x, 0)]),
		MapPalette.named(Game.data, "envelope_ink"), 1.5)
	draw_circle(size * Vector2(0.5, 0.55), minf(size.x, size.y) * 0.18, MapPalette.named(Game.data, "envelope_wax"))
