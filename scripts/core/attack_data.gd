## Data for one player attack: timing, hit shape, feel and look.
## Combos/abilities are lists of these, so new attacks are data, not code.
class_name AttackData
extends Resource

enum HitMode { SWEEP, CONE_AT_END }

@export var id := ""
@export_group("Damage")
@export var damage := 12.0
@export var knockback := 6.0
@export var stagger := 1.0
@export var launch := false
@export var hit_mode := HitMode.SWEEP
@export var radius := 2.9                 # reach of the hit arc
@export var cone_half := 30.0             # for CONE_AT_END
@export var impact_radius := 0.0          # optional AoE at end of active window
@export var impact_distance := 0.0
@export_group("Timing")
@export var windup := 0.08
@export var active := 0.11
@export var recovery := 0.22
@export var cancel_ratio := 0.35          # fraction of recovery after which the next attack can start
@export var combo_window := 0.35          # grace time after recovery to continue the combo
@export_group("Motion")
@export var lunge := 0.9                  # metres travelled during windup+active
@export var move_factor := 0.12           # steering allowed while attacking
@export_group("Swing")
@export var sweep_from := 110.0           # degrees, facing-relative (0 = forward, + = right side of screen when facing up)
@export var sweep_to := -80.0
@export var plane_tilt := 0.0             # tilt of the swing plane around the facing axis
@export var height := 0.95
@export var reach := 0.85
@export var pitch := 92.0
@export var spin := 0.0
@export var body_twist := 0.35
@export var body_spin := false            # body follows the sweep fully (spins)
@export_group("Feel")
@export var hitstop := 0.045
@export var shake := 0.22
@export var sound := "swing"
@export_group("Look")
@export var slash_inner := 0.5
@export var slash_outer := 3.0
@export var slash_trail := 0.75
@export var slash_life := 0.28
@export var slash_edge := Color(1.0, 0.05, 0.22)
@export var slash_core := Color(1.0, 0.72, 0.9)
@export var slash_intensity := 1.6

func total_time() -> float:
	return windup + active + recovery

func sweep_dir() -> float:
	return signf(sweep_to - sweep_from)
