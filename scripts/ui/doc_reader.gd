class_name DocReader
extends CanvasLayer

## Просмотр регламента ТО (слой 40, ширина <= 680 px)
## Отображает бумажный документ техпроцесса: шаги, инструменты, норму времени

signal closed
signal repair_requested

const PALETTE_GUNMETAL := Color("#1A2028")
const PALETTE_CLOUD_WHITE := Color("#EDF0F4")
const PALETTE_SIGNAL := Color("#748B91")
const PALETTE_ALERT := Color("#E62815")
const PALETTE_STEEL := Color("#5A5A59")
const PALETTE_PALE_STEEL := Color("#C4CDD6")
const PALETTE_COOL_SLATE := Color("#D1CCC7")
const PALETTE_RUST := Color("#8B4944")

const TOOL_NAMES_RU := {
	"cloth": "ВЕТОШЬ (САЛФЕТКА)",
	"cable": "БАЙОНЕТНЫЙ КАБЕЛЬ",
	"screwdriver": "ОТВЁРТКА",
	"keyboard": "ТЕРМИНАЛ",
	"wrench": "КЛЮЧ",
	"wirecutter": "КУСАЧКИ"
}

@onready var dimmer: ColorRect = $Dimmer
@onready var sheet: Control = $Sheet
@onready var tag_label: Label = $Sheet/Header/TagLabel
@onready var title_label: Label = $Sheet/Header/TitleLabel
@onready var stamp_label: Label = $Sheet/Header/StampLabel
@onready var tools_label: Label = $Sheet/ContentScroll/ContentBox/ToolsBlock/ToolsList
@onready var steps_box: VBoxContainer = $Sheet/ContentScroll/ContentBox/StepsBlock/StepsBox
@onready var safety_box: VBoxContainer = $Sheet/ContentScroll/ContentBox/SafetyBlock/SafetyBox
@onready var time_norm_label: Label = $Sheet/ContentScroll/ContentBox/TimeBlock/TimeValue
@onready var notes_box: VBoxContainer = $Sheet/ContentScroll/ContentBox/NotesBlock/NotesBox
@onready var start_repair_btn: Button = $Sheet/ButtonsBar/StartRepairButton
@onready var close_btn: Button = $Sheet/ButtonsBar/CloseButton

var _current_card: Dictionary = {}
var _repair_requested_emitted: bool = false
var _closed_emitted: bool = false


func _ready() -> void:
	layer = 40
	visible = false
	_ensure_nodes()
	if start_repair_btn != null and not start_repair_btn.pressed.is_connected(_on_start_repair_pressed):
		start_repair_btn.pressed.connect(_on_start_repair_pressed)
	if close_btn != null and not close_btn.pressed.is_connected(_on_close_pressed):
		close_btn.pressed.connect(_on_close_pressed)


func _ensure_nodes() -> void:
	if sheet == null and has_node("Sheet"):
		dimmer = get_node_or_null("Dimmer")
		sheet = get_node("Sheet")
		tag_label = get_node_or_null("Sheet/Header/TagLabel")
		title_label = get_node_or_null("Sheet/Header/TitleLabel")
		stamp_label = get_node_or_null("Sheet/Header/StampLabel")
		tools_label = get_node_or_null("Sheet/ContentScroll/ContentBox/ToolsBlock/ToolsList")
		steps_box = get_node_or_null("Sheet/ContentScroll/ContentBox/StepsBlock/StepsBox")
		safety_box = get_node_or_null("Sheet/ContentScroll/ContentBox/SafetyBlock/SafetyBox")
		time_norm_label = get_node_or_null("Sheet/ContentScroll/ContentBox/TimeBlock/TimeValue")
		notes_box = get_node_or_null("Sheet/ContentScroll/ContentBox/NotesBlock/NotesBox")
		start_repair_btn = get_node_or_null("Sheet/ButtonsBar/StartRepairButton")
		close_btn = get_node_or_null("Sheet/ButtonsBar/CloseButton")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed:
			if k.keycode == KEY_ESCAPE or k.keycode == KEY_BACKSPACE:
				get_viewport().set_input_as_handled()
				close()
			elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				get_viewport().set_input_as_handled()
				_on_start_repair_pressed()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			close()


func open(card: Dictionary = {}) -> void:
	_ensure_nodes()
	visible = true
	_repair_requested_emitted = false
	_closed_emitted = false
	_current_card = card
	_populate_card(card)


func close() -> void:
	_ensure_nodes()
	if not visible and _closed_emitted:
		return
	visible = false
	if not _closed_emitted:
		_closed_emitted = true
		emit_signal("closed")


func is_open() -> bool:
	return visible


func _populate_card(card: Dictionary) -> void:
	_ensure_nodes()
	var tag := str(card.get("tag", "ТО-??"))
	var title := str(card.get("title", "Регламент технического обслуживания"))

	if tag_label:
		tag_label.text = tag
	if title_label:
		title_label.text = title
	if stamp_label:
		stamp_label.text = "РЕГЛАМЕНТ ТО · УТВЕРЖДЕНО"

	# Инструменты
	var tool_list: Array = card.get("tool_list", [])
	if tools_label:
		if tool_list.is_empty():
			tools_label.text = "Не требуются"
		else:
			var names: Array = []
			for t in tool_list:
				var t_str := str(t)
				names.append(TOOL_NAMES_RU.get(t_str, t_str.to_upper()))
			tools_label.text = " · ".join(names)

	# Порядок шагов
	_clear_container(steps_box)
	var steps_text: Array = card.get("steps_text", [])
	if steps_box:
		if steps_text.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "Порядок операций не задан"
			empty_lbl.add_theme_font_size_override("font_size", 9)
			empty_lbl.add_theme_color_override("font_color", PALETTE_GUNMETAL)
			steps_box.add_child(empty_lbl)
		else:
			for i in range(steps_text.size()):
				var step_lbl := Label.new()
				step_lbl.text = "%d. %s" % [i + 1, str(steps_text[i])]
				step_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				step_lbl.add_theme_font_size_override("font_size", 9)
				step_lbl.add_theme_color_override("font_color", PALETTE_GUNMETAL)
				steps_box.add_child(step_lbl)

	# Техника безопасности
	_clear_container(safety_box)
	var safety: Array = card.get("safety_protocol", [])
	if safety_box:
		if safety.is_empty():
			var safe_lbl := Label.new()
			safe_lbl.text = "Стандартные меры электробезопасности."
			safe_lbl.add_theme_font_size_override("font_size", 9)
			safe_lbl.add_theme_color_override("font_color", PALETTE_GUNMETAL)
			safety_box.add_child(safe_lbl)
		else:
			for s in safety:
				var s_lbl := Label.new()
				s_lbl.text = "⚠ %s" % str(s)
				s_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				s_lbl.add_theme_font_size_override("font_size", 9)
				s_lbl.add_theme_color_override("font_color", PALETTE_RUST)
				safety_box.add_child(s_lbl)

	# Норма времени
	var time_sec: float = float(card.get("time_norm_sec", 60.0))
	var mins := int(time_sec) / 60
	var secs := int(time_sec) % 60
	if time_norm_label:
		time_norm_label.text = "%02d:%02d (%d с)" % [mins, secs, int(time_sec)]

	# Особые отметки / Предупреждения
	_clear_container(notes_box)
	var notes: Array = card.get("notes", [])
	if notes_box:
		if notes.is_empty():
			var n_lbl := Label.new()
			n_lbl.text = "Особых указаний нет."
			n_lbl.add_theme_font_size_override("font_size", 9)
			n_lbl.add_theme_color_override("font_color", PALETTE_GUNMETAL)
			notes_box.add_child(n_lbl)
		else:
			for note in notes:
				var n_lbl := Label.new()
				n_lbl.text = "• %s" % str(note)
				n_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				n_lbl.add_theme_font_size_override("font_size", 9)
				n_lbl.add_theme_color_override("font_color", PALETTE_GUNMETAL)
				notes_box.add_child(n_lbl)


func _clear_container(cont: Container) -> void:
	if cont == null:
		return
	for child in cont.get_children():
		child.queue_free()


func _on_start_repair_pressed() -> void:
	_ensure_nodes()
	if _repair_requested_emitted:
		return
	_repair_requested_emitted = true
	emit_signal("repair_requested")


func _on_close_pressed() -> void:
	close()


## Экранный прямоугольник кнопки «Начать ремонт» (для обучения).
func get_start_button_rect() -> Rect2:
	_ensure_nodes()
	if start_repair_btn == null or not visible or not start_repair_btn.is_visible_in_tree():
		return Rect2()
	return start_repair_btn.get_global_rect()
