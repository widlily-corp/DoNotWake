extends SceneTree

## Headless-тест картотеки: короткий индекс из GameState не должен затирать
## полную карточку (steps_text/notes), иначе регламент открывается пустым.

const GameStateScript = preload("res://scripts/core/game_state.gd")

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ КАРТОТЕКИ ---")
	var state = GameStateScript.new()
	state.initialize_game()

	var card_file = load("res://scenes/ui/CardFile.tscn").instantiate()
	root.add_child(card_file)
	card_file._ready()

	_check(not card_file._cards_data.is_empty(), "Картотека: карточки загружены с диска")
	var before: Dictionary = card_file._cards_data.get("doc_a04", {})
	_check((before.get("steps_text", []) as Array).size() >= 2, "Картотека: до открытия индекса есть шаги регламента")
	_check((before.get("notes", []) as Array).size() >= 1, "Картотека: до открытия индекса есть особые указания")

	var idx: Dictionary = state.get_documentation_index()
	_check(not idx.is_empty(), "Картотека: индекс документации получен")
	card_file.open(idx)

	var after: Dictionary = card_file._cards_data.get("doc_a04", {})
	_check((after.get("steps_text", []) as Array).size() == (before.get("steps_text", []) as Array).size(), "Картотека: индекс не затёр steps_text полной карточки")
	_check((after.get("notes", []) as Array).size() == (before.get("notes", []) as Array).size(), "Картотека: индекс не затёр notes полной карточки")
	_check((after.get("order", []) as Array).size() >= 2, "Картотека: порядок операций доступен после открытия индекса")

	card_file.close()
	card_file.free()
	state.free()

	if _failures.is_empty():
		print("--- ВСЕ ТЕСТЫ КАРТОТЕКИ ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
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
