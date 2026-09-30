# scripts/ledger3d/ledger_galaxy_layout.gd
class_name LedgerGalaxyLayout
extends RefCounted
## Where each star of the LEDGER's galaxy stands (spec 2026-09-30-ledger-
## galaxy-design §4). Every pair of stars repels by their sizes, a link is a
## spring (weaker across clusters), every star is pulled home to its
## cluster's anchor — an opened manor to its province's star. A new star's
## first place is hashed from its id (no RNG) and passes run over sorted ids,
## so one snapshot always lays out the same way; a star keeps its place
## across snapshots, and `step` runs a few passes at a time so the chart
## settles over some frames and then stops. The flat chart is the same model
## in the plane. Pure: no nodes, no clock.

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
var _edges := PackedInt32Array()       # pairs of indices
var _edge_k := PackedFloat32Array()
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
## anchor), a pin on a star no longer drawn is let go, and
## ledger_galaxy_passes are set to run.
func setup(repo: DataRepository, snap: Dictionary, as_flat: bool) -> void:
	_repo = repo
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
	_anchor.clear()
	for i in _ids.size():
		var n: Dictionary = by_id[_ids[i]]
		_size[i] = size_of(repo, n, int(degree.get(_ids[i], 0)))
		_anchor.append(at.get(String(n.get("cluster", "")), Vector3.ZERO))
		_home_of[i] = int(_index.get(String(n.get("home_id", "")), -1))
	var kept := {}
	for id: String in _ids:
		if pos.has(id):
			kept[id] = _flat(pos[id])
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
	var k := repo.bal("ledger_galaxy_spring")
	for l: Dictionary in snap["links"]:
		var a := int(_index.get(String(l["from"]), -1))
		var b := int(_index.get(String(l["to"]), -1))
		if a < 0 or b < 0 or a == b:
			continue
		_edges.append(a)
		_edges.append(b)
		var same := String(by_id[_ids[a]].get("cluster", "")) == String(by_id[_ids[b]].get("cluster", ""))
		_edge_k.append(k if same else k * repo.bal("ledger_galaxy_cross_spring"))
	_total = int(repo.bal("ledger_galaxy_passes"))
	passes_left = _total


func settled() -> bool:
	return passes_left <= 0


## Holds a star where the pointer put it; the rest settle round it.
func pin(id: String, at: Vector3) -> void:
	if not _index.has(id):
		return
	pinned[id] = true
	pos[id] = _flat(at)
	if passes_left <= 0:
		passes_left = int(_total * 0.3)


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
	var rest := _repo.bal("ledger_galaxy_rest_m")
	var cap := _repo.bal("ledger_galaxy_step_max_m")
	var half := PackedFloat32Array()   # each star's share of a pair's repulsion
	half.resize(n)
	for i in n:
		half[i] = rep * _size[i] * 0.5
	var f := PackedVector3Array()
	f.resize(n)
	for _k in mini(passes, passes_left):
		for i in n:
			var h := _home_of[i]
			var target: Vector3 = p[h] if h >= 0 else _anchor[i]
			f[i] = (target - p[i]) * home
		# every pair repels (the hot loop: each star's own place, share and
		# force held in locals, one read and one write of the other's a pair)
		for i in n:
			var pi := p[i]
			var hi := half[i]
			var fi := f[i]
			for j in range(i + 1, n):
				var d := pi - p[j]
				var push := d * ((hi + half[j]) / (d.length_squared() + 0.5))
				fi += push
				f[j] -= push
			f[i] = fi
		for e in range(0, _edges.size(), 2):
			var a := _edges[e]
			var b := _edges[e + 1]
			var dv := p[b] - p[a]
			var ln := dv.length() + 1e-6
			var pull := dv / ln * _edge_k[e >> 1] * (ln - rest)
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


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z) if flat else v
