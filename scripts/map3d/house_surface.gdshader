// One surface of a settlement house (owner 2026-09-25: "房屋墙壁和房顶的颜色
// 可以多样化一点，主色调不变，但可以有不同variant"). It draws exactly what the
// .glb's own imported material drew — its albedo texture, its roughness, the
// grime baked into its vertex colour, double-sided — and multiplies a WALL or
// ROOF surface by one of data/map3d_house_variants.csv's tints, picked per
// house (Map3DHouses.variant_of) and handed over as the MultiMesh instance's
// custom data: r the wall variant, g the roof's. Map3DLayerHouses binds it.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform bool use_vertex_color = true;
// 0 takes no tint (a recess, timber, slate), 1 a wall's, 2 a roof's
uniform int role = 0;
// linear multipliers, already raised from the table's sRGB hexes
uniform vec3 wall_tints[8];
uniform vec3 roof_tints[8];
uniform int wall_count = 1;
uniform int roof_count = 1;

varying flat vec3 tint;

void vertex() {
	tint = vec3(1.0);
	if (role == 1) {
		tint = wall_tints[clamp(int(INSTANCE_CUSTOM.r + 0.5), 0, wall_count - 1)];
	} else if (role == 2) {
		tint = roof_tints[clamp(int(INSTANCE_CUSTOM.g + 0.5), 0, roof_count - 1)];
	}
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo_color.rgb * tint;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
