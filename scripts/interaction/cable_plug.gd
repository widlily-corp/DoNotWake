class_name CablePlug
extends Node2D

## Tactile umbilical diagnostics cable and bayonet plug mechanic (Stage 3).
## Features dynamic multi-segment cable physics (Catenary curve),
## heavy plug dragging inertia, magnetic port snapping, keyway alignment,
## procedural electric micro-arcs (< 50px), neon light impulse wave surge,
## and robot cranial shudder & visor flash upon power delivery.
## Fully zero-GC per frame.

signal cable_locked()
signal plug_grabbed()
signal plug_released()
signal feedback_text_requested(text: String, is_alert: bool)
signal surge_started()
signal power_delivered()
signal electric_impulse(pos: Vector2, intensity: float)
signal head_shudder_triggered(intensity: float)

const CABLE_SEGMENTS: int = 18
const CABLE_OUTER_COLOR: Color = Color(0.12, 0.14, 0.17)
const CABLE_INNER_COLOR: Color = Color(0.32, 0.36, 0.42)
const PLUG_BRASS_COLOR: Color = Color(0.78, 0.62, 0.32)
const PLUG_DARK_COLOR: Color = Color(0.20, 0.22, 0.26)
const COLOR_SURGE: Color = Color(0.40, 0.95, 1.0)
const COLOR_ARC_BLUE: Color = Color(0.20, 0.60, 1.0)
const COLOR_ARC_WHITE: Color = Color(0.96, 0.98, 1.0)
const COLOR_VISOR_HOUSING: Color = Color(0.08, 0.10, 0.13, 0.95)
const COLOR_VISOR_BASE: Color = Color(0.12, 0.18, 0.24, 0.85)
const COLOR_VISOR_ACTIVE: Color = Color(0.25, 0.90, 1.0)
const COLOR_VISOR_CORE: Color = Color(0.95, 1.0, 1.0)

const KEYWAY_TARGET_DEG: float = 90.0
const ANGLE_TOLERANCE_DEG: float = 22.0
const ARC_TRIGGER_DISTANCE: float = 50.0
const MAX_ARCS: int = 4
const ARC_SEGMENTS: int = 6
const MAX_SPARKS: int = 24
const VISOR_WIDTH: float = 64.0
const VISOR_HEIGHT: float = 14.0

var anchor_pos: Vector2 = Vector2(980.0, 640.0)
var socket_pos: Vector2 = Vector2(640.0, 160.0)
var visor_pos: Vector2 = Vector2(640.0, 126.0)
var socket_radius: float = 26.0
var home_pos: Vector2 = Vector2(940.0, 600.0)

var keyway_target_deg: float = KEYWAY_TARGET_DEG
var angle_tolerance_deg: float = ANGLE_TOLERANCE_DEG
var lock_hold_time: float = 0.8

var current_plug_pos: Vector2 = Vector2(940.0, 600.0)
var target_plug_pos: Vector2 = Vector2(940.0, 600.0)
var plug_angle: float = 90.0 # degrees

var is_dragged: bool = false
var is_locked: bool = false
var is_near_socket: bool = false
var is_active: bool = true

# Power surge & delivery state
var surge_active: bool = false
var surge_progress: float = 0.0 # 0.0 at anchor -> 1.0 at socket
var surge_speed: float = 1.45 # Takes ~0.69s to traverse cable
var is_power_delivered: bool = false
var power_feed_timer: float = 0.0
var power_feed_duration: float = 1.35
var lock_completed_emitted: bool = false

# Cranial shudder & Visor animation parameters
var head_shudder_offset: Vector2 = Vector2.ZERO
var visor_intensity: float = 0.0
var visor_flare_alpha: float = 0.0
var optic_glitch_phase: float = 0.0

# Procedural electric micro-arcs state (< 50px)
var arc_intensity: float = 0.0
var arc_active_count: int = 0
var arc_crackle_timer: float = 0.0
var dist_to_socket: float = 999.0

# Pre-allocated arrays for Zero GC
var cable_points: PackedVector2Array = PackedVector2Array()
var arc_points: Array[PackedVector2Array] = []
var spark_pos: PackedVector2Array = PackedVector2Array()
var spark_vel: PackedVector2Array = PackedVector2Array()
var spark_life: PackedFloat32Array = PackedFloat32Array()
var spark_max_life: PackedFloat32Array = PackedFloat32Array()
var spark_color: PackedColorArray = PackedColorArray()

# Pre-allocated scratch buffers for zero-GC drawing
var _visor_poly: PackedVector2Array = PackedVector2Array()
var _cranial_arc_points: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	cable_points.resize(CABLE_SEGMENTS)
	for i in CABLE_SEGMENTS:
		cable_points[i] = home_pos

	arc_points.resize(MAX_ARCS)
	for a in MAX_ARCS:
		var pts := PackedVector2Array()
		pts.resize(ARC_SEGMENTS)
		for p in ARC_SEGMENTS:
			pts[p] = Vector2.ZERO
		arc_points[a] = pts

	spark_pos.resize(MAX_SPARKS)
	spark_vel.resize(MAX_SPARKS)
	spark_life.resize(MAX_SPARKS)
	spark_max_life.resize(MAX_SPARKS)
	spark_color.resize(MAX_SPARKS)
	for s in MAX_SPARKS:
		spark_pos[s] = Vector2.ZERO
		spark_vel[s] = Vector2.ZERO
		spark_life[s] = 0.0
		spark_max_life[s] = 0.0
		spark_color[s] = COLOR_ARC_BLUE

	_visor_poly.resize(6)
	for v in 6:
		_visor_poly[v] = Vector2.ZERO

	_cranial_arc_points.resize(ARC_SEGMENTS)
	for c in ARC_SEGMENTS:
		_cranial_arc_points[c] = Vector2.ZERO

	current_plug_pos = home_pos
	target_plug_pos = home_pos
	_recalculate_cable()


func configure(p_socket: Vector2, p_anchor: Vector2, p_home: Vector2, params: Dictionary = {}) -> void:
	socket_pos = p_socket
	anchor_pos = p_anchor
	home_pos = p_home
	socket_radius = float(params.get("socket_radius", 26.0))
	keyway_target_deg = float(params.get("keyway_angle_deg", params.get("keyway_target_deg", KEYWAY_TARGET_DEG)))
	angle_tolerance_deg = float(params.get("angle_tolerance_deg", ANGLE_TOLERANCE_DEG))
	lock_hold_time = float(params.get("lock_hold_time", 0.8))
	if params.has("visor_pos") and params["visor_pos"] is Array and params["visor_pos"].size() >= 2:
		var vp: Array = params["visor_pos"]
		visor_pos = Vector2(float(vp[0]), float(vp[1]))
	else:
		visor_pos = Vector2(socket_pos.x, socket_pos.y - 34.0)

	current_plug_pos = home_pos
	target_plug_pos = home_pos
	_recalculate_cable()


func reset() -> void:
	is_dragged = false
	is_locked = false
	is_near_socket = false
	surge_active = false
	surge_progress = 0.0
	is_power_delivered = false
	power_feed_timer = 0.0
	lock_completed_emitted = false
	head_shudder_offset = Vector2.ZERO
	visor_intensity = 0.0
	visor_flare_alpha = 0.0
	arc_intensity = 0.0
	arc_active_count = 0
	plug_angle = 90.0
	current_plug_pos = home_pos
	target_plug_pos = home_pos

	for s in MAX_SPARKS:
		spark_life[s] = 0.0

	_recalculate_cable()


func handle_input(event: InputEvent, mouse_pos: Vector2) -> bool:
	if not is_active or is_locked:
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mouse_pos.distance_to(current_plug_pos) <= 38.0:
					is_dragged = true
					emit_signal("plug_grabbed")
					return true
			elif is_dragged:
				is_dragged = false
				emit_signal("plug_released")
				# Check lock-in on release if aligned
				if is_near_socket:
					var angle_err: float = absf(wrapf(plug_angle - keyway_target_deg, -180.0, 180.0))
					if angle_err <= angle_tolerance_deg:
						_lock_into_socket()
					else:
						emit_signal("feedback_text_requested", "НЕ СОВПАЛ КЛЮЧ БАЙОНЕТА! Поверните штекер колесиком мыши на 12 часов.", true)
				return true

		# Mouse wheel rotates plug angle for keyway alignment
		if is_dragged and mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				plug_angle = wrapf(plug_angle + 12.0, 0.0, 360.0)
				return true
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				plug_angle = wrapf(plug_angle - 12.0, 0.0, 360.0)
				return true

	return false


func update_cable(delta: float, mouse_pos: Vector2, mid_shift: Vector2) -> void:
	if delta <= 0.0:
		return

	var effective_socket: Vector2 = socket_pos + mid_shift

	# 1. Update flying spark particles (Zero GC)
	for s in MAX_SPARKS:
		if spark_life[s] > 0.0:
			spark_life[s] -= delta
			spark_pos[s] += spark_vel[s] * delta
			spark_vel[s] = spark_vel[s].lerp(Vector2.ZERO, clampf(delta * 4.0, 0.0, 1.0))

	# 2. Electric micro-arcs generation (< 50px distance to temporal port)
	if is_active and not is_locked:
		dist_to_socket = current_plug_pos.distance_to(effective_socket)
		if dist_to_socket < ARC_TRIGGER_DISTANCE:
			arc_intensity = clampf(1.0 - (dist_to_socket / ARC_TRIGGER_DISTANCE), 0.0, 1.0)
			arc_crackle_timer += delta * (28.0 + arc_intensity * 36.0)

			# Number of simultaneous active arcs scales with proximity
			if dist_to_socket > 34.0:
				arc_active_count = 1
			elif dist_to_socket > 18.0:
				arc_active_count = 2
			else:
				arc_active_count = clampi(3 + int(fposmod(arc_crackle_timer, 2.0)), 3, MAX_ARCS)

			_update_micro_arcs(effective_socket)
		else:
			arc_intensity = 0.0
			arc_active_count = 0
	else:
		arc_intensity = 0.0
		arc_active_count = 0

	# 3. Power surge pulse wave & head shudder / visor sequence
	if surge_active:
		if not is_power_delivered:
			# Surge travels along the umbilical cable from anchor to robot head
			surge_progress += delta * surge_speed
			if surge_progress >= 1.0:
				surge_progress = 1.0
				is_power_delivered = true
				power_feed_timer = 0.0
				emit_signal("power_delivered")
				emit_signal("head_shudder_triggered", 1.0)
		else:
			# Power is surging directly into the robot's head!
			power_feed_timer += delta
			optic_glitch_phase += delta * 45.0

			# Cranial violent shudder: high-frequency mechanical tremor decaying smoothly
			if power_feed_timer < 0.85:
				var shudder_decay: float = exp(-power_feed_timer * 4.8) * (1.0 - (power_feed_timer / 0.85))
				var h_jolt: float = sin(power_feed_timer * 72.0) * 6.5 * shudder_decay
				var v_jolt: float = cos(power_feed_timer * 88.0) * 4.2 * shudder_decay
				head_shudder_offset = Vector2(h_jolt, v_jolt)
			else:
				head_shudder_offset = Vector2.ZERO

			# Visor ignition, overcharge blinding flash & optic boot scanlines
			if power_feed_timer < 0.18:
				# Stage A: Blinding power ignition flash
				var flash_norm: float = power_feed_timer / 0.18
				visor_intensity = 1.0
				visor_flare_alpha = 1.0 - flash_norm * 0.25
			elif power_feed_timer < 0.50:
				# Stage B: Cybernetic CRT boot scanline glitch & digital flicker
				var glitch_mod: float = 0.60 + 0.40 * sin(power_feed_timer * 92.0)
				visor_intensity = glitch_mod
				visor_flare_alpha = 0.65 * glitch_mod
			else:
				# Stage C: Settle into breathing active diagnostics glow
				var breath: float = 0.72 + 0.18 * sin((power_feed_timer - 0.50) * 7.5)
				visor_intensity = breath
				visor_flare_alpha = 0.22 * breath

			# Cranial high-voltage electric discharge arc between temple port and visor
			if power_feed_timer < 0.45:
				_update_cranial_arc(effective_socket + head_shudder_offset, visor_pos + mid_shift + head_shudder_offset)

			# Sequence climax: power delivery confirmation
			if power_feed_timer >= power_feed_duration and not lock_completed_emitted:
				lock_completed_emitted = true
				is_power_delivered = true
				emit_signal("power_delivered")
				emit_signal("feedback_text_requested", "ПУПОВИННЫЙ КАБЕЛЬ АКТИВЕН // ПИТАНИЕ СТАБИЛИЗИРОВАНО", false)

	# 4. Plug positioning
	if is_locked:
		current_plug_pos = effective_socket + head_shudder_offset
		_recalculate_cable()
		return

	if is_dragged:
		var dist_to_sock: float = mouse_pos.distance_to(effective_socket)
		if dist_to_sock <= socket_radius:
			is_near_socket = true
			target_plug_pos = effective_socket
			# Auto-align towards target keyway angle as player slides it in
			var dir: Vector2 = (effective_socket - mouse_pos).normalized()
			if dir.length_squared() > 0.01:
				plug_angle = lerpf(plug_angle, keyway_target_deg, delta * 6.0)
		else:
			is_near_socket = false
			target_plug_pos = mouse_pos

		# Heavy cable inertia
		current_plug_pos = current_plug_pos.lerp(target_plug_pos, clampf(delta * 12.0, 0.0, 1.0))
	else:
		is_near_socket = false
		if current_plug_pos.distance_to(home_pos) > 2.0:
			current_plug_pos = current_plug_pos.lerp(home_pos, clampf(delta * 10.0, 0.0, 1.0))

	_recalculate_cable()


func _lock_into_socket() -> void:
	is_locked = true
	is_dragged = false
	current_plug_pos = socket_pos
	plug_angle = keyway_target_deg
	surge_active = true
	surge_progress = 0.0
	is_power_delivered = false
	power_feed_timer = 0.0
	lock_completed_emitted = false
	emit_signal("cable_locked")
	emit_signal("surge_started")
	emit_signal("feedback_text_requested", "ЗАМОК ЗАЩЁЛКНУТ! ПОДАЧА ИМПУЛЬСА ПИТАНИЯ...", false)


func _update_micro_arcs(effective_socket: Vector2) -> void:
	var rad_ang: float = deg_to_rad(plug_angle)
	var forward: Vector2 = Vector2(cos(rad_ang), sin(rad_ang))
	var right: Vector2 = Vector2(-forward.y, forward.x)

	# 3 emitter contact points on the plug
	var plug_c0: Vector2 = current_plug_pos + right * 10.0 + forward * 14.0
	var plug_c1: Vector2 = current_plug_pos - right * 10.0 + forward * 14.0
	var plug_c2: Vector2 = current_plug_pos + forward * 20.0

	var denom: float = float(ARC_SEGMENTS - 1)

	for a in MAX_ARCS:
		if a >= arc_active_count:
			continue

		# Choose start contact on plug
		var start_p: Vector2 = plug_c0 if a == 0 else (plug_c1 if a == 1 else plug_c2)

		# Choose target pin on socket
		var pin_idx: int = (a * 2 + int(arc_crackle_timer * 1.5)) % 6
		var p_ang: float = float(pin_idx) * (TAU / 6.0)
		var end_p: Vector2 = effective_socket + Vector2(cos(p_ang), sin(p_ang)) * 12.0

		var chord: Vector2 = end_p - start_p
		var chord_len: float = chord.length()
		var norm: Vector2 = Vector2(-chord.y, chord.x).normalized() if chord_len > 0.001 else Vector2.UP

		var pts: PackedVector2Array = arc_points[a]
		pts[0] = start_p
		pts[ARC_SEGMENTS - 1] = end_p

		# Generate crackling jagged intermediate vertices
		for s in range(1, ARC_SEGMENTS - 1):
			var t: float = float(s) / denom
			var base: Vector2 = start_p.lerp(end_p, t)
			# Envelope peaks in the middle
			var env: float = 4.0 * t * (1.0 - t)
			var phase: float = arc_crackle_timer * 19.0 + float(a * 7 + s * 13)
			var jitter: float = (sin(phase) * 0.7 + cos(phase * 2.3) * 0.3) * (5.5 + arc_intensity * 4.0) * env
			pts[s] = base + norm * jitter

		# Occasionally spawn a spark from the contact
		if arc_intensity > 0.25 and fposmod(arc_crackle_timer + float(a), 1.0) < 0.25:
			_spawn_spark(start_p.lerp(end_p, randf_range(0.0, 0.4)), -chord.normalized() * randf_range(40.0, 120.0) + norm * randf_range(-60.0, 60.0))


func _update_cranial_arc(socket_p: Vector2, visor_p: Vector2) -> void:
	var chord: Vector2 = visor_p - socket_p
	var chord_len: float = chord.length()
	var norm: Vector2 = Vector2(-chord.y, chord.x).normalized() if chord_len > 0.001 else Vector2.UP
	var denom: float = float(ARC_SEGMENTS - 1)

	_cranial_arc_points[0] = socket_p
	_cranial_arc_points[ARC_SEGMENTS - 1] = visor_p

	for s in range(1, ARC_SEGMENTS - 1):
		var t: float = float(s) / denom
		var base: Vector2 = socket_p.lerp(visor_p, t)
		var env: float = 4.0 * t * (1.0 - t)
		var phase: float = power_feed_timer * 65.0 + float(s * 11)
		var jitter: float = (sin(phase) * 0.8 + cos(phase * 3.1) * 0.2) * 8.0 * env
		_cranial_arc_points[s] = base + norm * jitter


func _spawn_spark(pos: Vector2, vel: Vector2) -> void:
	for s in MAX_SPARKS:
		if spark_life[s] <= 0.0:
			spark_pos[s] = pos
			spark_vel[s] = vel
			spark_life[s] = randf_range(0.08, 0.22)
			spark_max_life[s] = spark_life[s]
			spark_color[s] = COLOR_SURGE if randf() > 0.3 else COLOR_ARC_WHITE
			break


func _recalculate_cable() -> void:
	# Catenary / Bezier curve from anchor to plug with natural gravitational sag
	var p0: Vector2 = anchor_pos
	var p3: Vector2 = current_plug_pos

	var span: float = p0.distance_to(p3)
	var sag: float = clampf(span * 0.45, 60.0, 240.0)

	var p1: Vector2 = Vector2(lerpf(p0.x, p3.x, 0.25), lerpf(p0.y, p3.y, 0.25) + sag)
	var p2: Vector2 = Vector2(lerpf(p0.x, p3.x, 0.75), lerpf(p0.y, p3.y, 0.75) + sag * 0.8)

	var denom: float = float(CABLE_SEGMENTS - 1)
	for i in CABLE_SEGMENTS:
		var t: float = float(i) / denom
		var omt: float = 1.0 - t
		var b_point: Vector2 = omt * omt * omt * p0 + 3.0 * omt * omt * t * p1 + 3.0 * omt * t * t * p2 + t * t * t * p3
		cable_points[i] = b_point


func render(canvas: CanvasItem, mid_shift: Vector2) -> void:
	var eff_socket: Vector2 = socket_pos + mid_shift + head_shudder_offset
	var eff_visor: Vector2 = visor_pos + mid_shift + head_shudder_offset

	# --------------------------------------------------------------------------
	# 1. Temporal Bayonet Port on Robot Head
	# --------------------------------------------------------------------------
	canvas.draw_circle(eff_socket, 24.0, Color(0.09, 0.11, 0.13))
	canvas.draw_circle(eff_socket, 22.0, Color(0.40, 0.46, 0.54), false, 2.5)
	canvas.draw_circle(eff_socket, 17.0, Color(0.18, 0.21, 0.26), false, 1.5)

	# Keyway guide slot indicator at 12 o'clock (-Y)
	canvas.draw_line(eff_socket - Vector2(0.0, 13.0), eff_socket - Vector2(0.0, 24.0), Color(0.92, 0.94, 0.98), 3.0)

	# Socket 6 pin contacts
	for p in 6:
		var p_ang: float = float(p) * (TAU / 6.0)
		var pin_pos: Vector2 = eff_socket + Vector2(cos(p_ang), sin(p_ang)) * 12.0
		var pin_col: Color = COLOR_SURGE if (is_locked or arc_intensity > 0.3) else Color(0.68, 0.58, 0.36)
		canvas.draw_circle(pin_pos, 2.2, pin_col)
		if is_locked or arc_intensity > 0.4:
			canvas.draw_circle(pin_pos, 4.0, Color(COLOR_SURGE.r, COLOR_SURGE.g, COLOR_SURGE.b, 0.35))

	# Radial power discharge glow around socket when energized
	if is_power_delivered and power_feed_timer < 0.65:
		var flare_r: float = 24.0 + (power_feed_timer / 0.65) * 28.0
		var flare_a: float = (1.0 - (power_feed_timer / 0.65)) * 0.45
		canvas.draw_circle(eff_socket, flare_r, Color(COLOR_SURGE.r, COLOR_SURGE.g, COLOR_SURGE.b, flare_a))

	# --------------------------------------------------------------------------
	# 2. Umbilical Cable Shadow (Deep contact shadow in room)
	# --------------------------------------------------------------------------
	var shadow_offset: Vector2 = Vector2(10.0, 16.0)
	for i in CABLE_SEGMENTS - 1:
		canvas.draw_line(cable_points[i] + shadow_offset, cable_points[i + 1] + shadow_offset, Color(0.03, 0.04, 0.05, 0.35), 14.0)

	# --------------------------------------------------------------------------
	# 3. Outer Armored Cable Jacket & Inner Core
	# --------------------------------------------------------------------------
	for i in CABLE_SEGMENTS - 1:
		canvas.draw_line(cable_points[i], cable_points[i + 1], CABLE_OUTER_COLOR, 12.0)

	# Cable ribbed/armored segmented rings
	for i in range(1, CABLE_SEGMENTS - 1):
		var seg_dir: Vector2 = (cable_points[i + 1] - cable_points[i - 1]).normalized()
		var seg_n: Vector2 = Vector2(-seg_dir.y, seg_dir.x)
		canvas.draw_line(cable_points[i] - seg_n * 6.5, cable_points[i] + seg_n * 6.5, Color(0.22, 0.26, 0.32), 2.0)

	# Inner conduit core line
	for i in CABLE_SEGMENTS - 1:
		canvas.draw_line(cable_points[i], cable_points[i + 1], CABLE_INNER_COLOR, 5.0)

	# --------------------------------------------------------------------------
	# 4. Neon Electrical Current Impulse Wave along Cable (Requirement 2)
	# --------------------------------------------------------------------------
	if surge_active:
		# A. Energized neon conduit trailing behind the pulse wavefront
		var wave_segment_pos: float = surge_progress * float(CABLE_SEGMENTS - 1)
		var active_seg_limit: int = clampi(int(wave_segment_pos) + 1, 0, CABLE_SEGMENTS - 1)

		for i in active_seg_limit:
			var seg_fade: float = 1.0 if not is_power_delivered else clampf(1.0 - (power_feed_timer / power_feed_duration) * 0.4, 0.5, 1.0)
			# Vibrant glowing neon core along energized cable length
			canvas.draw_line(cable_points[i], cable_points[i + 1], Color(0.18, 0.65, 1.0, 0.50 * seg_fade), 8.0)
			canvas.draw_line(cable_points[i], cable_points[i + 1], Color(COLOR_SURGE.r, COLOR_SURGE.g, COLOR_SURGE.b, 0.90 * seg_fade), 4.0)
			canvas.draw_line(cable_points[i], cable_points[i + 1], Color(1.0, 1.0, 1.0, 0.85 * seg_fade), 1.5)

		# B. Traveling Neon Wave Head (Surges straight into robot head)
		if not is_power_delivered:
			var pulse_idx: float = wave_segment_pos
			var base_i: int = clampi(int(pulse_idx), 0, CABLE_SEGMENTS - 2)
			var frac: float = pulse_idx - float(base_i)
			var pulse_pos: Vector2 = cable_points[base_i].lerp(cable_points[base_i + 1], frac)
			var pulse_tangent: Vector2 = (cable_points[base_i + 1] - cable_points[base_i]).normalized()

			# High-voltage neon bloom & corona
			canvas.draw_circle(pulse_pos, 28.0, Color(0.12, 0.55, 1.0, 0.32))
			canvas.draw_circle(pulse_pos, 18.0, Color(0.35, 0.90, 1.0, 0.65))
			canvas.draw_circle(pulse_pos, 8.0, Color(1.0, 1.0, 1.0, 0.98))

			# Directional laser capsule along the cable tangent
			canvas.draw_line(pulse_pos - pulse_tangent * 14.0, pulse_pos + pulse_tangent * 14.0, Color(0.40, 0.95, 1.0, 0.85), 10.0)
			canvas.draw_line(pulse_pos - pulse_tangent * 9.0, pulse_pos + pulse_tangent * 9.0, Color(1.0, 1.0, 1.0, 1.0), 5.0)

			# Trailing comet sparks along the cable
			for k in 3:
				var trail_t: float = clampf(frac - float(k) * 0.25, 0.0, 1.0)
				var trail_p: Vector2 = cable_points[base_i].lerp(cable_points[base_i + 1], trail_t)
				canvas.draw_circle(trail_p, 4.0 - float(k), Color(0.60, 0.95, 1.0, 0.7 - float(k) * 0.2))

	# --------------------------------------------------------------------------
	# 5. Connector Plug (Brass & Steel Bayonet Mechanism)
	# --------------------------------------------------------------------------
	var rad_ang: float = deg_to_rad(plug_angle)
	var forward: Vector2 = Vector2(cos(rad_ang), sin(rad_ang))
	var right: Vector2 = Vector2(-forward.y, forward.x)

	var plug_center: Vector2 = current_plug_pos
	canvas.draw_circle(plug_center, 18.0, PLUG_BRASS_COLOR)
	canvas.draw_circle(plug_center, 12.0, PLUG_DARK_COLOR)

	# Collar and keyway tab
	var tab_pos: Vector2 = plug_center + forward * 16.0
	canvas.draw_circle(tab_pos, 4.0, Color(0.95, 0.95, 0.98))
	canvas.draw_line(plug_center, plug_center + forward * 22.0, Color(0.95, 0.95, 0.98), 3.0)

	# Grounding prongs
	canvas.draw_line(plug_center + right * 10.0, plug_center + right * 10.0 + forward * 14.0, PLUG_BRASS_COLOR, 2.5)
	canvas.draw_line(plug_center - right * 10.0, plug_center - right * 10.0 + forward * 14.0, PLUG_BRASS_COLOR, 2.5)

	# Magnetic snap guide line
	if is_near_socket and not is_locked:
		canvas.draw_line(plug_center, eff_socket, Color(0.40, 0.85, 1.0, 0.5), 1.5)

	# --------------------------------------------------------------------------
	# 6. Blue Electric Micro-Arcs (< 50px Proximity) (Requirement 1)
	# --------------------------------------------------------------------------
	if arc_active_count > 0 and not is_locked:
		for a in arc_active_count:
			var pts: PackedVector2Array = arc_points[a]

			# Pass 1: Outer electric blue atmospheric glow
			canvas.draw_polyline(pts, Color(COLOR_ARC_BLUE.r, COLOR_ARC_BLUE.g, COLOR_ARC_BLUE.b, 0.35 * arc_intensity), 4.5)

			# Pass 2: High-voltage cyan plasma arc
			canvas.draw_polyline(pts, Color(COLOR_SURGE.r, COLOR_SURGE.g, COLOR_SURGE.b, 0.85 * arc_intensity), 2.2)

			# Pass 3: White-hot discharge core
			canvas.draw_polyline(pts, Color(COLOR_ARC_WHITE.r, COLOR_ARC_WHITE.g, COLOR_ARC_WHITE.b, 0.95 * arc_intensity), 1.0)

			# Terminal hot-spots at contacts
			canvas.draw_circle(pts[0], 3.0, Color(COLOR_SURGE.r, COLOR_SURGE.g, COLOR_SURGE.b, 0.8 * arc_intensity))
			canvas.draw_circle(pts[0], 1.5, COLOR_ARC_WHITE)
			canvas.draw_circle(pts[ARC_SEGMENTS - 1], 3.0, Color(COLOR_SURGE.r, COLOR_SURGE.g, COLOR_SURGE.b, 0.8 * arc_intensity))
			canvas.draw_circle(pts[ARC_SEGMENTS - 1], 1.5, COLOR_ARC_WHITE)

	# Micro-spark particles
	for s in MAX_SPARKS:
		if spark_life[s] > 0.0:
			var spark_a: float = clampf(spark_life[s] / spark_max_life[s], 0.0, 1.0)
			var col: Color = Color(spark_color[s].r, spark_color[s].g, spark_color[s].b, spark_a)
			canvas.draw_circle(spark_pos[s], 1.8, col)

	# --------------------------------------------------------------------------
	# 7. Robot Head Cranial Arc & Visor Flash upon Power Delivery (Requirement 3)
	# --------------------------------------------------------------------------
	if is_power_delivered:
		# A. Cranial high-voltage electric discharge arc (Socket -> Visor)
		if power_feed_timer < 0.45:
			var arc_fade: float = 1.0 - (power_feed_timer / 0.45)
			canvas.draw_polyline(_cranial_arc_points, Color(COLOR_ARC_BLUE.r, COLOR_ARC_BLUE.g, COLOR_ARC_BLUE.b, 0.40 * arc_fade), 4.0)
			canvas.draw_polyline(_cranial_arc_points, Color(COLOR_SURGE.r, COLOR_SURGE.g, COLOR_SURGE.b, 0.85 * arc_fade), 2.0)
			canvas.draw_polyline(_cranial_arc_points, Color(COLOR_ARC_WHITE.r, COLOR_ARC_WHITE.g, COLOR_ARC_WHITE.b, 0.95 * arc_fade), 1.0)

		# B. Robot Optic Visor
		_render_robot_visor(canvas, eff_visor)


func _render_robot_visor(canvas: CanvasItem, center: Vector2) -> void:
	var half_w: float = VISOR_WIDTH * 0.5
	var half_h: float = VISOR_HEIGHT * 0.5
	var chamfer: float = 5.0

	# Visor hexagonal armor frame (Zero GC polygon buffer)
	_visor_poly[0] = center + Vector2(-half_w + chamfer, -half_h)
	_visor_poly[1] = center + Vector2(half_w - chamfer, -half_h)
	_visor_poly[2] = center + Vector2(half_w, 0.0)
	_visor_poly[3] = center + Vector2(half_w - chamfer, half_h)
	_visor_poly[4] = center + Vector2(-half_w + chamfer, half_h)
	_visor_poly[5] = center + Vector2(-half_w, 0.0)

	# 1. Bezel and dark housing
	canvas.draw_colored_polygon(_visor_poly, COLOR_VISOR_HOUSING)
	canvas.draw_polyline(_visor_poly, Color(0.35, 0.42, 0.50, 0.8), 1.5)

	# 2. Visor active optic glowing background
	var bg_col: Color = COLOR_VISOR_BASE.lerp(COLOR_VISOR_ACTIVE, visor_intensity * 0.65)
	canvas.draw_colored_polygon(_visor_poly, bg_col)

	# 3. Anamorphic horizontal lens flare streak (Blinding ignition flash)
	if visor_flare_alpha > 0.01:
		var flare_half_len: float = 90.0 + visor_intensity * 40.0
		var fl_start := Vector2(center.x - flare_half_len, center.y)
		var fl_end := Vector2(center.x + flare_half_len, center.y)

		# Outer soft cyan flare
		canvas.draw_line(fl_start, fl_end, Color(0.20, 0.75, 1.0, 0.40 * visor_flare_alpha), 6.0)
		# Intense cyan beam
		canvas.draw_line(fl_start * 0.8 + center * 0.2, fl_end * 0.8 + center * 0.2, Color(COLOR_SURGE.r, COLOR_SURGE.g, COLOR_SURGE.b, 0.85 * visor_flare_alpha), 2.5)
		# Pure white laser core
		canvas.draw_line(center - Vector2(36.0, 0.0), center + Vector2(36.0, 0.0), Color(1.0, 1.0, 1.0, 0.95 * visor_flare_alpha), 1.2)

	# 4. Optic sensor diodes (5 segments inside visor glass)
	var num_diodes: int = 5
	var diode_w: float = 8.0
	var diode_gap: float = 3.0
	var total_diodes_w: float = float(num_diodes) * diode_w + float(num_diodes - 1) * diode_gap
	var start_dx: float = center.x - total_diodes_w * 0.5

	for d in num_diodes:
		var dx: float = start_dx + float(d) * (diode_w + diode_gap)
		var d_rect := Rect2(dx, center.y - 3.5, diode_w, 7.0)

		# Optic diode boot sequence / activity
		var diode_glow: float = clampf(visor_intensity * (0.8 + 0.2 * sin(optic_glitch_phase + float(d) * 1.5)), 0.0, 1.0)
		var d_col: Color = COLOR_VISOR_ACTIVE.lerp(COLOR_VISOR_CORE, diode_glow)
		d_col.a = diode_glow
		canvas.draw_rect(d_rect, d_col)

	# 5. Overcharge central core flash (Moment of initial power surge delivery)
	if power_feed_timer < 0.22:
		var flash_core_a: float = (1.0 - (power_feed_timer / 0.22)) * 0.90
		canvas.draw_colored_polygon(_visor_poly, Color(1.0, 1.0, 1.0, flash_core_a))
		canvas.draw_circle(center, 18.0, Color(0.85, 0.98, 1.0, flash_core_a * 0.8))
