class_name Robot
extends RefCounted

## Состояние и параметры стабильности робота
var instability: float = 0.0
var threshold: float = 70.0
var zones: Array = []


func add_instability(x: float) -> void:
	# TODO
	instability += x


func repair_zone(id: String) -> void:
	# TODO
	pass


func tick(delta: float) -> void:
	# TODO
	pass
