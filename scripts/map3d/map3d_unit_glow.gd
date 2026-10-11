class_name Map3DUnitGlow
extends RefCounted
## A selected regiment piece's glow (owner 2026-10-10: the selection is a faint
## glow under the piece, never a box or a number): a flat quad, child of the
## piece's formation node, lying on its SEAT under the figures — the node is
## tilted to the seat's plane, so the quad is too — depth-tested so the figures
## draw over it. Its look is `scenes/map3d/materials/unit_select_glow.tres`
## (+ `unit_select_glow.gdshader`); its size is balance map3d_unit_glow_ratio ×
## the formation's half EXTENT, an ellipse (a line of four is long and thin),
## so it stays inside the footprint the seat raised the piece clear of and
## never cuts into a slope. The band is narrow: `map3d_unit_glow_inner` to
## `map3d_unit_glow_peak`, set per piece as instance uniforms.

const MATERIAL := preload("res://scenes/map3d/materials/unit_select_glow.tres")
const NAME := "Glow"


## The piece's glow node, made on first use (no owner: never saved).
static func node_of(repo: DataRepository, piece: Dictionary) -> MeshInstance3D:
	var host: Node3D = piece["node"]
	var glow := host.get_node_or_null(NAME) as MeshInstance3D
	if glow != null:
		return glow
	var quad := PlaneMesh.new()  # lies in its XZ plane
	var half: Vector2 = piece["extent"] * repo.bal("map3d_unit_glow_ratio")
	quad.size = half * 2.0
	glow = MeshInstance3D.new()
	glow.name = NAME
	glow.mesh = quad
	glow.material_override = MATERIAL
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.set_instance_shader_parameter("inner", repo.bal("map3d_unit_glow_inner"))
	glow.set_instance_shader_parameter("peak", repo.bal("map3d_unit_glow_peak"))
	glow.visible = false
	host.add_child(glow)
	return glow


## Shown or hidden, and laid on the seat: `drop_m` is how far (world metres)
## the piece's origin stands above its seat, `k` its scale; the quad sits
## map3d_unit_glow_lift of the piece's height over the seat.
static func place(repo: DataRepository, piece: Dictionary, on: bool, drop_m: float, k: float) -> void:
	var host: Node3D = piece["node"]
	var glow := host.get_node_or_null(NAME) as MeshInstance3D
	if not on:
		if glow != null:
			glow.visible = false
		return
	glow = node_of(repo, piece)
	glow.position.y = -drop_m / maxf(k, 0.0001) + float(piece["height_m"]) * repo.bal("map3d_unit_glow_lift")
	glow.visible = true


## Whether the piece's glow shows (tests).
static func shown(piece: Dictionary) -> bool:
	var glow := (piece["node"] as Node3D).get_node_or_null(NAME) as Node3D
	return glow != null and glow.visible
