class_name ProximityAwareness
extends RefCounted

## Подсистема интерактивной реакции робота на приближение мыши (Proximity Awareness).
## Реализует напряжение гидравлики, отвод головы на 1-2 градуса,
## тихие щелчки шаговых двигателей и пульсацию индикатора нестабильности
## при наведении курсора / инструментов на уязвимые зоны робота.

signal stepper_clicked(zone_id: String, factor: float, pitch: float)
signal proximity_entered(zone_id: String)
signal proximity_exited(zone_id: String)

# Основные параметры
var enabled: bool = true
var max_tilt_deg: float = 1.6
var tilt_damping: float = 7.5
var hydraulic_jitter_amp: float = 0.45
var hydraulic_strain_y: float = -1.2
var pulse_frequency: float = 6.5
var stepper_cooldown_min: float = 0.28
var stepper_cooldown_max: float = 0.65
var stepper_volume_db: float = -22.0
var stepper_pitch_min: float = 1.8
var stepper_pitch_max: float = 2.4

# Список уязвимых зон (височный порт, контакты сервопривода, силовой бронелюк)
var zones: Array = []

# Динамическое состояние в рантайме
var proximity_factor: float = 0.0 # 0.0 (далеко) .. 1.0 (вплотную)
var active_zone_id: String = ""
var active_zone_name: String = ""
var target_tilt_angle: float = 0.0 # в радианах
var current_tilt_angle: float = 0.0 # в радианах
var hydraulic_offset: Vector2 = Vector2.ZERO
var pulse_intensity: float = 0.0
var needle_jitter: float = 0.0
var time_accum: float = 0.0
var stepper_timer: float = 0.0
var last_discrete_step: int = 0
var was_in_proximity: bool = false

# Центр робота по умолчанию для расчета направления отвода
var robot_center_x: float = 640.0
var robot_waist_pivot: Vector2 = Vector2(640.0, 385.0)


func _init() -> void:
	_init_default_zones()


func _init_default_zones() -> void:
	zones = [
		{
			"id": "temporal_port",
			"name": "Височный порт",
			"type": "point",
			"pos": Vector2(640.0, 160.0),
			"radius": 85.0,
			"tilt_multiplier": 1.2
		},
		{
			"id": "contacts",
			"name": "Контакты сервопривода",
			"type": "rect",
			"rect": Rect2(585.0, 215.0, 110.0, 45.0),
			"radius": 75.0,
			"tilt_multiplier": 1.0
		},
		{
			"id": "armor_hatch",
			"name": "Силовой бронелюк",
			"type": "rect",
			"rect": Rect2(570.0, 275.0, 140.0, 90.0),
			"radius": 85.0,
			"tilt_multiplier": 0.85
		}
	]


func configure(balance: Balance, layout: Dictionary = {}) -> void:
	if layout.has("robot_rect"):
		var rr: Rect2 = Balance.to_rect(layout["robot_rect"])
		robot_center_x = rr.position.x + rr.size.x * 0.5
		robot_waist_pivot = Vector2(robot_center_x, rr.position.y + rr.size.y * 0.6)

	if balance == null:
		return

	var cfg: Dictionary = balance.get_val("proximity_awareness", {})
	if cfg.is_empty():
		var proc: Variant = balance.get_val("procedural_animation", {})
		if proc is Dictionary and (proc as Dictionary).has("proximity_awareness"):
			cfg = (proc as Dictionary)["proximity_awareness"]
	if not cfg.is_empty():
		enabled = bool(cfg.get("enabled", true))
		max_tilt_deg = float(cfg.get("max_tilt_deg", 1.6))
		tilt_damping = float(cfg.get("tilt_damping", 7.5))
		hydraulic_jitter_amp = float(cfg.get("hydraulic_jitter_amp", 0.45))
		hydraulic_strain_y = float(cfg.get("hydraulic_strain_y", -1.2))
		pulse_frequency = float(cfg.get("pulse_frequency", 6.5))
		stepper_cooldown_min = float(cfg.get("stepper_cooldown_min", 0.28))
		stepper_cooldown_max = float(cfg.get("stepper_cooldown_max", 0.65))
		stepper_volume_db = float(cfg.get("stepper_volume_db", -22.0))
		stepper_pitch_min = float(cfg.get("stepper_pitch_min", 1.8))
		stepper_pitch_max = float(cfg.get("stepper_pitch_max", 2.4))

		if cfg.has("zones") and cfg["zones"] is Array:
			var loaded_zones: Array = []
			for z in cfg["zones"]:
				if not z is Dictionary:
					continue
				var zd := (z as Dictionary).duplicate(true)
				var z_type := str(zd.get("type", "point"))
				if z_type == "point" and zd.has("pos"):
					var p_raw: Variant = zd["pos"]
					if p_raw is Array and (p_raw as Array).size() >= 2:
						zd["pos"] = Vector2(float(p_raw[0]), float(p_raw[1]))
				elif z_type == "rect" and zd.has("rect"):
					zd["rect"] = Balance.to_rect(zd["rect"])
				loaded_zones.append(zd)
			if not loaded_zones.is_empty():
				zones = loaded_zones


## Обновление математической модели близости каждый кадр (Zero GC Alloc).
func update(delta: float, cursor_pos: Vector2, mid_shift: Vector2, is_active: bool) -> void:
	time_accum += delta

	if not enabled or not is_active:
		_fade_out(delta)
		return

	# Поиск зоны с наибольшим фактором близости
	var best_factor: float = 0.0
	var best_zone_id: String = ""
	var best_zone_name: String = ""
	var best_tilt_mul: float = 1.0

	for z in zones:
		var z_id: String = str(z.get("id", ""))
		var z_name: String = str(z.get("name", z_id))
		var z_type: String = str(z.get("type", "point"))
		var z_radius: float = float(z.get("radius", 80.0))
		var z_mul: float = float(z.get("tilt_multiplier", 1.0))
		var dist: float = 9999.0

		if z_type == "point":
			var base_pos: Vector2 = z.get("pos", Vector2(640.0, 160.0))
			var eff_pos: Vector2 = base_pos + mid_shift
			dist = cursor_pos.distance_to(eff_pos)
		elif z_type == "rect":
			var base_rect: Rect2 = z.get("rect", Rect2(585.0, 215.0, 110.0, 45.0))
			var eff_rect := Rect2(base_rect.position + mid_shift, base_rect.size)
			dist = _dist_to_rect(cursor_pos, eff_rect)

		if dist < z_radius:
			var t: float = clampf(1.0 - (dist / z_radius), 0.0, 1.0)
			# Гладкая кривая Smoothstep (Hermite) для органичного чувства нарастания напряжения
			var factor: float = t * t * (3.0 - 2.0 * t)
			if factor > best_factor:
				best_factor = factor
				best_zone_id = z_id
				best_zone_name = z_name
				best_tilt_mul = z_mul

	proximity_factor = best_factor
	active_zone_id = best_zone_id
	active_zone_name = best_zone_name

	var is_in_proximity_now := (proximity_factor > 0.05)

	# События входа и выхода из зоны внимания
	if is_in_proximity_now and not was_in_proximity:
		was_in_proximity = true
		proximity_entered.emit(active_zone_id)
		# Первый мгновенный микро-щелчок сервопривода при приближении
		_trigger_stepper_click(proximity_factor)
		stepper_timer = randf_range(stepper_cooldown_min, stepper_cooldown_max)
	elif not is_in_proximity_now and was_in_proximity:
		was_in_proximity = false
		proximity_exited.emit(best_zone_id)

	# 1. Расчет отвода головы и корпуса на 1-2 градуса
	if is_in_proximity_now:
		# Отвод в противоположную от курсора сторону (уклонение / recoil)
		var delta_x := cursor_pos.x - (robot_center_x + mid_shift.x)
		var sign_dir := -1.0 if delta_x >= 0.0 else 1.0
		# Если курсор строго по центру, микро-отклонение в сторону
		if absf(delta_x) < 2.0:
			sign_dir = -1.0

		var target_deg := sign_dir * max_tilt_deg * proximity_factor * best_tilt_mul
		target_tilt_angle = deg_to_rad(target_deg)

		# 2. Напряжение гидравлики: микродавление вверх/назад + микротремор (35-45 Гц)
		var tremor_x := sin(time_accum * 38.0) * (hydraulic_jitter_amp * proximity_factor)
		var tremor_y := cos(time_accum * 44.0) * (hydraulic_jitter_amp * 0.7 * proximity_factor)
		hydraulic_offset = Vector2(tremor_x, hydraulic_strain_y * proximity_factor + tremor_y)

		# 3. Щелчки шагового двигателя в суставах при движении и удержании
		var cur_discrete_step := int(proximity_factor * 4.0)
		if cur_discrete_step != last_discrete_step and cur_discrete_step > 0:
			last_discrete_step = cur_discrete_step
			_trigger_stepper_click(proximity_factor)
			stepper_timer = randf_range(stepper_cooldown_min, stepper_cooldown_max)

		stepper_timer -= delta
		if stepper_timer <= 0.0:
			_trigger_stepper_click(proximity_factor)
			# Чем ближе курсор, тем нервнее и чаще компенсируют шаговые двигатели
			var freq_boost: float = lerpf(1.0, 0.55, proximity_factor)
			stepper_timer = randf_range(stepper_cooldown_min, stepper_cooldown_max) * freq_boost

		# 4. Пульсация индикатора нестабильности
		pulse_intensity = (0.5 + 0.5 * sin(time_accum * pulse_frequency)) * proximity_factor
		# Нервный тремор стрелки манометра
		needle_jitter = (sin(time_accum * 18.0) * 0.035 + sin(time_accum * 37.0) * 0.015) * proximity_factor
	else:
		_fade_out(delta)

	# Плавное сглаживание угла наклона (демпфер)
	current_tilt_angle = lerp(current_tilt_angle, target_tilt_angle, clampf(tilt_damping * delta, 0.0, 1.0))


func _fade_out(delta: float) -> void:
	proximity_factor = maxf(proximity_factor - delta * 4.0, 0.0)
	target_tilt_angle = 0.0
	current_tilt_angle = lerp(current_tilt_angle, 0.0, clampf(tilt_damping * delta, 0.0, 1.0))
	hydraulic_offset = hydraulic_offset.lerp(Vector2.ZERO, clampf(8.0 * delta, 0.0, 1.0))
	pulse_intensity = maxf(pulse_intensity - delta * 3.0, 0.0)
	needle_jitter = lerp(needle_jitter, 0.0, clampf(12.0 * delta, 0.0, 1.0))
	last_discrete_step = 0


func _trigger_stepper_click(factor: float) -> void:
	var pitch := randf_range(stepper_pitch_min, stepper_pitch_max)
	stepper_clicked.emit(active_zone_id, factor, pitch)


## Преобразование мировых координат точки с учетом поворота вокруг поясного шарнира
func get_transformed_point(point: Vector2, mid_shift: Vector2) -> Vector2:
	if absf(current_tilt_angle) < 0.0001 and hydraulic_offset.is_zero_approx():
		return point
	var eff_pivot := robot_waist_pivot + mid_shift + hydraulic_offset
	var rel := point - eff_pivot
	return eff_pivot + rel.rotated(current_tilt_angle)


## Смещение для конкретной зоны относительно исходного положения
func get_zone_offset(base_pos: Vector2, mid_shift: Vector2) -> Vector2:
	var transformed := get_transformed_point(base_pos + mid_shift, mid_shift)
	return (transformed - (base_pos + mid_shift)) + hydraulic_offset


func get_tilt_angle() -> float:
	return current_tilt_angle


func get_tilt_degrees() -> float:
	return rad_to_deg(current_tilt_angle)


func get_hydraulic_offset() -> Vector2:
	return hydraulic_offset


func get_proximity_factor() -> float:
	return proximity_factor


func get_pulse_intensity() -> float:
	return pulse_intensity


func get_needle_jitter() -> float:
	return needle_jitter


func is_in_proximity() -> bool:
	return proximity_factor > 0.05


static func _dist_to_rect(p: Vector2, rect: Rect2) -> float:
	var cx := clampf(p.x, rect.position.x, rect.end.x)
	var cy := clampf(p.y, rect.position.y, rect.end.y)
	return p.distance_to(Vector2(cx, cy))
