class_name MainView
extends Node2D

## Главное игровое представление смены ремонта робота (Do Not Wake)

@onready var game_state: GameState = $GameState
@onready var end_screen: Control = $EndScreen
@onready var sfx_click: AudioStreamPlayer = $Audio/SFXClick
@onready var sfx_repair: AudioStreamPlayer = $Audio/SFXRepair
@onready var sfx_error: AudioStreamPlayer = $Audio/SFXError
@onready var sfx_wake: AudioStreamPlayer = $Audio/SFXWake
@onready var sfx_calm: AudioStreamPlayer = $Audio/SFXCalm

# Текстуры робота и UI
var tex_robot_calm: Texture2D
var tex_robot_awake: Texture2D
var tex_room_blockout: Texture2D
var tex_tool_cloth: Texture2D
var tex_tool_screw: Texture2D
var tex_tool_keyb: Texture2D
# UI-кит (пиксель-арт, 9-slice)
var tex_gauge: Texture2D
var tex_panel: Texture2D
var tex_slot: Texture2D
var tex_slot_sel: Texture2D
var tex_bar_frame: Texture2D
var tex_cursor: Texture2D

# 9-slice margin'ы из docs/ui-art-prompts.md §5
const PANEL_MARGIN: Vector4 = Vector4(24, 24, 24, 24)
const SLOT_MARGIN: Vector4 = Vector4(24, 24, 20, 20)
const BAR_MARGIN: Vector4 = Vector4(8, 8, 8, 8)

var font: Font = ThemeDB.fallback_font
var selected_tool: String = "cloth"
var message_text: String = "Выберите инструмент и проведите ремонт узла"
var message_is_alert: bool = false
var flash_timer: float = 0.0
var screen_shake: float = 0.0

# 2.5D-глубина: риг смещений слоёв от мыши (data/parallax.json)
var parallax: ParallaxRig
var _window_focused: bool = true

# Палитра
const COLOR_BG: Color = Color(0.03, 0.03, 0.04)
const COLOR_BENCH: Color = Color(0.22, 0.24, 0.27)
const COLOR_BENCH_EDGE: Color = Color(0.42, 0.46, 0.52)
const COLOR_TEXT_LIGHT: Color = Color(0.92, 0.94, 0.96)
const COLOR_TEXT_DIM: Color = Color(0.45, 0.55, 0.57)
const COLOR_ALERT: Color = Color(0.90, 0.16, 0.10)
const COLOR_SUCCESS: Color = Color(0.35, 0.92, 0.58)

var tools: Array = []

func _ready() -> void:
	parallax = ParallaxRig.new()
	tex_robot_calm = load("res://assets/sprites/robot/robot_calm.png")
	tex_robot_awake = load("res://assets/sprites/robot/robot_awake.png")
	if ResourceLoader.exists("res://docs/blockout_room.png"):
		tex_room_blockout = load("res://docs/blockout_room.png")

	if ResourceLoader.exists("res://assets/sprites/ui/tool_cloth.png"):
		tex_tool_cloth = load("res://assets/sprites/ui/tool_cloth.png")
	if ResourceLoader.exists("res://assets/sprites/ui/tool_screwdriver.png"):
		tex_tool_screw = load("res://assets/sprites/ui/tool_screwdriver.png")
	if ResourceLoader.exists("res://assets/sprites/ui/tool_keyboard.png"):
		tex_tool_keyb = load("res://assets/sprites/ui/tool_keyboard.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_gauge_face.png"):
		tex_gauge = load("res://assets/sprites/ui/ui_gauge_face.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_panel.png"):
		tex_panel = load("res://assets/sprites/ui/ui_panel.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_slot_plate.png"):
		tex_slot = load("res://assets/sprites/ui/ui_slot_plate.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_slot_plate_selected.png"):
		tex_slot_sel = load("res://assets/sprites/ui/ui_slot_plate_selected.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_bar_frame.png"):
		tex_bar_frame = load("res://assets/sprites/ui/ui_bar_frame.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_cursor.png"):
		tex_cursor = load("res://assets/sprites/ui/ui_cursor.png")
		Input.set_custom_mouse_cursor(tex_cursor, Input.CURSOR_ARROW, Vector2(7, 8))

	if game_state:
		game_state.feedback_triggered.connect(_on_feedback)
		game_state.state_changed.connect(_on_state_changed)
		game_state.game_finished.connect(_on_game_finished)

		if game_state.balance:
			tools = game_state.balance.get_tools()

	if tools.size() > 0:
		selected_tool = str(tools[0].get("id", "cloth"))


func _on_feedback(msg: String, is_alert: bool) -> void:
	message_text = msg
	message_is_alert = is_alert
	if is_alert:
		flash_timer = 0.4
		screen_shake = 6.0
		if sfx_error:
			sfx_error.play()
	else:
		if sfx_repair:
			sfx_repair.play()


func _on_state_changed(new_state: GameState.State) -> void:
	if new_state == GameState.State.AWAKE:
		screen_shake = 12.0
		if sfx_wake:
			sfx_wake.play()
	elif new_state == GameState.State.CALM:
		if sfx_calm:
			sfx_calm.play()


func _on_game_finished(is_success: bool) -> void:
	if end_screen and game_state and game_state.robot:
		end_screen.show_result(is_success, game_state.robot.wake_count, game_state.robot.instability)


func _process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer = maxf(flash_timer - delta, 0.0)
	if screen_shake > 0.0:
		screen_shake = maxf(screen_shake - delta * 20.0, 0.0)

	if parallax:
		if _window_focused:
			parallax.update(delta, get_global_mouse_position(), get_viewport_rect().size)
		else:
			parallax.reset()

	if game_state:
		game_state.tick(delta)

	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		if parallax:
			parallax.reset()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true


## Смещение именованного слоя (без тряски): один источник правды для _draw и кликов.
func _layer_shift(layer_name: String) -> Vector2:
	if parallax == null:
		return Vector2.ZERO
	return parallax.offset_for_layer(layer_name)


## 9-slice: рисует текстуру с нерастягиваемыми углами (margins — Vector4 слева, сверху, справа, снизу).
func _draw_nine(tex: Texture2D, rect: Rect2, margins: Vector4, tint: Color = Color.WHITE) -> void:
	if tex == null:
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw <= margins.x + margins.z or th <= margins.y + margins.w \
		or rect.size.x <= margins.x + margins.z or rect.size.y <= margins.y + margins.w:
		draw_texture_rect(tex, rect, false, tint)
		return
	var src_x := [0.0, margins.x, tw - margins.z, tw]
	var src_y := [0.0, margins.y, th - margins.w, th]
	var dst_x := [rect.position.x, rect.position.x + margins.x, rect.end.x - margins.z, rect.end.x]
	var dst_y := [rect.position.y, rect.position.y + margins.y, rect.end.y - margins.w, rect.end.y]
	for i in 3:
		for j in 3:
			var src := Rect2(float(src_x[i]), float(src_y[j]),
				float(src_x[i + 1]) - float(src_x[i]), float(src_y[j + 1]) - float(src_y[j]))
			var dst := Rect2(float(dst_x[i]), float(dst_y[j]),
				float(dst_x[i + 1]) - float(dst_x[i]), float(dst_y[j + 1]) - float(dst_y[j]))
			if src.size.x > 0.0 and src.size.y > 0.0 and dst.size.x > 0.0 and dst.size.y > 0.0:
				draw_texture_rect_region(tex, dst, src, tint)


func _input(event: InputEvent) -> void:
	if game_state == null:
		return

	if game_state.current_state == GameState.State.DONE or game_state.current_state == GameState.State.FAIL:
		return

	if event is InputEventMouseMotion and game_state.current_state == GameState.State.AWAKE:
		var motion := event as InputEventMouseMotion
		game_state.on_mouse_moved(motion.relative.length())
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click((event as InputEventMouseButton).position)


func _handle_click(pos: Vector2) -> void:
	if game_state.current_state == GameState.State.AWAKE:
		return

	# Клик по тулбару: тулбар нарисован со смещением near — компенсируем его.
	var near_shift := _layer_shift("near")
	var tool_pos := pos - near_shift
	for t in tools:
		var raw_rect: Variant = t.get("rect", null)
		if raw_rect is Rect2 or (raw_rect is Array and (raw_rect as Array).size() == 4):
			var r: Rect2
			if raw_rect is Rect2:
				r = raw_rect
			else:
				var arr := raw_rect as Array
				r = Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))

			if r.has_point(tool_pos):
				selected_tool = str(t.get("id", ""))
				message_text = "Выбран инструмент: " + str(t.get("label", ""))
				message_is_alert = false
				if sfx_click:
					sfx_click.play()
				return

	# Клик по активным зонам текущего этапа: они нарисованы со смещением mid.
	var mid_shift := _layer_shift("mid")
	var zone_pos := pos - mid_shift
	var stage: RepairStage = game_state.get_current_stage()
	if stage:
		for i in range(stage.zones.size()):
			var z: Dictionary = stage.zones[i]
			var raw_rect: Variant = z.get("rect", null)
			if raw_rect is Rect2 or (raw_rect is Array and (raw_rect as Array).size() == 4):
				var r: Rect2
				if raw_rect is Rect2:
					r = raw_rect
				else:
					var arr := raw_rect as Array
					r = Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))

				if r.has_point(zone_pos):
					game_state.apply_repair(i, selected_tool)
					return


func _draw() -> void:
	var shake_offset := Vector2.ZERO
	if screen_shake > 0.0:
		shake_offset = Vector2(randf_range(-screen_shake, screen_shake), randf_range(-screen_shake, screen_shake))

	# Смещения слоёв: параллакс (2.5D) + тряска поверх для фона/робота/зон.
	var far_shift := _layer_shift("far") + shake_offset
	var mid_shift := _layer_shift("mid")
	var near_shift := _layer_shift("near")

	# 1. Задний фон комнаты (подложка закрывает край при смещении far)
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), COLOR_BG)
	if tex_room_blockout:
		draw_texture_rect(tex_room_blockout, Rect2(far_shift, Vector2(1280, 720)), false, Color(0.55, 0.58, 0.62))

	# 2. Верстак (нижняя плоскость)
	draw_rect(Rect2(Vector2(0, 560) + mid_shift, Vector2(1280, 160)), Color(0.09, 0.10, 0.12))
	draw_line(Vector2(0, 560) + mid_shift, Vector2(1280, 560) + mid_shift, COLOR_BENCH_EDGE, 2.0)

	# 3. Отрисовка робота (спрайты)
	var robot_rect := Rect2(Vector2(530, 180) + mid_shift + shake_offset, Vector2(300, 375))
	var is_awake := (game_state and game_state.current_state == GameState.State.AWAKE)
	var current_tex := tex_robot_awake if is_awake else tex_robot_calm

	if current_tex:
		draw_texture_rect(current_tex, robot_rect, false)
	else:
		# Фолбэк прямоугольник
		var heat_col := Color(0.35, 0.45, 0.52).lerp(COLOR_ALERT, game_state.robot.get_heat_ratio() if game_state and game_state.robot else 0.0)
		draw_rect(robot_rect, heat_col)

	# 4. Зоны текущего этапа ремонта
	var stage: RepairStage = game_state.get_current_stage() if game_state else null
	if stage:
		for z in stage.zones:
			var raw_rect: Variant = z.get("rect", null)
			if raw_rect is Rect2 or (raw_rect is Array and (raw_rect as Array).size() == 4):
				var r: Rect2
				if raw_rect is Rect2:
					r = raw_rect
				else:
					var arr := raw_rect as Array
					r = Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
				r.position += mid_shift + shake_offset

				var is_done: bool = bool(z.get("done", false))
				var z_color := COLOR_SUCCESS if is_done else Color(0.45, 0.75, 0.95, 0.7)
				draw_rect(r, z_color, false, 2.0)
				draw_string(font, r.position + Vector2(6, -8), str(z.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_LIGHT)

	# 5. Панель инструментов (объёмные металлические слоты со спрайтами)
	for t in tools:
		var raw_rect: Variant = t.get("rect", null)
		if raw_rect is Rect2 or (raw_rect is Array and (raw_rect as Array).size() == 4):
			var r: Rect2
			if raw_rect is Rect2:
				r = raw_rect
			else:
				var arr := raw_rect as Array
				r = Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))

			r.position += near_shift
			var t_id := str(t.get("id", ""))
			var is_selected: bool = (selected_tool == t_id)

			# Объёмная плита лотка (9-slice), поверх неё иконка и подпись
			var plate: Texture2D = tex_slot_sel if is_selected else tex_slot
			if plate:
				_draw_nine(plate, r, SLOT_MARGIN, Color(1.10, 1.12, 1.15))
			else:
				draw_rect(r, Color(0.20, 0.28, 0.35) if is_selected else Color(0.12, 0.14, 0.17))
				draw_rect(r, Color(0.92, 0.94, 0.96) if is_selected else Color(0.35, 0.40, 0.46), false, 2.0)

			# Отрисовка объёмной иконки инструмента
			var icon_tex: Texture2D = null
			if t_id == "cloth":
				icon_tex = tex_tool_cloth
			elif t_id == "screwdriver":
				icon_tex = tex_tool_screw
			elif t_id == "keyboard":
				icon_tex = tex_tool_keyb

			var label_col := Color(0.93, 0.94, 0.96) if is_selected else Color(0.72, 0.77, 0.82)
			if icon_tex:
				var icon_rect := Rect2(r.position + Vector2(10, 6), Vector2(60, 60))
				draw_texture_rect(icon_tex, icon_rect, false)
				draw_string(font, r.position + Vector2(80, 44), str(t.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_col)
			else:
				draw_string(font, r.position + Vector2(16, 44), str(t.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_col)

	# 6. Верхний статус-бар: Нестабильность и Аналоговый манометр
	var cur_inst := game_state.robot.instability if (game_state and game_state.robot) else 20.0
	var cur_thresh := game_state.robot.threshold if (game_state and game_state.robot) else 70.0
	var inst_ratio := clampf(cur_inst / 100.0, 0.0, 1.0)
	var status_rect := Rect2(40, 24, 620, 72)

	if tex_panel:
		_draw_nine(tex_panel, status_rect, PANEL_MARGIN, Color(1.18, 1.22, 1.26))
	else:
		draw_rect(status_rect, Color(0.08, 0.10, 0.12, 0.9))
		draw_rect(status_rect, COLOR_BENCH_EDGE, false, 2.0)

	# Манометр: циферблат из спрайта + стрелка из кода
	var gauge_rect := Rect2(48, 28, 64, 64)
	if tex_gauge:
		draw_texture_rect(tex_gauge, gauge_rect, false)
	var hub := gauge_rect.position + gauge_rect.size * 0.5
	var needle_ang := deg_to_rad(lerp(135.0, 405.0, inst_ratio))
	var needle_col := COLOR_ALERT if inst_ratio >= 0.7 else Color(0.92, 0.94, 0.96)
	draw_line(hub, hub + Vector2(cos(needle_ang), sin(needle_ang)) * 19.0, needle_col, 2.0)
	draw_circle(hub, 2.0, Color(0.35, 0.38, 0.42))

	draw_string(font, Vector2(120, 52), "НЕСТАБИЛЬНОСТЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)

	# Шкала: заливка + рамка-жёлоб (9-slice) + метка порога
	var bar_rect := Rect2(270, 38, 260, 22)
	var bar_inner := bar_rect.grow(-6.0)
	if tex_bar_frame == null:
		draw_rect(bar_rect, Color(0.16, 0.18, 0.22))

	var fill_w := bar_inner.size.x * inst_ratio
	var bar_color := Color(0.35, 0.85, 0.55).lerp(COLOR_ALERT, inst_ratio)
	draw_rect(Rect2(bar_inner.position, Vector2(fill_w, bar_inner.size.y)), bar_color)

	if tex_bar_frame:
		_draw_nine(tex_bar_frame, bar_rect, BAR_MARGIN, Color(1.15, 1.18, 1.22))

	var thresh_t := clampf(cur_thresh / 100.0, 0.0, 1.0)
	var thresh_x := bar_inner.position.x + bar_inner.size.x * thresh_t
	draw_line(Vector2(thresh_x, bar_rect.position.y - 2), Vector2(thresh_x, bar_rect.end.y + 2), COLOR_ALERT, 2.0)

	draw_string(font, Vector2(545, 54), "%d%%" % int(cur_inst), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_LIGHT)

	# 7. Текущий этап ремонта
	if stage:
		var stage_rect := Rect2(720, 24, 520, 70)
		if tex_panel:
			_draw_nine(tex_panel, stage_rect, PANEL_MARGIN, Color(1.18, 1.22, 1.26))
		else:
			draw_rect(stage_rect, Color(0.08, 0.10, 0.12, 0.9))
			draw_rect(stage_rect, COLOR_BENCH_EDGE, false, 2.0)
		draw_string(font, Vector2(740, 50), stage.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_LIGHT)
		draw_string(font, Vector2(740, 76), stage.instruction, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_TEXT_DIM)

	# 8. Строка сообщений / подсказок (перенос по ширине, чтобы не уезжала за край)
	var msg_col := COLOR_ALERT if message_is_alert else COLOR_TEXT_LIGHT
	draw_multiline_string(font, Vector2(852, 634), message_text, HORIZONTAL_ALIGNMENT_LEFT, 424, 9, -1, msg_col)

	# 9. Экран тревоги при пробуждении
	if is_awake:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.85, 0.15, 0.1, 0.18))
		draw_rect(Rect2(420, 106, 440, 68), Color(0.35, 0.05, 0.05, 0.95))
		draw_rect(Rect2(420, 106, 440, 68), COLOR_ALERT, false, 2.0)
		draw_string(font, Vector2(440, 144), "НЕ ДВИГАЙ МЫШЬЮ!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.8))
		var sec_left: float = maxf(game_state.freeze_left, 0.0) if game_state else 0.0
		draw_string(font, Vector2(760, 144), "%.1f c" % sec_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.4, 0.3))

	# 10. Flash эффект при ошибке
	if flash_timer > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(1.0, 0.2, 0.1, flash_timer * 0.35))
