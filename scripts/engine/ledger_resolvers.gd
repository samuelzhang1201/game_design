# scripts/engine/ledger_resolvers.gd
class_name LedgerResolvers
extends RefCounted
## The LEDGER's readers (spec 2026-09-30-ledger-ontology-design §7.2): one
## per live link type of data/ledger_link_types.csv. Each reads the real
## systems and returns the TRUTH; Ledger turns it into belief through Intel.
## They never write state and never draw RNG.
##
## A returned link: {from, to, flow, subj, key}
##   from / to - node ids: "type:<type_id>" at the type level, "<type>:<id>"
##               for an instance
##   flow      - whole units a month, or a count; -1 for no magnitude (a
##               lever, or a tie that is only there or not)
##   subj      - the Intel subject that gates it ({} = the crown's own
##               records, always "full")
##   key       - the fact key Intel words it by
##
## focus {} is the type level (one link between the two type spheres, the
## crown's own figures); {"id": node id} the links touching that instance;
## {"all": true} every instance link (the court lens).

const NAMES := ["works", "part_of", "yields_civil", "yields_strategic", "taxed", "trade_gold",
	"rations", "stands_on", "holds", "member", "sits", "based_in", "carries", "spies_on",
	"describes", "court_relations", "converts_in", "converts_out", "supplies_in", "supplies_out", "garrisons",
	"governs", "skims", "builds", "consumes", "trades", "routes", "static"]
const INSTANCE_LISTS := ["peasants", "manors", "provinces", "regiments", "characters", "houses",
	"seats", "reports", "couriers", "workshops", "supply_lines", "artisans", "markets", "trade_routes", "static"]
const REPORT_KINDS := {"describes_province": "province", "describes_manor": "manor",
	"describes_regiment": "regiment", "describes_town": "burg"}


# One snapshot's plans (fix round 1 of M3 Task 4): Ledger.snapshot turns the
# memo on at its start and off at its end, so SupplySystem.plan,
# WorkshopSystem.plan, IndustrySystem.plan and MarketSystem.routes run at
# most once a snapshot and never outlive it.
static var _memo: Dictionary = {}
static var _memo_on := false


static func begin_memo() -> void:
	_memo.clear()
	_memo_on = true


static func end_memo() -> void:
	_memo.clear()
	_memo_on = false


static func memo_active() -> bool:
	return _memo_on


static func _supply_plan(repo: DataRepository, state: GameState) -> Array:
	if not _memo_on:
		return SupplySystem.plan(repo, state)
	if not _memo.has("supply"):
		_memo["supply"] = SupplySystem.plan(repo, state)
	return _memo["supply"]


static func _workshop_plan(repo: DataRepository, state: GameState) -> Array:
	if not _memo_on:
		return WorkshopSystem.plan(repo, state)
	if not _memo.has("workshop"):
		_memo["workshop"] = WorkshopSystem.plan(repo, state)
	return _memo["workshop"]


## A house's manors (MapManors.manors_of_house), from ONE index of every
## manor by its holder built per memo — the scan per house cost ~136 ms a
## galaxy (spec 2026-09-30-ledger-galaxy-design §3). Outside a memo, the scan.
static func _manors_of_house(repo: DataRepository, state: GameState, family: String) -> Array:
	if not _memo_on:
		return MapManors.manors_of_house(repo, state, family)
	if not _memo.has("house_manors"):
		var idx := {}
		var ids: Array = repo.manors.keys()
		ids.sort()
		for cell: int in ids:
			var owner := String(MapManors.owner_of(repo, state, cell))
			if owner != "":
				(idx.get_or_add(owner, []) as Array).append(cell)
		_memo["house_manors"] = idx
	return (_memo["house_manors"] as Dictionary).get(family, [])


## Intel.level, cached per subject within one memo (Ledger._account calls
## this instead of Intel.level directly). A pure function of repo + state +
## subj while the memo's state stands still, so caching it is safe; `holds`'
## house index alone asks it once per manor a house owns anywhere, and
## `_account` asked it again for every believed link the galaxy read.
static func intel_level(repo: DataRepository, state: GameState, subj: Dictionary) -> String:
	if not _memo_on:
		return Intel.level(repo, state, subj)
	var key := str(subj)
	var cache: Dictionary = _memo.get("intel_level", {})
	if not cache.has(key):
		cache[key] = Intel.level(repo, state, subj)
		_memo["intel_level"] = cache
	return cache[key]


## MarketSystem.province_of_burg, cached per burg within one memo
## (Ledger._province_code's `town` branch calls this instead). The
## uncached call scans every entry of `state.manor_province` looking for
## one that names this burg; a town's LEDGER links (`stands_on`,
## `garrisons`, `describes_town`) ask its province up to four times over
## (fix round 1, controller ruling).
static func burg_province(repo: DataRepository, state: GameState, burg: String) -> String:
	if not _memo_on:
		return MarketSystem.province_of_burg(repo, state, burg)
	var cache: Dictionary = _memo.get("burg_province", {})
	if not cache.has(burg):
		cache[burg] = MarketSystem.province_of_burg(repo, state, burg)
		_memo["burg_province"] = cache
	return cache[burg]


static func _industry_plan(repo: DataRepository, state: GameState) -> Array:
	if not _memo_on:
		return IndustrySystem.plan(repo, state)
	if not _memo.has("industry"):
		_memo["industry"] = IndustrySystem.plan(repo, state)
	return _memo["industry"]


static func _routes(repo: DataRepository, state: GameState) -> Array:
	if not _memo_on:
		return MarketSystem.routes(repo, state)
	if not _memo.has("routes"):
		_memo["routes"] = MarketSystem.routes(repo, state)
	return _memo["routes"]


static func has(name: String) -> bool:
	return name in NAMES


static func has_instances(name: String) -> bool:
	return name in INSTANCE_LISTS


static func run(row: Dictionary, repo: DataRepository, state: GameState, focus: Dictionary) -> Array:
	var from_t := String(row["from_type"])
	var to_t := String(row["to_type"])
	var id := String(focus.get("id", ""))
	var all := bool(focus.get("all", false))
	match String(row["resolver"]):
		"works":
			return _works(repo, state, id)
		"part_of":
			return _part_of(repo, state, id)
		"yields_civil":
			return _yields(repo, state, id, "civil", to_t)
		"yields_strategic":
			return _yields(repo, state, id, "strategic", to_t)
		"taxed":
			return _yields(repo, state, id, "tax", to_t)
		"trade_gold":
			return [_type_link(from_t, to_t, -1, "gold")] if id == "" and not all else []
		"rations":
			return [_type_link(from_t, to_t, TickEngine.ration_of(repo, state), "gold")] \
				if id == "" and not all else []
		"stands_on":
			return _stands_on(repo, state, id)
		"holds":
			return _holds(repo, state, id)
		"member":
			return _member(state, id)
		"sits":
			return _sits(state, id)
		"based_in":
			return _based_in(repo, state, id)
		"carries":
			return _couriers(repo, state, id, false)
		"spies_on":
			return _couriers(repo, state, id, true)
		"describes":
			return _describes(state, id, String(row["link_id"]), to_t)
		"court_relations":
			return _relations(state, id, all, String(row["link_id"]))
		"converts_in":
			return _workshops(repo, state, id, true)
		"converts_out":
			return _workshops(repo, state, id, false)
		"supplies_in":
			return _supply(repo, state, id, true)
		"supplies_out":
			return _supply(repo, state, id, false)
		"garrisons":
			return _garrisons(repo, state, id)
		"governs":
			return _governs(repo, state, id, to_t)
		"skims":
			return _skims(repo, state, id, to_t)
		"builds":
			return _builds(repo, state, id)
		"consumes":
			return _consumes(repo, state, id, to_t)
		"trades":
			return _trades(repo, state, id, to_t)
		"routes":
			return _routes_to_gold(repo, state, id)
		"static":
			return _static_links(row, repo, id, all)
	return []


# --- the links -------------------------------------------------------------

static func _type_link(from_t: String, to_t: String, flow: int, key: String) -> Dictionary:
	return {"from": "type:" + from_t, "to": "type:" + to_t, "flow": flow, "subj": {}, "key": key}


static func _link(from_id: String, to_id: String, flow: int, key: String,
		subj: Dictionary = {}) -> Dictionary:
	return {"from": from_id, "to": to_id, "flow": flow, "subj": subj, "key": key}


static func _rest(id: String) -> String:
	return id.substr(id.get_slice(":", 0).length() + 1)


## A link type whose links are written down (data/ledger_static_links.csv,
## spec 2026-09-30-ledger-galaxy-design §3b): the crown's own figure, no
## Intel subject. The type level is one link counting them.
static func _static_links(row: Dictionary, repo: DataRepository, id: String, all: bool) -> Array:
	var out: Array = []
	for l: Dictionary in repo.ledger_static_links:
		if String(l["link_id"]) != String(row["link_id"]):
			continue
		if all or id == "" or id == String(l["from"]) or id == String(l["to"]):
			out.append(_link(String(l["from"]), String(l["to"]), int(l["flow"]), "count"))
	if id == "" and not all:
		return [_type_link(String(row["from_type"]), String(row["to_type"]), out.size(), "count")] \
			if not out.is_empty() else []
	return out


## The written-down node `id` (data/ledger_static_nodes.csv), or {}.
static func static_node(repo: DataRepository, id: String) -> Dictionary:
	for n: Dictionary in repo.ledger_static_nodes:
		if String(n["node_id"]) == id:
			return n
	return {}


## A manor's Intel subject, from ONE build per cell per memo — a galaxy asks
## for the same manor's subject from several readers (works, yields, holds,
## stands_on, part_of), each rebuilding MapTerrain.cell_center's vertex
## average afresh; a pure function of repo + cell, safe to cache for the
## length of one memo. The cached Dictionary is SHARED across every caller
## within that memo — callers must not mutate the returned `subj`.
static func _manor_subj(repo: DataRepository, cell: int) -> Dictionary:
	if not _memo_on:
		return _manor_subj_raw(repo, cell)
	var subjs: Dictionary = _memo.get("manor_subj", {})
	if not subjs.has(cell):
		subjs[cell] = _manor_subj_raw(repo, cell)
		_memo["manor_subj"] = subjs
	return subjs[cell]


static func _manor_subj_raw(repo: DataRepository, cell: int) -> Dictionary:
	return MissiveLog.subject("manor", MapManors.code_of(repo, cell), cell,
		MapTerrain.cell_center(repo, repo.cells[cell]))


static func _province_subj(repo: DataRepository, code: String) -> Dictionary:
	var prov: Dictionary = repo.provinces.get(code, {})
	return MissiveLog.subject("province", code, -1,
		Vector2(float(prov.get("center_x", 0.0)), float(prov.get("center_y", 0.0))))


## The crown's own intake a month — what reaches its two purses.
static func intake_of(repo: DataRepository, state: GameState) -> Dictionary:
	return _intake(repo, state)


static func _intake(repo: DataRepository, state: GameState) -> Dictionary:
	var p := RealmEconomy.purses(repo, state)
	var lord: Dictionary = p["lord"]
	var share: Dictionary = p["realm_share"]
	return {"tax": int(lord["tax"]) + int(share["tax"]),
		"strategic": int(lord["strategic"]) + int(share["strategic"]),
		"civil": int(lord["civil"]) + int(share["civil"])}


static func _controlled_manors(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for code: String in MapManors.controlled_provinces(repo, state):
		out.append_array(MapManors.manors_of_province(repo, code, state))
	return out


static func _works(repo: DataRepository, state: GameState, id: String) -> Array:
	if id == "":
		return [_type_link("peasants", "manor", TickEngine.court_people(repo, state), "people")]
	if id.begins_with("peasants:"):
		var out: Array = []
		for cell: int in MapManors.manors_of_province(repo, _rest(id), state):
			var line := RealmEconomy.line_of(repo, state, cell)
			out.append(_link(id, "manor:%d" % cell, int(line["people"]), "people", _manor_subj(repo, cell)))
		return out
	if id.begins_with("manor:"):
		var cell := int(_rest(id))
		var line := RealmEconomy.line_of(repo, state, cell)
		return [_link("peasants:" + MapManors.province_of(repo, cell, state), id,
			int(line["people"]), "people", _manor_subj(repo, cell))]
	return []


static func _part_of(repo: DataRepository, state: GameState, id: String) -> Array:
	if id == "":
		return [_type_link("manor", "province", _controlled_manors(repo, state).size(), "count")]
	if id.begins_with("manor:"):
		var cell := int(_rest(id))
		return [_link(id, "province:" + MapManors.province_of(repo, cell, state), -1, "count",
			_manor_subj(repo, cell))]
	if id.begins_with("province:"):
		var out: Array = []
		for cell: int in MapManors.manors_of_province(repo, _rest(id), state):
			out.append(_link("manor:%d" % cell, id, -1, "count", _manor_subj(repo, cell)))
		return out
	return []


## A manor's yield of `key` (tax, civil, strategic). The tax thread asks
## Intel by the fact key a spy files it under ("tax", SpySystem.report), so
## a report's estimate reaches it; the goods keep "gold" (no report carries
## them yet).
static func _yields(repo: DataRepository, state: GameState, id: String, key: String,
		to_t: String) -> Array:
	var fact := "tax" if key == "tax" else "gold"
	if id == "":
		return [_type_link("manor", to_t, int(_intake(repo, state)[key]), fact)]
	if id.begins_with("manor:"):
		var cell := int(_rest(id))
		var line := RealmEconomy.line_of(repo, state, cell)
		return [_link(id, "type:" + to_t, int(line[key]), fact, _manor_subj(repo, cell))]
	return []


static func _stands_on(repo: DataRepository, state: GameState, id: String) -> Array:
	if id == "":
		var n := 0
		var mine := MapManors.controlled_provinces(repo, state)
		for key: String in state.manor_buildings:
			if MapManors.province_of(repo, int(key), state) in mine:
				n += (state.manor_buildings[key] as Array).size()
		return [_type_link("building", "manor", n, "count")]
	if id.begins_with("manor:"):
		var cell := int(_rest(id))
		var out: Array = []
		for code: String in state.manor_buildings.get(str(cell), []):
			out.append(_link("building:%d:%s" % [cell, code], id, -1, "count", _manor_subj(repo, cell)))
		return out
	if id.begins_with("building:"):
		var cell := int(_rest(id).get_slice(":", 0))
		# a work still in hand stands on nothing yet (M5: the artisans raise it)
		if not MapManors.has_building(state, cell, _rest(id).get_slice(":", 1)):
			return []
		return [_link(id, "manor:%d" % cell, -1, "count", _manor_subj(repo, cell))]
	return []


static func _holds(repo: DataRepository, state: GameState, id: String) -> Array:
	if id == "":
		return [_type_link("house", "manor", _controlled_manors(repo, state).size(), "count")]
	if id.begins_with("house:"):
		var out: Array = []
		for cell: int in _manors_of_house(repo, state, _rest(id)):
			out.append(_link(id, "manor:%d" % cell, -1, "count", _manor_subj(repo, cell)))
		return out
	if id.begins_with("manor:"):
		var cell := int(_rest(id))
		var owner := String(MapManors.owner_of(repo, state, cell))
		return [] if owner == "" else [_link("house:" + owner, id, -1, "count", _manor_subj(repo, cell))]
	return []


static func _member(state: GameState, id: String) -> Array:
	if id == "":
		var n := 0
		for cid: String in state.characters:
			if (state.characters[cid] as Character).family_name != "":
				n += 1
		return [_type_link("character", "house", n, "count")]
	if id.begins_with("character:"):
		var c: Character = state.characters.get(_rest(id))
		return [] if c == null or c.family_name == "" else [_link(id, "house:" + c.family_name, -1, "count")]
	if id.begins_with("house:"):
		var out: Array = []
		var ids: Array = state.characters.keys()
		ids.sort()
		for cid: String in ids:
			if (state.characters[cid] as Character).family_name == _rest(id):
				out.append(_link("character:" + cid, id, -1, "count"))
		return out
	return []


static func _sits(state: GameState, id: String) -> Array:
	if id == "":
		return [_type_link("character", "seat", state.council.size(), "count")]
	if id.begins_with("character:"):
		var out: Array = []
		for seat: String in state.council:
			if String(state.council[seat]) == _rest(id):
				out.append(_link(id, "seat:" + seat, -1, "count"))
		return out
	if id.begins_with("seat:"):
		var cid := String(state.council.get(_rest(id), ""))
		return [] if cid == "" else [_link("character:" + cid, id, -1, "count")]
	return []


## The province a regiment has REACHED (ArmySystem.position_of), not the one
## the pack seeded it in.
static func _province_now(repo: DataRepository, state: GameState, reg: Dictionary) -> String:
	var at := ArmySystem.position_of(repo, state, reg)
	return Intel.province_of(repo, state, MissiveLog.subject("point", "", -1, at))


## Every regiment's province NOW (_province_now) plus its own row, from ONE
## pass — a galaxy asks `_based_in` once per province AND once per regiment,
## and each call scanned every regiment's position afresh (the costliest
## reader after `holds`'s house index, spec 2026-09-30-ledger-galaxy-design
## §3). Built once regardless of the memo (fix round 1, M2: no duplicated
## loop) and cached only while a memo is on, so `_based_in` never has to
## call `MapObjects.regiments_of` a second time to get at the regiment rows.
static func _regiment_provinces(repo: DataRepository, state: GameState) -> Dictionary:
	if _memo_on and _memo.has("regiment_provinces"):
		return _memo["regiment_provinces"]
	var idx := {}
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		idx[String(reg["regiment_code"])] = {"province": _province_now(repo, state, reg), "reg": reg}
	if _memo_on:
		_memo["regiment_provinces"] = idx
	return idx


static func _based_in(repo: DataRepository, state: GameState, id: String) -> Array:
	var here_of := _regiment_provinces(repo, state)
	if id == "":
		return [_type_link("regiment", "province", here_of.size(), "count")]
	var out: Array = []
	var codes: Array = here_of.keys()
	codes.sort()
	for code: String in codes:
		var entry: Dictionary = here_of[code]
		var here := String(entry["province"])
		if here == "":
			continue
		if id == "regiment:" + code or id == "province:" + here:
			var reg: Dictionary = entry["reg"]
			out.append(_link("regiment:" + code, "province:" + here, ArmySystem.headcount(repo, reg), "heads",
				MissiveLog.subject("regiment", code, -1, ArmySystem.position_of(repo, state, reg))))
	return out


static func _aim_province(repo: DataRepository, state: GameState, c: Dictionary) -> String:
	var px := ArmySystem.metres_to_pack(repo, Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"])))
	return Intel.province_of(repo, state, MissiveLog.subject("point", "", -1, px))


static func _couriers(repo: DataRepository, state: GameState, id: String, spy: bool) -> Array:
	var mine: Array = []
	for c: Dictionary in state.couriers:
		if (String(c["kind"]) == CourierSystem.SPY) == spy:
			mine.append(c)
	if id == "":
		return [_type_link("courier", "province" if spy else "regiment", mine.size(), "count")]
	var out: Array = []
	for c: Dictionary in mine:
		var cid := "courier:%d" % int(c["id"])
		var to := ("province:" + _aim_province(repo, state, c)) if spy else ("regiment:" + String(c["target"]))
		if to.ends_with(":"):
			continue
		if id == cid or id == to:
			out.append(_link(cid, to, -1, "count"))
	return out


static func _subject_node(to_t: String, subj: Dictionary) -> String:
	match to_t:
		"manor":
			return "manor:%d" % int(subj.get("cell", -1))
		"town":
			return "town:" + String(subj.get("code", ""))
	return to_t + ":" + String(subj.get("code", ""))


static func _describes(state: GameState, id: String, link_id: String, to_t: String) -> Array:
	var kind := String(REPORT_KINDS.get(link_id, ""))
	var about: Array = []
	for i in range(state.missives.size() - 1, -1, -1):  # newest first
		var m: Dictionary = state.missives[i]
		if String((m["subject"] as Dictionary).get("kind", "")) == kind:
			about.append(m)
	if id == "":
		return [_type_link("report", to_t, about.size(), "count")]
	var out: Array = []
	for m: Dictionary in about:
		var rid := "report:%d" % int(m["id"])
		var node := _subject_node(to_t, m["subject"])
		if id == rid or id == node:
			out.append(_link(rid, node, -1, "count"))
	return out


static func _relations(state: GameState, id: String, all: bool, rel_type: String) -> Array:
	if id == "" and not all:
		return []  # character to character: an instance tie only
	var out: Array = []
	for e: Dictionary in state.relationships:
		if String(e["type"]) != rel_type:
			continue
		var from := "character:" + String(e["from"])
		var to := "character:" + String(e["to"])
		if all or id == from or id == to:
			var l := _link(from, to, absi(int(e["sentiment"])), "sentiment")
			l["sentiment"] = int(e["sentiment"])
			out.append(l)
	return out


# --- the supply chain (spec 2026-09-30-ledger-supply-design §5) --------------
# Each reads the ONE plan function the tick settles, so the LEDGER's figures
# are the month's own; the crown's own depots, so every account is full.

static func _workshops(repo: DataRepository, state: GameState, id: String, inward: bool) -> Array:
	var rows := _workshop_plan(repo, state)
	var key := "take" if inward else "make"
	if id == "":
		var n := 0
		var said := 0
		for row: Dictionary in rows:
			n += int(row[key])
			said += int(row["claimed"])
		if inward:
			return [_type_link("civil_goods", "workshop", n, "gold")]
		var t := _type_link("workshop", "strategic_goods", n, "gold")
		t["claims"] = [{"value": said, "source": _governor_source(repo, state, "workshop")}]
		return [t]
	var out: Array = []
	for row: Dictionary in rows:
		var wid := "workshop:%d" % int(row["cell"])
		if id != wid:
			continue
		if inward:
			out.append(_link("type:civil_goods", wid, int(row["take"]), "gold"))
		else:
			var l := _link(wid, "type:strategic_goods", int(row["make"]), "gold")
			l["claims"] = [{"value": int(row["claimed"]), "source": _governor_source(repo, state, "workshop")}]
			out.append(l)
	return out


static func _supply(repo: DataRepository, state: GameState, id: String, inward: bool) -> Array:
	var rows := _supply_plan(repo, state)
	if id == "":
		var n := 0
		var said := 0
		for row: Dictionary in rows:
			n += int(row["paid"] if inward else row["delivered"])
			said += int(row["claimed"])
		if inward:
			return [_type_link("strategic_goods", "supply_line", n, "gold")]
		var t := _type_link("supply_line", "regiment", n, "units")
		t["claims"] = _supply_claims(repo, state, said, n, "the regiments' own count")
		return [t]
	var out: Array = []
	for row: Dictionary in rows:
		var code := String(row["code"])
		var line := "supply_line:" + code
		if inward and id == line:
			out.append(_link("type:strategic_goods", line, int(row["paid"]), "gold"))
		elif not inward and (id == line or id == "regiment:" + code):
			var l := _link(line, "regiment:" + code, int(row["delivered"]), "units")
			l["claims"] = _supply_claims(repo, state, int(row["claimed"]), int(row["delivered"]),
				"the regiment's own count")
			out.append(l)
	return out


## A supply line's two accounts (spec 2026-09-30-ledger-governors-design §4):
## what the marshal says he delivered, and what the regiment (or, at the
## type level, the regiments) counted in.
static func _supply_claims(repo: DataRepository, state: GameState, said: int, counted: int,
		counter: String) -> Array:
	return [{"value": said, "source": _governor_source(repo, state, "supply_line")},
		{"value": counted, "source": counter}]


## "Steward: Mirella of the Weighhouse" — the governor's word under HIS OWN
## seat's office, and "(given the supply lines)" when the flow was given
## away from its seat (fix round 1: Father Odo is the Chaplain).
static func _governor_source(repo: DataRepository, state: GameState, flow: String) -> String:
	var gid := Governance.governor_of(repo, state, flow)
	if gid == "":
		return "no one's account"
	var seats: Array = state.council.keys()
	seats.sort()
	var office := ""
	for seat: String in seats:
		if String(state.council[seat]) == gid:
			office = String((repo.seats.get(seat, {}) as Dictionary).get("label", seat))
			break
	var name := (state.characters[gid] as Character).display_name
	var out := name if office == "" else "%s: %s" % [office, name]
	var row: Dictionary = repo.ledger_governance.get(flow, {})
	if gid != String(state.council.get(String(row.get("seat", "")), "")):
		out += " (given %s)" % String(row.get("label", flow))
	return out


static func _instances_of_flow(repo: DataRepository, state: GameState, flow: String) -> Array:
	var out: Array = []
	match flow:
		"workshop":
			for c: int in WorkshopSystem.cells(repo, state):
				out.append("workshop:%d" % c)
		"supply_line":
			for row: Dictionary in _supply_plan(repo, state):
				out.append("supply_line:" + String(row["code"]))
		"trade_route":
			for row: Dictionary in _routes(repo, state):
				out.append("trade_route:" + String(row["kingdom"]))
		"works":
			# the building works are drawn on the artisans who do them
			for code: String in MapManors.controlled_provinces(repo, state):
				out.append("artisans:" + code)
		_:
			push_error("LedgerResolvers: no instances for flow '%s'" % flow)
	return out


## Who governs a flow's instances (spec §4): a tie (flow -1) from the man
## who governs it now to each workshop / supply line / trade route / the
## artisans of each province. The link row's to_type names the flow through
## its LEDGER type (Governance.flow_of_type: the artisans are the works').
static func _governs(repo: DataRepository, state: GameState, id: String, to_t: String) -> Array:
	var flow := Governance.flow_of_type(repo, to_t)
	var gid := Governance.governor_of(repo, state, flow)
	if gid == "":
		# An empty seat (final review M8): the type level still draws the tie,
		# greyed and saying no one governs it; there is no man to draw it from
		# at the instance level.
		if id != "":
			return []
		var t := _type_link("character", to_t, -1, "count")
		t["vacant"] = true
		return [t]
	if id == "":
		return [_type_link("character", to_t, -1, "count")]
	var who := "character:" + gid
	var out: Array = []
	for node: String in _instances_of_flow(repo, state, flow):
		if id == node or id == who:
			out.append(_link(who, node, -1, "count"))
	return out


## What an audit caught (spec §4, fix round 1 ruling): ONE link per caught
## man and flow, character -> the flow's TYPE, carrying his caught total on
## it. Keyed on GameState.caught — whoever was caught, governor now or not —
## so it survives a handover; drawn on his own ego (and the type level),
## never on a workshop's or a supply line's.
static func _skims(repo: DataRepository, state: GameState, id: String, to_t: String) -> Array:
	var flow := Governance.flow_of_type(repo, to_t)
	var ids: Array = state.caught.keys()
	ids.sort()
	var all := 0
	var out: Array = []
	for gid: String in ids:
		var total := 0
		for hit: Dictionary in state.caught[gid]:
			if String(hit["flow"]) == flow:
				total += int(hit["amount"])
		all += total
		if total > 0 and id == "character:" + gid:
			out.append(_link(id, "type:" + to_t, total, "gold"))
	if id == "":
		return [_type_link("character", to_t, all, "gold")] if all > 0 else []
	return out


## A regiment under a GARRISON order in a province the crown controls
## stands in that province's capital town (SupplySystem.garrisoned_in; one
## merely standing by there draws through the town but is not garrisoned).
static func _garrisons(repo: DataRepository, state: GameState, id: String) -> Array:
	var codes: Array = state.regiments.keys()
	codes.sort()
	var out: Array = []
	for c in codes:
		var town := SupplySystem.garrisoned_in(repo, state, String(c))
		if town == "":
			continue
		var rid := "regiment:" + String(c)
		if id == "" or id == rid or id == "town:" + town:
			out.append(_link(rid, "town:" + town, -1, "count"))
	if id == "":
		return [_type_link("regiment", "town", out.size(), "count")]
	return out


# --- industry and trade (spec 2026-09-30-ledger-industry-trade-design) -------
# Each reads the ONE function the tick settles (IndustrySystem.plan,
# MapManors.work_speed_permille, MarketSystem.routes / market_value): the
# crown's own books, every account full.

## The pool a goods type sphere stands for.
static func _pool_of_type(to_t: String) -> String:
	return "strategic" if to_t == "strategic_goods" else "civil"


## The buildings the artisans of a crown province raise: every building
## standing, or in work, on a crown manor of that province, cells ascending,
## codes sorted. [[cell, code]].
static func _raised_in(repo: DataRepository, state: GameState, province: String) -> Array:
	var out: Array = []
	for cell: int in MapManors.manors_of_province(repo, province, state):
		if not MapManors.is_crowns(repo, state, cell):
			continue
		var codes: Array = MapManors.buildings_of(state, cell)
		for w: Dictionary in MapManors.works_of(state, cell):
			if not String(w["building"]) in codes:
				codes.append(String(w["building"]))
		codes.sort()
		for code: String in codes:
			out.append([cell, code])
	return out


## artisans -> building (M5): the pace the artisans add to a province's
## works, per mille over the plain 1000 (work_speed_permille − 1000). The type
## level carries the home province's bonus.
static func _builds(repo: DataRepository, state: GameState, id: String) -> Array:
	if id == "":
		var home := MapManors.home_province(repo, state)
		var bonus := 0 if home == "" else MapManors.work_speed_permille(repo, state, home) - 1000
		return [_type_link("artisans", "building", bonus, "permille")]
	var provinces: Array = []
	if id.begins_with("artisans:"):
		provinces = [_rest(id)]
	elif id.begins_with("building:"):
		provinces = [MapManors.province_of(repo, int(_rest(id).get_slice(":", 0)), state)]
	var mine := MapManors.controlled_provinces(repo, state)
	var out: Array = []
	for p: String in provinces:
		if not p in mine:
			continue
		var bonus := MapManors.work_speed_permille(repo, state, p) - 1000
		for pair: Array in _raised_in(repo, state, p):
			var bid := "building:%d:%s" % [int(pair[0]), String(pair[1])]
			if id == bid or id == "artisans:" + p:
				out.append(_link("artisans:" + p, bid, bonus, "permille"))
	return out


## building -> civil / strategic goods (M5): the gold of inputs a building
## buys from the lord's pool of `to_t` a month (IndustrySystem.plan's rows of
## that pool, summed per building); the type level every building's.
static func _consumes(repo: DataRepository, state: GameState, id: String, to_t: String) -> Array:
	var pool := _pool_of_type(to_t)
	var by: Dictionary = {}  # building node id -> gold, in the plan's order
	var total := 0
	for row: Dictionary in _industry_plan(repo, state):
		if String(row["pool"]) != pool:
			continue
		var bid := "building:%d:%s" % [int(row["cell"]), String(row["code"])]
		by[bid] = int(by.get(bid, 0)) + int(row["gold"])
		total += int(row["gold"])
	if id == "":
		return [_type_link("building", to_t, total, "gold")]
	return [_link(id, "type:" + to_t, int(by[id]), "gold")] if by.has(id) else []


## market -> civil / strategic goods (M6): a realm market's stock of the
## pool's goods at its own prices (MarketSystem.market_value); the type
## level every realm market's.
static func _trades(repo: DataRepository, state: GameState, id: String, to_t: String) -> Array:
	var pool := _pool_of_type(to_t)
	var markets := MarketSystem.realm_markets(repo, state)
	if id == "":
		var total := 0
		for m: String in markets:
			total += MarketSystem.market_value(repo, m, pool)
		return [_type_link("market", to_t, total, "gold")]
	if id.begins_with("market:") and _rest(id) in markets:
		return [_link(id, "type:" + to_t, MarketSystem.market_value(repo, _rest(id), pool), "gold")]
	return []


## trade_route -> gold (M6): the toll a route pays the treasury a month, as
## a governed flow (spec 2026-09-30-ledger-governors-design §4): the
## steward's word (the toll he collects, whole) and the treasury's own count
## (what reaches it, less his skim) — a venal steward splits the thread.
static func _routes_to_gold(repo: DataRepository, state: GameState, id: String) -> Array:
	var rows := _routes(repo, state)
	if id == "":
		var said := 0
		var paid := 0
		for r: Dictionary in rows:
			said += int(r["claimed"])
			paid += int(r["toll"])
		var t := _type_link("trade_route", "gold", paid, "gold")
		t["claims"] = _toll_claims(repo, state, said, paid)
		return [t]
	var out: Array = []
	for r: Dictionary in rows:
		var rid := "trade_route:" + String(r["kingdom"])
		if id != rid:
			continue
		var l := _link(rid, "type:gold", int(r["toll"]), "gold")
		l["claims"] = _toll_claims(repo, state, int(r["claimed"]), int(r["toll"]))
		out.append(l)
	return out


static func _toll_claims(repo: DataRepository, state: GameState, said: int, paid: int) -> Array:
	return [{"value": said, "source": _governor_source(repo, state, "trade_route")},
		{"value": paid, "source": "the treasury's own count"}]


# --- properties (spec 2026-09-30-ledger-ontology-design §6.3 "a property") ---

## The gauges a sphere carries: [{key, label, value, max}], whole numbers.
## A regiment the crown knows in full (its own; any in DEV MODE) carries its
## supply score (ArmySystem.bars_of, per mille) and its morale (0..100); the
## civil and strategic goods TYPE spheres carry the crown's and the lord's
## stock against ledger_gauge_stock_months of the month's intake. Anything
## else carries none.
static func props_of(repo: DataRepository, state: GameState, id: String) -> Array:
	match id:
		"type:civil_goods":
			return [_stock(repo, state, "civil", ["grain", "lord_civil"])]
		"type:strategic_goods":
			return [_stock(repo, state, "strategic", ["strategic", "lord_strategic"])]
	if not id.begins_with("regiment:"):
		return []
	var code := _rest(id)
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty():
		return []
	var subj := MissiveLog.subject("regiment", code, -1, ArmySystem.position_of(repo, state, reg))
	if Intel.level(repo, state, subj) != "full":
		return []
	var st := ArmySystem.state_of(repo, state, code)
	if st.is_empty():
		st = ArmySystem.starting_state(repo, reg)  # a foreign regiment, read as it would start
	return [{"key": "supplies", "label": "Supplies", "value": ArmySystem.bars_of(repo, state, code).y, "max": 1000},
		{"key": "morale", "label": "Morale", "value": clampi(int(st["morale"]), 0, 100), "max": 100}]


static func _stock(repo: DataRepository, state: GameState, pool: String, metrics: Array) -> Dictionary:
	var n := 0
	for m: String in metrics:
		n += maxi(int(state.metrics.get(m, 0.0)), 0)
	var cap := maxi(int(_intake(repo, state)[pool]) * int(repo.bal("ledger_gauge_stock_months")), 1)
	return {"key": "stock", "label": "Stock", "value": n, "max": cap}


# --- instances and names ---------------------------------------------------

static func instances(name: String, repo: DataRepository, state: GameState, type_id: String = "") -> Array:
	var out: Array = []
	var realm := repo.resolve_realm("player_realm")
	match name:
		"peasants":
			for code: String in MapManors.controlled_provinces(repo, state):
				out.append({"id": "peasants:" + code, "strain": 0})
		"manors":
			for cell: int in _controlled_manors(repo, state):
				out.append({"id": "manor:%d" % cell,
					"strain": int(RealmEconomy.line_of(repo, state, cell)["people"])})
		"provinces":
			for code: String in MapOwnership.provinces_of(repo, state, realm):
				out.append({"id": "province:" + code, "strain": 2 - int(state.wealth_tiers.get(code, 1))})
		"regiments":
			for reg: Dictionary in MapObjects.regiments_of(repo, realm):
				var code := String(reg["regiment_code"])
				out.append({"id": "regiment:" + code, "strain": 1000 - ArmySystem.bars_of(repo, state, code).x})
		"characters":
			for cid: String in state.characters:
				out.append({"id": "character:" + cid, "strain": -(state.characters[cid] as Character).opinion})
		"houses":
			var seen := {}
			for code: String in MapOwnership.provinces_of(repo, state, realm):
				var fam := MapObjects.house_name_of(repo, code)
				if fam != "" and not seen.has(fam):
					seen[fam] = true
					out.append({"id": "house:" + fam, "strain": 0})
		"seats":
			for seat: String in repo.seats:
				out.append({"id": "seat:" + seat, "strain": 0 if state.council.has(seat) else 1})
		"reports":
			for m: Dictionary in state.missives:
				out.append({"id": "report:%d" % int(m["id"]), "strain": int(m["day"])})
		"couriers":
			for c: Dictionary in state.couriers:
				out.append({"id": "courier:%d" % int(c["id"]), "strain": int(c.get("days", 0))})
		"workshops":
			for c: int in WorkshopSystem.cells(repo, state):
				out.append({"id": "workshop:%d" % c, "strain": 1000 - WorkshopSystem.rate_of(state, c)})
		"supply_lines":
			for row: Dictionary in _supply_plan(repo, state):
				out.append({"id": "supply_line:" + String(row["code"]), "strain": int(row["loss_permille"])})
		"artisans":
			for code: String in MapManors.controlled_provinces(repo, state):
				out.append({"id": "artisans:" + code,
					"strain": MapManors.work_speed_permille(repo, state, code) - 1000})
		"markets":
			for m: String in MarketSystem.realm_markets(repo, state):
				out.append({"id": "market:" + m, "strain": MarketSystem.market_value(repo, m, "civil")
					+ MarketSystem.market_value(repo, m, "strategic")})
		"trade_routes":
			for r: Dictionary in _routes(repo, state):
				out.append({"id": "trade_route:" + String(r["kingdom"]), "strain": int(r["value"])})
		"static":
			for n: Dictionary in repo.ledger_static_nodes:
				if String(n["type_id"]) == type_id:
					out.append({"id": String(n["node_id"]), "strain": 0})
	for row: Dictionary in out:
		row["label"] = label_of(repo, state, String(row["id"]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["strain"]) != int(b["strain"]):
			return int(a["strain"]) > int(b["strain"])
		return String(a["label"]) < String(b["label"]))
	return out


## A node's name, or "" when what it names no longer exists, cached per id
## within one memo (fix round: the galaxy's worklist checks a new end's
## label once to tell whether it still exists, then `_node` asked for the
## same label again to build it — a manor's or a building's label rebuilds
## MapManors.label_of's lookups each time, doubling the cost of every newly
## discovered node and pushing the galaxy over its ms budget).
static func label_of(repo: DataRepository, state: GameState, id: String) -> String:
	if not _memo_on:
		return _label_of_raw(repo, state, id)
	var cache: Dictionary = _memo.get("label_of", {})
	if not cache.has(id):
		cache[id] = _label_of_raw(repo, state, id)
		_memo["label_of"] = cache
	return cache[id]


static func _label_of_raw(repo: DataRepository, state: GameState, id: String) -> String:
	var written := static_node(repo, id)
	if not written.is_empty():
		return String(written["label"])
	var kind := id.get_slice(":", 0)
	var rest := _rest(id)
	match kind:
		"type":
			for r: Dictionary in repo.ledger_types:
				if String(r["type_id"]) == rest:
					return String(r["label"])
			return ""
		"manor":
			return MapManors.label_of(repo, int(rest)) if repo.manors.has(int(rest)) else ""
		"province":
			return String((repo.provinces.get(rest, {}) as Dictionary).get("label", ""))
		"peasants":
			var p := String((repo.provinces.get(rest, {}) as Dictionary).get("label", ""))
			return "" if p == "" else "Peasants of " + p
		"town":
			return String((repo.burgs.get(rest, {}) as Dictionary).get("label", ""))
		"building":
			var cell := int(rest.get_slice(":", 0))
			var b: Dictionary = repo.manor_buildings.get(rest.get_slice(":", 1), {})
			# a building that no longer stands (demolished) names nothing; one
			# still in work is named as a work (M5: the artisans raise it)
			if b.is_empty() or not repo.manors.has(cell):
				return ""
			if MapManors.has_building(state, cell, rest.get_slice(":", 1)):
				return "%s at %s" % [String(b["label"]), MapManors.label_of(repo, cell)]
			if MapManors.is_building(state, cell, rest.get_slice(":", 1)):
				return "%s at %s (in work)" % [String(b["label"]), MapManors.label_of(repo, cell)]
			return ""
		"artisans":
			# The artisans are the LEDGER's own (M5: work_speed_permille gives
			# the plain 1000‰ outside a controlled province, Minor2) — one not
			# controlled names nothing, and the focus falls back to whatever
			# reads it next.
			if not MapManors.controlled_provinces(repo, state).has(rest):
				return ""
			var p := String((repo.provinces.get(rest, {}) as Dictionary).get("label", ""))
			return "" if p == "" else "Artisans of " + p
		"market":
			# A market not the crown's own kingdom's names nothing (Task 4
			# ruled minors): a foreign market is not the LEDGER's to show.
			if not MarketSystem.is_realm_market(repo, state, rest):
				return ""
			var town := String((repo.world_table("economy", "markets").get(rest, {}) as Dictionary).get(
				"center_burg", ""))
			return "" if town == "" else "Market of " + String((repo.burgs.get(town, {}) as Dictionary).get(
				"label", town))
		"trade_route":
			for r: Dictionary in _routes(repo, state):
				if String(r["kingdom"]) == rest:
					return "Trade with " + MarketSystem.label_of(repo, rest)
			return ""
		"character":
			var c: Character = state.characters.get(rest)
			return "" if c == null else c.display_name
		"house":
			return "" if rest == "" else "House " + rest
		"seat":
			return String((repo.seats.get(rest, {}) as Dictionary).get("label", ""))
		"regiment":
			return String(ArmySystem.regiment(repo, rest).get("label", ""))
		"workshop":
			return "War workshop at " + MapManors.label_of(repo, int(rest)) \
				if rest.is_valid_int() and int(rest) in WorkshopSystem.cells(repo, state) else ""
		"supply_line":
			var reg := ArmySystem.regiment(repo, rest)
			# one per supplied regiment: a land regiment of the crown's (a fleet has none)
			return "Supply line to " + String(reg["label"]) \
				if not reg.is_empty() and state.regiments.has(rest) \
					and String(reg.get("is_naval", "0")) != "1" else ""
		"courier":
			for c: Dictionary in state.couriers:
				if str(int(c["id"])) == rest:
					return ("Spy #" if String(c["kind"]) == CourierSystem.SPY else "Courier #") + rest
			return ""
		"report":
			return String(MissiveLog.find(state, int(rest)).get("title", ""))
		"more":
			return "+%s more" % rest.get_slice(":", 1)
	return ""
