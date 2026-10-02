extends SceneTree
## The 3D map's committed PREVIEW textures (spec 2026-09-20 §2, Ruling 15):
## 512 px copies of the git-ignored Poly Haven pairs the roads and bridges
## wear, plus the clouds' shape, into res://assets/3D/terrain/textures_preview/, so the
## look's .tres (scenes/map3d/materials/) show a real texture in the editor on
## any checkout. The game swaps in the full-resolution pair when it is packed
## (Map3DLayerRoads.texture_pair). Re-run after tools/map3d/pack_textures.py
## changes a pair, then --import:
##   GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/make_previews.gd

const SRC_DIR := "res://assets/3D/terrain/textures/"
const OUT_DIR := "res://assets/3D/terrain/textures_preview/"
const PAIRS := ["rocky_trail_02_alb_ht", "rocky_trail_02_nrm_rgh", "medieval_blocks_03_alb_ht",
	"medieval_blocks_03_nrm_rgh"]
## The previews' longest side, px.
const PREVIEW_PX := 512


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failed := false
	for name: String in PAIRS:
		var src := ProjectSettings.globalize_path(SRC_DIR + name + ".png")
		var img := Image.load_from_file(src)
		if img == null or img.is_empty():
			push_error("make_previews: %s is missing (tools/map3d/pack_textures.py)" % src)
			failed = true
			continue
		img.resize(PREVIEW_PX, PREVIEW_PX, Image.INTERPOLATE_LANCZOS)
		_save(img, name)
	var repo := DataRepository.load_all("res://data")
	if repo == null:
		push_error("make_previews: data failed to load: " + DataRepository.last_error)
		quit(1)
		return
	# the deck's own seed (scenes/map3d/map3d_world.tscn's Clouds)
	var world := (load("res://scenes/map3d/map3d_world.tscn") as PackedScene).instantiate()
	var seed_v := int((world.get_node("Clouds") as Map3DLayerClouds).cloud_seed)
	world.free()
	var tex := Map3DCloudField.cloud_texture(seed_v) as Texture2D
	var cloud := tex.get_image()
	var longest := maxi(cloud.get_width(), cloud.get_height())
	if longest > PREVIEW_PX:
		var k := float(PREVIEW_PX) / float(longest)
		cloud.resize(roundi(cloud.get_width() * k), roundi(cloud.get_height() * k),
			Image.INTERPOLATE_LANCZOS)
	_save(cloud, "cloud_shape")
	quit(1 if failed else 0)


func _save(img: Image, name: String) -> void:
	var out := ProjectSettings.globalize_path(OUT_DIR + name + ".png")
	var err := img.save_png(out)
	print("make_previews: %s %dx%d -> %s (%s)" % [name, img.get_width(), img.get_height(), out,
		error_string(err)])
