extends SceneTree

const FONT_PATH = "res://assets/ui/fonts/PressStart2P-Regular.ttf"

class PreviewWrap extends Control:
	var font_sz: int = 13
	var font: Font = null
	
	func _ready() -> void:
		custom_minimum_size = Vector2(1280, 720)
		size = Vector2(1280, 720)
		font = load(FONT_PATH)
		
	func _draw() -> void:
		var frame := Rect2(120.0, 36.0, 1040.0, 648.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0392, 0.0510, 0.0706, 1.0))
		draw_rect(frame, Color(0.08, 0.16, 0.14, 0.9))
		draw_rect(frame, Color(0.12, 0.25, 0.22, 1.0), false, 1.5)
		
		# Header
		var header_rect := Rect2(frame.position.x + 24.0, frame.position.y + 16.0, frame.size.x - 48.0, 44.0)
		draw_rect(header_rect, Color(0.04, 0.09, 0.08, 0.95))
		draw_rect(header_rect, Color(0.12, 0.25, 0.22, 1.0), false, 1.0)
		draw_circle(Vector2(header_rect.position.x + 18.0, header_rect.position.y + 22.0), 4.5, Color(0.9, 0.15, 0.08))
		draw_string(font, Vector2(header_rect.position.x + 32.0, header_rect.position.y + 27.0), "КОМПЛЕКС «АНТРАЦИТ» // СЕКТОР ГЛУБОКОЙ ИЗОЛЯЦИИ 07", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.643, 1.0, 0.941))
		var st_w := font.get_string_size("СТАТУС: ТРЕВОГА // ЭКСТРЕННЫЙ РЕЖИМ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(header_rect.end.x - st_w - 18.0, header_rect.position.y + 27.0), "СТАТУС: ТРЕВОГА // ЭКСТРЕННЫЙ РЕЖИМ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.15, 0.08))
		
		# Alert Box
		var alert_rect := Rect2(frame.position.x + 24.0, 500.0, frame.size.x - 48.0, 48.0)
		draw_rect(alert_rect, Color(0.902, 0.157, 0.082, 0.22))
		draw_rect(alert_rect, Color(0.902, 0.157, 0.082, 1.0), false, 2.0)
		
		# Bottom prompt
		var prompt_rect := Rect2(frame.position.x + (frame.size.x - 560.0)*0.5, 624.0, 560.0, 34.0)
		draw_rect(prompt_rect, Color(0.02, 0.06, 0.05, 0.7))
		draw_rect(prompt_rect, Color(0.502, 0.847, 0.784, 0.6), false, 1.2)
		draw_string(font, prompt_rect.position + Vector2(0.0, 22.0), "[ ПРОБЕЛ ИЛИ ЛКМ — ПРИСТУПИТЬ К РЕМОНТУ ]", HORIZONTAL_ALIGNMENT_CENTER, prompt_rect.size.x, 12, Color(0.502, 0.847, 0.784))
		
		# Alert text
		var alert_text = "[!] ГЛАВНОЕ ПРАВИЛО: НЕ БУДИ ЕГО."
		var alert_w = font.get_string_size(alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2(alert_rect.position.x + (alert_rect.size.x - alert_w)*0.5, alert_rect.position.y + 30.0), alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.902, 0.157, 0.082))
		
		# Directive header
		var dir_hdr = "ДИРЕКТИВА СЛУЖБЫ БЕЗОПАСНОСТИ // ИСКЛЮЧИТЕЛЬНЫЙ ПРОТОКОЛ:"
		var dir_w = font.get_string_size(dir_hdr, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(frame.position.x + (frame.size.x - dir_w)*0.5, 474.0), dir_hdr, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.28, 0.24))

		var raw_lines = [
			{"text": "[!] СВОДКА ИНЦИДЕНТА // АВАРИЙНЫЙ ЖУРНАЛ СЕКТОРА 07:", "col": Color(0.29, 0.54, 0.50), "sz": 11, "is_header": true},
			{"text": "> ЛОКАЦИЯ:   КОМПЛЕКС «АНТРАЦИТ» // СЕКТОР ГЛУБОКОЙ ИЗОЛЯЦИИ 07", "col": Color(0.50, 0.84, 0.78), "sz": font_sz},
			{"text": "> ОБЪЕКТ:    ШТУРМОВОЙ АВТОМАТОН «ВЕПРЬ-04» (СЕРИЯ «ЦЕРБЕР»)", "col": Color(0.64, 1.0, 0.94), "sz": font_sz},
			{"text": "> СОБЫТИЕ:   ВНЕЗАПНЫЙ СРЫВ БОЕВОЙ МАТРИЦЫ НА НОЧНОЙ СМЕНЕ. 4 ТЕХНИКА ПОГИБЛИ.", "col": Color(0.68, 0.28, 0.24), "sz": font_sz},
			{"text": "> СТАТУС:    ПОДАВЛЕН ВЫСОКОВОЛЬТНЫМ ЭМИ, ПРИКОВАН К СТЕННОМУ СТАПЕЛЮ.", "col": Color(0.50, 0.84, 0.78), "sz": font_sz},
			{"divider": true},
			{"text": "[!] ОПЕРАТИВНАЯ ОБСТАНОВКА И ОЦЕНКА УГРОЗЫ:", "col": Color(0.29, 0.54, 0.50), "sz": 11, "is_header": true},
			{"text": "> НЕСТАБИЛЬНОСТЬ ЛОГИЧЕСКОГО ЯДРА РАСТЁТ // ПРЕДДВЕРИЕ ПРОБУЖДЕНИЯ.", "col": Color(0.50, 0.84, 0.78), "sz": font_sz},
			{"text": "> ОПАСНОСТЬ: РЫВКИ МЫШИ, СКРЕЖЕТ МЕТАЛЛА ИЛИ ТРЕНИЕ РАЗБУДЯТ МАШИНУ.", "col": Color(0.95, 0.72, 0.28), "sz": font_sz},
			{"text": "> ПОРОГ:     ПРИ НЕСТАБИЛЬНОСТИ >70% СИЛОВЫЕ РЕМНИ НЕ ВЫДЕРЖАТ.", "col": Color(0.90, 0.15, 0.08), "sz": font_sz},
			{"text": "> ЗАДАЧА:    ПРОВЕСТИ ПОЛЕВОЙ РЕМОНТ ДО ПРИБЫТИЯ КОНВОЯ УТИЛИЗАЦИИ.", "col": Color(0.64, 1.0, 0.94), "sz": font_sz},
			{"divider": true}
		]
		
		var cur_y := 120.0
		var content_w := 920.0
		var content_x := frame.position.x + (frame.size.x - content_w) * 0.5
		
		for item in raw_lines:
			if item.has("divider"):
				draw_line(Vector2(content_x, cur_y - 6.0), Vector2(content_x + content_w, cur_y - 6.0), Color(0.12, 0.25, 0.22, 1.0), 1.0)
				cur_y += 18.0
				continue
				
			var t: String = item["text"]
			var sz: int = item["sz"]
			var col: Color = item["col"]
			
			if item.get("is_header", false):
				var str_w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
				draw_string(font, Vector2(frame.position.x + (frame.size.x - str_w)*0.5, cur_y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
				cur_y += 26.0
				continue
				
			# Word wrap for entries
			var wrapped := _wrap_text(t, font, sz, content_w)
			for w_line in wrapped:
				draw_string(font, Vector2(content_x, cur_y), w_line, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
				cur_y += 24.0 if font_sz == 12 else 26.0

	func _wrap_text(text: String, f: Font, sz: int, max_w: float) -> PackedStringArray:
		var total_w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if total_w <= max_w:
			return PackedStringArray([text])
		var words := text.split(" ")
		var res := PackedStringArray()
		var cur := ""
		for word in words:
			var candidate := cur + (" " if cur != "" else "") + word
			var cw := f.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			if cw <= max_w or cur == "":
				cur = candidate
			else:
				res.append(cur)
				var indent := "             " if text.begins_with("> ") else "  "
				cur = indent + word
		if cur != "":
			res.append(cur)
		return res

func _init() -> void:
	var c = PreviewWrap.new()
	c.font_sz = 13
	root.add_child(c)
	for i in 8:
		await process_frame
	var img = root.get_viewport().get_texture().get_image()
	img.save_png("docs/preview/test_wrap_13.png")
	c.queue_free()
	quit(0)
