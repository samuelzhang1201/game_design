extends GutTest
## No panel shows a true figure about land the crown does not control
## (spec 2026-09-28 §1 "Closing the leaks"). Fix round 1 (owner review): a
## BarChart draws its rows on its own canvas (draw_string), never as
## Label/Button nodes or a tooltip_text property, and a Tree's cells live in
## TreeItems, which are not Nodes at all — so a naive Node-tree text walk
## never sees either widget's real numbers and the leak test could never
## fail. This file now also reads BarChart.rows directly (both a row's
## rendered "text" and its raw "value", in case the text itself is a
## RealmDashboard-style compaction like "1.2k" rather than the true figure)
## and walks the Manor Master's Tree the way its own test does
## (get_first_child/get_next), collecting every column's text and tooltip.

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


## Every string any BarChart under `root` carries in its rows: the row's own
## drawn "text" and str(int(value)) of its raw number — whichever the panel
## actually uses, a plain Label (covered by _all_text) or a BarChart
## (covered here), the true figure is caught either way.
func _chart_texts(root: Node) -> Array:
	var out: Array = []
	if root is BarChart:
		for row: Dictionary in (root as BarChart).rows:
			out.append(String(row.get("text", "")))
			out.append(str(int(float(row.get("value", 0.0)))))
	for c in root.get_children():
		out.append_array(_chart_texts(c))
	return out


## Every cell's text and tooltip in a Tree, walked the same way
## tests/ui/test_manor_master_panel.gd walks it — a TreeItem is not a Node,
## so no amount of get_children() recursion from the panel ever reaches it.
func _tree_texts(tree: Tree, columns: int) -> Array:
	var out: Array = []
	var root := tree.get_root()
	var item := root.get_first_child() if root != null else null
	while item != null:
		for col in range(columns):
			out.append(item.get_text(col))
			out.append(item.get_tooltip_text(col))
		item = item.get_next()
	return out


func test_the_neighbours_are_not_counted_for_you() -> void:
	var p := MilitaryPanel.new()
	add_child_autofree(p)
	p.refresh()
	await wait_frames(1)
	var text := _all_text(p) + " " + " ".join(_chart_texts(p))
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
	var text := _all_text(p) + " " + " ".join(_tree_texts(p.table(), ManorMasterPanel.COLUMNS.size()))
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
