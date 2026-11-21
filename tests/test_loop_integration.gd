extends SceneTree

## Do Not Wake — Сквозной интеграционный тест полного цикла смены (этап 4)
## Обязательные сценарии по docs/qa/report.md §4 и `docs/architecture.md` §2–§4.1:
## 1. Happy path (2 детали, 2 карточки, по 2 шага scrub + hold, проверка счетчиков шпиона)
## 2. Неверная деталь (select_part wrong_id -> штраф, фаза не меняется)
## 3. Неверная карточка (read_card wrong_doc -> штраф, фаза не меняется)
## 4. Не тот инструмент (report_step_result order: wrong_tool -> order_errors > 0, повтор, провал верификации)
## 5. Таймаут шага (tick(time_limit + 0.1) -> timeout_penalty, шаг повторяется)
## 6. Пауза (охлаждение, отклонение интентов, авто-резюм, кулдаун 20с, лимит 3 раз)
## 7. Пробуждение AWAKE (wake -> wake_started, отклонение ввода, tick -> wake_ended, снижение порога)
## 8. Verify fail (ошибки -> fail, возврат в диагностику, max_attempts (2) -> SHIFT_FAILED)
## 9. Легаси-совместимость (start() + apply_repair() не ломают новые счетчики и фазы)
## 10. Детерминированность сигналов (нет дубликатов phase_changed, строгий хронологический порядок)

const GameStateScript = preload("res://scripts/core/game_state.gd")

var _failures: Array = []
var _checks: int = 0


# =============================================================================
# ШПИОН СИГНАЛОВ (SignalSpy)
# =============================================================================

class SignalSpy:
	var events: Array = []
	var counts: Dictionary = {}

	func record(sig_name: String, args: Array) -> void:
		events.append({
			"signal": sig_name,
			"args": args,
			"order": events.size()
		})
		counts[sig_name] = counts.get(sig_name, 0) + 1

	func get_count(sig_name: String) -> int:
		return counts.get(sig_name, 0)

	func get_events(sig_name: String) -> Array:
		var res: Array = []
		for ev in events:
			if ev["signal"] == sig_name:
				res.append(ev)
		return res

	func get_first_event_index(sig_name: String, filter_func = null) -> int:
		for i in range(events.size()):
			if events[i]["signal"] == sig_name:
				if filter_func == null or filter_func.call(events[i]["args"]):
					return i
		return -1

	func clear() -> void:
		events.clear()
		counts.clear()


func _connect_spy(gs: Node, spy: SignalSpy) -> void:
	gs.phase_changed.connect(func(p): spy.record("phase_changed", [p]))
	gs.diagnostics_ready.connect(func(r): spy.record("diagnostics_ready", [r]))
	gs.part_selected.connect(func(id, ok): spy.record("part_selected", [id, ok]))
	gs.documentation_requested.connect(func(): spy.record("documentation_requested", []))
	gs.document_read.connect(func(id, ok): spy.record("document_read", [id, ok]))
	gs.repair_started.connect(func(id, steps): spy.record("repair_started", [id, steps]))
	gs.step_requested.connect(func(idx, step): spy.record("step_requested", [idx, step]))
	gs.step_progress.connect(func(idx, prog): spy.record("step_progress", [idx, prog]))
	gs.step_completed.connect(func(idx): spy.record("step_completed", [idx]))
	gs.step_failed.connect(func(idx, reason): spy.record("step_failed", [idx, reason]))
	gs.threat_changed.connect(func(lvl, inst): spy.record("threat_changed", [lvl, inst]))
	gs.wake_started.connect(func(dur): spy.record("wake_started", [dur]))
	gs.wake_ended.connect(func(): spy.record("wake_ended", []))
	gs.pause_changed.connect(func(paused, reason): spy.record("pause_changed", [paused, reason]))
	gs.verification_finished.connect(func(passed, det): spy.record("verification_finished", [passed, det]))
	gs.shift_finished.connect(func(ok, stats): spy.record("shift_finished", [ok, stats]))


# =============================================================================
# ФИКСТУРЫ ТЕСТОВ (контракты данных §3.1-§3.2: 2 детали, 2 карточки, 2 шага scrub+hold)
# =============================================================================

func _create_fixture_parts() -> Array:
	return [
		{
			"id": "part_alpha",
			"tag": "A-01",
			"label": "Сервопривод плеча A-01",
			"fault_code": "E-101",
			"symptom": "Дрожание манипулятора",
			"doc_id": "doc_alpha",
			"zone": "shoulder",
			"tag_pos": [612, 236],
			"difficulty": 1,
			"steps": [
				{
					"id": "step_a1_scrub",
					"type": "scrub",
					"tool": "cloth",
					"label": "Очистить контакты",
					"time_limit": 10.0,
					"params": {
						"rect": [100, 100, 50, 50],
						"safe_speed_min": 120.0,
						"safe_speed_max": 600.0,
						"target_ratio": 0.95
					},
					"instability": { "success": -4.0, "fail": 6.0, "timeout": 8.0 }
				},
				{
					"id": "step_a2_hold",
					"type": "hold",
					"tool": "none",
					"label": "Удержать шину",
					"time_limit": 10.0,
					"params": {
						"rect": [100, 100, 50, 50],
						"duration": 2.0,
						"motion_tolerance": 1.0
					},
					"instability": { "success": -4.0, "fail": 6.0, "timeout": 8.0 }
				}
			],
			"verify": { "type": "pulse", "expected": 1.0, "tolerance": 0.1, "time_limit": 5.0 },
			"reward": 10.0,
			"penalty": 12.0
		},
		{
			"id": "part_beta",
			"tag": "B-02",
			"label": "Блок питания B-02",
			"fault_code": "E-202",
			"symptom": "Просадка напряжения",
			"doc_id": "doc_beta",
			"zone": "chest",
			"tag_pos": [640, 360],
			"difficulty": 1,
			"steps": [
				{
					"id": "step_b1_scrub",
					"type": "scrub",
					"tool": "cloth",
					"label": "Обезжирить разъем",
					"time_limit": 10.0,
					"params": {
						"rect": [200, 200, 50, 50],
						"safe_speed_min": 120.0,
						"safe_speed_max": 600.0,
						"target_ratio": 0.95
					},
					"instability": { "success": -4.0, "fail": 6.0, "timeout": 8.0 }
				},
				{
					"id": "step_b2_hold",
					"type": "hold",
					"tool": "none",
					"label": "Стабилизировать контур",
					"time_limit": 10.0,
					"params": {
						"rect": [200, 200, 50, 50],
						"duration": 2.0,
						"motion_tolerance": 1.0
					},
					"instability": { "success": -4.0, "fail": 6.0, "timeout": 8.0 }
				}
			],
			"verify": { "type": "pulse", "expected": 1.0, "tolerance": 0.1, "time_limit": 5.0 },
			"reward": 10.0,
			"penalty": 12.0
		}
	]


func _create_fixture_cards() -> Array:
	return [
		{
			"id": "doc_alpha",
			"tag": "A-01",
			"drawer": "A",
			"title": "ТО-01. Сервопривод A-01",
			"tool_list": ["cloth", "none"],
			"time_norm_sec": 30,
			"steps_text": ["Шаг 1: Очистить", "Шаг 2: Удержать"],
			"order": ["step_a1_scrub", "step_a2_hold"]
		},
		{
			"id": "doc_beta",
			"tag": "B-02",
			"drawer": "B",
			"title": "ТО-02. Блок питания B-02",
			"tool_list": ["cloth", "none"],
			"time_norm_sec": 30,
			"steps_text": ["Шаг 1: Обезжирить", "Шаг 2: Стабилизировать"],
			"order": ["step_b1_scrub", "step_b2_hold"]
		}
	]


# =============================================================================
# ТОЧКА ВХОДА СЬЮТА
# =============================================================================

func _init() -> void:
	print("=================================================================")
	print(" DO NOT WAKE · ИНТЕГРАЦИОННЫЕ ТЕСТЫ ПЕТЛИ (test_loop_integration.gd)")
	print("=================================================================")

	var happy_spy := SignalSpy.new()
	_test_01_happy_path_full_shift_loop(happy_spy)
	_test_02_negative_wrong_part()
	_test_03_negative_wrong_card()
	_test_04_negative_wrong_tool()
	_test_05_negative_step_timeout()
	_test_06_tactical_pause()
	_test_07_awakening_flow()
	_test_08_negative_verify_fail()
	_test_09_legacy_compatibility()
	_test_10_signal_determinism(happy_spy)

	print("=================================================================")
	if _failures.is_empty():
		print("ИТОГ: ВСЕ 10 СЦЕНАРИЕВ УСПЕШНО ПРОЙДЕНЫ! Проверок: %d, Ошибок: 0" % _checks)
		quit(0)
	else:
		printerr("ИТОГ: ОБНАРУЖЕНЫ ОШИБКИ ИНТЕГРАЦИИ! (%d ошибок из %d проверок)" % [_failures.size(), _checks])
		for f in _failures:
			printerr("  [FAIL] %s" % f)
		quit(1)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)


func _t(title: String) -> void:
	print("  [OK] %s" % title)


# =============================================================================
# СЦЕНАРИЙ 1: HAPPY PATH (ПОЛНЫЙ СКВОЗНОЙ ЦИКЛ 2 ДЕТАЛЕЙ)
# =============================================================================

func _test_01_happy_path_full_shift_loop(spy: SignalSpy) -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	_connect_spy(state, spy)

	state.setup_loop(_create_fixture_parts(), _create_fixture_cards())
	state.start_shift()

	_check(state.current_mode == GameStateScript.Mode.NEW, "start_shift переводит режим в Mode.NEW")
	_check(state.current_phase == GameStateScript.Phase.DIAGNOSTICS, "start_shift переводит в Phase.DIAGNOSTICS")

	# --- ДЕТАЛЬ 1: part_alpha ---
	var rep1: Dictionary = state.run_diagnostics()
	_check(state.current_phase == GameStateScript.Phase.PART_SELECT, "run_diagnostics переводит в Phase.PART_SELECT")
	_check(rep1.get("count", 0) == 2, "в первом отчете диагностики 2 неисправных детали")
	_check(spy.get_count("diagnostics_ready") == 1, "сигнал diagnostics_ready эмитнут")

	var sel_ok1: bool = state.select_part("part_alpha")
	_check(sel_ok1, "select_part('part_alpha') успешен")
	_check(state.current_phase == GameStateScript.Phase.DOC_SEARCH, "выбор детали переводит в Phase.DOC_SEARCH")
	_check(spy.get_count("part_selected") == 1, "сигнал part_selected эмитнут")
	_check(spy.get_events("part_selected")[0]["args"][1] == true, "part_selected(part_alpha, true)")

	state.request_documentation()
	_check(spy.get_count("documentation_requested") == 1, "сигнал documentation_requested эмитнут")

	var doc_index: Dictionary = state.get_documentation_index()
	_check(doc_index.has("drawers") and doc_index.has("cards"), "индекс картотеки содержит drawers и cards")

	var card1: Dictionary = state.read_card("doc_alpha")
	_check(not card1.is_empty(), "read_card('doc_alpha') возвращает формуляр")
	_check(spy.get_count("document_read") == 1, "сигнал document_read эмитнут")
	_check(spy.get_events("document_read")[0]["args"][1] == true, "document_read(doc_alpha, true)")

	var rep_start_ok1: bool = state.begin_repair()
	_check(rep_start_ok1, "begin_repair успешен")
	_check(state.current_phase == GameStateScript.Phase.REPAIR, "фаза перешла в REPAIR")
	_check(spy.get_count("repair_started") == 1, "repair_started эмитнут ровно 1 раз для детали 1")
	_check(spy.get_count("step_requested") == 1, "step_requested(0) эмитнут для первого шага")

	# Шаг 0 (scrub)
	state.report_step_result(0, true, 1.0)
	_check(spy.get_count("step_completed") == 1, "step_completed(0) эмитнут")
	_check(spy.get_count("step_requested") == 2, "step_requested(1) эмитнут для второго шага")

	# Шаг 1 (hold)
	state.report_step_result(1, true, 1.0)
	_check(spy.get_count("step_completed") == 2, "step_completed(1) эмитнут")
	_check(state.current_phase == GameStateScript.Phase.THREAT_CONTROL, "все шаги выполнены -> авто-переход в THREAT_CONTROL")

	state.begin_threat_control()
	_check(state.current_phase == GameStateScript.Phase.THREAT_CONTROL, "фаза THREAT_CONTROL подтверждена")

	# Удержание 3.0 с -> tick(3.1) запускает верификацию детали 1
	state.tick(3.1)
	_check(state.parts_done == 1, "деталь 1 верифицирована (parts_done == 1)")
	_check(state.current_phase == GameStateScript.Phase.DIAGNOSTICS, "есть еще детали -> возврат в DIAGNOSTICS")
	_check(spy.get_count("verification_finished") == 1, "verification_finished эмитнут ровно 1 раз для детали 1")
	_check(spy.get_events("verification_finished")[0]["args"][0] == true, "верификация детали 1 прошла успешно (passed == true)")

	# --- ДЕТАЛЬ 2: part_beta ---
	var rep2: Dictionary = state.run_diagnostics()
	_check(state.current_phase == GameStateScript.Phase.PART_SELECT, "диагностика детали 2 переводит в PART_SELECT")
	_check(rep2.get("count", 0) == 1, "во втором отчете осталась 1 деталь")
	_check(rep2["parts"][0]["id"] == "part_beta", "оставшаяся деталь — part_beta")

	var sel_ok2: bool = state.select_part("part_beta")
	_check(sel_ok2, "select_part('part_beta') успешен")
	_check(state.current_phase == GameStateScript.Phase.DOC_SEARCH, "переход в DOC_SEARCH для детали 2")

	state.request_documentation()
	var card2: Dictionary = state.read_card("doc_beta")
	_check(not card2.is_empty(), "read_card('doc_beta') возвращает карточку")

	var rep_start_ok2: bool = state.begin_repair()
	_check(rep_start_ok2, "begin_repair детали 2 успешен")
	_check(state.current_phase == GameStateScript.Phase.REPAIR, "переход в REPAIR детали 2")
	_check(spy.get_count("repair_started") == 2, "repair_started эмитнут ровно 2 раза за смену (по 1 на деталь)")
	_check(spy.get_count("step_requested") == 3, "step_requested(0) для детали 2")

	state.report_step_result(0, true, 1.0)
	_check(spy.get_count("step_requested") == 4, "step_requested(1) для детали 2")

	state.report_step_result(1, true, 1.0)
	_check(state.current_phase == GameStateScript.Phase.THREAT_CONTROL, "деталь 2 перешла в THREAT_CONTROL")

	state.begin_threat_control()
	state.tick(3.1)

	# Финал смены
	_check(state.parts_done == 2, "обе детали обслужены (parts_done == 2)")
	_check(state.current_phase == GameStateScript.Phase.SHIFT_COMPLETE, "смена успешно закрыта в Phase.SHIFT_COMPLETE")
	_check(state.is_over(), "is_over() == true")
	_check(spy.get_count("verification_finished") == 2, "verification_finished эмитнут ровно 2 раза (по 1 на деталь)")
	_check(spy.get_events("verification_finished")[1]["args"][0] == true, "верификация детали 2 прошла успешно")
	_check(spy.get_count("shift_finished") == 1, "сигнал shift_finished эмитнут ровно 1 раз")
	_check(spy.get_events("shift_finished")[0]["args"][0] == true, "shift_finished(true) сигнализирует об успехе")

	# Проверка строгости счётчиков сигналов по §4 (без дубликатов)
	_check(spy.get_count("repair_started") == 2, "счётчик: ровно 1 repair_started на деталь (всего 2)")
	_check(spy.get_count("step_requested") == 4, "счётчик: ровно 2 step_requested на деталь (всего 4)")
	_check(spy.get_count("verification_finished") == 2, "счётчик: ровно 1 verification_finished на деталь (всего 2)")

	state.free()
	_t("Сценарий 1 (Happy path): сквозной проход 2 деталей, удержание, верификация и финал shift_finished(true)")


# =============================================================================
# СЦЕНАРИЙ 2: НЕВЕРНАЯ ДЕТАЛЬ
# =============================================================================

func _test_02_negative_wrong_part() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	var spy := SignalSpy.new()
	_connect_spy(state, spy)

	state.setup_loop(_create_fixture_parts(), _create_fixture_cards())
	state.start_shift()
	state.run_diagnostics()

	_check(state.current_phase == GameStateScript.Phase.PART_SELECT, "исходная фаза PART_SELECT")
	var inst_before: float = state.robot.instability
	var mistakes_before: int = state.mistakes

	# Попытка выбора несуществующей детали
	var sel_res: bool = state.select_part("wrong_id")
	_check(not sel_res, "select_part('wrong_id') возвращает false")
	_check(state.current_phase == GameStateScript.Phase.PART_SELECT, "фаза не изменилась и осталась PART_SELECT")
	_check(state.robot.instability >= inst_before + 5.0, "нестабильность выросла на wrong_part_penalty (+5%)")
	_check(state.mistakes == mistakes_before + 1, "счётчик ошибок mistakes увеличен на 1")

	var part_events: Array = spy.get_events("part_selected")
	_check(part_events.size() == 1, "сигнал part_selected эмитнут")
	_check(part_events[0]["args"][0] == "wrong_id" and part_events[0]["args"][1] == false, "part_selected('wrong_id', false) зафиксирован")

	state.free()
	_t("Сценарий 2 (Неверная деталь): штраф wrong_part_penalty, фаза не меняется, сигнал part_selected(id, false)")


# =============================================================================
# СЦЕНАРИЙ 3: НЕВЕРНАЯ КАРТОЧКА
# =============================================================================

func _test_03_negative_wrong_card() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	var spy := SignalSpy.new()
	_connect_spy(state, spy)

	state.setup_loop(_create_fixture_parts(), _create_fixture_cards())
	state.start_shift()
	state.run_diagnostics()
	state.select_part("part_alpha")

	_check(state.current_phase == GameStateScript.Phase.DOC_SEARCH, "фаза DOC_SEARCH после выбора детали")
	var inst_before: float = state.robot.instability
	var mistakes_before: int = state.mistakes

	# Попытка чтения неверной карточки (не от этой детали)
	var card_res: Dictionary = state.read_card("wrong_doc")
	_check(card_res.is_empty(), "read_card('wrong_doc') возвращает пустой словарь")
	_check(state.current_phase == GameStateScript.Phase.DOC_SEARCH, "фаза осталась DOC_SEARCH")
	_check(state.robot.instability >= inst_before + 4.0, "нестабильность выросла на wrong_doc_penalty (+4%)")
	_check(state.mistakes == mistakes_before + 1, "счётчик mistakes увеличен")

	var doc_events: Array = spy.get_events("document_read")
	_check(doc_events.size() == 1, "сигнал document_read эмитнут")
	_check(doc_events[0]["args"][0] == "wrong_doc" and doc_events[0]["args"][1] == false, "document_read('wrong_doc', false) зафиксирован")

	state.free()
	_t("Сценарий 3 (Неверная карточка): штраф wrong_doc_penalty, фаза DOC_SEARCH, сигнал document_read(id, false)")


# =============================================================================
# СЦЕНАРИЙ 4: НЕ ТОТ ИНСТРУМЕНТ (ORDER ERROR)
# =============================================================================

func _test_04_negative_wrong_tool() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	var spy := SignalSpy.new()
	_connect_spy(state, spy)

	state.setup_loop(_create_fixture_parts(), _create_fixture_cards())
	state.start_shift()
	state.run_diagnostics()
	state.select_part("part_alpha")
	state.read_card("doc_alpha")
	state.begin_repair()

	_check(state.current_phase == GameStateScript.Phase.REPAIR, "фаза REPAIR активна")
	_check(state._current_step_index == 0, "текущий шаг 0")

	var inst_before: float = state.robot.instability
	var ord_errors_before: int = state._order_errors

	# Применение не того инструмента (ошибка последовательности)
	state.report_step_result(0, false, 0.0, "order: wrong_tool")

	_check(state._order_errors > ord_errors_before, "счётчик order_errors инкрементирован")
	_check(state._current_step_index == 0, "индекс шага не сдвинулся (шаг повторяется)")
	_check(state.robot.instability >= inst_before + 16.0, "начислен двойной штраф: срыв шага (6%) + order_penalty (10%)")

	var fail_events: Array = spy.get_events("step_failed")
	_check(fail_events.size() == 1, "step_failed эмитнут")
	_check(fail_events[0]["args"][0] == 0 and fail_events[0]["args"][1] == "order: wrong_tool", "step_failed(0, order: wrong_tool) подтвержден")

	# Завершаем шаги и проверяем, что ошибка порядка приводит к провалу верификации
	state.report_step_result(0, true, 1.0)
	state.report_step_result(1, true, 1.0)
	_check(state.current_phase == GameStateScript.Phase.THREAT_CONTROL, "переход в THREAT_CONTROL")

	var verify_res: bool = state.run_verification()
	_check(not verify_res, "верификация провалена из-за ранее допущенной ошибки порядка (order_errors > 0)")

	state.free()
	_t("Сценарий 4 (Не тот инструмент): order_errors > 0, повтор шага, штраф order_penalty и провал верификации")


# =============================================================================
# СЦЕНАРИЙ 5: ТАЙМАУТ ШАГА
# =============================================================================

func _test_05_negative_step_timeout() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	var spy := SignalSpy.new()
	_connect_spy(state, spy)

	state.setup_loop(_create_fixture_parts(), _create_fixture_cards())
	state.start_shift()
	state.run_diagnostics()
	state.select_part("part_alpha")
	state.read_card("doc_alpha")
	state.begin_repair()

	_check(state._current_step_index == 0, "шаг 0")
	var inst_before: float = state.robot.instability
	var mistakes_before: int = state.mistakes

	# Превышение лимита времени шага (time_limit = 10.0) через tick(10.1)
	state.tick(10.1)

	_check(state._current_step_index == 0, "шаг повторяется (индекс остался 0)")
	_check(state.robot.instability >= inst_before + 8.0, "начислен штраф timeout_penalty (+8%)")
	_check(state.mistakes == mistakes_before + 1, "mistakes инкрементирован")

	var fail_events: Array = spy.get_events("step_failed")
	_check(fail_events.size() == 1, "сигнал step_failed эмитнут")
	_check(fail_events[0]["args"][0] == 0 and fail_events[0]["args"][1] == "timeout", "step_failed(0, 'timeout') подтвержден")

	# После таймаута шаг можно успешно выполнить
	state.report_step_result(0, true, 1.0)
	_check(state._current_step_index == 1, "после успешного повтора перешли к шагу 1")

	state.free()
	_t("Сценарий 5 (Таймаут шага): tick(time_limit + 0.1) начисляет timeout_penalty, шаг повторяется")


# =============================================================================
# СЦЕНАРИЙ 6: ТАКТИЧЕСКАЯ ПАУЗА
# =============================================================================

func _test_06_tactical_pause() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	var spy := SignalSpy.new()
	_connect_spy(state, spy)

	state.setup_loop(_create_fixture_parts(), _create_fixture_cards())
	state.start_shift()
	state.run_diagnostics()
	state.select_part("part_alpha")
	state.read_card("doc_alpha")
	state.begin_repair()

	# Начальная нестабильность 15% (достаточно для проверки охлаждения, но без перегрева от таймаутов)
	state.robot.instability = 15.0

	# 1. Запрос паузы
	state.request_pause("cooldown_test")
	_check(state.is_paused, "пауза успешно включена")
	_check(spy.get_count("pause_changed") == 1, "сигнал pause_changed(true) эмитнут")

	# 2. Охлаждение со скоростью cool_rate (1.2%/с)
	var inst_before_tick: float = state.robot.instability
	state.tick(2.0)
	var inst_diff: float = inst_before_tick - state.robot.instability
	_check(is_equal_approx(inst_diff, 2.4), "нестабильность падает со скоростью cool_rate (1.2%/с * 2с = 2.4%)")

	# 3. Интенты отклоняются во время паузы
	_check(not state.select_part("part_alpha"), "select_part отклонен во время паузы")
	_check(not state.begin_repair(), "begin_repair отклонен во время паузы")
	_check(state.read_card("doc_alpha").is_empty(), "read_card отклонен во время паузы")
	var idx_before: int = state._current_step_index
	state.report_step_result(0, true, 1.0)
	_check(state._current_step_index == idx_before, "report_step_result проигнорирован во время паузы")

	# 4. Возобновление работы (request_resume)
	state.request_resume()
	_check(not state.is_paused, "request_resume успешно возобновил работу")
	_check(spy.get_count("pause_changed") == 2, "pause_changed(false) эмитнут")

	# 5. Кулдаун 20 с: повторный запрос паузы сразу отклоняется
	state.request_pause("spam_pause")
	_check(not state.is_paused, "повторный запрос паузы во время кулдауна 20 с отклонен")

	state.tick(20.1) # кулдаун истек

	# 6. Проверка лимита 3 использований на смену
	state.request_pause("use_2")
	_check(state.is_paused, "пауза 2 принята")
	state.request_resume()
	state.tick(20.1)

	state.request_pause("use_3")
	_check(state.is_paused, "пауза 3 принята")
	state.request_resume()
	state.tick(20.1)

	state.request_pause("use_4")
	_check(not state.is_paused, "4-я пауза отклонена (достигнут лимит 3 использований на смену)")

	state.free()
	_t("Сценарий 6 (Пауза): охлаждение cool_rate, блокировка интентов, резюм, кулдаун 20с и лимит 3 использований")


# =============================================================================
# СЦЕНАРИЙ 7: ПРОБУЖДЕНИЕ (AWAKE)
# =============================================================================

func _test_07_awakening_flow() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	var spy := SignalSpy.new()
	_connect_spy(state, spy)

	state.setup_loop(_create_fixture_parts(), _create_fixture_cards())
	state.start_shift()
	state.run_diagnostics()

	_check(state.current_phase == GameStateScript.Phase.PART_SELECT, "фаза PART_SELECT")
	var thresh_before: float = state.robot.threshold

	# Принудительное пробуждение
	state.wake()
	_check(state.current_threat == GameStateScript.Threat.AWAKE, "угроза перешла в Threat.AWAKE")

	var wake_start_events: Array = spy.get_events("wake_started")
	_check(wake_start_events.size() == 1, "wake_started эмитнут")
	_check(wake_start_events[0]["args"][0] == state.freeze_seconds, "wake_started передал длительность freeze_seconds")

	# Ввод отклоняется
	_check(not state.select_part("part_alpha"), "select_part возвращает false во время AWAKE")
	_check(state.run_diagnostics().is_empty(), "run_diagnostics возвращает {} во время AWAKE")
	_check(not state.begin_repair(), "begin_repair возвращает false во время AWAKE")
	_check(not state.run_verification(), "run_verification возвращает false во время AWAKE")

	# Истечение freeze_seconds
	state.tick(state.freeze_seconds + 0.1)

	_check(state.current_threat == GameStateScript.Threat.CALM, "угроза вернулась в Threat.CALM")
	_check(spy.get_count("wake_ended") == 1, "wake_ended эмитнут")
	_check(state.robot.threshold < thresh_before, "порог пробуждения робота снижен")
	_check(state.current_phase == GameStateScript.Phase.PART_SELECT, "сохранился возврат к активной фазе PART_SELECT")

	# После пробуждения ввод снова активен
	var sel_ok: bool = state.select_part("part_alpha")
	_check(sel_ok, "после wake_ended ввод select_part снова работает")

	state.free()
	_t("Сценарий 7 (Пробуждение): wake_started, отклонение ввода, tick завершает freeze, wake_ended и снижение порога")


# =============================================================================
# СЦЕНАРИЙ 8: VERIFY FAIL И ЛИМИТ ПОПЫТОК
# =============================================================================

func _test_08_negative_verify_fail() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	var spy := SignalSpy.new()
	_connect_spy(state, spy)

	state.setup_loop(_create_fixture_parts(), _create_fixture_cards())
	state.start_shift()

	# --- ПОПЫТКА 1 ---
	state.run_diagnostics()
	state.select_part("part_alpha")
	state.read_card("doc_alpha")
	state.begin_repair()

	# Шаги с низким качеством (0.2) и ошибкой порядка
	state.report_step_result(0, false, 0.0, "order:wrong_tool")
	state.report_step_result(0, true, 0.2)
	state.report_step_result(1, true, 0.2)

	var pass1: bool = state.run_verification()
	_check(not pass1, "попытка верификации 1 провалена")
	_check(state._part_attempts == 1, "учтена попытка 1 (_part_attempts == 1)")
	_check(state.current_phase == GameStateScript.Phase.DIAGNOSTICS, "после провала деталь возвращается в фазу DIAGNOSTICS")

	var ver_events: Array = spy.get_events("verification_finished")
	_check(ver_events.size() == 1, "verification_finished эмитнут")
	_check(ver_events[0]["args"][0] == false, "verification_finished(false, details) подтвержден")

	# --- ПОПЫТКА 2 (ПЕРЕДЕЛКА) ---
	state.run_diagnostics()
	state.select_part("part_alpha")
	state.read_card("doc_alpha")
	state.begin_repair()

	state.report_step_result(0, false, 0.0, "order:wrong_tool")
	state.report_step_result(0, true, 0.1)
	state.report_step_result(1, true, 0.1)

	var pass2: bool = state.run_verification()
	_check(not pass2, "попытка верификации 2 провалена")
	_check(state.current_phase == GameStateScript.Phase.SHIFT_FAILED, "исчерпание max_attempts (2) переводит в Phase.SHIFT_FAILED")
	_check(state.is_over(), "смена завершена с провалом (is_over == true)")
	_check(state.fail_reason != "", "fail_reason заполнен причиной аварии")
	_check(state.fail_reason.contains("попыток"), "fail_reason указывает на превышение лимита попыток верификации")

	var shift_events: Array = spy.get_events("shift_finished")
	_check(shift_events.size() == 1, "shift_finished эмитнут")
	_check(shift_events[0]["args"][0] == false, "shift_finished(false, stats) подтвержден")

	state.free()
	_t("Сценарий 8 (Verify fail): провал верификации, возврат в диагностику, при max_attempts (2) -> SHIFT_FAILED")


# =============================================================================
# СЦЕНАРИЙ 9: ЛЕГАСИ-СОВМЕСТИМОСТЬ
# =============================================================================

func _test_09_legacy_compatibility() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	state.start()

	_check(state.current_mode == GameStateScript.Mode.LEGACY, "start() переводит в Mode.LEGACY")
	_check(state.current_state == GameStateScript.State.CALM, "легаси-состояние CALM")
	_check(state.current_stage_index == 0, "начальный легаси-этап 0")
	_check(state.stages.size() >= 3, "в легаси-режиме загружены 3 этапа ремонта")

	# Новые счетчики и фазы не должны портиться
	_check(state.parts_done == 0, "новые счетчики parts_done == 0")
	_check(state.current_phase == GameStateScript.Phase.BRIEFING, "current_phase остается BRIEFING")
	_check(state._verified_part_ids.is_empty(), "_verified_part_ids пуст")

	# Проходим все легаси-этапы старыми вызовами apply_repair
	state.apply_repair(0, "cloth")
	_check(state.current_stage_index == 1, "этап 1 завершен")

	state.apply_repair(0, "screwdriver")
	state.apply_repair(1, "screwdriver")
	state.apply_repair(2, "screwdriver")
	state.apply_repair(3, "screwdriver")
	_check(state.current_stage_index == 2, "этап 2 завершен")

	state.apply_repair(0, "cable")
	_check(state.current_state == GameStateScript.State.DONE, "легаси-заказ выполнен (State.DONE)")
	_check(state.is_over(), "легаси is_over() == true")

	# Новые структуры не повреждены после выполнения заказа
	_check(state.parts_done == 0, "parts_done не испорчен")
	_check(state.current_phase == GameStateScript.Phase.BRIEFING, "current_phase не поврежден")

	state.free()
	_t("Сценарий 9 (Легаси-совместимость): start() + apply_repair() проходят этапы, не падают и не портят счетчики петли")


# =============================================================================
# СЦЕНАРИЙ 10: ДЕТЕРМИНИРОВАННОСТЬ И ХРОНОЛОГИЯ СИГНАЛОВ
# =============================================================================

func _test_10_signal_determinism(spy: SignalSpy) -> void:
	# 1. Проверка отсутствия дубликатов phase_changed на один переход
	var phase_events: Array = spy.get_events("phase_changed")
	_check(phase_events.size() >= 8, "зафиксировано достаточное количество смен фаз (>= 8)")

	for i in range(phase_events.size() - 1):
		var p_cur: int = phase_events[i]["args"][0]
		var p_next: int = phase_events[i + 1]["args"][0]
		_check(p_cur != p_next, "нет последовательного дубликата phase_changed(%d -> %d)" % [p_cur, p_next])

	# 2. Проверка строгого хронологического порядка ключевых событий полного цикла
	var idx_diag_phase: int = spy.get_first_event_index("phase_changed", func(a): return a[0] == GameStateScript.Phase.DIAGNOSTICS)
	var idx_diag_ready: int = spy.get_first_event_index("diagnostics_ready")
	var idx_part_phase: int = spy.get_first_event_index("phase_changed", func(a): return a[0] == GameStateScript.Phase.PART_SELECT)
	var idx_doc_search_phase: int = spy.get_first_event_index("phase_changed", func(a): return a[0] == GameStateScript.Phase.DOC_SEARCH)
	var idx_part_selected: int = spy.get_first_event_index("part_selected")
	var idx_doc_requested: int = spy.get_first_event_index("documentation_requested")
	var idx_doc_read: int = spy.get_first_event_index("document_read")
	var idx_repair_phase: int = spy.get_first_event_index("phase_changed", func(a): return a[0] == GameStateScript.Phase.REPAIR)
	var idx_repair_started: int = spy.get_first_event_index("repair_started")
	var idx_step0_req: int = spy.get_first_event_index("step_requested", func(a): return a[0] == 0)
	var idx_step0_done: int = spy.get_first_event_index("step_completed", func(a): return a[0] == 0)
	var idx_step1_req: int = spy.get_first_event_index("step_requested", func(a): return a[0] == 1)
	var idx_step1_done: int = spy.get_first_event_index("step_completed", func(a): return a[0] == 1)
	var idx_threat_phase: int = spy.get_first_event_index("phase_changed", func(a): return a[0] == GameStateScript.Phase.THREAT_CONTROL)
	var idx_verify_phase: int = spy.get_first_event_index("phase_changed", func(a): return a[0] == GameStateScript.Phase.VERIFY)
	var idx_verify_done: int = spy.get_first_event_index("verification_finished")
	var idx_shift_complete_phase: int = spy.get_first_event_index("phase_changed", func(a): return a[0] == GameStateScript.Phase.SHIFT_COMPLETE)
	var idx_shift_finished: int = spy.get_first_event_index("shift_finished")

	_check(idx_diag_phase >= 0 and idx_diag_phase < idx_part_phase, "хронология: DIAGNOSTICS -> PART_SELECT")
	_check(idx_part_phase <= idx_diag_ready, "хронология: PART_SELECT перед diagnostics_ready")
	_check(idx_diag_ready < idx_doc_search_phase, "хронология: diagnostics_ready перед выбором детали")
	_check(idx_doc_search_phase <= idx_part_selected, "хронология: DOC_SEARCH перед part_selected")
	_check(idx_part_selected < idx_doc_requested, "хронология: part_selected перед request_documentation")
	_check(idx_doc_requested < idx_doc_read, "хронология: request_documentation перед read_card")
	_check(idx_doc_read < idx_repair_phase, "хронология: read_card перед REPAIR")
	_check(idx_repair_phase <= idx_repair_started, "хронология: REPAIR перед repair_started")
	_check(idx_repair_started <= idx_step0_req, "хронология: repair_started перед первым step_requested")
	_check(idx_step0_req < idx_step0_done, "хронология: step_requested(0) перед step_completed(0)")
	_check(idx_step0_done < idx_step1_req, "хронология: step_completed(0) перед step_requested(1)")
	_check(idx_step1_req < idx_step1_done, "хронология: step_requested(1) перед step_completed(1)")
	_check(idx_step1_done <= idx_threat_phase, "хронология: step_completed(1) перед THREAT_CONTROL")
	_check(idx_threat_phase < idx_verify_phase, "хронология: THREAT_CONTROL перед VERIFY")
	_check(idx_verify_phase <= idx_verify_done, "хронология: VERIFY перед verification_finished")
	_check(idx_verify_done < idx_shift_complete_phase, "хронология: верификация перед SHIFT_COMPLETE")
	_check(idx_shift_complete_phase <= idx_shift_finished, "хронология: SHIFT_COMPLETE перед shift_finished")

	_t("Сценарий 10 (Детерминированность сигналов): отсутствие дублей phase_changed и строго правильный хронологический порядок")
