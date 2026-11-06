## Automated smoke test / screenshot tool (not part of the game).
## godot -s res://tools/test_runner.gd -- [out_dir] [scenario]
## Simulates a play session with scripted input and saves screenshots.
extends SceneTree

var out := "/tmp/rr_shots"
var scenario := "combat"
var frame := 0
var t := 0.0
var main: Node
var shots := []
var _errors := 0
var fx_us := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	if args.size() > 1: scenario = args[1]
	if "run" in args: set_meta("run_film", true)
	if "noparticles" in args: root.get_node("FX").particles_enabled = false
	if "nospirits" in args: set_meta("nospirits", true)
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _process(delta: float) -> bool:
	frame += 1
	t += 1.0 / 60.0
	var g = root.get_node("Game")
	var p = g.player
	if frame == 30:
		# wait for sfx synthesis then start
		pass
	if scenario == "runside":
		_runside(g)
		return false
	if scenario == "touchbug":
		_touchbug(g)
		return false
	if scenario == "menus":
		_menus(g)
		return false
	if scenario == "film":
		_film(g)
		return false
	if scenario == "reactions":
		_reactions(g)
		return false
	if scenario == "spirits":
		_spirits(g)
		return false
	if scenario == "pose":
		_pose(g)
		return false
	if frame > 30 and not g.running and root.get_node("Sfx").is_ready():
		main._start()
		if scenario == "boss":
			main.director.start(10)
			return false
		if scenario == "stress":
			main._stress(120)
		else:
			main._stress(18)
	if g.running and p:
		_drive(p)
		if has_meta("nospirits"):
			for pr in g.enemies._renderers.values():
				for r in pr: r.visible = false
	if scenario == "stress" and g.running and frame % 60 == 0 and g.enemies.alive_count() < 100:
		main._stress(40)
	if frame % 60 == 0 and g.enemies:
		print("proc=%.2fms t=%.1f fps=%d enemies=%d hp=%d kills=%d souls=%d state=%d draw=%d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, t, Engine.get_frames_per_second(), g.enemies.alive_count(), p.hp, g.stats.kills, p.souls_total, p.state,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if scenario == "boss" and g.running:
		for e in g.enemies.all:
			if e.is_boss and e.alive and frame % 240 == 0:
				e.take_hit(DamageInfo.make(e.max_hp * 0.3, e.position, 0.0, 0.0))
				print("boss hp ratio ", e.hp / e.max_hp, " phase ", e.phase_n, " mode ", e.mode)
	for s in [90, 150, 200, 260, 330, 420, 520, 700, 900, 1100]:
		if frame == s:
			root.get_texture().get_image().save_png("%s/shot_%04d.png" % [out, frame])
	if frame > (1150 if scenario == "boss" else 600):
		quit()
	return false

func _drive(p) -> void:
	# keep the player alive for testing
	p.hp = maxf(p.hp, 60.0)
	var inp = p.input
	var near = null
	var best := 1e9
	for e in root.get_node("Game").enemies.query_radius(p.position, 30.0):
		var d = e.position.distance_to(p.position)
		if d < best:
			best = d; near = e
	if near:
		var dir = (near.position - p.position); dir.y = 0
		inp.touch_move = dir.normalized() * (1.0 if best > 2.5 else 0.0)
	var k := frame % 120
	if k in [0, 12, 24, 36]:
		inp.press("attack")
	if frame % 240 == 60: inp.press("ability_1")
	if frame % 200 == 100: inp.press("ability_2")
	if frame % 180 == 150: inp.press("dash")
	if frame % 300 == 200:
		p.soul_meter = 100.0
		inp.press("ability_3")

var pose_shots := {40: "idle", 78: "reap_mid", 81: "reap_end", 106: "ret_mid", 132: "rise", 168: "whirl", 230: "charge", 264: "heavy", 300: "run", 340: "maelstrom", 401: "dash"}
func _pose(g) -> void:
	var p = g.player
	var cam = g.camera
	if frame == 2:
		cam.distance = 7.0
		cam.pitch_deg = 45.0
		cam.look_ahead = 0.0
		main.hud.visible = false
	var inp = p.input
	inp.aim = Vector3(0, 0, 1)
	match frame:
		70, 95, 120, 150: inp.press("attack")
		200: inp.press("heavy"); inp.touch_heavy = true
		255: inp.touch_heavy = false
		270: inp.touch_move = Vector3(1, 0, 0)
		320: inp.touch_move = Vector3.ZERO; inp.press("ability_1")
		398: inp.press("dash")
	if pose_shots.has(frame):
		root.get_texture().get_image().save_png("%s/pose_%s.png" % [out, pose_shots[frame]])
	if frame > 410:
		quit()

func _spirits(g) -> void:
	if frame == 2:
		g.ai_frozen = true
		main.hud.visible = false
		g.camera.distance = 13.0
		g.camera.pitch_deg = 56.0
		g.camera.look_ahead = 0.0
		g.player.position = Vector3(0, 0, 9)
		g.camera.target = null
		g.camera._focus = Vector3(0, 0, 0)
		var kinds = ["wisp", "wraith", "banshee", "shade", "brute"]
		for i in kinds.size():
			g.enemies.spawn(kinds[i], Vector3(-5 + i * 2.2, 0, 2.0), 1.0, false, true)
		g.enemies.spawn("wraith", Vector3(-3, 0, -1.5), 1.0, true, true)
		g.enemies.spawn("boss", Vector3(2.0, 0, -2.0), 1.0, false, true)
	if frame == 60:
		root.get_texture().get_image().save_png("%s/spirits.png" % out)
	if frame == 62:
		for e in g.enemies.all:
			e.take_hit(DamageInfo.make(5.0, e.position + Vector3(1, 0, 0), 3.0, 0.0))
	if frame == 64:
		root.get_texture().get_image().save_png("%s/spirits_hit.png" % out)
	if frame == 70:
		for e in g.enemies.all:
			if e.kind != "boss": e.take_hit(DamageInfo.make(9999.0, e.position + Vector3(1, 0, 0), 8.0, 0.0))
	if frame == 80:
		root.get_texture().get_image().save_png("%s/spirits_die.png" % out)
	if frame == 90:
		quit()

var _elite = null
func _reactions(g) -> void:
	var p = g.player
	var inp = p.input
	if frame == 2:
		g.ai_frozen = true
		g.camera.distance = 11.0
		p.position = Vector3(0, 0, 3)
		inp.using_touch = true   # auto-aim at the nearest spirit
	if frame == 30:
		main._start()
		main.director.set_process(false)
	# 1) perfect dodge: bolt straight at the player, dash just before it lands
	if frame == 40:
		g.projectiles.fire(p.position + Vector3(0, 1.0, -3.0), Vector3(0, 0, 12.0), 10.0, Color.RED)
	if frame == 47:
		inp.touch_move = Vector3(1, 0, 0)
		inp.press("dash")
	if frame == 56:
		root.get_texture().get_image().save_png("%s/r1_perfect.png" % out)
	if frame == 60:
		inp.touch_move = Vector3.ZERO
		print("perfect=", g.stats.get("perfect", 0), " crit_t=", p.crit_t)
	# 2) parry: bolt toward the player, swing into it
	if frame == 110:
		_elite = g.enemies.spawn("wraith", p.position + Vector3(2.5, 0, -4), 1.0, true, true)
		g.projectiles.fire(p.position + Vector3(0, 1.0, -4.0), Vector3(0, 0, 5.0), 10.0, Color.RED)
	if frame == 128:
		inp.aim = Vector3(0, 0, -1)
		inp.press("attack")
	if frame == 136:
		root.get_texture().get_image().save_png("%s/r2_parry.png" % out)
	if frame == 170:
		print("parries=", g.stats.get("parries", 0), " elite hp ", _elite.hp, "/", _elite.max_hp)
	# 3) stun + execution
	if frame == 180 and is_instance_valid(_elite):
		_elite.take_hit(DamageInfo.make(_elite.hp - _elite.max_hp * 0.2, _elite.position + Vector3(0, 0, 1), 0.0, 0.0))
		print("stunned=", _elite.stunned)
	if frame == 195:
		root.get_texture().get_image().save_png("%s/r3_stunned.png" % out)
		inp.press("attack")
	for f in [203, 212, 220, 232]:
		if frame == f:
			root.get_texture().get_image().save_png("%s/r4_exec_%d.png" % [out, f])
	if frame == 260:
		print("executions=", g.stats.get("executions", 0), " kills=", g.stats.kills)
	# 4) upgrade screen
	if frame == 270:
		main._offer_upgrades()
	if frame == 300:
		root.get_texture().get_image().save_png("%s/r5_upgrades.png" % out)
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_2; ev.pressed = true
		main._unhandled_input(ev)
		print("upgrades=", p.upgrades, " paused=", paused)
	if frame == 320:
		quit()

## Filmstrip of the full light combo from a low 3/4 camera.
func _film(g) -> void:
	var p = g.player
	var inp = p.input
	if frame == 2:
		main.hud.visible = false
		g.camera.distance = 6.0
		g.camera.pitch_deg = 35.0
		g.camera.look_ahead = 0.0
		inp.using_touch = true
	inp.touch_move = Vector3.ZERO
	p.facing = Vector3(1, 0, 0) if frame < 60 else p.facing
	if frame in [60, 76, 92, 108]:
		inp.aim = Vector3(1, 0, 0)
		inp.press("attack")
	if has_meta("run_film") and frame > 30:
		var a := frame * 0.05
		inp.touch_move = Vector3(cos(a), 0, sin(a))
	if frame >= 58 and frame <= 150 and frame % 3 == 0:
		root.get_texture().get_image().save_png("%s/film_%03d.png" % [out, frame])
	if frame > 152:
		quit()

## Screenshots of every menu screen in the language given as 3rd argument.
func _menus(g) -> void:
	var args := OS.get_cmdline_user_args()
	var lang: String = args[2] if args.size() > 2 else "en"
	var shots := {60: "menu", 90: "settings", 120: "howto", 160: "play", 190: "paused", 230: "upgrade", 345: "dead"}
	if frame == 2:
		root.get_node("Loc").set_lang(lang)
	match frame:
		80: main._on_button("settings")
		110:
			main._on_button("back")
			main._on_button("howto")
		140:
			main._on_button("back")
			main._on_button("play")
		180: main._on_button("pause")
		210:
			main._on_button("resume")
			main._offer_upgrades()
		250:
			main._choose_upgrade(0)
			g.player.hp = 1.0
			g.player.take_damage(50.0, g.player.position + Vector3(1, 0, 0))
	if shots.has(frame):
		root.get_texture().get_image().save_png("%s/m_%s_%s.png" % [out, lang, shots[frame]])
	if frame > 350:
		quit()

## Regression: a finger lifted while the upgrade screen is open must not leave
## the touch joystick stuck (phones could not move after picking a gift).
func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx; e.position = pos; e.pressed = pressed
	_feed(e)

func _drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx; e.position = pos; e.relative = Vector2(10, 0)
	_feed(e)

## Same order as the engine's _input pass: touch controls (deeper) first, then Main.
func _feed(e: InputEvent) -> void:
	main.touch._input(e)
	main._input(e)

func _touchbug(g) -> void:
	var p = g.player
	match frame:
		5:
			main._enable_touch()
		40:
			main._on_button("play")
			main.director.set_process(false)
		60:
			_touch(0, Vector2(200, 450), true)
		62:
			_drag(0, Vector2(260, 450))
		64:
			print("f64 mode=", main.hud.mode, " stick=", main.touch._stick_id, " vis=", main.touch.visible, " running=", g.running)
		70:
			print("before gift: move=", p.input.touch_move)
			main._offer_upgrades()
		80:
			_touch(0, Vector2(260, 450), false)   # finger lifted while the gift screen is open
		120:
			main._choose_upgrade(0)
		130:
			_touch(1, Vector2(220, 460), true)
		132:
			_drag(1, Vector2(150, 460))
		140:
			print("after gift: move=", p.input.touch_move, " mode=", main.hud.mode, " vel=", p.velocity)
		141:
			quit()

## Side view of the run cycle (legs check). Pass "nomask" to see the old shader.
func _runside(g) -> void:
	var p = g.player
	if frame == 2:
		main.hud.visible = false
		g.ai_frozen = true
		main.director.set_process(false)
		g.camera.target = null
		g.camera.set_process(false)
		p.position = Vector3(-10, 0, 6)
		if "nomask" in OS.get_cmdline_user_args():
			p.rig.body_mat.set_shader_parameter("use_cloth_mask", false)
	if frame > 2:
		p.input.touch_move = Vector3(1, 0, 0)
		var cam = g.camera
		cam.global_position = p.global_position + Vector3(0, 1.2, 5.5)
		cam.look_at(p.global_position + Vector3(0, 0.8, 0), Vector3.UP)
	if frame >= 70 and frame < 94 and frame % 3 == 0:
		root.get_texture().get_image().save_png("%s/run_%03d.png" % [out, frame])
	if frame > 95:
		quit()
