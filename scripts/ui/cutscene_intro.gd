class_name CutsceneIntro
extends Control

## Кинематографичный пролог и терминальный брифинг (Do Not Wake)
## Воспроизводит армейский терминал с посимвольным телетайпом,
## ЭЛТ-сканлайнами, мерцающим курсором и строгим соблюдением лора игры.

signal cutscene_completed

# Публичные переменные состояния (строго по спецификации)
var is_active: bool = true
var fade_alpha: float = 1.0 # 1.0 = глухой черный экран, 0.0 = терминал открыт
var is_typing_finished: bool = false
var is_fading_in: bool = true
var is_fading_out: bool = false

# Конфигурация таймингов
@export var fade_in_duration: float = 0.45
@export var fade_out_duration: float = 0.50
@export var char_typing_speed: float = 0.016 # ~60 символов в секунду
@export var punctuation_pause: float = 0.07
@export var line_break_pause: float = 0.05

# Цветовая палитра (CRT Phosphor)
const COLOR_PHOSPHOR_BG: Color = Color(0.0392, 0.0510, 0.0706, 1.0) # #0A0D12
const COLOR_TERMINAL_CYAN: Color = Color(0.5020, 0.8471, 0.7843, 1.0) # #80D8C8
const COLOR_TERMINAL_BRIGHT: Color = Color(0.6431, 1.0, 0.9412, 1.0) # #A4FFF0
const COLOR_TERMINAL_DIM: Color = Color(0.2902, 0.5451, 0.5020, 1.0) # #4A8B80
const COLOR_ALERT_RED: Color = Color(0.9020, 0.1569, 0.0824, 1.0) # #E62815
const COLOR_ALERT_BG: Color = Color(0.9020, 0.1569, 0.0824, 0.22)
const COLOR_ALERT_DIM: Color = Color(0.68, 0.28, 0.24, 1.0)
const COLOR_WARNING_ORANGE: Color = Color(0.95, 0.72, 0.28, 1.0)
const COLOR_BORDER_FRAME: Color = Color(0.12, 0.25, 0.22, 1.0)

# Геометрия терминала (Canvas 1280x720)
const CANVAS_SIZE: Vector2 = Vector2(1280.0, 720.0)
const FRAME_RECT: Rect2 = Rect2(120.0, 36.0, 1040.0, 648.0)
const HEADER_RECT: Rect2 = Rect2(144.0, 52.0, 992.0, 44.0)
const ALERT_BOX_RECT: Rect2 = Rect2(144.0, 484.0, 992.0, 48.0)

# Внутреннее состояние тайпврайтера
var font: Font = ThemeDB.fallback_font
var header_title: String = "КОМПЛЕКС «АНТРАЦИТ» // СЕКТОР ГЛУБОКОЙ ИЗОЛЯЦИИ 07"
var header_status: String = "СТАТУС: ТРЕВОГА // ЭКСТРЕННЫЙ РЕЖИМ"
var _lines: Array[Dictionary] = []
var _current_line_idx: int = 0
var _current_char_idx: int = 0
var _char_timer: float = 0.0
var _wait_timer: float = 0.0
var _pulse_timer: float = 0.0
var _cursor_blink_timer: float = 0.0
var _cursor_visible: bool = true
var _status_led_blink: bool = false
var _typed_char_count: int = 0

# Кэш подстроки набора и сканлайнов (Zero-allocation в _draw)
var _cached_typing_substr: String = ""
var _cached_typing_width: float = 0.0
var _last_cached_char_idx: int = -1
var _last_cached_line_idx: int = -1
var _scanline_points: PackedVector2Array = PackedVector2Array()

# Аудио
var _sfx_player: AudioStreamPlayer = null


func _init() -> void:
	custom_minimum_size = CANVAS_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_content()


func _ready() -> void:
	if font == null:
		font = ThemeDB.fallback_font
	if size == Vector2.ZERO:
		size = CANVAS_SIZE
	_setup_scanlines()
	_setup_audio()
	queue_redraw()


func _setup_content() -> void:
	_lines = [
		# Блок 1: Сводка инцидента
		{
			"text": "[!] СВОДКА ИНЦИДЕНТА // АВАРИЙНЫЙ ЖУРНАЛ СЕКТОРА 07:",
			"color": COLOR_TERMINAL_DIM,
			"size": 11,
			"x": 168.0,
			"y": 124.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.08
		},
		{
			"text": "> ЛОКАЦИЯ:   КОМПЛЕКС «АНТРАЦИТ» // СЕКТОР ГЛУБОКОЙ ИЗОЛЯЦИИ 07",
			"color": COLOR_TERMINAL_CYAN,
			"size": 13,
			"x": 168.0,
			"y": 152.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.04
		},
		{
			"text": "> ОБЪЕКТ:    ШТУРМОВОЙ АВТОМАТОН «ВЕПРЬ-04» (СЕРИЯ «ЦЕРБЕР»)",
			"color": COLOR_TERMINAL_BRIGHT,
			"size": 13,
			"x": 168.0,
			"y": 180.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.04
		},
		{
			"text": "> СОБЫТИЕ:   СРЫВ БОЕВОЙ МАТРИЦЫ НА СМЕНЕ. 4 ТЕХНИКА ПОГИБЛИ.",
			"color": COLOR_ALERT_DIM,
			"size": 11,
			"x": 168.0,
			"y": 208.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.06
		},
		{
			"text": "> СТАТУС:    ПОДАВЛЕН ВЫСОКОВОЛЬТНЫМ ЭМИ, ПРИКОВАН К СТАПЕЛЮ.",
			"color": COLOR_TERMINAL_CYAN,
			"size": 11,
			"x": 168.0,
			"y": 236.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.04
		},
		{
			"text": "─────────────────────────────────────────────────────────────────────────────────",
			"color": COLOR_BORDER_FRAME,
			"size": 10,
			"x": 168.0,
			"y": 262.0,
			"is_alert": false,
			"is_divider": true,
			"pause": 0.03
		},
		# Блок 2: Оперативная обстановка
		{
			"text": "[!] ОПЕРАТИВНАЯ ОБСТАНОВКА И ОЦЕНКА УГРОЗЫ:",
			"color": COLOR_TERMINAL_DIM,
			"size": 11,
			"x": 168.0,
			"y": 288.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.08
		},
		{
			"text": "> НЕСТАБИЛЬНОСТЬ ЛОГИЧЕСКОГО ЯДРА РАСТЁТ // ПРЕДДВЕРИЕ ПРОБУЖДЕНИЯ.",
			"color": COLOR_TERMINAL_CYAN,
			"size": 13,
			"x": 168.0,
			"y": 316.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.04
		},
		{
			"text": "> ОПАСНОСТЬ: РЫВКИ МЫШИ, СКРЕЖЕТ МЕТАЛЛА ИЛИ ТРЕНИЕ РАЗБУДЯТ МАШИНУ.",
			"color": COLOR_WARNING_ORANGE,
			"size": 13,
			"x": 168.0,
			"y": 344.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.05
		},
		{
			"text": "> ПОРОГ:     ПРИ НЕСТАБИЛЬНОСТИ >70% СИЛОВЫЕ РЕМНИ НЕ ВЫДЕРЖАТ.",
			"color": COLOR_ALERT_RED,
			"size": 13,
			"x": 168.0,
			"y": 372.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.06
		},
		{
			"text": "> ЗАДАЧА:    ПРОВЕСТИ ПОЛЕВОЙ РЕМОНТ ДО ПРИБЫТИЯ КОНВОЯ УТИЛИЗАЦИИ.",
			"color": COLOR_TERMINAL_BRIGHT,
			"size": 13,
			"x": 168.0,
			"y": 400.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.05
		},
		{
			"text": "─────────────────────────────────────────────────────────────────────────────────",
			"color": COLOR_BORDER_FRAME,
			"size": 10,
			"x": 168.0,
			"y": 426.0,
			"is_alert": false,
			"is_divider": true,
			"pause": 0.03
		},
		# Блок 3: Директива и главное правило
		{
			"text": "ДИРЕКТИВА СЛУЖБЫ БЕЗОПАСНОСТИ // ИСКЛЮЧИТЕЛЬНЫЙ ПРОТОКОЛ:",
			"color": COLOR_ALERT_DIM,
			"size": 11,
			"x": 168.0,
			"y": 454.0,
			"is_alert": false,
			"is_divider": false,
			"pause": 0.08
		},
		{
			"text": "[!] ГЛАВНОЕ ПРАВИЛО: НЕ БУДИ ЕГО.",
			"color": COLOR_ALERT_RED,
			"size": 16,
			"x": 168.0,
			"y": 514.0,
			"is_alert": true,
			"is_divider": false,
			"pause": 0.20
		}
	]


func _setup_scanlines() -> void:
	var total_scanlines: int = int((FRAME_RECT.size.y) / 3.0)
	_scanline_points.resize(total_scanlines * 2)
	var idx: int = 0
	var y: float = FRAME_RECT.position.y
	while y < FRAME_RECT.end.y:
		_scanline_points[idx] = Vector2(FRAME_RECT.position.x, y)
		_scanline_points[idx + 1] = Vector2(FRAME_RECT.end.x, y)
		idx += 2
		y += 3.0
	_scanline_points.resize(idx)


func _setup_audio() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "CutsceneSFX"
	if ResourceLoader.exists("res://assets/sounds/click.wav"):
		_sfx_player.stream = load("res://assets/sounds/click.wav")
	add_child(_sfx_player)


func _process(delta: float) -> void:
	if not is_active:
		return

	# 1. Плавный вход из черного экрана в терминал
	if is_fading_in:
		fade_alpha = maxf(fade_alpha - delta / maxf(fade_in_duration, 0.001), 0.0)
		if fade_alpha <= 0.0:
			is_fading_in = false

	# 2. Плавный выход в игру
	if is_fading_out:
		fade_alpha = minf(fade_alpha + delta / maxf(fade_out_duration, 0.001), 1.0)
		if fade_alpha >= 1.0:
			_complete_cutscene()
			return

	# 3. Тайпврайтер текста
	if not is_typing_finished and not is_fading_in:
		var remaining_delta: float = delta
		if _wait_timer > 0.0:
			if remaining_delta < _wait_timer:
				_wait_timer -= remaining_delta
				remaining_delta = 0.0
			else:
				remaining_delta -= _wait_timer
				_wait_timer = 0.0

		if remaining_delta > 0.0:
			_char_timer += remaining_delta
			while _char_timer >= char_typing_speed and not is_typing_finished and _wait_timer <= 0.0:
				_char_timer -= char_typing_speed
				_advance_char()

	# 4. Анимация курсора и пульсации
	_cursor_blink_timer += delta
	if _cursor_blink_timer >= 0.28:
		_cursor_blink_timer = 0.0
		_cursor_visible = not _cursor_visible
		_status_led_blink = not _status_led_blink

	_pulse_timer += delta * 3.8
	queue_redraw()


func _advance_char() -> void:
	if _current_line_idx >= _lines.size():
		is_typing_finished = true
		return

	var line: Dictionary = _lines[_current_line_idx]
	var line_text: String = line["text"]

	if _current_char_idx < line_text.length():
		var char_at: String = line_text[_current_char_idx]
		_current_char_idx += 1
		_typed_char_count += 1

		# Звук клавиши телетайпа каждые 3 символа
		if _typed_char_count % 3 == 0 and char_at != " ":
			_play_click(randf_range(0.95, 1.15), -16.0)

		# Дополнительная пауза на знаках препинания
		if char_at in [".", "!", "?", ":"]:
			_wait_timer = punctuation_pause
	else:
		# Переход на следующую строку
		_wait_timer = float(line.get("pause", line_break_pause))
		_current_line_idx += 1
		_current_char_idx = 0
		if _current_line_idx >= _lines.size():
			is_typing_finished = true
			_current_line_idx = _lines.size() - 1
			_current_char_idx = str(_lines.back()["text"]).length()


## Мгновенно выводит весь текст на экран
func finish_typing() -> void:
	if is_typing_finished:
		return
	is_fading_in = false
	fade_alpha = 0.0
	is_typing_finished = true
	_wait_timer = 0.0
	_char_timer = 0.0
	if not _lines.is_empty():
		_current_line_idx = _lines.size() - 1
		_current_char_idx = str(_lines.back()["text"]).length()
	_play_click(1.0, -8.0)
	queue_redraw()


## Устанавливает тексты верхнего блока терминала (заголовок и статус)
func set_header_texts(p_title: String, p_status: String) -> void:
	header_title = p_title
	header_status = p_status
	queue_redraw()


## Начинает 0.5с плавный выход и передачу управления в игру
func start_exit() -> void:
	if is_fading_out or not is_active:
		return
	is_fading_in = false
	fade_alpha = 0.0
	is_fading_out = true
	_play_click(0.85, -4.0)


func _complete_cutscene() -> void:
	is_active = false
	is_fading_out = false
	visible = false
	cutscene_completed.emit()


## Обработка пользовательского ввода (Space, Enter, Escape, ЛКМ)
func _input(event: InputEvent) -> void:
	if not is_active:
		return

	var is_advancing: bool = false

	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			is_advancing = true
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			is_advancing = true

	if is_advancing:
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		if is_fading_in:
			fade_alpha = 0.0
			is_fading_in = false

		if not is_typing_finished:
			finish_typing()
		else:
			start_exit()


## Перезапуск катсцены
func start_cutscene() -> void:
	is_active = true
	is_typing_finished = false
	is_fading_in = true
	is_fading_out = false
	fade_alpha = 1.0
	_current_line_idx = 0
	_current_char_idx = 0
	_char_timer = 0.0
	_wait_timer = 0.0
	_typed_char_count = 0
	visible = true
	set_process(true)
	queue_redraw()


func _play_click(pitch: float = 1.0, volume_db: float = -12.0) -> void:
	if _sfx_player and _sfx_player.stream:
		_sfx_player.pitch_scale = pitch
		_sfx_player.volume_db = volume_db
		_sfx_player.play()


func _draw() -> void:
	if not visible:
		return

	# 1. Глубокий темно-фосфорный фон CRT
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), COLOR_PHOSPHOR_BG)

	# 2. Внешняя рамка терминала
	draw_rect(FRAME_RECT, Color(0.08, 0.16, 0.14, 0.9))
	draw_rect(FRAME_RECT, COLOR_BORDER_FRAME, false, 1.5)

	# Угловые тактические скобки терминала
	_draw_corner_brackets(FRAME_RECT, 20.0, COLOR_TERMINAL_CYAN)

	# 3. Верхний блок заголовка
	draw_rect(HEADER_RECT, Color(0.04, 0.09, 0.08, 0.95))
	draw_rect(HEADER_RECT, COLOR_BORDER_FRAME, false, 1.0)

	# Светодиод статуса
	var led_color: Color = COLOR_ALERT_RED if _status_led_blink else Color(0.3, 0.08, 0.08)
	draw_circle(Vector2(162.0, 74.0), 4.5, led_color)

	# Текст заголовка
	var status_text_color: Color = COLOR_ALERT_RED if _status_led_blink else COLOR_ALERT_DIM
	var status_w: float = minf(font.get_string_size(header_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x if font else 320.0, 360.0)
	var status_x: float = maxf(HEADER_RECT.end.x - status_w - 16.0, 178.0 + 400.0)
	var max_title_w: float = maxf(status_x - 178.0 - 20.0, 100.0)
	draw_string(font, Vector2(178.0, 78.0), header_title, HORIZONTAL_ALIGNMENT_LEFT, max_title_w, 11, COLOR_TERMINAL_BRIGHT)
	draw_string(font, Vector2(status_x, 78.0), header_status, HORIZONTAL_ALIGNMENT_LEFT, status_w, 10, status_text_color)

	# 4. Отрисовка строк тайпврайтера
	for i in range(_lines.size()):
		if i > _current_line_idx:
			break

		var line: Dictionary = _lines[i]
		var line_pos: Vector2 = Vector2(line["x"], line["y"])
		var full_text: String = line["text"]
		var font_size: int = line["size"]
		var col: Color = line["color"]

		if line.get("is_alert", false):
			# Специальный подсвеченный блок для "НЕ БУДИ ЕГО"
			var pulse_val: float = 0.15 + 0.10 * (sin(_pulse_timer * 2.5) * 0.5 + 0.5)
			draw_rect(ALERT_BOX_RECT, Color(0.902, 0.157, 0.082, pulse_val))
			draw_rect(ALERT_BOX_RECT, COLOR_ALERT_RED, false, 2.0)

		if i < _current_line_idx:
			# Полностью напечатанная строка
			draw_string(font, line_pos, full_text, HORIZONTAL_ALIGNMENT_LEFT, 940.0, font_size, col)
		else:
			# Строка в процессе набора
			if _current_char_idx != _last_cached_char_idx or i != _last_cached_line_idx:
				_last_cached_char_idx = _current_char_idx
				_last_cached_line_idx = i
				_cached_typing_substr = full_text.substr(0, _current_char_idx)
				if font != null:
					_cached_typing_width = font.get_string_size(_cached_typing_substr, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				else:
					_cached_typing_width = float(_cached_typing_substr.length()) * float(font_size) * 0.6

			draw_string(font, line_pos, _cached_typing_substr, HORIZONTAL_ALIGNMENT_LEFT, 940.0, font_size, col)

			# Мигающий курсор
			if _cursor_visible:
				var cursor_pos: Vector2 = line_pos + Vector2(_cached_typing_width + 3.0, 0.0)
				draw_string(font, cursor_pos, "_", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	# Если всё напечатано — мерцающий курсор на последней строке
	if is_typing_finished and _cursor_visible and not _lines.is_empty():
		var last_line: Dictionary = _lines.back()
		if not last_line.has("cached_width") and font != null:
			last_line["cached_width"] = font.get_string_size(last_line["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, last_line["size"]).x
		var l_width: float = float(last_line.get("cached_width", 0.0))
		var cursor_pos: Vector2 = Vector2(last_line["x"] + l_width + 4.0, last_line["y"])
		draw_string(font, cursor_pos, "_", HORIZONTAL_ALIGNMENT_LEFT, -1, last_line["size"], COLOR_ALERT_RED)

	# 5. ЭЛТ-сканлайны поверх текста
	if not _scanline_points.is_empty():
		draw_multiline(_scanline_points, Color(0.0, 0.0, 0.0, 0.16), 1.0)

	# 6. Глухая виньетка по периметру экрана
	_draw_crt_vignette()

	# 7. Пульсирующая подсказка внизу экрана
	_draw_bottom_prompt()

	# 8. Оверлей затемнения (fade_alpha)
	if fade_alpha > 0.001:
		draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.0, 0.0, 0.0, clampf(fade_alpha, 0.0, 1.0)))


func _draw_corner_brackets(r: Rect2, arm: float, col: Color) -> void:
	# Верхний левый
	draw_line(r.position, r.position + Vector2(arm, 0.0), col, 2.0)
	draw_line(r.position, r.position + Vector2(0.0, arm), col, 2.0)
	# Верхний правый
	var tr := Vector2(r.end.x, r.position.y)
	draw_line(tr, tr + Vector2(-arm, 0.0), col, 2.0)
	draw_line(tr, tr + Vector2(0.0, arm), col, 2.0)
	# Нижний левый
	var bl := Vector2(r.position.x, r.end.y)
	draw_line(bl, bl + Vector2(arm, 0.0), col, 2.0)
	draw_line(bl, bl + Vector2(0.0, -arm), col, 2.0)
	# Нижний правый
	draw_line(r.end, r.end + Vector2(-arm, 0.0), col, 2.0)
	draw_line(r.end, r.end + Vector2(0.0, -arm), col, 2.0)


func _draw_crt_vignette() -> void:
	# Затемнение границ за пределами терминала
	draw_rect(Rect2(0.0, 0.0, CANVAS_SIZE.x, FRAME_RECT.position.y), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(0.0, FRAME_RECT.end.y, CANVAS_SIZE.x, CANVAS_SIZE.y - FRAME_RECT.end.y), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(0.0, FRAME_RECT.position.y, FRAME_RECT.position.x, FRAME_RECT.size.y), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(FRAME_RECT.end.x, FRAME_RECT.position.y, CANVAS_SIZE.x - FRAME_RECT.end.x, FRAME_RECT.size.y), Color(0.0, 0.0, 0.0, 0.65))


func _draw_bottom_prompt() -> void:
	var prompt_rect: Rect2 = Rect2(360.0, 624.0, 560.0, 34.0)

	if is_typing_finished:
		var pulse: float = 0.45 + 0.55 * (sin(_pulse_timer) * 0.5 + 0.5)
		draw_rect(prompt_rect, Color(0.02, 0.06, 0.05, 0.7 * pulse))
		draw_rect(prompt_rect, Color(0.502, 0.847, 0.784, 0.6 * pulse), false, 1.2)
		var text_col: Color = Color(0.502, 0.847, 0.784, pulse)
		draw_string(font, prompt_rect.position + Vector2(0.0, 22.0), "[ ПРОБЕЛ ИЛИ ЛКМ — ПРИСТУПИТЬ К РЕМОНТУ ]", HORIZONTAL_ALIGNMENT_CENTER, prompt_rect.size.x, 12, text_col)
	else:
		# Во время печати отображаем ненавязчивую подсказку о возможности пропуска
		draw_string(font, prompt_rect.position + Vector2(0.0, 22.0), "[ ПРОБЕЛ / ЛКМ — ПРОПУСТИТЬ ТЕКСТ ]", HORIZONTAL_ALIGNMENT_CENTER, prompt_rect.size.x, 11, Color(0.35, 0.55, 0.50, 0.55))
