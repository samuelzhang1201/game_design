class_name ConversationScene
extends Control
## VN stage (R3/R4/R5). Layout (user rulings 2026-09-09, ScreenLayout): the
## LEFT column is FACTS — the realm dashboard, the hovered country, the host,
## a clicked map element's card; the MAP fills the middle; the RIGHT slot is
## empty by default and the council column (where you stand, who is present,
## MOVE, and the full record of what was said) opens from the ENTER THE
## COUNCIL handle on the right edge.
##
## The AUDIENCE WINDOW (owner 2026-09-15, after Crusader Kings III) stands
## centred over the map while a beat holds the stage: the person on the left
## before the room they are met in — portrait, name plate, opinion with its
## reasons on hover, traits, skills — and on the right their words, this
## beat's exchange, the options and the talk box. Events and the opening
## narration use the same window. It replaces the dossier standing over the
## talk in the right column (owner ruling 2026-09-10).
## Beats advance on Continue / reply / choice.

signal finished
## A councillor's miniature by the seal was clicked while they bring an event
## (owner 2026-10-02): GameRoot opens it in an audience with them.
signal audience_requested(id: String)

var _beats: Array = []
var _index := -1
## The opening narration's two speakers (owner 2026-10-12): Lord Malvern's bust
## in the window's upper left, the player's in the upper right, the speaking
## side lit and the other dimmed. Both are boxes the editor places in the scene
## (a Control each, custom_minimum_size set; _fill_portrait cuts the art to it);
## unset, the pages still read, just without the busts.
@export var narration_left: Control
@export var narration_right: Control
## How much the side that is not speaking is dimmed.
const NARRATION_DIM := Color(0.55, 0.55, 0.55, 1.0)
## Running transcript of the conversation, newest last — each entry
## {"speaker": name, "line": bbcode, "n": serial}. The right column's record
## shows the whole exchange, not just the latest line (user requirement
## 2026-08-30); when the player has singled people out, only lines between
## them and the player are shown (user request 2026-08-31). Reset per
## conversation, capped.
var _history: Array = []
const HISTORY_CAP := 60
## Serial of the next line said, and of the first line of the current beat:
## the audience window shows only this beat's exchange (the record keeps it
## all). Serials, not indices, because the cap drops lines off the front.
var _said := 0
var _beat_start := 0
var _report: TickReport
var _plate_arms: HeraldicShield
var _name_label: Label
var _text_label: RichTextLabel
var _speech_label: RichTextLabel
var _replies_box: VBoxContainer
var _free_text: LineEdit
var _map3d: Map3DView
var _map3d_theme := ""
var _map3d_military := false
## The hovered country's card, overlaying the minister column.
var _country_panel: CountryPanel
## The clicked map element's fact card, in the left column (MapDetailPanel).
var _detail: MapDetailPanel
## The left column's default content.
var _dashboard: RealmDashboard
var _dossier_up := false
## The realm's host, in the left column while the MILITARY layer is on.
var _military: MilitaryPanel
## Whether the MILITARY tab is lit (GameRoot owns the state; this follows).
var _military_view := false
var _continue_btn: Button
var _panel: PanelContainer
var _scroll: ScrollContainer
var _resolved_event := false
var _tab_pages: Array = []
var _tab_buttons: Array = []

## Dossier tabs (user ruling 2026-08-30): tabbed info about whoever you're
## talking with. In the audience window they sit beside the speaker's name
## and a page takes the speech's place while it is open.
const TAB_NAMES := ["BIO", "SKILLS", "TIES"]
## Seconds between reply buttons appearing (user ruling 2026-08-30: orders
## and suggestions surface in sequence, not all at once).
const REPLY_REVEAL_STEP := 0.3
## The audience window's largest size, in design px; a narrower map gets a
## window that fits it less AUDIENCE_MARGIN on every side.
const AUDIENCE_MAX := Vector2(780.0, 520.0)
const AUDIENCE_MARGIN := 16.0
## Tall figure art is cut to its upper part — head to waist, CK3's framing —
## rather than showing the whole figure small; these are shares of its height.
const PORTRAIT_TOP := 0.03
const PORTRAIT_HEIGHT := 0.56

## The screen's look lives in scenes/screens/conversation.tscn and is edited in the
## editor (owner 2026-10-02): THE WAR TABLE's oak, sheet, report and seal
## as on the court, the audience window's leather, banner, gilt portrait
## frame and name plate, the label kinds, the council column. _ready fetches
## the nodes and wires signals; dynamic content (portraits, trait chips,
## reply buttons) is spawned at runtime below. Under balance ui_war_table 0
## it puts the 2026-09-28 leather on instead (_dress_leather).
func _ready() -> void:
	# The council column is hidden until the player enters it (user ruling
	# 2026-09-09): the seal opens it, LEAVE closes it.
	if UiPalette.war_table():
		_handle = %CouncilHandle
		var seal := _handle as WaxSeal
		seal.council_requested.connect(enter_council)
		seal.councillor_chosen.connect(func(id: String) -> void:
			if Game.state != null and id == ConversationBeats.event_presenter(Game.state, Game.data):
				audience_requested.emit(id)
			else:
				seek(id))
	else:
		_dress_leather()
		_handle.pressed.connect(enter_council)
	%LeaveButton.pressed.connect(leave_council)
	# %MinisterPanel is the LEFT column — the facts column (owner ruling
	# 2026-09-10). Hovering a country swaps the column to its card and back
	# again (user request 2026-09-09).
	_country_panel = CountryPanel.attach(%MinisterPanel.get_node("MVBox"))
	# The left column shows the realm at a glance by default (user ruling
	# 2026-09-09).
	_dashboard = RealmDashboard.attach(%MinisterPanel.get_node("MVBox"))
	# The rest of the facts column (owner ruling 2026-09-10): the host while
	# the military layer is on, and the card of whatever was clicked.
	_military = MilitaryPanel.attach(%MinisterPanel.get_node("MVBox"))
	_detail = MapDetailPanel.create()
	_detail.name = "DetailPanel"
	%MinisterPanel.get_node("MVBox").add_child(_detail)
	_detail.ask_enabled = true
	_detail.ask_requested.connect(_fill_talk_box)
	# The world map fills the middle zone on every gameplay screen (user
	# ruling 2026-09-03) — the 3D map, the only one since 2026-09-24 — and the
	# audience window draws above it; a click opens the fact card in the left
	# column (user ruling 2026-09-09), whose Ask pre-fills the talk box and
	# never sends (spec 2026-09-08).
	_map3d = Map3DView.attach(%MapPanel, _detail, _country_panel, _refresh_left, %ArmyOrders,
		TitleRealm.take_handed())  # the title's live map, as the reign begins
	%SpyOrders.follow(_map3d, %ArmyOrders)
	_detail.visibility_changed.connect(_refresh_left)
	# The host opens from a regiment's card and closes back (owner 2026-09-27:
	# the MILITARY tab is gone; the regiments are always on the map).
	_detail.host_requested.connect(func() -> void:
		_detail.show_card({})
		set_military_view(true))
	_military.closed.connect(func() -> void: set_military_view(false))
	if UiPalette.war_table():
		# the report writes in paper ink and is drawn only as tall as the
		# realm's card (the compass is the map's own, at its top-left)
		WarTable.ink_column(%MinisterPanel)
		WarTable.fit_report(%MinisterPanel, _dashboard)
	_plate_arms = %PlateArms
	_show_dossier(false)
	_build_skill_rows()
	_build_dossier_tabs()
	_panel = %DialoguePanel
	_name_label = %NameLabel
	_scroll = %DialogueScroll
	_text_label = %TextLabel
	_speech_label = %SpeechLabel
	_replies_box = %RepliesBox
	_free_text = %FreeText
	_free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	_free_text.text_submitted.connect(_on_free_text)
	_continue_btn = %ContinueButton
	_continue_btn.pressed.connect(_on_continue)
	%MoveButton.pressed.connect(_open_move_popup)
	%AudienceLayer.resized.connect(_fit_audience)
	%AudienceLayer.visible = false
	%AudienceLayer.visibility_changed.connect(_render_history)
	Game.state_changed.connect(func() -> void:
		if is_inside_tree():
			_refresh_location())
	_refresh_location()
	_map_right = %MapPanel.offset_right
	_set_right("")
	_refresh_left()

## The leather chrome (balance ui_war_table 0): no table, no seal;
## the map and the facts column in the 2026-09-28 dark leather, and ENTER THE
## COUNCIL the screen's primary button. The audience window, the popup and
## the council column are leather either way (scenes/screens/conversation.tscn).
func _dress_leather() -> void:
	_leather = true
	%Bg.color = UiPalette.BG_SCREEN
	%Bg.z_index = 0
	%Table.queue_free()
	%CouncilHandle.queue_free()
	%MapPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 4, "map"))
	%MinisterPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 16, "column"))
	%MinisterPanel.theme = null
	%MinisterPanel.remove_meta("paper_ground")
	_handle = ScreenLayout.make_handle("ENTER THE COUNCIL")
	add_child(_handle)

## What holds the right slot: "" (nothing, the map runs to the edge) or
## "council". The fact card lives in the left column, so it never competes
## for this slot (owner ruling 2026-09-10: left = facts, right = people).
var _right := ""
var _handle: Button
## The table between the map and the council column while it is open, design
## px — the scene's (owner 2026-10-02: the layout is edited in the editor).
@export var council_gap := 8.0
## The map's right edge with the council column shut, from the scene.
var _map_right := 0.0
## The 2026-09-28 leather (ui_war_table 0) lays itself out in code.
var _leather := false

func _set_right(mode: String) -> void:
	_right = mode
	%DialoguePanel.visible = mode == "council"
	_handle.visible = mode == ""
	_layout()

## Who holds the left column, highest claim first: the card of a clicked
## object, the country under the cursor, the host while the military layer
## is on, then the realm dashboard. A person is never among them: they stand
## in the audience window, with their words.
func _refresh_left() -> void:
	if _detail == null:
		return
	var card := _detail.has_content()
	var country := not card and _country_panel.has_content()
	_detail.visible = card
	_country_panel.visible = country
	_military.visible = _military_view and not card and not country
	_dashboard.visible = not (card or country or _military_view)

## The host in the left column (owner 2026-09-27: opened from a regiment's
## card, closed by its own ×; the regiments are always on the map).
func set_military_view(on: bool) -> void:
	_military_view = on
	if on:
		_military.refresh()
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

## Columns, map, and whichever panel holds the right slot (ScreenLayout). The
## council column is narrower here than on the court (TALK_WIDTH): the talk
## itself moved into the audience window, so the map — and the window over
## it — gets the room back. The audience layer lies exactly over the map.
func _layout() -> void:
	if _leather:
		var top: float = %TopBar.bar_height() + 3.0
		ScreenLayout.apply(top, %MinisterPanel, %MapPanel, [%DialoguePanel], _right != "",
			ScreenLayout.TALK_WIDTH)
		ScreenLayout.place_handle(_handle, top)
	else:
		# where the scene puts them (owner 2026-10-02), the map's right edge
		# brought in while the council is open
		ScreenLayout.open_right(%MapPanel, _map_right, %DialoguePanel, council_gap, _right != "")
	# the audience window lies exactly over the map, wherever it is
	var map: Control = %MapPanel
	var layer: Control = %AudienceLayer
	layer.anchor_left = map.anchor_left
	layer.anchor_top = map.anchor_top
	layer.anchor_right = map.anchor_right
	layer.anchor_bottom = map.anchor_bottom
	layer.offset_left = map.offset_left
	layer.offset_top = map.offset_top
	layer.offset_right = map.offset_right
	layer.offset_bottom = map.offset_bottom
	_fit_audience()

## The window takes AUDIENCE_MAX, or what the map leaves it when the map is
## narrower (the council column open, a small window).
func _fit_audience() -> void:
	var room: Vector2 = %AudienceLayer.size - Vector2.ONE * AUDIENCE_MARGIN * 2.0
	if room.x <= 0.0 or room.y <= 0.0:
		return
	%AudienceWindow.custom_minimum_size = Vector2(
		minf(AUDIENCE_MAX.x, room.x), minf(AUDIENCE_MAX.y, room.y))

func enter_council() -> void:
	_set_right("council")

func leave_council() -> void:
	if _right == "council":
		_set_right("")

func council_open() -> bool:
	return _right == "council"

func council_handle() -> Button:
	return _handle

## Ask on a card pre-fills the talk box and brings the council up so the
## player can send it.
func _fill_talk_box(text: String) -> void:
	_map3d.clear_selection()
	_set_right("council")
	_free_text.text = text
	_free_text.caret_column = text.length()
	_free_text.grab_focus()

## `report` is the TickReport the beats were built from - kept so the summary
## beat can compose its text at display time (see ConversationBeats.summary_text)
## rather than baking it in at build time, since a quick-reply/free-text order
## taken earlier in THIS conversation can change what "resolved this session"
## means by the time the player reaches the summary (FIX 2, post-Task-5 review).
func start(beats: Array, report: TickReport) -> void:
	_beats = beats
	_report = report
	_index = -1
	_history = []
	_said = 0
	_beat_start = 0
	# A council the game opens by itself (the reign's first, the summary
	# beats) hears its ministers as surely as one entered through the seal,
	# so the seal stops marking them as waiting.
	if Game.state != null:
		var spoke: Array = []
		for b: Dictionary in beats:
			if String(b.get("kind", "")) == "minister":
				spoke.append(String(b.get("portrait_id", "")))
		if not spoke.is_empty():
			WaxSeal.hear(Game.state.tick, spoke)
	_advance()

## Appends one line to the transcript and re-renders it, scrolled to the
## newest line. Every piece of dialogue routes through here. Speaker names
## render in per-speaker colors (user ruling 2026-08-30).
func _say(speaker: String, text: String) -> void:
	if text.strip_edges() == "":
		return
	var escaped := text.replace("[", "[lb]")
	var line := "[i]%s[/i]" % escaped if speaker == "" else \
		"[color=#%s]%s:[/color] %s" % [
			_speaker_color(speaker).to_html(false), speaker, escaped]
	_history.append({"speaker": speaker, "line": line, "n": _said,
		"plain": escaped if speaker != "" else ""})
	_said += 1
	while _history.size() > HISTORY_CAP:
		_history.pop_front()
	_render_history()

## Renders the record and the window's speech. With people singled out, both
## show only the conversation between the player and them (user request
## 2026-08-31) — other speakers, herald notes and narration step aside until
## the selection is cleared. The speech keeps to this beat's lines.
func _render_history() -> void:
	var allowed := {}
	if not _selected_ids.is_empty():
		# The Herald stays: he narrates the outcome of orders the player just
		# typed — hiding him would swallow the response to your own words
		# (the exact bug class fixed 2026-08-30).
		allowed = {"You": true, "Herald": true, "Ledger": true}
		for id in _selected_ids:
			if Game.state != null and Game.state.characters.has(id):
				allowed[Game.state.characters[id].display_name] = true
	var shown: Array = []
	var speech: Array = []
	# The record holds what has PASSED (owner 2026-09-28, second critique: it
	# repeated in full the line the window was showing): while the audience
	# window is up, this beat's lines are the window's, and they join the
	# record when the next beat takes the stage.
	var window_up: bool = %AudienceLayer.visible
	for e in _history:
		if not allowed.is_empty() and not allowed.has(e["speaker"]):
			continue
		if not (window_up and int(e["n"]) >= _beat_start):
			shown.append(e["line"])
		if int(e["n"]) >= _beat_start:
			# The window already names who speaks (the plate, or the event's
			# heading): the speech does not say it again (owner 2026-09-28).
			var plain := String(e.get("plain", ""))
			speech.append(plain if plain != "" and _names_shown().has(String(e["speaker"])) else e["line"])
	# An empty record says why, in the game's voice (the first beat is still
	# on the stage).
	_text_label.text = "\n".join(shown) if not shown.is_empty() else \
		"[i][color=#%s]Nothing is set down yet; what is said here is written when it has passed.[/color][/i]" % \
		UiPalette.TEXT_DIM.to_html(false)
	_speech_label.text = "\n\n".join(speech)
	_scroll.set_deferred("scroll_vertical", 1000000)
	# The record keeps growing and reads from its newest line. The audience
	# window does too — EXCEPT while an event or the opening narration is on
	# stage: that is ONE block of authored prose, and it is read from its
	# first word, not from its last. The scene arrives deferred through the
	# voicer, so this has to be decided here rather than at the end of
	# _render_beat, which has already run by the time the words land.
	var kind := String(current_beat().get("kind", ""))
	%SpeechScroll.set_deferred("scroll_vertical",
		0 if kind in ["event", "narration"] else 1000000)

## Deterministic per-speaker name color: fixed for You/Herald, hashed into a
## small palette for everyone else so each courtier keeps one color.
## Picked to read on the dark panel (owner 2026-09-15); the bright theme's
## were 2f8a3e c43c3c 6d42c8 2468c0 b86e0e 11806f b3367f.
const SPEAKER_PALETTE := [Color("7fcf6e"), Color("ec6f5e"), Color("a383ee"),
	Color("5aa2ec"), Color("e6a04a"), Color("4cc3b0"), Color("e07bb5")]

static func _speaker_color(speaker: String) -> Color:
	if speaker == "You":
		return UiPalette.GOLD
	if speaker == "Herald" or speaker == "The Council":
		return UiPalette.TEXT_MUTED
	return SPEAKER_PALETTE[speaker.hash() % SPEAKER_PALETTE.size()]

## Dossier tab strip: BIO | SKILLS | TIES, clicked to swap pages.
func _build_dossier_tabs() -> void:
	_tab_pages = [%BioTab, %SkillsTab, %TiesTab]
	for i in TAB_NAMES.size():
		var btn := Button.new()
		btn.name = "Tab" + TAB_NAMES[i]
		btn.text = TAB_NAMES[i]
		btn.focus_mode = Control.FOCUS_NONE
		# Words with an underline, like the bottom bar's tabs (owner
		# 2026-09-28: a boxed tab inside the window was a frame in a frame).
		btn.toggle_mode = true
		UiPalette.flat_tab(btn, 12, 8.0)
		btn.pressed.connect(_select_tab.bind(i))
		%TabsRow.add_child(btn)
		_tab_buttons.append(btn)
	_refresh_dossier()

## Which page is open, or -1 when they are all closed — the resting state,
## so the speech has the room until the player asks for a page.
var _tab_index := -1

## Pressing a tab opens its page in the speech's place; pressing the open one
## closes it again and hands the room back to the words.
func _select_tab(index: int) -> void:
	_tab_index = -1 if index == _tab_index else index
	for i in _tab_pages.size():
		(_tab_buttons[i] as Button).set_pressed_no_signal(i == _tab_index)
	_refresh_dossier()

func select_tab(index: int) -> void:
	_select_tab(index)

func tab_page(index: int) -> Control:
	return _tab_pages[index]

func current_beat() -> Dictionary:
	return {} if _index < 0 or _index >= _beats.size() else _beats[_index]

func continue_button() -> Button:
	return _continue_btn

func reply_buttons() -> Array:
	# The beat's options and an event's choices live in the audience window;
	# the MOVE list lives in the small centred popup — one seam covers both.
	return _replies_box.get_children() + %PopupChoices.get_children()

## The record as drawn: what has passed, not this beat while the window shows it.
func dialogue_text() -> String:
	return _text_label.get_parsed_text()

## Everything said this council, the record and the window's beat together —
## what a test asks when it means "was it said", wherever it now stands.
func said_text() -> String:
	return _text_label.get_parsed_text() + "\n" + _speech_label.get_parsed_text()

## Events and the opening narration share the audience window (owner
## 2026-09-15): CK3's events and interactions wear one frame.
func event_popup() -> Control:
	return %AudienceWindow

func audience_window() -> PanelContainer:
	return %AudienceWindow

## Whoever the window names over the speech right now.
func _names_shown() -> Array:
	var out: Array = []
	for l: Label in [%MinisterName, _name_label]:
		if l != null and l.is_visible_in_tree() and l.text != "":
			out.append(l.text)
	return out

func speech_scroll() -> ScrollContainer:
	return %SpeechScroll

## This beat's words, as the audience window shows them.
func speech_text() -> String:
	return _speech_label.get_parsed_text()

## --- Location panel (the council column, upper container) --------------
## Where the player stands, who is present (click a face to seek them out),
## and MOVE — free movement within the region (LocationSystem).

## Who the player is addressing (user request 2026-08-31). Empty means the
## whole room: speaking with nobody selected addresses everyone present.
## Clicking a portrait toggles membership; the window follows the most
## recent click. Cleared on a move, since a selection cannot outlive being
## in the same place as the people in it.
var _selected_ids: Array = []

## Tracks where the panel last rendered, so a location change can clear the
## address list wherever the move came from — the move popup, an event, or a
## script. Clearing only in the popup handler would leave stale targets on
## every other path.
var _last_location := ""

func _refresh_location() -> void:
	if Game.state == null:
		return
	if Game.state.current_location != _last_location:
		_last_location = Game.state.current_location
		_selected_ids.clear()
		# The cleared selection widens the transcript back to the whole room
		# and restores the beat's reply options.
		_render_history()
		_update_reply_relevance()
	%Backdrop.location_code = Game.state.current_location
	_refresh_banner()
	# Same rename-then-free dance as _show_speaker: replacements arrive this
	# frame while the outgoing nodes are still pending delete, and a name
	# collision would permanently auto-rename the new nodes.
	for child in %LocationSlot.get_children():
		child.name = "OutgoingLocation"
		child.queue_free()
	%LocationSlot.add_child(LocationView.instantiate_for(Game.state.current_location))
	for child in %OccupantsRow.get_children():
		child.name = "OutgoingOccupant" + str(child.get_index())
		child.queue_free()
	for id in LocationSystem.occupants(Game.data, Game.state, Game.state.current_location):
		var btn := Button.new()
		btn.name = "Occupant_" + String(id)
		# 40px keeps a full council on ONE row of the right column (owner
		# ruling 2026-09-10).
		btn.custom_minimum_size = Vector2(40, 40)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = Game.state.characters[id].display_name
		btn.toggle_mode = true
		btn.button_pressed = String(id) in _selected_ids
		btn.add_theme_stylebox_override("pressed",
			UiPalette.chip_style(UiPalette.CHIP_PRESSED, UiPalette.GOLD))
		btn.pressed.connect(_toggle_target.bind(String(id)))
		var chip := CharacterPortrait.instantiate_for(id, false)
		chip.scale = Vector2(0.38, 0.38)
		chip.position = Vector2(1, 1)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(chip)
		%OccupantsRow.add_child(btn)
	_refresh_target_hint()

## The banner over the window names the scene: the room for a person or the
## council, the event's own title for an event, nothing for the narration.
func _refresh_banner() -> void:
	var b := current_beat()
	var kind := String(b.get("kind", ""))
	var text := ""
	match kind:
		"event":
			# The title is the story document's own heading (StorySource),
			# not a template key: templates.csv deliberately carries no
			# event_<id> row — a scene and its title must not be able to
			# drift from the document the game reads them out of.
			text = String(Game.data.event_titles.get(String(b["event"]["event_id"]), ""))
			if text == "":
				text = TemplateVoicer.line_for(Game.data,
					String(b["event"]["title_key"]), [], Game.state.tick)
		"narration":
			text = ""
		_:
			if Game.state != null:
				text = String(LocationSystem.location(Game.data,
					Game.state.current_location).get("label", ""))
	%AudienceTitle.text = text
	%AudienceBanner.visible = text != ""

## The event's own illustration, across the top of the audience window
## (chapter 0, 2026-09-21): assets/2D/events/illustrations/<event_id>.png, installed from the
## art library's V- chapter by install_map_art.py events. An event with no
## art installed simply has no band — the window is complete without it, so
## a fresh checkout is never broken by a missing render.
const EVENT_ART_DIR := "res://assets/2D/events/illustrations/"

func _show_narration_busts(b: Dictionary) -> void:
	var on := String(b.get("kind", "")) == "narration" and b.has("side")
	for pair: Array in [[narration_left, "left", "left_id"], [narration_right, "right", "right_id"]]:
		var box := pair[0] as Control
		if box == null:
			continue
		box.visible = on
		if on:
			_fill_portrait(box, String(b[pair[2]]))
			box.modulate = Color.WHITE if String(b["side"]) == pair[1] else NARRATION_DIM

func _show_event_art(b: Dictionary) -> void:
	var art: Texture2D = null
	if String(b.get("kind", "")) == "event":
		var path := EVENT_ART_DIR + String(b["event"].get("event_id", "")) + ".png"
		if ResourceLoader.exists(path):
			art = load(path) as Texture2D
	%EventArt.texture = art
	%EventArt.visible = art != null
	# The illustration IS the event's face. With one in the window the
	# round-table portrait beside it is a second picture of the same room and
	# a dossier for a speaker who is "The Council", so it stands down and the
	# prose takes the full width; an event with no render installed keeps it.
	if art != null:
		%PortraitSide.visible = false

## Adds or removes someone from the address list. Selecting nobody means the
## whole room, so deselecting the last target quietly returns to addressing
## everyone. The window follows the click so you still see who you are
## dealing with.
## An audience with `id` (owner 2026-10-02: a click on a councillor's
## miniature by the seal): the player goes to where they are, if it is in
## reach, and the window turns to them alone (`address` false: the player only
## goes to them — an event they bring speaks to the whole room, and a narrowed
## transcript would hide its scene). False when they cannot be met.
func seek(id: String, address := true) -> bool:
	if Game.state == null or not Game.state.characters.has(id):
		return false
	# an event or the opening narration holds the stage until it is answered
	if String(current_beat().get("kind", "")) in ["event", "narration"]:
		return false
	if not id in LocationSystem.occupants(Game.data, Game.state, Game.state.current_location):
		var to := ""
		for code: String in LocationSystem.reachable(Game.data, Game.state):
			if id in LocationSystem.occupants(Game.data, Game.state, code):
				to = code
				break
		if to == "" or not Game.move_to(to):
			return false
	_refresh_location()
	if address:
		_selected_ids.clear()
		_toggle_target(id)
		_refresh_location()
	return true

func _toggle_target(id: String) -> void:
	if id in _selected_ids:
		_selected_ids.erase(id)
	else:
		_selected_ids.append(id)
	if not _selected_ids.is_empty():
		var focus := String(_selected_ids[_selected_ids.size() - 1])
		var c: Character = Game.state.characters[focus]
		_show_speaker({"portrait_id": focus, "speaker": c.display_name})
		_name_label.text = c.display_name
	else:
		var b := current_beat()
		if not b.is_empty():
			_show_speaker(b)
			_name_label.text = String(b.get("speaker", ""))
	_refresh_target_hint()
	_render_history()
	_update_reply_relevance()

## The beat's default reply options belong to the minister who raised them:
## once the player singles out people that do NOT include that minister, the
## options step aside (user request 2026-08-31 — no "Raise the levies" while
## talking to someone else about something else). An empty selection means
## the whole room, minister included, so the options stand.
func _update_reply_relevance() -> void:
	var b := current_beat()
	if String(b.get("kind", "")) != "minister":
		return
	_replies_box.visible = _selected_ids.is_empty() \
		or String(b.get("portrait_id", "")) in _selected_ids

func _on_continue() -> void:
	_advance()

## Everyone the next typed line reaches: the explicit selection, or the whole
## room when nothing is selected. Filtered against who is actually here, so a
## stale id can never be addressed.
func audience() -> Array:
	if Game.state == null:
		return []
	var present := LocationSystem.occupants(
		Game.data, Game.state, Game.state.current_location)
	if _selected_ids.is_empty():
		return present
	var out: Array = []
	for id in _selected_ids:
		if id in present:
			out.append(String(id))
	return out

func selected_ids() -> Array:
	return _selected_ids.duplicate()

## The input box states who it will reach, so the player is never guessing.
func _refresh_target_hint() -> void:
	var who := audience()
	if _selected_ids.is_empty():
		_free_text.placeholder_text = "Talk to everyone here..."
	elif who.size() == 1:
		_free_text.placeholder_text = "Talk to %s..." % \
			Game.state.characters[who[0]].display_name
	else:
		_free_text.placeholder_text = "Talk to %d people..." % who.size()

func _open_move_popup() -> void:
	%EventPopup.visible = true
	%PopupTitle.visible = true
	%PopupTitle.text = "MOVE — " + String(Game.data.regions.get(
		LocationSystem.region_of(Game.data, Game.state.current_location),
		{}).get("label", ""))
	%PopupText.text = "Movement within the region costs no time."
	for child in %PopupChoices.get_children():
		child.queue_free()
	for code in LocationSystem.reachable(Game.data, Game.state):
		var row := LocationSystem.location(Game.data, code)
		var here: bool = String(code) == Game.state.current_location
		var btn := Button.new()
		btn.name = "Move_" + String(code)
		btn.text = "%s (%d here)%s" % [String(row["label"]),
			LocationSystem.occupants(Game.data, Game.state, code).size(),
			"  — you are here" if here else ""]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = here
		btn.pressed.connect(func() -> void:
			# The address list is cleared by _refresh_location on the location
			# change itself, so every route into move_to is covered.
			Game.move_to(String(code))
			%EventPopup.visible = false
			_say("", "You make your way to %s." % String(row["label"])))
		%PopupChoices.add_child(btn)
	var cancel := Button.new()
	cancel.name = "MoveCancel"
	cancel.text = "Stay"
	UiPalette.command_button(cancel)
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void: %EventPopup.visible = false)
	%PopupChoices.add_child(cancel)

## Test seam: who the dossier is focused on, or "" when it follows the beat.
func focused_id() -> String:
	return String(_selected_ids[_selected_ids.size() - 1]) \
		if not _selected_ids.is_empty() else ""

## True when the beat's speaker stands where the player stands. Non-character
## speakers (the round table, the herald) are location-free.
func _speaker_present(portrait_id: String) -> bool:
	if Game.state == null or not Game.state.characters.has(portrait_id):
		return true
	return portrait_id in LocationSystem.occupants(
		Game.data, Game.state, Game.state.current_location)

func free_text_field() -> LineEdit:
	return _free_text

func dialogue_panel() -> PanelContainer:
	return _panel

func dialogue_scroll() -> ScrollContainer:
	return _scroll

func top_bar() -> TopBar:
	return %TopBar

func minister_panel() -> PanelContainer:
	return %MinisterPanel

## The left column (the FACTS column, invariant 10): the WAR ROOM widens over it.
func left_column() -> PanelContainer:
	return %MinisterPanel

func map_panel() -> PanelContainer:
	return %MapPanel

## One row per council skill, mock-style: muted name, a bar in that skill's
## own color (UiPalette.skill_color), the value. Built once; values set
## per speaker in _show_speaker.
var _skill_bars: Dictionary = {}
var _skill_values: Dictionary = {}

func _build_skill_rows() -> void:
	for sk in CharacterFactory.SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := Label.new()
		name_l.text = String(UiPalette.SKILL_NAMES[sk]).to_upper()
		name_l.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
		name_l.add_theme_font_size_override("font_size", 16)
		name_l.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.max_value = UiPalette.SKILL_MAX
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UiPalette.bar_bg())
		bar.add_theme_stylebox_override("fill",
			UiPalette.bar_fill(UiPalette.skill_color(sk)))
		row.add_child(bar)
		_skill_bars[sk] = bar
		var value_l := Label.new()
		value_l.add_theme_font_size_override("font_size", 18)
		value_l.add_theme_color_override("font_color", UiPalette.skill_color(sk))
		row.add_child(value_l)
		_skill_values[sk] = value_l
		%SkillRows.add_child(row)
		# CK3's row of five under the portrait: short name and value in the
		# skill's colour, the full name on hover.
		# Two lines a badge (owner 2026-09-28, second critique: "ADM 18" in
		# one small run was hard to read on the dark): the short name small
		# over the value large in the book face's tabular figures, the chip
		# edged in the skill's colour.
		var badge := PanelContainer.new()
		badge.name = "Skill_" + String(sk)
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# No box of its own: the colour is the abbreviation's, and a hairline
		# parts one badge from the next.
		var chip := StyleBoxFlat.new()
		chip.bg_color = Color(0, 0, 0, 0)
		chip.content_margin_left = 4.0
		chip.content_margin_right = 4.0
		if CharacterFactory.SKILLS.find(sk) > 0:
			chip.border_color = Color(UiPalette.EDGE, 0.9)
			chip.border_width_left = 1
		badge.add_theme_stylebox_override("panel", chip)
		badge.tooltip_text = String(UiPalette.SKILL_NAMES[sk])
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		var pair := VBoxContainer.new()
		pair.add_theme_constant_override("separation", -3)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(pair)
		var abbr := Label.new()
		abbr.name = "Abbr"
		abbr.text = String(UiPalette.SKILL_SHORT[sk])
		abbr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		abbr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiPalette.style_header(abbr, 11, UiPalette.skill_color(sk).lightened(0.15))
		pair.add_child(abbr)
		var num := Label.new()
		num.name = "Value"
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num.add_theme_font_override("font", UiPalette.figures_font())
		num.add_theme_font_size_override("font_size", 19)
		num.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
		pair.add_child(num)
		%SkillBadges.add_child(badge)

func _advance() -> void:
	_index += 1
	if _index >= _beats.size():
		finished.emit()
		return
	var b := current_beat()
	# Location gating (user ruling 2026-08-30): a minister who is not where
	# the player stands cannot hold this conversation — their beat is skipped
	# with a note (their advice still waits in the court's side panel).
	# Events and narration always show.
	if String(b["kind"]) == "minister" and not _speaker_present(String(b["portrait_id"])):
		_say("", "(You are elsewhere; %s's counsel waits with the council.)" %
			String(b["speaker"]))
		_advance()
		return
	# A new beat opens a new exchange in the window; the record keeps the old.
	_beat_start = _said
	_render_history()
	_show_speaker(b)
	_name_label.text = String(b["speaker"])
	_continue_btn.text = "Wave them on"
	UiPalette.command_button(_continue_btn)
	# Deviation from the brief (pre-approved): the brief's literal `child.free()`
	# here frees while iterating the container's own get_children() snapshot -
	# a crash hazard idiom. queue_free() defers the actual removal to end of
	# frame; the fresh reply buttons added just below this block coexist with
	# the outgoing (pending-delete) ones for at most one frame, which is fine
	# since every test awaits frames before asserting on reply_buttons().
	for child in _replies_box.get_children():
		child.queue_free()
	for child in %PopupChoices.get_children():
		child.queue_free()
	%EventPopup.visible = false
	%AudienceLayer.visible = true
	_next_reply_letter = 0
	_resolved_event = false
	_replies_box.visible = true
	var kind := String(b["kind"])
	# The narration has nobody to stand before you; everything else does.
	%PortraitSide.visible = kind != "narration"
	_show_narration_busts(b)
	_refresh_banner()
	# The move popup is no place to be while an event or narration is on stage
	# (resolve or continue first).
	%MoveButton.disabled = kind in ["event", "narration"]
	_show_event_art(b)
	match kind:
		"event":
			_continue_btn.visible = false
			# The authored scene (RANDOM_EVENTS.md, never the model) arrives
			# through the voicer; the choices are the window's options.
			Game.voice_event_scene(b["event"], func(res: Dictionary):
				# F2 (final-review fix wave): choice buttons render immediately
				# while this call is in flight. With real latency the player can
				# resolve the event (via button or free text) before this
				# callback returns; without this guard the late scene-setting
				# narration would land after the outcome line already shown.
				if _resolved_event:
					return
				_say(String(b["speaker"]), String(res["text"])))
			for ch in b["event"]["choices"]:
				_add_reply(String(ch["label"]),
					_on_event_choice.bind(String(ch["choice_id"])))
		"narration":
			# The nameless opening narration (game background): no speaker, no
			# title, one continue option.
			_continue_btn.visible = false
			_say("", String(b["text"]))
			# one page a topic, a Continue turns it; the last one begins the reign
			var last := int(b.get("page", 1)) >= int(b.get("pages", 1))
			_add_reply("I am ready. Let the reign begin." if last else "Continue", _advance)
		"minister":
			_continue_btn.visible = true
			_say(String(b["speaker"]), String(b["text"]))
			for sug in b["suggestions"]:
				var label := TemplateVoicer.line_for(Game.data,
					"reply_" + String(sug["pitch_key"]), [], Game.state.tick)
				_add_reply(label, _on_quick_reply.bind(sug), _option_tooltip(sug))
		"summary":
			_continue_btn.visible = true
			_say(String(b["speaker"]),
				ConversationBeats.summary_text(_report, Game.state, Game.data))
	_reveal_replies_staggered()
	# A selection surviving from the previous beat still gates whose reply
	# options may show (user request 2026-08-31).
	_update_reply_relevance()
	# F1 (final-review fix wave): event beats must accept free text too - it's
	# the only path back to EVENT_CHOICE via typed orders (Game.submit_free_text's
	# EVENT_CHOICE branch was otherwise unreachable).
	# User request 2026-08-31 ("the prompt input box disappeared"): the box
	# stays available on EVERY beat where people can be spoken to — minister,
	# event and summary alike. Only the opening narration, which has its own
	# continue option and no one to talk to, hides it.
	_free_text.visible = kind != "narration"
	%TalkRow.visible = kind != "narration"
	# The transcript keeps growing; a fresh beat reads from its newest line.
	_scroll.set_deferred("scroll_vertical", 1000000)

## What an option costs and trades, on hover — CK3 shows an option's effects
## before it is taken. The trade-off is the pitch's own words; the gold is
## OrderCosts' price for the action, or for a decree LawSystem.preview's whole
## charge (the order, the law's own gold and one fee a courier).
func _option_tooltip(sug: Dictionary) -> String:
	var lines: Array = []
	var tradeoff := String(sug.get("tradeoff", ""))
	if tradeoff != "":
		lines.append(tradeoff)
	var request = sug.get("request")
	if request != null:
		var gold := OrderCosts.gold_of(Game.data, String(request.action_code))
		if String(request.action_code) == LawSystem.ACTION:
			var pv := LawSystem.preview(Game.data, Game.state, str(request.params.get("law", "")),
				str(request.params.get("value", "")))
			gold = float(int(pv["gold"]) + int(pv["fee"]))
		if gold > 0.0:
			lines.append("Costs %d gold" % int(gold))
	return "\n".join(lines)

## Mock-style lettered responses ("A. Distribute reserves"), left-aligned,
## wrapping inside their column, drawn as CK3 options. Buttons start hidden;
## _reveal_replies_staggered surfaces them one by one.
func _add_reply(label: String, handler: Callable, tooltip: String = "",
		into: Container = null) -> void:
	var btn := Button.new()
	btn.text = "%s.  %s" % [char(65 + _next_reply_letter), label]
	_next_reply_letter += 1
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = tooltip
	UiPalette.option_button(btn)
	btn.visible = false
	btn.pressed.connect(handler)
	(into if into != null else _replies_box).add_child(btn)

## Replies surface in sequence (REPLY_REVEAL_STEP apart), not all at once.
## Buttons stay clickable-by-signal for tests even while hidden; a freed
## button (beat advanced early) is skipped safely.
func _reveal_replies_staggered() -> void:
	var i := 0
	for btn in reply_buttons():
		if not btn.visible:
			# weakref: a freed button (beat advanced early) must not leave a
			# dangling lambda capture behind the pending timer.
			var ref: WeakRef = weakref(btn)
			get_tree().create_timer(REPLY_REVEAL_STEP * i).timeout.connect(
				func() -> void:
					var b: Button = ref.get_ref()
					if b != null:
						b.visible = true)
			i += 1

var _next_reply_letter := 0

## Put `portrait_id`'s art in `box`. Same queue_free() reasoning as _advance:
## the replacement is added immediately, the outgoing node is pending-delete
## for one frame. Rename it first so the incoming node can take the "FullArt"
## name instead of being auto-renamed around the still-pending sibling.
##
## `whole` shows the entire figure (the BIO page); otherwise tall figure art
## is cut head to waist at the box's aspect (the audience window's portrait),
## and wide or square art (the council medallion) is cover-cropped centred.
func _fill_portrait(box: Control, portrait_id: String, whole: bool = false) -> void:
	for child in box.get_children():
		child.name = "OutgoingPortrait"
		child.queue_free()
	var box_size: Vector2 = box.custom_minimum_size
	var full := CharacterPortrait.full_texture_for(portrait_id)
	if full != null:
		var pic := TextureRect.new()
		pic.name = "FullArt"
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		if whole:
			pic.texture = full
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		else:
			var atlas := AtlasTexture.new()
			atlas.atlas = full
			atlas.region = _portrait_region(Vector2(full.get_width(), full.get_height()),
				box_size.x / box_size.y)
			pic.texture = atlas
			pic.stretch_mode = TextureRect.STRETCH_SCALE
		box.add_child(pic)
	else:
		var p := CharacterPortrait.instantiate_for(portrait_id, false)
		var scale_factor := box_size.y / CharacterPortrait.PORTRAIT_SIZE.y
		var side := CharacterPortrait.PORTRAIT_SIZE.x * scale_factor
		p.scale = Vector2(scale_factor, scale_factor)
		p.position = Vector2((box_size.x - side) / 2.0, 0)
		box.add_child(p)

## The part of an image of size `img` shown in a box of aspect `box_aspect`
## (width / height): the upper PORTRAIT_HEIGHT of a figure taller than the box
## is wide, else the centred cover crop.
static func _portrait_region(img: Vector2, box_aspect: float) -> Rect2:
	if img.x / img.y < box_aspect and img.y * PORTRAIT_HEIGHT * box_aspect <= img.x:
		var h := img.y * PORTRAIT_HEIGHT
		var w := h * box_aspect
		return Rect2((img.x - w) / 2.0, img.y * PORTRAIT_TOP, w, h)
	if img.x / img.y > box_aspect:
		var rw := img.y * box_aspect
		return Rect2((img.x - rw) / 2.0, 0, rw, img.y)
	return Rect2(0, 0, img.x, img.x / box_aspect)

## Fills the window's person for this beat's speaker: portrait before the
## room, name plate, seat, opinion (its reasons on hover), trait chips and
## skill badges, and the SKILLS / TIES pages. Non-character beats (round
## table, herald) show the portrait and the speaker's name only.
func _show_speaker(b: Dictionary) -> void:
	var portrait_id := String(b["portrait_id"])
	for chip in %TraitChips.get_children():
		chip.queue_free()
	_fill_portrait(%PortraitBox, portrait_id)
	_fill_portrait(%BioArt, portrait_id, true)
	var c: Character = null
	if Game.state != null and Game.state.characters.has(portrait_id):
		c = Game.state.characters[portrait_id]
	_show_dossier(c != null)
	%MinisterName.text = c.display_name if c != null else String(b.get("speaker", ""))
	var arms := HouseArms.texture_of_house(Game.data, Game.state, c.family_name) if c != null else null
	_plate_arms.set_texture(arms)
	_plate_arms.visible = arms != null
	%MinisterTitle.visible = c != null
	%OpinionRow.visible = c != null
	%SkillRows.visible = c != null
	%ToolsTitle.visible = c != null
	%ToolsList.visible = c != null
	for child in %ToolsList.get_children():
		child.queue_free()
	# TIES tab: who this person loves and hates, live from the graph.
	%TiesText.text = RelationshipGraph.describe_for(Game.state, portrait_id) \
		if c != null and Game.state != null else ""
	if c == null:
		return
	%MinisterTitle.text = String(Game.data.seats[c.seat]["label"]) \
		if Game.data.seats.has(c.seat) else String(c.seat).capitalize()
	%OpinionBar.value = c.opinion
	var tone: Color = UiPalette.good_color() if c.opinion >= 0 else UiPalette.bad_color()
	%OpinionBar.add_theme_stylebox_override("fill", UiPalette.bar_fill(tone))
	%OpinionValue.text = "%+d" % c.opinion
	%OpinionValue.add_theme_color_override("font_color", tone)
	# Readable causality (invariant 4), where CK3 puts it: hover the number
	# and read why.
	var why := CharacterPortrait.opinion_summary(c)
	%OpinionValue.tooltip_text = "Opinion of you: %+d%s" % [c.opinion,
		why if why != "" else "\nNothing has moved it lately."]
	for sk in CharacterFactory.SKILLS:
		var value := int(c.skills.get(sk, 0))
		_skill_bars[sk].value = value
		_skill_values[sk].text = str(value)
		var badge := %SkillBadges.get_node("Skill_" + String(sk)) as Control
		(badge.find_child("Value", true, false) as Label).text = str(value)
	for t in c.traits:
		var row: Dictionary = Game.data.traits.get(t, {})
		var chip := Label.new()
		chip.text = String(row.get("label", t))
		chip.tooltip_text = String(row.get("notes", ""))
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.add_theme_font_size_override("font_size", 14)
		chip.add_theme_color_override("font_color", UiPalette.GOLD)
		var style := UiPalette.chip_style(UiPalette.CHIP_BG, UiPalette.BORDER_GOLD)
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		style.content_margin_top = 2.0
		style.content_margin_bottom = 2.0
		chip.add_theme_stylebox_override("normal", style)
		%TraitChips.add_child(chip)
	# SKILLS tab tools (user request 2026-08-31): the calls this courtier can
	# be asked to make, by their human-readable labels — seat-bound kingdom
	# operations in gold, person-to-person tools in teal (CharacterTools).
	for entry in CharacterTools.kingdom_tools(Game.data, c):
		%ToolsList.add_child(_tool_row(String(entry["label"]), UiPalette.TOOL_KINGDOM))
	for entry in CharacterTools.personal_tools(Game.data, c):
		%ToolsList.add_child(_tool_row(String(entry["label"]), UiPalette.TOOL_PERSONAL))

func _tool_row(label_text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l

func _on_quick_reply(sug: Dictionary) -> void:
	var result: Dictionary = Game.try_execute(sug["request"])
	if not result["ok"]:
		_say("Herald", String(result["error"]))
		return
	for child in _replies_box.get_children():
		child.queue_free()
	_say("Herald", TemplateVoicer.line_for(Game.data,
		"outcome_" + String(sug["request"].action_code), [], Game.state.tick) \
		+ _promise_kept_suffix(result["outcome"]["effects"]))

## Post-Task-5 review "also": a kept promise rides along as a pseudo-effect
## on the outcome (metric == "promise" - see ActionSystem.execute's promise
## loop), with no template lookup of its own; its reason string IS the line
## ("a promise kept: <label>"), so it's appended verbatim rather than routed
## through TemplateVoicer.line_for like the rest of this file's speech.
func _promise_kept_suffix(effects: Array) -> String:
	var suffix := ""
	for e in effects:
		if String(e.get("metric", "")) == "promise":
			suffix += " " + String(e["reason"])
	return suffix

func _on_event_choice(choice_id: String) -> void:
	var out: Dictionary = Game.apply_event_choice(choice_id)
	if out.is_empty():
		return
	_resolve_event(String(out["event_id"]), String(out["choice_id"]))

## Shared by the choice-button path (_on_event_choice) and the free-text path
## (_on_free_text, F1 final-review fix wave) so both resolve an event
## identically: clear the choice buttons, mark resolved (also guards the
## in-flight voice callback - see F2 above), re-enable Continue, and speak
## the same per-choice outcome line.
func _resolve_event(event_id: String, choice_id: String) -> void:
	for child in _replies_box.get_children():
		child.queue_free()
	for child in %PopupChoices.get_children():
		child.queue_free()
	_resolved_event = true
	_continue_btn.visible = true
	# The box stays after resolution (user request 2026-08-31): the player
	# can keep talking to the room before waving the council on.
	%EventPopup.visible = false
	%MoveButton.disabled = false
	_say("Herald", TemplateVoicer.line_for(Game.data,
		"event_%s_%s" % [event_id, choice_id], [], Game.state.tick))

func _on_free_text(text: String) -> void:
	if text.strip_edges() == "":
		return
	_free_text.editable = false
	# The current beat's minister is who the player is facing — conversational
	# text ("who are you") is answered by them unless the parse says the
	# player addressed someone else (see Game._converse_speaker).
	var facing := ""
	var beat := current_beat()
	if String(beat.get("kind", "")) == "minister":
		facing = String(beat.get("portrait_id", ""))
	# An explicit selection overrides the beat's speaker: typed words go to
	# whoever the player picked out of the room.
	var addressed := audience()
	if not _selected_ids.is_empty() and not addressed.is_empty():
		facing = String(addressed[0])
	_say("You", text)
	# Stale-callback bookkeeping: only text aimed at a then-UNRESOLVED event
	# can go stale (a button click resolving it while the parse flies).
	var aimed_at_open_event := String(beat.get("kind", "")) == "event" \
		and not _resolved_event
	Game.submit_free_text(text, func(res: Dictionary):
		_free_text.editable = true
		_free_text.clear()
		# Swallow ONLY the genuinely stale case above. The old blanket
		# `if _resolved_event: return` also ate every conversational reply
		# typed AFTER an event was resolved on this beat (user bug
		# 2026-08-30: greeted Malvern, reply never shown) — chat after
		# resolution must display normally.
		if aimed_at_open_event and _resolved_event:
			return
		if not res["ok"]:
			_say("Herald", "The council doesn't follow. (%s)" % String(res["error"]))
			return
		# F1: a free-text reply that parses to EVENT_CHOICE and actually
		# resolves the pending event must resolve it exactly as the button
		# path does (Game.submit_free_text already ran apply_event_choice -
		# see game.gd's EVENT_CHOICE branch). A parse that rejects (no such
		# choice awaits) or resolves to a normal action instead falls through
		# to the existing spoken-outcome loop below, leaving the event
		# pending and the free-text box visible.
		for outcome in res["executed"]:
			if String(outcome["action_code"]) == "EVENT_CHOICE":
				_resolve_event(String(outcome["event_id"]), String(outcome["choice_id"]))
				return
		var spoken := ""
		for outcome in res["executed"]:
			# The in-character reply IS the consult's voice — skip its
			# canned "leans in and speaks freely" outcome template.
			if res.has("reply") and String(outcome["action_code"]) == "COUNCIL_CONSULT":
				continue
			spoken += TemplateVoicer.line_for(Game.data,
				"outcome_" + String(outcome["action_code"]), [], Game.state.tick)
			spoken += _promise_kept_suffix(outcome["effects"]) + " "
		if spoken != "":
			_say("Herald", spoken)
		# Conversational text ("who are you", "how is my army?") gets the
		# role's in-character LLM reply (converse ride-along), spoken under
		# their own name in the transcript.
		if res.has("reply"):
			_say(String(res["reply"]["speaker"]), String(res["reply"]["text"]))
		# The ledger lines beneath the narrative (spec 2026-09-09 §4.2).
		var ledger: Array = res.get("ledger", [])
		for line in ledger:
			_say("Ledger", String(line))
		if not res.has("reply") and spoken == "" and ledger.is_empty():
			_say("Herald", "So noted.")
	, facing, addressed)

## Test seam.
func country_panel() -> CountryPanel:
	return _country_panel

func detail_panel() -> MapDetailPanel:
	return _detail

func dashboard() -> RealmDashboard:
	return _dashboard

func military_panel() -> MilitaryPanel:
	return _military

func dossier_up() -> bool:
	return _dossier_up

## The name plate, opinion, traits, skills and the tabs stand in the audience
## window while a person holds the stage. Everything else (the round table,
## the herald, narration) has no dossier: the portrait and the name only.
func _show_dossier(up: bool) -> void:
	_dossier_up = up
	_refresh_dossier()

## The head is up whenever a person is; the BIO / SKILLS / TIES pages are
## closed until a tab is pressed, and an open page takes the speech's room
## and gives it straight back — nobody reads a skill table and a speech at
## once.
func _refresh_dossier() -> void:
	%DossierHead.visible = _dossier_up
	%TabsRow.visible = _dossier_up
	var page_open := _dossier_up and _tab_index >= 0
	%DossierPages.visible = page_open
	%SpeechScroll.visible = not page_open
	# A person's name is on the plate under their portrait; the heading over
	# the words names only who has no plate (the council, an event). The
	# narration has no speaker at all.
	%NameLabel.visible = not _dossier_up \
		and String(current_beat().get("kind", "")) != "narration"
	for i in _tab_pages.size():
		_tab_pages[i].visible = _dossier_up and i == _tab_index

## Test seam and GameRoot's handle on this screen's map.
