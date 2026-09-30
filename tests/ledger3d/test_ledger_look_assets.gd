# tests/ledger3d/test_ledger_look_assets.gd
extends GutTest
## The galaxy's look assets hold a shader and nothing else: every number is
## data (CLAUDE.md, the map's practice).

const MATERIALS := {
	"res://scenes/ledger/materials/sky.tres": "res://scenes/ledger/sky.gdshader",
	"res://scenes/ledger/materials/star.tres": "res://scenes/ledger/star.gdshader",
	"res://scenes/ledger/materials/haze.tres": "res://scenes/ledger/haze.gdshader",
	"res://scenes/ledger/materials/link.tres": "res://scenes/ledger/link.gdshader",
}


func test_each_material_is_its_shader_and_nothing_else() -> void:
	for path: String in MATERIALS:
		var m := load(path) as ShaderMaterial
		assert_not_null(m, path)
		assert_eq(m.shader.resource_path, MATERIALS[path], path)
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("shader_parameter/"), "no value saved in " + path)
