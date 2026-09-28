class_name MissiveReportPopup
extends Control
## A spy's report (owner 2026-09-28, spec 2026-09-28 §2): centred over the
## map, the spy's painting (sub-project D; hidden until installed) and his
## report; Seal closes it and hands its rect to the envelope flight.

signal sealed(from: Rect2)


func _ready() -> void:
	# a floating dialog: a window, titled in the title face
	%Window.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 20, "window"))
	UiPalette.style_title(%ReportTitle, 20)
	%ReportMeta.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	UiPalette.command_button(%Seal)
	%Seal.pressed.connect(func() -> void:
		var r: Rect2 = %Window.get_global_rect()
		visible = false
		sealed.emit(r))


## Centres the dialog over `map_rect` (the active screen's map panel, in
## global coordinates) instead of the whole window (spec §2, fix round 1
## finding 4). The popup itself keeps filling the window — Dim still darkens
## everything — only the CenterContainer that places Window is bound to the
## map panel's own rect; GameRoot calls this right before open().
func center_on(map_rect: Rect2) -> void:
	%Center.anchor_left = 0.0
	%Center.anchor_top = 0.0
	%Center.anchor_right = 0.0
	%Center.anchor_bottom = 0.0
	var local := map_rect.position - global_position
	%Center.position = local
	%Center.size = map_rect.size


func open(m: Dictionary) -> void:
	%ReportTitle.text = String(m["title"])
	%ReportMeta.text = "%s · %s" % [CourierCard.date_of(int(m["day"])), MissiveScreen.HEADERS[String(m["column"])]]
	for c in %ReportFacts.get_children():
		c.queue_free()
	for f: Dictionary in m["facts"]:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "%s: %s" % [String(f["label"]), Intel.text_of(f)]
		%ReportFacts.add_child(l)
	var art := String((Game.data.courier_art.get("spy", {}) as Dictionary).get("painting", ""))
	var tex: Texture2D = UiPalette.load_art(art) if art != "" else null
	%Painting.texture = tex
	%Painting.visible = tex != null
	visible = true


func seal_button() -> Button:
	return %Seal
