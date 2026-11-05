## Composition root: builds the world, wires systems together and runs the
## simple title -> play -> death -> restart flow.
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
	e.ambient_light_color = Color(0.17, 0.16, 0.26)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_strength = 1.0
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 0.9
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

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.45, 0.55, 1.0)
	moon.light_energy = 0.75
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
	if DisplayServer.is_touchscreen_available() and OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		_enable_touch()

	Events.player_died.connect(func(): _dead_t = 0.0)
	Events.wave_cleared.connect(func(_n):
		get_tree().create_timer(1.1, false).timeout.connect(_offer_upgrades))
	Events.wave_started.connect(func(_n, boss): Sfx.play("boss_roar" if boss else "wave", 1.0, -3.0 if boss else -2.0))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_autostart = "autostart" in _query
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
	get_tree().paused = true
	Sfx.play("upgrade", 1.0, -2.0)

func _choose_upgrade(i: int) -> void:
	if i < 0 or i >= hud.offer.size() or hud._offer_t < 0.35:
		return
	var id: String = hud.offer[i]
	Upgrades.apply(player, id)
	hud.mode = "play"
	get_tree().paused = false
	Sfx.play("charged", 1.2)
	FX.shockwave(player.position, 3.5, Upgrades.RARE_COLOR if Upgrades.LIST[id].rare else Upgrades.COMMON_COLOR, 0.5)
	Events.popup.emit(Upgrades.LIST[id].name, player.position + Vector3.UP * 2.5, Color(1, 0.85, 0.95), 1.0)
	Events.upgrade_chosen.emit(id)

func _enable_touch() -> void:
	touch.visible = true
	hud.set_meta("touch", true)
	player.input.using_touch = true

func _url_query() -> String:
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		return str(q) if q != null else ""
	var args := " ".join(OS.get_cmdline_user_args())
	return args

func _start() -> void:
	if Game.running or not Sfx.is_ready():
		return
	hud.mode = "play"
	Game.running = true
	var w := _query.find("wave=")
	director.start(maxi(1, int(_query.substr(w + 5).split("&")[0])) if w != -1 else 1)
	Sfx.start_music()
	var m := _query.find("stress=")
	if m != -1:
		_stress(int(_query.substr(m + 7).split("&")[0]))

func _stress(n: int) -> void:
	var kinds := ["wisp", "wisp", "wraith", "wraith", "banshee", "shade", "brute"]
	for i in n:
		var p := Game.random_point_in_arena(2.0)
		if p.distance_to(player.position) < 5.0:
			p = player.position + (p - player.position).normalized() * 7.0
		Game.enemies.spawn(kinds[i % kinds.size()], p, 1.0, false, true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not touch.visible:
		_enable_touch()
	var start_press: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventScreenTouch and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	match hud.mode:
		"title":
			if start_press:
				_start()
				get_viewport().set_input_as_handled()
		"dead":
			if start_press and _dead_t > 1.2:
				get_tree().paused = false
				get_tree().reload_current_scene()
		"upgrade":
			if event is InputEventKey and event.pressed and not event.echo:
				var k: int = event.physical_keycode
				if k >= KEY_1 and k <= KEY_3:
					_choose_upgrade(k - KEY_1)
			elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
				_choose_upgrade(hud.card_at(event.position))
		"play", "paused":
			if event.is_action_pressed("pause"):
				var paused := not get_tree().paused
				get_tree().paused = paused
				hud.mode = "paused" if paused else "play"
			elif event.is_action_pressed("debug_stress") and hud.mode == "play":
				_stress(60)

func _process(delta: float) -> void:
	if _autostart and Sfx.is_ready():
		_autostart = false
		_start()
	if _dead_t >= 0.0:
		_dead_t += delta / maxf(Engine.time_scale, 0.01)
		if _dead_t > 1.4 and hud.mode != "dead":
			hud.mode = "dead"
			Game.running = false
	if OS.has_feature("web") and Engine.get_process_frames() % 30 == 0:
		# exposes live stats for automated browser tests (window.rrStats)
		JavaScriptBridge.eval("window.rrStats = {fps:%d, enemies:%d, kills:%d, hp:%d, wave:%d, process_ms:%.2f, draws:%d, mode:'%s'}" % [
			Engine.get_frames_per_second(), Game.enemies.alive_count() if Game.enemies else 0, Game.stats.kills,
			player.hp, Game.stats.wave, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), hud.mode], true)
	# adaptive quality: thin out particles if the frame rate drops
	var fps := Engine.get_frames_per_second()
	if fps > 0:
		FX.quality = lerpf(FX.quality, clampf((fps - 25.0) / 30.0, 0.35, 1.0), 0.02)
