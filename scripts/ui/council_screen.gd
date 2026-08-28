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
var transcript: RichTextLabel
var suggestions_box: VBoxContainer
var free_text: LineEdit
var end_turn: Button
var _suggestion_buttons: Array = []

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
	transcript = RichTextLabel.new()
	transcript.bbcode_enabled = true
	transcript.scroll_following = true
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(transcript)
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
	end_turn.pressed.connect(_on_end_turn)
	input_row.add_child(end_turn)
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

func suggestion_buttons() -> Array:
	return _suggestion_buttons

func end_turn_button() -> Button:
	return end_turn

func _on_end_turn() -> void:
	_render_report(Game.next_tick())

func _render_report(report: TickReport) -> void:
	_render_metrics(report)
	_render_portraits()
	for line in TemplateVoicer.render_outcomes(report, Game.state, Game.data):
		_say(line)
	for line in TemplateVoicer.render_briefing(report, Game.state, Game.data):
		_say(line)
	_render_suggestions(report)

func _say(line: Dictionary) -> void:
	transcript.append_text("[b]%s:[/b] %s\n" % [line["speaker"], line["text"]])

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
	panel.tooltip_text = Game.state.characters[char_id].display_name
	var portrait_path := "res://assets/portraits/%s.png" % char_id
	if FileAccess.file_exists(portrait_path):
		var tex := TextureRect.new()
		tex.texture = load(portrait_path)
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		panel.add_child(tex)
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
	_say({"speaker": "You", "text": text})
	Game.submit_free_text(text, func(res: Dictionary):
		free_text.editable = true
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
