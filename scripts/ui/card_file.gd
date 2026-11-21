class_name CardFile
extends CanvasLayer

## Картотека технической документации (слой 30, ширина <= 680 px)
## Отображает ящики A, B, C, карточки регламентов и поиск по ID

signal card_taken(card_id: String)
signal closed

const PALETTE_GUNMETAL := Color("#1A2028")
const PALETTE_CLOUD_WHITE := Color("#EDF0F4")
const PALETTE_SIGNAL := Color("#748B91")
const PALETTE_ALERT := Color("#E62815")
const PALETTE_STEEL := Color("#5A5A59")
const PALETTE_PALE_STEEL := Color("#C4CDD6")
const PALETTE_COOL_SLATE := Color("#D1CCC7")

const DRAWER_TEXTURE_CLOSED_PATH := "res://assets/sprites/ui/card_drawer.png"
const DRAWER_TEXTURE_OPEN_PATH := "res://assets/sprites/ui/card_drawer_open.png"
const CARD_TEXTURE_PATH := "res://assets/sprites/ui/doc_card.png"

@onready var dimmer: ColorRect = $Dimmer
@onready var cabinet: Control = $Cabinet
@onready var search_edit: LineEdit = $Cabinet/SearchBox/SearchEdit
@onready var error_label: Label = $Cabinet/ErrorLabel
@onready var drawers_box: VBoxContainer = $Cabinet/DrawersScroll/DrawersBox
@onready var close_button: Button = $Cabinet/CloseButton

var _drawer_closed_tex: Texture2D
var _drawer_open_tex: Texture2D
var _card_tex: Texture2D

var _drawers_data: Array = []
var _cards_data: Dictionary = {} # card_id -> card dict
var _drawer_buttons: Dictionary = {} # drawer_id -> Button
var _card_buttons: Dictionary = {} # card_id -> Button
var _open_drawer_id: String = ""
var _card_taken_emitted: bool = false
var _closed_emitted: bool = false


func _ready() -> void:
	layer = 30
	visible = false
	_ensure_nodes()
	_load_textures()
	_load_fallback_documents()
	if search_edit != null and not search_edit.text_changed.is_connected(_on_search_changed):
		search_edit.text_changed.connect(_on_search_changed)
		search_edit.text_submitted.connect(_on_search_submitted)
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)


func _ensure_nodes() -> void:
	if cabinet == null and has_node("Cabinet"):
		dimmer = get_node_or_null("Dimmer")
		cabinet = get_node("Cabinet")
		search_edit = get_node_or_null("Cabinet/SearchBox/SearchEdit")
		error_label = get_node_or_null("Cabinet/ErrorLabel")
		drawers_box = get_node_or_null("Cabinet/DrawersScroll/DrawersBox")
		close_button = get_node_or_null("Cabinet/CloseButton")


func _load_textures() -> void:
	if ResourceLoader.exists(DRAWER_TEXTURE_CLOSED_PATH):
		_drawer_closed_tex = load(DRAWER_TEXTURE_CLOSED_PATH)
	if ResourceLoader.exists(DRAWER_TEXTURE_OPEN_PATH):
		_drawer_open_tex = load(DRAWER_TEXTURE_OPEN_PATH)
	if ResourceLoader.exists(CARD_TEXTURE_PATH):
		_card_tex = load(CARD_TEXTURE_PATH)


func _load_fallback_documents() -> void:
	const DOCS_PATH := "res://data/documents.json"
	if FileAccess.file_exists(DOCS_PATH):
		var fa := FileAccess.open(DOCS_PATH, FileAccess.READ)
		if fa:
			var txt := fa.get_as_text()
			var json = JSON.parse_string(txt)
			if json is Dictionary:
				var dict := json as Dictionary
				_drawers_data = dict.get("drawers", [])
				for c in dict.get("cards", []):
					if c is Dictionary:
						var cid := str(c.get("id", ""))
						if cid != "":
							_cards_data[cid] = c


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and (k.keycode == KEY_ESCAPE or (k.keycode == KEY_BACKSPACE and (search_edit == null or not search_edit.has_focus()))):
			get_viewport().set_input_as_handled()
			close()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			close()


func open(data: Variant = null) -> void:
	_ensure_nodes()
	visible = true
	_card_taken_emitted = false
	_closed_emitted = false
	if error_label:
		error_label.visible = false
	if search_edit:
		search_edit.text = ""

	if data != null:
		if data is Array:
			_drawers_data = data as Array
		elif data is Dictionary:
			var d := data as Dictionary
			if d.has("drawers"):
				_drawers_data = d.get("drawers", [])
			if d.has("cards"):
				for c in d.get("cards", []):
					if c is Dictionary:
						var cid := str(c.get("id", ""))
						if cid != "":
							# Индекс картотеки приходит «коротким» (без steps_text/notes).
							# Не затираем полную карточку, уже загруженную с диска.
							if _cards_data.has(cid):
								var full: Dictionary = _cards_data[cid]
								for k in c.keys():
									if not full.has(k):
										full[k] = c[k]
							else:
								_cards_data[cid] = c

	_rebuild_drawers()


func close() -> void:
	_ensure_nodes()
	if not visible and _closed_emitted:
		return
	visible = false
	if not _closed_emitted:
		_closed_emitted = true
		emit_signal("closed")


func is_open() -> bool:
	return visible


func show_error(message: String) -> void:
	_ensure_nodes()
	# После ошибки карточку можно взять снова, иначе ящик «залипает».
	_card_taken_emitted = false
	if error_label:
		error_label.text = message
		error_label.visible = true
	_shake_cabinet()


func select_card(card_id: String) -> void:
	_ensure_nodes()
	_take_card(card_id)


func _shake_cabinet() -> void:
	if cabinet == null:
		return
	var orig_pos := cabinet.position
	var tw := create_tween()
	tw.tween_property(cabinet, "position", orig_pos + Vector2(3, 0), 0.05)
	tw.tween_property(cabinet, "position", orig_pos - Vector2(3, 0), 0.05)
	tw.tween_property(cabinet, "position", orig_pos + Vector2(2, 0), 0.05)
	tw.tween_property(cabinet, "position", orig_pos, 0.05)


func _rebuild_drawers(filter_query: String = "") -> void:
	_ensure_nodes()
	if drawers_box == null:
		return
	for child in drawers_box.get_children():
		child.queue_free()
	_drawer_buttons.clear()
	_card_buttons.clear()

	var norm_filter := _normalize_tag(filter_query)

	for d_entry in _drawers_data:
		if not d_entry is Dictionary:
			continue
		var drawer: Dictionary = d_entry as Dictionary
		var d_id: String = str(drawer.get("id", ""))
		var d_label: String = str(drawer.get("label", ""))
		var card_ids: Array = drawer.get("cards", [])

		var matching_cards: Array = []
		for cid in card_ids:
			var cdict: Dictionary = _cards_data.get(str(cid), {})
			var tag := str(cdict.get("tag", ""))
			if norm_filter == "" or _normalize_tag(tag).contains(norm_filter) or _normalize_tag(str(cid)).contains(norm_filter):
				matching_cards.append({
					"id": str(cid),
					"tag": tag,
					"title": str(cdict.get("title", cid)),
					"tools": cdict.get("tool_list", [])
				})

		if norm_filter != "" and matching_cards.is_empty():
			continue

		var drawer_item := _create_drawer_widget(d_id, d_label, card_ids.size(), matching_cards, norm_filter != "")
		drawers_box.add_child(drawer_item)


func _create_drawer_widget(drawer_id: String, label_str: String, total_cards: int, cards: Array, auto_open: bool) -> Control:
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(580, 50)
	btn.text = "  ЯЩИК %s · %s (%d)" % [drawer_id, label_str.to_upper(), total_cards]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", PALETTE_CLOUD_WHITE)

	var cards_container := VBoxContainer.new()
	cards_container.add_theme_constant_override("separation", 6)
	var is_open: bool = auto_open or (_open_drawer_id == drawer_id)
	cards_container.visible = is_open

	btn.pressed.connect(func():
		if _open_drawer_id == drawer_id:
			_open_drawer_id = ""
			cards_container.visible = false
		else:
			_open_drawer_id = drawer_id
			cards_container.visible = true
	)
	_drawer_buttons[drawer_id] = btn

	for c in cards:
		var c_widget := _create_card_widget(c)
		cards_container.add_child(c_widget)

	container.add_child(btn)
	container.add_child(cards_container)
	return container


func _create_card_widget(card: Dictionary) -> Control:
	var card_id := str(card.get("id", ""))
	var tag := str(card.get("tag", ""))
	var title := str(card.get("title", ""))
	var tools: Array = card.get("tools", [])

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 68)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)

	var tag_label := Label.new()
	tag_label.text = "[%s]" % tag
	tag_label.custom_minimum_size = Vector2(70, 30)
	tag_label.modulate = PALETTE_SIGNAL
	tag_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(tag_label)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.modulate = PALETTE_CLOUD_WHITE
	title_lbl.add_theme_font_size_override("font_size", 10)
	info_vbox.add_child(title_lbl)

	var tools_lbl := Label.new()
	var tools_str := ", ".join(tools)
	tools_lbl.text = "ИНСТРУМЕНТЫ: " + (tools_str if tools_str != "" else "НЕ ТРЕБУЮТСЯ")
	tools_lbl.modulate = PALETTE_COOL_SLATE
	tools_lbl.add_theme_font_size_override("font_size", 9)
	info_vbox.add_child(tools_lbl)

	hbox.add_child(info_vbox)

	var take_btn := Button.new()
	take_btn.text = "ВЗЯТЬ"
	take_btn.custom_minimum_size = Vector2(90, 36)
	take_btn.add_theme_font_size_override("font_size", 10)
	take_btn.pressed.connect(func():
		_take_card(card_id)
	)
	_card_buttons[card_id] = take_btn
	hbox.add_child(take_btn)

	panel.add_child(hbox)
	return panel


func _take_card(card_id: String) -> void:
	if _card_taken_emitted:
		return
	_card_taken_emitted = true
	emit_signal("card_taken", card_id)


func _on_search_changed(new_text: String) -> void:
	_ensure_nodes()
	if error_label:
		error_label.visible = false
	_rebuild_drawers(new_text)


func _on_search_submitted(text: String) -> void:
	_ensure_nodes()
	var norm := _normalize_tag(text)
	for cid in _cards_data.keys():
		var c: Dictionary = _cards_data[cid]
		var tag := str(c.get("tag", ""))
		if _normalize_tag(tag) == norm or _normalize_tag(cid) == norm:
			_take_card(cid)
			return
	show_error("РЕГЛАМЕНТ С ТАКИМ ID НЕ НАЙДЕН")


func _normalize_tag(raw: String) -> String:
	var s := raw.strip_edges().to_upper().replace("-", "").replace(" ", "").replace("_", "")
	return s


## Экранные прямоугольники кнопок картотеки (для обучения).
func get_drawer_button_rect(drawer_id: String) -> Rect2:
	var btn: Button = _drawer_buttons.get(drawer_id, null)
	if btn == null or not visible or not btn.is_visible_in_tree():
		return Rect2()
	return btn.get_global_rect()


func get_card_button_rect(card_id: String) -> Rect2:
	var btn: Button = _card_buttons.get(card_id, null)
	if btn == null or not visible or not btn.is_visible_in_tree():
		return Rect2()
	return btn.get_global_rect()


func _on_close_pressed() -> void:
	close()
