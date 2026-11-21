extends SceneTree
func _init():
    var font: Font = ThemeDB.fallback_font
    var stage_rect := Rect2(720, 24, 520, 70)
    var texts = [
        "Захватите ветошь и сотрите нагар с контактов. Контролируйте скорость трения!",
        "Выкрутите 4 болта отверткой и снимите люк. Избегайте срыва шлица!",
        "Протяните бронекабель к височному порту, совместите направляющий паз и зафиксируйте замок!"
    ]
    for t in texts:
        var sz = font.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, 480.0, 9, 2)
        print("Text: '", t.substr(0, 30), "...' -> size: ", sz)
        var sz_single = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
        print("  single line size: ", sz_single)
    quit()
