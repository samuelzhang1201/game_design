extends GutTest

class ClockListener extends Node:
	var speeds: Array[int] = []
	func changed(speed: int) -> void:
		speeds.append(speed)

var _speed: int
var _resume: int
var _held: bool
var _holds: Dictionary

func before_each() -> void:
	_held = Game.clock_held
	_speed = Game.clock_speed
	_resume = Game._resume_speed
	_holds = Game._clock_holders.duplicate()
	Game.release_clock_holds()
	Game.set_clock_speed(0)

func after_each() -> void:
	Game._clock_holders = _holds
	Game.clock_held = _held
	Game.clock_speed = _speed
	Game._resume_speed = _resume

func _hub() -> Node:
	var hub := get_node_or_null("/root/SignalHub")
	assert_not_null(hub, "global notifications have a dedicated autoload")
	return hub

func test_speed_notifies_after_state_change_once_and_rejects_invalid_speed() -> void:
	var hub := _hub()
	if hub == null:
		return
	var observed: Array[int] = []
	var receive := func(speed: int) -> void:
		assert_eq(Game.clock_speed, speed, "state commits before notification")
		observed.append(speed)
	hub.connect("clock_changed", receive)
	Game.set_clock_speed(1)
	Game.set_clock_speed(1)
	Game.set_clock_speed(-1)
	Game.set_clock_speed(0)
	assert_eq(observed, [1, 0])
	hub.disconnect("clock_changed", receive)

func test_hold_blocks_play_until_released() -> void:
	var hub := _hub()
	if hub == null:
		return
	watch_signals(hub)
	Game.set_clock_speed(1)
	Game.hold_clock(true, "signal_hub_test")
	Game.set_clock_speed(1)
	assert_eq(Game.clock_speed, 0)
	Game.hold_clock(false, "signal_hub_test")
	assert_eq(Game.clock_speed, 0, "releasing a hold does not start play")
	assert_signal_emit_count(hub, "clock_changed", 2)
	assert_signal_emit_count(hub, "clock_held_changed", 2)

func test_freed_receiver_is_disconnected() -> void:
	var hub := _hub()
	if hub == null:
		return
	var listener := ClockListener.new()
	hub.connect("clock_changed", listener.changed)
	Game.set_clock_speed(1)
	assert_eq(listener.speeds, [1])
	var before := hub.get_signal_connection_list("clock_changed").size()
	listener.free()
	assert_eq(hub.get_signal_connection_list("clock_changed").size(), before - 1)
	Game.set_clock_speed(0)
