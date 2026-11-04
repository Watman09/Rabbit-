## The Reaper. A small state machine: MOVE / ATTACK / DASH / CHARGE / CAST / DEAD.
## Attacks are AttackData driven; abilities are Ability objects that take over
## the CAST state. Movement is kinematic on the XZ plane (no physics engine)
## which keeps it cheap and predictable in the browser.
class_name Player
extends Node3D

enum State { MOVE, ATTACK, DASH, CHARGE, CAST, DEAD }

@export var max_hp := 120.0
@export var move_speed := 7.6
@export var accel := 70.0
@export var radius := 0.45
@export var dash_distance := 5.6
@export var dash_time := 0.17
@export var dash_iframes := 0.26
@export var dash_charges_max := 2
@export var dash_recharge := 0.85
@export var soul_meter_max := 100.0

var hp := max_hp
var state := State.MOVE
var velocity := Vector3.ZERO
var facing := Vector3(0, 0, 1)
var soul_meter := 0.0
var souls_total := 0

var input: PlayerInput
var rig: PlayerRig
var abilities: Array[Ability] = []

# attack state
var combo: Array[AttackData]
var combo_index := 0
var combo_timer := 0.0
var attack: AttackData
var attack_t := 0.0
var attack_facing := Vector3(0, 0, 1)
var attack_hit := {}
var attack_damage_mult := 1.0
var attack_queued := false
var _prev_sweep := 0.0
var _slash_spawned := false
var _impact_done := false
var _combat_idle := 0.0

# dash state
var dash_t := 0.0
var dash_dir := Vector3.ZERO
var dash_charges := 2
var dash_recharge_t := 0.0
var _afterimage_t := 0.0
var _dash_strike_window := 0.0

# charge state
var charge_t := 0.0
var _charge_fx_t := 0.0

var cast_ability: Ability
var invuln := 0.0
var hurt_grace := 0.0
var hit_count := 0
var combo_hits := 0
var combo_hits_timer := 0.0
var _hitstop_frame := 0.0
var _shadow: MeshInstance3D
var _step_t := 0.0

func _ready() -> void:
	Game.player = self
	input = PlayerInput.new()
	add_child(input)
	rig = PlayerRig.new()
	add_child(rig)
	_shadow = FX.make_shadow(1.1)
	add_child(_shadow)
	combo = Moveset.light_combo()
	abilities = [SoulMaelstrom.new(self), CrimsonCrescent.new(self), HarvestOfSouls.new(self)]
	hp = max_hp
	dash_charges = dash_charges_max
	_emit_souls()

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	input.update(delta, position)
	invuln = maxf(0.0, invuln - delta)
	hurt_grace = maxf(0.0, hurt_grace - delta)
	combo_timer = maxf(0.0, combo_timer - delta)
	_dash_strike_window = maxf(0.0, _dash_strike_window - delta)
	_combat_idle = maxf(0.0, _combat_idle - delta)
	_hitstop_frame = 0.0
	combo_hits_timer -= delta
	if combo_hits_timer <= 0.0 and combo_hits > 0:
		combo_hits = 0
		Events.combo_changed.emit(0)
	if dash_charges < dash_charges_max:
		dash_recharge_t += delta
		if dash_recharge_t >= dash_recharge:
			dash_recharge_t = 0.0
			dash_charges += 1
	for a in abilities:
		a.tick(delta)

	match state:
		State.MOVE: _state_move(delta)
		State.ATTACK: _state_attack(delta)
		State.DASH: _state_dash(delta)
		State.CHARGE: _state_charge(delta)
		State.CAST: _state_cast(delta)

	position = Game.resolve_circle(position, radius)
	position.y = 0.0
	rotation.y = atan2(facing.x, facing.z)
	var local_v := global_transform.basis.inverse() * velocity
	rig.set_drag(local_v)

# ------------------------------------------------------------------ MOVE
func _state_move(delta: float) -> void:
	var target_v := input.move * move_speed
	velocity = velocity.move_toward(target_v, accel * delta)
	position += velocity * delta
	if input.move.length() > 0.1:
		facing = _turn_toward(facing, input.move.normalized(), 16.0 * delta)
	var speed01 := velocity.length() / move_speed
	_step_t += delta * (6.0 + speed01 * 6.0)
	var target: PlayerRig.ScythePose
	if speed01 > 0.25:
		target = PlayerRig.POSE_RUN.copy()
		target.bob = absf(sin(_step_t)) * 0.07 * speed01
		target.lean = 0.12 + speed01 * 0.12
		target.body_yaw = sin(_step_t * 0.5) * 4.0
	elif _combat_idle > 0.0:
		target = PlayerRig.POSE_READY.copy()
		target.bob = sin(_step_t * 0.4) * 0.015
	else:
		target = PlayerRig.POSE_IDLE.copy()
		target.bob = sin(_step_t * 0.35) * 0.012
		target.squash = 1.0 + sin(_step_t * 0.35) * 0.01
	rig.blend_to(target, delta, 12.0)
	rig.scythe_glow = move_toward(rig.scythe_glow, 0.0, delta * 3.0)
	_try_actions(true)

func _try_actions(allow_attack: bool) -> bool:
	if input.consume("dash") and dash_charges > 0:
		_start_dash()
		return true
	for i in abilities.size():
		if input.peek("ability_%d" % (i + 1)):
			if abilities[i].can_use():
				input.consume("ability_%d" % (i + 1))
				_start_cast(abilities[i])
				return true
			else:
				input.consume("ability_%d" % (i + 1))
				Sfx.play("denied", 0.8)
	if allow_attack:
		if input.consume("heavy"):
			_start_charge()
			return true
		if input.consume("attack"):
			if _dash_strike_window > 0.0:
				_start_attack(Moveset.dash_strike())
			else:
				if combo_timer <= 0.0:
					combo_index = 0
				_start_attack(combo[combo_index])
				combo_index = (combo_index + 1) % combo.size()
			return true
	return false

# ------------------------------------------------------------------ ATTACK
func _start_attack(a: AttackData, damage_mult := 1.0) -> void:
	state = State.ATTACK
	attack = a
	attack_t = 0.0
	attack_hit.clear()
	attack_queued = false
	attack_damage_mult = damage_mult
	_slash_spawned = false
	_impact_done = false
	_prev_sweep = a.sweep_from
	attack_facing = input.aim if input.aim.length() > 0.1 else facing
	facing = attack_facing
	velocity = Vector3.ZERO
	_combat_idle = 2.5

func _state_attack(delta: float) -> void:
	var a := attack
	attack_t += delta
	var t := attack_t
	var steer := input.move * move_speed * a.move_factor
	if t < a.windup:
		# anticipation: pull the scythe back past the start angle
		var k := t / maxf(a.windup, 0.001)
		var back := a.sweep_from - a.sweep_dir() * 18.0
		var p := PlayerRig.attack_pose(a, lerpf(a.sweep_from, back, k), -0.05)
		p.squash = 1.0 - 0.05 * k
		rig.blend_to(p, delta, 30.0)
		position += attack_facing * (a.lunge * 0.15 / maxf(a.windup, 0.001)) * delta + steer * delta
		rig.scythe_glow = move_toward(rig.scythe_glow, 1.0, delta * 8.0)
	elif t < a.windup + a.active:
		var k := (t - a.windup) / a.active
		var s := 1.0 - pow(1.0 - k, 2.2)  # ease out: fast start, settle
		var sweep := lerpf(a.sweep_from, a.sweep_to, s)
		var p := PlayerRig.attack_pose(a, sweep, 0.22)
		p.squash = 1.04
		rig.set_pose(p)
		rig.scythe_glow = 1.0
		position += attack_facing * (a.lunge * 0.85 / a.active) * (1.0 - k) * 2.0 * delta + steer * delta
		if not _slash_spawned:
			_slash_spawned = true
			_spawn_slash(a)
			if a.sound != "":
				Sfx.play(a.sound, randf_range(0.92, 1.08))
		if a.hit_mode == AttackData.HitMode.SWEEP:
			_sweep_hits(a, _prev_sweep, sweep)
		_prev_sweep = sweep
		if Game.projectiles:
			Game.projectiles.cut_sweep(position, attack_facing, a.sweep_from, sweep, a.radius)
	else:
		if not _impact_done:
			_impact_done = true
			if a.hit_mode == AttackData.HitMode.CONE_AT_END:
				_cone_hits(a)
			if a.impact_radius > 0.0:
				_impact(a)
		var rec_t := t - a.windup - a.active
		var k := rec_t / maxf(a.recovery, 0.001)
		var end_pose := PlayerRig.attack_pose(a, a.sweep_to, 0.1)
		var ready := PlayerRig.POSE_READY.copy()
		if a.body_spin:
			ready.body_yaw = roundf(a.sweep_to / 360.0) * 360.0
			ready.yaw += roundf((a.sweep_to - ready.yaw) / 360.0) * 360.0
		rig.set_pose(end_pose.blend(ready, ease(k, 0.6)))
		rig.scythe_glow = move_toward(rig.scythe_glow, 0.0, delta * 4.0)
		position += steer * 2.0 * delta
		if input.peek("attack") or input.peek("heavy"):
			attack_queued = true
		var can_cancel := k >= a.cancel_ratio
		# dash and abilities cancel recovery immediately
		if input.peek("dash") or input.peek("ability_1") or input.peek("ability_2") or input.peek("ability_3"):
			if _try_actions(false):
				return
		if can_cancel and attack_queued:
			_finish_attack()
			_try_actions(true)
			return
		if rec_t >= a.recovery:
			_finish_attack()
	if t < a.windup + a.active and (input.peek("dash")) and t > a.windup:
		# allow dash-cancel mid-swing after the first frames for responsiveness
		if attack_t > a.windup + a.active * 0.5:
			_try_actions(false)

func _finish_attack() -> void:
	state = State.MOVE
	combo_timer = attack.combo_window if attack.combo_window > 0.0 else 0.0
	if attack.combo_window <= 0.0:
		combo_index = 0
	_normalize_pose()

## Keep pose angles in a canonical range after full spins so blends stay short.
func _normalize_pose() -> void:
	rig.pose.body_yaw = wrapf(rig.pose.body_yaw, -180.0, 180.0)
	rig.pose.yaw = wrapf(rig.pose.yaw, -90.0, 270.0)

func _spawn_slash(a: AttackData) -> void:
	var xf := Transform3D(Basis(Vector3.UP, atan2(attack_facing.x, attack_facing.z)), position)
	xf = xf * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(a.plane_tilt)), Vector3(0, a.height, 0))
	var follow := self if a.body_spin else null
	FX.slash(xf, a.sweep_from, a.sweep_to, a.slash_inner, a.slash_outer, a.active, a.slash_life,
		a.slash_trail, a.slash_edge, a.slash_core, a.slash_intensity, follow)

func _rel_angle(dir_to: Vector3) -> float:
	var fa := atan2(attack_facing.x, attack_facing.z)
	var ea := atan2(dir_to.x, dir_to.z)
	return rad_to_deg(wrapf(ea - fa, -PI, PI))

func _sweep_hits(a: AttackData, from_yaw: float, to_yaw: float) -> void:
	var dirs := signf(a.sweep_to - a.sweep_from)
	var swept := absf(to_yaw - a.sweep_from)
	for e in Game.enemies.query_radius(position, a.radius + 1.5):
		if attack_hit.has(e.get_instance_id()):
			continue
		var d: Vector3 = e.position - position
		d.y = 0
		var dist := d.length()
		if dist - e.radius > a.radius:
			continue
		var margin := rad_to_deg(atan2(e.radius, maxf(dist, 0.1))) + 6.0
		var rel := _rel_angle(d)
		var into := wrapf((rel - a.sweep_from) * dirs + margin, 0.0, 360.0)
		if dist < 0.9 or into <= swept + margin * 2.0 or swept >= 359.0:
			_hit_enemy(e, a)

func _cone_hits(a: AttackData) -> void:
	for e in Game.enemies.query_radius(position, a.radius + 1.5):
		if attack_hit.has(e.get_instance_id()):
			continue
		var d: Vector3 = e.position - position
		d.y = 0
		var dist := d.length()
		if dist - e.radius > a.radius:
			continue
		var margin := rad_to_deg(atan2(e.radius, maxf(dist, 0.1)))
		if dist < 1.0 or absf(_rel_angle(d)) <= a.cone_half + margin:
			_hit_enemy(e, a)

func _impact(a: AttackData) -> void:
	var c := position + attack_facing * a.impact_distance
	FX.shockwave(c, a.impact_radius * 1.4, Color(0.7, 0.2, 1.0), 0.45)
	FX.burst("embers", c + Vector3.UP * 0.2, Vector3.UP)
	FX.burst("smoke_ring", c + Vector3.UP * 0.1, Vector3.UP)
	for e in Game.enemies.query_radius(c, a.impact_radius + 1.0):
		if attack_hit.has(e.get_instance_id()):
			continue
		if e.position.distance_to(c) - e.radius <= a.impact_radius:
			_hit_enemy(e, a)
	if attack_damage_mult >= 1.25:
		# fully charged: release a crescent wave too
		FX.crescent_wave(self, position + Vector3.UP * 0.9, attack_facing, 30.0 * attack_damage_mult, 20.0, 0.6, 3.6,
			Color(0.7, 0.2, 1.0), Color(0.75, 0.95, 1.0))

func _hit_enemy(e: Node, a: AttackData) -> void:
	attack_hit[e.get_instance_id()] = true
	var info := DamageInfo.make(a.damage * attack_damage_mult, position, a.knockback, a.stagger, a.id)
	info.launch = a.launch
	info.color = a.slash_edge
	deal_damage(e, info, a.hitstop, a.shake)

## Single entry point for all player damage, so hit-stop / combo / FX are uniform.
func deal_damage(e: Node, info: DamageInfo, stop := 0.04, shake := 0.2) -> void:
	if not e.alive:
		return
	var killed: bool = e.take_hit(info)
	combo_hits += 1
	combo_hits_timer = 2.2
	Events.combo_changed.emit(combo_hits)
	if combo_hits > Game.stats.max_combo:
		Game.stats.max_combo = combo_hits
	Game.stats.damage += info.amount
	if stop > _hitstop_frame:
		_hitstop_frame = stop
		Game.hitstop(stop * (1.4 if killed else 1.0))
	if Game.camera:
		Game.camera.add_trauma(shake * (1.3 if killed else 0.7))

# ------------------------------------------------------------------ DASH
func _start_dash() -> void:
	if state == State.ATTACK:
		_finish_attack()
	state = State.DASH
	dash_t = 0.0
	dash_charges -= 1
	dash_dir = input.move.normalized() if input.move.length() > 0.2 else facing
	facing = dash_dir
	invuln = maxf(invuln, dash_iframes)
	_afterimage_t = 0.0
	Sfx.play("dash", randf_range(0.95, 1.1))
	FX.burst("dust", position + Vector3.UP * 0.2, -dash_dir)
	FX.dash_streak(position, position + dash_dir * dash_distance)
	rig.set_ghost(1.0)

func _state_dash(delta: float) -> void:
	dash_t += delta
	var k := clampf(dash_t / dash_time, 0.0, 1.0)
	# ease-out speed profile: integrates to dash_distance
	var speed := dash_distance / dash_time * 2.0 * (1.0 - k)
	velocity = dash_dir * speed
	position += velocity * delta
	var p := PlayerRig.POSE_RUN.copy()
	p.lean = 0.45
	p.squash = 0.92
	p.bob = 0.05
	rig.blend_to(p, delta, 30.0)
	_afterimage_t -= delta
	if _afterimage_t <= 0.0:
		_afterimage_t = 0.028
		FX.afterimage(rig, global_transform)
	if dash_t >= dash_time:
		state = State.MOVE
		velocity = dash_dir * move_speed * 0.6
		rig.set_ghost(0.0)
		_dash_strike_window = 0.18
		if input.peek("attack"):
			input.consume("attack")
			_start_attack(Moveset.dash_strike())
		elif input.peek("dash") and dash_charges > 0:
			input.consume("dash")
			_start_dash()

# ------------------------------------------------------------------ CHARGE
func _start_charge() -> void:
	state = State.CHARGE
	charge_t = 0.0
	_charge_fx_t = 0.0
	_combat_idle = 2.5
	Sfx.play("charge", 1.0)

func _state_charge(delta: float) -> void:
	charge_t += delta
	var full := charge_t >= 0.65
	velocity = velocity.move_toward(input.move * move_speed * 0.35, accel * delta)
	position += velocity * delta
	facing = _turn_toward(facing, input.aim, 14.0 * delta)
	var p := PlayerRig.ScythePose.make({"tilt": 90.0, "height": 1.05, "yaw": -150.0 - minf(charge_t, 0.65) * 20.0,
		"reach": 0.7, "pitch": 95.0, "lean": -0.12, "squash": 0.95, "sscale": 1.85})
	rig.blend_to(p, delta, 12.0)
	rig.scythe_glow = minf(1.0, charge_t / 0.65) * (1.0 + (0.3 * sin(charge_t * 40.0) if full else 0.0))
	_charge_fx_t -= delta
	if _charge_fx_t <= 0.0:
		_charge_fx_t = 0.08
		FX.burst("charge", rig.blade_point(), Vector3.UP)
	if full and not get_meta("charge_flashed", false):
		set_meta("charge_flashed", true)
		Sfx.play("charged", 1.0)
		FX.shockwave(position, 2.0, Color(0.7, 0.3, 1.0), 0.3)
	if input.peek("dash"):
		set_meta("charge_flashed", false)
		rig.scythe_glow = 0.0
		state = State.MOVE
		_try_actions(false)
		return
	if not input.heavy_held:
		set_meta("charge_flashed", false)
		var mult := remap(clampf(charge_t, 0.0, 0.65), 0.0, 0.65, 0.6, 1.0)
		if full:
			mult = 1.4
		input.aim = facing
		_start_attack(Moveset.heavy(), mult)

# ------------------------------------------------------------------ CAST
func _start_cast(ab: Ability) -> void:
	if state == State.ATTACK:
		_finish_attack()
	state = State.CAST
	cast_ability = ab
	_combat_idle = 2.5
	ab.begin()

func _state_cast(delta: float) -> void:
	if cast_ability.update(delta):
		cast_ability = null
		state = State.MOVE
		_normalize_pose()
		return
	if cast_ability.dash_cancelable and input.peek("dash") and dash_charges > 0:
		cast_ability.end()
		cast_ability = null
		state = State.MOVE
		_try_actions(false)

# ------------------------------------------------------------------ HEALTH & SOULS
func is_invulnerable() -> bool:
	return invuln > 0.0 or hurt_grace > 0.0 or state == State.DEAD or (cast_ability != null and cast_ability.invulnerable)

## Returns true if the hit landed.
func take_damage(amount: float, from: Vector3) -> bool:
	if is_invulnerable():
		return false
	hp = maxf(0.0, hp - amount)
	hurt_grace = 0.55
	rig.flash = 1.0
	var d := position - from
	d.y = 0
	if d.length() > 0.01:
		velocity = d.normalized() * 6.0
		if state == State.MOVE:
			position += d.normalized() * 0.3
	Events.player_damaged.emit(amount, hp, max_hp)
	Sfx.play("hurt", randf_range(0.9, 1.05))
	FX.burst("hit_player", position + Vector3.UP, d.normalized())
	if Game.camera:
		Game.camera.add_trauma(0.5)
	Game.hitstop(0.07, 0.1)
	if hp <= 0.0:
		_die()
	return true

func heal(amount: float) -> void:
	if state == State.DEAD:
		return
	hp = minf(max_hp, hp + amount)
	Events.player_healed.emit(hp, max_hp)

func add_soul(value: int) -> void:
	souls_total += value
	Game.stats.souls += value
	soul_meter = minf(soul_meter_max, soul_meter + value * 1.6)
	heal(value * 0.35)
	_emit_souls()

func spend_souls(amount: float) -> void:
	soul_meter = maxf(0.0, soul_meter - amount)
	_emit_souls()

func _emit_souls() -> void:
	Events.souls_changed.emit(souls_total, soul_meter, soul_meter_max)

func _die() -> void:
	state = State.DEAD
	rig.set_ghost(1.0)
	FX.burst("death", position + Vector3.UP, Vector3.UP)
	FX.shockwave(position, 4.0, Color(1, 0.05, 0.2), 0.8)
	Sfx.play("player_death", 1.0)
	Game.slowmo(1.2, 0.25)
	var tw := create_tween()
	tw.tween_property(rig, "scale", Vector3(1.2, 0.05, 1.2), 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	Events.player_died.emit()

# ------------------------------------------------------------------ helpers
static func _turn_toward(cur: Vector3, target: Vector3, t: float) -> Vector3:
	if target.length() < 0.01:
		return cur
	var a := atan2(cur.x, cur.z)
	var b := atan2(target.x, target.z)
	var r := lerp_angle(a, b, clampf(t, 0.0, 1.0))
	return Vector3(sin(r), 0, cos(r))
