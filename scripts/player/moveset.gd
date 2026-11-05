## The Reaper's attack data. Tweak numbers here to tune the combat feel.
## (Could be moved to .tres files later; kept in code for easy diffing.)
class_name Moveset
extends RefCounted

static func _a(id: String, props: Dictionary) -> AttackData:
	var a := AttackData.new()
	a.id = id
	for k in props:
		a.set(k, props[k])
	return a

## Light combo: LMB chain.
static func light_combo() -> Array[AttackData]:
	var list: Array[AttackData] = []
	list.append(_a("reap", {
		"damage": 12.0, "knockback": 5.5, "sweep_from": 115.0, "sweep_to": -85.0,
		"plane_tilt": 8.0, "windup": 0.09, "active": 0.16, "recovery": 0.24, "lunge": 0.9,
		"radius": 3.0, "slash_outer": 3.0, "sound": "swing",
	}))
	list.append(_a("return", {
		"damage": 12.0, "knockback": 5.5, "sweep_from": -100.0, "sweep_to": 110.0,
		"plane_tilt": -12.0, "spin": 180.0, "windup": 0.08, "active": 0.16, "recovery": 0.24,
		"lunge": 0.8, "radius": 3.0, "slash_outer": 3.0, "sound": "swing",
		"slash_edge": Color(0.85, 0.1, 0.6),
	}))
	list.append(_a("rising_crescent", {
		"damage": 16.0, "knockback": 7.0, "stagger": 1.5, "sweep_from": 130.0, "sweep_to": -115.0,
		"plane_tilt": 30.0, "windup": 0.1, "active": 0.18, "recovery": 0.26, "lunge": 1.2,
		"radius": 3.3, "slash_outer": 3.3, "slash_inner": 0.4, "sound": "swing_big", "shake": 0.3,
	}))
	list.append(_a("grim_whirl", {
		"damage": 24.0, "knockback": 13.0, "stagger": 3.0, "launch": true,
		"sweep_from": 90.0, "sweep_to": -330.0, "body_spin": true, "plane_tilt": 0.0,
		"windup": 0.14, "active": 0.32, "recovery": 0.36, "cancel_ratio": 0.6, "lunge": 1.4,
		"radius": 3.6, "slash_outer": 3.6, "slash_trail": 0.55, "slash_life": 0.34,
		"hitstop": 0.085, "shake": 0.55, "sound": "swing_big", "combo_window": 0.0,
		"slash_edge": Color(1.0, 0.02, 0.15), "slash_core": Color(1.0, 0.85, 0.95), "slash_intensity": 2.0,
	}))
	return list

## Charged heavy (RMB). Damage is scaled by charge at runtime.
static func heavy() -> AttackData:
	return _a("execution", {
		"damage": 34.0, "knockback": 15.0, "stagger": 4.0, "launch": true,
		"hit_mode": AttackData.HitMode.CONE_AT_END, "cone_half": 32.0, "radius": 4.8,
		"impact_radius": 2.6, "impact_distance": 2.8,
		"sweep_from": -150.0, "sweep_to": 40.0, "plane_tilt": 90.0, "height": 1.05, "pitch": 95.0,
		"windup": 0.07, "active": 0.18, "recovery": 0.4, "cancel_ratio": 0.5, "lunge": 1.6,
		"body_twist": 0.1, "hitstop": 0.11, "shake": 0.8, "sound": "heavy",
		"slash_outer": 4.4, "slash_inner": 0.6, "slash_trail": 0.9, "slash_life": 0.4,
		"slash_edge": Color(0.75, 0.15, 1.0), "slash_core": Color(0.8, 0.95, 1.0), "slash_intensity": 2.2,
		"combo_window": 0.0,
	})

## Attack out of a dash: a wide lunging cut.
static func dash_strike() -> AttackData:
	return _a("dash_strike", {
		"damage": 18.0, "knockback": 9.0, "stagger": 2.0, "sweep_from": 95.0, "sweep_to": -95.0,
		"plane_tilt": 4.0, "windup": 0.05, "active": 0.15, "recovery": 0.28, "lunge": 3.2,
		"radius": 3.2, "slash_outer": 3.2, "sound": "swing_big", "hitstop": 0.06, "shake": 0.35,
		"slash_edge": Color(1.0, 0.1, 0.45), "combo_window": 0.3,
	})

## Throw pose for the crescent ability.
static func crescent_throw() -> AttackData:
	return _a("crescent_throw", {
		"damage": 0.0, "sweep_from": 120.0, "sweep_to": -60.0, "plane_tilt": 15.0,
		"windup": 0.08, "active": 0.09, "recovery": 0.16, "lunge": 0.3, "radius": 0.0,
		"slash_outer": 2.6, "sound": "",
		"slash_edge": Color(1.0, 0.1, 0.3),
	})
