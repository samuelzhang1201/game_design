shader_type spatial;
// A WAR ROOM wooden piece (spec 2026-10-06-war-room-wooden-pieces): Tripo's
// albedo, ORM (glTF: G roughness, B metal) and normal maps, with the plinth's
// lacquer repainted in the realm's colour. lacquer_tex is read off the albedo
// by tools/war_room/blender/wr_pieces.py: R how much of the texel is lacquer,
// G the paint's light and shade (its value over twice the mean). Every piece
// of one arm shares this material; the colour is per instance.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D lacquer_tex : hint_default_black, filter_linear_mipmap;
uniform float normal_depth = 1.0;
// how far the lacquer's own light and shade carries into the realm colour
uniform float lacquer_shade : hint_range(0.0, 1.0) = 1.0;
// the lacquer's gloss: its roughness where the mask says lacquer
uniform float lacquer_roughness : hint_range(0.0, 1.0) = 0.42;
// old handled oak is satin, not varnished: Tripo's roughness is raised to at
// least this on the wood (at its own 0.27-0.45 the figures shone like bronze)
uniform float wood_roughness_min : hint_range(0.0, 1.0) = 0.75;

instance uniform vec4 lacquer : source_color = vec4(0.35, 0.08, 0.06, 1.0);

void fragment() {
	vec3 wood = texture(albedo_tex, UV).rgb;
	vec2 l = texture(lacquer_tex, UV).rg;
	float shade = mix(1.0, l.g * 2.0, lacquer_shade);
	ALBEDO = mix(wood, lacquer.rgb * shade, l.r);
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = mix(max(orm.g, wood_roughness_min), lacquer_roughness, l.r);
	METALLIC = orm.b * (1.0 - l.r);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
