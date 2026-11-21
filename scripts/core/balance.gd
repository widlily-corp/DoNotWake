class_name Balance
extends RefCounted

## Загрузка и типизированный доступ к параметрам баланса из data/robot.json
const DEFAULT_CONFIG_PATH: String = "res://data/robot.json"

const DEFAULT_BREATHING: Dictionary = {
	"amplitude": 3.0,
	"frequency": 0.5,
	"delay": 0.4,
}

const DEFAULT_MOUSE_PROXIMITY: Dictionary = {
	"distance": 180.0,
	"sensitivity": 0.85,
}

const DEFAULT_OPTIC_GLOW: Dictionary = {
	"calm": Color(0.455, 0.545, 0.569, 1.0),      # #748B91 (Signal)
	"twitch": Color(0.847, 0.761, 0.604, 1.0),    # #D8C29A (Lamp Warm)
	"alert": Color(0.902, 0.157, 0.082, 1.0),     # #E62815 (Alert)
	"complete": Color(0.929, 0.941, 0.957, 1.0),  # #EDF0F4 (Cloud White)
	"intensity": 0.85,
	"radius": 14.0,
}

const DEFAULT_STEAM_PARTICLES: Dictionary = {
	"count": 24,
	"lifetime": 1.4,
	"speed_min": 25.0,
	"speed_max": 65.0,
	"spread_deg": 32.0,
	"gravity_y": -22.0,
	"scale_min": 2.0,
	"scale_max": 5.0,
	"color": Color(0.769, 0.804, 0.839, 1.0),     # #C4CDD6 (Pale Steel)
	"alpha_start": 0.65,
	"alpha_end": 0.0,
}

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


func get_robot_layout() -> Dictionary:
	var raw: Variant = data.get("robot_layout", {})
	if raw is Dictionary:
		return raw as Dictionary
	return {}


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


## Возвращает весь набор параметров процедурной интерактивности и анимаций
func get_procedural_animation() -> Dictionary:
	return {
		"breathing": get_breathing_params(),
		"mouse_proximity": get_mouse_proximity_params(),
		"optic_glow": get_optic_glow_params(),
		"steam_particles": get_steam_particle_params(),
	}


## Возвращает параметры дыхания робота (амплитуда px, частота Гц, задержка сек)
func get_breathing_params() -> Dictionary:
	var raw := _get_nested_or_root_dict("breathing")
	var amp_val: Variant = raw.get("amplitude", raw.get("amplitude_px", null))
	var freq_val: Variant = raw.get("frequency", raw.get("frequency_hz", null))
	var delay_val: Variant = raw.get("delay", raw.get("delay_sec", raw.get("hold_delay", null)))
	return {
		"amplitude": _validate_float(amp_val, DEFAULT_BREATHING["amplitude"], 0.0, 100.0),
		"frequency": _validate_float(freq_val, DEFAULT_BREATHING["frequency"], 0.01, 20.0),
		"delay": _validate_float(delay_val, DEFAULT_BREATHING["delay"], 0.0, 60.0),
	}


## Возвращает пороги реакции робота на приближение мыши (дистанция px, чувствительность)
func get_mouse_proximity_params() -> Dictionary:
	var raw := _get_nested_or_root_dict("mouse_proximity")
	var dist_val: Variant = raw.get("distance", raw.get("trigger_distance", raw.get("proximity_distance", null)))
	var sens_val: Variant = raw.get("sensitivity", raw.get("reaction_sensitivity", raw.get("sensitivity_ratio", null)))
	return {
		"distance": _validate_float(dist_val, DEFAULT_MOUSE_PROXIMITY["distance"], 0.0, 2000.0),
		"sensitivity": _validate_float(sens_val, DEFAULT_MOUSE_PROXIMITY["sensitivity"], 0.0, 10.0),
	}


## Возвращает параметры и цвета свечения оптики робота
func get_optic_glow_params() -> Dictionary:
	var raw := _get_nested_or_root_dict("optic_glow")
	var calm_raw: Variant = raw.get("calm", raw.get("normal", null))
	var twitch_raw: Variant = raw.get("twitch", raw.get("warning", null))
	var alert_raw: Variant = raw.get("alert", raw.get("awake", null))
	var complete_raw: Variant = raw.get("complete", raw.get("surge", raw.get("done", null)))
	return {
		"calm": to_color(calm_raw, DEFAULT_OPTIC_GLOW["calm"]),
		"twitch": to_color(twitch_raw, DEFAULT_OPTIC_GLOW["twitch"]),
		"alert": to_color(alert_raw, DEFAULT_OPTIC_GLOW["alert"]),
		"complete": to_color(complete_raw, DEFAULT_OPTIC_GLOW["complete"]),
		"intensity": _validate_float(raw.get("intensity"), DEFAULT_OPTIC_GLOW["intensity"], 0.0, 10.0),
		"radius": _validate_float(raw.get("radius"), DEFAULT_OPTIC_GLOW["radius"], 0.0, 200.0),
	}


## Возвращает цвет оптики для конкретного состояния
func get_optic_color(state_name: String, fallback: Color = Color.WHITE) -> Color:
	var params := get_optic_glow_params()
	match state_name.to_lower():
		"calm", "normal", "idle":
			return params["calm"]
		"twitch", "warning", "strain":
			return params["twitch"]
		"alert", "awake", "critical":
			return params["alert"]
		"complete", "surge", "done", "finished":
			return params["complete"]
		_:
			if params.has(state_name) and params[state_name] is Color:
				return params[state_name] as Color
			return fallback


## Возвращает параметры частиц пара робота
func get_steam_particle_params() -> Dictionary:
	var raw := _get_nested_or_root_dict("steam_particles")
	var count_val: Variant = raw.get("count", raw.get("amount", raw.get("particle_count", null)))
	var life_val: Variant = raw.get("lifetime", raw.get("lifetime_sec", null))
	var s_min_val: Variant = raw.get("speed_min", raw.get("initial_velocity_min", null))
	var s_max_val: Variant = raw.get("speed_max", raw.get("initial_velocity_max", null))
	var spread_val: Variant = raw.get("spread_deg", raw.get("spread", null))
	var grav_val: Variant = raw.get("gravity_y", raw.get("gravity", null))
	var sc_min_val: Variant = raw.get("scale_min", raw.get("size_min", null))
	var sc_max_val: Variant = raw.get("scale_max", raw.get("size_max", null))
	var col_val: Variant = raw.get("color", raw.get("tint", null))
	var a_start_val: Variant = raw.get("alpha_start", raw.get("start_alpha", null))
	var a_end_val: Variant = raw.get("alpha_end", raw.get("end_alpha", null))

	var s_min := _validate_float(s_min_val, DEFAULT_STEAM_PARTICLES["speed_min"], 0.0, 1000.0)
	var s_max := _validate_float(s_max_val, DEFAULT_STEAM_PARTICLES["speed_max"], s_min, 1000.0)
	var sc_min := _validate_float(sc_min_val, DEFAULT_STEAM_PARTICLES["scale_min"], 0.1, 100.0)
	var sc_max := _validate_float(sc_max_val, DEFAULT_STEAM_PARTICLES["scale_max"], sc_min, 100.0)

	return {
		"count": _validate_int(count_val, DEFAULT_STEAM_PARTICLES["count"], 0, 500),
		"lifetime": _validate_float(life_val, DEFAULT_STEAM_PARTICLES["lifetime"], 0.05, 60.0),
		"speed_min": s_min,
		"speed_max": s_max,
		"spread_deg": _validate_float(spread_val, DEFAULT_STEAM_PARTICLES["spread_deg"], 0.0, 360.0),
		"gravity_y": _validate_float(grav_val, DEFAULT_STEAM_PARTICLES["gravity_y"], -1000.0, 1000.0),
		"scale_min": sc_min,
		"scale_max": sc_max,
		"color": to_color(col_val, DEFAULT_STEAM_PARTICLES["color"]),
		"alpha_start": _validate_float(a_start_val, DEFAULT_STEAM_PARTICLES["alpha_start"], 0.0, 1.0),
		"alpha_end": _validate_float(a_end_val, DEFAULT_STEAM_PARTICLES["alpha_end"], 0.0, 1.0),
	}


func _get_nested_or_root_dict(nested_key: String) -> Dictionary:
	var proc: Variant = data.get("procedural_animation", null)
	if proc is Dictionary and (proc as Dictionary).has(nested_key):
		var sub: Variant = (proc as Dictionary)[nested_key]
		if sub is Dictionary:
			return sub as Dictionary
		else:
			push_warning("Balance: 'procedural_animation.%s' must be a dictionary, got: %s" % [nested_key, str(sub)])
	elif proc != null and not (proc is Dictionary):
		push_warning("Balance: 'procedural_animation' must be a dictionary, got: %s" % str(proc))

	var root_val: Variant = data.get(nested_key, null)
	if root_val is Dictionary:
		return root_val as Dictionary
	elif root_val != null:
		push_warning("Balance: '%s' must be a dictionary, got: %s" % [nested_key, str(root_val)])

	return {}


static func _validate_float(raw: Variant, fallback: float, min_val: float = -INF, max_val: float = INF) -> float:
	if raw == null:
		return fallback
	if raw is int or raw is float:
		var v := float(raw)
		if is_nan(v) or is_inf(v):
			return fallback
		return clampf(v, min_val, max_val)
	if raw is String:
		var s := (raw as String).strip_edges()
		if s.is_valid_float():
			return clampf(float(s), min_val, max_val)
	return fallback


static func _validate_int(raw: Variant, fallback: int, min_val: int = -2147483648, max_val: int = 2147483647) -> int:
	if raw == null:
		return fallback
	if raw is int or raw is float:
		var v := int(raw)
		return clampi(v, min_val, max_val)
	if raw is String:
		var s := (raw as String).strip_edges()
		if s.is_valid_int():
			return clampi(int(s), min_val, max_val)
	return fallback


## Преобразует строку (#RRGGBB, #RRGGBBAA), массив или Color в Color. Некорректное значение -> fallback.
static func to_color(raw: Variant, fallback: Color = Color.WHITE) -> Color:
	if raw is Color:
		return raw
	if raw is String:
		var s := (raw as String).strip_edges()
		if s.is_empty():
			return fallback
		if not s.begins_with("#"):
			s = "#" + s
		if Color.html_is_valid(s):
			return Color.from_string(s, fallback)
		return fallback
	if raw is Array:
		var a := raw as Array
		if a.size() >= 4:
			return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
		elif a.size() == 3:
			return Color(float(a[0]), float(a[1]), float(a[2]), 1.0)
	return fallback
