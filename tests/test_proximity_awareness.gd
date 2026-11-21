extends SceneTree

const ProximityAwareness = preload("res://scripts/interaction/proximity_awareness.gd")

## Автотесты подсистемы Proximity Awareness (Godot 4.7.2).
## Проверяет интерактивную реакцию робота на приближение мыши:
## 1. Наклон головы на 1-2 градуса и напряжение гидравлики.
## 2. Щелчки шагового двигателя в суставах.
## 3. Пульсацию индикатора нестабильности и тремор стрелки.

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ PROXIMITY AWARENESS ---")
	_test_initialization()
	_test_proximity_detection_zones()
	_test_head_tilt_and_hydraulic_strain()
	_test_stepper_motor_clicks()
	_test_instability_pulse_and_needle_jitter()
	_test_configuration_from_balance()
	_test_coordinate_transformation()

	if _failures.is_empty():
		print("--- ВСЕ ТЕСТЫ PROXIMITY AWARENESS ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ПРОВАЛЕНО ТЕСТОВ PROXIMITY AWARENESS: %d из %d проверок ---" % [_failures.size(), _checks])
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


func _test_initialization() -> void:
	_t("Инициализация и базовые параметры зон уязвимости")
	var pa := ProximityAwareness.new()
	_check(pa.enabled, "ProximityAwareness по умолчанию включен")
	_check(pa.zones.size() == 3, "Содержит 3 уязвимые зоны (височный порт, контакты, бронелюк)")
	_check(pa.max_tilt_deg >= 1.0 and pa.max_tilt_deg <= 2.0, "Максимальный наклон в диапазоне 1-2 градуса (текущий: %.1f°)" % pa.max_tilt_deg)
	_check(pa.proximity_factor == 0.0, "Начальный фактор близости равен 0")
	_check(pa.get_tilt_angle() == 0.0, "Начальный угол наклона равен 0")
	_check(pa.get_hydraulic_offset() == Vector2.ZERO, "Начальное смещение гидравлики равно ZERO")


func _test_proximity_detection_zones() -> void:
	_t("Обнаружение приближения мыши к 3 зонам (висок, контакты, люк)")
	var pa := ProximityAwareness.new()

	# 1. Далекая точка: нет реакции
	pa.update(0.016, Vector2(100.0, 100.0), Vector2.ZERO, true)
	_check(pa.proximity_factor == 0.0, "Далекий курсор: фактор близости = 0")
	_check(not pa.is_in_proximity(), "Далекий курсор: is_in_proximity = false")

	# 2. Височный порт: около (640, 160)
	pa.update(0.016, Vector2(640.0, 160.0), Vector2.ZERO, true)
	_check(pa.proximity_factor > 0.95, "Курсор на височном порту: фактор близости ~ 1.0")
	_check(pa.active_zone_id == "temporal_port", "Активная зона - temporal_port")

	# 3. Контакты сервопривода: центр (640, 237.5) внутри Rect2(585, 215, 110, 45)
	pa.update(0.016, Vector2(640.0, 237.0), Vector2.ZERO, true)
	_check(pa.proximity_factor > 0.95, "Курсор на контактах: фактор близости ~ 1.0")
	_check(pa.active_zone_id == "contacts", "Активная зона - contacts")

	# 4. Силовой бронелюк: центр (640, 320) внутри Rect2(570, 275, 140, 90)
	pa.update(0.016, Vector2(640.0, 320.0), Vector2.ZERO, true)
	_check(pa.proximity_factor > 0.95, "Курсор на бронелюке: фактор близости ~ 1.0")
	_check(pa.active_zone_id == "armor_hatch", "Активная зона - armor_hatch")


func _test_head_tilt_and_hydraulic_strain() -> void:
	_t("Отвод головы на 1-2 градуса и напряжение гидравлики")
	var pa := ProximityAwareness.new()

	# Курсор справа от височного порта (x = 670, y = 160)
	# Робот должен отвести голову влево (отрицательный угол в радианах)
	for i in range(30):
		pa.update(0.016, Vector2(670.0, 160.0), Vector2.ZERO, true)

	var tilt_deg := pa.get_tilt_degrees()
	_check(tilt_deg < -0.3, "Курсор справа: голова отводится влево (tilt: %.2f°)" % tilt_deg)
	_check(absf(tilt_deg) <= 2.2, "Угол отвода не превышает пределов 1-2 градусов (tilt: %.2f°)" % tilt_deg)

	# Курсор слева от височного порта (x = 610, y = 160)
	# Робот должен отвести голову вправо (положительный угол)
	for i in range(40):
		pa.update(0.016, Vector2(610.0, 160.0), Vector2.ZERO, true)

	var tilt_deg_right := pa.get_tilt_degrees()
	_check(tilt_deg_right > 0.3, "Курсор слева: голова отводится вправо (tilt: %.2f°)" % tilt_deg_right)

	# Напряжение гидравлики
	var hydr := pa.get_hydraulic_offset()
	_check(hydr.length() > 0.1, "Гидравлика напряжена: смещение != 0 (offset: %s)" % str(hydr))
	_check(hydr.y < 0.0, "Гидравлическое сжатие направлено вверх/назад (y: %.2f)" % hydr.y)

	# Увод курсора -> плавный возврат в ноль
	for i in range(60):
		pa.update(0.016, Vector2(50.0, 50.0), Vector2.ZERO, true)
	_check(absf(pa.get_tilt_degrees()) < 0.05, "После ухода мыши голова возвращается в центр")


func _test_stepper_motor_clicks() -> void:
	_t("Щелчки шагового двигателя в суставах")
	var pa := ProximityAwareness.new()
	var click_stats := [0, 0.0]
	pa.stepper_clicked.connect(func(z_id: String, factor: float, pitch: float):
		click_stats[0] += 1
		click_stats[1] = pitch
	)

	# Вход в зону -> первый немедленный щелчок
	pa.update(0.016, Vector2(640.0, 160.0), Vector2.ZERO, true)
	_check(click_stats[0] >= 1, "При входе в зону раздался щелчок шагового двигателя")
	_check(click_stats[1] >= 1.7, "Питч щелчка повышенный (микро-шаг): %.2f" % click_stats[1])

	# Непрерывное удержание в зоне -> периодические компенсационные микро-шаги
	for i in range(60): # ~1 сек
		pa.update(0.016, Vector2(640.0, 160.0), Vector2.ZERO, true)
	_check(click_stats[0] >= 2, "При удержании мыши суставы продолжают микро-щелчки (всего: %d)" % click_stats[0])


func _test_instability_pulse_and_needle_jitter() -> void:
	_t("Пульсация индикатора нестабильности и нервный тремор стрелки")
	var pa := ProximityAwareness.new()

	# В зоне контакта
	var min_pulse := 1.0
	var max_pulse := 0.0
	var jitter_detected := false

	for i in range(30):
		pa.update(0.016, Vector2(640.0, 237.0), Vector2.ZERO, true)
		var p := pa.get_pulse_intensity()
		var j := pa.get_needle_jitter()
		min_pulse = minf(min_pulse, p)
		max_pulse = maxf(max_pulse, p)
		if absf(j) > 0.005:
			jitter_detected = true

	_check(max_pulse > 0.5, "Индикатор нестабильности слабо пульсирует (max: %.2f)" % max_pulse)
	_check(jitter_detected, "Стрелка манометра испытывает нервный микро-тремор от близости")


func _test_configuration_from_balance() -> void:
	_t("Конфигурирование через Balance и robot.json")
	var pa := ProximityAwareness.new()
	var balance := Balance.new()
	pa.configure(balance, balance.get_robot_layout())
	_check(pa.zones.size() >= 3, "Зоны успешно сконфигурированы")
	_check(pa.max_tilt_deg >= 1.0, "Параметры наклона загружены")


func _test_coordinate_transformation() -> void:
	_t("Трансформация координат точек зоны при наклоне тела")
	var pa := ProximityAwareness.new()
	# Принудительно устанавливаем наклон
	pa.current_tilt_angle = deg_to_rad(1.5)
	pa.hydraulic_offset = Vector2(0.5, -1.0)

	var orig_socket := Vector2(640.0, 160.0)
	var transformed := pa.get_transformed_point(orig_socket, Vector2.ZERO)

	_check(transformed != orig_socket, "Точка сокета сместилась при повороте робота")
	_check(absf(transformed.x - orig_socket.x) > 1.0, "Горизонтальное смещение сокета адекватно углу наклона")
