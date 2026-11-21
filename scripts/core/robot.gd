class_name Robot
extends RefCounted

## Состояние и параметры стабильности робота
var instability: float = 20.0
var threshold: float = 70.0
var min_threshold: float = 40.0
var threshold_drop_per_wake: float = 5.0
var idle_growth: float = 0.45
var calm_after_wake: float = 45.0
var wake_count: int = 0
var zones: Array = []

# Процедурные анимации и интерактивность из robot.json
var breathing_params: Dictionary = {}
var mouse_proximity_params: Dictionary = {}
var optic_glow_params: Dictionary = {}
var steam_particle_params: Dictionary = {}


func configure(balance: Balance) -> void:
	instability = balance.get_float("start_instability", 20.0)
	threshold = balance.get_float("threshold", 70.0)
	min_threshold = balance.get_float("min_threshold", 40.0)
	threshold_drop_per_wake = balance.get_float("threshold_drop_per_wake", 5.0)
	idle_growth = balance.get_float("idle_growth", 0.45)
	calm_after_wake = balance.get_float("calm_after_wake", 45.0)
	wake_count = 0
	breathing_params = balance.get_breathing_params()
	mouse_proximity_params = balance.get_mouse_proximity_params()
	optic_glow_params = balance.get_optic_glow_params()
	steam_particle_params = balance.get_steam_particle_params()


func add_instability(x: float) -> void:
	instability = clampf(instability + x, 0.0, 100.0)


func repair_zone(id: String) -> void:
	for z in zones:
		if str(z.get("id", "")) == id:
			z["done"] = true
			return


func tick(delta: float, is_calm: bool) -> bool:
	if is_calm:
		add_instability(idle_growth * delta)
		if instability >= threshold:
			return true
	return false


func on_wake() -> void:
	wake_count += 1


func calm_down() -> void:
	instability = calm_after_wake
	threshold = maxf(threshold - threshold_drop_per_wake, min_threshold)


func get_heat_ratio() -> float:
	return clampf((instability - 20.0) / 80.0, 0.0, 1.0)


func is_critical() -> bool:
	return instability >= 100.0


## Вертикальное смещение дыхания для заданного времени в секундах
func get_breathing_offset(time_sec: float) -> float:
	var amp: float = float(breathing_params.get("amplitude", 3.0))
	var freq: float = float(breathing_params.get("frequency", 0.5))
	var delay: float = float(breathing_params.get("delay", 0.4))
	var cycle: float = (1.0 / freq) + delay if freq > 0.0 else 1.0
	var phase: float = fmod(time_sec, cycle)
	if freq > 0.0 and phase < (1.0 / freq):
		return sin(phase * freq * TAU) * amp
	return 0.0


## Текущий цвет визора/оптики робота
func get_optic_color(is_awake: bool, is_critical_warn: bool = false) -> Color:
	if is_awake:
		return optic_glow_params.get("alert", Color(0.90, 0.16, 0.10))
	if is_critical_warn or is_critical():
		return optic_glow_params.get("twitch", Color(0.85, 0.76, 0.60))
	return optic_glow_params.get("calm", Color(0.45, 0.55, 0.57))
