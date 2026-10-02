class_name LedgerScreen
extends Control
## The LEDGER screen (spec 2026-09-30-ledger-ontology-design §6.1): laid
## exactly over the map panel (GameRoot fits it), so the left column keeps
## FACTS and the right column keeps the council (invariant 10). The only
## LEDGER piece that touches Game: opening it STOPS the clock and holds it
## still while it is open, and it stays stopped until the player starts it
## again (owner 2026-10-01: the chart reflects the present); it reads the galaxy (Ledger.galaxy) again
## after a state change while open (an order, DEV MODE — at most once a
## frame), fills the left column with a star's or a thread's card, and runs
## an order through Game.try_execute. It clears only a card it put in the
## left column. Its search box finds a star — or an instance folded into a
## province's star — by its label (LedgerSearch).

signal show_requested(subject: Dictionary)
signal closed

var _lens := "all"
var _opened: Dictionary = {}       # province code -> true: opened this viewing (never saved)
var _open_order: Array[String] = []
var _snap: Dictionary = {}
var _detail: MapDetailPanel
var _bound := false
var _dirty := false        # a state change waits to be drawn (drained in _process)
var _card_mine := false    # the left column's card is the LEDGER's own
var _card_star := ""       # the star whose card it is ("" for a thread's or an order's)
var _rebuilds := 0         # snapshots drawn (the tests' seam)
var _search_index: Array = []   # LedgerSearch.index of _snap, built on the first search after a redraw
var _search_found: Array = []   # the matches listed now
var _search_pick := 0           # the listed match Enter picks

@onready var _view: LedgerView3D = %View
@onready var _orders: LedgerOrderMenu = %Orders
@onready var _search: LineEdit = %Search
@onready var _search_list: PanelContainer = %SearchList
@onready var _search_rows: VBoxContainer = %SearchRows


func _ready() -> void:
	# its look is scenes/ledger_screen.tscn (owner 2026-10-02): the frame
	# (ledger_frame.tres), the title, the search list (ledger_search.tres)
	visible = false
	%Close.pressed.connect(close)
	%Front.pressed.connect(func() -> void: _view.front_view())
	%Back.pressed.connect(back)
	_view.sphere_selected.connect(_on_sphere)
	_view.thread_selected.connect(_on_thread)
	_view.drill_requested.connect(drill)
	_view.orders_requested.connect(_on_orders)
	_orders.chosen.connect(_on_order)
	_search.text_changed.connect(_on_search_text)
	_search.text_submitted.connect(func(_t: String) -> void: pick_match(_search_pick))
	_search.gui_input.connect(_on_search_key)
	# a press on the chart puts the list away and gives the keys back
	_view.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_search_list.visible = false
			_search.release_focus())


## Freed while open (the game quits, a test ends): the clock is let go, never
## left held for whatever comes next.
func _exit_tree() -> void:
	if visible:
		Game.hold_clock(false)


func view() -> LedgerView3D:
	return _view


func snapshot() -> Dictionary:
	return _snap


func lens() -> String:
	return _lens


## Open over the map, the left column's card being `detail`'s (the screen's
## own MapDetailPanel, handed in on every open: a screen swap makes a new one).
func open(detail: MapDetailPanel) -> void:
	if not _bound:
		_bound = true
		# The shipped ontology validates (tests/engine/test_ledger_schema.gd);
		# a hand edit that breaks it says so once, here, not as a silent gap.
		for err: String in Ledger.validate(Game.data):
			push_error("LEDGER data: " + err)
		_view.bind(Game.data)
		_build_lenses()
		_search.custom_minimum_size.x = Game.data.bal("ledger_search_width_px")
		Game.state_changed.connect(refresh)
	if not _has_detail() or detail != _detail:
		_card_mine = false  # a new screen's column holds nothing of the LEDGER's
	_detail = detail
	# the clock stops and nothing starts it while the LEDGER is open
	Game.hold_clock(true)
	visible = true
	_dirty = false
	_view.set_active(true)
	_rebuild(false)
	set_lens(_lens)


func close() -> void:
	if not visible:
		return
	visible = false
	_dirty = false
	_opened.clear()       # the provinces opened belong to this viewing
	_open_order.clear()
	_view.set_active(false)
	clear_search()
	_clear_card()
	# let go, but not restarted: the player starts the clock again (owner
	# 2026-10-01)
	Game.hold_clock(false)
	closed.emit()


## Draw the live state again, keeping the camera (an order, DEV MODE). Only
## marks the LEDGER dirty: several changes in one frame are one snapshot.
## (The clock is held still while the LEDGER is open, so no day passes under
## it — owner 2026-10-01.)
func refresh() -> void:
	if visible:
		_dirty = true


func _process(_delta: float) -> void:
	if _dirty and visible:
		_dirty = false
		_rebuild(true)


func opened() -> Dictionary:
	return _opened


## A tab chooses its cluster (data/ledger_clusters.csv `lens`); All is the
## whole galaxy. The camera flies; nothing is read again.
func set_lens(lens_id: String) -> void:
	_lens = lens_id
	for b: Node in %Lenses.get_children():
		(b as Button).set_pressed_no_signal(String(b.name) == "Lens_" + lens_id)
	_view.focus_cluster(_cluster_for(lens_id))
	_clear_card()  # the old tab's card names a star the camera has left
	_crumb()


func _cluster_for(lens_id: String) -> String:
	for c: Dictionary in Game.data.ledger_clusters:
		if String(c["lens"]) == lens_id:
			return String(c["cluster"])
	return "all"


## A double click: a province opens (its manors, towns and buildings settle
## round it) or closes; any other star is selected, its web framed and its
## card put in the left column.
func drill(id: String) -> void:
	if id == "" or id.begins_with("more:"):
		return
	if id.begins_with("province:"):
		var code := id.substr(9)
		if _opened.has(code):
			_opened.erase(code)
			_open_order.erase(code)
		else:
			_opened[code] = true
			_open_order.append(code)
		# the province is selected AS the new chart is drawn: one restyle,
		# not a second one after it (Task 11 fix round 1, F7: ~12 ms of the
		# third province's stall)
		_rebuild(true, id)
		# opening frames the province and what it unfolded; closing frames
		# nothing (Task 11 fix round 1, F8)
		if _opened.has(code):
			_view.frame_opened(id)
	else:
		_view.frame_web(id)
		_view.select(id)
	_show_card(LedgerCards.entry(Game.data, Game.state, id, _snap), id)


## Closes the last province opened.
func back() -> void:
	if _open_order.is_empty():
		return
	_opened.erase(_open_order.pop_back())
	_rebuild(true)


func _has_detail() -> bool:
	return _detail != null and is_instance_valid(_detail)


## The left column's card, put there by the LEDGER; `star` is the star it
## is the card of, if any (a redraw draws it again).
func _show_card(entry: Dictionary, star: String = "") -> void:
	if not _has_detail():
		return
	_detail.show_entry(entry)
	_card_mine = not entry.is_empty()
	_card_star = star if _card_mine else ""


## Closes the left column's card only if the LEDGER put it there: a card the
## player opened before the LEDGER stays when it closes.
func _clear_card() -> void:
	if _card_mine and _has_detail():
		_detail.show_entry({})
	_card_mine = false
	_card_star = ""


func _rebuild(keep_camera: bool, select_id: String = "") -> void:
	_rebuilds += 1
	var selected := _view.selected()
	_snap = Ledger.galaxy(Game.data, Game.state, _opened)
	_search_index = []
	_view.show_snapshot(_snap, keep_camera, select_id)
	if selected != "" and _view.selected() == "":
		_clear_card()  # the selected star is gone (a courier arrived, a report aged out)
	elif _card_mine and _card_star != "" and _card_star == _view.selected():
		# the selected star's card follows the day it is redrawn on
		_show_card(LedgerCards.entry(Game.data, Game.state, _card_star, _snap), _card_star)
	_crumb()


func _crumb() -> void:
	var parts: Array[String] = ["Realm"]
	for c: Dictionary in Game.data.ledger_clusters:
		if String(c["cluster"]) == _view.cluster():
			parts.append(String(c["label"]))
	for code: String in _open_order:
		parts.append(LedgerResolvers.label_of(Game.data, Game.state, "province:" + code))
	%Crumb.text = " › ".join(parts)
	%Back.visible = not _open_order.is_empty()


# --- search (owner 2026-10-01: 在ledger界面新增一个搜索栏，可以搜索node) ------

func search_box() -> LineEdit:
	return _search


## The matches listed now (LedgerSearch.matches entries).
func search_matches() -> Array:
	return _search_found


## The listed matches for `text`: the stars of this snapshot and the
## instances folded into a province's star, by label (LedgerSearch).
func search(text: String) -> Array:
	if _search_index.is_empty():
		_search_index = LedgerSearch.index(Game.data, Game.state, _snap)
	if text.strip_edges().length() < int(Game.data.bal("ledger_search_min_chars")):
		return []
	return LedgerSearch.matches(_search_index, text, int(Game.data.bal("ledger_search_max_matches")))


## Empties the box and puts the list away (Escape, a pick, closing).
func clear_search() -> void:
	_search.text = ""
	_search_found = []
	_search_list.visible = false
	_search.release_focus()


## Goes to the listed match `i` as a double click would: a folded instance's
## province is opened first, so its star exists; then the star is selected,
## its web framed and its card put in the left column. A province already
## open is only selected (a pick never closes one).
func pick_match(i: int) -> void:
	if i < 0 or i >= _search_found.size():
		return
	var e: Dictionary = _search_found[i]
	clear_search()
	go_to(String(e["id"]), String(e["fold"]))


## Selects `id` (opening `fold`, its province's star, first when it is folded).
func go_to(id: String, fold: String = "") -> void:
	if fold != "" and not _opened.has(fold.substr(9)):
		drill(fold)
	if id.begins_with("province:") and _opened.has(id.substr(9)):
		_view.frame_web(id)
		_view.select(id)
		_show_card(LedgerCards.entry(Game.data, Game.state, id, _snap), id)
		return
	drill(id)


func _on_search_text(text: String) -> void:
	_search_found = search(text)
	_search_pick = 0
	_fill_search_list()


func _on_search_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_ESCAPE:
			clear_search()
			_search.accept_event()
		KEY_DOWN, KEY_UP:
			if not _search_found.is_empty():
				var step := 1 if key.keycode == KEY_DOWN else -1
				_search_pick = posmod(_search_pick + step, _search_found.size())
				_fill_search_list()
			_search.accept_event()


## The list under the box: one row per match, its label and what it is, the
## one Enter picks lit.
func _fill_search_list() -> void:
	for c: Node in _search_rows.get_children():
		_search_rows.remove_child(c)
		c.queue_free()
	_search_list.visible = not _search_found.is_empty()
	if _search_found.is_empty():
		return
	var row_px := Game.data.bal("ledger_search_row_px")
	for i in _search_found.size():
		var e: Dictionary = _search_found[i]
		var b := Button.new()
		b.name = "Match%d" % i
		b.text = "%s — %s" % [e["label"], e["kind"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0.0, row_px)
		# the match Enter picks is lit in gold (the theme's LedgerMatch kinds)
		b.theme_type_variation = &"LedgerMatchLit" if i == _search_pick else &"LedgerMatch"
		b.pressed.connect(pick_match.bind(i))
		_search_rows.add_child(b)
	_place_search_list()


## Under the box, left-aligned with it, ledger_search_list_width_px wide —
## held inside the screen.
func _place_search_list() -> void:
	var box := _search.get_global_rect()
	var origin := get_global_rect().position
	var w := Game.data.bal("ledger_search_list_width_px")
	var x := minf(box.position.x - origin.x, size.x - w - 8.0)
	_search_list.position = Vector2(maxf(x, 8.0), box.end.y - origin.y + 4.0)
	_search_list.size = Vector2(w, 0.0)
	_search_list.reset_size()
	_search_list.size.x = w


## One flat tab per data/ledger_lenses.csv row, so a new lens needs no scene edit.
func _build_lenses() -> void:
	for row: Dictionary in Game.data.ledger_lenses:
		var b := Button.new()
		var lens_id := String(row["lens"])
		b.name = "Lens_" + lens_id
		b.text = String(row["label"])
		b.toggle_mode = true
		b.button_pressed = lens_id == _lens
		b.focus_mode = Control.FOCUS_NONE
		UiPalette.flat_tab(b, 14, 8.0)
		b.pressed.connect(func() -> void: set_lens(lens_id))
		%Lenses.add_child(b)


## A star's card in the left column; empty sky closes it.
func _on_sphere(id: String) -> void:
	if not _has_detail():
		return
	if id == "" or id.begins_with("more:"):
		_clear_card()
		return
	_show_card(LedgerCards.entry(Game.data, Game.state, id, _snap), id)


## A thread's card: its accounts, each with its source and its age. A
## strand ("<link id>#<i>") opens its whole link's card, every account on it.
func _on_thread(id: String) -> void:
	if not _has_detail():
		return
	var link_id := LedgerView3D.link_id_of(id)
	for l: Dictionary in _snap["links"]:
		if String(l["id"]) == link_id:
			_show_card(LedgerCards.thread_entry(Game.data, Game.state, l))
			return


## A strand's orders are its link's; a governed thread offers one "Give it
## to …" row per councillor, read from the council as it sits now.
func _on_orders(id: String, at: Vector2) -> void:
	var node_id := LedgerView3D.link_id_of(id)
	var rows := Ledger.actions_for(Game.data, node_id, Game.state)
	if rows.is_empty():
		return
	_orders.open_for(node_id, rows, _view.global_position + at)


## An order that needs the map (a place to build, a point to send a spy to)
## closes the LEDGER and shows its subject on the map — only that: its label
## says "Show on the map to …", and the player gives the order there (arming
## the march aim from here is left for later, spec §12); any other runs at once.
func _on_order(node_id: String, row: Dictionary) -> void:
	if bool(row["needs_map"]):
		var subj := LedgerCards.subject_of(Game.data, Game.state, node_id)
		if subj.is_empty():
			return
		close()
		show_requested.emit(subj)
		return
	var res := Game.try_execute(ActionRequest.make(String(row["code"]), Ledger.params_of(row, node_id)))
	if not bool(res["ok"]):
		_show_card({"title": Ledger.order_text(Game.data, row, node_id), "lines": [String(res["error"])]})
