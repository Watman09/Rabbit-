## Builds escalating waves from a point budget. Every 10th wave is the boss;
## after it the cycle repeats with higher difficulty (endless mode).
class_name WaveDirector
extends Node

const BOSS_EVERY := 10
const MAX_ALIVE := 110
const COST := {"wisp": 1, "wraith": 2, "banshee": 3, "shade": 3, "brute": 8}
const UNLOCK := {"wisp": 1, "wraith": 1, "banshee": 3, "shade": 4, "brute": 5}

var wave := 0
var budget := 0
var elites_left := 0
var difficulty := 1.0
var spawn_t := 0.0
var break_t := 2.0
var in_wave := false
var boss_wave := false
var boss_alive := false
var _boss_escort_t := 0.0

func _ready() -> void:
	Events.boss_defeated.connect(func(_b): boss_alive = false)

func start(first_wave := 1) -> void:
	wave = first_wave - 1
	break_t = 1.2
	in_wave = false

func _process(delta: float) -> void:
	if not Game.running or Game.enemies == null:
		return
	if not in_wave:
		break_t -= delta
		if break_t <= 0.0:
			_begin_wave()
		return
	spawn_t -= delta
	if boss_wave:
		_boss_escort_t -= delta
		if boss_alive and _boss_escort_t <= 0.0 and Game.enemies.alive_count() < 12:
			_boss_escort_t = 9.0
			_spawn_pack("wisp", 4, false)
	elif budget > 0 and spawn_t <= 0.0 and Game.enemies.alive_count() < MAX_ALIVE:
		_spawn_next()
	var done: bool = budget <= 0 and Game.enemies.alive_count() == 0
	if boss_wave:
		done = not boss_alive and Game.enemies.alive_count() == 0
	if done:
		in_wave = false
		break_t = 3.0
		Events.wave_cleared.emit(wave)
		if Game.player:
			Game.player.heal(15.0)

func _begin_wave() -> void:
	wave += 1
	Game.stats.wave = wave
	var cycle := (wave - 1) / BOSS_EVERY
	var local := (wave - 1) % BOSS_EVERY + 1
	difficulty = 1.0 + cycle * 0.75 + (local - 1) * 0.07
	boss_wave = local == BOSS_EVERY
	in_wave = true
	spawn_t = 0.6
	if boss_wave:
		budget = 0
		boss_alive = true
		_boss_escort_t = 12.0
		Events.wave_started.emit(wave, true)
		Events.announcement.emit(Loc.t("wave", wave), Loc.t("boss_wave", Boss.display_name()))
		var p := _spawn_point(8.0, 12.0)
		FX.portal(p, 4.0, 1.8)
		get_tree().create_timer(0.8, false).timeout.connect(func():
			if Game.enemies:
				Game.enemies.spawn("boss", p, difficulty, false))
		return
	budget = int(10 + local * 7 + cycle * 18)
	elites_left = 0 if local < 3 else (local / 3 + cycle)
	Events.wave_started.emit(wave, false)
	var sub := Loc.t("w_default")
	if local == 3:
		sub = Loc.t("w_elite")
	elif local == UNLOCK.banshee:
		sub = Loc.t("w_banshee")
	elif local == UNLOCK.shade:
		sub = Loc.t("w_shade")
	elif local == UNLOCK.brute:
		sub = Loc.t("w_brute")
	elif local == BOSS_EVERY - 1:
		sub = Loc.t("w_prelude")
	Events.announcement.emit(Loc.t("wave", wave), sub)

func _available_kinds() -> Array:
	var local := (wave - 1) % BOSS_EVERY + 1
	var cycle := (wave - 1) / BOSS_EVERY
	var out := []
	for k in UNLOCK:
		if UNLOCK[k] <= local or cycle > 0:
			out.append(k)
	return out

func _spawn_next() -> void:
	var kinds := _available_kinds()
	var weights := {"wisp": 5.0, "wraith": 4.0, "banshee": 2.0, "shade": 1.6, "brute": 0.8}
	var total := 0.0
	for k in kinds:
		total += weights[k]
	var r := randf() * total
	var kind: String = kinds[0]
	for k in kinds:
		r -= weights[k]
		if r <= 0.0:
			kind = k
			break
	var pack := 1
	match kind:
		"wisp": pack = randi_range(4, 8)
		"wraith": pack = randi_range(2, 5)
		"banshee": pack = randi_range(1, 3)
		"shade": pack = randi_range(1, 2)
		"brute": pack = 1
	pack = mini(pack, maxi(1, budget / COST[kind]))
	var elite := elites_left > 0 and randf() < 0.35
	if elite:
		elites_left -= 1
		pack = 1
	budget -= COST[kind] * pack * (3 if elite else 1)
	_spawn_pack(kind, pack, elite)
	spawn_t = randf_range(0.7, 1.6) / (1.0 + wave * 0.04)

func _spawn_pack(kind: String, count: int, elite: bool) -> void:
	var c := _spawn_point(9.0, 15.0)
	FX.portal(c, 1.2 + count * 0.25, 0.9)
	Sfx.play("portal", randf_range(0.9, 1.1), -10.0)
	for i in count:
		var a := TAU * i / maxf(count, 1) + randf()
		var p := c + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 0.6 + count * 0.2)
		Game.enemies.spawn(kind, p, difficulty, elite)

func _spawn_point(min_r: float, max_r: float) -> Vector3:
	var center := Game.player.position if Game.player else Vector3.ZERO
	for i in 16:
		var a := randf() * TAU
		var r := randf_range(min_r, max_r)
		var p := center + Vector3(cos(a), 0, sin(a)) * r
		if absf(p.x) < Game.arena_half.x - 1.5 and absf(p.z) < Game.arena_half.y - 1.5 and not Game.is_blocked(p, 1.0):
			return p
	return Game.random_point_in_arena(3.0)
