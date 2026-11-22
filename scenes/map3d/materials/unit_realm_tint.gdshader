shader_type spatial;
// The realm's colour on a map figure's tunic (Map3DUnitDress; spec
// 2026-11-21-infantry-melee-scrum-design, step 1). Worn as the figure's
// material_overlay: it repaints only where `tunic_mask` is set, over the scene's
// own material (which the WAR ROOM's tin and ink keep reading). The tunic keeps
// its cloth's light and shade — the atlas's luminance over the tunic's mean
// (`tunic_luminance`, linear) — in the realm's hue, so a mid-tunic texel is
// exactly `realm_tint`.
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D mr_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D tunic_mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float tunic_luminance = 0.12;
uniform float shade_max = 2.0;
// the tunic is matte cloth: no metal, at least this rough (no satin sheen on the back)
uniform float cloth_roughness : hint_range(0.0, 1.0) = 0.85;
instance uniform vec4 realm_tint : source_color = vec4(1.0);

void fragment() {
	vec3 base = texture(albedo_atlas, UV).rgb;
	float shade = dot(base, vec3(0.2126, 0.7152, 0.0722)) / tunic_luminance;
	ALBEDO = realm_tint.rgb * clamp(shade, 0.0, shade_max);
	vec4 mr = texture(mr_atlas, UV);
	ROUGHNESS = max(mr.g, cloth_roughness);
	METALLIC = 0.0;
	NORMAL_MAP = texture(normal_atlas, UV).rgb;
	ALPHA = texture(tunic_mask, UV).r;
}
