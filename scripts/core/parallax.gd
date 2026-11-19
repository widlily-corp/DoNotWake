class_name ParallaxRig
extends RefCounted

## Риг 2.5D-глубины для Do Not Wake.
##
## Считает смещение слоёв от позиции мыши относительно центра окна. Экземпляр
## создаётся сценой (MainView / MainMenu), автолоад не нужен.
##
## Знаки: мышь правее/ниже центра -> все слои уезжают вправо/вниз. Единая логика:
## чем больше depth слоя, тем сильнее он реагирует (дальний фон 1.0, средний план
## 0.45, ближний 0.15, UI 0.0). Дальний план «гуляет» сильнее всех, ближний стоит —
## получается эффект окна в комнату, а HUD и тулбар остаются неподвижной рамкой.
##
## Смещение всегда целое (Vector2.round()), чтобы Nearest-фильтр не мылил пиксель-арт.

const DEFAULT_CONFIG_PATH: String = "res://data/parallax.json"
const DESIGN_SIZE: Vector2 = Vector2(1280, 720)

## Значения по умолчанию совпадают с data/parallax.json: риг работает и без файла.
const DEFAULT_LAYERS: Dictionary = {
	"far": {"depth": 1.0},
	"mid": {"depth": 0.45},
	"near": {"depth": 0.15},
	"ui": {"depth": 0.0},
	"menu_bezel": {"depth": 0.4, "amplitude_px": 6.0},
	"menu_screen": {"depth": 0.8, "amplitude_px": 6.0},
	"menu_deck": {"depth": 0.5, "amplitude_px": 6.0},
}

var enabled: bool = true
var base_amplitude_px: float = 4.0
var global_multiplier: float = 1.0
var smoothing: float = 9.0
var max_offset_px: float = 5.0
var deadzone: float = 0.06
## name -> {"depth": float, "amplitude_px": float (опционально)}
var layers: Dictionary = {}

var _smoothed: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _warned_layers: Dictionary = {}


func _init(path: String = DEFAULT_CONFIG_PATH) -> void:
	load_config(path)


## Читает data/parallax.json. Отсутствующие и битые поля заменяются дефолтами.
func load_config(path: String = DEFAULT_CONFIG_PATH) -> void:
	enabled = true
	base_amplitude_px = 4.0
	global_multiplier = 1.0
	smoothing = 9.0
	max_offset_px = 5.0
	deadzone = 0.06
	layers = DEFAULT_LAYERS.duplicate(true)
	_warned_layers.clear()
	reset()

	if not FileAccess.file_exists(path):
		push_warning("ParallaxRig: config not found, defaults used: " + path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ParallaxRig: failed to open config: " + path)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("ParallaxRig: config is not a JSON dictionary: " + path)
		return

	_apply_config(parsed as Dictionary)


func _apply_config(cfg: Dictionary) -> void:
	enabled = _cfg_bool(cfg, "enabled", enabled)
	base_amplitude_px = clampf(_cfg_float(cfg, "base_amplitude_px", base_amplitude_px), 0.0, 12.0)
	global_multiplier = clampf(_cfg_float(cfg, "global_multiplier", global_multiplier), 0.0, 3.0)
	smoothing = clampf(_cfg_float(cfg, "smoothing", smoothing), 0.0, 30.0)
	max_offset_px = clampf(_cfg_float(cfg, "max_offset_px", max_offset_px), 0.0, 12.0)
	deadzone = clampf(_cfg_float(cfg, "deadzone", deadzone), 0.0, 0.9)

	var raw_layers: Variant = cfg.get("layers", null)
	if not raw_layers is Dictionary:
		return

	for key in (raw_layers as Dictionary):
		var layer_name := str(key)
		var raw: Variant = (raw_layers as Dictionary)[key]
		if not raw is Dictionary:
			push_warning("ParallaxRig: layer '%s' must be a dictionary" % layer_name)
			continue
		var depth_raw: Variant = (raw as Dictionary).get("depth", null)
		if not (depth_raw is float or depth_raw is int):
			push_warning("ParallaxRig: layer '%s' has no numeric depth" % layer_name)
			continue
		var entry: Dictionary = {"depth": clampf(float(depth_raw), 0.0, 2.0)}
		var amp_raw: Variant = (raw as Dictionary).get("amplitude_px", null)
		if amp_raw is float or amp_raw is int:
			entry["amplitude_px"] = clampf(float(amp_raw), 0.0, 12.0)
		layers[layer_name] = entry


## Обновляет сглаженное положение. mouse_pos и viewport_size — в координатах канваса
## (тот же масштаб, что у _draw), поэтому при canvas_items stretch всё сходится.
func update(delta: float, mouse_pos: Vector2, viewport_size: Vector2) -> void:
	if not enabled:
		reset()
		return

	_target = _target_from_mouse(mouse_pos, viewport_size)
	_smoothed = _smoothed.lerp(_target, smoothing_weight(delta))
	if _smoothed.length_squared() < 0.000001:
		_smoothed = Vector2.ZERO
	elif _smoothed.distance_squared_to(_target) < 0.000001:
		_smoothed = _target


## Вес lerp для экспоненциального затухания: 1 - exp(-smoothing * delta).
func smoothing_weight(delta: float) -> float:
	if smoothing <= 0.0:
		return 1.0
	return clampf(1.0 - exp(-smoothing * maxf(delta, 0.0)), 0.0, 1.0)


## Смещение для произвольной глубины (базовая амплитуда * depth).
func offset_for(depth: float) -> Vector2:
	return _offset(depth, base_amplitude_px)


## Смещение для именованного слоя из data/parallax.json (с учётом amplitude_px слоя).
func offset_for_layer(layer_name: String) -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var layer: Dictionary = layers.get(layer_name, {})
	if layer.is_empty():
		_warn_unknown_layer(layer_name)
		return Vector2.ZERO
	var layer_amplitude := float(layer.get("amplitude_px", base_amplitude_px))
	return _offset(float(layer.get("depth", 0.0)), layer_amplitude)


## Сброс в ноль: смена сцены, старт, потеря фокуса окна.
func reset() -> void:
	_target = Vector2.ZERO
	_smoothed = Vector2.ZERO


## Мгновенно применяет текущую цель без догоняющей анимации.
func snap() -> void:
	_smoothed = _target


func get_target_normalized() -> Vector2:
	return _target


func get_smoothed_normalized() -> Vector2:
	return _smoothed


func _offset(depth: float, amplitude_px: float) -> Vector2:
	if not enabled:
		return Vector2.ZERO
	if is_zero_approx(depth) or is_zero_approx(amplitude_px) or is_zero_approx(global_multiplier):
		return Vector2.ZERO

	var raw := _smoothed * amplitude_px * global_multiplier * depth
	if max_offset_px > 0.0:
		raw.x = clampf(raw.x, -max_offset_px, max_offset_px)
		raw.y = clampf(raw.y, -max_offset_px, max_offset_px)
	return raw.round()


## Нормализует позицию мыши к [-1..1] по каждой оси, затем радиальный deadzone.
func _target_from_mouse(mouse_pos: Vector2, viewport_size: Vector2) -> Vector2:
	var size := viewport_size
	if size.x < 2.0 or size.y < 2.0:
		size = DESIGN_SIZE
	var center := size * 0.5
	var norm := Vector2(
		clampf((mouse_pos.x - center.x) / center.x, -1.0, 1.0),
		clampf((mouse_pos.y - center.y) / center.y, -1.0, 1.0)
	)
	var length := norm.length()
	if length <= deadzone:
		return Vector2.ZERO
	var scale := (length - deadzone) / (1.0 - deadzone) / length
	return norm * scale


func _warn_unknown_layer(layer_name: String) -> void:
	if _warned_layers.has(layer_name):
		return
	_warned_layers[layer_name] = true
	push_warning("ParallaxRig: unknown layer '%s'" % layer_name)


func _cfg_float(cfg: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = cfg.get(key, fallback)
	if value is float or value is int:
		return float(value)
	return fallback


func _cfg_bool(cfg: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = cfg.get(key, fallback)
	if value is bool:
		return value
	return fallback
