class_name Map3DGroundStrips
extends RefCounted
## The open fields' FURROWS and STRIPS in the patched Terrain3D shader (owner
## 2026-10-01), spliced in by Map3DGroundTint.patch: up close fine furrow
## lines, then each strip its own shade, farther out broader bands of them,
## along each field's strip direction (bake/fields.png A). A 40 m texel holds
## one direction, so the pattern is drawn for each of the four texels round
## the pixel and blended bilinearly: blending the DIRECTION swung the strips
## into arcs, and the nearest texel's cut their ends in 40 m steps (visual
## review 2026-10-14). A texel's own sown share weighs its pattern, so the
## strips fade out at a field's rim instead of turning to another field's way.

const UNIFORMS := """
// Map3DGroundStrips: furrows and strips over the field map's directions.
uniform float furrow_m = 9.0;
uniform float furrow_depth = 0.0;
uniform float furrow_sharp = 1.0;
uniform float strip_m = 22.0;
uniform float strip_shade = 0.0;
uniform float strip_far_m = 80.0;
uniform float strip_far_shade = 0.0;

// The pattern's multiplier at `p` for strips running at `ang`, on ground `sown` (0..1) sown.
float field_strip_k(vec2 p, float ang, float sown) {
	vec2 across = vec2(-sin(ang), cos(ang));
	float ph = dot(p, across) / furrow_m;
	float aa = 1.0 - smoothstep(0.3, 0.6, fwidth(ph));
	float k = 1.0 - furrow_depth * sown * aa * pow(0.5 + 0.5 * sin(ph * 6.2831853), furrow_sharp);
	if (strip_shade > 0.0) {
		float sp = dot(p, across) / strip_m;
		float sa = dot(p, vec2(cos(ang), sin(ang))) / (strip_m * 9.0);
		float sh = wx_hash(vec2(floor(sp), floor(sa + wx_hash(vec2(floor(sp), 3.7)))));
		float saa = 1.0 - smoothstep(0.15, 0.4, fwidth(sp));
		k *= 1.0 + strip_shade * sown * saa * (sh - 0.5) * 2.0;
		// farther out, broader bands of its strips carry the furlong's grain
		float sp2 = sp * strip_m / strip_far_m;
		float sh2 = wx_hash(vec2(floor(sp2), floor(sa * strip_m / strip_far_m + 7.3)));
		k *= 1.0 + strip_far_shade * sown * (1.0 - smoothstep(0.2, 0.5, fwidth(sp2)))
			* (1.0 - saa) * (sh2 - 0.5) * 2.0;
	}
	return k;
}

// One texel's pattern: its own direction and sown share.
float field_strip_at(vec2 p, ivec2 t) {
	vec4 ft = texelFetch(field_map, clamp(t, ivec2(0), textureSize(field_map, 0) - 1), 0);
	float s = clamp((1.0 - min(min(ft.r, ft.g), ft.b)) / 0.25, 0.0, 1.0);
	return field_strip_k(p, ft.a * 3.14159265, s);
}
"""

## Replaces the stage's marker in Map3DGroundTint.TINTED_ALBEDO (`fuv` the
## pixel's field-map uv there).
const STAGE := """		vec2 ftx = fuv * vec2(textureSize(field_map, 0)) - 0.5;
		ivec2 f0 = ivec2(floor(ftx));
		vec2 ff = ftx - floor(ftx);
		base_albedo *= mix(
			mix(field_strip_at(v_vertex.xz, f0), field_strip_at(v_vertex.xz, f0 + ivec2(1, 0)), ff.x),
			mix(field_strip_at(v_vertex.xz, f0 + ivec2(0, 1)), field_strip_at(v_vertex.xz, f0 + ivec2(1, 1)), ff.x),
			ff.y);
"""
