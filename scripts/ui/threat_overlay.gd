class_name ThreatOverlay
extends CanvasLayer

## Оверлей угрозы и пробуждения (слой 60, 1280×720)
## Управляет блокировкой ввода при AWAKE и паузой в REPAIR/THREAT_CONTROL

signal pause_requested
signal resume_requested

const PALETTE_GUNMETAL := Color("#1A2028")
const PALETTE_CLOUD_WHITE := Color("#EDF0F4")
const PALETTE_SIGNAL := Color("#748B91")
const PALETTE_ALERT := Color("#E62815")
const PALETTE_STEEL := Color("#5A5A59")
const PALETTE_COOL_SLATE := Color("#D1CCC7")

@onready var wake_overlay: Control = $WakeOverlay
@onready var wake_center: VBoxContainer = $WakeOverlay/CenterBox
@onready var wake_bar: ProgressBar = $WakeOverlay/CenterBox/TimerBar
@onready var pause_overlay: Control = $PauseOverlay
@onready var pause_btn_hud: Button = $HudPauseButton
@onready var resume_btn: Button = $PauseOverlay/Banner/VBox/ResumeButton

var _wake_active: bool = false
var _pause_active: bool = false
var _hud_pause_visible: bool = false
var _freeze_total: float = 6.0
var _freeze_left: float = 0.0


func _ready() -> void:
	layer = 60
	visible = true
	_ensure_nodes()
	if wake_overlay != null:
		wake_overlay.visible = false
	if pause_overlay != null:
		pause_overlay.visible = false
	if pause_btn_hud != null:
		pause_btn_hud.visible = false
		if not pause_btn_hud.pressed.is_connected(_on_pause_pressed):
			pause_btn_hud.pressed.connect(_on_pause_pressed)
	if resume_btn != null and not resume_btn.pressed.is_connected(_on_resume_pressed):
		resume_btn.pressed.connect(_on_resume_pressed)


func _ensure_nodes() -> void:
	if wake_overlay == null and has_node("WakeOverlay"):
		wake_overlay = get_node("WakeOverlay")
		wake_center = get_node_or_null("WakeOverlay/CenterBox")
		wake_bar = get_node_or_null("WakeOverlay/CenterBox/TimerBar")
		pause_overlay = get_node_or_null("PauseOverlay")
		pause_btn_hud = get_node_or_null("HudPauseButton")
		resume_btn = get_node_or_null("PauseOverlay/Banner/VBox/ResumeButton")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_P:
			if _wake_active:
				return
			get_viewport().set_input_as_handled()
			if _pause_active:
				_on_resume_pressed()
			elif _hud_pause_visible:
				_on_pause_pressed()


func _process(delta: float) -> void:
	if _wake_active:
		_freeze_left = maxf(_freeze_left - delta, 0.0)
		if wake_bar != null and _freeze_total > 0.0:
			wake_bar.value = (_freeze_left / _freeze_total) * 100.0
		if wake_center != null:
			var shake_x := randf_range(-2.0, 2.0)
			var shake_y := randf_range(-1.5, 1.5)
			wake_center.position = Vector2(340 + shake_x, 260 + shake_y)


func show_wake(duration: float = 6.0) -> void:
	_ensure_nodes()
	_wake_active = true
	_freeze_total = maxf(duration, 0.1)
	_freeze_left = _freeze_total
	if wake_overlay:
		wake_overlay.visible = true
		wake_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if pause_btn_hud:
		pause_btn_hud.visible = false


func hide_wake() -> void:
	_ensure_nodes()
	_wake_active = false
	_freeze_left = 0.0
	if wake_overlay:
		wake_overlay.visible = false
	if _hud_pause_visible and not _pause_active and pause_btn_hud:
		pause_btn_hud.visible = true


func show_pause() -> void:
	_ensure_nodes()
	_pause_active = true
	if pause_overlay:
		pause_overlay.visible = true
	if pause_btn_hud:
		pause_btn_hud.visible = false


func hide_pause() -> void:
	_ensure_nodes()
	_pause_active = false
	if pause_overlay:
		pause_overlay.visible = false
	if _hud_pause_visible and not _wake_active and pause_btn_hud:
		pause_btn_hud.visible = true


func set_hud_pause_visible(is_vis: bool) -> void:
	_ensure_nodes()
	_hud_pause_visible = is_vis
	if pause_btn_hud:
		pause_btn_hud.visible = is_vis and not _wake_active and not _pause_active


func is_wake_active() -> bool:
	return _wake_active


func is_paused() -> bool:
	return _pause_active


func _on_pause_pressed() -> void:
	_ensure_nodes()
	if _wake_active:
		return
	emit_signal("pause_requested")


func _on_resume_pressed() -> void:
	_ensure_nodes()
	emit_signal("resume_requested")
