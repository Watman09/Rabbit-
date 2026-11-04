## Soul orbs dropped by spirits. They burst out, hover, then stream into
## the Reaper. Pooled glow sprites, updated in one loop.
class_name SoulManager
extends Node3D

const POOL := 260
const MAGNET_DELAY := 0.45

var _mm: MultiMeshInstance3D
var _col := PackedColorArray()
var _scale := PackedFloat32Array()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _value := PackedInt32Array()
var _active: Array[bool] = []
var _free: Array[int] = []
var _pickup_streak := 0
var _streak_t := 0.0

func _ready() -> void:
	Game.souls = self
	_pos.resize(POOL); _vel.resize(POOL); _age.resize(POOL); _value.resize(POOL); _col.resize(POOL); _scale.resize(POOL)
	_mm = FX.make_glow_multimesh(POOL)
	add_child(_mm)
	for i in POOL:
		_active.append(false)
		_free.append(POOL - 1 - i)

## Drop `value` souls worth of orbs (big values become bigger orbs).
func drop(pos: Vector3, value: int) -> void:
	var orbs := clampi(value, 1, 8)
	var per := maxi(1, value / orbs) if value > 0 else 0  # 0 = warm-up orb
	var rem := value - per * orbs
	for k in orbs:
		if _free.is_empty():
			# pool exhausted: give directly so nothing is lost
			if Game.player:
				Game.player.add_soul(per)
			continue
		var i: int = _free.pop_back()
		_active[i] = true
		var a := randf() * TAU
		_pos[i] = pos
		_vel[i] = Vector3(cos(a) * randf_range(2.0, 4.5), randf_range(3.0, 6.0), sin(a) * randf_range(2.0, 4.5))
		_age[i] = randf() * 0.15
		_value[i] = per + (rem if k == 0 else 0)
		_scale[i] = 0.45 + minf(_value[i], 6) * 0.08
		_col[i] = Color(0.45, 0.85, 1.0, 1.3) if randf() < 0.7 else Color(0.75, 0.45, 1.0, 1.3)

func _process(delta: float) -> void:
	var p := Game.player
	_streak_t -= delta
	if _streak_t <= 0.0:
		_pickup_streak = 0
	var target := Vector3.ZERO
	var alive_p: bool = p != null and p.state != Player.State.DEAD
	var mm := _mm.multimesh
	var n := 0
	if alive_p:
		target = p.position + Vector3.UP * 1.0
	for i in POOL:
		if not _active[i]:
			continue
		_age[i] += delta
		var v := _vel[i]
		if _age[i] < MAGNET_DELAY or not alive_p:
			v.y -= 14.0 * delta
			v *= exp(-2.5 * delta)
			if _pos[i].y < 0.4:
				_pos[i].y = 0.4
				v.y = absf(v.y) * 0.4
		else:
			var to := target - _pos[i]
			var dist := to.length()
			var pull := 30.0 + _age[i] * 50.0
			v = v.lerp(to / maxf(dist, 0.01) * minf(22.0, 6.0 + _age[i] * 14.0), 1.0 - exp(-4.0 * delta))
			v += to / maxf(dist, 0.01) * pull * delta * 0.2
			if dist < 0.7:
				_collect(i)
				continue
		_vel[i] = v
		_pos[i] += v * delta
		var s := _scale[i] * (1.0 + sin(_age[i] * 12.0 + i) * 0.12)
		mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(s, s, s)), _pos[i] + Vector3(0, sin(_age[i] * 9.0 + i) * 0.05, 0)))
		mm.set_instance_color(n, _col[i])
		n += 1
	mm.visible_instance_count = n

func _collect(i: int) -> void:
	_active[i] = false
	_free.append(i)
	_pickup_streak += 1
	_streak_t = 0.35
	if Game.player:
		Game.player.add_soul(_value[i])
	if _pickup_streak % 2 == 1:
		FX.burst("soul_pop", _pos[i], Vector3.UP)
	Sfx.play("soul", 1.0 + minf(_pickup_streak, 14) * 0.045, -9.0)
