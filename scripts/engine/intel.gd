class_name Intel
extends RefCounted
## The one place that decides what the player knows (owner 2026-09-28, spec
## 2026-09-28-missive-board-and-spies §1). A caller hands over the TRUE value
## and gets back what may be shown: exact for land the crown controls; else
## the newest report's estimate; else, in the player's own realm, a word; else
## (abroad) only who holds it, the stance and a wealth word. DEV MODE
## (dev_all, set by GameRoot) sees everything.

static var dev_all := false

## What a poor spy writes for a word he could not make out.
const UNCLEAR := "unclear"
## The keys a manor's report may answer for its whole province (Ruling 11).
const PROVINCE_KEYS := ["stance", "wealth"]



static func province_of(repo: DataRepository, state: GameState, subj: Dictionary) -> String:
	match String(subj.get("kind", "")):
		"province":
			return String(subj.get("code", ""))
		"manor":
			return MapManors.province_of(repo, int(subj.get("cell", -1)), state)
		"burg":
			return String((repo.burgs.get(String(subj.get("code", "")), {}) as Dictionary).get("province_code", ""))
	var cell := MapEconomy.cell_at(repo, Vector2(float(subj.get("x", 0)), float(subj.get("y", 0))))
	return MapManors.province_of(repo, cell, state) if cell >= 0 else ""


static func level(repo: DataRepository, state: GameState, subj: Dictionary) -> String:
	if dev_all:
		return "full"
	var realm := repo.resolve_realm("player_realm")
	if String(subj.get("kind", "")) == "regiment":
		var reg := ArmySystem.regiment(repo, String(subj["code"]), state)
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


## 0 poor, 1 middling, 2 rich: the province's tier as the STATE holds it
## (Ruling 15, final review I5) — settled by TickEngine right after the
## month's economy, never computed here on demand, so no reader (a card the
## player opens, say) can decide when the month's figures are sampled and
## what a spy's saved report then says. 1 for a province (or a state) with none.
static func wealth_tier(_repo: DataRepository, state: GameState, province: String) -> int:
	return int(state.wealth_tiers.get(province, 1)) if state != null else 1


## Every province's tier from the state as it stands: its tax per person
## against every province's terciles, in code order. Pure.
static func compute_wealth_tiers(repo: DataRepository, state: GameState) -> Dictionary:
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
	var out: Dictionary = {}
	for c: String in per:
		out[c] = tercile_of(rates, int(per[c]))
	return out


## The month's settlement of the tiers into the state (TickEngine.advance,
## and a new campaign's first state).
static func settle_wealth_tiers(repo: DataRepository, state: GameState) -> void:
	state.wealth_tiers = compute_wealth_tiers(repo, state)


## A save written before the tiers were state carries none: compute them
## once, from the loaded state (Game.load_campaign).
static func ensure_wealth_tiers(repo: DataRepository, state: GameState) -> void:
	if state != null and state.wealth_tiers.is_empty():
		settle_wealth_tiers(repo, state)


## A kingdom's tier (final review M2): the mean of the settled tiers of
## the provinces it holds now, rounded half up; 1 for a kingdom with none.
static func kingdom_wealth_tier(repo: DataRepository, state: GameState, kingdom: String) -> int:
	var provs := MapOwnership.provinces_of(repo, state, kingdom)
	if provs.is_empty():
		return 1
	var total := 0
	for p: String in provs:
		total += wealth_tier(repo, state, p)
	@warning_ignore("integer_division")  # whole tiers, half up
	return clampi((total * 2 + provs.size()) / (provs.size() * 2), 0, 2)


## The tercile (0/1/2) of value v within sorted_rates. A tie takes the
## MIDDLE rank of its run, so a run of equal values never all falls into the
## lowest tier: [1,1,1,1,1,2,2,2,3] -> 1:0, 2:2, 3:2.
static func tercile_of(sorted_rates: Array, v: int) -> int:
	var n := sorted_rates.size()
	if n == 0:
		return 1
	var first := sorted_rates.find(v)
	var last := sorted_rates.rfind(v)
	@warning_ignore("integer_division")
	var rank := (first + last) / 2
	@warning_ignore("integer_division")
	return clampi(rank * 3 / n, 0, 2)


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
	if prov == "":  # the wildlands: no province to name (final review M13)
		return MapManors.label_of(repo, cell)
	return "%s (%s)" % [MapManors.label_of(repo, cell), String(repo.provinces.get(prov, {}).get("label", prov))]


## What may be shown of one fact about a subject.
static func fact(repo: DataRepository, state: GameState, subj: Dictionary, key: String,
		exact: Variant) -> Dictionary:
	var lvl := level(repo, state, subj)
	var today := state.absolute_day() if state != null else 0
	if lvl == "full":
		return {"text": _show(repo, key, exact), "source": "own records", "day": today, "column": "truth"}
	var m := estimate(repo, state, subj, key)
	if not m.is_empty():
		return m
	if key in ["holder", "stance", "wealth"]:
		return {"text": _show(repo, key, exact), "source": "common knowledge", "day": today, "column": ""}
	if lvl == "general" and exact is int:
		return {"text": magnitude(repo, int(exact)), "source": "common knowledge", "day": today, "column": ""}
	return {"text": "—", "source": "", "day": today, "column": ""}


static func _show(repo: DataRepository, key: String, v: Variant) -> String:
	if key == "wealth":
		return wealth_word(repo, int(v))
	return num(int(v)) if v is int else String(v)


## A fact dictionary's own words: an exact number, a span as "≈ lo–hi", or
## its own text. Public — panels outside this file render a report's fact
## the same way `fact()` does.
static func text_of(f: Dictionary) -> String:
	if f.has("exact"):
		# an audit's fact carries the governor's word too (AuditWriter): the
		# letter names it when the truth is not what he said
		if f.has("claimed") and int(f["claimed"]) != int(f["exact"]):
			return "%s (he reported %s)" % [num(int(f["exact"])), num(int(f["claimed"]))]
		return num(int(f["exact"]))
	if f.has("lo"):
		# no width: one number, and a count of nobody is "none" (not "≈ 0–0")
		if int(f["lo"]) == int(f["hi"]):
			return "none" if int(f["lo"]) == 0 else "≈ " + num(int(f["lo"]))
		return "≈ %s–%s" % [num(int(f["lo"])), num(int(f["hi"]))]
	return String(f.get("text", "—"))


## The newest report carrying `key` about `subj` (see `_latest`'s own
## matching rules), rendered as `fact()` would: {text, source, day, column},
## or {} when no report answers. Public — a caller that already knows its
## subject is not `full` (a table row, say) can ask for a report's estimate
## directly rather than reaching into `_latest` and `text_of` itself.
static func estimate(repo: DataRepository, state: GameState, subj: Dictionary, key: String) -> Dictionary:
	var m := _latest(repo, state, subj, key)
	if m.is_empty():
		return {}
	return {"text": text_of(m["fact"]), "source": String(m["kind"]), "day": int(m["day"]),
		"column": String(m["column"])}


## The newest letter carrying `key` about this subject:
## - tier 1: a manor query matches a report whose own subject is a manor of
##   the SAME cell; a town (burg) query resolves to its cell
##   (MapEconomy.burg_cells) and matches a report on that cell the same way
##   (Ruling 12 — the town card asks for `town_people`, never the manor's
##   own `people`);
## - tier 2: a province query matches a report whose subject lies in that
##   same province — but a manor's report answers its province only in the
##   province's own words (PROVINCE_KEYS: stance, wealth); its people, tax,
##   output and holder are that one manor's and answer only a query about
##   the same manor (Ruling 11);
## - tier 3 (distance): only a report whose subject kind is "point", within
##   intel_match_km of the query's point AND in the SAME province as the
##   query (both province_of non-empty and equal). A manor or province
##   report never answers a different manor or province merely by distance
##   (two provinces' centers can sit a few px apart on the pack).
## A words fact that reads "unclear" (a poor spy's holder, stance or wealth)
## answers nothing: those are always given, so the next report or common
## knowledge speaks instead (Ruling 13; the letter itself still says it).
static func _latest(repo: DataRepository, state: GameState, subj: Dictionary, key: String) -> Dictionary:
	if state == null:
		return {}
	var prov := province_of(repo, state, subj)
	var qkind := String(subj.get("kind", ""))
	var qcell := int(subj.get("cell", -2))
	if qkind == "burg":
		qcell = int(MapEconomy.burg_cells(repo).get(String(subj.get("code", "")), -2))
	var reach := repo.bal("intel_match_km") * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
	var here := Vector2(float(subj.get("x", 0)), float(subj.get("y", 0)))
	var best: Dictionary = {}
	for m: Dictionary in state.missives:
		if not best.is_empty() and int(m["id"]) < int(best["id"]):
			continue
		var f: Dictionary = {}
		for x: Dictionary in m["facts"]:
			if String(x["key"]) == key and String(x.get("text", "")) != UNCLEAR:
				f = x
		if f.is_empty():
			continue
		var ms: Dictionary = m["subject"]
		var mkind := String(ms.get("kind", ""))
		if mkind == "ledger":
			# An audit's letter (LEDGER_AUDIT) is about a governed flow, never
			# a place — its subject carries no cell and sits at (0,0), which
			# province_of's point fallback would otherwise resolve to
			# whatever cell sits at the map's origin. Never let it stand in
			# for a place's own estimate (spec 2026-09-30-ledger-governors-design §3).
			continue
		var hit := false
		if qkind in ["manor", "burg"] and mkind == "manor" and qcell >= 0 \
				and int(ms.get("cell", -1)) == qcell:
			hit = true
		elif qkind == "province" and prov != "" and province_of(repo, state, ms) == prov \
				and (mkind != "manor" or key in PROVINCE_KEYS):
			hit = true
		elif mkind == "point" and prov != "" \
				and province_of(repo, state, ms) == prov \
				and here.distance_to(Vector2(float(ms.get("x", 0)), float(ms.get("y", 0)))) <= reach:
			hit = true
		if hit:
			best = {"id": int(m["id"]), "kind": String(m["kind"]), "day": int(m["day"]),
				"column": String(m["column"]), "fact": f}
	return best
