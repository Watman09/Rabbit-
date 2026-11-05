## Standard melee spirit: approaches, raises its claws (telegraph), slashes.
class_name Wraith
extends Enemy

var mode := "chase"
var t := 0.0
var cd := 0.0
var weave := 0.0
var strike_dir := Vector3.ZERO
var reach := 2.2
var windup_time := 0.6

func _init() -> void:
	kind = "wraith"
	max_hp = 34.0; hp = max_hp
	speed = 3.6; radius = 0.55; damage = 11.0
	poise = 1.0; soul_value = 2; hover = 0.2
	weave = randf() * 10.0

func _think(delta: float) -> void:
	t += delta
	cd -= delta
	var d := to_player()
	var dist := d.length()
	var dn := d / maxf(dist, 0.01)
	match mode:
		"chase":
			attack_amount = move_toward(attack_amount, 0.0, delta * 3.0)
			var side := Vector3(dn.z, 0, -dn.x) * sin(state_t * 1.3 + weave) * 0.4
			move_dir = (dn + side).normalized()
			move_speed = speed
			if dist < reach * visual_scale and cd <= 0.0 and player_alive():
				mode = "windup"; t = 0.0
				strike_dir = dn
				_tele = FX.telegraph_circle(position + dn * reach * 0.5 * visual_scale, reach * 0.65 * visual_scale, windup_time, Color(0.7, 0.03, 0.08))
				Sfx.play("telegraph", randf_range(0.9, 1.1), -10.0)
		"windup":
			move_dir = dn
			move_speed = 0.4
			strike_dir = strike_dir.slerp(dn, delta * 2.0)
			attack_amount = ease(t / windup_time, 0.5) * 0.8
			if t >= windup_time:
				mode = "strike"; t = 0.0
				_tele = {}
		"strike":
			attack_amount = minf(1.0, 0.8 + t * 6.0)
			move_dir = strike_dir
			move_speed = 7.0
			if t >= 0.05 and t - delta < 0.05:
				melee_check(reach * visual_scale, 110.0, damage)
				Sfx.play("claw", randf_range(0.9, 1.1), -6.0)
			if t >= 0.16:
				mode = "recover"; t = 0.0
		"recover":
			move_speed = 0.5
			attack_amount = move_toward(attack_amount, 0.0, delta * 2.5)
			if t >= 0.7:
				mode = "chase"; t = 0.0
				cd = randf_range(0.6, 1.6)

func threatens(p: Vector3) -> bool:
	var d := position.distance_to(p)
	return ((mode == "windup" and t > windup_time - 0.3) or mode == "strike") and d < reach * visual_scale + 0.8

func _on_interrupt() -> void:
	super()
	mode = "recover"; t = 0.0
