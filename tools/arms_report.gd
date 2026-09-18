extends SceneTree
## Where a map pack's coats of arms come from (HouseArms): its own installed
## art, arms_bindings.csv, or borrowed from the other packs' — and whether
## the pool ran short, which is the only case that needs new arms generated
## (assets/flux/arms_prompts.py). Run after importing a new map:
##   Godot --headless --path . -s tools/arms_report.gd [-- --map ID --list]
## --list prints every key and the art it wears.

func _init() -> void:
	var map := DataRepository.default_pack_id()
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--map":
			map = args[i + 1]
	var repo := DataRepository.load_all("res://data")
	if repo == null or (repo.map_id != map and not repo.load_map(map)):
		push_error("arms_report: cannot load pack %s: %s" % [map, DataRepository.last_error])
		quit(1)
		return
	var needed := HouseArms.needed_keys(repo)
	var src := HouseArms.pool(repo)
	var r := HouseArms.report(repo)
	print("pack %s: %d kingdoms, %d houses need arms" % [map,
		(needed["kingdoms"] as Array).size(), (needed["houses"] as Array).size()])
	print("  own %d, bound %d, borrowed %d (pool: %d kingdom, %d house arms)" % [
		r["own"], r["bound"], r["borrowed"], (src["kingdom"] as Array).size(), (src["house"] as Array).size()])
	if int(r["repeated"]) > 0 or int(r["missing"]) > 0:
		print("  SHORT: %d repeat art already worn, %d have none — generate new arms for this pack" % [
			r["repeated"], r["missing"]])
	else:
		print("  every key wears its own coat of arms — nothing to generate")
	if args.has("--list"):
		for key: String in needed["kingdoms"] + needed["houses"]:
			print("  %-32s %s" % [key, HouseArms.resolved_path(repo, key)])
	quit(0)
