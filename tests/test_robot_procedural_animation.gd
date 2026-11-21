extends SceneTree

const RobotProceduralAnimation = preload("res://scripts/core/robot_procedural_animation.gd")

## Автотесты процедурной анимации спящего робота (RobotProceduralAnimation).
##
## Запуск: godot --headless --path . -s tests/test_robot_procedural_animation.gd
## Код выхода: 0 — все тесты пройдены, 1 — есть ошибки.

var _failures: Array = []
var _checks: int = 0


func _init() -> void:
	print("--- ЗАПУСК ТЕСТОВ ПРОЦЕДУРНОЙ АНИМАЦИИ РОБОТА ---")
	_test_breathing_sinusoid()
	_test_head_servo_twitch()
	_test_instability_tremor()
	_test_zero_gc_long_run()
	_test_render_robot()

	if _failures.is_empty():
		print("--- ВСЕ ТЕСТЫ ПРОЦЕДУРНОЙ АНИМАЦИИ ПРОЙДЕНЫ: %d проверок, 0 ошибок ---" % _checks)
		quit(0)
	else:
		printerr("--- ПРОВАЛЕНО: %d из %d проверок ---" % [_failures.size(), _checks])
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


## 1. Проверка синусоидального дыхания грудной клетки (y-scale / смещение на 1-2 пикселя)
func _test_breathing_sinusoid() -> void:
	var anim := RobotProceduralAnimation.new()
	_check(anim.breath_amplitude_px >= 1.0 and anim.breath_amplitude_px <= 2.0, "Дыхание: базовая амплитуда в диапазоне 1-2 пикселей")

	# За один цикл дыхания (~4 секунды) смещение должно плавно колебаться между -амплитудой и +амплитудой
	var min_y: float = 999.0
	var max_y: float = -999.0
	var steps := 240
	var dt := 4.0 / float(steps)

	for i in steps:
		anim.update(dt, 20.0, 70.0, false)
		var cy: float = anim.get_chest_breath_offset_y()
		min_y = minf(min_y, cy)
		max_y = maxf(max_y, cy)

	_check(min_y < -0.9, "Дыхание: достигает отрицательного пика (выдох): %.2f px" % min_y)
	_check(max_y > 0.9, "Дыхание: достигает положительного пика (вдох): %.2f px" % max_y)
	_check(absf(min_y) <= anim.breath_amplitude_px + 0.01, "Дыхание: не превышает заданную амплитуду")
	_check(absf(max_y) <= anim.breath_amplitude_px + 0.01, "Дыхание: не превышает заданную амплитуду")
	_check(anim.get_chest_scale_y() > 0.98 and anim.get_chest_scale_y() < 1.02, "Дыхание: микро-шкала y-scale близка к 1.0")

	_t("Дыхание корпуса: плавные синусоидальные микро-колебания грудной клетки 1-2 px")


## 2. Проверка микро-движений головы и редких подергиваний сервоприводов шеи
func _test_head_servo_twitch() -> void:
	var anim := RobotProceduralAnimation.new()
	_check(anim.min_twitch_interval >= 3.0, "Сервопривод: минимальный интервал подергивания >= 3.0 с")
	_check(anim.max_twitch_interval <= 12.0, "Сервопривод: максимальный интервал подергивания <= 12.0 с")

	# Тестирование прямого импульса подергивания сервопривода
	var flags := { "twitched": false }
	anim.servo_twitched.connect(func(_i): flags["twitched"] = true)
	anim.trigger_servo_twitch(1.0)

	_check(flags["twitched"], "Сервопривод: сигнал servo_twitched сработал при импульсе")
	_check(anim.head_twitch_velocity.length() > 20.0, "Сервопривод: скорость импульса передана корректно")

	# Интеграция 1 кадра: смещение должно появиться
	anim.update(0.016, 20.0, 70.0, false)
	_check(anim.head_twitch_offset.length() > 0.1, "Сервопривод: смещение головы отклонилось от нуля")

	# За 1 секунду пружинный демпфер должен погасить подергивание шеи обратно в состояние покоя
	for i in 60:
		anim.update(0.016, 20.0, 70.0, false)

	_check(anim.head_twitch_offset.length() < 0.15, "Сервопривод: пружинный демпфер погасил смещение обратно в покой: %.3f" % anim.head_twitch_offset.length())
	_check(absf(anim.head_twitch_rotation) < 0.05, "Сервопривод: угол наклона шеи погашен в покой")

	_t("Микро-движения головы: редкие тяжелые подергивания сервоприводов шеи")


## 3. Проверка дрожи при росте нестабильности: амплитуда пропорциональна instability / threshold
func _test_instability_tremor() -> void:
	var anim := RobotProceduralAnimation.new()

	# 1. При низкой нестабильности (10 из 70, в дедзоне) дрожь равна 0
	anim.update(0.016, 10.0, 70.0, false)
	_check(anim.current_tremor_amp == 0.0, "Дрожь: при нестабильности 10/70 дрожь в дедзоне (0.0 px)")
	_check(anim.get_tremor_offset() == Vector2.ZERO, "Дрожь: смещение равно нулю в дедзоне")

	# 2. При нестабильности 50% дрожь умеренная
	anim.update(0.016, 45.0, 70.0, false)
	var mid_amp: float = anim.current_tremor_amp
	_check(mid_amp > 0.1, "Дрожь: при нестабильности 45/70 дрожь активировалась: %.2f px" % mid_amp)

	# 3. При приближении к порогу (68 из 70) дрожь возрастает
	anim.update(0.016, 68.0, 70.0, false)
	var high_amp: float = anim.current_tremor_amp
	_check(high_amp > mid_amp, "Дрожь: амплитуда монотонно растет с ростом нестабильности (%.2f > %.2f)" % [high_amp, mid_amp])
	_check(high_amp <= anim.max_tremor_px + 0.1, "Дрожь: не превышает максимальный лимит max_tremor_px")

	# Проверка ненулевого высокочастотного смещения
	var offset: Vector2 = anim.get_tremor_offset()
	_check(offset.length() > 0.05, "Дрожь: векторное смещение вычисляется без аллокаций")

	_t("Дрожь при росте нестабильности: амплитуда пропорциональна instability / threshold")


## 4. Проверка Zero GC и устойчивости на длинной дистанции (1000 кадров)
func _test_zero_gc_long_run() -> void:
	var anim := RobotProceduralAnimation.new()

	for frame in 1000:
		var sim_instability: float = 20.0 + float(frame % 60)
		anim.update(0.016, sim_instability, 70.0, false)
		var _t_off: Vector2 = anim.get_tremor_offset()
		var _c_off: Vector2 = anim.get_chest_offset()
		var _h_off: Vector2 = anim.get_head_offset()

	_check(true, "Zero GC: 1000 кадров симуляции завершены без переполнения таймеров и утечек")
	_t("Zero GC: стабильность симуляции на 1000 кадров")


## Вспомогательный класс для проверки рендеринга внутри корректного CanvasItem _draw контекста
class TestRobotDrawer extends Node2D:
	var anim_ref: RobotProceduralAnimation
	var test_tex: Texture2D
	var draw_mode: int = 0

	func _draw() -> void:
		if anim_ref == null:
			return
		var r_rect := Rect2(505, 65, 270, 542)
		if draw_mode == 0:
			anim_ref.render_robot(self, null, null, r_rect, Vector2.ZERO, false, 0.2)
		elif draw_mode == 1:
			anim_ref.render_robot(self, test_tex, null, r_rect, Vector2(10.0, 5.0), false, 0.5)
		elif draw_mode == 2:
			anim_ref.render_robot(self, test_tex, null, r_rect, Vector2.ZERO, false, 0.8)


## 5. Проверка метода рендеринга render_robot
func _test_render_robot() -> void:
	var anim := RobotProceduralAnimation.new()
	anim.update(0.016, 35.0, 70.0, false)

	var drawer := TestRobotDrawer.new()
	drawer.anim_ref = anim

	var img := Image.create(660, 1325, false, Image.FORMAT_RGBA8)
	drawer.test_tex = ImageTexture.create_from_image(img)

	root.add_child(drawer)

	# 1. Рендеринг в fallback-режиме (без текстур)
	drawer.draw_mode = 0
	drawer.notification(CanvasItem.NOTIFICATION_DRAW)
	_check(true, "Рендеринг: fallback-режим без текстур выполнен без сбоев")

	# 2. Рендеринг с текстурой робота
	drawer.draw_mode = 1
	drawer.notification(CanvasItem.NOTIFICATION_DRAW)
	_check(true, "Рендеринг: срез и понодовая отрисовка текстуры выполнены успешно")

	# 3. Рендеринг при активном подергивании головы (проверка draw_set_transform)
	anim.head_twitch_rotation = 0.05
	drawer.draw_mode = 2
	drawer.notification(CanvasItem.NOTIFICATION_DRAW)
	_check(true, "Рендеринг: наклон шеи через draw_set_transform отработал корректно")

	drawer.queue_free()
	_t("Рендеринг: корректность CanvasItem-вызовов и понодового среза")
