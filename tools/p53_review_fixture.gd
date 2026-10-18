extends "res://tools/snapshot_screen.gd"
## Real-window review fixture; run with the scratch runner and --screen root.
## Foreign consent is supplied explicitly by this fixture, not by production UI.
var _review_own := ""
var _review_enemy := ""
var _review_person := ""
var _review_batch := ""
var _review_price := 0
var _review_dir := ""
var _review_history := ""
var _review_population := 0
var _review_available := 0
var _review_origin := ""
var _review_character: Character
var _review_preproposal: GameState

func _process(delta: float) -> void:
	super._process(delta)
	if _root == null or not _root.overlays_are_ready(): return
	match _frames:
		20:
			_review_dir = _out.get_base_dir()
			_stage_review()
			_root.open_prisoners()
		25: _focus_review(false)
		30: _review_shot("01-held")
		31: _review_variant(_root._prisoner_panel, true)
		33: _review_shot("01-held-roomier")
		34: _review_variant(_root._prisoner_panel, false)
		35:
			_propose_review()
			_root.open_prisoners()
		40: _focus_review(true)
		45: _review_shot("02-proposed")
		50:
			print("P53 FIXTURE ONLY: explicitly supplying foreign consent through PrisonerDisposition.respond")
			_checked(PrisonerDisposition.respond(Game.data, Game.state, "p53-review-ransom", _review_enemy, true))
			_root.open_prisoners()
		55: _focus_review(true)
		60: _review_shot("03-consented")
		65:
			_fulfill_review()
			_root.open_prisoners()
		70: _focus_review(true)
		75: _review_shot("04-fulfilled")
		76: _review_variant(_root._prisoner_panel, true)
		78: _review_shot("04-fulfilled-roomier")
		79: _review_variant(_root._prisoner_panel, false)
		80:
			_root._prisoner_panel.hide()
			_root.open_battle_reports()
		90: _review_shot("05-report")
		91: _review_variant(_root._battle_report_panel, true)
		93: _review_shot("05-report-roomier")
		94: _review_variant(_root._battle_report_panel, false)
		95:
			_root._battle_report_panel.hide()
			var before := JSON.stringify(Game.state.to_dict())
			_root._open_character_record(_review_person)
			assert(Game.state.characters[_review_person] == _review_character)
			assert(JSON.stringify(Game.state.to_dict()) == before)
		105: _review_shot("06-original-dossier")
		110:
			_check_recruitment_after_promise()
			_check_production_lifecycle()

func _checked(result: Dictionary) -> void:
	assert(not result.has("error"), str(result))

func _review_shot(label: String) -> void:
	assert(_save_shot(_review_dir.path_join(label + ".png")) == OK)

func _review_variant(overlay: Control, wider: bool) -> void:
	# Review-only bracket; the selected look must be authored through the editor.
	var panel: Control = overlay.get_node("Panel")
	var direction := 1 if wider else -1
	panel.offset_left -= 36 * direction
	panel.offset_right += 36 * direction
	panel.offset_top -= 12 * direction
	panel.offset_bottom += 12 * direction

func _focus_review(agreement: bool) -> void:
	var panel: PrisonerPanel = _root._prisoner_panel
	var picker: OptionButton = panel.get_node("%Batch")
	for i: int in picker.item_count:
		if String(picker.get_item_metadata(i).get("id", "")) == _review_batch:
			picker.select(i)
			panel._batch_selected(i)
	var scroll: ScrollContainer = panel.get_node("Panel/Body/Scroll")
	if agreement:
		scroll.ensure_control_visible(panel.get_node("%ProposalDetails"))
	else:
		scroll.scroll_vertical = 0

func _cohort(code: String, id: String, count: int, person := "") -> void:
	Game.state.military_rosters[code].cohort_ids.append(id)
	Game.state.military_cohorts[id] = {"id": id, "unit_code": code, "stage": "active",
		"source_province": _review_origin, "source_population_field": "rural_population",
		"identity": "commoner" if person == "" else "noble", "person_id": person,
		"family_name": "" if person == "" else Game.state.characters[person].family_name,
		"initial": count, "fit": count, "wounded": 0, "dead": 0, "captured_current": 0, "released": 0}

func _stage_review() -> void:
	var own: Array = Game.state.regiments.keys()
	own.sort()
	own = own.filter(func(code: String) -> bool: return not ArmySystem.is_naval(Game.data, Game.state, code))
	var foes: Array = Game.state.foes.keys()
	foes.sort()
	foes = foes.filter(func(code: String) -> bool: return not ArmySystem.is_naval(Game.data, Game.state, code))
	assert(not own.is_empty() and foes.size() >= 2, "Review fixture needs one own and two opposing land units")
	_review_own = String(own[0])
	var enemy_code := String(foes[0])
	var other := String(foes[1])
	_review_enemy = ArmySystem.realm_of(Game.data, enemy_code, Game.state)
	var towns := Game.data.burgs.keys()
	towns.sort()
	for code: String in towns:
		var province := String(Game.data.burgs[code].province_code)
		if ArmyGround.holds(Game.data, Game.state, Game.data.resolve_realm("player_realm"), code) and MilitaryPopulation.available(Game.data, Game.state, province, "rural_population") > 2000:
			_review_origin = province
			break
	assert(_review_origin != "", "Fixture needs a held origin with an eligible civilian pool")
	var people := Game.state.characters.keys()
	people.sort()
	var commander := String(Game.state.military_rosters[enemy_code].get("commander_id", ""))
	if commander in people:
		people.erase(commander)
		people.push_front(commander)
	for id: String in people:
		var person: Character = Game.state.characters[id]
		if person.kingdom == _review_enemy and person.category == "officer" and not person.traits.has("crowned_head"):
			_review_person = id
			_review_character = person
			break
	assert(_review_person != "", "Review needs an original opposing officer, never a crowned head")
	for code: String in [_review_own, enemy_code]:
		for id: String in Game.state.military_rosters[code].cohort_ids:
			Game.state.military_cohorts.erase(id)
		Game.state.military_rosters[code].cohort_ids = []
	_cohort(_review_own, "p53-review-own", 600)
	_cohort(enemy_code, "p53-review-common", 99)
	_cohort(enemy_code, "p53-review-named", 1, _review_person)
	var at: Dictionary = Game.state.regiments[_review_own]
	for code: String in [enemy_code, other]:
		var unit: Dictionary = Game.state.foes[code]
		unit.x_m = int(at.x_m) + 100
		unit.y_m = int(at.y_m)
	Game.state.king_state.x_m = int(at.x_m)
	Game.state.king_state.y_m = int(at.y_m)
	var battle := {"id": 530053, "att": [_review_own], "def": [enemy_code, other],
		"rounds": 2, "start_day": Game.state.absolute_day(), "place_x_m": int(at.x_m),
		"place_y_m": int(at.y_m), "town": "", "parley": {"agreed": {"surrender": {"policy": "accept"}}}}
	Game.state.battles.append(battle)
	BattleReport.enroll(Game.state, battle, _review_own, "att")
	BattleReport.enroll(Game.state, battle, enemy_code, "def")
	_checked(MilitaryRoster.transition(Game.data, Game.state, "p53-review-losses", [
		{"cohort_id": "p53-review-own", "from": "fit", "to": "wounded", "count": 70},
		{"cohort_id": "p53-review-own", "from": "fit", "to": "dead", "count": 40}], "Review fixture: authored battlefield losses"))
	_checked(PrisonerSystem.capture(Game.data, Game.state, {"capture_id": "p53-review-intercepted", "battle_id": 530053,
		"participants": {other: 1}, "reason": "Review fixture: sixty intercepted survivors",
		"changes": [{"cohort_id": "p53-review-own", "from": "fit", "to": "captured_current", "count": 60}]}))
	# The second enemy keeps its sixty captives; only the named commander's unit surrenders.
	battle.def = [enemy_code]
	var surrender := BattleOrders._surrender(Game.data, Game.state, battle, "def", "p53-review-surrender")
	_checked(surrender)
	assert(surrender.get("accepted", false))
	battle.def = [other]
	battle["report_outcome"] = {"result": "surrender", "reason": "Review fixture: accepted surrender"}
	var record := BattleReport.snapshot(Game.data, Game.state, 530053)
	assert(record.personnel.att == {"participants":600,"fit":430,"wounded":70,"dead":40,"captured":60,"released":0})
	_review_history = JSON.stringify(record)
	var payload := MissiveWriter.king_report_payload(Game.data, Game.state, [{"kind":"end", "rounds":2,
		"battle_id":530053,"why":"surrender","winner":"att","att":[_review_own],"def":[enemy_code],
		"town":"","place_x_m":int(at.x_m),"place_y_m":int(at.y_m)}])
	payload.merge({"battle_id":530053,"day":Game.state.absolute_day()})
	BattleEvents.receive_report(Game.state, payload)
	for id: String in Game.state.prisoner_batches:
		if _review_person in Game.state.prisoner_batches[id].named_ids:
			_review_batch = id
	assert(_review_batch != "")
	var price_request := PrisonerDisposition._normalize({"id":"p53-price-reference", "kind":"ransom", "money":1,
		"batches":[{"batch_id":_review_batch,"count":1,"wounded_count":0,"named_ids":[_review_person]}],
		"parties":{"proposer":Game.data.resolve_realm("player_realm"),"payer":_review_enemy},
		"terms":{},"reason":"Review fixture: use existing named ransom reference"})
	_checked(price_request)
	var inspected := PrisonerDisposition._inspect(Game.data, Game.state, price_request)
	_checked(inspected)
	var valuation := PrisonerDisposition._valuation(Game.data, Game.state, price_request, inspected)
	_checked(valuation)
	_review_price = mini(50, int(valuation.affordable_gold))
	assert(_review_price > 0 and _review_price <= int(valuation.asking_gold))
	print("P53 OFFICER CHECK: %s category=%s crowned_head=false; offer=%d gold <= existing asking=%d gold" % [_review_person, _review_character.category, _review_price, int(valuation.asking_gold)])
	_review_population = int(WorldLedger.value_of(Game.data, Game.state, MilitaryPopulation.path(_review_origin, "rural_population")))
	_review_available = MilitaryPopulation.available(Game.data, Game.state, _review_origin, "rural_population")
	_review_preproposal = GameState.from_dict(Game.state.to_dict(), false)
	print("P53 CHECK: surrendered named original %s; own accounting 600 = 430 fit + 70 wounded + 40 dead + 60 captured" % _review_person)

func _propose_review() -> void:
	_checked(PrisonerDisposition.propose(Game.data, Game.state, {"id":"p53-review-ransom", "kind":"ransom",
		"batches":[{"batch_id":_review_batch,"count":1,"wounded_count":0,"named_ids":[_review_person]}],
		"money":_review_price,"parties":{"proposer":Game.data.resolve_realm("player_realm"),"payer":_review_enemy},
		"terms":{"no_fighting_until_day":Game.state.absolute_day()+30}, "reason":"Review fixture: agreed noble ransom and promise"}))
	assert(PrisonerDisposition.settle(Game.data, Game.state, "p53-review-ransom").has("error"))

func _fulfill_review() -> void:
	var result := PrisonerDisposition.settle(Game.data, Game.state, "p53-review-ransom")
	_checked(result)
	assert(result.released == 1 and result.civilians[0].civilian)
	var before := JSON.stringify(Game.state.to_dict())
	assert(PrisonerDisposition.settle(Game.data, Game.state, "p53-review-ransom") == result)
	assert(JSON.stringify(Game.state.to_dict()) == before)
	assert(JSON.stringify(BattleReport.snapshot(Game.data, Game.state, 530053)) == _review_history)
	assert(int(WorldLedger.value_of(Game.data, Game.state, MilitaryPopulation.path(_review_origin, "rural_population"))) == _review_population)
	assert(Game.state.military_cohorts["p53-review-named"].released == 1)
	assert(MilitaryPopulation.available(Game.data, Game.state, _review_origin, "rural_population") == _review_available, "Civilian promise delays recruitment eligibility")
	assert(Game.state.characters[_review_person] == _review_character)
	print("P53 CHECK: fulfilled once; original person preserved; civilian released+1, promise delays recruitment; population unchanged; historical 600 frozen")

func _check_recruitment_after_promise() -> void:
	# A copied-state expiry check preserves the live screenshot's date and dossier.
	var candidate := GameState.from_dict(Game.state.to_dict(), false)
	candidate.tick = maxi(candidate.tick, 1) + 2
	assert(MilitaryPopulation.available(Game.data, candidate, _review_origin, "rural_population") == _review_available + 1)
	var towns := Game.data.burgs.keys()
	towns.sort()
	var town := ""
	for code: String in towns:
		if String(Game.data.burgs[code].province_code) == _review_origin and ArmyGround.holds(Game.data, candidate, Game.data.resolve_realm("player_realm"), code):
			town = code
			break
	assert(town != "", "Released civilian source needs a held assembly town")
	var officers := RecruitmentSystem.available_commanders(Game.data, candidate, "infantry")
	assert(not officers.is_empty(), "Fixture needs an eligible original infantry commander")
	var before := MilitaryPopulation.available(Game.data, candidate, _review_origin, "rural_population")
	var recruits := ceili(1000.0 / Game.data.bal("army_noble_cap_permille"))
	var result := RecruitmentSystem.recruit(Game.data, candidate, {"request_id":"p53-review-recruit", "mode":"new", "arm":"infantry",
		"total":recruits,"source_province":_review_origin,"source_population_field":"rural_population","assembly_town":town,
		"noble_permille":0,"commander_id":officers[0]})
	_checked(result)
	assert(result.status == "assembling")
	assert(MilitaryPopulation.available(Game.data, candidate, _review_origin, "rural_population") == before - recruits)
	print("P53 CHECK: copied-state promise expiry restores one eligible civilian; paid RecruitmentSystem project reserves %d from the civilian pool; live state unchanged" % recruits)

func _check_production_lifecycle() -> void:
	# Isolated state and temporarily shortened fixture geography; all letters ride.
	var candidate := GameState.from_dict(_review_preproposal.to_dict(), false)
	var routes: Dictionary = Game.data.routes
	var rivers: Dictionary = Game.data.rivers
	var capital := String(Game.data.kingdoms[_review_enemy].capital_burg)
	var town: Dictionary = Game.data.burgs[capital]
	var old_x: Variant = town.x
	var old_y: Variant = town.y
	var radius: Variant = Game.data.balance.king_command_radius_m
	Game.data.routes = {}
	Game.data.rivers = {}
	Game.data.balance.king_command_radius_m = 1
	RoadGraph.forget()
	var holder: Dictionary = candidate.regiments[_review_own]
	candidate.king_state.x_m = int(holder.x_m) + 10000
	candidate.king_state.y_m = int(holder.y_m)
	var near_capital := ArmySystem.metres_to_pack(Game.data, KingSystem.position(candidate) + Vector2i(1000, 0))
	town.x = near_capital.x
	town.y = near_capital.y
	var request := {"id":"p53-production-ransom", "kind":"ransom", "money":_review_price,
		"batches":[{"batch_id":_review_batch,"count":1,"wounded_count":0,"named_ids":[_review_person]}],
		"parties":{"proposer":Game.data.resolve_realm("player_realm"),"payer":_review_enemy},
		"terms":{},"reason":"Production demonstration: lawful noble ransom"}
	var actions := ActionSystem.new(Game.data)
	var issued := actions.execute(ActionRequest.make("PRISONER_PROPOSE", request), candidate)
	assert(issued.get("ok", false), str(issued))
	assert(not candidate.couriers.is_empty())
	assert(not PrisonerCommunications.projection(candidate, request.id).consents.has(_review_enemy))
	var offer_days := _ride_review_until(candidate, request.id, "accepted")
	assert(offer_days >= 2, "Foreign consent must arrive on the returning rider")
	var settle_request := ActionRequest.make("PRISONER_SETTLE", {"proposal_id":request.id})
	var sent := actions.execute(settle_request, candidate)
	assert(sent.get("ok", false), str(sent))
	assert(candidate.military_cohorts["p53-review-named"].released == 0)
	assert(PrisonerCommunications.projection(candidate, request.id).result.is_empty())
	var receipt_days := _ride_review_until(candidate, request.id, "fulfilled")
	assert(receipt_days >= 2, "Remote execution and receipt require separate delivery legs")
	assert(candidate.military_cohorts["p53-review-named"].released == 1)
	assert(not PrisonerCommunications.projection(candidate, request.id).result.is_empty())
	var before := JSON.stringify(candidate.to_dict())
	assert(actions.execute(settle_request, candidate) == sent)
	assert(JSON.stringify(candidate.to_dict()) == before)
	assert(JSON.stringify(BattleReport.snapshot(Game.data, candidate, 530053)) == _review_history)
	Game.data.routes = routes
	Game.data.rivers = rivers
	Game.data.balance.king_command_radius_m = radius
	town.x = old_x
	town.y = old_y
	RoadGraph.forget()
	print("P53 PRODUCTION CHECK: ActionSystem offer/return consent %d day-ends; remote fulfillment/return receipt %d day-ends; released once, replay inert, history frozen. Actual CourierSystem.ride_day; shortened fixture geography; no manual respond or receive_report." % [offer_days, receipt_days])

func _ride_review_until(state: GameState, id: String, status: String) -> int:
	for i: int in 120:
		CourierSystem.ride_day(Game.data, state)
		state.day += 1
		if state.day > Calendar.DAYS_PER_TICK:
			state.day = 1
			state.tick += 1
		if PrisonerCommunications.projection(state, id).status == status:
			return i + 1
	assert(false, "Production prisoner delivery did not reach " + status)
	return -1
