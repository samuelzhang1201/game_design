extends Node
## Autoload "Game": owns the sim; UI talks only to this.

signal report_ready(report: TickReport)
signal battle_decision_requested(decision: Dictionary)
## A letter was read on the Missive board (final review M7): the read flag
## is saved state, so it changes only here.
signal missive_read(id: int)
## Letters were marked seen (the board shown, a spy's report opened): the
## MISSIVE tab's count is redrawn from MissiveLog.unseen.
signal missives_seen
## Emitted after any mutation of Game.state (orders, event choices, court
## reactions, tick advance, load). UI that mirrors live state (e.g. the
## TopBar) subscribes to this instead of refreshing at call sites.
signal state_changed
## The WAR ROOM's plans changed (WarPlans): only the room's plan layer
## listens, so a crayon stroke refreshes nothing else (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §1.1).
signal plans_changed
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
## The clock was held still, or let go (the LEDGER: owner 2026-10-01).
signal clock_held_changed(held: bool)

var data: DataRepository
var state: GameState
var engine: TickEngine
var current_report: TickReport
var client: OpenAIClient
var voicer: Voicer
## Makes a new campaign from (data, seed): GameState.new_campaign unless the
## test suite hands its cached copier here (tests/pre_run.gd, tests/suite_data.gd).
var campaign_maker: Callable = GameState.new_campaign
## Why the last load_campaign failed, in the player's words ("" after a good one).
var load_error := ""

func _ready() -> void:
	if OS.get_environment("CC_FORCE_OFFLINE") != "1":
		UserDirMigration.copy_missing(UserDirMigration.legacy_dir(), OS.get_user_data_dir(),
			PackedStringArray(["save.json", "config.json", "settings.cfg"]))
	data = DataRepository.load_all("res://data")
	assert(data != null, "data load failed: " + DataRepository.last_error)

func start_campaign(seed_value: int = 42) -> bool:
	var candidate: GameState = campaign_maker.call(data, seed_value)
	if candidate == null:
		load_error = GameState.campaign_error
		return false
	_reset_llm()
	release_clock_holds()  # a reign never begins held (each hold is its screen's viewing's)
	state = candidate
	engine = TickEngine.new(data)
	load_error = ""
	return true

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
	if speed > 0 and clock_held:
		return  # held still: nothing starts it (the play buttons, Space)
	if speed > 0:
		_resume_speed = speed
	if clock_speed == speed:
		return
	clock_speed = speed
	clock_changed.emit(speed)

## The speed the Space bar resumes at: the last one that ran (1 before any).
var _resume_speed := 1

## Space in play (owner 2026-09-30: 空格键可以暂停或者继续游戏): a running
## clock stops, a stopped one runs again at the speed it last ran.
func toggle_clock() -> void:
	set_clock_speed(0 if clock_speed > 0 else _resume_speed)


## Whether the clock is held still: while the LEDGER is open (owner
## 2026-10-01: entering the LEDGER stops the clock, which stays stopped while
## it is open — the chart reflects the present) or the WAR ROOM (owner
## 2026-10-02: 进入war room时间也一直是暂停的，无法继续，直到下达命令并退出),
## set_clock_speed refuses to start it, whoever asks.
var clock_held := false
## Who holds it ("ledger", "war_room"): each lets go of its own hold only, so
## the clock runs again (when the player starts it) once NO holder is left.
var _clock_holders: Dictionary = {}

## Holds the clock still (stopping it) or lets it go — stopped: letting go
## starts nothing, the player does (owner 2026-10-01). `who` names the holder.
func hold_clock(on: bool, who := "ledger") -> void:
	if on:
		set_clock_speed(0)
		_clock_holders[who] = true
	else:
		_clock_holders.erase(who)
	_set_held(not _clock_holders.is_empty())

## Every hold let go (a new reign, a restart): nothing is open any more.
func release_clock_holds() -> void:
	_clock_holders.clear()
	_set_held(false)

## Whether `who` holds the clock now (tests, tools).
func holds_clock(who: String) -> bool:
	return _clock_holders.has(who)

func _set_held(held: bool) -> void:
	if clock_held == held:
		return
	clock_held = held
	clock_held_changed.emit(held)


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
## {ticked, finished: [{cell, building}], arrived, couriers, supply (the
## supply lines' events, TickEngine.day_supply)} and, on the tick, idled:
## the buildings newly idle for want of inputs (M5).
func advance_day() -> Dictionary:
	var ended := state.absolute_day()
	var result := engine.resolve_day(state)
	if result["status"] == "error":
		hold_clock(true, "simulation_error")
		publish_news("The day's resolution stopped: " + String(result["error"]))
		state_changed.emit()
		return {"status": "error", "error": result["error"], "ticked": false,
			"ended": ended, "finished": [], "arrived": [], "couriers": [], "supply": [], "raids": []}
	if result["status"] == "blocked":
		_sync_battle_decision()
		state_changed.emit()
		return {"status": "blocked", "decision": result["decision"], "ticked": false,
			"ended": ended, "finished": [], "arrived": [], "couriers": [], "supply": [], "raids": []}
	if bool(result["ticked"]):
		_publish_tick(result["report"])
	state_changed.emit()
	var journal: Dictionary = result["journal"]
	return {"status": "complete", "ticked": result["ticked"], "finished": journal["works"],
		"arrived": journal["arrivals"], "couriers": journal["couriers"], "ended": result["ended"],
		"missives_from": journal["missive_start"],
		"supply": journal["supply"], "raids": journal["raids"],
		"idled": engine.newly_idle if result["ticked"] else [],
		"hazards": engine.month_hazard_news if result["ticked"] else []}

func next_tick() -> TickReport:
	var report := engine.advance(state)
	if report == null:
		_sync_battle_decision()
		state_changed.emit()
		return null
	_publish_tick(report)
	state_changed.emit()
	return report

func _publish_tick(report: TickReport) -> void:
	_prompts_this_tick = 0
	current_report = report
	report_ready.emit(current_report)

func resolve_battle_decision(token: String, choice: String) -> Dictionary:
	if state == null or engine == null:
		return {"status": "stale"}
	var result := engine.resolve_decision(state, token, choice)
	if result["status"] == "accepted":
		hold_clock(false, "battle_decision")
		state_changed.emit()
	return result

func _sync_battle_decision() -> void:
	var pending: Dictionary = state.day_resolution.get("pending_decision", {})
	var waiting := not pending.is_empty() and String(pending.get("selected", "")) == ""
	hold_clock(waiting, "battle_decision")
	if waiting:
		battle_decision_requested.emit(pending.duplicate(true))

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


## The WAR ROOM's drafts (spec 2026-10-02-war-room-v2 §3): pencilled, not
## sent. Game is their only writer.
func plant_draft(code: String, order: String, dest_px: Vector2, waypoints: Array = [], carry := -1,
		supply_town := "", supply_rate := 0, hold: Dictionary = {}, front := "") -> void:
	WarDrafts.plant(data, state, code, order, dest_px, waypoints, carry, supply_town, supply_rate, hold, front)
	state_changed.emit()


## A blue front drawn for `codes` (spec 2026-10-11-war-room-front-line-design
## §1): each regiment's post along the stroke `stroke_id` (WarFront.assign, by
## its place along the line) becomes its draft — a march to the post holding
## `hold` facing the teeth on arrival, or a halt with the hold where it
## already stands (within 1 pack px). {planted: [codes], refused: {code: why}}.
func plant_front(stroke_id: String, codes: Array) -> Dictionary:
	var out := {"planted": [], "refused": {}}
	if state == null:
		return out
	var stroke: Dictionary = state.war_plans[WarPlans.STROKES].get(stroke_id, {})
	if stroke.is_empty():
		return out
	var positions := {}
	for c: Variant in codes:
		var reg := ArmySystem.regiment(data, String(c), state)
		positions[String(c)] = Vector2(ArmySystem.pack_to_metres(data, ArmySystem.position_of(data, state, reg)))
	for a: Dictionary in WarFront.assign(data, stroke, codes, positions):
		var code := String(a["code"])
		var px := ArmySystem.metres_to_pack(data, a["dest_m"])
		var hold := {"stance": WarFront.HOLD_STANCE, "facing": int(a["facing_deg"])}
		var here := ArmySystem.position_of(data, state, ArmySystem.regiment(data, code, state))
		if here.distance_to(px) <= 1.0:
			WarDrafts.plant(data, state, code, WarDrafts.GARRISON, px, [], -1, "", 0, hold, stroke_id)
			out["planted"].append(code)
			continue
		var why := engine.actions.validate_place(ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": px.x, "y": px.y}), state)
		if why != "":
			out["refused"][code] = why
			continue
		WarDrafts.plant(data, state, code, WarDrafts.MARCH, px, [], -1, "", 0, hold, stroke_id)
		out["planted"].append(code)
	if not out["planted"].is_empty():
		state_changed.emit()
	return out


func restore_drafts(drafts: Dictionary) -> void:
	WarDrafts.restore(state, drafts)
	state_changed.emit()


func strike_draft(code: String) -> void:
	if WarDrafts.strike(state, code):
		state_changed.emit()


func discard_drafts() -> void:
	if WarDrafts.any(state):
		state.war_drafts.clear()
		state_changed.emit()


## The WAR ROOM's plans (spec 2026-10-07-war-room-annotations-and-planning-
## pieces): the player's own paper. Game is their only writer; each write that
## lands says plans_changed.
func _plans(done: Variant) -> Variant:
	if landed(done):
		plans_changed.emit()
	return done


## Whether a plans write landed: true, a new id, or a count above 0.
static func landed(done: Variant) -> bool:
	return (done is bool and done) or (done is String and done != "") or (done is int and done > 0)


func place_plan_piece(arm: String, heads: int, side: String, at: Vector2, facing_deg: int) -> String:
	return _plans(WarPlans.place(data, state, arm, heads, side, at, facing_deg))


func move_plan_piece(id: String, to: Vector2, facing_deg: int) -> bool:
	return _plans(WarPlans.move_piece(data, state, id, to, facing_deg))


func edit_plan_piece(id: String, arm: String, heads: int, side: String) -> bool:
	return _plans(WarPlans.edit_piece(data, state, id, arm, heads, side))


func remove_plan(id: String) -> bool:
	return _plans(WarPlans.remove(state, id))


func clear_plans(kind: String, rect: Rect2) -> int:
	return _plans(WarPlans.clear(data, state, kind, rect))


func draw_plan(kind: String, colour: String, pts: PackedVector2Array, r_px: float, plan_name: String, dashed: bool,
		flip := -1, of := "") -> String:
	return _plans(WarPlans.draw(data, state, kind, colour, pts, r_px, plan_name, dashed, flip, of))


func reshape_plan(id: String, pts: PackedVector2Array, r_px := -1.0) -> bool:
	return _plans(WarPlans.reshape(data, state, id, pts, r_px))


func shift_plan(id: String, offset: Vector2) -> bool:
	return _plans(WarPlans.shift(data, state, id, offset))


func restyle_plan(id: String, changes: Dictionary) -> bool:
	return _plans(WarPlans.restyle(data, state, id, changes))


## The room's undo: a snapshot of war_plans put back.
func restore_plans(snapshot: Dictionary) -> void:
	WarPlans.restore(state, snapshot)
	plans_changed.emit()


## The resolutions as they would be sealed now (spec §3.3): each draft's
## line — who, the order, where to, days, its gold — and why it would be
## refused. The gold is MEASURED, not summed from tables: the orders run in
## code order on ONE quiet copy of the state (the order's own cost, its
## always-rows and its courier's fee, whatever they are), each line spending
## before the next is weighed, so the review and the seal agree on a paused
## clock; a line validate refuses (the chest included: _validate_army counts
## the order and its courier) spends nothing.
func review_drafts() -> Dictionary:
	var lines: Array = []
	var total := 0
	var sim := GameState.from_dict(state.to_dict(), false)
	for code: String in WarDrafts.codes(state):
		var d := WarDrafts.of(state, code)
		# a march draft may carry a new load: its order runs first (spec
		# 2026-10-07-march-waypoints ruling 8), the line its gold and the march's
		var reqs := WarDrafts.requests_from(data, state, code, d)
		var req: ActionRequest = reqs.back()
		for r: ActionRequest in reqs:   # the march, when a front's stance rides behind it
			if r.action_code == "ARMY_MARCH":
				req = r
		var reg := ArmySystem.regiment(data, code, state)
		# each order weighed after the one before it has spent; a draft of two
		# runs on its own copy, kept only when both pass (nothing half-spent)
		var trial := sim if reqs.size() == 1 else GameState.from_dict(sim.to_dict(), false)
		var chest := float(trial.metrics.get("treasury", 0.0))
		var refusal := ""
		trial.war_drafts.erase(code)
		for r: ActionRequest in reqs:
			refusal = engine.actions.validate(r, trial)
			if refusal != "":
				break
			engine.actions.execute(r, trial)
		var gold := 0
		if refusal == "":
			sim = trial
			gold = int(round(chest - float(sim.metrics.get("treasury", 0.0))))
			total += gold
		var to := "where it stands"
		var days := 0
		if req.action_code == "ARMY_MARCH":
			var dest := WarDrafts.dest_px(data, d)
			to = Intel.place_label(data, state, dest)
			days = CourierSystem.arrival_days(data, state, code, dest, Vector2(-1, -1), -1,
				Array(WarDrafts.waypoints_px(data, d)), int(d.get("carry_days", -1)))   # ride + march
		var town := String(d.get("supply_town", ""))
		lines.append({"code": code, "label": String(reg.get("label", code)), "order": String(d["order"]),
			"to": to, "days": days, "gold": gold, "refusal": refusal,
			"supply": String((data.burgs.get(town, {}) as Dictionary).get("label", town)) if town != "" else "",
			"hold": WarFront.compass_words(int((d["hold"] as Dictionary).get("facing", 0))) if d.has("hold") else ""})
	return {"lines": lines, "total": total}


## Seal and send (spec §3.3): every draft the review passes runs through
## try_execute as its real order, in code order — a courier and a fee each;
## one the review refuses stays a draft with its reason. A draft is struck
## BEFORE its order runs, so ActionSystem's set-aside note never fires for its
## own deploy.
func deploy_drafts() -> Dictionary:
	var sent: Array = []
	var refused: Dictionary = {}
	for line: Dictionary in review_drafts()["lines"]:
		var code := String(line["code"])
		var d := WarDrafts.of(state, code)
		var why := String(line["refusal"])
		if why == "":
			state.war_drafts.erase(code)
			var out := {}
			for r: ActionRequest in WarDrafts.requests_from(data, state, code, d):
				out = try_execute(r)
				if not bool(out.get("ok", false)):
					break
			if bool(out.get("ok", false)):
				sent.append(code)
				continue
			why = String(out.get("error", ""))
		d["refused"] = why
		state.war_drafts[code] = d
		refused[code] = why
	state_changed.emit()
	return {"sent": sent, "refused": refused}

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
## The absolute day a headline published now is dated (NewsTicker): the day
## that just ENDED while GameRoot tells of its end (news_dated_to), else the
## day now running (owner 2026-10-06: 顶栏日期滞后一天).
var _news_day := -1

func news_dated_to(abs_day: int) -> void:
	_news_day = abs_day

func news_day() -> int:
	if _news_day > 0:
		return _news_day
	return state.absolute_day() if state != null else 0

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

## Mark letters SEEN (owner 2026-10-10): all of them when a Missive board is
## shown (or open as more land), one when a spy's report opens in its dialog.
func mark_missives_seen(id := -1) -> void:
	if state == null:
		return
	if MissiveLog.mark_seen(state, id):
		missives_seen.emit()

func save_campaign(path: String = "") -> bool:
	path = save_path if path == "" else path
	return SaveLoad.save_game(state, path)

func load_campaign(path: String = "") -> bool:
	path = save_path if path == "" else path
	var loaded := SaveLoad.load_game(path)
	if loaded == null:
		load_error = "The army's organisation has changed since this realm was saved; begin a new reign." \
			if SaveLoad.last_error == "outdated" else "No saved realm found."
		return false
	# The save names its world. Swap the pack in before the state goes live,
	# and refuse rather than silently drop the player into a different map
	# than the one they saved in. Pre-map_id saves ("") keep the default.
	if loaded.map_id != "" and loaded.map_id != data.map_id:
		if not data.load_map(loaded.map_id):
			push_error("load_campaign: save needs map '%s' which is not installed"
				% loaded.map_id)
			load_error = "No saved realm found."
			return false
	var personnel := MilitaryBootstrap.migrate(data, loaded)
	if personnel.has("error"):
		load_error = "Cannot restore the army's personnel: " + String(personnel["error"])
		return false
	var organization := MilitaryReorganization.reconcile(data, loaded)
	if organization.get("status", "error") == "error":
		load_error = "Cannot restore the army's organization: " + String(organization.get("error", "invalid organization"))
		return false
	load_error = ""
	hold_clock(false, "simulation_error")
	state = loaded
	# A save from before the wealth tiers were state computes them once, from
	# the state it loaded (Ruling 15).
	Intel.ensure_wealth_tiers(data, state)
	ArmySystem.ensure(data, state)  # a save from before the carried load: its load and cap now
	EnemyAi.ensure_deployments(data, state)  # restore actual siege deployment without replaying the day
	TownStores.ensure(data, state)  # a save from before the town stores
	Hazards.ensure(data, state)
	LawSystem.ensure(data, state)  # a save from before the laws
	DevelopmentSystem.ensure(data, state)  # a save from before the development axes
	_sync_battle_decision()
	state_changed.emit()
	return true

## Restart flow (R12): return to MENU with a clean sim + LLM seam. Called by
## GameRoot's global R handler.
func restart() -> void:
	set_clock_speed(0)
	release_clock_holds()
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
