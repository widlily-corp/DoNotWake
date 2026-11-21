extends SceneTree

const LoopAudio = preload("res://scripts/core/loop_audio.gd")
const ProceduralAudio = preload("res://scripts/core/procedural_audio.gd")

const REQUIRED_EVENTS: Array[String] = [
	"diag_scan",
	"diag_ready",
	"part_hover",
	"part_select",
	"drawer_open",
	"drawer_close",
	"paper_pick",
	"paper_flip",
	"wrong_doc",
	"repair_start",
	"step_ok",
	"step_fail",
	"hazard",
	"pause_on",
	"pause_off",
	"threat_alarm",
	"wake_cut",
	"verify_pass",
	"verify_fail",
	"stamp",
	"shift_end"
]

var _audio: LoopAudio
var _tested: bool = false
var _failures: Array[String] = []
var _checks: int = 0


func _init() -> void:
	print("--- TESTING LOOP AUDIO CONTROLLER ---")
	_audio = LoopAudio.new()
	_audio.name = "LoopAudio"
	root.add_child(_audio)


func _process(_delta: float) -> bool:
	if not _tested:
		_tested = true
		_run_all_tests()
		_audio.free()
		if _failures.is_empty():
			print("PASSED: LoopAudio passed all checks cleanly! Total checks: " + str(_checks))
			quit(0)
		else:
			printerr("FAILED checks (%d):" % _failures.size())
			for f in _failures:
				printerr("  - ", f)
			quit(1)
	return true


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)


func _run_all_tests() -> void:
	# 1. Event map coverage check
	_test_event_map_coverage(_audio)

	# 2. Stream validity and non-zero duration check
	_test_stream_validity(_audio)

	# 3. Unknown event does not crash or play
	_test_unknown_event(_audio)

	# 4. set_wake(true) stops players and plays wake_cut
	_test_wake_active(_audio)

	# 5. set_wake(false) restores ambient track
	_test_wake_restore(_audio)

	# 6. play_music crossfades cleanly and leaves only one active player
	_test_music_crossfade(_audio)

	# 7. set_threat_level switches music loops
	_test_threat_level_switching(_audio)

	# 8. part_hover throttling
	_test_hover_throttling(_audio)

	# 9. Procedural sound synthesis time under 200 ms
	_test_synthesis_performance()

	# 10. Volume levels within valid mix ranges
	_test_volume_ranges(_audio)


func _test_event_map_coverage(audio: LoopAudio) -> void:
	var registered := audio.get_all_event_names()
	for ev in REQUIRED_EVENTS:
		_check(registered.has(ev), "Required event '%s' is present in sound map" % ev)


func _test_stream_validity(audio: LoopAudio) -> void:
	for ev in REQUIRED_EVENTS:
		var stream := audio.get_event_stream(ev)
		_check(stream != null, "Stream for event '%s' resolved (not null)" % ev)
		if stream != null:
			var length := stream.get_length()
			_check(length > 0.0, "Stream for event '%s' has length > 0 (got %.3f)" % [ev, length])


func _test_unknown_event(audio: LoopAudio) -> void:
	var received_events: Array[String] = []
	var on_event := func(ev: String) -> void:
		received_events.append(ev)

	audio.event_played.connect(on_event)
	# Should not crash, and should not emit event_played
	audio.play("unknown_bogus_event_12345")
	audio.event_played.disconnect(on_event)

	_check(received_events.is_empty(), "Unknown event did not emit event_played")


func _test_wake_active(audio: LoopAudio) -> void:
	# Start music and an SFX
	audio.play_music("ambient_calm", 0.1)
	audio.play("step_ok")

	var wake_emitted := [false]
	var on_event := func(ev: String) -> void:
		if ev == "wake_cut":
			wake_emitted[0] = true
	audio.event_played.connect(on_event)

	audio.set_wake(true)
	audio.event_played.disconnect(on_event)

	_check(audio.is_wake_active(), "LoopAudio is in wake active state")
	_check(wake_emitted[0], "set_wake(true) emitted wake_cut")
	_check(audio.get_active_music_player() == null, "Music player stopped during wake")


func _test_wake_restore(audio: LoopAudio) -> void:
	_check(audio.is_wake_active(), "Precondition: wake was active")
	audio.set_wake(false)
	_check(not audio.is_wake_active(), "Wake is no longer active")
	_check(audio.get_current_music_track() == "ambient_calm", "Music track restored to ambient_calm")
	_check(audio.get_active_music_player() != null, "Active music player resumed")


func _test_music_crossfade(audio: LoopAudio) -> void:
	audio.play_music("menu_hum", 0.4)
	_check(audio.get_current_music_track() == "menu_hum", "Playing menu_hum")

	# Crossfade to ambient_threat
	audio.play_music("ambient_threat", 0.4)
	_check(audio.is_crossfading(), "Crossfade started between tracks")

	# Advance time past crossfade duration
	audio.tick(0.45)

	_check(not audio.is_crossfading(), "Crossfade completed after duration")
	_check(audio.get_current_music_track() == "ambient_threat", "Active track is ambient_threat")

	var p_active := audio.get_active_music_player()
	var p_inactive := audio.get_inactive_music_player()
	_check(p_active != null and p_active.playing, "Active music player is playing")
	_check(p_inactive == null or not p_inactive.playing, "Inactive music player is stopped (no 2 tracks playing simultaneously)")


func _test_threat_level_switching(audio: LoopAudio) -> void:
	audio.set_threat_level(0)
	_check(audio.get_current_music_track() == "ambient_calm", "Threat 0 plays ambient_calm")

	audio.set_threat_level(2)
	_check(audio.get_current_music_track() == "ambient_threat", "Threat 2 plays ambient_threat")


func _test_hover_throttling(audio: LoopAudio) -> void:
	var hover_box := [0]
	var on_event := func(ev: String) -> void:
		if ev == "part_hover":
			hover_box[0] += 1
	audio.event_played.connect(on_event)

	audio.play("part_hover")
	# Instant subsequent calls within 60 ms should be dropped
	audio.play("part_hover")
	audio.play("part_hover")

	audio.event_played.disconnect(on_event)
	_check(hover_box[0] == 1, "part_hover is throttled: 3 rapid calls resulted in %d plays" % hover_box[0])


func _test_synthesis_performance() -> void:
	var t0 := Time.get_ticks_usec()
	ProceduralAudio.initialize_all()
	var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("Procedural synthesis check took %.2f ms" % dt_ms)
	_check(dt_ms < 200.0, "Procedural synthesis initializes in < 200 ms (was %.2f ms)" % dt_ms)


func _test_volume_ranges(audio: LoopAudio) -> void:
	for ev in REQUIRED_EVENTS:
		var conf := audio.get_event_config(ev)
		var bus_name: String = conf.get("bus", "")
		var vol: float = conf.get("volume_db", 0.0)

		_check(["SFX", "UI", "Ambience", "Music"].has(bus_name), "Event '%s' assigned to valid bus '%s'" % [ev, bus_name])
		_check(vol <= 0.0 and vol >= -30.0, "Event '%s' volume %.1f dB in range [-30, 0] dB" % [ev, vol])
