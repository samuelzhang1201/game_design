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

## Static structure and layout live in scenes/court.tscn (editable in the
## editor): KingdomCard docked top-LEFT as the root HBox's first child (user
## ruling 2026-08-29, supersedes R1's right dock), an 8px screen inset, and
## the log/suggestions/order-bar column. _ready fetches nodes, paints them
## from UiPalette, and wires signals; log lines and suggestion buttons are
## spawned at runtime below.
func _ready() -> void:
	%Bg.color = UiPalette.BG_SCREEN
	card = %KingdomCard
	Game.state_changed.connect(_refresh_card)
	_log_scroll = %LogScroll
	log_box = %LogBox
	suggestions_box = %SuggestionsBox
	free_text = %FreeText
	free_text.max_length = int(Game.data.bal("prompt_max_chars"))
	free_text.text_submitted.connect(_on_free_text_submitted)
	end_turn = %EndTurn
	end_turn.pressed.connect(_on_end_turn)

## Post-conversation court entry (R2): numbers + orders only, speech already
## happened on the conversation stage. Called by GameRoot after the
## conversation scene finishes (see game_root.gd's _on_conversation_finished).
func enter_court(report: TickReport) -> void:
	_refresh_card()
	_render_suggestions(report)

func _refresh_card() -> void:
	if Game.state != null:
		card.show_values(Game.state)

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
