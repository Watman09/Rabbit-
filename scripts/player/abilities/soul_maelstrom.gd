## Q — spin into a scythe tornado that drags spirits inward and shreds them.
class_name SoulMaelstrom
extends Ability

const DURATION := 1.45
const TICK := 0.13
const RADIUS := 3.7
const DAMAGE := 8.0

var _tick_t := 0.0
var _spin := 0.0
var _hits := 0

func _init(p: Player) -> void:
	super(p)
	display_name = "Вихрь душ"
	icon = "whirl"
	cooldown = 7.0

func _begin() -> void:
	_tick_t = 0.0
	_spin = player.rig.pose.body_yaw
	_hits = 0
	Sfx.play("ability_whirl", 1.0)
	FX.shockwave(player.position, RADIUS, Color(0.9, 0.1, 0.4), 0.35)

func _update(delta: float) -> bool:
	var p := player
	p.velocity = p.velocity.move_toward(p.input.move * p.move_speed * 0.72, p.accel * delta)
	p.position += p.velocity * delta
	var speed := 1350.0 if t < DURATION - 0.2 else 700.0
	_spin -= speed * delta
	var pose := PlayerRig.ScythePose.make({"tilt": 6.0 * sin(t * 9.0), "height": 0.95, "yaw": _spin + 90.0,
		"reach": 0.8, "sscale": 1.6, "choke": 0.62, "pitch": 92.0, "body_yaw": _spin, "lean": 0.15, "squash": 1.03})
	p.rig.set_pose(pose)
	p.rig.scythe_glow = 1.0
	_tick_t -= delta
	if _tick_t <= 0.0 and t < DURATION - 0.1:
		_tick_t = TICK
		_hits += 1
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(_spin)), p.position)
		xf = xf * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(randf_range(-10, 10))), Vector3(0, 0.95, 0))
		var col := Color(1.0, 0.05, 0.25) if _hits % 2 == 0 else Color(0.75, 0.15, 1.0)
		FX.slash(xf, 0.0, -300.0, 0.4, RADIUS, 0.12, 0.22, 0.7, col, Color(1, 0.8, 0.95), 2.2, p)
		if _hits % 2 == 0:
			Sfx.play("swing", randf_range(1.1, 1.3), -6.0)
		for e in Game.enemies.query_radius(p.position, RADIUS + 1.0):
			var d: Vector3 = e.position - p.position
			d.y = 0
			if d.length() - e.radius > RADIUS:
				continue
			# origin beyond the enemy -> knockback pulls it toward the player
			var origin: Vector3 = e.position + d.normalized() * 2.0
			var info := DamageInfo.make(DAMAGE, origin, 2.5 if d.length() > 1.4 else 0.0, 0.6, "maelstrom")
			info.color = col
			p.deal_damage(e, info, 0.02, 0.12)
		if Game.projectiles:
			Game.projectiles.cut_sweep(p.position, Vector3(0, 0, 1), 0.0, 360.0, RADIUS)
	if t >= DURATION:
		# final outward blast
		for e in Game.enemies.query_radius(p.position, RADIUS + 1.0):
			if e.position.distance_to(p.position) - e.radius <= RADIUS:
				var info := DamageInfo.make(DAMAGE * 2.0, p.position, 12.0, 3.0, "maelstrom_end")
				info.launch = true
				p.deal_damage(e, info, 0.06, 0.4)
		FX.shockwave(p.position, RADIUS * 1.3, Color(1, 0.1, 0.3), 0.4)
		FX.burst("embers", p.position + Vector3.UP * 0.5, Vector3.UP)
		Sfx.play("heavy", 1.2, -4.0)
		return true
	return false
