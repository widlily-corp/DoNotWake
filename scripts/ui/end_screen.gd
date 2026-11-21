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


func _ensure_nodes() -> void:
	if not title_lbl:
		title_lbl = $CenterContainer/Panel/Margin/VBox/TitleLabel
		details_lbl = $CenterContainer/Panel/Margin/VBox/DetailsLabel
		stats_lbl = $CenterContainer/Panel/Margin/VBox/StatsLabel
		sfx_click = $SFXClick


func show_result(
	is_success: bool,
	wake_count: int = 0,
	final_instability: float = 0.0,
	threshold: float = 70.0,
	completed_stages: int = -1,
	total_stages: int = 3
) -> void:
	_ensure_nodes()
	visible = true

	var stages_count: int = completed_stages if completed_stages >= 0 else (total_stages if is_success else 1)
	var inst_val: int = clampi(int(round(final_instability)), 0, 100)
	var thresh_val: int = clampi(int(round(threshold)), 0, 100)

	if is_success:
		title_lbl.text = "ЗАКАЗ ВЫПОЛНЕН"
		title_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.6))
		details_lbl.text = "Все этапы ремонта успешно завершены."
		stats_lbl.text = "Этапы ремонта: %d из %d\nПорог нестабильности: %d%%\nФинальная нестабильность: %d%%\nКоличество пробуждений: %d" % [
			stages_count, total_stages, thresh_val, inst_val, wake_count
		]
	else:
		title_lbl.text = "СМЕНА ПРОВАЛЕНА"
		title_lbl.add_theme_color_override("font_color", Color(0.95, 0.22, 0.16))
		details_lbl.text = "Робот вышел из-под контроля! Смена сорвана."
		stats_lbl.text = "Этапы ремонта: %d из %d\nПорог нестабильности: %d%%\nФинальная нестабильность: %d%%\nКоличество пробуждений: %d" % [
			stages_count, total_stages, thresh_val, inst_val, wake_count
		]

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
