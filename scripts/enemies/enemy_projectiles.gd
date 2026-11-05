## Pooled enemy bolts. Scythe swings parry them: the bolt turns violet and
## flies back into the nearest spirit.
class_name EnemyProjectiles
extends Node3D

const POOL := 160
var _mm: MultiMeshInstance3D
var _col: PackedColorArray = PackedColorArray()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _dmg := PackedFloat32Array()
var _size := PackedFloat32Array()
var _active: Array[bool] = []
var _reflected: Array[bool] = []
var _last_parry_popup := 0
var _free: Array[int] = []

func _ready() -> void:
	Game.projectiles = self
	_pos.resize(POOL); _vel.resize(POOL); _life.resize(POOL); _dmg.resize(POOL); _size.resize(POOL); _col.resize(POOL)
	_mm = FX.make_glow_multimesh(POOL)
	add_child(_mm)
	for i in POOL:
		_active.append(false)
		_reflected.append(false)
		_free.append(POOL - 1 - i)

func fire(pos: Vector3, vel: Vector3, damage: float, color: Color, size := 0.45) -> void:
	if _free.is_empty():
		return
	var i: int = _free.pop_back()
	_active[i] = true
	_reflected[i] = false
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = 4.0
	_dmg[i] = damage
	_size[i] = size
	_col[i] = Color(color.r, color.g, color.b, 1.6)

func _kill(i: int, fx := true) -> void:
	_active[i] = false
	_free.append(i)
	if fx:
		FX.burst("hit", _pos[i], -_vel[i].normalized())

func clear_all() -> void:
	for i in POOL:
		if _active[i]:
			_kill(i, false)

## Remove bolts inside a swept arc (facing-relative degrees).
func cut_sweep(origin: Vector3, facing: Vector3, from_deg: float, to_deg: float, radius: float) -> void:
	var fa := atan2(facing.x, facing.z)
	var lo := minf(from_deg, to_deg)
	var hi := maxf(from_deg, to_deg)
	for i in POOL:
		if not _active[i]:
			continue
		var d := _pos[i] - origin
		d.y = 0
		if d.length() > radius:
			continue
		if hi - lo >= 359.0:
			_reflect(i, origin)
			continue
		var rel := rad_to_deg(wrapf(atan2(d.x, d.z) - fa, -PI, PI))
		if rel >= lo - 10.0 and rel <= hi + 10.0:
			_reflect(i, origin)

## Parry: send an enemy bolt back toward the nearest spirit.
func _reflect(i: int, origin: Vector3) -> void:
	if _reflected[i]:
		return
	_reflected[i] = true
	var target: Vector3 = _pos[i] + (_pos[i] - origin).normalized() * 6.0
	var best := INF
	if Game.enemies:
		for e in Game.enemies.query_radius(_pos[i], 14.0):
			var dd: float = e.position.distance_to(_pos[i])
			if dd < best:
				best = dd
				target = e.position + Vector3.UP * 1.0
	var dir := (target - _pos[i])
	dir.y *= 0.3
	_vel[i] = dir.normalized() * 18.0
	_life[i] = 1.6
	_dmg[i] = 24.0 * (Game.player.mods.damage if Game.player else 1.0)
	_col[i] = Color(0.75, 0.45, 1.0, 2.0)
	FX.burst("perfect", _pos[i], Vector3.UP)
	Sfx.play("parry", randf_range(0.95, 1.1), -3.0)
	Game.hitstop(0.03, 0.2)
	var now := Time.get_ticks_msec()
	if now - _last_parry_popup > 600:
		_last_parry_popup = now
		Events.popup.emit(Loc.t("p_parried"), _pos[i] + Vector3.UP * 0.8, Color(0.8, 0.6, 1.0), 0.9)
	Game.stats.parries = Game.stats.get("parries", 0) + 1

## True if an enemy bolt will pass within `r` of `p` in the next `horizon` seconds.
func threat_near(p: Vector3, r: float, horizon: float) -> bool:
	for i in POOL:
		if not _active[i] or _reflected[i]:
			continue
		var rel := Vector2(_pos[i].x - p.x, _pos[i].z - p.z)
		var v := Vector2(_vel[i].x, _vel[i].z)
		var t := clampf(-rel.dot(v) / maxf(v.length_squared(), 0.001), 0.0, horizon)
		if (rel + v * t).length() < r + _size[i]:
			return true
	return false

func cut_circle(origin: Vector3, radius: float) -> void:
	for i in POOL:
		if _active[i] and _pos[i].distance_to(origin) < radius:
			_kill(i)

func _process(delta: float) -> void:
	var p := Game.player
	var mm := _mm.multimesh
	var n := 0
	for i in POOL:
		if not _active[i]:
			continue
		_pos[i] += _vel[i] * delta
		_life[i] -= delta
		var s := _size[i] * 2.2 * (1.0 + sin(_life[i] * 30.0) * 0.08)
		mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(s, s, s)), _pos[i]))
		mm.set_instance_color(n, _col[i])
		n += 1
		if _life[i] <= 0.0 or Game.is_blocked(_pos[i], 0.1):
			_kill(i)
			continue
		if _reflected[i]:
			for e in Game.enemies.query_radius(_pos[i], 1.5):
				var flat := Vector2(e.position.x - _pos[i].x, e.position.z - _pos[i].z)
				if flat.length() - e.radius < 0.5 + _size[i]:
					var info := DamageInfo.make(_dmg[i], _pos[i] - _vel[i], 7.0, 1.5, "parry")
					p.deal_damage(e, info, 0.02, 0.15)
					_kill(i)
					break
			continue
		if p and p.state != Player.State.DEAD:
			var dx := _pos[i].x - p.position.x
			var dz := _pos[i].z - p.position.z
			var r: float = p.radius + _size[i] * 0.6
			if dx * dx + dz * dz < r * r:
				if p.take_damage(_dmg[i], _pos[i] - _vel[i]):
					_kill(i)
	mm.visible_instance_count = n
