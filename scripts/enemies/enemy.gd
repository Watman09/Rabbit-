## Base spirit. Movement is kinematic and updated centrally by EnemyManager
## (tick), which also provides separation. Subclasses implement _think() to
## set `move_dir` / `move_speed` and run their own attack state machine.
class_name Enemy
extends Node3D

enum State { SPAWN, ACT, STAGGER, DYING }

var kind := "wraith"
var max_hp := 30.0
var hp := 30.0
var speed := 3.5
var radius := 0.5
var damage := 10.0
var poise := 1.0                 # stagger threshold
var knock_resist := 0.0          # 0..1
var soul_value := 2
var elite := false
var is_boss := false
var hover := 0.25
var visual_scale := 1.0
var tint := Color(1.0, 0.06, 0.12, 1.0)

var alive := true
var state := State.SPAWN
var state_t := 0.0
var move_dir := Vector3.ZERO
var move_speed := 0.0
var knock := Vector3.ZERO
var lift := 0.0                  # vertical launch offset
var lift_v := 0.0
var flash := 0.0
var attack_amount := 0.0         # drives arm animation in shader
var punch := 0.0                 # hit squash
var yaw := 0.0
var phase := 0.0
var spawn_time := 0.55
var dying_time := 0.55
var _vel := Vector3.ZERO
var _tele: Dictionary = {}

# visual state (drawn by EnemyManager through a SpiritRenderer MultiMesh)
var render_key := ""
var vis_y := 0.0
var vis_scale := Vector3.ONE
var dissolve := 1.0
var _lag_z := 0.0
var aura: MeshInstance3D

func _ready() -> void:
	phase = float(randi() % 16)
	render_key = _mesh_kind() + ("_elite" if elite else "")
	vis_scale = Vector3.ONE * visual_scale
	if elite or is_boss:
		aura = FX.make_glow_sprite(Color(tint.r, tint.g * 0.5, tint.b, 0.35), 3.2 * visual_scale)
		aura.position.y = 1.0 * visual_scale
		add_child(aura)

func _mesh_kind() -> String:
	return kind

## Applies elite scaling. Call before adding to the tree.
func make_elite() -> void:
	elite = true
	max_hp *= 4.0
	hp = max_hp
	damage *= 1.4
	speed *= 1.1
	visual_scale *= 1.35
	radius *= 1.3
	poise *= 2.5
	knock_resist = minf(0.9, knock_resist + 0.45)
	soul_value *= 5
	tint = Color(1.0, 0.1, 0.55, 1.6)

func apply_difficulty(mult: float) -> void:
	max_hp *= mult
	hp = max_hp
	damage *= lerpf(1.0, mult, 0.6)

# ------------------------------------------------------------------ central update
func tick(delta: float, separation: Vector3) -> void:
	state_t += delta
	flash = maxf(0.0, flash - delta * 7.0)
	punch = maxf(0.0, punch - delta * 6.0)
	match state:
		State.SPAWN:
			var k := clampf(state_t / spawn_time, 0.0, 1.0)
			dissolve = 1.0 - k
			vis_y = hover - (1.0 - k) * 1.2
			if k >= 1.0:
				_enter_act()
			_update_visual(delta)
			return
		State.DYING:
			_update_dying(delta)
			return
		State.STAGGER:
			move_dir = Vector3.ZERO
			attack_amount = move_toward(attack_amount, 0.0, delta * 4.0)
			if state_t >= _stagger_time():
				_enter_act()
		State.ACT:
			if Game.ai_frozen:
				move_dir = Vector3.ZERO
			else:
				_think(delta)
	var desired := move_dir * move_speed
	_vel = _vel.lerp(desired, 1.0 - exp(-10.0 * delta))
	knock *= exp(-7.0 * delta)
	var motion := _vel + knock + separation
	position += motion * delta
	position = Game.resolve_circle(position, radius)
	# launch arc
	if lift > 0.0 or lift_v != 0.0:
		lift_v -= 22.0 * delta
		lift = maxf(0.0, lift + lift_v * delta)
		if lift <= 0.0:
			lift_v = 0.0
	_update_visual(delta)

func _update_visual(delta: float) -> void:
	var face_dir := move_dir
	var p := Game.player
	if p and (state == State.ACT or state == State.SPAWN) and _faces_player():
		face_dir = (p.position - position)
	face_dir.y = 0
	if face_dir.length() > 0.05:
		yaw = lerp_angle(yaw, atan2(face_dir.x, face_dir.z), 1.0 - exp(-8.0 * delta))
	rotation.y = yaw
	if state != State.SPAWN:
		vis_y = hover + sin(Time.get_ticks_msec() * 0.003 + phase) * 0.08 + lift
	var sq := 1.0 + punch * 0.25
	vis_scale = Vector3(visual_scale * sq, visual_scale / sq, visual_scale * sq)
	var v := _vel + knock
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	_lag_z = clampf(v.dot(fwd) * 0.07, -1.9, 1.9)

## Pushes this spirit into its type's MultiMesh.
func draw_spirit() -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(vis_scale), position + Vector3(0, vis_y, 0))
	Game.enemies.draw(render_key, xf, Color(flash, dissolve, attack_amount, phase * 8.0 + _lag_z + 2.0), self)

func _faces_player() -> bool:
	return true

func _stagger_time() -> float:
	return 0.35

func _enter_act() -> void:
	state = State.ACT
	state_t = 0.0
	dissolve = 0.0
	vis_y = hover

## Override in subclasses.
func _think(_delta: float) -> void:
	pass

## Called when this enemy is interrupted (telegraph cancel etc.)
func _on_interrupt() -> void:
	FX.cancel(_tele)
	_tele = {}

# ------------------------------------------------------------------ damage
## Returns true if the hit killed the enemy.
func take_hit(info: DamageInfo) -> bool:
	if not alive:
		return false
	hp -= info.amount
	flash = 1.0
	punch = 1.0
	var d := position - info.origin
	d.y = 0
	var dir := d.normalized() if d.length() > 0.01 else Vector3(0, 0, 1)
	knock += dir * info.knockback * (1.0 - knock_resist)
	if info.launch and knock_resist < 0.6:
		lift_v = 6.0 * (1.0 - knock_resist)
	FX.burst("hit", position + Vector3.UP * (hover + 0.9 * visual_scale), dir)
	Sfx.play("hit", randf_range(0.85, 1.15), -2.0)
	Events.enemy_hit.emit(self, info)
	if hp <= 0.0:
		die(info)
		return true
	if info.stagger >= poise and state == State.ACT:
		_on_interrupt()
		state = State.STAGGER
		state_t = 0.0
	return false

func die(info: DamageInfo) -> void:
	alive = false
	state = State.DYING
	state_t = 0.0
	_on_interrupt()
	var d := position - info.origin
	d.y = 0
	var dir := d.normalized() if d.length() > 0.01 else Vector3(0, 0, 1)
	knock = dir * (info.knockback * 1.3 + 3.0) * (1.0 - knock_resist * 0.5)
	var center := position + Vector3.UP * (hover + 0.8 * visual_scale)
	FX.burst("death", center, Vector3.UP)
	FX.burst("death_embers", center, Vector3.UP)
	FX.fragments(center, render_key, 3 if not elite else 6, visual_scale)
	if elite:
		FX.shockwave(position, 3.0 * visual_scale, Color(1, 0.1, 0.4), 0.45)
	Sfx.play("kill", randf_range(0.85, 1.15), -1.0)
	if Game.souls:
		Game.souls.drop(center, soul_value)
	Game.stats.kills += 1
	Events.enemy_killed.emit(self)
	_on_death()

func _on_death() -> void:
	pass

func _update_dying(delta: float) -> void:
	var k := clampf(state_t / dying_time, 0.0, 1.0)
	knock *= exp(-5.0 * delta)
	position += knock * delta
	position = Game.resolve_circle(position, radius)
	dissolve = k
	flash = maxf(0.0, 1.0 - k * 4.0)
	vis_y += delta * 0.8
	vis_scale = Vector3.ONE * visual_scale * (1.0 + k * 0.25)
	if aura:
		aura.scale = Vector3.ONE * 3.2 * visual_scale * (1.0 - k)
	if k >= 1.0:
		queue_free()

# ------------------------------------------------------------------ helpers for subclasses
func to_player() -> Vector3:
	var d: Vector3 = Game.player.position - position
	d.y = 0
	return d

func player_alive() -> bool:
	return Game.player != null and Game.player.state != Player.State.DEAD

## Melee hit check in a cone in front. Returns true if the player got hit.
func melee_check(reach: float, cone_deg: float, dmg: float) -> bool:
	if not player_alive():
		return false
	var d := to_player()
	var dist := d.length()
	if dist > reach + Game.player.radius:
		return false
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	if dist > 0.6 and rad_to_deg(fwd.angle_to(d)) > cone_deg * 0.5:
		return false
	return Game.player.take_damage(dmg, position)

func set_state_act() -> void:
	state = State.ACT
	state_t = 0.0
