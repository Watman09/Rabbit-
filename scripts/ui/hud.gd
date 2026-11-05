## Immediate-mode HUD + menus drawn with the canvas API: health, souls, dash
## pips, ability sigils, combo, banners, boss bar, floating text, tutorial
## prompts, and the menu screens (main, settings, how to play, pause, upgrade,
## game over). Buttons are registered while drawing; Main routes clicks, taps,
## keys and gamepad to them (button_at / move_focus / focused_id).
## All text goes through Loc.
class_name HUD
extends Control

const C_RED := Color(0.95, 0.08, 0.2)
const C_PINK := Color(1.0, 0.45, 0.75)
const C_SOUL := Color(0.45, 0.85, 1.0)
const C_VIOLET := Color(0.7, 0.35, 1.0)
const C_DIM := Color(1, 1, 1, 0.55)

var font: Font
var player: Player
var mode := "boot"    # boot, menu, settings, howto, play, paused, upgrade, dead
var back_mode := "menu"   # where Settings / How to play return to
var buttons: Array = []   # [{id, rect}] registered this frame
var focus := 0
var tutorial_text := ""
var tutorial_t := 0.0
var new_record := false
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
		_banner_title = Loc.t("boss_defeated"); _banner_sub = Loc.t("boss_defeated_sub"); _banner_t = 0.0)
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
	tutorial_t += rd
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
	buttons.clear()
	match mode:
		"boot", "menu":
			_draw_menu(vs)
			return
		"settings":
			_draw_settings(vs)
			return
		"howto":
			_draw_howto(vs)
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
	_text(p0 + Vector2(252, 41), Loc.t("souls", player.souls_total), 13, Color(0.7, 0.9, 1.0, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
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
	_text(Vector2(0, 36), Loc.t("wave", _wave), 22, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if Game.enemies:
		_text(Vector2(0, 56), Loc.t("spirits_left", Game.enemies.alive_count()), 13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)

	# --- boss bar ---
	if _boss and is_instance_valid(_boss):
		var bw := minf(vs.x * 0.6, 720.0)
		var bp := Vector2((vs.x - bw) * 0.5, 92)
		_text(Vector2(0, bp.y - 8), Boss.display_name().to_upper(), 17, Color(1, 0.6, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
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
		_text(Vector2(0, vs.y - 8), Loc.t("hint_bar"), 12, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
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
		_text(Vector2(cx - 400, vs.y * 0.42 + 22), Loc.t("hits"), 15, Color(1, 1, 1, a * 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 400, 4)
		var rank := ""
		if _combo >= 100: rank = Loc.t("rank_4")
		elif _combo >= 60: rank = Loc.t("rank_3")
		elif _combo >= 30: rank = Loc.t("rank_2")
		elif _combo >= 12: rank = Loc.t("rank_1")
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
		_text(p0 + Vector2(0, 98), Loc.t("crit_window"), 13, Color(0.6, 0.95, 1.0, 0.6 + 0.4 * sin(_t * 14.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
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
			"F9: +60 spirits",
		]
		for i in lines.size():
			_text(Vector2(vs.x - 260, 140 + i * 18), lines[i], 14, Color(0.6, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)

	# --- tutorial prompt ---
	if tutorial_text != "" and mode == "play":
		var ta := clampf(tutorial_t * 4.0, 0.0, 1.0)
		var tw := minf(vs.x - 40.0, 640.0)
		var tr := Rect2((vs.x - tw) * 0.5, vs.y * 0.68, tw, 46)
		draw_rect(tr, Color(0.03, 0.01, 0.06, 0.78 * ta))
		draw_rect(tr, Color(C_PINK.r, C_PINK.g, C_PINK.b, 0.55 * ta), false, 1.5)
		_text(Vector2(tr.position.x, tr.position.y + 30), tutorial_text, 19, Color(1, 1, 1, ta), HORIZONTAL_ALIGNMENT_CENTER, tw, 5)

	# --- in-game buttons: pause and mute (mouse / touch) ---
	if mode == "play":
		var bs := 44.0
		var pr := Rect2(vs.x - bs - 16, 14, bs, bs)
		var mr := Rect2(vs.x - bs * 2 - 26, 14, bs, bs)
		_icon_button("pause", pr, "pause")
		_icon_button("mute", mr, "sound_off" if Plat.save.muted else "sound_on")

	match mode:
		"paused":
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
			_text(Vector2(0, vs.y * 0.3), Loc.t("paused"), 56, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 8)
			_menu_column(vs, vs.y * 0.38, [["resume", Loc.t("resume")], ["settings", Loc.t("settings")],
				["howto", Loc.t("how_to_play")], ["to_menu", Loc.t("main_menu")]])
		"upgrade":
			_draw_upgrades(vs)
		"dead":
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0, 0.02, 0.65))
			_text(Vector2(0, vs.y * 0.27), Loc.t("dead_title"), 60, C_RED, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 10)
			var s := Game.stats
			var info := Loc.t("dead_stats", [s.wave, s.kills, s.souls, s.max_combo, int(s.time) / 60, int(s.time) % 60])
			_text(Vector2(0, vs.y * 0.27 + 42), info, 16, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
			var info2 := Loc.t("dead_stats2", [s.get("perfect", 0), s.get("executions", 0), s.get("parries", 0), player.upgrades.size()])
			_text(Vector2(0, vs.y * 0.27 + 66), info2, 14, Color(0.8, 0.7, 1.0, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
			if new_record:
				_text(Vector2(0, vs.y * 0.27 + 98), Loc.t("new_record"), 24, Color(1.0, 0.8, 0.3, 0.7 + 0.3 * sin(_t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
			_menu_column(vs, vs.y * 0.27 + 120, [["retry", Loc.t("retry")], ["to_menu", Loc.t("main_menu")]])

# ------------------------------------------------------------------ buttons
## Registers a clickable button (hit-tested by Main) and draws it.
func _button(id: String, r: Rect2, label: String, primary := false) -> void:
	var idx := buttons.size()
	buttons.append({"id": id, "rect": r})
	var hover: bool = r.has_point(get_viewport().get_mouse_position()) and not get_meta("touch", false)
	var focused: bool = idx == focus and not hover and not get_meta("touch", false)
	var lit: bool = hover or focused
	var col := C_RED if primary else C_PINK
	var sl := 10.0
	var pts := PackedVector2Array([r.position + Vector2(sl, 0), Vector2(r.end.x, r.position.y),
		r.end - Vector2(sl, 0), Vector2(r.position.x, r.end.y)])
	draw_colored_polygon(pts, Color(col.r * 0.35, col.g * 0.1, col.b * 0.2, 0.9) if lit else Color(0.04, 0.02, 0.07, 0.88))
	pts.append(pts[0])
	draw_polyline(pts, Color(col.r, col.g, col.b, 1.0 if lit else 0.55), 2.0 if lit else 1.5)
	if lit:
		draw_line(Vector2(r.position.x + sl, r.end.y + 4), Vector2(r.end.x - sl, r.end.y + 4), Color(col.r, col.g, col.b, 0.6), 2.0)
	_text(Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 8), label, 22 if primary else 19,
		Color(1, 1, 1, 1.0 if lit else 0.85), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 5)

func _icon_button(id: String, r: Rect2, icon: String) -> void:
	buttons.append({"id": id, "rect": r})
	var hover := r.has_point(get_viewport().get_mouse_position())
	var c := r.get_center()
	draw_circle(c, r.size.x * 0.5, Color(0.03, 0.02, 0.06, 0.75))
	draw_arc(c, r.size.x * 0.5, 0, TAU, 32, Color(C_PINK.r, C_PINK.g, C_PINK.b, 0.9 if hover else 0.5), 2.0)
	var w := Color(1, 1, 1, 0.9)
	match icon:
		"pause":
			draw_rect(Rect2(c + Vector2(-8, -10), Vector2(5, 20)), w)
			draw_rect(Rect2(c + Vector2(3, -10), Vector2(5, 20)), w)
		"sound_on", "sound_off":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-11, -5), c + Vector2(-5, -5), c + Vector2(2, -11),
				c + Vector2(2, 11), c + Vector2(-5, 5), c + Vector2(-11, 5)]), w)
			if icon == "sound_on":
				draw_arc(c + Vector2(2, 0), 7, -0.9, 0.9, 10, w, 2.0)
				draw_arc(c + Vector2(2, 0), 12, -0.9, 0.9, 12, w, 2.0)
			else:
				draw_line(c + Vector2(6, -6), c + Vector2(14, 6), C_RED, 3.0)
				draw_line(c + Vector2(14, -6), c + Vector2(6, 6), C_RED, 3.0)
		"gear":
			draw_arc(c, 7, 0, TAU, 20, w, 3.0)
			for k in 8:
				var a := TAU * k / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 9, c + Vector2(cos(a), sin(a)) * 13, w, 3.0)
		"globe":
			draw_arc(c, 11, 0, TAU, 24, w, 2.0)
			draw_line(c + Vector2(-11, 0), c + Vector2(11, 0), w, 1.5)
			draw_arc(c, 11, -0.6, 0.6, 8, w, 1.0)
			draw_line(c + Vector2(0, -11), c + Vector2(0, 11), w, 1.5)
			var e := PackedVector2Array()
			for k in 17:
				var a := -PI * 0.5 + PI * k / 16.0
				e.append(c + Vector2(cos(a) * 5.0, sin(a) * 11.0))
			draw_polyline(e, w, 1.5)

func _menu_column(vs: Vector2, y0: float, items: Array) -> void:
	var w := minf(340.0, vs.x - 60.0)
	for i in items.size():
		var r := Rect2((vs.x - w) * 0.5, y0 + i * 62.0, w, 50.0)
		_button(items[i][0], r, items[i][1], i == 0)

func button_at(p: Vector2) -> String:
	for b in buttons:
		if b.rect.has_point(p):
			return b.id
	return ""

func move_focus(d: int) -> void:
	var n := buttons.size()
	if n > 0:
		focus = wrapi(focus + d, 0, n)

func focused_id() -> String:
	return buttons[focus].id if focus < buttons.size() else ""

func set_mode(m: String) -> void:
	mode = m
	focus = 0

# ------------------------------------------------------------------ menu screens
func _dim(vs: Vector2, a := 0.5) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.0, 0.02, a))

func _draw_menu(vs: Vector2) -> void:
	_dim(vs, 0.45)
	var y := vs.y * 0.24
	_text(Vector2(0, y), "RABBIT REAPER", 76, Color(1, 0.94, 0.97), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 10)
	draw_line(Vector2(vs.x * 0.5 - 260, y + 22), Vector2(vs.x * 0.5 + 260, y + 22), C_RED, 2.0)
	_text(Vector2(0, y + 52), Loc.t("title_sub"), 19, C_PINK, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 5)
	if mode == "boot":
		if fmod(_t, 1.2) < 0.85:
			_text(Vector2(0, vs.y * 0.6), Loc.t("loading"), 22, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		return
	_menu_column(vs, y + 100, [["play", Loc.t("play")], ["settings", Loc.t("settings")], ["howto", Loc.t("how_to_play")]])
	var sv: Dictionary = Plat.save
	if int(sv.best_wave) > 0:
		_text(Vector2(0, y + 100 + 3 * 62 + 24), Loc.t("best", [int(sv.best_wave), int(sv.best_combo), int(sv.best_kills)]),
			15, Color(1, 0.8, 0.4, 0.85), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# quick language / settings icons (universal symbols, rule 3.4.4)
	_icon_button("lang", Rect2(vs.x - 60, 14, 44, 44), "globe")
	_icon_button("mute", Rect2(vs.x - 114, 14, 44, 44), "sound_off" if Plat.save.muted else "sound_on")
	_text(Vector2(vs.x - 260, 76), Loc.LANG_NAMES[Loc.lang], 14, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 244, 3)

func _draw_settings(vs: Vector2) -> void:
	_dim(vs, 0.72)
	_icon_button("noop", Rect2(vs.x * 0.5 - 22, vs.y * 0.08, 44, 44), "gear")
	buttons.pop_back()
	_text(Vector2(0, vs.y * 0.08 + 82), Loc.t("settings"), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 8)
	var sv: Dictionary = Plat.save
	var rows := [
		["music", Loc.t("music"), "%d%%" % roundi(float(sv.music) * 100.0), true],
		["sfx", Loc.t("sfx"), "%d%%" % roundi(float(sv.sfx) * 100.0), true],
		["muted", Loc.t("sound"), Loc.t("off") if sv.muted else Loc.t("on"), false],
		["shake", Loc.t("shake"), Loc.t("on") if sv.shake else Loc.t("off"), false],
		["quality", Loc.t("quality"), Loc.t("q_high") if sv.quality == "high" else Loc.t("q_low"), false],
		["lang", Loc.t("language"), Loc.LANG_NAMES[Loc.lang], false],
		["tutorial", Loc.t("tutorial_again"), Loc.t("yes") if not sv.tutorial_done else "—", false],
	]
	var w := minf(560.0, vs.x - 40.0)
	var x0 := (vs.x - w) * 0.5
	var y0 := vs.y * 0.08 + 112
	var rh := minf(54.0, (vs.y - y0 - 90.0) / rows.size())
	for i in rows.size():
		var r: Array = rows[i]
		var y := y0 + i * rh
		_text(Vector2(x0, y + rh * 0.5 + 6), r[1], 18, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
		var vw := 210.0
		if r[3]:
			_button("set_" + r[0] + "_dec", Rect2(x0 + w - vw, y + 6, 48, rh - 12), "–")
			_text(Vector2(x0 + w - vw + 48, y + rh * 0.5 + 7), r[2], 18, C_PINK, HORIZONTAL_ALIGNMENT_CENTER, vw - 96, 4)
			_button("set_" + r[0] + "_inc", Rect2(x0 + w - 48, y + 6, 48, rh - 12), "+")
		else:
			_button("set_" + r[0], Rect2(x0 + w - vw, y + 6, vw, rh - 12), r[2])
			if r[0] == "lang":
				var gc := Vector2(x0 + w - vw - 26, y + rh * 0.5)
				draw_arc(gc, 10, 0, TAU, 20, Color(1, 1, 1, 0.7), 1.5)
				draw_line(gc + Vector2(-10, 0), gc + Vector2(10, 0), Color(1, 1, 1, 0.7), 1.0)
				draw_line(gc + Vector2(0, -10), gc + Vector2(0, 10), Color(1, 1, 1, 0.7), 1.0)
	_button("back", Rect2((vs.x - 260) * 0.5, y0 + rows.size() * rh + 18, 260, 48), Loc.t("back"), true)

func _draw_howto(vs: Vector2) -> void:
	_dim(vs, 0.78)
	_text(Vector2(0, vs.y * 0.1), Loc.t("how_to_play"), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 8)
	var top := Vector2(vs.x * 0.5, vs.y * 0.1 + 44)
	_draw_controls(top)
	var rows := 2 if get_meta("touch", false) else 7
	var y := top.y + rows * 24 + 30
	_text(Vector2(0, y), Loc.t("tips_title"), 18, C_PINK, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	var tw := minf(760.0, vs.x - 40.0)
	for k in ["tip_perfect", "tip_parry", "tip_execute", "tip_upgrades"]:
		y += 26
		_text(Vector2((vs.x - tw) * 0.5, y), "•  " + Loc.t(k), 15, Color(1, 1, 1, 0.82), HORIZONTAL_ALIGNMENT_CENTER, tw, 4)
	_draw_tiers(vs.x * 0.5, y + 44)
	_button("back", Rect2((vs.x - 260) * 0.5, minf(y + 80, vs.y - 64), 260, 48), Loc.t("back"), true)

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
	_text(Vector2(0, vs.y * 0.17), Loc.t("gift_title"), 40, Color(1, 0.92, 0.96, appear), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 8)
	_text(Vector2(0, vs.y * 0.17 + 30), Loc.t("gift_sub"), 16, Color(1, 0.5, 0.7, appear), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
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
		_text(Vector2(r.position.x, r.position.y + 150), Upgrades.title(id), 20, Color(1, 0.95, 0.97, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 5)
		draw_multiline_string(font, Vector2(r.position.x + 16, r.position.y + 182), Upgrades.desc(id), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x - 32, 15, 4, Color(0.85, 0.85, 0.95, a))
		var lv := Upgrades.level(player, id)
		var lvl_text := Loc.t("lvl_up", [lv, lv + 1]) if lv > 0 else (Loc.t("rare") if u.rare else Loc.t("new"))
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

## Threat-colour legend (matches the spirit tints in the enemy scripts).
const TIERS := [
	["tier_weak", Color(1.0, 0.36, 0.03)], ["tier_normal", Color(1.0, 0.03, 0.07)], ["tier_ranged", Color(1.0, 0.05, 0.42)],
	["tier_strong", Color(0.62, 0.1, 1.0)], ["tier_heavy", Color(0.95, 0.0, 0.02)], ["tier_elite", Color(1.0, 0.7, 0.12)],
]

func _draw_tiers(center_x: float, y: float) -> void:
	var w := minf(112.0, (get_viewport_rect().size.x - 40.0) / TIERS.size())
	var x0 := center_x - w * TIERS.size() * 0.5
	_text(Vector2(0, y - 14), Loc.t("tiers_title"), 12, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER, get_viewport_rect().size.x, 3)
	for i in TIERS.size():
		var c: Color = TIERS[i][1]
		var p := Vector2(x0 + i * w + 14, y + 4)
		draw_circle(p, 6, c)
		if TIERS[i][0] == "tier_heavy":
			draw_circle(p, 2.5, Color(1.0, 0.78, 0.12))   # colossi: blood body, molten eyes
		draw_arc(p, 9, 0, TAU, 16, Color(c.r, c.g, c.b, 0.5), 1.5)
		_text(p + Vector2(14, 5), Loc.t(TIERS[i][0]), 13, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)

func _draw_controls(top: Vector2) -> void:
	var rows := [
		["WASD", Loc.t("c_move")], [Loc.t("k_lmb"), Loc.t("c_attack")], [Loc.t("k_rmb"), Loc.t("c_heavy")],
		[Loc.t("k_space"), Loc.t("c_dash")], ["Q / E / R", Loc.t("ab_maelstrom") + " / " + Loc.t("ab_crescent") + " / " + Loc.t("ab_harvest")],
		["P", Loc.t("c_pause")],
	]
	if get_meta("touch", false):
		rows = [[Loc.t("c_touch_move"), Loc.t("c_touch_move2")], [Loc.t("c_touch_act"), Loc.t("c_touch_act2")]]
	for i in rows.size():
		var y := top.y + i * 24
		_text(Vector2(top.x - 410, y), rows[i][0], 16, C_PINK, HORIZONTAL_ALIGNMENT_RIGHT, 400, 4)
		_text(Vector2(top.x + 14, y), rows[i][1], 16, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
