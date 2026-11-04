## Heavy spirit: slow, tanky, resists knockback. Telegraphed ground slam and
## a long charge. Only heavy hits stagger it.
class_name Brute
extends Enemy

var mode := "chase"
var t := 0.0
var slam_cd := 1.0
var charge_cd := 3.0
var charge_dir := Vector3.ZERO
var did_hit := false
const SLAM_R := 3.2

func _init() -> void:
	kind = "brute"
	max_hp = 160.0; hp = max_hp
	speed = 2.4; radius = 0.95; damage = 22.0
	poise = 3.0; knock_resist = 0.8; soul_value = 6; hover = 0.05
	visual_scale = 1.25
	tint = Color(1.0, 0.12, 0.08, 1.2)

func _stagger_time() -> float:
	return 0.6

func _think(delta: float) -> void:
	t += delta
	slam_cd -= delta
	charge_cd -= delta
	var d := to_player()
	var dist := d.length()
	var dn := d / maxf(dist, 0.01)
	match mode:
		"chase":
			attack_amount = move_toward(attack_amount, 0.0, delta * 2.0)
			move_dir = dn
			move_speed = speed
			if not player_alive():
				return
			if dist < SLAM_R * 0.9 and slam_cd <= 0.0:
				mode = "slam_windup"; t = 0.0
				_tele = FX.telegraph_circle(position, SLAM_R, 0.85)
				Sfx.play("telegraph", 0.6, -4.0)
			elif dist > 5.0 and dist < 13.0 and charge_cd <= 0.0:
				mode = "charge_windup"; t = 0.0
				charge_dir = dn
				_tele = FX.telegraph_line(position, dn, 13.0, radius * 2.2, 0.9)
				Sfx.play("roar_small", 1.0, -4.0)
		"slam_windup":
			move_speed = 0.0
			attack_amount = ease(t / 0.85, 0.4)
			vis_y += t * 0.3
			if t >= 0.85:
				_tele = {}
				FX.shockwave(position, SLAM_R * 1.2, Color(1, 0.1, 0.1), 0.4)
				FX.burst("smoke_ring", position + Vector3.UP * 0.1, Vector3.UP)
				Sfx.play("slam", 0.8, -2.0)
				if Game.camera:
					Game.camera.add_trauma(0.35)
				if player_alive() and to_player().length() < SLAM_R + Game.player.radius:
					Game.player.take_damage(damage, position)
				mode = "recover"; t = 0.0
				slam_cd = randf_range(2.5, 3.5)
		"charge_windup":
			move_speed = 0.0
			move_dir = charge_dir
			attack_amount = 0.5 + sin(t * 25.0) * 0.1
			if t >= 0.9:
				_tele = {}
				mode = "charging"; t = 0.0
				did_hit = false
		"charging":
			move_dir = charge_dir
			move_speed = 15.0
			_vel = charge_dir * 15.0
			attack_amount = 1.0
			if not did_hit and dist < radius + Game.player.radius + 0.3:
				did_hit = Game.player.take_damage(damage, position)
			if int(t * 20.0) != int((t - delta) * 20.0):
				FX.burst("dust", position + Vector3.UP * 0.3, -charge_dir)
			if t >= 0.85 or Game.is_blocked(position + charge_dir * (radius + 0.3), radius):
				if Game.camera:
					Game.camera.add_trauma(0.2)
				mode = "recover"; t = -0.4  # longer recovery = punish window
				charge_cd = randf_range(4.0, 6.0)
		"recover":
			move_speed = 0.3
			attack_amount = move_toward(attack_amount, 0.0, delta * 2.0)
			if t >= 0.8:
				mode = "chase"; t = 0.0

func _faces_player() -> bool:
	return mode == "chase" or mode == "slam_windup"

func _on_interrupt() -> void:
	super()
	mode = "recover"; t = 0.0
