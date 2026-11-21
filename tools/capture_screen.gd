extends SceneTree

## Скрипт детерминированного снятия скриншотов 5 фаз новой петли Do Not Wake (этап 3)
## Сохраняет изображения 1280x720 в docs/preview/ без необходимости ручного ввода.

func _init() -> void:
	print("--- ЗАПУСК ДЕТЕРМИНИРОВАННОГО ЗАХВАТА ФАЗ ПЕТЛИ ---")
	var main_scene = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_scene)
	await process_frame
	await process_frame

	# 0. Синематик-пролог (терминал "Антрацит")
	if main_scene.cutscene_node:
		main_scene.cutscene_node.finish_typing()
	for i in 6:
		await process_frame
	var img_cutscene = root.get_viewport().get_texture().get_image()
	img_cutscene.save_png("docs/preview/screen_cutscene_intro.png")
	print("SUCCESS: Cutscene captured to docs/preview/screen_cutscene_intro.png")

	# Старт новой смены ремонта
	main_scene.start_shift()
	for i in 6:
		await process_frame

	# 1. Фаза 1: Диагностика (docs/preview/screen_loop_diagnostics.png)
	var diag_report = {
		"parts": [
			{
				"id": "srv_04",
				"tag": "A-04",
				"fault_code": "E-217",
				"symptom": "Дрожание манипулятора под нагрузкой",
				"component_name": "Сервопривод плеча"
			}
		],
		"count": 1
	}
	if main_scene.loop_screens and main_scene.loop_screens.diagnostics_panel:
		main_scene.loop_screens.diagnostics_panel.open(diag_report)
	for i in 8:
		await process_frame
	var img_diag = root.get_viewport().get_texture().get_image()
	img_diag.save_png("docs/preview/screen_loop_diagnostics.png")
	print("SUCCESS: 1/5 Diagnostics captured to docs/preview/screen_loop_diagnostics.png")

	# 2. Фаза 2: Выбор детали на роботе (docs/preview/screen_loop_part_select.png)
	if main_scene.game_state:
		main_scene.game_state.run_diagnostics()
	for i in 8:
		await process_frame
	var img_part = root.get_viewport().get_texture().get_image()
	img_part.save_png("docs/preview/screen_loop_part_select.png")
	print("SUCCESS: 2/5 Part select captured to docs/preview/screen_loop_part_select.png")

	# 3. Фаза 3: Поиск документации в картотеке (docs/preview/screen_loop_card_file.png)
	if main_scene.game_state:
		main_scene.game_state.select_part("srv_04")
	for i in 8:
		await process_frame
	var img_cardfile = root.get_viewport().get_texture().get_image()
	img_cardfile.save_png("docs/preview/screen_loop_card_file.png")
	print("SUCCESS: 3/5 Card file captured to docs/preview/screen_loop_card_file.png")

	# 4. Фаза 4: Чтение регламента ремонта (docs/preview/screen_loop_doc_reader.png)
	if main_scene.game_state:
		main_scene.game_state.read_card("doc_a04")
	for i in 8:
		await process_frame
	var img_docreader = root.get_viewport().get_texture().get_image()
	img_docreader.save_png("docs/preview/screen_loop_doc_reader.png")
	print("SUCCESS: 4/5 Doc reader captured to docs/preview/screen_loop_doc_reader.png")

	# 5. Фаза 5: Проверка и штамп ОТК (docs/preview/screen_loop_verify.png)
	if main_scene.game_state:
		main_scene.game_state.begin_repair()
		main_scene.game_state.report_step_result(0, true, 1.0)
		main_scene.game_state.report_step_result(1, true, 1.0)
		main_scene.game_state.tick(3.2)
	for i in 8:
		await process_frame
	var verify_details := {
		"passed": true,
		"steps_ok": 2,
		"total_steps": 2,
		"order_errors": 0,
		"quality_avg": 0.96,
		"time_used": 18.4,
		"attempts": 1
	}
	if main_scene.loop_screens and main_scene.loop_screens.verify_panel:
		main_scene.loop_screens.verify_panel.open(verify_details)
	for i in 8:
		await process_frame
	var img_verify = root.get_viewport().get_texture().get_image()
	img_verify.save_png("docs/preview/screen_loop_verify.png")
	print("SUCCESS: 5/5 Verify captured to docs/preview/screen_loop_verify.png")

	print("--- ВСЕ 5 СКРИНШОТОВ УСПЕШНО СОХРАНЕНЫ В docs/preview/ ---")
	quit(0)
