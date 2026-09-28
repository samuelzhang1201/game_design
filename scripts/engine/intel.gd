class_name Intel
extends RefCounted
## The one place that decides what the player knows (owner 2026-09-28, spec
## 2026-09-28-missive-board-and-spies §1). A caller hands over the TRUE value
## and gets back what may be shown: exact for land the crown controls; else
## the newest report's estimate; else, in the player's own realm, a word; else
## (abroad) only who holds it, the stance and a wealth word. DEV MODE
## (dev_all, set by GameRoot) sees everything.

static var dev_all := false

static var _tiers: Dictionary = {}
static var _tiers_key := ""


static func province_of(repo: DataRepository, state: GameState, subj: Dictionary) -> String:
	match String(subj.get("kind", "")):
		"province":
			return String(subj["code"])
		"manor":
			return MapManors.province_of(repo, int(subj["cell"]), state)
		"burg":
			return String((repo.burgs.get(String(subj["code"]), {}) as Dictionary).get("province_code", ""))
	var cell := MapEconomy.cell_at(repo, Vector2(float(subj.get("x", 0)), float(subj.get("y", 0))))
	return MapManors.province_of(repo, cell, state) if cell >= 0 else ""


static func level(repo: DataRepository, state: GameState, subj: Dictionary) -> String:
	if dev_all:
		return "full"
	var realm := repo.resolve_realm("player_realm")
	if String(subj.get("kind", "")) == "regiment":
		var reg := ArmySystem.regiment(repo, String(subj["code"]))
		return "full" if String(reg.get("kingdom_code", "")) == realm else "basic"
	var prov := province_of(repo, state, subj)
	if prov == "":
		return "basic"
	if prov in MapManors.controlled_provinces(repo, state):
		return "full"
	return "general" if MapOwnership.owner_of(repo, state, prov) == realm else "basic"


static func stance_of(repo: DataRepository, kingdom: String) -> String:
	var realm := repo.resolve_realm("player_realm")
	if kingdom == realm:
		return "Our realm"
	var row: Dictionary = repo.world_table("political", "diplomacy").get("%s>%s" % [realm, kingdom], {})
	return String(row.get("stance", "Unknown"))


## 0 poor, 1 middling, 2 rich: the province's tax per person against every
## province's terciles. Cached per pack and month.
static func wealth_tier(repo: DataRepository, state: GameState, province: String) -> int:
	var key := "%s|%d" % [repo.map_id, state.tick if state != null else 0]
	if key != _tiers_key:
		_tiers = {}
		_tiers_key = key
		var rates: Array = []
		var per: Dictionary = {}
		var codes := repo.provinces.keys()
		codes.sort()
		for c: String in codes:
			var people := RealmEconomy._figure(repo, state, "economy.provinces.%s.rural_population" % c) \
				+ RealmEconomy._figure(repo, state, "economy.provinces.%s.urban_population" % c)
			if people <= 0:
				continue
			@warning_ignore("integer_division")  # gold per 1000 people, whole
			var rate := int(RealmEconomy.province(repo, state, c)["tax"]) * 1000 / people
			per[c] = rate
			rates.append(rate)
		rates.sort()
		for c: String in per:
			var i := rates.find(per[c])
			@warning_ignore("integer_division")  # terciles
			_tiers[c] = clampi(i * 3 / maxi(1, rates.size()), 0, 2)
	return int(_tiers.get(province, 1))


static func wealth_word(repo: DataRepository, tier: int) -> String:
	var tiers: PackedStringArray = (repo.intel_facts.get("wealth", {}) as Dictionary).get("tiers", PackedStringArray())
	return tiers[clampi(tier, 0, tiers.size() - 1)] if not tiers.is_empty() else str(tier)


static func magnitude(repo: DataRepository, n: int) -> String:
	if n < int(repo.bal("intel_magnitude_hundreds")):
		return "a handful"
	if n < int(repo.bal("intel_magnitude_thousands")):
		return "hundreds"
	if n < int(repo.bal("intel_magnitude_many")):
		return "thousands"
	return "many thousands"


static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func place_label(repo: DataRepository, state: GameState, px: Vector2) -> String:
	var cell := MapEconomy.cell_at(repo, px)
	if cell < 0 or not MapManors.is_manor(repo, cell):
		return "the open sea"
	var prov := MapManors.province_of(repo, cell, state)
	return "%s (%s)" % [MapManors.label_of(repo, cell), String(repo.provinces.get(prov, {}).get("label", prov))]


## What may be shown of one fact about a subject.
static func fact(repo: DataRepository, state: GameState, subj: Dictionary, key: String,
		exact: Variant) -> Dictionary:
	var lvl := level(repo, state, subj)
	var today := state.absolute_day() if state != null else 0
	if lvl == "full":
		return {"text": _show(repo, key, exact), "source": "own records", "day": today, "column": "truth"}
	var m := _latest(repo, state, subj, key)
	if not m.is_empty():
		return {"text": _from_fact(m["fact"]), "source": String(m["kind"]), "day": int(m["day"]),
			"column": String(m["column"])}
	if key in ["holder", "stance", "wealth"]:
		return {"text": _show(repo, key, exact), "source": "common knowledge", "day": today, "column": ""}
	if lvl == "general" and exact is int:
		return {"text": magnitude(repo, int(exact)), "source": "common knowledge", "day": today, "column": ""}
	return {"text": "—", "source": "", "day": today, "column": ""}


static func _show(repo: DataRepository, key: String, v: Variant) -> String:
	if key == "wealth":
		return wealth_word(repo, int(v))
	return num(int(v)) if v is int else String(v)


static func _from_fact(f: Dictionary) -> String:
	if f.has("exact"):
		return num(int(f["exact"]))
	if f.has("lo"):
		return "≈ %s–%s" % [num(int(f["lo"])), num(int(f["hi"]))]
	return String(f.get("text", "—"))


## The newest letter carrying `key` about this subject: the same manor cell,
## else the same province, else a point within intel_match_km.
static func _latest(repo: DataRepository, state: GameState, subj: Dictionary, key: String) -> Dictionary:
	if state == null:
		return {}
	var prov := province_of(repo, state, subj)
	var reach := repo.bal("intel_match_km") * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
	var here := Vector2(float(subj.get("x", 0)), float(subj.get("y", 0)))
	var best: Dictionary = {}
	for m: Dictionary in state.missives:
		if not best.is_empty() and int(m["id"]) < int(best["id"]):
			continue
		var f: Dictionary = {}
		for x: Dictionary in m["facts"]:
			if String(x["key"]) == key:
				f = x
		if f.is_empty():
			continue
		var ms: Dictionary = m["subject"]
		var hit := false
		if String(subj.get("kind", "")) == "manor" and int(ms.get("cell", -1)) == int(subj.get("cell", -2)):
			hit = true
		elif prov != "" and province_of(repo, state, ms) == prov and String(subj.get("kind", "")) == "province":
			hit = true
		elif here.distance_to(Vector2(float(ms.get("x", 0)), float(ms.get("y", 0)))) <= reach:
			hit = true
		if hit:
			best = {"id": int(m["id"]), "kind": String(m["kind"]), "day": int(m["day"]),
				"column": String(m["column"]), "fact": f}
	return best
