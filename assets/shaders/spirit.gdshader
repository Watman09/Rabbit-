// Dark spirit: opaque black smoke body with crimson rim, ragged dissolving
// tail, glowing eyes and shader-animated arms. Spirits are drawn with one
// MultiMesh per type; per-spirit values come from INSTANCE_CUSTOM:
//   x = hit flash, y = dissolve, z = attack (arms), w = phase*8 + (lag_z + 2)
// UV2.y = glow mask (1 eye, 0.6 maw, 0.3 teeth/claw tips), UV.y = arm (0 none, 0.5 left, 1 right),
// UV2.x = tail factor (0 head .. 1 tail tip), UV.x = arm length factor.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.06, 0.12, 1.0);   // tier colour: rim, veins
uniform vec3 hot : source_color = vec3(1.0, 0.35, 0.3);          // eyes and maw
uniform float twitch = 1.0;                                       // nervous head jerks

uniform float sway_amount = 0.16;
uniform vec3 shoulder = vec3(0.32, 1.05, 0.05);
uniform float eye_power = 2.4;
uniform float raggedness = 0.75;

varying float v_tail;
varying float v_eye;
varying vec3 v_pos;
varying float v_flash;
varying float v_dissolve;
varying float v_phase;
varying float v_fres;
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
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	float flash = INSTANCE_CUSTOM.x;
	float dissolve = INSTANCE_CUSTOM.y;
	float attack = INSTANCE_CUSTOM.z;
	float phase = floor(INSTANCE_CUSTOM.w / 8.0);
	vec3 lag = vec3(0.0, 0.0, mod(INSTANCE_CUSTOM.w, 8.0) - 2.0);
	v_flash = flash;
	v_dissolve = dissolve;
	v_phase = phase;
	float tail = UV2.x;
	float arm = UV.y;
	v_eye = UV2.y;
	v_tail = tail;
	if (arm > 0.1) {
		// rotate arm around its shoulder: raise forward with "attack"
		float side = arm > 0.75 ? 1.0 : -1.0;
		vec3 piv = vec3(shoulder.x * side, shoulder.y, shoulder.z);
		vec3 p = VERTEX - piv;
		float a = -attack * 1.9 + sin(TIME * 3.0 + phase + side) * 0.12;
		float c = cos(a), s = sin(a);
		p = vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
		// claws curl inward during the strike
		p.x -= side * attack * 0.25 * UV.x;
		VERTEX = piv + p;
	}
	// nervous twitch: the head snaps to a new offset a few times a second
	float jt = floor(TIME * 7.0 + phase * 3.1);
	float jerk = step(0.72, hash(vec3(jt, phase, 1.0)));
	vec3 jo = vec3(hash(vec3(jt, 2.0, phase)) - 0.5, hash(vec3(jt, 5.0, phase)) - 0.5, 0.0) * 0.07 * jerk * twitch;
	VERTEX += jo * (1.0 - smoothstep(0.0, 0.35, tail));
	v_attack = attack;
	float w = tail * tail;
	VERTEX.x += sin(TIME * 2.7 + phase + tail * 3.0) * sway_amount * w;
	VERTEX.z += cos(TIME * 2.1 + phase * 1.3 + tail * 2.5) * sway_amount * w;
	VERTEX -= lag * w;
	VERTEX *= 1.0 + sin(TIME * 3.0 + phase) * 0.03 * (1.0 - tail);
	v_pos = VERTEX;
	vec3 vn = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 vv = normalize(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_fres = pow(1.0 - abs(dot(vn, vv)), 2.4);
}

void fragment() {
	float flash = v_flash;
	float dissolve = v_dissolve;
	float phase = v_phase;
	// smoke flows from the head toward the tail (-Z)
	vec3 np = v_pos * 3.0 + vec3(phase * 1.7, -TIME * 0.6, TIME * 1.6);
	float n = noise(np) * 0.75 + (sin(np.x * 7.0 + np.z * 5.0 + np.y * 3.0) * 0.5 + 0.5) * 0.25;
	float cut = smoothstep(0.35, 1.0, v_tail) * raggedness;
	if (n < cut && v_eye < 0.1) {
		discard;
	}
	if (n < dissolve * 1.05) {
		discard;
	}
	float edge = (1.0 - smoothstep(0.0, 0.12, n - dissolve)) * step(0.001, dissolve);
	float fres = pow(v_fres, 1.4);
	vec3 col = vec3(0.01, 0.006, 0.014) + vec3(0.035, 0.02, 0.045) * n * (1.0 - v_tail);
	// thin crimson silhouette
	col += tint.rgb * pow(fres, 1.3) * tint.a * 1.1 * (1.0 - v_tail * 0.6);
	// glowing veins / cracks like smouldering embers
	float vein = 0.0;
	if (v_tail < 0.8) {
		float n2 = noise(v_pos * 3.2 + vec3(0.0, -TIME * 0.4, phase));
		vein = smoothstep(0.016, 0.0, abs(n2 - 0.5)) * (1.0 - v_tail) * 0.35 * step(0.0, sin(v_pos.x * 4.0 + v_pos.y * 3.0 + phase));
	}
	col += tint.rgb * vein * tint.a;
	// smouldering ragged edges of the tail
	col += tint.rgb * (cut > 0.01 ? smoothstep(cut + 0.06, cut, n) * 0.6 : 0.0);
	col += tint.rgb * 3.0 * edge;
	// masks: eyes / maw / teeth
	float eye = step(0.8, v_eye);
	float maw = step(0.45, v_eye) * (1.0 - eye);
	float tooth = step(0.15, v_eye) * (1.0 - step(0.45, v_eye));
	float breathe = 0.75 + 0.25 * sin(TIME * 5.0 + phase * 2.0);
	col = mix(col, mix(tint.rgb, hot, 0.45) * eye_power, eye);
	col = mix(col, mix(tint.rgb, hot, 0.3) * (0.9 + v_attack * 4.0) * breathe, maw);
	col = mix(col, vec3(0.75, 0.68, 0.62) * 0.9 + hot * 0.6, tooth);
	col += vec3(1.0, 0.55, 0.65) * flash * (0.08 + fres * 0.9);
	ALBEDO = col;
}
