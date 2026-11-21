class_name PartMarkers
extends Node2D

## Метки деталей робота (Node2D, Z-index 6)
## Отрисовывает плашки с tag по координатам tag_pos и диегетические шильдики

signal part_clicked(part_id: String)

const PALETTE_GUNMETAL := Color("#1A2028")
const PALETTE_PALE_STEEL := Color("#C4CDD6")
const PALETTE_CLOUD_WHITE := Color("#EDF0F4")
const PALETTE_SIGNAL := Color("#748B91")
const PALETTE_ALERT := Color("#E62815")
const PALETTE_STEEL := Color("#5A5A59")

const PLATE_SIZE := Vector2(64, 24)
const PLATE_TEXTURE_PATH := "res://assets/sprites/ui/part_tag_plate.png"

var _plate_texture: Texture2D
var _markers: Dictionary = {} # part_id -> Dictionary с ссылками на узлы
var selected_part_id: String = ""
var _is_locked: bool = false


func _ready() -> void:
	z_index = 6
	_load_resources()


func _load_resources() -> void:
	if ResourceLoader.exists(PLATE_TEXTURE_PATH):
		_plate_texture = load(PLATE_TEXTURE_PATH)


func show_for(parts: Array) -> void:
	visible = true
	_clear_markers()
	selected_part_id = ""
	_is_locked = false

	for p_data in parts:
		if p_data is Dictionary:
			_create_marker(p_data as Dictionary)


func hide_all() -> void:
	visible = false
	_clear_markers()


func select_part(part_id: String) -> void:
	selected_part_id = part_id
	for id in _markers.keys():
		var m: Dictionary = _markers[id]
		var plate: Control = m.get("plate")
		var label: Label = m.get("label")
		if id == part_id:
			if plate:
				plate.modulate = PALETTE_SIGNAL
			if label:
				label.modulate = PALETTE_CLOUD_WHITE
		else:
			if plate:
				plate.modulate = Color.WHITE
			if label:
				label.modulate = PALETTE_CLOUD_WHITE


func flash_error(part_id: String) -> void:
	var m: Dictionary = _markers.get(part_id, {})
	var plate: Control = m.get("plate")
	if plate == null:
		return
	var orig_color: Color = plate.modulate
	var tw := create_tween()
	tw.tween_property(plate, "modulate", PALETTE_ALERT, 0.1)
	tw.tween_property(plate, "modulate", orig_color, 0.3)


func click_part(part_id: String) -> void:
	_handle_click(part_id)


## Экранный прямоугольник бирки (для обучения).
func get_marker_rect(part_id: String) -> Rect2:
	var m: Dictionary = _markers.get(part_id, {})
	var root: Control = m.get("root")
	if root == null or not visible or not root.is_visible_in_tree():
		return Rect2()
	return root.get_global_rect()


func _clear_markers() -> void:
	for child in get_children():
		child.queue_free()
	_markers.clear()


func _create_marker(part: Dictionary) -> void:
	var part_id: String = str(part.get("id", ""))
	if part_id == "":
		return

	var tag: String = str(part.get("tag", "??"))
	var comp_name: String = str(part.get("component_name", part.get("label", part_id)))
	var pos_raw: Variant = part.get("tag_pos", [640, 360])
	var pos := Vector2(640, 360)
	if pos_raw is Array and (pos_raw as Array).size() >= 2:
		pos = Vector2(float(pos_raw[0]), float(pos_raw[1]))
	elif pos_raw is Vector2:
		pos = pos_raw

	var root_ctrl := Control.new()
	root_ctrl.name = "Marker_" + part_id
	root_ctrl.position = pos - (PLATE_SIZE * 0.5)
	root_ctrl.size = PLATE_SIZE
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS

	var plate := NinePatchRect.new()
	plate.name = "Plate"
	plate.size = PLATE_SIZE
	if _plate_texture:
		plate.texture = _plate_texture
		plate.patch_margin_left = 6
		plate.patch_margin_top = 6
		plate.patch_margin_right = 6
		plate.patch_margin_bottom = 6
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	root_ctrl.add_child(plate)

	var label := Label.new()
	label.name = "TagLabel"
	label.size = PLATE_SIZE
	label.text = tag
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", PALETTE_CLOUD_WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(label)

	var badge := PanelContainer.new()
	badge.name = "Badge"
	badge.visible = false
	badge.position = Vector2(-20, -28)
	badge.custom_minimum_size = Vector2(100, 22)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var badge_label := Label.new()
	badge_label.text = comp_name
	badge_label.add_theme_font_size_override("font_size", 9)
	badge_label.add_theme_color_override("font_color", PALETTE_PALE_STEEL)
	badge.add_child(badge_label)
	root_ctrl.add_child(badge)

	plate.mouse_entered.connect(func():
		if part_id != selected_part_id:
			plate.modulate = PALETTE_PALE_STEEL
		badge.visible = true
	)

	plate.mouse_exited.connect(func():
		if part_id != selected_part_id:
			plate.modulate = Color.WHITE
		badge.visible = false
	)

	plate.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_handle_click(part_id)
	)

	add_child(root_ctrl)
	_markers[part_id] = {
		"root": root_ctrl,
		"plate": plate,
		"label": label,
		"badge": badge,
		"tag": tag,
		"component_name": comp_name
	}


func _handle_click(part_id: String) -> void:
	if _is_locked or part_id == selected_part_id:
		return
	emit_signal("part_clicked", part_id)
