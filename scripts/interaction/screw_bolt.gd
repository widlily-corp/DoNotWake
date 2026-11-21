class_name ScrewBoltManager
extends Node2D

## Tactile unbolting mechanic & Spectacle Armor Hatch Demounting (Stage 2).
## Player engages screwdriver with 4 slotted bolts, performing circular / ratchet
## dragging to loosen them. Jerking or exceeding slip radius triggers a violent slip penalty.
## Once all 4 bolts pop out:
## 1. Pneumatic latches loudly snap open with spring recoil, releasing high-pressure steam plumes.
## 2. Hatch pops upward above the chassis with damped pneumatic spring physics.
## 3. Player physically grabs and slides the heavy armor plate aside along guide runners,
##    producing a metallic screech, friction sparks, and revealing a detailed power compartment
##    with pulsating multi-color diagnostic LEDs. Zero GC!

signal bolt_loosened(bolt_id: String, remaining: int)
signal tool_slipped(penalty: float, shake: float)
signal hatch_removed()
signal ratchet_tick()
signal feedback_text_requested(text: String, is_alert: bool)
signal hatch_unlatched()
signal hatch_scraped(intensity: float)
signal screen_shake_requested(shake: float)

# Authentic tactical armor & power bay palette
const COLOR_HATCH_SHADOW: Color = Color(0.01, 0.02, 0.03, 0.65)
const COLOR_HATCH_PLATE: Color = Color(0.16, 0.19, 0.23)
const COLOR_HATCH_SPECULAR: Color = Color(0.55, 0.65, 0.75, 0.85)
const COLOR_HATCH_SHADOW_RIM: Color = Color(0.08, 0.10, 0.12, 0.9)
const COLOR_HATCH_BEVEL_SIDE: Color = Color(0.10, 0.12, 0.15)

const COLOR_BOLT_RIM: Color = Color(0.80, 0.84, 0.90)
const COLOR_BOLT_CORE: Color = Color(0.22, 0.25, 0.29)
const COLOR_BOLT_SLOT: Color = Color(0.10, 0.12, 0.15)
const COLOR_SPARK: Color = Color(0.98, 0.95, 0.65)

const COLOR_BUSBAR_COPPER: Color = Color(0.88, 0.52, 0.28)
const COLOR_BUSBAR_SPECULAR: Color = Color(1.0, 0.82, 0.60)
const COLOR_HAZARD_YELLOW: Color = Color(0.94, 0.75, 0.12)
const COLOR_HAZARD_DARK: Color = Color(0.08, 0.09, 0.11)
const COLOR_STEAM_CORE: Color = Color(0.94, 0.97, 1.0)
const COLOR_STEAM_MIST: Color = Color(0.72, 0.82, 0.92)
const COLOR_LATCH_BODY: Color = Color(0.24, 0.28, 0.33)
const COLOR_LATCH_DOG: Color = Color(0.44, 0.50, 0.58)

# Backwards compatibility aliases
const COLOR_HATCH_BASE: Color = COLOR_HATCH_PLATE
const COLOR_HATCH_RIM: Color = COLOR_HATCH_SPECULAR
const COLOR_BOLT_METAL: Color = COLOR_BOLT_RIM
const COLOR_BOLT_DARK: Color = COLOR_BOLT_CORE

const MAX_SPARKS: int = 24
const MAX_STEAM: int = 80
const MAX_SCRAPE_SPARKS: int = 32

class BoltData:
	var id: String = ""
	var base_pos: Vector2 = Vector2.ZERO
	var current_pos: Vector2 = Vector2.ZERO
	var radius: float = 14.0
	var turns_required: float = 3.0
	var accumulated_rad: float = 0.0
	var angle: float = 0.0
	var last_mouse_angle: float = 0.0
	var initial_dist: float = 0.0
	var is_loose: bool = false
	var fall_velocity: Vector2 = Vector2.ZERO
	var fall_rotation_speed: float = 0.0
	var last_tick_rad: float = 0.0
	var is_popped: bool = false

var hatch_rect: Rect2 = Rect2(550.0, 320.0, 180.0, 120.0)
var snap_radius: float = 18.0
var slip_radius: float = 38.0
var max_angular_accel: float = 2500.0
var slip_penalty: float = 14.0
var slip_shake: float = 5.0

var bolts: Array[BoltData] = []
var active_bolt: BoltData = null
var is_active: bool = true
var is_hatch_removed: bool = false
var hatch_offset: Vector2 = Vector2.ZERO
var hatch_velocity: Vector2 = Vector2.ZERO
var is_dragging_hatch: bool = false
var hatch_drag_start: Vector2 = Vector2.ZERO
var anim_time: float = 0.0

# Pneumatic unlatch, lift and dragging states
var is_unlatched: bool = false
var latch_recoil: float = 0.0
var latch_recoil_vel: float = 0.0
var hatch_lift: float = 0.0
var hatch_lift_vel: float = 0.0
var hatch_rotation: float = 0.0
var hatch_rot_vel: float = 0.0
var steam_vent_timer: float = 0.0
var scrape_accum_dist: float = 0.0
var prev_drag_mouse_pos: Vector2 = Vector2.ZERO

# Pre-allocated particle pools (Zero GC)
var spark_pos: PackedVector2Array = PackedVector2Array()
var spark_vel: PackedVector2Array = PackedVector2Array()
var spark_life: PackedFloat32Array = PackedFloat32Array()

var steam_pos: PackedVector2Array = PackedVector2Array()
var steam_vel: PackedVector2Array = PackedVector2Array()
var steam_life: PackedFloat32Array = PackedFloat32Array()
var steam_max_life: PackedFloat32Array = PackedFloat32Array()
var steam_size: PackedFloat32Array = PackedFloat32Array()
var steam_growth: PackedFloat32Array = PackedFloat32Array()

var scrape_pos: PackedVector2Array = PackedVector2Array()
var scrape_vel: PackedVector2Array = PackedVector2Array()
var scrape_life: PackedFloat32Array = PackedFloat32Array()

# Procedural audio synthesis streams
var _stream_unlatch: AudioStreamWAV = null
var _stream_scrape: AudioStreamWAV = null
var _audio_player: AudioStreamPlayer = null


func _init() -> void:
	spark_pos.resize(MAX_SPARKS)
	spark_vel.resize(MAX_SPARKS)
	spark_life.resize(MAX_SPARKS)
	for i in MAX_SPARKS:
		spark_life[i] = 0.0

	steam_pos.resize(MAX_STEAM)
	steam_vel.resize(MAX_STEAM)
	steam_life.resize(MAX_STEAM)
	steam_max_life.resize(MAX_STEAM)
	steam_size.resize(MAX_STEAM)
	steam_growth.resize(MAX_STEAM)
	for i in MAX_STEAM:
		steam_life[i] = 0.0

	scrape_pos.resize(MAX_SCRAPE_SPARKS)
	scrape_vel.resize(MAX_SCRAPE_SPARKS)
	scrape_life.resize(MAX_SCRAPE_SPARKS)
	for i in MAX_SCRAPE_SPARKS:
		scrape_life[i] = 0.0

	_init_procedural_audio()


func _ready() -> void:
	if _audio_player == null and is_inside_tree():
		_audio_player = AudioStreamPlayer.new()
		_audio_player.name = "HatchSFXPlayer"
		add_child(_audio_player)


func configure(p_hatch_rect: Rect2, bolt_configs: Array, slip_params: Dictionary = {}) -> void:
	hatch_rect = p_hatch_rect
	snap_radius = float(slip_params.get("snap_radius", 18.0))
	slip_radius = float(slip_params.get("slip_radius", 38.0))
	max_angular_accel = float(slip_params.get("max_angular_accel", 2500.0))
	slip_penalty = float(slip_params.get("slip_penalty", 14.0))
	slip_shake = float(slip_params.get("slip_shake", 5.0))

	bolts.clear()
	for b in bolt_configs:
		if b is Dictionary:
			var b_data := BoltData.new()
			b_data.id = str(b.get("id", "bolt"))
			var p: Variant = b.get("pos", [0.0, 0.0])
			if p is Array and (p as Array).size() >= 2:
				b_data.base_pos = Vector2(float(p[0]), float(p[1]))
			elif p is Vector2:
				b_data.base_pos = p
			b_data.current_pos = b_data.base_pos
			b_data.radius = float(b.get("radius", 14.0))
			b_data.turns_required = float(b.get("turns_required", 3.0))
			bolts.append(b_data)


func reset() -> void:
	active_bolt = null
	is_hatch_removed = false
	is_unlatched = false
	latch_recoil = 0.0
	latch_recoil_vel = 0.0
	hatch_lift = 0.0
	hatch_lift_vel = 0.0
	hatch_rotation = 0.0
	hatch_rot_vel = 0.0
	steam_vent_timer = 0.0
	scrape_accum_dist = 0.0
	hatch_offset = Vector2.ZERO
	hatch_velocity = Vector2.ZERO
	is_dragging_hatch = false
	anim_time = 0.0

	for i in MAX_SPARKS:
		spark_life[i] = 0.0
	for i in MAX_STEAM:
		steam_life[i] = 0.0
	for i in MAX_SCRAPE_SPARKS:
		scrape_life[i] = 0.0

	for b in bolts:
		b.accumulated_rad = 0.0
		b.angle = 0.0
		b.initial_dist = 0.0
		b.is_loose = false
		b.is_popped = false
		b.current_pos = b.base_pos
		b.fall_velocity = Vector2.ZERO
		b.fall_rotation_speed = 0.0


func get_active_bolt() -> BoltData:
	return active_bolt


func get_bolts() -> Array[BoltData]:
	return bolts


func get_remaining_bolts_count() -> int:
	var count: int = 0
	for b in bolts:
		if not b.is_loose:
			count += 1
	return count


func is_hatch_unlocked() -> bool:
	return get_remaining_bolts_count() == 0


func update_bolts(delta: float, tool_tip_pos: Vector2, is_screwdriver_held: bool, mid_shift: Vector2, mouse_pos: Vector2 = Vector2.INF) -> void:
	if delta <= 0.0:
		return

	var eff_mouse_pos: Vector2 = tool_tip_pos if mouse_pos == Vector2.INF else mouse_pos
	anim_time += delta

	# Check unlatch trigger if all bolts are loose
	if is_hatch_unlocked() and not is_unlatched:
		_trigger_pneumatic_unlatch()

	# Update sparks (screwdriver slip)
	for i in MAX_SPARKS:
		if spark_life[i] > 0.0:
			spark_life[i] -= delta
			spark_pos[i] += spark_vel[i] * delta
			spark_vel[i].y += 180.0 * delta

	# Update friction scrape sparks
	for i in MAX_SCRAPE_SPARKS:
		if scrape_life[i] > 0.0:
			scrape_life[i] -= delta
			scrape_pos[i] += scrape_vel[i] * delta
			scrape_vel[i].y += 320.0 * delta

	# Update steam particles
	for i in MAX_STEAM:
		if steam_life[i] > 0.0:
			steam_life[i] -= delta
			steam_pos[i] += steam_vel[i] * delta
			steam_vel[i] = steam_vel[i].lerp(Vector2.ZERO, delta * 3.2)
			steam_vel[i].y -= 42.0 * delta # Thermal buoyancy
			steam_size[i] += steam_growth[i] * delta

	# Residual wisps of steam while hatch is unlatched
	if steam_vent_timer > 0.0 and not is_hatch_removed:
		steam_vent_timer -= delta
		if randf() < delta * 16.0:
			_spawn_steam_wisp()

	# Update pneumatic latch recoil spring
	if latch_recoil > 0.001 or absf(latch_recoil_vel) > 0.001:
		var recoil_force: float = -latch_recoil * 35.0 - latch_recoil_vel * 8.0
		latch_recoil_vel += recoil_force * delta
		latch_recoil += latch_recoil_vel * delta
		latch_recoil = clampf(latch_recoil, 0.0, 1.2)

	# Update pneumatic lift spring (hatch pops upward ~12px)
	var target_lift: float = 1.0 if (is_unlatched and not is_hatch_removed) else 0.0
	var lift_force: float = (target_lift - hatch_lift) * 110.0 - hatch_lift_vel * 14.0
	hatch_lift_vel += lift_force * delta
	hatch_lift += hatch_lift_vel * delta
	hatch_lift = clampf(hatch_lift, 0.0, 1.3)

	# Update falling popped bolts
	for b in bolts:
		if b.is_popped and b.is_loose:
			b.fall_velocity.y += 650.0 * delta
			b.current_pos += b.fall_velocity * delta
			b.angle += b.fall_rotation_speed * delta

	# Update hatch slide and drop animation
	if is_hatch_removed:
		if hatch_velocity.length_squared() > 1.0:
			hatch_velocity.y += 720.0 * delta
			hatch_offset += hatch_velocity * delta
			hatch_rotation += hatch_rot_vel * delta
	elif not is_dragging_hatch:
		# Return to guide runners if released before detachment threshold
		if hatch_offset.length_squared() > 0.1:
			hatch_offset = hatch_offset.lerp(Vector2.ZERO, delta * 12.0)
			hatch_rotation = lerpf(hatch_rotation, 0.0, delta * 14.0)

	if not is_active:
		return

	# Handle screwdriver interaction on active/target bolts
	if is_screwdriver_held:
		if active_bolt == null:
			for b in bolts:
				if not b.is_loose:
					var b_pos: Vector2 = b.base_pos + mid_shift
					if tool_tip_pos.distance_to(b_pos) <= snap_radius:
						active_bolt = b
						var rel: Vector2 = eff_mouse_pos - b_pos
						active_bolt.initial_dist = rel.length()
						active_bolt.last_mouse_angle = atan2(rel.y, rel.x)
						break
		else:
			var b_pos: Vector2 = active_bolt.base_pos + mid_shift
			var dist: float = eff_mouse_pos.distance_to(b_pos)

			# Slip check
			var max_allowed_dist: float = maxf(slip_radius, active_bolt.initial_dist + slip_radius)
			if dist > max_allowed_dist:
				_trigger_slip(eff_mouse_pos)
				return

			var rel: Vector2 = eff_mouse_pos - b_pos
			var current_angle: float = atan2(rel.y, rel.x)
			var angle_diff: float = wrapf(current_angle - active_bolt.last_mouse_angle, -PI, PI)
			active_bolt.last_mouse_angle = current_angle

			# Counter-clockwise rotation loosens bolt (angle_diff < 0)
			if angle_diff < 0.0:
				var rad_delta: float = -angle_diff
				var angular_speed: float = rad_delta / delta
				if angular_speed > max_angular_accel * 0.01:
					_trigger_slip(eff_mouse_pos)
					return

				active_bolt.accumulated_rad += rad_delta
				active_bolt.angle -= rad_delta

				# Ratchet tick every 45 degrees
				if active_bolt.accumulated_rad - active_bolt.last_tick_rad >= (PI * 0.25):
					active_bolt.last_tick_rad = active_bolt.accumulated_rad
					emit_signal("ratchet_tick")

				# Check bolt fully unscrewed
				var total_turns: float = active_bolt.accumulated_rad / TAU
				if total_turns >= active_bolt.turns_required and not active_bolt.is_loose:
					_pop_bolt(active_bolt)
					active_bolt = null
	else:
		active_bolt = null


func _trigger_slip(pos: Vector2) -> void:
	active_bolt = null
	emit_signal("tool_slipped", slip_penalty, slip_shake)
	emit_signal("feedback_text_requested", "СРЫВ ШЛИЦА ОТВЁРТКИ! +%d%% НЕСТАБИЛЬНОСТИ" % int(slip_penalty), true)

	for i in 8:
		_spawn_spark(pos, Vector2(randf_range(-140.0, 140.0), randf_range(-120.0, 40.0)), 0.35)


func _pop_bolt(bolt: BoltData) -> void:
	bolt.is_loose = true
	bolt.is_popped = true
	bolt.fall_velocity = Vector2(randf_range(-60.0, 60.0), randf_range(-180.0, -90.0))
	bolt.fall_rotation_speed = randf_range(-12.0, 12.0)

	var remaining: int = get_remaining_bolts_count()
	emit_signal("bolt_loosened", bolt.id, remaining)

	if remaining == 0:
		_trigger_pneumatic_unlatch()


func _trigger_pneumatic_unlatch() -> void:
	if is_unlatched:
		return
	is_unlatched = true

	# Spring impulses for pneumatic recoil and vertical pop-up
	latch_recoil = 1.0
	latch_recoil_vel = 12.0
	hatch_lift_vel = 8.0
	steam_vent_timer = 2.4

	# High-pressure steam plumes escaping from perimeter seals
	_burst_unlatch_steam()

	# Audio & haptic shockwave
	_play_sfx(_stream_unlatch, 1.0)
	emit_signal("hatch_unlatched")
	emit_signal("screen_shake_requested", 5.0)
	emit_signal("feedback_text_requested", "ПНЕВМОЗАМКИ ОТЩЕЛКНУЛИСЬ! Захватите люк и сдвиньте в сторону.", false)


func _burst_unlatch_steam() -> void:
	var cx: float = hatch_rect.position.x
	var cy: float = hatch_rect.position.y
	var cw: float = hatch_rect.size.x
	var ch: float = hatch_rect.size.y

	# Left seal
	for i in 14:
		var p := Vector2(cx + 2.0, cy + randf() * ch)
		var v := Vector2(randf_range(-260.0, -130.0), randf_range(-50.0, 50.0))
		_spawn_steam(p, v, randf_range(0.45, 0.75), randf_range(4.0, 7.0), randf_range(28.0, 48.0))

	# Right seal
	for i in 14:
		var p := Vector2(cx + cw - 2.0, cy + randf() * ch)
		var v := Vector2(randf_range(130.0, 260.0), randf_range(-50.0, 50.0))
		_spawn_steam(p, v, randf_range(0.45, 0.75), randf_range(4.0, 7.0), randf_range(28.0, 48.0))

	# Top seal
	for i in 10:
		var p := Vector2(cx + randf() * cw, cy + 2.0)
		var v := Vector2(randf_range(-80.0, 80.0), randf_range(-240.0, -120.0))
		_spawn_steam(p, v, randf_range(0.40, 0.65), randf_range(4.0, 6.0), randf_range(24.0, 42.0))

	# Bottom seal
	for i in 10:
		var p := Vector2(cx + randf() * cw, cy + ch - 2.0)
		var v := Vector2(randf_range(-80.0, 80.0), randf_range(110.0, 210.0))
		_spawn_steam(p, v, randf_range(0.40, 0.65), randf_range(4.0, 6.0), randf_range(24.0, 42.0))


func _spawn_steam_wisp() -> void:
	var cx: float = hatch_rect.position.x
	var cy: float = hatch_rect.position.y
	var cw: float = hatch_rect.size.x
	var ch: float = hatch_rect.size.y

	var edge: int = randi() % 4
	var p: Vector2 = Vector2.ZERO
	var v: Vector2 = Vector2.ZERO
	match edge:
		0: # left
			p = Vector2(cx + 4.0, cy + randf() * ch)
			v = Vector2(randf_range(-90.0, -40.0), randf_range(-40.0, 20.0))
		1: # right
			p = Vector2(cx + cw - 4.0, cy + randf() * ch)
			v = Vector2(randf_range(40.0, 90.0), randf_range(-40.0, 20.0))
		2: # top
			p = Vector2(cx + randf() * cw, cy + 4.0)
			v = Vector2(randf_range(-40.0, 40.0), randf_range(-110.0, -50.0))
		3: # bottom
			p = Vector2(cx + randf() * cw, cy + ch - 4.0)
			v = Vector2(randf_range(-40.0, 40.0), randf_range(30.0, 80.0))

	_spawn_steam(p, v, randf_range(0.35, 0.60), randf_range(3.0, 5.0), randf_range(20.0, 36.0))


func _spawn_steam(pos: Vector2, vel: Vector2, life: float, init_size: float, growth: float) -> void:
	for i in MAX_STEAM:
		if steam_life[i] <= 0.0:
			steam_pos[i] = pos
			steam_vel[i] = vel
			steam_life[i] = life
			steam_max_life[i] = life
			steam_size[i] = init_size
			steam_growth[i] = growth
			return


func _spawn_spark(pos: Vector2, vel: Vector2, life: float) -> void:
	for i in MAX_SPARKS:
		if spark_life[i] <= 0.0:
			spark_pos[i] = pos
			spark_vel[i] = vel
			spark_life[i] = life
			return


func _spawn_scrape_spark(pos: Vector2, vel: Vector2, life: float) -> void:
	for i in MAX_SCRAPE_SPARKS:
		if scrape_life[i] <= 0.0:
			scrape_pos[i] = pos
			scrape_vel[i] = vel
			scrape_life[i] = life
			return


func handle_hatch_input(event: InputEvent, mouse_pos: Vector2, mid_shift: Vector2) -> bool:
	if not is_active or not is_hatch_unlocked() or is_hatch_removed:
		return false

	var lift_px: float = hatch_lift * 12.0
	var current_hatch_rect: Rect2 = Rect2(hatch_rect.position + mid_shift + hatch_offset - Vector2(0.0, lift_px), hatch_rect.size)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var grab_rect: Rect2 = current_hatch_rect.grow(8.0)
			if grab_rect.has_point(mouse_pos):
				is_dragging_hatch = true
				hatch_drag_start = mouse_pos - hatch_offset
				prev_drag_mouse_pos = mouse_pos
				return true
		elif is_dragging_hatch and not event.pressed:
			is_dragging_hatch = false
			# Check detachment threshold (dragged far enough or flapped off runners)
			if hatch_offset.length() > 40.0:
				_detach_hatch()
			else:
				# Snaps back with solid clunk
				_play_sfx(_stream_scrape, 1.4)
			return true

	if event is InputEventMouseMotion and is_dragging_hatch:
		var target_offset: Vector2 = mouse_pos - hatch_drag_start
		# Guide runner constraints: freely slides right, elastic resistance pushing left
		if target_offset.x < -10.0:
			target_offset.x = -10.0 + (target_offset.x + 10.0) * 0.15
		# Guide runners constrain vertical play
		target_offset.y = clampf(target_offset.y, -16.0, 16.0)

		# Physical inertia
		var prev_off := hatch_offset
		hatch_offset = target_offset
		var dt := maxf(get_process_delta_time() if is_inside_tree() else 0.016, 0.001)
		hatch_velocity = (hatch_offset - prev_off) / dt

		# Dynamic angular tilt
		var target_rot: float = clampf(hatch_velocity.x * 0.0003, -0.07, 0.07)
		hatch_rotation = lerpf(hatch_rotation, target_rot, 0.35)

		# Metallic screech and friction sparks on physical dragging
		var drag_delta: float = (mouse_pos - prev_drag_mouse_pos).length()
		prev_drag_mouse_pos = mouse_pos

		if drag_delta > 1.5:
			scrape_accum_dist += drag_delta
			if scrape_accum_dist >= 14.0:
				scrape_accum_dist = 0.0
				var speed: float = hatch_velocity.length()
				var intensity: float = clampf(speed / 350.0, 0.35, 1.25)
				_trigger_metallic_scrape(intensity, current_hatch_rect)

		return true

	return false


func _trigger_metallic_scrape(intensity: float, h_rect: Rect2) -> void:
	emit_signal("hatch_scraped", intensity)
	emit_signal("screen_shake_requested", intensity * 1.5)
	_play_sfx(_stream_scrape, randf_range(0.92, 1.15) + (intensity - 0.5) * 0.35)

	# Spawn hot friction sparks from contact points along guide tracks
	var num_sparks: int = clampi(int(intensity * 3.0), 2, 5)
	for s in num_sparks:
		var is_top: bool = (s % 2 == 0)
		var y: float = h_rect.position.y if is_top else h_rect.end.y
		var x: float = h_rect.position.x + randf() * minf(h_rect.size.x, 70.0)
		var sp_pos := Vector2(x, y)
		var sp_vel := Vector2(randf_range(-150.0, -40.0), randf_range(-80.0, 80.0) if is_top else randf_range(-30.0, 130.0))
		_spawn_scrape_spark(sp_pos, sp_vel, randf_range(0.18, 0.35))


func _detach_hatch() -> void:
	is_hatch_removed = true
	hatch_velocity = Vector2(maxf(hatch_velocity.x, 220.0), 280.0)
	hatch_rot_vel = randf_range(2.0, 4.0)

	_play_sfx(_stream_unlatch, 0.8)
	emit_signal("hatch_removed")
	emit_signal("screen_shake_requested", 5.5)
	emit_signal("feedback_text_requested", "Бронелюк демонтирован! Силовой отсек полностью доступен.", false)


func render(canvas: CanvasItem, mid_shift: Vector2) -> void:
	if not is_active:
		return

	_ensure_audio_player(canvas)
	var current_anim_time: float = anim_time if anim_time > 0.0 else (float(Time.get_ticks_msec()) * 0.001)

	var cavity_rect: Rect2 = Rect2(hatch_rect.position + mid_shift, hatch_rect.size)
	var cx: float = cavity_rect.position.x
	var cy: float = cavity_rect.position.y
	var cw: float = cavity_rect.size.x
	var ch: float = cavity_rect.size.y

	# 1. Guide runners on chassis (upper and lower rails)
	var rail_top_y: float = cy - 4.0
	var rail_bot_y: float = cy + ch + 4.0
	var rail_len: float = cw + 150.0
	canvas.draw_line(Vector2(cx - 12.0, rail_top_y), Vector2(cx - 12.0 + rail_len, rail_top_y), Color(0.12, 0.15, 0.18), 3.0)
	canvas.draw_line(Vector2(cx - 12.0, rail_top_y - 1.0), Vector2(cx - 12.0 + rail_len, rail_top_y - 1.0), Color(0.28, 0.35, 0.42, 0.6), 1.0)
	canvas.draw_line(Vector2(cx - 12.0, rail_bot_y), Vector2(cx - 12.0 + rail_len, rail_bot_y), Color(0.12, 0.15, 0.18), 3.0)
	canvas.draw_line(Vector2(cx - 12.0, rail_bot_y + 1.0), Vector2(cx - 12.0 + rail_len, rail_bot_y + 1.0), Color(0.28, 0.35, 0.42, 0.6), 1.0)

	# Metallic scratch marks along exposed guide runners
	if hatch_offset.x > 8.0:
		var scratch_end_x: float = cx + minf(hatch_offset.x, cw + 90.0)
		for scr in 6:
			var scr_x: float = cx + float(scr) * 20.0 + fmod(float(scr) * 11.0, 15.0)
			if scr_x < scratch_end_x:
				canvas.draw_line(Vector2(scr_x, rail_bot_y - 0.5), Vector2(scr_x + 14.0, rail_bot_y - 0.5), Color(0.70, 0.75, 0.82, 0.65), 1.0)
				canvas.draw_line(Vector2(scr_x + 4.0, rail_top_y + 0.5), Vector2(scr_x + 16.0, rail_top_y + 0.5), Color(0.70, 0.75, 0.82, 0.65), 1.0)

	# 2. Recessed Power Bay (Силовой отсек)
	canvas.draw_rect(cavity_rect, Color(0.05, 0.06, 0.08, 0.98))
	canvas.draw_rect(cavity_rect, Color(0.20, 0.25, 0.30, 0.7), false, 1.5)

	# Inner pocket drop shadows
	canvas.draw_line(Vector2(cx, cy + 1.0), Vector2(cx + cw, cy + 1.0), Color(0.01, 0.02, 0.03, 0.9), 3.0)
	canvas.draw_line(Vector2(cx + 1.0, cy), Vector2(cx + 1.0, cy + ch), Color(0.01, 0.02, 0.03, 0.9), 3.0)

	# Heat-sink cooling ribs
	for rib in 10:
		var rx: float = cx + 16.0 + float(rib) * ((cw - 32.0) / 10.0)
		canvas.draw_line(Vector2(rx, cy + 10.0), Vector2(rx, cy + ch - 10.0), Color(0.09, 0.11, 0.14), 2.0)

	# High-voltage copper power busbars
	var bus_top_y: float = cy + 16.0
	var bus_bot_y: float = cy + ch - 16.0
	var bus_x1: float = cx + 36.0
	var bus_x2: float = cx + cw - 36.0
	canvas.draw_line(Vector2(bus_x1, bus_top_y), Vector2(bus_x2, bus_top_y), COLOR_BUSBAR_COPPER, 3.5)
	canvas.draw_line(Vector2(bus_x1, bus_top_y - 1.0), Vector2(bus_x2, bus_top_y - 1.0), COLOR_BUSBAR_SPECULAR, 1.0)
	canvas.draw_line(Vector2(bus_x1, bus_bot_y), Vector2(bus_x2, bus_bot_y), COLOR_BUSBAR_COPPER, 3.5)
	canvas.draw_line(Vector2(bus_x1, bus_bot_y - 1.0), Vector2(bus_x2, bus_bot_y - 1.0), COLOR_BUSBAR_SPECULAR, 1.0)

	# Dual heavy cylindrical capacitors
	var cap_w: float = 28.0
	var cap_h: float = ch - 26.0
	var cap_y: float = cy + 13.0
	_render_capacitor(canvas, Rect2(cx + 10.0, cap_y, cap_w, cap_h))
	_render_capacitor(canvas, Rect2(cx + cw - cap_w - 10.0, cap_y, cap_w, cap_h))

	# Central transformer / contactor module
	var xf_w: float = 38.0
	var xf_h: float = ch - 36.0
	var xf_rect := Rect2(cx + (cw - xf_w) * 0.5, cy + 18.0, xf_w, xf_h)
	canvas.draw_rect(xf_rect, Color(0.12, 0.14, 0.18))
	canvas.draw_rect(xf_rect, Color(0.28, 0.35, 0.42, 0.8), false, 1.0)
	for w in 5:
		var wy: float = xf_rect.position.y + 6.0 + float(w) * ((xf_h - 12.0) / 4.0)
		canvas.draw_line(Vector2(xf_rect.position.x + 2.0, wy), Vector2(xf_rect.end.x - 2.0, wy), Color(0.80, 0.48, 0.22), 2.0)

	# Multi-color diagnostic LED array
	_render_diagnostic_leds(canvas, cx, cy, cw, ch, current_anim_time)

	# 3. 4 Corner mechanical locks / latches
	_render_corner_latches(canvas, cx, cy, cw, ch)

	# 4. Raised tactical armor hatch plate
	if not is_hatch_removed or hatch_offset.length() < 350.0:
		var lift_px: float = hatch_lift * 12.0
		var h_pos: Vector2 = cavity_rect.position + hatch_offset - Vector2(0.0, lift_px)
		var h_rect := Rect2(h_pos, cavity_rect.size)

		# 3D Drop shadow expanding with lift height
		var sh_dist := Vector2(4.0 + hatch_lift * 8.0, 6.0 + hatch_lift * 14.0)
		canvas.draw_rect(Rect2(h_rect.position + sh_dist, h_rect.size), Color(0.01, 0.02, 0.03, 0.35))
		canvas.draw_rect(Rect2(h_rect.position + sh_dist * 0.7, h_rect.size), COLOR_HATCH_SHADOW)

		# Thick armor plate side bevels when lifted
		if lift_px > 1.0:
			canvas.draw_rect(Rect2(h_rect.position.x, h_rect.end.y, h_rect.size.x, lift_px), COLOR_HATCH_BEVEL_SIDE)
			canvas.draw_line(Vector2(h_rect.position.x, h_rect.end.y + lift_px), Vector2(h_rect.end.x, h_rect.end.y + lift_px), Color(0.25, 0.30, 0.36), 1.0)
			canvas.draw_rect(Rect2(h_rect.end.x, h_rect.position.y, lift_px * 0.6, h_rect.size.y + lift_px), COLOR_HATCH_BEVEL_SIDE)
			canvas.draw_line(Vector2(h_rect.end.x + lift_px * 0.6, h_rect.position.y), Vector2(h_rect.end.x + lift_px * 0.6, h_rect.end.y + lift_px), Color(0.25, 0.30, 0.36), 1.0)

		# Tactical armor plate body
		canvas.draw_rect(h_rect, COLOR_HATCH_PLATE)

		# Perimeter specular rim
		canvas.draw_line(h_rect.position + Vector2(1, 1), Vector2(h_rect.end.x - 1, h_rect.position.y + 1), COLOR_HATCH_SPECULAR, 1.5)
		canvas.draw_line(h_rect.position + Vector2(1, 1), Vector2(h_rect.position.x + 1, h_rect.end.y - 1), COLOR_HATCH_SPECULAR, 1.5)
		canvas.draw_line(Vector2(h_rect.end.x - 1, h_rect.position.y + 1), Vector2(h_rect.end.x - 1, h_rect.end.y - 1), COLOR_HATCH_SHADOW_RIM, 1.5)
		canvas.draw_line(Vector2(h_rect.position.x + 1, h_rect.end.y - 1), Vector2(h_rect.end.x - 1, h_rect.end.y - 1), COLOR_HATCH_SHADOW_RIM, 1.5)

		# Technical seam across hatch
		var mid_y: float = h_rect.position.y + h_rect.size.y * 0.5
		canvas.draw_line(Vector2(h_rect.position.x + 16.0, mid_y), Vector2(h_rect.end.x - 16.0, mid_y), Color(0.09, 0.11, 0.13, 0.9), 1.0)
		canvas.draw_line(Vector2(h_rect.position.x + 16.0, mid_y + 1.0), Vector2(h_rect.end.x - 16.0, mid_y + 1.0), Color(0.28, 0.33, 0.39, 0.5), 1.0)

		# Tactical grab handles on left and right
		_render_hatch_handles(canvas, h_rect, mid_y, current_anim_time)

		# Animated rightward sliding affordance chevrons
		if is_hatch_unlocked() and not is_hatch_removed:
			_render_drag_chevrons(canvas, h_rect, current_anim_time)

	# 5. Bolts
	for b in bolts:
		var b_pos: Vector2 = b.current_pos + mid_shift
		if not b.is_popped:
			b_pos += hatch_offset - Vector2(0.0, hatch_lift * 12.0)

		var turn_ratio: float = clampf(b.accumulated_rad / (b.turns_required * TAU), 0.0, 1.0)
		var bolt_lift_px: float = turn_ratio * 5.0

		canvas.draw_circle(b_pos + Vector2(2.0, 3.0 + bolt_lift_px * 0.5), b.radius, Color(0.04, 0.05, 0.06, 0.65))

		var rim_col: Color = Color(0.95, 0.98, 1.0) if (active_bolt == b) else COLOR_BOLT_RIM
		var head_center: Vector2 = b_pos - Vector2(0.0, bolt_lift_px)
		canvas.draw_circle(head_center, b.radius, rim_col)
		canvas.draw_circle(head_center, b.radius - 2.5, COLOR_BOLT_CORE)

		var rot: float = b.angle
		var slot_len: float = b.radius - 4.5
		var slot_dir1: Vector2 = Vector2(cos(rot), sin(rot)) * slot_len
		var slot_dir2: Vector2 = Vector2(-sin(rot), cos(rot)) * slot_len
		canvas.draw_line(head_center - slot_dir1, head_center + slot_dir1, COLOR_BOLT_SLOT, 2.5)
		canvas.draw_line(head_center - slot_dir2, head_center + slot_dir2, COLOR_BOLT_SLOT, 2.0)
		canvas.draw_circle(head_center, 1.5, Color(0.06, 0.07, 0.09))

	# 6. High-pressure steam particles
	for i in MAX_STEAM:
		if steam_life[i] > 0.0:
			var t_prog: float = 1.0 - (steam_life[i] / steam_max_life[i])
			var a: float = (1.0 - t_prog) * (1.0 - t_prog * 0.25) * 0.55
			var r: float = steam_size[i]
			var sp_col := Color(COLOR_STEAM_MIST.r, COLOR_STEAM_MIST.g, COLOR_STEAM_MIST.b, a * 0.45)
			var core_col := Color(COLOR_STEAM_CORE.r, COLOR_STEAM_CORE.g, COLOR_STEAM_CORE.b, a * 0.85)
			canvas.draw_circle(steam_pos[i] + mid_shift, r, sp_col)
			canvas.draw_circle(steam_pos[i] + mid_shift, r * 0.5, core_col)

	# 7. Friction scrape sparks
	for i in MAX_SCRAPE_SPARKS:
		if scrape_life[i] > 0.0:
			canvas.draw_circle(scrape_pos[i] + mid_shift, 2.2, Color(1.0, 0.88, 0.45))
			canvas.draw_circle(scrape_pos[i] + mid_shift, 1.2, Color(1.0, 1.0, 0.90))

	# 8. Screwdriver slip sparks
	for i in MAX_SPARKS:
		if spark_life[i] > 0.0:
			canvas.draw_circle(spark_pos[i], 2.0, COLOR_SPARK)


func _render_capacitor(canvas: CanvasItem, rect: Rect2) -> void:
	# Outer cylindrical casing
	canvas.draw_rect(rect, Color(0.12, 0.14, 0.18))
	canvas.draw_rect(rect, Color(0.28, 0.35, 0.42, 0.8), false, 1.0)

	# Specular vertical reflection
	var spec_x: float = rect.position.x + rect.size.x * 0.35
	canvas.draw_line(Vector2(spec_x, rect.position.y + 2.0), Vector2(spec_x, rect.end.y - 2.0), Color(0.45, 0.55, 0.65, 0.5), 1.5)

	# Hazard warning band across center
	var band_h: float = 14.0
	var band_y: float = rect.position.y + (rect.size.y - band_h) * 0.5
	var band_rect := Rect2(rect.position.x + 1.0, band_y, rect.size.x - 2.0, band_h)
	canvas.draw_rect(band_rect, COLOR_HAZARD_YELLOW)
	for s in 3:
		var sx: float = band_rect.position.x + 3.0 + float(s) * 8.0
		canvas.draw_line(Vector2(sx, band_rect.end.y), Vector2(sx + 5.0, band_rect.position.y), COLOR_HAZARD_DARK, 2.0)

	# Terminal contact lugs
	canvas.draw_circle(Vector2(rect.get_center().x, rect.position.y + 3.0), 2.5, Color(0.70, 0.75, 0.80))
	canvas.draw_circle(Vector2(rect.get_center().x, rect.end.y - 3.0), 2.5, Color(0.70, 0.75, 0.80))


func _render_diagnostic_leds(canvas: CanvasItem, cx: float, cy: float, cw: float, ch: float, t: float) -> void:
	# LED 1: PWR_MAIN (Amber / Gold) - Slow breathing pulse
	var pulse_amber: float = 0.55 + 0.45 * sin(t * 3.2)
	var led1_pos := Vector2(cx + cw * 0.5 - 12.0, cy + 9.0)
	canvas.draw_circle(led1_pos, 16.0, Color(0.98, 0.72, 0.12, 0.22 * pulse_amber))
	canvas.draw_circle(led1_pos, 5.0, Color(1.0, 0.85, 0.25, 0.65 * pulse_amber))
	canvas.draw_circle(led1_pos, 2.5, Color(1.0, 0.95, 0.70))

	# LED 2: CAP_SYNC (Emerald Green) - Double-strobe telemetry flash
	var cycle_sync: float = fmod(t * 1.5, 1.0)
	var is_strobe: bool = (cycle_sync < 0.08) or (cycle_sync > 0.15 and cycle_sync < 0.23)
	var sync_a: float = 1.0 if is_strobe else 0.18
	var led2_pos := Vector2(cx + cw * 0.5 + 12.0, cy + 9.0)
	canvas.draw_circle(led2_pos, 18.0, Color(0.20, 0.95, 0.45, 0.30 * sync_a))
	canvas.draw_circle(led2_pos, 5.5, Color(0.35, 1.0, 0.60, 0.70 * sync_a))
	canvas.draw_circle(led2_pos, 2.5, Color(0.85, 1.0, 0.90) if is_strobe else Color(0.10, 0.40, 0.20))

	# LED 3: 3-step energy ladder
	var ladder_step: int = int(fmod(t * 4.5, 3.0))
	for s in 3:
		var bar_rect := Rect2(cx + 42.0, cy + 26.0 + float(s) * 9.0, 6.0, 4.0)
		var is_active_bar: bool = (s == ladder_step)
		var bar_col: Color = Color(0.98, 0.80, 0.20) if is_active_bar else Color(0.22, 0.28, 0.34, 0.5)
		if is_active_bar:
			canvas.draw_rect(bar_rect.grow(3.0), Color(0.98, 0.80, 0.20, 0.25))
		canvas.draw_rect(bar_rect, bar_col)

	# LED 4: VENT_WARN (Crimson Red) - Alert strobe while steam is venting
	var is_venting: bool = (steam_vent_timer > 0.0)
	var red_blink: float = (1.0 if sin(t * 32.0) > 0.0 else 0.1) if is_venting else (0.5 + 0.5 * sin(t * 2.0))
	var led4_pos := Vector2(cx + cw - 18.0, cy + 9.0)
	canvas.draw_circle(led4_pos, 16.0, Color(0.95, 0.18, 0.12, 0.35 * red_blink))
	canvas.draw_circle(led4_pos, 4.5, Color(1.0, 0.30, 0.25, 0.75 * red_blink))
	canvas.draw_circle(led4_pos, 2.2, Color(1.0, 0.90, 0.90) if red_blink > 0.5 else Color(0.40, 0.05, 0.05))

	# LED 5: SYS_TELEMETRY (Electric Cyan) - Micro-pulse
	var cyan_pulse: float = 0.70 + 0.30 * sin(t * 9.0)
	var led5_pos := Vector2(cx + 18.0, cy + ch - 9.0)
	canvas.draw_circle(led5_pos, 12.0, Color(0.30, 0.88, 0.98, 0.22 * cyan_pulse))
	canvas.draw_circle(led5_pos, 2.5, Color(0.70, 0.95, 1.0))


func _render_corner_latches(canvas: CanvasItem, cx: float, cy: float, cw: float, ch: float) -> void:
	var latch_size: float = 14.0
	var corners: PackedVector2Array = [
		Vector2(cx, cy),
		Vector2(cx + cw, cy),
		Vector2(cx, cy + ch),
		Vector2(cx + cw, cy + ch)
	]

	var dog_retract: float = 0.0
	if is_hatch_unlocked():
		dog_retract = (1.0 - latch_recoil * 0.4) * 10.0

	for i in 4:
		var cp: Vector2 = corners[i]
		var h_box := Rect2(cp.x - latch_size * 0.5, cp.y - latch_size * 0.5, latch_size, latch_size)

		canvas.draw_rect(h_box, COLOR_LATCH_BODY)
		canvas.draw_rect(h_box, Color(0.45, 0.52, 0.60, 0.8), false, 1.0)
		canvas.draw_circle(h_box.get_center(), 2.0, Color(0.60, 0.68, 0.75))

		var dir_in := Vector2(1.0 if cp.x == cx else -1.0, 1.0 if cp.y == cy else -1.0).normalized()
		var dog_base := cp + dir_in * (8.0 - dog_retract)
		var dog_tip := dog_base + dir_in * 7.0
		canvas.draw_line(dog_base, dog_tip, COLOR_LATCH_DOG, 3.5)

		var led_pos := cp + dir_in * 3.0
		if is_hatch_unlocked():
			canvas.draw_circle(led_pos, 2.5, Color(0.25, 0.96, 0.52, 0.9))
		else:
			canvas.draw_circle(led_pos, 2.0, Color(0.95, 0.20, 0.15, 0.9))


func _render_hatch_handles(canvas: CanvasItem, h_rect: Rect2, mid_y: float, t: float) -> void:
	var handle_w: float = 6.0
	var handle_h: float = 28.0
	var left_r := Rect2(h_rect.position.x + 4.0, mid_y - handle_h * 0.5, handle_w, handle_h)
	var right_r := Rect2(h_rect.end.x - handle_w - 4.0, mid_y - handle_h * 0.5, handle_w, handle_h)

	var blink: float = 0.5 + 0.5 * sin(t * 6.0)
	var handle_col := Color(0.30, 0.90, 0.55, 0.40 + 0.50 * blink) if is_hatch_unlocked() else Color(0.25, 0.30, 0.36)
	var border_col := Color(0.70, 1.0, 0.80, 0.55 + 0.35 * blink) if is_hatch_unlocked() else Color(0.40, 0.48, 0.56)

	canvas.draw_rect(left_r, handle_col)
	canvas.draw_rect(left_r, border_col, false, 1.0)
	canvas.draw_rect(right_r, handle_col)
	canvas.draw_rect(right_r, border_col, false, 1.0)

	# Knurling grip ridges on handles
	for g in 3:
		var gy: float = left_r.position.y + 6.0 + float(g) * 8.0
		canvas.draw_line(Vector2(left_r.position.x + 1.0, gy), Vector2(left_r.end.x - 1.0, gy), Color(0.08, 0.10, 0.12), 1.0)
		canvas.draw_line(Vector2(right_r.position.x + 1.0, gy), Vector2(right_r.end.x - 1.0, gy), Color(0.08, 0.10, 0.12), 1.0)


func _render_drag_chevrons(canvas: CanvasItem, h_rect: Rect2, t: float) -> void:
	var blink: float = 0.5 + 0.5 * sin(t * 6.0)
	var arrow_center: Vector2 = h_rect.position + h_rect.size * 0.5
	var chevron_col: Color = Color(0.35, 0.95, 0.65, 0.35 + 0.55 * blink)
	for a in 3:
		var cx_a: float = arrow_center.x - 22.0 + float(a) * 18.0
		var p_top: Vector2 = Vector2(cx_a - 6.0, arrow_center.y - 9.0)
		var p_mid: Vector2 = Vector2(cx_a + 4.0, arrow_center.y)
		var p_bot: Vector2 = Vector2(cx_a - 6.0, arrow_center.y + 9.0)
		canvas.draw_line(p_top, p_mid, chevron_col, 2.2)
		canvas.draw_line(p_mid, p_bot, chevron_col, 2.2)


func _init_procedural_audio() -> void:
	var sr: int = 44100

	# 1. Pneumatic unlatch: loud snap + air hiss burst (0.28 sec)
	var dur_unlatch: float = 0.28
	var n_unlatch: int = int(sr * dur_unlatch)
	var bytes_unlatch := PackedByteArray()
	bytes_unlatch.resize(n_unlatch * 2)
	for i in n_unlatch:
		var t: float = float(i) / float(sr)
		var snap: float = sin(t * TAU * 1350.0) * exp(-t * 85.0)
		var thump: float = sin(t * TAU * 95.0) * exp(-t * 22.0) * 0.8
		var hiss: float = (randf() * 2.0 - 1.0) * exp(-t * 14.0) * 0.75
		var sample: float = clampf(snap + thump + hiss, -1.0, 1.0)
		bytes_unlatch.encode_s16(i * 2, int(sample * 31000.0))
	_stream_unlatch = AudioStreamWAV.new()
	_stream_unlatch.format = AudioStreamWAV.FORMAT_16_BITS
	_stream_unlatch.mix_rate = sr
	_stream_unlatch.stereo = false
	_stream_unlatch.data = bytes_unlatch

	# 2. Metallic scrape: resonant ring + friction noise (0.18 sec)
	var dur_scrape: float = 0.18
	var n_scrape: int = int(sr * dur_scrape)
	var bytes_scrape := PackedByteArray()
	bytes_scrape.resize(n_scrape * 2)
	for i in n_scrape:
		var t: float = float(i) / float(sr)
		var f1: float = 820.0 + sin(t * 120.0) * 40.0
		var f2: float = 1480.0 + cos(t * 90.0) * 60.0
		var ring: float = (sin(t * TAU * f1) * 0.5 + sin(t * TAU * f2) * 0.4)
		var friction: float = (randf() * 2.0 - 1.0) * (0.5 + 0.5 * sin(t * TAU * 45.0)) * 0.6
		var env: float = sin(t / dur_scrape * PI)
		var sample: float = clampf((ring + friction) * env, -1.0, 1.0)
		bytes_scrape.encode_s16(i * 2, int(sample * 29000.0))
	_stream_scrape = AudioStreamWAV.new()
	_stream_scrape.format = AudioStreamWAV.FORMAT_16_BITS
	_stream_scrape.mix_rate = sr
	_stream_scrape.stereo = false
	_stream_scrape.data = bytes_scrape


func _ensure_audio_player(canvas: CanvasItem) -> void:
	if _audio_player != null:
		return
	if is_inside_tree():
		_audio_player = AudioStreamPlayer.new()
		_audio_player.name = "HatchSFXPlayer"
		add_child(_audio_player)
	elif canvas != null and canvas.is_inside_tree():
		_audio_player = AudioStreamPlayer.new()
		_audio_player.name = "HatchSFXPlayer"
		canvas.add_child(_audio_player)


func _play_sfx(stream: AudioStream, pitch: float = 1.0) -> void:
	if _audio_player != null and _audio_player.is_inside_tree():
		_audio_player.pitch_scale = pitch
		_audio_player.stream = stream
		_audio_player.play()
