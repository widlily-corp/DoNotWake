extends SceneTree

## Автоматизированный модульный тест игрового ядра Do Not Wake

func _init() -> void:
	print("--- ЗАПУСК АВТОТЕСТОВ ИГРОВОГО ЯДРА ---")
	test_balance_loading()
	test_game_loop_and_stages()
	test_instability_and_awake_flow()
	print("--- ВСЕ АВТОТЕСТЫ УСПЕШНО ПРОЙДЕНЫ (0 ОШИБОК) ---")
	quit(0)


func test_balance_loading() -> void:
	var balance := Balance.new()
	assert(balance.data.size() > 0, "Balance data should not be empty")
	assert(balance.get_float("threshold", 0.0) == 70.0, "Threshold should be 70.0")
	assert(balance.get_stages().size() == 3, "There must be 3 stages in robot.json")
	assert(balance.get_tools().size() == 3, "There must be 3 tools in robot.json")
	print("  [OK] Загрузка balance и JSON данных")


func test_game_loop_and_stages() -> void:
	var state := GameState.new()
	state.initialize_game()
	state.start()

	assert(state.current_state == GameState.State.CALM, "Initial state should be CALM")
	assert(state.current_stage_index == 0, "Initial stage should be 0 (clean)")

	# Пробуем починить не тем инструментом на 1 этапе
	state.apply_repair(0, "screwdriver")
	assert(state.robot.instability > 20.0, "Wrong tool should increase instability")

	# Чиним правильным инструментом (cloth)
	state.apply_repair(0, "cloth")
	assert(state.current_stage_index == 1, "Stage should advance to 1 (replace)")

	# Этап 2: чиним отверткой (screwdriver)
	state.apply_repair(0, "screwdriver")
	assert(state.current_stage_index == 2, "Stage should advance to 2 (firmware)")

	# Этап 3: чиним клавиатурой (keyboard)
	state.apply_repair(0, "keyboard")
	assert(state.current_state == GameState.State.DONE, "Game should finish with DONE")
	print("  [OK] Полный цикл 3 стадий ремонта (чистка -> замена -> прошивка)")
	state.free()


func test_instability_and_awake_flow() -> void:
	var state := GameState.new()
	state.initialize_game()
	state.start()

	var initial_threshold := state.robot.threshold

	# Форсируем рост нестабильности выше порога
	state.robot.add_instability(60.0)
	state.tick(0.1)
	assert(state.current_state == GameState.State.AWAKE, "State should be AWAKE when exceeding threshold")

	# Проверяем реакцию на движение мыши
	var prev_inst := state.robot.instability
	state.on_mouse_moved(5.0)
	assert(state.robot.instability > prev_inst, "Mouse movement should increase instability during AWAKE")

	# Успокоение робота
	state.calm_down()
	assert(state.current_state == GameState.State.CALM, "State should return to CALM")
	assert(state.robot.threshold < initial_threshold, "Threshold must decrease after wake")
	print("  [OK] Механика пробуждения, замирания и снижения порога")
	state.free()
