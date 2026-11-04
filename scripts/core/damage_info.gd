## Describes a single hit. Shared by player and enemy attacks so new damage
## sources (traps, status effects, allies) can plug into the same pipeline.
class_name DamageInfo
extends RefCounted

var amount := 10.0
var origin := Vector3.ZERO      # where the hit came from (for knockback direction)
var knockback := 5.0            # impulse in m/s
var stagger := 1.0              # poise damage; interrupts enemies with poise <= this
var launch := false             # big finishers send enemies flying
var source := ""                # attack id, for future hooks (lifesteal, on-hit effects)
var color := Color(1.0, 0.1, 0.2)

static func make(amount_: float, origin_: Vector3, knockback_ := 5.0, stagger_ := 1.0, source_ := "") -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount_
	d.origin = origin_
	d.knockback = knockback_
	d.stagger = stagger_
	d.source = source_
	return d
