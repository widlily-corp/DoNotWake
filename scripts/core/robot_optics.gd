class_name RobotOptics
extends RefCounted

## Procedural optics, visor, and sensor diagnostic rendering for the combat automaton.
## Renders animated glowing visors, scanning focal beams, auxiliary telemetry diodes,
## diagnostic self-test pings, and threat-reactive glitch flashes.
##
## Strict Zero-Allocation in frame loop: all buffers and sensor descriptors
## are pre-allocated at initialization.

enum Mode {
	DORMANT,           ## Optics inert/dormant during deep sleep
	DIAGNOSTIC_PULSE,  ## Periodic cool blue/amber diagnostic self-test sweep
	ALERT_SCAN,        ## Threat detected: cursor near head or instability rising
	OVERDRIVE_AWAKE    ## Full emergency red illumination and stroboscopic flare
}

# --- Visual Color Standards ---
const COLOR_COLD_BLUE: Color = Color(0.20, 0.68, 0.98, 1.0)  ## Standby diagnostic cyan-blue
const COLOR_AMBER: Color = Color(0.98, 0.72, 0.16, 1.0)      ## Caution/diagnostic amber
const COLOR_ALERT_RED: Color = Color(1.0, 0.20, 0.08, 1.0)   ## High threat / awakened red
const COLOR_CORE_WHITE: Color = Color(0.96, 0.98, 1.0, 1.0)  ## Incandescent optical filament

# --- Geometrical Constants ---
const DEFAULT_VISOR_RECT: Rect2 = Rect2(618.0, 137.0, 44.0, 16.0)

# Preallocated bloom radii and falloff alphas for Zero-GC procedural volumetric glow
var bloom_radii: PackedFloat32Array = PackedFloat32Array([5.0, 12.0, 24.0, 42.0, 64.0])
var bloom_alphas: PackedFloat32Array = PackedFloat32Array([0.34, 0.18, 0.09, 0.038, 0.014])

# --- Configuration & Tuning Parameters ---
var visor_rect: Rect2 = DEFAULT_VISOR_RECT
var visor_center: Vector2 = Vector2(640.0, 145.0)

var warn_distance: float = 175.0      ## Distance (px) where automaton begins sensing proximity
var danger_distance: float = 45.0     ## Distance (px) of immediate head intrusion

var calm_pulse_min_interval: float = 4.0
var calm_pulse_max_interval: float = 7.5
var calm_pulse_duration: float = 1.25

# --- Live Dynamic State ---
var current_mode: Mode = Mode.DORMANT
var time_accum: float = 0.0
var calm_timer: float = 3.0
var pulse_elapsed: float = 0.0
var pulse_is_amber: bool = false

var cursor_proximity: float = 0.0    ## 0.0 (far) to 1.0 (directly on visor)
var heat_ratio: float = 0.0          ## 0.0 to 1.0 normalized instability
var threat_ratio: float = 0.0        ## instability / threshold ratio
var agitation: float = 0.0           ## combined agitation score
var is_awake: bool = false

var scan_phase: float = 0.0
var scan_speed: float = 2.5
var beam_x_norm: float = 0.5         ## 0.0 to 1.0 along visor width
var beam_width: float = 3.5

var flash_timer: float = 0.0
var flash_duration: float = 0.08
var flash_intensity: float = 0.0
var next_glitch_timer: float = 1.8

var current_color: Color = Color.BLACK
var current_intensity: float = 0.0

# Pre-allocated auxiliary sensor diode definitions (Zero Alloc)
var sensors: Array[Dictionary] = []


func _init() -> void:
	_init_sensors()
	_recalc_geometry()
	calm_timer = randf_range(calm_pulse_min_interval, calm_pulse_max_interval)


func _init_sensors() -> void:
	sensors.clear()
	# 1. Left auxiliary sub-sensor
	sensors.append({
		"id": "left_sub",
		"offset": Vector2(-28.0, 0.0),
		"radius": 2.2,
		"color": COLOR_COLD_BLUE,
		"glow_radius": 6.0,
		"alpha": 0.0
	})
	# 2. Right auxiliary sub-sensor
	sensors.append({
		"id": "right_sub",
		"offset": Vector2(28.0, 0.0),
		"radius": 2.2,
		"color": COLOR_COLD_BLUE,
		"glow_radius": 6.0,
		"alpha": 0.0
	})
	# 3. Forehead / brow diagnostic diode
	sensors.append({
		"id": "forehead_telemetry",
		"offset": Vector2(0.0, -18.0),
		"radius": 1.8,
		"color": COLOR_AMBER,
		"glow_radius": 5.0,
		"alpha": 0.0
	})
	# 4. Temple auxiliary node (near umbilical port)
	sensors.append({
		"id": "temple_node",
		"offset": Vector2(-23.0, -11.0),
		"radius": 1.6,
		"color": COLOR_COLD_BLUE,
		"glow_radius": 4.5,
		"alpha": 0.0
	})


func _recalc_geometry() -> void:
	visor_center = visor_rect.position + visor_rect.size * 0.5


## Configures the optics geometry from the robot bounding rect and optional config dictionary.
## Scales visor coordinates relative to the robot frame if not explicitly given.
func configure(p_robot_rect: Rect2, config: Dictionary = {}) -> void:
	if config.has("visor_rect"):
		visor_rect = Balance.to_rect(config["visor_rect"])
	else:
		# Auto-calculate from sprite proportions (660x1325 sprite texture)
		var rel_x := p_robot_rect.position.x + p_robot_rect.size.x * (278.0 / 660.0)
		var rel_y := p_robot_rect.position.y + p_robot_rect.size.y * (177.0 / 1325.0)
		var rel_w := p_robot_rect.size.x * (103.0 / 660.0)
		var rel_h := p_robot_rect.size.y * (43.0 / 1325.0)
		visor_rect = Rect2(rel_x, rel_y, rel_w, rel_h)

	_recalc_geometry()

	warn_distance = float(config.get("warn_distance", warn_distance))
	danger_distance = float(config.get("danger_distance", danger_distance))
	calm_pulse_min_interval = float(config.get("calm_pulse_min_interval", calm_pulse_min_interval))
	calm_pulse_max_interval = float(config.get("calm_pulse_max_interval", calm_pulse_max_interval))
	calm_pulse_duration = float(config.get("calm_pulse_duration", calm_pulse_duration))


## Frame update without any heap allocations.
func update(
	delta: float,
	mouse_pos: Vector2,
	robot_shift: Vector2,
	instability: float,
	threshold: float,
	awake: bool
) -> void:
	time_accum += delta
	is_awake = awake

	var world_center := visor_center + robot_shift
	var dist := mouse_pos.distance_to(world_center)

	# 1. Proximity detection
	if dist >= warn_distance:
		cursor_proximity = 0.0
	elif dist <= danger_distance:
		cursor_proximity = 1.0
	else:
		cursor_proximity = (warn_distance - dist) / (warn_distance - danger_distance)

	# 2. Instability & threat metrics
	heat_ratio = clampf((instability - 20.0) / 80.0, 0.0, 1.0)
	threat_ratio = clampf(instability / maxf(threshold, 1.0), 0.0, 1.5)

	# Combined agitation level: proximity to head + instability approaching threshold
	var raw_agitation := cursor_proximity * 0.75 + maxf(threat_ratio - 0.45, 0.0) * 1.5
	agitation = clampf(raw_agitation, 0.0, 1.0)
	if is_awake:
		agitation = 1.0

	# 3. State resolution
	if is_awake:
		current_mode = Mode.OVERDRIVE_AWAKE
	elif agitation > 0.12:
		current_mode = Mode.ALERT_SCAN
	elif current_mode != Mode.DIAGNOSTIC_PULSE:
		current_mode = Mode.DORMANT

	# 4. Mode-specific updates
	match current_mode:
		Mode.DORMANT:
			_update_dormant(delta)
		Mode.DIAGNOSTIC_PULSE:
			_update_diagnostic_pulse(delta)
		Mode.ALERT_SCAN:
			_update_alert_scan(delta)
		Mode.OVERDRIVE_AWAKE:
			_update_awake(delta)

	# 5. Micro-flashes and glitch jitter ("короткие всполохи")
	_update_flashes(delta)


func _update_dormant(delta: float) -> void:
	# Optics are dark, timer counts down to next diagnostic self-check
	current_intensity = 0.0
	current_color = COLOR_COLD_BLUE
	beam_x_norm = 0.5

	calm_timer -= delta
	if calm_timer <= 0.0:
		current_mode = Mode.DIAGNOSTIC_PULSE
		pulse_elapsed = 0.0
		# 65% cold blue self-check, 35% amber diagnostic telemetry
		pulse_is_amber = (randf() < 0.35)
		var overflow: float = -calm_timer
		calm_timer = randf_range(calm_pulse_min_interval, calm_pulse_max_interval)
		_update_diagnostic_pulse(overflow)
		return

	# Reset sensor alphas
	for i in range(sensors.size()):
		sensors[i]["alpha"] = 0.0


func _update_diagnostic_pulse(delta: float) -> void:
	pulse_elapsed += delta
	var t := clampf(pulse_elapsed / calm_pulse_duration, 0.0, 1.0)

	# Smooth bell curve for pulse intensity
	var envelope := sin(t * PI)
	current_intensity = envelope * 0.72

	# Color selection
	var base_col: Color = COLOR_AMBER if pulse_is_amber else COLOR_COLD_BLUE
	current_color = base_col

	# Visor beam sweeps smoothly from left to right (0.0 -> 1.0)
	beam_x_norm = t
	beam_width = 4.0

	# Sequential diagnostic firing of auxiliary sensor diodes
	# Forehead: early ping (0.10 -> 0.35)
	var a_forehead := _bell_window(t, 0.10, 0.35)
	# Left sub-sensor: second ping (0.25 -> 0.50)
	var a_left := _bell_window(t, 0.25, 0.50)
	# Right sub-sensor: acknowledgement ping (0.50 -> 0.75)
	var a_right := _bell_window(t, 0.50, 0.75)
	# Temple node: closing confirmation (0.65 -> 0.90)
	var a_temple := _bell_window(t, 0.65, 0.90)

	sensors[0]["alpha"] = a_left * 0.85
	sensors[0]["color"] = base_col
	sensors[1]["alpha"] = a_right * 0.85
	sensors[1]["color"] = base_col
	sensors[2]["alpha"] = a_forehead * 0.95
	sensors[2]["color"] = COLOR_AMBER
	sensors[3]["alpha"] = a_temple * 0.75
	sensors[3]["color"] = base_col

	if pulse_elapsed >= calm_pulse_duration:
		current_mode = Mode.DORMANT
		current_intensity = 0.0


func _update_alert_scan(delta: float) -> void:
	# Scanning speed ramps up with agitation (2.5 Hz to 9.5 Hz)
	scan_speed = lerpf(2.5, 9.5, agitation)
	scan_phase = fmod(scan_phase + delta * scan_speed, TAU)

	# Ping-pong scanning beam across visor width
	beam_x_norm = 0.5 + 0.5 * sin(scan_phase)
	beam_width = lerpf(4.5, 2.5, agitation) # beam narrows as focus tightens

	# Base intensity rises with agitation
	var base_intensity: float = lerpf(0.35, 0.92, agitation)
	# Add subtle breathing oscillation to baseline
	var breath: float = 0.08 * sin(time_accum * 4.0)
	current_intensity = clampf(base_intensity + breath, 0.0, 1.0)

	# Dynamic color gradient: Cold Blue -> Warning Amber -> Threat Red
	if agitation < 0.45:
		var factor: float = agitation / 0.45
		current_color = COLOR_COLD_BLUE.lerp(COLOR_AMBER, factor)
	else:
		var factor: float = (agitation - 0.45) / 0.55
		current_color = COLOR_AMBER.lerp(COLOR_ALERT_RED, factor)

	# Auxiliary sensor behavior: strobing warning cadence
	var strobe_hz: float = lerpf(3.0, 14.0, agitation)
	var s_pulse: float = 0.5 + 0.5 * sin(time_accum * strobe_hz)
	var s_alt: float = 0.5 + 0.5 * sin(time_accum * strobe_hz + PI)

	sensors[0]["alpha"] = s_pulse * (0.4 + 0.5 * agitation)
	sensors[0]["color"] = current_color
	sensors[1]["alpha"] = s_alt * (0.4 + 0.5 * agitation)
	sensors[1]["color"] = current_color
	sensors[2]["alpha"] = (s_pulse * 0.7) * (0.5 + 0.5 * agitation)
	sensors[2]["color"] = COLOR_AMBER.lerp(COLOR_ALERT_RED, agitation)
	sensors[3]["alpha"] = s_alt * 0.6
	sensors[3]["color"] = current_color


func _update_awake(delta: float) -> void:
	# Blinding emergency alert overdrive
	current_color = COLOR_ALERT_RED
	beam_x_norm = 0.5 + 0.48 * sin(time_accum * 22.0)
	beam_width = 6.0

	# Furious stroboscopic intensity pulse (28 Hz)
	var strobe := 0.7 + 0.3 * sin(time_accum * 28.0)
	current_intensity = 1.15 * strobe

	# All sensors strobing at max warning
	for i in range(sensors.size()):
		sensors[i]["alpha"] = strobe
		sensors[i]["color"] = COLOR_ALERT_RED


func _update_flashes(delta: float) -> void:
	# Trigger erratic glitch bursts ("короткие всполохи") when agitated or unstable
	if agitation > 0.18 and current_mode != Mode.OVERDRIVE_AWAKE:
		next_glitch_timer -= delta
		if next_glitch_timer <= 0.0:
			flash_timer = randf_range(0.04, 0.11)
			flash_duration = flash_timer
			flash_intensity = randf_range(0.5, 1.1) * agitation
			# Beam micro-twitch jitter
			beam_x_norm = clampf(beam_x_norm + randf_range(-0.18, 0.18), 0.05, 0.95)

			# Interval scales inversely with agitation
			var min_wait: float = lerpf(1.2, 0.25, agitation)
			var max_wait: float = lerpf(2.8, 0.70, agitation)
			next_glitch_timer = randf_range(min_wait, max_wait)

	if flash_timer > 0.0:
		flash_timer = maxf(flash_timer - delta, 0.0)
		var flash_ratio := flash_timer / maxf(flash_duration, 0.001)
		current_intensity = clampf(current_intensity + flash_intensity * flash_ratio, 0.0, 1.4)


## Zero-Allocation procedural rendering directly to Godot CanvasItem.
func render(canvas: CanvasItem, robot_shift: Vector2) -> void:
	var v_rect := Rect2(visor_rect.position + robot_shift, visor_rect.size)
	var wire_y := v_rect.position.y + v_rect.size.y * 0.5
	var eff_intensity := current_intensity

	# 1. Beveled mechanical aperture & dark optical glass
	_draw_visor_housing(canvas, v_rect)

	# If the optics are completely off, auxiliary sensors stay dormant and we exit early
	if eff_intensity <= 0.005:
		return

	# 2. Visor internal raster/scanlines
	_draw_visor_raster(canvas, v_rect)

	# 3. Slit ambient luminescence
	var ambient_col := current_color
	ambient_col.a = clampf(eff_intensity * 0.24, 0.0, 0.8)
	canvas.draw_rect(v_rect.grow(-1.0), ambient_col)

	# 4. Scanning beam & focal trail
	var beam_x := v_rect.position.x + v_rect.size.x * beam_x_norm
	_draw_scanning_beam(canvas, v_rect, beam_x, eff_intensity)

	# 5. Hot optical wire / central core
	var wire_col := current_color.lerp(COLOR_CORE_WHITE, 0.65)
	wire_col.a = clampf(eff_intensity * 0.85, 0.0, 1.0)
	canvas.draw_line(
		Vector2(v_rect.position.x + 2.0, wire_y),
		Vector2(v_rect.end.x - 2.0, wire_y),
		wire_col,
		1.5
	)

	# 6. Procedural multi-layered volumetric bloom (Zero GC: loop with static arrays)
	var beam_center := Vector2(beam_x, wire_y)
	var bloom_col := current_color
	for i in range(5):
		bloom_col.a = bloom_alphas[i] * eff_intensity
		canvas.draw_circle(beam_center, bloom_radii[i], bloom_col)

	# 7. Anamorphic horizontal lens flare streak
	if eff_intensity > 0.32:
		var flare_len := (v_rect.size.x * 0.75) * eff_intensity
		var flare_col := current_color.lerp(COLOR_CORE_WHITE, 0.55)
		flare_col.a = clampf((eff_intensity - 0.25) * 0.45, 0.0, 0.65)
		canvas.draw_line(
			Vector2(beam_x - flare_len, wire_y),
			Vector2(beam_x + flare_len, wire_y),
			flare_col,
			1.0
		)

	# 8. Auxiliary sensor diodes
	_draw_auxiliary_sensors(canvas, robot_shift)


func _draw_visor_housing(canvas: CanvasItem, v_rect: Rect2) -> void:
	# Outer dark recessed bevel
	canvas.draw_rect(v_rect.grow(2.0), Color(0.06, 0.08, 0.10, 0.85), false, 1.0)
	# Metallic aperture lip
	canvas.draw_rect(v_rect.grow(1.0), Color(0.18, 0.22, 0.26, 0.70), false, 1.0)
	# Deep dark optical glass base
	canvas.draw_rect(v_rect, Color(0.02, 0.03, 0.05, 0.95))


func _draw_visor_raster(canvas: CanvasItem, v_rect: Rect2) -> void:
	# Subtle horizontal scanlines inside visor glass
	var y_start := v_rect.position.y + 2.0
	var y_end := v_rect.end.y - 1.0
	var y := y_start
	while y < y_end:
		canvas.draw_line(
			Vector2(v_rect.position.x, y),
			Vector2(v_rect.end.x, y),
			Color(0.0, 0.0, 0.0, 0.35),
			1.0
		)
		y += 3.0


func _draw_scanning_beam(canvas: CanvasItem, v_rect: Rect2, beam_x: float, eff_intensity: float) -> void:
	var top_y := v_rect.position.y + 1.0
	var bot_y := v_rect.end.y - 1.0

	# Falloff persistence trail on both flanks
	var trail_alpha := clampf(eff_intensity * 0.22, 0.0, 0.45)
	var trail_col := current_color
	trail_col.a = trail_alpha

	canvas.draw_line(Vector2(beam_x - 3.5, top_y), Vector2(beam_x - 3.5, bot_y), trail_col, 2.0)
	canvas.draw_line(Vector2(beam_x + 3.5, top_y), Vector2(beam_x + 3.5, bot_y), trail_col, 2.0)

	# Main incandescent beam core
	var beam_col := current_color.lerp(COLOR_CORE_WHITE, 0.75)
	beam_col.a = clampf(eff_intensity * 0.95, 0.0, 1.0)
	canvas.draw_line(Vector2(beam_x, top_y), Vector2(beam_x, bot_y), beam_col, beam_width)


func _draw_auxiliary_sensors(canvas: CanvasItem, robot_shift: Vector2) -> void:
	for i in range(sensors.size()):
		var s: Dictionary = sensors[i]
		var s_alpha: float = float(s.get("alpha", 0.0))
		if s_alpha <= 0.01:
			continue

		var s_pos: Vector2 = visor_center + (s["offset"] as Vector2) + robot_shift
		var s_radius: float = float(s["radius"])
		var s_col: Color = s["color"] as Color
		var s_glow_rad: float = float(s["glow_radius"])

		# 1. Bezel ring
		canvas.draw_circle(s_pos, s_radius + 1.0, Color(0.08, 0.10, 0.12, 0.90))

		# 2. Outer soft halo
		var halo_col := s_col
		halo_col.a = s_alpha * 0.25
		canvas.draw_circle(s_pos, s_glow_rad, halo_col)

		# 3. Active diode core
		var core_col := s_col.lerp(COLOR_CORE_WHITE, 0.6)
		core_col.a = s_alpha * 0.95
		canvas.draw_circle(s_pos, s_radius, core_col)

		# 4. Specular glint
		canvas.draw_circle(s_pos - Vector2(0.5, 0.5), 0.6, Color(1.0, 1.0, 1.0, s_alpha * 0.8))


static func _bell_window(t: float, start_t: float, end_t: float) -> float:
	if t <= start_t or t >= end_t:
		return 0.0
	var local_t := (t - start_t) / (end_t - start_t)
	return sin(local_t * PI)
