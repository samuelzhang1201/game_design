class_name WarHoverSlip
extends PanelContainer
## The WAR ROOM's hover slip (spec 2026-10-07-war-room-scale-hover §4.2): the
## ground under the pointer as WarGround.lines sets it, beside the pointer and
## flipped to stay in the view. Its look is the scene's; it only fills lines
## and places itself. Never takes the mouse.

const KINDS := {"title": &"WarHoverTitle", "sub": &"WarHoverSub", "line": &"WarHoverLine", "rubric": &"WarHoverRubric"}

@onready var _lines: VBoxContainer = %Lines
var _width := 340.0
var _gap := 18.0


func setup(repo: DataRepository) -> void:
	_width = repo.bal("war_hover_width_px")
	_gap = repo.bal("war_hover_gap_px")


## Below and right of the pointer by `gap` (`left`: below and LEFT, the rake's
## slip, so the order menu that opens right of the tip never covers it);
## flipped to the other side where it would leave `bounds`.
static func place(pointer: Vector2, sz: Vector2, bounds: Rect2, gap: float, left := false) -> Vector2:
	var right_x := pointer.x + gap
	var left_x := pointer.x - gap - sz.x
	var at := Vector2(left_x if left else right_x, pointer.y + gap)
	if left and at.x < bounds.position.x:
		at.x = right_x
	elif not left and at.x + sz.x > bounds.end.x:
		at.x = left_x
	if at.y + sz.y > bounds.end.y:
		at.y = pointer.y - gap - sz.y
	return Vector2(maxf(at.x, bounds.position.x), maxf(at.y, bounds.position.y))


func show_lines(lines: Array, pointer: Vector2, bounds: Rect2, left := false) -> void:
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	for l: Dictionary in lines:
		if String(l["kind"]) == "rule":
			var sep := HSeparator.new()
			sep.theme_type_variation = &"WarHoverRule"
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_lines.add_child(sep)
			continue
		var label := Label.new()
		label.text = String(l["text"])
		label.theme_type_variation = KINDS.get(String(l["kind"]), &"WarHoverLine")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = _width
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lines.add_child(label)
	reset_size()
	visible = true
	position = place(pointer, get_combined_minimum_size(), bounds, _gap, left)


func hide_slip() -> void:
	visible = false
