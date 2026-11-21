class_name LoopScreens
extends CanvasLayer

## Координатор экранов и модальных окон новой петли ремонта
## Управляет видимостью панелей по фазам, без наложения модальных окон
## Связывает UI-интенты с GameState без хранения логики баланса

enum Phase {
	BRIEFING = 0,
	DIAGNOSTICS = 1,
	PART_SELECT = 2,
	DOC_SEARCH = 3,
	REPAIR = 4,
	THREAT_CONTROL = 5,
	VERIFY = 6,
	SHIFT_COMPLETE = 7,
	SHIFT_FAILED = 8
}

enum Threat {
	CALM = 0,
	TWITCH = 1,
	AWAKE = 2
}

const DIAGNOSTICS_SCENE_PATH := "res://scenes/ui/DiagnosticsPanel.tscn"
const CARDFILE_SCENE_PATH := "res://scenes/ui/CardFile.tscn"
const DOCREADER_SCENE_PATH := "res://scenes/ui/DocReader.tscn"
const THREAT_SCENE_PATH := "res://scenes/ui/ThreatOverlay.tscn"
const VERIFY_SCENE_PATH := "res://scenes/ui/VerifyPanel.tscn"

var diagnostics_panel: DiagnosticsPanel
var card_file: CardFile
var doc_reader: DocReader
var threat_overlay: ThreatOverlay
var verify_panel: VerifyPanel
var part_markers: PartMarkers

var world_root: Node = null

var _game_state: Node = null
var _current_phase: int = Phase.BRIEFING
var _current_modal: CanvasLayer = null
var _modal_before_wake: CanvasLayer = null

var _last_diagnostics_report: Dictionary = {}
var _last_verify_details: Dictionary = {}
var _last_read_card: Dictionary = {}


func _ready() -> void:
	layer = 15
	_ensure_panels()


func _ensure_panels() -> void:
	if diagnostics_panel == null:
		var diag_scene = load(DIAGNOSTICS_SCENE_PATH)
		if diag_scene:
			diagnostics_panel = diag_scene.instantiate()
			add_child(diagnostics_panel)

	if card_file == null:
		var card_scene = load(CARDFILE_SCENE_PATH)
		if card_scene:
			card_file = card_scene.instantiate()
			add_child(card_file)

	if doc_reader == null:
		var doc_scene = load(DOCREADER_SCENE_PATH)
		if doc_scene:
			doc_reader = doc_scene.instantiate()
			add_child(doc_reader)

	if threat_overlay == null:
		var threat_scene = load(THREAT_SCENE_PATH)
		if threat_scene:
			threat_overlay = threat_scene.instantiate()
			add_child(threat_overlay)

	if verify_panel == null:
		var ver_scene = load(VERIFY_SCENE_PATH)
		if ver_scene:
			verify_panel = ver_scene.instantiate()
			add_child(verify_panel)

	if part_markers == null:
		part_markers = PartMarkers.new()
		part_markers.name = "PartMarkers"
		part_markers.z_index = 6
		if world_root != null:
			world_root.add_child(part_markers)
		elif get_parent() is Node2D:
			get_parent().add_child(part_markers)
		else:
			add_child(part_markers)

	_connect_panel_signals()


func set_world_root(root: Node) -> void:
	world_root = root
	if part_markers != null and part_markers.get_parent() != root and root != null:
		var p := part_markers.get_parent()
		if p != null:
			p.remove_child(part_markers)
		root.add_child(part_markers)


func _connect_panel_signals() -> void:
	if diagnostics_panel != null and not diagnostics_panel.scan_requested.is_connected(_on_panel_scan_requested):
		diagnostics_panel.scan_requested.connect(_on_panel_scan_requested)
	if diagnostics_panel != null and not diagnostics_panel.closed.is_connected(_on_panel_closed):
		diagnostics_panel.closed.connect(_on_panel_closed)
	if diagnostics_panel != null and not diagnostics_panel.part_selected.is_connected(_on_panel_part_clicked):
		diagnostics_panel.part_selected.connect(_on_panel_part_clicked)

	if part_markers != null and not part_markers.part_clicked.is_connected(_on_panel_part_clicked):
		part_markers.part_clicked.connect(_on_panel_part_clicked)

	if card_file != null and not card_file.card_taken.is_connected(_on_panel_card_taken):
		card_file.card_taken.connect(_on_panel_card_taken)
	if card_file != null and not card_file.closed.is_connected(_on_panel_closed):
		card_file.closed.connect(_on_panel_closed)

	if doc_reader != null and not doc_reader.repair_requested.is_connected(_on_panel_repair_requested):
		doc_reader.repair_requested.connect(_on_panel_repair_requested)
	if doc_reader != null and not doc_reader.closed.is_connected(_on_panel_closed):
		doc_reader.closed.connect(_on_panel_closed)

	if threat_overlay != null and not threat_overlay.pause_requested.is_connected(_on_panel_pause_requested):
		threat_overlay.pause_requested.connect(_on_panel_pause_requested)
	if threat_overlay != null and not threat_overlay.resume_requested.is_connected(_on_panel_resume_requested):
		threat_overlay.resume_requested.connect(_on_panel_resume_requested)

	if verify_panel != null and not verify_panel.confirmed.is_connected(_on_panel_verify_confirmed):
		verify_panel.confirmed.connect(_on_panel_verify_confirmed)
	if verify_panel != null and not verify_panel.closed.is_connected(_on_panel_closed):
		verify_panel.closed.connect(_on_panel_closed)


func bind(game_state: Node) -> void:
	_ensure_panels()
	_game_state = game_state
	if _game_state == null:
		return

	if _game_state.has_signal("phase_changed") and not _game_state.phase_changed.is_connected(_on_phase_changed):
		_game_state.phase_changed.connect(_on_phase_changed)

	if _game_state.has_signal("diagnostics_ready") and not _game_state.diagnostics_ready.is_connected(_on_diagnostics_ready):
		_game_state.diagnostics_ready.connect(_on_diagnostics_ready)

	if _game_state.has_signal("part_selected") and not _game_state.part_selected.is_connected(_on_part_selected):
		_game_state.part_selected.connect(_on_part_selected)

	if _game_state.has_signal("documentation_requested") and not _game_state.documentation_requested.is_connected(_on_documentation_requested):
		_game_state.documentation_requested.connect(_on_documentation_requested)

	if _game_state.has_signal("document_read") and not _game_state.document_read.is_connected(_on_document_read):
		_game_state.document_read.connect(_on_document_read)

	if _game_state.has_signal("wake_started") and not _game_state.wake_started.is_connected(_on_wake_started):
		_game_state.wake_started.connect(_on_wake_started)

	if _game_state.has_signal("wake_ended") and not _game_state.wake_ended.is_connected(_on_wake_ended):
		_game_state.wake_ended.connect(_on_wake_ended)

	if _game_state.has_signal("pause_changed") and not _game_state.pause_changed.is_connected(_on_pause_changed):
		_game_state.pause_changed.connect(_on_pause_changed)

	if _game_state.has_signal("verification_finished") and not _game_state.verification_finished.is_connected(_on_verification_finished):
		_game_state.verification_finished.connect(_on_verification_finished)

	if _game_state.has_signal("shift_finished") and not _game_state.shift_finished.is_connected(_on_shift_finished):
		_game_state.shift_finished.connect(_on_shift_finished)


func _on_phase_changed(phase: int) -> void:
	_current_phase = phase
	match phase:
		Phase.BRIEFING:
			_close_all_modals()
			if part_markers:
				part_markers.hide_all()
			if threat_overlay:
				threat_overlay.set_hud_pause_visible(false)

		Phase.DIAGNOSTICS:
			_close_all_modals()
			if part_markers:
				part_markers.hide_all()
			if threat_overlay:
				threat_overlay.set_hud_pause_visible(false)
			var rep: Dictionary = {}
			if _game_state != null and _game_state.has_method("get_diagnostics_report"):
				rep = _game_state.get_diagnostics_report()
			if rep.is_empty():
				_last_diagnostics_report.clear()
			elif not _last_diagnostics_report.is_empty():
				rep = _last_diagnostics_report
			_open_modal(diagnostics_panel, [rep])

		Phase.PART_SELECT:
			_close_all_modals()
			if threat_overlay:
				threat_overlay.set_hud_pause_visible(false)
			var parts: Array = []
			if _last_diagnostics_report.has("parts"):
				parts = _last_diagnostics_report["parts"]
			elif _game_state != null and _game_state.has_method("get_diagnostics_report"):
				var rep: Dictionary = _game_state.get_diagnostics_report()
				if rep.has("parts"):
					parts = rep["parts"]
			if part_markers:
				part_markers.show_for(parts)

		Phase.DOC_SEARCH:
			_close_all_modals()
			if part_markers:
				part_markers.hide_all()
			if threat_overlay:
				threat_overlay.set_hud_pause_visible(false)
			var idx: Variant = null
			if _game_state != null and _game_state.has_method("get_documentation_index"):
				idx = _game_state.get_documentation_index()
			_open_modal(card_file, [idx])

		Phase.REPAIR:
			_close_all_modals()
			if part_markers:
				part_markers.hide_all()
			if threat_overlay:
				threat_overlay.set_hud_pause_visible(true)

		Phase.THREAT_CONTROL:
			_close_all_modals()
			if part_markers:
				part_markers.hide_all()
			if threat_overlay:
				threat_overlay.set_hud_pause_visible(true)

		Phase.VERIFY:
			_close_all_modals()
			if part_markers:
				part_markers.hide_all()
			if threat_overlay:
				threat_overlay.set_hud_pause_visible(false)
			_open_modal(verify_panel, [_last_verify_details])

		Phase.SHIFT_COMPLETE, Phase.SHIFT_FAILED:
			_close_all_modals()
			if part_markers:
				part_markers.hide_all()
			if threat_overlay:
				threat_overlay.set_hud_pause_visible(false)
				threat_overlay.hide_wake()
				threat_overlay.hide_pause()


func _on_diagnostics_ready(report: Dictionary) -> void:
	_last_diagnostics_report = report
	if diagnostics_panel != null:
		diagnostics_panel.set_report(report)


func _on_part_selected(part_id: String, correct: bool) -> void:
	if part_markers == null:
		return
	if correct:
		part_markers.select_part(part_id)
		part_markers.hide_all()
	else:
		part_markers.flash_error(part_id)


func _on_documentation_requested() -> void:
	if _current_phase == Phase.DOC_SEARCH and card_file != null and not card_file.is_open():
		var idx: Variant = null
		if _game_state != null and _game_state.has_method("get_documentation_index"):
			idx = _game_state.get_documentation_index()
		_open_modal(card_file, [idx])


func _on_document_read(card_id: String, correct: bool) -> void:
	if correct:
		if card_file != null:
			card_file.close()
		var card_dict := _last_read_card
		if card_dict.is_empty() and card_file != null and card_file._cards_data.has(card_id):
			card_dict = card_file._cards_data[card_id]
		_open_modal(doc_reader, [card_dict])
	else:
		if card_file != null:
			card_file.show_error("НЕ ТОТ РЕГЛАМЕНТ")


func _on_wake_started(duration: float) -> void:
	_modal_before_wake = _current_modal
	if _current_modal != null:
		_current_modal.visible = false
	if threat_overlay != null:
		threat_overlay.show_wake(duration)


func _on_wake_ended() -> void:
	if threat_overlay != null:
		threat_overlay.hide_wake()
	if _modal_before_wake != null:
		if _current_phase != Phase.SHIFT_COMPLETE and _current_phase != Phase.SHIFT_FAILED:
			_modal_before_wake.visible = true
			_current_modal = _modal_before_wake
		_modal_before_wake = null


func _on_pause_changed(paused: bool, _reason: String) -> void:
	if threat_overlay == null:
		return
	if paused:
		threat_overlay.show_pause()
	else:
		threat_overlay.hide_pause()


func _on_verification_finished(passed: bool, details: Dictionary) -> void:
	_last_verify_details = details.duplicate()
	_last_verify_details["passed"] = passed


## Заново открыть панель текущей фазы (TAB), чтобы закрытая панель не тупила петлю.
func reopen_phase_panel() -> void:
	match _current_phase:
		Phase.DIAGNOSTICS, Phase.PART_SELECT:
			var rep: Dictionary = {}
			if _game_state != null and _game_state.has_method("get_diagnostics_report"):
				rep = _game_state.get_diagnostics_report()
			elif not _last_diagnostics_report.is_empty():
				rep = _last_diagnostics_report
			_open_modal(diagnostics_panel, [rep])
		Phase.DOC_SEARCH:
			var idx: Variant = null
			if _game_state != null and _game_state.has_method("get_documentation_index"):
				idx = _game_state.get_documentation_index()
			_open_modal(card_file, [idx])
		Phase.VERIFY:
			_open_modal(verify_panel, [_last_verify_details])


func _on_shift_finished(_success: bool, _stats: Dictionary) -> void:
	_close_all_modals()
	if threat_overlay != null:
		threat_overlay.set_hud_pause_visible(false)
		threat_overlay.hide_wake()
		threat_overlay.hide_pause()


# Интенты от панелей к GameState

func _on_panel_scan_requested() -> void:
	if _game_state != null and _game_state.has_method("run_diagnostics"):
		var res: Dictionary = _game_state.run_diagnostics()
		if not res.is_empty():
			_on_diagnostics_ready(res)


func _on_panel_part_clicked(part_id: String) -> void:
	if _game_state != null and _game_state.has_method("select_part"):
		_game_state.select_part(part_id)


func _on_panel_card_taken(card_id: String) -> void:
	if _game_state != null and _game_state.has_method("read_card"):
		_last_read_card = _game_state.read_card(card_id)
		if not _last_read_card.is_empty() and (_game_state == null or not _game_state.has_signal("document_read")):
			_on_document_read(card_id, true)


func _on_panel_repair_requested() -> void:
	if doc_reader != null:
		doc_reader.close()
	if _game_state != null and _game_state.has_method("begin_repair"):
		_game_state.begin_repair()


func _on_panel_pause_requested() -> void:
	if _game_state != null and _game_state.has_method("request_pause"):
		_game_state.request_pause("manual")


func _on_panel_resume_requested() -> void:
	if _game_state != null and _game_state.has_method("request_resume"):
		_game_state.request_resume()


func _on_panel_verify_confirmed(passed: bool) -> void:
	if _game_state != null and _game_state.has_method("run_verification"):
		_game_state.run_verification()


func _on_panel_closed() -> void:
	if _current_modal != null and not _current_modal.visible:
		_current_modal = null


func _open_modal(modal: CanvasLayer, args: Array = []) -> void:
	if modal == null:
		return
	if _current_modal != null and _current_modal != modal:
		_close_modal(_current_modal)
	_current_modal = modal
	if modal.has_method("open"):
		modal.callv("open", args)
	else:
		modal.visible = true


func _close_modal(modal: CanvasLayer) -> void:
	if modal == null:
		return
	if modal.has_method("close"):
		modal.close()
	else:
		modal.visible = false
	if _current_modal == modal:
		_current_modal = null


func _close_all_modals() -> void:
	if diagnostics_panel:
		diagnostics_panel.close()
	if card_file:
		card_file.close()
	if doc_reader:
		doc_reader.close()
	if verify_panel:
		verify_panel.close()
	_current_modal = null
