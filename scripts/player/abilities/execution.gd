## Execution: press attack next to a stunned spirit (elites and colossi are
## stunned at low health). The Reaper blinks to it, rises and splits it in
## two. Invulnerable, slowed time, bonus souls and healing.
class_name Execution
extends Ability

const BLINK := 0.16
const STRIKE := 0.36
const END := 0.7

var target: Enemy
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _done := false
var _ghost_t := 0.0

func _init(p: Player) -> void:
	super(p)
	display_name = "ab_execution"
	icon = "heavy"
	cooldown = 0.0
	invulnerable = true
	dash_cancelable = false
	animates_body = true

func _begin() -> void:
	_done = false
	_from = player.position
	var d := target.position - player.position
	d.y = 0
	var dir := d.normalized() if d.length() > 0.01 else player.facing
	_to = target.position - dir * (target.radius + 0.9)
	player.facing = dir
	target.hold_for_execution()
	Game.slowmo(0.5, 0.35)
	Sfx.play("dash", 0.8)
	Sfx.play("charge", 1.3, -4.0)
	FX.dash_streak(_from, _to)

func _update(delta: float) -> bool:
	var p := player
	p.velocity = Vector3.ZERO
	var ph := 0 if t < BLINK else (1 if t < STRIKE else 2)
	p.rig.attack_clip("Heavy", ph, [BLINK, STRIKE - BLINK, END - STRIKE][ph], t <= delta)
	if t < BLINK:
		var k := Player.smootherstep(t / BLINK)
		p.position = _from.lerp(_to, k)
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.03
			FX.afterimage(p.rig, p.global_transform)
		var pose := PlayerRig.ScythePose.make({"tilt": 90.0, "height": 1.1, "yaw": -165.0, "reach": 0.7,
			"pitch": 95.0, "lean": -0.2, "sscale": 1.7, "choke": 0.62})
		p.rig.blend_to(pose, delta, 20.0)
		p.rig.scythe_glow = 1.5
	elif t < STRIKE:
		var k := Player.smootherstep((t - BLINK) / (STRIKE - BLINK))
		var pose := PlayerRig.ScythePose.make({"tilt": 90.0, "height": 1.1, "yaw": lerpf(-165.0, 70.0, k), "reach": 0.7,
			"pitch": 95.0, "lean": lerpf(-0.2, 0.4, k), "sscale": 1.7, "choke": 0.62, "bob": sin(k * PI) * 0.5})
		p.rig.set_pose(pose)
	elif not _done:
		_done = true
		_strike()
	else:
		p.rig.blend_to(PlayerRig.POSE_READY.copy(), delta, 7.0)
		p.rig.scythe_glow = move_toward(p.rig.scythe_glow, 0.0, delta * 3.0)
	return t >= END

func _strike() -> void:
	var p := player
	var xf := Transform3D(Basis(Vector3.UP, atan2(p.facing.x, p.facing.z)), p.position)
	xf = xf * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(90.0)), Vector3(0, 1.1, 0))
	FX.slash(xf, -170.0, 80.0, 0.6, 4.2, 0.08, 0.45, 1.0, Color(0.7, 0.15, 1.0), Color(0.85, 1.0, 1.0), 2.6)
	FX.shockwave(target.position, 5.0, Color(0.7, 0.2, 1.0), 0.5)
	FX.shockwave(target.position, 3.0, Color(1.0, 0.1, 0.4), 0.35)
	FX.burst("embers", target.position + Vector3.UP, Vector3.UP)
	FX.burst("perfect", target.position + Vector3.UP, Vector3.UP)
	FX.screen_flash(Color(0.75, 0.3, 1.0, 0.3))
	Sfx.play("execute", 1.0)
	Sfx.play("slam", 0.9, -4.0)
	Game.hitstop(0.14, 0.05)
	if Game.camera:
		Game.camera.add_trauma(0.9)
		Game.camera.punch_fov(-6.0)
	if is_instance_valid(target) and target.alive:
		var bonus := 2 if p.mods.executioner else 1
		target.soul_value *= 1 + bonus
		var info := DamageInfo.make(target.hp + 1.0, p.position, 18.0, 99.0, "execution")
		info.launch = true
		p.deal_damage(target, info, 0.0, 0.0)
	# the shockwave also hurts everything around
	for e in Game.enemies.query_radius(target.position, 3.5):
		if e.alive and e.position.distance_to(target.position) - e.radius < 3.0:
			p.deal_damage(e, DamageInfo.make(30.0, target.position, 12.0, 3.0, "execution_wave"), 0.0, 0.0)
	p.heal(25.0 if p.mods.executioner else 12.0)
	Events.popup.emit(Loc.t("p_execute"), target.position + Vector3.UP * 2.6, Color(0.8, 0.5, 1.0), 1.4)
	Game.stats.executions = Game.stats.get("executions", 0) + 1
