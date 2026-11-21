class_name DiagnosticsPanel
extends CanvasLayer

## Панель служебной диагностики (CRT-экран, слой 20)
## Отображает протокол неисправностей, коды (E-217) и симптомы

signal scan_requested
signal closed

const PALETTE_GUNMETAL := Color("#1A2028")
const PALETTE_CLOUD_WHITE := Color("#EDF0F4")
const PALETTE_SIGNAL := Color("#748B91")
const PALETTE_ALERT := Color("#E62815")
const PALETTE_STEEL := Color("#5A5A59")
const PALETTE_PALE_STEEL := Color("#C4CDD6")

const PANEL_RECT := Rect2(160, 150, 960, 420)

@onready var dimmer: ColorRect = $Dimmer
@onready var panel_root: Control = $Panel
@onready var title_label: Label = $Panel/Header/TitleLabel
@onready var subtitle_label: Label = $Panel/Header/SubtitleLabel
@onready var status_label: Label = $Panel/StatusLabel
@onready var scan_button: Button = $Panel/ScanButton
@onready var close_button: Button = $Panel/CloseButton
@onready var results_box: VBoxContainer = $Panel/ResultsScroll/ResultsBox
@onready var count_label: Label = $Panel/CountLabel

var _current_report: Dictionary = {}
var _is_scanned: bool = false
var _closed_emitted: bool = false


func _ready() -> void:
	layer = 20
	visible = false
	_ensure_nodes()
	if scan_button != null and not scan_button.pressed.is_connected(_on_scan_pressed):
		scan_button.pressed.connect(_on_scan_pressed)
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)


func _ensure_nodes() -> void:
	if panel_root == null and has_node("Panel"):
		panel_root = get_node("Panel")
		dimmer = get_node_or_null("Dimmer")
		title_label = get_node_or_null("Panel/Header/TitleLabel")
		subtitle_label = get_node_or_null("Panel/Header/SubtitleLabel")
		status_label = get_node_or_null("Panel/StatusLabel")
		scan_button = get_node_or_null("Panel/ScanButton")
		close_button = get_node_or_null("Panel/CloseButton")
		results_box = get_node_or_null("Panel/ResultsScroll/ResultsBox")
		count_label = get_node_or_null("Panel/CountLabel")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and (k.keycode == KEY_ESCAPE or k.keycode == KEY_BACKSPACE):
			get_viewport().set_input_as_handled()
			close()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			close()


func open(report: Dictionary = {}) -> void:
	_ensure_nodes()
	visible = true
	_closed_emitted = false
	set_report(report)


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


func set_report(report: Dictionary) -> void:
	_ensure_nodes()
	_current_report = report
	_clear_results()

	if report.is_empty():
		_is_scanned = false
		if status_label:
			status_label.text = "СИСТЕМА ГОТОВА К СКАНИРОВАНИЮ"
		if count_label:
			count_label.text = ""
		if scan_button:
			scan_button.visible = true
			scan_button.disabled = false
		return

	_is_scanned = true
	if scan_button:
		scan_button.visible = false

	var faults: Array = _extract_faults(report)
	if faults.is_empty():
		if status_label:
			status_label.text = "СКАНИРОВАНИЕ ЗАВЕРШЕНО: НОРМА"
		if count_label:
			count_label.text = "НЕИСПРАВНОСТЕЙ НЕ ОБНАРУЖЕНО"
			count_label.modulate = PALETTE_SIGNAL
	else:
		if status_label:
			status_label.text = "ОБНАРУЖЕНЫ КРИТИЧЕСКИЕ ДЕФЕКТЫ"
		if count_label:
			count_label.text = "НЕИСПРАВНОСТЕЙ: %d" % faults.size()
			count_label.modulate = PALETTE_ALERT

		for f_data in faults:
			_add_fault_entry(f_data)


func _extract_faults(report: Dictionary) -> Array:
	if report.has("faults") and report["faults"] is Array:
		return report["faults"] as Array
	if report.has("parts") and report["parts"] is Array:
		var res: Array = []
		for p in report["parts"]:
			if p is Dictionary:
				var d := p as Dictionary
				res.append({
					"code": d.get("fault_code", d.get("code", "E-000")),
					"tag": d.get("tag", ""),
					"symptom": d.get("symptom", d.get("label", "Неизвестный дефект")),
					"label": d.get("label", "")
				})
		return res
	return []


func _clear_results() -> void:
	if results_box == null:
		return
	for child in results_box.get_children():
		child.queue_free()


func _add_fault_entry(fault: Dictionary) -> void:
	if results_box == null:
		return
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(880, 36)

	var code_label := Label.new()
	var code_str := str(fault.get("code", fault.get("fault_code", "E-000")))
	var tag_str := str(fault.get("tag", ""))
	if tag_str != "":
		code_label.text = "[%s] %s" % [tag_str, code_str]
	else:
		code_label.text = code_str
	code_label.custom_minimum_size = Vector2(160, 24)
	code_label.modulate = PALETTE_SIGNAL
	code_label.add_theme_font_size_override("font_size", 11)
	row.add_child(code_label)

	var sep := Label.new()
	sep.text = " · "
	sep.modulate = PALETTE_STEEL
	sep.add_theme_font_size_override("font_size", 11)
	row.add_child(sep)

	var symptom_label := Label.new()
	var symptom_text := str(fault.get("symptom", fault.get("label", "Дефект контура")))
	symptom_label.text = symptom_text
	symptom_label.modulate = PALETTE_CLOUD_WHITE
	symptom_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	symptom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	symptom_label.add_theme_font_size_override("font_size", 11)
	row.add_child(symptom_label)

	results_box.add_child(row)


func _on_scan_pressed() -> void:
	_ensure_nodes()
	if scan_button:
		scan_button.disabled = true
	if status_label:
		status_label.text = "СКАНИРОВАНИЕ СИСТЕМ..."
	emit_signal("scan_requested")


## Экранный прямоугольник кнопки сканирования (для обучения).
func get_scan_button_rect() -> Rect2:
	_ensure_nodes()
	if scan_button == null or not visible or not scan_button.is_visible_in_tree():
		return Rect2()
	return scan_button.get_global_rect()


func _on_close_pressed() -> void:
	close()
