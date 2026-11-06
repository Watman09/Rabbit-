## Prints ankle/knee/toe positions of the left leg across a clip (gait check).
## godot --headless -s res://tools/leg_check.gd -- Run
extends SceneTree
var inst; var sk: Skeleton3D; var ap: AnimationPlayer; var f := 0; var i := 0
var clip := "Run"
func _initialize():
	inst = load("res://assets/models/hero_rigged.glb").instantiate()
	root.add_child(inst)
	sk = inst.find_child("Skeleton3D", true, false)
	ap = inst.find_child("AnimationPlayer", true, false)
	var args = OS.get_cmdline_user_args()
	if args.size() > 0: clip = args[0]
func _process(d):
	f += 1
	if f == 2:
		var fl := sk.find_bone("foot.L")
		print("rest ankle ", sk.get_bone_global_rest(fl).origin, " rest toe ", sk.get_bone_global_rest(fl).basis.y)
	if f >= 3 and f % 2 == 1:
		var t := ap.get_animation(clip).length * i / 10.0
		ap.play(clip); ap.seek(t, true); ap.pause()
	if f >= 4 and f % 2 == 0:
		var fl := sk.find_bone("foot.L"); var sl := sk.find_bone("shin.L")
		var ankle := sk.get_bone_global_pose(fl).origin
		var knee := sk.get_bone_global_pose(sl).origin
		var toe := sk.get_bone_global_pose(fl).basis.y
		print("%s t=%.2f ankle x=%.3f y=%.3f z=%.3f | knee x=%.3f z=%.3f | toe x=%.2f y=%.2f z=%.2f" % [clip, ap.current_animation_position, ankle.x, ankle.y, ankle.z, knee.x, knee.z, toe.x, toe.y, toe.z])
		i += 1
		if i >= 10: quit()
	return false
