class_name Map3DCommanderFigure
extends RefCounted
## The mounted commander's model (scenes/models/units/commander.tscn; spec
## 2026-11-27-commander-figure-design): one mesh of two surfaces, the body, horse and
## staff on the atlas and the banner's CLOTH, which carries its realm's flag.

const SCENE := "res://scenes/models/units/commander.tscn"
const CLOTH := "banner_cloth"  ## the cloth surface's material name in the .glb
const _BARE := &"commander_bare_cloth"  ## the scene's own cloth material, kept on the mesh

static var _cloths: Dictionary = {}  ## [scene cloth material, flag] -> that cloth with the flag on it


## The index of the cloth surface on `mesh`, -1 when it has none.
static func cloth_surface(mesh: MeshInstance3D) -> int:
	for i in mesh.mesh.get_surface_count():
		var mat := mesh.mesh.surface_get_material(i)
		if mat != null and mat.resource_name == CLOTH:
			return i
	return -1


## Puts `flag` (a realm's, Map3DNationalFlag.texture_for) on the banner of `figure`, an
## instance of the scene; null leaves the scene's bare cloth (a realm with no flag art).
## Every commander of one realm shares one material.
static func set_flag(figure: Node, flag: Texture2D) -> void:
	for mesh: MeshInstance3D in Map3DUnits.meshes(figure):
		var i := cloth_surface(mesh)
		if i < 0:
			continue
		if not mesh.has_meta(_BARE):
			mesh.set_meta(_BARE, mesh.get_surface_override_material(i))
		var bare := mesh.get_meta(_BARE) as BaseMaterial3D
		var key := [bare, flag]
		if flag != null and not _cloths.has(key):
			var dyed := bare.duplicate() as BaseMaterial3D
			dyed.albedo_color = Color.WHITE  # the flag's own colours
			dyed.albedo_texture = flag
			_cloths[key] = dyed
		mesh.set_surface_override_material(i, _cloths[key] if flag != null else bare)
