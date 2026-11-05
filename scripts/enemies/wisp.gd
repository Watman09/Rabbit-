## Small fast spirit. Swarms around the player and darts in for a bite.
class_name Wisp
extends Enemy

var mode := "chase"
var t := 0.0
var cd := 0.0
var orbit := 1.0
var lunge_dir := Vector3.ZERO
var did_hit := false

func _init() -> void:
	kind = "wisp"
	max_hp = 12.0; hp = max_hp
	speed = 6.0; radius = 0.35; damage = 6.0
	poise = 0.5; soul_value = 1; hover = 0.45
	cd = randf_range(0.8, 2.2)
	tint = Color(1.0, 0.36, 0.03, 1.0)   # tier 1: smouldering ember
	hot = Color(1.0, 0.85, 0.35)
	orbit = 1.0 if randf() < 0.5 else -1.0

func _think(delta: float) -> void:
	t += delta
	cd -= delta
	var d := to_player()
	var dist := d.length()
	var dn := d / maxf(dist, 0.01)
	match mode:
		"chase":
			attack_amount = move_toward(attack_amount, 0.0, delta * 3.0)
			var side := Vector3(dn.z, 0, -dn.x) * orbit
			move_dir = (dn + side * (0.9 if dist < 5.0 else 0.25)).normalized()
			move_speed = speed
			if dist < 4.5 and cd <= 0.0 and player_alive():
				mode = "windup"; t = 0.0
				move_speed = 0.0
		"windup":
			move_dir = -dn
			move_speed = 0.8
			attack_amount = t / 0.42
			flash = 0.25 * (sin(t * 40.0) * 0.5 + 0.5)
			if t >= 0.42:
				mode = "lunge"; t = 0.0
				lunge_dir = dn
				did_hit = false
		"lunge":
			move_dir = lunge_dir
			move_speed = 15.0
			_vel = lunge_dir * 15.0
			if not did_hit and dist < radius + Game.player.radius + 0.25:
				did_hit = Game.player.take_damage(damage, position)
			if t >= 0.26:
				mode = "recover"; t = 0.0
		"recover":
			move_speed = 1.0
			attack_amount = move_toward(attack_amount, 0.0, delta * 4.0)
			if t >= 0.5:
				mode = "chase"; t = 0.0
				cd = randf_range(1.4, 2.6)

func threatens(p: Vector3) -> bool:
	var d := position.distance_to(p)
	return (mode == "windup" and t > 0.25 and d < 4.5) or (mode == "lunge" and d < 2.5)

func _on_interrupt() -> void:
	super()
	mode = "recover"; t = 0.0
