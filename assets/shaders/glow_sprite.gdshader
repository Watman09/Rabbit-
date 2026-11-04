// Camera-facing additive glow (souls, eyes, projectiles, embers).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// COLOR = per-instance colour when drawn through a MultiMesh (white otherwise)
uniform vec4 color : source_color = vec4(1.0, 0.2, 0.3, 1.0);
varying vec4 v_col;
uniform float core = 0.35;
uniform float softness = 2.2;

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sx, INV_VIEW_MATRIX[2] * sx, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_col = COLOR * color;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), softness);
	float c = smoothstep(core, 0.0, d);
	ALBEDO = (v_col.rgb * halo + vec3(1.0) * c * 0.8) * v_col.a;
}
