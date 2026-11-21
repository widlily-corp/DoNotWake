extends SceneTree

## Headless auto-tests плейабилити петли ремонта (регресс на «ветошью тру — ничего не происходит»).
## Проверяет: скраб набирает прогресс, медленное движение не даёт прогресса,
## неверный инструмент не проваливает шаг, срыв/таймаут перезапускает шаг,
## инструмент «залипает» в руке, а движение в THREAT_CONTROL сбрасывает удержание.

const StepRunner = preload("res://scripts/core/step_runner.gd")
const GameStateScript = preload("res://scripts/core/game_state.gd")
const DraggableToolScript = preload("res://scripts/interaction/draggable_tool.gd")
const LoopDataScript = preload("res://scripts/core/loop_data.gd")

var _failures: Array = []
var _checks: int = 0


class MockHost extends Node2D:
	var mouse_pos: Vector2 = Vector2.ZERO
	var mid_shift: Vector2 = Vector2.ZERO
	var held_tools: Dictionary = {}
	var components: Dictionary = {}

	func get_mouse_pos() -> Vector2:
		return mouse_pos

	func is_tool_held(tool_id: String) -> bool:
		return bool(held_tools.get(tool_id, false))

	func get_tool_tip(_tool_id: String) -> Vector2:
		return mouse_pos

	func get_mid_shift() -> Vector2:
		return mid_shift

	func get_component(kind: String) -> Node2D:
		return components.get(kind, null)


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ ПЛЕЙАБИЛИТИ РЕМОНТА ---")
	_test_scrub_progress()
	_test_scrub_slow_feedback()
	_test_wrong_tool_is_soft()
	_test_timeout_restarts_step()
	_test_sticky_tool()
	_test_threat_control_motion()
	_test_awake_stops_step_timer()
	_test_diagnostics_carries_tag_positions()
	_test_verify_details()

	if _failures.is_empty():
		print("--- ВСЕ ТЕСТЫ ПЛЕЙАБИЛИТИ ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ПРОВАЛЕНО ТЕСТОВ: %d из %d проверок ---" % [_failures.size(), _checks])
		for f in _failures:
			printerr("    " + str(f))
		quit(1)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)
		printerr("  [FAIL] " + what)


func _t(t: String) -> void:
	print("  · " + t)


func _make_runner(step: Dictionary) -> Dictionary:
	var host := MockHost.new()
	root.add_child(host)
	var scrub := ScrubZone.new()
	host.add_child(scrub)
	host.components["scrub"] = scrub
	var runner := StepRunner.new()
	host.add_child(runner)
	runner.setup(host, step)
	return {"host": host, "scrub": scrub, "runner": runner}


func _free_fixture(f: Dictionary) -> void:
	var host: Node = f.get("host")
	if host != null and is_instance_valid(host):
		host.free()


func _scrub_step() -> Dictionary:
	return {
		"id": "clean_contacts",
		"type": "scrub",
		"tool": "cloth",
		"label": "Очистить контакты",
		"time_limit": 25.0,
		"params": {
			"rect": [585.0, 215.0, 110.0, 45.0],
			"safe_speed_min": 120.0,
			"safe_speed_max": 600.0,
			"target_ratio": 0.95
		}
	}


func _test_scrub_progress() -> void:
	var f := _make_runner(_scrub_step())
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]
	var scrub: ScrubZone = f["scrub"]

	var finished := {"q": -1.0}
	runner.step_finished.connect(func(q: float): finished["q"] = q)

	runner.start()
	host.held_tools["cloth"] = true
	host.mouse_pos = Vector2(600.0, 237.0)

	var dt := 1.0 / 60.0
	var t := 0.0
	var dir := 1.0
	while t < 6.0 and runner.is_active():
		host.mouse_pos.x += dir * 8.0
		if host.mouse_pos.x > 688.0:
			dir = -1.0
		elif host.mouse_pos.x < 592.0:
			dir = 1.0
		runner.tick(dt)
		t += dt

	_check(t < 6.0, "Scrub: шаг завершается за 6 с активного трения (t=%.2f)" % t)
	_check(finished["q"] >= 0.95, "Scrub: качество >= 0.95 при нормальном темпе")
	_check(scrub.is_completed, "Scrub: зона помечена очищенной")
	_free_fixture(f)
	_t("Scrub: ветошь в руке + движение 480 px/с дают прогресс и завершение")


func _test_scrub_slow_feedback() -> void:
	var f := _make_runner(_scrub_step())
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]
	var scrub: ScrubZone = f["scrub"]

	runner.start()
	host.held_tools["cloth"] = true
	host.mouse_pos = Vector2(600.0, 237.0)

	var dt := 1.0 / 60.0
	for i in 120:
		host.mouse_pos.x += 1.0
		if host.mouse_pos.x > 688.0:
			host.mouse_pos.x = 592.0
		runner.tick(dt)

	_check(scrub.clean_progress < 0.01, "Scrub: слишком медленное движение (60 px/с) не чистит контакты")
	_check(runner.is_active(), "Scrub: медленное движение не проваливает шаг")
	_free_fixture(f)
	_t("Scrub: медленное трение не даёт прогресса, но и не ломает шаг")


func _test_wrong_tool_is_soft() -> void:
	var f := _make_runner(_scrub_step())
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]

	var hazard := {"amt": -1.0, "msg": ""}
	runner.hazard.connect(func(a: float, m: String):
		hazard["amt"] = a
		hazard["msg"] = m
	)
	runner.start()
	host.held_tools["cloth"] = false
	host.mouse_pos = Vector2(640.0, 237.0)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var handled: bool = runner.handle_input(click)

	_check(handled, "Wrong tool: клик по зоне перехвачен")
	_check(runner.is_active(), "Wrong tool: шаг не провален")
	_check(hazard["amt"] == 0.0, "Wrong tool: подсказка без штрафа")
	_check(str(hazard["msg"]).begins_with("НУЖЕН ИНСТРУМЕНТ"), "Wrong tool: подсказка про инструмент")
	_free_fixture(f)
	_t("Wrong tool: клик без ветоши даёт подсказку, а не срыв шага")


func _fixture_parts() -> Array:
	return [{
		"id": "test_part",
		"tag": "T-01",
		"label": "Тестовый узел",
		"component_name": "Тестовый узел",
		"fault_code": "E-100",
		"symptom": "Тест",
		"doc_id": "doc_test",
		"zone": "chest",
		"tag_pos": [640, 360],
		"difficulty": 1,
		"steps": [
			{
				"id": "s1",
				"type": "scrub",
				"tool": "cloth",
				"label": "Чистка",
				"time_limit": 10.0,
				"params": {"rect": [585, 215, 110, 45], "target_ratio": 0.95},
				"instability": {"success": -4.0, "fail": 6.0, "timeout": 8.0}
			},
			{
				"id": "s2",
				"type": "hold",
				"tool": "none",
				"label": "Удержание",
				"time_limit": 5.0,
				"params": {"rect": [590, 300, 100, 40], "duration": 0.5},
				"instability": {"success": -4.0, "fail": 6.0, "timeout": 8.0}
			}
		],
		"verify": {"type": "pulse", "expected": 1.0, "tolerance": 0.1, "time_limit": 8.0},
		"reward": 8.0,
		"penalty": 10.0
	}]


func _fixture_cards() -> Array:
	return [{
		"id": "doc_test",
		"tag": "T-01",
		"drawer": "A",
		"title": "ТО-01. Тестовый узел",
		"tool_list": ["cloth"],
		"time_norm_sec": 20,
		"steps_text": ["Почистить", "Удержать"],
		"order": ["s1", "s2"],
		"safety_protocol": [],
		"notes": []
	}]


func _open_repair(state) -> void:
	state.start_shift()
	state.run_diagnostics()
	state.select_part("test_part")
	state.read_card("doc_test")
	state.begin_repair()


func _test_timeout_restarts_step() -> void:
	var state = GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_fixture_parts(), _fixture_cards())

	var requested: Array = []
	state.step_requested.connect(func(i, s): requested.append({"i": i, "id": s.get("id", "")}))

	_open_repair(state)
	_check(requested.size() == 1, "Retry: первый шаг запрошен один раз")

	state.tick(10.5)
	_check(requested.size() == 2, "Retry: после таймаута шаг запрошен повторно")
	_check(requested[1]["i"] == 0 and requested[1]["id"] == "s1", "Retry: перезапущен тот же шаг 0")

	state.report_step_result(0, true, 1.0)
	_check(state._current_step_index == 1, "Retry: после успешного повтора перешли к шагу 1")
	state.report_step_result(1, true, 1.0)
	_check(state.current_phase == GameStateScript.Phase.THREAT_CONTROL, "Retry: шаги завершены -> THREAT_CONTROL")

	state.tick(3.1)
	_check(state.parts_done == 1, "Retry: верификация проходит после честного повтора")
	_check(state.current_phase == GameStateScript.Phase.SHIFT_COMPLETE, "Retry: смена закрывается успешно")

	state.free()
	_t("Retry: таймаут перезапускает шаг, повтор проходит верификацию")


func _test_sticky_tool() -> void:
	var tool := DraggableToolScript.new()
	tool.setup("cloth", "Ветошь", Rect2(140.0, 600.0, 160.0, 90.0))
	root.add_child(tool)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false

	var center := Vector2(220.0, 645.0)
	_check(tool.handle_mouse_input(press, center), "Sticky: клик по лотку взят в обработку")
	_check(tool.is_in_hand(), "Sticky: инструмент в руке после клика")

	tool.update_tool(1.0 / 60.0, center)
	_check(tool.handle_mouse_input(release, center) == false, "Sticky: отпускание ЛКМ не обрабатывается")
	_check(tool.is_in_hand(), "Sticky: после отпускания ЛКМ инструмент остаётся в руке")

	var target := Vector2(640.0, 240.0)
	for i in 20:
		tool.update_tool(1.0 / 60.0, target)
	_check(tool.position.distance_to(target) < 12.0, "Sticky: инструмент следует за курсором без зажатой кнопки")

	_check(tool.handle_mouse_input(press, target) == false, "Sticky: клик в мире не отбирает инструмент")
	_check(tool.is_in_hand(), "Sticky: клик в мире не роняет инструмент")

	_check(tool.handle_mouse_input(press, center), "Sticky: клик по своему лотку убирает инструмент")
	_check(not tool.is_in_hand(), "Sticky: инструмент возвращается в лоток")

	tool.free()
	_t("Sticky: один клик берёт инструмент, повторный клик по лотку убирает")


func _test_threat_control_motion() -> void:
	var state = GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_fixture_parts(), _fixture_cards())
	_open_repair(state)
	state.report_step_result(0, true, 1.0)
	state.report_step_result(1, true, 1.0)
	_check(state.current_phase == GameStateScript.Phase.THREAT_CONTROL, "Threat: фаза контроля угрозы")

	state._threat_control_timer = 1.5
	var inst_before: float = state.robot.instability
	state.on_mouse_moved(20.0)
	_check(state._threat_control_timer == 0.0, "Threat: рывок мышью сбрасывает удержание")
	_check(state.robot.instability > inst_before, "Threat: рывок начисляет штраф")

	var inst_after: float = state.robot.instability
	state.on_mouse_moved(20.0)
	_check(is_equal_approx(state.robot.instability, inst_after), "Threat: повторный рывок в кулдауне не штрафуется")

	state.tick(3.1)
	_check(state.parts_done == 1, "Threat: спокойное удержание 3 с проходит проверку")
	state.free()
	_t("Threat: движение сбрасывает удержание, штраф не спамится каждый кадр")


func _test_awake_stops_step_timer() -> void:
	var state = GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_fixture_parts(), _fixture_cards())
	_open_repair(state)
	state.tick(2.0)
	_check(state._step_elapsed > 1.9, "Awake: таймер шага идёт в обычном режиме")

	state.robot.instability = 69.0
	state.add_instability(2.0)
	_check(state.current_threat == GameStateScript.Threat.AWAKE, "Awake: робот проснулся на пороге")
	var elapsed_at_wake: float = state._step_elapsed
	var requested_before: int = state._current_step_index

	state.tick(2.0)
	_check(is_equal_approx(state._step_elapsed, elapsed_at_wake), "Awake: таймер шага стоит во время пробуждения")
	_check(state._current_step_index == requested_before, "Awake: шаг не перезапускается во время пробуждения")

	# После пробуждения шаг продолжается, таймер снова идёт
	state.tick(state.freeze_left + 0.1)
	state.tick(1.0)
	_check(state._step_elapsed > elapsed_at_wake, "Awake: после пробуждения таймер шага продолжается")
	state.free()
	_t("Awake: пробуждение замораживает таймер шага, после — ремонт продолжается")


func _test_diagnostics_carries_tag_positions() -> void:
	var state = GameStateScript.new()
	state.initialize_game()
	var parts: Array = LoopDataScript.load_parts()
	var docs: Dictionary = LoopDataScript.load_documents()
	state.setup_loop(parts, docs.get("cards", []))
	state.start_shift()

	var rep: Dictionary = state.run_diagnostics()
	var positions: Dictionary = {}
	for p in rep.get("parts", []):
		if p is Dictionary:
			positions[str(p.get("id", ""))] = p.get("tag_pos", [])
	_check(positions.size() >= 2, "Diagnostics: в отчёте все неисправные детали")
	var srv: Array = positions.get("srv_04", [])
	var pwr: Array = positions.get("pwr_02", [])
	_check(srv.size() == 2 and absf(float(srv[0]) - 612.0) < 0.01 and absf(float(srv[1]) - 236.0) < 0.01, "Diagnostics: tag_pos детали A-04 сохранён")
	_check(pwr.size() == 2 and absf(float(pwr[0]) - 640.0) < 0.01 and absf(float(pwr[1]) - 360.0) < 0.01, "Diagnostics: tag_pos детали B-02 сохранён")
	_check(srv != pwr, "Diagnostics: бирки не сваливаются в одну точку")

	state.free()
	_t("Diagnostics: отчёт несёт tag_pos, бирки деталей стоят на своих местах")


func _test_verify_details() -> void:
	var state = GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_fixture_parts(), _fixture_cards())
	var details := {"d": {}}
	state.verification_finished.connect(func(_p: bool, det: Dictionary): details["d"] = det)
	_open_repair(state)
	state.report_step_result(0, true, 1.0)
	state.report_step_result(1, true, 0.9)
	state.tick(3.1)

	var d: Dictionary = details["d"]
	_check(d.has("steps_completed") and int(d["steps_completed"]) == 2, "Verify: details содержат число выполненных шагов")
	_check(d.has("steps_total") and int(d["steps_total"]) == 2, "Verify: details содержат общее число шагов")
	_check(d.has("quality") and absf(float(d["quality"]) - 0.95) < 0.01, "Verify: details содержат среднее качество")
	_check(bool(d.get("passed", false)), "Verify: деталь принята ОТК")
	state.free()
	_t("Verify: в details есть шаги и качество для панели ОТК")
