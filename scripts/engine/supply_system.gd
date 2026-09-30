class_name SupplySystem
extends RefCounted
## Supply lines (spec 2026-09-30-ledger-supply-design §3): each land
## regiment of the realm is refilled every month to army_supply_target_months
## of its own use, shipped from the depot (CourierSystem.origin) over the
## road network to where it stands NOW; the road loses
## army_supply_loss_permille_per_100km per 100 km (capped). A regiment
## STANDING (standby or garrison — anything but a march) in a province the
## crown controls draws through that province's capital town: no road, no
## loss (controller ruling, final review).
## The crown's strategic goods pay first, then the lord's; a short pool is
## shared by need. Whole numbers, code order. plan() is the one function
## the tick, the regiment card and the LEDGER read. The lines run as their
## governor (the marshal, Governance) runs them: his efficiency thins what
## arrives, his skim takes gold before it buys, and he reports the line as
## if nothing were skimmed (rows' `delivered` is the truth, `claimed` his
## word).


static func loss_of(repo: DataRepository, km: int) -> int:
	@warning_ignore("integer_division")
	var loss := km * int(repo.bal("army_supply_loss_permille_per_100km")) / 100
	return mini(loss, int(repo.bal("army_supply_loss_cap_permille")))


## Units to ship so that `short` arrive after a `loss` per mille.
static func ship_for(short: int, loss: int) -> int:
	if short <= 0:
		return 0
	var keep := 1000 - loss
	@warning_ignore("integer_division")
	return (short * 1000 + keep - 1) / keep


static func gold_for(repo: DataRepository, units: int) -> int:
	@warning_ignore("integer_division")
	return (units * int(repo.bal("army_supply_gold_permille")) + 999) / 1000


static func share(avail: int, golds: Array) -> Array:
	var total := 0
	for g: int in golds:
		total += g
	if total <= avail:
		return golds.duplicate()
	var out: Array = []
	for g: int in golds:
		@warning_ignore("integer_division")
		out.append(maxi(avail, 0) * g / total)
	return out


## The town a standing regiment draws on: a regiment NOT on the march
## (standby or garrison) standing in a province the crown controls draws on
## that province's capital town, loss-free. "" when it marches, stands
## outside the crown's provinces, or the province has no town.
static func stronghold_of(repo: DataRepository, state: GameState, code: String) -> String:
	if ArmySystem.order_of(repo, state, code) == ArmySystem.ORDER_MARCH:
		return ""
	var cell := MapEconomy.cell_at(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)))
	if cell < 0:
		return ""
	var prov := MapManors.province_of(repo, cell, state)
	if prov == "" or not MapManors.crown_controls(repo, state, prov):
		return ""
	return String((repo.provinces.get(prov, {}) as Dictionary).get("capital_burg", ""))


## The town a regiment is GARRISONED in: its stronghold, but only under an
## explicit GARRISON order — what earns the garrison's morale and the
## LEDGER's "garrisons in" thread. "" otherwise.
static func garrisoned_in(repo: DataRepository, state: GameState, code: String) -> String:
	if ArmySystem.order_of(repo, state, code) != ArmySystem.ORDER_GARRISON:
		return ""
	return stronghold_of(repo, state, code)


## The depot's shortest-path tree (RoadGraph.shortest), built once and
## shared by every regiment's line — the depot is the same point for all of
## them, so plan() need not run Dijkstra once per regiment. `line_of` builds
## its own single-use context so it keeps working standalone.
static func _road_context(repo: DataRepository, state: GameState) -> Dictionary:
	var from := CourierSystem.origin(repo, state)
	var a := ArmySystem.pack_to_metres(repo, from)
	var g := RoadGraph.of_pack(repo)
	var reach := float(repo.bal("courier_offroad_max_km")) * 1000.0
	var start := g.nearest(a)
	var ctx := {"a": a, "g": g, "start": start}
	if start >= 0 and Vector2(a).distance_to(Vector2(g.nodes[start])) <= reach:
		ctx["tree"] = g.shortest(start)
	return ctx


## The road from the depot to `to_px`, exactly as CourierSystem.path_between
## computes it, but off a precomputed depot tree (_road_context) instead of
## running Dijkstra again.
static func _path_from_ctx(repo: DataRepository, ctx: Dictionary, to_px: Vector2) -> Array:
	var a: Vector2i = ctx["a"]
	var b := ArmySystem.pack_to_metres(repo, to_px)
	if not ctx.has("tree"):
		return [[b.x, b.y, CourierSystem._leg_kind(repo, a, b)]]
	var g: RoadGraph = ctx["g"]
	var start: int = ctx["start"]
	var tree: Dictionary = ctx["tree"]
	var goal := g.nearest(b, tree["dist"])
	# a start ON the network (the capital is a road node) takes no leg to itself
	var way: Array = [] if g.nodes[start] == a else \
		[[g.nodes[start].x, g.nodes[start].y, CourierSystem._leg_kind(repo, a, g.nodes[start])]]
	way.append_array(g.route(tree, goal))
	way.append([b.x, b.y, CourierSystem._leg_kind(repo, g.nodes[goal], b)])
	return way


static func line_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	return _line_of(repo, state, code, _road_context(repo, state))


static func _line_of(repo: DataRepository, state: GameState, code: String, ctx: Dictionary) -> Dictionary:
	var town := stronghold_of(repo, state, code)
	if town != "":
		return {"length_km": 0, "loss_permille": 0, "stronghold": town,
			"garrison": ArmySystem.order_of(repo, state, code) == ArmySystem.ORDER_GARRISON}
	var to := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var origin_m: Vector2i = ctx["a"]
	var dest_m := ArmySystem.pack_to_metres(repo, to)
	var path := _path_from_ctx(repo, ctx, to)
	var metres := 0.0
	if path.is_empty():
		metres = Vector2(origin_m).distance_to(Vector2(dest_m))
	else:
		# Walk it exactly as CourierSystem.need_along does: `here` starts at
		# the depot, and each waypoint (path_between never includes the
		# origin itself — RoadGraph.route()'s own doc: "the start node itself
		# is not included") adds its own distance from `here`. The old code
		# summed only the legs BETWEEN waypoints and dropped this first one.
		var here := Vector2(origin_m)
		for p: Array in path:
			var wp := Vector2(float(p[0]), float(p[1]))
			metres += here.distance_to(wp)
			here = wp
		# path_between's last entry is always the target itself, but guard it
		# in case that ever changes.
		if here != Vector2(dest_m):
			metres += here.distance_to(Vector2(dest_m))
	var km := int(metres / 1000.0)
	return {"length_km": km, "loss_permille": loss_of(repo, km), "garrison": false, "stronghold": ""}


static func _land_codes(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for c in state.regiments.keys():
		var reg := ArmySystem.regiment(repo, String(c))
		if not reg.is_empty() and String(reg.get("is_naval", "0")) != "1":
			out.append(String(c))
	out.sort()
	return out


static func plan(repo: DataRepository, state: GameState) -> Array:
	var ctx := _road_context(repo, state)
	var rows: Array = []
	var golds: Array = []
	for code: String in _land_codes(repo, state):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), state)
		var target := use * int(repo.bal("army_supply_target_months"))
		var short := maxi(target - int(state.regiments[code]["supplies"]), 0)
		var line := _line_of(repo, state, code, ctx)
		var loss := int(line["loss_permille"])
		var ship := ship_for(short, loss)
		var gold := gold_for(repo, ship)
		golds.append(gold)
		rows.append({"code": code, "need": short, "ship": ship, "gold": gold, "paid": 0, "delivered": 0,
			"loss_permille": loss, "length_km": int(line["length_km"]), "garrison": bool(line["garrison"]),
			"stronghold": String(line["stronghold"])})
	var avail := maxi(int(state.metrics.get("strategic", 0.0)), 0) + maxi(int(state.metrics.get("lord_strategic", 0.0)), 0)
	# The pool being shared is GOLD, and every unit costs the same
	# (army_supply_gold_permille), so splitting it by gold need is exactly
	# splitting the ship need in the same proportion.
	var paid := share(avail, golds)
	var price := maxi(int(repo.bal("army_supply_gold_permille")), 1)
	# The lines run as their governor runs them (spec
	# 2026-09-30-ledger-governors-design §3): the pools pay `paid` in full,
	# he pockets `skimmed` of it and buys with the rest, and his efficiency
	# thins what the road delivers. `delivered` is the truth; `claimed` is
	# what he reports — the same line as if nothing were skimmed.
	var g := Governance.factors(repo, state, "supply_line")
	var eff := int(g["efficiency"])
	var skim := int(g["skim"])
	for i in rows.size():
		var row: Dictionary = rows[i]
		var gold_paid := int(paid[i])
		row["paid"] = gold_paid
		@warning_ignore("integer_division")
		var skimmed := gold_paid * skim / 1000
		var in_full := gold_paid >= int(row["gold"])
		@warning_ignore("integer_division")
		var bought := int(row["ship"]) if in_full and skimmed == 0 else (gold_paid - skimmed) * 1000 / price
		@warning_ignore("integer_division")
		var said := int(row["ship"]) if in_full else gold_paid * 1000 / price
		var keep := 1000 - int(row["loss_permille"])
		@warning_ignore("integer_division")
		row["delivered"] = mini(bought * keep * eff / 1000000, int(row["need"]))
		@warning_ignore("integer_division")
		row["claimed"] = mini(said * keep * eff / 1000000, int(row["need"]))
		row["skimmed"] = skimmed
		row["efficiency"] = eff
		row["skim"] = skim
		row["governor"] = String(g["governor"])
	return rows


## The month's shipment: supplies land on each regiment now; the pool lines
## are returned for the tick to apply with its report (crown first, then
## the lord).
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var total := 0
	var rows := plan(repo, state)
	for row: Dictionary in rows:
		total += int(row["paid"])
		var entry: Dictionary = state.regiments[String(row["code"])]
		entry["supplies"] = int(entry["supplies"]) + int(row["delivered"])
	# the pools pay in full; what the marshal skimmed is his (GameState.skims)
	Governance.add_skims(state, rows, "supply_line")
	if total == 0:
		return []
	var crown := mini(maxi(int(state.metrics.get("strategic", 0.0)), 0), total)
	var lines: Array = []
	if crown > 0:
		lines.append({"metric": "strategic", "delta": -crown, "reason": "supplies sent to the host"})
	if total - crown > 0:
		lines.append({"metric": "lord_strategic", "delta": -(total - crown), "reason": "supplies sent to the host"})
	return lines


## Any land regiment under army_supply_warn_permille (TriggerDsl host_hungry).
static func any_hungry(repo: DataRepository, state: GameState) -> bool:
	for code: String in _land_codes(repo, state):
		if ArmySystem.bars_of(repo, state, code).y < int(repo.bal("army_supply_warn_permille")):
			return true
	return false
