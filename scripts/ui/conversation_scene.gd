class_name ConversationScene
extends Control
## VN stage (R3/R4/R5), game_ui.png chrome (user ruling 2026-08-30): two UI
## columns with the BRIGHT map in between, never covered - dossier card fills
## the LEFT column (portrait, name, seat, opinion bar, trait chips), the
## dialogue/response panel fills the RIGHT column (mock's "your response"
## panel; long content scrolls), and the kings frame sits nine-patched in
## the middle map area only. Beats advance on Continue / reply / choice.

signal finished

var _beats: Array = []
var _index := -1
var _report: TickReport
var _name_label: Label
var _text_label: Label
var _replies_box: VBoxContainer
var _free_text: LineEdit
var _continue_btn: Button
var _panel: PanelContainer
var _scroll: ScrollContainer
var _resolved_event := false

## Static structure and layout live in scenes/conversation.tscn (editable in
## the editor); _ready only fetches the nodes, paints them from UiPalette,
## and wires signals. Dynamic content (portraits, trait chips, reply
## buttons) is spawned at runtime below.
func _ready() -> void:
	%Backdrop.texture = UiPalette.backdrop()
	%Backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	%Backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	%Shade.color = UiPalette.MAP_TINT
	UiPalette.setup_frame_nine(%Frame)
	%MinisterPanel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 8))
	UiPalette.style_header(%MinisterName, 11)
	UiPalette.style_header(%MinisterTitle, 8, UiPalette.TEXT_MUTED)
	%OpinionBar.add_theme_stylebox_override("background",
		UiPalette.chip_style(Color("0f1017"), UiPalette.BORDER_GOLD))
	%OpinionValue.add_theme_font_size_override("font_size", 9)
	_panel = %DialoguePanel
	_panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 10))
	_name_label = %NameLabel
	UiPalette.style_header(_name_label, 12)
	_scroll = %DialogueScroll
	_text_label = %TextLabel
	_replies_box = %RepliesBox
	_free_text = %FreeText
	_free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	_free_text.text_submitted.connect(_on_free_text)
	_continue_btn = %ContinueButton
	_continue_btn.pressed.connect(_advance)

## `report` is the TickReport the beats were built from - kept so the summary
## beat can compose its text at display time (see ConversationBeats.summary_text)
## rather than baking it in at build time, since a quick-reply/free-text order
## taken earlier in THIS conversation can change what "resolved this session"
## means by the time the player reaches the summary (FIX 2, post-Task-5 review).
func start(beats: Array, report: TickReport) -> void:
	_beats = beats
	_report = report
	_index = -1
	_advance()

func current_beat() -> Dictionary:
	return {} if _index < 0 or _index >= _beats.size() else _beats[_index]

func continue_button() -> Button:
	return _continue_btn

func reply_buttons() -> Array:
	return _replies_box.get_children()

func dialogue_text() -> String:
	return _text_label.text

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

func _advance() -> void:
	_index += 1
	if _index >= _beats.size():
		finished.emit()
		return
	var b := current_beat()
	_show_speaker(b)
	_name_label.text = String(b["speaker"])
	# Deviation from the brief (pre-approved): the brief's literal `child.free()`
	# here frees while iterating the container's own get_children() snapshot -
	# a crash hazard idiom. queue_free() defers the actual removal to end of
	# frame; the fresh reply buttons added just below this block coexist with
	# the outgoing (pending-delete) ones for at most one frame, which is fine
	# since every test awaits frames before asserting on reply_buttons().
	for child in _replies_box.get_children():
		child.queue_free()
	_next_reply_letter = 0
	_resolved_event = false
	match String(b["kind"]):
		"event":
			_continue_btn.visible = false
			_text_label.text = "..."
			Game.voice_event_scene(b["event"], func(res: Dictionary):
				# F2 (final-review fix wave): choice buttons render immediately
				# while this call is in flight. With real latency the player can
				# resolve the event (via button or free text) before this
				# callback returns; without this guard the late scene-setting
				# narration would overwrite the outcome line already shown.
				if _resolved_event:
					return
				_text_label.text = String(res["text"]))
			for ch in b["event"]["choices"]:
				_add_reply(String(ch["label"]), _on_event_choice.bind(String(ch["choice_id"])))
		"minister":
			_continue_btn.visible = true
			_text_label.text = String(b["text"])
			for sug in b["suggestions"]:
				var label := TemplateVoicer.line_for(Game.data,
					"reply_" + String(sug["pitch_key"]), [], Game.state.tick)
				_add_reply(label, _on_quick_reply.bind(sug))
		"summary":
			_continue_btn.visible = true
			_text_label.text = ConversationBeats.summary_text(_report, Game.state, Game.data)
	# F1 (final-review fix wave): event beats must accept free text too - it's
	# the only path back to EVENT_CHOICE via typed orders (Game.submit_free_text's
	# EVENT_CHOICE branch was otherwise unreachable). Shown alongside the choice
	# buttons while the event is unresolved; _resolve_event hides it again once
	# either path (button or free text) resolves the event.
	_free_text.visible = String(b["kind"]) in ["minister", "event"]
	# A fresh beat reads from the top of the fixed-height strip.
	_scroll.set_deferred("scroll_vertical", 0)

## Mock-style lettered responses ("A. Distribute reserves"), left-aligned,
## wrapping inside the response column instead of overflowing it.
func _add_reply(label: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = "%s.  %s" % [char(65 + _next_reply_letter), label]
	_next_reply_letter += 1
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	_replies_box.add_child(btn)

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
	if c == null:
		return
	%MinisterTitle.text = String(Game.data.seats[c.seat]["label"]).to_upper() \
		if Game.data.seats.has(c.seat) else String(c.seat).to_upper()
	%OpinionBar.value = c.opinion
	var tone: Color = UiPalette.POSITIVE if c.opinion >= 0 else UiPalette.NEGATIVE
	%OpinionBar.add_theme_stylebox_override("fill", UiPalette.chip_style(tone, tone))
	%OpinionValue.text = "%+d" % c.opinion
	%OpinionValue.add_theme_color_override("font_color", tone)
	for t in c.traits:
		var chip := Label.new()
		chip.text = String(Game.data.traits[t]["label"]) if Game.data.traits.has(t) else String(t)
		chip.add_theme_font_size_override("font_size", 7)
		chip.add_theme_color_override("font_color", UiPalette.GOLD)
		chip.add_theme_stylebox_override("normal", UiPalette.chip_style())
		%TraitChips.add_child(chip)

func _on_quick_reply(sug: Dictionary) -> void:
	var result: Dictionary = Game.try_execute(sug["request"])
	if not result["ok"]:
		_text_label.text = String(result["error"])
		return
	for child in _replies_box.get_children():
		child.queue_free()
	_text_label.text = TemplateVoicer.line_for(Game.data,
		"outcome_" + String(sug["request"].action_code), [], Game.state.tick) \
		+ _promise_kept_suffix(result["outcome"]["effects"])

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
	_resolved_event = true
	_continue_btn.visible = true
	_free_text.visible = false
	_text_label.text = TemplateVoicer.line_for(Game.data,
		"event_%s_%s" % [event_id, choice_id], [], Game.state.tick)

func _on_free_text(text: String) -> void:
	if text.strip_edges() == "":
		return
	_free_text.editable = false
	Game.submit_free_text(text, func(res: Dictionary):
		_free_text.editable = true
		_free_text.clear()
		# Re-review (final fix wave): both choice buttons and free text are
		# live on an unresolved event beat, so a button click can resolve the
		# event while this parse is still in flight. The stale callback must
		# restore the field (above) but never touch the dialogue line - the
		# same bug class as the F2 voice-callback guard. _resolved_event
		# resets at each _advance, so minister-beat replies are unaffected.
		if _resolved_event:
			return
		if not res["ok"]:
			_text_label.text = "The council doesn't follow. (%s)" % String(res["error"])
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
			spoken += TemplateVoicer.line_for(Game.data,
				"outcome_" + String(outcome["action_code"]), [], Game.state.tick)
			spoken += _promise_kept_suffix(outcome["effects"]) + " "
		_text_label.text = spoken if spoken != "" else "So noted."
	)
