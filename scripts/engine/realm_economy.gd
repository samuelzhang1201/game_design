class_name RealmEconomy
extends RefCounted
## The realm's economy from its manors (spec 2026-09-14 §4.4, §11): every
## manor's month kept COLUMNAR — five PackedInt32Array, people / tax /
## strategic / civil / units, one entry per manor, province-major
## (provinces by code, manors by cell id), so a province is a contiguous
## slice — with a KEY per province standing in for a dirty flag: the key strings together
## everything a line depends on (the tick, the tax and tariff in force in
## the province, the province's
## two ledger figures, and its manors' owner, buildings, focus and idle
## buildings), so a
## province is recomputed exactly when one of those moved and never
## otherwise, and nothing can forget to mark it (architecture RK-1). The
## realm's answer is cached on a signature of the same state, so a day
## step and a top-bar refresh are one string compare.
##
## The month's work is spread over its days: step_day recomputes the
## provinces of the day's bucket whose key went stale, so the month's end
## has almost nothing left (architecture R-5; the bucket count is the
## calendar's, in the save by construction). The buckets are BALANCED BY
## MANOR COUNT, not `province index mod 30` (2026-09-14, after the bench
## found a 196-manor bucket against a 117 mean and an 18 ms day step):
## setup() walks the provinces heaviest first and drops each into the
## lightest bucket so far. Deterministic — pack data, a fixed sort, ties
## to the lower index and the lower bucket; no RNG, nothing stored, so a
## save is unaffected.

static var _repo_id := 0
## The annexations the layout was built under (owner 2026-09-14): a manor
## that moved province moves its slice, so a new set rebuilds the index.
static var _annex_sig := 0
static var _cells := PackedInt32Array()      # i -> cell id
static var _index: Dictionary = {}            # cell id -> i
static var _codes := PackedStringArray()      # province index -> code
static var _range: Dictionary = {}            # code -> [start, end)
static var _bucket_of := PackedInt32Array()   # province index -> day bucket
static var _people := PackedInt32Array()      # i -> the manor's whole people
static var _tax := PackedInt32Array()
static var _strategic := PackedInt32Array()
static var _civil := PackedInt32Array()
## i -> how many units of goods the manor ships in the month, every good
## counted alike: the price input MapManors.value_of_units reads.
static var _units := PackedInt32Array()
static var _keys: Dictionary = {}             # code -> key computed under
static var _sums: Dictionary = {}             # code -> {tax, strategic, civil}
static var _realm_sig := ""
static var _realm: Dictionary = {}
## Provinces recomputed since forget(). Test seam.
static var compute_count := 0

static func forget() -> void:
	_repo_id = 0
	_annex_sig = 0
	_cells = PackedInt32Array()
	_index = {}
	_codes = PackedStringArray()
	_range = {}
	_bucket_of = PackedInt32Array()
	_people = PackedInt32Array()
	_tax = PackedInt32Array()
	_strategic = PackedInt32Array()
	_civil = PackedInt32Array()
	_units = PackedInt32Array()
	_keys = {}
	_sums = {}
	_realm_sig = ""
	_realm = {}
	compute_count = 0

## Index the manors, province-major. Once per repository and set of
## annexations.
static func setup(repo: DataRepository, state: GameState = null) -> void:
	var sig := 0 if state == null else state.manor_province.hash()
	if _repo_id == repo.get_instance_id() and _annex_sig == sig and not _cells.is_empty():
		return
	forget()
	_repo_id = repo.get_instance_id()
	_annex_sig = sig
	var codes: Array = []
	for code: String in repo.provinces:
		if not MapManors.manors_of_province(repo, code, state).is_empty():
			codes.append(code)
	codes.sort()
	for code: String in codes:
		var start := _cells.size()
		for id: int in MapManors.manors_of_province(repo, code, state):
			_index[id] = _cells.size()
			_cells.append(id)
		_range[code] = [start, _cells.size()]
		_codes.append(code)
	_people.resize(_cells.size())
	_tax.resize(_cells.size())
	_strategic.resize(_cells.size())
	_civil.resize(_cells.size())
	_units.resize(_cells.size())
	_assign_buckets()

## The day bucket of every province: the heaviest province goes into the
## lightest bucket, so no day of the month carries much more than the mean
## (1/DAYS_PER_TICK of the pack's manors). Pure pack data, fixed order.
static func _assign_buckets() -> void:
	var order: Array[int] = []
	for pi in _codes.size():
		order.append(pi)
	# Heaviest first; ties by province index ascending, so the order is one
	# order on every machine.
	order.sort_custom(func(a: int, b: int) -> bool:
		var wa := _manor_count(a)
		var wb := _manor_count(b)
		return wa > wb if wa != wb else a < b)
	var bucket_load := PackedInt32Array()
	bucket_load.resize(Calendar.DAYS_PER_TICK)
	_bucket_of = PackedInt32Array()
	_bucket_of.resize(_codes.size())
	for pi: int in order:
		var best := 0
		for b in bucket_load.size():
			if bucket_load[b] < bucket_load[best]:
				best = b
		_bucket_of[pi] = best
		bucket_load[best] += _manor_count(pi)

static func _manor_count(province_index: int) -> int:
	var r: Array = _range[_codes[province_index]]
	return int(r[1]) - int(r[0])

static func _figure(repo: DataRepository, state: GameState, path: String) -> int:
	var v: Variant = WorldLedger.value_of(repo, state, path)
	return int(roundf(float(v))) if v != null else 0

## Everything a province's lines depend on, as one string.
static func province_key(repo: DataRepository, state: GameState, code: String) -> String:
	var parts := PackedStringArray()
	parts.append(str(state.tick))
	# the tax and tariff in force HERE (laws, spec 2026-10-08 §4.3): a
	# courier's arrival recomputes his province alone
	var rates := ManorEconomy.rates_of(repo, state, code)
	parts.append(str(rates.x))
	parts.append(str(rates.y))
	parts.append(str(_figure(repo, state, "economy.provinces.%s.rural_population" % code)))
	parts.append(str(_figure(repo, state, "economy.provinces.%s.urban_population" % code)))
	for id: int in MapManors.manors_of_province(repo, code, state):
		var k := str(id)
		if state.manor_owner.has(k):
			parts.append("o%s=%s" % [k, str(state.manor_owner[k])])
		if state.manor_buildings.has(k):
			parts.append("b%s=%s" % [k, str(state.manor_buildings[k])])
		if state.manor_focus.has(k):
			parts.append("f%s=%s" % [k, str(state.manor_focus[k])])
		# An idle building makes and eats nothing (M5): its line moves.
		if state.idle_buildings.has(k):
			parts.append("i%s=%s" % [k, str(state.idle_buildings[k])])
	return "|".join(parts)

static func recompute_province(repo: DataRepository, state: GameState, code: String) -> void:
	setup(repo, state)
	compute_count += 1
	var r: Array = _range[code]
	var tax := 0
	var strategic := 0
	var civil := 0
	var rates := ManorEconomy.rates_of(repo, state, code)
	for i in range(int(r[0]), int(r[1])):
		var line := ManorEconomy.line_of(repo, state, _cells[i], state.tick, rates)
		_people[i] = int(line["people"])
		_tax[i] = int(line["tax"])
		_strategic[i] = int(line["strategic"])
		_civil[i] = int(line["civil"])
		_units[i] = 0
		for good: String in (line["units"] as Dictionary):
			_units[i] += int((line["units"] as Dictionary)[good])
		tax += _tax[i]
		strategic += _strategic[i]
		civil += _civil[i]
	_sums[code] = {"tax": tax, "strategic": strategic, "civil": civil}
	_keys[code] = province_key(repo, state, code)

## A province's month, current: recomputed when its key moved.
static func province(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	setup(repo, state)
	if not _range.has(code):
		return {"tax": 0, "strategic": 0, "civil": 0}
	if String(_keys.get(code, "")) != province_key(repo, state, code):
		recompute_province(repo, state, code)
	return _sums[code]

## A manor's cached line, current.
static func line_of(repo: DataRepository, state: GameState, cell: int) -> Dictionary:
	province(repo, state, MapManors.province_of(repo, cell, state))
	if not _index.has(cell):
		return {"people": 0, "tax": 0, "strategic": 0, "civil": 0, "units": 0}
	var i: int = _index[cell]
	return {"people": _people[i], "tax": _tax[i], "strategic": _strategic[i],
		"civil": _civil[i], "units": _units[i]}

## Every manor of a province at once: cell -> {people, tax, strategic,
## civil, units}. The province's key is checked ONCE and the answers come
## off the columnar arrays, so a table of a thousand rows (the Manor
## Master) costs one key build, not one per row.
static func lines_of_province(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	setup(repo, state)
	if not _range.has(code):
		return {}
	province(repo, state, code)
	var out: Dictionary = {}
	var r: Array = _range[code]
	for i in range(int(r[0]), int(r[1])):
		out[_cells[i]] = {"people": _people[i], "tax": _tax[i], "strategic": _strategic[i],
			"civil": _civil[i], "units": _units[i]}
	return out

## The month of many manors at once: cell -> {people, tax, strategic,
## civil, units}.
## The cells are grouped by province first, so each province's key is built
## and compared ONCE however the caller ordered them — a table of a thousand
## rows must never go through `line_of` per row, which is O(the province's
## manors) each time. Cells that are no manor are left out.
static func lines_table(repo: DataRepository, state: GameState, cells: Array) -> Dictionary:
	setup(repo, state)
	var by_province: Dictionary = {}
	for cell: int in cells:
		var code := MapManors.province_of(repo, cell, state)
		if code == "" or not _range.has(code):
			continue
		if not by_province.has(code):
			by_province[code] = []
		(by_province[code] as Array).append(cell)
	var out: Dictionary = {}
	for code: String in by_province:
		var lines := lines_of_province(repo, state, code)
		for cell: int in by_province[code]:
			if lines.has(cell):
				out[cell] = lines[cell]
	return out

## The month's tax alone: cell -> whole gold.
static func tax_table(repo: DataRepository, state: GameState, cells: Array) -> Dictionary:
	var out: Dictionary = {}
	var lines := lines_table(repo, state, cells)
	for cell: int in lines:
		out[cell] = int((lines[cell] as Dictionary)["tax"])
	return out

## What the realm's answer depends on, cheaply: the dictionaries that hold
## only what moved hash in C++ — ownership included, so a conquest that
## moves no manor and touches no ledger figure still turns the signature;
## the laws in force too, so a courier's arrival turns it (the rate metrics
## stay for a state with no law state, which reads them, R8).
static func realm_signature(state: GameState) -> String:
	return "%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [state.tick, state.manor_owner.hash(),
		state.manor_buildings.hash(), state.manor_focus.hash(), state.idle_buildings.hash(),
		state.world.hash(),
		state.province_owner.hash(), state.manor_province.hash(), state.law_in_force.hash(),
		int(state.metrics.get("tax_rate", 0)), int(state.metrics.get("tariff_rate", 0))]

## Whether realm() (and so purses()) would answer from its cache: the realm
## is cut for this state and none of its provinces has gone stale since — a
## UI that can wait asks this before a read that would recompute (perf
## 2026-10-02: the first read after a month's settlement costs ~9 ms).
static func is_warm(repo: DataRepository, state: GameState) -> bool:
	return repo.get_instance_id() == _repo_id and not _realm.is_empty() \
		and realm_signature(state) == _realm_sig


## {realm, crown, per_province}: the player's realm's provinces (live
## ownership), the crown's controlled ones summed apart.
static func realm(repo: DataRepository, state: GameState) -> Dictionary:
	setup(repo, state)
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
		for k: String in ["tax", "strategic", "civil"]:
			total[k] += int(p[k])
			if code in mine:
				crown[k] += int(p[k])
	_realm = {"realm": total, "crown": crown, "per_province": per}
	_realm_sig = sig
	return _realm

## The month split by PURSE (owner 2026-09-14): the LORD's — the provinces
## the player's house controls, in full — and the CROWN treasury's, its
## crown_share_permille of every other province of the realm. Whole gold;
## the settlement and the top bar both read it here, so they never disagree.
## {lord: {tax, strategic, civil}, realm_share: {tax, strategic, civil}}.
static func purses(repo: DataRepository, state: GameState) -> Dictionary:
	var e := realm(repo, state)
	var share := repo.bal("crown_share_permille") / 1000.0
	var lord: Dictionary = {}
	var crown_share: Dictionary = {}
	for k: String in ["tax", "strategic", "civil"]:
		var own := int(e["crown"][k])
		lord[k] = own
		crown_share[k] = int(roundf(share * float(int(e["realm"][k]) - own)))
	return {"lord": lord, "realm_share": crown_share}

## The day's bucket: recompute the stale provinces whose index falls on
## today. Returns how many were recomputed.
static func step_day(repo: DataRepository, state: GameState) -> int:
	setup(repo, state)
	var n := 0
	var bucket := (state.day - 1) % Calendar.DAYS_PER_TICK
	for pi: int in _codes.size():
		if _bucket_of[pi] != bucket:
			continue
		var code := _codes[pi]
		if String(_keys.get(code, "")) != province_key(repo, state, code):
			recompute_province(repo, state, code)
			n += 1
	return n

## Every province from scratch, no cache: code -> {tax, strategic, civil}.
static func recompute_all(repo: DataRepository, state: GameState) -> Dictionary:
	setup(repo, state)
	var out: Dictionary = {}
	for code: String in _codes:
		var r: Array = _range[code]
		var sum := {"tax": 0, "strategic": 0, "civil": 0}
		var rates := ManorEconomy.rates_of(repo, state, code)
		for i in range(int(r[0]), int(r[1])):
			var line := ManorEconomy.line_of(repo, state, _cells[i], state.tick, rates)
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
	for code: String in _codes:
		var cached := province(repo, state, code)
		if cached != fresh[code]:
			out.append({"province": code, "cached": cached, "fresh": fresh[code]})
	return out

## The one number the military reads as the army's capacity and reach.
static func strategic_stock(state: GameState) -> int:
	return int(state.metrics.get("strategic", 0))
