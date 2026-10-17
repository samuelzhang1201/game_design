class_name WarFormationDots
extends Control
## The folio's formation diagram (spec 2026-10-01-war-room-design §4): one ink
## dot per figure of the regiment's strength tier (data/army/army_formations.csv),
## the front marked above the first rank.


func _draw() -> void:
	if not has_meta("figures") or Game.data == null:
		return
	var n := int(get_meta("figures"))
	var gap := Game.data.bal("war_formation_dot_gap_px")
	var radius := Game.data.bal("war_formation_dot_r_px")
	var ink: Color = Game.data.war_palette["ink"]
	var rubric: Color = Game.data.war_palette["rubric"]
	for row: Dictionary in Game.data.army_formations:
		if int(row["figures"]) != n:
			continue
		var top := INF
		for s: Vector2 in deployment_slots():
			var at := size * 0.5 + s * gap   # slots: x to the right, z toward the rear (down the page)
			draw_circle(at, radius, ink)
			top = minf(top, at.y)
		var font := UiPalette.role_font("header")
		var px := int(Game.data.bal("war_formation_label_px"))
		var word := "FRONT ▲"
		var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, Vector2((size.x - w) * 0.5, top - Game.data.bal("war_formation_label_gap_px")),
			word, HORIZONTAL_ALIGNMENT_LEFT, -1, px, rubric)
		return

func deployment_slots() -> Array:
	var n := int(get_meta("figures", 0))
	var formation := String(get_meta("formation", ""))
	if formation != "":
		return BattleFormation.slots(formation, n, int(get_meta("frontage_permille", 1000)))
	if Game.data != null:
		for row: Dictionary in Game.data.army_formations:
			if int(row["figures"]) == n:
				return row["slots"]
	return []
