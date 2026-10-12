@tool
class_name Map3DLayerUnits
extends Node3D
## MILITARY's PIECES: the player's regiments as animated wargame models
## standing on the ground (owner 2026-09-22, "把这两个兵棋人应用到游戏中去").
## Nine, six or three .glb figures per regiment by its strength (Map3DFormation),
## each posed by its own AnimationPlayer — the one layer that cannot be a MultiMesh.
## THE SIZE IS NOT THE MODEL'S SIZE: a miniature's, one world size at every
## zoom, drawn at every zoom with no mark over it (owner 2026-10-10). That rule,
## the facing, seating, measuring and screen box are Map3DUnits, the pure half.
## Takes everything from Map3DContext, never the Game autoload (a test scans).

@export var preview := false: set = set_preview  ## the regiments from the pack alone

const GARRISON := "GARRISON"
const STANDBY := "STANDBY"
const MARCH := "MARCH"

## Figure spacing, × a figure's footprint (owner 2026-09-30: 可以适当分开一些).
@export var formation_gap := 1.6
## Seconds a clip blends into the next (owner 2026-09-27: 行进的动作非常突兀).
@export var blend_s := 0.3
## Degrees a second a piece turns (instant turning read as a glitch).
@export var turn_deg_per_s := 220.0
## How far behind a held line its camp is pitched, in the model's own metres
## past the line's half depth (spec 2026-10-11-war-room-front-line-design §3).
@export var camp_back_m := 6.0
var _camps := Map3DUnitCamps.new()  ## the camps pitched behind held lines
## How solid a GHOST's figures stand (spec 2026-10-10-player-sight-and-ghosts),
## 1 opaque — see-through as a courier's fading piece (Map3DCourierRide.apply).
@export_range(0.0, 1.0) var ghost_alpha := 0.35

var ctx: Map3DContext
## Whether the pieces show; Map3DView sets it from set_military.
var shown := false
## code -> {node, anims, height_m, half_w_m, extent, figures, ...} — model metres.
var _pieces: Dictionary = {}
## code -> the piece's box on screen, design px. What a click hits.
var _rects: Dictionary = {}
var _selected: Array = []  ## the selected codes: their pieces glow (Map3DUnitGlow)
## code -> {heading, trail}: the way it last ADVANCED (Map3DUnits.track).
var _track: Dictionary = {}
var _want_yaw: Dictionary = {}  ## code -> the yaw it turns toward
var _yaw: Dictionary = {}  ## code -> the yaw it is at
var _shown_xz: Dictionary = {}  ## code -> where it is DRAWN, world XZ (step)
var _days: Dictionary = {}  ## code -> {key, from, to, s0}: its day's march (Map3DUnits.along_day)
var _moves := 0
var _roster_was: Array = []  ## the state the drawn set was last cut for (_roster_key)
var _live: Array = []  ## the codes drawn, in roster order


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(refresh):
		ctx.camera_moved.connect(refresh)


## Shown or hidden (built on the first showing, then only hidden).
func set_shown(on: bool) -> void:
	shown = on
	visible = on
	if on:
		refresh()
	else:  # hidden: nothing to click
		_rects.clear()


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		_pieces.clear()
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


func preview_build(p_ctx: Map3DContext) -> void:
	bind(p_ctx)
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		return
	shown = true
	visible = true
	refresh()


## Every piece placed for the camera (never turned by it), cut once per pose; the drawn SET
## only when the state it reads moved (perf P0 2026-10-11: a pan re-cut the sight every frame).
func refresh() -> void:
	if ctx == null or not shown or ctx.camera == null or not is_inside_tree():
		return  # out of the tree: a view handed between screens (the title's)
	var key := _roster_key()
	if key != _roster_was:
		_roster_was = key
		_roster()
	_rects.clear()
	for code: String in _live:
		_place(code, _pieces[code])


## What the drawn set reads: the state, its day, its regiments (orders, stances, fronts), foes, sightings, DEV MODE.
func _roster_key() -> Array:
	var st := ctx.state()
	return [st, st.absolute_day(), st.regiments.hash(), st.foes.size(), st.sightings.size(), ctx.dev] \
		if st != null else [null, ctx.dev]


## The pieces to draw: every regiment the context gives, then the ghosts; the rest freed.
func _roster() -> void:
	var live: Dictionary = {}
	for reg: Dictionary in ctx.regiments():
		var code := String(reg["regiment_code"])
		var piece := _piece_of(code)
		if piece.is_empty():
			continue
		live[code] = true
		if not _shown_xz.has(code):
			_shown_xz[code] = _target_xz(reg)
	# the GHOSTS (Map3DContext.ghosts): where the crown last knew a foe, its unit's
	# piece (a host's: its first column's) at full strength, see-through, standing still
	for g: Dictionary in ctx.ghosts():
		var key := Sighting.GHOST_CODE + String(g["key"])
		if not _pieces.has(key) and not _build(key, ArmySystem.regiment(ctx.repo, Sighting.model_unit(
				ctx.state(), g), ctx.state()), Map3DFormation.tier_of(ctx.repo, 1000)).is_empty():
			Map3DCourierRide.apply(_pieces[key], ghost_alpha)
			play(key, STANDBY)
		if _pieces.has(key):
			live[key] = true
			_shown_xz[key] = ctx.to_world(ArmySystem.metres_to_pack(ctx.repo, Vector2i(int(g["x_m"]), int(g["y_m"]))))
	for code: String in _pieces.keys():  # no longer drawn: FREED, not hidden (hidden ones piled up, perf P0 2026-10-11)
		if not live.has(code): _drop(code)
	_live = live.keys()


## Where the ENGINE has a regiment today, world XZ.
func _target_xz(reg: Dictionary) -> Vector2:
	return ctx.to_world(ArmySystem.position_of(ctx.repo, ctx.state(), reg))


## Stand one piece where it is SHOWN, at the camera's scale, facing its way,
## SEATED on its footprint (Map3DUnits.seat; owner 2026-09-24: 斜面上兵人的一部分会被地图盖住).
func _place(code: String, piece: Dictionary) -> void:
	var repo := ctx.repo
	var xz: Vector2 = _shown_xz[code]
	_rects.erase(code)
	if ctx.camera.is_position_behind(Vector3(xz.x, ctx.height_at(xz), xz.y)):
		show_piece(piece, false)
		return
	show_piece(piece, true)
	var ref_m := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var k := Map3DUnits.scale_for(repo, repo.bal("map3d_fov_deg"), ctx.view_size.y, ref_m,
		float(piece["height_m"]), piece["size"])
	var heading := Map3DUnitRig.heading_for(repo, ctx.state(), code, _track.get(code, {}))
	_want_yaw[code] = Map3DUnits.facing_yaw(heading, piece.get("stand_deg", 0.0))
	_yaw[code] = _yaw.get(code, _want_yaw[code])
	var yaw := float(_yaw[code])
	if piece.get("seat_key", []) != [xz, yaw, k]:  # a pan moves none of it: seated once per stand
		piece["seat_key"] = [xz, yaw, k]
		Map3DUnitRig.seat(repo, ctx.height_at, piece, xz, yaw, k)
	Map3DUnitRig.plant(repo, ctx.height_at, piece)
	var ground: Vector3 = piece["ground"]
	Map3DUnitGlow.place(repo, piece, _selected.has(code), float(piece["lift"]), k)
	_rects[code] = Map3DUnits.screen_box(ctx.camera, ground, float(piece["height_m"]) * k,
		float(piece["half_w_m"]) * k, ctx.viewport_px_scale())
	_camps.sync(self, ctx, code, piece, xz, yaw, k, camp_back_m)


## Per FRAME: draw every piece where the day's share has it on its march
## (_day_of), turned the way it last advanced; true when one moved (the HUD redraws).
func step(delta: float) -> bool:
	if ctx == null or not shown:
		return false
	if _roster_key() != _roster_was:
		refresh()  # a day turned or a unit came or went: the drawn set follows with the camera still
	var repo := ctx.repo
	var moved := false
	for code: String in _pieces:
		var node: Node3D = _pieces[code]["node"]
		if not _shown_xz.has(code) or code.begins_with(Sighting.GHOST_CODE):
			continue  # a ghost stands where it was last known
		var now: Vector2 = _shown_xz[code]
		var day := _day_of(code)
		var want := Map3DUnits.along_day(day, ctx.day_share())
		if now != want:
			_shown_xz[code] = want
			_track[code] = Map3DUnits.track(_track.get(code, {}), now, want)
			_place(code, _pieces[code])
			moved = true
		Map3DUnitRig.keep_pace(repo, _pieces[code], day, ctx.day_share(), ctx.clock_speed(), code)
		var was_lagging: bool = _pieces[code].get("lagging", false)
		Map3DUnitRig.lag(repo, _pieces[code], code, (want - now) / maxf(delta, 0.0001), delta if ctx.clock_speed() > 0 else 0.0)
		if was_lagging or _pieces[code].get("lagging", false):
			Map3DUnitRig.plant(repo, ctx.height_at, _pieces[code])  # the trail moved a foot: back on its ground
		_sync_action(code)
		# a facing set at the day's end turns the piece without a camera move
		var facing := ArmySystem.facing_of(ctx.state(), code)
		if facing != Vector2.ZERO:
			_want_yaw[code] = Map3DUnits.facing_yaw(facing, _pieces[code].get("stand_deg", 0.0))
		if node.visible and float(_yaw.get(code, 0.0)) != float(_want_yaw.get(code, 0.0)):
			var rate := deg_to_rad(turn_deg_per_s) * delta
			_yaw[code] = rotate_toward(float(_yaw.get(code, 0.0)),
				float(_want_yaw.get(code, 0.0)), rate)
			_place(code, _pieces[code])  # re-seated: a long piece turned across a slope meets other ground
	_camps.prune(_pieces)
	if moved:
		_moves += 1
	return moved


func moves() -> int: return _moves  ## bumped each frame a piece moves
func show_piece(piece: Dictionary, on: bool) -> void: Map3DUnits.show_piece(piece, on)

## Where each piece is DRAWN, {code: world XZ} — where its road ahead starts.
func shown_positions() -> Dictionary: return _shown_xz


## The selected units: each one's piece glows on the ground under it.
func set_selected(codes: Array) -> void:
	_selected = codes.duplicate()
	refresh()


func has_piece(code: String) -> bool: return _pieces.has(code)  ## a fleet has none: its counter

## The pieces' boxes on screen, {code: Rect2} in design px — what a click on
## the SOLDIER hits (Map3DPicker), before the province under him.
func screen_rects() -> Dictionary:
	return _rects


## How many pieces are standing (tests, bench).
func drawn_count() -> int:
	return _pieces.values().filter(func(p: Dictionary) -> bool: return (p["node"] as Node3D).visible).size()


## Put a regiment's figures into an action by name; one without it keeps its own.
func play(code: String, action: String) -> void:
	if _pieces.has(code):
		_pieces[code]["action"] = action
		Map3DUnitRig.play(_pieces[code]["anims"], action, blend_s, code)


## The piece for a regiment, built on first sight; {} for an arm with no model (a fleet).
func _piece_of(code: String) -> Dictionary:
	var reg := ArmySystem.regiment(ctx.repo, code, ctx.state())
	if reg.is_empty():
		return {}
	var tier := Map3DFormation.tier_of(ctx.repo, ArmySystem.fit_permille(ctx.repo, ctx.state(), code))
	var layout := Map3DFormation.layout_of(ctx.repo, ctx.state(), code)
	if int(_pieces.get(code, {}).get("figures", -1)) == (tier["slots"] as Array).size() \
			and String(_pieces.get(code, {}).get("layout", "")) == layout:
		_sync_action(code)
		return _pieces[code]
	if _pieces.has(code):  # its strength crossed a tier or it formed a line: built anew
		(_pieces[code]["node"] as Node3D).queue_free()
		_pieces.erase(code)
	if _build(code, reg, tier, layout).is_empty():
		return {}
	_sync_action(code)
	return _pieces[code]


func _drop(code: String) -> void:  ## frees `code`'s piece, forgets all kept about it; rebuilt if it returns
	(_pieces[code]["node"] as Node3D).queue_free()
	for kept: Dictionary in [_pieces, _rects, _shown_xz, _track, _want_yaw, _yaw, _days]: kept.erase(code)

## Builds the piece of `reg` in formation `tier` as `_pieces[key]`; {} when its
## arm has no model.
func _build(key: String, reg: Dictionary, tier: Dictionary, layout := Map3DFormation.BLOCK) -> Dictionary:
	var built := Map3DFormation.of_regiment(ctx.repo, reg, tier, formation_gap, layout)
	if built.is_empty():
		return {}
	(built["node"] as Node3D).name = key.replace(":", "_")
	add_child(built["node"])  # no owner: never saved into the authored scene
	_pieces[key] = built
	return built


## A piece's day's march (Map3DUnits.day_march), remade when its row, the day or the couriers turn.
func _day_of(code: String) -> Dictionary:
	var st := ctx.state()
	var key := [st.regiments.get(code, {}), st.absolute_day(), st.next_courier_id, st.couriers.size()] if st != null else []
	if not _days.has(code) or _days[code]["key"] != key:
		var here := _target_xz(ArmySystem.regiment(ctx.repo, code, ctx.state()))
		_days[code] = Map3DUnits.day_march(ctx.repo, st, code, ctx.meta, here, _shown_xz.get(code, here), ctx.day_share())
		_days[code]["key"] = key.duplicate(true)
	return _days[code]


## The action follows the ORDER (owner 2026-09-29): MARCH while the clock runs and it walks;
## a held stance's standing clip (DEFEND, front-line §2); GARRISON under that
## order; else STANDBY (the start, on arrival, ready on a stopped clock).
func _sync_action(code: String) -> void:
	var walking: bool = _days.has(code) and Map3DUnits.walking(_days[code], ctx.day_share())
	var st := ctx.state()
	var order := ArmySystem.order_of(ctx.repo, st, code) if st != null else ArmySystem.ORDER_STANDBY
	var row: Dictionary = ctx.repo.battle_stances.get(BattleSystem.stance_of(st, code), {}) if st != null else {}
	var action := Map3DUnitRig.action_for(walking and ctx.clock_speed() > 0, order, row)
	if String(_pieces[code].get("action", "")) != action:  # each figure's clip looked up only on a change
		play(code, action)
