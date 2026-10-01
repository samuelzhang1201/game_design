class_name TitleRealm
extends Control
## THE TITLE'S LIVING REALM (owner 2026-10-01, title plan A, "The Living
## Realm"): behind the title menu, the live 3D map of the player's own seat —
## the reign the player is about to take, as Start would begin it (a preview
## GameState of the same seed, never Game.state) — the camera drifting slowly
## round the home province, the sun turning, the clouds and the wind moving.
## No HUD, no picking: it is a picture. Start sweeps the camera down to the
## game's own opening view (`sweep`) so the reign opens where the title left it.
## Every number is balance.csv ui_title_*; with no built world it is not made
## (TitleRealm.available) and the menu keeps its painted page.

signal swept

## The view handed to the game's first screen as the reign begins
## (`hand_over`), so the map the title showed IS the map laid on the table —
## not a second one built from nothing (~2.5 s of the screen swap).
static var handed: Map3DView

var view: Map3DView
var preview: GameState
var _yaw := 0.0
var _day := 0.0
var _distance := 0.0
var _sweep_t := -1.0
var _sweep_from := Vector3.ZERO  # distance, yaw, day share at the sweep's start
var _view_filter := Control.MOUSE_FILTER_STOP

## Whether the title can show the realm: the war table on, the 3D map on and
## the pack's world built.
static func available() -> bool:
	return UiPalette.war_table() and Game.data.bal("map3d_default") > 0.0 \
		and Map3DView.has_scene(Game.data.map_id) \
		and float(Game.data.balance.get("ui_title_living", 1.0)) > 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if preview == null:
		preview = GameState.new_campaign(Game.data, int(Game.data.bal("ui_title_seed")))
	view = Map3DView.create(Game.data)
	view.set_meta("state_fn", func() -> GameState: return preview)  # whose reign the map draws
	_view_filter = view.mouse_filter
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.activate()
	var ctx := view.context()
	if ctx == null:
		return  # the world would not open: the notice says why, the page shows
	# a picture, not a map: no HUD, the clouds and wind running, the day ours
	view.get_node("Hud").visible = false
	ctx.clock_fn = func() -> int: return 1
	ctx.day_fn = func() -> float: return _day
	_day = Game.data.bal("ui_title_day_share")
	_distance = Game.data.bal("ui_title_distance_m")
	_yaw = Game.data.bal("ui_title_yaw_deg")
	_place()

func _process(delta: float) -> void:
	var ctx := view.context() if view != null else null
	if ctx == null:
		return
	if _sweep_t >= 0.0:
		_step_sweep(delta)
		return
	_yaw += Game.data.bal("ui_title_drift_deg_per_s") * delta
	_day = fposmod(_day + Game.data.bal("ui_title_day_per_s") * delta, 1.0)
	_place()

func _place() -> void:
	var ctx := view.context()
	(view.get_node("Viewport/CameraRig") as Map3DCameraRig).place(ctx.home(), _distance, _yaw)

## Start: down from the title's height to the game's opening view (its scale
## bar's distance, north up), over ui_title_sweep_s; `swept` when it lands.
func sweep() -> void:
	var ctx := view.context() if view != null else null
	if ctx == null:
		swept.emit.call_deferred()
		return
	_sweep_from = Vector3(_distance, wrapf(_yaw, -180.0, 180.0), _day)
	_sweep_t = 0.0

func _step_sweep(delta: float) -> void:
	_sweep_t = minf(_sweep_t + delta / maxf(Game.data.bal("ui_title_sweep_s"), 0.01), 1.0)
	var k := _sweep_t * _sweep_t * (3.0 - 2.0 * _sweep_t)  # smoothstep
	var rig := view.get_node("Viewport/CameraRig") as Map3DCameraRig
	_distance = lerpf(_sweep_from.x, rig.start_distance(), k)
	_yaw = lerpf(_sweep_from.y, 0.0, k)
	_place()
	if _sweep_t >= 1.0:
		_sweep_t = -2.0
		swept.emit()

## Give the view to the game (TitleRealm.handed, taken by the first screen's
## Map3DView.attach): out of the title, made a map again — the live reign's
## state and clock, its HUD, its picking. Nothing when the world never opened.
func hand_over() -> void:
	var ctx := view.context() if view != null else null
	if ctx == null:
		return
	set_process(false)
	remove_child(view)
	view.remove_meta("state_fn")
	ctx.state_fn = func() -> GameState: return Game.state
	ctx.clock_fn = func() -> int: return Game.clock_speed
	ctx.day_fn = func() -> float: return Game.day_progress
	view.get_node("Hud").visible = true
	view.mouse_filter = _view_filter
	handed = view
	view = null

## The handed view, once (null when the title handed none).
static func take_handed() -> Map3DView:
	var v := handed
	handed = null
	return v

## The place the title shows, for its caption: the home province's capital
## town and the house that holds it.
func caption() -> Dictionary:
	var data := Game.data
	var code := MapManors.home_province(data, preview)
	var p: Dictionary = data.provinces.get(code, {})
	var town := String(p.get("label", code))
	var capital := String(p.get("capital_burg", ""))
	if capital != "" and data.burgs.has(capital):
		town = String(data.burgs[capital]["label"])
	return {"place": town, "house": MapManors.crown(preview),
		"season": Calendar.season_name(preview.tick)}
