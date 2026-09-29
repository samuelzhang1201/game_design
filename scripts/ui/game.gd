extends Node
## Autoload "Game": owns the sim; UI talks only to this.

signal report_ready(report: TickReport)
## A letter was read on the Missive board (final review M7): the read flag
## is saved state, so it changes only here.
signal missive_read(id: int)
## Emitted after any mutation of Game.state (orders, event choices, court
## reactions, tick advance, load). UI that mirrors live state (e.g. the
## TopBar) subscribes to this instead of refreshing at call sites.
signal state_changed
## Cross-cutting UI signal: the TopBar's MENU button asks for the pause
## menu; GameRoot (the flow owner) listens and shows it.
@warning_ignore("unused_signal")
signal menu_requested
## A chronicle headline for the persistent bottom news strip (user request
## 2026-08-31). Emitted via publish_news — GameRoot feeds it as works
## progress and the month closes; the NewsTicker (GameRoot-owned) displays it.
signal news_published(text: String)
## The clock's speed changed (owner 2026-09-13): 0 paused, 1, 2 or 4.
signal clock_changed(speed: int)

var data: DataRepository
var state: GameState
var engine: TickEngine
var current_report: TickReport
var client: OpenAIClient
var voicer: Voicer

func _ready() -> void:
	data = DataRepository.load_all("res://data")
	assert(data != null, "data load failed: " + DataRepository.last_error)

## Set by the main menu's character creation before start_requested fires;
## applied to the fresh campaign, then kept in the save via GameState.
var player_setup: Dictionary = {}

func start_campaign(seed_value: int = 42) -> void:
	_reset_llm()
	state = GameState.new_campaign(data, seed_value)
	if not player_setup.is_empty():
		state.apply_player_setup(player_setup)
	engine = TickEngine.new(data)

## The clock (owner 2026-09-13): 0 is paused, 1 a day per time_day_seconds,
## 2 and 4 that many times faster. Only GameRoot's _process reads it, on
## the court; the simulation never sees a second.
var clock_speed: int = 0
## The share of the current day already gone, 0..1 — GameRoot's clock writes
## it, the 3D map's sun reads it (owner 2026-09-27: the light turns with the day).
## Presentation only: the simulation never sees it.
var day_progress := 0.0
## Where the pause menu's Save / Load Game keep the campaign. The suite's
## pre-run hook points it into its own directory, so a test pressing Save
## never overwrites the player's save or another running suite's file.
var save_path := "user://save.json"

func set_clock_speed(speed: int) -> void:
	var allowed := [0, 1, int(data.bal("time_speed_fast")), int(data.bal("time_speed_faster"))]
	if not speed in allowed:
		return
	if clock_speed == speed:
		return
	clock_speed = speed
	clock_changed.emit(speed)

## Tools only (tools/map3d/bench.gd, through GameRoot): roll the day back
## to 1 once it passes `day_ceiling`, so a timed run never reaches the
## month's end — a completed month can roll a random event, which stops the
## clock and swaps the screen mid-measurement. Returns whether it rolled
## back. Lives here, not on GameRoot, because only Game writes the state
## (final review, owner 2026-09-18).
func hold_day_before_month_end(day_ceiling: int) -> bool:
	if state == null or state.day <= day_ceiling:
		return false
	state.day = 1
	return true


## One day of the clock (owner 2026-09-13). Works step; when the day is the
## tick's last, the tick itself runs and its report goes out. Returns
## {ticked, finished: [{cell, building}]}.
func advance_day() -> Dictionary:
	if state.day >= Calendar.DAYS_PER_TICK:
		var r := next_tick()
		return {"ticked": true, "finished": r.finished_works, "arrived": engine.day_arrivals,
			"couriers": engine.day_couriers}
	var finished := engine.advance_day(state)
	state_changed.emit()
	return {"ticked": false, "finished": finished, "arrived": engine.day_arrivals,
		"couriers": engine.day_couriers}

func next_tick() -> TickReport:
	_prompts_this_tick = 0
	current_report = engine.advance(state)
	report_ready.emit(current_report)
	state_changed.emit()
	return current_report

func apply_event_choice(choice_id: String) -> Dictionary:
	var out := engine.events.apply_choice(choice_id, state)
	if not out.is_empty():
		state_changed.emit()
	return out

func try_execute(req: ActionRequest) -> Dictionary:
	var err := engine.actions.validate(req, state)
	if err != "":
		return {"ok": false, "error": err, "outcome": null}
	var outcome := engine.actions.execute(req, state)
	state_changed.emit()
	return {"ok": true, "error": "", "outcome": outcome}

## Free movement within the current region (user ruling 2026-08-30: no time
## cost). Returns false (and moves nothing) for an unknown or out-of-region
## location. No tick advances.
func move_to(location_code: String) -> bool:
	if state == null or not LocationSystem.can_move(data, state, location_code):
		return false
	state.current_location = location_code
	state_changed.emit()
	return true

## Routes one headline to whatever is showing news (currently the bottom
## ticker). Presentation-only: no sim state is touched.
func publish_news(text: String) -> void:
	if text.strip_edges() == "":
		return
	news_published.emit(text)

## Mark a letter read (the Missive board's select): state changes go
## through Game, never a screen writing Game.state itself.
func mark_missive_read(id: int) -> void:
	if state == null:
		return
	MissiveLog.mark_read(state, id)
	missive_read.emit(id)

func save_campaign(path: String = "") -> bool:
	path = save_path if path == "" else path
	return SaveLoad.save_game(state, path)

func load_campaign(path: String = "") -> bool:
	path = save_path if path == "" else path
	var loaded := SaveLoad.load_game(path)
	if loaded == null:
		return false
	# The save names its world. Swap the pack in before the state goes live,
	# and refuse rather than silently drop the player into a different map
	# than the one they saved in. Pre-map_id saves ("") keep the default.
	if loaded.map_id != "" and loaded.map_id != data.map_id:
		if not data.load_map(loaded.map_id):
			push_error("load_campaign: save needs map '%s' which is not installed"
				% loaded.map_id)
			return false
	state = loaded
	# A save from before the wealth tiers were state computes them once, from
	# the state it loaded (Ruling 15).
	Intel.ensure_wealth_tiers(data, state)
	state_changed.emit()
	return true

## Restart flow (R12): return to MENU with a clean sim + LLM seam. Called by
## GameRoot's global R handler.
func restart() -> void:
	set_clock_speed(0)
	_reset_llm()
	state = null
	engine = null
	current_report = null
	_prompts_this_tick = 0

func _ensure_llm() -> void:
	if voicer != null:
		return
	client = OpenAIClient.new()
	add_child(client)
	voicer = Voicer.new(client)
	add_child(voicer)

## Tears down any LLM seam (real OpenAIClient, or a test-injected fake — see
## use_client_for_tests) left over from a previous campaign, so a new
## campaign starts with a clean _ensure_llm(). Without this, Game (an
## autoload, so its state outlives any one test) could hold a Voicer wrapping
## a client Node a *previous* test already freed (e.g. via
## add_child_autofree), and the next call that touches the LLM seam
## (submit_free_text, an order) would connect a signal on a freed
## object.
func _reset_llm() -> void:
	if voicer != null:
		voicer.queue_free()
		voicer = null
	if client != null:
		client.queue_free()
		client = null

## Voices a pending event's scene through the Voicer (see Voicer.voice_event).
## UI callers should route through here rather than calling TemplateVoicer
## directly, so a configured key is actually used for mini/flagship events.
func voice_event_scene(ev: Dictionary, cb: Callable) -> void:
	_ensure_llm()
	voicer.voice_event(ev, state, data, cb)

## Test-only seam: swap in a fake client (same signal/method surface as
## OpenAIClient) so tests exercise Voicer's real parsing/validation path
## without a network call. See tests/ui/test_court_screen.gd.
func use_client_for_tests(fake: Node) -> void:
	if voicer != null:
		voicer.queue_free()
	if client != null:
		client.queue_free()
		client = null
	voicer = Voicer.new(fake)
	add_child(voicer)

## Game is an autoload, so it is never freed mid-run — but GUT can tear down
## the SceneTree between full test-suite runs, and any leftover client/voicer
## Nodes must go with it or GUT's ObjectDB leak check at exit fires. Mirrors
## _reset_llm's teardown.
func _exit_tree() -> void:
	if voicer != null:
		voicer.queue_free()
	if client != null:
		client.queue_free()

## LLM parse calls per tick are capped (balance: prompt_calls_per_tick) so a
## player cannot burn unbounded API spend; over-cap orders are refused
## in-fiction without any API call. Clicked buttons remain free and unlimited.
var _prompts_this_tick := 0

## `speaker_hint`: the character the player is literally facing (the
## conversation stage passes its current beat's minister) — used to pick who
## answers conversational text; the court screen passes none and the
## Chancellor, "your primary voice" (council_seats.csv), answers instead.
## `audience`: everyone the words reach — the conversation screen's explicit
## selection, or the whole room when nothing is selected. All of them
## remember hearing it (AgentMemory); exactly one of them answers, so cost
## stays at one call per utterance however many people are listening.
## Empty audience falls back to whoever is at the player's location.
func submit_free_text(text: String, cb: Callable, speaker_hint: String = "",
		audience: Array = []) -> void:
	if _prompts_this_tick >= int(data.bal("prompt_calls_per_tick")):
		cb.call({"ok": false, "executed": [], "rejected": [],
			"error": "the council will hear no more orders this month"})
		return
	_prompts_this_tick += 1
	var heard_by: Array = audience if not audience.is_empty() \
		else LocationSystem.occupants(data, state, state.current_location)
	for id in heard_by:
		AgentMemory.remember(data, state, String(id), "you", text,
			heard_by, state.current_location, state.tick)
	if not heard_by.is_empty():
		state_changed.emit()
	_ensure_llm()
	# One call, two parts (spec 2026-09-09 §4): the engine picks who answers
	# BEFORE the call so the model speaks in one persona; the reply's
	# narrative is printed under that name and its impacts go through the
	# ledger, the actions through ActionSystem, both via OrderPipeline.
	var speaker := _order_speaker(text, speaker_hint, heard_by)
	voicer.order(text, speaker, current_report, state, data,
		func(res: Dictionary):
			if not res["ok"]:
				cb.call({"ok": false, "executed": [], "rejected": [], "error": res["error"]})
				return
			var out := OrderPipeline.apply_order(data, state, engine, res["actions"],
				res["world"], res["court_reaction"], "order")
			state_changed.emit()
			var result := {"ok": true, "executed": out["executed"], "rejected": out["rejected"],
				"error": "", "ledger": out["ledger"], "world_effects": out["world_effects"],
				"world_rejected": out["world_rejected"]}
			var narrative := String(res.get("narrative", ""))
			if _addressed_absent(res["court_reaction"], heard_by):
				# The player named someone who is NOT here (user ruling
				# 2026-08-30: no conversations with the absent): a herald note
				# replaces whatever voice the model used.
				result["reply"] = {"speaker": "Herald", "speaker_id": "", "degraded": true,
					"text": TemplateVoicer.line_for(data, "converse_no_one", [], state.tick)}
			elif narrative != "":
				var reply := {"speaker": _speaker_name(speaker), "speaker_id": speaker,
					"text": narrative, "degraded": false}
				_remember_reply(reply, heard_by)
				result["reply"] = reply
			cb.call(result))

## True when the reply addressed real characters and none of them heard it.
func _addressed_absent(court_reaction: Dictionary, heard_by: Array) -> bool:
	var named := 0
	for id in court_reaction.get("addressed", []):
		if state.characters.has(String(id)) and String(id) != "you":
			named += 1
			if String(id) in heard_by:
				return false
	return named > 0

## A conversational reply is itself words spoken aloud: everyone who heard
## the question heard the answer — the speaker included, so a character
## remembers what they themselves said (review finding 2026-09-01: memory
## recorded only the ruler's voice). Herald fallbacks (speaker_id "") are
## out-of-fiction notes and are not remembered.
func _remember_reply(reply: Dictionary, heard_by: Array) -> void:
	var sid := String(reply.get("speaker_id", ""))
	if sid == "" or not state.characters.has(sid):
		return
	for id in heard_by:
		AgentMemory.remember(data, state, String(id), sid,
			String(reply.get("text", "")), heard_by, state.current_location,
			state.tick)
	state_changed.emit()

func _speaker_name(id: String) -> String:
	return (state.characters[id] as Character).display_name if state.characters.has(id) else "Herald"

## Who answers, chosen BEFORE the call so the model speaks in one persona:
## the character the player faces; else someone present whose name or seat
## the text mentions; else the present holder of the seat whose topics the
## text touches; else the Chancellor if present; else anyone present; else ""
## for the herald. Only someone at the player's location may answer
## (user ruling 2026-08-30: no conversations with the absent).
func _order_speaker(text: String, hint: String, audience: Array) -> String:
	var present: Array = audience if not audience.is_empty() \
		else LocationSystem.occupants(data, state, state.current_location)
	if hint in present:
		return hint
	var lower := text.to_lower()
	for id in present:
		var c: Character = state.characters.get(String(id))
		if c == null or String(id) == "you":
			continue
		for token in c.display_name.split(" ", false):
			if token.length() > 3 and lower.contains(token.to_lower()):
				return String(id)
		if c.seat != "" and lower.contains(c.seat.to_lower()):
			return String(id)
	# A question in a seat's domain goes to that seat's holder when present
	# ("how is my army?" -> the Marshal): council_seats.csv `topics`.
	for seat: String in data.seats:
		var holder := String(state.council.get(seat, ""))
		if holder == "" or not holder in present:
			continue
		for word in String(data.seats[seat].get("topics", "")).split("|", false):
			if _mentions(lower, word):
				return holder
	var chancellor := String(state.council.get("chancellor", ""))
	if chancellor in present:
		return chancellor
	return String(present[0]) if not present.is_empty() else ""

## Whole-word match, so "port" does not fire on "important".
func _mentions(lower: String, word: String) -> bool:
	var at := lower.find(word)
	while at >= 0:
		var before_ok := at == 0 or not _is_word_char(lower.unicode_at(at - 1))
		var end := at + word.length()
		var after_ok := end >= lower.length() or not _is_word_char(lower.unicode_at(end))
		if before_ok and after_ok:
			return true
		at = lower.find(word, at + 1)
	return false

func _is_word_char(c: int) -> bool:
	return (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
