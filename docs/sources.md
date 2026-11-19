# Источники сторонних материалов

Ведётся с первого дня. Из этого файла потом собирается `Источники.pdf` для блока «Арт».
Правило задания: всё стороннее — с источником и лицензией, платное использовать нельзя.

## Изображения и референсы

| Что | Ссылка / источник | Автор | Лицензия | Где использовано |
|---|---|---|---|---|
| Палитры (Titanium/Obsidian и др.) | скриншоты палитр из чата | — | референс, не копирование | `docs/style.md` |
| | | | | |

## Генеративные модели

Указывать модель, версию и что именно сгенерировано.

| Модель | Что сгенерировано | Область использования | Доработано вручную |
|---|---|---|---|
| Gemini Imagen (gemini-3.1-flash-image) | Блок-аут мастерской (`blockout_room`) | `docs/blockout_room.png` | Ресайз до 1280×720, выравнивание пропорций под сцену |
| Gemini Imagen (gemini-3.1-flash-image) | Спрайт выключенного робота (`robot_calm`) | `assets/sprites/robot/robot_calm.png` | Удаление фона #FF00FF (bg_remover), дефрингинг контура, Nearest Neighbor ужимка до 256×320, карта нормалей |
| Gemini Imagen (gemini-3.1-flash-image) | Спрайт пробуждённого робота (`robot_awake`) | `assets/sprites/robot/robot_awake.png` | Удаление фона #FF00FF (bg_remover), дефрингинг контура, Nearest Neighbor ужимка до 256×320, карта нормалей |
| Gemini Imagen (gemini-3.1-flash-image) | Набор инструментов мастерской (`ui_tools`) | `assets/sprites/ui/tool_cloth.png`, `tool_screwdriver.png` | Нарезка на слоты, удаление фона #FF00FF, дефрингинг, квантование до 15 цветов |
| Gemini Imagen (gemini-3.1-flash-image) | Финальная клавиатура инструмента (`tool_keyboard`) | `assets/sprites/ui/tool_keyboard.png` | Генерация субагентом, вырезка магенты, ужимка до 52 px, центрирование в `tray_template_128.png`, квантование в палитру |
| Gemini Imagen (gemini-3.1-flash-image) | VHS-кассета меню (`ui_cassette`) | `assets/sprites/ui/ui_cassette.png` | Генерация субагентом, вырезка магенты, ужимка до 496×96, чистая наклейка под текст, квантование в палитру |
| Gemini Imagen (gemini-3.1-flash-image) | Подложка экрана диагностики (`ui_crt_screen_bg`) | `assets/sprites/ui/ui_crt_screen_bg.png` | Генерация субагентом, ресайз 960×380, притемнение до 42% под читаемость текста, квантование в палитру |
| Gemini Imagen (gemini-3.1-flash-image) | Аналоговый манометр стабильности (`ui_gauge`) | `assets/sprites/ui/gauge_meter.png` | Удаление фона #FF00FF, кадрирование 128×128, квантование, карта нормалей |
| Gemini Imagen (gemini-3.1-flash-image) | VHS-кассета и отсек привода (`ui_vhs_deck`) | `assets/sprites/ui/vhs_deck_prop.png` | Удаление фона #FF00FF, кадрирование 256×128, квантование, карта нормалей |

## Собственные ассеты (нарисовано в проекте)

| Ассет | Кто/чем | Где использовано |
|---|---|---|
| `assets/sprites/ui/ui_cursor.png` | пиксель-арт 16×16 вручную по палитре: треугольный курсор #E62815 с обводкой #080808 и бликом #EDF0F4 | кастомный курсор `Input.set_custom_mouse_cursor()` |
| `assets/sprites/ui/ui_button_metal_*.png` | пиксель-арт 256×64 (normal, hover, pressed, disabled) под 9-slice (18/18/16/16) | кнопки меню финала `EndScreen.tscn` |
| `assets/sprites/ui/ui_button_screen_*.png` | пиксель-арт 256×64 (normal, hover, pressed, disabled) под 9-slice (18/18/16/16) с циановым акцентом | кнопки ЭЛТ `MainMenu.tscn` |
| `assets/sprites/ui/ui_panel.png` | пиксель-арт 256×256 под 9-slice (24/24/24/24) со скобами и винтами | панели HUD в `scripts/main.gd` |
| `assets/sprites/ui/ui_slot_plate*.png` | пиксель-арт 256×128 под 9-slice (24/24/20/20), normal и selected со светодиодом | слоты лотков в `scripts/main.gd` |
| `assets/sprites/ui/ui_bar_frame.png` | пиксель-арт 128×32 под 9-slice (8/8/8/8) с прозрачным желобом | рамка шкалы нестабильности в `scripts/main.gd` |
| `assets/sprites/ui/ui_gauge_face.png` | пиксель-арт 128×128: шкала с 21 тиком, красным сектором 30% и ступицей без стрелки | циферблат манометра в `scripts/main.gd` |
| `assets/sprites/ui/ui_tv_bezel.png` | пиксель-арт 1056×472: корпус ЭЛТ с прозрачным окном 960×380, ручками и решеткой | `MainMenu.tscn` → TVBezel |
| `assets/sprites/ui/ui_vhs_deck_plate.png` | пиксель-арт 840×156: лицевая панель VHS со слотом 496×96, клавишами и счетчиком | `MainMenu.tscn` → VHSDeck |
| `assets/sprites/ui/menu_bg.png` | пиксель-арт 1280×720: фон мастерской с полками, дверью, кабелями и верхним светом | `MainMenu.tscn` → Background |
| `docs/tray_template_128.png` | пустой лоток-шаблон (ниша очищена) для вклейки новых иконок | заготовка для иконок 128×128 |
| `docs/ui-art-prompts.md` | спецификация и промпты для генерации UI | задание художникам |

Карты нормалей `*_normal.png` в проекте **не используются** ни одним материалом (в сцене только 2D-отрисовка без света). Карта `tool_keyboard_normal.png` удалена как неактуальная; остальные можно удалить или подключить позже отдельной задачей.

## Шрифты

| Шрифт | Автор | Лицензия | Где использовано |
|---|---|---|---|
| m5x7 | Matt Walkden | CC0 | UI, если выбран |
| Press Start 2P | CodeMan38 | OFL | альтернатива |

## Звуки

| Звук | Ссылка | Лицензия | Где использовано |
|---|---|---|---|
| click.wav | процедурный синтез (Python wave) | CC0 / Original | выбор инструмента, клики меню |
| repair_success.wav | процедурный синтез (Python wave) | CC0 / Original | успешный ремонт зоны |
| error_buzz.wav | процедурный синтез (Python wave) | CC0 / Original | ошибка выбора инструмента / нарушение замирания |
| robot_awake.wav | процедурный синтез (Python wave) | CC0 / Original | тревожный сигнал пробуждения |
| calm_down.wav | процедурный синтез (Python wave) | CC0 / Original | гидравлический сброс при успокоении |
| vhs_insert.wav | процедурный синтез (Python wave) | CC0 / Original | защелкивание кассеты в меню |

## Инструменты

| Инструмент | Лицензия |
|---|---|
| Godot 4.7.2 | MIT |
| Photopea / Piskel / Krita | бесплатные |
| OBS Studio | GPL |
| HandBrake | GPL |
