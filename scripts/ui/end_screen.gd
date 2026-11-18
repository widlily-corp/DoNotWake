class_name EndScreen
extends Control

## Экран завершения смены (успех / провал)

@onready var title_lbl: Label = $CenterContainer/Panel/Margin/VBox/TitleLabel
@onready var details_lbl: Label = $CenterContainer/Panel/Margin/VBox/DetailsLabel
@onready var stats_lbl: Label = $CenterContainer/Panel/Margin/VBox/StatsLabel
@onready var sfx_click: AudioStreamPlayer = $SFXClick


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func show_result(is_success: bool, wake_count: int = 0, final_instability: float = 0.0) -> void:
	visible = true
	if is_success:
		title_lbl.text = "ЗАКАЗ ВЫПОЛНЕН"
		title_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.6))
		details_lbl.text = "Все 3 этапа ремонта завершены. Диагностика в норме."
		stats_lbl.text = "Стресс-пробуждений робота: %d\nФинальная нестабильность: %d%%" % [wake_count, int(final_instability)]
	else:
		title_lbl.text = "СМЕНА ПРОВАЛЕНА"
		title_lbl.add_theme_color_override("font_color", Color(0.95, 0.22, 0.16))
		details_lbl.text = "Робот вышел из-под контроля! Превышен критический порог."
		stats_lbl.text = "Причина: аварийный перегрев сервосистем\nСтресс-пробуждений: %d" % wake_count

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_btn_restart_pressed() -> void:
	if sfx_click:
		sfx_click.play()
	get_tree().reload_current_scene()


func _on_btn_menu_pressed() -> void:
	if sfx_click:
		sfx_click.play()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
