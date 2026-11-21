extends SceneTree

const ProceduralAudio = preload("res://scripts/core/procedural_audio.gd")

func _init() -> void:
	print("--- TESTING PROCEDURAL AUDIO SYNTHESIZER ---")
	var t0 := Time.get_ticks_usec()
	ProceduralAudio.initialize_all()
	var dt := (Time.get_ticks_usec() - t0) / 1000.0
	print("ProceduralAudio initialized all sounds in %.2f ms" % dt)

	var ratchet := ProceduralAudio.get_ratchet_click(0)
	print("Ratchet 0: valid=", ratchet != null, " length=", ratchet.get_length() if ratchet else 0.0)

	var bolt := ProceduralAudio.get_bolt_chime(0)
	print("Bolt chime 0: valid=", bolt != null, " length=", bolt.get_length() if bolt else 0.0)

	var steam := ProceduralAudio.get_steam_burst()
	print("Steam burst: valid=", steam != null, " length=", steam.get_length() if steam else 0.0)

	var slip := ProceduralAudio.get_tool_slip()
	print("Tool slip: valid=", slip != null, " length=", slip.get_length() if slip else 0.0)

	var hatch := ProceduralAudio.get_hatch_thud()
	print("Hatch thud: valid=", hatch != null, " length=", hatch.get_length() if hatch else 0.0)

	var pulse := ProceduralAudio.get_electric_impulse()
	print("Electric pulse: valid=", pulse != null, " length=", pulse.get_length() if pulse else 0.0)

	var scan := ProceduralAudio.get_scan_sweep()
	print("Scan sweep: valid=", scan != null, " length=", scan.get_length() if scan else 0.0)

	var relay := ProceduralAudio.get_relay_click()
	print("Relay click: valid=", relay != null, " length=", relay.get_length() if relay else 0.0)

	var paper := ProceduralAudio.get_paper_rustle(0)
	print("Paper rustle 0: valid=", paper != null, " length=", paper.get_length() if paper else 0.0)

	var stamp := ProceduralAudio.get_stamp_thud()
	print("Stamp thud: valid=", stamp != null, " length=", stamp.get_length() if stamp else 0.0)

	var alarm := ProceduralAudio.get_alarm_ping()
	print("Alarm ping: valid=", alarm != null, " length=", alarm.get_length() if alarm else 0.0)

	var silence := ProceduralAudio.get_wake_silence()
	print("Wake silence: valid=", silence != null, " length=", silence.get_length() if silence else 0.0)

	if ratchet and bolt and steam and slip and hatch and pulse and scan and relay and paper and stamp and alarm and silence:
		print("PASSED: All procedural sounds generated cleanly!")
		quit(0)
	else:
		printerr("FAILED: some sounds were null")
		quit(1)
