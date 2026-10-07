class_name WarPlanForm
extends PanelContainer
## The Place form of a supposed enemy (spec 2026-10-07-war-room-annotations-
## and-planning-pieces §1.5): the arm (four icon buttons), the heads (a spin
## box stepped by war_plan_heads_step and quick counts), the side (the foreign
## kingdoms and Unknown), and the would-be piece's two figure lines read live;
## Place / Cancel, Escape cancels. Its look is the scene's; it fills the
## choices and says what was chosen — the screen writes it through Game.

signal placed(arm: String, heads: int, side: String)
signal cancelled

## (arm, heads, side) -> Array of the figure lines' texts, set by the screen.
var reading_fn := Callable()
var _repo: DataRepository
var _arms: Array = []
var _sides: Array = []

@onready var _title: Label = %FormTitle
@onready var _arm_row: HBoxContainer = %Arms
@onready var _heads: SpinBox = %Heads
@onready var _quick: HBoxContainer = %Quick
@onready var _side: OptionButton = %Side
@onready var _figures: VBoxContainer = %Figures
@onready var _place: Button = %Place
@onready var _cancel: Button = %Cancel


func _ready() -> void:
	_place.pressed.connect(_on_place)
	_cancel.pressed.connect(_on_cancel)
	_heads.value_changed.connect(func(_v: float) -> void: _refresh())
	_side.item_selected.connect(func(_i: int) -> void: _refresh())
	for b: Button in _quick.get_children():
		b.pressed.connect(func() -> void: _heads.value = float(String(b.text).replace(",", "").to_int()))


## The choices from the data: the arms' buttons in the pack's order (each
## arm's resource icon), the heads' range and step, the sides by name.
func setup(repo: DataRepository) -> void:
	_repo = repo
	_arms = WarPlans.arms(repo)
	var buttons := _arm_row.get_children()
	for i in buttons.size():
		var b := buttons[i] as Button
		b.visible = i < _arms.size()
		if i < _arms.size():
			var arm := String(_arms[i])
			b.set_meta("arm", arm)
			b.text = WarGround.arm_word(repo, arm).capitalize()
			b.icon = ResourceIconSet.texture_of(arm)
			if not b.toggled.is_connected(_on_arm):
				b.toggled.connect(_on_arm)
	_heads.min_value = repo.bal("war_plan_heads_min")
	_heads.max_value = repo.bal("war_plan_heads_max")
	_heads.step = repo.bal("war_plan_heads_step")
	_sides = WarPlans.sides(repo)
	_side.clear()
	for s: String in _sides:
		_side.add_item(WarGround.side_label(repo, s))


## Shows the form beside `pointer` inside `bounds`, chosen as given; `editing`
## titles it for an edit.
func open_at(pointer: Vector2, bounds: Rect2, arm: String, heads: int, side: String, editing := false) -> void:
	_title.text = "The supposed host" if editing else "A supposed host"
	_place.text = "Keep" if editing else "Place"
	for b: Button in _arm_row.get_children():
		b.set_pressed_no_signal(String(b.get_meta("arm", "")) == arm)
	_heads.set_value_no_signal(float(heads))
	_side.select(maxi(_sides.find(side), 0))
	visible = true
	reset_size()
	_refresh()
	position = WarHoverSlip.place(pointer, get_combined_minimum_size(), bounds, 12.0)
	_place.grab_focus.call_deferred()


func arm() -> String:
	for b: Button in _arm_row.get_children():
		if b.button_pressed:
			return String(b.get_meta("arm", ""))
	return String(_arms[0]) if not _arms.is_empty() else ""


func heads() -> int:
	return int(_heads.value)


func side() -> String:
	return String(_sides[_side.selected]) if _side.selected >= 0 and _side.selected < _sides.size() else WarPlans.UNKNOWN


func _on_arm(on: bool) -> void:
	if on:
		_refresh()


func _refresh() -> void:
	for c in _figures.get_children():
		_figures.remove_child(c)
		c.queue_free()
	if not reading_fn.is_valid():
		return
	for text: String in reading_fn.call(arm(), heads(), side()):
		var l := Label.new()
		l.text = text
		l.theme_type_variation = &"WarHoverLine"
		_figures.add_child(l)


func _on_place() -> void:
	visible = false
	placed.emit(arm(), heads(), side())


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func _gui_input(event: InputEvent) -> void:
	_escape(event)


func _unhandled_key_input(event: InputEvent) -> void:
	_escape(event)


func _escape(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k != null and k.pressed and k.keycode == KEY_ESCAPE:
		_on_cancel()
		get_viewport().set_input_as_handled()
