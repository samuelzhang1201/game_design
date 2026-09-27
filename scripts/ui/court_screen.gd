class_name CourtScreen
extends Control
## Court screen (Task 6, replaces CouncilScreen): the trimmed order screen.
## All minister speech, briefing, and event resolution now happen on the
## conversation stage (Task 5) before GameRoot ever switches here — this
## screen is numbers + orders only (spec R2). Layout (user rulings
## 2026-09-09, ScreenLayout): the realm's own information in the LEFT
## column, the BRIGHT map in the middle, and a RIGHT slot that is empty by
## default — the council column (the court record, the order box, the
## lettered suggestions — R8/R10) opens from the ENTER THE
## COUNCIL handle on the right edge.
##
## The columns divide by kind (owner ruling 2026-09-10): the LEFT column
## holds FACTS — the realm dashboard, the hovered country, the host while
## the military layer is on, and the card of whatever the player clicks on
## the map — and the RIGHT slot holds PEOPLE AND TALK, the council. So a
## map click never displaces the council, and _refresh_left decides which
## of the four holds the left column.

## There is no End Turn (owner 2026-09-14): the top bar's play button is the
## only thing that moves time, and the month's end comes on its own.

## Log cap (R10-adjacent polish, ported from the old council screen's transcript):
## keeps the court log short since it only ever holds order results, not a
## full conversation transcript.
const LOG_CAP := 8

var log_box: VBoxContainer
var suggestions_box: VBoxContainer
var free_text: LineEdit

var _log_scroll: ScrollContainer
var _suggestion_buttons: Array = []
## The hovered country's card, overlaying the left column.
var _country_panel: CountryPanel
## The clicked map element's fact card, in the left column.
var _detail: MapDetailPanel
## The realm's host, in the left column while the MILITARY layer is on.
var _military: MilitaryPanel
## The left column's default content: the realm dashboard.
var _dashboard: RealmDashboard
## Whether the MILITARY tab is lit (GameRoot owns the state; this follows).
var _military_view := false
var _manor_master: ManorMasterPanel
var _manor_view := false
var _map3d: Map3DView
var _map3d_theme := ""
var _map3d_military := false

## Static structure and layout live in scenes/court.tscn (editable in the
## editor); _ready fetches nodes, paints them from UiPalette, and wires
## signals; log lines and suggestion buttons are spawned at runtime below.
## The TopBar instance wires itself to Game's signals.
func _ready() -> void:
	%Bg.color = UiPalette.BG_SCREEN
	%MapPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 4))
	_handle = ScreenLayout.make_handle("ENTER THE COUNCIL")
	_handle.pressed.connect(enter_council)
	add_child(_handle)
	%LeaveButton.add_theme_font_size_override("font_size", 14)
	%LeaveButton.pressed.connect(leave_council)
	# Hovering a country swaps the left column to its card and back again
	# (user request 2026-09-09); the column's own content returns when it leaves.
	_country_panel = CountryPanel.attach(%LogPanel.get_node("LVBox"))
	# The left column's own content: the realm at a glance (user ruling 2026-09-09).
	_dashboard = RealmDashboard.attach(%LogPanel.get_node("LVBox"))
	# The rest of the facts column: the host while the military layer is on,
	# and the card of whatever was clicked on the map (owner ruling 2026-09-10).
	_military = MilitaryPanel.attach(%LogPanel.get_node("LVBox"))
	# The Manor Master (MANOR_SYSTEM.md §6): the manors table while the
	# MANORS layer is lit. A row centres and rings the manor; activating it
	# opens the card, which then takes the column until it closes.
	_manor_master = ManorMasterPanel.attach(%LogPanel.get_node("LVBox"))
	_manor_master.manor_chosen.connect(func(cell: int) -> void:
		_map3d.look_at_pack(MapTerrain.cell_center(Game.data, Game.data.cells[cell])))
	_manor_master.manor_activated.connect(func(cell: int) -> void:
		_detail.show_manor(cell)
		_map3d.select_object({"kind": "manor", "cell": cell}))
	_detail = MapDetailPanel.new()
	_detail.name = "DetailPanel"
	%LogPanel.get_node("LVBox").add_child(_detail)
	_detail.ask_enabled = true
	_detail.ask_requested.connect(_on_place_asked)
	# The world map fills the middle zone (user ruling 2026-09-03) — the 3D
	# map, the only one since 2026-09-24; a click opens its fact card in the
	# left column (user ruling 2026-09-09), whose Ask drops the question into
	# the order box and the player still presses Enter (spec 2026-09-08).
	_map3d = Map3DView.attach(%MapPanel, _detail, _country_panel, _refresh_left, %ArmyOrders)
	_detail.visibility_changed.connect(_refresh_left)
	# The host opens from a regiment's card and closes back (owner 2026-09-27:
	# the MILITARY tab is gone; the regiments are always on the map).
	_detail.host_requested.connect(func() -> void:
		_detail.show_card({})
		set_military_view(true))
	_military.closed.connect(func() -> void: set_military_view(false))
	%LogPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 24))
	%SidePanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 24))
	UiPalette.style_header(%LogHeader, 14)
	UiPalette.style_header(%SideHeader, 14)
	_log_scroll = %LogScroll
	log_box = %LogBox
	suggestions_box = %SuggestionsBox
	free_text = %FreeText
	free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	free_text.text_submitted.connect(_on_free_text_submitted)
	_set_right("")
	_refresh_left()

## What holds the right slot: "" (nothing) or "council". The detail card
## lives in the left column, so it never competes for this (owner ruling
## 2026-09-10).
var _right := ""
var _handle: Button

func _set_right(mode: String) -> void:
	_right = mode
	%SidePanel.visible = mode == "council"
	_handle.visible = mode == ""
	_layout()

## Who holds the left column, highest claim first: the card of a clicked
## object, the country under the cursor, the host while the military layer
## is on, then the realm dashboard. A deliberate click outranks a hover, so
## moving the mouse never takes the card away.
func _refresh_left() -> void:
	if _detail == null:
		return
	var card := _detail.has_content()
	var country := not card and _country_panel.has_content()
	_detail.visible = card
	_country_panel.visible = country
	_military.visible = _military_view and not card and not country
	_manor_master.visible = _manor_view and not _military_view and not card and not country
	_dashboard.visible = not (card or country or _military_view or _manor_view)

## The host in the left column (owner 2026-09-27: opened from a regiment's
## card, closed by its own ×; the regiments are always on the map).
func set_military_view(on: bool) -> void:
	_military_view = on
	if on:
		_military.refresh()
	_refresh_left()

## The MANORS tab (GameRoot): the Manor Master takes the left column while
## the manors are coloured by house on the map (MANOR_SYSTEM.md §6).
func set_manor_view(on: bool) -> void:
	_manor_view = on
	if on:
		_manor_master.refresh()
	_refresh_left()

## The map shown or put away (GameRoot): it loads the built world the first
## time it is shown, and shows the notice naming build_pack.sh without one.
func set_map3d_view(on: bool) -> void:
	if on:
		_map3d.activate()
		_map3d.set_manor_theme(_map3d_theme)
		_map3d.set_military(_map3d_military)
	else:
		_map3d.deactivate()

## The theme on the 3D ground ("", "manors" or "heights"; ECONOMY was folded
## into MANORS, owner 2026-09-19; HEIGHTS joined it the same day, spec
## 2026-09-19-map3d-heights) and the MILITARY counters (GameRoot); kept for a
## view made later.
func set_map3d_theme(theme_name: String, military := false) -> void:
	_map3d_theme = theme_name
	_map3d_military = military
	if _map3d != null:
		_map3d.set_manor_theme(theme_name)
		_map3d.set_military(military)

## Test seam: the 3D view, or null until the tab was first lit.
func map3d_view() -> Map3DView:
	return _map3d

func manor_master() -> ManorMasterPanel:
	return _manor_master

func manor_view() -> bool:
	return _manor_view

## Columns, map, and whichever panel holds the right slot (ScreenLayout).
func _layout() -> void:
	var top: float = %TopBar.bar_height() + 3.0
	ScreenLayout.apply(top, %LogPanel, %MapPanel, [%SidePanel], _right != "")
	ScreenLayout.place_handle(_handle, top)

func enter_council() -> void:
	_set_right("council")

func leave_council() -> void:
	if _right == "council":
		_set_right("")

func council_open() -> bool:
	return _right == "council"

func council_handle() -> Button:
	return _handle

## Test seam.

func detail_panel() -> MapDetailPanel:
	return _detail

func military_panel() -> MilitaryPanel:
	return _military

func dashboard() -> RealmDashboard:
	return _dashboard

## Post-conversation court entry (R2): numbers + orders only, speech already
## happened on the conversation stage. Called by GameRoot after the
## conversation scene finishes (see game_root.gd's _on_conversation_finished),
## and with null after loading a save (no report survives a save: the court
## reconvenes without suggestions until the next tick).
func enter_court(report: TickReport) -> void:
	if report == null:
		for child in suggestions_box.get_children():
			child.queue_free()
		_suggestion_buttons = []
		_log("Herald", "The court reconvenes.")
		return
	_render_suggestions(report)

func top_bar() -> TopBar:
	return %TopBar

func suggestion_buttons() -> Array:
	return _suggestion_buttons

## Natural-language suggestion buttons (R8): the pitch template IS the
## label - traits are passed as [] so labels stay generic (court has no
## on-screen speaker left to tint them for; that nuance lives on the
## conversation stage's pitch beats instead). {tradeoff} is stripped from
## the label itself (passed empty + strip_edges) since the tooltip already
## carries the tradeoff text in full.
func _render_suggestions(report: TickReport) -> void:
	for child in suggestions_box.get_children():
		child.queue_free()
	_suggestion_buttons = []
	for i in report.suggestions.size():
		var sug: Dictionary = report.suggestions[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		# Mock-style lettered response ("A. Raise the levies"), left-aligned.
		b.text = "%s.  %s" % [char(65 + i), TemplateVoicer.line_for(Game.data,
			"pitch_" + String(sug["pitch_key"]), [],
			Game.state.tick, {"tradeoff": ""}).strip_edges()]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.tooltip_text = String(sug["tradeoff"])
		b.pressed.connect(_on_suggestion.bind(sug, b))
		# Suggestions surface in sequence, not all at once (user ruling
		# 2026-08-30); hidden buttons still answer pressed() in tests.
		# weakref: freed buttons must not leave dangling lambda captures.
		b.visible = false
		var ref: WeakRef = weakref(b)
		get_tree().create_timer(0.3 * i).timeout.connect(func() -> void:
			var btn: Button = ref.get_ref()
			if btn != null:
				btn.visible = true)
		suggestions_box.add_child(b)
		_suggestion_buttons.append(b)

func _on_suggestion(sug: Dictionary, btn: Button) -> void:
	var result: Dictionary = Game.try_execute(sug["request"])
	if not result["ok"]:
		_log("Herald", result["error"])
		return
	var line: String = TemplateVoicer.line_for(Game.data,
		"outcome_" + String(sug["request"].action_code), [], Game.state.tick)
	_log("Herald", line + _promise_kept_suffix(result["outcome"]["effects"]))
	btn.disabled = true  # only this button - the rest are still valid orders

func _on_free_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	free_text.editable = false
	_log("You", text)
	Game.submit_free_text(text, func(res: Dictionary):
		# The order box always re-enables once the order is answered.
		free_text.editable = true
		free_text.clear()
		if not res["ok"]:
			_log("Herald", "The council cannot: " + String(res["error"]))
		else:
			for outcome in res["executed"]:
				if String(outcome["action_code"]) == "EVENT_CHOICE":
					_log("Herald", String(outcome["notes"]))
					continue
				# The in-character reply IS the consult's voice — skip its
				# canned outcome template.
				if res.has("reply") and String(outcome["action_code"]) == "COUNCIL_CONSULT":
					continue
				var line: String = TemplateVoicer.line_for(Game.data,
					"outcome_" + String(outcome["action_code"]), [], Game.state.tick)
				_log("Herald", line + _promise_kept_suffix(outcome["effects"]))
			for rej in res["rejected"]:
				_log("Herald", "The council cannot: " + String(rej["error"]))
			# The speaker's narrative, then the ledger lines that actually
			# applied (spec 2026-09-09 §4.2): what the court said and what the
			# record shows sit together, so an overreaching narrative is
			# visible as such.
			if res.has("reply"):
				_log(String(res["reply"]["speaker"]), String(res["reply"]["text"]))
			for line in res.get("ledger", []):
				_log("Ledger", String(line)))

## Ask on a card pre-fills the order box and brings the council up so the
## player can send it.
func _on_place_asked(text: String) -> void:
	_map3d.clear_selection()
	_set_right("council")
	free_text.text = text
	free_text.caret_column = text.length()
	free_text.grab_focus()

## Ported from conversation_scene.gd: a kept promise rides along as a
## pseudo-effect on the outcome (metric == "promise" - see
## ActionSystem.execute's promise loop), with no template lookup of its own;
## its reason string IS the line ("a promise kept: <label>"), so it's
## appended verbatim rather than routed through TemplateVoicer.line_for.
func _promise_kept_suffix(effects: Array) -> String:
	var suffix := ""
	for e in effects:
		if String(e.get("metric", "")) == "promise":
			suffix += " " + String(e["reason"])
	return suffix

## Plain-Label log line, newest last, capped at LOG_CAP (R10: no portraits,
## no per-speaker frames - just the order/result text).
func _log(speaker: String, text: String) -> void:
	var l := Label.new()
	l.text = "%s: %s" % [speaker, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_child(l)
	while log_box.get_child_count() > LOG_CAP:
		var oldest := log_box.get_child(0)
		log_box.remove_child(oldest)
		oldest.queue_free()
	_scroll_log_to_bottom.call_deferred()

func _scroll_log_to_bottom() -> void:
	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)

## Test seam.
func country_panel() -> CountryPanel:
	return _country_panel
