extends SceneTree
## Times the manor economy on the loaded pack (spec 2026-09-14 §11.3):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/bench_economy.gd
## Targets: a day's bucket <= 8 ms, the month's end <= 8 ms (16 hard), a
## warm realm read < 0.1 ms, one province < 1 ms; a cold recompute_all is
## reported, not bounded. The month's end is timed twice — the whole
## advance() (events, concerns and drift included) and RealmEconomy.realm
## alone, which is the economy's own share of it.
## A tool: it reads the clock, the engine never does.

func _init() -> void:
	var data := DataRepository.load_all("res://data")
	var s := GameState.new_campaign(data, 42)
	var engine := TickEngine.new(data)
	RealmEconomy.forget()
	var t0 := Time.get_ticks_usec()
	RealmEconomy.recompute_all(data, s)
	var cold := (Time.get_ticks_usec() - t0) / 1000.0
	RealmEconomy.forget()
	RealmEconomy.realm(data, s)
	t0 = Time.get_ticks_usec()
	for i in 100:
		RealmEconomy.realm(data, s)
	var warm := (Time.get_ticks_usec() - t0) / 100000.0
	var code: String = MapManors.controlled_provinces(data, s)[0]
	t0 = Time.get_ticks_usec()
	RealmEconomy.recompute_province(data, s, code)
	var one := (Time.get_ticks_usec() - t0) / 1000.0
	s.tick += 1
	var worst_day := 0.0
	for d in range(1, Calendar.DAYS_PER_TICK + 1):
		s.day = d
		t0 = Time.get_ticks_usec()
		RealmEconomy.step_day(data, s)
		worst_day = maxf(worst_day, (Time.get_ticks_usec() - t0) / 1000.0)
	t0 = Time.get_ticks_usec()
	RealmEconomy.realm(data, s)
	var realm_read := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	engine.advance(s)
	var month_end := (Time.get_ticks_usec() - t0) / 1000.0
	print("bench_economy: cold recompute_all %.1f ms | warm realm read %.3f ms | one province %.2f ms | worst day bucket %.1f ms | month's end (advance) %.1f ms | of which RealmEconomy.realm %.1f ms | provinces %d" % [
		cold, warm, one, worst_day, month_end, realm_read, RealmEconomy._codes.size()])
	quit(0)
