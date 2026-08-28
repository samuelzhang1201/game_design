extends Control
## Council screen: metrics strip / transcript / input row. Built in code.

const PIXEL_FONT_PATH := "res://assets/fonts/pixel.ttf"  # optional; falls back to default
const PORTRAIT_SIZE := Vector2(48, 48)

## Placeholder pixel portraits: distinct flat color per seat until real art
## lands (see assets/portraits/<character_id>.png escape hatch in _build_portrait).
const SEAT_COLORS := {
	"chancellor": Color("4a6fa5"), "marshal": Color("a54a4a"),
	"steward": Color("4aa571"), "spymaster": Color("6b4aa5"),
	"chaplain": Color("a58c4a"), "chief_justice": Color("4aa5a0"),
	"master_of_works": Color("8c8c8c"), "admiral": Color("2f5f8f"),
	"court_physician": Color("a54a8c"),
}
const DEFAULT_SEAT_COLOR := Color("555555")

var metrics_box: HBoxContainer
var portraits_box: HBoxContainer
var transcript_scroll: ScrollContainer
var transcript_box: VBoxContainer
var suggestions_box: VBoxContainer
var free_text: LineEdit
var end_turn: Button
var calendar_overlay: CalendarOverlay
var _pending_report: TickReport
var _suggestion_buttons: Array = []
var _portrait_cache: Dictionary = {}

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
	suggestions_box = VBoxContainer.new()
	root.add_child(suggestions_box)
	var input_row := HBoxContainer.new()
	root.add_child(input_row)
	free_text = LineEdit.new()
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
			and not calendar_overlay.playing():
		_on_end_turn()

func suggestion_buttons() -> Array:
	return _suggestion_buttons

func end_turn_button() -> Button:
	return end_turn

## End Turn advances the engine immediately (state is authoritative at once),
## then plays the calendar interlude; the new report renders when it finishes.
func _on_end_turn() -> void:
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
	var tex := _speaker_texture(speaker)
	if tex != null:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.custom_minimum_size = PORTRAIT_SIZE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		return SEAT_COLORS.get(Game.state.characters[char_id].seat, DEFAULT_SEAT_COLOR)
	return Color("8c5a5a")  # Herald / Council / system voices

func _speaker_texture(speaker: String) -> Texture2D:
	var key: String
	if speaker == "You":
		key = "you"
	elif speaker == "Herald" or speaker == "Council":
		key = "herald"
	else:
		key = _speaker_char_id(speaker)
	if key == "":
		return null
	return _portrait_texture("res://assets/portraits/%s.png" % key)

## Loads a portrait PNG directly from the filesystem (import-pipeline
## independent, so headless runs and fresh checkouts need no editor import),
## cached per path. Returns null when the file is absent.
func _portrait_texture(path: String) -> Texture2D:
	if _portrait_cache.has(path):
		return _portrait_cache[path]
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	_portrait_cache[path] = tex
	return tex

func _render_metrics(report: TickReport) -> void:
	for child in metrics_box.get_children():
		child.queue_free()
	var reasons := {}
	for d in report.metric_deltas:
		reasons[d["metric"]] = "%+.1f: %s" % [d["delta"], d["reason"]]
	for m in ["treasury", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]:
		var l := Label.new()
		l.text = "%s %d" % [m.capitalize(), int(Game.state.metrics[m])]
		l.tooltip_text = reasons.get(m, "no change")
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		metrics_box.add_child(l)
	var date := Label.new()
	date.text = Calendar.date_string(Game.state.tick)
	date.add_theme_color_override("font_color", Color("deba54"))
	date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	metrics_box.add_child(date)

## Placeholder pixel portraits (spec §6 / carried Task 11 acceptance criterion):
## one 48x48 panel per seated minister, in seat order, rebuilt whenever the
## council might have changed (mirrors _render_metrics' rebuild-on-every-call
## approach). Swappable for real art: drop a PNG at
## assets/portraits/<character_id>.png and _build_portrait picks it up.
func _render_portraits() -> void:
	for child in portraits_box.get_children():
		child.queue_free()
	for seat in Game.state.council:
		var char_id: String = Game.state.council[seat]
		portraits_box.add_child(_build_portrait(char_id, seat))

func _build_portrait(char_id: String, seat: String) -> Control:
	var panel := Control.new()
	panel.custom_minimum_size = PORTRAIT_SIZE
	var tex := _portrait_texture("res://assets/portraits/%s.png" % char_id)
	if tex != null:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		panel.add_child(pic)
	else:
		var bg := ColorRect.new()
		bg.color = SEAT_COLORS.get(seat, DEFAULT_SEAT_COLOR)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_child(bg)
		var initial := Label.new()
		initial.text = Game.state.characters[char_id].display_name.left(1).to_upper()
		initial.set_anchors_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(initial)
	var c: Character = Game.state.characters[char_id]
	var badge := Label.new()
	badge.text = str(c.opinion)
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color",
		Color("7fd47f") if c.opinion >= 0 else Color("d47f7f"))
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_child(badge)
	var recent := ""
	var log := c.opinion_log
	for i in range(maxi(0, log.size() - 5), log.size()):
		recent += "\n%+d %s" % [int(log[i]["delta"]), log[i]["reason"]]
	panel.tooltip_text = c.display_name + recent
	return panel

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

func _on_free_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	free_text.editable = false
	end_turn.disabled = true
	_say({"speaker": "You", "text": text})
	Game.submit_free_text(text, func(res: Dictionary):
		free_text.editable = true
		end_turn.disabled = false
		free_text.clear()
		if not res["ok"]:
			_say({"speaker": "Herald", "text":
				"The Chancellor frowns — the council doesn't follow. (%s)" % res["error"]})
			return
		for outcome in res["executed"]:
			_say({"speaker": "Herald", "text": "It is done: " + outcome["notes"]})
			_narrate_effects(outcome)
		for rej in res["rejected"]:
			_say({"speaker": "Herald", "text":
				"The council cannot: " + rej["error"]}))

func _apply_font() -> void:
	if not FileAccess.file_exists(PIXEL_FONT_PATH):
		return
	var font := load(PIXEL_FONT_PATH)
	if font:
		theme = Theme.new()
		theme.default_font = font
		theme.default_font_size = 16
