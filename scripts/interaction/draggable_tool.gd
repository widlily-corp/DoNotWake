class_name DraggableTool
extends Node2D

## Tactile draggable physical tool on the workbench / tray.
## Supports smooth inertia, drag tilt, bounds clamping, and spring-return.
## В новой петле инструмент «залипает» в руке: один клик по лотку — взять,
## повторный клик по лотку — положить. Так ветошью можно тереть без зажатой ЛКМ.

enum State { IDLE, DRAGGING, HELD, RETURNING }

signal drag_started(tool_id: String)
signal drag_ended(tool_id: String, drop_pos: Vector2)
signal returned_to_tray(tool_id: String)

const SHADOW_COLOR: Color = Color(0.02, 0.03, 0.04, 0.45)
const HIGHLIGHT_COLOR: Color = Color(0.92, 0.95, 0.98, 0.25)
const SCREEN_BOUNDS_MIN: Vector2 = Vector2(20.0, 20.0)
const SCREEN_BOUNDS_MAX: Vector2 = Vector2(1260.0, 700.0)

var tool_id: String = ""
var label: String = ""
var home_rect: Rect2 = Rect2()
var home_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var drag_offset: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var last_pos: Vector2 = Vector2.ZERO

var current_state: State = State.IDLE
var is_hovered: bool = false
var texture: Texture2D = null
var tool_size: Vector2 = Vector2(80.0, 80.0)
var font: Font = null

var tilt_angle: float = 0.0
var lift_scale: float = 1.0
var is_enabled: bool = true
var tip_offset: Vector2 = Vector2.ZERO
var is_anchored: bool = false


func setup(p_id: String, p_label: String, p_rect: Rect2, p_texture: Texture2D = null, p_font: Font = null) -> void:
	tool_id = p_id
	label = p_label
	home_rect = p_rect
	home_pos = p_rect.position + p_rect.size * 0.5
	position = home_pos
	target_pos = home_pos
	last_pos = home_pos
	texture = p_texture
	font = p_font
	tool_size = p_rect.size

	if tool_id == "screwdriver":
		tip_offset = Vector2(76.0, 0.0)
	else:
		tip_offset = Vector2.ZERO


func set_home_offset(shift: Vector2) -> void:
	var shifted_home: Vector2 = home_rect.position + home_rect.size * 0.5 + shift
	home_pos = shifted_home
	if current_state == State.IDLE:
		position = home_pos
		target_pos = home_pos


func handle_mouse_input(event: InputEvent, mouse_pos: Vector2) -> bool:
	if not is_enabled:
		return false

	if event is InputEventMouseMotion:
		is_hovered = _grab_rect().has_point(mouse_pos)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if current_state == State.HELD:
				# Инструмент в руке: убрать его можно только кликом по своему лотку.
				# Остальные клики уходят в мир (болты, порт, ползунок), чтобы не мешать ремонту.
				if _home_rect().has_point(mouse_pos):
					put_down()
					return true
				return false
			if current_state == State.DRAGGING:
				return false
			if _grab_rect().has_point(mouse_pos):
				take_in_hand(mouse_pos)
				return true
		else:
			if current_state == State.DRAGGING:
				end_drag(mouse_pos)
				return true

	return false


func _grab_rect() -> Rect2:
	var center: Vector2 = home_pos if current_state == State.RETURNING else position
	return Rect2(center - tool_size * 0.5, tool_size).grow(4.0)


func _home_rect() -> Rect2:
	return Rect2(home_pos - tool_size * 0.5, tool_size).grow(6.0)


func is_in_hand() -> bool:
	return current_state == State.HELD


## Взять инструмент в руку: он следует за курсором без удержания кнопки.
func take_in_hand(mouse_pos: Vector2) -> void:
	current_state = State.HELD
	drag_offset = Vector2.ZERO
	position = mouse_pos
	target_pos = mouse_pos
	last_pos = mouse_pos
	velocity = Vector2.ZERO
	z_index = 20
	rotation = 0.0
	scale = Vector2.ONE
	emit_signal("drag_started", tool_id)


## Положить инструмент обратно в лоток.
func put_down() -> void:
	if current_state != State.HELD and current_state != State.DRAGGING:
		return
	release_anchor()
	current_state = State.RETURNING
	target_pos = home_pos
	velocity = Vector2.ZERO
	z_index = 5
	emit_signal("drag_ended", tool_id, position)


func get_tip_position() -> Vector2:
	return position + tip_offset.rotated(rotation)


func anchor_tip_to(target_tip_pos: Vector2, mouse_pos: Vector2) -> void:
	is_anchored = true
	var angle := (mouse_pos - target_tip_pos).angle()
	rotation = angle + PI
	position = target_tip_pos - tip_offset.rotated(rotation)
	tilt_angle = rotation
	target_pos = position
	last_pos = position
	drag_offset = position - mouse_pos
	lift_scale = 1.0
	scale = Vector2.ONE


func release_anchor() -> void:
	if is_anchored:
		is_anchored = false
		target_pos = position
		last_pos = position


func start_drag(mouse_pos: Vector2) -> void:
	current_state = State.DRAGGING
	drag_offset = position - mouse_pos
	target_pos = mouse_pos + drag_offset
	z_index = 20
	emit_signal("drag_started", tool_id)


func end_drag(mouse_pos: Vector2) -> void:
	release_anchor()
	current_state = State.RETURNING
	target_pos = home_pos
	z_index = 5
	emit_signal("drag_ended", tool_id, position)


func return_to_tray() -> void:
	release_anchor()
	current_state = State.RETURNING
	target_pos = home_pos


func apply_kickback(impulse: Vector2, angular_impulse: float = 0.0) -> void:
	release_anchor()
	current_state = State.RETURNING
	velocity = impulse
	tilt_angle += angular_impulse
	lift_scale = 1.25
	target_pos = home_pos
	z_index = 15


func snap_to(pos: Vector2) -> void:
	position = pos
	target_pos = pos
	last_pos = pos
	velocity = Vector2.ZERO


func update_tool(delta: float, mouse_pos: Vector2) -> void:
	if delta <= 0.0:
		return

	if is_anchored:
		return

	if current_state == State.DRAGGING or current_state == State.HELD:
		target_pos = (mouse_pos + drag_offset).clamp(SCREEN_BOUNDS_MIN, SCREEN_BOUNDS_MAX)
		# Smooth follow with inertia
		var lerp_weight: float = clampf(delta * 28.0, 0.0, 1.0)
		position = position.lerp(target_pos, lerp_weight)
		velocity = (position - last_pos) / delta
		last_pos = position

		# Tilt based on horizontal velocity
		var target_tilt: float = clampf(velocity.x * 0.0004, -0.30, 0.30)
		tilt_angle = lerpf(tilt_angle, target_tilt, delta * 18.0)
		lift_scale = lerpf(lift_scale, 1.10, delta * 16.0)

	elif current_state == State.RETURNING:
		if velocity.length_squared() > 100.0:
			position += velocity * delta
			velocity = velocity.lerp(Vector2.ZERO, delta * 6.5)
			tilt_angle = lerpf(tilt_angle, 0.0, delta * 8.0)
			lift_scale = lerpf(lift_scale, 1.0, delta * 10.0)
			last_pos = position
		else:
			var dist: float = position.distance_to(home_pos)
			if dist < 2.0:
				position = home_pos
				current_state = State.IDLE
				tilt_angle = 0.0
				lift_scale = 1.0
				velocity = Vector2.ZERO
				emit_signal("returned_to_tray", tool_id)
			else:
				var lerp_weight: float = clampf(delta * 14.0, 0.0, 1.0)
				position = position.lerp(home_pos, lerp_weight)
				tilt_angle = lerpf(tilt_angle, 0.0, delta * 12.0)
				lift_scale = lerpf(lift_scale, 1.0, delta * 14.0)

	elif current_state == State.IDLE:
		tilt_angle = 0.0
		lift_scale = 1.0
		velocity = Vector2.ZERO

	rotation = tilt_angle
	scale = Vector2(lift_scale, lift_scale)


func _draw() -> void:
	var half_w: float = tool_size.x * 0.5
	var half_h: float = tool_size.y * 0.5
	var draw_rect: Rect2 = Rect2(-half_w, -half_h, tool_size.x, tool_size.y)

	# Drop shadow when lifted or anchored
	if current_state == State.DRAGGING or current_state == State.HELD or current_state == State.RETURNING:
		var shadow_offset: Vector2 = Vector2(3.0, 4.0) if is_anchored else (Vector2(8.0, 14.0) * lift_scale)
		var shadow_rect: Rect2 = Rect2(draw_rect.position + shadow_offset, draw_rect.size * 0.95)
		draw_rect(shadow_rect, SHADOW_COLOR, true)

	if texture:
		draw_texture_rect(texture, draw_rect, false)
	else:
		# Fallback stylized metallic tool plate
		draw_rect(draw_rect, Color(0.20, 0.24, 0.28))
		draw_rect(draw_rect, Color(0.60, 0.68, 0.74), false, 2.0)

	# Hover or drag outline
	if is_hovered or current_state == State.DRAGGING:
		draw_rect(draw_rect, HIGHLIGHT_COLOR, false, 2.0)
