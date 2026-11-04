## Draws every spirit of one type (and their death fragments) with a single
## MultiMesh. Producers call add() during the frame; commit happens at the
## end of the frame (high process_priority).
class_name SpiritRenderer
extends MultiMeshInstance3D

var _count := 0
var _cap := 0

func setup(mesh_: Mesh, mat: Material, capacity: int) -> void:
	_cap = capacity
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh_
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 30, 120))
	process_priority = 100

## custom: x flash, y dissolve, z attack, w phase*8 + lag+2
func add(xf: Transform3D, custom: Color) -> void:
	if _count >= _cap:
		return
	multimesh.set_instance_transform(_count, xf)
	multimesh.set_instance_custom_data(_count, custom)
	_count += 1

func _process(_d: float) -> void:
	multimesh.visible_instance_count = _count
	_count = 0
