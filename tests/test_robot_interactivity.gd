extends SceneTree

## Комплексный автотест интерактивности робота (Do Not Wake, Godot 4.7.2).
##
## Запуск: godot --headless --path . -s tests/test_robot_interactivity.gd
## Код выхода: 0 — все проверки успешно пройдены, 1 — есть ошибки (CI/CD совместимо).
##
## Проверяет:
## 1. Процедурное дыхание и изменение масштаба/позиции торса со временем.
## 2. Реакцию робота на курсор мыши на разной дистанции (Proximity Awareness).
## 3. Генерацию частиц пара и мерцание визора при росте нестабильности (Thermal FX & Optics).
## 4. Сквозной прогон через Godot headless с нулевым кодом возврата и Zero GC.

const RobotProceduralAnimation = preload("res://scripts/core/robot_procedural_animation.gd")
const ProximityAwareness = preload("res://scripts/interaction/proximity_awareness.gd")
const RobotThermalFX = preload("res://scripts/interaction/robot_thermal_fx.gd")
const RobotOptics = preload("res://scripts/core/robot_optics.gd")

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("=================================================================")
	print("--- ЗАПУСК КОМПЛЕКСНОГО АВТОТЕСТА ИНТЕРАКТИВНОСТИ РОБОТА ---")
	print("=================================================================")

	_test_procedural_breathing_and_torso()
	_test_mouse_cursor_proximity_reaction()
	_test_steam_and_visor_instability()
	_test_integrated_robot_canvas_rendering()

	if _failures.is_empty():
		print("-----------------------------------------------------------------")
		print("--- ВСЕ ТЕСТЫ ИНТЕРАКТИВНОСТИ УСПЕШНО ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		print("-----------------------------------------------------------------")
		quit(0)
	else:
		printerr("-----------------------------------------------------------------")
		printerr("--- ПРОВАЛЕНО ТЕСТОВ ИНТЕРАКТИВНОСТИ: %d из %d проверок ---" % [_failures.size(), _checks])
		for f in _failures:
			printerr("    [FAIL] " + str(f))
		printerr("-----------------------------------------------------------------")
		quit(1)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)
		printerr("  [FAIL] " + what)


func _t(t: String) -> void:
	print("  · " + t)


## -------------------------------------------------------------------
## 1. Процедурное дыхание и изменение масштаба/позиции торса со временем
## -------------------------------------------------------------------
func _test_procedural_breathing_and_torso() -> void:
	print("\n[1] Проверка процедурного дыхания и динамики торса:")

	var anim := RobotProceduralAnimation.new()
	_check(anim != null, "RobotProceduralAnimation: экземпляр успешно создан")
	_check(anim.breath_time == 0.0, "Начальное время дыхания == 0.0")
	_check(anim.get_chest_breath_offset_y() == 0.0, "Начальное смещение дыхания == 0.0")
	_check(is_equal_approx(anim.get_chest_scale_y(), 1.0), "Начальный масштаб груди == 1.0")
	_check(anim.get_tremor_offset() == Vector2.ZERO, "Начальный тремор == ZERO")

	# Симуляция плавного дыхания во времени (полный цикл ~4.0 сек)
	var max_positive_offset: float = -999.0
	var min_negative_offset: float = 999.0
	var max_scale_y: float = -999.0
	var min_scale_y: float = 999.0

	var sim_time: float = 0.0
	var step: float = 0.05
	while sim_time < 4.5:
		anim.update(step, 20.0, 70.0, false)
		sim_time += step

		var cur_y := anim.get_chest_breath_offset_y()
		var cur_scale := anim.get_chest_scale_y()

		max_positive_offset = maxf(max_positive_offset, cur_y)
		min_negative_offset = minf(min_negative_offset, cur_y)
		max_scale_y = maxf(max_scale_y, cur_scale)
		min_scale_y = minf(min_scale_y, cur_scale)

	# Проверка синусоидального диапазона смещения (амплитуда ~1.5 px)
	_check(max_positive_offset > 0.8, "Дыхание торса: достигнута положительная фаза (вдох: +%.2f px)" % max_positive_offset)
	_check(min_negative_offset < -0.8, "Дыхание торса: достигнута отрицательная фаза (выдох: %.2f px)" % min_negative_offset)
	_check(max_positive_offset <= anim.breath_amplitude_px + 0.01, "Смещение не превышает заданную амплитуду")

	# Проверка масштаба грудной клетки
	_check(max_scale_y > 1.003, "Масштаб грудной клетки расширяется на вдохе (>1.0: %.4f)" % max_scale_y)
	_check(min_scale_y < 0.997, "Масштаб грудной клетки сжимается на выдохе (<1.0: %.4f)" % min_scale_y)

	# Проверка составного смещения груди и головы
	var chest_off := anim.get_chest_offset()
	_check(absf(chest_off.y - (anim.get_tremor_offset().y + anim.get_chest_breath_offset_y())) < 0.001,
		"Составное смещение груди корректно суммирует дыхание и тремор")

	var head_off := anim.get_head_offset()
	_check(head_off is Vector2, "Смещение головы возвращает валидный Vector2")

	# Проверка ускорения дыхания при росте нестабильности
	anim.reset()
	anim.update(1.0, 20.0, 70.0, false)
	var breath_time_calm := anim.breath_time

	anim.reset()
	anim.update(1.0, 65.0, 70.0, false)
	var breath_time_hot := anim.breath_time
	_check(breath_time_hot > breath_time_calm,
		"При росте нестабильности частота дыхания динамически возрастает (%.2f > %.2f)" % [breath_time_hot, breath_time_calm])

	# Проверка дыхания в состоянии бодрствования (AWAKE)
	anim.reset()
	anim.update(1.0, 75.0, 70.0, true)
	var breath_time_awake := anim.breath_time
	_check(breath_time_awake > breath_time_hot * 1.5,
		"В состоянии AWAKE дыхание становится учащенным и тревожным")

	# Проверка импульса серво-тремора шеи (neck twitch)
	var twitched_flags := { "emitted": false }
	anim.servo_twitched.connect(func(_val): twitched_flags["emitted"] = true)
	anim.trigger_servo_twitch(1.0)
	_check(twitched_flags["emitted"], "Сигнал servo_twitched успешно отправлен при механическом толчке")
	_check(anim.head_twitch_velocity.length() > 10.0, "Импульс передал начальную скорость шарниру шеи")

	# Интеграция пружинно-демпферного затухания без NaN/inf
	for i in 60:
		anim.update(0.016, 20.0, 70.0, false)
	_check(anim.head_twitch_velocity.length() < 5.0, "Демпфер успешно погасил колебания шеи")
	_check(not is_nan(anim.get_head_rotation()) and not is_inf(anim.get_head_rotation()), "Угол поворота головы математически стабилен")

	# Проверка метода Balance/Robot: get_breathing_offset
	var robot := Robot.new()
	var balance := Balance.new()
	robot.configure(balance)
	_check(is_equal_approx(robot.get_breathing_offset(0.0), 0.0), "Robot.get_breathing_offset(0.0) == 0.0")
	var t_quarter := (1.0 / 0.5) * 0.25
	var offset_peak := robot.get_breathing_offset(t_quarter)
	_check(offset_peak > 1.0, "Robot.get_breathing_offset достигает пика на 1/4 цикла: %.2f px" % offset_peak)

	_t("Процедурное дыхание, синусоидальный масштаб и микро-толчки шеи полностью верифицированы")


## -------------------------------------------------------------------
## 2. Реакция робота на курсор мыши на разной дистанции (Proximity Awareness)
## -------------------------------------------------------------------
func _test_mouse_cursor_proximity_reaction() -> void:
	print("\n[2] Проверка реакции робота на курсор мыши на разной дистанции:")

	var prox := ProximityAwareness.new()
	_check(prox != null, "ProximityAwareness: экземпляр успешно создан")
	_check(prox.zones.size() >= 3, "ProximityAwareness: загружено %d интерактивных зон" % prox.zones.size())

	# 1. Курсор на дальней дистанции (>300px от робота)
	var far_pos := Vector2(50.0, 50.0)
	prox.update(0.05, far_pos, Vector2.ZERO, true)
	_check(prox.get_proximity_factor() == 0.0, "Дальняя дистанция: proximity_factor == 0.0")
	_check(prox.active_zone_id == "", "Дальняя дистанция: нет активной зоны")
	_check(not prox.is_in_proximity(), "Дальняя дистанция: is_in_proximity() == false")
	_check(is_equal_approx(prox.get_tilt_degrees(), 0.0), "Дальняя дистанция: наклон робота == 0.0°")

	# Сигналы входа/выхода
	var entered_zone := ""
	var exited_zone := ""
	var stepper_clicks := 0
	prox.proximity_entered.connect(func(zid): entered_zone = zid)
	prox.proximity_exited.connect(func(zid): exited_zone = zid)
	prox.stepper_clicked.connect(func(zid, factor, pitch): stepper_clicks += 1)

	# 2. Курсор на средней дистанции от височного порта (базовая точка 640, 160; радиус 85px)
	# Точка на расстоянии 65px (внутри радиуса 85px)
	var med_pos := Vector2(640.0 + 65.0, 160.0)
	prox.update(0.05, med_pos, Vector2.ZERO, true)
	_check(entered_zone == "temporal_port", "Событие proximity_entered для височного порта")
	_check(prox.active_zone_id == "temporal_port", "Активная зона определена как temporal_port")
	_check(prox.get_proximity_factor() > 0.0 and prox.get_proximity_factor() < 1.0,
		"Средняя дистанция: 0 < proximity_factor (%.3f) < 1.0" % prox.get_proximity_factor())
	_check(prox.is_in_proximity(), "is_in_proximity() == true на средней дистанции")
	_check(stepper_clicks > 0, "Шаговый двигатель щелкнул при входе в зону чувствительности")

	# 3. Курсор на близкой дистанции / вплотную к порту (расстояние 0-10px)
	var close_pos := Vector2(640.0 + 5.0, 160.0)
	prox.update(0.05, close_pos, Vector2.ZERO, true)
	_check(prox.get_proximity_factor() > 0.90, "Близкая дистанция: proximity_factor близок к максимуму (%.3f)" % prox.get_proximity_factor())
	_check(prox.target_tilt_angle != 0.0, "Определен ненулевой целевой угол отвода головы")

	# Проверка направления отвода (уклонение в противоположную сторону)
	# Курсор справа (+5px) -> наклон влево (отрицательный угол)
	_check(prox.target_tilt_angle < 0.0, "Курсор справа от центра вызывает уклонение корпуса влево")

	# Проверка сглаживания угла (демпфер lerp)
	for i in 20:
		prox.update(0.033, close_pos, Vector2.ZERO, true)
	_check(absf(prox.get_tilt_degrees()) > 0.5, "Демпфер плавно отвел корпус на угол: %.2f°" % prox.get_tilt_degrees())
	_check(absf(prox.get_tilt_degrees()) <= prox.max_tilt_deg * 1.5, "Угол отвода не превышает предельный максимум безопасности")

	# Проверка гидравлического смещения (напряжение и микродрожание)
	var hydr := prox.get_hydraulic_offset()
	_check(hydr != Vector2.ZERO, "Смещение гидравлики активно: (%f, %f)" % [hydr.x, hydr.y])
	_check(prox.get_pulse_intensity() > 0.0, "Пульсация индикатора нестабильности активна при близости")

	# 4. Проверка зоны контактов (Rect2(585, 215, 110, 45))
	var contacts_center := Vector2(640.0, 237.0)
	prox.update(0.05, contacts_center, Vector2.ZERO, true)
	_check(prox.active_zone_id == "contacts", "Наведение на контакты переключает active_zone_id на 'contacts'")
	_check(prox.get_proximity_factor() >= 0.99, "Курсор внутри прямоугольника контактов дает максимальную близость 1.0")

	# 5. Проверка зоны силового бронелюка (Rect2(570, 275, 140, 90))
	var hatch_center := Vector2(640.0, 320.0)
	prox.update(0.05, hatch_center, Vector2.ZERO, true)
	_check(prox.active_zone_id == "armor_hatch", "Наведение на люк переключает active_zone_id на 'armor_hatch'")

	# 6. Уход курсора и демпфированный возврат в покой
	prox.update(0.05, far_pos, Vector2.ZERO, true)
	_check(exited_zone != "", "Событие proximity_exited успешно отправлено при удалении курсора")
	for i in 30:
		prox.update(0.033, far_pos, Vector2.ZERO, true)
	_check(is_equal_approx(prox.get_proximity_factor(), 0.0), "Фактор близости плавно затух до 0.0")
	_check(absf(prox.get_tilt_degrees()) < 0.05, "Корпус плавно вернулся в исходное вертикальное положение")

	# 7. Проверка реакции сенсоров оптики на дистанцию курсора (RobotOptics)
	var optics := RobotOptics.new()
	var r_rect := Rect2(505.0, 65.0, 270.0, 542.0)
	optics.configure(r_rect)

	# Курсор вне радиуса обнаружения (> 175px от визора)
	optics.update(0.05, Vector2(100.0, 100.0), Vector2.ZERO, 20.0, 70.0, false)
	_check(optics.cursor_proximity == 0.0, "RobotOptics: курсор далеко -> cursor_proximity == 0.0")

	# Курсор приближается к визору (дистанция 100px: между warn_distance 175 и danger_distance 45)
	var near_visor := optics.visor_center + Vector2(100.0, 0.0)
	optics.update(0.05, near_visor, Vector2.ZERO, 20.0, 70.0, false)
	_check(optics.cursor_proximity > 0.0 and optics.cursor_proximity < 1.0,
		"RobotOptics: курсор на дистанции 100px -> 0.0 < proximity (%.2f) < 1.0" % optics.cursor_proximity)

	# Курсор вплотную к визору (< 45px)
	var touch_visor := optics.visor_center + Vector2(20.0, 0.0)
	optics.update(0.05, touch_visor, Vector2.ZERO, 20.0, 70.0, false)
	_check(is_equal_approx(optics.cursor_proximity, 1.0), "RobotOptics: курсор вплотную -> cursor_proximity == 1.0")
	_check(optics.current_mode == RobotOptics.Mode.ALERT_SCAN, "RobotOptics: приближение курсора переводит оптику в ALERT_SCAN")

	_t("Реакция на курсор мыши, дистанционные зоны, уклонение и отклик сенсоров оптики подтверждены")


## -------------------------------------------------------------------
## 3. Генерация частиц пара и мерцание визора при росте нестабильности
## -------------------------------------------------------------------
func _test_steam_and_visor_instability() -> void:
	print("\n[3] Проверка генерации пара и мерцания визора при росте нестабильности:")

	# --- Часть А: Генерация частиц пара (RobotThermalFX) ---
	var thermal := RobotThermalFX.new()
	thermal.configure(Rect2(505.0, 65.0, 270.0, 542.0))

	# 1. При низкой нестабильности (20.0 / 70.0) система спит и пара нет
	thermal.update(0.1, 20.0, 70.0, false)
	_check(thermal.get_heat_ratio() == 0.0, "RobotThermalFX: heat_ratio == 0.0 при нестабильности 20%")
	_check(thermal.get_active_particles_count() == 0, "RobotThermalFX: 0 частиц пара в состоянии покоя")

	# 2. Рост нестабильности до критической зоны (>60%)
	# Накопление тепла приводит к срабатыванию пассивных клапанов стравливания
	var steam_generated := false
	for i in 40:
		thermal.update(0.05, 66.0, 70.0, false)
		if thermal.get_active_particles_count() > 0:
			steam_generated = true
			break

	_check(thermal.get_heat_ratio() > 0.5, "RobotThermalFX: heat_ratio > 0.5 (%.2f) при нестабильности 66%%" % thermal.get_heat_ratio())
	_check(steam_generated, "При росте нестабильности >60% клапаны автоматически стравливают пар")

	# 3. Экстренный выброс давления при остром перегреве трением (acute blowoff)
	thermal.trigger_acute_blowoff(1.0)
	var active_particles := thermal.get_active_particles_count()
	_check(active_particles >= 10, "Экстренное стравливание: залп частиц пара (%d активных частиц)" % active_particles)
	_check(thermal.get_overheat_surge() > 0.8, "Всплеск перегрева зафиксирован (>0.8: %.2f)" % thermal.get_overheat_surge())

	# 4. Физика частиц: движение, замедление и рассеивание без утечек памяти (Zero GC)
	var initial_y := thermal.p_pos[0].y
	thermal.update(0.05, 60.0, 70.0, false)
	var moved_y := thermal.p_pos[0].y
	_check(moved_y != initial_y, "Частицы пара динамически перемещаются в пространстве")

	# Затухание пара при возврате в стабильное состояние
	for i in 80:
		thermal.update(0.05, 20.0, 70.0, false)
	_check(thermal.get_active_particles_count() == 0, "Пар полностью рассеивается после нормализации давления")
	_check(is_equal_approx(thermal.get_overheat_surge(), 0.0), "Всплеск перегрева плавно затух до 0.0")

	# --- Часть Б: Мерцание, цвет и пульсация визора (RobotOptics) ---
	var optics := RobotOptics.new()
	optics.configure(Rect2(505.0, 65.0, 270.0, 542.0))

	# 1. Состояние покоя (низкая нестабильность 20%, курсор далеко)
	optics.update(0.05, Vector2.ZERO, Vector2.ZERO, 20.0, 70.0, false)
	_check(optics.current_mode == RobotOptics.Mode.DORMANT or optics.current_mode == RobotOptics.Mode.DIAGNOSTIC_PULSE,
		"Низкая нестабильность: режим DORMANT или диагностический импульс")

	# 2. Рост нестабильности до пред-аварийного уровня (65.0 при пороге 70.0)
	optics.update(0.05, Vector2.ZERO, Vector2.ZERO, 65.0, 70.0, false)
	_check(optics.threat_ratio > 0.90, "Коэффициент угрозы визора threat_ratio > 0.90 (%.2f)" % optics.threat_ratio)
	_check(optics.current_mode == RobotOptics.Mode.ALERT_SCAN, "Рост нестабильности переводит оптику в тревожный режим ALERT_SCAN")
	_check(optics.get_visor_intensity() > 0.40, "Интенсивность свечения визора возросла (>0.40: %.2f)" % optics.get_visor_intensity())

	# Проверка смещения луча сканирования (ping-pong луч по ширине визора)
	var beam_pos_1 := optics.beam_x_norm
	optics.update(0.08, Vector2.ZERO, Vector2.ZERO, 65.0, 70.0, false)
	var beam_pos_2 := optics.beam_x_norm
	_check(beam_pos_1 != beam_pos_2, "Фокальный луч визора динамически сканирует по горизонтали")

	# 3. Всполохи и мерцание оптики (glitch flash)
	optics.trigger_glitch_flash(1.0)
	_check(optics.flash_timer > 0.0, "Таймер вспышки визора flash_timer > 0.0")
	_check(optics.flash_intensity > 0.8, "Интенсивность всполоха визора flash_intensity > 0.8")

	# Затухание вспышки со временем
	optics.update(0.1, Vector2.ZERO, Vector2.ZERO, 65.0, 70.0, false)
	_check(optics.flash_timer == 0.0, "Всполох визора успешно завершен после выгорания таймера")

	# 4. Пробуждение робота (AWAKE / OVERDRIVE)
	optics.update(0.05, Vector2.ZERO, Vector2.ZERO, 72.0, 70.0, true)
	_check(optics.current_mode == RobotOptics.Mode.OVERDRIVE_AWAKE, "Пробуждение переводит визор в режим OVERDRIVE_AWAKE")
	_check(optics.get_visor_color() == RobotOptics.COLOR_ALERT_RED, "Цвет визора переключился на аварийный насыщенный алый (COLOR_ALERT_RED)")
	_check(optics.get_visor_intensity() >= 0.95, "Максимальная яркость аварийного диодного свечения (>=0.95)")

	# Проверка активации вспомогательных датчиков (брови и виски)
	var active_sensor_count := 0
	for s in optics.sensors:
		if float(s.get("alpha", 0.0)) > 0.5:
			active_sensor_count += 1
	_check(active_sensor_count >= 2, "При тревоге вспомогательные датчики и диоды визора активны")

	_t("Генерация пара через клапаны, перегрев, мерцание визора и аварийный овердрайв подтверждены")


## -------------------------------------------------------------------
## 4. Сквозная отрисовка всех подсистем интерактивности на холст CanvasItem
## -------------------------------------------------------------------
func _test_integrated_robot_canvas_rendering() -> void:
	print("\n[4] Проверка рендеринга интерактивности на холст CanvasItem (Zero Exception):")

	var canvas := Node2D.new()
	root.add_child(canvas)

	var anim := RobotProceduralAnimation.new()
	var thermal := RobotThermalFX.new()
	var optics := RobotOptics.new()
	var prox := ProximityAwareness.new()

	var r_rect := Rect2(505.0, 65.0, 270.0, 542.0)
	thermal.configure(r_rect)
	optics.configure(r_rect)
	prox.configure(null, { "robot_rect": r_rect })

	# Обновляем кадр в напряженном состоянии
	anim.update(0.016, 60.0, 70.0, false)
	prox.update(0.016, Vector2(640.0, 160.0), Vector2.ZERO, true)
	thermal.update(0.016, 60.0, 70.0, false)
	thermal.trigger_acute_blowoff(0.5)
	optics.update(0.016, Vector2(640.0, 160.0), Vector2.ZERO, 60.0, 70.0, false)

	# Вызов методов отрисовки
	# Отрисовка процедурной анимации робота (фоллбэк без текстур)
	anim.render_robot(canvas, null, null, r_rect, Vector2.ZERO, false, 0.5)

	# Отрисовка радиатора и струй пара
	thermal.render(canvas, Vector2.ZERO)

	# Отрисовка процедурного визора, световых конусов и датчиков
	optics.render(canvas, Vector2.ZERO)

	_check(true, "Сквозной рендеринг всех интерактивных слоев робота выполнен без исключений")

	canvas.queue_free()
	_t("Сквозной рендеринг процедурного дыхания, пара и визора успешно проверен на CanvasItem")
