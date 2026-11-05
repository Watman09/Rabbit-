## Procedural layer on top of the Blender clips (runs after the
## AnimationPlayer every frame): upper-body twist toward the swing and
## two-bone IK so both hands stay on the scythe shaft.
class_name ReaperIK
extends SkeletonModifier3D

var twist_deg := 0.0            # extra yaw of spine+chest relative to the hips
var lean := 0.0                 # extra forward lean of the chest (rad)
var grip_target := Vector3.ZERO     # world space: scythe grip (main hand, .L)
var grip_weight := 1.0
var off_target := Vector3.ZERO      # world space: lower point on the shaft (off hand, .R)
var off_weight := 0.0

var _b := {}
# ear springs (secondary motion): offset angles (pitch, roll) and velocities per ear
var _ear_off := [Vector2.ZERO, Vector2.ZERO]
var _ear_vel := [Vector2.ZERO, Vector2.ZERO]
var _prev_head := Vector3.ZERO
var _prev_head_vel := Vector3.ZERO
var _has_prev := false
const EAR_STIFF := 140.0
const EAR_DAMP := 9.0
const EAR_GAIN := 0.035

func _ready() -> void:
	var sk := get_skeleton()
	for n in ["hips", "spine", "chest", "head", "ear.L", "ear.R", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"]:
		_b[n] = sk.find_bone(n)

## World position of the main-hand shoulder (used to keep the scythe in reach).
func shoulder_world(side := "L") -> Vector3:
	var sk := get_skeleton()
	return sk.global_transform * sk.get_bone_global_pose(_b["upper_arm." + side]).origin

func arm_length(side := "L") -> float:
	var sk := get_skeleton()
	var a := sk.get_bone_global_rest(_b["upper_arm." + side]).origin
	var b := sk.get_bone_global_rest(_b["forearm." + side]).origin
	var c := sk.get_bone_global_rest(_b["hand." + side]).origin
	return (b - a).length() + (c - b).length()

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _b.is_empty():
		return
	var inv := sk.global_transform.affine_inverse()
	# --- upper body twist / lean (skeleton space)
	var up := Vector3.UP
	var side := Vector3.RIGHT
	if absf(twist_deg) > 0.01 or absf(lean) > 0.001:
		var q_spine := Quaternion(up, deg_to_rad(twist_deg * 0.4)) * Quaternion(side, lean * 0.4)
		var q_chest := Quaternion(up, deg_to_rad(twist_deg * 0.6)) * Quaternion(side, lean * 0.6)
		_rotate_global(sk, _b["spine"], q_spine)
		_rotate_global(sk, _b["chest"], q_chest)
	_ears(sk)
	# --- arms
	if grip_weight > 0.001:
		_two_bone(sk, "L", inv * grip_target, grip_weight, Vector3(0.6, -0.5, -0.4))
	if off_weight > 0.001:
		_two_bone(sk, "R", inv * off_target, off_weight, Vector3(-0.6, -0.5, -0.4))

## Ears lag behind head motion like soft springs, then settle.
func _ears(sk: Skeleton3D) -> void:
	var dt := clampf(get_process_delta_time(), 0.001, 0.05)
	var head_w := sk.global_transform * sk.get_bone_global_pose(_b["head"]).origin
	if not _has_prev:
		_prev_head = head_w
		_has_prev = true
	var vel := (head_w - _prev_head) / dt
	var acc := (vel - _prev_head_vel) / dt
	_prev_head = head_w
	_prev_head_vel = vel
	# acceleration in skeleton space: forward accel tips the ears back, sideways sways them
	var local_acc := sk.global_transform.basis.inverse() * acc
	local_acc = local_acc.limit_length(80.0)
	var drive := Vector2(-local_acc.z, local_acc.x) * EAR_GAIN
	for i in 2:
		var x: Vector2 = _ear_off[i]
		var v: Vector2 = _ear_vel[i]
		var a := -x * EAR_STIFF - v * EAR_DAMP + drive * EAR_STIFF * (1.0 + 0.15 * i)
		v += a * dt
		x += v * dt
		x = x.limit_length(0.9)
		_ear_off[i] = x
		_ear_vel[i] = v
		var q := Quaternion(Vector3.RIGHT, x.x) * Quaternion(Vector3.FORWARD, x.y)
		_rotate_global(sk, _b["ear.L" if i == 0 else "ear.R"], q)

## Applies a rotation expressed in skeleton space to one bone (keeps children attached).
func _rotate_global(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var gp := sk.get_bone_global_pose(bone)
	var parent := sk.get_bone_parent(bone)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var nb := Basis(q) * gp.basis
	sk.set_bone_pose_rotation(bone, (pg.basis.inverse() * nb).get_rotation_quaternion())

## Analytic two-bone IK: upper_arm/forearm so that the hand reaches `target`.
func _two_bone(sk: Skeleton3D, s: String, target: Vector3, weight: float, pole_dir: Vector3) -> void:
	var iu: int = _b["upper_arm." + s]
	var iff: int = _b["forearm." + s]
	var ih: int = _b["hand." + s]
	var gu := sk.get_bone_global_pose(iu)
	var gf := sk.get_bone_global_pose(iff)
	var gh := sk.get_bone_global_pose(ih)
	var a := gu.origin
	var b := gf.origin
	var c := gh.origin
	var la := (b - a).length()
	var lb := (c - b).length()
	var t := c.lerp(target, clampf(weight, 0.0, 1.0))
	var at := t - a
	var d := clampf(at.length(), absf(la - lb) + 0.001, la + lb - 0.001)
	var dir := at.normalized()
	# elbow position in the plane spanned by the target direction and the pole
	var pole := (a + pole_dir.normalized()) - a
	var n := dir.cross(pole)
	if n.length() < 0.0001:
		n = dir.cross(Vector3.FORWARD)
	n = n.normalized()
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var bend_dir := dir.rotated(n, acos(cos_a))
	var b2 := a + bend_dir * la
	var c2 := a + dir * d
	# upper arm: rotate so (b-a) -> (b2-a)
	var q1 := _from_to((b - a).normalized(), (b2 - a).normalized())
	var parent_u := sk.get_bone_parent(iu)
	var pgu := sk.get_bone_global_pose(parent_u)
	var new_u := Basis(q1) * gu.basis
	sk.set_bone_pose_rotation(iu, (pgu.basis.inverse() * new_u).get_rotation_quaternion())
	# forearm: after q1 its direction is q1*(c-b); rotate onto (c2-b2)
	var fdir := (Basis(q1) * (c - b)).normalized()
	var q2 := _from_to(fdir, (c2 - b2).normalized())
	var new_f := Basis(q2) * Basis(q1) * gf.basis
	sk.set_bone_pose_rotation(iff, (new_u.inverse() * new_f).get_rotation_quaternion())

static func _from_to(u: Vector3, v: Vector3) -> Quaternion:
	var dot := clampf(u.dot(v), -1.0, 1.0)
	if dot > 0.99999:
		return Quaternion.IDENTITY
	if dot < -0.99999:
		var ax := u.cross(Vector3.RIGHT)
		if ax.length() < 0.01:
			ax = u.cross(Vector3.UP)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(u.cross(v).normalized(), acos(dot))
