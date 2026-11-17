class_name GameState
extends Node

## Состояния игрового процесса и робота
enum State { CALM, AWAKE, DONE, FAIL }

signal state_changed(new_state: State)


func _ready() -> void:
	print("core ready")


func start() -> void:
	# TODO
	pass


func wake() -> void:
	# TODO
	pass


func calm_down() -> void:
	# TODO
	pass


func finish() -> void:
	# TODO
	pass
