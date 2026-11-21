class_name GameState
extends Node

## Координатор игрового состояния, легаси-режима и 6-фазной петли смены
enum State { CALM, AWAKE, DONE, FAIL }
enum Phase { BRIEFING, DIAGNOSTICS, PART_SELECT, DOC_SEARCH, REPAIR,
             THREAT_CONTROL, VERIFY, SHIFT_COMPLETE, SHIFT_FAILED }
enum Threat { CALM, TWITCH, AWAKE }
enum Mode { LEGACY, NEW }

# Сигналы легаси-режима
signal state_changed(new_state: State)
signal stage_changed(stage_index: int, stage: RepairStage)
signal game_finished(is_success: bool)
signal feedback_triggered(message: String, is_alert: bool)

# 16 сигналов новой петли по контрактам данных §4.1
signal phase_changed(phase: int)
signal diagnostics_ready(report: Dictionary)
signal part_selected(part_id: String, correct: bool)
signal documentation_requested()
signal document_read(card_id: String, correct: bool)
signal repair_started(part_id: String, steps: Array)
signal step_requested(index: int, step: Dictionary)
signal step_progress(index: int, progress: float)
signal step_completed(index: int)
signal step_failed(index: int, reason: String)
signal threat_changed(level: int, instability: float)
signal wake_started(duration: float)
signal wake_ended()
signal pause_changed(paused: bool, reason: String)
signal verification_finished(passed: bool, details: Dictionary)
signal shift_finished(success: bool, stats: Dictionary)

# Состояние системы
var current_mode: Mode = Mode.LEGACY
var current_state: State = State.CALM
var current_phase: Phase = Phase.BRIEFING
var current_threat: Threat = Threat.CALM

var robot: Robot
var balance: Balance

# Легаси-переменные
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
var elapsed: float = 0.0
var mistakes: int = 0
var fail_reason: String = ""

var _grace_left: float = 0.0
var _penalty_cd: float = 0.0

# Переменные новой петли
var shift_elapsed: float = 0.0
var parts_done: int = 0
var is_paused: bool = false

var _pause_uses: int = 0
var _pause_cooldown_left: float = 0.0
var _pause_elapsed: float = 0.0

var _override_parts: Array = []
var _override_cards: Array = []
var _parts: Array = []
var _cards: Array = []
var _drawers: Array = []
var _verified_part_ids: Array = []

var _current_part: Dictionary = {}
var _current_part_id: String = ""
var _current_card: Dictionary = {}
var _current_card_id: String = ""

var _current_step_index: int = 0
var _step_quality_sum: float = 0.0
var _step_time_used: float = 0.0
var _step_elapsed: float = 0.0
var _step_success_count: int = 0
var _order_errors: int = 0
var _part_attempts: int = 0

var _threat_control_timer: float = 0.0
var _threat_hold_target: float = 3.0
var _threat_motion_cd: float = 0.0
var _diagnostics_report: Dictionary = {}


const LoopDataScript = preload("res://scripts/core/loop_data.gd")

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

	current_mode = Mode.LEGACY
	current_phase = Phase.BRIEFING
	current_threat = Threat.CALM
	current_stage_index = 0
	current_state = State.CALM
	elapsed = 0.0
	shift_elapsed = 0.0
	mistakes = 0
	parts_done = 0
	fail_reason = ""
	is_paused = false
	_pause_uses = 0
	_pause_cooldown_left = 0.0
	_pause_elapsed = 0.0

	_override_parts.clear()
	_override_cards.clear()
	_parts.clear()
	_cards.clear()
	_drawers.clear()
	_verified_part_ids.clear()
	_current_part = {}
	_current_part_id = ""
	_current_card = {}
	_current_card_id = ""
	_current_step_index = 0
	_step_quality_sum = 0.0
	_step_time_used = 0.0
	_step_elapsed = 0.0
	_step_success_count = 0
	_order_errors = 0
	_part_attempts = 0
	_threat_control_timer = 0.0
	_diagnostics_report = {}


# =============================================================================
# ПУБЛИЧНЫЙ API НОВОЙ ПЕТЛИ (контракты данных §4.1)
# =============================================================================

## Тестовый шов: детерминированные детали и карточки вместо чтения с диска
func setup_loop(parts: Array, cards: Array) -> void:
	_override_parts = parts.duplicate(true)
	_override_cards = cards.duplicate(true)
	if current_mode == Mode.NEW:
		_parts = _override_parts.duplicate(true)
		_cards = _override_cards.duplicate(true)


## Запуск новой смены: инициализация петли, переход в DIAGNOSTICS
func start_shift() -> void:
	current_mode = Mode.NEW
	current_state = State.CALM
	current_threat = Threat.CALM
	current_phase = Phase.BRIEFING

	shift_elapsed = 0.0
	mistakes = 0
	parts_done = 0
	fail_reason = ""
	is_paused = false
	_pause_uses = 0
	_pause_cooldown_left = 0.0
	_pause_elapsed = 0.0

	_verified_part_ids.clear()
	_current_part = {}
	_current_part_id = ""
	_current_card = {}
	_current_card_id = ""
	_current_step_index = 0
	_step_quality_sum = 0.0
	_step_time_used = 0.0
	_step_elapsed = 0.0
	_step_success_count = 0
	_order_errors = 0
	_part_attempts = 0
	_threat_control_timer = 0.0

	if robot != null and balance != null:
		robot.configure(balance)

	if not _override_parts.is_empty():
		_parts = _override_parts.duplicate(true)
	else:
		_parts = LoopDataScript.load_parts()

	if not _override_cards.is_empty():
		_cards = _override_cards.duplicate(true)
		_drawers = []
	else:
		var doc_data: Dictionary = LoopDataScript.load_documents()
		_cards = doc_data.get("cards", [])
		_drawers = doc_data.get("drawers", [])

	_diagnostics_report.clear()
	_set_phase(Phase.DIAGNOSTICS)
	threat_changed.emit(current_threat, robot.instability if robot != null else 0.0)


## Сборка отчёта по неисправным деталям текущей смены -> переход в PART_SELECT
func run_diagnostics() -> Dictionary:
	if current_phase != Phase.DIAGNOSTICS or current_threat == Threat.AWAKE or is_paused:
		return {}

	var report_parts: Array = []
	for p in _parts:
		if p is Dictionary:
			var pid: String = str(p.get("id", ""))
			if not _verified_part_ids.has(pid):
				report_parts.append({
					"id": pid,
					"tag": str(p.get("tag", "")),
					"label": str(p.get("label", "")),
					"component_name": str(p.get("component_name", p.get("label", ""))),
					"fault_code": str(p.get("fault_code", "")),
					"symptom": str(p.get("symptom", "")),
					"tag_pos": p.get("tag_pos", [640, 360])
				})

	_diagnostics_report = {
		"parts": report_parts,
		"count": report_parts.size()
	}

	_set_phase(Phase.PART_SELECT)
	diagnostics_ready.emit(_diagnostics_report)
	return _diagnostics_report


## Повторное получение последнего отчёта диагностики
func get_diagnostics_report() -> Dictionary:
	return _diagnostics_report


## Выбор узла/детали на роботе
func select_part(part_id: String) -> bool:
	if (current_phase != Phase.PART_SELECT and current_phase != Phase.DIAGNOSTICS) or current_threat == Threat.AWAKE or is_paused:
		return false

	var found_part: Dictionary = {}
	for p in _parts:
		if p is Dictionary and (str(p.get("id", "")) == part_id or str(p.get("tag", "")) == part_id):
			var pid: String = str(p.get("id", ""))
			if not _verified_part_ids.has(pid):
				found_part = p
				part_id = pid
				break

	if found_part.is_empty():
		var pen: float = _get_loop_float("wrong_part_penalty", 5.0)
		_add_instability_internal(pen)
		mistakes += 1
		part_selected.emit(part_id, false)
		emit_signal("feedback_triggered", "НЕВЕРНАЯ ДЕТАЛЬ: +%d%% НЕСТАБИЛЬНОСТИ" % int(pen), true)
		return false

	_current_part = found_part
	_current_part_id = part_id
	_current_card = {}
	_current_card_id = ""
	_set_phase(Phase.DOC_SEARCH)
	part_selected.emit(part_id, true)
	emit_signal("feedback_triggered", "Выбрана деталь: " + str(_current_part.get("label", part_id)), false)
	return true


## Запрос открытия интерфейса картотеки
func request_documentation() -> void:
	if current_threat == Threat.AWAKE or is_paused:
		return
	documentation_requested.emit()


## Индекс картотеки (ящики и краткие карточки без steps_text)
func get_documentation_index() -> Dictionary:
	var short_cards: Array = []
	for c in _cards:
		if c is Dictionary:
			short_cards.append({
				"id": str(c.get("id", "")),
				"tag": str(c.get("tag", "")),
				"title": str(c.get("title", "")),
				"drawer": str(c.get("drawer", "")),
				"tool_list": c.get("tool_list", []),
				"time_norm_sec": c.get("time_norm_sec", 0)
			})

	var drawers_out: Array = _drawers.duplicate(true)
	if drawers_out.is_empty():
		var drawer_map: Dictionary = {}
		for c in _cards:
			if c is Dictionary and c.has("drawer"):
				var d_id: String = str(c["drawer"])
				if not drawer_map.has(d_id):
					drawer_map[d_id] = {
						"id": d_id,
						"label": "Ящик " + d_id,
						"cards": []
					}
				drawer_map[d_id]["cards"].append(str(c.get("id", "")))
		drawers_out = drawer_map.values()

	return {
		"drawers": drawers_out,
		"cards": short_cards
	}


## Чтение карточки ТО из картотеки
func read_card(card_id: String) -> Dictionary:
	if current_phase != Phase.DOC_SEARCH or current_threat == Threat.AWAKE or is_paused:
		return {}

	var found_card: Dictionary = {}
	for c in _cards:
		if c is Dictionary and str(c.get("id", "")) == card_id:
			found_card = c
			break

	var is_correct: bool = false
	if not found_card.is_empty() and not _current_part.is_empty():
		var doc_id: String = str(_current_part.get("doc_id", ""))
		var part_tag: String = str(_current_part.get("tag", ""))
		var card_tag: String = str(found_card.get("tag", ""))
		if (doc_id != "" and card_id == doc_id) or (part_tag != "" and card_tag == part_tag):
			is_correct = true

	if not is_correct:
		var pen: float = _get_loop_float("wrong_doc_penalty", 4.0)
		_add_instability_internal(pen)
		mistakes += 1
		document_read.emit(card_id, false)
		emit_signal("feedback_triggered", "НЕВЕРНЫЙ ФОРМУЛЯР ТО: +%d%% НЕСТАБИЛЬНОСТИ" % int(pen), true)
		return {}

	_current_card = found_card
	_current_card_id = card_id
	document_read.emit(card_id, true)
	emit_signal("feedback_triggered", "Открыт формуляр: " + str(found_card.get("title", card_id)), false)
	return _current_card


## Старт тактильного ремонта по регламенту открытой карточки
func begin_repair() -> bool:
	if current_phase != Phase.DOC_SEARCH or current_threat == Threat.AWAKE or is_paused:
		return false

	if _current_card.is_empty() or _current_card_id == "":
		return false

	_set_phase(Phase.REPAIR)
	_current_step_index = 0
	_step_quality_sum = 0.0
	_step_time_used = 0.0
	_step_elapsed = 0.0
	_step_success_count = 0
	_order_errors = 0

	var steps: Array = _current_part.get("steps", [])
	repair_started.emit(_current_part_id, steps)
	if not steps.is_empty():
		var first_step: Dictionary = steps[0] as Dictionary
		step_requested.emit(0, first_step)
	else:
		begin_threat_control()

	return true


## Приём результата выполнения тактильного шага
func report_step_result(index: int, success: bool, quality: float = 1.0, reason: String = "") -> void:
	if current_phase != Phase.REPAIR or current_threat == Threat.AWAKE or is_paused:
		return

	if index != _current_step_index:
		return

	var steps: Array = _current_part.get("steps", [])
	if index < 0 or index >= steps.size():
		return

	var step: Dictionary = steps[index] as Dictionary
	var step_inst: Dictionary = step.get("instability", {})

	if success:
		var delta_inst: float = float(step_inst.get("success", -4.0))
		_add_instability_internal(delta_inst)
		_step_quality_sum += quality
		_step_time_used += _step_elapsed
		_step_elapsed = 0.0
		_step_success_count += 1
		step_completed.emit(index)

		_current_step_index += 1
		if _current_step_index >= steps.size():
			begin_threat_control()
		else:
			var next_step: Dictionary = steps[_current_step_index] as Dictionary
			step_requested.emit(_current_step_index, next_step)
	else:
		var delta_inst: float = float(step_inst.get("fail", 6.0))
		_add_instability_internal(delta_inst)
		mistakes += 1

		if reason.begins_with("order:"):
			_order_errors += 1
			var order_pen: float = _get_loop_float("order_penalty", 10.0)
			_add_instability_internal(order_pen)

		_step_elapsed = 0.0
		step_failed.emit(index, reason)

		# Шаг не сдвигается: игрок получает повторную попытку,
		# иначе после первого же срыва ремонт «зависает» без активного шага.
		if current_phase == Phase.REPAIR and index == _current_step_index:
			step_requested.emit(index, steps[index] as Dictionary)


## Запрос тактической паузы
func request_pause(reason: String = "") -> void:
	if current_phase != Phase.REPAIR and current_phase != Phase.THREAT_CONTROL:
		return
	if current_threat == Threat.AWAKE:
		return
	if is_paused:
		return
	var max_uses: int = _get_loop_int("pause.max_uses_per_shift", 3)
	if _pause_uses >= max_uses:
		return
	if _pause_cooldown_left > 0.0:
		return

	is_paused = true
	_pause_uses += 1
	_pause_elapsed = 0.0
	pause_changed.emit(true, reason)
	emit_signal("feedback_triggered", "ПАУЗА: Охлаждение систем", false)


## Возобновление работы после паузы
func request_resume() -> void:
	if not is_paused:
		return

	is_paused = false
	_pause_cooldown_left = _get_loop_float("pause.cooldown_seconds", 20.0)
	pause_changed.emit(false, "")
	emit_signal("feedback_triggered", "ВОЗОБНОВЛЕНИЕ РАБОТЫ", false)


## Переход в фазу замирания / контроля угрозы
func begin_threat_control() -> void:
	if current_phase != Phase.REPAIR and current_phase != Phase.THREAT_CONTROL:
		return
	if current_threat == Threat.AWAKE or is_paused:
		return

	_threat_control_timer = 0.0
	_threat_hold_target = _get_loop_float("threat_control.hold_seconds", 3.0)
	_set_phase(Phase.THREAT_CONTROL)
	emit_signal("feedback_triggered", "КОНТРОЛЬ УГРОЗЫ: Не двигайтесь %d с" % int(_threat_hold_target), false)


## Функциональная проверка узла (VERIFY)
func run_verification() -> bool:
	if (current_phase != Phase.THREAT_CONTROL and current_phase != Phase.VERIFY) or current_threat == Threat.AWAKE or is_paused:
		return false

	_set_phase(Phase.VERIFY)

	var steps: Array = _current_part.get("steps", [])
	var total_steps: int = steps.size()
	var steps_ok: bool = (_step_success_count == total_steps and _current_step_index >= total_steps)

	var quality_avg: float = (_step_quality_sum / float(_step_success_count)) if _step_success_count > 0 else 0.0
	var quality_ok: bool = quality_avg >= 0.5
	var order_ok: bool = (_order_errors == 0)

	var total_time_limit: float = 0.0
	for s in steps:
		if s is Dictionary:
			total_time_limit += float((s as Dictionary).get("time_limit", 0.0))
	var time_ok: bool = (total_time_limit <= 0.0 or _step_time_used <= (1.25 * total_time_limit))

	var passed: bool = steps_ok and order_ok and quality_ok and time_ok

	if passed:
		var reward: float = _get_loop_float("verify.pass_reward", 10.0)
		_add_instability_internal(-reward)
		parts_done += 1
		_verified_part_ids.append(_current_part_id)

		var details: Dictionary = {
			"steps_ok": steps_ok,
			"order_errors": _order_errors,
			"quality_avg": quality_avg,
			"quality": quality_avg,
			"steps_completed": _step_success_count,
			"steps_total": total_steps,
			"time_used": _step_time_used,
			"attempts": _part_attempts + 1,
			"passed": true,
			"reason": ""
		}
		_part_attempts = 0
		_current_part = {}
		_current_part_id = ""
		_current_card = {}
		_current_card_id = ""

		verification_finished.emit(true, details)

		var remaining: int = 0
		for p in _parts:
			if p is Dictionary and not _verified_part_ids.has(str(p.get("id", ""))):
				remaining += 1

		if remaining > 0:
			_diagnostics_report.clear()
			_set_phase(Phase.DIAGNOSTICS)
		else:
			_set_phase(Phase.SHIFT_COMPLETE)
			current_state = State.DONE
			var stats: Dictionary = get_shift_stats()
			shift_finished.emit(true, stats)
			emit_signal("game_finished", true)
			emit_signal("feedback_triggered", "СМЕНА УСПЕШНО ЗАВЕРШЕНА", false)

		return true
	else:
		var penalty: float = _get_loop_float("verify.fail_penalty", 12.0)
		_add_instability_internal(penalty)
		_part_attempts += 1
		mistakes += 1

		var fail_reason_text: String = "НАРУШЕН РЕГЛАМЕНТ"
		if not steps_ok:
			fail_reason_text = "ШАГИ ВЫПОЛНЕНЫ НЕ ПОЛНОСТЬЮ"
		elif not order_ok:
			fail_reason_text = "НАРУШЕН ПОРЯДОК ОПЕРАЦИЙ"
		elif not quality_ok:
			fail_reason_text = "НИЗКОЕ КАЧЕСТВО РАБОТ"
		elif not time_ok:
			fail_reason_text = "ПРЕВЫШЕНА НОРМА ВРЕМЕНИ"

		var details: Dictionary = {
			"steps_ok": steps_ok,
			"order_errors": _order_errors,
			"quality_avg": quality_avg,
			"quality": quality_avg,
			"steps_completed": _step_success_count,
			"steps_total": total_steps,
			"time_used": _step_time_used,
			"attempts": _part_attempts,
			"passed": false,
			"reason": fail_reason_text
		}
		verification_finished.emit(false, details)

		var max_att: int = _get_loop_int("verify.max_attempts", 2)
		if _part_attempts >= max_att:
			abort_shift("Превышен лимит попыток верификации (%d)" % max_att)
			return false
		else:
			_diagnostics_report.clear()
			_set_phase(Phase.DIAGNOSTICS)
			return false


## Аварийное или внешнее прерывание смены
func abort_shift(reason: String) -> void:
	if current_phase == Phase.SHIFT_FAILED or current_phase == Phase.SHIFT_COMPLETE:
		return
	fail_reason = reason
	_set_phase(Phase.SHIFT_FAILED)
	current_state = State.FAIL
	var stats: Dictionary = get_shift_stats()
	shift_finished.emit(false, stats)
	emit_signal("game_finished", false)
	emit_signal("feedback_triggered", "СМЕНА ПРОВАЛЕНА: " + reason, true)


## Текущий шаг ремонта (пустой словарь, если шага нет)
func get_current_step() -> Dictionary:
	var steps: Array = _current_part.get("steps", [])
	if _current_step_index >= 0 and _current_step_index < steps.size():
		return steps[_current_step_index] as Dictionary
	return {}


## Остаток времени на текущий шаг в секундах (-1, если лимита нет)
func get_step_time_left() -> float:
	var limit: float = float(get_current_step().get("time_limit", 0.0))
	if limit <= 0.0:
		return -1.0
	return maxf(limit - _step_elapsed, 0.0)


func get_step_limit() -> float:
	return float(get_current_step().get("time_limit", 0.0))


## Сколько ещё держать «замри» в фазе контроля угрозы
func get_threat_hold_left() -> float:
	return maxf(_threat_hold_target - _threat_control_timer, 0.0)


func get_threat_hold_target() -> float:
	return _threat_hold_target


func get_order_errors() -> int:
	return _order_errors


## Итоговая статистика смены
func get_shift_stats() -> Dictionary:
	var wakes_count: int = robot.wake_count if robot != null else 0
	var calculated_score: int = clampi(100 - (mistakes * 8) - (wakes_count * 15), 0, 100)
	return {
		"elapsed": shift_elapsed,
		"parts_done": parts_done,
		"mistakes": mistakes,
		"wakes": wakes_count,
		"score": calculated_score,
		"fail_reason": fail_reason,
	}


## Добавление нестабильности от опасных эффектов
func add_instability(amount: float) -> void:
	if current_mode == Mode.NEW:
		_add_instability_internal(amount)
	else:
		if robot == null:
			return
		robot.add_instability(amount)
		if robot.is_critical() and not is_over():
			finish(false)
		elif robot.instability >= robot.threshold:
			wake()


# =============================================================================
# ПРИВАТНЫЕ ХЕЛПЕРЫ НОВОЙ ПЕТЛИ
# =============================================================================

func _set_phase(next_phase: Phase) -> void:
	if current_phase == next_phase:
		return
	current_phase = next_phase
	phase_changed.emit(current_phase)


func _get_loop_dict() -> Dictionary:
	if balance != null:
		var lp: Variant = balance.get_val("loop")
		if lp is Dictionary:
			return lp as Dictionary
	return {}


func _get_loop_float(key_path: String, fallback: float) -> float:
	var dict: Dictionary = _get_loop_dict()
	var parts := key_path.split(".")
	var cur: Variant = dict
	for p in parts:
		if cur is Dictionary and (cur as Dictionary).has(p):
			cur = (cur as Dictionary)[p]
		else:
			return fallback
	if cur is int or cur is float:
		return float(cur)
	return fallback


func _get_loop_int(key_path: String, fallback: int) -> int:
	var dict: Dictionary = _get_loop_dict()
	var parts := key_path.split(".")
	var cur: Variant = dict
	for p in parts:
		if cur is Dictionary and (cur as Dictionary).has(p):
			cur = (cur as Dictionary)[p]
		else:
			return fallback
	if cur is int or cur is float:
		return int(cur)
	return fallback


func _add_instability_internal(amount: float) -> void:
	if robot == null:
		return
	robot.add_instability(amount)

	if robot.is_critical():
		abort_shift("Аварийный перегрев сервосистем (нестабильность 100%)")
		return

	if current_threat != Threat.AWAKE and robot.instability >= robot.threshold:
		wake()
		return

	if current_threat != Threat.AWAKE:
		var new_threat: Threat = Threat.TWITCH if robot.instability >= (robot.threshold - 10.0) else Threat.CALM
		if new_threat != current_threat:
			current_threat = new_threat
		threat_changed.emit(current_threat, robot.instability)


# =============================================================================
# ЛЕГАСИ-МЕТОДЫ (СОХРАНЯЮТ 100% ОБРАТНУЮ СОВМЕСТИМОСТЬ С test_gameplay.gd)
# =============================================================================

func start() -> void:
	current_mode = Mode.LEGACY
	current_state = State.CALM
	current_stage_index = 0
	robot.configure(balance)
	emit_signal("state_changed", current_state)
	if stages.is_empty():
		finish(false, "Нет данных об этапах ремонта (проверьте robot.json)")
		return
	emit_signal("stage_changed", current_stage_index, get_current_stage())


func is_over() -> bool:
	if current_mode == Mode.NEW:
		return current_phase == Phase.SHIFT_COMPLETE or current_phase == Phase.SHIFT_FAILED
	return current_state == State.DONE or current_state == State.FAIL


func get_current_stage() -> RepairStage:
	if current_stage_index >= 0 and current_stage_index < stages.size():
		return stages[current_stage_index]
	return null


func get_tool_label(tool_id: String) -> String:
	return str(tool_labels.get(tool_id, tool_id))


func tick(delta: float) -> void:
	if is_over() or robot == null:
		return

	if current_mode == Mode.LEGACY:
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
		return

	# --- ТАКТ В РЕЖИМЕ NEW ---
	shift_elapsed += delta

	var shift_limit: float = _get_loop_float("shift_time_limit", 600.0)
	if shift_limit > 0.0 and shift_elapsed >= shift_limit:
		abort_shift("Время смены истекло (%d с)" % int(shift_limit))
		return

	if is_paused:
		var cool_rate: float = _get_loop_float("pause.cool_rate", 1.2)
		robot.add_instability(-cool_rate * delta)
		threat_changed.emit(current_threat, robot.instability)

		_pause_elapsed += delta
		var max_pause: float = _get_loop_float("pause.max_seconds", 25.0)
		if _pause_elapsed >= max_pause:
			request_resume()
		return

	if _pause_cooldown_left > 0.0:
		_pause_cooldown_left = maxf(_pause_cooldown_left - delta, 0.0)
	if _threat_motion_cd > 0.0:
		_threat_motion_cd = maxf(_threat_motion_cd - delta, 0.0)

	if current_threat == Threat.AWAKE:
		_grace_left = maxf(_grace_left - delta, 0.0)
		freeze_left -= delta
		if freeze_left <= 0.0:
			calm_down()
	else:
		if robot.tick(delta, true):
			wake()
			return
		var new_threat: Threat = Threat.TWITCH if robot.instability >= (robot.threshold - 10.0) else Threat.CALM
		if new_threat != current_threat:
			current_threat = new_threat
			threat_changed.emit(current_threat, robot.instability)

	# Во время пробуждения время шага и удержание стоят: игрок не может действовать.
	if current_threat != Threat.AWAKE and current_phase == Phase.REPAIR:
		_step_elapsed += delta
		var steps: Array = _current_part.get("steps", [])
		if _current_step_index >= 0 and _current_step_index < steps.size():
			var step: Dictionary = steps[_current_step_index] as Dictionary
			var t_limit: float = float(step.get("time_limit", 0.0))
			if t_limit > 0.0 and _step_elapsed >= t_limit:
				var step_inst: Dictionary = step.get("instability", {})
				var t_pen: float = float(step_inst.get("timeout", _get_loop_float("timeout_penalty", 8.0)))
				_add_instability_internal(t_pen)
				mistakes += 1
				_step_elapsed = 0.0
				step_failed.emit(_current_step_index, "timeout")
				# Перезапуск шага: игрок не должен остаться без активной операции.
				if current_phase == Phase.REPAIR and current_threat != Threat.AWAKE:
					step_requested.emit(_current_step_index, step)

	elif current_threat != Threat.AWAKE and current_phase == Phase.THREAT_CONTROL:
		_threat_control_timer += delta
		if _threat_control_timer >= _threat_hold_target:
			run_verification()

	if robot.is_critical() and not is_over():
		abort_shift("Аварийный перегрев сервосистем (нестабильность 100%)")


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
		if current_mode == Mode.NEW:
			abort_shift("Робот проснулся слишком много раз (%d из %d допустимых)" % [robot.wake_count, max_wakes_allowed])
		else:
			finish(false, "Робот проснулся слишком много раз (%d из %d допустимых)" % [robot.wake_count, max_wakes_allowed])
		return
	current_state = State.AWAKE
	freeze_left = freeze_seconds
	_grace_left = freeze_grace
	_penalty_cd = 0.0
	emit_signal("state_changed", current_state)
	emit_signal("feedback_triggered", "РОБОТ ПРОСЫПАЕТСЯ! ЗАМРИ!", true)
	if current_mode == Mode.NEW:
		current_threat = Threat.AWAKE
		wake_started.emit(freeze_seconds)
		threat_changed.emit(current_threat, robot.instability)


func on_mouse_moved(relative_length: float) -> void:
	if current_mode == Mode.NEW and current_phase == Phase.THREAT_CONTROL:
		if not is_paused and current_threat != Threat.AWAKE:
			var motion_lim: float = _get_loop_float("threat_control.motion_limit", 1.2)
			if relative_length > motion_lim:
				_threat_control_timer = 0.0
				if _threat_motion_cd <= 0.0:
					_threat_motion_cd = 0.8
					mistakes += 1
					var safe_margin_pen: float = _get_loop_float("threat_control.safe_margin", 10.0)
					# Штраф пропорционален рывку: мелкое дрожание почти не наказывает,
					# грубое движение мышью — по полной.
					var scaled_pen: float = safe_margin_pen * clampf(relative_length / 20.0, 0.15, 1.0)
					_add_instability_internal(scaled_pen)
					emit_signal("feedback_triggered", "ДВИЖЕНИЕ В THREAT CONTROL! УДЕРЖАНИЕ СБРОШЕНО", true)
				return

	if current_state != State.AWAKE or _grace_left > 0.0 or _penalty_cd > 0.0:
		return
	if relative_length > freeze_motion_limit:
		_penalty_cd = freeze_penalty_cooldown
		mistakes += 1
		robot.add_instability(freeze_penalty)
		freeze_left += 1.5
		emit_signal("feedback_triggered", "ДВИЖЕНИЕ ЗАМЕЧЕНО! +%d%% НЕСТАБИЛЬНОСТИ" % int(freeze_penalty), true)
		if robot.is_critical():
			if current_mode == Mode.NEW:
				abort_shift("Аварийный перегрев сервосистем (нестабильность 100%)")
			else:
				finish(false)


func calm_down() -> void:
	current_state = State.CALM
	robot.calm_down()
	emit_signal("state_changed", current_state)
	emit_signal("feedback_triggered", "Робот успокоился. Порог снизился до %d%%" % int(robot.threshold), false)
	if current_mode == Mode.NEW:
		current_threat = Threat.CALM
		wake_ended.emit()
		threat_changed.emit(current_threat, robot.instability)


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
