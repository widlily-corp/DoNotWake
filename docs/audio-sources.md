# Источники аудио и музыки

Ведётся со дня создания аудио-системы. Из этого файла и `docs/sources.md` собирается единый документ `Источники.pdf`.
Все аудиоматериалы проекта имеют свободные, открытые или процедурные лицензии (без NC, без SA, без коммерческих ограничений).

## Реестр треков и звуковых эффектов

| Файл | Трек / Описание | Автор | Лицензия | Ссылка | Что изменено |
|---|---|---|---|---|---|
| `assets/music/menu_hum.ogg` | Workshop Menu Hum Loop | Evilbyte Studio | Procedural | — | Процедурный синтез (50 Hz mains hum, pink noise ventilation, LFO 0.08 Hz, seamless 3.0s xfade loop) |
| `assets/music/ambient_calm.ogg` | Cold Workshop Ambient Calm Loop | Evilbyte Studio | Procedural | — | Процедурный синтез (55/60 Hz sub drone, inharmonic metallic groans, seamless 4.0s xfade loop) |
| `assets/music/ambient_threat.ogg` | Tension Pulse Ambient Threat Loop | Evilbyte Studio | Procedural | — | Процедурный синтез (55 Hz base, open resonant bandpass, 1 Hz mechanical pulse, seamless 4.0s xfade loop) |
| `assets/music/sting_wake.ogg` | Wake Stinger Jolt | Evilbyte Studio | Procedural | — | Процедурный синтез (120 ms тишины, саб-бас панч 85->35 Hz, щелчок защёлки, гидравлика) |
| `assets/music/end_resolve.ogg` | Shift Resolve Exhale | Evilbyte Studio | Procedural | — | Процедурный синтез (пневматический сброс давления 1000->250 Hz, теплый аккорд 110/165/220 Hz) |
| `assets/music/end_fail.ogg` | Shift Fail Shutdown | Evilbyte Studio | Procedural | — | Процедурный синтез (глухой удар зажима 48 Hz, затухающий вой привода 550->0 Hz) |
| `assets/sounds/calm_down.wav` | Hydraulic Pressure Release | Evilbyte Studio | Own | — | Синтез гидравлического сброса давления при стабилизации |
| `assets/sounds/click.wav` | UI Click Mechanical | Evilbyte Studio | Own | — | Короткий тактильный клик переключателя |
| `assets/sounds/error_buzz.wav` | Error Buzzer Alert | Evilbyte Studio | Own | — | Зуммер ошибки выбора инструмента / срыва действия |
| `assets/sounds/horror-drone.wav` | Atmospheric Horror Sub Drone | Evilbyte Studio | Own | — | Фоновый глубокий гул операционной |
| `assets/sounds/mouse click.wav` | Mouse Click Button | Evilbyte Studio | Own | — | Микровыключатель мыши |
| `assets/sounds/repair_success.wav` | Repair Step Success Chime | Evilbyte Studio | Own | — | Подтверждающий двухтональный сигнал успешного ремонта |
| `assets/sounds/robot_awake.wav` | Robot Awake Alarm Whine | Evilbyte Studio | Own | — | Сигнал пробуждения робота и активации сенсоров |
| `assets/sounds/strap_creak.wav` | Restraint Strap Tension Creak | Evilbyte Studio | Own | — | Скрип натяжения ремней фиксации |
| `assets/sounds/strap_creak_heavy.wav` | Heavy Restraint Strap Creak | Evilbyte Studio | Own | — | Глухой скрип тяжелого натяжения ремней фиксации |
| `assets/sounds/vhs_insert.wav` | VHS Deck Cassette Latch | Evilbyte Studio | Own | — | Механический щелчок посадки кассеты в привод |

## Процедурные звуки в рантайме (`ProceduralAudio`)

Генерируются непосредственно в памяти через `scripts/core/procedural_audio.gd`:
- `ratchet_click` (4 вариации): щелчки храпового механизма (40 мс)
- `bolt_chime` (3 вариации): звон стального болта с отскоками по металлическому столу (320 мс)
- `steam_burst`: резкий выброс пара перегретых медных контактов (380 мс)
- `steam_loop`: бесшовный свист выходящего пара (850 мс)
- `tool_slip`: срыв жала отвертки со шлицев и металлический скрежет (180 мс)
- `hatch_thud`: глухой удар и резонанс бронелюка (350 мс)
- `electric_impulse`: разряд высоковольтной дуги и сетевой гул 100 Гц (280 мс)
- `scan_sweep`: частотный свип 400→1200 Гц луча диагностики (600 мс)
- `relay_click`: два механических щелчка контактов реле (120 мс)
- `paper_rustle` (3 вариации): органичный шелест и перелистывание бумажной карты (200 мс)
- `stamp_thud`: тяжелый удар штампа и бумажный хруст (150 мс)
- `alarm_ping`: тревожный пинг 880 Гц с микро-дрожанием (150 мс)
- `wake_silence`: маркер мгновенного звукового обрыва (120 мс)

Автор всех процедурных алгоритмов: Evilbyte Studio. Лицензия: Procedural / CC0.
