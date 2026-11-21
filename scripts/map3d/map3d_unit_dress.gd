class_name Map3DUnitDress
extends RefCounted
## Each map figure's tunic in its realm's colour (spec 2026-11-21-infantry-melee-scrum-design,
## step 1: the sides of a mixed fight told apart at a glance). A figure mesh of an arm listed in
## GameArt.UNIT_REALM_TINT takes that table's overlay material (it paints the model's tunic mask
## over the scene's own material, which the WAR ROOM's tin and ink keep reading) and the realm's
## colour as its `realm_tint` instance parameter. An arm with no entry keeps its own colours.


## The standard bearer (Map3DUnitStandard, as the layer always placed it), then the tunics.
static func sync(repo: DataRepository, piece: Dictionary, reg: Dictionary, realm_flags: ArtTable,
		national_standard: PackedScene) -> void:
	var code := String(reg.get("kingdom_code", ""))
	Map3DUnitStandard.sync(piece, Map3DNationalFlag.texture_for(repo, realm_flags, code), national_standard)
	dress(repo, piece, code, GameArt.table(GameArt.UNIT_REALM_TINT))


## The realm's map colour as cloth: its hue at saturation `sat`, and the value whose linear
## relative luminance is `lum` — every realm's tunic equally light and equally strong, told apart by
## hue alone (an HSV value left a sky-blue tunic far lighter than a coral one, and the palette's
## more vivid blue louder than its red).
static func tint(base: Color, sat: float, lum: float) -> Color:
	var s := sat
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
	var colour := tint_of(repo, kingdom_code)
	var fresh: bool = piece.get("tint") != colour
	piece["tint"] = colour
	for fig: Node in _figures(piece):
		for m: MeshInstance3D in _bodies(fig):
			if fresh or m.material_overlay != mat:
				m.material_overlay = mat
				m.set_instance_shader_parameter("realm_tint", colour)


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
