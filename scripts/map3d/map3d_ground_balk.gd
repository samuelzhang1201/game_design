class_name Map3DGroundBalk
extends RefCounted
## The fields' BALKS and hedges as lines (visual review 2026-10-05: field edges
## read jagged, like a mask). Terrain3D can only change a texture from vertex
## to vertex, so a field's rim steps every 20 m; tools/map3d/bake_world.py
## writes each field's distance to its own edge at the vertices
## (bake/field_edges.png), and this stage draws a line along it — bilinearly
## sampled, so the line runs smooth through the steps and hides them: a pale
## grass balk between furlongs, a darker hedge round a croft. It reads the
## ground's edge-warped position, so the line follows the drawn rim
## (Map3DGroundEdge). The ground look's `balk_*` (0 off).

const UNIFORMS := """
// Map3DGroundBalk: bake/field_edges.png, one byte per vertex, the metres to a field's edge.
uniform highp sampler2D field_edges : filter_linear, repeat_disable;
uniform float balk = 0.0;
uniform float balk_m = 6.0;
uniform float balk_per_m = 4.0;
uniform float balk_vertex_m = 20.0;
uniform vec4 balk_color : source_color = vec4(0.42, 0.45, 0.24, 1.0);
uniform float balk_far_m = 9000.0;
"""

const STAGE := """	if (balk > 0.0) {
		vec2 bxz = v_vertex.xz + (uv - UV) * _vertex_spacing;  // where the ground was looked up
		vec2 buv = ((bxz - pack_origin) / balk_vertex_m + 0.5) / vec2(textureSize(field_edges, 0));
		float bd = texture(field_edges, buv).r * 255.0 / balk_per_m;
		float baa = max(fwidth(bd), 0.5);
		float bk = (1.0 - smoothstep(balk_m - baa, balk_m + baa, bd)) * step(bd, 60.0)
			* (1.0 - smoothstep(balk_far_m * 0.5, balk_far_m, length(v_vertex - _camera_pos)));
		base_albedo = mix(base_albedo, balk_color.rgb, bk * balk);
	}
"""


## Hand the ground `mat` the build's edge map and the look's balks; off
## without the file.
static func apply(mat: Object, scene_path: String, look: Map3DGroundLook) -> void:
	var path := Map3DWorldLoader.data_dir(scene_path).path_join("bake/field_edges.png")  # res://, as woods.png
	var img: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null or look.balk <= 0.0:
		mat.call("set_shader_param", "balk", 0.0)
		return
	mat.call("set_shader_param", "field_edges", ImageTexture.create_from_image(img))
	for key: String in ["balk", "balk_m", "balk_color", "balk_far_m"]:
		mat.call("set_shader_param", key, look.get(key))
