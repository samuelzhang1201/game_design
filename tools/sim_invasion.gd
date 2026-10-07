extends SceneTree
## The prologue's invasion played headless, day by day, for tuning and as a
## demo (spec docs/superpowers/specs/2026-10-07-enemy-ai-and-battle-design.md):
##   Godot --headless --path . -s tools/sim_invasion.gd [-- --map ID --seed N
##         --defence none|weak|strong --days N --walls --bal key=value ...]
## The campaign opens as GameRoot opens it and the clock runs as
## Game.advance_day runs it (the thirtieth day is the tick). On the main host's
## crossing day the player's defence is set on the town it has chosen:
##   none    nothing (every regiment where the pack quartered it);
##   weak    the smallest land regiment garrisons it;
##   strong  the three largest land regiments garrison it.
## --walls gives that town walls and a citadel in this run's copy of the data;
## --bal overrides a balance.csv key for the run. Each day prints the hosts
## (mode, target, lead column in km and its distance to the target), the day's
## battles (start, end, winner), the siege, the raids' take and the crown's
## treasury and contentment moves; a summary closes the run. Engine calls
## only, no 3D, no clock: safe headless.

const SIDE := {"att": "attacker", "def": "defender", "": "none"}


func _init() -> void:
	var map := DataRepository.default_pack_id()
	var seed_value := 11
	var defence := "weak"
	var days := 45
	var walls := false
	var bal := {}
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var next := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--map": map = next
			"--seed": seed_value = int(next)
			"--defence": defence = next
			"--days": days = int(next)
			"--walls": walls = true
			"--bal":
				var kv := next.split("=")
				if kv.size() == 2:
					bal[kv[0]] = float(kv[1])
			_:
				pass
	if not defence in ["none", "weak", "strong"]:
		push_error("sim_invasion: --defence none|weak|strong, not %s" % defence)
		quit(1)
		return
	var repo := DataRepository.load_all("res://data")
	if repo == null or (repo.map_id != map and not repo.load_map(map)):
		push_error("sim_invasion: cannot load pack %s: %s" % [map, DataRepository.last_error])
		quit(1)
		return
	for k: String in bal:
		repo.balance[k] = bal[k]
	var s := GameState.new_campaign(repo, seed_value)
	var engine := TickEngine.new(repo)
	engine.advance(s)  # the reign's opening tick (GameRoot's)
	if s.ai_hosts.is_empty():
		print("pack %s raises no raid hosts (military/raid_hosts.csv): nothing to play" % map)
		quit(0)
		return
	# the first main host by code (EnemyAi.main_host names one only once it
	# is out of ASSEMBLE)
	var main := ""
	var cross := 0
	for h: String in EnemyAi.host_codes(s):
		if main == "" and EnemyAi.role_of(repo, h) == EnemyAi.ROLE_MAIN:
			main = h
	for row: Dictionary in repo.raid_hosts:
		if String(row["host_code"]) == main:
			cross = int(row["appear_day"])
	print("pack %s, seed %d, defence %s%s, %d days; the main host %s crosses on day %d" % [
		map, seed_value, defence, " (walls)" if walls else "", days, main, cross])
	var start := {"treasury": _metric(s, "treasury"), "content": _metric(s, "peasant_contentment"),
		"strategic": _metric(s, "strategic")}
	var sums := {"battles": 0, "won": 0, "lost": 0, "drawn": 0, "taken": 0, "fell": -1, "town": "",
		"garrison": [], "letters": 0, "best": 0}
	for n in days:
		var today := s.absolute_day()
		var treasury := _metric(s, "treasury")
		var content := _metric(s, "peasant_contentment")
		if s.day >= Calendar.DAYS_PER_TICK:
			engine.advance(s)
		else:
			engine.advance_day(s)
		var lines: Array = []
		if today == cross:
			var town := String(s.ai_hosts[main].get("target_id", ""))
			if String(s.ai_hosts[main].get("target_kind", "")) == EnemyAi.KIND_TOWN and defence != "none":
				sums["town"] = town
				sums["garrison"] = _garrison(repo, s, town, defence, walls)
				lines.append("  DEFENCE %s garrisons %s with %s" % [defence, town, sums["garrison"]])
			elif defence != "none":
				lines.append("  DEFENCE none set: the main host chose %s %s, not a town" % [
					s.ai_hosts[main].get("target_kind", ""), town])
		for e: Dictionary in engine.day_ai:
			if String(e.get("type", "")) in ["host_mode", "host_advance"]:
				lines.append("  AI     %s -> %s (%s)" % [e.get("host", ""), e.get("mode", "ADVANCE"), e.get("why", "sets out")])
		for e: Dictionary in engine.day_battles:
			match String(e.get("kind", "")):
				"start":
					sums["battles"] = int(sums["battles"]) + 1
					lines.append("  BATTLE %d begins%s: %s attack %s" % [int(e["battle_id"]),
						" at " + String(e["town"]) if String(e["town"]) != "" else " in the open", e["att"], e["def"]])
				"round":
					lines.append("  ROUND  %d.%d odds %d roll %d eff %d -> %s%s" % [int(e["battle_id"]), int(e["round"]),
						int(e["odds"]), int(e["roll"]), int(e["eff"]), e["tier"], _left(e)])
				"end":
					var won := _player_won(s, e)
					sums["won" if won == 1 else ("lost" if won == -1 else "drawn")] += 1
					lines.append("  END    %d after %d rounds: %s, winner %s" % [int(e["battle_id"]), int(e["rounds"]),
						e["why"], SIDE.get(String(e["winner"]), String(e["winner"]))])
		for e: Dictionary in engine.day_siege:
			var k := String(e.get("kind", ""))
			if e.has("type"):
				continue  # a host_mode, told above among the minds
			if k == "siege_day":
				sums["best"] = maxi(int(sums["best"]), int(e["progress"]))
				lines.append("  SIEGE  %s: attack %d defend %d gain %d -> %d/1000%s" % [e["town"], int(e["attack"]),
					int(e["defend"]), int(e["gain"]), int(e["progress"]), " STARVING" if bool(e["starving"]) else ""])
			elif k == "siege_fallen":
				sums["fell"] = today
				lines.append("  FALL   %s after %d days of siege: %s" % [e["town"], int(e["days"]), e["reason"]])
			elif k == "defeat_town_lost":
				lines.append("  LOSS   treasury -%d, contentment -%d, %d council opinions, beat %s" % [
					int(e["gold"]), int(e["morale"]), (e["opinion"] as Array).size(), e["event_id"]])
			elif k != "siege_begin":
				lines.append("  SIEGE  %s %s%s" % [k, e.get("town", ""), " (%s)" % e["why"] if e.has("why") else ""])
		for e: Dictionary in engine.day_raid:
			match String(e.get("kind", "")):
				"raid_begin":
					lines.append("  RAID   %s begins at %s" % [e["host"], e["place"]])
				"raid_day":
					sums["taken"] = int(sums["taken"]) + int(e["take"])
					lines.append("  RAID   %s takes %d (food %d, plunder %d, %s -%d)" % [e["host"], int(e["take"]),
						int(e["food"]), int(e["plunder"]), e["purse"], int(e["debit"])])
				"raid_spoils":
					lines.append("  SPOILS %d strategic from %s at %s" % [int(e["spoils"]), e["host"], e["place"]])
		for m: Dictionary in s.missives:
			if int(m["day"]) == today and String(m["kind"]) in ["rumour", "host_news"]:
				lines.append("  LETTER %s (%s): %s" % [m["kind"], m["column"], m["title"]])
		var dt := _metric(s, "treasury") - treasury
		var dc := _metric(s, "peasant_contentment") - content
		if dt != 0 or dc != 0:
			lines.append("  CROWN  treasury %+d, contentment %+.1f" % [dt, dc])
		print("day %3d %-16s %s" % [today, _date_of(today), _hosts(repo, s)])
		for l: String in lines:
			print(l)
	sums["letters"] = s.missives.filter(func(m: Dictionary) -> bool:
		return String(m["kind"]) in ["battle", "host_news", "rumour"]).size()
	_summary(repo, s, start, sums)
	quit(0)


## Garrisons `town` with the defence's regiments (by headcount: the smallest
## for weak, the three largest for strong, code order on ties), placed there
## as an order already carried out. Returns their codes.
func _garrison(repo: DataRepository, s: GameState, town: String, defence: String, walls: bool) -> Array:
	if walls:
		repo.burgs[town]["features"] = "walls|citadel"
		ArmySystem.forget_grids()
	var mine: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, r) > 0:
			mine.append(String(r["regiment_code"]))
	var weak := defence == "weak"
	mine.sort_custom(func(a: String, b: String) -> bool:
		var ha := ArmySystem.headcount(repo, ArmySystem.regiment(repo, a))
		var hb := ArmySystem.headcount(repo, ArmySystem.regiment(repo, b))
		return (ha < hb if weak else ha > hb) or (ha == hb and a < b))
	var picked: Array = mine.slice(0, 1 if weak else 3)
	var at := EnemyAi.target_point_m(repo, EnemyAi.KIND_TOWN, town)
	for c: String in picked:
		var e: Dictionary = s.regiments[c]
		e["x_m"] = at.x
		e["y_m"] = at.y
		e["dest_x_m"] = at.x
		e["dest_y_m"] = at.y
		e["order"] = ArmySystem.ORDER_GARRISON
	return picked


## Each host: mode, target, its lead live column in km and how far it stands
## from the target.
func _hosts(repo: DataRepository, s: GameState) -> String:
	var parts: Array = []
	for h: String in EnemyAi.host_codes(s):
		var m: Dictionary = s.ai_hosts[h]
		var live := EnemyAi.live_regiments(repo, s, h)
		var where := "gone"
		if not live.is_empty():
			var f: Dictionary = s.foes[live[0]]
			var at := Vector2i(int(f["x_m"]), int(f["y_m"]))
			where = "(%d,%d)km x%d" % [at.x / 1000, at.y / 1000, live.size()]
			if String(m.get("target_id", "")) != "":
				var to := EnemyAi.target_point_m(repo, String(m["target_kind"]), String(m["target_id"]))
				where += " %dkm off" % int(Vector2(at).distance_to(Vector2(to)) / 1000.0)
		var tgt := String(m.get("target_id", ""))
		parts.append("%s %s%s %s" % [h.trim_prefix("raid_"), m["mode"], "->" + tgt if tgt != "" else "", where])
	return " | ".join(parts)


## +1 the player's side won the battle, −1 the foe's, 0 neither.
func _player_won(s: GameState, e: Dictionary) -> int:
	var w := String(e["winner"])
	if w == "":
		return 0
	var side: Array = e[w]
	return -1 if side.any(func(c: String) -> bool: return ArmySystem.is_foe(s, c)) else 1


func _left(e: Dictionary) -> String:
	var out: Array = []
	for l: Dictionary in e.get("left", []):
		out.append("%s %s" % [l.get("code", ""), l.get("why", "")])
	return "" if out.is_empty() else ", left: " + ", ".join(out)


## The date of the absolute day `d` (tick 1 day 1 is day 1).
func _date_of(d: int) -> String:
	@warning_ignore("integer_division")
	return Calendar.date_string((d - 1) / Calendar.DAYS_PER_TICK + 1, (d - 1) % Calendar.DAYS_PER_TICK + 1)


func _metric(s: GameState, key: String) -> float:
	return float(s.metrics.get(key, 0))


func _summary(repo: DataRepository, s: GameState, start: Dictionary, sums: Dictionary) -> void:
	print("")
	print("SUMMARY %s" % Calendar.date_string(s.tick, s.day))
	for h: String in EnemyAi.host_codes(s):
		var m: Dictionary = s.ai_hosts[h]
		print("  host %-13s %-8s target %-12s plunder %5d  live columns %d" % [h, m["mode"],
			String(m.get("target_id", "")), int(m.get("plunder", 0)), EnemyAi.live_regiments(repo, s, h).size()])
	var town := String(sums["town"])
	if town != "":
		print("  town %s %s; best siege progress %d/1000" % [town,
			"FELL on day %d" % int(sums["fell"]) if int(sums["fell"]) > 0 else "HELD",
			int(sums["best"])])
		for c: String in sums["garrison"]:
			var e: Dictionary = s.regiments[c]
			print("  garrison %s: dead %d wounded %d morale %d" % [c, int(e.get("dead", 0)),
				int(e.get("wounded", 0)), int(e.get("morale", 0))])
	print("  battles %d (crown won %d, lost %d, neither %d); manors moved %d; town losses %d" % [
		int(sums["battles"]), int(sums["won"]), int(sums["lost"]), int(sums["drawn"]), s.manor_log.size(),
		s.town_losses.size()])
	print("  raided %d gold; treasury %+d, strategic %+d, contentment %+.1f; war letters %d" % [
		int(sums["taken"]), int(_metric(s, "treasury") - float(start["treasury"])),
		int(_metric(s, "strategic") - float(start["strategic"])),
		_metric(s, "peasant_contentment") - float(start["content"]), int(sums["letters"])])
	print("  state hash %s" % SaveLoad.state_hash(s))
