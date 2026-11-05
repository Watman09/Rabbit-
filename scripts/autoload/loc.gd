## Localization. English is the default and the fallback; the start language
## comes from the platform (Playgama Bridge platform.language), the player can
## switch it in Settings. Use Loc.t("key") or Loc.t("key", [args]).
extends Node

signal changed

const LANGS := ["en", "ru"]
const LANG_NAMES := {"en": "English", "ru": "Русский"}   # each in its own language

var lang := "en"

const T := {
	# ---- menus
	"title_sub": {"en": "A reaper against endless waves of dark spirits", "ru": "Жнец против бесконечных волн тёмных духов"},
	"play": {"en": "PLAY", "ru": "ИГРАТЬ"},
	"settings": {"en": "SETTINGS", "ru": "НАСТРОЙКИ"},
	"how_to_play": {"en": "HOW TO PLAY", "ru": "КАК ИГРАТЬ"},
	"back": {"en": "BACK", "ru": "НАЗАД"},
	"resume": {"en": "RESUME", "ru": "ПРОДОЛЖИТЬ"},
	"main_menu": {"en": "MAIN MENU", "ru": "ГЛАВНОЕ МЕНЮ"},
	"retry": {"en": "RISE AGAIN", "ru": "ВОССТАТЬ СНОВА"},
	"paused": {"en": "PAUSED", "ru": "ПАУЗА"},
	"loading": {"en": "summoning spirits…", "ru": "призыв духов…"},
	"best": {"en": "Best: wave %d  •  combo %d  •  %d spirits banished", "ru": "Рекорд: волна %d  •  комбо %d  •  изгнано %d"},
	"music": {"en": "Music", "ru": "Музыка"},
	"sfx": {"en": "Sound effects", "ru": "Звуки"},
	"sound": {"en": "Sound", "ru": "Звук"},
	"on": {"en": "ON", "ru": "ВКЛ"},
	"off": {"en": "OFF", "ru": "ВЫКЛ"},
	"shake": {"en": "Screen shake", "ru": "Тряска экрана"},
	"quality": {"en": "Graphics", "ru": "Графика"},
	"q_high": {"en": "HIGH", "ru": "ВЫСОКАЯ"},
	"q_low": {"en": "LOW", "ru": "НИЗКАЯ"},
	"language": {"en": "Language", "ru": "Язык"},
	"tutorial_again": {"en": "Show tutorial again", "ru": "Показать обучение снова"},
	"yes": {"en": "YES", "ru": "ДА"},
	# ---- controls
	"c_move": {"en": "move", "ru": "движение"},
	"c_attack": {"en": "scythe combo (4 hits)", "ru": "комбо косой (4 удара)"},
	"c_heavy": {"en": "charged strike", "ru": "заряженный удар"},
	"c_dash": {"en": "dash (charges), attack right after = dash strike", "ru": "рывок (заряды), атака сразу после — рывковый удар"},
	"c_pause": {"en": "pause", "ru": "пауза"},
	"k_lmb": {"en": "LMB", "ru": "ЛКМ"},
	"k_rmb": {"en": "RMB (hold)", "ru": "ПКМ (удерж.)"},
	"k_space": {"en": "SPACE / SHIFT", "ru": "ПРОБЕЛ / SHIFT"},
	"c_touch_move": {"en": "left thumb", "ru": "левый палец"},
	"c_touch_move2": {"en": "move", "ru": "движение"},
	"c_touch_act": {"en": "buttons on the right", "ru": "кнопки справа"},
	"c_touch_act2": {"en": "strike, dash, charge, abilities", "ru": "удар, рывок, заряд, способности"},
	"hint_bar": {"en": "LMB strike  •  RMB charge  •  SPACE dash  •  P pause", "ru": "ЛКМ удар  •  ПКМ заряд  •  ПРОБЕЛ рывок  •  P пауза"},
	"tips_title": {"en": "Combat tips", "ru": "Советы"},
	"tip_perfect": {"en": "Dash right before a hit lands: PERFECT dodge, time slows, your hits crit.", "ru": "Рывок в последний момент перед ударом — ИДЕАЛЬНО: время замедляется, удары критуют."},
	"tip_parry": {"en": "Swing at incoming bolts to send them back.", "ru": "Удар косой по летящему сгустку отправляет его обратно."},
	"tip_execute": {"en": "Gold and heavy spirits get stunned at low health — strike them to EXECUTE.", "ru": "Элита и колоссы оглушаются при малом здоровье — удар рядом = КАЗНЬ."},
	"tip_upgrades": {"en": "After every wave choose one Gift of the Harvest.", "ru": "После каждой волны выберите Дар жатвы."},
	"tiers_title": {"en": "spirit colour = threat level", "ru": "цвет духа — уровень угрозы"},
	"tier_weak": {"en": "weak", "ru": "слабый"},
	"tier_normal": {"en": "normal", "ru": "обычный"},
	"tier_ranged": {"en": "ranged", "ru": "дальний"},
	"tier_strong": {"en": "strong", "ru": "сильный"},
	"tier_heavy": {"en": "heavy", "ru": "тяжёлый"},
	"tier_elite": {"en": "elite", "ru": "элита"},
	# ---- tutorial
	"tut_move": {"en": "Move with W A S D", "ru": "Двигайтесь: W A S D"},
	"tut_move_touch": {"en": "Drag on the left side to move", "ru": "Ведите пальцем слева, чтобы двигаться"},
	"tut_attack": {"en": "Click to swing the scythe — keep clicking for a combo", "ru": "Кликайте, чтобы бить косой — серия даёт комбо"},
	"tut_attack_touch": {"en": "Tap the big button to swing — keep tapping for a combo", "ru": "Жмите большую кнопку — серия даёт комбо"},
	"tut_dash": {"en": "Press SPACE to dash through danger", "ru": "ПРОБЕЛ — рывок сквозь опасность"},
	"tut_dash_touch": {"en": "Tap the arrows button to dash", "ru": "Кнопка со стрелками — рывок"},
	"tut_heavy": {"en": "Hold RIGHT mouse button and release for a charged strike", "ru": "Зажмите ПКМ и отпустите — заряженный удар"},
	"tut_heavy_touch": {"en": "Hold the scythe button and release for a charged strike", "ru": "Зажмите кнопку косы и отпустите — заряженный удар"},
	"tut_abilities": {"en": "Q, E, R — abilities. R needs a full soul meter", "ru": "Q, E, R — способности. R требует полной шкалы душ"},
	"tut_abilities_touch": {"en": "Round buttons — abilities. The star needs a full soul meter", "ru": "Круглые кнопки — способности. Звезде нужна полная шкала душ"},
	"tut_done": {"en": "Survive the waves. Reap them all!", "ru": "Переживите волны. Пожните всех!"},
	# ---- HUD / game
	"souls": {"en": "souls %d", "ru": "души %d"},
	"wave": {"en": "WAVE %d", "ru": "ВОЛНА %d"},
	"spirits_left": {"en": "spirits: %d", "ru": "духов: %d"},
	"hits": {"en": "HITS", "ru": "УДАРОВ"},
	"rank_1": {"en": "BRUTAL", "ru": "ЖЕСТОКО"},
	"rank_2": {"en": "CARNAGE", "ru": "РЕЗНЯ"},
	"rank_3": {"en": "FRENZY", "ru": "БЕЗУМИЕ"},
	"rank_4": {"en": "HARVEST", "ru": "ЖАТВА"},
	"crit_window": {"en": "CRITICAL WINDOW", "ru": "КРИТИЧЕСКОЕ ОКНО"},
	"dead_title": {"en": "THE REAPER FALLS", "ru": "ЖНЕЦ ПАЛ"},
	"dead_stats": {"en": "Wave %d  •  Spirits banished: %d  •  Souls: %d  •  Best combo: %d  •  Time: %d:%02d",
		"ru": "Волна %d  •  Духов изгнано: %d  •  Душ: %d  •  Лучшее комбо: %d  •  Время: %d:%02d"},
	"dead_stats2": {"en": "Perfect dodges: %d  •  Executions: %d  •  Parried: %d  •  Gifts: %d",
		"ru": "Идеальных уклонений: %d  •  Казней: %d  •  Отражено: %d  •  Даров: %d"},
	"new_record": {"en": "NEW RECORD!", "ru": "НОВЫЙ РЕКОРД!"},
	"gift_title": {"en": "GIFT OF THE HARVEST", "ru": "ДАР ЖАТВЫ"},
	"gift_sub": {"en": "choose one blessing", "ru": "выберите одно усиление"},
	"lvl_up": {"en": "lv. %d → %d", "ru": "ур. %d → %d"},
	"rare": {"en": "rare", "ru": "редкий"},
	"new": {"en": "new", "ru": "новый"},
	"boss_defeated": {"en": "THE HOLLOW FALLS", "ru": "ПУСТОТА ПОВЕРЖЕНА"},
	"boss_defeated_sub": {"en": "...but the spirits do not rest", "ru": "Но духи не утихают…"},
	"boss_name": {"en": "The Mourning Hollow", "ru": "Скорбящая Пустота"},
	"boss_wave": {"en": "BOSS: %s", "ru": "БОСС: %s"},
	"phase": {"en": "PHASE %d", "ru": "ФАЗА %d"},
	"phase_sub": {"en": "The Hollow rages", "ru": "Пустота яростнее"},
	"w_default": {"en": "The spirits awaken", "ru": "Духи пробуждаются"},
	"w_elite": {"en": "Golden elites appear", "ru": "Появились элитные духи"},
	"w_banshee": {"en": "Banshees strike from afar", "ru": "Плакальщицы атакуют издалека"},
	"w_shade": {"en": "Shades split apart", "ru": "Тени распадаются на части"},
	"w_brute": {"en": "The Gloom Colossi march", "ru": "Идут Колоссы мрака"},
	"w_prelude": {"en": "The Hollow draws near…", "ru": "Пустота близко…"},
	"p_stunned": {"en": "STUNNED", "ru": "ОГЛУШЁН"},
	"p_parried": {"en": "PARRIED", "ru": "ОТРАЖЕНО"},
	"p_crit": {"en": "CRIT", "ru": "КРИТ"},
	"p_perfect": {"en": "PERFECT!", "ru": "ИДЕАЛЬНО!"},
	"p_execute": {"en": "EXECUTED", "ru": "КАЗНЬ"},
	"ab_maelstrom": {"en": "Soul Maelstrom", "ru": "Вихрь душ"},
	"ab_crescent": {"en": "Crimson Crescent", "ru": "Багровый серп"},
	"ab_harvest": {"en": "Harvest of Souls", "ru": "Жатва душ"},
	"ab_execution": {"en": "Execution", "ru": "Казнь"},
	# ---- upgrades: name / description
	"u_sharp": {"en": "Keen Edge", "ru": "Острая коса"},
	"u_sharp_d": {"en": "+20% damage to every strike", "ru": "+20% урона всем ударам"},
	"u_reach": {"en": "Long Scythe", "ru": "Длинная коса"},
	"u_reach_d": {"en": "+15% reach and width of swings", "ru": "+15% дальность и ширина взмахов"},
	"u_swift": {"en": "Swiftness", "ru": "Стремительность"},
	"u_swift_d": {"en": "+10% running speed", "ru": "+10% скорость бега"},
	"u_dash_charge": {"en": "Third Shadow Step", "ru": "Третий шаг тени"},
	"u_dash_charge_d": {"en": "+1 dash charge", "ru": "+1 заряд рывка"},
	"u_lifesteal": {"en": "Soul Thirst", "ru": "Жажда душ"},
	"u_lifesteal_d": {"en": "Every hit heals 0.6 HP", "ru": "Каждое попадание лечит 0.6 HP"},
	"u_vitality": {"en": "Reaper's Fortitude", "ru": "Крепость жнеца"},
	"u_vitality_d": {"en": "+25 max health and a full heal", "ru": "+25 к здоровью и полное лечение"},
	"u_soul_hunger": {"en": "Harvest Hunger", "ru": "Голод жатвы"},
	"u_soul_hunger_d": {"en": "Soul meter fills 35% faster", "ru": "Шкала душ заполняется на 35% быстрее"},
	"u_cooldown": {"en": "Dark Rhythm", "ru": "Тёмный ритм"},
	"u_cooldown_d": {"en": "-18% ability cooldowns", "ru": "-18% перезарядки способностей"},
	"u_shadow_trail": {"en": "Cutting Shadow", "ru": "Режущая тень"},
	"u_shadow_trail_d": {"en": "Dashing wounds spirits in your path (20 damage)", "ru": "Рывок ранит духов на пути (20 урона)"},
	"u_echo": {"en": "Scythe Echo", "ru": "Эхо косы"},
	"u_echo_d": {"en": "Every 4th swing launches a flying crescent", "ru": "Каждый 4-й удар выпускает летящий серп"},
	"u_crescent_fan": {"en": "Crescent Fan", "ru": "Веер серпов"},
	"u_crescent_fan_d": {"en": "Crimson Crescent flies as a triple fan", "ru": "Багровый серп летит тройным веером"},
	"u_storm": {"en": "Soul Storm", "ru": "Буря душ"},
	"u_storm_d": {"en": "Maelstrom lasts 40% longer and is 20% wider", "ru": "Вихрь дольше на 40% и шире на 20%"},
	"u_burst": {"en": "Unravelling", "ru": "Распад"},
	"u_burst_d": {"en": "Slain spirits explode (25% chance)", "ru": "Убитые духи взрываются с шансом 25%"},
	"u_executioner": {"en": "Executioner", "ru": "Палач"},
	"u_executioner_d": {"en": "Executions heal 25 and give double souls", "ru": "Казнь лечит на 25 и даёт двойные души"},
}

func set_lang(code: String) -> void:
	code = code.to_lower().substr(0, 2) if code else "en"
	if not code in LANGS:
		code = "en"
	if code != lang:
		lang = code
		changed.emit()

func next_lang() -> void:
	set_lang(LANGS[(LANGS.find(lang) + 1) % LANGS.size()])

func t(key: String, args = null) -> String:
	var row: Dictionary = T.get(key, {})
	var s: String = row.get(lang, row.get("en", key))
	if args != null:
		return s % args
	return s
