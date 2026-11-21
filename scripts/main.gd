class_name MainView
extends Node2D

const TactileTutorialHUD = preload("res://scripts/ui/tactile_tutorial_hud.gd")
const CutsceneIntro = preload("res://scripts/ui/cutscene_intro.gd")
const RobotThermalFX = preload("res://scripts/interaction/robot_thermal_fx.gd")
const RobotOptics = preload("res://scripts/core/robot_optics.gd")
const StepRunnerScript = preload("res://scripts/core/step_runner.gd")
const LoopAudioScript = preload("res://scripts/core/loop_audio.gd")
const LoopScreensScript = preload("res://scripts/ui/loop_screens.gd")
const TutorialScript = preload("res://scripts/ui/tutorial.gd")

## Главное игровое представление смены ремонта робота (Do Not Wake)
## Полностью тактильное физическое манипулирование объектами:
## перетаскивание инструментов, трение ветошью, выкручивание болтов, пуповинный кабель.

@onready var game_state: GameState = $GameState
var step_runner: Node = null
var loop_audio: Node = null
var loop_screens: CanvasLayer = null
var tutorial: CanvasLayer = null
var _current_step_index: int = 0
var _step_progress: float = 0.0
var _help_visible: bool = false
var _verify_banner_text: String = ""
var _verify_banner_color: Color = Color(0.35, 0.92, 0.58)
var _verify_banner_timer: float = 0.0
@onready var end_screen: Control = $EndScreen
@onready var sfx_click: AudioStreamPlayer = $Audio/SFXClick
@onready var sfx_repair: AudioStreamPlayer = $Audio/SFXRepair
@onready var sfx_error: AudioStreamPlayer = $Audio/SFXError
@onready var sfx_wake: AudioStreamPlayer = $Audio/SFXWake
@onready var sfx_calm: AudioStreamPlayer = $Audio/SFXCalm
@onready var sfx_insert: AudioStreamPlayer = $Audio/SFXInsert if has_node("Audio/SFXInsert") else null
@onready var sfx_strap_creak: AudioStreamPlayer = $Audio/SFXStrapCreak if has_node("Audio/SFXStrapCreak") else null
var stream_strap_creak: AudioStream = null
var stream_strap_creak_heavy: AudioStream = null

# Интро-катсцена
var cutscene_node: CutsceneIntro = null

# Текстуры робота и UI
var tex_robot_calm: Texture2D
var tex_robot_awake: Texture2D
var tex_robot_shadow: Texture2D
var tex_room_operating_bg: Texture2D
var tex_workbench_surface: Texture2D
var tex_room_blockout: Texture2D
var tex_tool_cloth: Texture2D
var tex_tool_screw: Texture2D
var tex_tool_keyb: Texture2D
var tex_gauge: Texture2D
var tex_panel: Texture2D
var tex_slot: Texture2D
var tex_slot_sel: Texture2D
var tex_bar_frame: Texture2D
var tex_cursor: Texture2D

# 9-slice margin'ы
const PANEL_MARGIN: Vector4 = Vector4(24, 24, 24, 24)
const SLOT_MARGIN: Vector4 = Vector4(24, 24, 20, 20)
const BAR_MARGIN: Vector4 = Vector4(8, 8, 8, 8)

var font: Font = ThemeDB.fallback_font
var selected_tool: String = "cloth"
var message_text: String = "Захватите ветошь мышью и начните чистку контактов"
var message_is_alert: bool = false
var flash_timer: float = 0.0
var screen_shake: float = 0.0
var spotlight_flicker: float = 1.0

# Кинематографичный пролог и предыстория
var is_cutscene_active: bool = true
var cutscene_timer: float = 0.0
var cutscene_lines: Array[String] = [
	"> [ ТЕРМИНАЛ БОКСА ИЗОЛЯЦИИ 07 // ДОСТУП РАЗРЕШЁН ]",
	"> ОБЪЕКТ: СЕРИЙНЫЙ ШТУРМОВОЙ АВТОМАТОН «ВЕПРЬ-04»",
	"> ПРИЧИНА ДОСТАВКИ: СПОНТАННЫЙ СБОЙ ЛОГИЧЕСКИХ МАТРИЦ",
	"> ИНЦИДЕНТ: АВАРИЯ НА СМЕНЕ, 4 ПОСТРАДАВШИХ ТЕХНИКА",
	"> ПРИКАЗ: ПРОВЕСТИ ЭКСТРЕННЫЙ РЕМОНТ ДО ПРИБЫТИЯ КОНВОЯ",
	"> --------------------------------------------------",
	"> ПРЕДУПРЕЖДЕНИЕ СЛУЖБЫ ОХРАНЫ:",
	"> МАШИНА НАХОДИТСЯ В ПРЕДПОРОГОВОЙ ФАЗЕ СНА.",
	"> РЕЗКИЕ ДВИЖЕНИЯ, РЫВКИ И ПЕРЕГРЕВ СОРВУТ РЕМНИ.",
	"> --------------------------------------------------",
	"> ГЛАВНОЕ ПРАВИЛО: НЕ БУДИ ЕГО."
]

# 2.5D-глубина: риг смещений слоёв от мыши (data/parallax.json)
var parallax: ParallaxRig
var _window_focused: bool = true

# Палитра
const COLOR_BG: Color = Color(0.02, 0.03, 0.04)
const COLOR_RIG_WALL: Color = Color(0.08, 0.09, 0.12)
const COLOR_RIG_FRAME: Color = Color(0.24, 0.28, 0.34)
const COLOR_BENCH: Color = Color(0.18, 0.20, 0.23)
const COLOR_BENCH_EDGE: Color = Color(0.38, 0.44, 0.50)
const COLOR_STRAP: Color = Color(0.14, 0.12, 0.10)
const COLOR_STRAP_BUCKLE: Color = Color(0.65, 0.70, 0.76)
const COLOR_TEXT_LIGHT: Color = Color(0.92, 0.94, 0.96)
const COLOR_TEXT_DIM: Color = Color(0.45, 0.55, 0.57)
const COLOR_ALERT: Color = Color(0.90, 0.16, 0.10)
const COLOR_SUCCESS: Color = Color(0.35, 0.92, 0.58)

const HELP_LINES: Array[String] = [
	"1. ДИАГНОСТИКА — нажмите СКАНИРОВАТЬ, запомните ID детали (A-04).",
	"2. ВЫБОР ДЕТАЛИ — кликните по бирке с этим ID на корпусе робота.",
	"3. КАРТОТЕКА — откройте ящик A и нажмите ВЗЯТЬ у карточки A-04.",
	"4. РЕГЛАМЕНТ — прочитайте шаги и нажмите НАЧАТЬ РЕМОНТ.",
	"5. РЕМОНТ — кликните ЛКМ по инструменту в лотке: он останется в руке.",
	"     Ветошью трите контакты влево-вправо. Слишком медленно — прогресса нет,",
	"     слишком быстро — перегрев и нестабильность.",
	"     Отвёрткой вращайте болты. Кабель тащите к виску и держите у порта.",
	"6. КОНТРОЛЬ УГРОЗЫ — не двигайте мышью, пока не истечёт таймер.",
	"7. ПРОВЕРКА — ОТК ставит штамп ГОДЕН или БРАК.",
	"",
	"TAB — снова открыть панель текущей фазы",
	"P — тактическая пауза (охлаждение)",
	"ПКМ — убрать инструмент из руки",
	"F2 — обучение (подсказки по шагам)",
	"F1 / ESC — закрыть эту памятку"
]

# Макет сцены из robot.json (или дефолты)
var containment_rig_rect: Rect2 = Rect2(480, 60, 320, 560)
var robot_rect: Rect2 = Rect2(512, 80, 256, 512)
var strap_rects: Array[Rect2] = [
	Rect2(490, 290, 300, 32),
	Rect2(490, 430, 300, 32),
	Rect2(490, 580, 300, 32)
]
var medical_tray_rect: Rect2 = Rect2(80, 580, 1120, 130)

# Интерактивные тактильные компоненты
var draggable_tools: Dictionary = {}
var held_tool: DraggableTool = null
var scrub_zone: ScrubZone = null
var screw_manager: ScrewBoltManager = null
var cable_plug: CablePlug = null
var tutorial_hud: TactileTutorialHUD = null
var thermal_fx: RobotThermalFX = null
var robot_optics: RobotOptics = null

var tools_data: Array = []

# Динамические удерживающие ремни и процедурное дыхание робота
var robot_breath_phase: float = 0.0
var robot_breath_weight: float = 0.0
var robot_shudder_intensity: float = 0.0
var robot_shudder_offset: Vector2 = Vector2.ZERO
var robot_next_twitch_timer: float = 3.5
var strap_tension_creak_cooldown: float = 0.0

var strap_tensions: Array[float] = [0.0, 0.0, 0.0]
var strap_deflections: Array[float] = [0.0, 0.0, 0.0]

# Pre-allocated Zero-GC buffers for frame drawing and updates
var _nine_src_x: PackedFloat32Array = PackedFloat32Array()
var _nine_src_y: PackedFloat32Array = PackedFloat32Array()
var _nine_dst_x: PackedFloat32Array = PackedFloat32Array()
var _nine_dst_y: PackedFloat32Array = PackedFloat32Array()

var _strap_top_pts: Array[PackedVector2Array] = []
var _strap_bot_pts: Array[PackedVector2Array] = []
var _strap_poly: Array[PackedVector2Array] = []
var _strap_shadow_poly: Array[PackedVector2Array] = []
var _strap_highlight_stitch: Array[PackedVector2Array] = []
var _strap_shadow_stitch: Array[PackedVector2Array] = []

var _cone_pts: PackedVector2Array = PackedVector2Array()
var _spot_radii: PackedFloat32Array = PackedFloat32Array([340.0, 240.0, 160.0, 90.0])
var _spot_alphas: PackedFloat32Array = PackedFloat32Array([0.015, 0.025, 0.035, 0.045])

var _instability_pct_strings: Array[String] = []
var _last_freeze_tenth: int = -1
var _cached_freeze_str: String = ""

var _draggable_tool_items: Array[DraggableTool] = []
var _screw_tool_cached: DraggableTool = null


func _init() -> void:
	_nine_src_x.resize(4)
	_nine_src_y.resize(4)
	_nine_dst_x.resize(4)
	_nine_dst_y.resize(4)

	_cone_pts = PackedVector2Array([
		Vector2(580.0, 0.0),
		Vector2(700.0, 0.0),
		Vector2(850.0, 560.0),
		Vector2(430.0, 560.0)
	])

	_instability_pct_strings.resize(101)
	for i in 101:
		_instability_pct_strings[i] = "%d%%" % i

	_init_strap_buffers()


func _init_strap_buffers() -> void:
	var segs := 24
	_strap_top_pts.clear()
	_strap_bot_pts.clear()
	_strap_poly.clear()
	_strap_shadow_poly.clear()
	_strap_highlight_stitch.clear()
	_strap_shadow_stitch.clear()

	for i in 3:
		var top_arr := PackedVector2Array()
		top_arr.resize(segs + 1)
		_strap_top_pts.append(top_arr)

		var bot_arr := PackedVector2Array()
		bot_arr.resize(segs + 1)
		_strap_bot_pts.append(bot_arr)

		var poly_arr := PackedVector2Array()
		poly_arr.resize((segs + 1) * 2)
		_strap_poly.append(poly_arr)

		var shadow_arr := PackedVector2Array()
		shadow_arr.resize((segs + 1) * 2)
		_strap_shadow_poly.append(shadow_arr)

		var hl_arr := PackedVector2Array()
		hl_arr.resize(segs + 1)
		_strap_highlight_stitch.append(hl_arr)

		var sh_arr := PackedVector2Array()
		sh_arr.resize(segs + 1)
		_strap_shadow_stitch.append(sh_arr)


static func _load_strap_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is AudioStream:
			return res
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var bytes := file.get_buffer(file.get_length())
			if bytes.size() > 44:
				var stream := AudioStreamWAV.new()
				stream.format = AudioStreamWAV.FORMAT_16_BITS
				stream.mix_rate = 22050
				stream.stereo = false
				stream.data = bytes.slice(44)
				return stream
	return null


static func _synthesize_strap_creak(duration: float, intensity: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var total_samples := int(22050 * duration)
	var samples: Array[float] = []
	samples.resize(total_samples)
	samples.fill(0.0)

	var cluster_starts := [0.03, 0.15, 0.28, 0.42]
	for c_start in cluster_starts:
		if c_start >= duration - 0.08:
			break
		var t: float = c_start
		var dt: float = 0.007
		var n_slips := 6 + int(randf() * 5.0)
		for _s in range(n_slips):
			var s_idx := int(t * 22050)
			var decay_len := int(22050 * 0.035)
			var f_res := randf_range(260.0, 380.0) * intensity
			var f_res2 := randf_range(650.0, 950.0)
			for i in range(decay_len):
				var idx := s_idx + i
				if idx >= total_samples:
					break
				var time_sec := float(i) / 22050.0
				var env := exp(-time_sec * 115.0)
				var osc := sin(TAU * f_res * time_sec) * 0.7 + sin(TAU * f_res2 * time_sec) * 0.3
				var grit := (randf() * 2.0 - 1.0) * 0.15
				samples[idx] += (osc + grit) * env * 0.8
			t += dt * randf_range(0.85, 1.4)
			dt *= 1.14

	var max_val: float = 0.001
	for s in samples:
		max_val = maxf(max_val, absf(s))

	var raw := PackedByteArray()
	raw.resize(total_samples * 2)
	for i in range(total_samples):
		var norm := clampf(samples[i] / max_val * 0.85, -1.0, 1.0)
		var int_val := int(norm * 32767.0)
		if int_val < 0:
			int_val += 65536
		raw[i * 2] = int_val & 0xFF
		raw[i * 2 + 1] = (int_val >> 8) & 0xFF

	stream.data = raw
	return stream


static func _load_disk_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _ready() -> void:
	parallax = ParallaxRig.new()
	tex_robot_calm = _load_disk_texture("res://assets/sprites/robot/robot_vertical_calm.png")
	tex_robot_awake = _load_disk_texture("res://assets/sprites/robot/robot_vertical_awake.png")
	tex_robot_shadow = _load_disk_texture("res://assets/sprites/robot/robot_niche_shadow.png")
	tex_workbench_surface = _load_disk_texture("res://assets/sprites/room/workbench_surface.png")
	tex_room_operating_bg = _load_disk_texture("res://assets/sprites/room/room_operating_bg.png")

	tex_tool_cloth = _load_disk_texture("res://assets/sprites/objects/tool_rag_physical.png")
	tex_tool_screw = _load_disk_texture("res://assets/sprites/objects/tool_screwdriver_physical.png")
	tex_tool_keyb = _load_disk_texture("res://assets/sprites/objects/tool_cable_physical.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_gauge_face.png"):
		tex_gauge = load("res://assets/sprites/ui/ui_gauge_face.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_panel.png"):
		tex_panel = load("res://assets/sprites/ui/ui_panel.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_slot_plate.png"):
		tex_slot = load("res://assets/sprites/ui/ui_slot_plate.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_slot_plate_selected.png"):
		tex_slot_sel = load("res://assets/sprites/ui/ui_slot_plate_selected.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_bar_frame.png"):
		tex_bar_frame = load("res://assets/sprites/ui/ui_bar_frame.png")
	if ResourceLoader.exists("res://assets/sprites/ui/ui_cursor.png"):
		tex_cursor = load("res://assets/sprites/ui/ui_cursor.png")
		Input.set_custom_mouse_cursor(tex_cursor, Input.CURSOR_ARROW, Vector2(7, 8))

	# Инициализация аудио-хука скрипа натяжения ремней
	if sfx_strap_creak == null:
		if has_node("Audio/SFXStrapCreak"):
			sfx_strap_creak = $Audio/SFXStrapCreak
		else:
			sfx_strap_creak = AudioStreamPlayer.new()
			sfx_strap_creak.name = "SFXStrapCreak"
			if has_node("Audio"):
				$Audio.add_child(sfx_strap_creak)
			else:
				add_child(sfx_strap_creak)

	stream_strap_creak = _load_strap_audio("res://assets/sounds/strap_creak.wav")
	stream_strap_creak_heavy = _load_strap_audio("res://assets/sounds/strap_creak_heavy.wav")
	if stream_strap_creak == null:
		stream_strap_creak = _synthesize_strap_creak(0.45, 1.0)
	if stream_strap_creak_heavy == null:
		stream_strap_creak_heavy = _synthesize_strap_creak(0.60, 1.3)

	if game_state:
		if not game_state.feedback_triggered.is_connected(_on_feedback):
			game_state.feedback_triggered.connect(_on_feedback)
		if not game_state.state_changed.is_connected(_on_state_changed):
			game_state.state_changed.connect(_on_state_changed)
		if not game_state.stage_changed.is_connected(_on_stage_changed):
			game_state.stage_changed.connect(_on_stage_changed)
		if not game_state.game_finished.is_connected(_on_game_finished):
			game_state.game_finished.connect(_on_game_finished)

		if game_state.balance == null:
			game_state.initialize_game()

		if game_state.balance:
			tools_data = game_state.balance.get_tools()
			_init_layout_from_balance(game_state.balance)

	_init_tactile_components()
	_init_loop_subsystems()

	# Инициализация кинематографичного пролога
	cutscene_node = CutsceneIntro.new()
	cutscene_node.cutscene_completed.connect(_on_cutscene_completed)
	add_child(cutscene_node)


var _loop_subsystems_initialized: bool = false


func _init_loop_subsystems() -> void:
	if _loop_subsystems_initialized:
		return
	_loop_subsystems_initialized = true

	if step_runner == null:
		if has_node("StepRunner"):
			step_runner = get_node("StepRunner")
		else:
			step_runner = StepRunnerScript.new()
			step_runner.name = "StepRunner"
			add_child(step_runner)

	if loop_audio == null:
		if has_node("LoopAudio"):
			loop_audio = get_node("LoopAudio")
		else:
			loop_audio = LoopAudioScript.new()
			loop_audio.name = "LoopAudio"
			add_child(loop_audio)

	if loop_screens == null:
		if has_node("LoopScreens"):
			loop_screens = get_node("LoopScreens") as CanvasLayer
		else:
			loop_screens = LoopScreensScript.new()
			loop_screens.name = "LoopScreens"
			add_child(loop_screens)

	loop_screens.set_world_root(self)
	if game_state:
		loop_screens.bind(game_state)
		loop_audio.bind(game_state, step_runner)
		_connect_loop_signals()

	if tutorial == null:
		if has_node("Tutorial"):
			tutorial = get_node("Tutorial") as CanvasLayer
		else:
			tutorial = TutorialScript.new()
			tutorial.name = "Tutorial"
			add_child(tutorial)
		tutorial.bind(self, game_state, loop_screens)


func _connect_loop_signals() -> void:
	if game_state:
		if not game_state.step_requested.is_connected(_on_step_requested):
			game_state.step_requested.connect(_on_step_requested)
		if not game_state.wake_started.is_connected(_on_wake_started):
			game_state.wake_started.connect(_on_wake_started)
		if not game_state.wake_ended.is_connected(_on_wake_ended):
			game_state.wake_ended.connect(_on_wake_ended)
		if not game_state.pause_changed.is_connected(_on_pause_changed):
			game_state.pause_changed.connect(_on_pause_changed)
		if not game_state.shift_finished.is_connected(_on_shift_finished):
			game_state.shift_finished.connect(_on_shift_finished)
		if not game_state.phase_changed.is_connected(_on_phase_changed):
			game_state.phase_changed.connect(_on_phase_changed)
		if not game_state.verification_finished.is_connected(_on_verification_finished):
			game_state.verification_finished.connect(_on_verification_finished)

	if step_runner:
		if not step_runner.step_finished.is_connected(_on_runner_step_finished):
			step_runner.step_finished.connect(_on_runner_step_finished)
		if not step_runner.step_failed.is_connected(_on_runner_step_failed):
			step_runner.step_failed.connect(_on_runner_step_failed)
		if not step_runner.hazard.is_connected(_on_runner_hazard):
			step_runner.hazard.connect(_on_runner_hazard)
		if not step_runner.progress_changed.is_connected(_on_runner_progress_changed):
			step_runner.progress_changed.connect(_on_runner_progress_changed)


# =============================================================================
# ХОСТ-ИНТЕРФЕЙС ДЛЯ StepRunner (контракт данных §4.2 — ровно 5 методов)
# =============================================================================

func get_mouse_pos() -> Vector2:
	return get_global_mouse_position()


func is_tool_held(tool_id: String) -> bool:
	return held_tool != null and held_tool.tool_id == tool_id


func get_tool_tip(tool_id: String) -> Vector2:
	return held_tool.get_tip_position() if held_tool != null else Vector2.ZERO


func get_mid_shift() -> Vector2:
	return _layer_shift("mid")


func get_component(kind: String) -> Node2D:
	match kind:
		"scrub":
			return scrub_zone
		"unbolt":
			return screw_manager
		"cable":
			return cable_plug
		_:
			return null


func get_tool_label(tool_id: String) -> String:
	return game_state.get_tool_label(tool_id) if game_state else tool_id


# =============================================================================
# ОБРАБОТЧИКИ СИГНАЛОВ НОВОЙ ПЕТЛИ РЕМОНТА
# =============================================================================

func _on_step_requested(index: int, step: Dictionary) -> void:
	_current_step_index = index
	_step_progress = 0.0
	message_text = "Операция: " + str(step.get("label", "Выполняйте регламент"))
	message_is_alert = false
	if step_runner:
		step_runner.setup(self, step)
		step_runner.start()


func _on_runner_step_finished(quality: float) -> void:
	if game_state:
		game_state.report_step_result(_current_step_index, true, quality)
	if held_tool:
		held_tool.put_down()
		held_tool = null


func _on_runner_step_failed(reason: String) -> void:
	if game_state:
		game_state.report_step_result(_current_step_index, false, 0.0, reason)
	# Инструмент остаётся в руке: шаг перезапущен, игроку не нужно брать его заново.
	if reason == "timeout":
		_on_feedback("ВРЕМЯ ШАГА ИСТЕКЛО. ОПЕРАЦИЯ ПЕРЕЗАПУЩЕНА", true)
	elif reason.begins_with("order:"):
		_on_feedback("НАРУШЕН ПОРЯДОК. ШАГ ПЕРЕЗАПУЩЕН", true)


func _on_runner_hazard(amount: float, message: String) -> void:
	if game_state:
		game_state.add_instability(amount)
	_on_feedback(message, true)


func _on_runner_progress_changed(value: float) -> void:
	if game_state and game_state.has_signal("step_progress"):
		game_state.step_progress.emit(_current_step_index, value)


func _on_wake_started(duration: float) -> void:
	if step_runner:
		step_runner.set_frozen(true)
	if held_tool:
		held_tool.return_to_tray()
		held_tool = null
	screen_shake = 12.0
	trigger_robot_shudder(12.0, false)
	if sfx_wake:
		sfx_wake.play()


func _on_wake_ended() -> void:
	if step_runner:
		step_runner.set_frozen(false)
	if sfx_calm:
		sfx_calm.play()


func _on_pause_changed(paused: bool, _reason: String) -> void:
	if step_runner:
		step_runner.set_frozen(paused)
	if paused and held_tool:
		held_tool.return_to_tray()
		held_tool = null


func _on_shift_finished(success: bool, stats: Dictionary) -> void:
	if end_screen and game_state:
		var wakes_cnt: int = int(stats.get("wakes", 0))
		var cur_inst: float = game_state.robot.instability if game_state.robot else 0.0
		var thresh: float = game_state.robot.threshold if game_state.robot else 70.0
		var parts_done: int = int(stats.get("parts_done", 0))
		var total_parts: int = 1
		if "_parts" in game_state and not game_state._parts.is_empty():
			total_parts = game_state._parts.size()
		end_screen.show_result(success, wakes_cnt, cur_inst, thresh, parts_done, total_parts)


func _on_verification_finished(passed: bool, details: Dictionary) -> void:
	var quality: float = float(details.get("quality", details.get("quality_avg", 1.0)))
	if passed:
		_verify_banner_text = "ОТК: ГОДЕН · КАЧЕСТВО %d%%" % int(clampf(quality, 0.0, 1.0) * 100.0)
		_verify_banner_color = COLOR_SUCCESS
		screen_shake = maxf(screen_shake, 3.0)
		if sfx_repair:
			sfx_repair.play()
	else:
		_verify_banner_text = "ОТК: БРАК · " + str(details.get("reason", "НАРУШЕН РЕГЛАМЕНТ"))
		_verify_banner_color = COLOR_ALERT
		flash_timer = maxf(flash_timer, 0.3)
		if sfx_error and not sfx_error.playing:
			sfx_error.play()
	_verify_banner_timer = 3.0


func _on_phase_changed(phase: int) -> void:
	match phase:
		GameState.Phase.DIAGNOSTICS:
			message_text = "Диагностика: нажмите СКАНИРОВАТЬ на терминале"
			message_is_alert = false
		GameState.Phase.PART_SELECT:
			message_text = "Выберите деталь с ID, указанным в отчёте диагностики"
			message_is_alert = false
		GameState.Phase.DOC_SEARCH:
			message_text = "Найдите карточку регламента по коду узла в картотеке"
			message_is_alert = false
		GameState.Phase.REPAIR:
			message_text = "Возьмите инструмент из лотка (ЛКМ) и выполните операцию"
			message_is_alert = false
		GameState.Phase.THREAT_CONTROL:
			message_text = "Не двигайте мышью, пока узел не остынет"
			message_is_alert = false
		GameState.Phase.VERIFY:
			message_text = "Проверка ОТК: смотрите штамп ГОДЕН/БРАК"
			message_is_alert = false
		GameState.Phase.SHIFT_COMPLETE:
			message_text = "Смена успешно завершена"
			message_is_alert = false
		GameState.Phase.SHIFT_FAILED:
			message_text = "Смена сорвана: " + str(game_state.fail_reason if game_state else "")
			message_is_alert = true


func _is_overlay_active() -> bool:
	if loop_screens == null:
		return false
	if loop_screens._current_modal != null and loop_screens._current_modal.visible:
		return true
	if loop_screens.threat_overlay != null and (loop_screens.threat_overlay._wake_active or loop_screens.threat_overlay._pause_active):
		return true
	if loop_screens.diagnostics_panel != null and loop_screens.diagnostics_panel.visible:
		return true
	if loop_screens.card_file != null and loop_screens.card_file.visible:
		return true
	if loop_screens.doc_reader != null and loop_screens.doc_reader.visible:
		return true
	if loop_screens.verify_panel != null and loop_screens.verify_panel.visible:
		return true
	return false


func _get_phase_title(phase: int) -> String:
	match phase:
		GameState.Phase.DIAGNOSTICS:
			return "ЭТАП 1 // ДИАГНОСТИКА"
		GameState.Phase.PART_SELECT:
			return "ЭТАП 2 // ВЫБОР ДЕТАЛИ"
		GameState.Phase.DOC_SEARCH:
			return "ЭТАП 3 // КАРТОТЕКА И РЕГЛАМЕНТ"
		GameState.Phase.REPAIR:
			return "ЭТАП 4 // РЕМОНТ УЗЛА"
		GameState.Phase.THREAT_CONTROL:
			return "ЭТАП 5 // КОНТРОЛЬ УГРОЗЫ"
		GameState.Phase.VERIFY:
			return "ЭТАП 6 // ПРОВЕРКА ОТК"
		GameState.Phase.SHIFT_COMPLETE:
			return "СМЕНА ВЫПОЛНЕНА"
		GameState.Phase.SHIFT_FAILED:
			return "СМЕНА СОРВАНА"
		_:
			return "БРИФИНГ"


func _get_phase_instruction(phase: int) -> String:
	match phase:
		GameState.Phase.DIAGNOSTICS:
			return "Нажмите СКАНИРОВАТЬ на терминале. TAB — открыть терминал снова"
		GameState.Phase.PART_SELECT:
			return "Кликните по бирке детали на корпусе робота (например A-04)"
		GameState.Phase.DOC_SEARCH:
			return "Откройте ящик картотеки и нажмите ВЗЯТЬ у нужной карточки. TAB — картотека"
		GameState.Phase.REPAIR:
			return "Возьмите инструмент из лотка (ЛКМ) и выполните операцию. F1 — помощь"
		GameState.Phase.THREAT_CONTROL:
			return "Не двигайте мышью, пока узел не остынет"
		GameState.Phase.VERIFY:
			return "ОТК проверяет узел — смотрите штамп ГОДЕН/БРАК"
		GameState.Phase.SHIFT_COMPLETE:
			return "Все неисправности устранены. Автоматон стабилизирован."
		GameState.Phase.SHIFT_FAILED:
			return "Робот пробудился или повреждён критически. Смена прервана."
		_:
			return "Ожидание запуска смены..."


func start_shift() -> void:
	is_cutscene_active = false
	if is_instance_valid(cutscene_node):
		cutscene_node.queue_free()
		cutscene_node = null
	# В новой петле кабель — это физический штекер CablePlug. Отдельная иконка
	# «кабель» перехватывала бы клики по штекеру, поэтому убираем её из лотка.
	var cable_tool: DraggableTool = draggable_tools.get("cable", null)
	if cable_tool != null:
		cable_tool.is_enabled = false
		cable_tool.visible = false
	if held_tool != null:
		held_tool.put_down()
		held_tool = null
	_help_visible = false
	_step_progress = 0.0
	if game_state:
		game_state.start_shift()
	if tutorial != null:
		tutorial.start_if_needed()
	message_text = "Смена начата. Нажмите СКАНИРОВАТЬ на терминале диагностики"
	message_is_alert = false


func _on_cutscene_completed() -> void:
	start_shift()


func _init_layout_from_balance(balance: Balance) -> void:
	var layout: Dictionary = balance.get_robot_layout()
	if layout.has("containment_rig_rect"):
		containment_rig_rect = Balance.to_rect(layout["containment_rig_rect"])
	if layout.has("robot_rect"):
		robot_rect = Balance.to_rect(layout["robot_rect"])
		if thermal_fx:
			thermal_fx.configure(robot_rect)
	if layout.has("medical_tray_rect"):
		medical_tray_rect = Balance.to_rect(layout["medical_tray_rect"])
	if layout.has("straps") and layout["straps"] is Array:
		strap_rects.clear()
		for s in layout["straps"]:
			if s is Dictionary and s.has("rect"):
				strap_rects.append(Balance.to_rect(s["rect"]))


func _init_tactile_components() -> void:
	# 1. Физические перетаскиваемые инструменты
	_draggable_tool_items.clear()
	for t in tools_data:
		var t_id: String = str(t.get("id", ""))
		var t_label: String = str(t.get("label", t_id))
		t["upper_label"] = t_label.to_upper()
		var raw_rect: Variant = t.get("rect", [140, 600, 160, 90])
		var t_rect: Rect2 = Balance.to_rect(raw_rect)
		t["tool_rect"] = t_rect

		var t_tex: Texture2D = null
		if t_id == "cloth":
			t_tex = tex_tool_cloth
		elif t_id == "screwdriver":
			t_tex = tex_tool_screw
		elif t_id == "cable" or t_id == "keyboard":
			t_tex = tex_tool_keyb

		var tool_node := DraggableTool.new()
		tool_node.setup(t_id, t_label, t_rect, t_tex, font)
		tool_node.drag_started.connect(_on_tool_drag_started)
		tool_node.drag_ended.connect(_on_tool_drag_ended)
		add_child(tool_node)
		# Располагаем до CRTPostProcess, чтобы шейдер накладывался поверх
		move_child(tool_node, 0)
		draggable_tools[t_id] = tool_node
		_draggable_tool_items.append(tool_node)

	_screw_tool_cached = draggable_tools.get("screwdriver", null)

	# 2. Этап 1: Зона скраббинга контактов ветошью
	scrub_zone = ScrubZone.new()
	var stage0_zones: Array = []
	if game_state and not game_state.stages.is_empty():
		stage0_zones = game_state.stages[0].zones

	var scrub_rect := Rect2(570, 250, 140, 60)
	var scrub_params := {}
	if not stage0_zones.is_empty():
		var z0: Dictionary = stage0_zones[0]
		scrub_rect = Balance.to_rect(z0.get("rect", [570, 250, 140, 60]))
		if z0.has("scrub_params") and z0["scrub_params"] is Dictionary:
			scrub_params = z0["scrub_params"]

	scrub_zone.configure(scrub_rect, scrub_params)
	scrub_zone.scrub_completed.connect(_on_scrub_completed)
	scrub_zone.overheat_occurred.connect(_on_scrub_overheated)
	scrub_zone.feedback_text_requested.connect(_on_feedback)
	scrub_zone.is_active = true

	# 3. Этап 2: Выкручивание 4 болтов и снятие бронелюка
	screw_manager = ScrewBoltManager.new()
	var hatch_rect := Rect2(570, 275, 140, 90)
	var bolts_arr := [
		{ "id": "bolt_tl", "pos": [590, 295], "radius": 14.0, "turns_required": 3.0 },
		{ "id": "bolt_tr", "pos": [690, 295], "radius": 14.0, "turns_required": 3.0 },
		{ "id": "bolt_bl", "pos": [590, 345], "radius": 14.0, "turns_required": 3.0 },
		{ "id": "bolt_br", "pos": [690, 345], "radius": 14.0, "turns_required": 3.0 }
	]
	var slip_params := {}
	if game_state and game_state.stages.size() > 1:
		var st1_zones: Array = game_state.stages[1].zones
		if not st1_zones.is_empty():
			var z1: Dictionary = st1_zones[0]
			hatch_rect = Balance.to_rect(z1.get("rect", [550, 320, 180, 120]))
			if z1.has("bolts") and z1["bolts"] is Array:
				bolts_arr = z1["bolts"]
			if z1.has("slip_params") and z1["slip_params"] is Dictionary:
				slip_params = z1["slip_params"]

	screw_manager.configure(hatch_rect, bolts_arr, slip_params)
	screw_manager.bolt_loosened.connect(_on_bolt_loosened)
	screw_manager.tool_slipped.connect(_on_tool_slipped)
	screw_manager.hatch_removed.connect(_on_hatch_removed)
	screw_manager.ratchet_tick.connect(_on_ratchet_tick)
	screw_manager.feedback_text_requested.connect(_on_feedback)
	screw_manager.is_active = false

	# 4. Этап 3: Пуповинный кабель и гнездо в голове
	cable_plug = CablePlug.new()
	var socket_pos := Vector2(640, 180)
	var anchor_pos := Vector2(980, 640)
	var home_plug := Vector2(940, 600)
	var cable_params := {}
	if game_state and game_state.stages.size() > 2:
		var st2_zones: Array = game_state.stages[2].zones
		if not st2_zones.is_empty():
			var z2: Dictionary = st2_zones[0]
			if z2.has("cable_params") and z2["cable_params"] is Dictionary:
				cable_params = z2["cable_params"]
				if cable_params.has("socket_pos"):
					var sp: Array = cable_params["socket_pos"]
					socket_pos = Vector2(float(sp[0]), float(sp[1]))
				if cable_params.has("cable_anchor"):
					var ap: Array = cable_params["cable_anchor"]
					anchor_pos = Vector2(float(ap[0]), float(ap[1]))

	cable_plug.configure(socket_pos, anchor_pos, home_plug, cable_params)
	cable_plug.cable_locked.connect(_on_cable_locked)
	cable_plug.surge_started.connect(_on_surge_started)
	cable_plug.head_shudder_triggered.connect(_on_cable_head_shudder)
	cable_plug.feedback_text_requested.connect(_on_feedback)
	cable_plug.is_active = false

	# 5. Тактильный обучающий HUD и аффордансы управления
	tutorial_hud = TactileTutorialHUD.new()
	add_child(tutorial_hud)

	# 6. Система теплового излучения радиатора шасси и стравливания давления
	thermal_fx = RobotThermalFX.new()
	thermal_fx.configure(robot_rect)


func _on_tool_drag_started(tool_id: String) -> void:
	var new_tool: DraggableTool = draggable_tools.get(tool_id, null)
	if held_tool != null and held_tool != new_tool:
		held_tool.put_down()
	selected_tool = tool_id
	held_tool = new_tool
	if held_tool and held_tool.label != "":
		message_text = "В руке: %s · ЛКМ по лотку или ПКМ — убрать" % held_tool.label.to_upper()
	else:
		message_text = "Инструмент в руке: " + tool_id
	message_is_alert = false
	if sfx_click:
		sfx_click.pitch_scale = 1.0
		sfx_click.play()


func _on_tool_drag_ended(tool_id: String, drop_pos: Vector2) -> void:
	if held_tool and held_tool.tool_id == tool_id:
		held_tool = null


func _on_scrub_completed() -> void:
	if game_state and game_state.current_mode == GameState.Mode.LEGACY and game_state.current_stage_index == 0:
		game_state.apply_repair(0, "cloth")
		screen_shake = 4.0
		if sfx_repair:
			sfx_repair.play()


func _on_scrub_overheated(heat_penalty: float) -> void:
	if game_state and game_state.robot and game_state.current_mode == GameState.Mode.LEGACY:
		game_state.robot.add_instability(heat_penalty)
		screen_shake = maxf(screen_shake, 3.5)
		flash_timer = 0.22
		if sfx_error and not sfx_error.playing:
			sfx_error.play()
	if thermal_fx:
		thermal_fx.trigger_acute_overheat(heat_penalty)
	trigger_robot_shudder(4.0)


func _on_bolt_loosened(bolt_id: String, remaining: int) -> void:
	screen_shake = 2.0
	trigger_robot_shudder(1.2, false)
	if sfx_click:
		sfx_click.pitch_scale = 0.85
		sfx_click.play()
	if remaining > 0:
		message_text = "Болт ослаблен! Осталось: %d" % remaining
		message_is_alert = false


func _on_ratchet_tick() -> void:
	trigger_robot_shudder(0.5, false)
	if sfx_click:
		sfx_click.pitch_scale = randf_range(1.15, 1.35)
		sfx_click.play()


func _on_tool_slipped(penalty: float, shake: float) -> void:
	if game_state and game_state.robot:
		game_state.robot.add_instability(penalty)
	screen_shake = shake
	flash_timer = 0.35
	if sfx_error:
		sfx_error.play()
	if thermal_fx:
		thermal_fx.trigger_acute_overheat(penalty * 0.4)
	if held_tool:
		held_tool.return_to_tray()
		held_tool = null
	trigger_robot_shudder(6.0)


func _on_hatch_removed() -> void:
	if game_state and game_state.current_stage_index == 1:
		game_state.apply_repair(0, "screwdriver")
		screen_shake = 5.0
		trigger_robot_shudder(3.0, false)
		if sfx_repair:
			sfx_repair.play()


func _on_cable_locked() -> void:
	if sfx_repair:
		sfx_repair.play()
	elif sfx_calm:
		sfx_calm.play()

	screen_shake = 6.0
	spotlight_flicker = 0.3
	trigger_robot_shudder(4.0)
	if game_state and game_state.current_stage_index == 2:
		game_state.apply_repair(0, "cable")


func _on_surge_started() -> void:
	if sfx_insert:
		sfx_insert.play()
	screen_shake = 4.0
	spotlight_flicker = 0.4
	trigger_robot_shudder(5.0)


func _on_cable_head_shudder(intensity: float) -> void:
	screen_shake = maxf(screen_shake, 7.5 * intensity)
	spotlight_flicker = 0.25
	trigger_robot_shudder(7.0 * intensity)


func _on_stage_changed(stage_index: int, stage: RepairStage) -> void:
	# Переключение активных компонентов по этапам
	if scrub_zone:
		scrub_zone.is_active = (stage_index == 0)
	if screw_manager:
		screw_manager.is_active = (stage_index == 1)
	if cable_plug:
		cable_plug.is_active = (stage_index == 2)

	if held_tool:
		held_tool.return_to_tray()
		held_tool = null


func _on_feedback(msg: String, is_alert: bool) -> void:
	message_text = msg
	message_is_alert = is_alert
	if is_alert:
		flash_timer = 0.4
		screen_shake = maxf(screen_shake, 5.0)
		trigger_robot_shudder(5.0)
		if sfx_error:
			sfx_error.play()
	else:
		if sfx_repair and not sfx_repair.playing:
			sfx_repair.play()


func _on_state_changed(new_state: GameState.State) -> void:
	if new_state == GameState.State.AWAKE:
		screen_shake = 12.0
		trigger_robot_shudder(12.0, false)
		if sfx_wake:
			sfx_wake.play()
		if held_tool:
			held_tool.return_to_tray()
			held_tool = null
	elif new_state == GameState.State.CALM:
		if sfx_calm:
			sfx_calm.play()


func trigger_robot_shudder(intensity: float, play_sound_if_severe: bool = true) -> void:
	robot_shudder_intensity = maxf(robot_shudder_intensity, intensity)
	var cur_inst: float = game_state.robot.instability if (game_state and game_state.robot) else 20.0
	if play_sound_if_severe and (intensity >= 4.0 or cur_inst >= 45.0) and strap_tension_creak_cooldown <= 0.6:
		play_strap_creak_sfx(intensity >= 5.0)
		strap_tension_creak_cooldown = randf_range(1.8, 3.2)


func play_strap_creak_sfx(is_heavy: bool = false) -> void:
	if sfx_strap_creak == null:
		return
	var stream_to_play: AudioStream = stream_strap_creak_heavy if is_heavy else stream_strap_creak
	if stream_to_play == null:
		return
	sfx_strap_creak.stream = stream_to_play
	var cur_inst: float = game_state.robot.instability if (game_state and game_state.robot) else 20.0
	var inst_ratio: float = clampf((cur_inst - 20.0) / 80.0, 0.0, 1.0)
	sfx_strap_creak.pitch_scale = randf_range(0.92, 1.12) + inst_ratio * 0.12
	sfx_strap_creak.volume_db = lerpf(-7.0, 1.5, inst_ratio)
	sfx_strap_creak.play()


func _on_game_finished(is_success: bool) -> void:
	if end_screen and game_state and game_state.robot:
		var stages_done: int = game_state.stages.size() if is_success else game_state.current_stage_index
		var total_st: int = game_state.stages.size()
		var thresh: float = game_state.robot.threshold
		end_screen.show_result(
			is_success,
			game_state.robot.wake_count,
			game_state.robot.instability,
			thresh,
			stages_done,
			total_st
		)


func _process(delta: float) -> void:
	if is_cutscene_active:
		return

	if flash_timer > 0.0:
		flash_timer = maxf(flash_timer - delta, 0.0)
	if _verify_banner_timer > 0.0:
		_verify_banner_timer = maxf(_verify_banner_timer - delta, 0.0)
	if screen_shake > 0.0:
		screen_shake = maxf(screen_shake - delta * 20.0, 0.0)
	if spotlight_flicker < 1.0:
		spotlight_flicker = minf(spotlight_flicker + delta * 2.5, 1.0)

	var mouse_pos: Vector2 = get_global_mouse_position() if get_viewport() != null else Vector2.ZERO
	var vp_size: Vector2 = get_viewport_rect().size if get_viewport() != null else Vector2(1280, 720)

	if parallax:
		if _window_focused:
			parallax.update(delta, mouse_pos, vp_size)
		else:
			parallax.reset()

	if game_state and not _help_visible:
		game_state.tick(delta)

	# Пока открыта памятка, шаг замирает (иначе «удержание» шло бы вслепую).
	if step_runner:
		step_runner.set_process(not _help_visible)

	if tutorial != null:
		var tutorial_hidden: bool = _help_visible or (game_state != null and (
			game_state.is_over() or game_state.is_paused
			or game_state.current_threat == GameState.Threat.AWAKE))
		tutorial.set_hidden(tutorial_hidden)

	# Обучающие подсказки старого прототипа живут только в легаси-режиме,
	# иначе они дублируют HUD новой петли.
	if tutorial_hud:
		var legacy_mode: bool = (game_state != null and game_state.current_mode == GameState.Mode.LEGACY)
		tutorial_hud.visible = legacy_mode
		tutorial_hud.set_process(legacy_mode)

	var mid_shift: Vector2 = _layer_shift("mid")
	var near_shift: Vector2 = _layer_shift("near")

	# Обновление физических инструментов
	for tool_item in _draggable_tool_items:
		tool_item.set_home_offset(near_shift)
		tool_item.update_tool(delta, mouse_pos)

	if step_runner and step_runner.is_active():
		_step_progress = step_runner.get_progress()

	# Обновление тактильных подсистем
	var tool_tip: Vector2 = held_tool.get_tip_position() if held_tool else mouse_pos
	var is_rag_held: bool = (held_tool != null and held_tool.tool_id == "cloth")
	var is_screw_held: bool = (held_tool != null and held_tool.tool_id == "screwdriver")

	if game_state and game_state.current_mode == GameState.Mode.LEGACY:
		if scrub_zone and scrub_zone.is_active:
			scrub_zone.update_scrub(delta, tool_tip, is_rag_held, mid_shift)

		if screw_manager and screw_manager.is_active:
			screw_manager.update_bolts(delta, tool_tip, is_screw_held, mid_shift, mouse_pos)

		if cable_plug:
			cable_plug.update_cable(delta, mouse_pos, mid_shift)

		if tutorial_hud:
			var held_id: String = held_tool.tool_id if held_tool else ""
			var cur_stage_idx: int = game_state.current_stage_index if game_state else 0
			tutorial_hud.update_hud(delta, cur_stage_idx, held_id, mouse_pos, mid_shift, scrub_zone, screw_manager, cable_plug)

	# Привязка острия отвертки к активному болту (работает в обоих режимах)
	if is_screw_held and _screw_tool_cached and screw_manager and screw_manager.active_bolt != null:
		var bolt_pos: Vector2 = screw_manager.active_bolt.base_pos + mid_shift
		_screw_tool_cached.anchor_tip_to(bolt_pos, mouse_pos)
	elif _screw_tool_cached and _screw_tool_cached.is_anchored and (screw_manager == null or screw_manager.active_bolt == null or not is_screw_held):
		_screw_tool_cached.release_anchor()

	if thermal_fx:
		var is_scrub_overheating: bool = (scrub_zone != null and scrub_zone.is_active and scrub_zone.get_speed_state() == 1)
		var cur_instability: float = game_state.robot.instability if (game_state and game_state.robot) else 20.0
		thermal_fx.update_thermal(delta, cur_instability, is_scrub_overheating)

	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		if parallax:
			parallax.reset()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true


func _layer_shift(layer_name: String) -> Vector2:
	if parallax == null:
		return Vector2.ZERO
	return parallax.offset_for_layer(layer_name)


func _draw_nine(tex: Texture2D, rect: Rect2, margins: Vector4, tint: Color = Color.WHITE) -> void:
	if tex == null:
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw <= margins.x + margins.z or th <= margins.y + margins.w \
		or rect.size.x <= margins.x + margins.z or rect.size.y <= margins.y + margins.w:
		draw_texture_rect(tex, rect, false, tint)
		return

	_nine_src_x[0] = 0.0
	_nine_src_x[1] = margins.x
	_nine_src_x[2] = tw - margins.z
	_nine_src_x[3] = tw

	_nine_src_y[0] = 0.0
	_nine_src_y[1] = margins.y
	_nine_src_y[2] = th - margins.w
	_nine_src_y[3] = th

	_nine_dst_x[0] = rect.position.x
	_nine_dst_x[1] = rect.position.x + margins.x
	_nine_dst_x[2] = rect.end.x - margins.z
	_nine_dst_x[3] = rect.end.x

	_nine_dst_y[0] = rect.position.y
	_nine_dst_y[1] = rect.position.y + margins.y
	_nine_dst_y[2] = rect.end.y - margins.w
	_nine_dst_y[3] = rect.end.y

	for i in 3:
		for j in 3:
			var src := Rect2(_nine_src_x[i], _nine_src_y[j],
				_nine_src_x[i + 1] - _nine_src_x[i], _nine_src_y[j + 1] - _nine_src_y[j])
			var dst := Rect2(_nine_dst_x[i], _nine_dst_y[j],
				_nine_dst_x[i + 1] - _nine_dst_x[i], _nine_dst_y[j + 1] - _nine_dst_y[j])
			if src.size.x > 0.0 and src.size.y > 0.0 and dst.size.x > 0.0 and dst.size.y > 0.0:
				draw_texture_rect_region(tex, dst, src, tint)


func _input(event: InputEvent) -> void:
	if is_cutscene_active:
		return

	if game_state == null:
		return

	if game_state.current_state == GameState.State.DONE or game_state.current_state == GameState.State.FAIL:
		return

	# Режим AWAKE: любая мышь штрафуется.
	# В фазе контроля угрозы движение тоже сбрасывает удержание.
	var is_awake: bool = (game_state.current_threat == GameState.Threat.AWAKE or game_state.current_state == GameState.State.AWAKE)
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if is_awake or game_state.current_phase == GameState.Phase.THREAT_CONTROL:
			game_state.on_mouse_moved(motion.relative.length())
		if is_awake:
			return

	if is_awake:
		return

	# F1 — памятка по управлению, TAB — заново открыть панель текущей фазы
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_F1:
			_help_visible = not _help_visible
			return
		if key_event.keycode == KEY_F2:
			if tutorial != null:
				tutorial.toggle_manual()
			return
		if key_event.keycode == KEY_ESCAPE and _help_visible:
			_help_visible = false
			return
		if key_event.keycode == KEY_TAB and not _is_overlay_active():
			if loop_screens != null and loop_screens.has_method("reopen_phase_panel"):
				loop_screens.reopen_phase_panel()
			return

	# Памятка — модальный экран: пока она открыта, игровой ввод и время стоят.
	if _help_visible:
		return

	# Если активен оверлей LoopScreens или игра на паузе — блокируем игровой ввод
	if _is_overlay_active() or game_state.is_paused:
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	var mid_shift: Vector2 = _layer_shift("mid")

	# ПКМ — быстро убрать инструмент из руки
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and held_tool != null:
		held_tool.put_down()
		held_tool = null
		return

	# 1. Интерактив перетаскивания физических инструментов (всегда доступен в покое)
	for t_id in draggable_tools:
		var tool_item: DraggableTool = draggable_tools[t_id]
		if tool_item.handle_mouse_input(event, mouse_pos):
			return

	# 2. Если новая петля и запущен StepRunner — передаём ввод исполнителю шага
	if game_state.current_mode == GameState.Mode.NEW:
		if step_runner and step_runner.is_active():
			if step_runner.handle_input(event):
				return
		return

	# 3. Легаси-режим (для совместимости с test_gameplay и прототипом)
	if cable_plug and cable_plug.is_active:
		if cable_plug.handle_input(event, mouse_pos):
			return

	if screw_manager and screw_manager.is_active:
		if screw_manager.handle_hatch_input(event, mouse_pos, mid_shift):
			return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_fallback_click(event.position)


func _handle_fallback_click(pos: Vector2) -> void:
	var mid_shift := _layer_shift("mid")
	var zone_pos := pos - mid_shift
	var stage: RepairStage = game_state.get_current_stage()
	if stage:
		for i in range(stage.zones.size()):
			var z: Dictionary = stage.zones[i]
			var r: Rect2 = Balance.to_rect(z.get("rect", null))
			if r.has_point(zone_pos):
				game_state.apply_repair(i, selected_tool)
				return


func _draw() -> void:
	var shake_offset := Vector2.ZERO
	if screen_shake > 0.0:
		shake_offset = Vector2(randf_range(-screen_shake, screen_shake), randf_range(-screen_shake, screen_shake))

	var far_shift := _layer_shift("far") + shake_offset
	var mid_shift := _layer_shift("mid")
	var near_shift := _layer_shift("near")

	# 1. Задний фон операционной / бокса
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), COLOR_BG)
	if tex_room_operating_bg:
		draw_texture_rect(tex_room_operating_bg, Rect2(far_shift, Vector2(1280, 720)), false)
	elif tex_room_blockout:
		draw_texture_rect(tex_room_blockout, Rect2(far_shift, Vector2(1280, 720)), false, Color(0.48, 0.52, 0.56))

	# 2. Вертикальный робот-монолит в полный рост
	var cur_stage_idx: int = game_state.current_stage_index if game_state else 0
	var head_jolt: Vector2 = cable_plug.head_shudder_offset if (cable_plug and cur_stage_idx == 2) else Vector2.ZERO
	var r_rect := Rect2(robot_rect.position + mid_shift + shake_offset + head_jolt, robot_rect.size)
	var is_awake := (game_state and game_state.current_state == GameState.State.AWAKE)
	var current_tex := tex_robot_awake if is_awake else tex_robot_calm

	# Мягкая контактная тень в стенную нишу за роботом
	if tex_robot_shadow:
		draw_texture_rect(tex_robot_shadow, Rect2(r_rect.position + Vector2(10.0, 14.0), r_rect.size), false)

	if current_tex:
		draw_texture_rect(current_tex, r_rect, false)
	else:
		var heat_col := Color(0.28, 0.35, 0.42).lerp(COLOR_ALERT, game_state.robot.get_heat_ratio() if (game_state and game_state.robot) else 0.0)
		draw_rect(r_rect, heat_col)

	# 2.3. Пульсирующее тепловое свечение радиатора внутри шасси робота
	if thermal_fx:
		thermal_fx.render_radiator(self, mid_shift + shake_offset)

	# 2.5. Удерживающие тяжелые промышленные ремни в стенной нише
	_draw_restraint_straps(mid_shift + shake_offset)

	# 3. Отрисовка тактильных подсистем по этапам ремонта
	# Кабель рисуется позже верстака: штекер физически лежит на столе.
	if game_state and game_state.current_mode == GameState.Mode.NEW:
		if scrub_zone and scrub_zone.is_active:
			scrub_zone.render(self, mid_shift + shake_offset)
		if screw_manager and screw_manager.is_active:
			screw_manager.render(self, mid_shift + shake_offset)
	else:
		if scrub_zone and cur_stage_idx == 0:
			scrub_zone.render(self, mid_shift + shake_offset)
		if screw_manager and cur_stage_idx == 1:
			screw_manager.render(self, mid_shift + shake_offset)

	# 3.5. Микро-струйки пара/дыма стравливания давления из вентиляционных клапанов торса и сочленений
	if thermal_fx:
		thermal_fx.render_steam_jets(self, mid_shift + shake_offset)

	# 6. Медицинский верстак из нержавеющей стали (передний план)
	var bench_y: float = 560.0 + near_shift.y
	if tex_workbench_surface:
		draw_texture_rect(tex_workbench_surface, Rect2(Vector2(0.0, bench_y), Vector2(1280.0, 160.0)), false)
	else:
		var bench_r := Rect2(Vector2(0.0, bench_y), Vector2(1280.0, 160.0))
		draw_rect(bench_r, COLOR_BENCH)
		draw_line(bench_r.position, Vector2(bench_r.end.x, bench_r.position.y), COLOR_BENCH_EDGE, 3.0)

	# Тиснёные лотки для физических инструментов на стальном столе
	for t in tools_data:
		var r: Rect2 = t.get("tool_rect", Rect2())
		r.position += near_shift

		var t_id := str(t.get("id", ""))
		var is_selected: bool = (selected_tool == t_id)

		# Тиснёное углубление на металле стола под инструмент
		draw_rect(r.grow(4.0), Color(0.06, 0.08, 0.10, 0.40))
		var recess_border: Color = Color(0.35, 0.85, 0.95, 0.40) if is_selected else Color(0.24, 0.28, 0.34, 0.50)
		draw_rect(r.grow(4.0), recess_border, false, 1.0)

		# Мягкая техническая маркировка на стали
		var label_col := Color(0.70, 0.82, 0.92) if is_selected else Color(0.42, 0.48, 0.54)
		var label_text: String = str(t.get("upper_label", ""))
		draw_string(font, Vector2(r.position.x, r.position.y - 8.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, label_col)

		# В новой петле отдельной иконки кабеля нет: в лотке лежит физический штекер.
		if t_id == "cable" and game_state != null and game_state.current_mode == GameState.Mode.NEW:
			if tex_tool_keyb and (cable_plug == null or not cable_plug.is_active):
				var icon_rect := Rect2(r.position + Vector2(18.0, 8.0), r.size - Vector2(36.0, 16.0))
				draw_texture_rect(tex_tool_keyb, icon_rect, false, Color(1.0, 1.0, 1.0, 0.85))

	# Физический штекер кабеля поверх верстака (иначе стол перекрывает его)
	if cable_plug != null:
		var cable_visible: bool = false
		if game_state != null and game_state.current_mode == GameState.Mode.NEW:
			cable_visible = cable_plug.is_active
		else:
			cable_visible = (cur_stage_idx == 2)
		if cable_visible:
			cable_plug.render(self, mid_shift + shake_offset)

	# Подсветка активной зоны шага (удержание/калибровка) в мировых координатах
	_draw_step_zone(mid_shift + shake_offset)

	# 7. Верхний статус-бар: Манометр Нестабильности
	var cur_inst := game_state.robot.instability if (game_state and game_state.robot) else 20.0
	var cur_thresh := game_state.robot.threshold if (game_state and game_state.robot) else 70.0
	var inst_ratio := clampf(cur_inst / 100.0, 0.0, 1.0)
	var status_rect := Rect2(40, 24, 620, 72)

	if tex_panel:
		_draw_nine(tex_panel, status_rect, PANEL_MARGIN, Color(1.18, 1.22, 1.26))
	else:
		draw_rect(status_rect, Color(0.08, 0.10, 0.12, 0.92))
		draw_rect(status_rect, COLOR_BENCH_EDGE, false, 2.0)

	# Манометр со стрелкой
	var gauge_rect := Rect2(48, 28, 64, 64)
	if tex_gauge:
		draw_texture_rect(tex_gauge, gauge_rect, false)
	var hub := gauge_rect.position + gauge_rect.size * 0.5
	var needle_ang := deg_to_rad(lerp(135.0, 405.0, inst_ratio))
	var needle_col := COLOR_ALERT if inst_ratio >= 0.7 else Color(0.92, 0.94, 0.96)
	draw_line(hub, hub + Vector2(cos(needle_ang), sin(needle_ang)) * 19.0, needle_col, 2.0)
	draw_circle(hub, 2.0, Color(0.35, 0.38, 0.42))

	draw_string(font, Vector2(120, 52), "НЕСТАБИЛЬНОСТЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)

	# Горизонтальная шкала
	var bar_rect := Rect2(270, 38, 260, 22)
	var bar_inner := bar_rect.grow(-6.0)
	if tex_bar_frame == null:
		draw_rect(bar_rect, Color(0.16, 0.18, 0.22))

	var fill_w := bar_inner.size.x * inst_ratio
	var bar_color := Color(0.35, 0.85, 0.55).lerp(COLOR_ALERT, inst_ratio)
	draw_rect(Rect2(bar_inner.position, Vector2(fill_w, bar_inner.size.y)), bar_color)

	if tex_bar_frame:
		_draw_nine(tex_bar_frame, bar_rect, BAR_MARGIN, Color(1.15, 1.18, 1.22))

	var thresh_t := clampf(cur_thresh / 100.0, 0.0, 1.0)
	var thresh_x := bar_inner.position.x + bar_inner.size.x * thresh_t
	draw_line(Vector2(thresh_x, bar_rect.position.y - 2), Vector2(thresh_x, bar_rect.end.y + 2), COLOR_ALERT, 2.0)

	var cur_inst_idx: int = clampi(int(cur_inst), 0, 100)
	draw_string(font, Vector2(545, 54), _instability_pct_strings[cur_inst_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_LIGHT)

	# 8. Панель текущего этапа / фазы
	if game_state and game_state.current_mode == GameState.Mode.NEW:
		var phase_rect := Rect2(720, 24, 520, 70)
		if tex_panel:
			_draw_nine(tex_panel, phase_rect, PANEL_MARGIN, Color(1.18, 1.22, 1.26))
		else:
			draw_rect(phase_rect, Color(0.08, 0.10, 0.12, 0.92))
			draw_rect(phase_rect, COLOR_BENCH_EDGE, false, 2.0)
		var p_title := _get_phase_title(game_state.current_phase)
		var p_instr := _get_phase_instruction(game_state.current_phase)
		draw_string(font, Vector2(750, 48), p_title, HORIZONTAL_ALIGNMENT_LEFT, 450.0, 12, COLOR_TEXT_LIGHT)
		draw_multiline_string(font, Vector2(750, 66), p_instr, HORIZONTAL_ALIGNMENT_LEFT, 450.0, 9, 2, COLOR_TEXT_DIM)
	else:
		var stage: RepairStage = game_state.get_current_stage() if game_state else null
		if stage:
			var stage_rect := Rect2(720, 24, 520, 70)
			if tex_panel:
				_draw_nine(tex_panel, stage_rect, PANEL_MARGIN, Color(1.18, 1.22, 1.26))
			else:
				draw_rect(stage_rect, Color(0.08, 0.10, 0.12, 0.92))
				draw_rect(stage_rect, COLOR_BENCH_EDGE, false, 2.0)
			draw_string(font, Vector2(750, 48), stage.title, HORIZONTAL_ALIGNMENT_LEFT, 450.0, 12, COLOR_TEXT_LIGHT)
			draw_multiline_string(font, Vector2(750, 66), stage.instruction, HORIZONTAL_ALIGNMENT_LEFT, 450.0, 9, 2, COLOR_TEXT_DIM)

	# 9. Строка оперативных сообщений / подсказок
	var msg_col := COLOR_ALERT if message_is_alert else COLOR_TEXT_LIGHT
	var msg_box := Rect2(320.0, 510.0 + near_shift.y, 640.0, 44.0)
	draw_rect(msg_box, Color(0.04, 0.06, 0.08, 0.88))
	draw_rect(msg_box, Color(0.25, 0.35, 0.42, 0.70), false, 1.0)
	draw_multiline_string(font, msg_box.position + Vector2(14.0, 16.0), message_text, HORIZONTAL_ALIGNMENT_LEFT, 612.0, 10, 2, msg_col)

	# 9.5. Тактильный обучающий HUD и живые подсказки инструментов (только в легаси-режиме)
	if tutorial_hud and (game_state == null or game_state.current_mode == GameState.Mode.LEGACY):
		tutorial_hud.render(self, font)

	# 10. Хирургический прожектор и глухая виньетка
	_draw_spotlight_and_vignette()

	# 10.5. HUD ремонта: шаг, инструмент, прогресс, таймер, подсказки
	_draw_step_hud()
	_draw_verify_banner()
	_draw_help_overlay()

	# 11. Экран тревоги при пробуждении
	if is_awake:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.85, 0.15, 0.1, 0.18))
		draw_rect(Rect2(420, 106, 440, 68), Color(0.35, 0.05, 0.05, 0.95))
		draw_rect(Rect2(420, 106, 440, 68), COLOR_ALERT, false, 2.0)
		draw_string(font, Vector2(440, 144), "НЕ ДВИГАЙ МЫШЬЮ!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.8))
		var sec_left: float = maxf(game_state.freeze_left, 0.0) if game_state else 0.0
		var freeze_tenth := int(sec_left * 10.0)
		if freeze_tenth != _last_freeze_tenth:
			_last_freeze_tenth = freeze_tenth
			_cached_freeze_str = "%.1f c" % (float(freeze_tenth) * 0.1)
		draw_string(font, Vector2(760, 144), _cached_freeze_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.4, 0.3))

	# 12. Вспышка ошибки / срыва
	if flash_timer > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(1.0, 0.2, 0.1, flash_timer * 0.4))


func _step_hint_text(step: Dictionary) -> String:
	var tool_id := str(step.get("tool", "none"))
	var in_hand: bool = held_tool != null and held_tool.tool_id == tool_id
	match str(step.get("type", "")):
		"scrub":
			if tool_id != "none" and not in_hand:
				return "Кликните ЛКМ по ветоши в лотке — она останется в руке.\nЗатем ведите курсор по контактам влево-вправо."
			return "Ведите ветошью по контактам влево-вправо.\nСлишком медленно — прогресса нет, слишком быстро — перегрев."
		"unbolt":
			if not in_hand:
				return "Кликните ЛКМ по отвёртке в лотке внизу.\nОстрие отвёртки должно быть на болте."
			return "Наведите острие на болт и вращайте мышью.\nНа каждый болт — 3 полных оборота без рывков."
		"cable_lock":
			return "Схватите кабель в правом лотке и тащите к височному порту.\nКолесиком мыши выставьте паз на 12 часов и удержите 0.8 с."
		"hold":
			return "Держите курсор в подсвеченной зоне и не двигайте мышью 3 с."
		"calibrate":
			return "Зажмите ЛКМ в зоне и тяните вправо до значения 65.\nУдержите в допуске ±5, пока не заполнится полоса."
		_:
			return ""


func _draw_hand_indicator() -> void:
	var step: Dictionary = game_state.get_current_step() if game_state != null else {}
	var need_tool: String = str(step.get("tool", "none"))
	var in_hand_text := "ИНСТРУМЕНТ НЕ ВЗЯТ · ЛКМ ПО ЛОТКУ"
	var col := COLOR_ALERT
	if need_tool == "none":
		in_hand_text = "ИНСТРУМЕНТ: НЕ ТРЕБУЕТСЯ"
		col = COLOR_TEXT_DIM
	elif held_tool != null and held_tool.label != "":
		in_hand_text = "В РУКЕ: " + held_tool.label.to_upper()
		col = COLOR_SUCCESS
	draw_string(font, Vector2(40, 118), in_hand_text, HORIZONTAL_ALIGNMENT_LEFT, 300.0, 8, col)
	draw_string(font, Vector2(40, 136), "F1 — КАК ИГРАТЬ · TAB — ПАНЕЛЬ ФАЗЫ", HORIZONTAL_ALIGNMENT_LEFT, 340.0, 7, COLOR_TEXT_DIM)


func _draw_step_zone(shift: Vector2) -> void:
	if step_runner == null or not step_runner.is_active():
		return
	var step_type: String = step_runner.get_step_type()
	if step_type != "hold" and step_type != "calibrate" and step_type != "cable_lock":
		return
	var r: Rect2 = step_runner.get_step_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var rr := Rect2(r.position + shift, r.size).grow(6.0)
	var pulse: float = 0.55 + 0.25 * sin(Time.get_ticks_msec() / 180.0)
	var col := Color(0.35, 0.92, 0.70, pulse)
	var arm := 12.0
	# Угловые скобки активной зоны
	draw_line(rr.position, rr.position + Vector2(arm, 0), col, 2.0)
	draw_line(rr.position, rr.position + Vector2(0, arm), col, 2.0)
	draw_line(Vector2(rr.end.x, rr.position.y), Vector2(rr.end.x - arm, rr.position.y), col, 2.0)
	draw_line(Vector2(rr.end.x, rr.position.y), Vector2(rr.end.x, rr.position.y + arm), col, 2.0)
	draw_line(Vector2(rr.position.x, rr.end.y), Vector2(rr.position.x + arm, rr.end.y), col, 2.0)
	draw_line(Vector2(rr.position.x, rr.end.y), Vector2(rr.position.x, rr.end.y - arm), col, 2.0)
	draw_line(rr.end, rr.end - Vector2(arm, 0), col, 2.0)
	draw_line(rr.end, rr.end - Vector2(0, arm), col, 2.0)


func _draw_step_hud() -> void:
	if game_state == null or game_state.current_mode != GameState.Mode.NEW:
		return
	if _help_visible:
		return

	if game_state.current_phase == GameState.Phase.REPAIR:
		_draw_hand_indicator()
	if game_state.current_phase == GameState.Phase.THREAT_CONTROL:
		_draw_threat_hold_hud()
		return
	if game_state.current_phase != GameState.Phase.REPAIR:
		return

	var step: Dictionary = game_state.get_current_step()
	if step.is_empty():
		return

	var rect := Rect2(806.0, 300.0, 452.0, 200.0)
	draw_rect(rect, Color(0.04, 0.06, 0.08, 0.94))
	draw_rect(rect, Color(0.30, 0.40, 0.47, 0.85), false, 1.0)

	var steps: Array = game_state._current_part.get("steps", [])
	var total: int = maxi(steps.size(), 1)
	var idx: int = clampi(game_state._current_step_index + 1, 1, total)
	draw_string(font, rect.position + Vector2(14.0, 22.0), "ОПЕРАЦИЯ %d/%d" % [idx, total], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_TEXT_DIM)
	draw_string(font, rect.position + Vector2(14.0, 42.0), str(step.get("label", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 10, COLOR_TEXT_LIGHT)

	var tool_id := str(step.get("tool", "none"))
	var in_hand: bool = held_tool != null and held_tool.tool_id == tool_id
	var tool_text := "НЕ ТРЕБУЕТСЯ"
	var tool_col := COLOR_TEXT_DIM
	if tool_id != "none":
		tool_text = game_state.get_tool_label(tool_id).to_upper()
		if in_hand:
			tool_text += " · В РУКЕ"
			tool_col = COLOR_SUCCESS
		else:
			tool_text += " · НЕ ВЗЯТ"
			tool_col = COLOR_ALERT
	draw_string(font, rect.position + Vector2(14.0, 62.0), "ИНСТРУМЕНТ: " + tool_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 8, tool_col)

	var bar := Rect2(rect.position + Vector2(14.0, 72.0), Vector2(200.0, 12.0))
	draw_rect(bar, Color(0.12, 0.14, 0.17))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_step_progress, 0.0, 1.0), bar.size.y)), COLOR_SUCCESS)
	draw_rect(bar, Color(0.35, 0.45, 0.52, 0.80), false, 1.0)
	draw_string(font, rect.position + Vector2(14.0, 100.0), "ПРОГРЕСС %d%%" % int(clampf(_step_progress, 0.0, 1.0) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_TEXT_DIM)

	var limit: float = game_state.get_step_limit()
	if limit > 0.0:
		var left: float = game_state.get_step_time_left()
		var tr: float = clampf(left / limit, 0.0, 1.0)
		var tb := Rect2(rect.position + Vector2(238.0, 72.0), Vector2(200.0, 12.0))
		draw_rect(tb, Color(0.12, 0.14, 0.17))
		var tcol := COLOR_SUCCESS if tr > 0.35 else COLOR_ALERT
		draw_rect(Rect2(tb.position, Vector2(tb.size.x * tr, tb.size.y)), tcol)
		draw_rect(tb, Color(0.35, 0.45, 0.52, 0.80), false, 1.0)
		draw_string(font, rect.position + Vector2(238.0, 100.0), "ВРЕМЯ %.1f c" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, tcol)

	var hint_y := 122.0
	if str(step.get("type", "")) == "calibrate" and step_runner != null:
		var p: Dictionary = step.get("params", {}) if step.get("params") is Dictionary else {}
		var mn: float = float(p.get("min", 0.0))
		var mx: float = float(p.get("max", 100.0))
		var tgt: float = float(p.get("target", 50.0))
		var tol: float = float(p.get("tolerance", 5.0))
		var val: float = float(step_runner.get_calibration_value())
		var span: float = maxf(mx - mn, 0.001)
		var bx := Rect2(rect.position + Vector2(14.0, 124.0), Vector2(rect.size.x - 28.0, 14.0))
		draw_rect(bx, Color(0.10, 0.12, 0.15))
		var zone_x: float = bx.position.x + bx.size.x * clampf((tgt - tol - mn) / span, 0.0, 1.0)
		var zone_w: float = bx.size.x * clampf((2.0 * tol) / span, 0.0, 1.0)
		draw_rect(Rect2(zone_x, bx.position.y, zone_w, bx.size.y), Color(0.20, 0.55, 0.32, 0.90))
		var vx: float = bx.position.x + bx.size.x * clampf((val - mn) / span, 0.0, 1.0)
		draw_line(Vector2(vx, bx.position.y - 3.0), Vector2(vx, bx.end.y + 3.0), Color(1.0, 0.90, 0.35), 2.0)
		draw_string(font, rect.position + Vector2(14.0, 156.0), "КАЛИБРОВКА: %d / ЦЕЛЬ %d ±%d" % [int(round(val)), int(tgt), int(tol)], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 8, COLOR_TEXT_LIGHT)
		hint_y = 170.0
	elif str(step.get("type", "")) == "scrub" and scrub_zone != null and in_hand:
		var speed_state: int = scrub_zone.get_speed_state()
		var speed_val: float = scrub_zone.get_current_speed()
		var speed_text := "ТЕМП: ДВИГАЙТЕ ВЕТОШЬ ВЛЕВО-ВПРАВО"
		var speed_col := COLOR_TEXT_DIM
		if speed_val >= 5.0:
			if speed_state == 0:
				speed_text = "ТЕМП: НОРМА"
				speed_col = COLOR_SUCCESS
			elif speed_state == 1:
				speed_text = "ТЕМП: ПЕРЕГРЕВ — СБАВЬТЕ СКОРОСТЬ"
				speed_col = COLOR_ALERT
			else:
				speed_text = "ТЕМП: СЛИШКОМ МЕДЛЕННО — ТРИТЕ БЫСТРЕЕ"
				speed_col = COLOR_ALERT
		draw_string(font, rect.position + Vector2(14.0, 122.0), speed_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 8, speed_col)
		hint_y = 140.0

	var hint := _step_hint_text(step)
	if hint != "":
		draw_multiline_string(font, rect.position + Vector2(14.0, hint_y + 8.0), hint, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28.0, 8, 4, COLOR_TEXT_DIM)


func _draw_threat_hold_hud() -> void:
	var left: float = game_state.get_threat_hold_left()
	var total: float = maxf(game_state.get_threat_hold_target(), 0.001)
	var ratio: float = clampf(1.0 - left / total, 0.0, 1.0)
	var rect := Rect2(390.0, 420.0, 500.0, 82.0)
	draw_rect(rect, Color(0.05, 0.07, 0.09, 0.95))
	draw_rect(rect, Color(0.35, 0.85, 0.55, 0.65), false, 2.0)
	draw_string(font, rect.position + Vector2(0.0, 28.0), "НЕ ДВИГАЙТЕ МЫШЬЮ", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, COLOR_TEXT_LIGHT)
	var bar := Rect2(rect.position + Vector2(30.0, 40.0), Vector2(rect.size.x - 60.0, 14.0))
	draw_rect(bar, Color(0.12, 0.14, 0.17))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), COLOR_SUCCESS)
	draw_rect(bar, Color(0.35, 0.45, 0.52, 0.80), false, 1.0)
	draw_string(font, rect.position + Vector2(0.0, 72.0), "%.1f / %.1f c" % [maxf(left, 0.0), total], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 9, COLOR_TEXT_DIM)


func _draw_verify_banner() -> void:
	if _verify_banner_timer <= 0.0 or _verify_banner_text == "":
		return
	var alpha: float = clampf(_verify_banner_timer / 0.6, 0.0, 1.0)
	var rect := Rect2(340.0, 118.0, 600.0, 54.0)
	draw_rect(rect, Color(0.04, 0.06, 0.08, 0.94 * alpha))
	draw_rect(rect, Color(_verify_banner_color.r, _verify_banner_color.g, _verify_banner_color.b, alpha), false, 2.0)
	draw_string(font, rect.position + Vector2(0.0, 34.0), _verify_banner_text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color(_verify_banner_color.r, _verify_banner_color.g, _verify_banner_color.b, alpha))


func _draw_help_overlay() -> void:
	if not _help_visible:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.0, 0.0, 0.0, 0.74))
	var rect := Rect2(210.0, 60.0, 860.0, 600.0)
	draw_rect(rect, Color(0.05, 0.07, 0.09, 0.98))
	draw_rect(rect, Color(0.40, 0.50, 0.57), false, 2.0)
	draw_string(font, rect.position + Vector2(30.0, 44.0), "КАК ИГРАТЬ", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_TEXT_LIGHT)
	var line_y := 84.0
	for line in HELP_LINES:
		if line != "":
			draw_string(font, rect.position + Vector2(30.0, line_y), line, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 60.0, 9, COLOR_TEXT_LIGHT)
		line_y += 17.0


func _draw_restraint_straps(shift: Vector2) -> void:
	for s_rect in strap_rects:
		var r := Rect2(s_rect.position + shift, s_rect.size)

		# 1. Затененная контактная тень под ремнем на корпусе робота
		draw_rect(Rect2(r.position + Vector2(0.0, 3.0), r.size), Color(0.02, 0.03, 0.04, 0.65))

		# 2. Основная полоса ремня (армированная кожа / кевлар)
		draw_rect(r, COLOR_STRAP)

		# 3. Декоративные канавки / строчки по верхнему и нижнему краю
		draw_line(Vector2(r.position.x, r.position.y + 2.0), Vector2(r.end.x, r.position.y + 2.0), Color(0.32, 0.28, 0.25, 0.7), 1.0)
		draw_line(Vector2(r.position.x, r.end.y - 2.0), Vector2(r.end.x, r.end.y - 2.0), Color(0.06, 0.05, 0.04, 0.9), 1.0)

		# 4. Настенные стальные анкерные скобы на стойках ниши (слева и справа)
		var bracket_w: float = 14.0
		var left_bracket := Rect2(r.position.x - 4.0, r.position.y - 3.0, bracket_w, r.size.y + 6.0)
		var right_bracket := Rect2(r.end.x - bracket_w + 4.0, r.position.y - 3.0, bracket_w, r.size.y + 6.0)
		draw_rect(left_bracket, Color(0.24, 0.28, 0.34))
		draw_rect(left_bracket, Color(0.45, 0.52, 0.60), false, 1.0)
		draw_circle(left_bracket.position + left_bracket.size * 0.5, 2.5, Color(0.70, 0.78, 0.85))

		draw_rect(right_bracket, Color(0.24, 0.28, 0.34))
		draw_rect(right_bracket, Color(0.45, 0.52, 0.60), false, 1.0)
		draw_circle(right_bracket.position + right_bracket.size * 0.5, 2.5, Color(0.70, 0.78, 0.85))

		# 5. Центральная кованая пряжка с натяжителем
		var buckle_w: float = 32.0
		var buckle_h: float = r.size.y + 6.0
		var buckle_x: float = r.position.x + r.size.x * 0.5 - buckle_w * 0.5
		var buckle_rect := Rect2(buckle_x, r.position.y - 3.0, buckle_w, buckle_h)

		draw_rect(buckle_rect, Color(0.12, 0.14, 0.17))
		draw_rect(buckle_rect, COLOR_STRAP_BUCKLE, false, 2.0)
		# Язычок / замок пряжки
		draw_line(Vector2(buckle_x + buckle_w * 0.5, buckle_rect.position.y + 2.0), Vector2(buckle_x + buckle_w * 0.5, buckle_rect.end.y - 2.0), Color(0.85, 0.90, 0.95), 2.0)
		draw_circle(Vector2(buckle_x + 6.0, buckle_rect.position.y + buckle_h * 0.5), 1.5, Color(0.85, 0.90, 0.95))
		draw_circle(Vector2(buckle_x + buckle_w - 6.0, buckle_rect.position.y + buckle_h * 0.5), 1.5, Color(0.85, 0.90, 0.95))


func _draw_spotlight_and_vignette() -> void:
	# 1. Хирургический конус света сверху вниз на торс робота
	var cone_alpha := 0.035 * spotlight_flicker
	draw_colored_polygon(_cone_pts, Color(0.80, 0.92, 1.0, cone_alpha))

	# 2. Мягкое фокальное световое пятно на роботе
	var spot_center := Vector2(640.0, 270.0)
	for i in 4:
		var rad: float = _spot_radii[i]
		var a: float = _spot_alphas[i] * spotlight_flicker
		draw_circle(spot_center, rad, Color(0.82, 0.92, 0.98, a))

	# 3. Давящая операционная виньетка по краям экрана (смягчает и затемняет боковые серые шкафы)
	# Левый край
	draw_rect(Rect2(0.0, 0.0, 180.0, 720.0), Color(0.01, 0.02, 0.03, 0.50))
	draw_rect(Rect2(0.0, 0.0, 320.0, 720.0), Color(0.01, 0.02, 0.03, 0.28))
	# Правый край
	draw_rect(Rect2(1100.0, 0.0, 180.0, 720.0), Color(0.01, 0.02, 0.03, 0.50))
	draw_rect(Rect2(960.0, 0.0, 320.0, 720.0), Color(0.01, 0.02, 0.03, 0.28))
	# Верхний край
	draw_rect(Rect2(0.0, 0.0, 1280.0, 90.0), Color(0.01, 0.02, 0.03, 0.35))
