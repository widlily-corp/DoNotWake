class_name RobotProceduralAnimation
extends RefCounted

## Procedural life animation for the sleeping robot (Do Not Wake).
## Operates under strict Zero GC principles: no memory allocations during update or render frames.
##
## 1. Torso breathing: smooth sinusoidal micro-oscillations of the chest (1-2 px y-offset / y-scale).
## 2. Head micro-motions: rare heavy neck servo twitches during sleep (spring-damper physical response).
## 3. Instability tremor: high-frequency body micro-shudder scaled to instability / threshold.

signal servo_twitched(intensity: float)

# --- Configurable Parameters ---
var breath_base_frequency: float = 0.25 # Hz (~4.0s breath cycle)
var breath_amplitude_px: float = 1.5 # 1-2 pixels micro-oscillation

var min_twitch_interval: float = 4.0 # Seconds between neck servo twitches
var max_twitch_interval: float = 8.5 # Seconds between neck servo twitches
var twitch_stiffness: float = 160.0 # Heavy spring stiffness
var twitch_damping: float = 15.0 # Damped settling

var max_tremor_px: float = 2.4 # Maximum micro-tremor amplitude at threshold
var tremor_deadzone: float = 0.20 # Below 20% of threshold, tremor is 0.0

# --- Runtime State (Pre-allocated, Zero GC) ---
var breath_time: float = 0.0
var breath_offset_y: float = 0.0
var breath_scale_y: float = 1.0

var twitch_timer: float = 0.0
var head_twitch_offset: Vector2 = Vector2.ZERO
var head_twitch_velocity: Vector2 = Vector2.ZERO
var head_twitch_rotation: float = 0.0
var head_twitch_rot_velocity: float = 0.0

var tremor_time: float = 0.0
var current_tremor_amp: float = 0.0
var tremor_offset: Vector2 = Vector2.ZERO

var current_instability: float = 20.0
var current_threshold: float = 70.0
var is_awake: bool = false


func _init() -> void:
	reset()


## Resets all internal timers and oscillation states to pristine sleep values.
func reset() -> void:
	breath_time = 0.0
	breath_offset_y = 0.0
	breath_scale_y = 1.0

	twitch_timer = randf_range(min_twitch_interval * 0.5, min_twitch_interval)
	head_twitch_offset = Vector2.ZERO
	head_twitch_velocity = Vector2.ZERO
	head_twitch_rotation = 0.0
	head_twitch_rot_velocity = 0.0

	tremor_time = 0.0
	current_tremor_amp = 0.0
	tremor_offset = Vector2.ZERO

	current_instability = 20.0
	current_threshold = 70.0
	is_awake = false


## Primary frame update. Operates without any heap allocations (Zero GC).
func update(delta: float, instability: float, threshold: float, awake: bool) -> void:
	current_instability = instability
	current_threshold = maxf(threshold, 1.0)
	is_awake = awake

	var inst_ratio: float = clampf(current_instability / current_threshold, 0.0, 1.5)

	# 1. Torso Breathing: smooth sinusoidal micro-oscillation (1-2 px)
	_update_breathing(delta, inst_ratio, awake)

	# 2. Neck Servo Micro-twitches: rare heavy mechanical impulses in sleep
	_update_head_twitches(delta, awake)

	# 3. Instability Tremor: multi-frequency vibration proportional to instability / threshold
	_update_tremor(delta, inst_ratio, awake)


## Calculates smooth sinusoidal chest breathing.
func _update_breathing(delta: float, inst_ratio: float, awake: bool) -> void:
	if awake:
		# Rapid, tense, erratic breathing while awake
		breath_time += delta * 1.8 * TAU
		breath_offset_y = sin(breath_time) * (breath_amplitude_px * 0.7)
		breath_scale_y = 1.0 + (breath_offset_y * 0.005)
		return

	# Breathing speeds up slightly as internal temperature/instability rises
	var dynamic_freq: float = lerpf(breath_base_frequency, breath_base_frequency * 1.5, inst_ratio)
	breath_time += delta * dynamic_freq * TAU
	if breath_time > TAU * 1000.0:
		breath_time = fmod(breath_time, TAU)

	# Smooth sinusoidal oscillation between -1.0 and +1.0
	var breath_sin: float = sin(breath_time)
	breath_offset_y = breath_sin * breath_amplitude_px
	breath_scale_y = 1.0 + (breath_offset_y * 0.006)


## Physical spring-damper simulation for heavy neck servo twitches.
func _update_head_twitches(delta: float, awake: bool) -> void:
	if awake:
		# In awake state, servos are engaged; damp any lingering twitch to zero
		head_twitch_velocity = Vector2.ZERO
		head_twitch_offset = head_twitch_offset.move_toward(Vector2.ZERO, delta * 10.0)
		head_twitch_rot_velocity = 0.0
		head_twitch_rotation = move_toward(head_twitch_rotation, 0.0, delta * 2.0)
		return

	# Countdown to next rare twitch
	twitch_timer -= delta
	if twitch_timer <= 0.0:
		trigger_servo_twitch()
		twitch_timer = randf_range(min_twitch_interval, max_twitch_interval)

	# Damped harmonic oscillator integration (semi-implicit Euler, zero GC)
	head_twitch_velocity.x += (-twitch_stiffness * head_twitch_offset.x - twitch_damping * head_twitch_velocity.x) * delta
	head_twitch_velocity.y += (-twitch_stiffness * head_twitch_offset.y - twitch_damping * head_twitch_velocity.y) * delta
	head_twitch_offset.x += head_twitch_velocity.x * delta
	head_twitch_offset.y += head_twitch_velocity.y * delta

	head_twitch_rot_velocity += (-twitch_stiffness * head_twitch_rotation - twitch_damping * head_twitch_rot_velocity) * delta
	head_twitch_rotation += head_twitch_rot_velocity * delta


## Manually or periodically injects a heavy mechanical neck servo twitch impulse.
func trigger_servo_twitch(impulse_scale: float = 1.0) -> void:
	var dir_x: float = -1.0 if randf() < 0.5 else 1.0
	head_twitch_velocity.x += dir_x * randf_range(28.0, 48.0) * impulse_scale
	head_twitch_velocity.y += randf_range(-12.0, 14.0) * impulse_scale
	head_twitch_rot_velocity += dir_x * randf_range(0.35, 0.85) * impulse_scale
	servo_twitched.emit(impulse_scale)


## Multi-frequency deterministic mechanical vibration proportional to instability.
func _update_tremor(delta: float, inst_ratio: float, awake: bool) -> void:
	tremor_time += delta
	if tremor_time > 10000.0:
		tremor_time = fmod(tremor_time, 100.0)

	if awake:
		# Violently shaking when awakened
		current_tremor_amp = max_tremor_px * 1.5
	elif inst_ratio <= tremor_deadzone:
		current_tremor_amp = 0.0
		tremor_offset.x = 0.0
		tremor_offset.y = 0.0
		return
	else:
		# Quadratic ease-in: micro-vibrations start faint and grow menacingly
		var norm_t: float = clampf((inst_ratio - tremor_deadzone) / (1.0 - tremor_deadzone), 0.0, 1.5)
		current_tremor_amp = norm_t * norm_t * max_tremor_px

	# Resonant multi-frequency synthesis (non-harmonic sines, Zero GC)
	var sx: float = sin(tremor_time * 43.7) * 0.55 + sin(tremor_time * 89.3) * 0.35 + sin(tremor_time * 151.1) * 0.1
	var sy: float = cos(tremor_time * 47.1) * 0.55 + cos(tremor_time * 83.9) * 0.35 + cos(tremor_time * 143.7) * 0.1

	tremor_offset.x = sx * current_tremor_amp
	tremor_offset.y = sy * current_tremor_amp


# --- Public Kinematic Query Accessors ---

## Body micro-tremor offset (applied to whole containment rig / chassis).
func get_tremor_offset() -> Vector2:
	return tremor_offset


## Vertical breathing offset of the chest (1-2 px oscillation).
func get_chest_breath_offset_y() -> float:
	return breath_offset_y


## Full composite offset for the chest (instability tremor + breathing oscillation).
func get_chest_offset() -> Vector2:
	return tremor_offset + Vector2(0.0, breath_offset_y)


## Full composite offset for the head (amplified tremor + breath follow + servo twitch).
func get_head_offset() -> Vector2:
	return tremor_offset * 1.25 + Vector2(0.0, breath_offset_y * 0.5) + head_twitch_offset


## Angular tilt of the head in radians (neck servo mechanical jolt).
func get_head_rotation() -> float:
	return head_twitch_rotation


## Subtle y-scale for chest breathing expansion.
func get_chest_scale_y() -> float:
	return breath_scale_y


# --- High-Fidelity Procedural Renderer ---

## Renders the sleeping automaton with organic procedural life:
## Slices head, chest, and lower body seamlessly with strap overlaps and procedural transforms.
func render_robot(
	canvas: CanvasItem,
	tex_robot: Texture2D,
	tex_shadow: Texture2D,
	robot_rect: Rect2,
	base_offset: Vector2,
	awake: bool,
	heat_ratio: float = 0.0
) -> void:
	if canvas == null:
		return

	# 1. Contact shadow in the niche (subtle damped tremor gives 2.5D depth separation)
	if tex_shadow:
		var shadow_pos := robot_rect.position + base_offset + tremor_offset * 0.25 + Vector2(10.0, 14.0)
		canvas.draw_texture_rect(tex_shadow, Rect2(shadow_pos, robot_rect.size), false)

	# Fallback if no texture is present
	if tex_robot == null:
		_render_fallback(canvas, robot_rect, base_offset, awake, heat_ratio)
		return

	var tw: float = float(tex_robot.get_width())
	var th: float = float(tex_robot.get_height())

	# Subtle thermal warning glow as instability rises
	var robot_tint := Color.WHITE
	if awake:
		robot_tint = Color(1.15, 0.88, 0.88)
	elif heat_ratio > 0.4:
		var alert_glow := (heat_ratio - 0.4) / 0.6
		robot_tint = Color.WHITE.lerp(Color(1.18, 0.90, 0.82), alert_glow * 0.35)

	# 2. Lower Body (Legs and Pelvis - securely clamped in niche)
	# Src texture slice: y = 0.60 to 1.0 (overlaps under waist strap)
	var lower_src := Rect2(0.0, th * 0.60, tw, th * 0.40)
	var lower_dst := Rect2(
		robot_rect.position.x + base_offset.x + tremor_offset.x,
		robot_rect.position.y + robot_rect.size.y * 0.60 + base_offset.y + tremor_offset.y,
		robot_rect.size.x,
		robot_rect.size.y * 0.40
	)
	canvas.draw_texture_rect_region(tex_robot, lower_dst, lower_src, robot_tint)

	# 3. Torso / Ribcage (Breathing sine micro-oscillation + tremor)
	# Src texture slice: y = 0.24 to 0.62 (overlaps under collar strap and waist strap)
	var chest_src := Rect2(0.0, th * 0.24, tw, th * 0.38)
	var chest_y := robot_rect.position.y + robot_rect.size.y * 0.24 + base_offset.y + tremor_offset.y + breath_offset_y
	var chest_dst := Rect2(
		robot_rect.position.x + base_offset.x + tremor_offset.x,
		chest_y,
		robot_rect.size.x,
		robot_rect.size.y * 0.38
	)
	canvas.draw_texture_rect_region(tex_robot, chest_dst, chest_src, robot_tint)

	# 4. Head and Neck (Rare servo twitch impulse + rotation + breath follow)
	# Src texture slice: y = 0.0 to 0.26 (overlaps under collar strap)
	var head_src := Rect2(0.0, 0.0, tw, th * 0.26)
	var head_size := Vector2(robot_rect.size.x, robot_rect.size.y * 0.26)

	var neck_pivot := Vector2(
		robot_rect.position.x + base_offset.x + tremor_offset.x + robot_rect.size.x * 0.5,
		robot_rect.position.y + base_offset.y + tremor_offset.y + robot_rect.size.y * 0.25 + (breath_offset_y * 0.5)
	)

	var head_rel_pos := Vector2(
		-robot_rect.size.x * 0.5 + head_twitch_offset.x,
		-robot_rect.size.y * 0.25 + head_twitch_offset.y
	)

	if absf(head_twitch_rotation) > 0.0001:
		canvas.draw_set_transform(neck_pivot, head_twitch_rotation, Vector2.ONE)
		canvas.draw_texture_rect_region(tex_robot, Rect2(head_rel_pos, head_size), head_src, robot_tint)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var head_abs_rect := Rect2(neck_pivot + head_rel_pos, head_size)
		canvas.draw_texture_rect_region(tex_robot, head_abs_rect, head_src, robot_tint)


func _render_fallback(canvas: CanvasItem, robot_rect: Rect2, base_offset: Vector2, awake: bool, heat_ratio: float) -> void:
	var col_base := Color(0.28, 0.35, 0.42).lerp(Color(0.90, 0.16, 0.10), heat_ratio if not awake else 1.0)

	# Lower body
	var lower_dst := Rect2(
		robot_rect.position.x + base_offset.x + tremor_offset.x,
		robot_rect.position.y + robot_rect.size.y * 0.60 + base_offset.y + tremor_offset.y,
		robot_rect.size.x,
		robot_rect.size.y * 0.40
	)
	canvas.draw_rect(lower_dst, col_base * 0.85)

	# Chest
	var chest_y := robot_rect.position.y + robot_rect.size.y * 0.24 + base_offset.y + tremor_offset.y + breath_offset_y
	var chest_dst := Rect2(
		robot_rect.position.x + base_offset.x + tremor_offset.x,
		chest_y,
		robot_rect.size.x,
		robot_rect.size.y * 0.38
	)
	canvas.draw_rect(chest_dst, col_base)

	# Head
	var head_pos := Vector2(
		robot_rect.position.x + base_offset.x + tremor_offset.x + head_twitch_offset.x,
		robot_rect.position.y + base_offset.y + tremor_offset.y + (breath_offset_y * 0.5) + head_twitch_offset.y
	)
	var head_dst := Rect2(head_pos, Vector2(robot_rect.size.x, robot_rect.size.y * 0.26))
	canvas.draw_rect(head_dst, col_base * 1.15)
