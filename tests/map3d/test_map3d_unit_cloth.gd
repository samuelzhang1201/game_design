extends GutTest
## Every land unit's dyed cloth wears its realm's colour on the 3D map
## (Map3DUnitCloth): the masked atlas surface is redrawn by unit_cloth.tres
## with the realm colour as its instance uniform; a surface with no mask
## (the archer's bow, quiver, arrow) keeps the scene's own material.


func _dress(model: String, color: Color) -> Node3D:
	var fig := (load("res://scenes/models/units/%s.tscn" % model) as PackedScene).instantiate() as Node3D
	add_child_autofree(fig)
	Map3DUnitCloth.sync({"node": fig}, color)
	return fig


func test_every_land_arm_has_a_dressed_cloth_surface() -> void:
	for model: String in ["infantry", "cavalry", "royal", "archers"]:
		var c := Color(0.8, 0.1, 0.2)
		var dressed := 0
		for m: MeshInstance3D in Map3DUnits.meshes(_dress(model, c)):
			for i in m.get_surface_override_material_count():
				var mat := m.get_active_material(i)
				if mat is ShaderMaterial and (mat as ShaderMaterial).shader == Map3DUnitCloth.TEMPLATE.shader:
					dressed += 1
					assert_eq(m.get_instance_shader_parameter("realm_color"), c, model + " wears the realm colour")
					assert_not_null((mat as ShaderMaterial).get_shader_parameter("cloth_tex"), model + " has its mask")
		assert_eq(dressed, 1, model + ": exactly its body atlas is dressed")


func test_redressing_keeps_one_shared_material_and_takes_the_new_colour() -> void:
	var fig := _dress("infantry", Color.RED)
	var first: Material = null
	for m: MeshInstance3D in Map3DUnits.meshes(fig):
		if m.get_surface_override_material_count() > 0 and m.get_active_material(0) is ShaderMaterial:
			first = m.get_active_material(0)
	Map3DUnitCloth.sync({"node": fig}, Color.BLUE)
	var other := _dress("infantry", Color.GREEN)
	for m: MeshInstance3D in Map3DUnits.meshes(fig) + Map3DUnits.meshes(other):
		if m.get_active_material(0) is ShaderMaterial:
			assert_same(m.get_active_material(0), first, "one cloth material per atlas, shared")
	for m: MeshInstance3D in Map3DUnits.meshes(fig):
		if m.get_active_material(0) is ShaderMaterial:
			assert_eq(m.get_instance_shader_parameter("realm_color"), Color.BLUE)
