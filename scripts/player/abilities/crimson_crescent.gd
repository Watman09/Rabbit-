## E — hurl a piercing crescent of crimson energy.
class_name CrimsonCrescent
extends Ability

var _thrown := false
var _dir := Vector3.FORWARD
var _data: AttackData

func _init(p: Player) -> void:
	super(p)
	display_name = "Багровый серп"
	icon = "crescent"
	cooldown = 3.2
	_data = Moveset.crescent_throw()

func _begin() -> void:
	_thrown = false
	_dir = player.input.aim
	player.facing = _dir
	player.velocity = Vector3.ZERO

func _update(delta: float) -> bool:
	var a := _data
	var k := clampf((t - a.windup) / a.active, 0.0, 1.0)
	var sweep := lerpf(a.sweep_from + 20.0, a.sweep_to, 1.0 - pow(1.0 - k, 2.0))
	var pose := PlayerRig.attack_pose(a, sweep, 0.25 * k)
	if t < a.windup:
		player.rig.blend_to(pose, delta, 30.0)
	else:
		player.rig.set_pose(pose)
	player.rig.scythe_glow = 1.0
	if not _thrown and t >= a.windup + a.active * 0.5:
		_thrown = true
		Sfx.play("ability_crescent", 1.0)
		FX.crescent_wave(player, player.position + Vector3.UP * 0.95 + _dir * 0.8, _dir, 26.0, 24.0, 0.72, 4.0,
			Color(1.0, 0.04, 0.2), Color(1.0, 0.75, 0.85))
		player.position -= _dir * 0.25
		if Game.camera:
			Game.camera.add_trauma(0.25)
	return t >= a.total_time()
