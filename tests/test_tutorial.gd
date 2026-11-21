extends SceneTree

## Headless-тесты пошагового обучения: порядок шагов, условия выполнения,
## переход по всей петле, пропуск и сохранение флага «обучение пройдено».

const GameStateScript = preload("res://scripts/core/game_state.gd")
const TutorialScript = preload("res://scripts/ui/tutorial.gd")

var _failures: Array = []
var _checks: int = 0


class StubCardFile extends Node:
	var _open_drawer_id: String = ""
	var _cards_data: Dictionary = {"doc_test": {"drawer": "A"}}

	func get_drawer_button_rect(_id: String) -> Rect2:
		return Rect2(100, 100, 200, 40)

	func get_card_button_rect(_id: String) -> Rect2:
		return Rect2(120, 200, 90, 30)


class StubDocReader extends Node:
	var visible: bool = false

	func get_start_button_rect() -> Rect2:
		return Rect2(300, 500, 200, 40)


class StubScreens extends Node:
	var card_file: Node = null
	var doc_reader: Node = null
	var diagnostics_panel: Node = null
	var part_markers: Node = null


class StubTool extends Node:
	var tool_id: String = "cloth"


class StubMain extends Node:
	var held_tool: Node = null
	var draggable_tools: Dictionary = {}
	var step_runner: Node = null
	var cable_plug: Node = null

	func get_mid_shift() -> Vector2:
		return Vector2.ZERO


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ ОБУЧЕНИЯ ---")
	_test_full_flow()
	_test_skip_and_persist()
	_test_initial_index()

	if _failures.is_empty():
		print("--- ВСЕ ТЕСТЫ ОБУЧЕНИЯ ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
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
			{"id": "s1", "type": "scrub", "tool": "cloth", "label": "Чистка", "time_limit": 20.0,
			 "params": {"rect": [585, 215, 110, 45], "target_ratio": 0.95},
			 "instability": {"success": -4.0, "fail": 6.0, "timeout": 8.0}},
			{"id": "s2", "type": "hold", "tool": "none", "label": "Удержание", "time_limit": 10.0,
			 "params": {"rect": [590, 300, 100, 40], "duration": 0.5},
			 "instability": {"success": -4.0, "fail": 6.0, "timeout": 8.0}}
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
		"title": "ТО-01",
		"tool_list": ["cloth"],
		"time_norm_sec": 30,
		"steps_text": ["Почистить", "Удержать"],
		"order": ["s1", "s2"],
		"safety_protocol": [],
		"notes": []
	}]


func _make_tutorial(state) -> Dictionary:
	var main := StubMain.new()
	root.add_child(main)
	var screens := StubScreens.new()
	screens.card_file = StubCardFile.new()
	screens.add_child(screens.card_file)
	screens.doc_reader = StubDocReader.new()
	screens.add_child(screens.doc_reader)
	root.add_child(screens)
	var tut = TutorialScript.new()
	root.add_child(tut)
	tut._ready()
	tut.save_path = "user://dnw_tutorial_test.cfg"
	tut.bind(main, state, screens)
	return {"tut": tut, "main": main, "screens": screens}


func _cleanup(f: Dictionary, state) -> void:
	var tut: Node = f["tut"]
	var main: Node = f["main"]
	var screens: Node = f["screens"]
	tut.free()
	main.free()
	screens.free()
	state.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://dnw_tutorial_test.cfg"))


func _test_full_flow() -> void:
	var state = GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_fixture_parts(), _fixture_cards())
	state.start_shift()
	var f := _make_tutorial(state)
	var tut = f["tut"]
	var main: StubMain = f["main"]
	var screens: StubScreens = f["screens"]

	tut.start()
	_check(tut.is_active(), "Старт: обучение активно")
	_check(tut._index == 0, "Старт: первый шаг — диагностика")

	state.run_diagnostics()
	tut._process(0.016)
	_check(tut._index == 1, "Диагностика пройдена -> шаг «выбери деталь»")

	state.select_part("test_part")
	tut._process(0.016)
	_check(tut._index == 2, "Деталь выбрана -> шаг «картотека»")

	screens.card_file._open_drawer_id = "A"
	tut._process(0.016)
	_check(tut._index == 3, "Ящик A открыт -> шаг «возьми карточку»")

	screens.doc_reader.visible = true
	tut._process(0.016)
	_check(tut._index == 4, "Карточка открыта -> шаг «регламент»")

	state.read_card("doc_test")
	state.begin_repair()
	tut._process(0.016)
	_check(tut._index == 5, "Ремонт начат -> шаг «инструмент»")

	main.held_tool = StubTool.new()
	main.add_child(main.held_tool)
	tut._process(0.016)
	_check(tut._index == 6, "Ветошь в руке -> шаг «чистка»")

	state.report_step_result(0, true, 1.0)
	tut._process(0.016)
	_check(tut._index == 7, "Первый шаг выполнен -> шаг «питание»")

	state.report_step_result(1, true, 1.0)
	tut._process(0.016)
	_check(tut._index == 8, "Все шаги выполнены -> шаг «замри»")

	state.run_verification()
	tut._process(0.016)
	_check(not tut.is_active(), "Проверка завершена -> обучение закончено")
	_check(tut.is_completed(), "Флаг «обучение пройдено» сохранён")

	_cleanup(f, state)
	_t("Полный проход обучения: 9 шагов, завершение и сохранение флага")


func _test_skip_and_persist() -> void:
	var state = GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_fixture_parts(), _fixture_cards())
	state.start_shift()
	var f := _make_tutorial(state)
	var tut = f["tut"]

	tut.start()
	tut.skip()
	_check(not tut.is_active(), "Пропуск: обучение выключено")
	_check(tut.is_completed(), "Пропуск: флаг сохранён, второй запуск не помешает")

	tut.start_if_needed()
	_check(not tut.is_active(), "start_if_needed не включает обучение после прохождения")

	tut.toggle_manual()
	_check(tut.is_active(), "F2 включает обучение повторно вручную")

	_cleanup(f, state)
	_t("Пропуск: F2 выключает и запоминает, повторный запуск — по F2")


func _test_initial_index() -> void:
	var state = GameStateScript.new()
	state.initialize_game()
	state.setup_loop(_fixture_parts(), _fixture_cards())
	state.start_shift()
	state.run_diagnostics()
	state.select_part("test_part")
	state.read_card("doc_test")
	state.begin_repair()
	var f := _make_tutorial(state)
	var tut = f["tut"]

	tut.start()
	_check(tut._index == 5, "Старт в REPAIR: обучение подхватывает с шага «инструмент», а не с нуля")

	_cleanup(f, state)
	_t("Повторный запуск подхватывает текущую фазу")
