class_name CourtScreen
extends Control
## Court screen (Task 6, replaces CouncilScreen): the trimmed order screen.
## All minister speech, briefing, and event resolution now happen on the
## conversation stage (Task 5) before GameRoot ever switches here — this
## screen is numbers + orders only (spec R2). Layout (user rulings
## 2026-09-09, ScreenLayout): the realm's own information in the LEFT
## column, the BRIGHT map in the middle, and a RIGHT slot that is empty by
## default — the council column (the court record, the order box, the
## lettered suggestions, End Turn — R8/R10) opens from the ENTER THE
## COUNCIL handle on the right edge.
##
## The columns divide by kind (owner ruling 2026-09-10): the LEFT column
## holds FACTS — the realm dashboard, the hovered country, the host while
## the military layer is on, and the card of whatever the player clicks on
## the map — and the RIGHT slot holds PEOPLE AND TALK, the council. So a
## map click never displaces the council, and _refresh_left decides which
## of the four holds the left column.

## Emitted instead of self-driving the turn cycle: GameRoot owns advancing
## the tick and playing the DAY_RUN interlude. See enter_court.
signal end_turn_requested

## Log cap (R10-adjacent polish, ported from the old council screen's transcript):
## keeps the court log short since it only ever holds order results, not a
## full conversation transcript.
const LOG_CAP := 8

var log_box: VBoxContainer
var suggestions_box: VBoxContainer
var free_text: LineEdit
var end_turn: Button

var _log_scroll: ScrollContainer
var _suggestion_buttons: Array = []
var _world_map: WorldMapView
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
var _economy: EconomyPanel
var _economy_view := false

## Static structure and layout live in scenes/court.tscn (editable in the
## editor); _ready fetches nodes, paints them from UiPalette, and wires
## signals; log lines and suggestion buttons are spawned at runtime below.
## The TopBar instance wires itself to Game's signals.
func _ready() -> void:
	%Bg.color = UiPalette.BG_SCREEN
	%MapPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 4))
	# The live world map fills the middle zone (user ruling 2026-09-03).
	_world_map = WorldMapView.create()
	%MapPanel.add_child(_world_map)
	# A click on the map opens the fact card in the left column, not the
	# floating card (user ruling 2026-09-09); its Ask drops the question into the
	# order box and the player still presses Enter, so no order or API call
	# happens without them (spec 2026-09-08).
	_world_map.use_card = false
	_world_map.place_asked.connect(_on_place_asked)
	_handle = ScreenLayout.make_handle("ENTER THE COUNCIL")
	_handle.pressed.connect(enter_council)
	add_child(_handle)
	%LeaveButton.add_theme_font_size_override("font_size", 14)
	%LeaveButton.pressed.connect(leave_council)
	# Hovering a country swaps the left column to its card and back again
	# (user request 2026-09-09); the column's own content returns when it leaves.
	_country_panel = CountryPanel.attach(%LogPanel.get_node("LVBox"), _world_map)
	_world_map.country_hovered.connect(func(_code: String) -> void: _refresh_left())
	# The left column's own content: the realm at a glance (user ruling 2026-09-09).
	_dashboard = RealmDashboard.attach(%LogPanel.get_node("LVBox"))
	# The rest of the facts column: the host while the military layer is on,
	# and the card of whatever was clicked on the map (owner ruling 2026-09-10).
	_military = MilitaryPanel.attach(%LogPanel.get_node("LVBox"))
	_economy = EconomyPanel.attach(%LogPanel.get_node("LVBox"))
	_detail = MapDetailPanel.new()
	_detail.name = "DetailPanel"
	%LogPanel.get_node("LVBox").add_child(_detail)
	_detail.follow(_world_map)
	_detail.ask_enabled = true
	_detail.ask_requested.connect(_on_place_asked)
	_detail.closed.connect(_world_map.clear_selection)
	_detail.visibility_changed.connect(_refresh_left)
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
	end_turn = %EndTurn
	end_turn.pressed.connect(_on_end_turn)
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
	# The economy column yields to the military one: two layers can be lit at
	# once, but the column holds one set of facts.
	_economy.visible = _economy_view and not _military_view and not card and not country
	_dashboard.visible = not (card or country or _military_view or _economy_view)

## The MILITARY tab (GameRoot): the host takes the left column while the
## regiments are drawn on the map.
func set_military_view(on: bool) -> void:
	_military_view = on
	if on:
		_military.refresh()
	_refresh_left()

## The ECONOMY tab (GameRoot): what the realm makes takes the left column
## while the same categories are washed across the map.
func set_economy_view(on: bool) -> void:
	_economy_view = on
	if on:
		_economy.refresh()
	_refresh_left()

## Test seam.
func economy_panel() -> EconomyPanel:
	return _economy

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
func world_map() -> WorldMapView:
	return _world_map

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

## Enter ends the turn (when the order box isn't focused - a focused LineEdit
## consumes Enter itself, so this only fires from unhandled input).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not end_turn.disabled \
			and Game.state.pending_event.is_empty():
		_on_end_turn()

func suggestion_buttons() -> Array:
	return _suggestion_buttons

func end_turn_button() -> Button:
	return end_turn

## End Turn does not advance the engine itself - GameRoot owns the tick
## advance and the DAY_RUN interlude; this screen just signals that the
## player is done for the fortnight. Gated on pending_event so a player
## cannot skip past an event still awaiting a decision.
func _on_end_turn() -> void:
	if not Game.state.pending_event.is_empty():
		return
	end_turn.disabled = true
	end_turn_requested.emit()

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
		b.focus_mode = Control.FOCUS_NONE  # Enter is reserved for End Turn
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
	end_turn.disabled = true
	_log("You", text)
	Game.submit_free_text(text, func(res: Dictionary):
		# free_text itself always re-enables; End Turn only when no event is
		# pending - a free-text NORMAL action must not let the player skip
		# past an event that's still awaiting a choice (controller ruling,
		# ported from the old council screen). If this free text WAS the
		# EVENT_CHOICE that resolved the event, pending_event is already
		# clear by the time this callback runs, so End Turn re-enables
		# correctly too.
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
				_log("Ledger", String(line))
		if Game.state.pending_event.is_empty():
			end_turn.disabled = false)

## Ask on a card pre-fills the order box and brings the council up so the
## player can send it.
func _on_place_asked(text: String) -> void:
	_world_map.clear_selection()
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
