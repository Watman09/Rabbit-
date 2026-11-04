## Angled top-down follow camera with look-ahead, trauma-based shake and FOV punch.
class_name GameCamera
extends Camera3D

@export var pitch_deg := 56.0
@export var distance := 16.0
@export var base_fov := 42.0
@export var follow_sharpness := 7.0
@export var look_ahead := 0.18

var target: Node3D
var trauma := 0.0
var _focus := Vector3.ZERO
var _fov_kick := 0.0
var _t := 0.0

func _ready() -> void:
	Game.camera = self
	fov = base_fov
	near = 0.5
	far = 80.0
	if target:
		_focus = target.position

func add_trauma(v: float) -> void:
	trauma = clampf(trauma + v * 0.5, 0.0, 1.0)

func punch_fov(v: float) -> void:
	_fov_kick = v

func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	_t += real_dt
	if target:
		var want: Vector3 = target.position
		if target is Player:
			var p: Player = target
			var ahead := (p.input.aim_point - p.position)
			ahead.y = 0
			want += ahead.limit_length(4.0) * look_ahead
		_focus = _focus.lerp(want, 1.0 - exp(-follow_sharpness * real_dt))
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(0, sin(pitch), cos(pitch)) * distance
	var shake := trauma * trauma
	var so := Vector3(
		sin(_t * 47.0) + sin(_t * 23.0) * 0.5,
		sin(_t * 41.0 + 1.0) + sin(_t * 19.0) * 0.5,
		0) * shake * 0.35
	position = _focus + offset
	look_at(_focus + Vector3(0, 0.6, 0), Vector3.UP)
	position += global_transform.basis * so
	rotation.z += sin(_t * 31.0) * shake * 0.02
	trauma = maxf(0.0, trauma - real_dt * 1.6)
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-6.0 * real_dt))
	fov = base_fov + _fov_kick
