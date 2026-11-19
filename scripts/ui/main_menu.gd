class_name MainMenu
extends Control

## Главное меню: ЭЛТ-монитор и VHS-привод (Do Not Wake)

@onready var cassette: Control = $VHSDeck/Cassette
@onready var tv_bezel: ColorRect = $TVBezel
@onready var crt_screen: ColorRect = $TVBezel/CRTScreen
@onready var vhs_deck: ColorRect = $VHSDeck
@onready var rec_dot: Label = $TVBezel/CRTScreen/VBoxTop/StatusBar/RecLabel
@onready var timecode_lbl: Label = $TVBezel/CRTScreen/VBoxTop/StatusBar/TimecodeLabel
@onready var title_lbl: Label = $TVBezel/CRTScreen/VBoxMenu/Title
@onready var sfx_click: AudioStreamPlayer = $SFXClick
@onready var sfx_vhs: AudioStreamPlayer = $SFXVHS

var is_starting: bool = false
var timecode_seconds: float = 868.0
var rec_timer: float = 0.0
var title_drift_timer: float = 0.0
var original_title_pos: Vector2 = Vector2.ZERO

# 2.5D-глубина: корпус ТВ и VHS-привод живут на разных слоях (data/parallax.json)
var parallax: ParallaxRig
var _base_positions: Dictionary = {}
var _window_focused: bool = true


func _ready() -> void:
	if title_lbl:
		original_title_pos = title_lbl.position
	parallax = ParallaxRig.new()
	_base_positions = {
		"bezel": tv_bezel.position,
		"screen": crt_screen.position,
		"deck": vhs_deck.position,
	}
	_apply_parallax()
	update_timecode_string()


func _process(delta: float) -> void:
	timecode_seconds += delta
	update_timecode_string()

	# Мигание REC раз в 1 сек
	rec_timer += delta
	if rec_dot:
		rec_dot.visible = fmod(rec_timer, 1.0) < 0.65

	# Дрейф заголовка (эффект рассинхрона строчной развёртки ЭЛТ)
	title_drift_timer += delta
	if title_drift_timer > 3.5 and title_lbl:
		title_lbl.position.x = original_title_pos.x + randf_range(-2.0, 2.0)
		if title_drift_timer > 3.65:
			title_lbl.position.x = original_title_pos.x
			title_drift_timer = 0.0

	_update_parallax(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		if parallax:
			parallax.reset()
			_apply_parallax()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true


func _update_parallax(delta: float) -> void:
	if parallax == null:
		return
	if _window_focused:
		parallax.update(delta, get_global_mouse_position(), get_viewport_rect().size)
	else:
		parallax.reset()
	_apply_parallax()


## Корпус двигается на своей глубине, экран — на своей поверх корпуса.
func _apply_parallax() -> void:
	if parallax == null or _base_positions.is_empty():
		return
	var bezel_shift := parallax.offset_for_layer("menu_bezel")
	var screen_shift := parallax.offset_for_layer("menu_screen")
	var deck_shift := parallax.offset_for_layer("menu_deck")
	tv_bezel.position = (_base_positions["bezel"] as Vector2) + bezel_shift
	crt_screen.position = (_base_positions["screen"] as Vector2) + (screen_shift - bezel_shift)
	vhs_deck.position = (_base_positions["deck"] as Vector2) + deck_shift


func update_timecode_string() -> void:
	if not timecode_lbl:
		return
	var total_sec := int(timecode_seconds)
	var hrs := total_sec / 3600
	var mins := (total_sec % 3600) / 60
	var secs := total_sec % 60
	var frames := int(fmod(timecode_seconds, 1.0) * 24.0)
	timecode_lbl.text = "CH 03   SP   %02d:%02d:%02d:%02d" % [hrs, mins, secs, frames]


func _on_cassette_gui_input(event: InputEvent) -> void:
	if is_starting:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		start_game_sequence()


func _on_new_shift_pressed() -> void:
	if is_starting:
		return
	start_game_sequence()


func _on_quit_pressed() -> void:
	if sfx_click:
		sfx_click.play()
	get_tree().quit()


func start_game_sequence() -> void:
	is_starting = true
	if sfx_vhs:
		sfx_vhs.play()

	# Анимация заезда кассеты в слот
	var tween := create_tween().set_parallel(true)
	if cassette:
		tween.tween_property(cassette, "position:y", cassette.position.y + 14.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(cassette, "modulate:a", 0.3, 0.4)

	var screen_node: Node = $TVBezel/CRTScreen
	if screen_node is CanvasItem:
		var crt_tween := create_tween()
		crt_tween.tween_interval(0.35)
		crt_tween.tween_property(screen_node, "modulate", Color(1.8, 1.8, 2.0), 0.08)
		crt_tween.tween_property(screen_node, "modulate", Color(0.0, 0.0, 0.0), 0.15)

	await get_tree().create_timer(0.65).timeout
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
