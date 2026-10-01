# scripts/ledger3d/ledger_galaxy_layout.gd
class_name LedgerGalaxyLayout
extends RefCounted
## Where each star of the LEDGER's galaxy stands (spec 2026-09-30-ledger-
## galaxy-design §4). Every pair of stars repels by their sizes (two of
## different clusters only ledger_galaxy_cross_repel as hard — owner
## 2026-10-01: the clusters closer together, the stars within one more spread),
## a link is a spring (weaker across clusters), every star is pulled home to
## its cluster's anchor — an opened manor to its province's star. A new star's
## first place is hashed from its id (no RNG) and passes run over sorted ids,
## so one snapshot always lays out the same way; a star keeps its place
## across snapshots — a redraw of the same stars runs no pass, one that adds
## or drops stars only a short settle (final review I1b) — and `step` runs a
## few passes at a time so the chart settles over some frames and then stops.
## Past ledger_galaxy_grid_min_stars a pass repels only pairs within
## ledger_galaxy_repel_cutoff_m, found through a uniform grid (I1c). The flat
## chart is the same model in the plane. No nodes; the FORCES use no clock
## (only `step_within` reads one, to stop a frame's share inside its budget).

var pos: Dictionary = {}        # node id -> Vector3, where it stands now
var pinned: Dictionary = {}     # node id -> true: held where the pointer put it (this viewing only)
var flat := false
var passes_left := 0

var _repo: DataRepository
var _ids: Array[String] = []
var _index: Dictionary = {}
var _size := PackedFloat32Array()
var _anchor: Array[Vector3] = []
var _home_of := PackedInt32Array()     # the index of the star it settles round, or -1
var _cluster_of := PackedInt32Array()  # each star's cluster, as an index
var _edges := PackedInt32Array()       # pairs of indices
var _edge_k := PackedFloat32Array()
var _edge_rest := PackedFloat32Array() # each link's rest length: longer at a busy star (owner 2026-10-01)
var _total := 1


## A star's radius (metres): a pool one fixed size; any other kind grows with
## the square root of its links and, on a province, of what it folds.
static func size_of(repo: DataRepository, node: Dictionary, degree: int) -> float:
	var row := Ledger.type_row(repo, String(node["type"]))
	if String(row.get("star", "instance")) == "pool":
		return repo.bal("ledger_star_pool")
	var folded := 0
	for v: Variant in (node.get("folded", {}) as Dictionary).values():
		folded += int(v)
	var r := repo.bal("ledger_star_min") + repo.bal("ledger_star_per_link") * sqrt(float(degree)) \
		+ repo.bal("ledger_star_per_fold") * sqrt(float(folded))
	return clampf(r, repo.bal("ledger_star_min"), repo.bal("ledger_star_max"))


## cluster -> its anchor (data/ledger_clusters.csv), the 2D one when flat.
static func anchors(repo: DataRepository, as_flat: bool) -> Dictionary:
	var out := {}
	for c: Dictionary in repo.ledger_clusters:
		out[String(c["cluster"])] = c["at2"] if as_flat else c["at"]
	return out


## An offset of about `r` hashed from the id: where a new star first stands.
static func jitter(id: String, r: float, as_flat: bool) -> Vector3:
	var h := id.hash()
	var a := float(h & 0xFFFF) / 65535.0 * TAU
	var b := float((h >> 16) & 0xFFFF) / 65535.0
	var reach := r * (0.5 + 0.5 * b)
	return Vector3(cos(a) * reach, 0.0 if as_flat else (b - 0.5) * r, sin(a) * reach)


## Takes a snapshot: every star it already placed keeps its place (flattened
## when flat), a new one starts round its home star (or its cluster's
## anchor), and a pin on a star no longer drawn is let go. What runs then
## (final review I1b): the first chart, or the chart laid flat or stood up,
## settles fully (ledger_galaxy_passes); the same stars as before run nothing
## more than they had left; other stars, ledger_galaxy_resettle_passes.
func setup(repo: DataRepository, snap: Dictionary, as_flat: bool) -> void:
	_repo = repo
	var fresh := pos.is_empty() or as_flat != flat
	flat = as_flat
	var at := anchors(repo, as_flat)
	var degree := {}
	for l: Dictionary in snap["links"]:
		for e: String in [String(l["from"]), String(l["to"])]:
			degree[e] = int(degree.get(e, 0)) + 1
	var by_id := {}
	_ids.clear()
	for n: Dictionary in snap["nodes"]:
		by_id[String(n["id"])] = n
		_ids.append(String(n["id"]))
	_ids.sort()
	_index.clear()
	for i in _ids.size():
		_index[_ids[i]] = i
	_size.resize(_ids.size())
	_home_of.resize(_ids.size())
	_cluster_of.resize(_ids.size())
	_anchor.clear()
	var cluster_index := {}
	for i in _ids.size():
		var n: Dictionary = by_id[_ids[i]]
		var c := String(n.get("cluster", ""))
		if not cluster_index.has(c):
			cluster_index[c] = cluster_index.size()
		_cluster_of[i] = int(cluster_index[c])
		_size[i] = size_of(repo, n, int(degree.get(_ids[i], 0)))
		_anchor.append(at.get(String(n.get("cluster", "")), Vector3.ZERO))
		_home_of[i] = int(_index.get(String(n.get("home_id", "")), -1))
	var kept := {}
	for id: String in _ids:
		if pos.has(id):
			kept[id] = _flat(pos[id])
	var unchanged := not fresh and kept.size() == _ids.size() and pos.size() == _ids.size()
	for i in _ids.size():
		if kept.has(_ids[i]):
			continue
		var h := _home_of[i]
		var base: Vector3 = _anchor[i]
		if h >= 0:
			base = kept.get(_ids[h], _anchor[h])
		kept[_ids[i]] = _flat(base + jitter(_ids[i], repo.bal("ledger_galaxy_rest_m") * 2.0, as_flat))
	pos = kept
	for id: String in pinned.keys():
		if not _index.has(id):
			pinned.erase(id)
	_edges.clear()
	_edge_k.clear()
	_edge_rest.clear()
	var k := repo.bal("ledger_galaxy_spring")
	var rest := repo.bal("ledger_galaxy_rest_m")
	var per_link := repo.bal("ledger_galaxy_rest_per_link")
	var busy_cap := int(repo.bal("ledger_galaxy_rest_busy_cap"))
	for l: Dictionary in snap["links"]:
		var a := int(_index.get(String(l["from"]), -1))
		var b := int(_index.get(String(l["to"]), -1))
		if a < 0 or b < 0 or a == b:
			continue
		_edges.append(a)
		_edges.append(b)
		var same := String(by_id[_ids[a]].get("cluster", "")) == String(by_id[_ids[b]].get("cluster", ""))
		_edge_k.append(k if same else k * repo.bal("ledger_galaxy_cross_spring"))
		# a hub's many neighbours stand on a sphere round it: the busier end's
		# links lengthen its springs so they have room on it (owner 2026-10-01:
		# the King's inner ring crowded while the court's edge spread)
		# (held to ledger_galaxy_rest_busy_cap links: an opened province's
		# dozens of manors must not push its stars into the next cluster)
		var busy := mini(maxi(int(degree.get(_ids[a], 0)), int(degree.get(_ids[b], 0))), busy_cap)
		_edge_rest.append(rest + per_link * sqrt(float(busy)))
	if fresh:
		_total = int(repo.bal("ledger_galaxy_passes"))
		passes_left = _total
	elif not unchanged:
		var short := int(repo.bal("ledger_galaxy_resettle_passes"))
		if passes_left < short:
			_total = short
			passes_left = short


func settled() -> bool:
	return passes_left <= 0


## Holds a star where the pointer put it; the rest settle round it.
func pin(id: String, at: Vector3) -> void:
	if not _index.has(id):
		return
	pinned[id] = true
	pos[id] = _flat(at)
	if passes_left <= 0:
		_total = int(_repo.bal("ledger_galaxy_passes"))
		passes_left = int(_total * _repo.bal("ledger_galaxy_pin_share"))


const PASS_MARGIN := 1.25   # a pass on a busy machine can cost a quarter more than the dearest yet


## Runs passes for at most `budget_ms` of this frame (the view's
## ledger_galaxy_ms_per_frame): always one, then another only while the
## dearest pass so far still fits in what is left, so a frame never runs
## past its budget by starting a pass it cannot finish. Returns the passes run.
func step_within(budget_ms: float) -> int:
	var t0 := Time.get_ticks_usec()
	var budget := budget_ms * 1000.0
	var ran := 0
	var dearest := 0.0
	while not settled():
		var t1 := Time.get_ticks_usec()
		if ran > 0 and float(t1 - t0) + dearest * PASS_MARGIN > budget:
			break
		step(1)
		dearest = maxf(dearest, float(Time.get_ticks_usec() - t1))
		ran += 1
	return ran


## Runs up to `passes` passes, cooling as the chart settles.
func step(passes: int) -> void:
	var n := _ids.size()
	if n == 0:
		passes_left = 0
		return
	var p := PackedVector3Array()
	p.resize(n)
	for i in n:
		p[i] = pos[_ids[i]]
	var rep := _repo.bal("ledger_galaxy_repel")
	var home := _repo.bal("ledger_galaxy_home")
	var cap := _repo.bal("ledger_galaxy_step_max_m")
	var half := PackedFloat32Array()   # each star's share of a pair's repulsion
	half.resize(n)
	for i in n:
		half[i] = rep * _size[i] * 0.5
	var f := PackedVector3Array()
	f.resize(n)
	var grid := float(n) >= _repo.bal("ledger_galaxy_grid_min_stars")
	var cut := _repo.bal("ledger_galaxy_repel_cutoff_m")
	# the flat chart lays every cluster in one plane, where they spread wider
	# and bled together at the 3D share (critic, round 2): its own share
	var cross := _repo.bal("ledger_galaxy_cross_repel_flat" if flat else "ledger_galaxy_cross_repel")
	var cl := _cluster_of
	# two stars nearer than their radii and ledger_galaxy_gap_m are pushed
	# apart by ledger_galaxy_gap_push of the overlap besides (owner 2026-10-01:
	# no two discs crowd), whichever cluster they are of
	var gap := _repo.bal("ledger_galaxy_gap_m")
	var gap_k := _repo.bal("ledger_galaxy_gap_push")
	var sz := _size
	for _k in mini(passes, passes_left):
		for i in n:
			var h := _home_of[i]
			var target: Vector3 = p[h] if h >= 0 else _anchor[i]
			f[i] = (target - p[i]) * home
		if grid:
			_repel_near(p, half, f, cut, cross, gap, gap_k)
		else:
			# every pair repels (the hot loop: each star's own place, share and
			# force held in locals, one read and one write of the other's a pair)
			for i in n:
				var pi := p[i]
				var hi := half[i]
				var fi := f[i]
				var ci := cl[i]
				var si := sz[i] + gap
				for j in range(i + 1, n):
					var d := pi - p[j]
					var dd := d.length_squared()
					var push := d * ((hi + half[j]) / (dd + 0.5) * (1.0 if cl[j] == ci else cross))
					var need := si + sz[j]
					if dd < need * need:
						var ln := sqrt(dd) + 1e-6
						push += d * (gap_k * (need - ln) / ln)
					fi += push
					f[j] -= push
				f[i] = fi
		for e in range(0, _edges.size(), 2):
			var a := _edges[e]
			var b := _edges[e + 1]
			var dv := p[b] - p[a]
			var ln := dv.length() + 1e-6
			var pull := dv / ln * _edge_k[e >> 1] * (ln - _edge_rest[e >> 1])
			f[a] += pull
			f[b] -= pull
		var cool := 0.2 + 0.8 * float(passes_left) / float(maxi(_total, 1))
		for i in n:
			if pinned.has(_ids[i]):
				continue
			var s := (f[i] * cool).limit_length(cap)
			if flat:
				s.y = 0.0
			p[i] += s
		passes_left -= 1
	for i in n:
		pos[_ids[i]] = p[i]


## The 13 neighbour cells half of a cell's 26 (the other half see it from
## their side), so each pair of cells is visited once.
const _FORWARD: Array[Vector3i] = [Vector3i(1, -1, -1), Vector3i(1, -1, 0), Vector3i(1, -1, 1),
	Vector3i(1, 0, -1), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 1, -1), Vector3i(1, 1, 0),
	Vector3i(1, 1, 1), Vector3i(0, 1, -1), Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 0, 1)]


## Repulsion between the pairs nearer than `cut` only (final review I1c): the
## stars dealt into cells `cut` wide in index (sorted id) order, every cell
## met with itself and its 13 forward neighbours (gathered once a cell, in
## _FORWARD's order) in the order it was first filled — the same sums in the
## same order for the same places.
func _repel_near(p: PackedVector3Array, half: PackedFloat32Array, f: PackedVector3Array, cut: float,
		cross: float, gap: float, gap_k: float) -> void:
	var cl := _cluster_of
	var sz := _size
	var inv := 1.0 / maxf(cut, 1e-6)
	var cut2 := cut * cut
	var cells := {}
	var order: Array[Vector3i] = []
	for i in p.size():
		var v := p[i]
		var key := Vector3i(floori(v.x * inv), floori(v.y * inv), floori(v.z * inv))
		var bucket: Variant = cells.get(key)
		if bucket == null:
			cells[key] = PackedInt32Array([i])
			order.append(key)
		else:
			var grown: PackedInt32Array = bucket
			grown.append(i)
			cells[key] = grown
	for key: Vector3i in order:
		var mine: PackedInt32Array = cells[key]
		var near := PackedInt32Array()   # the forward neighbours' stars
		for off: Vector3i in _FORWARD:
			var other: Variant = cells.get(key + off)
			if other != null:
				near.append_array(other as PackedInt32Array)
		var m := mine.size()
		for a in m:
			var i := mine[a]
			var pi := p[i]
			var hi := half[i]
			var fi := f[i]
			var ci := cl[i]
			var si := sz[i] + gap
			for b in range(a + 1, m):
				var j := mine[b]
				var d := pi - p[j]
				var dd := d.length_squared()
				if dd < cut2:
					var push := d * ((hi + half[j]) / (dd + 0.5) * (1.0 if cl[j] == ci else cross))
					var need := si + sz[j]
					if dd < need * need:
						var ln := sqrt(dd) + 1e-6
						push += d * (gap_k * (need - ln) / ln)
					fi += push
					f[j] -= push
			for j in near:
				var d := pi - p[j]
				var dd := d.length_squared()
				if dd < cut2:
					var push := d * ((hi + half[j]) / (dd + 0.5) * (1.0 if cl[j] == ci else cross))
					var need := si + sz[j]
					if dd < need * need:
						var ln := sqrt(dd) + 1e-6
						push += d * (gap_k * (need - ln) / ln)
					fi += push
					f[j] -= push
			f[i] = fi


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z) if flat else v
