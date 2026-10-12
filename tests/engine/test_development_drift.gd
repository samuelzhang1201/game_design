extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Laws drift the development axes monthly (spec 2026-10-12-development-axes §5).
## Hand values: start 100, decay 2.

var repo: DataRepository
var s: GameState
var player: String


func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	player = repo.resolve_realm("player_realm")
	repo.balance["dev_start_renaissance"] = 100.0
	repo.balance["dev_start_chivalry"] = 100.0
	repo.balance["dev_decay_per_month"] = 2.0


func _decree(law: String, value: String) -> void:
	s.law_decree[law] = {"value": value, "decree_id": 1, "day": 1}


## Every default undone, so only a test's own decree drifts.
func _undefault() -> void:
	_decree("quarter", "refuse")
	_decree("ransom", "execute")


func _score(axis: String) -> int:
	return DevelopmentSystem.score(s, player, axis)


func test_drift_sums_law_rows_in_file_order() -> void:
	_undefault()
	s.development[player]["renaissance"] = 140
	_decree("patronage", "scholars")
	_decree("guild_charter", "granted")
	var lines := _settle()
	assert_eq(_score("renaissance"), 144)
	assert_eq(lines.size(), 3)
	assert_eq(int(lines[0]["delta"]), 4)
	assert_eq(int(lines[1]["delta"]), 2)
	assert_eq(int(lines[2]["delta"]), -2)
	for l: Dictionary in lines:
		assert_ne(String(l["reason"]), "")


func test_decay_never_overshoots_start() -> void:
	_undefault()
	s.development[player]["renaissance"] = 101
	var lines := _settle()
	assert_eq(_score("renaissance"), 100)
	assert_eq(lines.size(), 1)
	assert_eq(int(lines[0]["delta"]), -1)


func test_untouched_realm_at_start_logs_nothing() -> void:
	_undefault()
	assert_eq(_settle().size(), 0)
	assert_eq(s.recent_outcomes.size(), 0)


func test_pinned_at_bounds_logs_no_zero_line() -> void:
	_undefault()
	repo.balance["dev_decay_per_month"] = 0.0
	s.development[player]["renaissance"] = 1000
	_decree("patronage", "court")
	_decree("guild_charter", "granted")
	var lines := _settle()
	assert_eq(_score("renaissance"), 1000)
	assert_eq(lines.size(), 0, "a clamped move logs no zero line")
	# Below the start, decay pulls up (start above the floor).
	repo.balance["dev_decay_per_month"] = 2.0
	_decree("patronage", "none")
	_decree("guild_charter", "none")
	s.development[player]["renaissance"] = 0
	DevelopmentSystem.settle_month(repo, s)
	assert_eq(_score("renaissance"), 2)


## The month's lines of the player's realm (the foreign realms' follow theirs).
func _settle() -> Array:
	return DevelopmentSystem.settle_month(repo, s).filter(
		func(l: Dictionary) -> bool: return String(l["realm"]) == player)


func test_default_laws_drift_nothing() -> void:
	for axis: String in DevelopmentSystem.AXES:
		assert_eq(DevelopmentSystem.law_drift(repo, s, axis).size(), 0, axis)
	assert_eq(_settle().size(), 0)


func test_settle_month_runs_in_tick() -> void:
	_undefault()
	_decree("knightly_orders", "on")
	var before := _score("chivalry")
	var engine := TickEngine.new(repo)
	var report := engine.advance(s)
	assert_eq(_score("chivalry"), before + 3 - 2)
	var found := false
	for o: Dictionary in report.outcomes:
		if String(o.get("action_code", "")) == "DEVELOPMENT":
			found = true
			assert_eq(String(o["effects"][0]["metric"]), "chivalry")
	assert_true(found, "a DEVELOPMENT outcome rides the report")


func test_dev_channel_does_not_touch_metrics() -> void:
	_decree("knightly_orders", "on")
	_decree("tolerance", "edict")
	var keys_before := s.metrics.keys()
	LawEffects.apply_lines(repo, s, LawEffects.month_lines(repo, s))
	for k: String in s.metrics:
		assert_false(String(k).begins_with("dev_"))
	assert_eq(s.metrics.keys().size(), keys_before.size())
	# tolerance's church row IS a metric line
	var church := LawEffects.month_lines(repo, s).filter(
		func(l: Dictionary) -> bool: return String(l["metric"]) == "church_opinion" and float(l["delta"]) < 0.0)
	assert_eq(church.size(), 1)
	assert_almost_eq(float(church[0]["delta"]), -0.3, 0.0001)
