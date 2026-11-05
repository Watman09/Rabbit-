## Run upgrades offered after each wave ("pick 1 of 3").
## Each entry is data + a small apply function that edits Player.mods or
## player fields. Add a new upgrade = add one entry here (and read the mod
## where it matters).
class_name Upgrades
extends RefCounted

const RARE_COLOR := Color(0.75, 0.35, 1.0)
const COMMON_COLOR := Color(1.0, 0.2, 0.35)

## id -> {max, rare, icon}; texts are Loc keys "u_<id>" and "u_<id>_d"
const LIST := {
	"sharp": {"max": 5, "rare": false, "icon": "attack"},
	"reach": {"max": 3, "rare": false, "icon": "crescent"},
	"swift": {"max": 3, "rare": false, "icon": "dash"},
	"dash_charge": {"max": 2, "rare": true, "icon": "dash"},
	"lifesteal": {"max": 3, "rare": false, "icon": "harvest"},
	"vitality": {"max": 3, "rare": false, "icon": "harvest"},
	"soul_hunger": {"max": 3, "rare": false, "icon": "harvest"},
	"cooldown": {"max": 3, "rare": false, "icon": "whirl"},
	"shadow_trail": {"max": 3, "rare": true, "icon": "dash"},
	"echo": {"max": 2, "rare": true, "icon": "crescent"},
	"crescent_fan": {"max": 1, "rare": true, "icon": "crescent"},
	"storm": {"max": 2, "rare": false, "icon": "whirl"},
	"burst": {"max": 3, "rare": true, "icon": "whirl"},
	"executioner": {"max": 1, "rare": true, "icon": "heavy"},
}

static func title(id: String) -> String:
	return Loc.t("u_" + id)

static func desc(id: String) -> String:
	return Loc.t("u_" + id + "_d")

static func level(p: Player, id: String) -> int:
	return p.upgrades.get(id, 0)

## Three distinct offers that are not maxed out; rare ones are less likely.
static func roll(p: Player, count := 3) -> Array[String]:
	var pool: Array[String] = []
	for id in LIST:
		if level(p, id) < LIST[id].max:
			pool.append(id)
	var out: Array[String] = []
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for id in pool:
			total += 0.45 if LIST[id].rare else 1.0
		var r := randf() * total
		for id in pool:
			r -= 0.45 if LIST[id].rare else 1.0
			if r <= 0.0:
				out.append(id)
				pool.erase(id)
				break
	return out

static func apply(p: Player, id: String) -> void:
	p.upgrades[id] = level(p, id) + 1
	var m := p.mods
	match id:
		"sharp": m.damage += 0.2
		"reach": m.radius += 0.15
		"swift": p.move_speed *= 1.1
		"dash_charge":
			p.dash_charges_max += 1
			p.dash_charges = p.dash_charges_max
		"lifesteal": m.lifesteal += 0.6
		"vitality":
			p.max_hp += 25.0
			p.heal(p.max_hp)
		"soul_hunger": m.soul_gain += 0.35
		"cooldown": m.cooldown *= 0.82
		"shadow_trail": m.dash_damage += 20.0
		"echo": m.echo_every = 4 if level(p, id) == 1 else 3
		"crescent_fan": m.crescent_count = 3
		"storm": m.storm += 1
		"burst": m.burst_chance += 0.25
		"executioner": m.executioner = true
	Events.souls_changed.emit(p.souls_total, p.soul_meter, p.soul_meter_max)
