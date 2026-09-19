extends Node
## Render the world map to a PNG for palette work — the whole world at the
## view's zoom-out floor, drawn exactly as the game draws it (terrain mesh,
## political wash, borders, labels, pins), without the screens around it.
##
## Runs as a scene so the autoloads (Game) exist; needs the real renderer,
## so a window opens for a moment:
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_map.tscn \
##     -- --out assets/flux/out/palette/after.png [--zoom 3.0]
## --zoom multiplies the floor zoom (3.0 = three times closer, centred on
## the player's capital).

## The game's design viewport; the PNG is upscaled 2x (nearest) so it shows
## what a 1280x720 window shows, pins and labels at their real size.
## The design viewport; --size N renders N x N*9/16 instead, for a high
## resolution sheet (the view lays out in design units, so a larger render
## shows the same framing with more pixels, not more map).
const WIDTH := 1280
const HEIGHT := 720
var _width := WIDTH
var _height := HEIGHT
const UPSCALE := 1

var _out := "user://map_snapshot.png"
var _zoom_mul := 1.0
var _heights := false
var _armies := false
var _manors := false
var _home := false  # --home 1: keep the opening framing (the crown's provinces)
var _hover := ""  # --hover <kingdom_code>: light that kingdom's border
var _annex := 0  # --annex 1: buy the first cross-border manor, framed on it; 2: frame it only (the before shot)
var _annexed_at := Vector2.ZERO
var _clouds := false  # --clouds 1: run the clock so the clouds show
var _biomes := true  # BIOMES LAYER (experiment 2026-09-14): --biomes 0 for a before shot
var _viewport: SubViewport
var _view: WorldMapView
var _frames := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size() - 1:
		if args[i] == "--out":
			_out = args[i + 1]
		elif args[i] == "--zoom":
			_zoom_mul = float(args[i + 1])
		elif args[i] == "--heights":
			_heights = args[i + 1] == "1"
		elif args[i] == "--manors":
			_manors = args[i + 1] == "1"
		elif args[i] == "--armies":
			_armies = args[i + 1] == "1"
		elif args[i] == "--home":
			_home = args[i + 1] == "1"
		elif args[i] == "--hover":
			_hover = args[i + 1]
		elif args[i] == "--annex":
			_annex = int(args[i + 1])
		elif args[i] == "--clouds":
			_clouds = args[i + 1] == "1"
		elif args[i] == "--size":
			_width = maxi(int(args[i + 1]), 320)
			@warning_ignore("integer_division")
			_height = _width * 9 / 16
		elif args[i] == "--biomes":
			_biomes = args[i + 1] == "1"
		i += 1
	Game.start_campaign(42)
	if _annex > 0:
		_buy_across_the_border(_annex == 1)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(_width, _height)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_view = WorldMapView.create()
	_view.size = Vector2(_width, _height)
	_viewport.add_child(_view)
	_view._go_home()
	if not _home:
		_view._zoom_at(Vector2(_width, _height) / 2.0, 0.0001)
	if _hover != "" and Game.data.kingdoms.has(_hover):
		_view.hover_state(int(Game.data.kingdoms[_hover]["state_id"]))
	if _zoom_mul != 1.0:
		var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
		var capital: Dictionary = Game.data.burgs[String(realm["capital_burg"])]
		var at := Vector2(float(capital["x"]), float(capital["y"]))
		_view._zoom_at(_view.map_to_screen(at), _zoom_mul)
		_view._offset += Vector2(_width, _height) / 2.0 - _view.map_to_screen(at)
		_view._clamp_offset()
	if _annexed_at != Vector2.ZERO:
		_view._zoom = 6.0
		_view._offset = Vector2(_width, _height) / 2.0 - _annexed_at * _view._zoom
		_view._clamp_offset()
	_view.show_heights = _heights
	_view.show_manors = _manors
	_view.show_armies = _armies
	_view.show_biomes = _biomes
	if _clouds:
		Game.data.balance["map_cloud_fade_s"] = 0.001
		Game.data.balance["map_cloud_max"] = 12.0
		Game.data.balance["map_cloud_interval_min_s"] = 0.0
		Game.data.balance["map_cloud_interval_max_s"] = 0.0
		Game.set_clock_speed(1)
	_view.queue_redraw()


## The first manor, in cell order, the crown may buy across the border, bought
## through the order system (owner 2026-09-14: it joins the realm's richest
## bordering province), so the shot shows the border taking it in.
func _buy_across_the_border(buy: bool) -> void:
	var ids: Array = Game.data.manors.keys()
	ids.sort()
	for id: int in ids:
		var how := MapManors.purchase_kind(Game.data, Game.state, id)
		if String(how["kind"]) != "foreign":
			continue
		_annexed_at = MapTerrain.cell_center(Game.data, Game.data.cells[id])
		if not buy:
			print("annex: framing cell %d (%s), not bought" % [id, MapManors.label_of(Game.data, id)])
			return
		Game.state.metrics["treasury"] = 1.0e7
		var out := Game.try_execute(ActionRequest.make("MANOR_BUY", {"manor": id}))
		print("annex %s: cell %d (%s) -> %s, now in %s" % ["ok" if bool(out["ok"]) else "FAILED " + String(out["error"]),
			id, MapManors.label_of(Game.data, id), String(how["province"]),
			MapManors.province_of(Game.data, id, Game.state)])
		_annexed_at = MapTerrain.cell_center(Game.data, Game.data.cells[id])
		return
	print("annex: no manor touches the realm from abroad")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10:
		var img := _viewport.get_texture().get_image()
		img.resize(_width * UPSCALE, _height * UPSCALE, Image.INTERPOLATE_NEAREST)
		var abs_path := ProjectSettings.globalize_path(_out)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		var err := img.save_png(abs_path)
		print("snapshot %s -> %s (mesh %s, zoom %.4f)" % [
			"ok" if err == OK else "FAILED %d" % err, _out,
			_view.terrain_mesh() != null, _view._zoom])
		get_tree().quit()
