extends SceneTree

const VALID_LICENSES := [
	"CC0-1.0",
	"CC-BY-3.0",
	"CC-BY-4.0",
	"Pixabay",
	"Sonniss",
	"Own",
	"Procedural"
]

var _failures: Array[String] = []
var _checks: int = 0

func _init() -> void:
	print("--- TESTING AUDIO CREDITS REGISTRY ---")
	_test_audio_credits()
	if _failures.is_empty():
		print("PASSED: Audio credits registry is 100% valid! Checks: " + str(_checks))
		quit(0)
	else:
		printerr("FAILED checks (%d):" % _failures.size())
		for f in _failures:
			printerr("  - ", f)
		quit(1)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)


func _test_audio_credits() -> void:
	var path := "res://data/audio_credits.json"
	_check(FileAccess.file_exists(path), "File data/audio_credits.json exists")
	if not FileAccess.file_exists(path):
		return

	var file := FileAccess.open(path, FileAccess.READ)
	_check(file != null, "Can open data/audio_credits.json")
	if file == null:
		return

	var text := file.get_as_text()
	var json = JSON.parse_string(text)
	_check(json is Dictionary, "JSON root is a Dictionary")
	if not (json is Dictionary):
		return

	_check(json.has("tracks") and json["tracks"] is Array, "JSON has 'tracks' array")
	if not (json.has("tracks") and json["tracks"] is Array):
		return

	var tracks: Array = json["tracks"]
	_check(tracks.size() >= 6, "At least 6 tracks defined (got %d)" % tracks.size())

	var registered_files: Dictionary = {}

	for i in tracks.size():
		var t = tracks[i]
		_check(t is Dictionary, "Track %d is Dictionary" % i)
		if not (t is Dictionary):
			continue

		var track_file: String = t.get("file", "")
		var title: String = t.get("title", "")
		var author: String = t.get("author", "")
		var license: String = t.get("license", "")
		var url: String = t.get("url", "")
		var added: String = t.get("added", "")

		_check(track_file.begins_with("res://"), "Track %d file begins with res:// (%s)" % [i, track_file])
		_check(FileAccess.file_exists(track_file), "Track %d file exists on disk (%s)" % [i, track_file])
		_check(not registered_files.has(track_file), "Track file is unique: %s" % track_file)
		registered_files[track_file] = true

		_check(not title.is_empty(), "Track %s has non-empty title" % track_file)
		_check(VALID_LICENSES.has(license), "Track %s license '%s' is in allowed list" % [track_file, license])

		if license.begins_with("CC-BY"):
			_check(not author.is_empty(), "CC-BY track %s has non-empty author" % track_file)
			_check(not url.is_empty(), "CC-BY track %s has non-empty URL" % track_file)
		elif license == "Own" or license == "Procedural":
			_check(author == "Evilbyte Studio", "Own/Procedural track %s author is 'Evilbyte Studio'" % track_file)

		_check(not added.is_empty(), "Track %s has added date" % track_file)

	# Verify all .wav and .ogg files in assets/sounds and assets/music are registered
	_verify_directory_coverage("res://assets/sounds", registered_files)
	_verify_directory_coverage("res://assets/music", registered_files)


func _verify_directory_coverage(dir_path: String, registered: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			if file_name.ends_with(".wav") or file_name.ends_with(".ogg"):
				var full_res := "%s/%s" % [dir_path, file_name]
				_check(registered.has(full_res), "Disk file %s is registered in audio_credits.json" % full_res)
		file_name = dir.get_next()
	dir.list_dir_end()
