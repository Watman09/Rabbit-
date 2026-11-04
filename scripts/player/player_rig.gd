## Procedural animation rig for the Reaper. The source model is a static mesh,
## so the body and scythe are posed in code: every pose is a small set of
## numbers (ScythePose) that can be blended, which makes swings easy to author
## from AttackData. When a skinned model arrives, this class is the only thing
## that needs replacing.
class_name PlayerRig
extends Node3D

const BODY_MESH := preload("res://assets/models/hero_body.res")
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

	func copy() -> ScythePose:
		var p := ScythePose.new()
		p.tilt = tilt; p.height = height; p.yaw = yaw; p.reach = reach
		p.pitch = pitch; p.spin = spin; p.roll = roll; p.body_yaw = body_yaw
		p.lean = lean; p.bob = bob; p.squash = squash; p.sscale = sscale
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

var pose := ScythePose.new()
var scythe_glow := 0.0
var flash := 0.0

static var POSE_IDLE := ScythePose.make({})
static var POSE_READY := ScythePose.make({"sscale": 1.45, "yaw": 62.0, "reach": 0.5, "pitch": 48.0, "roll": -18.0, "height": 0.98, "lean": 0.08})
static var POSE_RUN := ScythePose.make({"yaw": 128.0, "reach": 0.42, "pitch": -58.0, "roll": 10.0, "height": 0.92, "lean": 0.2})

func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = BODY_MESH
	body_mat = ShaderMaterial.new()
	body_mat.shader = HERO_SHADER
	body_mat.set_shader_parameter("cloth_height", 1.05)
	body_mat.set_shader_parameter("rim_strength", 0.75)
	body_mat.set_shader_parameter("glow_strength", 0.8)
	body_mesh.material_override = body_mat
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(body_mesh)

	for side in [-1.0, 1.0]:
		var e := FX.make_glow_sprite(Color(1.0, 0.08, 0.12, 1.0), 0.16)
		e.position = Vector3(EYE_POS.x * side, EYE_POS.y, EYE_POS.z)
		body.add_child(e)
		eyes.append(e)

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

	blade_light = OmniLight3D.new()
	blade_light.light_color = Color(0.85, 0.25, 1.0)
	blade_light.omni_range = 5.0
	blade_light.light_energy = 1.2
	blade_light.position = Vector3(-0.1, 0.65, 0.0)
	align.add_child(blade_light)
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
	p.sscale = 1.85
	p.pitch = a.pitch
	p.spin = a.spin
	p.roll = 0.0
	p.body_yaw = sweep_yaw if a.body_spin else sweep_yaw * a.body_twist
	p.lean = lean
	return p

func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 6.0)
	_apply()

func _apply() -> void:
	swing_plane.position = Vector3(0, pose.height, 0)
	swing_plane.basis = Basis(Vector3(0, 0, 1), deg_to_rad(pose.tilt))
	scythe_root.rotation = Vector3(0, deg_to_rad(pose.yaw), 0)
	scythe_arm.position = Vector3(0, 0, pose.reach)
	scythe_arm.basis = Basis(Vector3(0, 0, 1), deg_to_rad(pose.roll)) \
		* Basis(Vector3(1, 0, 0), deg_to_rad(pose.pitch)) \
		* Basis(Vector3(0, 1, 0), deg_to_rad(pose.spin))
	scythe_align.scale = Vector3.ONE * pose.sscale
	body.rotation = Vector3(pose.lean, deg_to_rad(pose.body_yaw), 0)
	body.position.y = pose.bob
	body.scale = Vector3(1.0 / sqrt(pose.squash), pose.squash, 1.0 / sqrt(pose.squash))
	scythe_mat.set_shader_parameter("glow_strength", 1.4 + scythe_glow * 4.0)
	scythe_mat.set_shader_parameter("flash", flash * 0.5)
	body_mat.set_shader_parameter("flash", flash)
	blade_light.light_energy = 1.0 + scythe_glow * 2.5

func set_ghost(v: float) -> void:
	body_mat.set_shader_parameter("ghost", v)

func set_drag(local_vel: Vector3) -> void:
	body_mat.set_shader_parameter("drag", local_vel * 0.05)

## Snapshot used for dash afterimages.
func make_afterimage() -> Node3D:
	var root := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = BODY_MESH
	var mat := ShaderMaterial.new()
	mat.shader = GHOST_SHADER
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.transform = body.transform
	return root

## World-space point of the blade tip (for effects).
func blade_point() -> Vector3:
	return blade_light.global_position
