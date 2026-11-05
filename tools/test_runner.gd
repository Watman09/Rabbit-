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
			for r in g.enemies._renderers.values(): r.visible = false
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
		g.player.position = Vector3(7, 0, 1)
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
