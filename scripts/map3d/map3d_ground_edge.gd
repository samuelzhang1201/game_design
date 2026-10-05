class_name Map3DGroundEdge
extends RefCounted
## The grounds' EDGES drawn per pixel (visual review 2026-10-05, lever ③: the
## fields read as paper cut-outs). Terrain3D blends its textures and colour
## map between 20 m vertices, so every edge — a field against the grass, a
## furlong against its neighbour, a wood's floor — runs in 20 m stair-steps.
## This patch bends the fragment's vertex coordinates by a fine noise before
## Terrain3D looks its vertices up: the edge wanders a few metres like a balk
## or a hedge line, sharp at the pixel, and the stair is gone. The geometry is
## untouched (the vertex stage never sees it), and far out, where a vertex is
## under a pixel, it fades away (the ground look's `edge_warp_*`, 0 off).

const UV_LINE := "\tvec2 uv = UV;\n"

const UNIFORMS := """
// Map3DGroundEdge: the edges' per-pixel wander (the ground look's edge_warp_*).
uniform float edge_warp_m = 0.0;
uniform float edge_warp_wave_m = 60.0;
uniform float edge_warp_fine = 0.35;
uniform float edge_warp_far_m = 9000.0;
uniform float edge_fray_m = 0.0;
uniform float edge_fray_wave_m = 36.0;
uniform float edge_fray_from_m = 2500.0;
uniform float edge_fray_full_m = 6000.0;
"""

const WARPED_UV := """	vec2 uv = UV;
	// Map3DGroundEdge: two octaves of value noise, each axis its own
	if (edge_warp_m > 0.0) {
		vec2 eq = v_vertex.xz / edge_warp_wave_m;
		vec2 ew = vec2(wx_noise(eq), wx_noise(eq + vec2(17.3, 41.9))) - 0.5;
		ew += (vec2(wx_noise(eq * 3.7 + vec2(5.1, 9.4)), wx_noise(eq * 3.7 + vec2(29.7, 3.3))) - 0.5) * edge_warp_fine;
		float e_dist = length(v_vertex - _camera_pos);
		float ek = 1.0 - smoothstep(edge_warp_far_m * 0.5, edge_warp_far_m, e_dist);
		// farther out a 20 m step is a few px: a finer fray breaks it up there
		vec2 fq = v_vertex.xz / edge_fray_wave_m;
		vec2 fw = vec2(wx_noise(fq + vec2(3.1, 7.7)), wx_noise(fq + vec2(11.9, 23.5))) - 0.5;
		float fk = smoothstep(edge_fray_from_m, edge_fray_full_m, e_dist) * edge_fray_m;
		uv += (ew * edge_warp_m + fw * fk) * (2.0 * _vertex_density * ek);
	}
"""


## `code` (already carrying Map3DGroundTint's patch, whose wx_noise this
## uses) with the edge warp; unchanged when it has it or lacks the line.
static func patch(code: String) -> String:
	if code.contains("// Map3DGroundEdge:") or not code.contains(UV_LINE):
		return code
	var at := code.find("// Map3DGroundTint:")
	if at < 0:
		return code
	return code.insert(at, UNIFORMS + "\n").replace(UV_LINE, WARPED_UV)


## Hand the ground `mat` the look's wander.
static func apply(mat: Object, look: Map3DGroundLook) -> void:
	for key: String in ["edge_warp_m", "edge_warp_wave_m", "edge_warp_fine", "edge_warp_far_m", "edge_fray_m",
			"edge_fray_wave_m", "edge_fray_from_m", "edge_fray_full_m"]:
		mat.call("set_shader_param", key, float(look.get(key)))
