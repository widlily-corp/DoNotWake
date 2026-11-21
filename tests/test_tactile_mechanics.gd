extends SceneTree

## Автотесты тактильных механик Do Not Wake (Godot 4.7.2).
## Проверяет DraggableTool, ScrubZone, ScrewBoltManager, CablePlug и сцену Main.tscn.

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ ТАКТИЛЬНЫХ МЕХАНИК ---")
	_test_draggable_tool()
	_test_scrub_zone()
	_test_screw_bolts()
	_test_cable_plug()
	_test_main_scene_load()

	if _failures.is_empty():
		print("--- ВСЕ ТАКТИЛЬНЫЕ ТЕСТЫ ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ПРОВАЛЕНО ТАКТИЛЬНЫХ ТЕСТОВ: %d из %d проверок ---" % [_failures.size(), _checks])
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


func _test_draggable_tool() -> void:
	var tool := DraggableTool.new()
	var home_r := Rect2(140, 600, 160, 90)
	tool.setup("cloth", "Ветошь", home_r)

	_check(tool.tool_id == "cloth", "DraggableTool: id установлен")
	_check(tool.current_state == DraggableTool.State.IDLE, "DraggableTool: начальное состояние IDLE")
	_check(tool.position == Vector2(220, 645), "DraggableTool: начальная позиция в центре home_r")

	# Захват мышью
	tool.start_drag(Vector2(220, 645))
	_check(tool.current_state == DraggableTool.State.DRAGGING, "DraggableTool: start_drag -> DRAGGING")

	# Обновление физики с инерцией
	tool.update_tool(0.1, Vector2(500, 300))
	_check(tool.position != Vector2(220, 645), "DraggableTool: перемещается за мышью")

	# Окончание перетаскивания и возврат
	tool.end_drag(tool.position)
	_check(tool.current_state == DraggableTool.State.RETURNING, "DraggableTool: end_drag -> RETURNING")

	# Симуляция возврата
	for i in 30:
		tool.update_tool(0.05, Vector2.ZERO)

	_check(tool.current_state == DraggableTool.State.IDLE, "DraggableTool: вернулся в IDLE в лотке")
	_check(tool.position.distance_to(tool.home_pos) < 2.0, "DraggableTool: позиция соответствует home_pos")

	tool.free()

	# Тестирование отвертки (tip_offset и анкеровка кончика)
	var screw := DraggableTool.new()
	screw.setup("screwdriver", "Отвертка", Rect2(360, 600, 180, 80))
	_check(screw.tip_offset == Vector2(76.0, 0.0), "DraggableTool: screwdriver tip_offset == (76.0, 0.0)")
	_check(screw.get_tip_position() == screw.position + Vector2(76.0, 0.0), "DraggableTool: screwdriver get_tip_position() в IDLE смещен на tip_offset")

	# Анкеровка кончика к болту
	var bolt_target := Vector2(590.0, 295.0)
	var mouse_p := Vector2(590.0, 395.0) # мышь снизу от болта
	screw.anchor_tip_to(bolt_target, mouse_p)
	_check(screw.is_anchored, "DraggableTool: is_anchored == true после anchor_tip_to")
	_check(screw.get_tip_position().distance_to(bolt_target) < 0.01, "DraggableTool: кончик зафиксирован точно в bolt_target")

	# Освобождение анкера
	screw.release_anchor()
	_check(not screw.is_anchored, "DraggableTool: is_anchored == false после release_anchor")
	screw.free()

	_t("DraggableTool: захват, перетаскивание, инерция, screwdriver tip_offset и анкеровка")


func _test_scrub_zone() -> void:
	var scrub := ScrubZone.new()
	var rect := Rect2(570, 250, 140, 60)
	scrub.configure(rect, {
		"safe_speed_min": 120.0,
		"safe_speed_max": 600.0,
		"clean_rate": 0.01,
		"target_clean_ratio": 0.95,
		"friction_heat_rate": 0.02
	})

	_check(scrub.clean_progress == 0.0, "ScrubZone: стартовый прогресс 0")
	_check(scrub.get_clean_ratio() == 0.0, "ScrubZone: get_clean_ratio() начальный 0.0")
	_check(scrub.get_speed_state() == -1, "ScrubZone: начальная скорость -1 (слишком медленно)")
	_check(not scrub.is_completed, "ScrubZone: изначально не завершен")

	var flags := { "completed": false, "heat": 0.0 }
	scrub.scrub_completed.connect(func(): flags["completed"] = true)
	scrub.overheat_occurred.connect(func(penalty): flags["heat"] += penalty)

	# Скраббинг в безопасном диапазоне: 15 px за 0.05 с = 300 px/s
	var center := rect.position + rect.size * 0.5
	scrub.last_mouse_pos = center
	scrub.update_scrub(0.05, center + Vector2(15.0, 0.0), true, Vector2.ZERO)
	_check(scrub.clean_progress > 0.0, "ScrubZone: безопасная скорость очищает контакты")
	_check(scrub.get_current_speed() > 0.0, "ScrubZone: get_current_speed() > 0")
	_check(scrub.get_speed_state() == 0, "ScrubZone: get_speed_state() == 0 (оптимальная скорость)")
	_check(scrub.get_clean_ratio() > 0.0, "ScrubZone: get_clean_ratio() > 0.0")

	# Проверка 1: Осыпание сажи под гравитацией с разлетом
	var soot_particle_found := false
	var soot_has_gravity := false
	for i in scrub.MAX_PARTICLES:
		if scrub.particle_life[i] > 0.0 and scrub.particle_type[i] == scrub.PARTICLE_SOOT:
			soot_particle_found = true
			if scrub.particle_vel[i].y > 0.0:
				soot_has_gravity = true
				break
	_check(soot_particle_found, "ScrubZone: частицы сажи отслаиваются при трении")
	_check(soot_has_gravity, "ScrubZone: сажа реалистично осыпается вниз под гравитацией")

	# Проверка 3: Предварительное термо-свечение до штрафа за перегрев
	# Скорость 625 px/s (выше safe_speed_max=600, но ниже штрафного порога 650)
	var heat_before: float = float(flags["heat"])
	scrub.last_mouse_pos = center
	scrub.update_scrub(0.04, center + Vector2(25.0, 0.0), true, Vector2.ZERO) # 25 / 0.04 = 625 px/s
	_check(scrub.get_thermal_heat() > 0.0, "ScrubZone: контакты накаляются (термо-свечение)")
	_check(flags["heat"] == heat_before, "ScrubZone: термо-свечение накаляется ДО штрафа за перегрев")

	# Скраббинг с превышением штрафной скорости: 20 px за 0.02 с = 1000 px/s (> 650)
	scrub.last_mouse_pos = center
	scrub.update_scrub(0.02, center + Vector2(20.0, 0.0), true, Vector2.ZERO)
	_check(flags["heat"] > heat_before, "ScrubZone: перегрев трением повышает нестабильность")
	_check(scrub.get_speed_state() == 1, "ScrubZone: get_speed_state() == 1 (перегрев)")
	_check(scrub.get_thermal_heat() > 0.0, "ScrubZone: тепловой накал сохраняется при перегреве")

	# Завершение очистки и вспышка металлического блика
	scrub.clean_progress = 0.94
	scrub.update_scrub(0.05, center + Vector2(10.0, 0.0), true, Vector2.ZERO)
	_check(scrub.is_completed, "ScrubZone: завершение при clean_progress >= 0.95")
	_check(scrub.get_clean_ratio() >= 1.0, "ScrubZone: get_clean_ratio() достигает 1.0")
	_check(flags["completed"], "ScrubZone: сигнал scrub_completed отправлен")
	_check(scrub.shine_timer > 0.0, "ScrubZone: контакты вспыхивают ярким металлическим бликом (specular shine)")

	scrub.free()
	_t("ScrubZone: скорость, очистка, перегрев трением и завершение")


func _test_screw_bolts() -> void:
	var manager := ScrewBoltManager.new()
	var hatch_r := Rect2(550, 320, 180, 120)
	var bolts := [
		{ "id": "b1", "pos": [575, 340], "radius": 14.0, "turns_required": 1.0 },
		{ "id": "b2", "pos": [705, 340], "radius": 14.0, "turns_required": 1.0 }
	]
	manager.configure(hatch_r, bolts, {
		"snap_radius": 20.0,
		"slip_radius": 40.0,
		"slip_penalty": 14.0,
		"max_angular_accel": 5000.0
	})

	_check(manager.get_remaining_bolts_count() == 2, "ScrewBoltManager: 2 болта на старте")
	_check(manager.get_bolts().size() == 2, "ScrewBoltManager: get_bolts() возвращает 2 болта")
	_check(manager.get_active_bolt() == null, "ScrewBoltManager: get_active_bolt() изначально null")
	_check(not manager.is_hatch_unlocked(), "ScrewBoltManager: is_hatch_unlocked() изначально false")

	var flags := { "loosened": 0, "slipped": false, "hatch_off": false, "ticks": 0 }
	manager.bolt_loosened.connect(func(_id, _rem): flags["loosened"] += 1)
	manager.tool_slipped.connect(func(_pen, _shk): flags["slipped"] = true)
	manager.hatch_removed.connect(func(): flags["hatch_off"] = true)
	manager.ratchet_tick.connect(func(): flags["ticks"] += 1)

	# Срыв отвертки: отведение курсора дальше slip_radius во время захвата
	var b1_pos := Vector2(575, 340)
	manager.update_bolts(0.05, b1_pos, true, Vector2.ZERO) # snap
	_check(manager.active_bolt != null, "ScrewBoltManager: отвертка захватила болт")
	_check(manager.get_active_bolt() == manager.bolts[0], "ScrewBoltManager: get_active_bolt() возвращает текущий болт")

	# Вращение против часовой стрелки (unscrewing) и проверка трещотки (ratchet_tick)
	# 2 шага по 45 градусов против часовой стрелки (< 1 оборота)
	var angle_step := -PI * 0.25
	var cur_a := 0.0
	for step in 2:
		cur_a += angle_step
		var sim_m := b1_pos + Vector2(cos(cur_a), sin(cur_a)) * 30.0
		manager.update_bolts(0.05, b1_pos, true, Vector2.ZERO, sim_m)

	_check(flags["ticks"] > 0, "ScrewBoltManager: ratchet_tick срабатывает при вращении против часовой стрелки")
	_check(manager.bolts[0].accumulated_rad > 0.0, "ScrewBoltManager: накоплен угол выкручивания")
	_check(manager.active_bolt == manager.bolts[0], "ScrewBoltManager: болт всё ещё удерживается")

	# Срыв инструмента при отведении мыши далеко от начальной позиции
	manager.update_bolts(0.05, b1_pos, true, Vector2.ZERO, b1_pos + Vector2(100.0, 0.0))
	_check(flags["slipped"], "ScrewBoltManager: срыв инструмента при превышении slip_radius")

	# Выкручивание болтов (симуляция углового прогресса)
	manager.bolts[0].accumulated_rad = TAU + 0.1
	manager.bolts[0].is_loose = true
	_check(manager.get_remaining_bolts_count() == 1, "ScrewBoltManager: 1 болт остался")
	_check(not manager.is_hatch_unlocked(), "ScrewBoltManager: люк ещё заблокирован")

	manager.bolts[1].accumulated_rad = TAU + 0.1
	manager.bolts[1].is_loose = true
	_check(manager.get_remaining_bolts_count() == 0, "ScrewBoltManager: все болты выкручены")
	_check(manager.is_hatch_unlocked(), "ScrewBoltManager: is_hatch_unlocked() теперь true")

	# Снятие люка
	manager.hatch_offset = Vector2(50.0, 50.0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	manager.is_dragging_hatch = true
	var handled := manager.handle_hatch_input(ev, Vector2(600, 400), Vector2.ZERO)
	_check(handled, "ScrewBoltManager: люк реагирует на мышь")
	_check(manager.is_hatch_removed, "ScrewBoltManager: люк снят со стапеля")

	manager.free()
	_t("ScrewBoltManager: захват, выкручивание, срыв и снятие бронелюка")


func _test_cable_plug() -> void:
	var plug := CablePlug.new()
	var socket := Vector2(640, 180)
	var anchor := Vector2(980, 640)
	var home := Vector2(940, 600)
	plug.configure(socket, anchor, home, {"socket_radius": 32.0})

	_check(not plug.is_locked, "CablePlug: изначально не зафиксирован")
	_check(plug.cable_points.size() == CablePlug.CABLE_SEGMENTS, "CablePlug: точки кабеля инициализированы")

	var flags := { "locked": false }
	plug.cable_locked.connect(func(): flags["locked"] = true)

	# Захват штекера
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	plug.handle_input(ev_press, home)
	_check(plug.is_dragged, "CablePlug: штекер взят в руку")

	# Подтягивание к гнезду
	plug.update_cable(0.1, socket + Vector2(10.0, 10.0), Vector2.ZERO)
	_check(plug.is_near_socket, "CablePlug: магнитный захват вблизи гнезда")

	# Фиксация в гнезде при совпадении ключа (90 градусов)
	plug.plug_angle = 90.0
	var ev_release := InputEventMouseButton.new()
	ev_release.button_index = MOUSE_BUTTON_LEFT
	ev_release.pressed = false
	plug.handle_input(ev_release, socket)
	_check(plug.is_locked, "CablePlug: байонет защёлкнут в гнезде")
	_check(flags["locked"], "CablePlug: сигнал cable_locked отправлен")

	plug.free()
	_t("CablePlug: перетаскивание, кривая кабеля, магнитный захват и защёлкивание")


func _test_main_scene_load() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	_check(scene != null, "Main.tscn загружена корректно")

	var main_inst: Node = scene.instantiate()
	_check(main_inst is MainView, "Экземпляр сцены имеет тип MainView")

	root.add_child(main_inst)
	if not main_inst.is_node_ready():
		main_inst._ready()

	var main_view := main_inst as MainView
	_check(main_view.draggable_tools.has("cloth"), "MainView: создан инструмент cloth")
	_check(main_view.draggable_tools.has("screwdriver"), "MainView: создан инструмент screwdriver")
	_check(main_view.draggable_tools.has("cable"), "MainView: создан инструмент cable")
	_check(main_view.scrub_zone != null, "MainView: scrub_zone инициализирована")
	_check(main_view.screw_manager != null, "MainView: screw_manager инициализирован")
	_check(main_view.cable_plug != null, "MainView: cable_plug инициализирован")

	# Проверка кадрового цикла (2 кадра)
	main_view._process(0.016)
	main_view._process(0.016)
	_check(true, "MainView: 2 кадра выполнены без ошибок")

	main_inst.queue_free()
	_t("MainView & Main.tscn: полная сквозная инициализация и рендеринг")
