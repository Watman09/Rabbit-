## One-off asset tool: splits the static rabbit FBX into a body mesh and a
## scythe mesh (so the scythe can be animated independently), bakes a stylised
## vertex-colour palette and saves both as binary meshes.
##
## Run:  godot --headless -s res://tools/build_hero_meshes.gd
extends SceneTree

const SRC := "res://assets/models/rabbit_reaper.fbx"
const OUT_BODY := "res://assets/models/hero_body.res"
const OUT_SCYTHE := "res://assets/models/hero_scythe.res"
const SCALE := 1.75  # source model is 1 unit tall -> 1.75 m hero

var parent := PackedInt32Array()

func _find(x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

func _init() -> void:
	var inst: Node = load(SRC).instantiate()
	var mi: MeshInstance3D = inst.get_child(0)
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]

	# --- connected components (merge split vertices by position) ---
	parent.resize(v.size())
	for i in v.size():
		parent[i] = i
	var posmap := {}
	for i in v.size():
		var k := Vector3i((v[i] * 10000.0).round())
		if posmap.has(k):
			parent[_find(i)] = _find(posmap[k])
		else:
			posmap[k] = i
	for t in range(0, idx.size(), 3):
		var a := _find(idx[t])
		parent[_find(idx[t + 1])] = a
		parent[_find(idx[t + 2])] = a
	var comp_aabb := {}
	var comp_count := {}
	for i in v.size():
		var r := _find(i)
		if not comp_aabb.has(r):
			comp_aabb[r] = AABB(v[i], Vector3.ZERO)
			comp_count[r] = 0
		comp_aabb[r] = comp_aabb[r].expand(v[i])
		comp_count[r] += 1

	# --- classify components ---
	var kind := {}  # root -> String
	var biggest := -1
	for r in comp_aabb:
		if biggest == -1 or comp_count[r] > comp_count[biggest]:
			biggest = r
	for r in comp_aabb:
		var b: AABB = comp_aabb[r]
		var c := b.get_center()
		if b.size.y > 0.6 and b.size.x < 0.25 and b.size.z < 0.15:
			kind[r] = "staff"
		elif b.position.y > 0.72 and b.size.x > 0.25 and r != biggest:
			kind[r] = "blade"
		elif c.x > 0.15 and b.size.y > 0.2:
			kind[r] = "ribbon"
		elif r == biggest:
			kind[r] = "torso"
		else:
			kind[r] = "cloth"
	# second largest = legs/pants, wide back piece = cape
	var sorted: Array = comp_count.keys()
	sorted.sort_custom(func(a, b): return comp_count[a] > comp_count[b])
	kind[sorted[1]] = "legs"
	kind[sorted[2]] = "hood"
	kind[sorted[4]] = "cape"

	# --- grip point = centre of staff vertices around hand height ---
	# The staff is a long thin cylinder: average its bottom and top vertex rings
	# to get its axis, then take the point on that axis at hand height.
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	var nlo := 0
	var nhi := 0
	for i in v.size():
		if kind[_find(i)] != "staff":
			continue
		if v[i].y < 0.05:
			lo += v[i]; nlo += 1
		elif v[i].y > 0.70:
			hi += v[i]; nhi += 1
	lo /= max(nlo, 1)
	hi /= max(nhi, 1)
	var grip := lo.lerp(hi, (0.55 - lo.y) / (hi.y - lo.y))
	print("staff axis lo ", lo * SCALE, " hi ", hi * SCALE)
	var blade_tip := grip
	for i in v.size():
		var k2: String = kind[_find(i)]
		if k2 == "blade" and v[i].distance_to(grip) > blade_tip.distance_to(grip):
			blade_tip = v[i]

	# --- build output surfaces ---
	var body := _Builder.new()
	var scythe := _Builder.new()
	var remap_body := {}
	var remap_scythe := {}
	for t in range(0, idx.size(), 3):
		var k: String = kind[_find(idx[t])]
		var is_scythe := k == "staff" or k == "blade" or k == "ribbon"
		var b: _Builder = scythe if is_scythe else body
		var remap: Dictionary = remap_scythe if is_scythe else remap_body
		for j in 3:
			var vi := idx[t + j]
			if not remap.has(vi):
				var p := v[vi]
				var col := _colour(k, p, nrm[vi])
				var outp := (p - grip) if is_scythe else p
				remap[vi] = b.add(outp * SCALE, nrm[vi], col)
			b.idx.append(remap[vi])
	ResourceSaver.save(body.mesh(), OUT_BODY, ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(scythe.mesh(), OUT_SCYTHE, ResourceSaver.FLAG_COMPRESS)
	print("grip (scaled): ", grip * SCALE)
	print("blade tip rel grip (scaled): ", (blade_tip - grip) * SCALE)
	print("body verts ", body.v.size(), " scythe verts ", scythe.v.size())
	var face := Vector3(0, 0, -1)
	for i in v.size():
		if _find(i) == biggest and v[i].y > 0.70 and v[i].y < 0.80 and absf(v[i].x) < 0.05 and v[i].z > face.z:
			face = v[i]
	print("face front (scaled): ", face * SCALE)
	inst.free()
	quit()

## Stylised palette. COLOR.a is an emission mask used by hero.gdshader.
func _colour(k: String, p: Vector3, n: Vector3) -> Color:
	match k:
		"blade":
			var t := clampf(remap(p.x, -0.04, 0.27, 0.0, 1.0), 0.0, 1.0)
			var c := Color(0.75, 0.25, 1.0).lerp(Color(0.25, 0.75, 1.0), t)
			return Color(c.r, c.g, c.b, 0.85)
		"staff":
			return Color(0.10, 0.07, 0.14, 0.05)
		"ribbon":
			return Color(0.20, 0.03, 0.06, 0.25)
		"legs":
			return Color(0.07, 0.06, 0.09, 0.0)
		"hood":
			return Color(0.09, 0.05, 0.08, 0.0)
		"cape":
			return Color(0.05, 0.04, 0.07, 0.0)
		"torso":
			if p.y > 0.785:  # ears
				var inner := clampf(n.z, 0.0, 1.0)
				var c2 := Color(0.62, 0.66, 0.86).lerp(Color(0.85, 0.45, 1.0), inner * 0.8)
				return Color(c2.r, c2.g, c2.b, 0.25 + inner * 0.5)
			if p.y > 0.70:  # face / head
				return Color(0.66, 0.70, 0.86, 0.0)
			if p.y < 0.2:  # feet
				return Color(0.45, 0.47, 0.6, 0.0)
			return Color(0.08, 0.06, 0.10, 0.0)
	return Color(0.12, 0.08, 0.12, 0.0)

class _Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	func add(p: Vector3, nn: Vector3, col: Color) -> int:
		v.append(p); n.append(nn); c.append(col)
		return v.size() - 1
	func mesh() -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		return m
