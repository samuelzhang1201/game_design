class_name Map3DBodyBridge
extends Node
## ACT-PROJECTION: the admitted body projection's bridge, off until ACT-CUTOVER turns it on (no
## caller yet; `attach` puts it beside a Map3DView). Each published tactical slice hands its commit
## envelope ({cursor: {version, abs_day, substep, receipt}}, BodyMotion's) to `committed` in the frame
## its state is published; the slice plays over its window of the day (Map3DCandidateBodies.slice_share).
## With none, on any other state (a load) or on another day, the bodies stand at their committed
## endpoints. A reloaded world's layer starts from endpoints too. Never reads the Game autoload.

var enabled := false
## -> Map3DLayerUnits or null: the layer to drive (`attach` reads the view's world).
var units_fn: Callable = Callable()
var _units: Map3DLayerUnits
var _state: GameState  ## the state the last envelope was published with
var _driven := false  ## a layer was last told `enabled` true by this bridge (turned off on its return)

static func attach(view: Map3DView) -> Map3DBodyBridge:
	var bridge := Map3DBodyBridge.new()
	bridge.units_fn = func() -> Map3DLayerUnits:
		var world := view.world() if view.is_inside_tree() else null
		return world.get_node_or_null("Units") as Map3DLayerUnits if world != null else null
	bridge.process_priority = view.process_priority - 1  # ahead of the view's layer step
	view.add_child(bridge)
	return bridge

func set_enabled(on: bool) -> void:
	enabled = on
	_state = null
	var units := _layer()
	if units != null:
		units.set_candidate_bodies(on)
		_driven = on
	elif on: _driven = true

func committed(envelope: Dictionary) -> void:
	var units := _layer()
	if not enabled or units == null: return
	_state = units.ctx.state()
	units.set_candidate_bodies(true, BodyMotion._canonical(envelope))  # a JSON copy's whole floats are ints

func _process(_delta: float) -> void: tick()

## A loaded state never plays the envelope of another: the endpoints stand until the next commit.
func tick() -> void:
	var units := _layer()
	if units != null and _state != null and units.ctx.state() != _state:
		_state = null
		units.set_candidate_bodies(true)

func _layer() -> Map3DLayerUnits:
	var units: Map3DLayerUnits = units_fn.call() if units_fn.is_valid() else null
	if units != null and units.ctx == null: units = null
	if units != _units:
		_units = units
		_state = null
		if units != null and (enabled or _driven):
			units.set_candidate_bodies(enabled)
			_driven = enabled
	return units
