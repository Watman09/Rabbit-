## Platform layer over the Playgama Bridge (addons/playgama_bridge):
## language, save data (Bridge storage only), platform audio/pause state,
## game_ready, gameplay messages and interstitial ads.
## Everything else in the game talks to this node, never to Bridge directly.
extends Node

signal ready_changed            # save data loaded, settings applied
signal ad_finished              # interstitial closed / failed / not shown

const SAVE_KEY := "rabbit_reaper_save"

var is_ready := false
var platform_muted := false     # platform says audio is off
var platform_paused := false    # platform says pause (tab hidden, ad, ...)
var ad_open := false
var save := {
	"best_wave": 0, "best_kills": 0, "best_combo": 0, "tutorial_done": false,
	"music": 0.7, "sfx": 0.9, "muted": false, "shake": true, "quality": "high", "lang": "",
}
var _ad_callback: Callable
var _game_ready_sent := false

func _bridge() -> Node:
	return get_node_or_null("/root/Bridge")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var b := _bridge()
	if b == null:
		_finish_load(null)
		return
	# language from the platform first; a saved choice may override it below
	Loc.set_lang(str(b.platform.language))
	platform_muted = not bool(b.platform.is_audio_enabled)
	b.platform.audio_state_changed.connect(func(enabled): platform_muted = not enabled; _apply_audio())
	b.platform.pause_state_changed.connect(func(p): platform_paused = p; _apply_pause())
	b.advertisement.interstitial_state_changed.connect(_on_interstitial_state)
	b.storage.get([SAVE_KEY], func(ok, data): _finish_load(data[0] if ok and data is Array and data.size() > 0 else null), true)

func _finish_load(data) -> void:
	if data is Dictionary:
		for k in data:
			save[k] = data[k]
	if str(save.get("lang", "")) != "":
		Loc.set_lang(save.lang)
	is_ready = true
	_apply_audio()
	ready_changed.emit()

## Write the whole save in one call (only on meaningful changes).
func write() -> void:
	save.lang = Loc.lang
	var b := _bridge()
	if b:
		b.storage.set(SAVE_KEY, save.duplicate(), func(_ok): pass)

## Record a finished run; returns true if it set a new best.
func record_run(wave: int, kills: int, combo: int) -> bool:
	var best := false
	if wave > int(save.best_wave):
		save.best_wave = wave
		best = true
	if kills > int(save.best_kills):
		save.best_kills = kills
	if combo > int(save.best_combo):
		save.best_combo = combo
	write()
	return best

## First interactive frame is on screen (menu shown, input works).
func game_ready() -> void:
	if _game_ready_sent:
		return
	_game_ready_sent = true
	var b := _bridge()
	if b:
		b.platform.send_message("game_ready")

func gameplay(started: bool) -> void:
	var b := _bridge()
	if b:
		b.platform.send_message("gameplay_started" if started else "gameplay_stopped")

## Interstitial at a natural pause. The Bridge decides whether an ad is shown;
## `done` runs when the game may continue (closed, failed or not shown).
func show_interstitial(done: Callable) -> void:
	var b := _bridge()
	if b == null or not b.advertisement.is_interstitial_supported:
		done.call()
		return
	_ad_callback = done
	b.advertisement.show_interstitial()
	# if nothing happens (ad skipped by the Bridge's own pacing) continue quickly
	get_tree().create_timer(1.5, true, false, true).timeout.connect(func():
		if not ad_open and _ad_callback.is_valid():
			_finish_ad())

func _on_interstitial_state(state) -> void:
	match str(state):
		"opened":
			ad_open = true
			_apply_audio()
			_apply_pause()
		"closed", "failed":
			ad_open = false
			_apply_audio()
			_apply_pause()
			_finish_ad()

func _finish_ad() -> void:
	if _ad_callback.is_valid():
		var cb := _ad_callback
		_ad_callback = Callable()
		cb.call()
	ad_finished.emit()

# ------------------------------------------------------------------ audio / pause
func audio_blocked() -> bool:
	return platform_muted or platform_paused or ad_open or bool(save.muted)

func _apply_audio() -> void:
	Sfx.apply_settings()

## Platform pause (tab hidden, ad): freeze the game; Main restores its own pause.
func _apply_pause() -> void:
	var main := get_tree().current_scene
	if main and main.has_method("platform_pause"):
		main.platform_pause(platform_paused or ad_open)
	_apply_audio()

func _notification(what: int) -> void:
	# outside the Bridge (desktop/editor) still stop sound when the window is hidden
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _bridge() == null:
		platform_paused = true
		_apply_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _bridge() == null:
		platform_paused = false
		_apply_pause()
