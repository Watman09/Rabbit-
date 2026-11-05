## Animation rig for the Reaper.
## * Body: skinned model rigged in Blender (tools/blender/rig_rabbit.py) with
##   clips Idle / Run / Dash / Hit / Death played by an AnimationPlayer.
## * Scythe: a separate mesh posed in code from a ScythePose (a few blendable
##   numbers), so swings are authored from AttackData and match the trails.
## * ReaperIK (SkeletonModifier3D) twists the upper body toward the swing and
##   keeps both hands on the shaft with two-bone IK.
class_name PlayerRig
extends Node3D

const HERO_SCENE := preload("res://assets/models/hero_rigged.glb")
const SCYTHE_MESH := preload("res://assets/models/hero_scythe.res")
const HERO_SHADER := preload("res://assets/shaders/hero.gdshader")
const GHOST_SHADER := preload("res://assets/shaders/ghost.gdshader")

## Grip position of the scythe in the original model (metres).
const GRIP := Vector3(0.2414, 0.9625, 0.2786)
const SCYTHE_SCALE := 1.3
const EYE_POS := Vector3(0.048, 1.385, 0.145)

class ScythePose:
	var tilt := 0.0      # swing plane tilt (deg)
	var height := 0.96
	var yaw := 40.9      # scythe orbit angle around the body (deg)
	var reach := 0.369
	var pitch := 0.0
	var spin := 0.0
	var roll := 0.0
	var body_yaw := 0.0
	var lean := 0.0
	var bob := 0.0
	var squash := 1.0
	var sscale := 1.3    # scythe scale (grows during swings)
	var choke := 0.0     # how far down the shaft the main hand slides (mesh units)

	func copy() -> ScythePose:
		var p := ScythePose.new()
		p.tilt = tilt; p.height = height; p.yaw = yaw; p.reach = reach
		p.pitch = pitch; p.spin = spin; p.roll = roll; p.body_yaw = body_yaw
		p.lean = lean; p.bob = bob; p.squash = squash; p.sscale = sscale; p.choke = choke
		return p

	func blend(o: ScythePose, t: float) -> ScythePose:
		var p := ScythePose.new()
		p.tilt = lerpf(tilt, o.tilt, t); p.height = lerpf(height, o.height, t)
		p.yaw = lerpf(yaw, o.yaw, t); p.reach = lerpf(reach, o.reach, t)
		p.pitch = lerpf(pitch, o.pitch, t); p.spin = lerpf(spin, o.spin, t)
		p.roll = lerpf(roll, o.roll, t); p.body_yaw = lerpf(body_yaw, o.body_yaw, t)
		p.lean = lerpf(lean, o.lean, t); p.bob = lerpf(bob, o.bob, t)
		p.squash = lerpf(squash, o.squash, t)
		p.sscale = lerpf(sscale, o.sscale, t)
		p.choke = lerpf(choke, o.choke, t)
		return p

	static func make(d: Dictionary) -> ScythePose:
		var p := ScythePose.new()
		for k in d:
			p.set(k, d[k])
		return p

var body: Node3D
var body_mesh: MeshInstance3D
var swing_plane: Node3D
var scythe_root: Node3D
var scythe_arm: Node3D
var scythe_mesh: MeshInstance3D
var scythe_align: Node3D
var blade_light: OmniLight3D
var body_mat: ShaderMaterial
var scythe_mat: ShaderMaterial
var eyes: Array[MeshInstance3D] = []
var skeleton: Skeleton3D
var anim: AnimationPlayer
var ik: ReaperIK
var anim_state := ""
var _arm_len := 0.5
var _ghosts: Array[Node3D] = []
var _ghost_t: Array[float] = []
var _ghost_i := 0
const STAFF_DIR := Vector3(0.216, 0.970, 0.111)   # shaft axis in scythe-mesh space

var pose := ScythePose.new()
var scythe_glow := 0.0
var flash := 0.0

static var POSE_IDLE := ScythePose.make({})
static var POSE_READY := ScythePose.make({"sscale": 1.4, "choke": 0.3, "yaw": 62.0, "reach": 0.5, "pitch": 48.0, "roll": -18.0, "height": 0.98, "lean": 0.08})
static var POSE_RUN := ScythePose.make({"yaw": 128.0, "reach": 0.42, "pitch": -58.0, "roll": 10.0, "height": 0.92, "lean": 0.2})

func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var hero := HERO_SCENE.instantiate()
	body.add_child(hero)
	skeleton = hero.find_child("Skeleton3D", true, false)
	anim = hero.find_child("AnimationPlayer", true, false)
	body_mesh = hero.find_child("Body", true, false)
	body_mat = ShaderMaterial.new()
	body_mat.shader = HERO_SHADER
	body_mat.set_shader_parameter("cloth_height", 1.05)
	body_mat.set_shader_parameter("rim_strength", 1.5)
	body_mat.set_shader_parameter("rim_color", Color(0.55, 0.4, 1.0))
	body_mat.set_shader_parameter("glow_strength", 0.8)
	body_mat.set_shader_parameter("sway", 0.5)
	body_mesh.material_override = body_mat
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_setup_clips(anim)
	ik = ReaperIK.new()
	skeleton.add_child(ik)
	_arm_len = ik.arm_length("L") if skeleton.find_bone("upper_arm.L") >= 0 else 0.5

	# eyes follow the head bone
	var head_att := BoneAttachment3D.new()
	head_att.bone_name = "head"
	skeleton.add_child(head_att)
	var head_rest := skeleton.get_bone_global_rest(skeleton.find_bone("head"))
	for side in [-1.0, 1.0]:
		var e := FX.make_glow_sprite(Color(1.0, 0.08, 0.12, 1.0), 0.16)
		e.position = head_rest.affine_inverse() * Vector3(EYE_POS.x * side, EYE_POS.y, EYE_POS.z)
		head_att.add_child(e)
		eyes.append(e)
	play("Idle")

	swing_plane = Node3D.new()
	add_child(swing_plane)
	scythe_root = Node3D.new()
	swing_plane.add_child(scythe_root)
	scythe_arm = Node3D.new()
	scythe_root.add_child(scythe_arm)
	var align := Node3D.new()
	align.rotation.y = -deg_to_rad(POSE_IDLE.yaw)
	align.scale = Vector3.ONE * SCYTHE_SCALE
	scythe_arm.add_child(align)
	scythe_align = align
	scythe_mesh = MeshInstance3D.new()
	scythe_mesh.mesh = SCYTHE_MESH
	scythe_mat = ShaderMaterial.new()
	scythe_mat.shader = HERO_SHADER
	scythe_mat.set_shader_parameter("sway", 0.0)
	scythe_mat.set_shader_parameter("rim_strength", 0.6)
	scythe_mesh.material_override = scythe_mat
	scythe_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	align.add_child(scythe_mesh)

	# soft violet pool of light under the Reaper for readability in crowds
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.2, 3.2)
	pool.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://assets/shaders/ground_fx.gdshader")
	gm.set_shader_parameter("mode", 5)
	gm.set_shader_parameter("fade", 1.6)
	gm.set_shader_parameter("color", Color(0.35, 0.2, 0.8))
	pool.material_override = gm
	pool.position.y = 0.03
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)

	blade_light = OmniLight3D.new()
	blade_light.light_color = Color(0.85, 0.25, 1.0)
	blade_light.omni_range = 5.0
	blade_light.light_energy = 1.2
	blade_light.position = Vector3(-0.1, 0.65, 0.0)
	scythe_mesh.add_child(blade_light)
	_apply()

## Blend toward a target pose (exponential smoothing).
func blend_to(target: ScythePose, delta: float, sharpness := 14.0) -> void:
	pose = pose.blend(target, 1.0 - exp(-sharpness * delta))

func set_pose(p: ScythePose) -> void:
	pose = p

## Pose during an attack. t: 0 at windup start; phase handled by the caller.
static func attack_pose(a: AttackData, sweep_yaw: float, lean: float) -> ScythePose:
	var p := ScythePose.new()
	p.tilt = a.plane_tilt
	p.height = a.height
	p.yaw = sweep_yaw
	p.reach = a.reach
	p.sscale = 1.55
	p.choke = 0.62
	p.pitch = a.pitch
	p.spin = a.spin
	p.roll = 0.0
	p.body_yaw = sweep_yaw if a.body_spin else sweep_yaw * a.body_twist
	p.lean = lean
	return p

static func _setup_clips(ap: AnimationPlayer) -> void:
	# loop the locomotion clips; trim the duplicated last key of Blender cycles
	for n in ["Idle", "Run", "Dash"]:
		if ap.has_animation(n):
			var a := ap.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR
			a.length = maxf(a.length - 1.0 / 30.0, 0.05)

## Cross-fade to a clip (no-op if already playing).
func play(clip: String, blend := 0.15, speed := 1.0) -> void:
	anim.speed_scale = speed
	if anim_state == clip:
		return
	anim_state = clip
	anim.play(clip, blend)

## Clip/speed selection from movement. speed in m/s.
func locomotion(speed: float, busy: bool) -> void:
	if busy:
		play("Idle", 0.2, 1.0)
	elif speed > 1.0:
		# ~2.2 m per two-step cycle of the Run clip
		play("Run", 0.18, clampf(speed / 3.3, 0.7, 2.6))
	else:
		play("Idle", 0.25, 1.0)

func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 6.0)
	_apply()
	for i in _ghosts.size():
		if _ghosts[i].visible:
			_ghost_t[i] -= delta
			var a := maxf(_ghost_t[i] / 0.28, 0.0)
			((_ghosts[i].get_meta("mesh") as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("alpha", a * 0.8)
			if _ghost_t[i] <= 0.0:
				_ghosts[i].visible = false

func _apply() -> void:
	swing_plane.position = Vector3(0, pose.height, 0)
	swing_plane.basis = Basis(Vector3(0, 0, 1), deg_to_rad(pose.tilt))
	scythe_root.rotation = Vector3(0, deg_to_rad(pose.yaw), 0)
	scythe_arm.position = Vector3(0, 0, pose.reach)
	scythe_arm.basis = Basis(Vector3(0, 0, 1), deg_to_rad(pose.roll)) \
		* Basis(Vector3(1, 0, 0), deg_to_rad(pose.pitch)) \
		* Basis(Vector3(0, 1, 0), deg_to_rad(pose.spin))
	scythe_align.scale = Vector3.ONE * pose.sscale
	scythe_mesh.position = STAFF_DIR.normalized() * pose.choke
	# upper body twists toward the swing (limited), the rest turns the hips
	var twist := clampf(pose.body_yaw * 0.6, -55.0, 55.0)
	body.rotation = Vector3(pose.lean * 0.5, deg_to_rad(pose.body_yaw - twist), 0)
	if ik:
		ik.twist_deg = twist
		ik.lean = pose.lean * 0.6
		_bind_hands()
	body.position.y = pose.bob
	body.scale = Vector3(1.0 / sqrt(pose.squash), pose.squash, 1.0 / sqrt(pose.squash))
	scythe_mat.set_shader_parameter("glow_strength", 1.4 + scythe_glow * 4.0)
	scythe_mat.set_shader_parameter("flash", flash * 0.5)
	body_mat.set_shader_parameter("flash", flash)
	blade_light.light_energy = 1.0 + scythe_glow * 2.5

## Apply the current pose immediately (callers that read blade positions this frame).
func apply_now() -> void:
	_apply()

## Keeps the scythe in the main hand's reach and feeds the IK targets.
func _bind_hands() -> void:
	if not is_inside_tree():
		return
	var grip := scythe_arm.global_position
	var shoulder := ik.shoulder_world("L")
	var reach := _arm_len * global_transform.basis.get_scale().x * 0.97
	var off := grip - shoulder
	if off.length() > reach:
		# out of reach: pull the whole scythe toward the hand instead of letting it float
		var delta := shoulder + off.normalized() * reach - grip
		swing_plane.global_position += delta
		grip += delta
	ik.grip_target = grip
	ik.grip_weight = 1.0
	# off hand grabs the shaft lower down while fighting
	var axis := (scythe_align.global_basis * STAFF_DIR).normalized()
	ik.off_target = grip - axis * 0.28 * pose.sscale
	var want_off := smoothstep(0.2, 0.5, pose.choke)
	var oshoulder := ik.shoulder_world("R")
	if ik.off_target.distance_to(oshoulder) > reach * 1.25:
		want_off *= 0.35
	ik.off_weight = lerpf(ik.off_weight, want_off, 0.25)

func set_ghost(v: float) -> void:
	body_mat.set_shader_parameter("ghost", v)

func set_drag(local_vel: Vector3) -> void:
	body_mat.set_shader_parameter("drag", local_vel * 0.05)

## Dash afterimage: a pooled copy of the body frozen in the Dash pose.
func spawn_afterimage(xf: Transform3D) -> void:
	var g: Node3D
	if _ghosts.size() < 6:
		g = HERO_SCENE.instantiate() as Node3D
		get_tree().current_scene.add_child(g)
		var m: MeshInstance3D = g.find_child("Body", true, false)
		var mat := ShaderMaterial.new()
		mat.shader = GHOST_SHADER
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ap: AnimationPlayer = g.find_child("AnimationPlayer", true, false)
		ap.play("Dash")
		ap.seek(0.05, true)
		ap.pause()
		g.set_meta("mesh", m)
		_ghosts.append(g)
		_ghost_t.append(0.0)
	else:
		g = _ghosts[_ghost_i]
		_ghost_i = (_ghost_i + 1) % _ghosts.size()
	g.global_transform = xf * Transform3D(Basis.from_scale(scale), Vector3.ZERO) * body.transform
	g.visible = true
	_ghost_t[_ghosts.find(g)] = 0.28

func free_afterimages() -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()

func _exit_tree() -> void:
	free_afterimages()

## World-space point of the blade tip (for effects).
func blade_point() -> Vector3:
	return blade_light.global_position
