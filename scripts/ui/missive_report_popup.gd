class_name MissiveReportPopup
extends Control
## A spy's report (owner 2026-09-28, spec 2026-09-28 §2): centred over the
## map, the spy's painting (sub-project D; hidden until installed) and his
## report; Seal closes it and hands its rect to the envelope flight.

signal sealed(from: Rect2)


func _ready() -> void:
	%Window.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 20))
	UiPalette.style_header(%ReportTitle, 20)
	%Seal.pressed.connect(func() -> void:
		var r: Rect2 = %Window.get_global_rect()
		visible = false
		sealed.emit(r))


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
