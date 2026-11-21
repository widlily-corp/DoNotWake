class_name RobotThermalFX
extends RefCounted

## Visual procedural system for robot chassis overheating and pressure venting (Do Not Wake).
## Features:
## 1. Soft pulsing thermal glow of the chassis radiator with dynamic heat-sink slats.
## 2. Directional procedural micro-jets of steam/smoke from torso vent valves and articulated joints.
## 3. Acute pressure release blow-offs triggered by rag friction overheat or instability spikes.
## 4. Zero GC architecture: 100% pre-allocated fixed-size particle and geometry pools.

# Pre-allocated pool capacity
const MAX_PARTICLES: int = 160
const NUM_VALVES: int = 10
const NUM_RADIATOR_SLATS: int = 8

# Particle types
const PARTICLE_STREAK: int = 0
const PARTICLE_VAPOR: int = 1

# Color palettes
const COLOR_RADIATOR_COLD: Color = Color(0.12, 0.06, 0.04, 0.0)
const COLOR_RADIATOR_WARM: Color = Color(0.82, 0.25, 0.05, 0.45)
const COLOR_RADIATOR_HOT: Color = Color(1.0, 0.52, 0.08, 0.78)
const COLOR_RADIATOR_INCANDESCENT: Color = Color(1.0, 0.92, 0.68, 0.95)

const COLOR_VALVE_METAL: Color = Color(0.14, 0.16, 0.19)
const COLOR_VALVE_ORIFICE: Color = Color(0.04, 0.05, 0.06)
const COLOR_VALVE_HOT_GLOW: Color = Color(1.0, 0.40, 0.10, 0.85)

const COLOR_STEAM_STREAK_HOT: Color = Color(1.0, 0.88, 0.62, 0.90)
const COLOR_STEAM_STREAK_NORMAL: Color = Color(0.96, 0.97, 1.0, 0.80)
const COLOR_STEAM_VAPOR_CORE: Color = Color(0.88, 0.92, 0.96)
const COLOR_STEAM_MIST: Color = Color(0.68, 0.74, 0.80)

# Robot & Radiator bounds
var robot_rect: Rect2 = Rect2(505.0, 65.0, 270.0, 542.0)
var radiator_rel_rect: Rect2 = Rect2(58.0, 185.0, 154.0, 180.0)

# Pre-allocated valve definitions
var valve_offsets: PackedVector2Array = PackedVector2Array()
var valve_dirs: PackedVector2Array = PackedVector2Array()
var valve_types: PackedInt32Array = PackedInt32Array() # 0 = Torso Flank, 1 = Shoulder, 2 = Neck, 3 = Sternum, 4 = Waist

# Thermal simulation state
var heat_ratio: float = 0.0
var target_heat_ratio: float = 0.0
var pulse_phase: float = 0.0
var pulse_frequency: float = 1.6
var overheat_surge: float = 0.0
var passive_puff_timer: float = 0.4
var active_particle_count: int = 0
var pool_cursor: int = 0
var acute_burst_accumulator: float = 0.0

# Pre-allocated particle pool for Zero GC
var p_pos: PackedVector2Array = PackedVector2Array()
var p_prev_pos: PackedVector2Array = PackedVector2Array()
var p_vel: PackedVector2Array = PackedVector2Array()
var p_life: PackedFloat32Array = PackedFloat32Array()
var p_max_life: PackedFloat32Array = PackedFloat32Array()
var p_radius_init: PackedFloat32Array = PackedFloat32Array()
var p_radius_max: PackedFloat32Array = PackedFloat32Array()
var p_curl_freq: PackedFloat32Array = PackedFloat32Array()
var p_curl_amp: PackedFloat32Array = PackedFloat32Array()
var p_age: PackedFloat32Array = PackedFloat32Array()
var p_kind: PackedInt32Array = PackedInt32Array()
var p_hot_core: Array[bool] = []

# Pre-allocated radiator slats geometry
var slat_y_offsets: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_init_valves()
	_init_particles()
	_init_slats()


func _init_valves() -> void:
	valve_offsets.resize(NUM_VALVES)
	valve_dirs.resize(NUM_VALVES)
	valve_types.resize(NUM_VALVES)

	# 0: Torso Left Flank exhaust vent
	valve_offsets[0] = Vector2(38.0, 235.0)
	valve_dirs[0] = Vector2(-0.88, -0.47).normalized()
	valve_types[0] = 0

	# 1: Torso Right Flank exhaust vent
	valve_offsets[1] = Vector2(232.0, 235.0)
	valve_dirs[1] = Vector2(0.88, -0.47).normalized()
	valve_types[1] = 0

	# 2: Left Shoulder Articulation Joint
	valve_offsets[2] = Vector2(28.0, 162.0)
	valve_dirs[2] = Vector2(-0.75, -0.66).normalized()
	valve_types[2] = 1

	# 3: Right Shoulder Articulation Joint
	valve_offsets[3] = Vector2(242.0, 162.0)
	valve_dirs[3] = Vector2(0.75, -0.66).normalized()
	valve_types[3] = 1

	# 4: Left Neck Articulation Joint
	valve_offsets[4] = Vector2(96.0, 138.0)
	valve_dirs[4] = Vector2(-0.45, -0.89).normalized()
	valve_types[4] = 2

	# 5: Right Neck Articulation Joint
	valve_offsets[5] = Vector2(174.0, 138.0)
	valve_dirs[5] = Vector2(0.45, -0.89).normalized()
	valve_types[5] = 2

	# 6: Sternum Decompression Slit Left
	valve_offsets[6] = Vector2(112.0, 208.0)
	valve_dirs[6] = Vector2(-0.25, -0.97).normalized()
	valve_types[6] = 3

	# 7: Sternum Decompression Slit Right
	valve_offsets[7] = Vector2(158.0, 208.0)
	valve_dirs[7] = Vector2(0.25, -0.97).normalized()
	valve_types[7] = 3

	# 8: Left Pelvis/Waist Articulation Joint
	valve_offsets[8] = Vector2(56.0, 385.0)
	valve_dirs[8] = Vector2(-0.82, 0.57).normalized()
	valve_types[8] = 4

	# 9: Right Pelvis/Waist Articulation Joint
	valve_offsets[9] = Vector2(214.0, 385.0)
	valve_dirs[9] = Vector2(0.82, 0.57).normalized()
	valve_types[9] = 4


func _init_particles() -> void:
	p_pos.resize(MAX_PARTICLES)
	p_prev_pos.resize(MAX_PARTICLES)
	p_vel.resize(MAX_PARTICLES)
	p_life.resize(MAX_PARTICLES)
	p_max_life.resize(MAX_PARTICLES)
	p_radius_init.resize(MAX_PARTICLES)
	p_radius_max.resize(MAX_PARTICLES)
	p_curl_freq.resize(MAX_PARTICLES)
	p_curl_amp.resize(MAX_PARTICLES)
	p_age.resize(MAX_PARTICLES)
	p_kind.resize(MAX_PARTICLES)
	p_hot_core.resize(MAX_PARTICLES)

	for i in MAX_PARTICLES:
		p_pos[i] = Vector2.ZERO
		p_prev_pos[i] = Vector2.ZERO
		p_vel[i] = Vector2.ZERO
		p_life[i] = 0.0
		p_max_life[i] = 0.5
		p_radius_init[i] = 1.0
		p_radius_max[i] = 8.0
		p_curl_freq[i] = 10.0
		p_curl_amp[i] = 15.0
		p_age[i] = 0.0
		p_kind[i] = PARTICLE_VAPOR
		p_hot_core[i] = false


func _init_slats() -> void:
	slat_y_offsets.resize(NUM_RADIATOR_SLATS)
	var step: float = radiator_rel_rect.size.y / float(NUM_RADIATOR_SLATS + 1)
	for i in NUM_RADIATOR_SLATS:
		slat_y_offsets[i] = (i + 1) * step


func configure(p_robot_rect: Rect2) -> void:
	robot_rect = p_robot_rect
	var w: float = robot_rect.size.x * 0.58
	var h: float = robot_rect.size.y * 0.33
	var x: float = (robot_rect.size.x - w) * 0.5
	var y: float = robot_rect.size.y * 0.34
	radiator_rel_rect = Rect2(x, y, w, h)
	_init_slats()


## Triggers an emergency high-pressure blow-off across all vent valves (e.g. on rag friction overheat).
func trigger_acute_overheat(intensity: float = 1.0) -> void:
	overheat_surge = minf(overheat_surge + clampf(0.5 + intensity * 0.06, 0.4, 1.0), 1.0)
	acute_burst_accumulator = 0.35

	# Fire pressurized steam micro-jets simultaneously from all vent valves
	for v_idx in NUM_VALVES:
		var v_pos: Vector2 = robot_rect.position + valve_offsets[v_idx]
		var v_dir: Vector2 = valve_dirs[v_idx]

		# 1-2 razor needle streaks
		var streak_speed: float = randf_range(280.0, 440.0) * (0.8 + 0.4 * intensity)
		_spawn_particle(
			v_pos,
			v_dir.rotated(randf_range(-0.08, 0.08)) * streak_speed,
			randf_range(0.18, 0.30),
			1.2,
			3.0,
			PARTICLE_STREAK,
			true
		)

		# 2-3 expanding turbulent vapor clouds
		for p_idx in 3:
			var puff_speed: float = randf_range(140.0, 260.0) * (0.8 + 0.3 * intensity)
			var spread: float = randf_range(-0.35, 0.35)
			_spawn_particle(
				v_pos + v_dir * randf_range(2.0, 8.0),
				v_dir.rotated(spread) * puff_speed,
				randf_range(0.45, 0.85),
				randf_range(1.5, 3.0),
				randf_range(9.0, 18.0),
				PARTICLE_VAPOR,
				randf() < 0.4
			)


## Convenience alias for trigger_acute_overheat
func trigger_acute_blowoff(intensity: float = 1.0) -> void:
	trigger_acute_overheat(intensity)


## Convenience alias for update_thermal
func update(delta: float, current_instability: float = 20.0, _thresh: float = 70.0, is_scrub_overheating: bool = false) -> void:
	update_thermal(delta, current_instability, is_scrub_overheating)


## Convenience combined render of radiator and steam jets
func render(canvas: CanvasItem, shift: Vector2 = Vector2.ZERO) -> void:
	render_radiator(canvas, shift)
	render_steam_jets(canvas, shift)



func _spawn_particle(
	pos: Vector2,
	vel: Vector2,
	max_life: float,
	rad_init: float,
	rad_max: float,
	kind: int,
	hot_core: bool
) -> void:
	var slot: int = -1

	# Find next available slot in circular buffer
	for step in MAX_PARTICLES:
		var idx: int = (pool_cursor + step) % MAX_PARTICLES
		if p_life[idx] <= 0.0:
			slot = idx
			pool_cursor = (idx + 1) % MAX_PARTICLES
			break

	if slot == -1:
		# Pool full, overwrite oldest slot
		slot = pool_cursor
		pool_cursor = (pool_cursor + 1) % MAX_PARTICLES

	p_pos[slot] = pos
	p_prev_pos[slot] = pos
	p_vel[slot] = vel
	p_life[slot] = max_life
	p_max_life[slot] = max_life
	p_radius_init[slot] = rad_init
	p_radius_max[slot] = rad_max
	p_curl_freq[slot] = randf_range(8.0, 16.0)
	p_curl_amp[slot] = randf_range(12.0, 28.0)
	p_age[slot] = 0.0
	p_kind[slot] = kind
	p_hot_core[slot] = hot_core


func update_thermal(delta: float, current_instability: float, is_scrub_overheating: bool = false) -> void:
	if delta <= 0.0:
		return

	# Instability normalization: 20% = baseline calm, 100% = max danger
	target_heat_ratio = clampf((current_instability - 20.0) / 80.0, 0.0, 1.0)
	heat_ratio = lerpf(heat_ratio, target_heat_ratio, delta * 3.5)

	# Overheat surge decay
	if overheat_surge > 0.0:
		overheat_surge = maxf(overheat_surge - delta * 0.85, 0.0)

	# Continuous friction overheat stimulation
	if is_scrub_overheating:
		overheat_surge = minf(overheat_surge + delta * 2.2, 1.0)

	# Pulse frequency scales non-linearly with heat: calm 1.4 rad/s -> critical 8.5 rad/s
	var effective_heat: float = clampf(heat_ratio + overheat_surge * 0.5, 0.0, 1.0)
	pulse_frequency = lerpf(1.4, 8.5, effective_heat)
	pulse_phase += delta * pulse_frequency
	if pulse_phase > TAU * 100.0:
		pulse_phase = fmod(pulse_phase, TAU)

	# Particle physics simulation (Zero GC)
	active_particle_count = 0
	for i in MAX_PARTICLES:
		if p_life[i] > 0.0:
			active_particle_count += 1
			p_life[i] -= delta
			p_age[i] += delta
			p_prev_pos[i] = p_pos[i]

			# Drag deceleration
			var drag: float = 3.6 if (p_kind[i] == PARTICLE_VAPOR) else 1.8
			p_vel[i] = p_vel[i] * maxf(1.0 - drag * delta, 0.0)

			# Thermal buoyancy (hot steam rises upwards)
			p_vel[i].y -= 45.0 * delta

			# Lateral sinusoidal turbulence
			var t_phase: float = p_age[i] * p_curl_freq[i]
			var lateral_drift: Vector2 = Vector2(-p_vel[i].y, p_vel[i].x).normalized() * sin(t_phase) * p_curl_amp[i] * delta
			p_pos[i] += p_vel[i] * delta + lateral_drift

	# Continuous passive pressure venting from valves
	if effective_heat > 0.12 or acute_burst_accumulator > 0.0:
		if acute_burst_accumulator > 0.0:
			acute_burst_accumulator = maxf(acute_burst_accumulator - delta, 0.0)

		passive_puff_timer -= delta
		var puff_interval: float = lerpf(0.55, 0.05, effective_heat)
		if is_scrub_overheating:
			puff_interval = 0.04

		if passive_puff_timer <= 0.0:
			passive_puff_timer = puff_interval + randf_range(-0.015, 0.015)
			_emit_passive_vent_puffs(effective_heat)


func _emit_passive_vent_puffs(heat_val: float) -> void:
	# Choose valves based on heat intensity
	var puffs_count: int = 1
	if heat_val > 0.40:
		puffs_count = 2
	if heat_val > 0.70:
		puffs_count = 3
	if heat_val > 0.88:
		puffs_count = 5

	for p in puffs_count:
		var v_idx: int = randi() % NUM_VALVES
		var v_pos: Vector2 = robot_rect.position + valve_offsets[v_idx]
		var v_dir: Vector2 = valve_dirs[v_idx]

		var speed: float = randf_range(130.0, 240.0) * (0.7 + 0.6 * heat_val)
		var is_streak: bool = (randf() < 0.35)

		if is_streak:
			_spawn_particle(
				v_pos,
				v_dir.rotated(randf_range(-0.06, 0.06)) * (speed * 1.4),
				randf_range(0.14, 0.24),
				1.0,
				2.5,
				PARTICLE_STREAK,
				heat_val > 0.75
			)
		else:
			_spawn_particle(
				v_pos,
				v_dir.rotated(randf_range(-0.25, 0.25)) * speed,
				randf_range(0.40, 0.75),
				randf_range(1.2, 2.2),
				randf_range(7.0, 14.0),
				PARTICLE_VAPOR,
				false
			)


## Renders the pulsing internal chassis radiator glow and heatsink cooling slats.
## Must be called during robot torso rendering.
func render_radiator(canvas: CanvasItem, shift: Vector2) -> void:
	var effective_heat: float = clampf(heat_ratio + overheat_surge * 0.55, 0.0, 1.0)
	if effective_heat <= 0.02:
		return

	var r_origin: Vector2 = robot_rect.position + shift
	var rad_rect: Rect2 = Rect2(r_origin + radiator_rel_rect.position, radiator_rel_rect.size)
	var rad_center: Vector2 = rad_rect.position + rad_rect.size * 0.5

	# Smooth pulsing rhythm with organic sub-harmonics
	var pulse_sin: float = sin(pulse_phase)
	var harmonic: float = sin(pulse_phase * 2.3 + 0.5) * 0.08
	var pulse_norm: float = clampf(0.70 + 0.30 * pulse_sin + harmonic, 0.45, 1.0)
	var glow_intensity: float = effective_heat * pulse_norm

	# 1. Multi-tier concentric volumetric warm halo behind/through chassis
	var halo_color_outer := Color(
		COLOR_RADIATOR_WARM.r,
		COLOR_RADIATOR_WARM.g,
		COLOR_RADIATOR_WARM.b,
		0.09 * glow_intensity
	)
	var halo_color_mid := Color(
		COLOR_RADIATOR_HOT.r,
		COLOR_RADIATOR_HOT.g,
		COLOR_RADIATOR_HOT.b,
		0.22 * glow_intensity
	)
	var halo_color_core := Color(
		COLOR_RADIATOR_INCANDESCENT.r,
		COLOR_RADIATOR_INCANDESCENT.g,
		COLOR_RADIATOR_INCANDESCENT.b,
		0.45 * glow_intensity
	)

	# Soft ambient bloom
	canvas.draw_circle(rad_center, rad_rect.size.x * 0.85, halo_color_outer)
	canvas.draw_circle(rad_center, rad_rect.size.x * 0.52, halo_color_mid)
	canvas.draw_circle(rad_center, rad_rect.size.x * 0.28, halo_color_core)

	# 2. Recessed radiator bay backplate
	var bay_bg := Color(0.04, 0.05, 0.06, 0.65 * effective_heat)
	canvas.draw_rect(rad_rect, bay_bg)
	var bay_border := Color(
		COLOR_RADIATOR_HOT.r,
		COLOR_RADIATOR_HOT.g,
		COLOR_RADIATOR_HOT.b,
		0.35 * glow_intensity
	)
	canvas.draw_rect(rad_rect, bay_border, false, 1.5)

	# 3. Horizontal radiator heatsink cooling slats / fins
	var slat_w: float = rad_rect.size.x - 16.0
	var slat_x: float = rad_rect.position.x + 8.0

	var slat_cold := Color(0.18, 0.14, 0.12, 0.6)
	var slat_hot := COLOR_RADIATOR_HOT.lerp(COLOR_RADIATOR_INCANDESCENT, effective_heat)
	var slat_glow_col := slat_cold.lerp(slat_hot, effective_heat * pulse_norm)

	for i in NUM_RADIATOR_SLATS:
		var s_y: float = rad_rect.position.y + slat_y_offsets[i]
		var slat_rect := Rect2(slat_x, s_y - 2.5, slat_w, 5.0)

		# Recessed groove
		canvas.draw_rect(slat_rect.grow(1.0), Color(0.02, 0.03, 0.04, 0.8))

		# Glowing slat core
		canvas.draw_rect(slat_rect, slat_glow_col)

		# Intense incandescent filament line along slat center
		if effective_heat > 0.35:
			var filament_col := Color(
				COLOR_RADIATOR_INCANDESCENT.r,
				COLOR_RADIATOR_INCANDESCENT.g,
				COLOR_RADIATOR_INCANDESCENT.b,
				0.65 * glow_intensity
			)
			canvas.draw_line(
				Vector2(slat_x + 8.0, s_y),
				Vector2(slat_x + slat_w - 8.0, s_y),
				filament_col,
				1.5
			)

	# 4. Thermal seam bleeding: incandescent slits leaking through chassis armor seams
	var seam_alpha: float = 0.55 * glow_intensity
	var seam_col := Color(COLOR_RADIATOR_HOT.r, COLOR_RADIATOR_HOT.g, COLOR_RADIATOR_HOT.b, seam_alpha)

	# Left & right chassis armor vertical ventilation louvers
	var l_seam_x: float = rad_rect.position.x - 8.0
	var r_seam_x: float = rad_rect.end.x + 8.0
	canvas.draw_line(Vector2(l_seam_x, rad_rect.position.y + 10.0), Vector2(l_seam_x, rad_rect.end.y - 10.0), seam_col, 2.0)
	canvas.draw_line(Vector2(r_seam_x, rad_rect.position.y + 10.0), Vector2(r_seam_x, rad_rect.end.y - 10.0), seam_col, 2.0)


## Renders the procedural micro-jets of steam and smoke venting from valves and joints.
## Must be called after robot body rendering so steam plumes drift in front of the chassis.
func render_steam_jets(canvas: CanvasItem, shift: Vector2) -> void:
	var r_origin: Vector2 = robot_rect.position + shift
	var effective_heat: float = clampf(heat_ratio + overheat_surge * 0.55, 0.0, 1.0)

	# 1. Render physical valve nozzles on the chassis
	for v_idx in NUM_VALVES:
		var v_pos: Vector2 = r_origin + valve_offsets[v_idx]
		var v_dir: Vector2 = valve_dirs[v_idx]

		# Outer metallic collar
		canvas.draw_circle(v_pos, 3.5, COLOR_VALVE_METAL)
		# Deep orifice slot
		canvas.draw_circle(v_pos, 2.0, COLOR_VALVE_ORIFICE)

		# When hot, valve nozzle rim glows with thermal emission
		if effective_heat > 0.25:
			var rim_glow := Color(
				COLOR_VALVE_HOT_GLOW.r,
				COLOR_VALVE_HOT_GLOW.g,
				COLOR_VALVE_HOT_GLOW.b,
				(effective_heat - 0.25) * 1.33 * (0.6 + 0.4 * sin(pulse_phase + v_idx))
			)
			canvas.draw_circle(v_pos, 1.5, rim_glow)

		# Tiny pressure nozzle slit line
		var normal := Vector2(-v_dir.y, v_dir.x)
		canvas.draw_line(v_pos - normal * 2.5, v_pos + normal * 2.5, COLOR_VALVE_ORIFICE, 1.0)

	# 2. Render all active particles from pool (Zero GC)
	for i in MAX_PARTICLES:
		if p_life[i] <= 0.0:
			continue

		var life_ratio: float = p_life[i] / p_max_life[i] # 1.0 (newborn) -> 0.0 (dead)
		var age_ratio: float = 1.0 - life_ratio           # 0.0 (newborn) -> 1.0 (dead)

		# Smooth alpha envelope: fast attack, sustained dissipation fade
		var alpha: float = sin(life_ratio * PI * 0.5) * life_ratio

		if p_kind[i] == PARTICLE_STREAK:
			# High-pressure razor needle streak at nozzle
			var streak_col: Color = COLOR_STEAM_STREAK_HOT if p_hot_core[i] else COLOR_STEAM_STREAK_NORMAL
			streak_col.a = alpha * 0.95
			var cur_pos: Vector2 = p_pos[i] + shift
			var old_pos: Vector2 = p_prev_pos[i] + shift
			canvas.draw_line(cur_pos, old_pos, streak_col, 2.0)
			# Sharp leading tip
			canvas.draw_circle(cur_pos, 1.2, streak_col)
		else:
			# Expanding condensation vapor puff
			var rad: float = lerpf(p_radius_init[i], p_radius_max[i], sqrt(age_ratio))
			var vapor_col: Color = COLOR_STEAM_VAPOR_CORE.lerp(COLOR_STEAM_MIST, age_ratio)
			vapor_col.a = alpha * 0.48

			var cur_pos: Vector2 = p_pos[i] + shift

			# Soft dual-pass puff: denser core + soft diffuse vapor halo
			canvas.draw_circle(cur_pos, rad, vapor_col)
			if rad > 3.0:
				var inner_core_col := Color(1.0, 1.0, 1.0, alpha * 0.35)
				canvas.draw_circle(cur_pos, rad * 0.45, inner_core_col)


func get_active_particles_count() -> int:
	var count: int = 0
	for i in MAX_PARTICLES:
		if p_life[i] > 0.0:
			count += 1
	return count


func get_heat_ratio() -> float:
	return heat_ratio


func get_overheat_surge() -> float:
	return overheat_surge
