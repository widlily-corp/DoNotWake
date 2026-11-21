extends SceneTree

## Headless auto-tests for StepRunner (контракт данных §4.2).
## Tests all 5 step types (scrub, unbolt, cable_lock, hold, calibrate),
## wrong tool protection, freezing, abort, component isolation, and single final signal.

const StepRunner = preload("res://scripts/core/step_runner.gd")

var _failures: Array = []
var _checks: int = 0


class MockHost extends Node2D:
	var mouse_pos: Vector2 = Vector2.ZERO
	var mid_shift: Vector2 = Vector2.ZERO
	var held_tools: Dictionary = {}
	var tool_tips: Dictionary = {}
	var components: Dictionary = {}

	func get_mouse_pos() -> Vector2:
		return mouse_pos

	func is_tool_held(tool_id: String) -> bool:
		return bool(held_tools.get(tool_id, false))

	func get_tool_tip(tool_id: String) -> Vector2:
		return tool_tips.get(tool_id, mouse_pos)

	func get_mid_shift() -> Vector2:
		return mid_shift

	func get_component(kind: String) -> Node2D:
		return components.get(kind, null)


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ STEP_RUNNER (§4.2) ---")
	_test_unsupported_type()
	_test_scrub_step()
	_test_unbolt_step()
	_test_cable_lock_step()
	_test_hold_step()
	_test_calibrate_step()
	_test_wrong_tool_protection()
	_test_set_frozen()
	_test_abort_silence()
	_test_no_double_final()
	_test_component_isolation()

	if _failures.is_empty():
		print("--- ВСЕ ТЕСТЫ STEP_RUNNER ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
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


func _create_fixture() -> Dictionary:
	var host := MockHost.new()
	root.add_child(host)

	var scrub := ScrubZone.new()
	host.add_child(scrub)
	host.components["scrub"] = scrub

	var unbolt := ScrewBoltManager.new()
	host.add_child(unbolt)
	host.components["unbolt"] = unbolt

	var cable := CablePlug.new()
	host.add_child(cable)
	host.components["cable"] = cable

	var runner := StepRunner.new()
	host.add_child(runner)

	return {
		"host": host,
		"scrub": scrub,
		"unbolt": unbolt,
		"cable": cable,
		"runner": runner
	}


func _cleanup_fixture(f: Dictionary) -> void:
	var host: Node = f.get("host")
	if host and is_instance_valid(host):
		host.free()


func _test_unsupported_type() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]

	var step := {
		"id": "unknown_step",
		"type": "plasma_cutter",
		"tool": "torch",
		"params": {}
	}

	var results := { "failed_reason": "" }
	runner.step_failed.connect(func(reason: String): results["failed_reason"] = reason)

	runner.setup(host, step)
	_check(not runner.is_active(), "Unsupported type: runner не активен после setup")

	runner.start()
	_check(results["failed_reason"] == "unsupported_type", "Unsupported type: сигнал step_failed('unsupported_type') получен")
	_check(not runner.is_active(), "Unsupported type: runner деактивирован после ошибки")

	_cleanup_fixture(f)
	_t("Unsupported step type: немедленный отказ step_failed('unsupported_type')")


func _test_scrub_step() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]
	var scrub: ScrubZone = f["scrub"]

	var step := {
		"id": "clean_contacts",
		"type": "scrub",
		"tool": "cloth",
		"params": {
			"rect": [585.0, 215.0, 110.0, 45.0],
			"safe_speed_min": 120.0,
			"safe_speed_max": 600.0,
			"target_ratio": 0.95,
			"friction_heat_rate": 0.012,
			"overheat_penalty": 6.0
		}
	}

	runner.setup(host, step)
	_check(scrub.zone_rect == Rect2(585.0, 215.0, 110.0, 45.0), "Scrub: зона установлена из параметров шага")
	_check(scrub.safe_speed_min == 120.0, "Scrub: safe_speed_min настроен")
	_check(scrub.safe_speed_max == 600.0, "Scrub: safe_speed_max настроен")
	_check(scrub.target_clean_ratio == 0.95, "Scrub: target_clean_ratio настроен")

	var results := {
		"finished_quality": -1.0,
		"hazard_amount": 0.0,
		"hazard_msg": "",
		"progress_val": -1.0
	}

	runner.step_finished.connect(func(q: float): results["finished_quality"] = q)
	runner.hazard.connect(func(amt: float, msg: String):
		results["hazard_amount"] = amt
		results["hazard_msg"] = msg
	)
	runner.progress_changed.connect(func(p: float): results["progress_val"] = p)

	runner.start()
	_check(runner.is_active(), "Scrub: runner активен после start")

	# Проверка перегрева (hazard без провала шага)
	scrub.overheat_occurred.emit(6.0)
	_check(results["hazard_amount"] == 6.0, "Scrub: hazard получен с величиной overheat_penalty")
	_check(results["hazard_msg"] == "Перегрев", "Scrub: hazard содержит сообщение 'Перегрев'")
	_check(runner.is_active(), "Scrub: шаг продолжается после hazard (не завершился провалом)")

	# Проверка передачи прогресса
	scrub.clean_progress = 0.475
	scrub.scrub_progress_changed.emit(0.475)
	_check(absf(results["progress_val"] - 0.5) < 0.01, "Scrub: progress_changed транслирует отношение к target_ratio")

	# Завершение чистки
	scrub.clean_progress = 0.95
	scrub.scrub_completed.emit()
	_check(results["finished_quality"] >= 0.95, "Scrub: шаг успешно завершён с quality >= 0.95")
	_check(not runner.is_active(), "Scrub: runner не активен после завершения")

	_cleanup_fixture(f)
	_t("Scrub step: настройка, прогресс, hazard при перегреве и успешное завершение")


func _test_unbolt_step() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]
	var unbolt: ScrewBoltManager = f["unbolt"]

	var step := {
		"id": "unbolt_hatch",
		"type": "unbolt",
		"tool": "screwdriver",
		"params": {
			"hatch_rect": [570.0, 275.0, 140.0, 90.0],
			"bolts": [
				{ "id": "bolt_tl", "pos": [590.0, 295.0], "radius": 14.0, "turns_required": 1.0 },
				{ "id": "bolt_tr", "pos": [690.0, 295.0], "radius": 14.0, "turns_required": 1.0 }
			],
			"slip_params": {
				"snap_radius": 16.0,
				"slip_radius": 36.0,
				"max_angular_accel": 2500.0,
				"slip_penalty": 14.0,
				"slip_shake": 5.0
			}
		}
	}

	runner.setup(host, step)
	_check(unbolt.bolts.size() == 2, "Unbolt: создано ровно 2 болта")
	_check(unbolt.hatch_rect == Rect2(570.0, 275.0, 140.0, 90.0), "Unbolt: hatch_rect настроен")

	var results := {
		"finished_quality": -1.0,
		"hazard_amount": 0.0,
		"progress_val": 0.0
	}

	runner.step_finished.connect(func(q: float): results["finished_quality"] = q)
	runner.hazard.connect(func(amt: float, _msg: String): results["hazard_amount"] = amt)
	runner.progress_changed.connect(func(p: float): results["progress_val"] = p)

	runner.start()
	_check(runner.is_active(), "Unbolt: runner активен после start")

	# Симуляция срыва шлица (hazard)
	unbolt.tool_slipped.emit(14.0, 5.0)
	_check(results["hazard_amount"] == 14.0, "Unbolt: срыв шлица даёт hazard(14.0)")
	_check(runner.is_active(), "Unbolt: шаг остаётся активным после срыва")

	# Выкручивание первого болта
	unbolt.bolt_loosened.emit("bolt_tl", 1)
	_check(absf(results["progress_val"] - 0.5) < 0.01, "Unbolt: прогресс 0.5 после 1 из 2 болтов")

	# Демонтаж люка
	unbolt.hatch_removed.emit()
	# Качество: 1.0 - 0.2 * 1 срыв = 0.8
	_check(absf(results["finished_quality"] - 0.8) < 0.01, "Unbolt: качество 0.8 с учётом 1 срыва (1.0 - 0.2*slips)")
	_check(not runner.is_active(), "Unbolt: runner деактивирован после демонтажа люка")

	_cleanup_fixture(f)
	_t("Unbolt step: болты, срыв шлица с hazard, расчёт качества по числу срывов")


func _test_cable_lock_step() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]
	var cable: CablePlug = f["cable"]

	var step := {
		"id": "lock_cable",
		"type": "cable_lock",
		"tool": "cable",
		"params": {
			"socket_pos": [640.0, 160.0],
			"socket_radius": 26.0,
			"cable_anchor": [980.0, 640.0],
			"cable_home": [940.0, 600.0],
			"keyway_angle_deg": 90.0,
			"angle_tolerance_deg": 15.0,
			"lock_hold_time": 0.8
		}
	}

	runner.setup(host, step)
	_check(cable.socket_pos == Vector2(640.0, 160.0), "CableLock: socket_pos настроен")
	_check(cable.socket_radius == 26.0, "CableLock: socket_radius настроен")
	_check(cable.keyway_target_deg == 90.0, "CableLock: keyway_target_deg настроен")
	_check(cable.angle_tolerance_deg == 15.0, "CableLock: angle_tolerance_deg настроен")

	var results := { "finished_quality": -1.0 }
	runner.step_finished.connect(func(q: float): results["finished_quality"] = q)

	runner.start()
	_check(runner.is_active(), "CableLock: runner активен после start")

	# Симулируем перелёт по времени удержания (удерживали 1.2 с при норме 0.8 с, дельта = 0.4 с)
	host.mouse_pos = cable.socket_pos
	cable.is_dragged = true
	runner.tick(1.2)

	cable.cable_locked.emit()
	# Качество: 1.0 - 0.3 * (1.2 - 0.8) = 1.0 - 0.12 = 0.88
	_check(absf(results["finished_quality"] - 0.88) < 0.02, "CableLock: расчёт качества 0.88 с учётом перелёта удержания")
	_check(not runner.is_active(), "CableLock: шаг завершён")

	_cleanup_fixture(f)
	_t("CableLock step: конфиг, удержание у гнезда и фиксация замка")


func _test_hold_step() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]

	var step := {
		"id": "stabilize_power",
		"type": "hold",
		"tool": "none",
		"params": {
			"rect": [200.0, 200.0, 100.0, 100.0],
			"duration": 1.0,
			"motion_tolerance": 3.0
		}
	}

	runner.setup(host, step)
	var results := {
		"finished_quality": -1.0,
		"hazard_count": 0,
		"last_progress": 0.0
	}

	runner.step_finished.connect(func(q: float): results["finished_quality"] = q)
	runner.hazard.connect(func(_amt: float, _msg: String): results["hazard_count"] += 1)
	runner.progress_changed.connect(func(p: float): results["last_progress"] = p)

	runner.start()
	host.mouse_pos = Vector2(250.0, 250.0)

	# Удержание первые 0.4 с
	for i in 4:
		runner.tick(0.1)
	_check(results["last_progress"] >= 0.39, "Hold: прогресс растёт при спокойном удержании (0.4)")

	# Резкий рывок мышью за пределы tolerance
	host.mouse_pos = Vector2(290.0, 250.0) # 40px > 3.0px
	runner.tick(0.016)
	_check(results["last_progress"] == 0.0, "Hold: прогресс сброшен в ноль при резком движении")
	_check(results["hazard_count"] == 1, "Hold: срыв вызвал сигнал hazard")

	# Теперь держим спокойно до истечения 1.0 с (10 шагов по 0.1 с)
	for i in 10:
		runner.tick(0.1)

	_check(results["finished_quality"] > 0.0, "Hold: шаг успешно завершён по истечении времени")
	# 1 срыв: quality = 1.0 - 0.2 * 1 = 0.8
	_check(absf(results["finished_quality"] - 0.8) < 0.01, "Hold: качество 0.8 с учётом 1 срыва")

	_cleanup_fixture(f)
	_t("Hold step: удержание, сброс прогресса при рывке, завершение по таймеру")


func _test_calibrate_step() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]

	var step := {
		"id": "calibrate_optic",
		"type": "calibrate",
		"tool": "none",
		"params": {
			"rect": [100.0, 100.0, 80.0, 40.0],
			"min": 0.0,
			"max": 100.0,
			"target": 70.0,
			"tolerance": 10.0,
			"hold_time": 0.4
		}
	}

	runner.setup(host, step)
	var results := { "finished_quality": -1.0 }
	runner.step_finished.connect(func(q: float): results["finished_quality"] = q)

	runner.start()
	host.mouse_pos = Vector2(140.0, 120.0)

	# Тест изменения значения колесом мыши
	var ev_up := InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_WHEEL_UP
	ev_up.pressed = true
	runner.handle_input(ev_up)
	_check(runner.get_calibration_value() > 0.0, "Calibrate: колесо мыши изменяет значение")

	# Выставляем значение близкое к target (66.0, ошибка 4.0 <= толеранс 10.0)
	runner.set_calibration_value(66.0)
	runner.tick(0.2)
	_check(runner.is_active(), "Calibrate: через 0.2 с ещё не завершён (требуется 0.4 с)")

	# Додерживаем ещё 0.25 с
	runner.tick(0.25)
	# Качество: 1.0 - 0.5 * (4.0 / 10.0) = 1.0 - 0.2 = 0.8
	_check(absf(results["finished_quality"] - 0.8) < 0.01, "Calibrate: шаг завершён с качеством 0.8 (error=4, tol=10)")

	_cleanup_fixture(f)
	_t("Calibrate step: ввод колесом, удержание в окне допуска и расчёт качества")


func _test_wrong_tool_protection() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]

	var step := {
		"id": "clean_contacts",
		"type": "scrub",
		"tool": "cloth",
		"params": {
			"rect": [200.0, 200.0, 100.0, 100.0]
		}
	}

	runner.setup(host, step)
	var results := { "failed_reason": "", "hazard_msg": "", "hazard_amount": -1.0 }
	runner.step_failed.connect(func(r: String): results["failed_reason"] = r)
	runner.hazard.connect(func(amt: float, msg: String):
		results["hazard_amount"] = amt
		results["hazard_msg"] = msg
	)

	runner.start()
	host.held_tools["cloth"] = false
	host.mouse_pos = Vector2(250.0, 250.0) # Внутри зоны шага

	var click_ev := InputEventMouseButton.new()
	click_ev.button_index = MOUSE_BUTTON_LEFT
	click_ev.pressed = true
	var handled := runner.handle_input(click_ev)

	_check(handled, "Wrong tool: клик без инструмента перехвачен")
	_check(results["failed_reason"] == "", "Wrong tool: шаг НЕ проваливается (мягкая подсказка)")
	_check(results["hazard_amount"] == 0.0, "Wrong tool: подсказка без штрафа нестабильности")
	_check(results["hazard_msg"].begins_with("НУЖЕН ИНСТРУМЕНТ"), "Wrong tool: подсказка называет инструмент")
	_check(runner.is_active(), "Wrong tool: шаг продолжает выполняться")

	_cleanup_fixture(f)
	_t("Wrong tool: мягкая подсказка в зоне без штрафа; шаг не проваливается")


func _test_set_frozen() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]

	var step := {
		"id": "hold_test",
		"type": "hold",
		"tool": "none",
		"params": {
			"rect": [200.0, 200.0, 100.0, 100.0],
			"duration": 1.0,
			"motion_tolerance": 5.0
		}
	}

	runner.setup(host, step)
	runner.start()
	host.mouse_pos = Vector2(250.0, 250.0)

	runner.tick(0.4)
	runner.set_frozen(true)
	_check(runner.is_frozen(), "Frozen: флаг is_frozen установлен")

	# Во время заморозки тик не должен продвигать таймер
	runner.tick(0.5)
	_check(runner.is_active(), "Frozen: шаг не завершился во время заморозки")

	# Разморозка
	runner.set_frozen(false)
	_check(not runner.is_frozen(), "Frozen: флаг сброшен")
	# Осталось 0.6 с, тикаем 7 раз по 0.1 с
	for i in 7:
		runner.tick(0.1)
	_check(not runner.is_active(), "Frozen: после разморозки шаг успешно завершился")

	_cleanup_fixture(f)
	_t("Frozen state: set_frozen(true) замораживает прогресс и ввод")


func _test_abort_silence() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]

	var step := {
		"id": "hold_test",
		"type": "hold",
		"tool": "none",
		"params": {
			"rect": [200.0, 200.0, 100.0, 100.0],
			"duration": 1.0
		}
	}

	runner.setup(host, step)
	var results := { "any_signal": false }
	runner.step_finished.connect(func(_q): results["any_signal"] = true)
	runner.step_failed.connect(func(_r): results["any_signal"] = true)

	runner.start()
	_check(runner.is_active(), "Abort: шаг активен до abort")

	runner.abort()
	_check(not runner.is_active(), "Abort: runner не активен после abort")
	_check(not results["any_signal"], "Abort: abort() молчит, не эмитя step_finished или step_failed")

	_cleanup_fixture(f)
	_t("Abort: деактивация без финальных сигналов (abort молчит)")


func _test_no_double_final() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]
	var scrub: ScrubZone = f["scrub"]

	var step := {
		"id": "clean_contacts",
		"type": "scrub",
		"tool": "cloth",
		"params": {
			"rect": [100.0, 100.0, 50.0, 50.0],
			"target_ratio": 1.0
		}
	}

	runner.setup(host, step)
	var results := {
		"finish_count": 0,
		"fail_count": 0
	}
	runner.step_finished.connect(func(_q): results["finish_count"] += 1)
	runner.step_failed.connect(func(_r): results["fail_count"] += 1)

	runner.start()

	# Первое завершение
	scrub.scrub_completed.emit()
	_check(results["finish_count"] == 1, "Single final: сигнал step_finished отправлен ровно один раз")

	# Повторные попытки вызова
	scrub.scrub_completed.emit()
	runner.handle_input(InputEventMouseButton.new())
	runner.tick(0.1)

	_check(results["finish_count"] == 1, "Single final: дублирование step_finished заблокировано")
	_check(results["fail_count"] == 0, "Single final: step_failed не отправлялся")

	_cleanup_fixture(f)
	_t("Single final: ровно один финальный сигнал, повторные вызовы игнорируются")


func _test_component_isolation() -> void:
	var f := _create_fixture()
	var runner: StepRunner = f["runner"]
	var host: MockHost = f["host"]
	var scrub: ScrubZone = f["scrub"]
	var unbolt: ScrewBoltManager = f["unbolt"]
	var cable: CablePlug = f["cable"]

	scrub.is_active = true
	unbolt.is_active = true
	cable.is_active = true

	var step := {
		"id": "unbolt_test",
		"type": "unbolt",
		"tool": "screwdriver",
		"params": {
			"hatch_rect": [100.0, 100.0, 50.0, 50.0],
			"bolts": []
		}
	}

	runner.setup(host, step)
	runner.start()

	_check(unbolt.is_active, "Isolation: целевой компонент unbolt активен")
	_check(not scrub.is_active, "Isolation: сторонний компонент scrub отключён")
	_check(not cable.is_active, "Isolation: сторонний компонент cable отключён")

	runner.abort()

	_check(scrub.is_active, "Isolation: исходное состояние scrub восстановлено после завершения")
	_check(unbolt.is_active, "Isolation: исходное состояние unbolt восстановлено")
	_check(cable.is_active, "Isolation: исходное состояние cable восстановлено")

	_cleanup_fixture(f)
	_t("Component isolation: активен только компонент текущего шага, состояния восстанавливаются")
