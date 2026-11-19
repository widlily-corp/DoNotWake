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
var tool_labels: Dictionary = {}
var current_stage_index: int = 0
var freeze_left: float = 0.0
var freeze_seconds: float = 6.0
var freeze_motion_limit: float = 1.2
var freeze_penalty: float = 15.0
var freeze_grace: float = 0.4
var freeze_penalty_cooldown: float = 0.6
var max_wakes_allowed: int = 3

# Статистика смены
var elapsed: float = 0.0
var mistakes: int = 0
var fail_reason: String = ""

var _grace_left: float = 0.0
var _penalty_cd: float = 0.0


func _ready() -> void:
	initialize_game()


func initialize_game(config_path: String = Balance.DEFAULT_CONFIG_PATH) -> void:
	balance = Balance.new(config_path)
	robot = Robot.new()
	robot.configure(balance)

	freeze_seconds = maxf(balance.get_float("freeze_seconds", 6.0), 0.5)
	freeze_motion_limit = maxf(balance.get_float("freeze_motion_limit", 1.2), 0.0)
	freeze_penalty = maxf(balance.get_float("freeze_penalty", 15.0), 0.0)
	freeze_grace = maxf(balance.get_float("freeze_grace", 0.4), 0.0)
	freeze_penalty_cooldown = maxf(balance.get_float("freeze_penalty_cooldown", 0.6), 0.0)
	max_wakes_allowed = maxi(balance.get_int("max_wakes_allowed", 3), 0)

	tool_labels.clear()
	for t in balance.get_tools():
		tool_labels[str(t["id"])] = str(t.get("label", t["id"]))

	stages.clear()
	var rew: float = absf(balance.get_float("success_reward", 8.0))
	var pen: float = absf(balance.get_float("wrong_tool_penalty", 10.0))
	for s_data in balance.get_stages():
		stages.append(RepairStage.from_dict(s_data, rew, pen))

	current_stage_index = 0
	current_state = State.CALM
	elapsed = 0.0
	mistakes = 0
	fail_reason = ""


func start() -> void:
	current_state = State.CALM
	current_stage_index = 0
	robot.configure(balance)
	emit_signal("state_changed", current_state)
	if stages.is_empty():
		finish(false, "Нет данных об этапах ремонта (проверьте robot.json)")
		return
	emit_signal("stage_changed", current_stage_index, get_current_stage())


func is_over() -> bool:
	return current_state == State.DONE or current_state == State.FAIL


func get_current_stage() -> RepairStage:
	if current_stage_index >= 0 and current_stage_index < stages.size():
		return stages[current_stage_index]
	return null


func get_tool_label(tool_id: String) -> String:
	return str(tool_labels.get(tool_id, tool_id))


func tick(delta: float) -> void:
	if is_over():
		return
	elapsed += delta
	_penalty_cd = maxf(_penalty_cd - delta, 0.0)

	if current_state == State.CALM:
		if robot.tick(delta, true):
			wake()
	elif current_state == State.AWAKE:
		_grace_left = maxf(_grace_left - delta, 0.0)
		freeze_left -= delta
		if freeze_left <= 0.0:
			calm_down()

	if robot.is_critical() and not is_over():
		finish(false)


func apply_repair(zone_index: int, tool_id: String) -> void:
	if current_state != State.CALM:
		return

	var stage: RepairStage = get_current_stage()
	if stage == null:
		return

	var result: Dictionary = stage.try_repair(zone_index, tool_id)
	if bool(result.get("already_done", false)):
		emit_signal("feedback_triggered", str(result.get("message", "")), false)
		return

	robot.add_instability(float(result.get("delta_instability", 0.0)))

	var is_success: bool = bool(result.get("success", false))
	var msg: String = str(result.get("message", ""))
	if not is_success:
		mistakes += 1
		var req := str(result.get("required_tool", ""))
		if req != "":
			msg += " Нужно: " + get_tool_label(req)
	emit_signal("feedback_triggered", msg, not is_success)

	if robot.is_critical():
		finish(false)
		return

	if robot.instability >= robot.threshold:
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
		emit_signal("feedback_triggered", "Этап завершён! Далее: " + get_current_stage().title, false)


func wake() -> void:
	robot.on_wake()
	if robot.wake_count > max_wakes_allowed:
		finish(false, "Робот проснулся слишком много раз (%d из %d допустимых)" % [robot.wake_count, max_wakes_allowed])
		return
	current_state = State.AWAKE
	freeze_left = freeze_seconds
	_grace_left = freeze_grace
	_penalty_cd = 0.0
	emit_signal("state_changed", current_state)
	emit_signal("feedback_triggered", "РОБОТ ПРОСЫПАЕТСЯ! ЗАМРИ!", true)


func on_mouse_moved(relative_length: float) -> void:
	if current_state != State.AWAKE or _grace_left > 0.0 or _penalty_cd > 0.0:
		return
	if relative_length > freeze_motion_limit:
		_penalty_cd = freeze_penalty_cooldown
		mistakes += 1
		robot.add_instability(freeze_penalty)
		freeze_left += 1.5
		emit_signal("feedback_triggered", "ДВИЖЕНИЕ ЗАМЕЧЕНО! +%d%% НЕСТАБИЛЬНОСТИ" % int(freeze_penalty), true)
		if robot.is_critical():
			finish(false)


func calm_down() -> void:
	current_state = State.CALM
	robot.calm_down()
	emit_signal("state_changed", current_state)
	emit_signal("feedback_triggered", "Робот успокоился. Порог снизился до %d%%" % int(robot.threshold), false)


func finish(is_success: bool, reason: String = "") -> void:
	if is_over():
		return
	current_state = State.DONE if is_success else State.FAIL
	if not is_success:
		fail_reason = reason if reason != "" else "Аварийный перегрев сервосистем (нестабильность 100%)"
	emit_signal("state_changed", current_state)
	emit_signal("game_finished", is_success)
	var end_msg: String = "ЗАКАЗ ВЫПОЛНЕН УСПЕШНО" if is_success else "СМЕНА ПРОВАЛЕНА"
	emit_signal("feedback_triggered", end_msg, not is_success)
