extends SceneTree

## Тест скрипта интро-катсцены (CutsceneIntro)
## Запуск: godot --headless --path . --script tests/test_cutscene_intro.gd

const CutsceneIntro = preload("res://scripts/ui/cutscene_intro.gd")


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ CUTSCENE_INTRO ---")
	var success := true

	success = success and _test_initialization()
	success = success and _test_lore_content()
	success = success and _test_fade_in_and_typewriter()
	success = success and _test_instant_skip()
	success = success and _test_exit_fade_and_signal()
	success = success and _test_input_handling()
	success = success and _test_scene_load()

	if success:
		print("--- ВСЕ ТЕСТЫ CUTSCENE_INTRO УСПЕШНО ПРОЙДЕНЫ ---")
		quit(0)
	else:
		printerr("--- ТЕСТЫ CUTSCENE_INTRO ЗАВЕРШИЛИСЬ С ОШИБКАМИ ---")
		quit(1)


func _test_initialization() -> bool:
	print("  · Тест 1: Инициализация и геометрические параметры")
	var cutscene: CutsceneIntro = CutsceneIntro.new()
	root.add_child(cutscene)

	var ok: bool = true
	if not cutscene.is_active:
		printerr("    [ОШИБКА] is_active должен быть true по умолчанию")
		ok = false
	if not is_equal_approx(cutscene.fade_alpha, 1.0):
		printerr("    [ОШИБКА] fade_alpha должен быть 1.0 по умолчанию")
		ok = false
	if cutscene.is_typing_finished:
		printerr("    [ОШИБКА] is_typing_finished должен быть false при старте")
		ok = false
	if cutscene.custom_minimum_size != Vector2(1280, 720):
		printerr("    [ОШИБКА] custom_minimum_size должен быть 1280x720, получено: ", cutscene.custom_minimum_size)
		ok = false

	cutscene.queue_free()
	return ok


func _test_lore_content() -> bool:
	print("  · Тест 2: Проверка лора, обязательных строк и правил")
	var cutscene: CutsceneIntro = CutsceneIntro.new()
	root.add_child(cutscene)

	var ok: bool = true
	var found_vepr: bool = false
	var found_antracit: bool = false
	var found_do_not_wake: bool = false
	var found_fatalities: bool = false
	var found_threshold: bool = false

	for line: Dictionary in cutscene._lines:
		var text: String = line.get("text", "")
		if "ВЕПРЬ-04" in text:
			found_vepr = true
		if "АНТРАЦИТ" in text:
			found_antracit = true
		if "НЕ БУДИ ЕГО" in text:
			found_do_not_wake = true
			if not line.get("is_alert", false):
				printerr("    [ОШИБКА] Строка 'НЕ БУДИ ЕГО' должна иметь флаг is_alert = true")
				ok = false
		if "4 ТЕХНИКА" in text:
			found_fatalities = true
		if ">70%" in text:
			found_threshold = true

	if not found_vepr:
		printerr("    [ОШИБКА] Не найдено упоминание 'ВЕПРЬ-04'")
		ok = false
	if not found_antracit:
		printerr("    [ОШИБКА] Не найдено упоминание 'АНТРАЦИТ'")
		ok = false
	if not found_do_not_wake:
		printerr("    [ОШИБКА] Не найдено ключевое правило 'НЕ БУДИ ЕГО'")
		ok = false
	if not found_fatalities:
		printerr("    [ОШИБКА] Не найдено упоминание о 4 погибших техниках")
		ok = false
	if not found_threshold:
		printerr("    [ОШИБКА] Не найдено упоминание порога нестабильности >70%")
		ok = false

	cutscene.queue_free()
	return ok


func _test_fade_in_and_typewriter() -> bool:
	print("  · Тест 3: Плавный вход (fade-in) и продвижение тайпврайтера")
	var cutscene: CutsceneIntro = CutsceneIntro.new()
	root.add_child(cutscene)

	var ok: bool = true

	# Шаг 1: Симулируем 0.2 сек плавного входа
	cutscene._process(0.2)
	if cutscene.fade_alpha >= 1.0 or cutscene.fade_alpha <= 0.0:
		printerr("    [ОШИБКА] fade_alpha должен уменьшаться при входе: ", cutscene.fade_alpha)
		ok = false

	# Шаг 2: Доводим fade-in до завершения
	cutscene._process(0.35)
	if cutscene.fade_alpha > 0.001 or cutscene.is_fading_in:
		printerr("    [ОШИБКА] fade-in должен завершиться, fade_alpha: ", cutscene.fade_alpha)
		ok = false

	# Шаг 3: Симулируем набор символов
	var initial_char: int = cutscene._current_char_idx
	var initial_line: int = cutscene._current_line_idx
	cutscene._process(0.1)

	if cutscene._current_char_idx == initial_char and cutscene._current_line_idx == initial_line:
		printerr("    [ОШИБКА] Тайпврайтер не продвинулся после _process(0.1)")
		ok = false

	cutscene.queue_free()
	return ok


func _test_instant_skip() -> bool:
	print("  · Тест 4: Мгновенный пропуск набора (finish_typing)")
	var cutscene: CutsceneIntro = CutsceneIntro.new()
	root.add_child(cutscene)

	var ok: bool = true
	cutscene.finish_typing()

	if not cutscene.is_typing_finished:
		printerr("    [ОШИБКА] is_typing_finished должен стать true после finish_typing")
		ok = false
	if cutscene._current_line_idx != cutscene._lines.size() - 1:
		printerr("    [ОШИБКА] _current_line_idx должен указывать на последнюю строку")
		ok = false

	cutscene.queue_free()
	return ok


func _test_exit_fade_and_signal() -> bool:
	print("  · Тест 5: Выходной фейд и сигнал cutscene_completed")
	var cutscene: CutsceneIntro = CutsceneIntro.new()
	root.add_child(cutscene)

	var signal_tracker: Array[bool] = [false]
	cutscene.cutscene_completed.connect(func(): signal_tracker[0] = true)

	cutscene.finish_typing()
	cutscene.start_exit()

	var ok: bool = true
	if not cutscene.is_fading_out:
		printerr("    [ОШИБКА] is_fading_out должен быть true после start_exit()")
		ok = false

	# Симулируем 0.6 сек (длительность фейда 0.5с)
	cutscene._process(0.6)

	if not signal_tracker[0]:
		printerr("    [ОШИБКА] Сигнал cutscene_completed не был отправлен")
		ok = false
	if cutscene.is_active:
		printerr("    [ОШИБКА] is_active должен стать false после завершения катсцены")
		ok = false

	cutscene.queue_free()
	return ok


func _test_input_handling() -> bool:
	print("  · Тест 6: Реакция на нажатия клавиш и клики мыши")
	var cutscene: CutsceneIntro = CutsceneIntro.new()
	root.add_child(cutscene)

	var ok: bool = true

	# 1. Нажатие пробела во время набора -> мгновенный пропуск
	var space_event := InputEventKey.new()
	space_event.pressed = true
	space_event.keycode = KEY_SPACE
	cutscene._input(space_event)

	if not cutscene.is_typing_finished:
		printerr("    [ОШИБКА] Пробел во время набора должен завершить печать")
		ok = false

	# 2. Нажатие пробела после завершения печати -> запуск выхода
	cutscene._input(space_event)
	if not cutscene.is_fading_out:
		printerr("    [ОШИБКА] Пробел после завершения печати должен запустить выход (is_fading_out)")
		ok = false

	cutscene.queue_free()
	return ok


func _test_scene_load() -> bool:
	print("  · Тест 7: Загрузка сцены CutsceneIntro.tscn")
	var scene: PackedScene = load("res://scenes/ui/CutsceneIntro.tscn")
	if scene == null:
		printerr("    [ОШИБКА] Не удалось загрузить res://scenes/ui/CutsceneIntro.tscn")
		return false

	var instance: Node = scene.instantiate()
	if instance == null or not (instance is CutsceneIntro):
		printerr("    [ОШИБКА] Инстанс сцены не является CutsceneIntro")
		return false

	root.add_child(instance)
	var ok: bool = instance.is_active and is_equal_approx(instance.fade_alpha, 1.0)
	instance.queue_free()
	return ok
