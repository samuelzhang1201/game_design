class_name Map3DGroundRelief
extends RefCounted
## The relief's sky occlusion on the ground (visual review 2026-10-05: the
## land read flat at the opening zoom). The sun rides high (owner 2026-09-28),
## so the slopes facing the camera get little modelling from it; the light
## the map lacked is the SKY's — a valley floor, a terrace's foot and a gorge
## see less of it. tools/map3d/bake_relief_ao.py bakes how much of the sky
## each 40 m texel sees into bake/relief_ao.png; this stage darkens the ground
## by it (the ground look's `relief_ao`, 0 off). It has no direction, so it
## never fights the turning sun, and baked it costs one texture fetch.

const UNIFORMS := """
// Map3DGroundRelief: the baked sky occlusion (bake/relief_ao.png).
uniform highp sampler2D relief_ao_map : filter_linear, repeat_disable;
uniform float relief_ao = 0.0;
uniform float relief_ao_gamma = 1.0;
uniform float relief_ao_m_per_texel = 40.0;
uniform float relief_ao_near = 0.35;
uniform float relief_ao_near_m = 2500.0;
uniform float relief_ao_far_m = 10000.0;
"""

const STAGE := """	if (relief_ao > 0.0) {
		vec2 ruv = (v_vertex.xz - pack_origin) / relief_ao_m_per_texel / vec2(textureSize(relief_ao_map, 0));
		float sky_seen = pow(texture(relief_ao_map, ruv).r, relief_ao_gamma);
		// full strength far out; up close the sun and SSAO model the slope, and a
		// 40 m texel's dark would read as a burn beside a house
		float ao_k = relief_ao * mix(relief_ao_near, 1.0,
			smoothstep(relief_ao_near_m, relief_ao_far_m, length(v_vertex - _camera_pos)));
		base_albedo *= mix(1.0, sky_seen, ao_k);
	}
"""


## Hand the ground `mat` (the patched Terrain3D material) the build's
## occlusion and the look's strength; off without the file.
static func apply(mat: Object, scene_path: String, look: Map3DGroundLook) -> void:
	var path := Map3DWorldLoader.data_dir(scene_path).path_join("bake/relief_ao.png")  # res://, as woods.png
	var img: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null or look.relief_ao <= 0.0:
		mat.call("set_shader_param", "relief_ao", 0.0)
		return
	mat.call("set_shader_param", "relief_ao_map", ImageTexture.create_from_image(img))
	mat.call("set_shader_param", "relief_ao", look.relief_ao)
	for key: String in ["relief_ao_gamma", "relief_ao_near", "relief_ao_near_m", "relief_ao_far_m"]:
		mat.call("set_shader_param", key, float(look.get(key)))
