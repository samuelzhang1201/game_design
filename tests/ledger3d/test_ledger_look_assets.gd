# tests/ledger3d/test_ledger_look_assets.gd
extends GutTest
## The galaxy's look assets hold a shader and nothing else: every number is
## data (CLAUDE.md, the map's practice). The one exception is a texture: the
## generated art (owner 2026-10-10) is a look, so its sampler is the .tres's,
## never a res:// path in a CSV.

const MATERIALS := {
	"res://scenes/ledger/materials/sky.tres": "res://scenes/ledger/sky.gdshader",
	"res://scenes/ledger/materials/star.tres": "res://scenes/ledger/star.gdshader",
	"res://scenes/ledger/materials/star_faint.tres": "res://scenes/ledger/star_faint.gdshader",
	"res://scenes/ledger/materials/haze.tres": "res://scenes/ledger/haze.gdshader",
	"res://scenes/ledger/materials/link.tres": "res://scenes/ledger/link.gdshader",
	"res://scenes/ledger/materials/spark.tres": "res://scenes/ledger/spark.gdshader",
}
## The textures a material holds: its only saved values.
const TEXTURES := {
	"res://scenes/ledger/materials/star.tres": ["matcap"],
	"res://scenes/ledger/materials/star_faint.tres": ["matcap"],
	"res://scenes/ledger/materials/link.tres": ["strand"],
}


func test_each_material_is_its_shader_and_nothing_else() -> void:
	for path: String in MATERIALS:
		var m := load(path) as ShaderMaterial
		assert_not_null(m, path)
		assert_eq(m.shader.resource_path, MATERIALS[path], path)
		var saved: Array = []
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("shader_parameter/"):
				saved.append(line.get_slice(" ", 0).trim_prefix("shader_parameter/"))
		assert_eq(saved, TEXTURES.get(path, []), "only textures saved in " + path)
		for key: String in TEXTURES.get(path, []):
			assert_true(m.get_shader_parameter(key) is Texture2D, "%s holds its %s" % [path, key])


## Final review minors: the dimmed stars draw after the links, whatever the
## camera (a blended order sorted by distance flipped as it turned), so a
## dimmed star covers its own links' ends as a whole star does.
func test_the_dimmed_stars_draw_over_the_links() -> void:
	var link := load("res://scenes/ledger/materials/link.tres") as ShaderMaterial
	var faint := load("res://scenes/ledger/materials/star_faint.tres") as ShaderMaterial
	assert_gt(faint.render_priority, link.render_priority)


## The current round the stars (owner 2026-10-01) is added to what is behind
## it after the dimmed stars and the links, whatever the camera.
func test_the_current_draws_over_the_dimmed_stars_and_the_links() -> void:
	var spark := load("res://scenes/ledger/materials/spark.tres") as ShaderMaterial
	var faint := load("res://scenes/ledger/materials/star_faint.tres") as ShaderMaterial
	assert_gt(spark.render_priority, faint.render_priority)
