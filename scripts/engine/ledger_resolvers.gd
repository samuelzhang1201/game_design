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
	"describes", "court_relations", "converts_in", "converts_out", "supplies_in", "supplies_out", "garrisons"]
const INSTANCE_LISTS := ["peasants", "manors", "provinces", "regiments", "characters", "houses",
	"seats", "reports", "couriers", "workshops", "supply_lines"]
const REPORT_KINDS := {"describes_province": "province", "describes_manor": "manor",
	"describes_regiment": "regiment", "describes_town": "burg"}


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
	return []


# --- the links -------------------------------------------------------------

static func _type_link(from_t: String, to_t: String, flow: int, key: String) -> Dictionary:
	return {"from": "type:" + from_t, "to": "type:" + to_t, "flow": flow, "subj": {}, "key": key}


static func _link(from_id: String, to_id: String, flow: int, key: String,
		subj: Dictionary = {}) -> Dictionary:
	return {"from": from_id, "to": to_id, "flow": flow, "subj": subj, "key": key}


static func _rest(id: String) -> String:
	return id.substr(id.get_slice(":", 0).length() + 1)


static func _manor_subj(repo: DataRepository, cell: int) -> Dictionary:
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
		return [_link(id, "manor:%d" % cell, -1, "count", _manor_subj(repo, cell))]
	return []


static func _holds(repo: DataRepository, state: GameState, id: String) -> Array:
	if id == "":
		return [_type_link("house", "manor", _controlled_manors(repo, state).size(), "count")]
	if id.begins_with("house:"):
		var out: Array = []
		for cell: int in MapManors.manors_of_house(repo, state, _rest(id)):
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


static func _based_in(repo: DataRepository, state: GameState, id: String) -> Array:
	var regs := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))
	if id == "":
		return [_type_link("regiment", "province", regs.size(), "count")]
	var out: Array = []
	for reg: Dictionary in regs:
		var code := String(reg["regiment_code"])
		var here := _province_now(repo, state, reg)
		if here == "":
			continue
		if id == "regiment:" + code or id == "province:" + here:
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
	var rows := WorkshopSystem.plan(repo, state)
	var key := "take" if inward else "make"
	if id == "":
		var n := 0
		for row: Dictionary in rows:
			n += int(row[key])
		return [_type_link("civil_goods", "workshop", n, "gold") if inward
			else _type_link("workshop", "strategic_goods", n, "gold")]
	var out: Array = []
	for row: Dictionary in rows:
		var wid := "workshop:%d" % int(row["cell"])
		if id == wid:
			out.append(_link("type:civil_goods", wid, int(row[key]), "gold") if inward
				else _link(wid, "type:strategic_goods", int(row[key]), "gold"))
	return out


static func _supply(repo: DataRepository, state: GameState, id: String, inward: bool) -> Array:
	var rows := SupplySystem.plan(repo, state)
	if id == "":
		var n := 0
		for row: Dictionary in rows:
			n += int(row["paid"] if inward else row["delivered"])
		return [_type_link("strategic_goods", "supply_line", n, "gold") if inward
			else _type_link("supply_line", "regiment", n, "units")]
	var out: Array = []
	for row: Dictionary in rows:
		var code := String(row["code"])
		var line := "supply_line:" + code
		if inward and id == line:
			out.append(_link("type:strategic_goods", line, int(row["paid"]), "gold"))
		elif not inward and (id == line or id == "regiment:" + code):
			out.append(_link(line, "regiment:" + code, int(row["delivered"]), "units"))
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

static func instances(name: String, repo: DataRepository, state: GameState) -> Array:
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
			for row: Dictionary in SupplySystem.plan(repo, state):
				out.append({"id": "supply_line:" + String(row["code"]), "strain": int(row["loss_permille"])})
	for row: Dictionary in out:
		row["label"] = label_of(repo, state, String(row["id"]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["strain"]) != int(b["strain"]):
			return int(a["strain"]) > int(b["strain"])
		return String(a["label"]) < String(b["label"]))
	return out


## A node's name, or "" when what it names no longer exists.
static func label_of(repo: DataRepository, state: GameState, id: String) -> String:
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
			# a building that no longer stands (demolished) names nothing
			if b.is_empty() or not repo.manors.has(cell) \
					or not MapManors.has_building(state, cell, rest.get_slice(":", 1)):
				return ""
			return "%s at %s" % [String(b["label"]), MapManors.label_of(repo, cell)]
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
