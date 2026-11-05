## Visual effects service: slashes, particles, shockwaves, telegraphs,
## afterimages, death fragments. Everything is pooled or cached where it
## matters for browser performance.
extends Node

const SLASH_SHADER := preload("res://assets/shaders/slash.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/glow_sprite.gdshader")
const GROUND_SHADER := preload("res://assets/shaders/ground_fx.gdshader")
const SHADOW_SHADER := preload("res://assets/shaders/shadow.gdshader")
const CrescentWaveScript := preload("res://scripts/fx/crescent_wave.gd")

var _glow_mat: ShaderMaterial
var _shadow_mat: ShaderMaterial
var _quad: QuadMesh
var _plane: PlaneMesh
var _arc_cache := {}
var _slashes: Array = []     # [{node, mat, t, active, life, trail, follow}]
var _grounds: Array = []     # [{node, mat, t, dur, kind}]
var _ghosts: Array = []      # [{node, t, life}]
var _frags: Array = []       # [{node, t, life, vel}]
var _pools := {}             # type -> {nodes: Array, i: int}
var _soft_tex: GradientTexture2D
var _flash_rect: ColorRect
var particles_enabled := true
var quality := 1.0           # scales particle amounts (lowered automatically on slow devices)

func _ready() -> void:
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GLOW_SHADER
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = SHADOW_SHADER
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE
	_plane = PlaneMesh.new()
	_plane.size = Vector2(2, 2)
	_soft_tex = GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	_soft_tex.gradient = g
	_soft_tex.fill = GradientTexture2D.FILL_RADIAL
	_soft_tex.fill_from = Vector2(0.5, 0.5)
	_soft_tex.fill_to = Vector2(1.0, 0.5)
	_soft_tex.width = 64
	_soft_tex.height = 64
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	layer.add_child(_flash_rect)

## Called by Main when a new world is built (scene reload frees old nodes).
func reset() -> void:
	_slashes.clear()
	_grounds.clear()
	_ghosts.clear()
	_frags.clear()
	_pools.clear()

func _root() -> Node3D:
	return Game.world

# ------------------------------------------------------------------ simple builders
func make_glow_sprite(color: Color, size: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _quad
	m.material_override = glow_material(color)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3.ONE * size
	return m

var _glow_mats := {}
## Shared glow material per colour (instance uniforms are unavailable on WebGL).
func glow_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _glow_mats.has(key):
		var mat := _glow_mat.duplicate()
		mat.set_shader_parameter("color", color)
		_glow_mats[key] = mat
	return _glow_mats[key]

## MultiMesh of glow quads with per-instance colours (souls, bolts).
func make_glow_multimesh(count: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _quad
	mm.instance_count = count
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = glow_material(Color(1, 1, 1, 1))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 30, 120))
	return mmi

func make_shadow(size: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _plane
	m.material_override = _shadow_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3(size * 0.5, 1, size * 0.5)
	m.position.y = 0.02
	return m

# ------------------------------------------------------------------ slashes
func _arc_mesh(from_deg: float, to_deg: float, inner: float, outer: float) -> ArrayMesh:
	var key := "%d_%d_%.2f_%.2f" % [int(from_deg), int(to_deg), inner, outer]
	if _arc_cache.has(key):
		return _arc_cache[key]
	var seg := clampi(int(absf(to_deg - from_deg) / 5.0), 12, 90)
	var rows := 3
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in seg + 1:
		var u := float(i) / seg
		var a := deg_to_rad(lerpf(from_deg, to_deg, u))
		for j in rows + 1:
			var w := float(j) / rows
			var r := lerpf(inner, outer, w)
			v.append(Vector3(sin(a) * r, 0, cos(a) * r))
			uv.append(Vector2(u, w))
	for i in seg:
		for j in rows:
			var a0 := i * (rows + 1) + j
			var b0 := a0 + rows + 1
			idx.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_arc_cache[key] = m
	return m

func make_slash_material(edge: Color, core: Color, intensity: float, trail: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SLASH_SHADER
	mat.set_shader_parameter("edge_color", edge)
	mat.set_shader_parameter("core_color", core)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("trail", trail)
	return mat

## A crescent trail that sweeps from `from_deg` to `to_deg` in the XZ plane of `xf`.
func slash(xf: Transform3D, from_deg: float, to_deg: float, inner: float, outer: float,
		active: float, life: float, trail: float, edge: Color, core: Color, intensity := 2.4,
		follow: Node3D = null, eased := false) -> Dictionary:
	var root := _root()
	if root == null:
		return {}
	var m := MeshInstance3D.new()
	m.mesh = _arc_mesh(from_deg, to_deg, inner, outer)
	var mat := make_slash_material(edge, core, intensity, trail)
	mat.set_shader_parameter("progress", 0.0)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.global_transform = xf
	var off := Vector3.ZERO
	if follow:
		off = xf.origin - follow.global_position
	var d := {"node": m, "mat": mat, "t": 0.0, "active": maxf(active, 0.01), "life": life,
		"trail": trail, "follow": follow, "off": off, "eased": eased, "from": from_deg, "to": to_deg, "manual": -1.0}
	_slashes.append(d)
	return d

## Drive a slash's leading edge from the real blade-tip position (world space).
func slash_track(handle: Dictionary, tip: Vector3) -> void:
	if handle.is_empty() or not is_instance_valid(handle.node):
		return
	var local: Vector3 = (handle.node as Node3D).global_transform.affine_inverse() * tip
	var ang := rad_to_deg(atan2(local.x, local.z))
	var span: float = handle.to - handle.from
	# unwrap toward the expected progress so ±180 crossings do not jump
	var expect: float = handle.from + span * maxf(handle.manual, 0.0)
	ang += roundf((expect - ang) / 360.0) * 360.0
	var k := clampf((ang - handle.from) / span, 0.0, 1.0)
	handle.manual = maxf(handle.manual, k)
	# apply now: FX._process already ran this frame (autoloads update first)
	handle.mat.set_shader_parameter("progress", handle.manual)

# ------------------------------------------------------------------ ground effects
func _ground(pos: Vector3, mode: int, color: Color, dur: float, kind: String) -> Dictionary:
	var m := MeshInstance3D.new()
	m.mesh = _plane
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("color", color)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root().add_child(m)
	m.global_position = pos + Vector3(0, 0.03 + randf() * 0.01, 0)
	var d := {"node": m, "mat": mat, "t": 0.0, "dur": dur, "kind": kind}
	_grounds.append(d)
	return d

func shockwave(pos: Vector3, radius: float, color: Color, dur := 0.4) -> void:
	if _root() == null:
		return
	var d := _ground(pos, 2, color, dur, "wave")
	d.node.scale = Vector3(radius, 1, radius)

## Danger zone; returns a handle that can be cancelled.
func telegraph_circle(pos: Vector3, radius: float, dur: float, color := Color(1, 0.05, 0.1)) -> Dictionary:
	var d := _ground(pos, 0, color, dur, "tele")
	d.node.scale = Vector3(radius, 1, radius)
	return d

func telegraph_line(pos: Vector3, dir: Vector3, length: float, width: float, dur: float, color := Color(1, 0.05, 0.1)) -> Dictionary:
	var d := _ground(pos + dir * length * 0.5, 1, color, dur, "tele")
	d.node.basis = Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis.from_scale(Vector3(width * 0.5, 1, length * 0.5))
	return d

func portal(pos: Vector3, radius: float, dur: float, color := Color(0.9, 0.05, 0.2)) -> void:
	var d := _ground(pos, 3, color, dur, "portal")
	d.node.scale = Vector3(radius, 1, radius)

## True if `p` stands inside a danger zone that is about to go off.
func telegraph_threat(p: Vector3, min_progress := 0.65) -> bool:
	for g in _grounds:
		if g.kind != "tele" or not is_instance_valid(g.node):
			continue
		if g.t / g.dur < min_progress:
			continue
		var local: Vector3 = (g.node as Node3D).global_transform.affine_inverse() * p
		# plane mesh spans -1..1 in local x/z
		if g.mat.get_shader_parameter("mode") == 0:
			if Vector2(local.x, local.z).length() <= 1.05:
				return true
		elif absf(local.x) <= 1.1 and absf(local.z) <= 1.05:
			return true
	return false

func cancel(handle: Dictionary) -> void:
	if handle.is_empty():
		return
	handle.t = handle.dur
	handle.kind = "cancel"

func dash_streak(from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var len := dir.length()
	if len < 0.1:
		return
	var d := _ground(from, 4, Color(0.8, 0.05, 0.35), 0.32, "streak")
	d.node.global_position = from + dir * 0.5 + Vector3.UP * 0.05
	d.node.basis = Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis.from_scale(Vector3(0.6, 1, len * 0.5))

# ------------------------------------------------------------------ afterimages / fragments
func afterimage(rig: PlayerRig, xf: Transform3D) -> void:
	rig.spawn_afterimage(xf)

## "Dispersal stages": small spirit shards fly off and dissolve. They are
## drawn through the enemy type's MultiMesh.
func fragments(pos: Vector3, render_key: String, count: int, size: float) -> void:
	for i in count:
		var a := randf() * TAU
		var vel := Vector3(cos(a), randf_range(0.6, 1.6), sin(a)) * randf_range(2.5, 5.0)
		_frags.append({"key": render_key, "pos": pos + Vector3(cos(a), 0.3, sin(a)) * 0.3, "t": 0.0,
			"life": randf_range(0.45, 0.7), "vel": vel, "yaw": atan2(vel.x, vel.z),
			"scale": size * randf_range(0.28, 0.42), "phase": float(randi() % 16)})

func crescent_wave(owner_player: Node3D, pos: Vector3, dir: Vector3, damage: float, speed: float,
		life: float, width: float, edge: Color, core: Color) -> void:
	var w := CrescentWaveScript.new()
	_root().add_child(w)
	w.setup(owner_player, pos, dir, damage, speed, life, width, edge, core)

func screen_flash(c: Color) -> void:
	_flash_rect.color = c
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.35)

# ------------------------------------------------------------------ particles
func _make_particles(type: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.billboard_keep_scale = true
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = _soft_tex
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.no_depth_test = false
	var q := QuadMesh.new()
	q.material = dm
	p.draw_pass_1 = q
	p.process_material = pm
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 8, 12))
	pm.direction = Vector3(0, 0, 1)
	var ramp := Gradient.new()
	var size_curve := Curve.new()
	size_curve.add_point(Vector2(0, 1))
	size_curve.add_point(Vector2(1, 0))
	match type:
		"hit":
			p.amount = 16; p.lifetime = 0.32
			pm.spread = 55.0
			pm.initial_velocity_min = 5.0; pm.initial_velocity_max = 13.0
			pm.gravity = Vector3(0, -9, 0)
			pm.damping_min = 8.0; pm.damping_max = 14.0
			pm.scale_min = 0.08; pm.scale_max = 0.2
			ramp.set_color(0, Color(1, 0.75, 0.85)); ramp.set_color(1, Color(1, 0.02, 0.15, 0))
			q.size = Vector2(1, 1)
		"hit_player":
			p.amount = 20; p.lifetime = 0.4
			pm.spread = 180.0
			pm.initial_velocity_min = 3.0; pm.initial_velocity_max = 9.0
			pm.damping_min = 6.0; pm.damping_max = 10.0
			pm.scale_min = 0.1; pm.scale_max = 0.25
			ramp.set_color(0, Color(1, 1, 1)); ramp.set_color(1, Color(1, 0.1, 0.1, 0))
		"embers":
			p.amount = 36; p.lifetime = 1.1
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 80.0
			pm.initial_velocity_min = 1.5; pm.initial_velocity_max = 6.0
			pm.gravity = Vector3(0, 1.5, 0)
			pm.damping_min = 2.0; pm.damping_max = 4.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.6
			pm.scale_min = 0.06; pm.scale_max = 0.16
			ramp.set_color(0, Color(1, 0.5, 0.6)); ramp.set_color(1, Color(0.8, 0.0, 0.1, 0))
		"death_embers":
			p.amount = 18; p.lifetime = 0.9
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 70.0
			pm.initial_velocity_min = 1.0; pm.initial_velocity_max = 4.0
			pm.gravity = Vector3(0, 2.0, 0)
			pm.damping_min = 2.0; pm.damping_max = 3.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.4
			pm.scale_min = 0.05; pm.scale_max = 0.13
			ramp.set_color(0, Color(1, 0.3, 0.35)); ramp.set_color(1, Color(0.6, 0.0, 0.1, 0))
		"step":
			dm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			p.amount = 5; p.lifetime = 0.45
			pm.direction = Vector3(0, 0.4, 0)
			pm.spread = 180.0
			pm.flatness = 0.7
			pm.initial_velocity_min = 0.6; pm.initial_velocity_max = 1.4
			pm.damping_min = 3.0; pm.damping_max = 4.0
			pm.scale_min = 0.18; pm.scale_max = 0.32
			ramp.set_color(0, Color(0.22, 0.18, 0.3, 0.45)); ramp.set_color(1, Color(0.1, 0.08, 0.15, 0))
		"perfect":
			p.amount = 40; p.lifetime = 0.6
			pm.spread = 180.0
			pm.initial_velocity_min = 4.0; pm.initial_velocity_max = 9.0
			pm.damping_min = 6.0; pm.damping_max = 9.0
			pm.scale_min = 0.08; pm.scale_max = 0.2
			ramp.set_color(0, Color(0.8, 1.0, 1.0)); ramp.set_color(1, Color(0.3, 0.6, 1.0, 0))
		"smoke", "smoke_ring", "dust", "death":
			dm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			p.amount = 12; p.lifetime = 0.9
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 90.0
			pm.initial_velocity_min = 0.6; pm.initial_velocity_max = 2.5
			pm.gravity = Vector3(0, 0.8, 0)
			pm.damping_min = 1.5; pm.damping_max = 3.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.45
			pm.scale_min = 0.7; pm.scale_max = 1.4
			pm.angle_min = 0.0; pm.angle_max = 360.0
			size_curve = Curve.new()
			size_curve.add_point(Vector2(0, 0.4))
			size_curve.add_point(Vector2(1, 1.0))
			ramp.set_color(0, Color(0.02, 0.0, 0.03, 0.85)); ramp.set_color(1, Color(0.05, 0.0, 0.04, 0))
			if type == "smoke_ring":
				p.amount = 24
				pm.direction = Vector3(0, 0.15, 0)
				pm.spread = 180.0
				pm.flatness = 1.0
				pm.initial_velocity_min = 4.0; pm.initial_velocity_max = 7.0
				pm.damping_min = 5.0; pm.damping_max = 7.0
			elif type == "dust":
				p.amount = 8; p.lifetime = 0.5
				pm.direction = Vector3(0, 0.3, 1)
				pm.spread = 40.0
				pm.scale_min = 0.4; pm.scale_max = 0.8
				ramp.set_color(0, Color(0.2, 0.15, 0.28, 0.6)); ramp.set_color(1, Color(0.1, 0.05, 0.15, 0))
			elif type == "death":
				p.amount = 22
				pm.initial_velocity_max = 4.0
				pm.scale_max = 1.8
		"charge":
			p.amount = 6; p.lifetime = 0.35
			pm.spread = 180.0
			pm.initial_velocity_min = 0.5; pm.initial_velocity_max = 1.5
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.5
			pm.scale_min = 0.08; pm.scale_max = 0.18
			ramp.set_color(0, Color(0.8, 0.5, 1)); ramp.set_color(1, Color(0.4, 0.8, 1, 0))
		"soul_pop":
			p.amount = 8; p.lifetime = 0.35
			pm.spread = 180.0
			pm.initial_velocity_min = 1.5; pm.initial_velocity_max = 4.0
			pm.damping_min = 6.0; pm.damping_max = 8.0
			pm.scale_min = 0.06; pm.scale_max = 0.14
			ramp.set_color(0, Color(0.7, 0.95, 1)); ramp.set_color(1, Color(0.5, 0.3, 1, 0))
		"souls_swirl":
			p.amount = 48; p.lifetime = 0.9
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 30.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3(0, 1, 0)
			pm.emission_ring_radius = 2.5
			pm.emission_ring_inner_radius = 2.0
			pm.emission_ring_height = 0.2
			pm.initial_velocity_min = 2.0; pm.initial_velocity_max = 5.0
			pm.radial_accel_min = -6.0; pm.radial_accel_max = -4.0
			pm.tangential_accel_min = 6.0; pm.tangential_accel_max = 9.0
			pm.scale_min = 0.08; pm.scale_max = 0.18
			ramp.set_color(0, Color(0.6, 0.9, 1)); ramp.set_color(1, Color(0.7, 0.2, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	var ct := CurveTexture.new()
	ct.curve = size_curve
	pm.scale_curve = ct
	return p

func burst(type: String, pos: Vector3, dir := Vector3.UP) -> void:
	var root := _root()
	if root == null or not particles_enabled:
		return
	if not _pools.has(type):
		var count := 10 if type in ["hit", "smoke", "death", "death_embers", "soul_pop"] else (6 if type == "step" else 4)
		var nodes := []
		for i in count:
			var p := _make_particles(type)
			root.add_child(p)
			nodes.append(p)
		_pools[type] = {"nodes": nodes, "i": 0}
	var pool: Dictionary = _pools[type]
	var node: GPUParticles3D = pool.nodes[pool.i]
	pool.i = (pool.i + 1) % pool.nodes.size()
	if not is_instance_valid(node):
		_pools.erase(type)
		return
	var b := Basis.IDENTITY
	if dir.length() > 0.01 and absf(dir.normalized().dot(Vector3.UP)) < 0.99:
		b = Basis.looking_at(-dir.normalized(), Vector3.UP)
	node.global_transform = Transform3D(b, pos)
	node.amount_ratio = clampf(quality, 0.3, 1.0)
	node.restart()

## Draw every effect once, hidden under the floor, so the browser compiles all
## shader variants on the title screen instead of stuttering mid-fight.
func warmup(center: Vector3) -> void:
	var under := center + Vector3(0, -3.0, 0)
	for t in ["hit", "hit_player", "embers", "death_embers", "smoke", "smoke_ring", "dust", "death", "charge", "soul_pop", "souls_swirl", "step", "perfect"]:
		burst(t, under, Vector3.UP)
	var xf := Transform3D(Basis.IDENTITY, under)
	slash(xf, 0.0, 90.0, 0.5, 2.0, 0.05, 0.05, 0.5, Color.RED, Color.WHITE)
	shockwave(under, 1.0, Color.RED, 0.1)
	telegraph_circle(under, 1.0, 0.1)
	telegraph_line(under, Vector3.FORWARD, 2.0, 1.0, 0.1)
	portal(under, 1.0, 0.1)
	dash_streak(under, under + Vector3.FORWARD)

# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	for i in range(_slashes.size() - 1, -1, -1):
		var s: Dictionary = _slashes[i]
		var node: MeshInstance3D = s.node
		if not is_instance_valid(node):
			_slashes.remove_at(i)
			continue
		s.t += delta
		var t: float = s.t
		var prog: float
		var fade := 1.0
		if t < s.active:
			prog = t / s.active
			if s.eased:
				prog = Player.smootherstep(prog)
			if s.manual >= 0.0:
				prog = s.manual
		elif s.manual >= 0.0:
			var k2: float = (t - s.active) / s.life
			prog = s.manual + k2 * s.trail
			fade = 1.0 - k2 * k2
		else:
			var k: float = (t - s.active) / s.life
			prog = 1.0 + k * s.trail
			fade = 1.0 - k * k
		s.mat.set_shader_parameter("progress", prog)
		s.mat.set_shader_parameter("fade", fade)
		if s.follow and is_instance_valid(s.follow):
			node.global_position = s.follow.global_position + s.off
		if t >= s.active + s.life:
			node.queue_free()
			_slashes.remove_at(i)
	for i in range(_grounds.size() - 1, -1, -1):
		var g: Dictionary = _grounds[i]
		if not is_instance_valid(g.node):
			_grounds.remove_at(i)
			continue
		g.t += delta
		var k: float = clampf(g.t / g.dur, 0.0, 1.0)
		match g.kind:
			"wave":
				g.mat.set_shader_parameter("fill", 1.0 - pow(1.0 - k, 2.5))
				g.mat.set_shader_parameter("fade", (1.0 - k) * 1.8)
			"tele":
				g.mat.set_shader_parameter("fill", k)
				g.mat.set_shader_parameter("fade", 0.6 + 0.4 * sin(g.t * 18.0) * k)
			"portal":
				g.mat.set_shader_parameter("fill", sin(k * PI))
			"streak":
				g.mat.set_shader_parameter("fade", (1.0 - k) * 1.5)
			"cancel":
				pass
		if g.t >= g.dur:
			g.node.queue_free()
			_grounds.remove_at(i)
	for i in range(_ghosts.size() - 1, -1, -1):
		var gh: Dictionary = _ghosts[i]
		gh.t += delta
		var node3: Node3D = gh.node
		if not is_instance_valid(node3):
			_ghosts.remove_at(i)
			continue
		var a: float = 1.0 - gh.t / gh.life
		((node3.get_child(0) as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("alpha", a * 0.8)
		if gh.t >= gh.life:
			node3.queue_free()
			_ghosts.remove_at(i)
	for i in range(_frags.size() - 1, -1, -1):
		var f: Dictionary = _frags[i]
		f.t += delta
		f.vel *= exp(-3.0 * delta)
		f.vel.y += 1.0 * delta
		f.pos += f.vel * delta
		if f.t >= f.life or Game.enemies == null:
			_frags.remove_at(i)
			continue
		var xf := Transform3D(Basis(Vector3.UP, f.yaw).scaled(Vector3.ONE * f.scale), f.pos)
		var dis: float = clampf(f.t / f.life, 0.0, 1.0)
		Game.enemies.draw(f.key, xf, Color(maxf(0.0, 0.6 - f.t * 3.0), dis * 0.9, 0.0, f.phase * 8.0 + 3.5))
