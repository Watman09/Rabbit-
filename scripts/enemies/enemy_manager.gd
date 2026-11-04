## Owns all spirits: spawning, the central update loop, a spatial hash for
## separation and hit queries, and batched blob shadows (one draw call).
class_name EnemyManager
extends Node3D

const CELL := 2.0
const MAX_SHADOWS := 400
var TYPES := {
	"wisp": Wisp,
	"wraith": Wraith,
	"banshee": Banshee,
	"shade": Shade,
	"brute": Brute,
	"boss": Boss,
}
var _renderers := {}   # render_key -> SpiritRenderer

var all: Array[Enemy] = []
var _pending: Array[Enemy] = []   # spawned this frame (may happen mid-iteration)
var _grid := {}
var _shadows: MultiMeshInstance3D
var _alive_count := 0

func _ready() -> void:
	Game.enemies = self
	_shadows = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mm.mesh = pm
	mm.instance_count = MAX_SHADOWS
	mm.visible_instance_count = 0
	_shadows.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/shadow.gdshader")
	mat.set_shader_parameter("strength", 0.75)
	_shadows.material_override = mat
	_shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadows)

func spawn(kind: String, pos: Vector3, difficulty := 1.0, elite := false, instant := false) -> Enemy:
	if not TYPES.has(kind):
		return null
	var e: Enemy = TYPES[kind].new()
	if elite:
		e.make_elite()
	e.apply_difficulty(difficulty)
	if instant:
		e.spawn_time = 0.15
	e.position = Game.resolve_circle(Vector3(pos.x, 0, pos.z), e.radius)
	e.yaw = randf() * TAU
	add_child(e)
	_pending.append(e)
	_alive_count += 1
	Events.enemy_spawned.emit(e)
	return e

## Queue a spirit instance for drawing this frame. `src` provides the look
## (kind, tint) when the renderer for that key does not exist yet.
func draw(key: String, xf: Transform3D, custom: Color, src: Enemy = null) -> void:
	var r: SpiritRenderer = _renderers.get(key)
	if r == null:
		if src == null:
			return
		r = SpiritRenderer.new()
		var kind := src._mesh_kind()
		var mat: ShaderMaterial = SpiritMesh.material_for(kind).duplicate()
		mat.set_shader_parameter("tint", src.tint)
		r.setup(SpiritMesh.mesh_for(kind), mat, 24 if src.is_boss else 260)
		add_child(r)
		_renderers[key] = r
	r.add(xf, custom)

## Create every spirit renderer up front (and draw it once under the floor)
## so shaders compile before the fight starts.
func warmup(center: Vector3) -> void:
	for kind in TYPES:
		for elite in [false, true]:
			if elite and kind == "boss":
				continue
			var e: Enemy = TYPES[kind].new()
			if elite:
				e.make_elite()
			var key := e._mesh_kind() + ("_elite" if elite else "")
			draw(key, Transform3D(Basis.IDENTITY, center + Vector3(0, -6, 0)), Color(0, 0, 0, 2), e)
			e.free()

func alive_count() -> int:
	return _alive_count

func _key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))

## Living enemies whose centre is within r (+ their radius slack) of p.
func query_radius(p: Vector3, r: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var r2 := (r + 1.5) * (r + 1.5)
	var c0 := _key(p.x - r, p.z - r)
	var c1 := _key(p.x + r, p.z + r)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell = _grid.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for e in cell:
				if e.alive and is_instance_valid(e):
					var dx: float = e.position.x - p.x
					var dz: float = e.position.z - p.z
					if dx * dx + dz * dz <= r2:
						out.append(e)
	return out

func _process(delta: float) -> void:
	all.append_array(_pending)
	_pending.clear()
	# rebuild grid
	_grid.clear()
	var i := 0
	while i < all.size():
		var e := all[i]
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			all.remove_at(i)
			continue
		if e.alive:
			var k := _key(e.position.x, e.position.z)
			if _grid.has(k):
				_grid[k].append(e)
			else:
				_grid[k] = [e]
		i += 1
	_alive_count = 0
	var p := Game.player
	var mm := _shadows.multimesh
	var si := 0
	for e in all:
		var sep := Vector3.ZERO
		if e.alive:
			_alive_count += 1
			var k := _key(e.position.x, e.position.z)
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var cell = _grid.get(Vector2i(k.x + dx, k.y + dz))
					if cell == null:
						continue
					for o in cell:
						if o == e:
							continue
						var ox: float = e.position.x - o.position.x
						var oz: float = e.position.z - o.position.z
						var min_d: float = e.radius + o.radius
						var d2 := ox * ox + oz * oz
						if d2 < min_d * min_d:
							var d := sqrt(d2)
							if d < 0.001:
								ox = randf() - 0.5; oz = randf() - 0.5; d = 0.5
							var push := (min_d - d) / min_d
							# heavier enemies push lighter ones more
							var w: float = o.radius / (e.radius + o.radius) * 2.0
							sep.x += ox / d * push * 6.0 * w
							sep.z += oz / d * push * 6.0 * w
			# keep out of the player's body
			if p:
				var px: float = e.position.x - p.position.x
				var pz: float = e.position.z - p.position.z
				var pm: float = e.radius + p.radius
				var pd2 := px * px + pz * pz
				if pd2 < pm * pm and pd2 > 0.0001:
					var pd := sqrt(pd2)
					sep.x += px / pd * (pm - pd) * 14.0
					sep.z += pz / pd * (pm - pd) * 14.0
		e.tick(delta, sep)
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			e.draw_spirit()
		if si < MAX_SHADOWS:
			var s: float = e.radius * 1.6 * (1.0 if e.alive else maxf(0.0, 1.0 - e.state_t * 2.0))
			mm.set_instance_transform(si, Transform3D(Basis.from_scale(Vector3(s, 1, s)), Vector3(e.position.x, 0.025, e.position.z)))
			si += 1
	mm.visible_instance_count = si
