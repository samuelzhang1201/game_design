class_name CourtScreen
extends Control
## Court screen (Task 6, replaces CouncilScreen): the trimmed order screen.
## All minister speech, briefing, and event resolution now happen on the
## conversation stage (Task 5) before GameRoot ever switches here — this
## screen is numbers + orders only (spec R2): a KingdomCard docked right
## (R1/R7/R9), a short Herald/court log (plain Labels, no portraits — R10),
## and the free-text/suggestion order bar (R8).

## Emitted instead of self-driving the turn cycle: GameRoot owns advancing
## the tick and playing the DAY_RUN interlude. See enter_court.
signal end_turn_requested

const PIXEL_FONT_PATH := "res://assets/fonts/pixel.ttf"  # optional; falls back to default
## Log cap (R10-adjacent polish, ported from the old council screen's transcript):
## keeps the court log short since it only ever holds order results, not a
## full conversation transcript.
const LOG_CAP := 8

var card: KingdomCard
var log_box: VBoxContainer
var suggestions_box: VBoxContainer
var free_text: LineEdit
var end_turn: Button

var _log_scroll: ScrollContainer
var _suggestion_buttons: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a1423")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	root.add_child(left)

	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_log_scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 4)
	_log_scroll.add_child(log_box)

	suggestions_box = VBoxContainer.new()
	suggestions_box.add_theme_constant_override("separation", 2)
	left.add_child(suggestions_box)

	var input_row := HBoxContainer.new()
	left.add_child(input_row)
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

	# KingdomCard docked right (R1): last child of the root HBoxContainer, so
	# it hugs the right edge while `left` absorbs all remaining width.
	card = load("res://scenes/kingdom_card.tscn").instantiate()
	card.custom_minimum_size = Vector2(180, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(card)

	_apply_font()

## Post-conversation court entry (R2): numbers + orders only, speech already
## happened on the conversation stage. Called by GameRoot after the
## conversation scene finishes (see game_root.gd's _on_conversation_finished).
func enter_court(report: TickReport) -> void:
	card.show_values(Game.state)
	_render_suggestions(report)

## Enter ends the turn (when the order box isn't focused - a focused LineEdit
## consumes Enter itself, so this only fires from unhandled input).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not end_turn.disabled \
			and Game.state.pending_event.is_empty():
		_on_end_turn()

func suggestion_buttons() -> Array:
	return _suggestion_buttons

func end_turn_button() -> Button:
	return end_turn

## End Turn does not advance the engine itself - GameRoot owns the tick
## advance and the DAY_RUN interlude; this screen just signals that the
## player is done for the fortnight. Gated on pending_event so a player
## cannot skip past an event still awaiting a decision.
func _on_end_turn() -> void:
	if not Game.state.pending_event.is_empty():
		return
	end_turn.disabled = true
	end_turn_requested.emit()

## Natural-language suggestion buttons (R8): the pitch template IS the
## label - traits are passed as [] so labels stay generic (court has no
## on-screen speaker left to tint them for; that nuance lives on the
## conversation stage's pitch beats instead). {tradeoff} is stripped from
## the label itself (passed empty + strip_edges) since the tooltip already
## carries the tradeoff text in full.
func _render_suggestions(report: TickReport) -> void:
	for child in suggestions_box.get_children():
		child.queue_free()
	_suggestion_buttons = []
	for sug in report.suggestions:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE  # Enter is reserved for End Turn
		b.text = TemplateVoicer.line_for(Game.data, "pitch_" + String(sug["pitch_key"]), [],
			Game.state.tick, {"tradeoff": ""}).strip_edges()
		b.tooltip_text = String(sug["tradeoff"])
		b.pressed.connect(_on_suggestion.bind(sug, b))
		suggestions_box.add_child(b)
		_suggestion_buttons.append(b)

func _on_suggestion(sug: Dictionary, btn: Button) -> void:
	var result: Dictionary = Game.try_execute(sug["request"])
	if not result["ok"]:
		_log("Herald", result["error"])
		return
	var line: String = TemplateVoicer.line_for(Game.data,
		"outcome_" + String(sug["request"].action_code), [], Game.state.tick)
	_log("Herald", line + _promise_kept_suffix(result["outcome"]["effects"]))
	btn.disabled = true  # only this button - the rest are still valid orders
	card.show_values(Game.state)

func _on_free_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	free_text.editable = false
	end_turn.disabled = true
	_log("You", text)
	Game.submit_free_text(text, func(res: Dictionary):
		# free_text itself always re-enables; End Turn only when no event is
		# pending - a free-text NORMAL action must not let the player skip
		# past an event that's still awaiting a choice (controller ruling,
		# ported from the old council screen). If this free text WAS the
		# EVENT_CHOICE that resolved the event, pending_event is already
		# clear by the time this callback runs, so End Turn re-enables
		# correctly too.
		free_text.editable = true
		free_text.clear()
		if not res["ok"]:
			_log("Herald", "The council cannot: " + String(res["error"]))
		else:
			for outcome in res["executed"]:
				if String(outcome["action_code"]) == "EVENT_CHOICE":
					_log("Herald", String(outcome["notes"]))
					continue
				var line: String = TemplateVoicer.line_for(Game.data,
					"outcome_" + String(outcome["action_code"]), [], Game.state.tick)
				_log("Herald", line + _promise_kept_suffix(outcome["effects"]))
			for rej in res["rejected"]:
				_log("Herald", "The council cannot: " + String(rej["error"]))
			card.show_values(Game.state)
		if Game.state.pending_event.is_empty():
			end_turn.disabled = false)

## Ported from conversation_scene.gd: a kept promise rides along as a
## pseudo-effect on the outcome (metric == "promise" - see
## ActionSystem.execute's promise loop), with no template lookup of its own;
## its reason string IS the line ("a promise kept: <label>"), so it's
## appended verbatim rather than routed through TemplateVoicer.line_for.
func _promise_kept_suffix(effects: Array) -> String:
	var suffix := ""
	for e in effects:
		if String(e.get("metric", "")) == "promise":
			suffix += " " + String(e["reason"])
	return suffix

## Plain-Label log line, newest last, capped at LOG_CAP (R10: no portraits,
## no per-speaker frames - just the order/result text).
func _log(speaker: String, text: String) -> void:
	var l := Label.new()
	l.text = "%s: %s" % [speaker, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_child(l)
	while log_box.get_child_count() > LOG_CAP:
		var oldest := log_box.get_child(0)
		log_box.remove_child(oldest)
		oldest.queue_free()
	_scroll_log_to_bottom.call_deferred()

func _scroll_log_to_bottom() -> void:
	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)

func _apply_font() -> void:
	if not FileAccess.file_exists(PIXEL_FONT_PATH):
		return
	var font := load(PIXEL_FONT_PATH)
	if font:
		theme = Theme.new()
		theme.default_font = font
		theme.default_font_size = 16
