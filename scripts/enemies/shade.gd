## Bigger wraith that splits into wisps when destroyed.
class_name Shade
extends Wraith

func _init() -> void:
	super()
	kind = "shade"
	max_hp = 55.0; hp = max_hp
	speed = 3.1; radius = 0.65; damage = 14.0
	poise = 1.5; soul_value = 3
	reach = 2.5
	windup_time = 0.7
	tint = Color(0.85, 0.08, 0.35, 1.0)

func _on_death() -> void:
	if Game.enemies == null:
		return
	for i in 3:
		var a := TAU * i / 3.0 + randf()
		var p := position + Vector3(cos(a), 0, sin(a)) * 0.8
		var w: Enemy = Game.enemies.spawn("wisp", p, 1.0, false, true)
		if w:
			w.knock = Vector3(cos(a), 0, sin(a)) * 6.0
