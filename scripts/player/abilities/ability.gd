## Base class for active abilities. An ability owns the player's CAST state
## from begin() until update() returns true. Add new abilities by subclassing.
class_name Ability
extends RefCounted

var player: Player
var display_name := "Ability"   # localization key (Loc)
var icon := "none"           # HUD sigil id
var cooldown := 5.0
var cd_left := 0.0
var soul_cost := 0.0
var invulnerable := false
var dash_cancelable := true
var animates_body := false     # true if the ability drives the rig's clips itself
var t := 0.0

func _init(p: Player) -> void:
	player = p

func can_use() -> bool:
	return cd_left <= 0.0 and player.soul_meter >= soul_cost

func tick(delta: float) -> void:
	cd_left = maxf(0.0, cd_left - delta)

func cooldown_ratio() -> float:
	var full: float = cooldown * player.mods.cooldown
	return cd_left / full if full > 0.0 else 0.0

func begin() -> void:
	t = 0.0
	cd_left = cooldown * player.mods.cooldown
	if soul_cost > 0.0:
		player.spend_souls(soul_cost)
	_begin()

## Return true when finished.
func update(delta: float) -> bool:
	t += delta
	return _update(delta)

func end() -> void:
	pass

func _begin() -> void:
	pass

func _update(_delta: float) -> bool:
	return true
