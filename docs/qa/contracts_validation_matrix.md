# Матрица валидации контрактов данных (Do Not Wake)

## Спецификация: `docs/architecture.md` §3.1–§3.5, `docs/qa/report.md` §3, §5

| № | Объект / Область | Правило проверки | Реализация в `tests/test_data_integrity.gd` | Статус этап 1 |
|---|---|---|---|---|
| 1 | `data/robot.json` | Файл существует и парсится в Dictionary | `FileAccess.file_exists` + `JSON.parse_string` | PASS |
| 2 | `data/robot.json` | `threshold` > 0 | `r_dict.has("threshold") and val > 0.0` | PASS |
| 3 | `data/robot.json` | `stages` массив >= 3 элементов | `r_dict["stages"].size() >= 3` | PASS |
| 4 | `data/robot.json` | `tools` массив >= 3 инструментов | `r_dict["tools"].size() >= 3` | PASS |
| 5 | `data/robot.json` | Секция `loop` на месте | `r_dict.has("loop") and r_dict["loop"] is Dictionary` | PASS |
| 6 | `data/robot.json` | Все числовые поля `loop` > 0 (`diagnostics_seconds`, `wrong_part_penalty`, `wrong_doc_penalty`, `order_penalty`, `timeout_penalty`, `shift_time_limit`) | Проверка числовых типов и границ > 0 | PASS |
| 7 | `data/robot.json` | `loop.pause`: `cool_rate` >= 0, `max_seconds` > 0, `resume_delay` > 0 | Проверка словаря `pause` | PASS |
| 8 | `data/robot.json` | `loop.threat_control`: `hold_seconds` > 0, `motion_limit` > 0, `safe_margin` > 0 | Проверка словаря `threat_control` | PASS |
| 9 | `data/robot.json` | `loop.verify`: `pass_reward` > 0, `fail_penalty` > 0, `max_attempts` >= 1 | Проверка словаря `verify` | PASS |
| 10 | `data/parts.json` | Файл существует и парсится в Dictionary | `FileAccess.file_exists` + `JSON.parse_string` | PASS |
| 11 | `data/parts.json` | `tutorial_part_id` задан и существует в `parts[].id` | Сверка с множеством `part_ids` | PASS |
| 12 | `data/parts.json` | `parts` непустой массив | `parts.size() >= 1` | PASS |
| 13 | `data/parts.json` | `part.id` уникальны и соответствуют `^[a-z0-9_]+$` | RegEx проверка и hash-set | PASS |
| 14 | `data/parts.json` | `part.tag` уникальны и соответствуют `^[A-Z]-\d{2}$` | RegEx `^[A-Z]-\d{2}$` | PASS |
| 15 | `data/parts.json` | `label`, `fault_code`, `symptom`, `doc_id`, `zone` непустые строки | Проверка строк без пробелов | PASS |
| 16 | `data/parts.json` | `tag_pos` в границах экрана 1280×720 | `0 <= x <= 1280`, `0 <= y <= 720` | PASS |
| 17 | `data/parts.json` | `difficulty` целое от 1 до 3 | Проверка целого числа в [1, 3] | PASS |
| 18 | `data/parts.json` | `reward` и `penalty` в диапазоне `[-30, 30]` | Проверка вещественных границ | PASS |
| 19 | `data/parts.json` | `verify`: `type` ∈ `pulse\|visual\|sequence`, `time_limit` > 0 | Валидация подсекции `verify` | PASS |
| 20 | `data/parts.json` | `steps` непустой массив, `step.id` уникальны в пределах детали | Hash-set по деталям | PASS |
| 21 | `data/parts.json` | `step.type` ∈ `scrub\|unbolt\|cable_lock\|hold\|calibrate` | Проверка допустимых типов шагов | PASS |
| 22 | `data/parts.json` | `step.tool` ∈ `robot.json.tools` (или `"none"` для шагов без инструмента) | Сверка с инструментами лотка | PASS |
| 23 | `data/parts.json` | `step.time_limit` > 0 | Проверка времени шага | PASS |
| 24 | `data/parts.json` | `step.instability` (`success`, `fail`, `timeout`) в `[-30, 30]` | Проверка дельт нестабильности | PASS |
| 25 | `data/parts.json` | Обязательные параметры `params` для `scrub` (`rect`, `safe_speed_min`, `safe_speed_max`, `target_ratio`) | Проверка типов и геометрии | PASS |
| 26 | `data/parts.json` | Обязательные параметры `params` для `unbolt` (`hatch_rect`, `bolts`, `slip_params`) | Проверка болтов и параметров срыва | PASS |
| 27 | `data/parts.json` | Обязательные параметры `params` для `cable_lock` (`socket_pos`, `socket_radius`, `cable_anchor`, `keyway_angle_deg`, `angle_tolerance_deg`, `lock_hold_time`) | Проверка параметров замка | PASS |
| 28 | `data/parts.json` | Обязательные параметры `params` для `hold` (`rect`, `duration`, `motion_tolerance`) | Проверка зоны удержания | PASS |
| 29 | `data/parts.json` | Обязательные параметры `params` для `calibrate` (`rect`, `min`, `max`, `target`, `tolerance`, `control`) | Проверка калибровки | PASS |
| 30 | `data/documents.json` | Файл существует и парсится в Dictionary | `FileAccess.file_exists` + `JSON.parse_string` | PASS |
| 31 | `data/documents.json` | `drawers` непустой массив, `id` уникальны, `label` непустой | Проверка ящиков | PASS |
| 32 | `data/documents.json` | `cards` непустой массив, `id` уникальны и по regex `^[a-z0-9_]+$` | Проверка карточек | PASS |
| 33 | `data/documents.json` | `card.tag` по regex `^[A-Z]-\d{2}$`, `drawer` ссылается на существующий ящик | Валидация карточек | PASS |
| 34 | `data/documents.json` | `card.tool_list` содержит инструменты из `robot.json.tools` | Валидация списка инструментов | PASS |
| 35 | `data/documents.json` | `card.time_norm_sec` > 0 | Проверка норматива времени | PASS |
| 36 | `data/documents.json` | `card.steps_text` и `card.order` непустые массивы | Проверка шагов регламента | PASS |
| 37 | Cross-reference | Каждая карточка лежит ровно в одном ящике (`drawers[].cards`) | 1:1 отображение | PASS |
| 38 | Cross-reference | Все ссылки в `drawers[].cards` указывают на существующие карточки (0 фантомов) | Проверка ссылок | PASS |
| 39 | Cross-reference | Каждая деталь имеет существующий `doc_id` в `cards` | Проверка перекрёстных ссылок | PASS |
| 40 | Cross-reference | `card.tag == part.tag` для всех деталей и карточек | Проверка соответствия тегов | PASS |
| 41 | Cross-reference | `card.order == part.steps.map(id)` строго по составу и порядку | Точное пошаговое совпадение | PASS |
| 42 | Cross-reference | `card.tool_list` включает все инструменты из шагов детали | Проверка покрытия инструментов | PASS |
| 43 | Cross-reference | `card.time_norm_sec >= 0.9 * sum(time_limits)` шагов детали | Проверка формулы норматива | PASS |

---

## Реестр лицензий аудио (`data/audio_credits.json` / `tests/test_audio_credits.gd`)

| № | Проверка | Описание | Статус этап 1 |
|---|---|---|---|
| A1 | `data/audio_credits.json` | Файл существует и парсится в Dictionary | Ожидает AUD (FAIL на живом файле) |
| A2 | `tracks` array | Массив не пустой, содержит список треков | Реализовано в валидаторе |
| A3 | 0 файлов-сирот | Все файлы из `assets/sounds/` и `assets/music/` зарегистрированы в реестре | Реализовано в валидаторе |
| A4 | 0 фантомных файлов | Все записи в реестре указывают на существующие локальные файлы (`res://...`) | Реализовано в валидаторе |
| A5 | Разрешённые лицензии | `CC0-1.0`, `CC-BY-3.0`, `CC-BY-4.0`, `Pixabay`, `Sonniss`, `Own`, `Procedural` | Реализовано в валидаторе (8/8 мутаций PASS) |
| A6 | Запрет ограничений | Отсутствие подстрок `NC`, `SA`, `personal use`, `non-commercial` | Реализовано в валидаторе |
| A7 | Требования CC-BY | Непустой `author` и валидный `url` с `https://` | Реализовано в валидаторе |
| A8 | Формат даты | Поле `added` в формате `YYYY-MM-DD` | Реализовано в валидаторе |
| A9 | Квота музыки | Не менее 3 лупов и не менее 1 стингера в `assets/music/` | Реализовано в валидаторе |
| A10 | Документация музыки | Каждый музыкальный трек описан в `docs/audio-sources.md` | Реализовано в валидаторе |
