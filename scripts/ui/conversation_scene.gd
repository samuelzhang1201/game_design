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

var _beats: Array = []
var _index := -1
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
## The name plate's house arms, design px tall.
const PLATE_ARMS_PX := 36.0
var _plate_arms: HeraldicShield
var _name_label: Label
var _text_label: RichTextLabel
var _speech_label: RichTextLabel
var _replies_box: VBoxContainer
var _free_text: LineEdit
var _world_map: WorldMapView
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
## How much the map darkens behind the window: enough to lift the window,
## little enough that the realm still reads beneath it.
const AUDIENCE_DIM := Color(0.0, 0.0, 0.0, 0.35)
## Tall figure art is cut to its upper part — head to waist, CK3's framing —
## rather than showing the whole figure small; these are shares of its height.
const PORTRAIT_TOP := 0.03
const PORTRAIT_HEIGHT := 0.56

## Static structure and layout live in scenes/conversation.tscn (editable in
## the editor); _ready only fetches the nodes, paints them from UiPalette,
## and wires signals. Dynamic content (portraits, trait chips, reply
## buttons) is spawned at runtime below.
func _ready() -> void:
	%Bg.color = UiPalette.BG_SCREEN
	%MapPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 4))
	# The live world map fills the middle zone on every gameplay screen
	# (user ruling 2026-09-03); the audience window draws above it.
	_world_map = WorldMapView.create()
	%MapPanel.add_child(_world_map)
	# A click on the map opens the fact card in the left column, not the
	# floating card (user ruling 2026-09-09); its Ask pre-fills the talk box
	# and never sends (spec 2026-09-08).
	_world_map.use_card = false
	_world_map.place_asked.connect(_fill_talk_box)
	# The council column is hidden until the player enters it (user ruling
	# 2026-09-09): a handle on the right edge opens it, LEAVE closes it.
	_handle = ScreenLayout.make_handle("ENTER THE COUNCIL")
	_handle.pressed.connect(enter_council)
	add_child(_handle)
	%LeaveButton.add_theme_font_size_override("font_size", 14)
	%LeaveButton.pressed.connect(leave_council)
	# %MinisterPanel is the LEFT column — the facts column (owner ruling
	# 2026-09-10). Hovering a country swaps the column to its card and back
	# again (user request 2026-09-09).
	_country_panel = CountryPanel.attach(%MinisterPanel.get_node("MVBox"), _world_map)
	_world_map.country_hovered.connect(func(_code: String) -> void: _refresh_left())
	# The left column shows the realm at a glance by default (user ruling
	# 2026-09-09).
	_dashboard = RealmDashboard.attach(%MinisterPanel.get_node("MVBox"))
	# The rest of the facts column (owner ruling 2026-09-10): the host while
	# the military layer is on, and the card of whatever was clicked.
	_military = MilitaryPanel.attach(%MinisterPanel.get_node("MVBox"))
	_detail = MapDetailPanel.new()
	_detail.name = "DetailPanel"
	%MinisterPanel.get_node("MVBox").add_child(_detail)
	_detail.follow(_world_map)
	_detail.ask_enabled = true
	_detail.ask_requested.connect(_fill_talk_box)
	_detail.closed.connect(_world_map.clear_selection)
	_detail.visibility_changed.connect(_refresh_left)
	%MinisterPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 16))
	_style_audience()
	_show_dossier(false)
	_build_skill_rows()
	_build_dossier_tabs()
	UiPalette.style_header(%ToolsTitle, 14, UiPalette.TEXT_MUTED)
	%TiesText.add_theme_font_size_override("font_size", 16)
	%PopupPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 2, 24))
	UiPalette.style_header(%PopupTitle, 18)
	var popup_dim: ColorRect = %EventPopup.get_node("PopupDim")
	popup_dim.color = UiPalette.DIM_OVERLAY
	_panel = %DialoguePanel
	_panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 20))
	UiPalette.style_header(%RecordTitle, 14, UiPalette.TEXT_MUTED)
	_name_label = %NameLabel
	_scroll = %DialogueScroll
	_text_label = %TextLabel
	_speech_label = %SpeechLabel
	# Owner report 2026-09-13: the 8 px transcript (user request 2026-08-31)
	# was unreadable and drew in the default white. The size and the ink come
	# from the theme (UiPalette.build_theme); set here too so the text reads
	# right even under a screen that was built without that theme.
	for label: RichTextLabel in [_text_label, _speech_label]:
		label.add_theme_font_size_override("normal_font_size", UiPalette.DIALOGUE_FONT_SIZE)
		label.add_theme_font_size_override("bold_font_size", UiPalette.DIALOGUE_FONT_SIZE)
		label.add_theme_font_size_override("italics_font_size", UiPalette.DIALOGUE_FONT_SIZE)
		label.add_theme_color_override("default_color", UiPalette.TEXT_SOFT)
	# The record is the smaller voice now: the window carries the words.
	_text_label.add_theme_font_size_override("normal_font_size", 15)
	_text_label.add_theme_font_size_override("bold_font_size", 15)
	_text_label.add_theme_font_size_override("italics_font_size", 15)
	_replies_box = %RepliesBox
	_free_text = %FreeText
	_free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	_free_text.text_submitted.connect(_on_free_text)
	_continue_btn = %ContinueButton
	_continue_btn.pressed.connect(_on_continue)
	# The talk box keeps a line's worth of room beside the button: at the
	# theme's size the button took half the row and cut the placeholder off.
	UiPalette.compact_button(_continue_btn, 36.0, 15, 14.0)
	_free_text.custom_minimum_size.x = 240.0
	%MoveButton.add_theme_font_size_override("font_size", 16)
	%MoveButton.pressed.connect(_open_move_popup)
	%AudienceLayer.resized.connect(_fit_audience)
	%AudienceLayer.visible = false
	Game.state_changed.connect(func() -> void:
		if is_inside_tree():
			_refresh_location())
	_refresh_location()
	_set_right("")
	_refresh_left()

## The window's chrome: the framed card, the title banner, the portrait's
## gilt frame, the name plate and the speaker's name.
func _style_audience() -> void:
	%AudienceDim.color = AUDIENCE_DIM
	%AudienceWindow.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 20))
	var banner := StyleBoxFlat.new()
	banner.bg_color = UiPalette.INPUT_BG
	banner.border_color = UiPalette.BORDER_GOLD
	banner.border_width_top = 1
	banner.border_width_bottom = 1
	banner.content_margin_top = 4.0
	banner.content_margin_bottom = 4.0
	banner.content_margin_left = 12.0
	banner.content_margin_right = 12.0
	%AudienceBanner.add_theme_stylebox_override("panel", banner)
	UiPalette.style_header(%AudienceTitle, 20)
	var frame := StyleBoxFlat.new()
	frame.bg_color = UiPalette.BG_SCREEN
	frame.border_color = UiPalette.BORDER_GOLD
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(2)
	frame.shadow_color = UiPalette.SHADOW
	frame.shadow_size = 6
	%PortraitFrame.add_theme_stylebox_override("panel", frame)
	UiPalette.style_header(%MinisterName, 20)
	UiPalette.style_header(%MinisterTitle, 13, UiPalette.TEXT_MUTED)
	%OpinionCaption.add_theme_font_size_override("font_size", 13)
	%OpinionCaption.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	%OpinionBar.add_theme_stylebox_override("background", UiPalette.bar_bg())
	%OpinionValue.add_theme_font_size_override("font_size", 16)
	UiPalette.style_header(%NameLabel, 20)
	# The person's house arms beside the name on the plate (owner 2026-09-15).
	var name_label: Label = %MinisterName
	var head := name_label.get_parent()
	var plate := HBoxContainer.new()
	plate.name = "PlateRow"
	plate.add_theme_constant_override("separation", 8)
	head.add_child(plate)
	head.move_child(plate, name_label.get_index())
	plate.owner = self
	_plate_arms = HeraldicShield.new()
	_plate_arms.name = "PlateArms"
	_plate_arms.custom_minimum_size = Vector2(PLATE_ARMS_PX * 0.85, PLATE_ARMS_PX)
	_plate_arms.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_plate_arms.visible = false
	plate.add_child(_plate_arms)
	name_label.reparent(plate)
	name_label.owner = self
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## What holds the right slot: "" (nothing, the map runs to the edge) or
## "council". The fact card lives in the left column, so it never competes
## for this slot (owner ruling 2026-09-10: left = facts, right = people).
var _right := ""
var _handle: Button

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

## The MILITARY tab (GameRoot): the host takes the left column while the
## regiments are drawn on the map.
func set_military_view(on: bool) -> void:
	_military_view = on
	if on:
		_military.refresh()
	_refresh_left()

## The 3D MAP tab (GameRoot): the Terrain3D view takes the map panel in
## place of the 2D map while the tab is lit (Map3DView.toggle_in).
func set_map3d_view(on: bool) -> void:
	_map3d = Map3DView.toggle_in(%MapPanel, _world_map, _map3d, on, _detail, _country_panel,
		_refresh_left)
	if _map3d != null:
		_map3d.set_manor_theme(_map3d_theme)
		_map3d.set_military(_map3d_military)

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
	var top: float = %TopBar.bar_height() + 3.0
	ScreenLayout.apply(top, %MinisterPanel, %MapPanel, [%DialoguePanel], _right != "",
		ScreenLayout.TALK_WIDTH)
	ScreenLayout.place_handle(_handle, top)
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
	_world_map.clear_selection()
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
	_history.append({"speaker": speaker, "line": line, "n": _said})
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
	for e in _history:
		if not allowed.is_empty() and not allowed.has(e["speaker"]):
			continue
		shown.append(e["line"])
		if int(e["n"]) >= _beat_start:
			speech.append(e["line"])
	_text_label.text = "\n".join(shown)
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
		UiPalette.style_tab(btn, 12, 8.0)
		btn.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
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
		_tab_buttons[i].add_theme_color_override("font_color",
			UiPalette.GOLD if i == _tab_index else UiPalette.TEXT_MUTED)
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

func dialogue_text() -> String:
	return _text_label.get_parsed_text()

## Events and the opening narration share the audience window (owner
## 2026-09-15): CK3's events and interactions wear one frame.
func event_popup() -> Control:
	return %AudienceWindow

func audience_window() -> PanelContainer:
	return %AudienceWindow

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
## (chapter 0, 2026-09-21): assets/events/<event_id>.png, installed from the
## art library's V- chapter by install_map_art.py events. An event with no
## art installed simply has no band — the window is complete without it, so
## a fresh checkout is never broken by a missing render.
const EVENT_ART_DIR := "res://assets/events/"

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

func map_panel() -> PanelContainer:
	return %MapPanel

## One row per council skill, mock-style: muted name, a bar in that skill's
## own color (see UiPalette.SKILL_COLORS), the value. Built once; values set
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
			UiPalette.bar_fill(UiPalette.SKILL_COLORS[sk]))
		row.add_child(bar)
		_skill_bars[sk] = bar
		var value_l := Label.new()
		value_l.add_theme_font_size_override("font_size", 18)
		value_l.add_theme_color_override("font_color", UiPalette.SKILL_COLORS[sk])
		row.add_child(value_l)
		_skill_values[sk] = value_l
		%SkillRows.add_child(row)
		# CK3's row of five under the portrait: short name and value in the
		# skill's colour, the full name on hover.
		var badge := Label.new()
		badge.name = "Skill_" + String(sk)
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", UiPalette.SKILL_COLORS[sk])
		var chip := UiPalette.chip_style()
		chip.content_margin_left = 4.0
		chip.content_margin_right = 4.0
		chip.content_margin_top = 2.0
		chip.content_margin_bottom = 2.0
		badge.add_theme_stylebox_override("normal", chip)
		badge.tooltip_text = String(UiPalette.SKILL_NAMES[sk])
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
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
			_add_reply("I am ready. Let the reign begin.", _advance)
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
## OrderCosts' price for the action.
func _option_tooltip(sug: Dictionary) -> String:
	var lines: Array = []
	var tradeoff := String(sug.get("tradeoff", ""))
	if tradeoff != "":
		lines.append(tradeoff)
	var request = sug.get("request")
	if request != null:
		var gold := OrderCosts.gold_of(Game.data, String(request.action_code))
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
	%MinisterTitle.text = String(Game.data.seats[c.seat]["label"]).to_upper() \
		if Game.data.seats.has(c.seat) else String(c.seat).to_upper()
	%OpinionBar.value = c.opinion
	var tone: Color = UiPalette.POSITIVE if c.opinion >= 0 else UiPalette.NEGATIVE
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
		var badge: Label = %SkillBadges.get_node("Skill_" + String(sk))
		badge.text = "%s %d" % [UiPalette.SKILL_SHORT[sk], value]
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
func world_map() -> WorldMapView:
	return _world_map
