shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, depth_prepass_alpha;
// The woods as PHOTOGRAPHS (owner 2026-10-01: 树木一旦把标尺拉到20km以下就非常丑非常假
// — the critic: smooth CG crowns on the aerial ground break "one world, one
// medium"). Every crown of a clump (Map3DTreeMesh.cards) is one card turned
// to face the camera about its own centre, wearing a cut-out aerial
// photograph of a real tree from the crown atlas; it is lit as a soft sphere
// so the sun still turns it, sways with the wind like the 3D crowns did, and
// casts the crown's own shape as its shadow (in the shadow pass the "camera"
// is the light, so the card faces the light).
//
// A card's four corners share their crown's centre as VERTEX; CUSTOM0 holds
// (corner x, corner y, half size m, atlas cell). Colour is the instance's
// tint (sRGB, turned linear here, like tree_sway.gdshader).

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int atlas_cols = 4;
uniform int atlas_rows = 4;
uniform float alpha_cut = 0.5;
uniform float sphere = 0.6;          // how far the normal bulges from flat-to-camera to a sphere
uniform float lift = 0.15;           // the card's centre lifted toward the camera, a share of its size
uniform float saturation = 0.9;
uniform float value_gain = 1.0;
uniform float tint_k = 0.5;          // how far the instance tint colours the photograph
uniform float alpha_far_gain = 0.6;  // per mip level the cut-out's alpha is raised, so a far crown stays full
uniform float far_value = 0.8;       // the brightness a crown keeps once a texel is a whole crown (far away)
uniform float wind_time = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float sway_m = 0.6;
uniform float sway_hz = 0.25;

varying vec2 corner;
varying vec2 cell_uv0;
varying vec3 tint;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	corner = CUSTOM0.xy;
	float half_m = CUSTOM0.z * length(MODEL_MATRIX[0].xyz);
	int cell = int(CUSTOM0.w + 0.5);
	cell_uv0 = vec2(float(cell % atlas_cols), float(cell / atlas_cols)) / vec2(float(atlas_cols), float(atlas_rows));
	tint = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// the top of the card sways down the wind and back, on its own phase
	float ph = dot(floor(wp.xz / 7.0), vec2(1.71, 2.37)) + dot(wp.xz, wind_dir) * 0.015;
	float t = wind_time * sway_hz * 6.2831853 + ph;
	vec3 sway = vec3(wind_dir.x, 0.0, wind_dir.y) * (0.55 + 0.45 * sin(t)) * sway_m * max(corner.y, 0.0);
	vec4 centre = VIEW_MATRIX * vec4(wp + sway, 1.0);
	vec3 to_cam = normalize(-centre.xyz);
	VERTEX = centre.xyz + to_cam * lift * half_m * 2.0 + vec3(corner * half_m, 0.0);
	NORMAL = normalize(vec3(corner * sphere, 1.0));
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec2 uv = cell_uv0 + (vec2(corner.x, -corner.y) * 0.5 + 0.5) / vec2(float(atlas_cols), float(atlas_rows));
	vec4 px = texture(atlas, uv);
	// a far crown's mips average its rim with clear texels: its alpha thins
	// and the woods read as grey stipple — raise it by the mip level
	vec2 texel = uv * vec2(textureSize(atlas, 0));
	float mip = max(0.0, 0.5 * log2(max(dot(dFdx(texel), dFdx(texel)), dot(dFdy(texel), dFdy(texel)))));
	px.a = clamp(px.a * (1.0 + alpha_far_gain * mip), 0.0, 1.0);
	vec3 c = px.rgb * mix(1.0, far_value, clamp(mip / 6.0, 0.0, 1.0));
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(grey), c, saturation) * value_gain;
	c *= mix(vec3(1.0), to_linear(tint) / max(dot(to_linear(tint), vec3(0.333)), 0.001), tint_k);
	ALBEDO = clamp(c, 0.0, 1.0);
	ALPHA = px.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
