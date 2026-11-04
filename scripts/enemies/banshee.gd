## Ranged spirit: keeps its distance and fires bolts of red soul-fire.
class_name Banshee
extends Enemy

var mode := "drift"
var t := 0.0
var cd := 0.0
var strafe := 1.0

func _init() -> void:
	kind = "banshee"
	max_hp = 24.0; hp = max_hp
	speed = 3.2; radius = 0.5; damage = 9.0
	poise = 0.8; soul_value = 2; hover = 0.6
	cd = randf_range(1.5, 3.0)
	strafe = 1.0 if randf() < 0.5 else -1.0
	tint = Color(1.0, 0.15, 0.25, 1.1)

func _think(delta: float) -> void:
	t += delta
	cd -= delta
	var d := to_player()
	var dist := d.length()
	var dn := d / maxf(dist, 0.01)
	match mode:
		"drift":
			attack_amount = move_toward(attack_amount, 0.0, delta * 3.0)
			var side := Vector3(dn.z, 0, -dn.x) * strafe
			if dist < 6.0:
				move_dir = (-dn + side * 0.5).normalized()
			elif dist > 10.5:
				move_dir = (dn + side * 0.3).normalized()
			else:
				move_dir = side
			move_speed = speed
			if Game.is_blocked(position + move_dir * 1.2, radius):
				strafe = -strafe
			if cd <= 0.0 and dist < 15.0 and player_alive():
				mode = "charge"; t = 0.0
				Sfx.play("telegraph", 1.4, -8.0)
		"charge":
			move_speed = 0.0
			attack_amount = t / 0.7 * 0.6
			flash = 0.35 * (sin(t * 30.0) * 0.5 + 0.5)
			if t >= 0.7:
				var spread := 3 if not elite else 5
				for i in spread:
					var off := (i - (spread - 1) * 0.5) * 0.22
					var dir := dn.rotated(Vector3.UP, off)
					Game.projectiles.fire(position + Vector3.UP * (hover + 1.2) + dir * 0.5, dir * 9.0, damage, Color(1, 0.08, 0.2))
				Sfx.play("bolt", randf_range(0.9, 1.1), -4.0)
				mode = "recover"; t = 0.0
		"recover":
			move_speed = speed * 0.5
			move_dir = -dn
			attack_amount = move_toward(attack_amount, 0.0, delta * 3.0)
			if t >= 0.6:
				mode = "drift"; t = 0.0
				cd = randf_range(2.2, 3.4)

func _on_interrupt() -> void:
	super()
	mode = "recover"; t = 0.0
