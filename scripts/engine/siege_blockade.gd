class_name SiegeBlockade
extends RefCounted
## The blockade of a besieged town (player siege spec docs/superpowers/specs/
## 2026-11-18-player-siege-design.md §4.1, step 6). A record's `entries`: entry
## id (a pack route's code, or "countryside") -> {group, x_m, y_m,
## inflow_share (per mille, the town's entries sum to 1000), closed_by (the
## besieging unit holding it shut, "" while open)}. Its `stores`: a town with
## no TownStores (any but the crown's) opens with need x siege_tactics.csv
## stores_days and moves by stores_day; a crown town keeps 0 there and eats
## from TownStores, whose inflows its open share gates (TownStores.deposit_month,
## SupplyLines.siege_cut). Whole numbers, code order, no random number.

const COUNTRYSIDE := "countryside"
const SEA := "searoutes"


## The town's entries, all open: one per pack route that ends at it, on the
## route siege_entry_km from its end nearest the town, and the countryside at
## the town's point. Raw shares (siege_entries.csv by group) normalised to 1000.
static func entries_of(repo: DataRepository, town: String) -> Dictionary:
	var home := ArmyGround.town_point_m(repo, town)
	var b: Dictionary = repo.burgs.get(town, {})
	var town_px := Vector2(float(b.get("x", 0)), float(b.get("y", 0)))
	var raw := {COUNTRYSIDE: int(repo.siege_entries.get(COUNTRYSIDE, 0))}
	var out := {COUNTRYSIDE: {"group": COUNTRYSIDE, "x_m": home.x, "y_m": home.y}}
	var codes: Array = repo.routes.keys()
	codes.sort()
	for code: String in codes:
		var r: Dictionary = repo.routes[code]
		var line: PackedVector2Array = r.get("polyline", PackedVector2Array())
		if line.size() < 2 or town not in [String(r.get("from_burg", "")), String(r.get("to_burg", ""))]:
			continue
		var at := ArmySystem.pack_to_metres(repo, _along(repo, line, town_px))
		var group := String(r.get("group", ""))
		raw[code] = int(repo.siege_entries.get(group, 0))
		out[code] = {"group": group, "x_m": at.x, "y_m": at.y}
	var shares := TownStores.apportion(1000, raw)
	for e: String in out:
		out[e]["inflow_share"] = int(shares[e])
		out[e]["closed_by"] = ""
	return out


## The point siege_entry_km along `line` from its end nearer `town_px` (its
## far end when the route is shorter), pack px.
static func _along(repo: DataRepository, line: PackedVector2Array, town_px: Vector2) -> Vector2:
	var pts := line
	if line[line.size() - 1].distance_squared_to(town_px) < line[0].distance_squared_to(town_px):
		pts = line.duplicate()
		pts.reverse()
	var left := float(repo.bal("siege_entry_km")) * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
	for i in range(1, pts.size()):
		var step := pts[i - 1].distance_to(pts[i])
		if step >= left:
			return pts[i - 1].lerp(pts[i], left / step) if step > 0.0 else pts[i]
		left -= step
	return pts[pts.size() - 1]


## The town's food a day, supply units: its defenders' daily ration
## (ArmySystem.day_bite of each one's supply_use) plus population x
## siege_civil_need_permille / 1000.
static func need(repo: DataRepository, state: GameState, town: String) -> int:
	var total := 0
	for c: String in SiegeSystem.defenders_of(repo, state, town):
		total += ArmySystem.day_bite(ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c, state), state), state.day)
	@warning_ignore("integer_division")  # whole supply units
	total += int((repo.burgs.get(town, {}) as Dictionary).get("population", 0)) * int(repo.bal("siege_civil_need_permille")) / 1000
	return total


## The stores a town with no TownStores opens with: need x stores_days of its
## works (TownMilitia.works_of_town); 0 for a crown town (TownStores feeds it).
static func opening_stores(repo: DataRepository, state: GameState, id: String) -> int:
	var rec: Dictionary = state.sieges[id]
	var town := String(rec["town"])
	if String(rec["defender"]) == repo.resolve_realm("player_realm"):
		return 0
	var days := int((repo.siege_tactics.get(TownMilitia.works_of_town(repo, town), {}) as Dictionary).get("stores_days", 0))
	return need(repo, state, town) * days


## Sets a record's entries and stores when it has none (its opening; an old
## save's record on its first day).
static func ensure(repo: DataRepository, state: GameState, id: String) -> void:
	var rec: Dictionary = state.sieges[id]
	if not rec.has("entries"):
		rec["entries"] = entries_of(repo, String(rec["town"]))
	if not rec.has("stores"):
		rec["stores"] = opening_stores(repo, state, id)


## One day of stores (spec §4.1): max(0, stores − need + need × open_share / 1000).
static func stores_day(stores: int, day_need: int, share: int) -> int:
	@warning_ignore("integer_division")  # whole supply units
	return maxi(0, stores - day_need + day_need * share / 1000)


## The per-mille share of a record's open entries (1000 with no entries).
static func open_share(rec: Dictionary) -> int:
	var entries: Dictionary = rec.get("entries", {})
	if entries.is_empty():
		return 1000
	var share := 0
	for e: String in entries:
		if String(entries[e].get("closed_by", "")) == "":
			share += int(entries[e]["inflow_share"])
	return share


## The besiegers close the entries (spec §4.1): every entry but a sea one, by
## share descending then id, takes the stationed besiegers (SiegeSystem.stationed)
## until it holds siege_blockade_men_per_entry fit men — first those already
## standing at it (a road entry; code order), then the others in code order;
## an entry short of them stays open, and so does every entry after it. A unit
## closes one entry at most. The closing units camp at it (_camp), and its closed_by
## is the first of them that stands at it (_holds), else "".
static func close(repo: DataRepository, state: GameState, id: String) -> void:
	var rec: Dictionary = state.sieges[id]
	var town := String(rec["town"])
	var entries: Dictionary = rec["entries"]
	var order: Array = []
	for e: String in entries:
		entries[e]["closed_by"] = ""
		if String(entries[e]["group"]) != SEA:
			order.append(e)
	order.sort_custom(func(a: String, b: String) -> bool:
		var sa := int(entries[a]["inflow_share"])
		var sb := int(entries[b]["inflow_share"])
		return sa > sb or (sa == sb and a < b))
	var free := SiegeSystem.stationed(repo, state, id)
	free.sort()
	# a unit already standing at a road entry keeps it, so an arrival that
	# sorts first does not move the blockade round
	var standing: Dictionary = {}
	for e: String in order:
		standing[e] = []
		if String(entries[e]["group"]) == COUNTRYSIDE:
			continue
		for c: String in free.duplicate():
			if _holds(repo, state, c, entries[e], town):
				standing[e].append(c)
				free.erase(c)
	var per := int(repo.bal("siege_blockade_men_per_entry"))
	for e: String in order:
		var pool: Array = (standing[e] as Array) + free
		var men := 0
		var mine: Array = []
		while men < per and not pool.is_empty():
			var c := String(pool.pop_front())
			men += ArmySystem.fit_count(repo, state, c)
			mine.append(c)
			free.erase(c)
		for c: String in standing[e]:
			if not c in mine and not c in free:
				free.append(c)   # more than the entry needs: free for the next
		free.sort()
		if men < per or per <= 0:
			break
		var entry: Dictionary = entries[e]
		for c: String in mine:
			_camp(repo, state, c, entry, town)
		for c: String in mine:
			if _holds(repo, state, c, entry, town):
				entry["closed_by"] = c
				break


## True when unit `code` stands at the entry: for the countryside, stationed
## at the town (SiegeSystem.deployed_at); else within siege_entry_reach_m of
## its point.
static func _holds(repo: DataRepository, state: GameState, code: String, entry: Dictionary, town: String) -> bool:
	if ArmySystem.fit_count(repo, state, code) <= 0 or not SiegeSystem.deployed_at(repo, state, code, town):
		return false
	if String(entry["group"]) == COUNTRYSIDE:
		return true
	var reach := int(repo.bal("siege_entry_reach_m"))
	return MarchClearance.dist2(BattleSystem._at_m(repo, state, code), Vector2i(int(entry["x_m"]), int(entry["y_m"]))) \
		<= reach * reach


## A closing unit not yet at its entry camps on its point when the ground is
## free (ArmyGround.free_slot, as a host's columns spread round their target),
## never while it fights a battle or carries bodies (body_groups); else it
## stays where it stands and the entry waits for it.
static func _camp(repo: DataRepository, state: GameState, code: String, entry: Dictionary, town: String) -> void:
	if _holds(repo, state, code, entry, town) or not BattleSystem.battle_of(state, code).is_empty():
		return
	var e := BattleSystem._stored(state, code)
	if e.is_empty() or e.has("body_groups"):
		return
	var point := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	var arm := MapObjects.regiment_arm(repo, ArmySystem.regiment(repo, code, state))
	var taken := ArmyGround.held_taken(repo, state, code)
	var reach := int(repo.bal("siege_entry_reach_m"))
	var at := Vector2i(int(e["x_m"]), int(e["y_m"]))
	var slot := ArmyGround.free_slot(repo, point, arm, taken, "", false, at, 0, reach)
	if slot == ArmyGround.NONE:
		slot = ArmyGround.free_slot(repo, point, arm, taken, "", true, at, 0, reach)
	if slot == ArmyGround.NONE:
		return
	e["x_m"] = slot.x
	e["y_m"] = slot.y
	e["dest_x_m"] = slot.x
	e["dest_y_m"] = slot.y


## Record `id`'s blockade day (SiegeSystem._siege_day, after the assault):
## the entries close; a town with no TownStores moves its stores and, at 0,
## each of its defenders' morale falls army_morale_starving_day (a crown
## garrison's hunger is ArmySystem.hunger_day's, off its own supplies).
## Returns {open_share, stores}.
static func day(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	ensure(repo, state, id)
	close(repo, state, id)
	var rec: Dictionary = state.sieges[id]
	var share := open_share(rec)
	var town := String(rec["town"])
	if String(rec["defender"]) != repo.resolve_realm("player_realm"):
		rec["stores"] = stores_day(int(rec["stores"]), need(repo, state, town), share)
		if int(rec["stores"]) == 0:
			var loss := int(repo.bal("army_morale_starving_day"))
			for c: String in SiegeSystem.defenders_of(repo, state, town):
				if state.foes.has(c):
					state.foes[c]["morale"] = maxi(0, int(state.foes[c].get("morale", 0)) - loss)
	return {"open_share": share, "stores": int(rec["stores"])}


## The defenders' morale, weighted by their fit men; 0 with none.
static func mean_morale(repo: DataRepository, state: GameState, town: String) -> int:
	var men := 0
	var sum := 0
	for c: String in SiegeSystem.defenders_of(repo, state, town):
		var fit := ArmySystem.fit_count(repo, state, c)
		men += fit
		sum += fit * int(BattleSystem._stored(state, c).get("morale", 0))
	@warning_ignore("integer_division")  # whole morale
	return sum / men if men > 0 else 0


## True when the town yields to hunger (spec §4.1): it starves
## (SiegeSystem.starving), its defenders' mean morale is below
## siege_yield_morale, its first defender's own_surrender is allow and the
## first stationed besieger's quarter is give (code order each).
static func yields(repo: DataRepository, state: GameState, id: String) -> bool:
	var town := String(state.sieges[id]["town"])
	var defs := SiegeSystem.defenders_of(repo, state, town)
	var besiegers := SiegeSystem.stationed(repo, state, id)
	besiegers.sort()
	if defs.is_empty() or besiegers.is_empty() or not SiegeSystem.starving(repo, state, town) \
			or mean_morale(repo, state, town) >= int(repo.bal("siege_yield_morale")):
		return false
	return LawSystem.value(repo, state, "own_surrender", String(defs[0])) == "allow" \
		and LawSystem.value(repo, state, "quarter", String(besiegers[0])) == "give"


## The hand-over with no terms (spec §4.1, §7): every defender's fit and
## wounded become captives of the first stationed besieger
## (PrisonerSystem.capture, reason "<town> yielded to hunger"), and the
## prisoners they held pass to it. Returns the capture's result ({error} when
## it cannot be made; then nothing moved).
static func hand_over(repo: DataRepository, state: GameState, id: String) -> Dictionary:
	var town := String(state.sieges[id]["town"])
	var besiegers := SiegeSystem.stationed(repo, state, id)
	besiegers.sort()
	var defs := SiegeSystem.defenders_of(repo, state, town)
	if besiegers.is_empty() or defs.is_empty():
		return {"error": "no one to yield to"}
	var captor := String(besiegers[0])
	var changes: Array = []
	for code: String in defs:
		for cohort_id: String in state.military_rosters.get(code, {}).get("cohort_ids", []):
			var cohort: Dictionary = state.military_cohorts[cohort_id]
			for from: String in ["fit", "wounded"]:
				if int(cohort.get(from, 0)) > 0:
					changes.append({"cohort_id": cohort_id, "from": from, "to": "captured_current",
						"count": int(cohort[from])})
	if changes.is_empty():
		return {"error": "no one left to yield"}
	var label := String((repo.burgs.get(town, {}) as Dictionary).get("label", town))
	var out := PrisonerSystem.capture(repo, state, {"capture_id": "siege_yield:%s:%d" % [id, state.absolute_day()],
		"participants": {captor: 1}, "changes": changes, "reason": "%s yielded to hunger" % label})
	if out.has("error"):
		return out
	var controllers: Array[String] = [captor]
	for code: String in defs:
		PrisonerSystem.holder_defeated(repo, state, code, controllers, "siege_yield_custody:%s:%s" % [id, code])
	return out
