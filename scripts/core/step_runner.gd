class_name StepRunner
extends Node

## Universal executor for tactile repair steps (контракт данных §4.2).
## Configures tactile components (ScrubZone, ScrewBoltManager, CablePlug),
## handles "hold" and "calibrate" mechanics, validates tools, tracks progress
## and instability hazards, and emits strictly ONE final signal:
## step_finished(quality) OR step_failed(reason).
## Zero GC allocations in the frame update loop.

signal step_finished(quality: float)
signal step_failed(reason: String)
signal progress_changed(value: float)
signal hazard(amount: float, message: String)

var _host: Node2D = null
var _step: Dictionary = {}
var _step_id: String = ""
var _step_type: String = ""
var _step_tool: String = "none"
var _step_params: Dictionary = {}
var _step_rect: Rect2 = Rect2()

var _is_active: bool = false
var _finished: bool = false
var _is_frozen: bool = false
var _is_type_supported: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _hint_cd: float = 0.0
var _progress_value: float = 0.0

# Component references
var _scrub_comp: ScrubZone = null
var _unbolt_comp: ScrewBoltManager = null
var _cable_comp: CablePlug = null
var _saved_active_states: Dictionary = {}

# Unbolt state
var _total_bolts: int = 0
var _slips_count: int = 0

# Cable lock state
var _cable_target_hold: float = 0.8
var _cable_hold_time: float = 0.0

# Hold state
var _hold_timer: float = 0.0
var _hold_duration: float = 3.0
var _motion_tolerance: float = 1.5
var _hold_slips: int = 0

# Calibrate state
var _calib_min: float = 0.0
var _calib_max: float = 100.0
var _calib_target: float = 50.0
var _calib_tolerance: float = 5.0
var _calib_control: String = "drag"
var _calib_hold_required: float = 0.4
var _calib_hold_timer: float = 0.0
var _calib_val: float = 0.0
var _is_dragging_calib: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_val: float = 0.0


func setup(host: Node2D, step: Dictionary) -> void:
	_disconnect_component_signals()
	_restore_component_states()

	_host = host
	_step = step
	_step_id = str(step.get("id", ""))
	_step_type = str(step.get("type", ""))
	_step_tool = str(step.get("tool", "none"))
	_step_params = step.get("params", {}) if step.get("params") is Dictionary else {}

	_is_active = false
	_finished = false
	_is_frozen = false
	_slips_count = 0
	_hold_timer = 0.0
	_hold_slips = 0
	_calib_hold_timer = 0.0
	_cable_hold_time = 0.0
	_is_dragging_calib = false
	_hint_cd = 0.0
	_progress_value = 0.0

	_scrub_comp = null
	_unbolt_comp = null
	_cable_comp = null

	_is_type_supported = (_step_type in ["scrub", "unbolt", "cable_lock", "hold", "calibrate"])
	if not _is_type_supported:
		return

	match _step_type:
		"scrub":
			_step_rect = _to_rect(_step_params.get("rect"))
			if _host and _host.has_method("get_component"):
				_scrub_comp = _host.get_component("scrub") as ScrubZone
			if _scrub_comp:
				_scrub_comp.configure(_step_rect, _step_params)
				_scrub_comp.reset()
				if not _scrub_comp.scrub_completed.is_connected(_on_scrub_completed):
					_scrub_comp.scrub_completed.connect(_on_scrub_completed)
				if not _scrub_comp.overheat_occurred.is_connected(_on_scrub_overheat):
					_scrub_comp.overheat_occurred.connect(_on_scrub_overheat)
				if not _scrub_comp.scrub_progress_changed.is_connected(_on_scrub_progress):
					_scrub_comp.scrub_progress_changed.connect(_on_scrub_progress)

		"unbolt":
			_step_rect = _to_rect(_step_params.get("hatch_rect"))
			if _host and _host.has_method("get_component"):
				_unbolt_comp = _host.get_component("unbolt") as ScrewBoltManager
			var bolts: Array = _step_params.get("bolts", [])
			_total_bolts = bolts.size()
			var slip_p: Dictionary = _step_params.get("slip_params", {}) if _step_params.get("slip_params") is Dictionary else {}
			if _unbolt_comp:
				_unbolt_comp.configure(_step_rect, bolts, slip_p)
				_unbolt_comp.reset()
				if not _unbolt_comp.hatch_removed.is_connected(_on_unbolt_hatch_removed):
					_unbolt_comp.hatch_removed.connect(_on_unbolt_hatch_removed)
				if not _unbolt_comp.tool_slipped.is_connected(_on_unbolt_tool_slipped):
					_unbolt_comp.tool_slipped.connect(_on_unbolt_tool_slipped)
				if not _unbolt_comp.bolt_loosened.is_connected(_on_unbolt_loosened):
					_unbolt_comp.bolt_loosened.connect(_on_unbolt_loosened)

		"cable_lock":
			var sp: Vector2 = _to_vector2(_step_params.get("socket_pos", Vector2(640.0, 160.0)))
			var sr: float = float(_step_params.get("socket_radius", 26.0))
			_step_rect = Rect2(sp.x - sr, sp.y - sr, sr * 2.0, sr * 2.0)
			var anchor: Vector2 = _to_vector2(_step_params.get("cable_anchor", Vector2(980.0, 640.0)))
			var home: Vector2 = _to_vector2(_step_params.get("cable_home", Vector2(940.0, 600.0)))
			_cable_target_hold = float(_step_params.get("lock_hold_time", 0.8))
			if _host and _host.has_method("get_component"):
				_cable_comp = _host.get_component("cable") as CablePlug
			if _cable_comp:
				_cable_comp.configure(sp, anchor, home, _step_params)
				_cable_comp.reset()
				if not _cable_comp.cable_locked.is_connected(_on_cable_locked):
					_cable_comp.cable_locked.connect(_on_cable_locked)

		"hold":
			_step_rect = _to_rect(_step_params.get("rect"))
			_hold_duration = float(_step_params.get("duration", 3.0))
			_motion_tolerance = float(_step_params.get("motion_tolerance", 1.5))

		"calibrate":
			_step_rect = _to_rect(_step_params.get("rect"))
			_calib_min = float(_step_params.get("min", 0.0))
			_calib_max = float(_step_params.get("max", 100.0))
			_calib_target = float(_step_params.get("target", 50.0))
			_calib_tolerance = float(_step_params.get("tolerance", 5.0))
			_calib_control = str(_step_params.get("control", "drag"))
			_calib_hold_required = float(_step_params.get("hold_time", 0.4))
			_calib_val = float(_step_params.get("initial", _calib_min))


func start() -> void:
	if not _is_type_supported:
		_fail_step("unsupported_type")
		return

	_is_active = true
	_finished = false
	_is_frozen = false
	_last_mouse_pos = _host.get_mouse_pos() if (_host and _host.has_method("get_mouse_pos")) else Vector2.ZERO
	_save_and_isolate_components()


func abort() -> void:
	if _finished:
		return
	_finished = true
	_is_active = false
	_disconnect_component_signals()
	_restore_component_states()


func set_frozen(frozen: bool) -> void:
	_is_frozen = frozen
	if not _is_frozen and _host and _host.has_method("get_mouse_pos"):
		_last_mouse_pos = _host.get_mouse_pos()


func is_active() -> bool:
	return _is_active and not _finished


func is_frozen() -> bool:
	return _is_frozen


func get_step_id() -> String:
	return _step_id


func get_step_type() -> String:
	return _step_type


## Прямоугольник активной зоны шага в мировых координатах (для подсветки в HUD).
func get_step_rect() -> Rect2:
	return _step_rect


func get_calibration_value() -> float:
	return _calib_val


func set_calibration_value(val: float) -> void:
	_calib_val = clampf(val, _calib_min, _calib_max)


## Текущий прогресс шага 0..1 (для HUD полосы).
func get_progress() -> float:
	match _step_type:
		"scrub":
			return _scrub_comp.get_clean_ratio() if _scrub_comp != null else 0.0
		"hold":
			return clampf(_hold_timer / maxf(_hold_duration, 0.001), 0.0, 1.0)
		"calibrate":
			return clampf(_calib_hold_timer / maxf(_calib_hold_required, 0.001), 0.0, 1.0)
		"cable_lock":
			return clampf(_cable_hold_time / maxf(_cable_target_hold, 0.001), 0.0, 1.0)
		_:
			return clampf(_progress_value, 0.0, 1.0)


func _is_tool_present() -> bool:
	if _host == null or not _host.has_method("is_tool_held"):
		return true
	return bool(_host.is_tool_held(_step_tool))


func _emit_tool_hint() -> void:
	if _hint_cd > 0.0:
		return
	_hint_cd = 1.4
	var label: String = _step_tool
	if _host != null and _host.has_method("get_tool_label"):
		label = str(_host.get_tool_label(_step_tool))
	emit_signal("hazard", 0.0, "НУЖЕН ИНСТРУМЕНТ: %s. Возьмите его из лотка (ЛКМ)" % label.to_upper())


func _unhandled_input(event: InputEvent) -> void:
	handle_input(event)


func handle_input(event: InputEvent) -> bool:
	if not _is_active or _finished or _is_frozen:
		return false

	var m_pos: Vector2 = _host.get_mouse_pos() if (_host and _host.has_method("get_mouse_pos")) else Vector2.ZERO
	var shift: Vector2 = _host.get_mid_shift() if (_host and _host.has_method("get_mid_shift")) else Vector2.ZERO
	var eff_rect: Rect2 = Rect2(_step_rect.position + shift, _step_rect.size)

	# Мягкая защита от неверного инструмента: шаг НЕ проваливается,
	# игрок получает подсказку и продолжает ремонт.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if (_step_type == "unbolt" or _step_type == "scrub") and _step_tool != "" and _step_tool != "none":
			var check_rect := eff_rect.grow_individual(35.0, 25.0, 35.0, 25.0) if _step_type == "scrub" else eff_rect
			if check_rect.has_area() and check_rect.has_point(m_pos) and not _is_tool_present():
				_emit_tool_hint()
				return true

	match _step_type:
		"unbolt":
			if _unbolt_comp:
				return _unbolt_comp.handle_hatch_input(event, m_pos, shift)
		"cable_lock":
			if _cable_comp:
				return _cable_comp.handle_input(event, m_pos)
		"calibrate":
			return _handle_calibrate_input(event, m_pos, eff_rect)

	return false


func _handle_calibrate_input(event: InputEvent, m_pos: Vector2, eff_rect: Rect2) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if eff_rect.has_point(m_pos):
				var step_sz: float = (_calib_max - _calib_min) * 0.05
				_calib_val = clampf(_calib_val + step_sz, _calib_min, _calib_max)
				return true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if eff_rect.has_point(m_pos):
				var step_sz: float = (_calib_max - _calib_min) * 0.05
				_calib_val = clampf(_calib_val - step_sz, _calib_min, _calib_max)
				return true
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if eff_rect.has_point(m_pos):
					_is_dragging_calib = true
					_drag_start_mouse = m_pos
					_drag_start_val = _calib_val
					return true
			elif _is_dragging_calib:
				_is_dragging_calib = false
				return true
	elif event is InputEventMouseMotion and _is_dragging_calib:
		var span: float = _calib_max - _calib_min
		var px_span: float = maxf(eff_rect.size.x, 40.0)
		var dx: float = m_pos.x - _drag_start_mouse.x
		_calib_val = clampf(_drag_start_val + (dx / px_span) * span, _calib_min, _calib_max)
		return true

	return false


func tick(delta: float) -> void:
	_process(delta)


func _process(delta: float) -> void:
	if _hint_cd > 0.0:
		_hint_cd = maxf(_hint_cd - delta, 0.0)
	if not _is_active or _finished or _is_frozen or delta <= 0.0:
		return

	match _step_type:
		"scrub":
			_process_scrub(delta)
		"unbolt":
			_process_unbolt(delta)
		"cable_lock":
			_process_cable(delta)
		"hold":
			_process_hold(delta)
		"calibrate":
			_process_calibrate(delta)


func _process_scrub(delta: float) -> void:
	if _scrub_comp == null or _host == null:
		return
	var m_pos: Vector2 = _host.get_mouse_pos()
	var is_held: bool = _host.is_tool_held(_step_tool)
	var shift: Vector2 = _host.get_mid_shift()
	if not is_held:
		var eff_rect := Rect2(_step_rect.position + shift, _step_rect.size)
		var hint_rect := _scrub_comp.get_effective_hit_rect(shift) if _scrub_comp.has_method("get_effective_hit_rect") else eff_rect
		if hint_rect.has_point(m_pos):
			_emit_tool_hint()
	_scrub_comp.update_scrub(delta, m_pos, is_held, shift)


func _process_unbolt(delta: float) -> void:
	if _unbolt_comp == null or _host == null:
		return
	var tip_pos: Vector2 = _host.get_tool_tip(_step_tool)
	var is_held: bool = _host.is_tool_held(_step_tool)
	var shift: Vector2 = _host.get_mid_shift()
	var m_pos: Vector2 = _host.get_mouse_pos()
	_unbolt_comp.update_bolts(delta, tip_pos, is_held, shift, m_pos)


func _process_cable(delta: float) -> void:
	if _cable_comp == null or _host == null:
		return
	var m_pos: Vector2 = _host.get_mouse_pos()
	var shift: Vector2 = _host.get_mid_shift()
	_cable_comp.update_cable(delta, m_pos, shift)
	if _cable_comp.is_near_socket and _cable_comp.is_dragged:
		_cable_hold_time += delta


func _process_hold(delta: float) -> void:
	if _host == null:
		return
	var m_pos: Vector2 = _host.get_mouse_pos()
	var shift: Vector2 = _host.get_mid_shift()
	var eff_rect := Rect2(_step_rect.position + shift, _step_rect.size)
	var inside: bool = eff_rect.has_point(m_pos)

	if inside:
		if _hold_timer <= 0.0:
			# Начало удержания в зоне
			_last_mouse_pos = m_pos
			_hold_timer += delta
			var prog: float = clampf(_hold_timer / maxf(_hold_duration, 0.001), 0.0, 1.0)
			emit_signal("progress_changed", prog)
		else:
			var dist: float = m_pos.distance_to(_last_mouse_pos)
			_last_mouse_pos = m_pos
			if dist <= _motion_tolerance:
				_hold_timer += delta
				var prog: float = clampf(_hold_timer / maxf(_hold_duration, 0.001), 0.0, 1.0)
				emit_signal("progress_changed", prog)
				if _hold_timer >= (_hold_duration - 0.0001):
					var q: float = 1.0 if _hold_slips == 0 else clampf(1.0 - 0.2 * float(_hold_slips), 0.2, 1.0)
					_finish_step(q)
			else:
				_hold_slips += 1
				_hold_timer = 0.0
				emit_signal("progress_changed", 0.0)
				emit_signal("hazard", 2.0, "Срыв удержания: движение курсора")
	else:
		_last_mouse_pos = m_pos
		if _hold_timer > 0.0:
			_hold_slips += 1
			_hold_timer = 0.0
			emit_signal("progress_changed", 0.0)
			emit_signal("hazard", 2.0, "Срыв удержания: выход из зоны")


func _process_calibrate(delta: float) -> void:
	var err: float = absf(_calib_val - _calib_target)
	if err <= _calib_tolerance:
		_calib_hold_timer += delta
		var prog: float = clampf(_calib_hold_timer / maxf(_calib_hold_required, 0.001), 0.0, 1.0)
		emit_signal("progress_changed", prog)
		if _calib_hold_timer >= (_calib_hold_required - 0.0001):
			var q: float = clampf(1.0 - 0.5 * (err / maxf(_calib_tolerance, 0.001)), 0.5, 1.0)
			_finish_step(q)
	else:
		_calib_hold_timer = 0.0
		emit_signal("progress_changed", 0.0)


func _finish_step(quality: float) -> void:
	if _finished:
		return
	_finished = true
	_is_active = false
	_disconnect_component_signals()
	_restore_component_states()
	emit_signal("step_finished", clampf(quality, 0.0, 1.0))


func _fail_step(reason: String) -> void:
	if _finished:
		return
	_finished = true
	_is_active = false
	_disconnect_component_signals()
	_restore_component_states()
	emit_signal("step_failed", reason)


func _on_scrub_completed() -> void:
	var q: float = 1.0
	if _scrub_comp:
		q = _scrub_comp.get_clean_ratio()
	_finish_step(q)


func _on_scrub_overheat(heat_penalty: float) -> void:
	var penalty: float = float(_step_params.get("overheat_penalty", heat_penalty))
	emit_signal("hazard", penalty, "Перегрев")


func _on_scrub_progress(_p: float) -> void:
	if _scrub_comp:
		emit_signal("progress_changed", _scrub_comp.get_clean_ratio())


func _on_unbolt_hatch_removed() -> void:
	var q: float = clampf(1.0 - 0.2 * float(_slips_count), 0.2, 1.0)
	_finish_step(q)


func _on_unbolt_tool_slipped(penalty: float, _shake: float) -> void:
	_slips_count += 1
	var p: float = penalty
	if _step_params.has("slip_params") and _step_params["slip_params"] is Dictionary:
		p = float(_step_params["slip_params"].get("slip_penalty", penalty))
	emit_signal("hazard", p, "Срыв шлица")


func _on_unbolt_loosened(_bolt_id: String, remaining: int) -> void:
	var unbolted: int = maxi(_total_bolts - remaining, 0)
	var prog: float = float(unbolted) / float(maxi(_total_bolts, 1))
	_progress_value = prog
	emit_signal("progress_changed", prog)


func _on_cable_locked() -> void:
	var overshoot: float = maxf(0.0, _cable_hold_time - _cable_target_hold)
	var q: float = clampf(1.0 - 0.3 * overshoot, 0.1, 1.0)
	_finish_step(q)


func _save_and_isolate_components() -> void:
	_saved_active_states.clear()
	if _host == null or not _host.has_method("get_component"):
		return

	var kinds := ["scrub", "unbolt", "cable"]
	var target_kind := ""
	match _step_type:
		"scrub": target_kind = "scrub"
		"unbolt": target_kind = "unbolt"
		"cable_lock": target_kind = "cable"

	for kind in kinds:
		var comp: Node2D = _host.get_component(kind)
		if comp and is_instance_valid(comp) and "is_active" in comp:
			_saved_active_states[kind] = comp.is_active
			comp.is_active = (kind == target_kind)


func _restore_component_states() -> void:
	if _host == null or not _host.has_method("get_component"):
		return

	for kind in _saved_active_states.keys():
		var comp: Node2D = _host.get_component(kind)
		if comp and is_instance_valid(comp) and "is_active" in comp:
			comp.is_active = _saved_active_states[kind]
	_saved_active_states.clear()


func _disconnect_component_signals() -> void:
	if _scrub_comp and is_instance_valid(_scrub_comp):
		if _scrub_comp.scrub_completed.is_connected(_on_scrub_completed):
			_scrub_comp.scrub_completed.disconnect(_on_scrub_completed)
		if _scrub_comp.overheat_occurred.is_connected(_on_scrub_overheat):
			_scrub_comp.overheat_occurred.disconnect(_on_scrub_overheat)
		if _scrub_comp.scrub_progress_changed.is_connected(_on_scrub_progress):
			_scrub_comp.scrub_progress_changed.disconnect(_on_scrub_progress)

	if _unbolt_comp and is_instance_valid(_unbolt_comp):
		if _unbolt_comp.hatch_removed.is_connected(_on_unbolt_hatch_removed):
			_unbolt_comp.hatch_removed.disconnect(_on_unbolt_hatch_removed)
		if _unbolt_comp.tool_slipped.is_connected(_on_unbolt_tool_slipped):
			_unbolt_comp.tool_slipped.disconnect(_on_unbolt_tool_slipped)
		if _unbolt_comp.bolt_loosened.is_connected(_on_unbolt_loosened):
			_unbolt_comp.bolt_loosened.disconnect(_on_unbolt_loosened)

	if _cable_comp and is_instance_valid(_cable_comp):
		if _cable_comp.cable_locked.is_connected(_on_cable_locked):
			_cable_comp.cable_locked.disconnect(_on_cable_locked)


func _to_rect(val: Variant) -> Rect2:
	if val is Rect2:
		return val
	if val is Array and (val as Array).size() >= 4:
		var a := val as Array
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Rect2()


func _to_vector2(val: Variant) -> Vector2:
	if val is Vector2:
		return val
	if val is Array and (val as Array).size() >= 2:
		var a := val as Array
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
