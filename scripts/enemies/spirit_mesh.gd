## Builds and caches procedural spirit meshes + materials per enemy type.
## Body, eyes, arms and horns are one mesh (one draw call per spirit); the
## spirit shader animates tail, arms and dissolve from vertex colours.
class_name SpiritMesh
extends RefCounted

const SHADER := preload("res://assets/shaders/spirit.gdshader")

static var _meshes := {}
static var _materials := {}

const PRESETS := {
	"wisp": {"height": 0.9, "head_r": 0.2, "body_r": 0.22, "back": 1.5, "arms": false, "eye": 0.06, "eye_gap": 0.075, "sway": 0.22, "ragged": 0.8},
	"wraith": {"height": 1.55, "head_r": 0.23, "body_r": 0.3, "back": 2.0, "arms": true, "arm_len": 0.85, "arm_r": 0.08, "eye": 0.055, "eye_gap": 0.09, "sway": 0.16, "ragged": 0.75},
	"banshee": {"height": 1.8, "head_r": 0.22, "body_r": 0.3, "back": 2.4, "arms": true, "arm_len": 1.0, "arm_r": 0.05, "eye": 0.05, "eye_gap": 0.08, "sway": 0.25, "ragged": 0.85, "hood": true},
	"shade": {"height": 1.75, "head_r": 0.27, "body_r": 0.38, "back": 2.2, "arms": true, "arm_len": 1.0, "arm_r": 0.1, "eye": 0.065, "eye_gap": 0.11, "sway": 0.14, "ragged": 0.7, "horns": 0.25},
	"brute": {"height": 1.7, "head_r": 0.26, "body_r": 0.55, "back": 1.6, "arms": true, "arm_len": 1.25, "arm_r": 0.17, "eye": 0.07, "eye_gap": 0.11, "sway": 0.1, "ragged": 0.6, "horns": 0.3, "hunch": 0.25},
	"boss": {"height": 2.0, "head_r": 0.3, "body_r": 0.55, "back": 3.0, "arms": true, "arm_len": 1.4, "arm_r": 0.12, "eye": 0.07, "eye_gap": 0.11, "sway": 0.12, "ragged": 0.7, "horns": 0.55, "hunch": 0.15},
}

static func preset(kind: String) -> Dictionary:
	return PRESETS.get(kind, PRESETS["wraith"])

static func mesh_for(kind: String) -> ArrayMesh:
	if not _meshes.has(kind):
		_meshes[kind] = _build(preset(kind))
	return _meshes[kind]

static func material_for(kind: String) -> ShaderMaterial:
	if not _materials.has(kind):
		var p := preset(kind)
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("sway_amount", p.sway)
		m.set_shader_parameter("raggedness", p.ragged)
		var sh := _shoulder(p)
		m.set_shader_parameter("shoulder", Vector3(absf(sh.x), sh.y, sh.z))
		_materials[kind] = m
	return _materials[kind]

## Spine: head up high, body sinks, then the tail streams backwards close to
## the floor so it reads as a smoke trail from the top-down camera.
static func _spine(p: Dictionary, t: float) -> Vector3:
	var h: float = p.height
	var hunch: float = p.get("hunch", 0.0)
	var y := lerpf(h, h * 0.28 + 0.12, smoothstep(0.0, 0.7, t))
	var z: float = -p.back * pow(clampf((t - 0.38) / 0.62, 0.0, 1.0), 1.1) + hunch * (1.0 - t) * 0.5
	return Vector3(0, y, z)

static func _radius(p: Dictionary, t: float) -> float:
	var hr: float = p.head_r
	var br: float = p.body_r
	if t < 0.2:
		return hr * sin(PI * 0.5 * t / 0.2)
	if t < 0.28:
		return lerpf(hr, hr * 0.85, (t - 0.2) / 0.08)
	if t < 0.42:
		return lerpf(hr * 0.85, br, smoothstep(0.28, 0.42, t))
	var u := (t - 0.42) / 0.58
	return maxf(0.015, br * pow(1.0 - u, 0.95))

static func _shoulder(p: Dictionary) -> Vector3:
	var c := _spine(p, 0.36)
	return Vector3(p.body_r * 0.92, c.y, c.z + 0.05)

static func _build(p: Dictionary) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var rings := 13
	var seg := 9
	# --- body: rings swept along the spine, perpendicular to its tangent ---
	for i in rings + 1:
		var t := float(i) / rings
		var c := _spine(p, t)
		var tang := (_spine(p, minf(t + 0.01, 1.0)) - _spine(p, maxf(t - 0.01, 0.0))).normalized()
		var side := Vector3.RIGHT
		var up := side.cross(tang).normalized()   # perpendicular to tangent in the YZ plane
		var r := _radius(p, t)
		if i == 0:
			r = 0.0
		for j in seg:
			var a := TAU * j / seg
			var ca := cos(a)
			var sa := sin(a)
			v.append(c + side * ca * r * 1.12 + up * sa * r * 0.92)
			var nn := (side * ca + up * sa)
			if i == 0:
				nn = -tang
			n.append(nn.normalized())
			col.append(Color(0, 0, t, 1))
			uv.append(Vector2(float(j) / seg, t))
	for i in rings:
		for j in seg:
			var a0 := i * seg + j
			var a1 := i * seg + (j + 1) % seg
			var b0 := a0 + seg
			var b1 := a1 + seg
			idx.append_array([a0, a1, b0, a1, b1, b0])
	# --- eyes (slanted, glowing) ---
	var head := _spine(p, 0.11)
	for side in [-1.0, 1.0]:
		var ec := head + Vector3(side * p.eye_gap, 0.0, p.head_r * 0.92)
		var b := Basis(Vector3(0, 0, 1), side * 0.45) * Basis.from_scale(Vector3(p.eye * 1.6, p.eye * 0.7, p.eye * 0.5))
		_add_ellipsoid(v, n, col, uv, idx, ec, b, Color(1, 0, 0, 1))
	# --- arms ---
	if p.arms:
		var sh := _shoulder(p)
		for side in [-1.0, 1.0]:
			var start := Vector3(sh.x * side, sh.y, sh.z)
			var dir := Vector3(side * 0.35, -0.8, 0.5).normalized()
			_add_tube(v, n, col, uv, idx, start, dir, p.arm_len, p.arm_r, Color(0, 0.5 if side < 0 else 1.0, 0.25, 1), true)
	# --- trailing smoke tendrils (sway like the tail) ---
	var tendrils: int = p.get("tendrils", 3)
	for k in tendrils:
		var st := _spine(p, 0.4 + 0.1 * k)
		var sx: float = (1.0 if k % 2 == 0 else -1.0) * p.body_r * 0.8
		var d := Vector3(sx * 0.8, -0.25, -1.0).normalized()
		_add_tube(v, n, col, uv, idx, st + Vector3(sx, 0, 0), d, p.back * 0.7, p.body_r * 0.3, Color(0, 0, 0.6, 1), false)
	# --- hood spikes (banshee) ---
	if p.get("hood", false):
		var top := _spine(p, 0.02)
		for k in 5:
			var a2 := lerpf(-1.2, 1.2, k / 4.0)
			var d2 := Vector3(sin(a2) * 0.5, -0.4, -0.8).normalized()
			_add_tube(v, n, col, uv, idx, top + Vector3(sin(a2) * 0.12, 0, -0.05), d2, 0.9, 0.05, Color(0, 0, 0.8, 1), false)
	# --- horns ---
	var hl: float = p.get("horns", 0.0)
	if hl > 0.0:
		var top2 := _spine(p, 0.05)
		for side in [-1.0, 1.0]:
			var d3 := Vector3(side * 0.7, 0.75, -0.15).normalized()
			_add_tube(v, n, col, uv, idx, top2 + Vector3(side * p.head_r * 0.6, 0, 0), d3, hl, p.head_r * 0.28, Color(0, 0, 0.0, 1), false)
	# Masks travel in UV/UV2 (COLOR is replaced by the instance colour on the
	# GL MultiMesh path): UV = (arm length t, arm code), UV2 = (tail, eye).
	var uv2 := PackedVector2Array()
	uv2.resize(v.size())
	for i in v.size():
		uv[i] = Vector2(uv[i].x, col[i].g)
		uv2[i] = Vector2(col[i].b, col[i].r)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func _add_ellipsoid(v: PackedVector3Array, n: PackedVector3Array, col: PackedColorArray, uv: PackedVector2Array,
		idx: PackedInt32Array, c: Vector3, b: Basis, color: Color) -> void:
	var base := v.size()
	var rs := 3
	var ss := 6
	for i in rs + 1:
		var phi := PI * i / rs
		for j in ss:
			var th := TAU * j / ss
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			v.append(c + b * d)
			n.append(d)
			col.append(color)
			uv.append(Vector2.ZERO)
	for i in rs:
		for j in ss:
			var a0 := base + i * ss + j
			var a1 := base + i * ss + (j + 1) % ss
			idx.append_array([a0, a0 + ss, a1, a1, a0 + ss, a1 + ss])

## Tapered tube along a slightly curved path; UV.x = 0..1 along its length.
static func _add_tube(v: PackedVector3Array, n: PackedVector3Array, col: PackedColorArray, uv: PackedVector2Array,
		idx: PackedInt32Array, start: Vector3, dir: Vector3, length: float, r0: float, color: Color, claw: bool) -> void:
	var base := v.size()
	var rings := 4
	var seg := 5
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	for i in rings + 1:
		var t := float(i) / rings
		var bend := (dir + Vector3(0, 0.5 if claw else 0.4, 0) * t * t).normalized() if not claw else (dir + Vector3(0, 0, 0.6) * t * t).normalized()
		var c := start + bend * length * t
		var r := r0 * (1.0 - t * 0.85) * (1.0 + (0.4 if claw and t > 0.7 else 0.0))
		for j in seg:
			var a := TAU * j / seg
			var d := side * cos(a) + up * sin(a)
			v.append(c + d * r)
			n.append(d)
			var cc := color
			cc.b = maxf(color.b, t * 0.5)
			col.append(cc)
			uv.append(Vector2(t, 0))
	for i in rings:
		for j in seg:
			var a0 := base + i * seg + j
			var a1 := base + i * seg + (j + 1) % seg
			idx.append_array([a0, a1, a0 + seg, a1, a1 + seg, a0 + seg])
