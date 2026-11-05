// Ink-smoke ribbons trailing behind a spirit: alpha-blended black with torn,
// ember-lit edges and a wave travelling down each ribbon.
// UV = (across 0..1, along 0 root .. 1 tip), UV2 = (arm t, arm code)
// INSTANCE_CUSTOM like spirit.gdshader: x flash, y dissolve, z attack, w phase*8 + lag+2
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 tint : source_color = vec4(1.0, 0.04, 0.08, 1.1);
uniform vec3 hot : source_color = vec3(1.0, 0.3, 0.2);
uniform float amp = 0.2;
uniform vec3 shoulder = vec3(0.27, 1.2, 0.1);
uniform float twitch = 1.0;

varying float v_dissolve;
varying float v_flash;
varying float v_phase;
varying float v_attack;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_flash = INSTANCE_CUSTOM.x;
	v_dissolve = INSTANCE_CUSTOM.y;
	v_attack = INSTANCE_CUSTOM.z;
	float phase = floor(INSTANCE_CUSTOM.w / 8.0);
	float lag = mod(INSTANCE_CUSTOM.w, 8.0) - 2.0;
	v_phase = phase;
	float along = UV.y;
	float arm = UV2.y;
	if (arm > 0.1) {
		float side = arm > 0.75 ? 1.0 : -1.0;
		vec3 piv = vec3(shoulder.x * side, shoulder.y, shoulder.z);
		vec3 p = VERTEX - piv;
		float a = -v_attack * 1.6;
		float c = cos(a), s = sin(a);
		p = vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
		VERTEX = piv + p;
	}
	// a wave rolls down the ribbon; tips whip more
	float w = along * along;
	float wave = sin(TIME * 3.2 - along * 5.0 + phase * 1.7 + UV.x * 0.5);
	VERTEX.x += wave * amp * w;
	VERTEX.y += cos(TIME * 2.4 - along * 4.0 + phase) * amp * 0.5 * w;
	// trail behind motion
	VERTEX.z -= lag * w * 0.9;
}

void fragment() {
	float along = UV.y;
	float across = abs(UV.x * 2.0 - 1.0);
	vec3 np = vec3(UV.x * 2.2 + v_phase * 3.0, along * 7.0 - TIME * 1.6, v_phase);
	float n = noise(np) * 0.65 + noise(np * 2.7 + 11.0) * 0.35;
	// density: full in the middle and at the root, torn toward edges and tip
	float body = (1.0 - pow(across, 1.6)) * (1.0 - smoothstep(0.35, 1.0, along));
	float d = body * 1.55 + (n - 0.5) * 1.4 - v_dissolve * 1.4;
	float alpha = smoothstep(0.08, 0.5, d) * (0.55 + 0.45 * smoothstep(0.2, 0.9, n + body * 0.4));
	if (alpha < 0.01) {
		discard;
	}
	// ember edge where the smoke is torn
	// thin ember line right at the torn edge; the inside stays ink-black
	float rim = smoothstep(0.26, 0.1, d) * smoothstep(0.02, 0.1, d) * (1.0 - along * 0.5);
	vec3 col = vec3(0.012, 0.006, 0.016) + tint.rgb * rim * tint.a * 2.0;
	col += tint.rgb * smoothstep(0.03, 0.0, abs(n - 0.62)) * 0.6 * (1.0 - along);
	col += vec3(1.0, 0.6, 0.7) * v_flash * 0.12;
	ALBEDO = col;
	ALPHA = alpha * 0.9;
}
