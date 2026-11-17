extends Control
## Главное меню: «Играть» открывает сцену ремонта, «Выход» закрывает игру.

const MAIN_SCENE := "res://scenes/Main.tscn"

@onready var play_button: Button = $Center/Menu/PlayButton
@onready var quit_button: Button = $Center/Menu/QuitButton


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_button.grab_focus()


func _on_play_pressed() -> void:
	var err := get_tree().change_scene_to_file(MAIN_SCENE)
	if err != OK:
		push_error("Не удалось открыть сцену %s (код %d)" % [MAIN_SCENE, err])


func _on_quit_pressed() -> void:
	get_tree().quit()
