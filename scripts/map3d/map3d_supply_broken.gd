class_name Map3DSupplyBroken
extends RefCounted
## A BROKEN supply line on the 3D map (owner 2026-10-11): a FRONT line — its
## town lies ahead of the column (SupplyLines.front_of) — is drawn as a DARK
## DASHED road from its town along the road toward the column, stopping
## `map3d_supply_broken_gap_m` short of the piece where it is drawn, with a
## solid tick across the road where it breaks (`map3d_supply_broken_tick_m`
## each way), so the player sees where the supply fails; a pale halo under
## both keeps them read on dark ground. Never the gold flowing line; a CUT
## line stays undrawn (SupplyLines.drawn_broken). Looks:
## lines/supply_broken.tres (the dashes), lines/supply_break.tres (the tick),
## lines/supply_broken_halo.tres (the halo). Driven by Map3DSupplyLines (its
## step and redraw). Never the Game
## autoload.

var ctx: Map3DContext
var lines: Map3DLayerLines
var units: Map3DLayerUnits
## code -> hash(day, its line record): its road below was searched for it.
var _sigs: Dictionary = {}
## code -> the broken line's road in world XZ (town first), searched once a day.
var _roads: Dictionary = {}
var _since := 0.0
var _laid_sig := 0
var _shown_on := true


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_units: Map3DLayerUnits) -> void:
	ctx = p_ctx
	lines = p_lines
	units = p_units
	_sigs.clear()
	_roads.clear()


## The marks of one broken road (world XZ, town first): the road stopped
## where it last comes within `gap` of its end (where the column is drawn;
## MapGeometry.stop_outside) and the tick across it
## there, `tick` each way — [dashes, tick], either empty when too short.
static func marks(road: PackedVector2Array, gap: float, tick: float) -> Array:
	var dashes := MapGeometry.stop_outside(road, road[road.size() - 1], gap) if road.size() >= 2 else PackedVector2Array()
	return [dashes, MapGeometry.tick_across(dashes, tick)]


## The roads again, every one searched anew, and laid.
func redraw() -> void:
	if ctx == null or lines == null:
		return
	_sigs.clear()
	_roads.clear()
	var st := ctx.state()
	if st != null:
		_refresh(st)
	_lay()


## Per frame: a road searched once a day (or when its record moves), the
## marks laid at once; a piece moving re-lays them at most every
## map3d_supply_follow_s; hiding or showing the regiments, at once.
func step(delta: float) -> void:
	var st := ctx.state() if ctx != null else null
	if st == null or lines == null:
		return
	_since += delta
	var fresh := _refresh(st)
	var on := units == null or units.shown
	if fresh or on != _shown_on or (_sig() != _laid_sig and _since >= ctx.repo.bal("map3d_supply_follow_s")):
		_shown_on = on
		_lay()


func _refresh(st: GameState) -> bool:
	var day := st.absolute_day()
	var live := {}
	var changed := false
	for code: String in SupplyLines.drawn_broken(st):
		live[code] = true
		var sig := hash([day, (st.supply_lines[code] as Dictionary).hash()])
		if _sigs.get(code, 0) == sig:
			continue
		_sigs[code] = sig
		changed = true
		var road := Map3DSupplyLines._road_of(ctx, st, code)
		if road.size() >= 2:
			_roads[code] = road
		else:
			_roads.erase(code)
	for code: String in _sigs.keys():
		if not live.has(code):
			_sigs.erase(code)
			_roads.erase(code)
			changed = true
	return changed


func _lay() -> void:
	_since = 0.0
	var shown: Dictionary = units.shown_positions() if units != null else {}
	var dashes: Array = []
	var ticks: Array = []
	if units == null or units.shown:
		var codes: Array = _roads.keys()
		codes.sort()
		for code: String in codes:
			var road: PackedVector2Array = Map3DSupplyLines._to_piece(ctx, code, _roads[code], shown)
			var m := marks(road, ctx.repo.bal("map3d_supply_broken_gap_m"), ctx.repo.bal("map3d_supply_broken_tick_m"))
			if (m[0] as PackedVector2Array).size() >= 2:
				dashes.append(m[0])
			if (m[1] as PackedVector2Array).size() >= 2:
				ticks.append(m[1])
	_laid_sig = _sig()
	lines.set_lines("SupplyBrokenHalo", dashes + ticks, Map3DLayerLines.SUPPLY_BROKEN_HALO, Map3DPriority.SUPPLY_LINES)
	lines.set_lines("SupplyBroken", dashes, Map3DLayerLines.SUPPLY_BROKEN, Map3DPriority.SUPPLY_BROKEN)
	lines.set_lines("SupplyBreak", ticks, Map3DLayerLines.SUPPLY_BREAK, Map3DPriority.SUPPLY_BROKEN)


## Where the pieces with a broken line are drawn.
func _sig() -> int:
	var shown: Dictionary = units.shown_positions() if units != null else {}
	var at: Array = []
	for code: String in _roads:
		at.append(shown.get(code, Vector2.ZERO))
	return hash(at)
