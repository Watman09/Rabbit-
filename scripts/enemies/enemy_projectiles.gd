## Pooled enemy bolts. Scythe swings can cut them out of the air.
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
var _free: Array[int] = []

func _ready() -> void:
	Game.projectiles = self
	_pos.resize(POOL); _vel.resize(POOL); _life.resize(POOL); _dmg.resize(POOL); _size.resize(POOL); _col.resize(POOL)
	_mm = FX.make_glow_multimesh(POOL)
	add_child(_mm)
	for i in POOL:
		_active.append(false)
		_free.append(POOL - 1 - i)

func fire(pos: Vector3, vel: Vector3, damage: float, color: Color, size := 0.45) -> void:
	if _free.is_empty():
		return
	var i: int = _free.pop_back()
	_active[i] = true
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
			_kill(i)
			continue
		var rel := rad_to_deg(wrapf(atan2(d.x, d.z) - fa, -PI, PI))
		if rel >= lo - 10.0 and rel <= hi + 10.0:
			_kill(i)

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
		if p and p.state != Player.State.DEAD:
			var dx := _pos[i].x - p.position.x
			var dz := _pos[i].z - p.position.z
			var r: float = p.radius + _size[i] * 0.6
			if dx * dx + dz * dz < r * r:
				if p.take_damage(_dmg[i], _pos[i] - _vel[i]):
					_kill(i)
	mm.visible_instance_count = n
