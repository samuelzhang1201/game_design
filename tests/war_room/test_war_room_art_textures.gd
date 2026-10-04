extends GutTest
## The room's art loads from a fresh clone (assets/3D/war_room/README.md): every
## texture a war-room .glb extracts beside itself is a file in the checkout,
## imported as Basis Universal with mipmaps like the houses'.

const ART_DIR := "res://assets/3D/war_room/"


func _textures_of(node: Node, into: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for s: int in mesh.get_surface_count():
				var mat := mesh.surface_get_material(s) as BaseMaterial3D
				if mat == null:
					continue
				for p: int in BaseMaterial3D.TEXTURE_MAX:
					var tex := mat.get_texture(p)
					if tex != null and tex.resource_path != "" and not tex.resource_path.contains("::"):
						into[tex.resource_path] = true
	for child: Node in node.get_children():
		_textures_of(child, into)


func test_every_extracted_texture_is_in_the_checkout_as_basis_universal() -> void:
	var seen := {}
	for object: String in DirAccess.get_directories_at(ART_DIR):
		var glb := ART_DIR + object + "/" + object + ".glb"
		if not ResourceLoader.exists(glb):
			continue
		var scene := load(glb) as PackedScene
		assert_not_null(scene, glb + " loads")
		if scene == null:
			continue
		var root := scene.instantiate()
		_textures_of(root, seen)
		root.free()
	assert_true(seen.has(ART_DIR + "pennant/pennant_pennant_atlas.png"),
		"the pennant's atlas is extracted beside its .glb: " + str(seen.keys()))
	for path: String in seen:
		assert_true(FileAccess.file_exists(path), path + " is in the checkout")
		var cf := ConfigFile.new()
		assert_eq(cf.load(path + ".import"), OK, path + " has its .import")
		assert_eq(int(cf.get_value("params", "compress/mode", -1)), 4,
			path + " is Basis Universal, GPU-compressed like the houses' textures")
		assert_true(bool(cf.get_value("params", "mipmaps/generate", false)), path + " has mipmaps")
