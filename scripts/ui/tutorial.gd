class_name Tutorial
extends CanvasLayer

## Пошаговое обучение первого запуска.
## Ведёт игрока по всей петле: диагностика → деталь → картотека → регламент →
## инструмент → чистка → кабель → «замри» → проверка.
## Рисуется поверх модальных панелей (layer 70), но ввод не перехватывает:
## подсвечивает цель скобками, притемняет остальное и даёт короткий текст.
## Прогресс хранится в user://dnw_tutorial.cfg (повтор — F2).

const SAVE_PATH := "user://dnw_tutorial.cfg"
const LAYER := 70

const CARD_RECT := Rect2(36.0, 168.0, 380.0, 246.0)
const DIM := Color(0.01, 0.02, 0.03, 0.62)
const GOLD := Color("#D8C29A")
const WHITE := Color("#EDF0F4")
const DIM_TEXT := Color("#8FA0A6")
const ALERT := Color("#E62815")
const OK_COL := Color("#59EB94")

const TASKS := [
	{"id": "scan", "title": "1 · ДИАГНОСТИКА"},
	{"id": "part", "title": "2 · ВЫБЕРИ ДЕТАЛЬ"},
	{"id": "drawer", "title": "3 · КАРТОТЕКА"},
	{"id": "card", "title": "4 · ВОЗЬМИ КАРТОЧКУ"},
	{"id": "repair", "title": "5 · РЕГЛАМЕНТ"},
	{"id": "tool", "title": "6 · ИНСТРУМЕНТ"},
	{"id": "scrub", "title": "7 · ЧИСТКА КОНТАКТОВ"},
	{"id": "cable", "title": "8 · ПИТАНИЕ"},
	{"id": "threat", "title": "9 · ЗАМРИ"},
]

var _main: Node = null
var _game_state: Node = null
var _loop_screens: Node = null
var _font: Font = ThemeDB.fallback_font

var _painter: Node2D = null
var _active: bool = false
var _index: int = 0
var _pulse: float = 0.0
var _verify_seen: bool = false
var _toast_timer: float = 0.0
var _error_text: String = ""
var _error_timer: float = 0.0
var _hidden_by_help: bool = false
var save_path: String = SAVE_PATH


func _ready() -> void:
	if _painter != null:
		return
	layer = LAYER
	_painter = Node2D.new()
	_painter.name = "Painter"
	add_child(_painter)
	_painter.draw.connect(_paint)


func bind(main: Node, game_state: Node, loop_screens: Node) -> void:
	_main = main
	_game_state = game_state
	_loop_screens = loop_screens
	if main != null and "font" in main:
		_font = main.font
	if game_state != null:
		if not game_state.part_selected.is_connected(_on_part_selected):
			game_state.part_selected.connect(_on_part_selected)
		if not game_state.document_read.is_connected(_on_document_read):
			game_state.document_read.connect(_on_document_read)
		if not game_state.verification_finished.is_connected(_on_verification_finished):
			game_state.verification_finished.connect(_on_verification_finished)


func is_completed() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return false
	return bool(cfg.get_value("tutorial", "done", false))


func _mark_completed() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tutorial", "done", true)
	cfg.save(save_path)


func is_active() -> bool:
	return _active


## Запуск при старте смены: если обучение уже проходили — не мешаем.
func start_if_needed() -> void:
	if is_completed():
		return
	start()


func start() -> void:
	_active = true
	_error_text = ""
	_error_timer = 0.0
	_verify_seen = false
	_index = _initial_index()
	if _painter != null:
		_painter.visible = true
		_painter.queue_redraw()


func skip() -> void:
	if not _active:
		return
	_active = false
	_mark_completed()
	if _painter != null:
		_painter.visible = false


func toggle_manual() -> void:
	if _active:
		skip()
	else:
		start()


func set_hidden(hidden: bool) -> void:
	_hidden_by_help = hidden


func _process(delta: float) -> void:
	if _painter == null:
		return
	_painter.visible = (_active or _toast_timer > 0.0) and not _hidden_by_help
	_pulse += delta
	if _error_timer > 0.0:
		_error_timer = maxf(_error_timer - delta, 0.0)
	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
	if _active:
		var guard := 0
		while guard < 4 and _task_id() != "" and _is_done(_task_id()):
			guard += 1
			_index += 1
			_error_text = ""
			if _index >= TASKS.size():
				_finish()
				break
	_painter.queue_redraw()


func _finish() -> void:
	_active = false
	_toast_timer = 5.0
	_mark_completed()
	_painter.queue_redraw()


func _task_id() -> String:
	if _index < 0 or _index >= TASKS.size():
		return ""
	return str(TASKS[_index].get("id", ""))


func _initial_index() -> int:
	if _game_state == null:
		return 0
	match _game_state.current_phase:
		GameState.Phase.DIAGNOSTICS:
			return 0
		GameState.Phase.PART_SELECT:
			return 1
		GameState.Phase.DOC_SEARCH:
			return 2
		GameState.Phase.REPAIR:
			var idx: int = int(_game_state._current_step_index)
			if idx <= 0:
				return 5
			if idx == 1:
				return 6
			return 7
		GameState.Phase.THREAT_CONTROL, GameState.Phase.VERIFY:
			return 8
		_:
			return 0


func _on_part_selected(_part_id: String, correct: bool) -> void:
	if not _active:
		return
	if not correct and _task_id() == "part":
		_show_error("Не та бирка. Нужна " + _target_tag() + ".")


func _on_document_read(_card_id: String, correct: bool) -> void:
	if not _active:
		return
	if not correct and (_task_id() == "card" or _task_id() == "drawer"):
		_show_error("Не тот формуляр. Нужен " + _target_tag() + ".")


func _on_verification_finished(_passed: bool, _details: Dictionary) -> void:
	_verify_seen = true


func _show_error(text: String) -> void:
	_error_text = text
	_error_timer = 3.0


# =============================================================================
# Условия выполнения шагов
# =============================================================================

func _is_done(id: String) -> bool:
	if _game_state == null:
		return false
	var phase: int = _game_state.current_phase
	match id:
		"scan":
			return phase != GameState.Phase.DIAGNOSTICS
		"part":
			return phase == GameState.Phase.DOC_SEARCH or phase == GameState.Phase.REPAIR \
				or phase == GameState.Phase.THREAT_CONTROL or phase == GameState.Phase.VERIFY \
				or int(_game_state.parts_done) > 0
		"drawer":
			var cf: Node = _card_file()
			return cf != null and str(cf._open_drawer_id) == _target_drawer()
		"card":
			var dr: Node = _doc_reader()
			return dr != null and dr.visible
		"repair":
			return phase == GameState.Phase.REPAIR
		"tool":
			return _main != null and _main.held_tool != null and _main.held_tool.tool_id == "cloth"
		"scrub":
			return int(_game_state._current_step_index) >= 1 or phase != GameState.Phase.REPAIR
		"cable":
			return phase == GameState.Phase.THREAT_CONTROL or phase == GameState.Phase.VERIFY \
				or phase == GameState.Phase.DIAGNOSTICS or int(_game_state.parts_done) > 0
		"threat":
			return _verify_seen and phase != GameState.Phase.THREAT_CONTROL \
				and phase != GameState.Phase.VERIFY
		_:
			return false


# =============================================================================
# Цели и данные текущей детали
# =============================================================================

func _target_part() -> Dictionary:
	if _game_state == null:
		return {}
	var rep: Dictionary = _game_state.get_diagnostics_report()
	if rep.has("parts") and rep["parts"] is Array and not rep["parts"].is_empty():
		return rep["parts"][0] as Dictionary
	# До сканирования отчёта нет — берём учебную деталь из parts.json.
	for p in _game_state._parts:
		if p is Dictionary and str(p.get("id", "")) == "srv_04":
			return p as Dictionary
	return {}


func _target_tag() -> String:
	var p := _target_part()
	var tag := str(p.get("tag", ""))
	return tag if tag != "" else "A-04"


func _target_part_id() -> String:
	return str(_target_part().get("id", "srv_04"))


func _target_card_id() -> String:
	return str(_target_part().get("doc_id", "doc_a04"))


func _target_drawer() -> String:
	var cf: Node = _card_file()
	if cf != null:
		var card: Dictionary = cf._cards_data.get(_target_card_id(), {})
		return str(card.get("drawer", "A"))
	return "A"


func _card_file() -> Node:
	if _loop_screens == null:
		return null
	return _loop_screens.card_file


func _doc_reader() -> Node:
	if _loop_screens == null:
		return null
	return _loop_screens.doc_reader


func _rect_for(id: String) -> Rect2:
	match id:
		"scan":
			var dp: Node = _loop_screens.diagnostics_panel if _loop_screens != null else null
			return dp.get_scan_button_rect() if dp != null else Rect2()
		"part":
			var pm: Node = _loop_screens.part_markers if _loop_screens != null else null
			return pm.get_marker_rect(_target_part_id()) if pm != null else Rect2()
		"drawer":
			var cf: Node = _card_file()
			return cf.get_drawer_button_rect(_target_drawer()) if cf != null else Rect2()
		"card":
			var cf2: Node = _card_file()
			return cf2.get_card_button_rect(_target_card_id()) if cf2 != null else Rect2()
		"repair":
			var dr: Node = _doc_reader()
			return dr.get_start_button_rect() if dr != null else Rect2()
		"tool":
			if _main != null:
				var cloth = _main.draggable_tools.get("cloth", null)
				if cloth != null:
					return Rect2(cloth.home_pos - cloth.tool_size * 0.5, cloth.tool_size)
			return Rect2()
		"scrub":
			if _main != null and _main.step_runner != null:
				var r: Rect2 = _main.step_runner.get_step_rect()
				if r.size.x > 0.0:
					return Rect2(r.position + _main.get_mid_shift(), r.size)
			return Rect2()
		"cable":
			if _main != null and _main.cable_plug != null:
				var p: Vector2 = _main.cable_plug.current_plug_pos + _main.get_mid_shift()
				return Rect2(p - Vector2(52.0, 52.0), Vector2(104.0, 104.0))
			return Rect2()
		"threat":
			return Rect2(382.0, 412.0, 516.0, 98.0)
		_:
			return Rect2()


# =============================================================================
# Отрисовка
# =============================================================================

func _paint() -> void:
	if not _active and _toast_timer <= 0.0:
		return
	if _active:
		var target := _rect_for(_task_id())
		if target.size.x > 0.0 and target.size.y > 0.0:
			_dim_except(target)
			_draw_brackets(target)
			_draw_pointer(target)
		_draw_card()
	if _toast_timer > 0.0:
		_draw_toast()


## Для модальных панелей карточка обучения уходит вправо, чтобы не закрывать документ.
func _card_rect() -> Rect2:
	var id := _task_id()
	if id == "drawer" or id == "card" or id == "repair":
		return Rect2(1280.0 - 36.0 - CARD_RECT.size.x, 150.0, CARD_RECT.size.x, CARD_RECT.size.y)
	return CARD_RECT


func _dim_except(r: Rect2) -> void:
	var g := r.grow(8.0)
	var x0: float = clampf(g.position.x, 0.0, 1280.0)
	var x1: float = clampf(g.end.x, 0.0, 1280.0)
	var y0: float = clampf(g.position.y, 0.0, 720.0)
	var y1: float = clampf(g.end.y, 0.0, 720.0)
	_painter.draw_rect(Rect2(0.0, 0.0, 1280.0, y0), DIM)
	_painter.draw_rect(Rect2(0.0, y1, 1280.0, 720.0 - y1), DIM)
	_painter.draw_rect(Rect2(0.0, y0, x0, y1 - y0), DIM)
	_painter.draw_rect(Rect2(x1, y0, 1280.0 - x1, y1 - y0), DIM)


func _draw_brackets(r: Rect2) -> void:
	var pulse := 0.55 + 0.45 * absf(sin(_pulse * 2.6))
	var col := Color(GOLD.r, GOLD.g, GOLD.b, pulse)
	var glow := Color(GOLD.r, GOLD.g, GOLD.b, pulse * 0.20)
	var arm: float = 16.0
	var rr := r.grow(8.0)
	_painter.draw_rect(rr, glow)
	_painter.draw_line(rr.position, rr.position + Vector2(arm, 0), col, 2.0)
	_painter.draw_line(rr.position, rr.position + Vector2(0, arm), col, 2.0)
	_painter.draw_line(Vector2(rr.end.x, rr.position.y), Vector2(rr.end.x - arm, rr.position.y), col, 2.0)
	_painter.draw_line(Vector2(rr.end.x, rr.position.y), Vector2(rr.end.x, rr.position.y + arm), col, 2.0)
	_painter.draw_line(Vector2(rr.position.x, rr.end.y), Vector2(rr.position.x + arm, rr.end.y), col, 2.0)
	_painter.draw_line(Vector2(rr.position.x, rr.end.y), Vector2(rr.position.x, rr.end.y - arm), col, 2.0)
	_painter.draw_line(rr.end, rr.end - Vector2(arm, 0), col, 2.0)
	_painter.draw_line(rr.end, rr.end - Vector2(0, arm), col, 2.0)


func _draw_pointer(r: Rect2) -> void:
	var bob: float = sin(_pulse * 3.0) * 5.0
	var col := Color(GOLD.r, GOLD.g, GOLD.b, 0.9)
	if r.position.y > 150.0:
		var tip := Vector2(r.get_center().x, r.position.y - 18.0 + bob)
		_painter.draw_colored_polygon(PackedVector2Array([
			tip, tip + Vector2(-11.0, -16.0), tip + Vector2(11.0, -16.0)
		]), col)
		_painter.draw_line(tip + Vector2(0, -16), tip + Vector2(0, -34), col, 2.0)
	else:
		var tip2 := Vector2(r.get_center().x, r.end.y + 18.0 - bob)
		_painter.draw_colored_polygon(PackedVector2Array([
			tip2, tip2 + Vector2(-11.0, 16.0), tip2 + Vector2(11.0, 16.0)
		]), col)


func _draw_card() -> void:
	var lines := _task_lines(_task_id())
	var rect := _card_rect()
	_painter.draw_rect(rect, Color(0.04, 0.06, 0.08, 0.96))
	_painter.draw_rect(rect, Color(0.38, 0.48, 0.54, 0.9), false, 1.0)
	_painter.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 24.0)), Color(0.10, 0.13, 0.16, 0.95))

	_painter.draw_string(_font, rect.position + Vector2(14.0, 17.0), "ОБУЧЕНИЕ %d/%d" % [_index + 1, TASKS.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, DIM_TEXT)
	var title := str(TASKS[_index].get("title", ""))
	_painter.draw_string(_font, rect.position + Vector2(14.0, 48.0), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 10, WHITE)

	var y := 74.0
	for line in lines:
		_painter.draw_string(_font, rect.position + Vector2(14.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 9, WHITE)
		y += 17.0

	var footer_y := rect.end.y - 30.0
	if _error_timer > 0.0 and _error_text != "":
		_painter.draw_string(_font, Vector2(rect.position.x + 14.0, footer_y), _error_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 8, ALERT)
	else:
		_painter.draw_string(_font, Vector2(rect.position.x + 14.0, footer_y), "F2 — ПРОПУСТИТЬ ОБУЧЕНИЕ", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 7, DIM_TEXT)
	# Точки прогресса
	var dot_y := rect.end.y - 12.0
	for i in TASKS.size():
		var dot_col: Color = OK_COL if i < _index else (GOLD if i == _index else Color(0.25, 0.30, 0.34))
		_painter.draw_circle(Vector2(rect.position.x + 14.0 + float(i) * 12.0, dot_y), 2.4, dot_col)


func _draw_toast() -> void:
	var alpha: float = clampf(_toast_timer / 1.0, 0.0, 1.0)
	var rect := Rect2(340.0, 300.0, 600.0, 96.0)
	_painter.draw_rect(rect, Color(0.04, 0.06, 0.08, 0.96 * alpha))
	_painter.draw_rect(rect, Color(OK_COL.r, OK_COL.g, OK_COL.b, alpha), false, 2.0)
	_painter.draw_string(_font, rect.position + Vector2(0.0, 40.0), "ОБУЧЕНИЕ ПРОЙДЕНО", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14, Color(OK_COL.r, OK_COL.g, OK_COL.b, alpha))
	_painter.draw_string(_font, rect.position + Vector2(0.0, 66.0), "F2 — показать подсказки ещё раз", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 8, Color(WHITE.r, WHITE.g, WHITE.b, alpha * 0.8))


func _task_lines(id: String) -> Array:
	var tag := _target_tag()
	match id:
		"scan":
			return [
				"Нажми кнопку СКАНИРОВАТЬ.",
				"Робот покажет неисправные",
				"узлы и их ID (например " + tag + ").",
			]
		"part":
			return [
				"Кликни по бирке " + tag + " на",
				"корпусе робота. Бирки",
				"подсвечены прямоугольниками.",
			]
		"drawer":
			return [
				"Открой ящик " + _target_drawer() + " в картотеке.",
				"Внутри лежат карточки",
				"регламентов. TAB — открыть снова.",
			]
		"card":
			return [
				"Нажми ВЗЯТЬ у карточки " + tag + ".",
				"Откроется регламент ремонта",
				"с порядком операций.",
			]
		"repair":
			return [
				"Прочитай порядок операций",
				"и нажми НАЧАТЬ РЕМОНТ [ENTER].",
			]
		"tool":
			return [
				"Кликни ЛКМ по ветоши в лотке.",
				"Она останется в руке —",
				"кнопку держать не нужно.",
				"Убрать: ПКМ или клик по лотку.",
			]
		"scrub":
			return [
				"Веди ветошь по контактам",
				"влево-вправо. Слишком медленно —",
				"нет прогресса, слишком быстро —",
				"перегрев. Доведи шкалу до 100%.",
			]
		"cable":
			return [
				"Схвати кабель в правом лотке,",
				"тащи к виску и держи у порта",
				"0.8 с до щелчка. Колесо мыши —",
				"довернуть паз.",
			]
		"threat":
			return [
				"Не двигай мышью, пока полоса",
				"удержания не заполнится.",
				"Движение сбрасывает прогресс.",
			]
		_:
			return []
