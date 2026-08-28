extends Control
## Council screen: metrics strip / transcript / input row. Built in code.

const PIXEL_FONT_PATH := "res://assets/fonts/pixel.ttf"  # optional; falls back to default
## Character visuals live in their own scenes (scenes/characters/*) with
## script scripts/ui/character_portrait.gd - swap art there, not here.
## Short metric display names: the full names overflow the 640px canvas
## once six metrics render, pushing End Turn off-screen (live bug).
const METRIC_NAMES := {"treasury": "Gold", "grain": "Grain", "unrest": "Unrest",
	"legitimacy": "Legit", "army_quality": "Army", "church_opinion": "Church"}

var metrics_box: HBoxContainer
var portraits_box: HBoxContainer
var transcript_scroll: ScrollContainer
var transcript_box: VBoxContainer
var event_box: VBoxContainer
var suggestions_box: VBoxContainer
var free_text: LineEdit
var end_turn: Button
var calendar_overlay: CalendarOverlay
var _pending_report: TickReport
var _suggestion_buttons: Array = []
var _event_buttons: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a1423")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	metrics_box = HBoxContainer.new()
	root.add_child(metrics_box)
	portraits_box = HBoxContainer.new()
	portraits_box.add_theme_constant_override("separation", 4)
	root.add_child(portraits_box)
	transcript_scroll = ScrollContainer.new()
	transcript_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	transcript_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(transcript_scroll)
	transcript_box = VBoxContainer.new()
	transcript_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transcript_box.add_theme_constant_override("separation", 6)
	transcript_scroll.add_child(transcript_box)
	event_box = VBoxContainer.new()
	root.add_child(event_box)
	suggestions_box = VBoxContainer.new()
	root.add_child(suggestions_box)
	var input_row := HBoxContainer.new()
	root.add_child(input_row)
	free_text = LineEdit.new()
	free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	free_text.placeholder_text = "Give an order..."
	free_text.editable = true
	free_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	free_text.text_submitted.connect(_on_free_text_submitted)
	input_row.add_child(free_text)
	end_turn = Button.new()
	end_turn.text = "End Turn"
	end_turn.focus_mode = Control.FOCUS_NONE  # activated by click or Enter (unhandled)
	end_turn.pressed.connect(_on_end_turn)
	input_row.add_child(end_turn)
	calendar_overlay = CalendarOverlay.new()
	calendar_overlay.finished.connect(_on_interlude_finished)
	add_child(calendar_overlay)
	_apply_font()
	# Only auto-start when running as the main scene. Under a test harness the
	# screen is added beneath a test node, so this guard is false and the test
	# fully controls the lifecycle (start_campaign + begin are called explicitly).
	if get_parent() == get_tree().root:
		if Game.state == null:
			Game.start_campaign(42)
		begin.call_deferred()

func begin() -> void:
	_render_report(Game.next_tick())

## Enter ends the turn (when the order box isn't focused - a focused LineEdit
## consumes Enter itself, so this only fires from unhandled input).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not end_turn.disabled \
			and not calendar_overlay.playing() and Game.state.pending_event.is_empty():
		_on_end_turn()

func suggestion_buttons() -> Array:
	return _suggestion_buttons

func event_buttons() -> Array:
	return _event_buttons

func end_turn_button() -> Button:
	return end_turn

## End Turn advances the engine immediately (state is authoritative at once),
## then plays the calendar interlude; the new report renders when it finishes.
func _on_end_turn() -> void:
	if not Game.state.pending_event.is_empty():
		return
	end_turn.disabled = true
	_pending_report = Game.next_tick()
	calendar_overlay.play(_pending_report.tick)

func _on_interlude_finished() -> void:
	end_turn.disabled = false
	if _pending_report != null:
		var report := _pending_report
		_pending_report = null
		_render_report(report)

func _render_report(report: TickReport) -> void:
	_render_metrics(report)
	_render_portraits()
	for line in TemplateVoicer.render_outcomes(report, Game.state, Game.data):
		_say(line)
	for pe in report.promise_events:
		var key := "promise_" + String(pe["status"])
		_say({"speaker": "Herald", "text": TemplateVoicer.line_for(Game.data, key, [], report.tick)})
	# Briefing lines arrive via Game.voice_briefing's callback, which is
	# asynchronous even offline (Voicer's busy-guard/fallback path still
	# goes through a signal). Suggestions below render synchronously, so
	# they may appear in the transcript before the briefing text — ordering
	# is outcomes first, then briefing, then suggestions is not guaranteed
	# relative to briefing; that's acceptable (see FIX 4 in the fix wave).
	Game.voice_briefing(func(res: Dictionary):
		for line in res["lines"]:
			_say(line))
	_render_suggestions(report)
	if not report.event.is_empty():
		_render_event(report.event)

## One conversation frame per spoken line: the speaker's pixel portrait on the
## left, name + wrapped speech beside it, framed in the speaker's seat colour.
func _say(line: Dictionary) -> void:
	var speaker: String = line["speaker"]
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241c33")
	style.border_color = _speaker_color(speaker)
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	frame.add_child(row)
	var portrait_id := _speaker_portrait_id(speaker)
	if portrait_id != "":
		var pic := CharacterPortrait.instantiate_for(portrait_id, false)
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(pic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var name_label := Label.new()
	name_label.text = speaker
	name_label.add_theme_color_override("font_color", _speaker_color(speaker))
	col.add_child(name_label)
	var text_label := Label.new()
	text_label.text = line["text"]
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(text_label)
	transcript_box.add_child(frame)
	_scroll_to_bottom.call_deferred()

func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	transcript_scroll.scroll_vertical = int(transcript_scroll.get_v_scroll_bar().max_value)

func _speaker_char_id(speaker: String) -> String:
	if Game.state == null:
		return ""
	for id in Game.state.characters:
		if Game.state.characters[id].display_name == speaker:
			return id
	return ""

func _speaker_color(speaker: String) -> Color:
	if speaker == "You":
		return Color("deba54")
	var char_id := _speaker_char_id(speaker)
	if char_id != "":
		return CharacterPortrait.SEAT_COLORS.get(
			Game.state.characters[char_id].seat, CharacterPortrait.DEFAULT_SEAT_COLOR)
	return Color("8c5a5a")  # Herald / Council / system voices

func _speaker_portrait_id(speaker: String) -> String:
	if speaker == "You":
		return "you"
	if speaker == "Herald" or speaker == "Council":
		return "herald"
	return _speaker_char_id(speaker)

func _render_metrics(report: TickReport) -> void:
	for child in metrics_box.get_children():
		child.queue_free()
	var reasons := {}
	for d in report.metric_deltas:
		reasons[d["metric"]] = "%+.1f: %s" % [d["delta"], d["reason"]]
	for m in ["treasury", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]:
		var l := Label.new()
		l.text = "%s %d" % [METRIC_NAMES[m], int(Game.state.metrics[m])]
		l.tooltip_text = "%s\n%s" % [m.capitalize(), reasons.get(m, "no change")]
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		metrics_box.add_child(l)


func _render_date() -> void:
	for child in portraits_box.get_children():
		if child.name == "DateLabel":
			child.queue_free()
	var date := Label.new()
	date.name = "DateLabel"
	date.text = Calendar.date_string(Game.state.tick)
	date.add_theme_color_override("font_color", Color("deba54"))
	date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portraits_box.add_child(date)

## One CharacterPortrait scene instance per seated minister, in seat order,
## rebuilt each render. Per-character art is edited in scenes/characters/.
func _render_portraits() -> void:
	for child in portraits_box.get_children():
		child.queue_free()
	for seat in Game.state.council:
		portraits_box.add_child(
			CharacterPortrait.instantiate_for(Game.state.council[seat]))
	# Date lives at the right of the portraits row (plenty of free width).
	_render_date()

func _chancellor_name() -> String:
	if Game.state.council.has("chancellor"):
		return Game.state.characters[Game.state.council["chancellor"]].display_name
	return "The Chancellor"

## Guided-phase polish (spec CS-1.5): "post-execution explanation of what
## moved and why" — one line per metric effect, in the Chancellor's voice.
func _narrate_effects(outcome: Dictionary) -> void:
	var chancellor_name := _chancellor_name()
	for e in outcome["effects"]:
		_say({"speaker": chancellor_name, "text":
			"%s: %+d — %s" % [e["metric"], int(e["delta"]), e["reason"]]})

func _render_suggestions(report: TickReport) -> void:
	for child in suggestions_box.get_children():
		child.queue_free()
	_suggestion_buttons = []
	for sug in report.suggestions:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE  # Enter is reserved for End Turn
		var sp: String = Game.state.characters[Game.state.council[sug["seat"]]].display_name \
			if Game.state.council.has(sug["seat"]) else sug["seat"]
		b.text = "%s: %s" % [sp, sug["request"].action_code]
		b.tooltip_text = sug["tradeoff"]
		b.pressed.connect(_on_suggestion.bind(sug["request"]))
		suggestions_box.add_child(b)
		_suggestion_buttons.append(b)

func _on_suggestion(req: ActionRequest) -> void:
	var result: Dictionary = Game.try_execute(req)
	if not result["ok"]:
		_say({"speaker": "Herald", "text": result["error"]})
		return
	_narrate_effects(result["outcome"])
	for b in _suggestion_buttons:
		b.disabled = true

## While Game.state.pending_event is non-empty, End Turn/Enter and the
## suggestion buttons are gated off and a scene frame + one Button per choice
## render in event_box; picking a choice restores normal input.
func _render_event(ev: Dictionary) -> void:
	for child in event_box.get_children():
		child.queue_free()
	_event_buttons = []
	for child in suggestions_box.get_children():
		child.visible = false
	end_turn.disabled = true
	free_text.placeholder_text = "The court waits on your decision..."
	Game.voice_event_scene(ev, func(res: Dictionary):
		_say({"speaker": "Herald", "text": String(res["text"])}))
	for ch in ev["choices"]:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(ch["label"])
		b.pressed.connect(_on_event_choice.bind(String(ch["choice_id"])))
		event_box.add_child(b)
		_event_buttons.append(b)

func _on_event_choice(choice_id: String) -> void:
	var event_id := String(Game.state.pending_event.get("event_id", ""))
	var out: Dictionary = Game.apply_event_choice(choice_id)
	if out.is_empty():
		return
	_say({"speaker": "You", "text": String(out["label"])})
	_finish_event(event_id, choice_id, out)

## Shared post-resolution cleanup for a pending event, regardless of whether
## the choice arrived by button click (_on_event_choice) or was parsed out of
## free text as the EVENT_CHOICE pseudo-action (_on_free_text_submitted):
## narrates the outcome, hides the (now stale) choice buttons, restores
## suggestions/placeholder/End Turn, and re-renders portraits so drifted
## opinions show. `out` is the apply_event_choice/apply_choice result
## ({event_id, choice_id, label, effects, drift}) — event_id/choice_id are
## passed separately since the button path captures event_id before the
## resolved pending_event is cleared.
func _finish_event(event_id: String, choice_id: String, out: Dictionary) -> void:
	for b in _event_buttons:
		b.queue_free()
	_event_buttons = []
	_say({"speaker": "Herald", "text": TemplateVoicer.line_for(Game.data,
		"event_%s_%s" % [event_id, choice_id], [], Game.state.tick)})
	for d in out["drift"]:
		var c: Character = Game.state.characters[d["character_id"]]
		_say({"speaker": c.display_name, "text": "%+d — %s" % [int(d["delta"]), d["reason"]]})
	for child in suggestions_box.get_children():
		child.visible = true
	end_turn.disabled = false
	free_text.placeholder_text = "Give an order..."
	_render_portraits()

func _on_free_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	free_text.editable = false
	end_turn.disabled = true
	_say({"speaker": "You", "text": text})
	Game.submit_free_text(text, func(res: Dictionary):
		# free_text itself always re-enables; End Turn only when no event is
		# pending — a free-text NORMAL action must not let the player skip
		# past an event that's still awaiting a choice (controller ruling,
		# Task 7 review). If this free text WAS the EVENT_CHOICE that
		# resolved the event, _finish_event below has already cleared
		# pending_event, so this still re-enables End Turn correctly.
		free_text.editable = true
		free_text.clear()
		if not res["ok"]:
			_say({"speaker": "Herald", "text":
				"The Chancellor frowns — the council doesn't follow. (%s)" % res["error"]})
		else:
			for outcome in res["executed"]:
				if outcome["action_code"] == "EVENT_CHOICE":
					_finish_event(String(outcome["event_id"]), String(outcome["choice_id"]), outcome)
					continue
				_say({"speaker": "Herald", "text": "It is done: " + outcome["notes"]})
				_narrate_effects(outcome)
			for rej in res["rejected"]:
				_say({"speaker": "Herald", "text":
					"The council cannot: " + rej["error"]})
		if Game.state.pending_event.is_empty():
			end_turn.disabled = false)

func _apply_font() -> void:
	if not FileAccess.file_exists(PIXEL_FONT_PATH):
		return
	var font := load(PIXEL_FONT_PATH)
	if font:
		theme = Theme.new()
		theme.default_font = font
		theme.default_font_size = 16
