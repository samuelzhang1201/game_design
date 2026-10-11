class_name FpsCounter
extends CanvasLayer
## The frame counter (owner 2026-09-30: 右上角帮我加上游戏实时FPS): the
## engine's own frames per second at the screen's top-right, in the top bar's
## free stretch left of MENU, over every screen and popup. GameRoot shows it
## while the menus' FPS row is on (GameRoot.set_show_fps), whatever DEV MODE
## says; it reads, never writes.
## balance.csv ui_fps_right_px (its right edge's inset from the window's),
## ui_fps_bar_px (the band it is centred in: the top bar's height),
## ui_fps_refresh_s (how often it rereads), ui_fps_good / ui_fps_poor (the
## rates it turns from good to gold to bad at).

@onready var _label: Label = %FpsLabel
var _since := 0.0

func _ready() -> void:
	UiPalette.style_header(_label, 14)
	_label.offset_right = -_bal("ui_fps_right_px", 104.0)
	_label.offset_left = _label.offset_right - 120.0
	_label.offset_bottom = _bal("ui_fps_bar_px", 44.0)
	visibility_changed.connect(_reread)
	_reread()

func _process(delta: float) -> void:
	if not visible:
		return
	_since += delta
	if _since >= _bal("ui_fps_refresh_s", 0.25):
		_reread()

func _reread() -> void:
	_since = 0.0
	var fps := Engine.get_frames_per_second()
	_label.text = "%d FPS" % roundi(fps)
	var color := UiPalette.GOLD
	if fps >= _bal("ui_fps_good", 55.0):
		color = UiPalette.good_color()
	elif fps < _bal("ui_fps_poor", 30.0):
		color = UiPalette.bad_color()
	_label.add_theme_color_override("font_color", color)

## Test seam.
func text() -> String:
	return _label.text

func _bal(key: String, fallback: float) -> float:
	return UiPalette._bal_or(key, fallback)
