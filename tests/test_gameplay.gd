extends SceneTree

## Автотесты ядра Do Not Wake.
##
## Запуск: godot --headless --path . -s tests/test_gameplay.gd
## Код выхода: 0 — все проверки прошли, 1 — есть провалы (годится для CI).
##
## Важно: assert в GDScript обрывает только текущую функцию, поэтому тест
## на assert'ах раньше печатал «ВСЕ ПРОЙДЕНЫ» даже после падения. Здесь
## явный счётчик проверок и провалов, а не assert.

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("--- ЗАПУСК АВТОТЕСТОВ ИГРОВОГО ЯДРА ---")
	_test_balance_loading()
	_test_procedural_interactivity_and_animations()
	_test_game_loop_and_stages()
	_test_instability_and_awake_flow()
	_test_freeze_grace()
	_test_parallax_rig()

	if _failures.is_empty():
		print("--- ВСЕ АВТОТЕСТЫ ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ПРОВАЛЕНО: %d из %d проверок ---" % [_failures.size(), _checks])
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


func _test_balance_loading() -> void:
	var balance := Balance.new()
	_check(balance.data.size() > 0, "Balance: конфиг загружен")
	_check(is_equal_approx(balance.get_float("threshold", 0.0), 70.0), "Balance: threshold = 70.0")
	_check(balance.get_stages().size() == 3, "Balance: 3 этапа в robot.json")
	_check(balance.get_tools().size() == 3, "Balance: 3 инструмента в robot.json")

	# Мусор в конфиге не должен ломать список
	balance.data["tools"] = [{"id": "cloth", "label": "Тряпка"}, "мусор", 42, {}]
	_check(balance.get_tools().size() == 1, "Balance: некорректные записи инструментов отбрасываются")
	_check(Balance.to_rect([10, 20, 30, 40]) == Rect2(10, 20, 30, 40), "Balance: to_rect из массива")
	_check(Balance.to_rect("мусор") == Rect2(), "Balance: to_rect мусора -> пустой Rect2")
	_t("загрузка данных и защита от мусора")


func _test_procedural_interactivity_and_animations() -> void:
	var balance := Balance.new()

	# 1. Загрузка параметров дыхания из robot.json
	var breath := balance.get_breathing_params()
	_check(is_equal_approx(breath["amplitude"], 3.0), "Breathing: amplitude == 3.0")
	_check(is_equal_approx(breath["frequency"], 0.5), "Breathing: frequency == 0.5")
	_check(is_equal_approx(breath["delay"], 0.4), "Breathing: delay == 0.4")

	# 2. Загрузка порогов реакции на приближение мыши
	var prox := balance.get_mouse_proximity_params()
	_check(is_equal_approx(prox["distance"], 180.0), "Mouse Proximity: distance == 180.0")
	_check(is_equal_approx(prox["sensitivity"], 0.85), "Mouse Proximity: sensitivity == 0.85")

	# 3. Загрузка цветов свечения оптики
	var optics := balance.get_optic_glow_params()
	_check(optics["calm"].is_equal_approx(Color.from_string("#748B91", Color.WHITE)), "Optic Glow: calm color matches #748B91")
	_check(optics["alert"].is_equal_approx(Color.from_string("#E62815", Color.WHITE)), "Optic Glow: alert color matches #E62815")
	_check(balance.get_optic_color("calm") == optics["calm"], "Optic Glow: get_optic_color('calm')")
	_check(balance.get_optic_color("alert") == optics["alert"], "Optic Glow: get_optic_color('alert')")

	# 4. Загрузка параметров частиц пара
	var steam := balance.get_steam_particle_params()
	_check(steam["count"] == 24, "Steam: count == 24")
	_check(is_equal_approx(steam["lifetime"], 1.4), "Steam: lifetime == 1.4")
	_check(is_equal_approx(steam["speed_min"], 25.0), "Steam: speed_min == 25.0")
	_check(is_equal_approx(steam["speed_max"], 65.0), "Steam: speed_max == 65.0")
	_check(steam["color"].is_equal_approx(Color.from_string("#C4CDD6", Color.WHITE)), "Steam: color matches #C4CDD6")

	# 5. Сводный словарь get_procedural_animation()
	var proc := balance.get_procedural_animation()
	_check(proc.has("breathing") and proc.has("mouse_proximity") and proc.has("optic_glow") and proc.has("steam_particles"), "Procedural animation: all 4 modules present")

	# 6. Защита от мусора и валидация типов
	# to_color
	_check(Balance.to_color("#E62815") == Color.from_string("#E62815", Color.WHITE), "Balance: to_color валидный hex")
	_check(Balance.to_color("E62815") == Color.from_string("#E62815", Color.WHITE), "Balance: to_color hex без решетки")
	_check(Balance.to_color(Color.RED) == Color.RED, "Balance: to_color объект Color")
	_check(Balance.to_color([1.0, 0.0, 0.0]) == Color(1.0, 0.0, 0.0), "Balance: to_color RGB массив")
	_check(Balance.to_color("мусор", Color.BLUE) == Color.BLUE, "Balance: to_color мусор -> fallback")
	_check(Balance.to_color(12345, Color.BLUE) == Color.BLUE, "Balance: to_color невалидный тип -> fallback")

	# Подмена на мусорный конфиг
	var junk_balance := Balance.new()
	junk_balance.data = {
		"procedural_animation": "мусор вместо словаря"
	}
	var junk_breath := junk_balance.get_breathing_params()
	_check(is_equal_approx(junk_breath["amplitude"], Balance.DEFAULT_BREATHING["amplitude"]), "Breathing: мусорный блок -> fallback amplitude")
	_check(is_equal_approx(junk_breath["frequency"], Balance.DEFAULT_BREATHING["frequency"]), "Breathing: мусорный блок -> fallback frequency")

	junk_balance.data = {
		"procedural_animation": {
			"breathing": {"amplitude": "мусор", "frequency": -10.0, "delay": "не число"},
			"mouse_proximity": {"distance": null, "sensitivity": 999.0},
			"optic_glow": {"calm": "не цвет", "alert": 123},
			"steam_particles": {"count": "много", "lifetime": 0.0}
		}
	}
	var safe_breath := junk_balance.get_breathing_params()
	_check(is_equal_approx(safe_breath["amplitude"], Balance.DEFAULT_BREATHING["amplitude"]), "Breathing: невалидная амплитуда -> fallback")
	_check(safe_breath["frequency"] >= 0.01, "Breathing: отрицательная частота скорректирована")

	var safe_prox := junk_balance.get_mouse_proximity_params()
	_check(is_equal_approx(safe_prox["distance"], Balance.DEFAULT_MOUSE_PROXIMITY["distance"]), "Mouse Proximity: null дистанция -> fallback")
	_check(safe_prox["sensitivity"] <= 10.0, "Mouse Proximity: зашкаливающая чувствительность ограничена")

	var safe_optics := junk_balance.get_optic_glow_params()
	_check(safe_optics["calm"] == Balance.DEFAULT_OPTIC_GLOW["calm"], "Optic Glow: 'не цвет' -> fallback color")
	_check(safe_optics["alert"] == Balance.DEFAULT_OPTIC_GLOW["alert"], "Optic Glow: число -> fallback color")

	var safe_steam := junk_balance.get_steam_particle_params()
	_check(safe_steam["count"] == Balance.DEFAULT_STEAM_PARTICLES["count"], "Steam: 'много' -> fallback count")
	_check(safe_steam["lifetime"] >= 0.05, "Steam: нулевой lifetime скорректирован")

	# 7. Интеграция с Robot
	var robot := Robot.new()
	robot.configure(balance)
	_check(robot.breathing_params.size() > 0, "Robot: breathing_params настроены")
	_check(robot.mouse_proximity_params.size() > 0, "Robot: mouse_proximity_params настроены")
	_check(robot.optic_glow_params.size() > 0, "Robot: optic_glow_params настроены")
	_check(robot.steam_particle_params.size() > 0, "Robot: steam_particle_params настроены")
	_check(is_equal_approx(robot.get_breathing_offset(0.0), 0.0), "Robot: get_breathing_offset(0) == 0")
	_check(robot.get_optic_color(false) == optics["calm"], "Robot: calm optic color")
	_check(robot.get_optic_color(true) == optics["alert"], "Robot: alert optic color")

	_t("процедурная интерактивность, дыхание, оптика, пар и валидация мусора")


func _test_game_loop_and_stages() -> void:
	var state := GameState.new()
	state.initialize_game()
	state.start()

	_check(state.current_state == GameState.State.CALM, "Старт: состояние CALM")
	_check(state.current_stage_index == 0, "Старт: этап 0 (чистка)")

	# Не тот инструмент: штраф, этап не двигается
	var before := state.robot.instability
	state.apply_repair(0, "screwdriver")
	_check(state.robot.instability > before, "Не тот инструмент повышает нестабильность")
	_check(state.current_stage_index == 0, "Не тот инструмент не закрывает этап")

	# Верный инструмент: этап 1 -> 2
	state.apply_repair(0, "cloth")
	_check(state.current_stage_index == 1, "Этап 1 закрыт тряпкой -> этап 2")

	state.apply_repair(0, "screwdriver")
	_check(state.current_stage_index == 2, "Этап 2 закрыт отвёрткой -> этап 3")

	state.apply_repair(0, "keyboard")
	_check(state.current_state == GameState.State.DONE, "Этап 3 закрыт клавиатурой -> DONE")

	# Повторный клик по закрытому узлу не двигает игру и не штрафует
	var inst_after := state.robot.instability
	state.apply_repair(0, "keyboard")
	_check(is_equal_approx(state.robot.instability, inst_after), "Повторный клик по закрытому узлу не штрафует")
	_t("полный цикл 3 этапов и повторные клики")
	state.free()


func _test_instability_and_awake_flow() -> void:
	var state := GameState.new()
	state.initialize_game()
	state.start()

	var initial_threshold := state.robot.threshold
	state.robot.add_instability(60.0)
	state.tick(0.1)
	_check(state.current_state == GameState.State.AWAKE, "Нестабильность выше порога -> AWAKE")

	# В grace-периоде движение игрока не наказывается
	var before := state.robot.instability
	state.on_mouse_moved(50.0)
	_check(is_equal_approx(state.robot.instability, before), "Движение в grace-периоде не штрафуется")

	# После grace период замирания идёт, движение штрафуется
	state.tick(state.freeze_grace + 0.05)
	state.on_mouse_moved(5.0)
	_check(state.robot.instability > before, "Движение после grace повышает нестабильность")

	state.calm_down()
	_check(state.current_state == GameState.State.CALM, "Успокоение -> CALM")
	_check(state.robot.threshold < initial_threshold, "Порог снижается после пробуждения")
	_t("пробуждение, grace-период, замирание и снижение порога")
	state.free()


func _test_freeze_grace() -> void:
	var state := GameState.new()
	state.initialize_game()
	state.start()
	state.wake()
	_check(state.current_state == GameState.State.AWAKE, "wake() переводит в AWAKE")

	# Слишком частые пробуждения валят смену
	var guard := 0
	while state.current_state == GameState.State.AWAKE and guard < 50:
		state.freeze_left = 0.0
		state.tick(0.01)
		guard += 1
		state.wake()
	_check(state.current_state == GameState.State.FAIL, "Превышение лимита пробуждений -> FAIL")
	_check(state.fail_reason != "", "Причина провала заполнена")
	_t("лимит пробуждений и причина провала")
	state.free()


func _test_parallax_rig() -> void:
	var rig := ParallaxRig.new()
	rig.load_config("res://data/parallax.json")

	# Центр экрана — нулевое смещение
	rig.update(1.0, Vector2(640, 360), Vector2(1280, 720))
	_check(rig.offset_for_layer("far") == Vector2.ZERO, "Параллакс: центр экрана = 0")
	_check(rig.offset_for_layer("ui") == Vector2.ZERO, "Параллакс: слой ui неподвижен")

	# Правый-нижний угол: смещение растёт от far к ui
	rig.update(1.0, Vector2(1279, 719), Vector2(1280, 720))
	var far := rig.offset_for_layer("far")
	var mid := rig.offset_for_layer("mid")
	var near := rig.offset_for_layer("near")
	_check(far.x > 0.0 and far.y > 0.0, "Параллакс: far уезжает за мышью")
	_check(far == far.round(), "Параллакс: смещения целые (пиксель-арт не мылится)")
	_check(far.length() >= mid.length() and mid.length() >= near.length(),
		"Параллакс: глубина убывает far -> mid -> near")
	_check(far.length() <= float(rig.max_offset_px) * 1.42, "Параллакс: дальний слой не выходит за лимит")

	# Выключение и сброс
	rig.enabled = false
	_check(rig.offset_for_layer("far") == Vector2.ZERO, "Параллакс: enabled=false обнуляет смещения")
	rig.enabled = true
	rig.reset()
	_check(rig.offset_for_layer("far") == Vector2.ZERO, "Параллакс: reset() обнуляет смещения")
	_t("риг глубины: центр, угол, затухание, лимит, сброс")
