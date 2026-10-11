class_name Map3DHouseApron
extends RefCounted
## The skirt round a house's foot (owner 2026-10-12: 房子直接平放在地上，像贴上去的):
## a packed-dirt apron round a countryside house, a brick paving round a town's
## or city's, one flat quad per house in one MultiMesh per kind. Pure and static;
## Map3DLayerHouses draws them. Every number is in data/map3d_aprons.csv; which
## kind a settlement gets is `map3d_settlements.apron`, which types wear one
## `map3d_houses.apron`. Never reaches for the Game autoload.

const BUFFER_STRIDE := 12  # a 3x4 transform, no custom data


## The apron kind of a burg group ("dirt" / "brick"), "" when the group has none.
static func kind_of(group: String, repo: DataRepository) -> String:
	var row: Dictionary = repo.map3d_settlements.get(group, {})
	return String(row.get("apron", ""))


## Whether a house type wears an apron.
static func wears(type: String, repo: DataRepository) -> bool:
	return String(repo.map3d_houses.get(type, {}).get("apron", "0")) == "1"


## The apron's world transform for house `h` seated at height `seat_y`: the
## quad (a unit PlaneMesh) scaled to the mesh's own footprint (`box`, its AABB,
## times the house's scale and stretch) plus `margin_m` on every side, turned
## with the house, centred on the box's centre, `lift_m` above the seat.
static func transform_of(h: Dictionary, box: AABB, seat_y: float, margin_m: float, lift_m: float) -> Transform3D:
	var at: Vector2 = h["at"]
	var s := float(h["scale"])
	var st := s * float(h.get("stretch", 1.0))
	var turn := Basis(Vector3.UP, deg_to_rad(float(h["yaw_deg"])))
	var c := box.get_center()
	var o: Vector3 = turn * Vector3(c.x * st, 0.0, c.z * s)
	var sx := box.size.x * st + 2.0 * margin_m
	var sz := box.size.z * s + 2.0 * margin_m
	return Transform3D(turn * Basis.from_scale(Vector3(sx, 1.0, sz)), Vector3(at.x + o.x, seat_y + lift_m, at.y + o.z))


## `rows` (one settlement's houses, the layer's `seat_fn` giving each its
## Vector2(lowest, seat)) packed for the kind's MultiMesh: {buf, xf}.
static func pack(rows: Array, boxes: Dictionary, seat_fn: Callable, margin_m: float, lift_m: float,
		repo: DataRepository) -> Dictionary:
	var xf: Array[Transform3D] = []
	var buf := PackedFloat32Array()
	for h: Dictionary in rows:
		var type := String(h["type"])
		if not wears(type, repo) or not boxes.has(type):
			continue
		var t := transform_of(h, boxes[type], (seat_fn.call(h, type) as Vector2).y, margin_m, lift_m)
		xf.append(t)
		var o := buf.size()
		buf.resize(o + BUFFER_STRIDE)
		for r in 3:
			buf[o + r * 4] = t.basis.x[r]
			buf[o + r * 4 + 1] = t.basis.y[r]
			buf[o + r * 4 + 2] = t.basis.z[r]
			buf[o + r * 4 + 3] = t.origin[r]
	return {"buf": buf, "xf": xf}


## The material of a kind from its table row: house_apron.gdshader with the
## row's colours and sizes (a look value in the CSV; the shader is the look).
static func material_of(row: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/map3d/house_apron.gdshader")
	m.set_shader_parameter("color_a", Color(String(row["color"])))
	m.set_shader_parameter("color_b", Color(String(row["color_alt"])))
	m.set_shader_parameter("style", int(row["style"]))
	m.set_shader_parameter("fade_m", float(row["fade_m"]))
	m.set_shader_parameter("unit_m", float(row["unit_m"]))
	return m


## One kind's MultiMeshInstance3D: a unit up-facing quad, no shadows.
static func multimesh_instance(kind: String, row: Dictionary) -> MultiMeshInstance3D:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = material_of(row)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "apron_" + kind
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
