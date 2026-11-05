## Composition root: builds the world, wires systems together and runs the
## flow: boot -> main menu -> play (pause / settings / upgrades) -> game over
## -> retry or menu. Platform hooks (game_ready, ads, pause) go through Plat.
extends Node

var world: Node3D
var player: Player
var director: WaveDirector
var hud: HUD
var touch: TouchControls
var camera: GameCamera
var _dead_t := -1.0
var _query := ""
var _autostart := false
var _env: Environment
var _user_paused := false
var _platform_paused := false
var _game_ready_t := -1.0
# tutorial (first run): step index into TUTORIAL, progress timers
const TUTORIAL := ["move", "attack", "dash", "heavy", "abilities", "done"]
var _tut_step := -1
var _tut_t := 0.0
var _tut_seen := {}
var _stats_t := 0.0

func _ready() -> void:
	Game.reset()
	FX.reset()
	_query = _url_query()

	world = Node3D.new()
	world.name = "World"
	add_child(world)
	Game.world = world

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.005, 0.004, 0.012)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.31, 0.36)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.25
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_strength = 1.0
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(3, 0.6)
	e.set_glow_level(4, 0.3)
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	e.adjustment_contrast = 1.08
	env.environment = e
	add_child(env)
	_env = e

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.66, 0.9)
	moon.light_energy = 1.0
	moon.rotation_degrees = Vector3(-58, 35, 0)
	moon.shadow_enabled = false
	world.add_child(moon)

	world.add_child(Arena.new())
	var em := EnemyManager.new()
	world.add_child(em)
	var proj := EnemyProjectiles.new()
	world.add_child(proj)
	var souls := SoulManager.new()
	world.add_child(souls)

	player = Player.new()
	world.add_child(player)
	player.position = Vector3(0, 0, 3)

	camera = GameCamera.new()
	camera.target = player
	world.add_child(camera)
	camera.make_current()

	director = WaveDirector.new()
	add_child(director)

	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	hud = HUD.new()
	hud.player = player
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(hud)
	touch = TouchControls.new()
	touch.player = player
	touch.hud = hud
	touch.visible = false
	layer.add_child(touch)
	if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		_enable_touch()

	Events.player_died.connect(func(): _dead_t = 0.0)
	Events.wave_cleared.connect(func(_n):
		get_tree().create_timer(1.1, false).timeout.connect(_offer_upgrades))
	Events.wave_started.connect(func(_n, boss): Sfx.play("boss_roar" if boss else "wave", 1.0, -3.0 if boss else -2.0))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_autostart = "rr_autostart" in _query or Game.retry_requested
	Game.retry_requested = false
	Loc.changed.connect(func(): hud.queue_redraw())
	apply_settings()
	_warmup.call_deferred()

func _warmup() -> void:
	FX.warmup(player.position)
	Game.enemies.warmup(player.position)
	FX.afterimage(player.rig, player.global_transform.translated(Vector3(0, -4, 0)))
	Game.souls.drop(player.position + Vector3(0, -3, 0), 0)

## After each wave: pause and let the player pick one of three upgrades.
func _offer_upgrades() -> void:
	if not Game.running or player.state == Player.State.DEAD or hud.mode != "play":
		return
	var ids := Upgrades.roll(player)
	if ids.is_empty():
		return
	hud.open_upgrades(ids)
	_set_paused(true)
	Sfx.play("upgrade", 1.0, -2.0)

func _choose_upgrade(i: int) -> void:
	if i < 0 or i >= hud.offer.size() or hud._offer_t < 0.35:
		return
	var id: String = hud.offer[i]
	Upgrades.apply(player, id)
	hud.set_mode("play")
	_set_paused(false)
	Sfx.play("charged", 1.2)
	FX.shockwave(player.position, 3.5, Upgrades.RARE_COLOR if Upgrades.LIST[id].rare else Upgrades.COMMON_COLOR, 0.5)
	Events.popup.emit(Upgrades.title(id), player.position + Vector3.UP * 2.5, Color(1, 0.85, 0.95), 1.0)
	Events.upgrade_chosen.emit(id)

func _enable_touch() -> void:
	touch.visible = true
	hud.set_meta("touch", true)
	player.input.using_touch = true
	# phones: larger UI so text stays readable (the 3D view is unaffected)
	get_tree().root.content_scale_factor = 1.3

func _url_query() -> String:
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		return str(q) if q != null else ""
	return " ".join(OS.get_cmdline_user_args())

func _query_int(key: String, fallback: int) -> int:
	var i := _query.find(key + "=")
	return int(_query.substr(i + key.length() + 1).split("&")[0]) if i != -1 else fallback

# ------------------------------------------------------------------ settings
## Applies Plat.save settings: audio, shake, graphics quality.
func apply_settings() -> void:
	Sfx.apply_settings()
	camera.shake_enabled = bool(Plat.save.shake)
	var high: bool = Plat.save.quality == "high"
	_env.glow_enabled = high
	FX.quality_cap = 1.0 if high else 0.5
	get_viewport().scaling_3d_scale = 1.0 if high else 0.75

# ------------------------------------------------------------------ flow
func _start() -> void:
	if Game.running or not Sfx.is_ready():
		return
	hud.set_mode("play")
	Game.running = true
	director.start(maxi(1, _query_int("rr_wave", 1)))
	Sfx.start_music()
	Plat.gameplay(true)
	if not bool(Plat.save.tutorial_done):
		_tut_step = 0
		_tut_t = 0.0
		director.set_process(false)   # first spirits arrive once the player has moved
		_show_tutorial()
	var n := _query_int("rr_stress", 0)
	if n > 0:
		_stress(n)

func _stress(n: int) -> void:
	var kinds := ["wisp", "wisp", "wraith", "wraith", "banshee", "shade", "brute"]
	for i in n:
		var p := Game.random_point_in_arena(2.0)
		if p.distance_to(player.position) < 5.0:
			p = player.position + (p - player.position).normalized() * 7.0
		Game.enemies.spawn(kinds[i % kinds.size()], p, 1.0, false, true)

## Pause requested by the player (menu) — the tree stays paused also while
## the platform pause is active.
func _set_paused(p: bool) -> void:
	_user_paused = p
	get_tree().paused = _user_paused or _platform_paused

## Called by Plat when the platform pauses (tab hidden, ad open).
func platform_pause(p: bool) -> void:
	_platform_paused = p
	if p and hud.mode == "play":
		_open_pause()
	get_tree().paused = _user_paused or _platform_paused

func _open_pause() -> void:
	hud.set_mode("paused")
	_set_paused(true)
	Plat.gameplay(false)

func _resume() -> void:
	hud.set_mode("play")
	_set_paused(false)
	Plat.gameplay(true)

## Leave the run: an interstitial at this natural pause, then reload.
func _leave_run(retry: bool) -> void:
	if hud.mode == "boot":
		return
	hud.set_mode("boot")
	Plat.gameplay(false)
	Plat.show_interstitial(func():
		_set_paused(false)
		Game.retry_requested = retry
		get_tree().reload_current_scene())

func _on_button(id: String) -> void:
	if id == "":
		return
	Sfx.play("click", randf_range(0.95, 1.05), -6.0)
	match id:
		"play": _start()
		"retry": _leave_run(true)
		"to_menu": _leave_run(false)
		"resume": _resume()
		"pause": _open_pause()
		"settings":
			hud.back_mode = hud.mode
			hud.set_mode("settings")
		"howto":
			hud.back_mode = hud.mode
			hud.set_mode("howto")
		"back":
			if hud.mode == "settings":
				Plat.write()
			hud.set_mode(hud.back_mode)
		"mute":
			Plat.save.muted = not bool(Plat.save.muted)
			Plat.write()
			apply_settings()
		"lang":
			Loc.next_lang()
			Plat.write()
		_:
			if id.begins_with("set_"):
				_setting(id.substr(4))

func _setting(key: String) -> void:
	var sv: Dictionary = Plat.save
	match key:
		"music_dec": sv.music = clampf(snappedf(float(sv.music) - 0.1, 0.1), 0.0, 1.0)
		"music_inc": sv.music = clampf(snappedf(float(sv.music) + 0.1, 0.1), 0.0, 1.0)
		"sfx_dec": sv.sfx = clampf(snappedf(float(sv.sfx) - 0.1, 0.1), 0.0, 1.0)
		"sfx_inc": sv.sfx = clampf(snappedf(float(sv.sfx) + 0.1, 0.1), 0.0, 1.0)
		"muted": sv.muted = not bool(sv.muted)
		"shake": sv.shake = not bool(sv.shake)
		"quality": sv.quality = "low" if sv.quality == "high" else "high"
		"lang": Loc.next_lang()
		"tutorial": sv.tutorial_done = false
	apply_settings()

# ------------------------------------------------------------------ input
## Menu buttons get clicks/taps before gameplay input (so the pause button
## never also swings the scythe).
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not touch.visible:
		_enable_touch()
	var click: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if click:
		if hud.mode == "upgrade":
			_choose_upgrade(hud.card_at(event.position))
			get_viewport().set_input_as_handled()
			return
		var id := hud.button_at(event.position)
		if id != "":
			_on_button(id)
			get_viewport().set_input_as_handled()
			return
		if hud.mode != "play":
			get_viewport().set_input_as_handled()   # menus swallow stray clicks

func _unhandled_input(event: InputEvent) -> void:
	var menu := hud.mode in ["menu", "settings", "howto", "paused", "dead"]
	if menu:
		if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right") and hud.mode != "settings":
			hud.move_focus(1)
		elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left") and hud.mode != "settings":
			hud.move_focus(-1)
		elif event.is_action_pressed("ui_accept"):
			_on_button(hud.focused_id())
		elif event.is_action_pressed("pause") and hud.mode == "paused":
			_resume()
		elif event.is_action_pressed("ui_cancel") and hud.mode in ["settings", "howto"]:
			_on_button("back")
		return
	match hud.mode:
		"upgrade":
			if event is InputEventKey and event.pressed and not event.echo:
				var k: int = event.physical_keycode
				if k >= KEY_1 and k <= KEY_3:
					_choose_upgrade(k - KEY_1)
		"play":
			if event.is_action_pressed("pause"):
				_open_pause()
			elif event.is_action_pressed("debug_stress"):
				_stress(60)

# ------------------------------------------------------------------ tutorial
func _show_tutorial() -> void:
	if _tut_step < 0 or _tut_step >= TUTORIAL.size():
		hud.tutorial_text = ""
		return
	var key: String = "tut_" + TUTORIAL[_tut_step]
	if hud.get_meta("touch", false) and TUTORIAL[_tut_step] != "done":
		key += "_touch"
	hud.tutorial_text = Loc.t(key)
	hud.tutorial_t = 0.0

func _tutorial(delta: float) -> void:
	if _tut_step < 0 or hud.mode != "play":
		return
	_tut_t += delta
	var done := false
	match TUTORIAL[_tut_step]:
		"move":
			if Vector2(player.velocity.x, player.velocity.z).length() > 2.0:
				_tut_seen.moved = _tut_seen.get("moved", 0.0) + delta
			done = _tut_seen.get("moved", 0.0) > 1.0
			if done:
				director.set_process(true)
		"attack":
			done = player._swings >= 3
		"dash":
			done = player.state == Player.State.DASH
		"heavy":
			done = player.state == Player.State.ATTACK and player.attack and player.attack.id == "execution"
		"abilities":
			done = player.state == Player.State.CAST or _tut_t > 8.0
		"done":
			done = _tut_t > 3.0
	if _tut_t > 20.0 and TUTORIAL[_tut_step] != "move":
		done = true   # never block the player on a prompt
	if done:
		_tut_step += 1
		_tut_t = 0.0
		if _tut_step >= TUTORIAL.size():
			_tut_step = -1
			Plat.save.tutorial_done = true
			Plat.write()
		_show_tutorial()

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	var rd := delta / maxf(Engine.time_scale, 0.01)
	if hud.mode == "boot" and Sfx.is_ready() and Plat.is_ready and not Game.running:
		hud.set_mode("menu")
		apply_settings()
		_game_ready_t = 0.0
	if _game_ready_t >= 0.0:
		_game_ready_t += rd
		if _game_ready_t > 0.1:      # the menu has been drawn: it is interactive
			_game_ready_t = -1.0
			Plat.game_ready()
	if _autostart and hud.mode == "menu":
		_autostart = false
		_start()
	_tutorial(delta)
	if _dead_t >= 0.0:
		_dead_t += rd
		if _dead_t > 1.4 and hud.mode == "play":
			hud.new_record = Plat.record_run(Game.stats.wave, Game.stats.kills, Game.stats.max_combo)
			hud.set_mode("dead")
			Game.running = false
			Plat.gameplay(false)
			_dead_t = -1.0
	_stats_t += rd
	if OS.has_feature("web") and "rr_" in _query and _stats_t > 0.4:
		_stats_t = 0.0
		# live stats for automated browser tests (only with rr_ debug params)
		JavaScriptBridge.eval("window.rrStats = {fps:%d, enemies:%d, kills:%d, hp:%d, wave:%d, draws:%d, mode:'%s'}" % [
			Engine.get_frames_per_second(), Game.enemies.alive_count() if Game.enemies else 0, Game.stats.kills,
			player.hp, Game.stats.wave, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), hud.mode], true)
	# adaptive quality: thin out particles if the frame rate drops
	var fps := Engine.get_frames_per_second()
	if fps > 0:
		FX.quality = minf(FX.quality_cap, lerpf(FX.quality, clampf((fps - 25.0) / 30.0, 0.35, 1.0), 0.02))
