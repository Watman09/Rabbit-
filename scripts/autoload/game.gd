## Global game state + shared services: world references, hit-stop / slow-mo,
## arena collision, input map and run statistics.
extends Node

var player: Node3D
var enemies: Node        # EnemyManager
var projectiles: Node    # EnemyProjectiles
var souls: Node          # SoulManager
var camera: Node         # GameCamera
var world: Node3D        # root for spawned gameplay objects

var arena_half := Vector2(19.0, 19.0)
## Circular obstacles: Array of Vector3(x, z, radius)
var obstacles: Array[Vector3] = []

var running := false
var ai_frozen := false   # debug/test: spirits idle in place
var stats := {}

var _hitstop_end := 0
var _slowmo_end := 0
var _slowmo_scale := 1.0
var _hitstop_scale := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	reset()

func reset() -> void:
	running = false
	obstacles.clear()
	stats = {"kills": 0, "souls": 0, "max_combo": 0, "wave": 0, "time": 0.0, "damage": 0.0}
	_hitstop_end = 0
	_slowmo_end = 0
	Engine.time_scale = 1.0

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var s := 1.0
	if now < _slowmo_end:
		s = _slowmo_scale
	if now < _hitstop_end:
		s = minf(s, _hitstop_scale)
	Engine.time_scale = s
	if running and not get_tree().paused:
		stats.time += delta

## Freeze-frame on impact. Real-time duration so it is independent of time scale.
func hitstop(duration: float, scale := 0.04) -> void:
	var end := Time.get_ticks_msec() + int(duration * 1000.0)
	if end > _hitstop_end:
		_hitstop_end = end
		_hitstop_scale = scale

func slowmo(duration: float, scale := 0.35) -> void:
	_slowmo_end = Time.get_ticks_msec() + int(duration * 1000.0)
	_slowmo_scale = scale

## Keeps a circle inside the arena and outside obstacles. Returns new position.
func resolve_circle(p: Vector3, r: float) -> Vector3:
	for o in obstacles:
		var dx := p.x - o.x
		var dz := p.z - o.y
		var min_d := r + o.z
		var d2 := dx * dx + dz * dz
		if d2 < min_d * min_d:
			var d := sqrt(d2)
			if d < 0.001:
				dx = 1.0; dz = 0.0; d = 1.0
			p.x = o.x + dx / d * min_d
			p.z = o.y + dz / d * min_d
	p.x = clampf(p.x, -arena_half.x + r, arena_half.x - r)
	p.z = clampf(p.z, -arena_half.y + r, arena_half.y - r)
	return p

func is_blocked(p: Vector3, r: float) -> bool:
	return resolve_circle(p, r).distance_squared_to(p) > 0.0004

func random_point_in_arena(margin := 2.0) -> Vector3:
	for i in 12:
		var p := Vector3(randf_range(-arena_half.x + margin, arena_half.x - margin), 0,
				randf_range(-arena_half.y + margin, arena_half.y - margin))
		if not is_blocked(p, 1.0):
			return p
	return Vector3.ZERO

# --------------------------------------------------------------------------
# Input map lives in code so it is easy to read and remap in one place.
const BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"attack": [KEY_J, "mouse_left", "joy_x"],
	"heavy": [KEY_K, "mouse_right", "joy_y"],
	"dash": [KEY_SPACE, KEY_SHIFT, "joy_a"],
	"ability_1": [KEY_Q, KEY_1, "joy_lb"],
	"ability_2": [KEY_E, KEY_2, "joy_rb"],
	"ability_3": [KEY_R, KEY_3, "joy_b"],
	"pause": [KEY_ESCAPE, KEY_P, "joy_start"],
	"debug_stats": [KEY_F3],
	"debug_stress": [KEY_F9],
}

func _setup_input() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for b in BINDINGS[action]:
			var ev: InputEvent
			if b is int:
				var k := InputEventKey.new()
				k.physical_keycode = b
				ev = k
			else:
				match b:
					"mouse_left":
						ev = InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT
					"mouse_right":
						ev = InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_RIGHT
					"joy_a":
						ev = InputEventJoypadButton.new(); ev.button_index = JOY_BUTTON_A
					"joy_b":
						ev = InputEventJoypadButton.new(); ev.button_index = JOY_BUTTON_B
					"joy_x":
						ev = InputEventJoypadButton.new(); ev.button_index = JOY_BUTTON_X
					"joy_y":
						ev = InputEventJoypadButton.new(); ev.button_index = JOY_BUTTON_Y
					"joy_lb":
						ev = InputEventJoypadButton.new(); ev.button_index = JOY_BUTTON_LEFT_SHOULDER
					"joy_rb":
						ev = InputEventJoypadButton.new(); ev.button_index = JOY_BUTTON_RIGHT_SHOULDER
					"joy_start":
						ev = InputEventJoypadButton.new(); ev.button_index = JOY_BUTTON_START
			if ev:
				InputMap.action_add_event(action, ev)
