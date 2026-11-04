## Final boss: "Скорбящая Пустота" (The Mourning Hollow).
## Three phases; each unlocks more attacks and makes it faster.
class_name Boss
extends Enemy

const NAME := "Скорбящая Пустота"

var mode := "idle"
var t := 0.0
var cd := 1.5
var phase_n := 1
var combo_left := 0
var strike_dir := Vector3.ZERO
var did_hit := false
var _eruptions: Array = []   # [{pos, t}]
var _last_attack := ""

func _init() -> void:
	kind = "boss"
	is_boss = true
	max_hp = 2400.0; hp = max_hp
	speed = 2.6; radius = 1.4; damage = 18.0
	poise = 9999.0; knock_resist = 1.0; soul_value = 80; hover = 0.3
	visual_scale = 1.9
	spawn_time = 1.6
	dying_time = 1.6
	tint = Color(1.0, 0.05, 0.25, 1.5)

func _ready() -> void:
	super()
	Events.boss_spawned.emit(self)

func _faces_player() -> bool:
	return mode in ["idle", "sweep_windup", "nova_windup", "summon"]

func take_hit(info: DamageInfo) -> bool:
	if mode == "phase_change":
		flash = 0.5
		return false
	var killed := super(info)
	Events.boss_health_changed.emit(maxf(hp, 0.0) / max_hp)
	if not killed:
		var ratio := hp / max_hp
		if phase_n == 1 and ratio < 0.66 or phase_n == 2 and ratio < 0.33:
			_start_phase_change()
	return killed

func _start_phase_change() -> void:
	phase_n += 1
	_on_interrupt()
	mode = "phase_change"; t = 0.0
	Sfx.play("boss_roar", 1.0 + phase_n * 0.08)
	Events.announcement.emit("ФАЗА %d" % phase_n, "Пустота яростнее")
	FX.shockwave(position, 9.0, Color(1, 0.05, 0.3), 0.7)
	if Game.camera:
		Game.camera.add_trauma(0.6)
	speed *= 1.15

func _think(delta: float) -> void:
	t += delta
	cd -= delta
	_update_eruptions(delta)
	var d := to_player()
	var dist := d.length()
	var dn := d / maxf(dist, 0.01)
	var spd_mult := 1.0 + (phase_n - 1) * 0.2
	match mode:
		"idle":
			attack_amount = move_toward(attack_amount, 0.0, delta * 2.0)
			move_dir = dn if dist > 4.5 else Vector3(dn.z, 0, -dn.x)
			move_speed = speed
			if cd <= 0.0 and player_alive():
				_choose_attack(dist)
		"sweep_windup":
			move_dir = dn; move_speed = 1.0
			strike_dir = strike_dir.slerp(dn, delta * 3.0)
			attack_amount = ease(t / (0.75 / spd_mult), 0.5) * 0.8
			if t >= 0.75 / spd_mult:
				mode = "sweep"; t = 0.0; _tele = {}
		"sweep":
			attack_amount = 1.0
			move_dir = strike_dir; move_speed = 9.0
			if t - delta < 0.04 and t >= 0.04:
				Sfx.play("claw", 0.6, 0.0)
				FX.slash(Transform3D(Basis(Vector3.UP, atan2(strike_dir.x, strike_dir.z)), position + Vector3.UP * 1.2),
					80.0, -80.0, 1.0, 5.4, 0.12, 0.3, 0.8, Color(1, 0.02, 0.1), Color(1, 0.5, 0.6), 2.0)
				melee_check(5.4, 160.0, damage * 1.2)
			if t >= 0.2:
				combo_left -= 1
				if combo_left > 0:
					mode = "sweep_windup"; t = 0.25
					strike_dir = dn
					_tele = FX.telegraph_circle(position + dn * 2.6, 3.0, 0.5 / spd_mult, Color(0.8, 0.02, 0.1))
				else:
					_recover(0.8)
		"nova_windup":
			move_speed = 0.0
			attack_amount = t / 0.8 * 0.7
			vis_y += t * 0.5
			flash = 0.3 * (sin(t * 30.0) * 0.5 + 0.5)
			if t >= 0.8:
				_fire_nova(0.0)
				if phase_n >= 3:
					mode = "nova_second"; t = 0.0
				else:
					_recover(0.9)
		"nova_second":
			if t >= 0.35:
				_fire_nova(0.5)
				_recover(0.9)
		"summon":
			move_speed = 0.0
			attack_amount = 0.6
			if t >= 0.9:
				var n := 3 + phase_n * 2
				for i in n:
					var a := TAU * i / n
					var p := position + Vector3(cos(a), 0, sin(a)) * 4.0
					p = Game.resolve_circle(p, 0.5)
					Game.enemies.spawn("wisp" if i % 3 != 0 or phase_n == 1 else "wraith", p, 1.0, false)
				_recover(0.6)
		"charge_windup":
			move_speed = 0.0
			attack_amount = 0.5
			if t >= 1.0 / spd_mult:
				mode = "charging"; t = 0.0; did_hit = false; _tele = {}
				Sfx.play("dash", 0.5, 2.0)
		"charging":
			move_dir = strike_dir
			move_speed = 20.0
			_vel = strike_dir * 20.0
			if not did_hit and dist < radius + Game.player.radius + 0.4:
				did_hit = Game.player.take_damage(damage * 1.3, position)
			if int(t * 25.0) != int((t - delta) * 25.0):
				FX.burst("smoke", position + Vector3.UP, -strike_dir)
			if t >= 0.75 or Game.is_blocked(position + strike_dir * (radius + 0.4), radius):
				if Game.camera:
					Game.camera.add_trauma(0.4)
				FX.shockwave(position, 3.5, Color(1, 0.1, 0.2), 0.35)
				_recover(1.1)
		"eruption":
			move_speed = 0.0
			attack_amount = 0.9
			if t >= 0.4:
				var n2 := 8
				_queue_eruption(Game.player.position)
				for i in n2 - 1:
					var a2 := randf() * TAU
					var r := randf_range(2.0, 7.0)
					_queue_eruption(Game.resolve_circle(Game.player.position + Vector3(cos(a2), 0, sin(a2)) * r, 1.0))
				_recover(1.0)
		"phase_change":
			move_speed = 0.0
			attack_amount = 0.5 + sin(t * 20.0) * 0.3
			flash = 0.4
			if t >= 1.4:
				var n3 := 6
				for i in n3:
					var a3 := TAU * i / n3
					Game.enemies.spawn("wisp", Game.resolve_circle(position + Vector3(cos(a3), 0, sin(a3)) * 5.0, 0.5), 1.0, false)
				_recover(0.3)
		"recover":
			move_speed = speed * 0.4
			move_dir = dn
			attack_amount = move_toward(attack_amount, 0.0, delta * 2.0)
			if t >= 0.0:
				mode = "idle"; t = 0.0

func _recover(time: float) -> void:
	mode = "recover"
	t = -time / (1.0 + (phase_n - 1) * 0.25)
	cd = randf_range(0.2, 0.8)

func _choose_attack(dist: float) -> void:
	var options := []
	if dist < 6.5:
		options += ["sweep", "sweep"]
	options += ["nova"]
	if phase_n == 1 or randf() < 0.5:
		options += ["summon"] if _last_attack != "summon" else []
	if phase_n >= 2:
		options += ["charge", "charge"] if dist > 5.0 else ["charge"]
	if phase_n >= 3:
		options += ["eruption", "eruption"]
	var pick: String = options[randi() % options.size()]
	if pick == _last_attack and options.size() > 1:
		pick = options[randi() % options.size()]
	_last_attack = pick
	t = 0.0
	var dn := to_player().normalized()
	match pick:
		"sweep":
			mode = "sweep_windup"
			combo_left = phase_n
			strike_dir = dn
			_tele = FX.telegraph_circle(position + dn * 2.6, 3.0, 0.75 / (1.0 + (phase_n - 1) * 0.2), Color(0.8, 0.02, 0.1))
			Sfx.play("telegraph", 0.6, -2.0)
		"nova":
			mode = "nova_windup"
			Sfx.play("charge", 0.6, 0.0)
		"summon":
			mode = "summon"
			Sfx.play("roar_small", 0.7, 0.0)
			for i in 3:
				FX.portal(position + Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 4.0, 1.4, 0.9)
		"charge":
			mode = "charge_windup"
			strike_dir = dn
			_tele = FX.telegraph_line(position, dn, 16.0, radius * 2.0, 1.0 / (1.0 + (phase_n - 1) * 0.2))
			Sfx.play("roar_small", 0.8, 0.0)
		"eruption":
			mode = "eruption"
			Sfx.play("boss_roar", 1.3, -6.0)

func _fire_nova(offset: float) -> void:
	var n := 14 + phase_n * 4
	for i in n:
		var a := TAU * (i + offset) / n
		var dir := Vector3(cos(a), 0, sin(a))
		Game.projectiles.fire(position + Vector3.UP * 1.6 + dir * 1.2, dir * (7.5 + phase_n), damage * 0.7, Color(1, 0.05, 0.25), 0.55)
	Sfx.play("bolt", 0.7, 0.0)
	FX.shockwave(position, 3.0, Color(1, 0.1, 0.3), 0.3)

func _queue_eruption(p: Vector3) -> void:
	FX.telegraph_circle(p, 2.0, 1.0)
	_eruptions.append({"pos": p, "t": 1.0})

func _update_eruptions(delta: float) -> void:
	for i in range(_eruptions.size() - 1, -1, -1):
		var e: Dictionary = _eruptions[i]
		e.t -= delta
		if e.t <= 0.0:
			FX.burst("embers", e.pos + Vector3.UP * 0.2, Vector3.UP)
			FX.burst("smoke", e.pos + Vector3.UP * 0.4, Vector3.UP)
			FX.shockwave(e.pos, 2.4, Color(1, 0.1, 0.2), 0.3)
			Sfx.play("slam", randf_range(1.1, 1.3), -8.0)
			if player_alive() and Game.player.position.distance_to(e.pos) < 2.0 + Game.player.radius:
				Game.player.take_damage(damage, e.pos)
			_eruptions.remove_at(i)

func _on_death() -> void:
	Game.slowmo(1.5, 0.3)
	FX.shockwave(position, 12.0, Color(1, 0.05, 0.3), 1.2)
	FX.shockwave(position, 8.0, Color(0.6, 0.3, 1.0), 0.9)
	FX.burst("souls_swirl", position + Vector3.UP, Vector3.UP)
	Sfx.play("boss_roar", 0.7)
	if Game.camera:
		Game.camera.add_trauma(1.0)
	Events.boss_defeated.emit(self)
