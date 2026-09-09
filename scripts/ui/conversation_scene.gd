class_name ConversationScene
extends Control
## VN stage (R3/R4/R5). Layout (user rulings 2026-09-09, ScreenLayout): the
## dossier fills the LEFT column (portrait, identity, opinion, per-skill
## colored bars, traits); the MAP fills the middle with the dialogue strip
## under it (where you stand and who is present, the transcript, replies,
## the talk box); a RIGHT detail column exists only while something on the
## map is selected. Beats advance on Continue / reply / choice.

signal finished

var _beats: Array = []
var _index := -1
## Running transcript of the conversation, newest last — each entry
## {"speaker": name, "line": bbcode}. The dialogue box shows the whole
## exchange, not just the latest line (user requirement 2026-08-30); when
## the player has singled people out, only lines between them and the player
## are shown (user request 2026-08-31). Reset per conversation, capped.
var _history: Array = []
const HISTORY_CAP := 60
var _report: TickReport
var _name_label: Label
var _text_label: RichTextLabel
var _replies_box: VBoxContainer
var _free_text: LineEdit
var _world_map: WorldMapView
## The hovered country's card, overlaying the minister column.
var _country_panel: CountryPanel
## The right detail column: the clicked map element (MapDetailPanel).
var _detail: MapDetailPanel
var _continue_btn: Button
var _panel: PanelContainer
var _scroll: ScrollContainer
var _resolved_event := false
var _tab_pages: Array = []
var _tab_buttons: Array = []

## Dossier tabs (user ruling 2026-08-30: the left column is tabbed info about
## whoever you're talking with — no scrolling, separators between sections).
const TAB_NAMES := ["BIO", "SKILLS", "TIES"]
## Seconds between reply buttons appearing (user ruling 2026-08-30: orders
## and suggestions surface in sequence, not all at once).
const REPLY_REVEAL_STEP := 0.3

## Static structure and layout live in scenes/conversation.tscn (editable in
## the editor); _ready only fetches the nodes, paints them from UiPalette,
## and wires signals. Dynamic content (portraits, trait chips, reply
## buttons) is spawned at runtime below.
func _ready() -> void:
	%Bg.color = UiPalette.BG_SCREEN
	%MapPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 2))
	# The live world map fills the middle zone on every gameplay screen
	# (user ruling 2026-09-03); portraits and dialogue draw above it.
	_world_map = WorldMapView.create()
	%MapPanel.add_child(_world_map)
	# A click on the map opens the right detail column, not the floating
	# card (user ruling 2026-09-09); its Ask pre-fills the talk box and
	# never sends (spec 2026-09-08).
	_world_map.use_card = false
	_detail = MapDetailPanel.new()
	_detail.name = "DetailPanel"
	add_child(_detail)
	_detail.follow(_world_map)
	_detail.ask_enabled = true
	_detail.ask_requested.connect(_fill_talk_box)
	_detail.closed.connect(_world_map.clear_selection)
	_detail.visibility_changed.connect(_layout)
	_world_map.place_asked.connect(_fill_talk_box)
	# Hovering a country swaps the left column to its card and back again
	# (user request 2026-09-09); the minister returns when the cursor leaves.
	_country_panel = CountryPanel.attach(%MinisterPanel.get_node("MVBox"), _world_map)
	%MinisterPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 8))
	UiPalette.style_header(%MinisterName, 9)
	UiPalette.style_header(%MinisterTitle, 7, UiPalette.TEXT_MUTED)
	%OpinionBar.add_theme_stylebox_override("background", UiPalette.bar_bg())
	%OpinionValue.add_theme_font_size_override("font_size", 8)
	_build_skill_rows()
	_build_dossier_tabs()
	UiPalette.style_header(%ToolsTitle, 7, UiPalette.TEXT_MUTED)
	%TiesText.add_theme_font_size_override("font_size", 8)
	%PopupPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 1, 12))
	UiPalette.style_header(%PopupTitle, 9)
	%PopupArt.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 6))
	%PopupArtText.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	%PopupArtText.add_theme_font_size_override("font_size", 8)
	var popup_dim: ColorRect = %EventPopup.get_node("PopupDim")
	popup_dim.color = UiPalette.DIM_OVERLAY
	_panel = %DialoguePanel
	_panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 10))
	_name_label = %NameLabel
	UiPalette.style_header(_name_label, 8)
	_scroll = %DialogueScroll
	_text_label = %TextLabel
	# User request 2026-08-31: the conversation reads smaller — compact body
	# text keeps the box from dominating the column.
	_text_label.add_theme_font_size_override("normal_font_size", 8)
	_text_label.add_theme_font_size_override("italics_font_size", 8)
	_replies_box = %RepliesBox
	_free_text = %FreeText
	_free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	_free_text.text_submitted.connect(_on_free_text)
	_continue_btn = %ContinueButton
	_continue_btn.pressed.connect(_on_continue)
	%MoveButton.add_theme_font_size_override("font_size", 8)
	%MoveButton.pressed.connect(_open_move_popup)
	Game.state_changed.connect(func() -> void:
		if is_inside_tree():
			_refresh_location())
	_refresh_location()
	_layout()

## Columns, map, strip, and the detail column when it is up (ScreenLayout).
func _layout() -> void:
	ScreenLayout.apply(%TopBar.bar_height() + 3.0, %MinisterPanel, %MapPanel,
		%DialoguePanel, _detail, _detail != null and _detail.visible)

func _fill_talk_box(text: String) -> void:
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
	_history.append({"speaker": speaker, "line": line})
	while _history.size() > HISTORY_CAP:
		_history.pop_front()
	_render_history()

## Renders the transcript. With people singled out, the box shows only the
## conversation between the player and them (user request 2026-08-31) —
## other speakers, herald notes and narration step aside until the selection
## is cleared.
func _render_history() -> void:
	var shown: Array = []
	if _selected_ids.is_empty():
		for e in _history:
			shown.append(e["line"])
	else:
		# The Herald stays: he narrates the outcome of orders the player just
		# typed — hiding him would swallow the response to your own words
		# (the exact bug class fixed 2026-08-30).
		var allowed := {"You": true, "Herald": true}
		for id in _selected_ids:
			if Game.state != null and Game.state.characters.has(id):
				allowed[Game.state.characters[id].display_name] = true
		for e in _history:
			if allowed.has(e["speaker"]):
				shown.append(e["line"])
	_text_label.text = "\n".join(shown)
	_scroll.set_deferred("scroll_vertical", 1000000)

## Deterministic per-speaker name color: fixed for You/Herald, hashed into a
## small palette for everyone else so each courtier keeps one color.
const SPEAKER_PALETTE := [Color("6fbf73"), Color("c05b5b"), Color("8b6bb5"),
	Color("5b8fc0"), Color("bf8f5f"), Color("6bb5ab"), Color("b56b9d")]

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
		btn.add_theme_font_size_override("font_size", 7)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_tab.bind(i))
		%TabsRow.add_child(btn)
		_tab_buttons.append(btn)
	_select_tab(0)

func _select_tab(index: int) -> void:
	for i in _tab_pages.size():
		_tab_pages[i].visible = i == index
		_tab_buttons[i].add_theme_color_override("font_color",
			UiPalette.GOLD if i == index else UiPalette.TEXT_MUTED)

func select_tab(index: int) -> void:
	_select_tab(index)

func tab_page(index: int) -> Control:
	return _tab_pages[index]

func current_beat() -> Dictionary:
	return {} if _index < 0 or _index >= _beats.size() else _beats[_index]

func continue_button() -> Button:
	return _continue_btn

func reply_buttons() -> Array:
	# Minister replies live in the right column; event/narration choices live
	# in the centered popup — one seam covers both.
	return _replies_box.get_children() + %PopupChoices.get_children()

func dialogue_text() -> String:
	return _text_label.get_parsed_text()

func event_popup() -> Control:
	return %EventPopup

## --- Location panel (the strip's left part) ----------------------------
## Where the player stands, who is present (click a face to seek them out),
## and MOVE — free movement within the region (LocationSystem).

## Who the player is addressing (user request 2026-08-31). Empty means the
## whole room: speaking with nobody selected addresses everyone present.
## Clicking a portrait toggles membership; the dossier follows the most
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
		btn.custom_minimum_size = Vector2(26, 26)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = Game.state.characters[id].display_name
		btn.toggle_mode = true
		btn.button_pressed = String(id) in _selected_ids
		btn.add_theme_stylebox_override("pressed",
			UiPalette.chip_style(UiPalette.CHIP_BG, UiPalette.GOLD))
		btn.pressed.connect(_toggle_target.bind(String(id)))
		var chip := CharacterPortrait.instantiate_for(id, false)
		chip.scale = Vector2(0.5, 0.5)
		chip.position = Vector2(1, 1)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(chip)
		%OccupantsRow.add_child(btn)
	_refresh_target_hint()

## Adds or removes someone from the address list. Selecting nobody means the
## whole room, so deselecting the last target quietly returns to addressing
## everyone. The dossier follows the click so you still see who you are
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
	%PopupArt.visible = false
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
		row.add_theme_constant_override("separation", 4)
		var name_l := Label.new()
		name_l.text = String(UiPalette.SKILL_NAMES[sk]).to_upper()
		name_l.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
		name_l.add_theme_font_size_override("font_size", 8)
		name_l.custom_minimum_size = Vector2(42, 0)
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.max_value = UiPalette.SKILL_MAX
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 5)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UiPalette.bar_bg())
		bar.add_theme_stylebox_override("fill",
			UiPalette.bar_fill(UiPalette.SKILL_COLORS[sk]))
		row.add_child(bar)
		_skill_bars[sk] = bar
		var value_l := Label.new()
		value_l.add_theme_font_size_override("font_size", 9)
		value_l.add_theme_color_override("font_color", UiPalette.SKILL_COLORS[sk])
		row.add_child(value_l)
		_skill_values[sk] = value_l
		%SkillRows.add_child(row)

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
	_next_reply_letter = 0
	_resolved_event = false
	_replies_box.visible = true
	# The move popup shares the centered popup with events/narration — no
	# moving while one is on stage (resolve or continue first).
	%MoveButton.disabled = String(b["kind"]) in ["event", "narration"]
	match String(b["kind"]):
		"event":
			_continue_btn.visible = false
			# Events pop centered (user ruling 2026-08-30: the old in-column
			# rendering distorted the top of the UI): title, an art
			# placeholder carrying the scene description until real event art
			# exists, the narration, and the choices.
			%EventPopup.visible = true
			%PopupTitle.visible = true
			%PopupTitle.text = "AN EVENT AT COURT"
			%PopupArt.visible = true
			%PopupArtText.text = "[ event art ]\n" + TemplateVoicer.line_for(
				Game.data, String(b["event"]["title_key"]), [], Game.state.tick)
			%PopupText.text = "..."
			Game.voice_event_scene(b["event"], func(res: Dictionary):
				# F2 (final-review fix wave): choice buttons render immediately
				# while this call is in flight. With real latency the player can
				# resolve the event (via button or free text) before this
				# callback returns; without this guard the late scene-setting
				# narration would land after the outcome line already shown.
				if _resolved_event:
					return
				%PopupText.text = String(res["text"])
				_say(String(b["speaker"]), String(res["text"])))
			for ch in b["event"]["choices"]:
				_add_reply(String(ch["label"]),
					_on_event_choice.bind(String(ch["choice_id"])), %PopupChoices)
		"narration":
			# The nameless opening narration (game background): centered like
			# an event, no speaker, no title, one continue button.
			_continue_btn.visible = false
			%EventPopup.visible = true
			%PopupTitle.visible = false
			%PopupArt.visible = false
			%PopupText.text = String(b["text"])
			_say("", String(b["text"]))
			_add_reply("I am ready. Let the reign begin.",
				_advance, %PopupChoices)
		"minister":
			_continue_btn.visible = true
			_say(String(b["speaker"]), String(b["text"]))
			for sug in b["suggestions"]:
				var label := TemplateVoicer.line_for(Game.data,
					"reply_" + String(sug["pitch_key"]), [], Game.state.tick)
				_add_reply(label, _on_quick_reply.bind(sug))
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
	# event and summary alike (a quiet tick now opens directly on the summary
	# beat, since standing suggestions no longer manufacture minister beats).
	# Only the modal opening narration, which has its own continue button and
	# no one to talk to, hides it.
	_free_text.visible = String(b["kind"]) != "narration"
	# The transcript keeps growing; a fresh beat reads from its newest line.
	_scroll.set_deferred("scroll_vertical", 1000000)

## Mock-style lettered responses ("A. Distribute reserves"), left-aligned,
## wrapping inside their column. Buttons start hidden; _reveal_replies_staggered
## surfaces them one by one.
func _add_reply(label: String, handler: Callable,
		into: Container = null) -> void:
	var btn := Button.new()
	btn.text = "%s.  %s" % [char(65 + _next_reply_letter), label]
	_next_reply_letter += 1
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.focus_mode = Control.FOCUS_NONE
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

## Fills the left dossier card for this beat's speaker: portrait (full-body
## art fitted into the box, chip fallback), name, seat title, opinion bar,
## and trait chips. Non-character beats (round table, herald) show just the
## portrait and name.
func _show_speaker(b: Dictionary) -> void:
	var portrait_id := String(b["portrait_id"])
	# Same queue_free() reasoning as _advance: the replacement is added
	# immediately, the outgoing node is pending-delete for one frame. Rename
	# it first so the incoming node can take the "FullArt" name instead of
	# being auto-renamed around the still-pending sibling.
	for child in %PortraitBox.get_children():
		child.name = "OutgoingPortrait"
		child.queue_free()
	for chip in %TraitChips.get_children():
		chip.queue_free()
	var box_size: Vector2 = %PortraitBox.custom_minimum_size
	var full := CharacterPortrait.full_texture_for(portrait_id)
	if full != null:
		# Cover-crop at the portrait box's aspect: tall figure art is cut from
		# the top (head and shoulders); wide/square art (the council
		# medallion) is centered.
		var img := Vector2(full.get_width(), full.get_height())
		var box_aspect := box_size.x / box_size.y
		var region: Rect2
		if img.x / img.y > box_aspect:
			var rw := img.y * box_aspect
			region = Rect2((img.x - rw) / 2.0, 0, rw, img.y)
		else:
			region = Rect2(0, 0, img.x, img.x / box_aspect)
		var atlas := AtlasTexture.new()
		atlas.atlas = full
		atlas.region = region
		var pic := TextureRect.new()
		pic.name = "FullArt"
		pic.texture = atlas
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		%PortraitBox.add_child(pic)
	else:
		var p := CharacterPortrait.instantiate_for(portrait_id, false)
		var scale_factor := box_size.y / CharacterPortrait.PORTRAIT_SIZE.y
		var side := CharacterPortrait.PORTRAIT_SIZE.x * scale_factor
		p.scale = Vector2(scale_factor, scale_factor)
		p.position = Vector2((box_size.x - side) / 2.0, 0)
		%PortraitBox.add_child(p)
	var c: Character = null
	if Game.state != null and Game.state.characters.has(portrait_id):
		c = Game.state.characters[portrait_id]
	%MinisterName.text = c.display_name if c != null else String(b.get("speaker", ""))
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
	for sk in CharacterFactory.SKILLS:
		_skill_bars[sk].value = int(c.skills.get(sk, 0))
		_skill_values[sk].text = str(int(c.skills.get(sk, 0)))
	for t in c.traits:
		var chip := Label.new()
		chip.text = String(Game.data.traits[t]["label"]) if Game.data.traits.has(t) else String(t)
		chip.add_theme_font_size_override("font_size", 9)
		chip.add_theme_color_override("font_color", UiPalette.GOLD)
		chip.add_theme_stylebox_override("normal", UiPalette.chip_style())
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
	l.add_theme_font_size_override("font_size", 7)
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
## in-flight voice callback - see F2 above), re-enable Continue, hide the
## free-text box, and speak the same per-choice outcome line.
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

## Test seam and GameRoot's handle on this screen's map.
func world_map() -> WorldMapView:
	return _world_map
