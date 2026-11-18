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
| Gemini Imagen (gemini-3.1-flash-image) | Набор инструментов мастерской (`ui_tools`) | `assets/sprites/ui/tool_*.png` | Нарезка на 3 слота (ветошь, отвёртка, терминал), удаление фона #FF00FF, дефрингинг, квантование до 15 цветов, карты нормалей |
| Gemini Imagen (gemini-3.1-flash-image) | Аналоговый манометр стабильности (`ui_gauge`) | `assets/sprites/ui/gauge_meter.png` | Удаление фона #FF00FF, кадрирование 128×128, квантование, карта нормалей |
| Gemini Imagen (gemini-3.1-flash-image) | VHS-кассета и отсек привода (`ui_vhs_deck`) | `assets/sprites/ui/vhs_deck_prop.png` | Удаление фона #FF00FF, кадрирование 256×128, квантование, карта нормалей |

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
