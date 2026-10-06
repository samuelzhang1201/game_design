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


## Below and right of the pointer by `gap`; flipped left or up where it would
## leave `bounds`.
static func place(pointer: Vector2, size: Vector2, bounds: Rect2, gap: float) -> Vector2:
	var at := pointer + Vector2(gap, gap)
	if at.x + size.x > bounds.end.x:
		at.x = pointer.x - gap - size.x
	if at.y + size.y > bounds.end.y:
		at.y = pointer.y - gap - size.y
	return Vector2(maxf(at.x, bounds.position.x), maxf(at.y, bounds.position.y))


func show_lines(lines: Array, pointer: Vector2, bounds: Rect2) -> void:
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
	position = place(pointer, get_combined_minimum_size(), bounds, _gap)


func hide_slip() -> void:
	visible = false
