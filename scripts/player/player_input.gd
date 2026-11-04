## Converts raw devices (keyboard+mouse, gamepad, touch) into intent:
## a move vector, an aim direction and buffered action presses.
## The player only talks to this class, so new devices plug in here.
class_name PlayerInput
extends Node

const BUFFER_TIME := 0.28
const ACTIONS := ["attack", "heavy", "dash", "ability_1", "ability_2", "ability_3"]

var move := Vector3.ZERO          # world-space XZ, length <= 1
var aim := Vector3(0, 0, 1)       # world-space XZ, normalised
var aim_point := Vector3.ZERO     # world point under the cursor
var heavy_held := false
var using_touch := false
var using_pad := false

var _pressed_at := {}             # action -> time
var _time := 0.0
# Touch controls write here.
var touch_move := Vector3.ZERO
var touch_heavy := false
var _mouse_moved := true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_moved = true
		using_pad = false
	elif event is InputEventScreenTouch:
		using_touch = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		using_pad = true
	for a in ACTIONS:
		if event.is_action_pressed(a):
			press(a)

## Called by touch buttons too.
func press(action: String) -> void:
	_pressed_at[action] = _time

## Returns true (once) if the action was pressed in the last BUFFER_TIME seconds.
func consume(action: String, window := BUFFER_TIME) -> bool:
	if _pressed_at.has(action) and _time - _pressed_at[action] <= window:
		_pressed_at.erase(action)
		return true
	return false

func peek(action: String, window := BUFFER_TIME) -> bool:
	return _pressed_at.has(action) and _time - _pressed_at[action] <= window

func update(delta: float, player_pos: Vector3) -> void:
	_time += delta
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var pad := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if pad.length() > 0.2:
		v = pad
	move = Vector3(v.x, 0, v.y)
	if touch_move.length() > 0.05:
		move = touch_move
	if move.length() > 1.0:
		move = move.normalized()
	heavy_held = Input.is_action_pressed("heavy") or touch_heavy

	if using_touch or using_pad:
		_auto_aim(player_pos)
	else:
		_mouse_aim(player_pos)

func _mouse_aim(player_pos: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var hit = Plane(Vector3.UP, 0.9).intersects_ray(from, dir)
	if hit != null:
		aim_point = hit
		var d: Vector3 = hit - player_pos
		d.y = 0
		if d.length() > 0.2:
			aim = d.normalized()

## Gamepad right stick, else nearest enemy in front, else move direction.
func _auto_aim(player_pos: Vector3) -> void:
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.35:
		aim = Vector3(rs.x, 0, rs.y).normalized()
		aim_point = player_pos + aim * 4.0
		return
	var base := move.normalized() if move.length() > 0.2 else aim
	var best: Node3D = null
	var best_score := INF
	if Game.enemies:
		for e in Game.enemies.query_radius(player_pos, 7.0):
			var d: Vector3 = e.position - player_pos
			d.y = 0
			var dist := d.length()
			var facing_bonus := 1.0 - base.dot(d / maxf(dist, 0.01))
			var score := dist + facing_bonus * 3.0
			if score < best_score:
				best_score = score
				best = e
	if best:
		var d2: Vector3 = best.position - player_pos
		d2.y = 0
		aim = d2.normalized()
	else:
		aim = base
	aim_point = player_pos + aim * 4.0
