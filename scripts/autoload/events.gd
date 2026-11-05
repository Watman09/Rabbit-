## Global signal bus. Gameplay systems emit, UI/FX/audio listen, so systems
## don't need direct references to each other.
extends Node

signal enemy_spawned(enemy: Node)
signal enemy_hit(enemy: Node, info: DamageInfo)
signal enemy_killed(enemy: Node)
signal player_damaged(amount: float, hp: float, max_hp: float)
signal player_healed(hp: float, max_hp: float)
signal player_died
signal souls_changed(total: int, meter: float, meter_max: float)
signal combo_changed(count: int)
signal wave_started(number: int, is_boss: bool)
signal wave_cleared(number: int)
signal boss_spawned(boss: Node)
signal boss_health_changed(ratio: float)
signal boss_defeated(boss: Node)
signal announcement(title: String, subtitle: String)
signal popup(text: String, world_pos: Vector3, color: Color, size: float)
signal upgrade_chosen(id: String)
