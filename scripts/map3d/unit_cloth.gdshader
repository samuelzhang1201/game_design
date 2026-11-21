shader_type spatial;
render_mode cull_disabled;
// A unit figure on the 3D map in its REALM'S CLOTH (Map3DUnitCloth): the figure
// scene's StandardMaterial3D redrawn (albedo, metal B / rough G, normal map),
// its dyed cloth repainted in the owning realm's colour. `cloth_tex` is baked
// by tools/units3d/cloth_mask.py: R = cloth, G = the texel's shade over the
// dye's mean, halved, so the new colour keeps the folds.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D cloth_tex : hint_default_black, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float metallic = 1.0;
uniform float roughness = 1.0;
uniform bool has_normal = true;
// how far the dye turns to the realm's colour (0 = the model's own dye)
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// the realm colour at the dye's mean shade (1 = the colour as on the map)
uniform float value = 1.0;
uniform float fold_contrast : hint_range(0.0, 2.0) = 1.0;
instance uniform vec4 realm_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * albedo_tint.rgb;
	vec2 cloth = texture(cloth_tex, UV).rg;
	float shade = mix(1.0, cloth.g * 2.0, fold_contrast);
	vec3 dyed = clamp(realm_color.rgb * value * shade, 0.0, 1.0);
	ALBEDO = mix(base, dyed, cloth.r * strength);
	vec4 mr = texture(mr_tex, UV);
	METALLIC = metallic * mr.b * (1.0 - cloth.r * strength);
	ROUGHNESS = roughness * mr.g;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
