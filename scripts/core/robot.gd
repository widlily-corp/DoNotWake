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


func configure(balance: Balance) -> void:
	instability = balance.get_float("start_instability", 20.0)
	threshold = balance.get_float("threshold", 70.0)
	min_threshold = balance.get_float("min_threshold", 40.0)
	threshold_drop_per_wake = balance.get_float("threshold_drop_per_wake", 5.0)
	idle_growth = balance.get_float("idle_growth", 0.45)
	calm_after_wake = balance.get_float("calm_after_wake", 45.0)
	wake_count = 0


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
