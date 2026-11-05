## Builds the dungeon arena procedurally: floor, walls, pillars, props,
## braziers and moonlight. Registers circular obstacles with Game.
class_name Arena
extends Node3D

const FLOOR_SHADER := preload("res://assets/shaders/floor.gdshader")
const STONE_SHADER := preload("res://assets/shaders/stone.gdshader")

var _stone: ShaderMaterial
var _pillar_mat: ShaderMaterial
var _wood: ShaderMaterial
var _flames: Array = []

func _ready() -> void:
	var half := Game.arena_half
	_stone = ShaderMaterial.new()
	_stone.shader = STONE_SHADER
	_pillar_mat = _stone.duplicate()
	_pillar_mat.set_shader_parameter("see_through", true)
	_wood = ShaderMaterial.new()
	_wood.shader = STONE_SHADER
	_wood.set_shader_parameter("planks", true)
	_wood.set_shader_parameter("base", Color(0.2, 0.13, 0.09))
	_wood.set_shader_parameter("dark", Color(0.05, 0.03, 0.02))
	_wood.set_shader_parameter("scale", 2.0)

	# floor
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(half.x * 2.0 + 12.0, half.y * 2.0 + 12.0)
	plane.subdivide_width = 0
	fm.mesh = plane
	var fmat := ShaderMaterial.new()
	fmat.shader = FLOOR_SHADER
	fmat.set_shader_parameter("arena_half", half)
	fm.material_override = fmat
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fm)

	# walls: tall at the back, low ledge at the front so the camera sees in
	_wall(Vector3(0, 0, -half.y - 0.75), Vector3(half.x * 2.0 + 3.0, 4.5, 1.5))
	_wall(Vector3(-half.x - 0.75, 0, 0), Vector3(1.5, 2.6, half.y * 2.0))
	_wall(Vector3(half.x + 0.75, 0, 0), Vector3(1.5, 2.6, half.y * 2.0))
	_wall(Vector3(0, 0, half.y + 0.75), Vector3(half.x * 2.0 + 3.0, 0.6, 1.5))
	# wall buttresses on the back wall
	for x in range(-16, 17, 8):
		_box(Vector3(x, 0, -half.y + 0.2), Vector3(1.4, 5.0, 1.2), _stone)

	# pillars (tactical cover)
	for p in [Vector2(-8, -7), Vector2(8, -7), Vector2(-8, 7), Vector2(8, 7)]:
		_pillar(Vector3(p.x, 0, p.y))

	# props along the walls
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 22:
		var side := i % 4
		var t := rng.randf_range(-0.9, 0.9)
		var pos: Vector3
		match side:
			0: pos = Vector3(t * half.x, 0, -half.y + 1.2)
			1: pos = Vector3(-half.x + 1.1, 0, t * half.y)
			2: pos = Vector3(half.x - 1.1, 0, t * half.y)
			3: pos = Vector3(t * half.x, 0, half.y - 1.0)
		if rng.randf() < 0.55:
			var s := rng.randf_range(0.8, 1.3)
			var b := _box(pos, Vector3(s, s, s), _wood)
			b.rotation.y = rng.randf() * PI
			Game.obstacles.append(Vector3(pos.x, pos.z, s * 0.6))
			if rng.randf() < 0.4:
				var b2 := _box(pos + Vector3(0, s, 0), Vector3(s * 0.7, s * 0.7, s * 0.7), _wood)
				b2.rotation.y = rng.randf() * PI
		else:
			_barrel(pos)

	# braziers with cold blue flame in the corners
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_brazier(Vector3(c.x * (half.x - 2.5), 0, c.y * (half.y - 2.5)))

	# drifting ambient embers
	var amb := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half.x, 0.5, half.y)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.1, 0.15, 0)
	pm.scale_min = 0.03
	pm.scale_max = 0.07
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.1, 0.25, 0))
	ramp.add_point(0.3, Color(0.9, 0.15, 0.35, 0.8))
	ramp.set_color(1, Color(0.3, 0.4, 1.0, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	amb.process_material = pm
	var dq := QuadMesh.new()
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.billboard_keep_scale = true
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_texture = FX._soft_tex
	dq.material = dm
	amb.draw_pass_1 = dq
	amb.amount = 90
	amb.lifetime = 7.0
	amb.preprocess = 7.0
	amb.visibility_aabb = AABB(Vector3(-half.x, -1, -half.y), Vector3(half.x * 2, 8, half.y * 2))
	amb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(amb)

func _process(_delta: float) -> void:
	if Game.player:
		_pillar_mat.set_shader_parameter("player_pos", Game.player.global_position)
	var t := Time.get_ticks_msec() * 0.001
	for i in _flames.size():
		var l: OmniLight3D = _flames[i]
		l.light_energy = 2.2 + sin(t * 7.0 + i * 2.0) * 0.25 + sin(t * 13.0 + i) * 0.15

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos + Vector3(0, size.y * 0.5, 0)
	add_child(m)
	return m

func _wall(pos: Vector3, size: Vector3) -> void:
	_box(pos, size, _stone)

func _pillar(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.75
	c.bottom_radius = 0.9
	c.height = 2.4
	c.radial_segments = 10
	m.mesh = c
	m.material_override = _pillar_mat
	m.position = pos + Vector3(0, 1.2, 0)
	add_child(m)
	var base := _box(pos, Vector3(2.1, 0.45, 2.1), _stone)
	base.rotation.y = PI * 0.25
	var cap := _box(pos + Vector3(0, 2.3, 0), Vector3(1.9, 0.35, 1.9), _pillar_mat)
	cap.rotation.y = PI * 0.25
	Game.obstacles.append(Vector3(pos.x, pos.z, 1.05))
	# faint red rune ring at the base
	var ring := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.2, 4.2)
	ring.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/ground_fx.gdshader")
	mat.set_shader_parameter("mode", 2)
	mat.set_shader_parameter("fill", 0.75)
	mat.set_shader_parameter("thickness", 0.03)
	mat.set_shader_parameter("fade", 0.3)
	mat.set_shader_parameter("color", Color(0.7, 0.03, 0.12))
	ring.material_override = mat
	ring.position = pos + Vector3(0, 0.03, 0)
	add_child(ring)

func _barrel(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.42
	c.bottom_radius = 0.42
	c.height = 1.0
	c.radial_segments = 10
	m.mesh = c
	m.material_override = _wood
	m.position = pos + Vector3(0, 0.5, 0)
	add_child(m)
	Game.obstacles.append(Vector3(pos.x, pos.z, 0.45))

func _brazier(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.55
	c.bottom_radius = 0.25
	c.height = 1.1
	c.radial_segments = 8
	m.mesh = c
	m.material_override = _stone
	m.position = pos + Vector3(0, 0.55, 0)
	add_child(m)
	Game.obstacles.append(Vector3(pos.x, pos.z, 0.6))
	var flame := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 1.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.scale_min = 0.3
	pm.scale_max = 0.5
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1)); sc.add_point(Vector2(1, 0))
	var sct := CurveTexture.new(); sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.4, 0.6, 1.0, 0.8))
	ramp.add_point(0.35, Color(0.15, 0.35, 1.0, 0.6))
	ramp.set_color(1, Color(0.3, 0.1, 0.8, 0))
	var rt := GradientTexture1D.new(); rt.gradient = ramp
	pm.color_ramp = rt
	flame.process_material = pm
	var q := QuadMesh.new()
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.billboard_keep_scale = true
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_texture = FX._soft_tex
	q.material = dm
	flame.draw_pass_1 = q
	flame.amount = 24
	flame.lifetime = 0.8
	flame.position = pos + Vector3(0, 1.15, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)
	var l := OmniLight3D.new()
	l.light_color = Color(0.35, 0.55, 1.0)
	l.omni_range = 9.0
	l.light_energy = 2.2
	l.position = pos + Vector3(0, 1.8, 0)
	add_child(l)
	_flames.append(l)
