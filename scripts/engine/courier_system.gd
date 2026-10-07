class_name CourierSystem
extends RefCounted
## Couriers (owner 2026-09-27, spec docs/superpowers/specs/2026-09-27-courier-core-design.md):
## an order to a regiment rides from the capital and takes effect only when
## the courier reaches the column. One courier per order, gone on delivery.
## The route is the road network's fastest (RoadGraph); the pace each day is
## the stretch's kind, the height tier it starts on and the province's
## weather (Weather). Whole metres and whole per-mille throughout; couriers
## ride in id order.
##
## A courier rides EVENLY to the end of the day he arrives (owner 2026-10-02:
## 信使移动的逻辑不对，应该是收到命令-》游戏开始信使出发，如果是一天的话，意味着这天
## 结束的时候到达目的地。而不是一下子就飞快的到达！游戏显示的到达天数全部以当天结束为准):
## each day he rides only his share of what is left — the clear-road metres
## still ahead over the whole days they take (day_pace) — so a trip of N days
## is covered at one pace over all N and ends exactly as the Nth day ends; the
## order takes effect then, AFTER that day's march (TickEngine), so the column
## acts on it from the next day. Every day count shown is a count of day-ends,
## the day the clock is started on being the first.

const ORDINARY := "ordinary"
const SECRET := "secret"
const SPY := "spy"


## Whether a regiment's orders ride by courier: every land regiment; a fleet
## is exempt in this sub-project (spec §1).
static func carries_orders(reg: Dictionary) -> bool:
	return String(reg.get("is_naval", "0")) != "1"


static func fee_gold(repo: DataRepository, kind: String) -> int:
	return int((repo.courier_kinds.get(kind, {}) as Dictionary).get("fee_gold", 0))


## Clear-road metres a courier of this kind rides in a day.
static func day_budget(repo: DataRepository, kind: String) -> int:
	return int(repo.bal("courier_base_km_per_day")) \
		* int((repo.courier_kinds.get(kind, {}) as Dictionary).get("speed_permille", 1000))


## Where couriers ride from, in pack px: the realm's capital while the realm
## holds its province; else the most populous town of the first province the
## realm holds, in order: the crown's home province, its controlled provinces,
## then any province by code.
static func origin(repo: DataRepository, state: GameState) -> Vector2:
	var realm := repo.resolve_realm("player_realm")
	var cap := String((repo.kingdoms.get(realm, {}) as Dictionary).get("capital_burg", ""))
	if repo.burgs.has(cap) and _holds(repo, state, String(repo.burgs[cap]["province_code"]), realm):
		return _burg_px(repo.burgs[cap])
	var order: Array = []
	var home := MapManors.home_province(repo, state)
	if home != "":
		order.append(home)
	for p: String in MapManors.controlled_provinces(repo, state):
		if not p in order:
			order.append(p)
	var rest := repo.provinces.keys()
	rest.sort()
	for p: String in rest:
		if not p in order:
			order.append(p)
	var codes := repo.burgs.keys()
	codes.sort()
	for p: String in order:
		if not _holds(repo, state, p, realm):
			continue
		var best := ""
		var best_pop := -1
		for b: String in codes:
			var row: Dictionary = repo.burgs[b]
			if String(row["province_code"]) != p:
				continue
			var pop := int(float(row["population"]))
			if pop > best_pop:
				best = b
				best_pop = pop
		if best != "":
			return _burg_px(repo.burgs[best])
	return _burg_px(repo.burgs[cap]) if repo.burgs.has(cap) else Vector2.ZERO


static func _holds(repo: DataRepository, state: GameState, province: String, realm: String) -> bool:
	return MapOwnership.owner_of(repo, state, province) == realm


static func _burg_px(b: Dictionary) -> Vector2:
	return Vector2(float(b["x"]), float(b["y"]))


## The waypoints from one point to another, [x_m, y_m, kind] each (the kind
## of the stretch INTO it): across country to the nearest road node, the
## network's fastest route to the reached node nearest the target, across
## country (or by sea) to the target. Farther than courier_offroad_max_km
## from any node: one straight leg.
static func path_between(repo: DataRepository, from_px: Vector2, to_px: Vector2) -> Array:
	var a := ArmySystem.pack_to_metres(repo, from_px)
	var b := ArmySystem.pack_to_metres(repo, to_px)
	var g := RoadGraph.of_pack(repo)
	var reach := float(repo.bal("courier_offroad_max_km")) * 1000.0
	var start := g.nearest(a)
	if start < 0 or Vector2(a).distance_to(Vector2(g.nodes[start])) > reach:
		return [[b.x, b.y, _leg_kind(repo, a, b)]]
	var tree := g.shortest(start)
	var goal := g.nearest(b, tree["dist"])
	# a start ON the network (the capital is a road node) takes no leg to itself
	var way: Array = [] if g.nodes[start] == a else \
		[[g.nodes[start].x, g.nodes[start].y, _leg_kind(repo, a, g.nodes[start])]]
	way.append_array(g.route(tree, goal))
	way.append([b.x, b.y, _leg_kind(repo, g.nodes[goal], b)])
	return way


## "offroad", or "sea" when any sample every courier_sea_sample_km along the
## leg is off the land grid (MapEconomy.cell_at < 0, the land/sea test
## ActionSystem uses).
static func _leg_kind(repo: DataRepository, a: Vector2i, b: Vector2i) -> String:
	var step := maxf(repo.bal("courier_sea_sample_km") * 1000.0, 1.0)
	var length := Vector2(a).distance_to(Vector2(b))
	for i in range(1, int(length / step) + 1):
		var p := Vector2(a).lerp(Vector2(b), float(i) * step / length)
		if MapEconomy.cell_at(repo, ArmySystem.metres_to_pack(repo, Vector2i(p))) < 0:
			return "sea"
	return "offroad"


## A stretch's pace as a product of per-milles out of 10^9: its kind x the
## height tier where it starts (none at sea) x the weather there.
static func stretch_factor(repo: DataRepository, kind: String, at_m: Vector2i, weather: String) -> int:
	var tier := 1000 if kind == "sea" else RoadGraph.tier_permille(repo, Vector2(at_m))
	return RoadGraph.factor_permille(repo, kind) * tier * Weather.speed_permille(repo, weather)


## Clear-road metres from a point along a path, each stretch at its start's
## weather on `abs_day`.
static func need_along(repo: DataRepository, state: GameState, from_m: Vector2i, path: Array,
		abs_day: int) -> int:
	var need := 0
	var here := from_m
	for p: Array in path:
		var to := Vector2i(int(p[0]), int(p[1]))
		var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), abs_day)
		need += RoadGraph.stretch_need(int(round(Vector2(here).distance_to(Vector2(to)))),
			stretch_factor(repo, String(p[2]), here, wx))
		here = to
	return need


## Whole days to ride `need` clear-road metres, rounded up, at least one.
static func days_for(repo: DataRepository, kind: String, need: int) -> int:
	var b := maxi(1, day_budget(repo, kind))
	@warning_ignore("integer_division")  # whole days, rounded up
	return maxi(1, (need + b - 1) / b)


## Send a courier of `kind` with `order` for regiment `code`. Charges
## nothing: the fee is ActionSystem's ledger line.
static func dispatch(repo: DataRepository, state: GameState, kind: String, code: String,
		order: Dictionary) -> Dictionary:
	return dispatch_to(repo, state, kind, code, order,
		ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)))


## A courier for regiment `code` whose road ends at `to_px` — the regiment
## itself (dispatch), or its supply TOWN (spec 2026-10-07-army-supply-lines
## §4, `order.to_town`): such a courier is never re-aimed at the column.
static func dispatch_to(repo: DataRepository, state: GameState, kind: String, code: String,
		order: Dictionary, to_px: Vector2) -> Dictionary:
	var from := origin(repo, state)
	var home := ArmySystem.pack_to_metres(repo, from)
	var aim := ArmySystem.pack_to_metres(repo, to_px)
	state.next_courier_id += 1
	var c := {
		"id": state.next_courier_id, "kind": kind, "x_m": home.x, "y_m": home.y,
		"path": path_between(repo, from, to_px), "target": code, "order": order.duplicate(true),
		"issued": state.absolute_day(), "aim_x_m": aim.x, "aim_y_m": aim.y,
		"days": 0, "day_m": 0, "slow_spell": -1,
	}
	state.couriers.append(c)
	return c


## A spy bound for a point (spec 2026-09-28 §1): A's courier, whose target is
## the point itself; his road is set once and never re-aimed.
static func dispatch_spy(repo: DataRepository, state: GameState, to_px: Vector2) -> Dictionary:
	var from := origin(repo, state)
	var home := ArmySystem.pack_to_metres(repo, from)
	var aim := ArmySystem.pack_to_metres(repo, to_px)
	state.next_courier_id += 1
	var c := {
		"id": state.next_courier_id, "kind": SPY, "x_m": home.x, "y_m": home.y,
		"path": path_between(repo, from, to_px), "target": "",
		"order": {"action_code": "SPY_SEND", "x_m": aim.x, "y_m": aim.y},
		"issued": state.absolute_day(), "aim_x_m": aim.x, "aim_y_m": aim.y,
		"days": 0, "day_m": 0, "slow_spell": -1,
	}
	state.couriers.append(c)
	return c


## The absolute day a courier rides next: the day now running, ridden as it
## ends (TickEngine). The ETAs read it so they agree with the ride.
static func _ride_day_of(state: GameState) -> int:
	return state.absolute_day()


## Days a courier still has to ride — the day now running the first, his last
## ending as he delivers — the weather of his next day held.
static func days_left(repo: DataRepository, state: GameState, c: Dictionary) -> int:
	return days_for(repo, String(c["kind"]), need_along(repo, state,
		Vector2i(int(c["x_m"]), int(c["y_m"])), c["path"], _ride_day_of(state)))


## Days a spy sent now would ride to reach `to_px`, the route and today's
## weather held (SPY_SEND's refusal past the fuse, final review M15).
static func spy_eta_days(repo: DataRepository, state: GameState, to_px: Vector2) -> int:
	var from := origin(repo, state)
	var path := path_between(repo, from, to_px)
	return days_for(repo, SPY, need_along(repo, state, ArmySystem.pack_to_metres(repo, from),
		path, _ride_day_of(state)))


## The aim ruler's estimate (spec §1): days for a courier sent now to reach
## the regiment — counted in day-ends, the day now running (or about to run)
## the first — the route and his first day's weather held. 0 for no regiment.
static func eta_days(repo: DataRepository, state: GameState, kind: String, code: String) -> int:
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty():
		return 0
	var from := origin(repo, state)
	var path := path_between(repo, from, ArmySystem.position_of(repo, state, reg))
	return days_for(repo, kind, need_along(repo, state, ArmySystem.pack_to_metres(repo, from),
		path, _ride_day_of(state)))


## Days for a courier sent now to reach `to_px` (a supply town: the supply
## orders ride to the town, not the column) — eta_days to a place.
static func eta_days_to(repo: DataRepository, state: GameState, kind: String, to_px: Vector2) -> int:
	var from := origin(repo, state)
	var path := path_between(repo, from, to_px)
	return days_for(repo, kind, need_along(repo, state, ArmySystem.pack_to_metres(repo, from),
		path, _ride_day_of(state)))


## Days until `code` stands at `dest_px` if a march there were ordered now —
## ONE figure, the courier's ride and the march after it (owner 2026-10-02:
## 显示一个总的到达日): his days (none for a regiment that takes its orders
## directly), then the march from where it stands, walked over the ground and
## the weather it will meet (ArmySystem.march_days_between), each counted in
## day-ends. 0 for a regiment that cannot march.
static func arrival_days(repo: DataRepository, state: GameState, code: String, dest_px: Vector2,
		from_px := Vector2(-1, -1), ride := -1) -> int:
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty() or ArmySystem.day_march_m(repo, state, code) <= 0:
		return 0
	if ride < 0:
		ride = eta_days(repo, state, ORDINARY, code) if carries_orders(reg) else 0
	var from := from_px if from_px.x >= 0.0 else ArmySystem.position_of(repo, state, reg)
	# the march walked over its own ground and weather, from the day it starts
	return ride + ArmySystem.march_days_between(repo, state, code, from, dest_px,
		state.absolute_day() + ride)


## Days until `code` arrives where it was last ordered: a march order still
## riding with its courier counts his days left and then the march; a column on
## the march its days out; 0 when it is bound nowhere.
static func days_to_arrival(repo: DataRepository, state: GameState, code: String) -> int:
	var c := pending_for(state, code)
	var order: Dictionary = c.get("order", {}) if not c.is_empty() else {}
	if String(order.get("action_code", "")) == "ARMY_MARCH":
		var dest := ArmySystem.metres_to_pack(repo, Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"])))
		return arrival_days(repo, state, code, dest, Vector2(-1, -1), days_left(repo, state, c))
	if not c.is_empty():
		return 0   # a halt is riding: the column stops where it is
	return ArmySystem.days_out(repo, state, code)


## One DAY on the road for every courier, in id order (TickEngine, at the
## day's END, after the regiments march: an order delivered today is marched
## on from tomorrow). Returns the day's events for the news bar; his setting
## out is said when the day he rides begins (setting_out), not here.
static func ride_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	var today := state.absolute_day()
	var list: Array = state.couriers.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	var keep: Array = []
	for c: Dictionary in list:
		if _ride(repo, state, c, today, events):
			keep.append(c)
	state.couriers = keep
	return events


## One courier's day; false when he is done (delivered, lost, or out of time).
static func _ride(repo: DataRepository, state: GameState, c: Dictionary, today: int, events: Array) -> bool:
	var code := String(c["target"])
	var reg := ArmySystem.regiment(repo, code)
	if not _is_spy(c) and (reg.is_empty() or ArmySystem.state_of(repo, state, code).is_empty()):
		events.append(_event("lost", c))
		return false
	c["days"] = int(c.get("days", 0)) + 1
	if int(c["days"]) > int(repo.bal("courier_max_days")):
		events.append(_spy_placed(repo, state, c, _event("fuse", c)))
		return false
	if not _fixed_point(c):
		_reaim(repo, state, c, reg)
	@warning_ignore("return_value_discarded")  # the budget left matters only to the preview
	_advance(repo, state, c, today, events)
	if (c["path"] as Array).is_empty():
		events.append(SpySystem.observe(repo, state, c) if _is_spy(c) else _deliver(repo, state, c))
		return false
	return true


## The news bar's "he leaves" lines for the couriers whose FIRST day is the
## one now running (days 0), in id order, past `after` (the last id already
## said) — said when the clock runs that day, so the leaving and a one-day
## delivery are never the same moment. Nothing is written.
static func setting_out(repo: DataRepository, state: GameState, after: int) -> Array:
	var out: Array = []
	var list: Array = state.couriers.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for c: Dictionary in list:
		if int(c["id"]) <= after or int(c.get("days", 0)) > 0:
			continue
		var e := _event("set_out", c)
		e["capital"] = 1 if _at_capital(repo, c) else 0
		if _is_spy(c):
			e["place"] = Intel.place_label(repo, state, ArmySystem.metres_to_pack(repo,
				Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"]))))
		out.append(e)
	return out


## A spy courier (SPY_SEND): he rides for a point, not a regiment.
static func _is_spy(c: Dictionary) -> bool:
	return String(c.get("kind", "")) == SPY


## A courier bound for a fixed point, never re-aimed at a column: a spy, or
## a supply order riding to its town.
static func _fixed_point(c: Dictionary) -> bool:
	return _is_spy(c) or String((c.get("order", {}) as Dictionary).get("to_town", "")) != ""


## Where a courier's NEXT day on the road takes him: the engine's own ride run
## on a copy, so the map draws him riding it as the day passes instead of a
## day behind (owner 2026-09-28: he stood still a whole day after play was
## pressed). {points: the points he passes in whole metres, ending where the
## day leaves him ([] when he will not ride); share: the share of the day his
## ride takes — the whole day, since he rides evenly to the day's end (owner
## 2026-10-02); ends: true when that day's ride delivers, AS THE DAY ENDS (the
## map fades him out then, owner 2026-09-30: 信使送到信息后要立即淡化消失)}.
## Nothing of `state` or `c` is written.
static func ride_ahead(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var before: Array = []
	var copy := _ride_copy(repo, state, c, before)
	if copy.is_empty():
		return {"points": [], "share": 1.0, "ends": false}
	return {"points": passed_points(before, (copy["path"] as Array).size(),
		Vector2i(int(copy["x_m"]), int(copy["y_m"]))), "share": float(copy["ride_share"]),
		"ends": (copy["path"] as Array).is_empty()}


## `c` after his next day, on a copy ({} when he will not ride), its
## `ride_share` the share of the day's ride he used; `before` receives his road
## as the day starts.
static func _ride_copy(repo: DataRepository, state: GameState, c: Dictionary, before: Array) -> Dictionary:
	var code := String(c["target"])
	var reg := ArmySystem.regiment(repo, code)
	# a spy rides for a point, not a regiment: nothing to lose, nothing to re-aim
	if not _is_spy(c) and (reg.is_empty() or ArmySystem.state_of(repo, state, code).is_empty()):
		return {}
	var copy: Dictionary = c.duplicate(true)
	if not _fixed_point(c):
		_reaim(repo, state, copy, reg)
	before.append_array((copy["path"] as Array).duplicate(true))
	var day := _ride_day_of(state)
	var pace := day_pace(repo, state, copy, day)
	var left := _advance(repo, state, copy, day, [])
	copy["ride_share"] = 1.0 - float(left) / float(pace) if pace > 0 else 1.0
	return copy


## Where the next day leaves a regiment, in whole metres (ArmySystem.march_ahead
## on a copy of its row). A courier delivering that day changes nothing: his
## order takes effect as the day ENDS, after the march (owner 2026-10-02), so
## the column marches on it from the next day. Nothing is written.
static func day_ahead_of(repo: DataRepository, state: GameState, code: String) -> Vector2i:
	var entry: Dictionary = (state.regiments.get(code, {}) as Dictionary).duplicate(true)
	return ArmySystem.march_ahead(repo, state, code, entry)


## The points (whole metres) a courier passed on a day: the waypoints his road
## dropped from its front, then where he stands.
static func passed_points(old_path: Array, new_size: int, now: Vector2i) -> Array:
	var out: Array = []
	for i in range(maxi(old_path.size() - new_size, 0)):
		out.append(Vector2i(int(old_path[i][0]), int(old_path[i][1])))
	out.append(now)
	return out


## The clear-road metres a courier rides on `today` (owner 2026-10-02): what
## is still ahead of him, under `today`'s weather, over the whole days it takes
## (days_for), rounded up — never more than his day_budget — so he keeps one
## pace to the end of his last day and reaches the column as it ends, never
## part-way through it. A day of worse weather adds a day and slows him; each
## day re-reckons, so the count only ever falls by one a day while the
## weather and the column hold.
static func day_pace(repo: DataRepository, state: GameState, c: Dictionary, today: int) -> int:
	var need := need_along(repo, state, Vector2i(int(c["x_m"]), int(c["y_m"])), c["path"], today)
	var days := days_for(repo, String(c["kind"]), need)
	@warning_ignore("integer_division")  # whole metres, rounded up
	return mini(day_budget(repo, String(c["kind"])), (need + days - 1) / days)


## One day's ride along `c`'s road, which it writes: his spot, his road, day_m.
## He rides day_pace, not his whole day_budget. Returns the pace left unridden
## (0 but for rounding: on his last day the pace is exactly what was left).
static func _advance(repo: DataRepository, state: GameState, c: Dictionary, today: int, events: Array) -> int:
	var budget := day_pace(repo, state, c, today)
	var here := Vector2i(int(c["x_m"]), int(c["y_m"]))
	var start := here
	var path: Array = c["path"]
	# a stretch needing nothing (no length) is passed even on a spent pace
	while not path.is_empty():
		var to := Vector2i(int(path[0][0]), int(path[0][1]))
		var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), today)
		var f := stretch_factor(repo, String(path[0][2]), here, wx)
		var length := int(round(Vector2(here).distance_to(Vector2(to))))
		var need := RoadGraph.stretch_need(length, f)
		if budget <= 0 and need > 0:
			break  # the day's pace is ridden
		_note_slow(repo, state, c, wx, today, events)
		if need <= budget:
			budget -= need
			here = to
			path.pop_front()
			continue
		@warning_ignore("integer_division")  # whole metres into the stretch
		var adv := budget * f / 1_000_000_000
		if length > 0:
			var way := (Vector2(to) - Vector2(here)) / float(length)
			here = Vector2i(roundi(float(here.x) + way.x * float(adv)), roundi(float(here.y) + way.y * float(adv)))
		budget = 0
		break
	c["day_m"] = int(round(Vector2(start).distance_to(Vector2(here))))
	c["x_m"] = here.x
	c["y_m"] = here.y
	return budget


## The column has moved more than courier_reaim_m since his road was set:
## his last leg now ends where it stands (a column is far slower than a
## courier, so the road itself is not re-planned).
static func _reaim(repo: DataRepository, state: GameState, c: Dictionary, reg: Dictionary) -> void:
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, reg))
	if Vector2(at).distance_to(Vector2(int(c["aim_x_m"]), int(c["aim_y_m"]))) <= repo.bal("courier_reaim_m"):
		return
	c["aim_x_m"] = at.x
	c["aim_y_m"] = at.y
	var path: Array = c["path"]
	if path.is_empty():
		path.append([at.x, at.y, "offroad"])
	else:
		path[path.size() - 1] = [at.x, at.y, String(path[path.size() - 1][2])]


static func _note_slow(repo: DataRepository, state: GameState, c: Dictionary, weather: String,
		today: int, events: Array) -> void:
	if Weather.speed_permille(repo, weather) >= int(repo.bal("courier_slow_news_permille")):
		return
	var spell := Weather.spell_of(repo, today)
	if int(c.get("slow_spell", -1)) == spell:
		return
	c["slow_spell"] = spell
	events.append(_spy_placed(repo, state, c, _event("slow", c, weather)))


## A spy rides for no regiment: his event names the place he was sent to,
## so the news bar can say where (final review M1).
static func _spy_placed(repo: DataRepository, state: GameState, c: Dictionary, e: Dictionary) -> Dictionary:
	if _is_spy(c):
		e["place"] = Intel.place_label(repo, state, ArmySystem.metres_to_pack(repo,
			Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"]))))
	return e


## The order takes effect — unless the column already obeys a NEWER one (a
## higher courier id), in which case this one is set aside.
static func _deliver(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var code := String(c["target"])
	if String((c["order"] as Dictionary).get("action_code", "")).begins_with("SUPPLY_"):
		return SupplyLines.deliver(repo, state, c)
	var entry: Dictionary = state.regiments.get(code, {})
	if int(entry.get("order_id", 0)) > int(c["id"]):
		MissiveLog.add(repo, state, MissiveWriter.receipt(repo, state, c, true))
		return _event("stale", c)
	var order: Dictionary = c["order"]
	match String(order.get("action_code", "")):
		"ARMY_MARCH":
			ArmySystem.set_march(repo, state, code, ArmySystem.metres_to_pack(repo,
				Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"]))))
		"ARMY_GARRISON":
			ArmySystem.set_garrison(repo, state, code)
	if state.regiments.has(code):
		state.regiments[code]["order_id"] = int(c["id"])
	MissiveLog.add(repo, state, MissiveWriter.receipt(repo, state, c, false))
	return _event("delivered", c)


## Whether he stands on the capital's own spot — where dispatch puts him when
## the realm holds its capital (origin), and nowhere else it would.
static func _at_capital(repo: DataRepository, c: Dictionary) -> bool:
	var cap := String((repo.kingdoms.get(repo.resolve_realm("player_realm"), {}) as Dictionary).get("capital_burg", ""))
	if not repo.burgs.has(cap):
		return false
	return ArmySystem.pack_to_metres(repo, _burg_px(repo.burgs[cap])) == Vector2i(int(c["x_m"]), int(c["y_m"]))


static func _event(type: String, c: Dictionary, weather: String = "") -> Dictionary:
	return {"type": type, "courier": int(c["id"]), "regiment": String(c["target"]), "weather": weather,
		"town": String((c.get("order", {}) as Dictionary).get("to_town", ""))}


## The newest MARCH / HALT courier riding for a regiment, {} when none. The
## supply orders (SUPPLY_*) are not the march: they never move a column's
## arrival day, so this reader (days_to_arrival, the regiment card, the war
## folio) passes them by.
static func pending_for(state: GameState, code: String) -> Dictionary:
	var best: Dictionary = {}
	if state == null:
		return best
	for c: Dictionary in state.couriers:
		if String((c["order"] as Dictionary).get("action_code", "")).begins_with("SUPPLY_"):
			continue
		if String(c["target"]) == code and (best.is_empty() or int(c["id"]) > int(best["id"])):
			best = c
	return best


static func _town_label(repo: DataRepository, town: String) -> String:
	return String((repo.burgs.get(town, {}) as Dictionary).get("label", town))


## The news bar's line for a ride_day event.
static func headline(repo: DataRepository, e: Dictionary) -> String:
	var label := String(ArmySystem.regiment(repo, String(e.get("regiment", ""))).get("label", e.get("regiment", "")))
	match String(e.get("type", "")):
		"set_out":
			if String(e.get("place", "")) != "":
				if int(e.get("capital", 0)) == 1:
					return "A spy leaves the capital for %s." % String(e["place"])
				return "A spy rides for %s." % String(e["place"])
			if String(e.get("town", "")) != "":
				var to := _town_label(repo, String(e["town"]))
				if int(e.get("capital", 0)) == 1:
					return "A courier leaves the capital for %s with supply orders for %s." % [to, label]
				return "A courier rides for %s with supply orders for %s." % [to, label]
			if int(e.get("capital", 0)) == 1:
				return "A courier leaves the capital for %s." % label
			return "A courier rides for %s." % label
		"spy_report":
			return "The spy at %s reports." % String(e.get("place", "the place"))
		"delivered":
			if String(e.get("town", "")) != "":
				return "Supply orders for %s delivered at %s." % [label, _town_label(repo, String(e["town"]))]
			return "Orders delivered to %s." % label
		"stale":
			return "Older orders to %s came after newer ones and were set aside." % label
		"lost":
			return "Orders to %s undelivered: the regiment is gone." % label
		"fuse":
			if String(e.get("place", "")) != "":
				return "The spy sent to %s never got there." % String(e["place"])
			return "Orders to %s undelivered: the courier never found them." % label
		"slow":
			var wx := Weather.label_of(repo, String(e.get("weather", ""))).to_lower()
			if String(e.get("place", "")) != "":
				return "The spy riding for %s is held up by %s." % [String(e["place"]), wx]
			return "The courier to %s is held up by %s." % [label, wx]
	return ""
