class_name ConversationScene
extends Control
## VN stage (R3/R4/R5): one big portrait, name plate, dialogue box pinned to
## the bottom. Beats advance on Continue / reply / event choice.
##
## User ruling (2026-08-29, supersedes the brief's "mid-bottom" auto-sizing
## box): the dialogue box is a FIXED-height full-width strip at the bottom of
## the view; long content (event text, many choices) scrolls inside it, so the
## box never grows over the portrait, which stands fully above it. The
## KingdomCard sits top-left here too, same corner as every gameplay screen.

signal finished

var _beats: Array = []
var _index := -1
var _report: TickReport
var _portrait_holder: Control
var _name_label: Label
var _text_label: Label
var _replies_box: VBoxContainer
var _free_text: LineEdit
var _continue_btn: Button
var _panel: PanelContainer
var _scroll: ScrollContainer
var _card: KingdomCard
var _resolved_event := false

## Static structure and layout live in scenes/conversation.tscn (editable in
## the editor); _ready only fetches the nodes, paints them from UiPalette,
## and wires signals. Dynamic content (portraits, reply buttons) is spawned
## at runtime below.
func _ready() -> void:
	%Bg.color = UiPalette.BG_STAGE
	_portrait_holder = %PortraitHolder
	_panel = %DialoguePanel
	_panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_MUTED, 2, 10))
	_name_label = %NameLabel
	_name_label.add_theme_color_override("font_color", UiPalette.GOLD)
	_scroll = %DialogueScroll
	_text_label = %TextLabel
	_replies_box = %RepliesBox
	_free_text = %FreeText
	_free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	_free_text.text_submitted.connect(_on_free_text)
	_continue_btn = %ContinueButton
	_continue_btn.pressed.connect(_advance)
	_card = %KingdomCard
	Game.state_changed.connect(_refresh_card)

func _refresh_card() -> void:
	if Game.state != null:
		_card.show_values(Game.state)

## `report` is the TickReport the beats were built from - kept so the summary
## beat can compose its text at display time (see ConversationBeats.summary_text)
## rather than baking it in at build time, since a quick-reply/free-text order
## taken earlier in THIS conversation can change what "resolved this session"
## means by the time the player reaches the summary (FIX 2, post-Task-5 review).
func start(beats: Array, report: TickReport) -> void:
	_beats = beats
	_report = report
	_index = -1
	_refresh_card()
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

func kingdom_card() -> KingdomCard:
	return _card

func _advance() -> void:
	_index += 1
	if _index >= _beats.size():
		finished.emit()
		return
	var b := current_beat()
	_show_portrait(String(b["portrait_id"]))
	_name_label.text = String(b["speaker"])
	# Deviation from the brief (pre-approved): the brief's literal `child.free()`
	# here frees while iterating the container's own get_children() snapshot -
	# a crash hazard idiom. queue_free() defers the actual removal to end of
	# frame; the fresh reply buttons added just below this block coexist with
	# the outgoing (pending-delete) ones for at most one frame, which is fine
	# since every test awaits frames before asserting on reply_buttons().
	for child in _replies_box.get_children():
		child.queue_free()
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

func _add_reply(label: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	_replies_box.add_child(btn)

# Portrait sizes, sharing the PORTRAIT_FLOOR line so both kinds stand fully
# above the fixed dialogue strip (user ruling 2026-08-29): full-body art
# 176 tall (top at y=10), the 48px chip scaled 3.5x to 168.
const FULL_ART_HEIGHT := 176.0
const CHIP_SCALE := 3.5

func _show_portrait(portrait_id: String) -> void:
	# Deviation from the brief (pre-approved): same queue_free() reasoning as
	# _advance above - the new portrait is added immediately after, so the
	# outgoing one is only pending-delete for the rest of this frame.
	for child in _portrait_holder.get_children():
		child.queue_free()
	var full := CharacterPortrait.full_texture_for(portrait_id)
	if full != null:
		var pic := TextureRect.new()
		pic.name = "FullArt"
		pic.texture = full
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var w := FULL_ART_HEIGHT * full.get_width() / full.get_height()
		pic.size = Vector2(w, FULL_ART_HEIGHT)
		pic.position = Vector2(-w / 2.0, -FULL_ART_HEIGHT)
		_portrait_holder.add_child(pic)
		return
	var p := CharacterPortrait.instantiate_for(portrait_id, false)
	p.scale = Vector2(CHIP_SCALE, CHIP_SCALE)
	var side := CharacterPortrait.PORTRAIT_SIZE.x * CHIP_SCALE
	p.position = Vector2(-side / 2.0, -side)
	_portrait_holder.add_child(p)

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
