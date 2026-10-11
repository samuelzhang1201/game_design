class_name Map3DQuality
extends RefCounted
## The 3D map's graphics tiers (spec 2026-09-20 §4): data/graphics_quality.csv
## rows low / medium / high / ultra. A first run picks one from the GPU's name
## (detect); user://settings.cfg [graphics] quality — the pause menu's choice —
## overrides it; "auto" defers to the detection. Pure: no scene, no autoload.

const TIERS := ["low", "medium", "high", "ultra"]
const AUTO := "auto"
const SECTION := "graphics"
const KEY := "quality"
## Test and bench seam: a tier forced over the setting and the detection ("" none).
static var forced := ""


static func row(repo: DataRepository, tier: String) -> Dictionary:
	if repo.graphics_quality.has(tier):
		return repo.graphics_quality[tier]
	return repo.graphics_quality.get("high", {})


## A row's number (the CSV parses as strings).
static func num(r: Dictionary, key: String, fallback: float = 1.0) -> float:
	return float(r[key]) if r.has(key) and String(r[key]) != "" else fallback


## SubViewport px per design px for a window `window_scale` design px wide per
## design px: the tier's render_scale of it, held under its max_px_scale (empty:
## no cap). A Retina window is ~2.4x the 1280x720 design, so it renders at
## most max_px_scale there, while a 1080p one (1.5x) is untouched (perf P0
## 2026-10-11: the near zoom is pixel-bound).
static func px_scale(r: Dictionary, window_scale: float) -> float:
	var s := window_scale * num(r, "render_scale")
	var cap := num(r, "max_px_scale", 0.0)
	return minf(s, cap) if cap > 0.0 else s


## The tier a GPU starts at (spec §4): integrated Intel, AMD APUs and software
## GL low; the base Apple M chips, GTX 10xx and older, and MX parts medium;
## everything else — and an unknown adapter — high.
static func detect(adapter: String, vendor: String) -> String:
	var a := (adapter + " " + vendor).to_lower().replace("(r)", "").replace("(tm)", "")
	if a.strip_edges() == "":
		return "high"
	for soft: String in ["llvmpipe", "swiftshader", "softpipe", "software", "basic render"]:
		if a.contains(soft):
			return "low"
	if a.contains("intel") and (a.contains("uhd") or a.contains("iris") or a.contains("hd graphics")
			or a.contains(" xe")):
		return "low"
	if a.contains("radeon") and not a.contains(" rx") and not a.contains(" pro") \
			and (a.contains("radeon graphics") or a.contains("vega")):
		return "low"
	if a.contains("apple m") and not (a.contains(" pro") or a.contains(" max") or a.contains(" ultra")):
		return "medium"
	var gtx := RegEx.create_from_string("gtx\\s*(\\d{3,4})").search(a)
	if gtx != null and int(gtx.get_string(1)) < 1100:
		return "medium"
	if RegEx.create_from_string("\\bmx\\s?\\d{3}").search(a) != null:
		return "medium"
	return "high"


static func setting(path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return AUTO
	var t := String(cfg.get_value(SECTION, KEY, AUTO))
	return t if t in TIERS else AUTO


static func save_setting(path: String, tier: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is a fresh one
	cfg.set_value(SECTION, KEY, tier)
	cfg.save(path)


static func resolve(settings_path: String, adapter: String, vendor: String) -> String:
	if forced in TIERS:
		return forced
	var t := setting(settings_path)
	return t if t != AUTO else detect(adapter, vendor)


## resolve() for the GPU this runs on (the view at load, the pause menu).
static func resolve_here(settings_path: String) -> String:
	return resolve(settings_path, RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor())


## The pause menu's next choice: auto, then each tier, then auto again.
static func next_setting(current: String) -> String:
	var order: Array = [AUTO] + TIERS
	return String(order[(order.find(current) + 1) % order.size()])


## `tier`'s row with `overrides` set over single values (the bench's
## --render-scale), a copy: the CSV's row is shared.
static func merged(repo: DataRepository, tier: String, overrides: Dictionary = {}) -> Dictionary:
	var r: Dictionary = row(repo, tier).duplicate()
	r.merge(overrides, true)
	return r
