class_name WarTable
extends RefCounted
## The plotting table's maths (owner 2026-10-01, spec 2026-10-01-war-room-design
## §2): a sheet laid war_table_w_m wide, centred on the table's origin, x east
## and z south as the pack's own y; the relief from the pack's height field in
## REAL metres, raised by war_relief_exaggeration over the table's true scale.
## Pure but for build_mesh, which only makes an ArrayMesh.


static func depth_m(sheet_rect: Rect2, table_w: float) -> float:
	return table_w * sheet_rect.size.y / sheet_rect.size.x


## Table (x, z) metres of a pack px, the table's centre at 0.
static func to_table(sheet_rect: Rect2, table_w: float, px: Vector2) -> Vector2:
	var s := table_w / sheet_rect.size.x
	return (px - sheet_rect.position) * s - Vector2(table_w, depth_m(sheet_rect, table_w)) * 0.5


static func from_table(sheet_rect: Rect2, table_w: float, xz: Vector2) -> Vector2:
	var s := table_w / sheet_rect.size.x
	return (xz + Vector2(table_w, depth_m(sheet_rect, table_w)) * 0.5) / s + sheet_rect.position


## Metres above the waterline of one L8 relief value (0..255).
static func metres_of_relief(repo: DataRepository, value_0_255: float) -> float:
	var units := value_0_255 * 100.0 / 255.0
	return maxf(0.0, (units - repo.bal("elevation_sea_level")) * repo.bal("elevation_m_per_unit"))


## Real metres per vertex over the sheet, row-major (z outer).
static func heights(repo: DataRepository, relief: Image, sheet_rect: Rect2, nx: int, nz: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	var scale := maxf(repo.bal("map_relief_scale"), 1.0)
	var w := relief.get_width()
	var h := relief.get_height()
	for j in nz:
		for i in nx:
			var px := sheet_rect.position + sheet_rect.size * Vector2(float(i) / float(nx - 1), float(j) / float(nz - 1))
			var x := clampi(int(px.x / scale), 0, w - 1)
			var y := clampi(int(px.y / scale), 0, h - 1)
			out[j * nx + i] = metres_of_relief(repo, relief.get_pixel(x, y).r * 255.0)
	return out


## Table metres up for `metres` of real height: the table's true scale times
## war_relief_exaggeration.
static func table_y(repo: DataRepository, sheet_rect: Rect2, table_w: float, metres: float) -> float:
	var metres_per_px := float(ArmySystem.metres_per_pack_px(repo))
	return metres / metres_per_px * (table_w / sheet_rect.size.x) * repo.bal("war_relief_exaggeration")


## Bilinear real metres at a table (x, z).
static func height_at(heights_m: PackedFloat32Array, nx: int, nz: int, table_w: float, depth: float,
		xz: Vector2) -> float:
	var u := clampf((xz.x / table_w + 0.5) * float(nx - 1), 0.0, float(nx - 1))
	var v := clampf((xz.y / depth + 0.5) * float(nz - 1), 0.0, float(nz - 1))
	var i0 := mini(int(u), nx - 2)
	var j0 := mini(int(v), nz - 2)
	var fu := u - float(i0)
	var fv := v - float(j0)
	var a := lerpf(heights_m[j0 * nx + i0], heights_m[j0 * nx + i0 + 1], fu)
	var b := lerpf(heights_m[(j0 + 1) * nx + i0], heights_m[(j0 + 1) * nx + i0 + 1], fu)
	return lerpf(a, b, fv)


## Where a ray meets the relief: the flat table first, then refined against
## y_at(Vector2 xz) -> table y. Vector3.INF when the ray does not point down.
static func ray_hit(origin: Vector3, dir: Vector3, y_at: Callable) -> Vector3:
	if dir.y >= -0.000001:
		return Vector3.INF
	var y := 0.0
	var p := origin
	for _i in 4:
		var t := (y - origin.y) / dir.y
		p = origin + dir * t
		y = float(y_at.call(Vector2(p.x, p.z)))
	return Vector3(p.x, y, p.z)


## The relief as one mesh in vertex order row-major (z outer): UV = the sheet
## 0..1, UV2.x = the vertex's real metres, y = metres × y_scale. Normals come
## from the grid's own gradient so the vertex order stays the contract.
static func build_mesh(heights_m: PackedFloat32Array, nx: int, nz: int, table_w: float, depth: float,
		y_scale: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var dx := table_w / float(nx - 1)
	var dz := depth / float(nz - 1)
	for j in nz:
		for i in nx:
			var u := float(i) / float(nx - 1)
			var v := float(j) / float(nz - 1)
			var m := heights_m[j * nx + i]
			verts.append(Vector3((u - 0.5) * table_w, m * y_scale, (v - 0.5) * depth))
			uvs.append(Vector2(u, v))
			uv2s.append(Vector2(m, 0.0))
			var west := heights_m[j * nx + maxi(i - 1, 0)]
			var east := heights_m[j * nx + mini(i + 1, nx - 1)]
			var north := heights_m[maxi(j - 1, 0) * nx + i]
			var south := heights_m[mini(j + 1, nz - 1) * nx + i]
			var sx := (east - west) * y_scale / (dx * float(mini(i + 1, nx - 1) - maxi(i - 1, 0)))
			var sz := (south - north) * y_scale / (dz * float(mini(j + 1, nz - 1) - maxi(j - 1, 0)))
			normals.append(Vector3(-sx, 1.0, -sz).normalized())
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
