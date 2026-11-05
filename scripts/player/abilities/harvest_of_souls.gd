## R — ultimate. Spend a full soul meter: leap, then slam the scythe down,
## reaping everything nearby. Executes weakened spirits and heals.
class_name HarvestOfSouls
extends Ability

const RADIUS := 8.5
const DAMAGE := 95.0
const EXECUTE_RATIO := 0.35
const RISE := 0.42
const SLAM := 0.52
const END := 0.95

var _slammed := false

func _init(p: Player) -> void:
	super(p)
	display_name = "ab_harvest"
	icon = "harvest"
	cooldown = 1.0
	soul_cost = 100.0
	invulnerable = true
	dash_cancelable = false
	animates_body = true

func _begin() -> void:
	_slammed = false
	Sfx.play("ability_harvest", 1.0)
	Game.slowmo(0.45, 0.45)
	FX.burst("souls_swirl", player.position + Vector3.UP, Vector3.UP)

func _update(delta: float) -> bool:
	var p := player
	p.velocity = Vector3.ZERO
	# Heavy clip phases: crouch+spring (to the air key), drop, slam recovery
	var ph := 0 if t < RISE else (1 if t < SLAM else 2)
	p.rig.attack_clip("Heavy", ph, [RISE, SLAM - RISE, END - SLAM][ph], t <= delta)
	if t < RISE:
		var k := t / RISE
		var pose := PlayerRig.ScythePose.make({"tilt": 90.0, "height": 1.1, "yaw": -170.0, "reach": 0.8, "sscale": 1.6, "choke": 0.62,
			"pitch": 95.0, "lean": -0.25, "bob": sin(k * PI * 0.5) * 1.6, "squash": 1.08})
		p.rig.blend_to(pose, delta, 14.0)
		p.rig.scythe_glow = k * 1.5
	elif t < SLAM:
		var k := (t - RISE) / (SLAM - RISE)
		var pose := PlayerRig.ScythePose.make({"tilt": 90.0, "height": 1.0, "yaw": lerpf(-170.0, 60.0, k * k), "reach": 0.8, "sscale": 1.6, "choke": 0.62,
			"pitch": 95.0, "lean": 0.35, "bob": (1.0 - k * k) * 1.6, "squash": 0.95})
		p.rig.set_pose(pose)
	elif not _slammed:
		_slammed = true
		_slam()
	else:
		var k := (t - SLAM) / (END - SLAM)
		p.rig.blend_to(PlayerRig.POSE_READY.copy(), delta, 6.0)
		p.rig.scythe_glow = 1.5 * (1.0 - k)
	return t >= END

func _slam() -> void:
	var p := player
	Sfx.play("slam", 1.0)
	Game.hitstop(0.12, 0.03)
	if Game.camera:
		Game.camera.add_trauma(1.0)
		Game.camera.punch_fov(-7.0)
	FX.screen_flash(Color(0.9, 0.2, 1.0, 0.35))
	FX.shockwave(p.position, RADIUS * 1.15, Color(1.0, 0.05, 0.25), 0.55)
	FX.shockwave(p.position, RADIUS * 0.8, Color(0.7, 0.25, 1.0), 0.4)
	FX.shockwave(p.position, RADIUS * 1.5, Color(0.3, 0.7, 1.0), 0.8)
	FX.burst("embers", p.position + Vector3.UP * 0.3, Vector3.UP)
	FX.burst("smoke_ring", p.position + Vector3.UP * 0.1, Vector3.UP)
	# two counter-rotating rings of reaping light
	var xf := Transform3D(Basis(Vector3.UP, randf() * TAU), p.position + Vector3.UP * 0.4)
	FX.slash(xf, 0.0, 360.0, 1.5, RADIUS, 0.2, 0.5, 1.0, Color(1, 0.05, 0.3), Color(1, 0.85, 1), 2.2, null)
	FX.slash(xf, 180.0, -180.0, 1.0, RADIUS * 0.65, 0.16, 0.45, 1.0, Color(0.7, 0.2, 1.0), Color(0.8, 0.95, 1), 2.0, null)
	for e in Game.enemies.query_radius(p.position, RADIUS + 1.5):
		var dist: float = e.position.distance_to(p.position) - e.radius
		if dist > RADIUS:
			continue
		var dmg := DAMAGE * (1.0 - 0.4 * dist / RADIUS)
		if not e.is_boss and e.hp - dmg <= e.max_hp * EXECUTE_RATIO:
			dmg = e.hp + 1.0
		var info := DamageInfo.make(dmg, p.position, 16.0, 10.0, "harvest")
		info.launch = true
		p.deal_damage(e, info, 0.0, 0.0)
	p.heal(p.max_hp * 0.25)
