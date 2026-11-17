class_name Balance
extends RefCounted

## Загрузка и типизированный доступ к параметрам баланса из data/robot.json
const DEFAULT_CONFIG_PATH: String = "res://data/robot.json"

var data: Dictionary = {}


func _init(path: String = DEFAULT_CONFIG_PATH) -> void:
	load_config(path)


func load_config(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Config file not found: " + path)
		data = {}
		return data

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Failed to open config file: " + path)
		data = {}
		return data

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		data = parsed
	else:
		push_warning("Failed to parse JSON dictionary from: " + path)
		data = {}

	return data


func get_val(key: String, fallback: Variant = null) -> Variant:
	return data.get(key, fallback)


func get_float(key: String, fallback: float = 0.0) -> float:
	if data.has(key):
		return float(data[key])
	return fallback


func get_int(key: String, fallback: int = 0) -> int:
	if data.has(key):
		return int(data[key])
	return fallback


func get_stages() -> Array:
	var st: Variant = data.get("stages", [])
	if st is Array:
		return st
	return []


func get_tools() -> Array:
	var tl: Variant = data.get("tools", [])
	if tl is Array:
		return tl
	return []
