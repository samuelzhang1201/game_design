class_name BottomBar
extends Control
## Bottom tab strip on every gameplay screen (user ruling 2026-08-30),
## outside the map: MAP | REALM | MILITARY | LAWS | RELIGION | RELATIONSHIP.
## Pure chrome — GameRoot owns it and decides what each tab opens (MAP
## closes overlays, RELATIONSHIP toggles the graph, the rest open the
## matching InfoScreen table). Replaces the TopBar's RELATIONS button.

signal tab_selected(tab: String)

const TABS := ["MAP", "REALM", "MILITARY", "LAWS", "RELIGION", "RELATIONSHIP"]
const BAR_HEIGHT := 18.0

var _buttons: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -BAR_HEIGHT
	var bar := PanelContainer.new()
	bar.name = "Bar"
	bar.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 2))
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bar)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	for tab in TABS:
		var btn := Button.new()
		btn.name = tab.capitalize()
		btn.text = tab
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(func() -> void: tab_selected.emit(tab))
		row.add_child(btn)
		_buttons[tab] = btn

## Test seam.
func button(tab: String) -> Button:
	return _buttons.get(tab)
