class_name LoopAudio
extends Node

## Audio Controller for the new repair loop in Do Not Wake.
## Controls one-shot events, procedural physical audio, ambient soundscapes,
## music crossfading, wake silence cutoff, and bus routing according to
## data contracts §3.5, §4.4 (one-shots, buses, wake cutoff).

signal event_played(event: String)

# Configuration constants
const HOVER_THROTTLE_MSEC: int = 60
const MAX_CONCURRENT_PER_EVENT: int = 2
const SFX_POOL_SIZE: int = 12
const DEFAULT_FADE_SEC: float = 1.0

# Registered sound map: event -> { stream: AudioStream or Callable, bus: String, volume_db: float, loop: bool }
var _event_map: Dictionary = {}

# Music tracks map: track_id -> { stream: AudioStream, volume_db: float }
var _music_map: Dictionary = {}

# Node pools and players
var _sfx_pool: Array[AudioStreamPlayer] = []
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _wake_player: AudioStreamPlayer

# Music state & crossfade
var _active_music_player: AudioStreamPlayer = null
var _inactive_music_player: AudioStreamPlayer = null
var _current_music_track: String = ""
var _is_crossfading: bool = false
var _crossfade_duration: float = 1.0
var _crossfade_elapsed: float = 0.0
var _fade_out_start_db: float = -22.0
var _fade_in_target_db: float = -22.0

# Volume modifiers & wake state
var _threat_level: int = 0
var _threat_music_offset_db: float = 0.0
var _wake_music_offset_db: float = 0.0
var _is_wake_active: bool = false
var _last_hover_msec: int = -1000

# Active playing events tracker for polyphony control
var _event_player_map: Dictionary = {} # player -> event


func _init() -> void:
	_init_event_map()
	_init_music_map()
	_ensure_setup()


func _enter_tree() -> void:
	_ensure_setup()


func _ready() -> void:
	_ensure_setup()


func _process(delta: float) -> void:
	tick(delta)


## Manual deterministic tick for tests and animation
func tick(delta: float) -> void:
	_update_crossfade(delta)


# ==============================================================================
# PUBLIC AUDIO API (§4.4)
# ==============================================================================

## Binds to GameState and StepRunner signals to automatically trigger audio feedback
func bind(game_state: GameState, runner: Node = null) -> void:
	if game_state != null:
		if game_state.has_signal("threat_changed"):
			game_state.connect("threat_changed", Callable(self, "_on_threat_changed"))
		if game_state.has_signal("wake_started"):
			game_state.connect("wake_started", Callable(self, "_on_wake_started"))
		if game_state.has_signal("wake_ended"):
			game_state.connect("wake_ended", Callable(self, "_on_wake_ended"))
		if game_state.has_signal("diagnostics_ready"):
			game_state.connect("diagnostics_ready", Callable(self, "_on_diagnostics_ready"))
		if game_state.has_signal("part_selected"):
			game_state.connect("part_selected", Callable(self, "_on_part_selected"))
		if game_state.has_signal("document_read"):
			game_state.connect("document_read", Callable(self, "_on_document_read"))
		if game_state.has_signal("repair_started"):
			game_state.connect("repair_started", Callable(self, "_on_repair_started"))
		if game_state.has_signal("step_completed"):
			game_state.connect("step_completed", Callable(self, "_on_step_completed"))
		if game_state.has_signal("step_failed"):
			game_state.connect("step_failed", Callable(self, "_on_step_failed"))
		if game_state.has_signal("pause_changed"):
			game_state.connect("pause_changed", Callable(self, "_on_pause_changed"))
		if game_state.has_signal("verification_finished"):
			game_state.connect("verification_finished", Callable(self, "_on_verification_finished"))
		if game_state.has_signal("shift_finished"):
			game_state.connect("shift_finished", Callable(self, "_on_shift_finished"))

	if runner != null:
		if runner.has_signal("hazard"):
			runner.connect("hazard", Callable(self, "_on_hazard"))


## Plays a registered audio event from the sound map
func play(event: String) -> void:
	if not _event_map.has(event):
		push_warning("LoopAudio: unknown event '%s'" % event)
		return

	if _is_wake_active and event != "wake_cut":
		# Silenced during active wake
		return

	# Throttling for rapid hover events (60 ms)
	if event == "part_hover":
		var now := Time.get_ticks_msec()
		if now - _last_hover_msec < HOVER_THROTTLE_MSEC:
			return
		_last_hover_msec = now

	# Polyphony check: limit max concurrent instances
	var active_count := _get_active_event_count(event)
	if active_count >= MAX_CONCURRENT_PER_EVENT:
		_stop_oldest_event_instance(event)

	var conf: Dictionary = _event_map[event]
	var stream := _resolve_stream(conf["stream"])
	if stream == null:
		push_warning("LoopAudio: failed to resolve stream for event '%s'" % event)
		return

	_ensure_setup()
	var player := _acquire_player()
	player.stream = stream
	player.bus = conf.get("bus", "SFX")
	player.volume_db = conf.get("volume_db", -10.0)
	_safe_play(player)

	_event_player_map[player] = event
	event_played.emit(event)


## Plays a music track with smooth crossfading
func play_music(track: String, fade_sec: float = DEFAULT_FADE_SEC) -> void:
	if track.is_empty() or track == "none":
		stop_music(fade_sec)
		return

	if not _music_map.has(track):
		push_warning("LoopAudio: unknown music track '%s'" % track)
		return

	_ensure_setup()

	if _current_music_track == track and _active_music_player != null and _active_music_player.playing and not _is_crossfading:
		return

	_current_music_track = track
	var track_data: Dictionary = _music_map[track]
	var stream: AudioStream = track_data["stream"]
	var base_vol: float = track_data.get("volume_db", -22.0)
	var target_vol: float = base_vol + _threat_music_offset_db + _wake_music_offset_db

	if _active_music_player == null or not _active_music_player.playing:
		# Initial music playback without crossfade
		_active_music_player = _music_player_a
		_inactive_music_player = _music_player_b
		_active_music_player.stream = stream
		_active_music_player.bus = "Music"
		_active_music_player.volume_db = target_vol
		_safe_play(_active_music_player)
		_is_crossfading = false
		return

	# Crossfade: switch active/inactive players
	_inactive_music_player = _active_music_player
	_active_music_player = _music_player_b if _inactive_music_player == _music_player_a else _music_player_a

	_active_music_player.stream = stream
	_active_music_player.bus = "Music"
	_active_music_player.volume_db = -80.0
	_safe_play(_active_music_player)

	_is_crossfading = true
	_crossfade_duration = maxf(fade_sec, 0.05)
	_crossfade_elapsed = 0.0
	_fade_out_start_db = _inactive_music_player.volume_db
	_fade_in_target_db = target_vol


## Smoothly fades out and stops music
func stop_music(fade_sec: float = DEFAULT_FADE_SEC) -> void:
	_current_music_track = ""
	if _active_music_player == null or not _active_music_player.playing:
		return

	if fade_sec <= 0.05:
		_active_music_player.stop()
		if _inactive_music_player:
			_inactive_music_player.stop()
		_is_crossfading = false
		return

	_inactive_music_player = _active_music_player
	_active_music_player = null
	_is_crossfading = true
	_crossfade_duration = fade_sec
	_crossfade_elapsed = 0.0
	_fade_out_start_db = _inactive_music_player.volume_db
	_fade_in_target_db = -80.0


## Adjusts ambient music and threat drone based on threat level
func set_threat_level(level: int) -> void:
	_threat_level = level
	match level:
		0, 1: # CALM or slightly elevated
			_threat_music_offset_db = 0.0
			play_music("ambient_calm", 1.2)
		2: # CRITICAL / TWITCH
			_threat_music_offset_db = 2.0
			play_music("ambient_threat", 1.0)
		3: # AWAKE
			set_wake(true)


## Instantly cuts all loops and sounds during robot wake up, or restores ambient on calm
func set_wake(active: bool) -> void:
	if active == _is_wake_active:
		return

	_is_wake_active = active
	_ensure_setup()

	if _is_wake_active:
		# INSTANT CUT: Silence all repair and SFX players in 1 frame
		for player in _sfx_pool:
			player.stop()
		_event_player_map.clear()

		# Stop all music players immediately without lingering fade
		if _music_player_a:
			_music_player_a.stop()
		if _music_player_b:
			_music_player_b.stop()
		_is_crossfading = false
		_active_music_player = null
		_inactive_music_player = null

		# Play wake cutoff stinger immediately
		if _wake_player:
			_wake_player.stream = _resolve_stream(_event_map.get("wake_cut", {}).get("stream"))
			_wake_player.bus = "SFX"
			_wake_player.volume_db = -6.0
			_safe_play(_wake_player)
		event_played.emit("wake_cut")
	else:
		# Wake ended: return ambient soundscape over 1.2 s, music is 2 dB quieter
		_wake_music_offset_db = -2.0
		if _threat_level >= 2:
			play_music("ambient_threat", 1.2)
		else:
			play_music("ambient_calm", 1.2)


# ==============================================================================
# INTERNAL LOGIC & HELPERS
# ==============================================================================

func _init_event_map() -> void:
	ProceduralAudio.initialize_all()

	# Specification §6 Sound Map: event -> { stream, bus, volume_db, loop }
	_event_map = {
		"diag_scan": {
			"stream": Callable(ProceduralAudio, "get_scan_sweep"),
			"bus": "UI",
			"volume_db": -16.0,
			"loop": false
		},
		"diag_ready": {
			"stream": Callable(ProceduralAudio, "get_relay_click"),
			"bus": "UI",
			"volume_db": -14.0,
			"loop": false
		},
		"part_hover": {
			"stream": Callable(ProceduralAudio, "get_ratchet_click"),
			"bus": "UI",
			"volume_db": -24.0,
			"loop": false
		},
		"part_select": {
			"stream": Callable(ProceduralAudio, "get_bolt_chime"),
			"bus": "SFX",
			"volume_db": -12.0,
			"loop": false
		},
		"drawer_open": {
			"stream": preload("res://assets/sounds/strap_creak.wav"),
			"bus": "SFX",
			"volume_db": -14.0,
			"loop": false
		},
		"drawer_close": {
			"stream": Callable(ProceduralAudio, "get_hatch_thud"),
			"bus": "SFX",
			"volume_db": -14.0,
			"loop": false
		},
		"paper_pick": {
			"stream": Callable(ProceduralAudio, "get_paper_rustle"),
			"bus": "SFX",
			"volume_db": -14.0,
			"loop": false
		},
		"paper_flip": {
			"stream": Callable(ProceduralAudio, "get_paper_rustle"),
			"bus": "SFX",
			"volume_db": -14.0,
			"loop": false
		},
		"wrong_doc": {
			"stream": preload("res://assets/sounds/error_buzz.wav"),
			"bus": "UI",
			"volume_db": -16.0,
			"loop": false
		},
		"repair_start": {
			"stream": Callable(ProceduralAudio, "get_steam_burst"),
			"bus": "SFX",
			"volume_db": -12.0,
			"loop": false
		},
		"step_ok": {
			"stream": preload("res://assets/sounds/repair_success.wav"),
			"bus": "SFX",
			"volume_db": -10.0,
			"loop": false
		},
		"step_fail": {
			"stream": Callable(ProceduralAudio, "get_electric_impulse"),
			"bus": "SFX",
			"volume_db": -10.0,
			"loop": false
		},
		"hazard": {
			"stream": Callable(ProceduralAudio, "get_tool_slip"),
			"bus": "SFX",
			"volume_db": -10.0,
			"loop": false
		},
		"pause_on": {
			"stream": preload("res://assets/sounds/vhs_insert.wav"),
			"bus": "UI",
			"volume_db": -14.0,
			"loop": false
		},
		"pause_off": {
			"stream": preload("res://assets/sounds/click.wav"),
			"bus": "UI",
			"volume_db": -14.0,
			"loop": false
		},
		"threat_alarm": {
			"stream": Callable(ProceduralAudio, "get_alarm_ping"),
			"bus": "Ambience",
			"volume_db": -20.0,
			"loop": false
		},
		"wake_cut": {
			"stream": preload("res://assets/music/sting_wake.ogg"),
			"bus": "SFX",
			"volume_db": -6.0,
			"loop": false
		},
		"verify_pass": {
			"stream": preload("res://assets/sounds/repair_success.wav"),
			"bus": "UI",
			"volume_db": -12.0,
			"loop": false
		},
		"verify_fail": {
			"stream": preload("res://assets/sounds/robot_awake.wav"),
			"bus": "SFX",
			"volume_db": -12.0,
			"loop": false
		},
		"stamp": {
			"stream": Callable(ProceduralAudio, "get_stamp_thud"),
			"bus": "SFX",
			"volume_db": -12.0,
			"loop": false
		},
		"shift_end": {
			"stream": preload("res://assets/sounds/calm_down.wav"),
			"bus": "Ambience",
			"volume_db": -18.0,
			"loop": false
		}
	}


func _init_music_map() -> void:
	_music_map = {
		"menu_hum": {
			"stream": preload("res://assets/music/menu_hum.ogg"),
			"volume_db": -22.0
		},
		"ambient_calm": {
			"stream": preload("res://assets/music/ambient_calm.ogg"),
			"volume_db": -22.0
		},
		"ambient_threat": {
			"stream": preload("res://assets/music/ambient_threat.ogg"),
			"volume_db": -20.0
		},
		"sting_wake": {
			"stream": preload("res://assets/music/sting_wake.ogg"),
			"volume_db": -18.0
		},
		"end_resolve": {
			"stream": preload("res://assets/music/end_resolve.ogg"),
			"volume_db": -20.0
		},
		"end_fail": {
			"stream": preload("res://assets/music/end_fail.ogg"),
			"volume_db": -20.0
		}
	}


func _ensure_setup() -> void:
	if _music_player_a == null:
		_music_player_a = AudioStreamPlayer.new()
		_music_player_a.name = "MusicPlayer_A"
		_music_player_a.bus = "Music"

	if _music_player_b == null:
		_music_player_b = AudioStreamPlayer.new()
		_music_player_b.name = "MusicPlayer_B"
		_music_player_b.bus = "Music"

	if _wake_player == null:
		_wake_player = AudioStreamPlayer.new()
		_wake_player.name = "WakePlayer"
		_wake_player.bus = "SFX"

	if _sfx_pool.is_empty():
		for i in SFX_POOL_SIZE:
			var p := AudioStreamPlayer.new()
			p.name = "SFXPlayer_%d" % i
			p.bus = "SFX"
			_sfx_pool.append(p)

	if is_inside_tree():
		if _music_player_a.get_parent() == null:
			add_child(_music_player_a)
		if _music_player_b.get_parent() == null:
			add_child(_music_player_b)
		if _wake_player.get_parent() == null:
			add_child(_wake_player)
		for p in _sfx_pool:
			if p.get_parent() == null:
				add_child(p)


func _update_crossfade(delta: float) -> void:
	if not _is_crossfading:
		return

	_crossfade_elapsed += delta
	var progress := clampf(_crossfade_elapsed / _crossfade_duration, 0.0, 1.0)

	if _inactive_music_player != null and _inactive_music_player.playing:
		_inactive_music_player.volume_db = lerpf(_fade_out_start_db, -80.0, progress)

	if _active_music_player != null and _active_music_player.playing:
		_active_music_player.volume_db = lerpf(-80.0, _fade_in_target_db, progress)

	if progress >= 1.0:
		if _inactive_music_player != null:
			_inactive_music_player.stop()
			_inactive_music_player.volume_db = -80.0
		_is_crossfading = false


func _acquire_player() -> AudioStreamPlayer:
	_ensure_setup()
	for p in _sfx_pool:
		if not p.playing:
			return p
	# Fallback: steal oldest playing player
	return _sfx_pool[0]


func _get_active_event_count(event: String) -> int:
	var count := 0
	for p in _sfx_pool:
		if p.playing and _event_player_map.get(p, "") == event:
			count += 1
	return count


func _stop_oldest_event_instance(event: String) -> void:
	for p in _sfx_pool:
		if p.playing and _event_player_map.get(p, "") == event:
			p.stop()
			_event_player_map.erase(p)
			return


func _safe_play(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	if is_inside_tree():
		if player.get_parent() == null:
			add_child(player)
		if player.is_inside_tree():
			player.play()


func _resolve_stream(stream_source: Variant) -> AudioStream:
	if stream_source is AudioStream:
		return stream_source
	elif stream_source is Callable:
		var res: Variant = stream_source.call()
		if res is AudioStream:
			return res
	return null


# ==============================================================================
# INSPECTION GETTERS (FOR TESTS AND TOOLS)
# ==============================================================================

func get_event_stream(event: String) -> AudioStream:
	if not _event_map.has(event):
		return null
	return _resolve_stream(_event_map[event]["stream"])


func get_event_config(event: String) -> Dictionary:
	return _event_map.get(event, {})


func get_all_event_names() -> Array:
	return _event_map.keys()


func is_wake_active() -> bool:
	return _is_wake_active


func get_current_music_track() -> String:
	return _current_music_track


func is_crossfading() -> bool:
	return _is_crossfading


func get_active_music_player() -> AudioStreamPlayer:
	return _active_music_player


func get_inactive_music_player() -> AudioStreamPlayer:
	return _inactive_music_player


# ==============================================================================
# SIGNAL HANDLERS FOR GAMESTATE & RUNNER
# ==============================================================================

func _on_threat_changed(level: int, _instability: float) -> void:
	set_threat_level(level)


func _on_wake_started(_duration: float) -> void:
	set_wake(true)


func _on_wake_ended() -> void:
	set_wake(false)


func _on_diagnostics_ready(_report: Dictionary) -> void:
	play("diag_ready")


func _on_part_selected(_part_id: String, _correct: bool = true) -> void:
	play("part_select")


func _on_document_read(_card_id: String, correct: bool) -> void:
	if correct:
		play("paper_flip")
	else:
		play("wrong_doc")


func _on_repair_started(_part_id: String, _steps: Array) -> void:
	play("repair_start")


func _on_step_completed(_index: int) -> void:
	play("step_ok")


func _on_step_failed(_index: int, _reason: String) -> void:
	play("step_fail")


func _on_pause_changed(paused: bool, _reason: String) -> void:
	if paused:
		play("pause_on")
	else:
		play("pause_off")


func _on_verification_finished(passed: bool, _details: Dictionary) -> void:
	if passed:
		play("verify_pass")
	else:
		play("verify_fail")


func _on_shift_finished(success: bool, _stats: Dictionary) -> void:
	play("shift_end")
	if success:
		play_music("end_resolve", 1.5)
	else:
		play_music("end_fail", 1.5)


func _on_hazard(_amount: float, _message: String) -> void:
	play("hazard")
