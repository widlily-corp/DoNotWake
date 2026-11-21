class_name LoopData
extends RefCounted

## Загрузчик данных деталей и формуляров ТО для новой петли
const DEFAULT_PARTS_PATH: String = "res://data/parts.json"
const DEFAULT_DOCUMENTS_PATH: String = "res://data/documents.json"


## Загружает список деталей из JSON-файла. Возвращает Array деталей.
## При ошибке чтения/парсинга возвращает пустой массив и выдаёт push_warning.
static func load_parts(path: String = DEFAULT_PARTS_PATH) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("LoopData: parts file not found at: " + path)
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LoopData: failed to open parts file: " + path)
		return []

	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var parts_val: Variant = (parsed as Dictionary).get("parts", [])
		if parts_val is Array:
			return parts_val as Array
		push_warning("LoopData: 'parts' in %s is not an Array" % path)
		return []
	elif parsed is Array:
		return parsed as Array

	push_warning("LoopData: invalid JSON format in: " + path)
	return []


## Загружает формуляры и ящики ТО из JSON-файла. Возвращает Dictionary {"drawers": [...], "cards": [...]}.
## При ошибке чтения/парсинга возвращает пустой словарь и выдаёт push_warning.
static func load_documents(path: String = DEFAULT_DOCUMENTS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("LoopData: documents file not found at: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LoopData: failed to open documents file: " + path)
		return {}

	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	elif parsed is Array:
		return {"cards": parsed as Array, "drawers": []}

	push_warning("LoopData: invalid JSON format in: " + path)
	return {}
