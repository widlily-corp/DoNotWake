extends Node2D
## Прототип Do Not Wake.
## Петля: выбрать инструмент -> применить к зоне робота -> отклик -> изменилась нестабильность.
## Все числа баланса лежат в res://data/robot.json (data-driven, без магии в коде).

## Путь к сцене главного меню. Поменяй под свой проект, если файл называется иначе.
const MAIN_MENU_PATH := "res://scenes/ui/MainMenu.tscn"

var cfg: Dictionary = {}
var font: Font = ThemeDB.fallback_font

var instability: float = 20.0
var threshold: float = 70.0
var state: String = "calm"        # calm / awake / done / fail
var selected_tool: String = ""
var freeze_left: float = 0.0
var flash: float = 0.0
var message: String = ""

var zones: Array = []
var tools: Array = []

@onready var sfx_click: AudioStreamPlayer = $SfxClick
@onready var sfx_wake: AudioStreamPlayer = $SfxWake

func _ready() -> void:
	cfg = _load_config("res://data/robot.json")
	instability = _num("start_instability", 20.0)
	threshold = _num("threshold", 70.0)
	zones = [
		{"id": "panel", "rect": Rect2(585, 315, 190, 105), "tool": "screwdriver", "done": false, "label": "Панель"},
		{"id": "contacts", "rect": Rect2(585, 445, 190, 105), "tool": "cloth", "done": false, "label": "Контакты"},
	]
	tools = [
		{"id": "cloth", "rect": Rect2(120, 615, 220, 72), "label": "Тряпка"},
		{"id": "screwdriver", "rect": Rect2(370, 615, 220, 72), "label": "Отвёртка"},
		{"id": "keyboard", "rect": Rect2(620, 615, 220, 72), "label": "Клавиатура"},
	]


func _load_config(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Нет файла данных: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("Битый JSON: " + path)
	return {}


func _num(key: String, fallback: float) -> float:
	if cfg.has(key):
		return float(cfg[key])
	return fallback


func _process(delta: float) -> void:
	flash = maxf(flash - delta, 0.0)

	if state == "awake":
		freeze_left -= delta
		if freeze_left <= 0.0:
			_calm_down()
	elif state == "calm":
		instability += _num("idle_growth", 0.4) * delta
		if instability >= threshold:
			_start_wake()
		instability = minf(instability, 100.0)

	queue_redraw()


func _input(event: InputEvent) -> void:
	# Esc -> главное меню. Проверяем в самом начале, чтобы работало в любом состоянии.
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_exit_to_menu()
			return

	if state == "done" or state == "fail":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_tree().reload_current_scene()
		return

	if event is InputEventMouseMotion and state == "awake":
		var motion := event as InputEventMouseMotion
		if motion.relative.length() > _num("freeze_motion_limit", 1.0):
			_break_freeze()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click((event as InputEventMouseButton).position)


func _play_click(pitch: float = 1.0) -> void:
	sfx_click.pitch_scale = pitch
	sfx_click.play()


func _exit_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	sfx_wake.stop()
	var err := get_tree().change_scene_to_file(MAIN_MENU_PATH)
	if err != OK:
		push_error("Не удалось открыть главное меню: %s (код %d)" % [MAIN_MENU_PATH, err])


func _on_click(pos: Vector2) -> void:
	if state == "awake":
		return

	for tool in tools:
		if (tool["rect"] as Rect2).has_point(pos):
			selected_tool = str(tool["id"])
			message = "Выбрано: " + str(tool["label"])
			_play_click()
			return

	for i in zones.size():
		var zone: Dictionary = zones[i]
		if (zone["rect"] as Rect2).has_point(pos) and not bool(zone["done"]):
			_use_zone(i)
			return


func _use_zone(index: int) -> void:
	var zone: Dictionary = zones[index]
	if zone["done"]:
		return

	if selected_tool == str(zone["tool"]):
		zone["done"] = true
		instability = maxf(instability - _num("success_reward", 5.0), 0.0)
		message = "Сделано: " + str(zone["label"])
		_play_click(1.18)
	else:
		instability = minf(instability + _num("wrong_tool_penalty", 8.0), 100.0)
		flash = 0.45
		message = "Не тот инструмент"
		_play_click(0.82)

	if _all_done():
		state = "done"
	elif instability >= threshold and state == "calm":
		_start_wake()
	elif instability >= 100.0:
		state = "fail"


func _all_done() -> bool:
	for zone in zones:
		if not bool(zone["done"]):
			return false
	return true


func _start_wake() -> void:
	state = "awake"
	freeze_left = _num("freeze_seconds", 6.0)
	message = "Робот просыпается"
	sfx_wake.play()


func _break_freeze() -> void:
	instability = minf(instability + _num("freeze_penalty", 15.0), 100.0)
	freeze_left += 1.5
	flash = 0.5
	if instability >= 100.0:
		state = "fail"
		sfx_wake.stop()


func _calm_down() -> void:
	state = "calm"
	instability = _num("calm_after_wake", 45.0)
	threshold = maxf(threshold - 5.0, 45.0)
	message = "Робот успокоился. Порог снизился"
	sfx_wake.stop()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.07, 0.07, 0.09))
	draw_rect(Rect2(0, 560, 1280, 160), Color(0.11, 0.10, 0.12))
	draw_line(Vector2(0, 560), Vector2(1280, 560), Color(0.25, 0.22, 0.25), 2.0)
	draw_rect(Rect2(70, 250, 1140, 22), Color(0.20, 0.16, 0.14))

	var heat: float = clampf((instability - 20.0) / 80.0, 0.0, 1.0)
	var body_color: Color = Color(0.34, 0.44, 0.50).lerp(Color(0.78, 0.22, 0.16), heat)
	var jitter := Vector2.ZERO
	if state == "awake":
		jitter = Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0))

	draw_rect(Rect2(Vector2(560, 290) + jitter, Vector2(240, 300)), body_color)
	draw_rect(Rect2(Vector2(600, 180) + jitter, Vector2(160, 100)), body_color.lightened(0.10))

	var eye := Color(0.4, 0.9, 0.6)
	if state == "awake":
		eye = Color(1.0, 0.25, 0.2)
	elif heat > 0.5:
		eye = Color(0.95, 0.75, 0.25)
	draw_circle(Vector2(640, 228) + jitter, 11.0, eye)
	draw_circle(Vector2(720, 228) + jitter, 11.0, eye)

	for zone in zones:
		var rect: Rect2 = zone["rect"]
		var zone_color := Color(0.55, 0.62, 0.68, 0.55)
		if bool(zone["done"]):
			zone_color = Color(0.35, 0.75, 0.45, 0.55)
		draw_rect(rect, zone_color, false, 2.0)
		var label_pos := Vector2(rect.position.x, rect.position.y - 8)
		draw_string(font, label_pos, str(zone["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.78, 0.82))

	for tool in tools:
		var tool_rect: Rect2 = tool["rect"]
		var picked: bool = selected_tool == str(tool["id"])
		var fill := Color(0.22, 0.24, 0.28)
		if picked:
			fill = Color(0.30, 0.45, 0.60)
		draw_rect(tool_rect, fill)
		draw_rect(tool_rect, Color(0.45, 0.50, 0.58), false, 2.0)
		draw_string(font, tool_rect.position + Vector2(14, 44), str(tool["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.90, 0.92, 0.95))

	draw_string(font, Vector2(40, 60), "СТАБИЛЬНОСТЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.63, 0.68))
	draw_rect(Rect2(240, 42, 300, 24), Color(0.18, 0.18, 0.21))
	draw_rect(Rect2(240, 42, 300.0 * clampf(instability / 100.0, 0.0, 1.0), 24), Color(0.85, 0.35, 0.25))
	draw_string(font, Vector2(556, 62), str(int(instability)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.9, 0.9))

	# Подсказка про выход в меню
	draw_string(font, Vector2(40, 100), "ESC — главное меню", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.55, 0.58, 0.62))

	if message != "":
		draw_string(font, Vector2(560, 660), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.85, 0.85, 0.88))

	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(1.0, 0.25, 0.2, flash * 0.35))

	if state == "awake":
		draw_rect(Rect2(Vector2(860, 40), Vector2(380, 70)), Color(0.35, 0.05, 0.05))
		draw_string(font, Vector2(880, 88), "НЕ ДВИГАЙСЯ", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1.0, 0.75, 0.7))
		draw_string(font, Vector2(880, 130), "%.1f c" % maxf(freeze_left, 0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.6, 0.55))

	if state == "done":
		draw_rect(Rect2(Vector2(340, 300), Vector2(600, 160)), Color(0.06, 0.12, 0.08))
		draw_string(font, Vector2(380, 370), "ЗАКАЗ ВЫПОЛНЕН", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.6, 0.95, 0.7))
		draw_string(font, Vector2(380, 415), "ЛКМ — начать заново", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.9, 0.85))

	if state == "fail":
		draw_rect(Rect2(Vector2(340, 300), Vector2(600, 160)), Color(0.14, 0.05, 0.05))
		draw_string(font, Vector2(380, 370), "СМЕНА ПРОВАЛЕНА", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1.0, 0.55, 0.5))
		draw_string(font, Vector2(380, 415), "ЛКМ — начать заново", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.8, 0.8))
