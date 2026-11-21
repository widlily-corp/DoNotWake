class_name VerifyPanel
extends CanvasLayer

## Панель проверки узла и штампа ОТК (слой 50, 640×360)
## Отображает осциллограф/импульс, параметры качества и штамп ГОДЕН/БРАК

signal confirmed(passed: bool)
signal closed

const PALETTE_GUNMETAL := Color("#1A2028")
const PALETTE_CLOUD_WHITE := Color("#EDF0F4")
const PALETTE_SIGNAL := Color("#748B91")
const PALETTE_ALERT := Color("#E62815")
const PALETTE_STEEL := Color("#5A5A59")
const PALETTE_COOL_SLATE := Color("#D1CCC7")
const PALETTE_OBSIDIAN := Color("#080808")

const STAMP_OK_PATH := "res://assets/sprites/ui/stamp_ok.png"
const STAMP_FAIL_PATH := "res://assets/sprites/ui/stamp_fail.png"

@onready var dimmer: ColorRect = $Dimmer
@onready var panel_ctrl: Control = $Panel
@onready var title_label: Label = $Panel/Header/TitleLabel
@onready var subtitle_label: Label = $Panel/Header/SubtitleLabel
@onready var osc_view: Control = $Panel/Oscilloscope
@onready var osc_status_label: Label = $Panel/Oscilloscope/StatusLabel
@onready var steps_label: Label = $Panel/DetailsBox/StepsLabel
@onready var order_label: Label = $Panel/DetailsBox/OrderLabel
@onready var quality_label: Label = $Panel/DetailsBox/QualityLabel
@onready var stamp_rect: TextureRect = $Panel/StampRect
@onready var stamp_text_label: Label = $Panel/StampRect/StampText
@onready var confirm_button: Button = $Panel/ConfirmButton

var _stamp_ok_tex: Texture2D
var _stamp_fail_tex: Texture2D
var _passed: bool = true
var _confirmed_emitted: bool = false
var _closed_emitted: bool = false
var _wave_time: float = 0.0


func _ready() -> void:
	layer = 50
	visible = false
	_ensure_nodes()
	_load_textures()
	if confirm_button != null and not confirm_button.pressed.is_connected(_on_confirm_pressed):
		confirm_button.pressed.connect(_on_confirm_pressed)


func _ensure_nodes() -> void:
	if panel_ctrl == null and has_node("Panel"):
		dimmer = get_node_or_null("Dimmer")
		panel_ctrl = get_node("Panel")
		title_label = get_node_or_null("Panel/Header/TitleLabel")
		subtitle_label = get_node_or_null("Panel/Header/SubtitleLabel")
		osc_view = get_node_or_null("Panel/Oscilloscope")
		osc_status_label = get_node_or_null("Panel/Oscilloscope/StatusLabel")
		steps_label = get_node_or_null("Panel/DetailsBox/StepsLabel")
		order_label = get_node_or_null("Panel/DetailsBox/OrderLabel")
		quality_label = get_node_or_null("Panel/DetailsBox/QualityLabel")
		stamp_rect = get_node_or_null("Panel/StampRect")
		stamp_text_label = get_node_or_null("Panel/StampRect/StampText")
		confirm_button = get_node_or_null("Panel/ConfirmButton")


func _load_textures() -> void:
	if ResourceLoader.exists(STAMP_OK_PATH):
		_stamp_ok_tex = load(STAMP_OK_PATH)
	if ResourceLoader.exists(STAMP_FAIL_PATH):
		_stamp_fail_tex = load(STAMP_FAIL_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed:
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE:
				get_viewport().set_input_as_handled()
				_on_confirm_pressed()
			elif k.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				close()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			close()


func _process(delta: float) -> void:
	if visible and osc_view != null:
		_wave_time += delta * 4.0
		osc_view.queue_redraw()


func open(details: Dictionary = {}) -> void:
	_ensure_nodes()
	visible = true
	_confirmed_emitted = false
	_closed_emitted = false

	_passed = bool(details.get("passed", details.get("success", true)))
	var reason := str(details.get("reason", details.get("fail_reason", "")))
	var quality := float(details.get("quality", 1.0))
	var steps_done := int(details.get("steps_completed", 3))
	var steps_total := int(details.get("steps_total", 3))

	if steps_label:
		steps_label.text = "ШАГИ: %d/%d ВЫПОЛНЕНЫ" % [steps_done, steps_total]
	if order_label:
		if _passed:
			order_label.text = "ПОРЯДОК: СОБЛЮДЁН (НОРМА)"
			order_label.modulate = PALETTE_SIGNAL
		else:
			order_label.text = "ОШИБКА: " + (reason if reason != "" else "НАРУШЕН РЕГЛАМЕНТ")
			order_label.modulate = PALETTE_ALERT

	if quality_label:
		quality_label.text = "КАЧЕСТВО СИГНАЛА: %d%%" % int(quality * 100.0)

	if osc_status_label:
		if _passed:
			osc_status_label.text = "ИМПУЛЬС: 0.85 (В ДОПУСКЕ) · СТАБИЛЬНОСТЬ 100%"
			osc_status_label.modulate = PALETTE_SIGNAL
		else:
			osc_status_label.text = "СБОЙ ИМПУЛЬСА: ВНЕ ДОПУСКА · АМПЛИТУДА НИЖЕ 0.5"
			osc_status_label.modulate = PALETTE_ALERT

	_apply_stamp(_passed)


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


func _apply_stamp(passed: bool) -> void:
	if stamp_rect == null:
		return

	stamp_rect.rotation = deg_to_rad(-8.0)
	if passed:
		if _stamp_ok_tex:
			stamp_rect.texture = _stamp_ok_tex
		if stamp_text_label:
			stamp_text_label.text = "ГОДЕН"
			stamp_text_label.modulate = PALETTE_SIGNAL
		stamp_rect.modulate = PALETTE_SIGNAL
	else:
		if _stamp_fail_tex:
			stamp_rect.texture = _stamp_fail_tex
		if stamp_text_label:
			stamp_text_label.text = "БРАК"
			stamp_text_label.modulate = PALETTE_ALERT
		stamp_rect.modulate = PALETTE_ALERT

	# Анимация штампа 180 мс
	stamp_rect.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	if tw:
		tw.tween_property(stamp_rect, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_confirm_pressed() -> void:
	_ensure_nodes()
	if _confirmed_emitted:
		return
	_confirmed_emitted = true
	emit_signal("confirmed", _passed)
	close()
