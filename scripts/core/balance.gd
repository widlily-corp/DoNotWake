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
	return _dict_list("stages", "zones")


func get_tools() -> Array:
	return _dict_list("tools", "id")


## Возвращает только корректные записи-словари с обязательным ключом; мусор пропускается с предупреждением.
func _dict_list(key: String, required_key: String) -> Array:
	var raw: Variant = data.get(key, [])
	var out: Array = []
	if not raw is Array:
		push_warning("Balance: '%s' must be an array" % key)
		return out
	for item in raw:
		if item is Dictionary and (item as Dictionary).has(required_key):
			out.append(item)
		else:
			push_warning("Balance: skipped invalid entry in '%s': %s" % [key, str(item)])
	return out


## Преобразует [x, y, w, h] или Rect2 в Rect2. Некорректное значение -> пустой Rect2.
static func to_rect(raw: Variant) -> Rect2:
	if raw is Rect2:
		return raw
	if raw is Array and (raw as Array).size() == 4:
		var a := raw as Array
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Rect2()
