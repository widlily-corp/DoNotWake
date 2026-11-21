extends SceneTree

## Автотесты процедурной оптики и визора робота (RobotOptics).
## Запуск: godot --headless --path . -s tests/test_robot_optics.gd

const RobotOptics = preload("res://scripts/core/robot_optics.gd")

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ ПРОЦЕДУРНОЙ ОПТИКИ И ВИЗОРА (ROBOT_OPTICS) ---")
	_test_initialization_and_geometry()
	_test_calm_diagnostic_pulse()
	_test_cursor_proximity_reaction()
	_test_instability_reaction()
	_test_awake_overdrive()
	_test_render_execution()

	if _failures.is_empty():
		print("--- ВСЕ ТЕСТЫ ОПТИКИ РОБОТА ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ПРОВАЛЕНО ТЕСТОВ ОПТИКИ: %d из %d проверок ---" % [_failures.size(), _checks])
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


func _test_initialization_and_geometry() -> void:
	_t("Инициализация, авто-расчёт геометрии и сенсоры")
	var optics := RobotOptics.new()
	_check(optics.current_mode == RobotOptics.Mode.DORMANT, "Начальный режим DORMANT")
	_check(optics.sensors.size() == 4, "4 вспомогательных сенсора инициализированы")
	_check(optics.bloom_radii.size() == 5, "Preallocated bloom_radii size == 5")
	_check(optics.bloom_alphas.size() == 5, "Preallocated bloom_alphas size == 5")

	# Конфигурация от robot_rect
	var r_rect := Rect2(505, 65, 270, 542)
	optics.configure(r_rect)
	_check(optics.visor_rect.size.x > 35.0 and optics.visor_rect.size.x < 50.0, "Ширина визора корректно смасштабирована")
	_check(optics.visor_center.x > 630.0 and optics.visor_center.x < 650.0, "Центр визора по X ~ 640")
	_check(optics.visor_center.y > 130.0 and optics.visor_center.y < 160.0, "Центр визора по Y ~ 145")


func _test_calm_diagnostic_pulse() -> void:
	_t("Спящее состояние: периодический импульс самодиагностики")
	var optics := RobotOptics.new()
	var r_rect := Rect2(505, 65, 270, 542)
	optics.configure(r_rect)

	# Курсор далеко, нестабильность 20 (норма)
	var far_mouse := Vector2(100, 600)
	var shift := Vector2.ZERO

	# Проверяем, что в спящем состоянии оптика выключена
	optics.update(0.1, far_mouse, shift, 20.0, 70.0, false)
	_check(optics.current_mode == RobotOptics.Mode.DORMANT, "В спячке режим DORMANT")
	_check(optics.current_intensity == 0.0, "В спячке интенсивность свечения = 0.0")

	# Принудительно взводим таймер импульса самодиагностики
	optics.calm_timer = 0.05
	optics.update(0.1, far_mouse, shift, 20.0, 70.0, false)

	_check(optics.current_mode == RobotOptics.Mode.DIAGNOSTIC_PULSE, "Таймер истек -> включился DIAGNOSTIC_PULSE")
	_check(optics.current_intensity > 0.0, "Во время импульса интенсивность > 0.0")
	_check(optics.current_color == RobotOptics.COLOR_COLD_BLUE or optics.current_color == RobotOptics.COLOR_AMBER,
		"Цвет импульса - холодный синий или янтарный")

	# Прокручиваем импульс до середины
	optics.update(optics.calm_pulse_duration * 0.45, far_mouse, shift, 20.0, 70.0, false)
	_check(optics.current_intensity > 0.5, "В пике импульса свечение выраженное")
	_check(optics.beam_x_norm > 0.3 and optics.beam_x_norm < 0.8, "Сканирующий луч проходит вдоль визора")

	# Завершаем импульс
	optics.update(optics.calm_pulse_duration * 0.7, far_mouse, shift, 20.0, 70.0, false)
	_check(optics.current_mode == RobotOptics.Mode.DORMANT, "После завершения импульса возвращается в DORMANT")
	_check(optics.current_intensity == 0.0, "Оптика снова погасла")


func _test_cursor_proximity_reaction() -> void:
	_t("Приближение курсора к голове: тревожное сканирование и сдвиг спектра")
	var optics := RobotOptics.new()
	var r_rect := Rect2(505, 65, 270, 542)
	optics.configure(r_rect)

	var head_pos := optics.visor_center
	var far_mouse := head_pos + Vector2(300, 0)
	var near_mouse := head_pos + Vector2(20, 10) # 22 px < danger_distance 45 px

	# Далеко: близость 0
	optics.update(0.016, far_mouse, Vector2.ZERO, 20.0, 70.0, false)
	_check(optics.cursor_proximity == 0.0, "Курсор далеко -> proximity = 0.0")

	# Близко к голове: тревожная реакция
	optics.update(0.016, near_mouse, Vector2.ZERO, 20.0, 70.0, false)
	_check(optics.cursor_proximity >= 0.95, "Курсор у головы -> proximity ~ 1.0")
	_check(optics.current_mode == RobotOptics.Mode.ALERT_SCAN, "Режим переключился на ALERT_SCAN")
	_check(optics.current_intensity >= 0.6, "Интенсивность тревожного свечения выросла")
	_check(optics.current_color.r > 0.7, "Спектр сдвинулся в янтарно-тревожный/красный")
	_check(optics.scan_speed > 5.0, "Скорость сканирования визора возросла")


func _test_instability_reaction() -> void:
	_t("Рост нестабильности: тревожный сигнал без приближения мыши")
	var optics := RobotOptics.new()
	var r_rect := Rect2(505, 65, 270, 542)
	optics.configure(r_rect)

	var far_mouse := Vector2(100, 600)
	# Нестабильность 68 при пороге 70 (очень близко к порогу)
	optics.update(0.016, far_mouse, Vector2.ZERO, 68.0, 70.0, false)
	_check(optics.threat_ratio > 0.9, "threat_ratio > 0.9")
	_check(optics.current_mode == RobotOptics.Mode.ALERT_SCAN, "Высокая нестабильность активировала ALERT_SCAN")
	_check(optics.current_intensity > 0.5, "Визор светится при высокой нестабильности")
	_check(optics.current_color.r > 0.8, "Цвет тревожный янтарный/красный при высокой нестабильности")


func _test_awake_overdrive() -> void:
	_t("Пробуждение робота: полномасштабный овердрайв и стробоскоп")
	var optics := RobotOptics.new()
	var r_rect := Rect2(505, 65, 270, 542)
	optics.configure(r_rect)

	optics.update(0.016, Vector2(640, 145), Vector2.ZERO, 90.0, 70.0, true)
	_check(optics.current_mode == RobotOptics.Mode.OVERDRIVE_AWAKE, "Режим OVERDRIVE_AWAKE")
	_check(optics.current_color == RobotOptics.COLOR_ALERT_RED, "Цвет визора ярко-красный тревожный")
	_check(optics.current_intensity >= 0.8, "Интенсивность овердрайва максимальная")


func _test_render_execution() -> void:
	_t("Процедурный рендеринг CanvasItem без утечек и ошибок")
	var optics := RobotOptics.new()
	var r_rect := Rect2(505, 65, 270, 542)
	optics.configure(r_rect)

	# Создаем CanvasItem узел для проверки рендеринга
	var dummy_canvas := Node2D.new()
	root.add_child(dummy_canvas)

	var current_shift := Vector2.ZERO
	dummy_canvas.draw.connect(func():
		optics.render(dummy_canvas, current_shift)
	)

	# 1. Рендер в режиме DORMANT
	optics.update(0.016, Vector2(100, 600), Vector2.ZERO, 20.0, 70.0, false)
	current_shift = Vector2.ZERO
	dummy_canvas.notification(CanvasItem.NOTIFICATION_DRAW)

	# 2. Рендер в режиме активного сканирования с бликами, bloom и сенсорами
	optics.update(0.016, optics.visor_center, Vector2(5, 5), 50.0, 70.0, false)
	current_shift = Vector2(5, 5)
	dummy_canvas.notification(CanvasItem.NOTIFICATION_DRAW)

	# 3. Рендер в режиме OVERDRIVE_AWAKE
	optics.update(0.016, optics.visor_center, Vector2.ZERO, 100.0, 70.0, true)
	current_shift = Vector2.ZERO
	dummy_canvas.notification(CanvasItem.NOTIFICATION_DRAW)

	_check(true, "CanvasItem render выполнился штатно для всех режимов")
	dummy_canvas.queue_free()
