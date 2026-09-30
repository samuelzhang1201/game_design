shader_type spatial;
// The woods' clumps (Map3DTreeMesh) swaying in the wind (owner 2026-09-30):
// each crown leans down the wind and back on its own phase, more the higher
// up the tree, the trunk's foot still. Map3DLayerWind sets wind_time (it
// runs only while the clock does) and the rest from balance.csv map3d_wind_*.
// Colour is the mesh's vertex colour times the instance's tint, both sRGB:
// Forward+ hands COLOR over unconverted, so it is turned linear here.

uniform float wind_time = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float sway_m = 0.6;
uniform float sway_height_m = 30.0;
uniform float sway_hz = 0.25;
uniform float flutter = 0.35;
uniform float roughness_value = 0.95;
uniform float specular_value = 0.15;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(VERTEX.y / sway_height_m, 0.0, 1.0);
	k *= k;
	// each tree its own phase (its spot, quantised to a crown's size), and a
	// travelling term so a gust visibly rolls through the wood
	float ph = dot(floor(wp.xz / 7.0), vec2(1.71, 2.37)) + dot(wp.xz, wind_dir) * 0.015;
	float t = wind_time * sway_hz * 6.2831853 + ph;
	float lean = 0.55 + 0.45 * sin(t);
	float side = sin(t * 1.7 + ph * 0.5) * flutter;
	vec3 dir_m = normalize((inverse(mat3(MODEL_MATRIX)) * vec3(wind_dir.x, 0.0, wind_dir.y)));
	vec3 perp_m = normalize((inverse(mat3(MODEL_MATRIX)) * vec3(-wind_dir.y, 0.0, wind_dir.x)));
	// the model is scaled by its instance: sway_m is world metres at the top
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX += (dir_m * lean + perp_m * side) * sway_m * k / max(s, 0.0001);
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb);
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
