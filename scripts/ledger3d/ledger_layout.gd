# scripts/ledger3d/ledger_layout.gd
class_name LedgerLayout
extends RefCounted
## Where each sphere stands (spec 2026-09-30 §6.2). Type spheres stand at
## their hand-set places, so the type level is the same every time; the
## spheres of an ego network or of the court are laid out per layer by a
## force layout with a fixed number of passes from places set by sorted ids,
## so one snapshot always lays out the same way. The layer sets the height.


static func layer_y(repo: DataRepository, layer: String) -> float:
	return float(maxi(Ledger.LAYERS.find(layer), 0)) * repo.bal("ledger_layer_gap_m")


static func positions(repo: DataRepository, snap: Dictionary) -> Dictionary:
	var out := {}
	var by_layer := {}
	for n: Dictionary in snap["nodes"]:
		var y := layer_y(repo, String(n["layer"]))
		if n.has("x"):
			out[String(n["id"])] = Vector3(float(n["x"]), y, float(n["z"]))
		else:
			if not by_layer.has(String(n["layer"])):
				by_layer[String(n["layer"])] = []
			by_layer[String(n["layer"])].append(String(n["id"]))
	if by_layer.is_empty():
		return out
	var focus := String(snap.get("focus_id", ""))
	var side := {}   # -1 upstream of the focus (left), +1 downstream (right)
	for l: Dictionary in snap["links"]:
		if String(l["to"]) == focus:
			side[String(l["from"])] = -1.0
		elif String(l["from"]) == focus:
			side[String(l["to"])] = 1.0
	var ring := repo.bal("ledger_ego_ring_m")
	for layer: String in by_layer:
		var ids: Array = by_layer[layer]
		ids.sort()
		var y := layer_y(repo, layer)
		for i in ids.size():
			var id := String(ids[i])
			if id == focus:
				out[id] = Vector3(0.0, y, 0.0)
				continue
			var a := PI * (float(i) + 0.5) / float(ids.size())
			var x := sin(a) * ring
			if side.has(id):
				x = absf(x) * float(side[id]) + float(side[id]) * ring * 0.5
			out[id] = Vector3(x, y, cos(a) * ring)
	var repel := repo.bal("ledger_layout_repel")
	var spring := repo.bal("ledger_layout_spring")
	for _pass in int(repo.bal("ledger_layout_iterations")):
		for layer: String in by_layer:
			var ids: Array = by_layer[layer]
			for id: String in ids:
				if id == focus:
					continue
				var p: Vector3 = out[id]
				var f := Vector2.ZERO
				for other: String in ids:
					if other == id:
						continue
					var q: Vector3 = out[other]
					var dv := Vector2(p.x - q.x, p.z - q.z)
					f += dv / maxf(dv.length_squared(), 0.01) * repel
				f -= Vector2(p.x, p.z) * spring
				if side.has(id):
					f.x += float(side[id]) * spring * ring
				var step := f * 0.1
				var nx := p.x + step.x
				if side.has(id) and signf(nx) != float(side[id]):
					nx = float(side[id]) * 0.1  # a side is kept: upstream stays left
				out[id] = Vector3(nx, p.y, p.z + step.y)
	_fit_to_disc(repo, out, by_layer, focus)
	return out


## The spheres stand ON their disc: a laid-out layer that the force pass
## spread wider than the disc (the court's 21, repelling one another, reached
## twice its radius) is drawn in about the disc's centre, its shape kept, to
## ledger_layout_margin_m inside the rim.
static func _fit_to_disc(repo: DataRepository, out: Dictionary, by_layer: Dictionary, focus: String) -> void:
	var limit := repo.bal("ledger_disc_radius_m") - repo.bal("ledger_layout_margin_m")
	if limit <= 0.0:
		return
	for layer: String in by_layer:
		var reach := 0.0
		for id: String in by_layer[layer]:
			var p: Vector3 = out[id]
			reach = maxf(reach, Vector2(p.x, p.z).length())
		if reach <= limit:
			continue
		var k := limit / reach
		for id: String in by_layer[layer]:
			if id == focus:
				continue
			var p: Vector3 = out[id]
			out[id] = Vector3(p.x * k, p.y, p.z * k)


## The layers that hold at least one sphere in this snapshot, bottom to top:
## only their discs are drawn (Task 10: the court lens stands on one disc,
## not over two empty ones).
static func layers_present(snap: Dictionary) -> Array[String]:
	var seen := {}
	for n: Dictionary in snap.get("nodes", []):
		seen[String(n["layer"])] = true
	var out: Array[String] = []
	for layer: String in Ledger.LAYERS:
		if seen.has(layer):
			out.append(layer)
	return out


## What the camera frames (LedgerOrbit.frame): each sphere's reach along the
## three axes and ledger_frame_rim_samples points round the rim of each disc
## drawn, so neither a sphere nor a disc runs off the opening view.
static func frame_points(repo: DataRepository, snap: Dictionary, pos: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n: Dictionary in snap.get("nodes", []):
		var id := String(n["id"])
		if not pos.has(id):
			continue
		var p: Vector3 = pos[id]
		var r := repo.bal("ledger_sphere_radius_instance") if bool(n.get("instance", false)) \
			else repo.bal("ledger_sphere_radius_type")
		for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			out.append(p + axis * r)
			out.append(p - axis * r)
	var samples := maxi(int(repo.bal("ledger_frame_rim_samples")), 4)
	for layer: String in layers_present(snap):
		var y := disc_y(repo, layer)
		var rim := disc_radius(repo, snap, pos, layer)
		for i in samples:
			var a := TAU * float(i) / float(samples)
			out.append(Vector3(cos(a) * rim, y, sin(a) * rim))
	return out


## A disc's radius: it reaches ledger_disc_pad_m past the farthest edge of
## its own layer's spheres from the axis, never under ledger_disc_min_m nor
## over ledger_disc_radius_m — so a two-sphere ego network stands on a
## small disc the camera can come close to, and the type level on its full
## disc. The discs stay on one axis, an orrery's tiers.
static func disc_radius(repo: DataRepository, snap: Dictionary, pos: Dictionary, layer: String) -> float:
	var reach := 0.0
	for n: Dictionary in snap.get("nodes", []):
		var id := String(n["id"])
		if String(n["layer"]) != layer or not pos.has(id):
			continue
		var p: Vector3 = pos[id]
		var r := repo.bal("ledger_sphere_radius_instance") if bool(n.get("instance", false)) \
			else repo.bal("ledger_sphere_radius_type")
		reach = maxf(reach, Vector2(p.x, p.z).length() + r)
	return clampf(reach + repo.bal("ledger_disc_pad_m"), repo.bal("ledger_disc_min_m"), repo.bal("ledger_disc_radius_m"))


## The height a layer's disc floats at, under its spheres.
static func disc_y(repo: DataRepository, layer: String) -> float:
	return layer_y(repo, layer) - repo.bal("ledger_disc_offset_m")
