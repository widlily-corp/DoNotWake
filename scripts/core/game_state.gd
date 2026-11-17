class_name GameState
extends Node

## Координатор игрового состояния и петли ремонта
enum State { CALM, AWAKE, DONE, FAIL }

signal state_changed(new_state: State)
signal stage_changed(stage_index: int, stage: RepairStage)
signal game_finished(is_success: bool)
signal feedback_triggered(message: String, is_alert: bool)

var current_state: State = State.CALM
var robot: Robot
var balance: Balance
var stages: Array[RepairStage] = []
var current_stage_index: int = 0
var freeze_left: float = 0.0
var freeze_seconds: float = 6.0
var freeze_motion_limit: float = 1.2
var freeze_penalty: float = 15.0


func _ready() -> void:
	print("core ready")
	initialize_game()


func initialize_game() -> void:
	balance = Balance.new()
	robot = Robot.new()
	robot.configure(balance)

	freeze_seconds = balance.get_float("freeze_seconds", 6.0)
	freeze_motion_limit = balance.get_float("freeze_motion_limit", 1.2)
	freeze_penalty = balance.get_float("freeze_penalty", 15.0)

	stages.clear()
	var raw_stages: Array = balance.get_stages()
	var rew: float = balance.get_float("success_reward", 8.0)
	var pen: float = balance.get_float("wrong_tool_penalty", 10.0)
	for s_data in raw_stages:
		if s_data is Dictionary:
			stages.append(RepairStage.from_dict(s_data, rew, pen))

	current_stage_index = 0
	current_state = State.CALM


func start() -> void:
	current_state = State.CALM
	current_stage_index = 0
	robot.configure(balance)
	emit_signal("state_changed", current_state)
	if stages.size() > 0:
		emit_signal("stage_changed", current_stage_index, get_current_stage())


func get_current_stage() -> RepairStage:
	if current_stage_index >= 0 and current_stage_index < stages.size():
		return stages[current_stage_index]
	return null


func tick(delta: float) -> void:
	if current_state == State.CALM:
		var breached: bool = robot.tick(delta, true)
		if breached:
			wake()
	elif current_state == State.AWAKE:
		freeze_left -= delta
		if freeze_left <= 0.0:
			calm_down()

	if robot.is_critical() and current_state != State.DONE and current_state != State.FAIL:
		finish(false)


func apply_repair(zone_index: int, tool_id: String) -> void:
	if current_state != State.CALM:
		return

	var stage: RepairStage = get_current_stage()
	if stage == null:
		return

	var result: Dictionary = stage.try_repair(zone_index, tool_id)
	var delta_inst: float = float(result.get("delta_instability", 0.0))
	robot.add_instability(delta_inst)

	var is_success: bool = bool(result.get("success", false))
	var msg: String = str(result.get("message", ""))
	emit_signal("feedback_triggered", msg, not is_success)

	if robot.is_critical():
		finish(false)
		return

	if robot.instability >= robot.threshold and current_state == State.CALM:
		wake()
		return

	if stage.is_completed():
		advance_stage()


func advance_stage() -> void:
	current_stage_index += 1
	if current_stage_index >= stages.size():
		finish(true)
	else:
		emit_signal("stage_changed", current_stage_index, get_current_stage())
		emit_signal("feedback_triggered", "Стадия завершена! " + get_current_stage().title, false)


func wake() -> void:
	current_state = State.AWAKE
	freeze_left = freeze_seconds
	robot.on_wake()
	emit_signal("state_changed", current_state)
	emit_signal("feedback_triggered", "РОБОТ ПРОСЫПАЕТСЯ! НЕ ДВИГАЙ МЫШЬЮ!", true)


func on_mouse_moved(relative_length: float) -> void:
	if current_state == State.AWAKE:
		if relative_length > freeze_motion_limit:
			robot.add_instability(freeze_penalty)
			freeze_left += 1.5
			emit_signal("feedback_triggered", "ДВИЖЕНИЕ ЗАМЕЧЕНО! ШТРАФ СТАБИЛЬНОСТИ!", true)
			if robot.is_critical():
				finish(false)


func calm_down() -> void:
	current_state = State.CALM
	robot.calm_down()
	emit_signal("state_changed", current_state)
	emit_signal("feedback_triggered", "Робот успокоился. Порог снизился до " + str(int(robot.threshold)), false)


func finish(is_success: bool) -> void:
	current_state = State.DONE if is_success else State.FAIL
	emit_signal("state_changed", current_state)
	emit_signal("game_finished", is_success)
	var end_msg: String = "ЗАКАЗ ВЫПОЛНЕН УСПЕШНО" if is_success else "СМЕНА ПРОВАЛЕНА: РОБОТ ПЕРЕГРЕЛСЯ"
	emit_signal("feedback_triggered", end_msg, not is_success)
