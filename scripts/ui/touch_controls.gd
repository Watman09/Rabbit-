## On-screen controls for phones/tablets: floating joystick on the left half,
## action buttons on the right. Feeds PlayerInput just like a gamepad would.
class_name TouchControls
extends Control

var player: Player
var hud: HUD
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _btn_touch := {}   # touch index -> button id
var _buttons := []     # [{id, action, pos, r, icon}]
const STICK_R := 70.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var vs := get_viewport_rect().size
	var br := Vector2(vs.x - 110, vs.y - 110)
	_buttons = [
		{"id": "attack", "action": "attack", "pos": br, "r": 62.0, "icon": "attack"},
		{"id": "dash", "action": "dash", "pos": br + Vector2(-150, 30), "r": 44.0, "icon": "dash"},
		{"id": "heavy", "action": "heavy", "pos": br + Vector2(-20, -150), "r": 44.0, "icon": "heavy"},
		{"id": "ability_1", "action": "ability_1", "pos": br + Vector2(-150, -85), "r": 38.0, "icon": "whirl"},
		{"id": "ability_2", "action": "ability_2", "pos": br + Vector2(-125, -195), "r": 38.0, "icon": "crescent"},
		{"id": "ability_3", "action": "ability_3", "pos": br + Vector2(-240, -40), "r": 38.0, "icon": "harvest"},
	]

func _input(event: InputEvent) -> void:
	if not visible or player == null:
		return
	if hud and hud.mode != "play":
		return   # menus (upgrade cards, pause) get the touches
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			var b := _button_at(st.position)
			if b != "":
				_btn_touch[st.index] = b
				_press(b)
				get_viewport().set_input_as_handled()
			elif st.position.x < get_viewport_rect().size.x * 0.5 and _stick_id == -1:
				_stick_id = st.index
				_stick_origin = st.position
				_stick_pos = st.position
				get_viewport().set_input_as_handled()
		else:
			if st.index == _stick_id:
				_stick_id = -1
				player.input.touch_move = Vector3.ZERO
			if _btn_touch.has(st.index):
				if _btn_touch[st.index] == "heavy":
					player.input.touch_heavy = false
				_btn_touch.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		if sd.index == _stick_id:
			_stick_pos = sd.position
			var v := (_stick_pos - _stick_origin) / STICK_R
			if v.length() > 1.0:
				_stick_origin = _stick_pos - v.normalized() * STICK_R
				v = v.normalized()
			player.input.touch_move = Vector3(v.x, 0, v.y)
			get_viewport().set_input_as_handled()

func _press(id: String) -> void:
	for b in _buttons:
		if b.id == id:
			player.input.press(b.action)
			if id == "heavy":
				player.input.touch_heavy = true

func _button_at(p: Vector2) -> String:
	for b in _buttons:
		if p.distance_to(b.pos) <= b.r * 1.15:
			return b.id
	return ""

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player == null:
		return
	if _stick_id != -1:
		draw_circle(_stick_origin, STICK_R, Color(0, 0, 0, 0.35))
		draw_arc(_stick_origin, STICK_R, 0, TAU, 40, Color(1, 0.3, 0.5, 0.5), 2.0)
		draw_circle(_stick_pos, 30, Color(1, 0.3, 0.5, 0.45))
	for b in _buttons:
		var held: bool = b.id in _btn_touch.values()
		var col := Color(1, 0.2, 0.35)
		var ready := true
		if b.id.begins_with("ability_"):
			var ab: Ability = player.abilities[int(b.id.substr(8)) - 1]
			ready = ab.can_use()
			if ab.cd_left > 0.0:
				var k := ab.cooldown_ratio()
				draw_arc(b.pos, b.r + 4, -PI * 0.5, -PI * 0.5 + TAU * k, 30, Color(1, 1, 1, 0.4), 3.0)
		elif b.id == "dash":
			ready = player.dash_charges > 0
		draw_circle(b.pos, b.r, Color(0.02, 0.0, 0.04, 0.6 if not held else 0.85))
		draw_arc(b.pos, b.r, 0, TAU, 40, Color(col.r, col.g, col.b, 0.7 if ready else 0.25), 2.5)
		HUD.draw_sigil(self, b.pos, b.icon, b.r * 0.55, col if ready else Color(0.5, 0.4, 0.5, 0.6), Time.get_ticks_msec() * 0.001)
