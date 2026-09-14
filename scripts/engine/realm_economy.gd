class_name RealmEconomy
extends RefCounted
## The realm's economy from its manors (spec 2026-09-14 §4.4, §11): every
## manor's month kept COLUMNAR — three PackedInt32Array, tax / strategic /
## civil, one entry per manor, province-major (provinces by code, manors
## by cell id), so a province is a contiguous slice — with a KEY per
## province standing in for a dirty flag: the key strings together
## everything a line depends on (the tick, the tax levels, the province's
## two ledger figures, and its manors' owner, buildings and focus), so a
## province is recomputed exactly when one of those moved and never
## otherwise, and nothing can forget to mark it (architecture RK-1). The
## realm's answer is cached on a signature of the same state, so a day
## step and a top-bar refresh are one string compare.
##
## The month's work is spread over its days: step_day recomputes the
## provinces of the day's bucket (province index mod 30) whose key went
## stale, so the month's end has almost nothing left (architecture R-5;
## the bucket count is the calendar's, in the save by construction).

static var _repo_id := 0
static var _cells := PackedInt32Array()      # i -> cell id
static var _index: Dictionary = {}            # cell id -> i
static var _codes := PackedStringArray()      # province index -> code
static var _range: Dictionary = {}            # code -> [start, end)
static var _tax := PackedInt32Array()
static var _strategic := PackedInt32Array()
static var _civil := PackedInt32Array()
static var _keys: Dictionary = {}             # code -> key computed under
static var _sums: Dictionary = {}             # code -> {tax, strategic, civil}
static var _realm_sig := ""
static var _realm: Dictionary = {}
## Provinces recomputed since forget(). Test seam.
static var compute_count := 0

static func forget() -> void:
	_repo_id = 0
	_cells = PackedInt32Array()
	_index = {}
	_codes = PackedStringArray()
	_range = {}
	_tax = PackedInt32Array()
	_strategic = PackedInt32Array()
	_civil = PackedInt32Array()
	_keys = {}
	_sums = {}
	_realm_sig = ""
	_realm = {}
	compute_count = 0

## Index the pack's manors, province-major. Once per repository.
static func setup(repo: DataRepository) -> void:
	if _repo_id == repo.get_instance_id() and not _cells.is_empty():
		return
	forget()
	_repo_id = repo.get_instance_id()
	var codes: Array = []
	for code: String in repo.provinces:
		if not MapManors.manors_of_province(repo, code).is_empty():
			codes.append(code)
	codes.sort()
	for code: String in codes:
		var start := _cells.size()
		for id: int in MapManors.manors_of_province(repo, code):
			_index[id] = _cells.size()
			_cells.append(id)
		_range[code] = [start, _cells.size()]
		_codes.append(code)
	_tax.resize(_cells.size())
	_strategic.resize(_cells.size())
	_civil.resize(_cells.size())

static func _figure(repo: DataRepository, state: GameState, path: String) -> int:
	var v: Variant = WorldLedger.value_of(repo, state, path)
	return int(roundf(float(v))) if v != null else 0

## Everything a province's lines depend on, as one string.
static func province_key(repo: DataRepository, state: GameState, code: String) -> String:
	var parts := PackedStringArray()
	parts.append(str(state.tick))
	parts.append(str(int(state.metrics.get("tax_rate", 0))))
	parts.append(str(int(state.metrics.get("tariff_rate", 0))))
	parts.append(str(_figure(repo, state, "economy.provinces.%s.rural_population" % code)))
	parts.append(str(_figure(repo, state, "economy.provinces.%s.urban_population" % code)))
	for id: int in MapManors.manors_of_province(repo, code):
		var k := str(id)
		if state.manor_owner.has(k):
			parts.append("o%s=%s" % [k, str(state.manor_owner[k])])
		if state.manor_buildings.has(k):
			parts.append("b%s=%s" % [k, str(state.manor_buildings[k])])
		if state.manor_focus.has(k):
			parts.append("f%s=%s" % [k, str(state.manor_focus[k])])
	return "|".join(parts)

static func recompute_province(repo: DataRepository, state: GameState, code: String) -> void:
	setup(repo)
	compute_count += 1
	var r: Array = _range[code]
	var tax := 0
	var strategic := 0
	var civil := 0
	for i in range(int(r[0]), int(r[1])):
		var line := ManorEconomy.line_of(repo, state, _cells[i], state.tick)
		_tax[i] = int(line["tax"])
		_strategic[i] = int(line["strategic"])
		_civil[i] = int(line["civil"])
		tax += _tax[i]
		strategic += _strategic[i]
		civil += _civil[i]
	_sums[code] = {"tax": tax, "strategic": strategic, "civil": civil}
	_keys[code] = province_key(repo, state, code)

## A province's month, current: recomputed when its key moved.
static func province(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	setup(repo)
	if not _range.has(code):
		return {"tax": 0, "strategic": 0, "civil": 0}
	if String(_keys.get(code, "")) != province_key(repo, state, code):
		recompute_province(repo, state, code)
	return _sums[code]

## A manor's cached line, current.
static func line_of(repo: DataRepository, state: GameState, cell: int) -> Dictionary:
	province(repo, state, MapManors.province_of(repo, cell))
	if not _index.has(cell):
		return {"tax": 0, "strategic": 0, "civil": 0}
	var i: int = _index[cell]
	return {"tax": _tax[i], "strategic": _strategic[i], "civil": _civil[i]}

## What the realm's answer depends on, cheaply: the dictionaries that hold
## only what moved hash in C++.
static func realm_signature(state: GameState) -> String:
	return "%d|%d|%d|%d|%d|%d|%d" % [state.tick, state.manor_owner.hash(),
		state.manor_buildings.hash(), state.manor_focus.hash(), state.world.hash(),
		int(state.metrics.get("tax_rate", 0)), int(state.metrics.get("tariff_rate", 0))]

## {realm, crown, per_province}: the player's realm's provinces (live
## ownership), the crown's controlled ones summed apart.
static func realm(repo: DataRepository, state: GameState) -> Dictionary:
	setup(repo)
	var sig := realm_signature(state)
	if sig == _realm_sig and not _realm.is_empty():
		return _realm
	var mine := MapManors.controlled_provinces(repo, state)
	var total := {"tax": 0, "strategic": 0, "civil": 0}
	var crown := {"tax": 0, "strategic": 0, "civil": 0}
	var per: Dictionary = {}
	var codes: Array = Array(MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")))
	codes.sort()
	for code: String in codes:
		if not _range.has(code):
			continue
		var p := province(repo, state, code)
		per[code] = p
		for k in ["tax", "strategic", "civil"]:
			total[k] += int(p[k])
			if code in mine:
				crown[k] += int(p[k])
	_realm = {"realm": total, "crown": crown, "per_province": per}
	_realm_sig = sig
	return _realm

## The day's bucket: recompute the stale provinces whose index falls on
## today. Returns how many were recomputed.
static func step_day(repo: DataRepository, state: GameState) -> int:
	setup(repo)
	var n := 0
	var bucket := (state.day - 1) % Calendar.DAYS_PER_TICK
	for pi in _codes.size():
		if pi % Calendar.DAYS_PER_TICK != bucket:
			continue
		var code := _codes[pi]
		if String(_keys.get(code, "")) != province_key(repo, state, code):
			recompute_province(repo, state, code)
			n += 1
	return n

## Every province from scratch, no cache: code -> {tax, strategic, civil}.
static func recompute_all(repo: DataRepository, state: GameState) -> Dictionary:
	setup(repo)
	var out: Dictionary = {}
	for code in _codes:
		var r: Array = _range[code]
		var sum := {"tax": 0, "strategic": 0, "civil": 0}
		for i in range(int(r[0]), int(r[1])):
			var line := ManorEconomy.line_of(repo, state, _cells[i], state.tick)
			sum["tax"] += int(line["tax"])
			sum["strategic"] += int(line["strategic"])
			sum["civil"] += int(line["civil"])
		out[code] = sum
	return out

## The provinces whose cached sum differs from a fresh one:
## [{province, cached, fresh}]. Empty is the only right answer.
static func check_full(repo: DataRepository, state: GameState) -> Array:
	var fresh := recompute_all(repo, state)
	var out: Array = []
	for code in _codes:
		var cached := province(repo, state, code)
		if cached != fresh[code]:
			out.append({"province": code, "cached": cached, "fresh": fresh[code]})
	return out

## The one number the military reads as the army's capacity and reach.
static func strategic_stock(state: GameState) -> int:
	return int(state.metrics.get("strategic", 0))
