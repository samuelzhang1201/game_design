extends SceneTree
## The opening numbers Chapter 0 is balanced against (docs/design/CHAPTER_0.md
## §5): what a fresh campaign actually starts with, and what the chapter's
## province earns in a month. Every target in the chapter tables is a
## multiple of a number printed here, so re-run this after any balance or
## pack change and check the design doc's table still reads true:
##   Godot --headless --path . -s tools/chapter0_numbers.gd [-- --map ID --province CODE]

func _init() -> void:
	var map := DataRepository.default_pack_id()
	var province := "bineterston"
	var ticks := 0
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map = args[i + 1]
		if args[i] == "--province":
			province = args[i + 1]
		if args[i] == "--ticks":
			ticks = int(args[i + 1])
	var repo := DataRepository.load_all("res://data")
	if repo == null or (repo.map_id != map and not repo.load_map(map)):
		push_error("chapter0_numbers: cannot load pack %s: %s" % [map, DataRepository.last_error])
		quit(1)
		return
	var state := GameState.new_campaign(repo, 44)
	print("pack %s, seed 44, %s" % [map, Calendar.date_string(state.tick, state.day)])
	print("")
	print("CROWN metrics at start")
	for k: String in ["treasury", "grain", "strategic", "unrest", "legitimacy",
			"peasant_contentment", "church_opinion", "army_quality", "tax_rate"]:
		print("  %-20s %s" % [k, state.metrics.get(k, "-")])
	print("  %-20s %s" % ["lord_gold", state.metrics.get("lord_gold", "-")])
	print("  %-20s %s" % ["lord_civil", state.metrics.get("lord_civil", "-")])
	print("  %-20s %s" % ["lord_strategic", state.metrics.get("lord_strategic", "-")])
	var purses := RealmEconomy.purses(repo, state)
	print("  month's purses  lord %s / crown share %s" % [purses["lord"], purses["realm_share"]])
	var e := RealmEconomy.realm(repo, state)
	print("  realm month     %s" % [e["realm"]])
	print("  crown month     %s" % [e["crown"]])
	print("  controls        %s" % [MapManors.controlled_provinces(repo, state)])
	print("")
	print("PROVINCE %s" % province)
	var row: Dictionary = repo.provinces.get(province, {})
	if not row.is_empty():
		print("  %s, %s, population %s, area %s" % [row.get("full_name", ""),
			row.get("kingdom_code", ""), row.get("population", ""), row.get("area", "")])
	print("  house           %s" % MapObjects.house_name_of(repo, province))
	print("  controller      %s" % MapManors.controller_of(repo, state, province))
	print("  month           %s" % [RealmEconomy.province(repo, state, province)])
	var nb: Dictionary = MapManors.province_neighbours(repo)
	print("  neighbours      %s" % [nb.get(province, [])])
	print("")
	print("  %-8s %-18s %-10s %8s %8s %8s %8s %10s" % [
		"cell", "manor", "focus", "people", "tax", "civil", "units", "price"])
	for cell: int in MapManors.manors_of_province(repo, province, state):
		var line := RealmEconomy.line_of(repo, state, cell)
		print("  %-8d %-18s %-10s %8d %8d %8d %8d %10d" % [cell,
			MapManors.label_of(repo, cell), MapManors.focus_of(repo, state, cell),
			int(line["people"]), int(line["tax"]), int(line["civil"]), int(line["units"]),
			int(MapManors.price_of(repo, state, cell))])
	if ticks > 0:
		print("")
		print("THE UNTOUCHED YEAR — %d months with no order given" % ticks)
		print("  %-16s %10s %10s %10s %10s %8s %8s" % [
			"date", "treasury", "civil", "lord_gold", "lord_civil", "unrest", "content"])
		var engine := TickEngine.new(repo)
		for t in ticks:
			for d in Calendar.DAYS_PER_TICK - 1:
				var daily := engine.resolve_day(state)
				if daily["status"] != "complete":
					print("Day stopped: ", daily)
					quit(0 if daily["status"] == "blocked" else 1)
					return
			var monthly := engine.resolve_day(state, true)
			if monthly["status"] != "complete":
				print("Month stopped: ", monthly)
				quit(0 if monthly["status"] == "blocked" else 1)
				return
			var rep: TickReport = monthly["report"]
			if not rep.event.is_empty():
				state.pending_event = {}  # nobody is at the table to answer it
			print("  %-16s %10d %10d %10d %10d %8.1f %8.1f" % [
				Calendar.date_string(state.tick, 1),
				int(state.metrics["treasury"]), int(state.metrics["grain"]),
				int(state.metrics["lord_gold"]), int(state.metrics["lord_civil"]),
				float(state.metrics["unrest"]), float(state.metrics["peasant_contentment"])])
	quit(0)
