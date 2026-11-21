class_name ScrubZone
extends Node2D

## Tactile scrubbing mechanic (Stage 1: Dirty Contacts).
## Recessed industrial terminal block with copper contact bars.
## Cleans grime through back-and-forth rag movement within safe speed limits.
## High speed friction generates heat and instability spikes.
## Features realistic falling soot particles, specular metal shine, and incandescent thermal red-hot glow.
## Engineered for strict Zero GC in runtime updates and rendering.

signal scrub_progress_changed(progress: float)
signal scrub_completed()
signal overheat_occurred(heat_penalty: float)
signal feedback_text_requested(text: String, is_alert: bool)

# High-fidelity industrial terminal palette
const COLOR_RECESS_BG: Color = Color(0.06, 0.08, 0.10, 0.70)
const COLOR_COPPER_BASE: Color = Color(0.85, 0.55, 0.28)
const COLOR_COPPER_HIGHLIGHT: Color = Color(0.98, 0.88, 0.70)
const COLOR_COPPER_SHADOW: Color = Color(0.50, 0.30, 0.14)
const COLOR_SOOT_BASE: Color = Color(0.05, 0.05, 0.06)
const COLOR_SPARK: Color = Color(0.95, 0.85, 0.40)

# Thermal glow palette (incandescent cherry-red / orange / yellow-hot core)
const COLOR_HEAT_RED: Color = Color(0.96, 0.12, 0.04)
const COLOR_HEAT_ORANGE: Color = Color(1.0, 0.45, 0.08)
const COLOR_HEAT_HOT_CORE: Color = Color(1.0, 0.85, 0.35)
const COLOR_HEAT_AURA: Color = Color(0.98, 0.15, 0.04)

# Particle types
const PARTICLE_SOOT: int = 0
const PARTICLE_SPARK: int = 1
const PARTICLE_EMBER: int = 2

const MAX_PARTICLES: int = 64
const NUM_DIRT_SPOTS: int = 48
const SHINE_DURATION: float = 1.2
const OVERHEAT_WARN_SPEED: float = 580.0
const OVERHEAT_PENALTY_SPEED: float = 750.0

# Backwards compatibility aliases
const COLOR_CLEAN_BG: Color = Color(0.24, 0.32, 0.28)
const COLOR_COPPER: Color = COLOR_COPPER_BASE
const COLOR_COPPER_SHINE: Color = COLOR_COPPER_HIGHLIGHT
const COLOR_SOOT: Color = Color(0.05, 0.05, 0.06, 0.88)

var zone_rect: Rect2 = Rect2(570.0, 250.0, 140.0, 60.0)
var safe_speed_min: float = 80.0
var safe_speed_max: float = 650.0
var clean_rate: float = 0.0015
var friction_heat_rate: float = 0.012
var target_clean_ratio: float = 0.95
var overheat_penalty: float = 6.0
var overheat_penalty_speed: float = OVERHEAT_PENALTY_SPEED
var hit_padding_x: float = 40.0
var hit_padding_y: float = 25.0

var clean_progress: float = 0.0
var is_completed: bool = false
var is_active: bool = true

var last_mouse_pos: Vector2 = Vector2.ZERO
var current_speed: float = 0.0
var last_dir_x: float = 0.0
var reversals_count: int = 0
var overheat_timer: float = 0.0
var shine_timer: float = 0.0

# Tactile juice & thermodynamic variables
var thermal_heat: float = 0.0
var anim_time: float = 0.0
var peel_distance_accum: float = 0.0

# Pre-allocated particle pool for zero GC
var particle_pos: PackedVector2Array = PackedVector2Array()
var particle_vel: PackedVector2Array = PackedVector2Array()
var particle_life: PackedFloat32Array = PackedFloat32Array()
var particle_max_life: PackedFloat32Array = PackedFloat32Array()
var particle_size: PackedFloat32Array = PackedFloat32Array()
var particle_type: PackedInt32Array = PackedInt32Array()
var particle_rot: PackedFloat32Array = PackedFloat32Array()
var particle_rot_speed: PackedFloat32Array = PackedFloat32Array()
var particle_is_spark: Array[bool] = []

# Pre-allocated static dirt stipple distribution for zero GC
var dirt_spots: PackedVector2Array = PackedVector2Array()
var dirt_radii: PackedFloat32Array = PackedFloat32Array()
var dirt_threshold: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	particle_pos.resize(MAX_PARTICLES)
	particle_vel.resize(MAX_PARTICLES)
	particle_life.resize(MAX_PARTICLES)
	particle_max_life.resize(MAX_PARTICLES)
	particle_size.resize(MAX_PARTICLES)
	particle_type.resize(MAX_PARTICLES)
	particle_rot.resize(MAX_PARTICLES)
	particle_rot_speed.resize(MAX_PARTICLES)
	particle_is_spark.resize(MAX_PARTICLES)

	for i in MAX_PARTICLES:
		particle_pos[i] = Vector2.ZERO
		particle_vel[i] = Vector2.ZERO
		particle_life[i] = 0.0
		particle_max_life[i] = 1.0
		particle_size[i] = 2.0
		particle_type[i] = PARTICLE_SOOT
		particle_rot[i] = 0.0
		particle_rot_speed[i] = 0.0
		particle_is_spark[i] = false

	dirt_spots.resize(NUM_DIRT_SPOTS)
	dirt_radii.resize(NUM_DIRT_SPOTS)
	dirt_threshold.resize(NUM_DIRT_SPOTS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in NUM_DIRT_SPOTS:
		dirt_spots[i] = Vector2(rng.randf(), rng.randf())
		dirt_radii[i] = rng.randf_range(1.5, 3.8)
		dirt_threshold[i] = rng.randf_range(0.08, 0.95)


func _ready() -> void:
	pass


func configure(p_rect: Rect2, params: Dictionary = {}) -> void:
	zone_rect = p_rect
	safe_speed_min = float(params.get("safe_speed_min", 80.0))
	safe_speed_max = float(params.get("safe_speed_max", 650.0))
	clean_rate = float(params.get("clean_rate", 0.0015))
	friction_heat_rate = float(params.get("friction_heat_rate", 0.012))
	target_clean_ratio = float(params.get("target_clean_ratio", params.get("target_ratio", 0.95)))
	overheat_penalty = float(params.get("overheat_penalty", 6.0))
	overheat_penalty_speed = float(params.get("overheat_penalty_speed", OVERHEAT_PENALTY_SPEED))
	hit_padding_x = float(params.get("hit_padding_x", 40.0))
	hit_padding_y = float(params.get("hit_padding_y", 25.0))


## Returns the expanded interaction hit zone with generous padding to prevent slipping out during horizontal wipes.
func get_effective_hit_rect(mid_shift: Vector2 = Vector2.ZERO) -> Rect2:
	return Rect2(zone_rect.position + mid_shift, zone_rect.size).grow_individual(hit_padding_x, hit_padding_y, hit_padding_x, hit_padding_y)


func reset() -> void:
	clean_progress = 0.0
	is_completed = false
	current_speed = 0.0
	reversals_count = 0
	overheat_timer = 0.0
	shine_timer = 0.0
	thermal_heat = 0.0
	anim_time = 0.0
	peel_distance_accum = 0.0
	for i in MAX_PARTICLES:
		particle_life[i] = 0.0


func get_clean_ratio() -> float:
	if target_clean_ratio <= 0.0:
		return 1.0
	return clampf(clean_progress / target_clean_ratio, 0.0, 1.0)


func get_current_speed() -> float:
	return current_speed


func get_speed_state() -> int:
	if current_speed > safe_speed_max:
		return 1
	elif current_speed >= safe_speed_min:
		return 0
	else:
		return -1


func get_thermal_heat() -> float:
	return thermal_heat


func update_scrub(delta: float, mouse_pos: Vector2, is_rag_held: bool, mid_shift: Vector2) -> void:
	if delta <= 0.0:
		return

	anim_time += delta

	# Update visual particles (gravity, flutter, dispersion)
	_update_particles(delta)

	if shine_timer > 0.0:
		shine_timer = maxf(shine_timer - delta, 0.0)

	if is_completed or not is_active:
		# Passive cooling when inactive or completed
		thermal_heat = maxf(thermal_heat - 2.5 * delta, 0.0)
		last_mouse_pos = mouse_pos
		return

	var effective_rect: Rect2 = Rect2(zone_rect.position + mid_shift, zone_rect.size)
	var hit_rect: Rect2 = effective_rect.grow_individual(hit_padding_x, hit_padding_y, hit_padding_x, hit_padding_y)
	var in_zone: bool = hit_rect.has_point(mouse_pos)

	if in_zone and is_rag_held:
		var dist: float = mouse_pos.distance_to(last_mouse_pos)
		current_speed = dist / delta

		# Detect direction reversal (scrubbing motion)
		var dir_x: float = mouse_pos.x - last_mouse_pos.x
		if absf(dir_x) > 3.0:
			if (dir_x > 0.0 and last_dir_x < 0.0) or (dir_x < 0.0 and last_dir_x > 0.0):
				reversals_count += 1
			last_dir_x = dir_x

		if current_speed >= safe_speed_min and current_speed <= safe_speed_max:
			var gain: float = clean_rate * current_speed * delta
			clean_progress = minf(clean_progress + gain, 1.0)
			emit_signal("scrub_progress_changed", clean_progress)

			# Tactile soot crumbling with realistic gravity & dispersion
			peel_distance_accum += dist
			while peel_distance_accum >= 7.0:
				peel_distance_accum -= 7.0
				var flake_pos := mouse_pos + Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0))
				# Horizontal dispersion combines stroke momentum with fan spread
				var flake_vel_x := clampf(last_dir_x * 0.45, -75.0, 75.0) + randf_range(-40.0, 40.0)
				# Flakes crumble downwards with horizontal stroke momentum + spread, accelerated by gravity
				var flake_vel_y := randf_range(15.0, 55.0)
				var flake_life := randf_range(0.8, 1.4)
				var flake_size := randf_range(1.6, 3.4)
				_spawn_particle(flake_pos, Vector2(flake_vel_x, flake_vel_y), flake_life, PARTICLE_SOOT, flake_size)

			# Warmth feedback when scrubbing near the upper speed limit (> 80% safe_speed_max)
			var warm_thresh: float = safe_speed_max * 0.8
			if current_speed > warm_thresh:
				var warm_factor: float = (current_speed - warm_thresh) / maxf(safe_speed_max - warm_thresh, 1.0)
				thermal_heat = minf(thermal_heat + warm_factor * delta * 1.5, 0.35)
			else:
				thermal_heat = maxf(thermal_heat - 1.6 * delta, 0.0)

			if clean_progress >= target_clean_ratio and not is_completed:
				is_completed = true
				shine_timer = SHINE_DURATION
				emit_signal("scrub_completed")

		elif current_speed > safe_speed_max:
			# Exceeded safe speed: rapid incandescent red glow накал builds up before penalty
			var excess_speed: float = current_speed - safe_speed_max
			var heat_gain: float = (excess_speed / 150.0) * delta * 3.0
			thermal_heat = minf(thermal_heat + heat_gain, 1.0)

			if current_speed > overheat_penalty_speed:
				# Exceeded penalty threshold: instability penalty!
				var heat_spike: float = friction_heat_rate * (current_speed - overheat_penalty_speed) * delta
				emit_signal("overheat_occurred", heat_spike)

				overheat_timer += delta
				if overheat_timer >= 0.25:
					overheat_timer = 0.0
					emit_signal("feedback_text_requested", "ОПАСНОСТЬ: ПЕРЕГРЕВ ОТ ТРЕНИЯ!", true)

				# Violent sparks and floating incandescent embers
				if randf() < 0.7:
					_spawn_particle(mouse_pos, Vector2(randf_range(-90.0, 90.0), randf_range(-80.0, 10.0)), 0.45, PARTICLE_SPARK, randf_range(1.8, 2.6))
				if randf() < 0.5:
					_spawn_particle(mouse_pos, Vector2(randf_range(-40.0, 40.0), randf_range(-50.0, -10.0)), 0.7, PARTICLE_EMBER, randf_range(2.0, 3.5))
			else:
				# Warning zone (safe_speed_max .. overheat_penalty_speed): pre-penalty warning embers
				if randf() < 0.3:
					_spawn_particle(mouse_pos, Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 5.0)), 0.5, PARTICLE_EMBER, 1.8)
		else:
			# Speed below safe_speed_min: cool down
			thermal_heat = maxf(thermal_heat - 1.8 * delta, 0.0)
	else:
		current_speed = 0.0
		# Not scrubbing or rag not held: passive cooling
		thermal_heat = maxf(thermal_heat - 2.2 * delta, 0.0)

	last_mouse_pos = mouse_pos


func _spawn_particle(pos: Vector2, vel: Vector2, life: float, type_or_spark = PARTICLE_SOOT, size: float = 2.0) -> void:
	var p_type: int = PARTICLE_SOOT
	if type_or_spark is bool:
		p_type = PARTICLE_SPARK if type_or_spark else PARTICLE_SOOT
	elif type_or_spark is int:
		p_type = type_or_spark

	for i in MAX_PARTICLES:
		if particle_life[i] <= 0.0:
			particle_pos[i] = pos
			particle_vel[i] = vel
			particle_life[i] = life
			particle_max_life[i] = maxf(life, 0.001)
			particle_size[i] = size
			particle_type[i] = p_type
			particle_is_spark[i] = (p_type == PARTICLE_SPARK)
			particle_rot[i] = randf() * TAU
			particle_rot_speed[i] = randf_range(-8.0, 8.0)
			return


func _update_particles(delta: float) -> void:
	for i in MAX_PARTICLES:
		if particle_life[i] > 0.0:
			particle_life[i] -= delta
			var p_type: int = particle_type[i]
			if p_type == PARTICLE_SOOT:
				# Realistic soot gravity, horizontal drag, and aerodynamic flutter
				particle_vel[i].y += 360.0 * delta
				particle_vel[i].x *= exp(-2.8 * delta)
				particle_rot[i] += particle_rot_speed[i] * delta
				particle_pos[i].x += sin(particle_rot[i] * 2.0) * 10.0 * delta
				particle_pos[i] += particle_vel[i] * delta
			elif p_type == PARTICLE_SPARK:
				# Sharp ballistic spark trajectory
				particle_vel[i].y += 260.0 * delta
				particle_vel[i].x *= exp(-1.2 * delta)
				particle_pos[i] += particle_vel[i] * delta
			elif p_type == PARTICLE_EMBER:
				# Hot ember floating with heat updraft then drifting down
				particle_vel[i].y += 160.0 * delta
				particle_vel[i].x *= exp(-2.0 * delta)
				particle_rot[i] += particle_rot_speed[i] * delta
				particle_pos[i].x += sin(particle_rot[i] * 3.0) * 14.0 * delta
				particle_pos[i] += particle_vel[i] * delta


func render(canvas: CanvasItem, mid_shift: Vector2) -> void:
	if not is_active:
		return

	var r: Rect2 = Rect2(zone_rect.position + mid_shift, zone_rect.size)

	# 1. Semi-transparent dark chassis recess
	canvas.draw_rect(r, COLOR_RECESS_BG)

	# Thermal backscatter glow inside chassis recess when overheated
	if thermal_heat > 0.15:
		var pulse: float = 0.85 + 0.15 * sin(anim_time * 16.0)
		var recess_glow := Color(0.85, 0.12, 0.04, (thermal_heat - 0.15) * 0.35 * pulse)
		canvas.draw_rect(r, recess_glow)

	canvas.draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0.02, 0.03, 0.04, 0.6), 1.0)
	canvas.draw_line(r.position, Vector2(r.position.x, r.end.y), Color(0.02, 0.03, 0.04, 0.6), 1.0)
	canvas.draw_line(Vector2(r.position.x, r.end.y), r.end, Color(0.18, 0.22, 0.26, 0.3), 1.0)
	canvas.draw_line(Vector2(r.end.x, r.position.y), r.end, Color(0.18, 0.22, 0.26, 0.3), 1.0)

	# 2. 5 copper contact bars with bevel highlights and thermal incandescent emission
	var bar_count: int = 5
	var bar_step: float = r.size.x / float(bar_count)
	var bar_w: float = bar_step - 6.0
	var bar_h: float = r.size.y - 10.0
	var bar_y: float = r.position.y + 5.0

	var heat_pulse: float = 0.85 + 0.15 * sin(anim_time * 18.0)
	var effective_heat: float = thermal_heat * heat_pulse

	for b in bar_count:
		var bx: float = r.position.x + float(b) * bar_step + 3.0
		var bar_rect: Rect2 = Rect2(bx, bar_y, bar_w, bar_h)

		# Drop shadow under contact bar
		canvas.draw_rect(Rect2(bar_rect.position + Vector2(1, 1), bar_rect.size), Color(0.02, 0.03, 0.04, 0.5))

		# Thermal red aura glow behind/around incandescent contact bars
		if effective_heat > 0.05:
			var aura_rect := Rect2(bar_rect.position - Vector2(3, 3), bar_rect.size + Vector2(6, 6))
			var aura_col := Color(COLOR_HEAT_AURA.r, COLOR_HEAT_AURA.g, COLOR_HEAT_AURA.b, effective_heat * 0.5)
			canvas.draw_rect(aura_rect, aura_col)

		# Bar body: smooth transition from copper tone to incandescent cherry-red
		var bar_c: Color = COLOR_COPPER_BASE.lerp(COLOR_HEAT_RED, effective_heat * 0.90)
		canvas.draw_rect(bar_rect, bar_c)

		# Bevel highlights (top and left edges + vertical specular line)
		var bevel_c: Color = COLOR_COPPER_HIGHLIGHT.lerp(COLOR_HEAT_ORANGE, effective_heat)
		canvas.draw_line(bar_rect.position, Vector2(bar_rect.end.x, bar_rect.position.y), bevel_c, 1.0)
		canvas.draw_line(bar_rect.position, Vector2(bar_rect.position.x, bar_rect.end.y), bevel_c, 1.0)
		canvas.draw_line(Vector2(bx + 2.0, bar_y + 1.0), Vector2(bx + 2.0, bar_y + bar_h - 1.0), bevel_c, 1.0)

		# Shadow bevel (bottom and right edges)
		var shadow_c: Color = COLOR_COPPER_SHADOW.lerp(Color(0.40, 0.05, 0.02), effective_heat)
		canvas.draw_line(Vector2(bar_rect.position.x, bar_rect.end.y), bar_rect.end, shadow_c, 1.0)
		canvas.draw_line(Vector2(bar_rect.end.x, bar_rect.position.y), bar_rect.end, shadow_c, 1.0)

		# Super-heated incandescent core wire (white-yellow hot center at high thermal heat)
		if effective_heat > 0.32:
			var core_heat_t: float = (effective_heat - 0.32) / 0.68
			var core_w: float = 2.0 + core_heat_t * 3.0
			var core_rect := Rect2(bx + (bar_w - core_w) * 0.5, bar_y + 3.0, core_w, bar_h - 6.0)
			var core_col := Color(COLOR_HEAT_HOT_CORE.r, COLOR_HEAT_HOT_CORE.g, COLOR_HEAT_HOT_CORE.b, core_heat_t * heat_pulse)
			canvas.draw_rect(core_rect, core_col)

		# Polished metallic luster line on cleaned copper (when not glowing red)
		if clean_progress > 0.05 and effective_heat < 0.40:
			var luster_a: float = clampf(get_clean_ratio() * (1.0 - effective_heat), 0.0, 1.0) * 0.35
			canvas.draw_line(Vector2(bx + bar_w * 0.35, bar_y + 2.0), Vector2(bx + bar_w * 0.35, bar_y + bar_h - 2.0), Color(1.0, 0.95, 0.85, luster_a), 1.5)

	# 3. Soot overlay that smoothly fades with clean_progress, with soft stippled dirty particles
	var clean_ratio: float = get_clean_ratio()
	var soot_alpha: float = clampf(1.0 - clean_ratio, 0.0, 1.0)
	if soot_alpha > 0.01:
		var soot_col: Color = Color(COLOR_SOOT_BASE.r, COLOR_SOOT_BASE.g, COLOR_SOOT_BASE.b, 0.88 * soot_alpha)
		canvas.draw_rect(r, soot_col)

		# Soft stippled dirty particles with progressive threshold peeling
		for i in NUM_DIRT_SPOTS:
			if clean_ratio < dirt_threshold[i]:
				var spot_fade: float = clampf((dirt_threshold[i] - clean_ratio) / 0.25, 0.0, 1.0)
				var spot_col := Color(COLOR_SOOT_BASE.r, COLOR_SOOT_BASE.g, COLOR_SOOT_BASE.b, 0.92 * spot_fade * soot_alpha)
				var spot_pos: Vector2 = r.position + Vector2(dirt_spots[i].x * r.size.x, dirt_spots[i].y * r.size.y)
				canvas.draw_circle(spot_pos, dirt_radii[i], spot_col)

	# 4. Brilliant metallic specular shine burst (blik) across cleaned copper contacts
	if shine_timer > 0.0:
		var shine_progress: float = 1.0 - (shine_timer / SHINE_DURATION)
		var sweep_center_x: float = r.position.x - 30.0 + shine_progress * (r.size.x + 60.0)
		var sweep_alpha: float = sin(shine_progress * PI)

		# Specular reflection beam across the 5 contact bars
		for b in bar_count:
			var bar_cx: float = r.position.x + float(b) * bar_step + 3.0 + bar_w * 0.5
			var dist_to_sweep: float = absf(sweep_center_x - bar_cx)
			if dist_to_sweep < 22.0:
				var bar_shine_t: float = 1.0 - (dist_to_sweep / 22.0)
				var shine_bar_col := Color(1.0, 0.96, 0.82, bar_shine_t * sweep_alpha * 0.85)
				canvas.draw_rect(Rect2(r.position.x + float(b) * bar_step + 3.0, bar_y, bar_w, bar_h), shine_bar_col)
				# 4-point specular star flash on the top contact point
				var star_pos := Vector2(bar_cx, bar_y + 4.0)
				_draw_specular_star(canvas, star_pos, 10.0 * bar_shine_t, Color(1.0, 0.98, 0.92, bar_shine_t * sweep_alpha))

		# Angled diagonal specular glare sheen lines
		var beam_top := Vector2(sweep_center_x + 8.0, r.position.y + 2.0)
		var beam_bot := Vector2(sweep_center_x - 8.0, r.end.y - 2.0)
		canvas.draw_line(beam_top, beam_bot, Color(1.0, 0.98, 0.92, sweep_alpha * 0.90), 3.0)
		canvas.draw_line(beam_top + Vector2(4, 0), beam_bot + Vector2(4, 0), Color(1.0, 0.85, 0.45, sweep_alpha * 0.50), 1.5)
		canvas.draw_line(beam_top - Vector2(4, 0), beam_bot - Vector2(4, 0), Color(1.0, 0.85, 0.45, sweep_alpha * 0.50), 1.5)

		# Initial full-recess specular burst
		if shine_progress < 0.25:
			var burst_a: float = (0.25 - shine_progress) / 0.25 * 0.35
			canvas.draw_rect(r, Color(1.0, 0.98, 0.92, burst_a))

	# 5. Subtle corner brackets [ ] instead of an intrusive solid border
	var bracket_len: float = 10.0
	var bracket_col: Color = Color(0.40, 0.90, 0.60, 0.85) if is_completed else Color(0.45, 0.55, 0.65, 0.60)
	# Top-left corner
	canvas.draw_line(r.position, Vector2(r.position.x + bracket_len, r.position.y), bracket_col, 1.5)
	canvas.draw_line(r.position, Vector2(r.position.x, r.position.y + bracket_len), bracket_col, 1.5)
	# Top-right corner
	canvas.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - bracket_len, r.position.y), bracket_col, 1.5)
	canvas.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + bracket_len), bracket_col, 1.5)
	# Bottom-left corner
	canvas.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + bracket_len, r.end.y), bracket_col, 1.5)
	canvas.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - bracket_len), bracket_col, 1.5)
	# Bottom-right corner
	canvas.draw_line(r.end, Vector2(r.end.x - bracket_len, r.end.y), bracket_col, 1.5)
	canvas.draw_line(r.end, Vector2(r.end.x, r.end.y - bracket_len), bracket_col, 1.5)

	# 6. Physical particles: crumbling soot flakes, friction sparks, and incandescent embers
	for i in MAX_PARTICLES:
		if particle_life[i] > 0.0:
			var p_pos: Vector2 = particle_pos[i]
			var p_type: int = particle_type[i]

			if p_type == PARTICLE_SOOT:
				var life_t: float = particle_life[i] / particle_max_life[i]
				var alpha: float = clampf(life_t * 1.4, 0.0, 0.92)
				var sz: float = particle_size[i]
				var p_col := Color(0.07, 0.07, 0.08, alpha)
				var p_col_edge := Color(0.18, 0.17, 0.19, alpha * 0.65)
				canvas.draw_circle(p_pos, sz, p_col)
				var flake_offset := Vector2(cos(particle_rot[i]), sin(particle_rot[i])) * (sz * 0.55)
				canvas.draw_circle(p_pos + flake_offset, sz * 0.7, p_col_edge)

			elif p_type == PARTICLE_SPARK:
				var life_t: float = particle_life[i] / particle_max_life[i]
				var spark_col := Color(1.0, 0.95, 0.55, life_t)
				canvas.draw_circle(p_pos, particle_size[i], spark_col)
				var streak_tail: Vector2 = p_pos - particle_vel[i] * 0.012
				canvas.draw_line(p_pos, streak_tail, Color(1.0, 0.75, 0.25, life_t * 0.8), 1.2)

			elif p_type == PARTICLE_EMBER:
				var life_t: float = particle_life[i] / particle_max_life[i]
				var ember_col := Color(1.0, 0.35 + 0.35 * life_t, 0.05, life_t)
				canvas.draw_circle(p_pos, particle_size[i] * 1.6, Color(1.0, 0.12, 0.02, life_t * 0.45))
				canvas.draw_circle(p_pos, particle_size[i], ember_col)


func _draw_specular_star(canvas: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	if radius <= 0.5 or col.a <= 0.01:
		return
	var arm_len := radius
	var arm_short := radius * 0.4
	# Primary horizontal and vertical rays
	canvas.draw_line(center - Vector2(arm_len, 0.0), center + Vector2(arm_len, 0.0), col, 1.5)
	canvas.draw_line(center - Vector2(0.0, arm_len), center + Vector2(0.0, arm_len), col, 1.5)
	# Secondary diagonal rays
	canvas.draw_line(center - Vector2(arm_short, arm_short), center + Vector2(arm_short, arm_short), Color(col.r, col.g, col.b, col.a * 0.6), 1.0)
	canvas.draw_line(center - Vector2(arm_short, -arm_short), center + Vector2(arm_short, -arm_short), Color(col.r, col.g, col.b, col.a * 0.6), 1.0)
	# Central bright hot spot
	canvas.draw_circle(center, radius * 0.25, Color(1.0, 1.0, 1.0, col.a))
