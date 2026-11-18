class_name RepairStage
extends RefCounted

## Описание этапа ремонта: зоны, необходимые инструменты, награда и штраф
var id: String = ""
var title: String = ""
var instruction: String = ""
var recommended_tool: String = ""
var zones: Array = []
var required_tools: Array = []
var reward: float = 8.0
var penalty: float = 10.0


func _init(p_zones: Array = [], p_tools: Array = [], p_reward: float = 8.0, p_penalty: float = 10.0) -> void:
	zones = p_zones
	required_tools = p_tools
	reward = p_reward
	penalty = p_penalty


static func from_dict(d: Dictionary, p_reward: float = 8.0, p_penalty: float = 10.0) -> RepairStage:
	var stage := RepairStage.new([], [], p_reward, p_penalty)
	stage.id = str(d.get("id", ""))
	stage.title = str(d.get("title", ""))
	stage.instruction = str(d.get("instruction", ""))
	stage.recommended_tool = str(d.get("recommended_tool", ""))

	var raw_zones: Variant = d.get("zones", [])
	if raw_zones is Array:
		for z in raw_zones:
			if z is Dictionary:
				var z_copy: Dictionary = (z as Dictionary).duplicate(true)
				if not z_copy.has("done"):
					z_copy["done"] = false
				stage.zones.append(z_copy)

	return stage


func is_completed() -> bool:
	for z in zones:
		if not bool(z.get("done", false)):
			return false
	return true


func try_repair(zone_index: int, selected_tool_id: String) -> Dictionary:
	if zone_index < 0 or zone_index >= zones.size():
		return {"success": false, "already_done": false, "message": "Зона не найдена", "delta_instability": 0.0}

	var z: Dictionary = zones[zone_index]
	if bool(z.get("done", false)):
		return {"success": true, "already_done": true, "message": "Узел уже починен", "delta_instability": 0.0}

	var required_tool: String = str(z.get("tool", ""))
	if selected_tool_id == required_tool:
		z["done"] = true
		return {
			"success": true,
			"already_done": false,
			"message": "Успешно: " + str(z.get("label", "Узел")),
			"delta_instability": -reward
		}
	else:
		return {
			"success": false,
			"already_done": false,
			"message": "Не тот инструмент! Требуется: " + required_tool,
			"delta_instability": penalty
		}
