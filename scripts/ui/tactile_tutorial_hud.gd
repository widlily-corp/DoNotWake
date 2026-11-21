class_name TactileTutorialHUD
extends Node2D

## Tactile Tutorial and Affordance HUD (Do Not Wake)
## Provides live visual guidance, diegetic affordances, animated prompts,
## holographic target brackets, and real-time tactile feedback for all repair stages.

# Palette colors matching project standard
const COLOR_CYAN: Color = Color(0.35, 0.85, 0.95)
const COLOR_CYAN_DIM: Color = Color(0.376, 0.627, 0.753) # #60A0C0
const COLOR_GREEN_LIME: Color = Color(0.314, 0.878, 0.439) # #50E070
const COLOR_GREEN_SUCCESS: Color = Color(0.35, 0.92, 0.58)
const COLOR_RED_ALERT: Color = Color(0.902, 0.157, 0.082) # #E62815
const COLOR_BG_PANEL: Color = Color(0.04, 0.06, 0.09, 0.88)
const COLOR_BORDER_SUBTLE: Color = Color(0.25, 0.35, 0.45, 0.60)
const COLOR_TEXT_LIGHT: Color = Color(0.92, 0.95, 0.98)
const COLOR_TEXT_MUTED: Color = Color(0.55, 0.65, 0.72)
const COLOR_AMBER: Color = Color(0.96, 0.75, 0.25)

# Strict Safe Area screen boundaries (1280x720 canvas: x in [20, 1260], y in [20, 700])
const SAFE_MIN_X: float = 20.0
const SAFE_MAX_X: float = 1260.0
const SAFE_MIN_Y: float = 20.0
const SAFE_MAX_Y: float = 700.0
const SAFE_RECT: Rect2 = Rect2(SAFE_MIN_X, SAFE_MIN_Y, SAFE_MAX_X - SAFE_MIN_X, SAFE_MAX_Y - SAFE_MIN_Y)

const MAX_SPARKLES: int = 16

# Animation timers and state
var anim_time: float = 0.0
var flash_timer: float = 0.0

# Current frame cache (from update_hud)
var current_stage_index: int = 0
var held_tool_id: String = ""
var mouse_pos: Vector2 = Vector2.ZERO
var mid_shift: Vector2 = Vector2.ZERO

var scrub_zone_ref: ScrubZone = null
var screw_manager_ref: ScrewBoltManager = null
var cable_plug_ref: CablePlug = null

# Tray slot positions (from robot.json / workbench layout)
var tray_cloth_pos: Vector2 = Vector2(220.0, 645.0)
var tray_screw_pos: Vector2 = Vector2(450.0, 640.0)
var tray_cable_pos: Vector2 = Vector2(1030.0, 640.0)

# Sparkle particles for optimal scrubbing velocity
var sparkle_pos: PackedVector2Array = PackedVector2Array()
var sparkle_vel: PackedVector2Array = PackedVector2Array()
var sparkle_life: PackedFloat32Array = PackedFloat32Array()
var sparkle_max_life: PackedFloat32Array = PackedFloat32Array()
var sparkle_color: PackedColorArray = PackedColorArray()

# Pre-allocated arrays and strings for zero-GC drawing
var _pts_arrow: PackedVector2Array = PackedVector2Array()
var _pts_poly: PackedVector2Array = PackedVector2Array()
var _clean_pct_strings: Array[String] = []


func _init() -> void:
	sparkle_pos.resize(MAX_SPARKLES)
	sparkle_vel.resize(MAX_SPARKLES)
	sparkle_life.resize(MAX_SPARKLES)
	sparkle_max_life.resize(MAX_SPARKLES)
	sparkle_color.resize(MAX_SPARKLES)
	for i in MAX_SPARKLES:
		sparkle_pos[i] = Vector2.ZERO
		sparkle_vel[i] = Vector2.ZERO
		sparkle_life[i] = 0.0
		sparkle_max_life[i] = 0.0
		sparkle_color[i] = COLOR_GREEN_LIME

	_pts_arrow.resize(3)
	_pts_poly.resize(4)

	_clean_pct_strings.resize(101)
	for i in 101:
		_clean_pct_strings[i] = "ОЧИСТКА: %d%%" % i


func update_hud(
	delta: float,
	p_current_stage_index: int,
	p_held_tool_id: String,
	p_mouse_pos: Vector2,
	p_mid_shift: Vector2,
	scrub_zone: ScrubZone,
	screw_manager: ScrewBoltManager,
	cable_plug: CablePlug
) -> void:
	anim_time += delta
	current_stage_index = p_current_stage_index
	held_tool_id = p_held_tool_id
	mouse_pos = p_mouse_pos
	mid_shift = p_mid_shift
	scrub_zone_ref = scrub_zone
	screw_manager_ref = screw_manager
	cable_plug_ref = cable_plug

	if flash_timer > 0.0:
		flash_timer = maxf(flash_timer - delta, 0.0)

	_update_sparkles(delta)

	# In Stage 1, spawn sparkles when scrubbing in optimal zone
	if current_stage_index == 0 and scrub_zone != null and held_tool_id == "cloth":
		var spd := scrub_zone.current_speed
		if spd >= scrub_zone.safe_speed_min and spd <= scrub_zone.safe_speed_max:
			if randf() < 0.45:
				var spawn_p := mouse_pos + Vector2(randf_range(-25.0, 25.0), randf_range(-65.0, -45.0))
				_spawn_sparkle(spawn_p, COLOR_GREEN_LIME)

	if is_inside_tree():
		queue_redraw()


func _draw() -> void:
	render(self, ThemeDB.fallback_font)


func render(canvas: CanvasItem, font: Font) -> void:
	if canvas == null:
		return
	var eff_font: Font = font if font != null else ThemeDB.fallback_font

	match current_stage_index:
		0:
			_render_stage_1_cloth(canvas, eff_font)
		1:
			_render_stage_2_screwdriver(canvas, eff_font)
		2:
			_render_stage_3_cable(canvas, eff_font)

	_render_sparkles(canvas)


# ==============================================================================
# STAGE 1: ТАКТИЛЬНАЯ ЧИСТКА ВЕТОШЬЮ
# ==============================================================================

func _render_stage_1_cloth(canvas: CanvasItem, font: Font) -> void:
	var is_cloth_held := (held_tool_id == "cloth")

	# Step A: When cloth is idle in tray
	if not is_cloth_held:
		var bounce := sin(anim_time * 5.0) * 8.0
		var arrow_tip := Vector2(tray_cloth_pos.x, tray_cloth_pos.y - 45.0 + bounce)
		var pulse_glow := 0.75 + 0.25 * sin(anim_time * 6.0)
		var arrow_col := Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, pulse_glow)

		_draw_bounce_arrow_down(canvas, arrow_tip, 24.0, arrow_col)
		var badge_pos := Vector2(tray_cloth_pos.x, tray_cloth_pos.y - 82.0 + bounce)
		_draw_hud_badge(canvas, font, badge_pos, "[ 1. ЗАЖМИТЕ ЛКМ И ПОТЯНИТЕ ВЕТОШЬ К ГРУДИ ]", arrow_col, COLOR_TEXT_LIGHT, 10)

	# Step B: Target zone on robot (contact area)
	var zone_rect := Rect2(Vector2(570.0, 250.0) + mid_shift, Vector2(140.0, 60.0))
	if scrub_zone_ref != null:
		zone_rect = Rect2(scrub_zone_ref.zone_rect.position + mid_shift, scrub_zone_ref.zone_rect.size)

	var is_completed := (scrub_zone_ref != null and scrub_zone_ref.is_completed)
	if not is_completed:
		var bracket_pulse := 0.65 + 0.35 * sin(anim_time * 4.0)
		var bracket_col := Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, bracket_pulse)
		if is_cloth_held:
			bracket_col = Color(COLOR_GREEN_LIME.r, COLOR_GREEN_LIME.g, COLOR_GREEN_LIME.b, bracket_pulse)

		_draw_corner_brackets(canvas, zone_rect.grow(6.0), 14.0, bracket_col, 2.0)

		# Label for target zone
		if not is_cloth_held:
			var target_label_pos := Vector2(zone_rect.get_center().x, zone_rect.position.y - 18.0)
			_draw_hud_badge(canvas, font, target_label_pos, "[ 2. ЗОНА НАГАРА // ТРИТЕ ГОРИЗОНТАЛЬНО ]", Color(COLOR_CYAN_DIM.r, COLOR_CYAN_DIM.g, COLOR_CYAN_DIM.b, 0.8), COLOR_TEXT_MUTED, 9)

	# Step C: Dynamic floating tactile speedometer HUD hovering directly above cloth / tool tip
	if is_cloth_held and not is_completed:
		_render_scrub_speedometer(canvas, font, mouse_pos)


func _render_scrub_speedometer(canvas: CanvasItem, font: Font, target_pos: Vector2) -> void:
	var hud_center := Vector2(target_pos.x, target_pos.y - 78.0)
	hud_center.x = clampf(hud_center.x, 160.0, 1120.0)
	hud_center.y = clampf(hud_center.y, 80.0, 640.0)

	var panel_w := 300.0
	var panel_h := 72.0
	var panel_r := Rect2(hud_center.x - panel_w * 0.5, hud_center.y - panel_h * 0.5, panel_w, panel_h)

	# Panel plate and holographic corners
	canvas.draw_rect(panel_r, COLOR_BG_PANEL)
	canvas.draw_rect(panel_r, COLOR_BORDER_SUBTLE, false, 1.0)
	_draw_corner_brackets(canvas, panel_r, 6.0, COLOR_CYAN, 1.5)

	# 1. Horizontal scrubbing movement prompt with animated arrows
	var guide_txt := "[ ◀ ── ТРИТЕ ВПРАВО-ВЛЕВО ── ▶ ]"
	_draw_centered_string(canvas, font, Vector2(hud_center.x, panel_r.position.y + 12.0), guide_txt, 9, COLOR_TEXT_LIGHT)

	# 2. Horizontal speed gauge bar
	var bar_w := 260.0
	var bar_h := 8.0
	var bar_x := hud_center.x - bar_w * 0.5
	var bar_y := panel_r.position.y + 24.0
	var bar_rect := Rect2(bar_x, bar_y, bar_w, bar_h)

	canvas.draw_rect(bar_rect, Color(0.06, 0.08, 0.11, 0.95))

	var safe_min := scrub_zone_ref.safe_speed_min if scrub_zone_ref else 80.0
	var safe_max := scrub_zone_ref.safe_speed_max if scrub_zone_ref else 650.0
	const MAX_METER_SPEED: float = 900.0

	var w_slow := bar_w * (safe_min / MAX_METER_SPEED)
	var w_opt := bar_w * ((safe_max - safe_min) / MAX_METER_SPEED)
	var w_fast := bar_w - w_slow - w_opt

	# Low speed zone (dim cyan)
	canvas.draw_rect(Rect2(bar_x, bar_y, w_slow, bar_h), Color(COLOR_CYAN_DIM.r, COLOR_CYAN_DIM.g, COLOR_CYAN_DIM.b, 0.40))
	# Optimal zone (lime green)
	canvas.draw_rect(Rect2(bar_x + w_slow, bar_y, w_opt, bar_h), Color(COLOR_GREEN_LIME.r, COLOR_GREEN_LIME.g, COLOR_GREEN_LIME.b, 0.65))
	# Overheat danger zone (alert red)
	canvas.draw_rect(Rect2(bar_x + w_slow + w_opt, bar_y, w_fast, bar_h), Color(COLOR_RED_ALERT.r, COLOR_RED_ALERT.g, COLOR_RED_ALERT.b, 0.65))

	# Boundary tick lines
	canvas.draw_line(Vector2(bar_x + w_slow, bar_y - 2.0), Vector2(bar_x + w_slow, bar_y + bar_h + 2.0), Color.WHITE, 1.2)
	canvas.draw_line(Vector2(bar_x + w_slow + w_opt, bar_y - 2.0), Vector2(bar_x + w_slow + w_opt, bar_y + bar_h + 2.0), Color.WHITE, 1.2)
	canvas.draw_rect(bar_rect, COLOR_BORDER_SUBTLE, false, 1.0)

	# Needle indicator
	var cur_speed := scrub_zone_ref.current_speed if scrub_zone_ref else 0.0
	var speed_t := clampf(cur_speed / MAX_METER_SPEED, 0.0, 1.0)
	var needle_x := bar_x + bar_w * speed_t

	var status_text := ""
	var status_col := COLOR_CYAN_DIM

	if cur_speed < safe_min:
		status_text = "[ ТЕМП НИЗКИЙ: УСКОРЬТЕСЬ ]"
		status_col = COLOR_CYAN_DIM
	elif cur_speed <= safe_max:
		status_text = "[ ОПТИМАЛЬНО: ИДЁТ ЧИСТКА ]"
		status_col = COLOR_GREEN_LIME
	else:
		status_text = "[ ⚠ ПЕРЕГРЕВ! СНИЗЬТЕ ТЕМП! ]"
		var flash := 0.6 + 0.4 * sin(anim_time * 24.0)
		status_col = Color(COLOR_RED_ALERT.r, COLOR_RED_ALERT.g, COLOR_RED_ALERT.b, flash)

	# Draw needle cursor
	canvas.draw_line(Vector2(needle_x, bar_y - 3.0), Vector2(needle_x, bar_y + bar_h + 3.0), status_col, 2.5)
	_pts_arrow[0] = Vector2(needle_x - 3.0, bar_y - 6.0)
	_pts_arrow[1] = Vector2(needle_x + 3.0, bar_y - 6.0)
	_pts_arrow[2] = Vector2(needle_x, bar_y - 1.0)
	canvas.draw_colored_polygon(_pts_arrow, status_col)

	# 3. Status badge based on speed
	_draw_centered_string(canvas, font, Vector2(hud_center.x, panel_r.position.y + 44.0), status_text, 9, status_col)

	# 4. Live progress counter: ОЧИСТКА: %d%%
	var prog := scrub_zone_ref.clean_progress if scrub_zone_ref else 0.0
	var prog_pct := clampi(int(prog * 100.0), 0, 100)
	var prog_text := _clean_pct_strings[prog_pct]
	_draw_centered_string(canvas, font, Vector2(hud_center.x, panel_r.position.y + 58.0), prog_text, 10, COLOR_GREEN_SUCCESS)


# ==============================================================================
# STAGE 2: ДЕМОНТАЖ БРОНЕЛЮКА ОТВЁРТКОЙ
# ==============================================================================

func _render_stage_2_screwdriver(canvas: CanvasItem, font: Font) -> void:
	var is_screw_held := (held_tool_id == "screwdriver")
	var remaining_bolts := screw_manager_ref.get_remaining_bolts_count() if screw_manager_ref else 4
	var is_hatch_off := (screw_manager_ref != null and screw_manager_ref.is_hatch_removed)

	# Step A: Pulsing arrow over screwdriver tray slot
	if not is_screw_held and not is_hatch_off:
		var bounce := sin(anim_time * 5.0) * 8.0
		var arrow_tip := Vector2(tray_screw_pos.x, tray_screw_pos.y - 45.0 + bounce)
		var pulse_glow := 0.75 + 0.25 * sin(anim_time * 6.0)
		var arrow_col := Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, pulse_glow)

		_draw_bounce_arrow_down(canvas, arrow_tip, 24.0, arrow_col)
		var badge_pos := Vector2(tray_screw_pos.x, tray_screw_pos.y - 82.0 + bounce)
		_draw_hud_badge(canvas, font, badge_pos, "[ 1. ВОЗЬМИТЕ ОТВЁРТКУ ]", arrow_col, COLOR_TEXT_LIGHT, 10)

	# Step B: Around active bolt (circular holographic reticle + rotating CCW arrow)
	if remaining_bolts > 0 and not is_hatch_off:
		var target_bolt = null
		if screw_manager_ref != null:
			if screw_manager_ref.active_bolt != null:
				target_bolt = screw_manager_ref.active_bolt
			else:
				for b in screw_manager_ref.bolts:
					if not b.is_loose:
						target_bolt = b
						break

		if target_bolt != null:
			var bolt_p: Vector2 = target_bolt.base_pos + mid_shift
			_render_active_bolt_hud(canvas, font, target_bolt, bolt_p, is_screw_held)

	# Step C: When all 4 bolts are loosened: glowing release latches on hatch + animated rightward sliding arrow
	if remaining_bolts == 0 and not is_hatch_off:
		var hatch_r := Rect2(Vector2(550.0, 320.0) + mid_shift, Vector2(180.0, 120.0))
		if screw_manager_ref != null:
			hatch_r = Rect2(screw_manager_ref.hatch_rect.position + mid_shift + screw_manager_ref.hatch_offset, screw_manager_ref.hatch_rect.size)

		var latch_pulse := 0.70 + 0.30 * sin(anim_time * 6.0)
		var latch_col := Color(COLOR_GREEN_SUCCESS.r, COLOR_GREEN_SUCCESS.g, COLOR_GREEN_SUCCESS.b, latch_pulse)

		# Glowing green release latches on all 4 corners
		_draw_corner_brackets(canvas, hatch_r.grow(6.0), 20.0, latch_col, 3.0)

		# Animated rightward sliding arrow across hatch center
		var h_center := hatch_r.get_center()
		_draw_slide_arrow_right(canvas, h_center - Vector2(30.0, 0.0), 75.0, latch_col)

		# Prompt badge
		var badge_pos := Vector2(h_center.x, hatch_r.position.y - 20.0)
		_draw_hud_badge(canvas, font, badge_pos, "[ 3. ЗАХВАТИТЕ ЛЮК И СДВИНЬТЕ В СТОРОНУ ]", latch_col, COLOR_TEXT_LIGHT, 10)


func _render_active_bolt_hud(canvas: CanvasItem, font: Font, bolt, bolt_p: Vector2, is_tool_held: bool) -> void:
	# Circular holographic reticle
	var pulse := 0.75 + 0.25 * sin(anim_time * 5.0)
	var reticle_col := Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, pulse)
	if is_tool_held:
		reticle_col = Color(COLOR_GREEN_LIME.r, COLOR_GREEN_LIME.g, COLOR_GREEN_LIME.b, pulse)

	canvas.draw_arc(bolt_p, 20.0, 0.0, TAU, 28, Color(reticle_col.r, reticle_col.g, reticle_col.b, 0.4), 1.0, true)

	# Radial progress arc around active bolt (0% -> 100%)
	var req_rad: float = maxf(bolt.turns_required * TAU, 0.001)
	var turn_pct: float = clampf(bolt.accumulated_rad / req_rad, 0.0, 1.0)
	var sweep_angle := -turn_pct * TAU
	if absf(sweep_angle) > 0.05:
		canvas.draw_arc(bolt_p, 23.0, -PI * 0.5, -PI * 0.5 + sweep_angle, 28, COLOR_GREEN_SUCCESS, 3.0, true)

	# Rotating counter-clockwise arrow
	var rot := -anim_time * 3.5
	_draw_circular_ccw_arrow(canvas, bolt_p, 31.0, rot, reticle_col)

	# Instruction badge
	var badge_pos := Vector2(bolt_p.x, bolt_p.y - 48.0)
	_draw_hud_badge(canvas, font, badge_pos, "[ 2. ВРАЩАЙТЕ МЫШЬ ПО КРУГУ ПРОТИВ ЧАСОВОЙ ]", reticle_col, COLOR_TEXT_LIGHT, 9)

	# Slip risk radius guard indicator when actively engaged
	if screw_manager_ref != null and screw_manager_ref.active_bolt == bolt:
		var slip_r := screw_manager_ref.slip_radius
		canvas.draw_arc(bolt_p, slip_r, 0.0, TAU, 32, Color(COLOR_RED_ALERT.r, COLOR_RED_ALERT.g, COLOR_RED_ALERT.b, 0.35), 1.0, true)


# ==============================================================================
# STAGE 3: ПУПОВИННЫЙ КАБЕЛЬ
# ==============================================================================

func _render_stage_3_cable(canvas: CanvasItem, font: Font) -> void:
	if cable_plug_ref == null:
		return

	var is_dragged: bool = cable_plug_ref.is_dragged
	var is_locked: bool = cable_plug_ref.is_locked
	var is_near: bool = cable_plug_ref.is_near_socket
	var socket_p: Vector2 = cable_plug_ref.socket_pos + mid_shift
	var plug_p: Vector2 = cable_plug_ref.current_plug_pos

	# Step A: Arrow over cable plug when idle
	if not is_dragged and not is_locked:
		var bounce := sin(anim_time * 5.0) * 8.0
		var arrow_tip := Vector2(plug_p.x, plug_p.y - 36.0 + bounce)
		var pulse_glow := 0.75 + 0.25 * sin(anim_time * 6.0)
		var arrow_col := Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, pulse_glow)

		_draw_bounce_arrow_down(canvas, arrow_tip, 24.0, arrow_col)
		var badge_pos := Vector2(plug_p.x, plug_p.y - 74.0 + bounce)
		_draw_hud_badge(canvas, font, badge_pos, "[ 1. ЗАХВАТИТЕ ШТЕКЕР ]", arrow_col, COLOR_TEXT_LIGHT, 10)

	# Step B: Magnetic crosshair over head temple port when plug is dragged
	if is_dragged and not is_locked:
		var cross_pulse := 0.70 + 0.30 * sin(anim_time * 6.0)
		var cross_col := Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, cross_pulse)

		# Concentric holographic crosshair rings
		canvas.draw_arc(socket_p, 28.0, 0.0, TAU, 32, cross_col, 2.0, true)
		canvas.draw_arc(socket_p, 40.0, 0.0, TAU, 32, Color(cross_col.r, cross_col.g, cross_col.b, 0.35), 1.0, true)

		# Crosshair tick marks
		canvas.draw_line(socket_p - Vector2(46.0, 0.0), socket_p - Vector2(16.0, 0.0), cross_col, 2.0)
		canvas.draw_line(socket_p + Vector2(16.0, 0.0), socket_p + Vector2(46.0, 0.0), cross_col, 2.0)
		canvas.draw_line(socket_p - Vector2(0.0, 46.0), socket_p - Vector2(0.0, 16.0), cross_col, 2.0)
		canvas.draw_line(socket_p + Vector2(0.0, 16.0), socket_p + Vector2(0.0, 46.0), cross_col, 2.0)

		# Guideline trajectory connecting plug to socket
		_draw_dashed_line(canvas, plug_p, socket_p, Color(COLOR_CYAN.r, COLOR_CYAN.g, COLOR_CYAN.b, 0.5), 10.0, 6.0)

		# Target badge over head port
		var socket_badge_pos := Vector2(socket_p.x, socket_p.y - 58.0)
		_draw_hud_badge(canvas, font, socket_badge_pos, "[ 2. ВСТАВЬТЕ В ПОРТ ГОЛОВЫ ]", cross_col, COLOR_TEXT_LIGHT, 10)

	# Step C: Alignment notch and hold timer
	if (is_near or is_locked) and not is_locked:
		var angle_err: float = absf(wrapf(cable_plug_ref.plug_angle - 90.0, -180.0, 180.0))
		var is_aligned := (angle_err <= 18.0)

		# Notch dial indicator
		var dial_center := socket_p + Vector2(0.0, 64.0)
		canvas.draw_circle(dial_center, 18.0, COLOR_BG_PANEL)
		canvas.draw_arc(dial_center, 18.0, 0.0, TAU, 24, COLOR_BORDER_SUBTLE, 1.5, true)

		# Target notch at 12 o'clock (green)
		canvas.draw_line(dial_center, dial_center - Vector2(0.0, 16.0), COLOR_GREEN_SUCCESS, 2.5)

		# Current plug angle notch
		var cur_rad := deg_to_rad(cable_plug_ref.plug_angle - 90.0 - 90.0)
		var notch_p := dial_center + Vector2(cos(cur_rad), sin(cur_rad)) * 14.0
		var notch_col := COLOR_GREEN_LIME if is_aligned else COLOR_AMBER
		canvas.draw_line(dial_center, notch_p, notch_col, 2.0)

		var badge_y := socket_p.y + 44.0
		if is_aligned:
			_draw_hud_badge(canvas, font, Vector2(socket_p.x, badge_y), "[ 3. УДЕРЖИВАЙТЕ ДЛЯ ФИКСАЦИИ ]", COLOR_GREEN_SUCCESS, COLOR_TEXT_LIGHT, 10)
		else:
			_draw_hud_badge(canvas, font, Vector2(socket_p.x, badge_y), "[ КОЛЁСИКО МЫШИ: ВЫРАВНЯЙТЕ ПАЗ ]", COLOR_AMBER, COLOR_TEXT_LIGHT, 9)

	elif is_locked:
		var badge_pos := Vector2(socket_p.x, socket_p.y + 44.0)
		_draw_hud_badge(canvas, font, badge_pos, "[ ✔ ПУПОВИННЫЙ КАБЕЛЬ ЗАФИКСИРОВАН ]", COLOR_GREEN_SUCCESS, COLOR_TEXT_LIGHT, 10)


# ==============================================================================
# DRAWING UTILITIES (Zero-GC)
# ==============================================================================

func _draw_bounce_arrow_down(canvas: CanvasItem, tip: Vector2, length: float, col: Color) -> void:
	var top := tip - Vector2(0.0, length)
	canvas.draw_line(top, tip, col, 2.5)

	# Main arrowhead
	_pts_arrow[0] = tip + Vector2(-8.0, -9.0)
	_pts_arrow[1] = tip
	_pts_arrow[2] = tip + Vector2(8.0, -9.0)
	canvas.draw_polyline(_pts_arrow, col, 2.5)

	# Trailing secondary chevron
	_pts_arrow[0] = tip + Vector2(-6.0, -16.0)
	_pts_arrow[1] = tip + Vector2(0.0, -8.0)
	_pts_arrow[2] = tip + Vector2(6.0, -16.0)
	canvas.draw_polyline(_pts_arrow, Color(col.r, col.g, col.b, 0.45), 1.5)


func _draw_slide_arrow_right(canvas: CanvasItem, start_pos: Vector2, total_len: float, col: Color) -> void:
	var phase := fmod(anim_time * 55.0, 24.0)
	for i in 3:
		var x_off := float(i) * 20.0 + phase
		if x_off <= total_len:
			var tip := start_pos + Vector2(x_off, 0.0)
			_pts_arrow[0] = tip + Vector2(-8.0, -7.0)
			_pts_arrow[1] = tip
			_pts_arrow[2] = tip + Vector2(-8.0, 7.0)
			var a := clampf(1.0 - (x_off / total_len), 0.25, 1.0)
			canvas.draw_polyline(_pts_arrow, Color(col.r, col.g, col.b, a), 2.5)


func _draw_corner_brackets(canvas: CanvasItem, rect: Rect2, bracket_len: float, col: Color, width: float = 2.0) -> void:
	# Top-left
	canvas.draw_line(Vector2(rect.position.x, rect.position.y + bracket_len), rect.position, col, width)
	canvas.draw_line(rect.position, Vector2(rect.position.x + bracket_len, rect.position.y), col, width)
	# Top-right
	canvas.draw_line(Vector2(rect.end.x - bracket_len, rect.position.y), Vector2(rect.end.x, rect.position.y), col, width)
	canvas.draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + bracket_len), col, width)
	# Bottom-left
	canvas.draw_line(Vector2(rect.position.x, rect.end.y - bracket_len), Vector2(rect.position.x, rect.end.y), col, width)
	canvas.draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x + bracket_len, rect.end.y), col, width)
	# Bottom-right
	canvas.draw_line(Vector2(rect.end.x - bracket_len, rect.end.y), rect.end, col, width)
	canvas.draw_line(rect.end, Vector2(rect.end.x, rect.end.y - bracket_len), col, width)


func _draw_circular_ccw_arrow(canvas: CanvasItem, center: Vector2, radius: float, current_rot: float, col: Color) -> void:
	var sweep := -PI * 1.25
	canvas.draw_arc(center, radius, current_rot, current_rot + sweep, 24, col, 2.0, true)

	var head_ang := current_rot + sweep
	var tip := center + Vector2(cos(head_ang), sin(head_ang)) * radius
	var tangent := Vector2(sin(head_ang), -cos(head_ang))
	var normal := Vector2(cos(head_ang), sin(head_ang))

	_pts_arrow[0] = tip - tangent * 8.0 + normal * 6.0
	_pts_arrow[1] = tip
	_pts_arrow[2] = tip - tangent * 8.0 - normal * 6.0
	canvas.draw_polyline(_pts_arrow, col, 2.5)


func _draw_dashed_line(canvas: CanvasItem, from: Vector2, to: Vector2, col: Color, dash_len: float = 8.0, gap_len: float = 6.0) -> void:
	var diff := to - from
	var dist := diff.length()
	if dist < 1.0:
		return
	var dir := diff / dist
	var step := dash_len + gap_len
	var cur := fmod(anim_time * 35.0, step)
	while cur < dist:
		var d_end := minf(cur + dash_len, dist)
		if d_end > cur:
			canvas.draw_line(from + dir * cur, from + dir * d_end, col, 1.5)
		cur += step


## Вычисляет ограниченный безопасной зоной ([20, 1260], [20, 700]) прямоугольник плашки бейджа
func compute_badge_rect(
	font: Font,
	center: Vector2,
	text: String,
	font_size: int = 10,
	pad_x: float = 10.0,
	pad_y: float = 5.0
) -> Rect2:
	var sz := _get_text_size(font, text, font_size)
	var box_w: float = minf(sz.x + pad_x * 2.0, 1240.0)
	var box_h: float = minf(sz.y + pad_y * 2.0, 680.0)
	var min_safe_x: float = 20.0 + box_w * 0.5
	var max_safe_x: float = 1260.0 - box_w * 0.5
	var safe_x: float = clampf(center.x, min_safe_x, maxf(min_safe_x, max_safe_x))
	var min_safe_y: float = 20.0 + box_h * 0.5
	var max_safe_y: float = 700.0 - box_h * 0.5
	var safe_y: float = clampf(center.y, min_safe_y, maxf(min_safe_y, max_safe_y))
	return Rect2(safe_x - box_w * 0.5, safe_y - box_h * 0.5, box_w, box_h)


func _draw_hud_badge(
	canvas: CanvasItem,
	font: Font,
	center: Vector2,
	text: String,
	border_col: Color,
	text_col: Color,
	font_size: int = 10,
	pad_x: float = 10.0,
	pad_y: float = 5.0
) -> void:
	var r := compute_badge_rect(font, center, text, font_size, pad_x, pad_y)

	canvas.draw_rect(r, COLOR_BG_PANEL)
	canvas.draw_rect(r, border_col, false, 1.2)

	var clen := minf(4.0, r.size.y * 0.3)
	canvas.draw_line(r.position, Vector2(r.position.x + clen, r.position.y), border_col, 2.0)
	canvas.draw_line(r.position, Vector2(r.position.x, r.position.y + clen), border_col, 2.0)
	canvas.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - clen, r.position.y), border_col, 2.0)
	canvas.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + clen), border_col, 2.0)
	canvas.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + clen, r.end.y), border_col, 2.0)
	canvas.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - clen), border_col, 2.0)
	canvas.draw_line(r.end, Vector2(r.end.x - clen, r.end.y), border_col, 2.0)
	canvas.draw_line(r.end, Vector2(r.end.x, r.end.y - clen), border_col, 2.0)

	var text_max_w: float = maxf(r.size.x - pad_x * 2.0, 10.0)
	var sz := _get_text_size(font, text, font_size)
	var text_pos := Vector2(r.position.x + pad_x, r.position.y + pad_y + sz.y * 0.78)
	if font != null:
		canvas.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, text_max_w, font_size, text_col)


## Вычисляет ограниченный безопасной зоной ([20, 1260], [20, 700]) прямоугольник центрированного текста
func compute_centered_string_rect(
	font: Font,
	center: Vector2,
	text: String,
	font_size: int
) -> Rect2:
	var sz := _get_text_size(font, text, font_size)
	var max_w: float = minf(sz.x, 1240.0)
	var min_safe_x: float = 20.0
	var max_safe_x: float = 1260.0 - max_w
	var draw_x: float = clampf(center.x - max_w * 0.5, min_safe_x, maxf(min_safe_x, max_safe_x))
	var draw_y: float = clampf(center.y + sz.y * 0.35, 20.0 + sz.y, 700.0)
	return Rect2(draw_x, draw_y - sz.y, max_w, sz.y)


func _draw_centered_string(
	canvas: CanvasItem,
	font: Font,
	center: Vector2,
	text: String,
	font_size: int,
	color: Color
) -> void:
	var sz := _get_text_size(font, text, font_size)
	var max_w: float = minf(sz.x, 1240.0)
	var min_safe_x: float = 20.0
	var max_safe_x: float = 1260.0 - max_w
	var draw_x: float = clampf(center.x - max_w * 0.5, min_safe_x, maxf(min_safe_x, max_safe_x))
	var draw_y: float = clampf(center.y + sz.y * 0.35, 20.0 + sz.y, 700.0)
	var pos := Vector2(draw_x, draw_y)
	if font != null:
		canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, color)


func _get_text_size(font: Font, text: String, font_size: int) -> Vector2:
	if font != null:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Vector2(float(text.length()) * float(font_size) * 0.6, float(font_size))


func _update_sparkles(delta: float) -> void:
	for i in MAX_SPARKLES:
		if sparkle_life[i] > 0.0:
			sparkle_life[i] = maxf(sparkle_life[i] - delta, 0.0)
			sparkle_pos[i] += sparkle_vel[i] * delta
			sparkle_vel[i] = sparkle_vel[i].lerp(Vector2.ZERO, delta * 4.0)


func _spawn_sparkle(origin: Vector2, col: Color) -> void:
	for i in MAX_SPARKLES:
		if sparkle_life[i] <= 0.0:
			sparkle_pos[i] = origin
			sparkle_vel[i] = Vector2(randf_range(-40.0, 40.0), randf_range(-35.0, -10.0))
			sparkle_max_life[i] = randf_range(0.3, 0.55)
			sparkle_life[i] = sparkle_max_life[i]
			sparkle_color[i] = col
			return


func _render_sparkles(canvas: CanvasItem) -> void:
	for i in MAX_SPARKLES:
		if sparkle_life[i] > 0.0:
			var max_l := maxf(sparkle_max_life[i], 0.001)
			var t := sparkle_life[i] / max_l
			var rad := 2.2 * t
			var col := Color(sparkle_color[i].r, sparkle_color[i].g, sparkle_color[i].b, t * 0.9)
			canvas.draw_circle(sparkle_pos[i], rad, col)

			var fl := rad * 2.2
			canvas.draw_line(sparkle_pos[i] - Vector2(fl, 0.0), sparkle_pos[i] + Vector2(fl, 0.0), col, 1.0)
			canvas.draw_line(sparkle_pos[i] - Vector2(0.0, fl), sparkle_pos[i] + Vector2(0.0, fl), col, 1.0)
