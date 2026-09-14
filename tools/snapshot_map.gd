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
const WIDTH := 1280
const HEIGHT := 720
const UPSCALE := 1

var _out := "user://map_snapshot.png"
var _zoom_mul := 1.0
var _heights := false
var _economy := false
var _armies := false
var _manors := false
var _home := false  # --home 1: keep the opening framing (the crown's provinces)
var _hover := ""  # --hover <kingdom_code>: light that kingdom's border
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
		elif args[i] == "--economy":
			_economy = args[i + 1] == "1"
		elif args[i] == "--manors":
			_manors = args[i + 1] == "1"
		elif args[i] == "--armies":
			_armies = args[i + 1] == "1"
		elif args[i] == "--home":
			_home = args[i + 1] == "1"
		elif args[i] == "--hover":
			_hover = args[i + 1]
		elif args[i] == "--biomes":
			_biomes = args[i + 1] == "1"
		i += 1
	Game.start_campaign(42)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_view = WorldMapView.create()
	_view.size = Vector2(WIDTH, HEIGHT)
	_viewport.add_child(_view)
	_view._go_home()
	if not _home:
		_view._zoom_at(Vector2(WIDTH, HEIGHT) / 2.0, 0.0001)
	if _hover != "" and Game.data.kingdoms.has(_hover):
		_view.hover_state(int(Game.data.kingdoms[_hover]["state_id"]))
	if _zoom_mul != 1.0:
		var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
		var capital: Dictionary = Game.data.burgs[String(realm["capital_burg"])]
		var at := Vector2(float(capital["x"]), float(capital["y"]))
		_view._zoom_at(_view.map_to_screen(at), _zoom_mul)
		_view._offset += Vector2(WIDTH, HEIGHT) / 2.0 - _view.map_to_screen(at)
		_view._clamp_offset()
	_view.show_heights = _heights
	_view.show_economy = _economy
	_view.show_manors = _manors
	_view.show_armies = _armies
	_view.show_biomes = _biomes
	_view.queue_redraw()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10:
		var img := _viewport.get_texture().get_image()
		img.resize(WIDTH * UPSCALE, HEIGHT * UPSCALE, Image.INTERPOLATE_NEAREST)
		var abs := ProjectSettings.globalize_path(_out)
		DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
		var err := img.save_png(abs)
		print("snapshot %s -> %s (mesh %s, zoom %.4f)" % [
			"ok" if err == OK else "FAILED %d" % err, _out,
			_view.terrain_mesh() != null, _view._zoom])
		get_tree().quit()
