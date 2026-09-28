extends GutTest
## No panel shows a true figure about land the crown does not control
## (spec 2026-09-28 §1 "Closing the leaks").

func before_each() -> void:
	Game.start_campaign(42)
	Intel.dev_all = false


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += " " + (n as Label).text
	if n is Button:
		out += " " + (n as Button).text
	if "tooltip_text" in n:
		out += " " + String(n.get("tooltip_text"))
	for c in n.get_children():
		out += _all_text(c)
	return out


func test_the_neighbours_are_not_counted_for_you() -> void:
	var p := MilitaryPanel.new()
	add_child_autofree(p)
	p.refresh()
	await wait_frames(1)
	var text := _all_text(p)
	var realm := Game.data.resolve_realm("player_realm")
	for code: String in String(Game.data.kingdoms[realm].get("neighbor_codes", "")).split("|", false):
		var total := 0
		for u: String in Game.data.world_table("military", "unit_types"):
			var v: Variant = WorldLedger.value_of(Game.data, Game.state, "military.kingdoms.%s.%s" % [code, u])
			total += int(float(v)) if v != null else 0
		if total >= 100:
			assert_false(text.contains(str(total)) or text.contains(Intel.num(total)), code)


func test_the_manor_master_shows_no_foreign_figures() -> void:
	var p := ManorMasterPanel.new()
	add_child_autofree(p)
	p.set_scope(true)
	p.refresh()
	await wait_frames(1)
	var text := _all_text(p)
	var realm := Game.data.resolve_realm("player_realm")
	var ids := Game.data.manors.keys()
	ids.sort()
	var checked := 0
	for id: int in ids:
		if MapOwnership.owner_of(Game.data, Game.state, MapManors.province_of(Game.data, id, Game.state)) == realm:
			continue
		var people := int(RealmEconomy.line_of(Game.data, Game.state, id)["people"])
		if people >= 1000:
			assert_false(text.contains(str(people)) or text.contains(Intel.num(people)), str(id))
			checked += 1
		if checked >= 5:
			break
