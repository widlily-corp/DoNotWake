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
var tex_gauge: Texture2D

var font: Font = ThemeDB.fallback_font
var selected_tool: String = "cloth"
var message_text: String = "Выберите инструмент и проведите ремонт узла"
var message_is_alert: bool = false
var flash_timer: float = 0.0
var screen_shake: float = 0.0

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
	if ResourceLoader.exists("res://assets/sprites/ui/gauge_meter.png"):
		tex_gauge = load("res://assets/sprites/ui/gauge_meter.png")

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

	if game_state:
		game_state.tick(delta)

	queue_redraw()


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

	# Клик по тулбару
	for t in tools:
		var raw_rect: Variant = t.get("rect", null)
		if raw_rect is Rect2 or (raw_rect is Array and (raw_rect as Array).size() == 4):
			var r: Rect2
			if raw_rect is Rect2:
				r = raw_rect
			else:
				var arr := raw_rect as Array
				r = Rect2(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))

			if r.has_point(pos):
				selected_tool = str(t.get("id", ""))
				message_text = "Выбран инструмент: " + str(t.get("label", ""))
				message_is_alert = false
				if sfx_click:
					sfx_click.play()
				return

	# Клик по активным зонам текущего этапа
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

				if r.has_point(pos):
					game_state.apply_repair(i, selected_tool)
					return


func _draw() -> void:
	var shake_offset := Vector2.ZERO
	if screen_shake > 0.0:
		shake_offset = Vector2(randf_range(-screen_shake, screen_shake), randf_range(-screen_shake, screen_shake))

	# 1. Задний фон комнаты
	if tex_room_blockout:
		draw_texture_rect(tex_room_blockout, Rect2(shake_offset, Vector2(1280, 720)), false, Color(0.55, 0.58, 0.62))
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), COLOR_BG)

	# 2. Верстак (нижняя плоскость)
	draw_rect(Rect2(Vector2(0, 560), Vector2(1280, 160)), Color(0.09, 0.10, 0.12))
	draw_line(Vector2(0, 560), Vector2(1280, 560), COLOR_BENCH_EDGE, 2.0)

	# 3. Отрисовка робота (спрайты)
	var robot_rect := Rect2(Vector2(530, 180) + shake_offset, Vector2(300, 375))
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
				r.position += shake_offset

				var is_done: bool = bool(z.get("done", false))
				var z_color := COLOR_SUCCESS if is_done else Color(0.45, 0.75, 0.95, 0.7)
				draw_rect(r, z_color, false, 2.0)
				draw_string(font, r.position + Vector2(6, -8), str(z.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_TEXT_LIGHT)

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

			var t_id := str(t.get("id", ""))
			var is_selected: bool = (selected_tool == t_id)
			var fill_color := Color(0.20, 0.28, 0.35) if is_selected else Color(0.12, 0.14, 0.17)
			var border_color := Color(0.92, 0.94, 0.96) if is_selected else Color(0.35, 0.40, 0.46)

			# Объёмная подложка ячейки (скосы и фаски)
			draw_rect(r, fill_color)
			draw_rect(r, border_color, false, 2.0 if not is_selected else 3.0)

			# Отрисовка объёмной иконки инструмента
			var icon_tex: Texture2D = null
			if t_id == "cloth":
				icon_tex = tex_tool_cloth
			elif t_id == "screwdriver":
				icon_tex = tex_tool_screw
			elif t_id == "keyboard":
				icon_tex = tex_tool_keyb

			if icon_tex:
				var icon_rect := Rect2(r.position + Vector2(6, 6), Vector2(60, 60))
				draw_texture_rect(icon_tex, icon_rect, false)
				draw_string(font, r.position + Vector2(74, 44), str(t.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT_LIGHT)
			else:
				draw_string(font, r.position + Vector2(16, 44), str(t.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR_TEXT_LIGHT)

	# 6. Верхний статус-бар: Нестабильность и Аналоговый манометр
	draw_rect(Rect2(40, 24, 620, 72), Color(0.08, 0.10, 0.12, 0.9))
	draw_rect(Rect2(40, 24, 620, 72), COLOR_BENCH_EDGE, false, 2.0)

	if tex_gauge:
		draw_texture_rect(tex_gauge, Rect2(48, 28, 64, 64), false)

	var cur_inst := game_state.robot.instability if (game_state and game_state.robot) else 20.0
	var cur_thresh := game_state.robot.threshold if (game_state and game_state.robot) else 70.0

	draw_string(font, Vector2(120, 52), "НЕСТАБИЛЬНОСТЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_TEXT_DIM)
	var bar_rect := Rect2(270, 38, 260, 22)
	draw_rect(bar_rect, Color(0.16, 0.18, 0.22))

	var fill_w := bar_rect.size.x * clampf(cur_inst / 100.0, 0.0, 1.0)
	var bar_color := Color(0.35, 0.85, 0.55).lerp(COLOR_ALERT, cur_inst / 100.0)
	draw_rect(Rect2(bar_rect.position, Vector2(fill_w, bar_rect.size.y)), bar_color)

	# Порог пробуждения (метка на шкале)
	var thresh_x := bar_rect.position.x + bar_rect.size.x * clampf(cur_thresh / 100.0, 0.0, 1.0)
	draw_line(Vector2(thresh_x, bar_rect.position.y - 4), Vector2(thresh_x, bar_rect.position.y + bar_rect.size.y + 4), COLOR_ALERT, 3.0)

	draw_string(font, Vector2(545, 54), "%d%%" % int(cur_inst), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT_LIGHT)

	# 7. Текущий этап ремонта
	if stage:
		draw_rect(Rect2(720, 24, 520, 70), Color(0.08, 0.10, 0.12, 0.9))
		draw_rect(Rect2(720, 24, 520, 70), COLOR_BENCH_EDGE, false, 2.0)
		draw_string(font, Vector2(740, 50), stage.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_TEXT_LIGHT)
		draw_string(font, Vector2(740, 76), stage.instruction, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_TEXT_DIM)

	# 8. Строка сообщений / подсказок
	var msg_col := COLOR_ALERT if message_is_alert else COLOR_TEXT_LIGHT
	draw_string(font, Vector2(880, 650), message_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, msg_col)

	# 9. Экран тревоги при пробуждении
	if is_awake:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.85, 0.15, 0.1, 0.18))
		draw_rect(Rect2(420, 106, 440, 68), Color(0.35, 0.05, 0.05, 0.95))
		draw_rect(Rect2(420, 106, 440, 68), COLOR_ALERT, false, 2.0)
		draw_string(font, Vector2(440, 144), "НЕ ДВИГАЙ МЫШЬЮ!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.85, 0.8))
		var sec_left: float = maxf(game_state.freeze_left, 0.0) if game_state else 0.0
		draw_string(font, Vector2(740, 144), "%.1f c" % sec_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.4, 0.3))

	# 10. Flash эффект при ошибке
	if flash_timer > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(1.0, 0.2, 0.1, flash_timer * 0.35))
