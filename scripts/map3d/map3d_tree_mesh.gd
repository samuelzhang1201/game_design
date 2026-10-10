class_name Map3DTreeMesh
extends RefCounted
## The 3D map's tree CLUMPS (look route 2026-09-30), built from numbers alone:
## a clump is a few crowns — rounded, lumpy broadleaf crowns or two-tier
## conifers — on short trunks, coloured by vertex (dark under the crown, lit
## on top) so it reads at 5-15 px as silhouette and colour, the way the
## houses do (taste: at a 10 px draw size what reads is silhouette and
## colour). LOD 0 is the near clump; LOD 1 the same crowns as octahedra and
## pyramids for the middle distance. Deterministic: a (kind, variant) pair is
## always the same mesh. Pure: no scene, no autoload.

const BROADLEAF := 0
const CONIFER := 1
const LONE := 2

## sRGB crown colours by kind: [dark, light]; the vertex colour runs from the
## first under the crown to the second on its crown.
const COLOURS := {
	BROADLEAF: [Color("#142110"), Color("#36502a")],
	CONIFER: [Color("#111e14"), Color("#304c30")],
	LONE: [Color("#18260f"), Color("#46602a")],
}
const TRUNK := Color("#4a3a2a")


## The clump for `kind` at `lod` (0 near, 1 middle), variant `variant`.
static func clump(kind: int, lod: int, variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (kind + 1) + 104729 * (variant + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 3 if kind == LONE else (8 if kind == CONIFER else 8)
	var spread := 7.0 if kind == LONE else 15.0
	var placed: Array[Vector2] = []
	for i in count:
		var at := Vector2.ZERO
		for _t in 12:   # keep the crowns from standing inside one another
			at = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spread
			var clear := true
			for p in placed:
				if p.distance_to(at) < 6.5:
					clear = false
			if clear:
				break
		placed.append(at)
		var tone := rng.randf_range(-0.08, 0.08)
		if kind == CONIFER:
			var h := rng.randf_range(22.0, 32.0)
			var r := rng.randf_range(5.8, 7.6)
			_conifer(st, Vector3(at.x, 0, at.y), h, r, lod, tone, rng)
		else:
			var r := rng.randf_range(4.2, 7.4)
			var trunk := rng.randf_range(4.0, 7.0)
			_broadleaf(st, Vector3(at.x, 0, at.y), trunk, r, lod, tone, kind, rng)
	return st.commit()


static func _shade(kind: int, t: float, tone: float) -> Color:
	var c: Array = COLOURS[kind]
	var col := (c[0] as Color).lerp(c[1], clampf(t, 0.0, 1.0))
	return Color(col.r * (1.0 + tone), col.g * (1.0 + tone * 0.6), col.b * (1.0 + tone * 0.3))


static func _broadleaf(st: SurfaceTool, base: Vector3, trunk: float, r: float, lod: int,
		tone: float, kind: int, rng: RandomNumberGenerator) -> void:
	if lod == 0:
		_trunk(st, base, trunk + r * 0.3, r * 0.14)
	var centre := base + Vector3(0, trunk + r * 0.75, 0)
	var verts: Array[Vector3] = _icosphere(1 if lod == 0 else 0)
	var lump := []
	for v in verts.size():
		lump.append(1.0 + rng.randf_range(-0.24, 0.24))
	var squash := Vector3(r * rng.randf_range(0.85, 1.15), r * rng.randf_range(0.7, 0.9), r * rng.randf_range(0.85, 1.15))
	var tris: Array = _ico_faces(1 if lod == 0 else 0)
	for f in tris:
		for k in 3:
			var i: int = f[k]
			var d: Vector3 = verts[i]
			var p := centre + d * squash * float(lump[i])
			st.set_normal((d * Vector3(1.0, 1.25, 1.0)).normalized())
			st.set_color(_shade(kind, 0.5 + d.y * 0.55, tone))
			st.add_vertex(p)


static func _conifer(st: SurfaceTool, base: Vector3, h: float, r: float, lod: int, tone: float,
		_rng: RandomNumberGenerator) -> void:
	if lod == 0:
		_trunk(st, base, h * 0.3, r * 0.12)
	var sides := 7 if lod == 0 else 4
	var tiers := [[0.18, 0.62, 1.0], [0.48, 1.0, 0.72]] if lod == 0 else [[0.18, 1.0, 1.0]]
	for tier in tiers:
		var y0: float = h * float(tier[0])
		var y1: float = h * float(tier[1])
		var rr: float = r * float(tier[2])
		var apex := base + Vector3(0, y1, 0)
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var p0 := base + Vector3(cos(a0) * rr, y0, sin(a0) * rr)
			var p1 := base + Vector3(cos(a1) * rr, y0, sin(a1) * rr)
			var n0 := Vector3(cos(a0), rr / (y1 - y0), sin(a0)).normalized()
			var n1 := Vector3(cos(a1), rr / (y1 - y0), sin(a1)).normalized()
			var na := Vector3(0, 1, 0)
			st.set_normal(na)
			st.set_color(_shade(CONIFER, 1.0, tone))
			st.add_vertex(apex)
			st.set_normal(n1)
			st.set_color(_shade(CONIFER, 0.15, tone))
			st.add_vertex(p1)
			st.set_normal(n0)
			st.set_color(_shade(CONIFER, 0.15, tone))
			st.add_vertex(p0)


static func _trunk(st: SurfaceTool, base: Vector3, h: float, w: float) -> void:
	var b := base - Vector3(0, 3.0, 0)   # sunk: a coarse ground LOD never shows its foot
	for s in 4:
		var a0 := TAU * s / 4.0
		var a1 := TAU * (s + 1) / 4.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n := (d0 + d1).normalized()
		var q := [b + d0 * w, b + d1 * w, b + d1 * w * 0.6 + Vector3(0, h + 3.0, 0), b + d0 * w * 0.6 + Vector3(0, h + 3.0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_color(TRUNK)
			st.add_vertex(q[idx])


static func _icosphere(subdiv: int) -> Array[Vector3]:
	return _ico(subdiv)[0]


static func _ico_faces(subdiv: int) -> Array:
	return _ico(subdiv)[1]


static func _ico(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = []
	for p in [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t],
			[0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]:
		v.append(Vector3(p[0], p[1], p[2]).normalized())
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for _s in subdiv:
		var mid := {}
		var nf := []
		for tri in f:
			var m := []
			for k in 3:
				var a: int = tri[k]
				var b: int = tri[(k + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mid.has(key):
					v.append(((v[a] + v[b]) * 0.5).normalized())
					mid[key] = v.size() - 1
				m.append(mid[key])
			nf.append([tri[0], m[0], m[2]])
			nf.append([tri[1], m[1], m[0]])
			nf.append([tri[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		f = nf
	# SurfaceTool's front face is clockwise: turn every face over
	var out := []
	for tri in f:
		out.append([tri[0], tri[2], tri[1]])
	return [v, out]


## The same clump as PHOTO CARDS (owner 2026-10-01: below a 20 km scale the
## 3D crowns read fake): one camera-facing card per crown, drawn by
## tree_card.gdshader from the crown atlas. Every corner of a card sits at its
## crown's centre; CUSTOM0 carries (corner x, corner y, half size m, atlas
## cell), the cell drawn by the crown's own rng from `cells` (the atlas cells
## of this kind, data/map3d_tree_crowns.csv). Two triangles a tree. `count`,
## `spread` and `size` override the kind's own (a species row's crowns,
## spread_m and size: species_cards).
static func cards(kind: int, variant: int, cells: PackedInt32Array, count := -1,
		spread := -1.0, size := 1.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (kind + 1) + 104729 * (variant + 1) + 31
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	if count < 0:
		count = 3 if kind == LONE else 8
	if spread < 0.0:
		spread = 7.0 if kind == LONE else 15.0
	var placed: Array[Vector2] = []
	var reach := 0.0
	for i in count:
		var at := Vector2.ZERO
		for _t in 12:   # in a disc, kept apart: a clump is trees side by side
			at = Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * spread
			var clear := true
			for p in placed:
				if p.distance_to(at) < 6.5 * size:
					clear = false
			if clear:
				break
		placed.append(at)
		var half: float
		var centre: Vector3
		if kind == CONIFER:
			var h := rng.randf_range(22.0, 32.0) * size
			half = h * 0.55
			centre = Vector3(at.x, h * 0.5, at.y)
		else:
			var r := rng.randf_range(4.2, 7.4) * size
			var trunk := rng.randf_range(4.0, 7.0) * size
			half = (trunk + 2.0 * r) * 0.62
			centre = Vector3(at.x, (trunk + 2.0 * r) * 0.5, at.y)
		var cell := cells[rng.randi() % cells.size()] if not cells.is_empty() else 0
		reach = maxf(reach, at.length() + half * 1.5)
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for idx in [0, 2, 1, 0, 3, 2]:
			var cn: Vector2 = corners[idx]
			st.set_custom(0, Color(cn.x, cn.y, half, float(cell)))
			st.set_normal(Vector3.UP)
			st.set_color(Color.WHITE)
			st.add_vertex(centre)
	var mesh := st.commit()
	# every vertex sits at its crown's centre: the box must hold the cards
	mesh.custom_aabb = AABB(Vector3(-reach, -4.0, -reach), Vector3(reach * 2.0, 40.0 + reach, reach * 2.0))
	return mesh


## A species' clump (data/map3d_tree_species.csv row, owner 2026-10-10: 树木
## 的品种过于单一): its form, atlas cells, crowns, spread and size; variant
## `variant` of it, seeded by the species' kind so no two species share a layout.
static func species_cards(row: Dictionary, variant: int) -> ArrayMesh:
	var cells := PackedInt32Array()
	for c: String in String(row["cells"]).split("|", false):
		cells.append(int(c))
	var form := CONIFER if String(row.get("form", "")) == "conifer" else BROADLEAF
	return cards(form, variant + 64 * int(row["kind"]), cells, int(row["crowns"]),
		float(row["spread_m"]), float(row["size"]))
