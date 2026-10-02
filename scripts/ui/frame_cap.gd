class_name FrameCap
extends RefCounted
## The frame-rate cap (owner 2026-10-02: 开启游戏后的GPU占用很快又是100%):
## with no cap the game draws as many frames as the GPU can, up to the
## display's refresh (120 Hz on a ProMotion screen), so a GPU-bound view keeps
## the GPU at 100% however cheap a frame becomes. The menus' "Frame rate" row
## cycles balance.csv ui_frame_cap_choice_1, _2, … (0 = unlimited), remembered
## in user://settings.cfg [graphics] frame_cap; ui_frame_cap_default is a
## first run's. Pure but for apply(), which sets Engine.max_fps.

const SECTION := "graphics"
const KEY := "frame_cap"
## Test, bench and snapshot seam: a cap forced over the setting (-1 none).
## The suite and the tools force 0, so a cap never slows a headless run or
## reads into a bench row.
static var forced := -1


## The choices in their cycling order, frames a second (0 = unlimited).
static func choices(balance: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var i := 1
	while balance.has("ui_frame_cap_choice_%d" % i):
		out.append(int(balance["ui_frame_cap_choice_%d" % i]))
		i += 1
	return out


static func setting(path: String, balance: Dictionary) -> int:
	var fallback := int(balance.get("ui_frame_cap_default", 60.0))
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return fallback
	var v := int(cfg.get_value(SECTION, KEY, fallback))
	return v if v in choices(balance) else fallback


static func save_setting(path: String, fps: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is a fresh one
	cfg.set_value(SECTION, KEY, fps)
	cfg.save(path)


static func next_setting(current: int, balance: Dictionary) -> int:
	var order := choices(balance)
	if order.is_empty():
		return current
	return order[(order.find(current) + 1) % order.size()]


static func label(fps: int) -> String:
	return "Frame rate: %s" % ("Unlimited" if fps <= 0 else "%d" % fps)


## The cap that runs: the forced one, else the setting.
static func resolve(path: String, balance: Dictionary) -> int:
	return forced if forced >= 0 else setting(path, balance)


static func apply(fps: int) -> void:
	Engine.max_fps = maxi(fps, 0)
