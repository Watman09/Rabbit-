## Immediate-mode HUD drawn with the canvas API: health, souls, dash pips,
## ability sigils with cooldowns, combo counter, wave banner, boss bar,
## overlays. One Control, one draw call batch, no scene files to maintain.
class_name HUD
extends Control

const C_RED := Color(0.95, 0.08, 0.2)
const C_PINK := Color(1.0, 0.45, 0.75)
const C_SOUL := Color(0.45, 0.85, 1.0)
const C_VIOLET := Color(0.7, 0.35, 1.0)
const C_DIM := Color(1, 1, 1, 0.55)

var font: Font
var player: Player
var mode := "title"   # title, play, paused, dead, upgrade
var offer: Array[String] = []
var card_rects: Array[Rect2] = []
var _popups: Array = []      # [{text, pos, color, size, t}]
var _offer_t := 0.0
var _hp_shown := 1.0
var _hp_lag := 1.0
var _combo := 0
var _combo_pulse := 0.0
var _combo_t := 0.0
var _banner_title := ""
var _banner_sub := ""
var _banner_t := 99.0
var _boss: Node = null
var _boss_ratio := 1.0
var _boss_lag := 1.0
var _hurt := 0.0
var _wave := 0
var _debug := false
var _fps_acc := 0.0
var _fps_frames := 0
var _fps := 60.0
var _t := 0.0
var _vignette: ColorRect
var _vmat: ShaderMaterial

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vmat = ShaderMaterial.new()
	_vmat.shader = preload("res://assets/shaders/vignette.gdshader")
	_vignette.material = _vmat
	add_child(_vignette)
	_vignette.show_behind_parent = true
	Events.combo_changed.connect(func(c):
		if c > _combo:
			_combo_pulse = 1.0
		_combo = c
		if c > 0:
			_combo_t = 0.0)
	Events.announcement.connect(func(a, b):
		_banner_title = a; _banner_sub = b; _banner_t = 0.0)
	Events.wave_started.connect(func(n, _boss_wave): _wave = n)
	Events.boss_spawned.connect(func(b): _boss = b; _boss_ratio = 1.0; _boss_lag = 1.0)
	Events.boss_health_changed.connect(func(r): _boss_ratio = r)
	Events.boss_defeated.connect(func(_b):
		_boss = null
		_banner_title = "ПУСТОТА ПОВЕРЖЕНА"; _banner_sub = "Но духи не утихают…"; _banner_t = 0.0)
	Events.player_damaged.connect(func(_a, _h, _m): _hurt = 1.0)
	Events.popup.connect(func(text, pos, col, sz):
		if _popups.size() > 12:
			_popups.pop_front()
		_popups.append({"text": text, "pos": pos, "color": col, "size": sz, "t": 0.0}))

func _process(delta: float) -> void:
	var rd := delta / maxf(Engine.time_scale, 0.01)
	_t += rd
	_banner_t += rd
	_combo_t += rd
	_combo_pulse = maxf(0.0, _combo_pulse - rd * 5.0)
	_hurt = maxf(0.0, _hurt - rd * 1.8)
	_offer_t += rd
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i].t += rd
		if _popups[i].t > 1.1:
			_popups.remove_at(i)
	_fps_acc += rd
	_fps_frames += 1
	if _fps_acc >= 0.5:
		_fps = _fps_frames / _fps_acc
		_fps_acc = 0.0
		_fps_frames = 0
	if player:
		var r := player.hp / player.max_hp
		_hp_shown = lerpf(_hp_shown, r, 1.0 - exp(-14.0 * rd))
		_hp_lag = maxf(_hp_shown, _hp_lag - rd * 0.35) if _hp_lag > _hp_shown else _hp_shown
		var low := clampf(1.0 - r / 0.3, 0.0, 1.0)
		_vmat.set_shader_parameter("damage", maxf(_hurt, low * (0.4 + 0.2 * sin(_t * 6.0))))
	_boss_lag = maxf(_boss_ratio, _boss_lag - rd * 0.25)
	if Input.is_action_just_pressed("debug_stats"):
		_debug = not _debug
	queue_redraw()

func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 6) -> void:
	if outline > 0:
		draw_string_outline(font, pos, s, align, width, size, outline, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, s, align, width, size, col)

func _slant_bar(pos: Vector2, size: Vector2, ratio: float, lag: float, col: Color, col2: Color) -> void:
	var sl := size.y * 0.6
	var bg := PackedVector2Array([pos + Vector2(sl, 0), pos + Vector2(size.x + sl, 0), pos + Vector2(size.x, size.y), pos + Vector2(0, size.y)])
	draw_colored_polygon(bg, Color(0.03, 0.02, 0.05, 0.85))
	if lag > ratio:
		var lw := size.x * lag
		draw_colored_polygon(PackedVector2Array([pos + Vector2(sl, 0), pos + Vector2(lw + sl, 0), pos + Vector2(lw, size.y), pos + Vector2(0, size.y)]), Color(1, 1, 1, 0.5))
	var w := size.x * clampf(ratio, 0.0, 1.0)
	if w > 1.0:
		var pts := PackedVector2Array([pos + Vector2(sl, 0), pos + Vector2(w + sl, 0), pos + Vector2(w, size.y), pos + Vector2(0, size.y)])
		draw_polygon(pts, PackedColorArray([col2, col2, col, col]))
		draw_line(pos + Vector2(sl, 1), pos + Vector2(w + sl, 1), Color(1, 1, 1, 0.35), 1.0)
	draw_polyline(PackedVector2Array([bg[0], bg[1], bg[2], bg[3], bg[0]]), Color(col.r, col.g, col.b, 0.6), 1.5)

func _draw() -> void:
	var vs := get_viewport_rect().size
	match mode:
		"title":
			_draw_title(vs)
			return
	if player == null:
		return
	# --- health & souls ---
	var p0 := Vector2(28, 26)
	_slant_bar(p0 + Vector2(0, 4), Vector2(300, 18), _hp_shown, _hp_lag, Color(0.55, 0.0, 0.08), C_RED)
	_text(p0 + Vector2(312, 20), "%d" % ceili(player.hp), 16, Color.WHITE)
	var sm := player.soul_meter / player.soul_meter_max
	var full := sm >= 1.0
	var scol := C_SOUL.lerp(Color.WHITE, (0.5 + 0.5 * sin(_t * 8.0)) * 0.6) if full else C_SOUL
	_slant_bar(p0 + Vector2(0, 30), Vector2(240, 10), sm, sm, Color(0.3, 0.2, 0.8), scol)
	_text(p0 + Vector2(252, 41), "души %d" % player.souls_total, 13, Color(0.7, 0.9, 1.0, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	# dash pips
	for i in player.dash_charges_max:
		var c := p0 + Vector2(10 + i * 22, 62)
		var filled := i < player.dash_charges
		var col := C_PINK if filled else Color(0.4, 0.3, 0.45, 0.6)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)]), col if filled else Color(0, 0, 0, 0.5))
		draw_polyline(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0), c + Vector2(0, -7)]), col, 1.5)
		if not filled and i == player.dash_charges:
			var k := player.dash_recharge_t / player.dash_recharge
			draw_arc(c, 10, -PI * 0.5, -PI * 0.5 + TAU * k, 16, C_PINK, 1.5)

	# --- wave / counters ---
	_text(Vector2(0, 36), "ВОЛНА %d" % _wave, 22, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if Game.enemies:
		_text(Vector2(0, 56), "духов: %d" % Game.enemies.alive_count(), 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)

	# --- boss bar ---
	if _boss and is_instance_valid(_boss):
		var bw := minf(vs.x * 0.6, 720.0)
		var bp := Vector2((vs.x - bw) * 0.5, 92)
		_text(Vector2(0, bp.y - 8), Boss.NAME.to_upper(), 17, Color(1, 0.6, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_slant_bar(bp, Vector2(bw, 14), _boss_ratio, _boss_lag, Color(0.4, 0.0, 0.1), Color(1.0, 0.1, 0.35))
		for k in [0.33, 0.66]:
			draw_line(bp + Vector2(bw * k + 8, 0), bp + Vector2(bw * k, 14), Color(0, 0, 0, 0.8), 2.0)

	# --- abilities ---
	if not get_meta("touch", false):
		var keys := ["Q", "E", "R"]
		var n := player.abilities.size()
		var spacing := 86.0
		var base := Vector2(vs.x * 0.5 - spacing * (n - 1) * 0.5, vs.y - 68)
		for i in n:
			_draw_ability(base + Vector2(i * spacing, 0), player.abilities[i], keys[i], 30.0)
		_text(Vector2(0, vs.y - 8), "ЛКМ удар  •  ПКМ заряд  •  ПРОБЕЛ рывок  •  ESC пауза", 12, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
	else:
		pass

	# --- combo ---
	if _combo >= 2 and _combo_t < 2.2:
		var a := clampf(2.2 - _combo_t, 0.0, 1.0)
		var sc := 1.0 + _combo_pulse * 0.35
		var cx := vs.x - 70
		var col := C_RED.lerp(C_PINK, clampf(_combo / 60.0, 0.0, 1.0))
		col.a = a
		var fs := int((44 + mini(_combo, 100) * 0.25) * sc)
		_text(Vector2(cx - 400, vs.y * 0.42), "%d" % _combo, fs, col, HORIZONTAL_ALIGNMENT_RIGHT, 400, 8)
		_text(Vector2(cx - 400, vs.y * 0.42 + 22), "УДАРОВ", 15, Color(1, 1, 1, a * 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 400, 4)
		var rank := ""
		if _combo >= 100: rank = "ЖАТВА"
		elif _combo >= 60: rank = "БЕЗУМИЕ"
		elif _combo >= 30: rank = "РЕЗНЯ"
		elif _combo >= 12: rank = "ЖЕСТОКО"
		if rank != "":
			_text(Vector2(cx - 400, vs.y * 0.42 + 46), rank, 20, Color(C_PINK.r, C_PINK.g, C_PINK.b, a), HORIZONTAL_ALIGNMENT_RIGHT, 400, 5)

	# --- floating combat text ---
	var cam := get_viewport().get_camera_3d()
	if cam:
		for pp in _popups:
			var t: float = pp.t
			var wp: Vector3 = pp.pos + Vector3.UP * t * 0.9
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - t * 6.0)
			var a := clampf((1.1 - t) * 3.0, 0.0, 1.0)
			var col: Color = pp.color
			col.a = a
			var fs := int(26.0 * pp.size * pop)
			_text(Vector2(sp.x - 200, sp.y), pp.text, fs, col, HORIZONTAL_ALIGNMENT_CENTER, 400, 6)
	if player.crit_t > 0.0:
		var k := player.crit_t / 1.6
		_text(p0 + Vector2(0, 98), "КРИТИЧЕСКОЕ ОКНО", 13, Color(0.6, 0.95, 1.0, 0.6 + 0.4 * sin(_t * 14.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
		draw_rect(Rect2(p0 + Vector2(0, 104), Vector2(160 * k, 3)), Color(0.6, 0.95, 1.0, 0.9))
	if player.upgrades.size() > 0:
		var x := 28.0
		for id in player.upgrades:
			var u: Dictionary = Upgrades.LIST[id]
			var c := p0 + Vector2(x - 18, 126)
			draw_circle(c, 11, Color(0, 0, 0, 0.5))
			draw_sigil(self, c, u.icon, 6.5, Upgrades.RARE_COLOR if u.rare else Upgrades.COMMON_COLOR, _t)
			if player.upgrades[id] > 1:
				_text(c + Vector2(4, 12), str(player.upgrades[id]), 10, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
			x += 26.0

	# --- banner ---
	if _banner_t < 3.2:
		var a2 := clampf(_banner_t * 4.0, 0.0, 1.0) * clampf((3.2 - _banner_t) * 2.0, 0.0, 1.0)
		var y := vs.y * 0.2
		var spread := (1.0 - clampf(_banner_t * 3.0, 0.0, 1.0)) * 60.0
		draw_rect(Rect2(0, y - 52, vs.x, 84), Color(0, 0, 0, 0.45 * a2))
		draw_line(Vector2(vs.x * 0.25 - spread, y + 30), Vector2(vs.x * 0.75 + spread, y + 30), Color(C_RED.r, C_RED.g, C_RED.b, a2), 2.0)
		_text(Vector2(0, y), _banner_title, 42, Color(1, 0.92, 0.95, a2), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 8)
		_text(Vector2(0, y + 24), _banner_sub, 17, Color(1, 0.5, 0.65, a2), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)

	if _debug:
		var lines := [
			"FPS %d" % roundi(_fps),
			"enemies %d / nodes %d" % [Game.enemies.alive_count() if Game.enemies else 0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)],
			"draw calls %d" % Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"process %.1f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
			"F9: +60 духов",
		]
		for i in lines.size():
			_text(Vector2(vs.x - 260, 140 + i * 18), lines[i], 14, Color(0.6, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)

	match mode:
		"paused":
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
			_text(Vector2(0, vs.y * 0.4), "ПАУЗА", 56, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 8)
			_draw_controls(Vector2(vs.x * 0.5, vs.y * 0.4 + 40))
		"upgrade":
			_draw_upgrades(vs)
		"dead":
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0, 0.02, 0.6))
			_text(Vector2(0, vs.y * 0.36), "ЖНЕЦ ПАЛ", 64, C_RED, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 10)
			var s := Game.stats
			var info := "Волна %d   •   Духов изгнано: %d   •   Душ: %d   •   Лучшее комбо: %d   •   Время: %d:%02d" % [
				s.wave, s.kills, s.souls, s.max_combo, int(s.time) / 60, int(s.time) % 60]
			_text(Vector2(0, vs.y * 0.36 + 44), info, 17, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
			var info2 := "Идеальных уклонений: %d   •   Казней: %d   •   Отражено: %d   •   Даров: %d" % [
				s.get("perfect", 0), s.get("executions", 0), s.get("parries", 0), player.upgrades.size()]
			_text(Vector2(0, vs.y * 0.36 + 70), info2, 15, Color(0.8, 0.7, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
			if fmod(_t, 1.2) < 0.85:
				_text(Vector2(0, vs.y * 0.36 + 100), "нажмите, чтобы восстать снова", 20, C_PINK, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 5)

func open_upgrades(ids: Array[String]) -> void:
	offer = ids
	mode = "upgrade"
	_offer_t = 0.0

## Index of the card under a screen point, or -1.
func card_at(p: Vector2) -> int:
	for i in card_rects.size():
		if card_rects[i].has_point(p):
			return i
	return -1

func _draw_upgrades(vs: Vector2) -> void:
	var appear := clampf(_offer_t * 4.0, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.0, 0.04, 0.72 * appear))
	_text(Vector2(0, vs.y * 0.17), "ДАР ЖАТВЫ", 40, Color(1, 0.92, 0.96, appear), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 8)
	_text(Vector2(0, vs.y * 0.17 + 30), "выберите одно усиление", 16, Color(1, 0.5, 0.7, appear), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	var n := offer.size()
	var cw := minf(260.0, (vs.x - 60.0) / maxf(n, 1) - 20.0)
	var ch := minf(300.0, vs.y * 0.52)
	var total := n * cw + (n - 1) * 24.0
	var x0 := (vs.x - total) * 0.5
	var y0 := vs.y * 0.3
	var mouse := get_viewport().get_mouse_position()
	card_rects.clear()
	for i in n:
		var id := offer[i]
		var u: Dictionary = Upgrades.LIST[id]
		var col: Color = Upgrades.RARE_COLOR if u.rare else Upgrades.COMMON_COLOR
		var delay := clampf(_offer_t * 5.0 - i * 0.35, 0.0, 1.0)
		var ease_in := 1.0 - pow(1.0 - delay, 3.0)
		var r := Rect2(x0 + i * (cw + 24.0), y0 + (1.0 - ease_in) * 60.0, cw, ch)
		card_rects.append(r)
		var hover := r.has_point(mouse)
		if hover:
			r = r.grow(6)
		var a := ease_in
		draw_rect(r, Color(0.05, 0.03, 0.08, 0.95 * a))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), Color(col.r, col.g, col.b, a))
		draw_rect(r, Color(col.r, col.g, col.b, (0.9 if hover else 0.45) * a), false, 2.0 if hover else 1.5)
		if hover:
			draw_rect(r.grow(5), Color(col.r, col.g, col.b, 0.15 + 0.1 * sin(_t * 8.0)), false, 6.0)
		var c := r.position + Vector2(r.size.x * 0.5, 74)
		draw_circle(c, 40, Color(col.r, col.g, col.b, 0.12 * a))
		draw_arc(c, 40, 0, TAU, 40, Color(col.r, col.g, col.b, 0.6 * a), 2.0)
		draw_sigil(self, c, u.icon, 24.0, Color(col.r, col.g, col.b, a), _t)
		_text(Vector2(r.position.x, r.position.y + 150), u.name, 20, Color(1, 0.95, 0.97, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 5)
		draw_multiline_string(font, Vector2(r.position.x + 16, r.position.y + 182), u.desc, HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x - 32, 15, 4, Color(0.85, 0.85, 0.95, a))
		var lv := Upgrades.level(player, id)
		var lvl_text := ("ур. %d → %d" % [lv, lv + 1]) if lv > 0 else ("редкий" if u.rare else "новый")
		_text(Vector2(r.position.x, r.end.y - 38), lvl_text, 13, Color(col.r, col.g, col.b, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
		if not get_meta("touch", false):
			_text(Vector2(r.position.x, r.end.y - 14), "[%d]" % (i + 1), 14, Color(1, 1, 1, 0.5 * a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)

func _draw_ability(c: Vector2, ab: Ability, key: String, r: float) -> void:
	var ready := ab.can_use()
	var cdr := ab.cooldown_ratio()
	var col := C_RED
	match ab.icon:
		"whirl": col = Color(1.0, 0.15, 0.35)
		"crescent": col = Color(1.0, 0.1, 0.2)
		"harvest": col = C_SOUL
	draw_circle(c, r, Color(0.03, 0.02, 0.05, 0.88))
	if ab.soul_cost > 0.0:
		var k := clampf(player.soul_meter / ab.soul_cost, 0.0, 1.0)
		draw_arc(c, r + 3, -PI * 0.5, -PI * 0.5 + TAU * k, 40, C_SOUL if k >= 1.0 else Color(0.4, 0.5, 0.9, 0.7), 3.0)
	var icol := col if ready else Color(0.4, 0.35, 0.45)
	if ready and ab.soul_cost > 0.0:
		icol = col.lerp(Color.WHITE, 0.3 + 0.3 * sin(_t * 7.0))
		draw_circle(c, r + 10, Color(col.r, col.g, col.b, 0.12 + 0.06 * sin(_t * 7.0)))
	draw_sigil(self, c, ab.icon, r * 0.6, icol, _t)
	if cdr > 0.0:
		var pts := PackedVector2Array([c])
		var steps := 24
		for i in steps + 1:
			var a := -PI * 0.5 + TAU * cdr * float(i) / steps
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
		_text(c + Vector2(-30, 6), "%.1f" % ab.cd_left, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 60, 4)
	draw_arc(c, r, 0, TAU, 40, Color(col.r, col.g, col.b, 0.8 if ready else 0.3), 2.0)
	_text(c + Vector2(-30, r + 18), key, 14, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 60, 4)

## Simple vector sigils for abilities.
static func draw_sigil(ci: CanvasItem, c: Vector2, kind: String, s: float, col: Color, t: float) -> void:
	match kind:
		"whirl":
			for k in 3:
				var a0 := TAU * k / 3.0 + t * 2.0
				ci.draw_arc(c, s * 0.85, a0, a0 + 1.6, 12, col, 3.0)
			ci.draw_circle(c, s * 0.18, col)
		"crescent":
			ci.draw_arc(c + Vector2(-s * 0.15, 0), s * 0.9, -1.3, 1.3, 16, col, 4.0)
			ci.draw_arc(c + Vector2(-s * 0.45, 0), s * 0.75, -1.0, 1.0, 16, Color(col.r, col.g, col.b, 0.5), 2.0)
		"harvest":
			var pts := PackedVector2Array()
			for k in 9:
				var a := -PI * 0.5 + TAU * k / 8.0
				var rr := s if k % 2 == 0 else s * 0.35
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_polyline(pts, col, 2.5)
			ci.draw_arc(c, s * 1.05, 0.3, PI - 0.3, 16, col, 2.0)
		"heavy":
			ci.draw_line(c + Vector2(0, -s), c + Vector2(0, s), col, 3.0)
			ci.draw_arc(c + Vector2(-s * 0.3, -s * 0.4), s * 0.7, -PI * 0.9, -PI * 0.2, 12, col, 3.0)
		"dash":
			for k in 3:
				var o := Vector2(-s * 0.5 + k * s * 0.45, 0)
				ci.draw_polyline(PackedVector2Array([c + o + Vector2(-s * 0.25, -s * 0.5), c + o + Vector2(s * 0.2, 0), c + o + Vector2(-s * 0.25, s * 0.5)]), col, 3.0)
		"attack":
			ci.draw_arc(c, s * 0.9, -2.4, 0.6, 16, col, 4.0)
			ci.draw_line(c + Vector2(-s * 0.5, s * 0.8), c + Vector2(s * 0.3, -s * 0.6), col, 2.5)

func _draw_title(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.45))
	var y := vs.y * 0.3
	_text(Vector2(0, y), "RABBIT REAPER", 76, Color(1, 0.94, 0.97), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 10)
	draw_line(Vector2(vs.x * 0.3, y + 22), Vector2(vs.x * 0.7, y + 22), C_RED, 2.0)
	_text(Vector2(0, y + 52), "Жнец против бесконечных волн тёмных духов", 20, C_PINK, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 5)
	_draw_controls(Vector2(vs.x * 0.5, y + 96))
	var ready := Sfx.is_ready()
	if fmod(_t, 1.2) < 0.85 or not ready:
		_text(Vector2(0, vs.y - 70), "нажмите, чтобы начать жатву" if ready else "призыв духов…", 24, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)

func _draw_controls(top: Vector2) -> void:
	var rows := [
		["WASD", "движение"], ["ЛКМ", "комбо косой (4 удара)"], ["ПКМ (удерж.)", "заряженный удар"],
		["ПРОБЕЛ / SHIFT", "рывок (2 заряда), атака после рывка"], ["Q", "Вихрь душ"], ["E", "Багровый серп"],
		["R", "Жатва душ (полная шкала душ)"], ["ESC", "пауза"],
	]
	if get_meta("touch", false):
		rows = [["левый палец", "движение"], ["кнопки справа", "удар, рывок, способности"]]
	for i in rows.size():
		var y := top.y + i * 24
		_text(Vector2(top.x - 410, y), rows[i][0], 16, C_PINK, HORIZONTAL_ALIGNMENT_RIGHT, 400, 4)
		_text(Vector2(top.x + 14, y), rows[i][1], 16, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
