class_name ConversationScene
extends Control
## VN stage (R3/R4/R5): one big portrait, name plate, dialogue box mid-bottom,
## replies inside the box. Beats advance on Continue / reply / event choice.

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
var _resolved_event := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("161020")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_portrait_holder = Control.new()
	_portrait_holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_portrait_holder.position += Vector2(90, -40)
	add_child(_portrait_holder)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241c33")
	style.border_color = Color("8c86a0")
	style.set_border_width_all(2)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position.y -= 16
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", Color("deba54"))
	col.add_child(_name_label)
	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(400, 0)
	col.add_child(_text_label)
	_replies_box = VBoxContainer.new()
	col.add_child(_replies_box)
	_free_text = LineEdit.new()
	_free_text.placeholder_text = "Speak your mind..."
	_free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	_free_text.text_submitted.connect(_on_free_text)
	col.add_child(_free_text)
	_continue_btn = Button.new()
	_continue_btn.text = "Wave them on"
	_continue_btn.focus_mode = Control.FOCUS_NONE
	_continue_btn.pressed.connect(_advance)
	col.add_child(_continue_btn)

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
	_free_text.visible = String(b["kind"]) == "minister"

func _add_reply(label: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	_replies_box.add_child(btn)

func _show_portrait(portrait_id: String) -> void:
	# Deviation from the brief (pre-approved): same queue_free() reasoning as
	# _advance above - the new portrait is added immediately after, so the
	# outgoing one is only pending-delete for the rest of this frame.
	for child in _portrait_holder.get_children():
		child.queue_free()
	var p := CharacterPortrait.instantiate_for(portrait_id, false)
	p.scale = Vector2(4, 4)
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
	for child in _replies_box.get_children():
		child.queue_free()
	_resolved_event = true
	_continue_btn.visible = true
	_text_label.text = TemplateVoicer.line_for(Game.data,
		"event_%s_%s" % [String(out["event_id"]), String(out["choice_id"])], [],
		Game.state.tick)

func _on_free_text(text: String) -> void:
	if text.strip_edges() == "":
		return
	_free_text.editable = false
	Game.submit_free_text(text, func(res: Dictionary):
		_free_text.editable = true
		_free_text.clear()
		if not res["ok"]:
			_text_label.text = "The council doesn't follow. (%s)" % String(res["error"])
			return
		var spoken := ""
		for outcome in res["executed"]:
			spoken += TemplateVoicer.line_for(Game.data,
				"outcome_" + String(outcome["action_code"]), [], Game.state.tick)
			spoken += _promise_kept_suffix(outcome["effects"]) + " "
		_text_label.text = spoken if spoken != "" else "So noted."
	)
