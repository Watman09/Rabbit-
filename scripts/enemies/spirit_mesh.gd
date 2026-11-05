## Spirit meshes + materials per enemy type. The shapes are sculpted in
## Blender (tools/blender/build_spirits.py -> assets/models/spirits.glb):
## an opaque core (hooded skull, hunched body, clawed arms) and a set of
## smoke ribbons. Per-vertex data comes in as vertex colour and is moved to
## UV/UV2 here, because on the GL MultiMesh path COLOR is the instance colour.
##   core : UV = (arm t, arm code)  UV2 = (sway, glow)
##   smoke: UV = (across, along)    UV2 = (arm t, arm code)
class_name SpiritMesh
extends RefCounted

const SCENE := "res://assets/models/spirits.glb"
const META := "res://assets/models/spirits.json"
const CORE_SHADER := preload("res://assets/shaders/spirit.gdshader")
const SMOKE_SHADER := preload("res://assets/shaders/spirit_smoke.gdshader")

## Look per type: shader tuning only (shapes live in the Blender script).
const LOOK := {
	"wisp": {"sway": 0.16, "ragged": 0.6, "smoke_amp": 0.22},
	"wraith": {"sway": 0.12, "ragged": 0.55, "smoke_amp": 0.2},
	"banshee": {"sway": 0.16, "ragged": 0.6, "smoke_amp": 0.28},
	"shade": {"sway": 0.1, "ragged": 0.5, "smoke_amp": 0.2},
	"brute": {"sway": 0.06, "ragged": 0.45, "smoke_amp": 0.14},
	"boss": {"sway": 0.08, "ragged": 0.5, "smoke_amp": 0.2},
}

static var _meshes := {}
static var _materials := {}
static var _shoulders := {}
static var _scene: Node

static func _load() -> void:
	if _scene != null:
		return
	_scene = (load(SCENE) as PackedScene).instantiate()
	var f := FileAccess.open(META, FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		for k in data.shoulder:
			var a: Array = data.shoulder[k]
			_shoulders[k] = Vector3(absf(a[0]), a[1], a[2])

static func _convert(name: String, smoke: bool) -> ArrayMesh:
	_load()
	var mi := _scene.find_child(name, true, false) as MeshInstance3D
	if mi == null:
		push_error("spirit mesh missing: " + name)
		return ArrayMesh.new()
	var arr := mi.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var n := cols.size()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	uv.resize(n)
	uv2.resize(n)
	for i in n:
		var c := cols[i]
		if smoke:
			uv[i] = Vector2(c.r, c.b)
			uv2[i] = Vector2(c.a, c.g)
		else:
			uv[i] = Vector2(c.a, c.g)
			uv2[i] = Vector2(c.b, c.r)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = arr[Mesh.ARRAY_VERTEX]
	out[Mesh.ARRAY_NORMAL] = arr[Mesh.ARRAY_NORMAL]
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m

static func mesh_for(kind: String) -> ArrayMesh:
	if not _meshes.has(kind):
		_meshes[kind] = _convert("core_" + kind, false)
	return _meshes[kind]

static func smoke_mesh_for(kind: String) -> ArrayMesh:
	var key := kind + "_smoke"
	if not _meshes.has(key):
		_meshes[key] = _convert("smoke_" + kind, true)
	return _meshes[key]

static func shoulder(kind: String) -> Vector3:
	_load()
	return _shoulders.get(kind, Vector3(0.27, 1.2, 0.1))

static func material_for(kind: String) -> ShaderMaterial:
	if not _materials.has(kind):
		var look: Dictionary = LOOK.get(kind, LOOK["wraith"])
		var m := ShaderMaterial.new()
		m.shader = CORE_SHADER
		m.set_shader_parameter("sway_amount", look.sway)
		m.set_shader_parameter("raggedness", look.ragged)
		m.set_shader_parameter("shoulder", shoulder(kind))
		_materials[kind] = m
	return _materials[kind]

static func smoke_material_for(kind: String) -> ShaderMaterial:
	var key := kind + "_smoke"
	if not _materials.has(key):
		var look: Dictionary = LOOK.get(kind, LOOK["wraith"])
		var m := ShaderMaterial.new()
		m.shader = SMOKE_SHADER
		m.set_shader_parameter("amp", look.smoke_amp)
		m.set_shader_parameter("shoulder", shoulder(kind))
		_materials[key] = m
	return _materials[key]
