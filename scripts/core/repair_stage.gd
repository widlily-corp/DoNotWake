class_name RepairStage
extends RefCounted

## Описание этапа ремонта: зоны, необходимые инструменты, награда и штраф
var zones: Array = []
var required_tools: Array = []
var reward: float = 0.0
var penalty: float = 0.0


func _init(p_zones: Array = [], p_tools: Array = [], p_reward: float = 5.0, p_penalty: float = 8.0) -> void:
	zones = p_zones
	required_tools = p_tools
	reward = p_reward
	penalty = p_penalty
