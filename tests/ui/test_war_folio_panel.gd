extends GutTest
## The folio opens on a chosen piece and closes on ×, Escape or a click outside (spec §4).

const RunDir := preload("res://tests/run_dir.gd")

var panel: WarFolioPanel
var code := ""


func before_each() -> void:
	Game.start_campaign(42)
	panel = load("res://scenes/war_room/war_folio.tscn").instantiate()
	panel.size = Vector2(1000, 640)
	add_child_autofree(panel)
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break


func test_the_right_page_lays_out_every_section_and_row() -> void:
	panel.open_for(code)
	assert_true(panel.visible)
	var secs := WarFolio.sections(Game.data, Game.state, code)
	var nodes := panel.section_nodes()
	assert_eq(nodes.size(), secs.size())
	var first: Node = nodes[0]
	assert_eq((first.get_node("Header") as Label).text, String(secs[0]["label"]).to_upper())
	assert_eq(first.get_node("Rows").get_child_count(), (secs[0]["rows"] as Array).size())


func test_escape_closes_it() -> void:
	panel.open_for(code)
	watch_signals(panel)
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	panel._unhandled_input(e)
	assert_false(panel.visible)
	assert_signal_emitted(panel, "closed")


## Owner 2026-10-07/08: the book opens SMALL in the room's upper-left — one
## page, the figure beside the regiment's name and the glance rows — with no
## dim, so the room around it stays in play; + holds the whole book up full
## size over a dim, and the book's − or a click on the dim lays it back.
func test_it_opens_docked_as_one_small_page_with_the_room_free_around_it() -> void:
	panel.open_for(code)
	await wait_process_frames(2)
	assert_false((panel.get_node("%Dim") as Control).visible, "no dim")
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks beside the book reach the room")
	assert_true((panel.get_node("%Docket") as Control).visible)
	assert_false((panel.get_node("%Folder") as Control).visible, "the whole book waits")
	var rect := panel.book_rect()
	# the design canvas is 1280x720: at most ~30% of its width and ~45% of its height
	assert_lte(rect.size.x, 1280.0 * 0.30, "narrow")
	assert_lte(rect.size.y, 720.0 * 0.45, "short")
	assert_lt(rect.get_center().x, panel.size.x * 0.5, "in the left half")
	assert_lt(rect.get_center().y, panel.size.y * 0.5, "and the upper")
	assert_eq(panel.get_node("%Figure").get_parent(), panel.get_node("%DockFigSlot"), "the figure is on the small page")


func test_the_docked_page_reads_the_brief_and_follows_the_state() -> void:
	panel.open_for(code)
	var b := WarFolio.brief(Game.data, Game.state, code)
	assert_eq((panel.get_node("%DockTitle") as Label).text, String(b["title"]))
	var want := {}
	for row: Dictionary in b["rows"]:
		want[String(row["label"])] = String(row["text"])
	assert_eq(panel.brief_rows(), want)
	var st := ArmySystem.state_of(Game.data, Game.state, code).duplicate()
	st["morale"] = int(st["morale"]) - 7
	Game.state.regiments[code] = st
	panel.refresh()
	assert_true(String(panel.brief_rows()["Morale"]).begins_with("%d / 100" % int(st["morale"])))


func test_the_docked_pages_plus_or_a_click_on_it_holds_the_whole_book_up() -> void:
	panel.open_for(code)
	await wait_process_frames(2)
	(panel.get_node("%DockEnlarge") as Button).pressed.emit()
	assert_true(panel.is_full())
	panel.set_full(false)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	(panel.get_node("%DockBook") as Control).gui_input.emit(e)
	assert_true(panel.is_full(), "a click on the page opens the book")
	(panel.get_node("%Enlarge") as Button).pressed.emit()
	assert_false(panel.is_full(), "the book's − lays it back")
	(panel.get_node("%DockClose") as Button).pressed.emit()
	assert_false(panel.visible, "the small page's × closes it")


func test_the_book_held_up_is_full_size_and_a_click_on_the_dim_lays_it_back() -> void:
	panel.open_for(code)
	await wait_process_frames(2)
	(panel.get_node("%DockEnlarge") as Button).pressed.emit()
	assert_true(panel.is_full())
	assert_true((panel.get_node("%Dim") as Control).visible)
	assert_true((panel.get_node("%Folder") as Control).visible)
	assert_false((panel.get_node("%Docket") as Control).visible)
	assert_eq((panel.get_node("%Folder") as Control).scale, Vector2.ONE, "full size")
	var fig: WarInkFigure = panel.get_node("%Figure")
	assert_eq(fig.get_parent(), panel.get_node("%FigSlot"), "the figure moved into the whole book")
	assert_not_null(panel.get_node_or_null("%FigViewport"), "its own names still resolve")
	await wait_process_frames(2)
	assert_eq((panel.get_node("%FigViewport") as SubViewport).render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	(panel.get_node("%Dim") as ColorRect).gui_input.emit(e)
	assert_true(panel.visible, "still open")
	assert_false(panel.is_full(), "back in its corner")
	assert_false((panel.get_node("%Dim") as Control).visible)
	assert_eq(fig.get_parent(), panel.get_node("%DockFigSlot"), "the figure came back")
	assert_eq((panel.get_node("%FigViewport") as SubViewport).render_target_update_mode, SubViewport.UPDATE_ALWAYS,
		"and still draws")


func test_the_close_cross_closes_it_and_it_opens_docked_again() -> void:
	panel.open_for(code)
	panel.set_full(true)
	(panel.get_node("%Close") as Button).pressed.emit()
	assert_false(panel.visible)
	panel.open_for(code)
	assert_false(panel.is_full())


## The court on a fresh reign, as Start Game begins it but without the
## opening narration's screen, which no test here needs.
func _court() -> GameRoot:
	Game.start_campaign(44)   # the seed Start Game begins
	Game.next_tick()
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	r.bottom_bar().button("WAR ROOM").pressed.emit()
	await wait_process_frames(2)
	return r


func _own_code() -> String:
	return String(WarRoom.pieces(Game.data, Game.state)[0]["code"])


func test_all_six_sections_are_laid_in_the_panels_columns() -> void:
	panel.open_for(code)
	var cols := panel.get_node("%Right").get_children()
	assert_eq(cols.size(), panel.columns)
	var keys: Array = []
	for col in cols:
		assert_gt(col.get_child_count(), 0, "no empty column")
		for sec in col.get_children():
			keys.append(String(sec.name))
	assert_eq(keys, ["composition", "arms", "morale", "supply", "ground", "march"])


func test_a_long_label_keeps_its_fixed_width_and_is_present() -> void:
	panel.open_for(code)
	await wait_process_frames(2)
	var found := false
	var w := panel.label_w_px
	for sec in panel.section_nodes():
		for line in sec.get_node("Rows").get_children():
			var l := line.get_child(0) as Label
			assert_lte(l.size.x, w + 0.5, "label '%s' wider than the key" % l.text)
			assert_eq(l.vertical_alignment, VERTICAL_ALIGNMENT_TOP)
			if l.text.begins_with("Matchups"):
				found = true
	assert_true(found, "a Matchups label is present")


func test_the_page_is_laid_again_when_the_state_moves_under_it() -> void:
	panel.open_for(code)
	var st := ArmySystem.state_of(Game.data, Game.state, code)
	var before := _row_text("Morale")
	assert_ne(before, "")
	Game.state.regiments[code] = st.duplicate()
	Game.state.regiments[code]["morale"] = int(st["morale"]) - 7
	panel.refresh()
	assert_ne(_row_text("Morale"), before)
	assert_true(_row_text("Morale").begins_with(str(int(st["morale"]) - 7)))


func _row_text(label: String) -> String:
	for sec in panel.section_nodes():
		for line in sec.get_node("Rows").get_children():
			if (line.get_child(0) as Label).text == label:
				return (line.get_child(1) as Label).text
	return ""


func test_escape_does_nothing_while_the_folio_is_not_in_a_visible_tree() -> void:
	var holder := Control.new()
	add_child_autofree(holder)
	var p: WarFolioPanel = load("res://scenes/war_room/war_folio.tscn").instantiate()
	holder.add_child(p)
	p.open_for(code)
	holder.hide()
	watch_signals(p)
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	p._unhandled_input(e)
	assert_signal_not_emitted(p, "closed")


func test_open_for_starts_at_the_top() -> void:
	panel.open_for(code)
	var scroll: ScrollContainer = panel.get_node("%RightScroll")
	scroll.scroll_vertical = 50
	panel.open_for(code)
	assert_eq(scroll.scroll_vertical, 0)


func test_a_piece_selected_in_the_war_room_opens_the_folio_and_closing_clears_it() -> void:
	var r: GameRoot = await _court()
	var screen := r.war_room_screen()
	var folio: WarFolioPanel = screen.get_node("%Folio")
	assert_false(folio.visible)
	var c := _own_code()
	screen.view().select(c)
	await wait_process_frames(1)
	assert_true(folio.visible)
	assert_eq(folio.code(), c)
	assert_eq(screen.view().selected_army(), c)
	folio.close()
	assert_false(folio.visible)
	assert_eq(screen.view().selected_army(), "")


func test_closing_the_war_room_closes_the_folio() -> void:
	var r: GameRoot = await _court()
	var screen := r.war_room_screen()
	var folio: WarFolioPanel = screen.get_node("%Folio")
	screen.view().select(_own_code())
	await wait_process_frames(1)
	assert_true(folio.visible)
	screen.close()
	assert_false(folio.visible)


func test_the_screens_refresh_lays_an_open_folio_again() -> void:
	var r: GameRoot = await _court()
	var screen := r.war_room_screen()
	var folio: WarFolioPanel = screen.get_node("%Folio")
	var c := _own_code()
	screen.view().select(c)
	await wait_process_frames(1)
	var st := ArmySystem.state_of(Game.data, Game.state, c).duplicate()
	st["morale"] = int(st["morale"]) - 9
	Game.state.regiments[c] = st
	screen.refresh()
	await wait_process_frames(2)
	var found := false
	for sec in folio.section_nodes():
		for line in sec.get_node("Rows").get_children():
			if (line.get_child(0) as Label).text == "Morale":
				found = (line.get_child(1) as Label).text.begins_with(str(int(st["morale"])))
	assert_true(found)


func test_the_drill_tabs_are_the_arms_clips_and_the_current_order_plays() -> void:
	panel.open_for(code)
	var fig: WarInkFigure = panel.get_node("%Figure")
	var arm := MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code))
	var clips := fig.show_arm(Game.data, arm)
	var drills := WarFolio.drills_for(Game.data, arm, clips)
	var tabs := panel.get_node("%Drills").get_children()
	assert_gt(drills.size(), 0, "the arm's model has clips")
	assert_eq(tabs.size(), drills.size())
	var cur := WarFolio.current_drill(drills, ArmySystem.order_of(Game.data, Game.state, code))
	assert_eq(fig.playing(), String(drills[cur]["clip_name"]))


func test_a_drill_tab_plays_its_clip() -> void:
	panel.open_for(code)
	var tabs := panel.get_node("%Drills").get_children()
	if tabs.size() < 2:
		pass_test("this arm's model has one clip")
		return
	(tabs[1] as Button).pressed.emit()
	assert_eq((panel.get_node("%Figure") as WarInkFigure).playing(), String(tabs[1].get_meta("clip")))


func test_one_arms_button_per_arm_and_the_formation_draws_its_figures() -> void:
	panel.open_for(code)
	assert_eq(panel.get_node("%Arms").get_child_count(), WarFolio.arms_of(Game.data, code).size())
	assert_eq(int(panel.get_node("%Formation").get_meta("figures")), WarFolio.figures(Game.data, Game.state, code))


func test_a_refresh_does_not_rebuild_the_figure_while_nothing_changed() -> void:
	panel.open_for(code)
	var fig: WarInkFigure = panel.get_node("%Figure")
	var tab := (panel.get_node("%Drills").get_child(0) as Button)
	var before := fig.loads()
	panel.refresh()
	panel.refresh()
	assert_eq(fig.loads(), before)
	assert_eq(panel.get_node("%Drills").get_child(0), tab, "the tabs stand")


func test_the_figure_renders_only_while_the_folio_is_open() -> void:
	panel.open_for(code)
	var vp: SubViewport = panel.get_node("%FigViewport")
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	panel.close()
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED)


func test_a_changed_order_replays_the_current_drill_without_a_reload() -> void:
	panel.open_for(code)
	var fig: WarInkFigure = panel.get_node("%Figure")
	var before := fig.loads()
	var st := ArmySystem.state_of(Game.data, Game.state, code).duplicate()
	st["order"] = ArmySystem.ORDER_MARCH
	Game.state.regiments[code] = st
	panel.refresh()
	assert_eq(fig.loads(), before)
	var arm := MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code))
	var drills := WarFolio.drills_for(Game.data, arm, fig.clips())
	var cur := WarFolio.current_drill(drills, ArmySystem.ORDER_MARCH)
	assert_eq(fig.playing(), String(drills[cur]["clip_name"]))


## A crown land regiment with the given arm among its men ("" when none).
func _code_with(arm: String) -> String:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm"), Game.state):
		if String(r.get("is_naval", "0")) != "1" and int(float(r.get(arm, 0))) > 0:
			return String(r["regiment_code"])
	return ""


func _arm_button(arm: String) -> Button:
	for b: Button in panel.get_node("%Arms").get_children():
		if String(b.get_meta("arm")) == arm:
			return b
	return null


func test_an_arms_button_wears_its_icon_drawn_in_ink() -> void:
	panel.open_for(code)
	var ink: Color = Game.data.war_palette["ink"]
	for b: Button in panel.get_node("%Arms").get_children():
		assert_not_null(b.icon, "arm %s has its icon" % b.get_meta("arm"))
		var bytes := b.icon.get_image().get_data()   # every mip level: a small draw shows the lower ones
		var inked := 0
		for i in range(0, bytes.size() - 3, 4):
			if bytes[i + 3] > 3:
				inked += 1
				assert_almost_eq(float(bytes[i]) / 255.0, ink.r, 0.02)
				assert_almost_eq(float(bytes[i + 1]) / 255.0, ink.g, 0.02)
				assert_almost_eq(float(bytes[i + 2]) / 255.0, ink.b, 0.02)
		assert_gt(inked, 0, "arm %s's icon has ink" % b.get_meta("arm"))


func test_clicking_an_arm_switches_the_figure_and_retargets_the_tabs() -> void:
	var c := _code_with("cavalry")
	assert_ne(c, "")
	panel.open_for(c)
	var fig: WarInkFigure = panel.get_node("%Figure")
	for arm: String in ["infantry", "cavalry"]:
		var b := _arm_button(arm)
		if b == null:
			continue
		b.pressed.emit()
		var drills := WarFolio.drills_for(Game.data, arm, fig.clips())
		assert_gt(drills.size(), 0)
		assert_eq(panel.get_node("%Drills").get_child_count(), drills.size(), arm)
		assert_false(fig.glyph_shown())
		assert_ne(fig.playing(), "")
		for t: Button in panel.get_node("%Drills").get_children():
			assert_true(fig.clips().has(String(t.get_meta("clip"))), "tab clip belongs to the shown model")


func test_artillery_has_no_model_so_it_draws_its_glyph_with_no_tabs() -> void:
	var c := _code_with("artillery")
	assert_ne(c, "", "a crown regiment fields guns")
	assert_false(WarFolio.modelled(Game.data, "artillery"))
	assert_true(WarFolio.modelled(Game.data, "infantry"))
	panel.open_for(c)
	var fig: WarInkFigure = panel.get_node("%Figure")
	var loads := fig.loads()
	_arm_button("artillery").pressed.emit()
	assert_true(fig.glyph_shown())
	assert_eq(panel.get_node("%Drills").get_child_count(), 0)
	assert_eq(fig.playing(), "")
	assert_eq(fig.loads(), loads, "no model is loaded for the guns")
	# a unit is one arm: the guns' train has only its own button, and a foot
	# unit opened after it shows its model with its drills
	assert_null(_arm_button("infantry"), "the train fields no foot")
	panel.open_for(_code_with("infantry"))
	assert_false(fig.glyph_shown())
	assert_gt(panel.get_node("%Drills").get_child_count(), 0)


func test_playing_a_clip_loops_a_copy_never_the_shared_animation() -> void:
	var fig: WarInkFigure = panel.get_node("%Figure")
	var clips := fig.show_arm(Game.data, "cavalry")
	var attack := ""
	for n in clips:
		if n.to_upper().ends_with("ATTACK"):
			attack = n
	assert_ne(attack, "", "the cavalry model has an ATTACK clip")
	var path := GameArt.path(GameArt.ARMY_MODELS, "cavalry")
	var fresh := (load(path) as PackedScene).instantiate() as Node3D
	var shared := Map3DUnits.find_anim(fresh).get_animation(attack)
	var was := shared.loop_mode
	fig.play(attack)
	assert_eq(fig.loop_of(attack), Animation.LOOP_LINEAR, "the folio's own copy loops")
	var again := (load(path) as PackedScene).instantiate() as Node3D
	assert_eq(Map3DUnits.find_anim(again).get_animation(attack).loop_mode, was, "the shared clip is untouched")
	fresh.free()
	again.free()


func test_take_apart_shows_only_when_the_arms_parts_exist() -> void:
	panel.open_for(code)
	var arm := MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code))
	var want := WarFolio.modelled(Game.data, arm) and ResourceLoader.exists(WarExplode.parts_path(arm))
	assert_eq((panel.get_node("%TakeApart") as Button).visible, want)


## The owner's parts exports are installed: infantry and cavalry take apart,
## archers do not until they have their own model (Ruling 23).
func test_take_apart_shows_for_the_installed_arms_only() -> void:
	panel.open_for(code)
	for arm: String in ["infantry", "cavalry"]:
		panel._show_arm(arm)
		assert_true((panel.get_node("%TakeApart") as Button).visible, arm)
	panel._show_arm("archers")
	assert_false((panel.get_node("%TakeApart") as Button).visible, "archers")


func test_take_apart_is_hidden_for_an_unmodelled_arm() -> void:
	panel.open_for(code)
	panel._show_arm("artillery")
	assert_false((panel.get_node("%TakeApart") as Button).visible)


func test_take_apart_toggles_the_exploded_view() -> void:
	panel.open_for(code)
	var arm := MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code))
	var btn: Button = panel.get_node("%TakeApart")
	var fig: WarInkFigure = panel.get_node("%Figure")
	panel._show_arm(arm)
	panel.toggle_take_apart(_stand_in())   # the seam: the real file is the owner's Blender step
	assert_not_null(fig.parts_root(), "apart")
	assert_eq(btn.text, "Put together")
	assert_false((panel.get_node("%Drills") as Control).visible, "the drill tabs make way")
	panel.toggle_take_apart(null)
	assert_null(fig.parts_root(), "together again")
	assert_true((panel.get_node("%Drills") as Control).visible)


func test_another_arm_puts_the_kit_back_together() -> void:
	panel.open_for(code)
	var arm := MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code))
	panel._show_arm(arm)
	panel.toggle_take_apart(_stand_in())
	panel._show_arm(arm)
	assert_null((panel.get_node("%Figure") as WarInkFigure).parts_root())
	assert_true((panel.get_node("%Drills") as Control).visible)


func _stand_in() -> PackedScene:
	var root := Node3D.new()
	var m := MeshInstance3D.new()
	m.name = "helmet"
	m.mesh = BoxMesh.new()
	root.add_child(m)
	m.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


func after_each() -> void:
	WarExplode.overrides = {}


## A parts file on disk (a stand-in for the owner's Blender export), so the
## button's real exists-check and the real load path run.
func _parts_file(arm: String) -> String:
	var path := RunDir.dir("war_parts").path_join("%s_parts.tscn" % arm)
	assert_eq(ResourceSaver.save(_stand_in(), path), OK)
	WarExplode.overrides[arm] = path
	return path


func test_take_apart_shows_when_the_arms_parts_file_exists() -> void:
	panel.open_for(code)
	var arm := MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code))
	assert_true(WarFolio.modelled(Game.data, arm))
	_parts_file(arm)
	panel._show_arm(arm)
	var btn: Button = panel.get_node("%TakeApart")
	assert_true(btn.visible)
	btn.pressed.emit()   # the real press: the file is loaded, not handed in
	assert_not_null((panel.get_node("%Figure") as WarInkFigure).parts_root())
	assert_eq(btn.text, "Put together")


func test_a_second_press_kills_the_running_tween() -> void:
	panel.open_for(code)
	panel._show_arm(MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code)))
	panel.toggle_take_apart(_stand_in())
	var tween: Tween = panel._fly
	assert_not_null(tween)
	assert_true(tween.is_valid())
	panel.toggle_take_apart(null)
	assert_false(tween.is_valid(), "killed")
	assert_null(panel._fly)


func test_closing_puts_the_kit_back_together() -> void:
	panel.open_for(code)
	panel._show_arm(MapObjects.regiment_arm(Game.data, ArmySystem.regiment(Game.data, code)))
	panel.toggle_take_apart(_stand_in())
	panel.close()
	assert_null((panel.get_node("%Figure") as WarInkFigure).parts_root())
	assert_null(panel._fly)
	assert_true((panel.get_node("%Drills") as Control).visible)


## P4.4b9: a battlefield unit's docked page carries its task block; Send task
## runs the quoted BATTLE_TASK through Game and the page then reads it pending.
func _on_battlefield() -> String:
	var enemy := String(Game.state.foes.keys()[0])
	var at := ArmySystem.pack_to_metres(Game.data, ArmySystem.position_of(Game.data, Game.state, ArmySystem.regiment(Game.data, code, Game.state)))
	Game.state.battles = [{"id": 77, "att": [code], "def": [enemy], "rounds": 0, "town": "", "place_x_m": at.x, "place_y_m": at.y}]
	Game.state.king_state.x_m = 100000000
	Game.state.king_state.y_m = 100000000
	Game.state.metrics.treasury = 500
	return enemy


func test_the_task_block_shows_only_on_a_battlefield() -> void:
	panel.open_for(code)
	assert_false((panel.get_node("%TaskOrders") as Control).visible)
	_on_battlefield()
	panel.refresh()
	assert_true((panel.get_node("%TaskOrders") as Control).visible)
	assert_eq((panel.get_node("%Task") as OptionButton).item_count, Game.data.battle_behaviors.size())
	assert_eq((panel.get_node("%Target") as OptionButton).item_count, 2, "any enemy, then the one opponent")
	assert_eq((panel.get_node("%TaskFormation") as OptionButton).item_count, Game.data.battle_formations.size() + 1)
	assert_false((panel.get_node("%CancelTask") as Control).visible, "nothing to cancel yet")
	await wait_process_frames(2)
	assert_lte(panel.book_rect().size.x, 1280.0 * 0.30, "the block never widens the docked page")


func test_send_task_runs_the_quote_and_the_page_reads_it_pending() -> void:
	var enemy := _on_battlefield()
	panel.open_for(code)
	var target: OptionButton = panel.get_node("%Target")
	target.select(1)
	target.item_selected.emit(1)
	var quote := panel.task_quote()
	assert_eq(String(quote["reason"]), "")
	assert_eq(quote["params"]["target_unit"], enemy)
	assert_string_contains((panel.get_node("%TaskQuote") as Label).text, "%d gold filing + %d gold courier" % [int(quote["filing_gold"]), int(quote["courier_gold"])])
	var before := int(Game.state.metrics.treasury)
	(panel.get_node("%SendTask") as Button).pressed.emit()
	assert_eq(int(Game.state.metrics.treasury), before - int(quote["filing_gold"]) - int(quote["courier_gold"]))
	panel.refresh()
	assert_true((panel.get_node("%TaskStatus") as Label).text.begins_with("Pending: Frontal charge against"))
	assert_true((panel.get_node("%CancelTask") as Control).visible)
	assert_eq((panel.get_node("%Target") as OptionButton).selected, 1, "the picks survive the refresh")
	assert_string_contains((panel.get_node("%TaskQuote") as Label).text, "Rides with the courier already waiting")
	(panel.get_node("%CancelTask") as Button).pressed.emit()
	panel.refresh()
	assert_eq((panel.get_node("%TaskStatus") as Label).text.count("Pending:"), 2)


func test_a_refused_task_names_its_reason_and_cannot_be_sent() -> void:
	_on_battlefield()
	Game.state.metrics.treasury = 0
	panel.open_for(code)
	var why := String(panel.task_quote()["reason"])
	assert_ne(why, "")
	assert_eq((panel.get_node("%TaskQuote") as Label).text, why, "ActionSystem.validate's own words")
	assert_true((panel.get_node("%SendTask") as Button).disabled)


func test_the_quote_follows_the_purse_without_a_new_task_view() -> void:
	_on_battlefield()
	panel.open_for(code)
	assert_false((panel.get_node("%SendTask") as Button).disabled)
	Game.state.metrics.treasury = 0
	panel.refresh()
	assert_true((panel.get_node("%SendTask") as Button).disabled)
	assert_eq((panel.get_node("%TaskQuote") as Label).text, String(panel.task_quote()["reason"]))
