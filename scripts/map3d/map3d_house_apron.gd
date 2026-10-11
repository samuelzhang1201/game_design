class_name Map3DHouseApron
extends RefCounted
## The skirt round a house's foot (owner 2026-10-12: 房屋脚下加上一点点小小的过渡):
## packed dirt round a countryside house, brick paving round a town's or a
## city's. GEOMETRY only, pure and static: the apron's corners from the mesh's
## footprint, and a grid draped on the ground under them; Map3DLayerAprons
## merges them per settlement and draws them in its authored materials. Every
## number is in data/screens/map3d/map3d_aprons.csv; which kind a settlement gets
## is `map3d_settlements.apron`, which types wear one `map3d_houses.apron`.
## Never reaches for the Game autoload.


## The apron kind of a burg group ("dirt" / "brick"), "" when the group has none.
static func kind_of(group: String, repo: DataRepository) -> String:
	var row: Dictionary = repo.map3d_settlements.get(group, {})
	return String(row.get("apron", ""))


## Whether a house type wears an apron.
static func wears(type: String, repo: DataRepository) -> bool:
	return String(repo.map3d_houses.get(type, {}).get("apron", "0")) == "1"


## The apron's four world-XZ corners for house `h` — the mesh's own footprint
## (`box`, its AABB, times the house's scale and stretch) plus `margin_m` on
## every side, turned with the house: (-x,-z), (+x,-z), (+x,+z), (-x,+z).
static func corners(h: Dictionary, box: AABB, margin_m: float) -> PackedVector2Array:
	var at: Vector2 = h["at"]
	var s := float(h["scale"])
	var st := s * float(h.get("stretch", 1.0))
	var turn := Basis(Vector3.UP, deg_to_rad(float(h["yaw_deg"])))
	var lo := Vector2(box.position.x * st - margin_m, box.position.z * s - margin_m)
	var hi := Vector2(box.end.x * st + margin_m, box.end.z * s + margin_m)
	var out := PackedVector2Array()
	for p: Vector2 in [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]:
		var w: Vector3 = turn * Vector3(p.x, 0.0, p.y)
		out.append(Vector2(at.x + w.x, at.y + w.z))
	return out


## Empty arrays for drape() to append to.
static func new_arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
		"uv2": PackedVector2Array(), "i": PackedInt32Array()}


## One apron appended to `a`: `n` x `n` cells over the quad `c` (corners()),
## each of its (n+1)^2 vertices ON the ground (`height_fn` of its XZ; the lift
## is the shader's, in screen px, as the roads'), its normal from its grid
## neighbours; UV runs 0..1 across the apron, UV2 is its size in metres (the
## shader fades the edge by it).
static func drape(a: Dictionary, c: PackedVector2Array, n: int, height_fn: Callable) -> void:
	n = maxi(n, 1)
	var base: int = (a["v"] as PackedVector3Array).size()
	var du := c[1] - c[0]
	var dv := c[3] - c[0]
	var size := Vector2(du.length(), dv.length())
	var pts: Array[Vector3] = []
	for j in n + 1:
		for i in n + 1:
			var xz := c[0] + du * (float(i) / n) + dv * (float(j) / n)
			pts.append(Vector3(xz.x, float(height_fn.call(xz)), xz.y))
	for j in n + 1:
		for i in n + 1:
			var along: Vector3 = pts[j * (n + 1) + mini(i + 1, n)] - pts[j * (n + 1) + maxi(i - 1, 0)]
			var across: Vector3 = pts[mini(j + 1, n) * (n + 1) + i] - pts[maxi(j - 1, 0) * (n + 1) + i]
			var up := across.cross(along).normalized()
			a["v"].append(pts[j * (n + 1) + i])
			a["n"].append(up if up.y >= 0.0 else -up)
			a["uv"].append(Vector2(float(i) / n, float(j) / n))
			a["uv2"].append(size)
	for j in n:
		for i in n:
			var k := base + j * (n + 1) + i
			a["i"].append_array(PackedInt32Array([k, k + 1, k + n + 1, k + 1, k + n + 2, k + n + 1]))


## `a` as ArrayMesh surface arrays.
static func arrays_of(a: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a["v"]
	arrays[Mesh.ARRAY_NORMAL] = a["n"]
	arrays[Mesh.ARRAY_TEX_UV] = a["uv"]
	arrays[Mesh.ARRAY_TEX_UV2] = a["uv2"]
	arrays[Mesh.ARRAY_INDEX] = a["i"]
	return arrays
