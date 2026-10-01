extends RefCounted
## The empty 3D world the map's tests open: a bare Node3D carrying a build's
## `map3d_world` meta — no Terrain3D, no rivers, no layers of its own — saved
## in this run's own directory (tests/run_dir.gd). GameRoot's tests point
## every new view at it through Map3DView.world_override (2026-10-02: a
## GameRoot that opened the pack's real build loaded a 514 MB Terrain3D and
## 31,911 houses, ~4 s a test, for assertions about signals and panels).

const RunDir := preload("res://tests/run_dir.gd")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


## Save the world under `dir_name` and return its path.
static func save(dir_name: String) -> String:
	var path := RunDir.dir(dir_name).path_join("world.tscn")
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()
	return path


## Every view made from now on opens the fixture saved under `dir_name`.
static func open_in_views(dir_name: String) -> void:
	Map3DView.world_override = save(dir_name)


## Views open the pack's build again, and the kept world is let go.
static func close_in_views() -> void:
	Map3DView.world_override = ""
	Map3DWorldCache.clear()
