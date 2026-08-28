extends Control
## Council screen: metrics strip / transcript / input row. Built in code.

const PIXEL_FONT_PATH := "res://assets/fonts/pixel.ttf"  # optional; falls back to default

var metrics_box: HBoxContainer
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
	free_text.placeholder_text = "Give an order... (couriers arrive in a later build)"
	free_text.editable = false
	free_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	for b in _suggestion_buttons:
		b.disabled = true

func _apply_font() -> void:
	if not FileAccess.file_exists(PIXEL_FONT_PATH):
		return
	var font := load(PIXEL_FONT_PATH)
	if font:
		theme = Theme.new()
		theme.default_font = font
		theme.default_font_size = 16
