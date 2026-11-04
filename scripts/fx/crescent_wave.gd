## Flying crescent projectile (E ability, fully charged heavy). Pierces and
## hits each spirit once.
extends Node3D

var player: Node3D
var dir := Vector3.FORWARD
var damage := 20.0
var speed := 20.0
var life := 0.7
var width := 3.5
var t := 0.0
var hit := {}
var mat: ShaderMaterial
var mesh_i: MeshInstance3D

func setup(p: Node3D, pos: Vector3, d: Vector3, dmg: float, spd: float, lf: float, w: float, edge: Color, core: Color) -> void:
	player = p
	dir = d.normalized()
	damage = dmg
	speed = spd
	life = lf
	width = w
	global_position = pos
	basis = Basis(Vector3.UP, atan2(dir.x, dir.z))
	mesh_i = MeshInstance3D.new()
	var half := rad_to_deg(asin(clampf(width * 0.5 / 2.2, 0.0, 1.0)))
	mesh_i.mesh = FX._arc_mesh(-half - 10.0, half + 10.0, 1.6, 2.4)
	mat = FX.make_slash_material(edge, core, 3.0, 1.0)
	mat.set_shader_parameter("symmetric", true)
	mat.set_shader_parameter("progress", 1.0)
	mesh_i.material_override = mat
	mesh_i.position = Vector3(0, 0, -2.0)
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_i)
	var g := FX.make_glow_sprite(Color(edge.r, edge.g, edge.b, 0.5), 2.2)
	add_child(g)

func _process(delta: float) -> void:
	t += delta
	var step := dir * speed * delta
	global_position += step
	var k := t / life
	mat.set_shader_parameter("fade", 1.0 - k * k)
	mesh_i.scale = Vector3.ONE * (0.8 + k * 0.5)
	if Game.enemies and is_instance_valid(player):
		for e in Game.enemies.query_radius(global_position, width + 1.0):
			if hit.has(e.get_instance_id()):
				continue
			var rel: Vector3 = e.position - global_position
			rel.y = 0
			var along := rel.dot(dir)
			var lateral := absf(rel.dot(Vector3(dir.z, 0, -dir.x)))
			if along > -1.0 and along < 1.0 + speed * delta and lateral < width * 0.5 + e.radius:
				hit[e.get_instance_id()] = true
				var info := DamageInfo.make(damage, global_position - dir * 2.0, 9.0, 2.0, "crescent")
				info.color = Color(1, 0.1, 0.3)
				player.deal_damage(e, info, 0.025, 0.15)
	if Game.projectiles:
		Game.projectiles.cut_circle(global_position, width * 0.5)
	if t >= life or Game.is_blocked(global_position, 0.3):
		FX.burst("death_embers", global_position, Vector3.UP)
		queue_free()
