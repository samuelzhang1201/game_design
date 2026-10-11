class_name BootLoads
extends RefCounted
## THE HEAVY ART READ ON WORKER THREADS AT LAUNCH (owner 2026-10-10: 点击进入
## 游戏时候会有黑屏卡顿 … 用godot的preload功能先去load一下重资产进来加速): the
## moment GameRoot starts, the 3D world scene (Map3DWorldLoader.request) and
## the art tables every map and the WAR ROOM read — the regiments', couriers',
## houses' and wooden pieces' scenes, each table loading every model it names
## — and the overlay screens' scenes begin loading in parallel through
## ResourceLoader's threaded loads, so the title draws its first frame at once
## and the title's living map opens (MainMenu, once `title_ready`) without
## reading them on the main thread. Main thread only: what a worker thread
## runs is ResourceLoader's own load; this class only asks and collects.

## The art tables read in the background (GameArt's; each loads its models).
const TABLES := [GameArt.ARMY_MODELS, GameArt.COURIER_MODELS, GameArt.HOUSE_MODELS, GameArt.WAR_PIECES]

## Every path asked for and not yet collected.
static var _asked: Array[String] = []
## What has been collected, held so the cache keeps it for the map to take.
static var _held: Dictionary = {}
static var _world := ""


## Ask for everything: the world of `repo`'s pack and the art tables when the
## 3D map is on (and the world built), and `scenes` (the overlays GameRoot instances next,
## whose own load() then waits on these threads instead of reading alone).
static func start(repo: DataRepository, scenes: Array = []) -> void:
	_world = ""
	var tables: Array = []
	if repo.bal("map3d_default") > 0.0:  # no 3D map (the suite): its models are never drawn
		var world := Map3DView.scene_path_for(repo.map_id)
		if Map3DWorldLoader.request(world):
			_world = world
		tables = TABLES
	for path: String in tables + scenes:
		_ask(path)


static func _ask(path: String) -> void:
	if _held.has(path) or path in _asked or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE \
			or ResourceLoader.load_threaded_request(path, "", true) == OK:
		_asked.append(path)


## Collect every load that has finished; true when nothing is left in flight.
static func poll() -> bool:
	for path: String in _asked.duplicate():
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_held[path] = ResourceLoader.load_threaded_get(path)
		_asked.erase(path)
	return _asked.is_empty()


## Whether the title's living map can be made without waiting on a thread:
## the world is in and every art table collected.
static func title_ready() -> bool:
	var done := poll()
	for path: String in TABLES:
		if path in _asked:
			return false
	return done or _world == "" or Map3DWorldLoader.is_ready(_world)


## Whether anything is still being read (tests, tools).
static func loading() -> bool:
	return not poll()
