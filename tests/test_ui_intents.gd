extends SceneTree

## Автотест UI-экранов новой петли и координатора LoopScreens
## Проверяет инстанцирование, open/close, перехват кликов, сигналы и bind(GameState)

var _failures: Array = []
var _checks: int = 0


class MockGameState extends Node:
	signal phase_changed(phase: int)
	signal diagnostics_ready(report: Dictionary)
	signal part_selected(part_id: String, correct: bool)
	signal documentation_requested()
	signal document_read(card_id: String, correct: bool)
	signal repair_started(part_id: String, steps: Array)
	signal threat_changed(level: int, instability: float)
	signal wake_started(duration: float)
	signal wake_ended()
	signal pause_changed(paused: bool, reason: String)
	signal verification_finished(passed: bool, details: Dictionary)
	signal shift_finished(success: bool, stats: Dictionary)

	var calls: Array = []
	var report_to_return: Dictionary = {
		"parts": [
			{
				"id": "srv_04",
				"tag": "A-04",
				"fault_code": "E-217",
				"symptom": "Дрожание манипулятора",
				"component_name": "Сервопривод плеча",
				"tag_pos": [612, 236]
			}
		]
	}
	var doc_index_to_return: Dictionary = {
		"drawers": [{"id": "A", "label": "Приводы", "cards": ["doc_a04"]}]
	}
	var card_to_return: Dictionary = {
		"id": "doc_a04",
		"tag": "A-04",
		"title": "ТО-04. Сервопривод",
		"tool_list": ["cloth", "cable"],
		"time_norm_sec": 60,
		"steps_text": ["Шаг 1", "Шаг 2"]
	}

	func run_diagnostics() -> Dictionary:
		calls.append("run_diagnostics")
		emit_signal("diagnostics_ready", report_to_return)
		return report_to_return

	func get_diagnostics_report() -> Dictionary:
		calls.append("get_diagnostics_report")
		return report_to_return

	func select_part(part_id: String) -> bool:
		calls.append("select_part:" + part_id)
		var correct := (part_id == "srv_04")
		emit_signal("part_selected", part_id, correct)
		return correct

	func request_documentation() -> void:
		calls.append("request_documentation")
		emit_signal("documentation_requested")

	func get_documentation_index() -> Dictionary:
		calls.append("get_documentation_index")
		return doc_index_to_return

	func read_card(card_id: String) -> Dictionary:
		calls.append("read_card:" + card_id)
		var correct := (card_id == "doc_a04")
		emit_signal("document_read", card_id, correct)
		return card_to_return if correct else {}

	func begin_repair() -> bool:
		calls.append("begin_repair")
		emit_signal("repair_started", "srv_04", [])
		return true

	func request_pause(reason: String = "") -> void:
		calls.append("request_pause:" + reason)
		emit_signal("pause_changed", true, reason)

	func request_resume() -> void:
		calls.append("request_resume")
		emit_signal("pause_changed", false, "")

	func run_verification() -> bool:
		calls.append("run_verification")
		emit_signal("verification_finished", true, {"passed": true, "quality": 1.0})
		return true


func _init() -> void:
	print("--- ЗАПУСК АВТОТЕСТОВ UI И КООРДИНАТОРА LOOPSCREENS ---")
	_test_instantiation_and_empty_open_close()
	_test_diagnostics_panel_signals()
	_test_part_markers_intents()
	_test_card_file_intents()
	_test_doc_reader_intents()
	_test_threat_overlay_intents()
	_test_verify_panel_intents()
	_test_dimensions_and_hud_clearing()
	_test_loopscreens_bind_and_phase_transitions()
	_test_wake_closes_and_restores_modal()
	_test_intent_forwarding_from_screens()

	if _failures.is_empty():
		print("--- ВСЕ АВТОТЕСТЫ UI ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ПРОВАЛЕНО ТЕСТОВ: %d из %d ---" % [_failures.size(), _checks])
		for f in _failures:
			printerr("  [FAIL] %s" % f)
		quit(1)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)


func _test_instantiation_and_empty_open_close() -> void:
	# 1. DiagnosticsPanel
	var diag_scn := load("res://scenes/ui/DiagnosticsPanel.tscn")
	_check(diag_scn != null, "Сцена DiagnosticsPanel.tscn загружается")
	var diag: DiagnosticsPanel = diag_scn.instantiate()
	_check(diag != null, "DiagnosticsPanel успешно инстанцируется")
	diag.open({})
	_check(diag.visible, "DiagnosticsPanel.open({}) открывается на пустых данных")
	diag.close()
	_check(not diag.visible, "DiagnosticsPanel.close() закрывается")
	diag.free()

	# 2. CardFile
	var card_scn := load("res://scenes/ui/CardFile.tscn")
	_check(card_scn != null, "Сцена CardFile.tscn загружается")
	var card: CardFile = card_scn.instantiate()
	_check(card != null, "CardFile успешно инстанцируется")
	card.open()
	_check(card.visible, "CardFile.open() открывается")
	card.close()
	_check(not card.visible, "CardFile.close() закрывается")
	card.free()

	# 3. DocReader
	var doc_scn := load("res://scenes/ui/DocReader.tscn")
	_check(doc_scn != null, "Сцена DocReader.tscn загружается")
	var doc: DocReader = doc_scn.instantiate()
	_check(doc != null, "DocReader успешно инстанцируется")
	doc.open({})
	_check(doc.visible, "DocReader.open({}) открывается на пустых данных")
	doc.close()
	_check(not doc.visible, "DocReader.close() закрывается")
	doc.free()

	# 4. VerifyPanel
	var ver_scn := load("res://scenes/ui/VerifyPanel.tscn")
	_check(ver_scn != null, "Сцена VerifyPanel.tscn загружается")
	var ver: VerifyPanel = ver_scn.instantiate()
	_check(ver != null, "VerifyPanel успешно инстанцируется")
	ver.open({})
	_check(ver.visible, "VerifyPanel.open({}) открывается на пустых данных")
	ver.close()
	_check(not ver.visible, "VerifyPanel.close() закрывается")
	ver.free()

	# 5. ThreatOverlay
	var thr_scn := load("res://scenes/ui/ThreatOverlay.tscn")
	_check(thr_scn != null, "Сцена ThreatOverlay.tscn загружается")
	var thr: ThreatOverlay = thr_scn.instantiate()
	_check(thr != null, "ThreatOverlay успешно инстанцируется")
	thr.show_wake(2.0)
	_check(thr.is_wake_active(), "ThreatOverlay.show_wake активирует пробуждение")
	thr.hide_wake()
	_check(not thr.is_wake_active(), "ThreatOverlay.hide_wake деактивирует пробуждение")
	thr.free()

	# 6. PartMarkers
	var pm: PartMarkers = PartMarkers.new()
	_check(pm != null, "PartMarkers успешно инстанцируется")
	pm.show_for([])
	_check(pm.visible, "PartMarkers.show_for([]) работает без падения")
	pm.hide_all()
	_check(not pm.visible, "PartMarkers.hide_all() скрывает метки")
	pm.free()


func _test_diagnostics_panel_signals() -> void:
	var diag_scn := load("res://scenes/ui/DiagnosticsPanel.tscn")
	var diag: DiagnosticsPanel = diag_scn.instantiate()
	root.add_child(diag)
	diag._ensure_nodes()

	var scan_emitted := [false]
	diag.scan_requested.connect(func(): scan_emitted[0] = true)
	diag._on_scan_pressed()
	_check(scan_emitted[0], "DiagnosticsPanel эмитит scan_requested при нажатии 'Сканировать'")

	var closed_emitted := [false]
	diag.closed.connect(func(): closed_emitted[0] = true)
	diag.close()
	_check(closed_emitted[0], "DiagnosticsPanel эмитит closed при закрытии")

	# Проверка передачи отчёта с кодами неисправностей (E-217)
	diag.open({
		"faults": [
			{"code": "E-217", "symptom": "Дрожание манипулятора под нагрузкой"}
		]
	})
	_check(diag.count_label != null and diag.count_label.text.contains("1"), "DiagnosticsPanel корректно отображает счётчик неисправностей")

	diag.free()


func _test_part_markers_intents() -> void:
	var pm: PartMarkers = PartMarkers.new()
	root.add_child(pm)

	var clicked_id := [""]
	var click_count := [0]
	pm.part_clicked.connect(func(pid: String):
		clicked_id[0] = pid
		click_count[0] += 1
	)

	pm.show_for([
		{
			"id": "srv_04",
			"tag": "A-04",
			"component_name": "Сервопривод плечевого шарнира",
			"tag_pos": [612, 236]
		}
	])

	_check(pm.visible, "PartMarkers виден после show_for")
	pm.click_part("srv_04")
	_check(clicked_id[0] == "srv_04", "Клик по метке отдаёт part_clicked('srv_04')")
	_check(click_count[0] == 1, "Эмиссия клика произошла ровно 1 раз")

	# Повторный клик по выбранной игнорируется
	pm.select_part("srv_04")
	pm.click_part("srv_04")
	_check(click_count[0] == 1, "Повторный клик по выбранной детали игнорируется")

	pm.free()


func _test_card_file_intents() -> void:
	var card_scn := load("res://scenes/ui/CardFile.tscn")
	var card_file: CardFile = card_scn.instantiate()
	root.add_child(card_file)
	card_file._ensure_nodes()

	var taken_id := [""]
	var taken_count := [0]
	card_file.card_taken.connect(func(cid: String):
		taken_id[0] = cid
		taken_count[0] += 1
	)

	card_file.open({
		"drawers": [{"id": "A", "label": "Приводы", "cards": ["doc_a04"]}],
		"cards": [{"id": "doc_a04", "tag": "A-04", "title": "ТО-04"}]
	})

	card_file.select_card("doc_a04")
	_check(taken_id[0] == "doc_a04", "CardFile эмитит card_taken с правильным ID")
	_check(taken_count[0] == 1, "card_taken эмитится ровно один раз")

	# Повторный выбор без reopen не дублирует сигнал
	card_file.select_card("doc_a04")
	_check(taken_count[0] == 1, "Повторный выбор не дублирует card_taken")

	var closed_emitted := [false]
	card_file.closed.connect(func(): closed_emitted[0] = true)
	card_file.close()
	_check(closed_emitted[0], "CardFile эмитит closed при close()")

	card_file.free()


func _test_doc_reader_intents() -> void:
	var doc_scn := load("res://scenes/ui/DocReader.tscn")
	var doc_reader: DocReader = doc_scn.instantiate()
	root.add_child(doc_reader)
	doc_reader._ensure_nodes()

	var repair_emitted := [false]
	var repair_count := [0]
	doc_reader.repair_requested.connect(func():
		repair_emitted[0] = true
		repair_count[0] += 1
	)

	doc_reader.open({
		"tag": "A-04",
		"title": "ТО-04. Сервопривод",
		"tool_list": ["cloth", "cable"],
		"time_norm_sec": 60,
		"safety_protocol": ["Обесточить контур"],
		"steps_text": ["Очистить контакты", "Подать питание"],
		"notes": ["Скорость чистки <= 600 px/с"]
	})

	doc_reader._on_start_repair_pressed()
	_check(repair_emitted[0], "DocReader эмитит repair_requested по кнопке 'Начать ремонт'")
	_check(repair_count[0] == 1, "repair_requested эмитится ровно один раз")

	# Повторный клик не дублирует
	doc_reader._on_start_repair_pressed()
	_check(repair_count[0] == 1, "Повторный клик не дублирует repair_requested")

	var closed_emitted := [false]
	doc_reader.closed.connect(func(): closed_emitted[0] = true)
	doc_reader.close()
	_check(closed_emitted[0], "DocReader эмитит closed при close()")

	doc_reader.free()


func _test_threat_overlay_intents() -> void:
	var thr_scn := load("res://scenes/ui/ThreatOverlay.tscn")
	var thr: ThreatOverlay = thr_scn.instantiate()
	root.add_child(thr)
	thr._ensure_nodes()

	var pause_emitted := [false]
	thr.pause_requested.connect(func(): pause_emitted[0] = true)
	thr._on_pause_pressed()
	_check(pause_emitted[0], "ThreatOverlay эмитит pause_requested")

	var resume_emitted := [false]
	thr.resume_requested.connect(func(): resume_emitted[0] = true)
	thr._on_resume_pressed()
	_check(resume_emitted[0], "ThreatOverlay эмитит resume_requested")

	thr.show_wake(4.0)
	_check(thr.is_wake_active(), "Пробуждение активно")
	_check(thr.wake_overlay != null and thr.wake_overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "Пробуждение блокирует ввод (mouse_filter = STOP)")

	thr.free()


func _test_verify_panel_intents() -> void:
	var ver_scn := load("res://scenes/ui/VerifyPanel.tscn")
	var ver: VerifyPanel = ver_scn.instantiate()
	root.add_child(ver)
	ver._ensure_nodes()

	var confirmed_result := [false]
	var confirmed_count := [0]
	ver.confirmed.connect(func(passed: bool):
		confirmed_result[0] = passed
		confirmed_count[0] += 1
	)

	ver.open({"passed": true, "quality": 1.0})
	ver._on_confirm_pressed()
	_check(confirmed_result[0] == true, "VerifyPanel эмитит confirmed(true) для успешного теста")
	_check(confirmed_count[0] == 1, "confirmed эмитится ровно один раз")

	ver.free()


func _test_dimensions_and_hud_clearing() -> void:
	# Проверка геометрии по контрактам (1280x720)
	var diag_scn := load("res://scenes/ui/DiagnosticsPanel.tscn")
	var diag: DiagnosticsPanel = diag_scn.instantiate()
	root.add_child(diag)
	diag._ensure_nodes()
	_check(diag.panel_root != null and diag.panel_root.size.x <= 960 and diag.panel_root.size.y <= 420, "DiagnosticsPanel не превышает 960x420")
	diag.close()
	_check(not diag.visible, "DiagnosticsPanel скрыт и не блокирует экран")
	diag.free()

	var card_scn := load("res://scenes/ui/CardFile.tscn")
	var card: CardFile = card_scn.instantiate()
	root.add_child(card)
	card._ensure_nodes()
	_check(card.cabinet != null and card.cabinet.size.x <= 680, "CardFile ширина <= 680 px слева экрана")
	card.free()

	var doc_scn := load("res://scenes/ui/DocReader.tscn")
	var doc: DocReader = doc_scn.instantiate()
	root.add_child(doc)
	doc._ensure_nodes()
	_check(doc.sheet != null and doc.sheet.size.x <= 680, "DocReader ширина <= 680 px")
	doc.free()


func _test_loopscreens_bind_and_phase_transitions() -> void:
	var ls: LoopScreens = LoopScreens.new()
	root.add_child(ls)

	var mock_gs := MockGameState.new()
	root.add_child(mock_gs)

	ls.bind(mock_gs)

	# 1. Фаза DIAGNOSTICS: открывает diagnostics_panel
	mock_gs.emit_signal("phase_changed", LoopScreens.Phase.DIAGNOSTICS)
	_check(ls.diagnostics_panel.visible, "LoopScreens открывает DiagnosticsPanel при Phase.DIAGNOSTICS")
	_check(not ls.card_file.visible, "CardFile закрыт в фазе DIAGNOSTICS")

	# 2. Фаза PART_SELECT: закрывает diagnostics_panel, открывает part_markers
	mock_gs.emit_signal("phase_changed", LoopScreens.Phase.PART_SELECT)
	_check(not ls.diagnostics_panel.visible, "DiagnosticsPanel закрыт в Phase.PART_SELECT")
	_check(ls.part_markers.visible, "PartMarkers открыт в Phase.PART_SELECT")

	# 3. Фаза DOC_SEARCH: открывает card_file, скрывает part_markers
	mock_gs.emit_signal("phase_changed", LoopScreens.Phase.DOC_SEARCH)
	_check(ls.card_file.visible, "CardFile открыт в Phase.DOC_SEARCH")
	_check(not ls.part_markers.visible, "PartMarkers скрыт в Phase.DOC_SEARCH")

	# 4. Фаза REPAIR: закрывает картотеку, включает кнопку паузы
	mock_gs.emit_signal("phase_changed", LoopScreens.Phase.REPAIR)
	_check(not ls.card_file.visible, "CardFile закрыт в Phase.REPAIR")
	_check(ls.threat_overlay.pause_btn_hud.visible, "HUD кнопка паузы видна в Phase.REPAIR")

	# 5. Фаза VERIFY: открывает verify_panel
	mock_gs.emit_signal("phase_changed", LoopScreens.Phase.VERIFY)
	_check(ls.verify_panel.visible, "VerifyPanel открыт в Phase.VERIFY")

	ls.free()
	mock_gs.free()


func _test_wake_closes_and_restores_modal() -> void:
	var ls: LoopScreens = LoopScreens.new()
	root.add_child(ls)
	var mock_gs := MockGameState.new()
	root.add_child(mock_gs)
	ls.bind(mock_gs)

	# Открываем DOC_SEARCH
	mock_gs.emit_signal("phase_changed", LoopScreens.Phase.DOC_SEARCH)
	_check(ls.card_file.visible, "CardFile изначально открыт")

	# Пробуждение
	mock_gs.emit_signal("wake_started", 4.0)
	_check(ls.threat_overlay.is_wake_active(), "ThreatOverlay активен при wake_started")
	_check(not ls.card_file.visible, "CardFile временно скрыт во время пробуждения")

	# Конец пробуждения
	mock_gs.emit_signal("wake_ended")
	_check(not ls.threat_overlay.is_wake_active(), "ThreatOverlay не активен после wake_ended")
	_check(ls.card_file.visible, "CardFile восстановлен после завершения пробуждения")

	ls.free()
	mock_gs.free()


func _test_intent_forwarding_from_screens() -> void:
	var ls: LoopScreens = LoopScreens.new()
	root.add_child(ls)
	var mock_gs := MockGameState.new()
	root.add_child(mock_gs)
	ls.bind(mock_gs)

	mock_gs.calls.clear()

	# Интент сканирования
	ls.diagnostics_panel.emit_signal("scan_requested")
	_check(mock_gs.calls.has("run_diagnostics"), "scan_requested пересылается в GameState.run_diagnostics")

	# Интент выбора детали
	ls.part_markers.emit_signal("part_clicked", "srv_04")
	_check(mock_gs.calls.has("select_part:srv_04"), "part_clicked пересылается в GameState.select_part")

	# Интент выбора карточки
	ls.card_file.emit_signal("card_taken", "doc_a04")
	_check(mock_gs.calls.has("read_card:doc_a04"), "card_taken пересылается в GameState.read_card")

	# Интент запроса ремонта
	ls.doc_reader.emit_signal("repair_requested")
	_check(mock_gs.calls.has("begin_repair"), "repair_requested пересылается в GameState.begin_repair")

	# Интент паузы
	ls.threat_overlay.emit_signal("pause_requested")
	_check(mock_gs.calls.has("request_pause:manual"), "pause_requested пересылается в GameState.request_pause")

	# Интент возобновления
	ls.threat_overlay.emit_signal("resume_requested")
	_check(mock_gs.calls.has("request_resume"), "resume_requested пересылается в GameState.request_resume")

	# Интент проверки
	ls.verify_panel.emit_signal("confirmed", true)
	_check(mock_gs.calls.has("run_verification"), "confirmed пересылается в GameState.run_verification")

	ls.free()
	mock_gs.free()
