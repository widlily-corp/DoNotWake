extends SceneTree

## Тестовый сьют новой 6-фазной петли смены (Do Not Wake этап 2 / ядро)
## Проверяет Phase FSM, LoopData, тактильную паузу, угрозу/пробуждение, верификацию и легаси-режим.

const GameStateScript = preload("res://scripts/core/game_state.gd")
const LoopDataScript = preload("res://scripts/core/loop_data.gd")

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("--- ЗАПУСК АВТОТЕСТОВ СЕССИИ И ПЕТЛИ (test_session.gd) ---")
	_test_loop_data_loading_and_safety()
	_test_start_shift_and_reset()
	_test_deterministic_setup_loop_and_diagnostics()
	_test_select_part_and_documentation()
	_test_repair_flow_and_steps()
	_test_pause_system_and_limits()
	_test_threat_awake_flow_and_motion()
	_test_threat_control_and_verify_pass_complete_shift()
	_test_verify_fail_retry_and_max_attempts()
	_test_critical_instability_and_shift_timeout()
	_test_legacy_flow_untouched()

	if _failures.is_empty():
		print("--- ВСЕ АВТОТЕСТЫ СЕССИИ ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ОБНАРУЖЕНЫ ОШИБКИ ТЕСТИРОВАНИЯ СЕССИИ (%d ошибок из %d проверок) ---" % [_failures.size(), _checks])
		for f in _failures:
			printerr("  [FAIL] %s" % f)
		quit(1)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)


func _t(title: String) -> void:
	print("  · %s" % title)


func _create_test_parts() -> Array:
	return [
		{
			"id": "test_part_1",
			"tag": "A-01",
			"label": "Тестовая деталь 1",
			"fault_code": "E-101",
			"symptom": "Люфт в суставе",
			"doc_id": "doc_test_1",
			"steps": [
				{
					"id": "step_1_clean",
					"type": "scrub",
					"tool": "cloth",
					"time_limit": 10.0,
					"instability": { "success": -4.0, "fail": 6.0, "timeout": 8.0 }
				},
				{
					"id": "step_1_lock",
					"type": "cable_lock",
					"tool": "cable",
					"time_limit": 10.0,
					"instability": { "success": -4.0, "fail": 6.0, "timeout": 8.0 }
				}
			],
			"verify": { "type": "pulse", "expected": 1.0, "tolerance": 0.1, "time_limit": 5.0 },
			"reward": 10.0,
			"penalty": 12.0
		},
		{
			"id": "test_part_2",
			"tag": "B-02",
			"label": "Тестовая деталь 2",
			"fault_code": "E-202",
			"symptom": "Перегрев шины",
			"doc_id": "doc_test_2",
			"steps": [
				{
					"id": "step_2_hold",
					"type": "hold",
					"tool": "none",
					"time_limit": 10.0,
					"instability": { "success": -5.0, "fail": 5.0, "timeout": 8.0 }
				}
			],
			"verify": { "type": "pulse", "expected": 0.8, "tolerance": 0.1, "time_limit": 5.0 },
			"reward": 8.0,
			"penalty": 10.0
		}
	]


func _create_test_cards() -> Array:
	return [
		{
			"id": "doc_test_1",
			"tag": "A-01",
			"drawer": "A",
			"title": "ТО-01. Тестовая деталь 1",
			"tool_list": ["cloth", "cable"],
			"time_norm_sec": 30,
			"steps_text": ["Шаг 1", "Шаг 2"],
			"order": ["step_1_clean", "step_1_lock"]
		},
		{
			"id": "doc_test_2",
			"tag": "B-02",
			"drawer": "B",
			"title": "ТО-02. Тестовая деталь 2",
			"tool_list": ["none"],
			"time_norm_sec": 20,
			"steps_text": ["Шаг 1"],
			"order": ["step_2_hold"]
		}
	]


func _test_loop_data_loading_and_safety() -> void:
	# Проверка чтения боевых файлов
	var parts: Array = LoopDataScript.load_parts()
	_check(not parts.is_empty(), "LoopData: load_parts читает data/parts.json")

	var docs: Dictionary = LoopDataScript.load_documents()
	_check(docs.has("cards") and docs.has("drawers"), "LoopData: load_documents читает data/documents.json")

	# Защита от несуществующих файлов и мусора
	var invalid_parts: Array = LoopDataScript.load_parts("res://non_existent_file.json")
	_check(invalid_parts.is_empty(), "LoopData: несуществующий parts файл возвращает []")

	var invalid_docs: Dictionary = LoopDataScript.load_documents("res://non_existent_file.json")
	_check(invalid_docs.is_empty(), "LoopData: несуществующий documents файл возвращает {}")
	_t("LoopData: загрузка данных и безопасность при ошибках")


func _test_start_shift_and_reset() -> void:
	var state := GameStateScript.new()
	state.initialize_game()

	# Имитируем грязное состояние
	state.mistakes = 8
	state.parts_done = 2
	state.shift_elapsed = 120.0
	state.fail_reason = "предыдущая авария"

	var phase_log: Array = []
	state.phase_changed.connect(func(p): phase_log.append(p))

	state.start_shift()

	_check(state.current_mode == GameStateScript.Mode.NEW, "start_shift переключает режим в NEW")
	_check(state.current_phase == GameStateScript.Phase.DIAGNOSTICS, "start_shift переводит в Phase.DIAGNOSTICS")
	_check(phase_log.has(GameStateScript.Phase.DIAGNOSTICS), "start_shift эмитит phase_changed(DIAGNOSTICS)")
	_check(state.mistakes == 0, "start_shift сбрасывает mistakes")
	_check(state.parts_done == 0, "start_shift сбрасывает parts_done")
	_check(state.shift_elapsed == 0.0, "start_shift сбрасывает shift_elapsed")
	_check(state.fail_reason == "", "start_shift сбрасывает fail_reason")
	_check(state.current_threat == GameStateScript.Threat.CALM, "робот стартует в Threat.CALM")

	state.free()
	_t("start_shift: переход в DIAGNOSTICS, эмиссия phase_changed и сброс статистики")


func _test_deterministic_setup_loop_and_diagnostics() -> void:
	var state := GameStateScript.new()
	state.initialize_game()

	state.setup_loop(_create_test_parts(), _create_test_cards())
	state.start_shift()

	var diagnostics_event: Array = []
	state.diagnostics_ready.connect(func(r): diagnostics_event.append(r))

	var report: Dictionary = state.run_diagnostics()

	_check(state.current_phase == GameStateScript.Phase.PART_SELECT, "run_diagnostics переводит в Phase.PART_SELECT")
	_check(report.get("count", 0) == 2, "отчет диагностики содержит count == 2")
	_check(report.get("parts", []).size() == 2, "в отчете 2 детали")
	_check(diagnostics_event.size() == 1 and diagnostics_event[0] == report, "diagnostics_ready сигнал эмитит полный отчет")
	_check(state.get_diagnostics_report() == report, "get_diagnostics_report возвращает сохраненный отчет")

	state.free()
	_t("setup_loop и run_diagnostics: детерминированный отчет и переход в PART_SELECT")


func _test_select_part_and_documentation() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_create_test_parts(), _create_test_cards())
	state.start_shift()
	state.run_diagnostics()

	var part_sel_log: Array = []
	state.part_selected.connect(func(id, ok): part_sel_log.append({"id": id, "ok": ok}))

	# 1. Неверная деталь -> штраф, фаза не меняется
	var inst_before: float = state.robot.instability
	var wrong_sel: bool = state.select_part("non_existent_part")
	_check(not wrong_sel, "select_part неверный ID возвращает false")
	_check(state.current_phase == GameStateScript.Phase.PART_SELECT, "при ошибке выбора фаза остается PART_SELECT")
	_check(state.robot.instability > inst_before, "неверная деталь увеличивает нестабильность (штраф)")
	_check(part_sel_log.back()["ok"] == false, "part_selected(id, false) эмитнут")

	# 2. Верная деталь -> DOC_SEARCH
	var ok_sel: bool = state.select_part("test_part_1")
	_check(ok_sel, "select_part верный ID возвращает true")
	_check(state.current_phase == GameStateScript.Phase.DOC_SEARCH, "выбор детали переводит в DOC_SEARCH")
	_check(part_sel_log.back()["ok"] == true, "part_selected(id, true) эмитнут")

	# 3. Картотека: request_documentation и индекс без steps_text
	var doc_requested_called := [false]
	state.documentation_requested.connect(func(): doc_requested_called[0] = true)
	state.request_documentation()
	_check(doc_requested_called[0], "request_documentation эмитит documentation_requested")

	var doc_index: Dictionary = state.get_documentation_index()
	_check(doc_index.has("drawers") and doc_index.has("cards"), "индекс содержит drawers и cards")
	var short_cards: Array = doc_index.get("cards", [])
	_check(not short_cards.is_empty(), "карточки присутствуют в индексе")
	_check(not (short_cards[0] as Dictionary).has("steps_text"), "краткая карточка не содержит steps_text")

	# 4. Неверная карточка -> штраф, фаза не меняется
	var doc_read_log: Array = []
	state.document_read.connect(func(id, ok): doc_read_log.append({"id": id, "ok": ok}))

	inst_before = state.robot.instability
	var wrong_card: Dictionary = state.read_card("doc_test_2") # doc_test_2 для детали 2, а выбрана деталь 1
	_check(wrong_card.is_empty(), "read_card не от той детали возвращает {}")
	_check(state.current_phase == GameStateScript.Phase.DOC_SEARCH, "при неверной карточке фаза DOC_SEARCH")
	_check(state.robot.instability > inst_before, "неверная карточка начисляет штраф")
	_check(doc_read_log.back()["ok"] == false, "document_read(id, false) эмитнут")

	# 5. Верная карточка -> read_card возвращает карточку
	var correct_card: Dictionary = state.read_card("doc_test_1")
	_check(not correct_card.is_empty(), "read_card верной карточки возвращает данные")
	_check(correct_card.get("id", "") == "doc_test_1", "ID прочитанной карточки совпадает")
	_check(correct_card.has("steps_text"), "полная карточка содержит steps_text")
	_check(state.current_phase == GameStateScript.Phase.DOC_SEARCH, "после карточки остаемся в DOC_SEARCH до begin_repair")
	_check(doc_read_log.back()["ok"] == true, "document_read(id, true) эмитнут")

	state.free()
	_t("выбор детали, картотека, штрафы за ошибки и чтение регламента ТО")


func _test_repair_flow_and_steps() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_create_test_parts(), _create_test_cards())
	state.start_shift()
	state.run_diagnostics()
	state.select_part("test_part_1")

	# 1. begin_repair без прочитанной карточки -> отказ
	_check(not state.begin_repair(), "begin_repair без карточки возвращает false")
	_check(state.current_phase == GameStateScript.Phase.DOC_SEARCH, "фаза остается DOC_SEARCH")

	# Читаем верную карточку
	state.read_card("doc_test_1")

	var step_requested_log: Array = []
	state.step_requested.connect(func(idx, step): step_requested_log.append({"idx": idx, "step": step}))

	# 2. begin_repair -> переход в REPAIR и один вызов step_requested(0)
	var started: bool = state.begin_repair()
	_check(started, "begin_repair возвращает true")
	_check(state.current_phase == GameStateScript.Phase.REPAIR, "фаза переходит в REPAIR")
	_check(step_requested_log.size() == 1, "step_requested эмитнут ровно один раз")
	_check(step_requested_log[0]["idx"] == 0, "первый шаг имеет index 0")

	# 3. Успешный шаг 0 -> запрос шага 1
	var inst_before: float = state.robot.instability
	state.report_step_result(0, true, 1.0)
	_check(state.robot.instability < inst_before, "успешный шаг снижает нестабильность")
	_check(step_requested_log.size() == 2, "эмитнут следующий шаг")
	_check(step_requested_log[1]["idx"] == 1, "индекс следующего шага 1")
	_check(state._current_step_index == 1, "текущий индекс перешел на 1")

	# 4. Устаревший вызов index 0 игнорируется
	var inst_after_step0: float = state.robot.instability
	state.report_step_result(0, true, 1.0)
	_check(state.robot.instability == inst_after_step0, "устаревший index игнорируется")
	_check(state._current_step_index == 1, "индекс не сдвинулся")

	# 5. Провал шага 1 -> штраф, шаг повторяется (индекс не сдвинут)
	var step_failed_log: Array = []
	state.step_failed.connect(func(idx, r): step_failed_log.append({"idx": idx, "reason": r}))

	inst_before = state.robot.instability
	var m_before: int = state.mistakes
	state.report_step_result(1, false, 0.0, "slip")
	_check(state._current_step_index == 1, "при fail индекс не сдвинулся")
	_check(state.mistakes == m_before + 1, "mistakes инкрементирован")
	_check(state.robot.instability > inst_before, "начислен штраф за fail")
	_check(step_failed_log.back()["reason"] == "slip", "step_failed эмитнут с причиной slip")

	# 6. Ошибка порядка (reason: "order:...") -> дополнительный штраф loop.order_penalty
	inst_before = state.robot.instability
	var ord_before: int = state._order_errors
	state.report_step_result(1, false, 0.0, "order:wrong_tool")
	_check(state._order_errors == ord_before + 1, "order_errors инкрементирован")
	_check(state.robot.instability >= inst_before + 16.0, "начислен штраф fail(6) + order(10)")

	# 7. Таймаут шага через tick() -> step_failed("timeout")
	inst_before = state.robot.instability
	state._step_elapsed = 9.9
	state.tick(0.2) # превышает time_limit 10.0
	_check(step_failed_log.back()["reason"] == "timeout", "таймаут эмитит step_failed(timeout)")
	_check(state.robot.instability > inst_before, "таймаут начисляет штраф")
	_check(state._current_step_index == 1, "индекс все еще 1")

	state.free()
	_t("ремонт: запуск, пошаговое исполнение, устаревшие вызовы, срывы, order-штрафы и таймаут")


func _test_pause_system_and_limits() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_create_test_parts(), _create_test_cards())
	state.start_shift()
	state.run_diagnostics()
	state.select_part("test_part_1")
	state.read_card("doc_test_1")
	state.begin_repair()

	var pause_log: Array = []
	state.pause_changed.connect(func(p, r): pause_log.append({"p": p, "r": r}))

	# 1. Запрос паузы
	state.request_pause("cooldown_test")
	_check(state.is_paused, "пауза успешно активирована")
	_check(pause_log.back()["p"] == true, "pause_changed(true) эмитнут")

	# 2. Ввод заблокирован на паузе
	_check(not state.select_part("test_part_1"), "ввод select_part заблокирован на паузе")
	_check(state.read_card("doc_test_1").is_empty(), "ввод read_card заблокирован на паузе")
	_check(not state.begin_repair(), "ввод begin_repair заблокирован на паузе")
	var inst_before_report: float = state.robot.instability
	state.report_step_result(0, true, 1.0)
	_check(state._current_step_index == 0, "report_step_result заблокирован на паузе")

	# 3. Охлаждение нестабильности на паузе (-1.2%/с)
	var inst_frozen: float = state.robot.instability
	state.tick(2.0)
	_check(state.robot.instability < inst_frozen, "на паузе нестабильность охлаждается")

	# 4. Авто-возобновление после max_seconds (25 с)
	state.tick(24.0) # суммарно 26.0 с > 25.0 с
	_check(not state.is_paused, "автоматическое возобновление работы после max_seconds")
	_check(pause_log.back()["p"] == false, "pause_changed(false) эмитнут")

	# 5. Кулдаун паузы (20 с): повторная пауза сразу отклоняется
	state.request_pause("spam_pause")
	_check(not state.is_paused, "пауза во время кулдауна отклонена")
	state.tick(20.1) # кулдаун истек

	# 6. Пауза при AWAKE отклоняется
	state.wake()
	_check(state.current_threat == GameStateScript.Threat.AWAKE, "робот в AWAKE")
	state.request_pause("awake_pause")
	_check(not state.is_paused, "пауза в состоянии AWAKE отклоняется")
	state.calm_down()

	# 7. Лимит пауз на смену (максимум 3 раза)
	state.request_pause("use_2")
	_check(state.is_paused, "пауза 2 успешна")
	state.request_resume()
	state.tick(20.1)

	state.request_pause("use_3")
	_check(state.is_paused, "пауза 3 успешна")
	state.request_resume()
	state.tick(20.1)

	state.request_pause("use_4")
	_check(not state.is_paused, "4-я пауза отклонена по лимиту max_uses_per_shift (3)")

	state.free()
	_t("пауза: охлаждение, блокировка ввода, авто-резюм, кулдаун 20с, отказ в AWAKE и лимит 3 раз")


func _test_threat_awake_flow_and_motion() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_create_test_parts(), _create_test_cards())
	state.start_shift()

	var wake_started_fired := [false]
	var wake_ended_fired := [false]
	state.wake_started.connect(func(d): wake_started_fired[0] = true)
	state.wake_ended.connect(func(): wake_ended_fired[0] = true)

	# 1. Порог нестабильности вызывает пробуждение
	state.robot.instability = state.robot.threshold - 1.0
	state.add_instability(2.0)

	_check(state.current_threat == GameStateScript.Threat.AWAKE, "превышение порога переводит в Threat.AWAKE")
	_check(wake_started_fired[0], "wake_started эмитнут")

	# 2. Интенты отклоняются во время пробуждения
	_check(not state.select_part("test_part_1"), "select_part отклонен при AWAKE")
	_check(state.run_diagnostics().is_empty(), "run_diagnostics отклонен при AWAKE")
	_check(not state.run_verification(), "run_verification отклонен при AWAKE")

	# 3. Движение во время grace-периода безопасно
	var inst_awake: float = state.robot.instability
	state.on_mouse_moved(5.0)
	_check(state.robot.instability == inst_awake, "в grace-периоде движение не штрафуется")

	# 4. Движение после grace-периода штрафуется
	state.tick(state.freeze_grace + 0.05)
	state.on_mouse_moved(5.0)
	_check(state.robot.instability > inst_awake, "после grace-периода движение штрафуется")

	# 5. Истечение freeze_seconds завершает пробуждение
	state.tick(state.freeze_left + 0.1)
	_check(state.current_threat == GameStateScript.Threat.CALM, "угроза возвращается в Threat.CALM")
	_check(wake_ended_fired[0], "wake_ended эмитнут")

	state.free()
	_t("угроза и AWAKE: блокировка интентов, grace-период, штраф за движение и wake_ended")


func _test_threat_control_and_verify_pass_complete_shift() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_create_test_parts(), _create_test_cards())
	state.start_shift()

	# --- ОБСЛУЖИВАНИЕ ДЕТАЛИ 1 ---
	state.run_diagnostics()
	state.select_part("test_part_1")
	state.read_card("doc_test_1")
	state.begin_repair()
	state.report_step_result(0, true, 1.0)
	state.report_step_result(1, true, 1.0)

	_check(state.current_phase == GameStateScript.Phase.THREAT_CONTROL, "все шаги детали 1 завершены -> THREAT_CONTROL")

	# Срыв удержания движением мыши в THREAT_CONTROL
	var inst_tc: float = state.robot.instability
	state.on_mouse_moved(3.0)
	_check(state.robot.instability > inst_tc, "срыв движения в THREAT_CONTROL начисляет штраф")
	_check(state._threat_control_timer == 0.0, "таймер удержания сброшен")

	# Спокойное удержание 3.0 с
	state.tick(3.1)
	_check(state.parts_done == 1, "деталь 1 успешно проверена (parts_done = 1)")
	_check(state.current_phase == GameStateScript.Phase.DIAGNOSTICS, "есть еще детали -> переход в DIAGNOSTICS")

	# --- ОБСЛУЖИВАНИЕ ДЕТАЛИ 2 ---
	var rep2: Dictionary = state.run_diagnostics()
	_check(rep2.get("count", 0) == 1, "в диагностике осталась 1 деталь")
	_check(rep2["parts"][0]["id"] == "test_part_2", "осталась деталь 2")

	state.select_part("test_part_2")
	state.read_card("doc_test_2")
	state.begin_repair()
	state.report_step_result(0, true, 1.0)

	_check(state.current_phase == GameStateScript.Phase.THREAT_CONTROL, "шаги детали 2 завершены -> THREAT_CONTROL")
	state.tick(3.1)

	# Все детали обслужены -> SHIFT_COMPLETE
	_check(state.current_phase == GameStateScript.Phase.SHIFT_COMPLETE, "все детали готовы -> SHIFT_COMPLETE")
	_check(state.is_over(), "смена завершена (is_over = true)")

	var stats: Dictionary = state.get_shift_stats()
	_check(stats.get("parts_done", 0) == 2, "статистика: parts_done == 2")
	_check(stats.get("score", 0) > 0, "статистика: score > 0")
	_check(stats.get("fail_reason", "") == "", "статистика: fail_reason пуст при успехе")

	state.free()
	_t("полная цепочка 2 деталей: THREAT_CONTROL, удержание, верификация и SHIFT_COMPLETE")


func _test_verify_fail_retry_and_max_attempts() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_create_test_parts(), _create_test_cards())
	state.start_shift()

	state.run_diagnostics()
	state.select_part("test_part_1")
	state.read_card("doc_test_1")
	state.begin_repair()

	# Ошибка порядка и плохое качество -> гарантированный провал верификации
	state.report_step_result(0, false, 0.0, "order:bad")
	state.report_step_result(0, true, 0.2)
	state.report_step_result(1, true, 0.2)

	# Попытка 1 верификации
	var pass1: bool = state.run_verification()
	_check(not pass1, "верификация с order_errors и плохим качеством провалена")
	_check(state._part_attempts == 1, "попытка верификации учтена (1)")
	_check(state.current_phase == GameStateScript.Phase.DIAGNOSTICS, "после провала возврат в DIAGNOSTICS")

	# Повторная попытка переделки
	state.run_diagnostics()
	state.select_part("test_part_1")
	state.read_card("doc_test_1")
	state.begin_repair()
	state.report_step_result(0, false, 0.0, "order:bad")
	state.report_step_result(0, true, 0.1)
	state.report_step_result(1, true, 0.1)

	# Попытка 2 верификации -> исчерпание max_attempts (2) -> SHIFT_FAILED
	var pass2: bool = state.run_verification()
	_check(not pass2, "повторная верификация провалена")
	_check(state.current_phase == GameStateScript.Phase.SHIFT_FAILED, "исчерпание max_attempts -> SHIFT_FAILED")
	_check(state.is_over(), "смена завершена с провалом")
	_check(state.fail_reason != "", "fail_reason заполнен")

	state.free()
	_t("верификация: провал, переделка детали, исчерпание попыток и SHIFT_FAILED")


func _test_critical_instability_and_shift_timeout() -> void:
	# 1. Аварийный перегрев (нестабильность 100%)
	var state := GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_create_test_parts(), _create_test_cards())
	state.start_shift()
	state.add_instability(120.0)

	_check(state.current_phase == GameStateScript.Phase.SHIFT_FAILED, "нестабильность 100% -> SHIFT_FAILED")
	_check(state.is_over(), "смена провалена по перегреву")
	state.free()

	# 2. Таймаут смены (600 с)
	var state2 := GameStateScript.new()
	state2.initialize_game()
	state2.setup_loop(_create_test_parts(), _create_test_cards())
	state2.start_shift()
	state2.tick(605.0)

	_check(state2.current_phase == GameStateScript.Phase.SHIFT_FAILED, "таймаут смены 600 с -> SHIFT_FAILED")
	_check(state2.is_over(), "смена провалена по времени")
	state2.free()
	_t("аварийные выходы: перегрев 100% и таймаут смены 600с")


func _test_legacy_flow_untouched() -> void:
	var state := GameStateScript.new()
	state.initialize_game()
	state.start()

	_check(state.current_mode == GameStateScript.Mode.LEGACY, "start() переводит в режим LEGACY")
	_check(state.current_state == GameStateScript.State.CALM, "LEGACY: состояние CALM")
	_check(state.current_stage_index == 0, "LEGACY: стартовый этап 0")
	_check(state.stages.size() >= 3, "LEGACY: загружено 3 этапа ремонта")

	# Проходим все 3 легаси-этапа
	state.apply_repair(0, "cloth")
	_check(state.current_stage_index == 1, "LEGACY: этап 1 завершен")

	state.apply_repair(0, "screwdriver")
	state.apply_repair(1, "screwdriver")
	state.apply_repair(2, "screwdriver")
	state.apply_repair(3, "screwdriver")
	_check(state.current_stage_index == 2, "LEGACY: этап 2 завершен")

	state.apply_repair(0, "cable")
	_check(state.current_state == GameStateScript.State.DONE, "LEGACY: заказ выполнен успешно")
	_check(state.is_over(), "LEGACY: is_over == true")

	state.free()
	_t("полный легаси-путь: start() + 3 этапа работают байт-в-байт")
