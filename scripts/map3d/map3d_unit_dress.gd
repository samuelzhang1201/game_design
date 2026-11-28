class_name Map3DUnitDress
extends RefCounted
## Each map figure's tunic in its realm's colour (spec 2026-11-21-infantry-melee-scrum-design,
## step 1: the sides of a mixed fight told apart at a glance). A figure mesh of an arm listed in
## GameArt.UNIT_REALM_TINT takes that table's overlay material (it paints the model's tunic mask
## over the scene's own material, which the WAR ROOM's tin and ink keep reading) and the realm's
## colour as its `realm_tint` instance parameter. An arm with no entry keeps its own colours; a mesh
## not drawn from the overlay's `albedo_atlas` (a prop on its own texture) is left bare.


## The tunics, and the unit's mounted commander under his realm's banner (Map3DCommanderRider).
## No SOLDIER carries a standard (owner 2026-11-23: every soldier of a unit alike); the standard's
## scene stays an argument because the royal-pinned Units layer still passes it.
static func sync(repo: DataRepository, piece: Dictionary, reg: Dictionary, realm_flags: ArtTable,
		_national_standard: PackedScene) -> void:
	dress(repo, piece, String(reg.get("kingdom_code", "")), GameArt.table(GameArt.UNIT_REALM_TINT))
	Map3DCommanderRider.sync(repo, piece, reg, realm_flags)


## The realm's map colour as cloth: its hue at saturation `sat`, and the value whose linear
## relative luminance is `lum` — every realm's tunic equally light and equally strong, told apart by
## hue alone (an HSV value left a sky-blue tunic far lighter than a coral one, and the palette's
## more vivid blue louder than its red).
static func tint(base: Color, sat: float, lum: float) -> Color:
	var s := sat if base.s > 0.01 else 0.0  # a grey (MapPalette.FALLBACK) has no hue to tint
	var lo := 0.0
	var hi := 1.0
	for i in 30:
		var mid := (lo + hi) * 0.5
		if luminance(Color.from_hsv(base.h, s, mid)) < lum:
			lo = mid
		else:
			hi = mid
	return Color.from_hsv(base.h, s, (lo + hi) * 0.5)


## Linear relative luminance (Rec. 709) of an sRGB colour.
static func luminance(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


static func tint_of(repo: DataRepository, kingdom_code: String) -> Color:
	return tint(MapPalette.color_of(repo, kingdom_code), float(repo.bal("map3d_unit_tint_sat")),
		float(repo.bal("map3d_unit_tint_lum")))


## Every figure mesh of `piece` (a physical-groups piece's too, groups placed later included)
## wears `table`'s material for the piece's model and the realm's tint; set only where it differs.
static func dress(repo: DataRepository, piece: Dictionary, kingdom_code: String, table: ArtTable) -> void:
	var mat := table.of(String(piece.get("model", ""))) as Material if table != null else null
	if mat == null:
		return
	var atlas: Texture2D = (mat as ShaderMaterial).get_shader_parameter("albedo_atlas") if mat is ShaderMaterial else null
	var colour := tint_of(repo, kingdom_code)
	var fresh: bool = piece.get("tint") != colour
	piece["tint"] = colour
	for fig: Node in _figures(piece):
		for m: MeshInstance3D in _bodies(fig):
			if not _on_atlas(m, atlas):
				continue  # a carried prop on its own texture (the archer's bow, quiver, arrow)
			if fresh or m.material_overlay != mat:
				m.material_overlay = mat
				m.set_instance_shader_parameter("realm_tint", colour)


## Whether mesh `m` is drawn from `atlas`, the one its overlay's mask is painted on (no atlas: any mesh).
static func _on_atlas(m: MeshInstance3D, atlas: Texture2D) -> bool:
	if atlas == null or m.mesh == null or m.mesh.get_surface_count() == 0:
		return atlas == null
	var own := m.get_active_material(0) as BaseMaterial3D
	return own == null or own.albedo_texture == atlas


static func _figures(piece: Dictionary) -> Array:
	if piece.get("layout", "") != "physical_groups":
		return piece.get("figs", [])
	var out: Array = []
	for group: Dictionary in piece.get("groups", []):
		out.append_array(_figures(group["piece"]))
	return out


## A figure's meshes, not its carried standard's.
static func _bodies(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		if not c is Map3DNationalFlag:
			out.append_array(_bodies(c))
	return out
