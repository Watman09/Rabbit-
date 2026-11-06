## Renders every hero clip from the front and side (debug tool).
## xvfb-run godot --rendering-driver opengl3 -s res://tools/anim_preview.gd
extends SceneTree
const OUT = "user://anim_preview/"
var f := 0
var inst: Node3D
var ap: AnimationPlayer
var cam: Camera3D
var shots := []  # [anim, time, view]
var si := 0
func _init():
	DirAccess.make_dir_recursive_absolute(OUT)
	var r = Node3D.new(); get_root().add_child(r)
	inst = load("res://assets/models/hero_rigged.glb").instantiate(); r.add_child(inst)
	_dump(inst, 0)
	ap = inst.find_child("AnimationPlayer", true, false)
	print("anims: ", ap.get_animation_list())
	for a in ap.get_animation_list(): print(a, " len ", ap.get_animation(a).length)
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false)
	print("bones: ", sk.get_bone_count())
	var mi: MeshInstance3D = inst.find_child("Body", true, false)
	var arr = mi.mesh.surface_get_arrays(0)
	print("has colors: ", arr[Mesh.ARRAY_COLOR] != null, " sample ", arr[Mesh.ARRAY_COLOR][100] if arr[Mesh.ARRAY_COLOR] else null)
	var m = ShaderMaterial.new(); m.shader = load("res://assets/shaders/hero.gdshader"); mi.material_override = m
	var env = WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.25,0.25,0.3); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(1,1,1); r.add_child(env)
	var l = DirectionalLight3D.new(); l.rotation_degrees = Vector3(-30, 30, 0); r.add_child(l)
	var fl = MeshInstance3D.new(); var pm = PlaneMesh.new(); pm.size = Vector2(4,4); fl.mesh = pm; r.add_child(fl)
	cam = Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 2.2; r.add_child(cam)
	var clips = OS.get_cmdline_user_args() if OS.get_cmdline_user_args().size() > 0 else ap.get_animation_list()
	for a in clips:
		var n = 8 if a == "Run" else 4
		for i in n:
			for v in ["front", "side", "back"]:
				shots.append([a, ap.get_animation(a).length * i / (n - 1), v])
func _dump(n, d):
	if d < 4: print("  ".repeat(d), n.name, " ", n.get_class())
	for c in n.get_children(): _dump(c, d + 1)
func _process(dt):
	f += 1
	if f % 3 == 1:
		if si >= shots.size(): quit(); return false
		var s = shots[si]
		ap.play(s[0]); ap.seek(s[1], true); ap.pause()
		if s[2] == "front":
			cam.position = Vector3(0, 0.9, 4); cam.look_at(Vector3(0, 0.9, 0))
		elif s[2] == "back":
			cam.position = Vector3(0, 0.9, -4); cam.look_at(Vector3(0, 0.9, 0))
		else:
			cam.position = Vector3(4, 0.9, 0); cam.look_at(Vector3(0, 0.9, 0))
	if f % 3 == 0:
		var s = shots[si]
		get_root().get_texture().get_image().save_png(OUT + "%s_%02d_%s.png" % [s[0], si, s[2]])
		si += 1
	return false
