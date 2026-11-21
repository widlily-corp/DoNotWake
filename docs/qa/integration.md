# Отчёт интеграции сцены Main.tscn (этап 3)

## 1. Обзор и цели интеграции

В рамках этапа 3 (интеграция) выполнена сквозная сборка и координация ключевых игровых подсистем ремонта робота:
- **`GameState`** (`scripts/core/game_state.gd`): авторитетный контроллер 6-фазной петли смены и состояний автоматона.
- **`StepRunner`** (`scripts/core/step_runner.gd`): универсальный исполнитель тактильных операций ремонта (scrub, unbolt, cable_lock, hold, calibrate).
- **`LoopScreens`** (`scripts/ui/loop_screens.gd`): координатор экранных оверлеев и модальных окон (CanvasLayer 15..60).
- **`LoopAudio`** (`scripts/core/loop_audio.gd`): контроллер звукового ландшафта, физического аудио, шин микшера и кроссфейда музыки.
- **`MainView`** (`scripts/main.gd`): хост-сцена, композитор мира, физических инструментов и тактильных узлов.

Сборка обеспечивает непрерывный игровой цикл:
`ДИАГНОСТИКА` → `ВЫБОР ДЕТАЛИ` → `КАРТОТЕКА` → `РЕГЛАМЕНТ` → `РЕМОНТ` → `КОНТРОЛЬ УГРОЗЫ` → `ПРОВЕРКА ОТК` → `ФИНАЛ СМЕНЫ`.

---

## 2. Архитектура сцены и узловая структура

### 2.1. Иерархия сцены `scenes/Main.tscn`

```
Main (Node2D, scripts/main.gd)
├── GameState (Node, scripts/core/game_state.gd)
├── Audio (Node)
│   ├── SFXClick (AudioStreamPlayer)
│   ├── SFXRepair (AudioStreamPlayer)
│   ├── SFXError (AudioStreamPlayer)
│   ├── SFXWake (AudioStreamPlayer)
│   ├── SFXCalm (AudioStreamPlayer)
│   ├── SFXInsert (AudioStreamPlayer)
│   └── SFXStrapCreak (AudioStreamPlayer)
├── CRTPostProcess (ColorRect, ShaderMaterial crt_screen.gdshader)
└── EndScreen (Control, scenes/ui/EndScreen.tscn)
```

В рантайме в методе `_ready()` динамически инстанцируются и привязываются подсистемы новой петли:
```
Main (Node2D)
├── StepRunner (Node, scripts/core/step_runner.gd)
├── LoopAudio (Node, scripts/core/loop_audio.gd)
├── LoopScreens (CanvasLayer, layer 15, scripts/ui/loop_screens.gd)
│   ├── DiagnosticsPanel (CanvasLayer, layer 20, scenes/ui/DiagnosticsPanel.tscn)
│   ├── CardFile (CanvasLayer, layer 30, scenes/ui/CardFile.tscn)
│   ├── DocReader (CanvasLayer, layer 40, scenes/ui/DocReader.tscn)
│   ├── VerifyPanel (CanvasLayer, layer 50, scenes/ui/VerifyPanel.tscn)
│   └── ThreatOverlay (CanvasLayer, layer 60, scenes/ui/ThreatOverlay.tscn)
└── PartMarkers (Node2D, z_index 6, scripts/ui/part_markers.gd) -> world_root
```

### 2.2. Матрица слоёв и глубина рендеринга (1280×720)

| Элемент / Оверлей | Слой / Уровень | Z-Index / Rect | Назначение |
|---|---|---|---|
| Задний фон бокса | Мир (Node2D) | Z 0, `0, 0, 1280, 720` | Стена ниши, освещение |
| Робот-монолит | Мир (Node2D) | Z 1, `512, 80, 256, 512` | Спрайт, тепловое излучение, ремни |
| Тактильные компоненты | Мир (Node2D) | Z 2..3, зоны ремонта | ScrubZone, ScrewBoltManager, CablePlug |
| Лоток инструментов | Мир (Node2D) | Z 4, `80, 580, 1120, 130` | Тиснёные стальные слоты |
| Физические инструменты | Мир (Node2D) | Z 5 | Ветошь, отвёртка, кабель |
| ID-метки деталей (`PartMarkers`) | Мир (Node2D) | Z 6, `tag_pos`, 56×22 | Бирки узлов (напр. `A-04`) |
| Верхний статус-бар и манометр | Мир / Canvas | Z 10, `40, 24, 620, 72` | Манометр нестабильности |
| Баннер этапа / подсказка | Мир / Canvas | Z 10, `720, 24, 520, 70` | Название фазы и инструкции |
| Координатор `LoopScreens` | CanvasLayer | Layer 15 | Родитель модальных окон |
| Терминал диагностики | CanvasLayer | Layer 20, `160, 150, 960, 420` | Отчёт неполадок и сбоев |
| Картотека регламентов | CanvasLayer | Layer 30, `120, 80, 1040, 560` | Ящики и карточки документации |
| Чтение регламента | CanvasLayer | Layer 40, `180, 80, 920, 560` | Техническая карта шагов |
| Панель проверки ОТК | CanvasLayer | Layer 50, `320, 180, 640, 360` | Осциллограф и штамп годности |
| Оверлей тревоги / пробуждения | CanvasLayer | Layer 60, `0, 0, 1280, 720` | Блокировка ввода, стробоскоп, пауза |
| ЭЛТ Пост-процесс | Canvas / Top | `0, 0, 1280, 720` | Сканлайны, виньетка, фосфор |
| Финал смены (`EndScreen`) | Control / Canvas | `0, 0, 1280, 720` | Итоги смены, статистика, перезапуск |

---

## 3. Сигнальные цепочки и координация

| Источник (From) | Сигнал | Приёмник (To) | Метод / Обработка |
|---|---|---|---|
| `GameState` | `step_requested(index, step)` | `MainView` | Сохраняет `_current_step_index`, настраивает `StepRunner.setup(self, step)` и вызывает `StepRunner.start()` |
| `StepRunner` | `step_finished(quality)` | `MainView` | Вызывает `GameState.report_step_result(index, true, quality)`, возвращает инструмент в лоток |
| `StepRunner` | `step_failed(reason)` | `MainView` | Вызывает `GameState.report_step_result(index, false, 0.0, reason)`, возвращает инструмент в лоток |
| `StepRunner` | `hazard(amount, message)` | `MainView` | Вызывает `GameState.add_instability(amount)`, запускает сотрясение экрана и алерт |
| `StepRunner` | `progress_changed(val)` | `MainView` | Транслирует в `GameState.step_progress(index, val)` |
| `GameState` | `wake_started(duration)` | `MainView` | Замораживает `StepRunner.set_frozen(true)`, сбрасывает инструмент в лоток, включает тревогу |
| `GameState` | `wake_ended()` | `MainView` | Размораживает `StepRunner.set_frozen(false)` |
| `GameState` | `pause_changed(paused, reason)` | `MainView` | Передаёт `StepRunner.set_frozen(paused)`, при паузе сбрасывает инструмент в лоток |
| `GameState` | `shift_finished(success, stats)` | `MainView` | Передаёт статистику в `EndScreen.show_result(...)` |
| `GameState` | `phase_changed(phase)` | `MainView` | Обновляет баннер задачи и текст подсказки |
| `GameState` | 10 сигналов петли | `LoopScreens` | Управляет открытием/закрытием модальных окон по фазам |
| `GameState` | Сигналы угрозы/шагов | `LoopAudio` | Запускает звуки, кроссфейд `ambient_calm` / `ambient_threat`, мгновенный обрыв на wake |
| `LoopScreens` | Интенты панелей | `GameState` | Вызовы `run_diagnostics()`, `select_part()`, `read_card()`, `begin_repair()`, `run_verification()` |

---

## 4. Хост-интерфейс StepRunner (контракт данных §4.2)

В `scripts/main.gd` строго реализованы 5 хост-методов:

```gdscript
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
```

---

## 5. Разделение конфликтов ввода

1. **Приоритет модальных окон LoopScreens:**
   - Если открыто любое модальное окно (`DiagnosticsPanel`, `CardFile`, `DocReader`, `VerifyPanel` или активен оверлей `ThreatOverlay`), метод `_is_overlay_active()` возвращает `true`.
   - При этом игровой ввод по миру, захват инструментов в лотке и клики по роботу немедленно блокируются. Клавиатурные события (Esc, Enter, стрелки) перехватываются активным окном UI.

2. **Защита в режиме AWAKE и на паузе:**
   - При `Threat.AWAKE` или `State.AWAKE` перемещение мыши фиксируется и штрафует игрока нестабильностью (`game_state.on_mouse_moved`). Любые попытки взять инструмент или кликнуть по узлу блокируются.
   - При `is_paused` перетаскивание инструментов и воздействие на детали заблокированы; удержание клавиши P переключает паузу через `ThreatOverlay`.

3. **Разделение ввода инструментов и шагов:**
   - Ввод мыши сначала проверяется интерактивными инструментами (`DraggableTool.handle_mouse_input`). Если клик пришёлся на инструмент в лотке или начато перетаскивание, событие поглощается (`return`).
   - Если клик не связан с инструментом и активен `StepRunner`, событие передаётся в `step_runner.handle_input(event)`.

4. **Полная изоляция легаси-режима:**
   - Если `current_mode == Mode.LEGACY`, `MainView` использует прежние обработчики (`handle_hatch_input`, `handle_input` кабеля, `_handle_fallback_click`), гарантируя прохождение 69 проверок в `tests/test_gameplay.gd`.
   - В режиме `Mode.NEW` легаси-клики отключены; все действия контролируются `StepRunner`.

---

## 6. Верификация и артефакты

### 6.1. Скриншоты 5 фаз петли (`docs/preview/`)

Сгенерированы детерминированным скриптом `tools/capture_screen.gd` через Vulkan рендерер Forward+:

1. **`docs/preview/screen_loop_diagnostics.png`** (136 KB) — Фаза `DIAGNOSTICS`: панель диагностики с отчётом по коду неполадки `E-217` и симптомам дрожания манипулятора.
2. **`docs/preview/screen_loop_part_select.png`** (808 KB) — Фаза `PART_SELECT`: операционный бокс, автоматон в нише с диегетической ID-биркой `A-04` на сервоприводе.
3. **`docs/preview/screen_loop_card_file.png`** (200 KB) — Фаза `DOC_SEARCH`: картотека технического бокса с разделителями ящиков и карточками регламентов.
4. **`docs/preview/screen_loop_doc_reader.png`** (195 KB) — Фаза `DOC_SEARCH` (чтение): бланк регламента `ТО-04. СЕРВОПРИВОД ПЛЕЧА`, норма времени, инструмент и шаги.
5. **`docs/preview/screen_loop_verify.png`** (56 KB) — Фаза `VERIFY`: панель контрольного теста ОТК, осциллограмма сигнала, параметры качества и зелёный штамп `ГОДЕН`.

### 6.2. Результаты запуска тестового набора (`tools/run_all_tests.ps1`)

| Название теста | Статус | Время | Проверок / Описание |
|---|---|---|---|
| `test_audio_credits.gd` | **PASS** | 0.21s | 149 проверок аудио-реестра |
| `test_cutscene_intro.gd` | **PASS** | 0.30s | 7 проверок синематик-пролога |
| `test_data_integrity.gd` | **PASS** | 0.30s | 33 проверки целостности JSON-данных |
| `test_gameplay.gd` | **PASS** | 0.28s | **69 проверок** легаси-ядра и этапов |
| `test_loop_audio.gd` | **PASS** | 0.48s | 21 звуковое событие и кроссфейд музыки |
| `test_procedural_audio.gd` | **PASS** | 0.40s | Процедурный синтез аудио |
| `test_proximity_awareness.gd` | **PASS** | 0.30s | Реакция автоматона на мышь |
| `test_robot_interactivity.gd` | *FAIL* | 0.75s | *известное ограничение прототипа* |
| `test_robot_optics.gd` | **PASS** | 0.29s | Оптика и свечение сенсоров |
| `test_robot_procedural_animation.gd` | **PASS** | 0.20s | Дыхание и тремор автоматона |
| `test_robot_thermal_fx.gd` | **PASS** | 0.30s | Тепловые эффекты и пар |
| `test_session.gd` | **PASS** | 0.29s | Смена, FSM, пауза, угроза, верификация |
| `test_steps.gd` | **PASS** | 0.49s | Все 5 типов шагов StepRunner |
| `test_tactile_mechanics.gd` | **PASS** | 0.95s | Тактильные механики и сцена `Main.tscn` |
| `test_tactile_tutorial_hud.gd` | **PASS** | 0.39s | Тактильный HUD |
| `test_ui_intents.gd` | **PASS** | 0.39s | 69 проверок UI-панелей и LoopScreens |

**Итог:** 15 из 16 тестов успешно пройдены (100% валидных тестов с кодом выхода 0). Единственный красный тест — зафиксированный в контракте baseline.
