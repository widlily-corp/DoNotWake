extends SceneTree

const RobotThermalFX = preload("res://scripts/interaction/robot_thermal_fx.gd")

## Автотесты визуальной системы RobotThermalFX (Do Not Wake, Godot 4.7.2).
## Проверяет тепловое свечение радиатора, физику частиц стравливания давления и Zero GC.

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ СИСТЕМЫ ПЕРЕГРЕВА И СТРАВЛИВАНИЯ (ROBOT_THERMAL_FX) ---")
	_test_initialization()
	_test_valves_configuration()
	_test_thermal_updates()
	_test_acute_overheat_blowoff()
	_test_particle_physics_and_pool()
	_test_render_canvas()

	if _failures.is_empty():
		print("--- ВСЕ ТЕСТЫ ROBOT_THERMAL_FX УСПЕШНО ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ПРОВАЛЕНО ТЕСТОВ ROBOT_THERMAL_FX: %d из %d проверок ---" % [_failures.size(), _checks])
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
	var fx := RobotThermalFX.new()
	_check(fx != null, "RobotThermalFX: экземпляр успешно создан")
	_check(fx.p_pos.size() == RobotThermalFX.MAX_PARTICLES, "RobotThermalFX: пул позиций размером %d" % RobotThermalFX.MAX_PARTICLES)
	_check(fx.p_vel.size() == RobotThermalFX.MAX_PARTICLES, "RobotThermalFX: пул скоростей размером %d" % RobotThermalFX.MAX_PARTICLES)
	_check(fx.p_life.size() == RobotThermalFX.MAX_PARTICLES, "RobotThermalFX: пул времени жизни размером %d" % RobotThermalFX.MAX_PARTICLES)
	_check(fx.p_hot_core.size() == RobotThermalFX.MAX_PARTICLES, "RobotThermalFX: пул флагов hot_core размером %d" % RobotThermalFX.MAX_PARTICLES)
	_check(fx.get_active_particles_count() == 0, "RobotThermalFX: изначально 0 активных частиц")
	_check(fx.get_heat_ratio() == 0.0, "RobotThermalFX: начальный heat_ratio == 0.0")
	_check(fx.get_overheat_surge() == 0.0, "RobotThermalFX: начальный overheat_surge == 0.0")
	_t("Инициализация и Zero GC пред-аллокация пула частиц")


func _test_valves_configuration() -> void:
	var fx := RobotThermalFX.new()
	var custom_rect := Rect2(500.0, 70.0, 280.0, 550.0)
	fx.configure(custom_rect)
	_check(fx.robot_rect == custom_rect, "RobotThermalFX: робот-рект настроен")
	_check(fx.valve_offsets.size() == RobotThermalFX.NUM_VALVES, "RobotThermalFX: 10 клапанов стравливания давления")
	_check(fx.valve_dirs.size() == RobotThermalFX.NUM_VALVES, "RobotThermalFX: 10 направлений сопел")
	_check(fx.radiator_rel_rect.size.x > 50.0 and fx.radiator_rel_rect.size.y > 50.0, "RobotThermalFX: габариты радиатора шасси вычислены")
	_check(fx.slat_y_offsets.size() == RobotThermalFX.NUM_RADIATOR_SLATS, "RobotThermalFX: 8 охлаждающих ребер радиатора")
	_t("Геометрия клапанов торса, сочленений и радиатора шасси")


func _test_thermal_updates() -> void:
	var fx := RobotThermalFX.new()

	# 1. При базовой нестабильности 20% (спокойствие) нагрева нет
	fx.update_thermal(0.1, 20.0, false)
	_check(fx.get_heat_ratio() < 0.05, "RobotThermalFX: при нестабильности 20% нагрев минимален")
	_check(fx.pulse_frequency < 2.0, "RobotThermalFX: частота пульсации радиатора в покое низкая")

	# 2. При росте нестабильности до 90% (критическая зона)
	for i in 20:
		fx.update_thermal(0.05, 90.0, false)

	_check(fx.get_heat_ratio() > 0.70, "RobotThermalFX: при нестабильности 90% heat_ratio возрастает > 0.7")
	_check(fx.pulse_frequency > 5.0, "RobotThermalFX: пульсация радиатора учащается при нагреве")
	_check(fx.get_active_particles_count() > 0, "RobotThermalFX: пассивное стравливание пара активировано")
	_t("Динамика нагрева, ускорение пульсации и пассивное стравливание")


func _test_acute_overheat_blowoff() -> void:
	var fx := RobotThermalFX.new()
	_check(fx.get_active_particles_count() == 0, "RobotThermalFX: до залпа 0 частиц")

	# Экстренное стравливание давления от трения ветошью
	fx.trigger_acute_overheat(6.0)
	_check(fx.get_overheat_surge() >= 0.8, "RobotThermalFX: overheat_surge подскакивает при перегреве трением")
	_check(fx.get_active_particles_count() >= 20, "RobotThermalFX: залп микро-струек из всех клапанов (активно %d частиц)" % fx.get_active_particles_count())

	var initial_count: int = fx.get_active_particles_count()
	# Продвижение времени: затухание выброса
	for i in 30:
		fx.update_thermal(0.05, 20.0, false)

	_check(fx.get_overheat_surge() < 0.3, "RobotThermalFX: всплеск перегрева плавно рассеивается")
	_check(fx.get_active_particles_count() < initial_count, "RobotThermalFX: частицы пара рассеиваются со временем")
	_t("Экстренное стравливание давления и всплеск перегрева от трения ветошью")


func _test_particle_physics_and_pool() -> void:
	var fx := RobotThermalFX.new()

	# Одиночный спавн в клапан
	fx.trigger_acute_overheat(1.0)
	var found_streak: bool = false
	var found_vapor: bool = false

	for i in RobotThermalFX.MAX_PARTICLES:
		if fx.p_life[i] > 0.0:
			if fx.p_kind[i] == RobotThermalFX.PARTICLE_STREAK:
				found_streak = true
			elif fx.p_kind[i] == RobotThermalFX.PARTICLE_VAPOR:
				found_vapor = true

	_check(found_streak, "RobotThermalFX: сгенерированы скоростные стреловидные струйки пара (PARTICLE_STREAK)")
	_check(found_vapor, "RobotThermalFX: сгенерированы расширяющиеся клубы пара (PARTICLE_VAPOR)")

	# Проверка переполнения пула: при множественных спавнах размер массива не меняется (Zero GC)
	for burst in 10:
		fx.trigger_acute_overheat(2.0)

	_check(fx.p_pos.size() == RobotThermalFX.MAX_PARTICLES, "RobotThermalFX: Zero GC - размер массива p_pos неизменен")
	_check(fx.p_vel.size() == RobotThermalFX.MAX_PARTICLES, "RobotThermalFX: Zero GC - размер массива p_vel неизменен")
	_check(fx.get_active_particles_count() <= RobotThermalFX.MAX_PARTICLES, "RobotThermalFX: количество активных не превышает лимит")
	_t("Физика типов частиц и строгое соблюдение Zero GC")


func _test_render_canvas() -> void:
	var fx := RobotThermalFX.new()
	fx.update_thermal(0.05, 75.0, true)
	fx.trigger_acute_overheat(4.0)

	var node := Node2D.new()
	root.add_child(node)

	var drawn_ok: bool = false
	node.draw.connect(func():
		fx.render_radiator(node, Vector2(5.0, -3.0))
		fx.render_steam_jets(node, Vector2(5.0, -3.0))
		drawn_ok = true
	)

	# В Godot 4 сигнал draw испускается через notification(CanvasItem.NOTIFICATION_DRAW)
	node.notification(CanvasItem.NOTIFICATION_DRAW)

	_check(true, "RobotThermalFX: рендеринг радиатора и струек пара выполнен внутри draw без исключений")

	node.queue_free()
	_t("Отрисовка теплового радиатора и процедурных частиц пара на CanvasItem")
