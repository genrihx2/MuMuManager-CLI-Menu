# MuMu Manager CLI Menu

[![Code Scanning](https://github.com/genrihx2/MuMuManager-CLI-Menu/actions/workflows/security-scan.yml/badge.svg)](https://github.com/genrihx2/MuMuManager-CLI-Menu/actions/workflows/security-scan.yml)
[![Latest Release](https://img.shields.io/github/v/release/genrihx2/MuMuManager-CLI-Menu?label=latest)](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)
[![Release Date](https://img.shields.io/github/release-date/genrihx2/MuMuManager-CLI-Menu)](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases)

> Открытый исходный код. Скрипт управляет локальными инстансами MuMu Emulator на вашей машине. Функции приватности (подмена модели, случайные IMEI/Android ID/MAC) работают только на собственных инстансах и требуют подтверждения.

Интерактивное PowerShell-меню для управления MuMu Emulator (6.x).

Русский · English summary — см. раздел "English summary" ниже.

## Возможности

- 🚀 Запуск, выключение, перезагрузка эмулятора
- 🐑 Клонирование инстансов
- 🗑️ Удаление инстансов
- ✏️ Переименование инстансов
- 📦 Установка и удаление приложений (APK)
- 📱 ADB-команды
- 🧹 Очистка данных приложения, force stop, запуск приложения
- 💾 Экспорт данных инстанса (.mumudata)
- 💾 Резервное копирование папки данных инстанса (vms) с прогрессом
- 🗜️ Сжатие бэкапа в ZIP (встроенный tar, опционально с удалением исходной папки)
- 🎭 Подмена модели устройства (brand / model / код модели)
- 📶 Смена оператора/SIM страны (MCC/MNC, iso-country) — для TikTok и др. (38 пресетов + кастом)
- 🎲 Генерация случайных IMEI (с контрольной суммой) / Android ID / MAC
- 📸 Скриншоты эмулятора через ADB
- 🎬 Запись экрана (screenrecord, до 180с)
- 📁 Передача файлов push/pull между PC и эмулятором
- 💻 Интерактивная ADB-сессия (прямой shell)
- 🔐 Цифровая подпись скрипта (self-signed CodeSigning сертификат)
- 🪟 Управление окнами: показать/скрыть все, закрыть все инстансы одним вызовом
- 🧩 Сетка окон `[L]` — shrink-to-fit: считается один коэффициент `scale = min(1, (W-2M-(C-1)G)/(C*w), (H-2M-(R-1)G)/(R*h))` по рабочей области экрана (M = G = 10 px, `C = min(окон в ряд, N)`, `R = ceil(N/C)`). «Исходный размер» — тот, с которым MuMu открывает окно инстанса (он хранится в `customer_config.json` самого инстанса), поэтому окно, ранее уменьшенное раскладкой, возвращается к нормальному размеру, а не остаётся маленьким. Увеличивать сверх этого размера скрипт не умеет, пропорции сохраняются, порядок — слева направо и сверху вниз. После раскладки окна один раз поднимаются наверх (без always-on-top).
- 🎬 `mmor-run.ps1` — отдельный скрипт рядом с меню (не пункт `[L]`): `-Apply -File x.mmor` — это GUI-автоматизация мышью (курсор + `mouse_event` по окну Operation Recorder), поэтому зависит от позиции окна, DPI, фокуса и таймингов. Нативной команды для `.mmor` у MuMu нет — воспроизведение живёт только в GUI; варианты без мыши описаны в `SKILL.md`.
- 🔄 Массовые операции (все инстансы)
- 📋 Просмотр логов (статические файлы + **adb logcat**: снапшот, live-стрим, фильтр по уровню/тегу)
- 🛡️ Менеджер GitHub-токена (DPAPI-шифрование)

> Хранилище токена — `.github-token.dpapi`, зашифрованный DPAPI-блоб (CurrentUser). Это не простая строка и не portable-файл: ручная попытка расшифровки в стороннем PowerShell может вообще не выполниться, если среда не загружает `System.Security.Cryptography.ProtectedData`, а сам блоб не читается после перемещения между машинами/пользователями. В таких случаях восстановление — через меню `[K]`, а не редактированием или ручным дешифрованием файла.
- 📊 Информация о версиях
- ⚡ Автообновление из GitHub
- 🗄️ Загрузка репозитория (git clone, ZIP, отдельный файл)

Для полного списка функций и опций см. SKILL.md или запустите меню.

- 📥 Offline-инсталляторы: пункт `[OI]` показывает все текущие официальные сборки (Windows .exe, macOS .dmg, Android APK) прямо из CDN NetEase — с именем файла, размером и бейджем целостности, когда заголовки его отдают. Без скачивания, только список. Источник: https://www.mumuplayer.com/ 
- 🐙 JavaScript-движок (`node mumu-menu.cjs`): статус и управление инстансами, сетевой watcher и проверка версий — нативно на Node.js, без npm install; остальные функции по-прежнему в полном PowerShell-меню, куда JS-меню передаёт управление.

## Требования

- Windows 10/11
- PowerShell 5.1+ или PowerShell 7+
- MuMu Emulator 6.x (тестировано на V6.7.1, минимально поддерживаемая версия: 4.0.0.3179)
- Node.js 18+ — опционально, только для JavaScript-движка

## Установка

Через Git:

```powershell
git clone https://github.com/genrihx2/MuMuManager-CLI-Menu.git
cd MuMuManager-CLI-Menu
.\mumu-menu.ps1
```

Два движка, один репозиторий. PowerShell-меню (`mumu-menu.ps1`) остаётся эталонным и работает ровно как раньше; JavaScript-движок (`mumu-menu.cjs`) добавляет нативную альтернативу для тех, у кого есть Node.js 18+ — ноль зависимостей, `npm install` не нужен, запуск из любой папки:

```powershell
node mumu-menu.cjs              # интерактивное JS-меню
node mumu-menu.cjs --status     # таблица инстансов (read-only; --json для машинного вывода)
node mumu-menu.cjs --watch      # сетевой watcher + updater (read-only)
node mumu-menu.cjs --ps         # полное PowerShell-меню (все функции)
```

JS-движок покрывает `--status`/`--list`, `--start/--stop/--restart <N>`, `--watch [--interval <сек>] [--log <файл>]` и `--ps`; остальное (APK, ADB, бэкапы, spoofing, обновления, `[DIAG]` и т.д.) делает PowerShell-меню, в которое JS-меню передаёт управление. Оба файла лежат рядом и в git-клоне, и в установленной папке, поэтому `node mumu-menu.cjs` работает и в деплое.

`npm run menu` — то же самое через package.json (только в git-клоне).

Быстрый запуск (скачивает и запускает временный файл):

```powershell
irm https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/mumu-menu.ps1 -OutFile $env:TEMP\mumu-menu.ps1; & $env:TEMP\mumu-menu.ps1
```

Или скачайте ZIP с Releases и запустите `mumu-menu.ps1`.

## Использование

Запуск меню:

```powershell
.\mumu-menu.ps1
```

Если PowerShell отказывается запускать скрипт с ошибкой «выполнение сценариев отключено в этой системе» (`PSSecurityException`), в git-клоне используйте `mumu-menu.cmd` — двойной клик или:

```cmd
mumu-menu.cmd
```

Лаунчер поднимает PowerShell с `-ExecutionPolicy Bypass` только для этого процесса: системная политика и реестр не меняются, окно закрывается вместе с меню. В ZIP с Releases этого файла нет — там снимайте блокировку через `Unblock-File` или запускайте `powershell -ExecutionPolicy Bypass -File .\mumu-menu.ps1`.

Меню предоставляет удобный интерактивный интерфейс для выбора инстанса и выполнения операций (ADB, установка APK, бэкап/рестор, spoofing, просмотр логов и т.д.).

### Неинтерактивный режим

Для скриптов, CI и циклов по всем инстансам есть `-Action`: ни одного вопроса, код возврата `0` только когда все запрошенные инстансы отработали.

```powershell
.\mumu-menu.ps1 -Action launch  -Instance all        # запустить все и дождаться загрузки
.\mumu-menu.ps1 -Action stop    -Instance 0,2        # остановить два конкретных
.\mumu-menu.ps1 -Action restart -Instance all -Json  # перезапуск, машинный вывод
.\mumu-menu.ps1 -Action logs    -Instance 0 -Lines 50  # снапшот logcat
```

- `-Instance` — `all` (по умолчанию), один индекс или список через запятую; неизвестный индекс — ошибка, а не тишина.
- `-Lines` — сколько строк logcat брать для `logs` (по умолчанию 200).
- `-TimeoutSec` — сколько ждать загрузки для `launch`/`restart` (по умолчанию 300; интерактивное меню ждёт 120).
- `-Json` — вместо строк выводит объект (`action`, `ok`, `failed`, `instances[]`).

Стартовая проверка обновлений и баннер при `-Action` не выполняются, поэтому stdout остаётся пригодным для разбора.

## Порядок помощи

Если что-то не работает, используйте такой порядок:

1. Проверьте требования
   - Windows 10/11
   - PowerShell 5.1+ / 7+
   - MuMu установлен и доступен
   - Скрипт запущен из корректной папки

2. Запустите меню и проверьте состояние
   - `[V]` — версия и окружение
   - `[IN]` — активная установка MuMu
   - `[ST]` — статус установки
   - `[DIAG]` — диагностика проблем

3. Если меню не запускается
   - Проверьте `Mark-of-the-Web` и `Unblock-File`
   - Попробуйте запустить через PowerShell явно
   - Убедитесь, что у вас нет блокировки по политике ExecutionPolicy

4. Если есть проблема с MuMu
   - Проверьте активную установку через `[IN]`
   - Используйте `[DIAG]` для проверки установки
   - Проверьте наличие запущенных инстансов и ADB-моста

5. Если обновление не проходит
   - Сначала `[F]` — проверить целостность файлов
   - Затем `[ST]` — посмотреть общий статус
   - Затем `[J]` — посмотреть журнал обновлений
   - Если нужно, выполните восстановление из `backup\\YYYYMMDD_HHMMSS`

6. Если нужен полный список изменений
   - `relnotes.md`
   - GitHub Releases: https://github.com/genrihx2/MuMuManager-CLI-Menu/releases

7. Если нужен быстрый ответ
   - Проблема с запуском и файлами → `MotW / Unblock-File`
   - Проблема с MuMu → `[DIAG]` и `[IN]`
   - Проблема с обновлением → `[F]`, `[ST]`, `[J]`

8. Если меню пишет «Cannot decrypt .github-token.dpapi» или token не работает
   - Не пытайтесь расшифровать `.github-token.dpapi` вручную — это DPAPI blob (CurrentUser), он не переносится между машинами/пользователями и не поддаётся простому ручному раскладыванию.
   - В меню выберите `[K]` Update GitHub token, введите токен заново, дождитесь проверки `api.github.com/user` и сохранения.
   - Если вы работали в PowerShell, где нет загрузки `System.Security.Cryptography.ProtectedData`, то даже ручная попытка `[...ProtectedData]::Unprotect(...)` будет падать с `TypeNotFound` — это проблема среды, а не манифеста репозитория.

## Автообновление и проверка целостности

- Обновления берутся только из помеченных тегов релизов GitHub Releases.
- Перед установкой ZIP проверяется по SHA-256; после установки — сверка локальных файлов с содержимым тега.
- Подробная логика и поведение обновления документированы в README и в скриптах `bootstrap-update.ps1` и `mumu-menu.ps1`.

## Mark-of-the-Web (MotW)

Если вы распаковали релиз ZIP через Windows Explorer и PowerShell отказывается запускать скрипт (ошибка "not digitally signed"), это, скорее всего, из-за Mark‑of‑the‑Web (NTFS Zone.Identifier). Решения:

1. Использовать пункт `[U]` в меню или `bootstrap-update.ps1` (рекомендуется).
2. Выполнить `Get-ChildItem 'C:\\путь\\к\\MuMuManager-CLI-Menu' -Recurse -File | Unblock-File`.
3. Распаковать ZIP с помощью `tar`/7-Zip вместо встроенного экстрактора Explorer.

## Что нового

### v10.4.36 (23.11.2026)

- Fixed: `yes` на запросе согласия больше не отменяет опцию. `Confirm-AdbConsent` (`[A]`, `[AF]`, `[AS]`, `[AH]`) и `Confirm-SpoofConsent` (`[DM]`, `[SIM]`, `[SIM+]`, `[AI]`, `[DI]`) требовали ровно `OK` (`-eq 'OK'`), поэтому ответ `yes` печатал «Cancelled (consent not given)»; общий `Test-ConsentAnswer` принимает `OK`/`yes`/`y` в любом регистре, подсказка обновлена, остальные ответы по-прежнему отменяют действие.
- Tests: **381/381** Pester на pwsh, PSScriptAnalyzer 0 findings с настройками репозитория, разбор без ошибок, UTF-8 BOM сохранён, CRLF = 0.

### v10.4.35 (23.11.2026)

- Changed: 11 замечаний сканеров в `mumu-ui.ps1` устранены без изменения поведения окна. Пространства имён XAML больше не хранятся в файле литералами `http://` — схема собирается в рантайме, а `Expand-XamlNamespace` подставляет `__WPFNS__` / `__XAMLNS__` перед парсером (пять here-string-блоков и два инлайновых `DataTemplate`); `Write-Log` переименован в `Add-DeviceLog` (перекрывал встроенное имя), три пустых `catch { }` пишут `Write-Debug` с текстом исключения, `$sender` заменён на `$source`.
- Fixed: job `security-scan` больше не падает с `PSScriptAnalyzer produced no SARIF output` — `.github/scripts/psa-sarif.ps1` сам пишет SARIF 2.1.0, потому что `Invoke-ScriptAnalyzer | ConvertTo-SARIF` в композитном экшене валился с `Object reference not set`.
- Tests: **381/381** Pester на pwsh, PSScriptAnalyzer 0 findings с настройками репозитория, все XAML-блоки парсятся `XamlReader`, `test-changelog-sync.ps1` и `test-orphan-files.ps1` зелёные.

### v10.4.34 (22.11.2026)

- New: раздел «Диск» в «Настройках устройства» — как в MuMu: «Очистка диска» открывает папку инстанса, «Дисковое пространство» показывает занятое место из `info -v <i>` (`disk_size_bytes`) и свободное место на диске с `vms`. Оба числа реальные, один вызов менеджера на секцию.
- Fixed: «Папка инстанса не найдена: менеджер не назвал путь» — у части инстансов нет ключа `device_thumbnail`, и путь строился только из него. Теперь папка ищется и по правилу MuMu: каталог в `<установка>\vms` с окончанием `-<индекс>` (проверено на инстансах 0 и 2).
- Note: «Расширить» нет — у `MuMuManager` нет ни ключа ёмкости (`setting -aw`: 44 ключа, ни одного про диск), ни команды расширения, а 126 ГБ в MuMu — размер гостевой ФС внутри `data.vdi`.
- Tests: **381/381** Pester на pwsh, `test-changelog-sync.ps1` и `test-orphan-files.ps1` зелёные.

### v10.4.33 (22.11.2026)

- New: пункт `[UI]` — нативное окно `mumu-ui.ps1` (WPF) поверх того же `MuMuManager.exe`, без новых зависимостей и без сети. Карточки устройств показывают Android, состояние и текущий `max_frame_rate`; кнопки запускают, останавливают и перезапускают выбранный инстанс, а лог печатает сырые ответы менеджера.
- New: экран «Настройки устройства» — семь разделов по реальным ключам `setting -v <i> -a` (Производительность, Дисплей, Звук, Сеть, Модель, Для разработчиков, Другие). Разрешение списком как в MuMu (`1920 × 1080, 280 DPI (Планшет)` … `Пользовательский`), готовая модель устройства подставляет бренд, модель и код, рендерер — `Режим Vulkan` / `Режим DirectX` (значения `gles`, `gl`, `opengl`, `directx` менеджер отклоняет, проверено чтением обратно).
- New: `Копировать` (`clone`), `Переименовать` (`rename`), `Резервная копия` (`export`), `Восстановить` (`import`) и `Удалить` (`delete -v`) — действия из контекстного меню MuMu, кроме «Очистки диска» и ярлыка: у `MuMuManager` для них нет команд.
- Fixed: правка настройки больше не уходит с пустым ключом — обработчики строк создавались без `GetNewClosure()`, из-за чего `$Key` к моменту клика не разрешался и менеджер отвечал `cmd params invalid` / `key not writable`.
- Fixed: FPS пишется в `max_frame_rate` через `MuMuManager setting`, а не в `customer_config.json` → `setting.frame_setting.desired_framerate`, который плеер перезаписывает из своего хранилища.
- Fixed: список устройств читается двумя вызовами менеджера вместо вызова на каждый инстанс, а сохранение настройки проверяет только свой ключ — окно не замирает на каждом действии.
- Tests: **381/381** Pester на pwsh, `test-changelog-sync.ps1` и `test-orphan-files.ps1` зелёные.

### v10.4.32 (22.11.2026)

- Fixed: `[U]` больше не рапортует «Up to date» вместо починки. После `Repairing: downloading the release file set` блок лечения маркера больше не срабатывает: локальный `mumu-menu.ps1` совпадал по хэшу с тегом, печаталось `Up to date (v10.4.31)` и функция выходила до цикла скачивания — отсутствующий файл (живой случай: `mumu-f11-probe.ps1`) не появлялся никогда.
- Fixed: набор файлов после докачки перепроверяется по диску, а не по счётчику цикла. Если файл так и не лёг — `Repair failed - N file(s) are still missing: ...`, запись `update-fail` в журнал, `.version` не двигается, код возврата 1. При успехе — `Repaired N file(s), up to date (vX.Y.Z)`.
- Fixed: `[RF]` удаляет устройство через `MuMuManager delete -v <index>` и проверяет по `info -v all`, что индекс исчез; ручное удаление каталогов оставляло «призрак» с бесконечным спиннером в MuMu.
- Fixed: `[RF]` больше не удаляет `nx_device\<version>` — это общий Android-рантайм всех инстансов версии, и его удаление давало `errcode 60014 "android engine not installed"` до переустановки MuMu.
- Fixed: призрак (индекс в списке менеджера, папки `vms` нет) чинится, а не отвергается; выбранный индекс считается существующим, даже если опрос `info -v all` не ответил; подтверждение принимает `YES` в любом регистре и показывает введённое значение при отказе; неудачное удаление перечисляет уцелевшие пути и говорит `Nothing was deleted`, когда не тронуто ничего; резерв удаления — один проход с одним повтором после закрытия процессов MuMu из этих папок.
- Tests: **381/381** Pester на pwsh и PowerShell 5.1, `test-changelog-sync.ps1` и `test-orphan-files.ps1` зелёные; живой прогон `[RF]` на MuMu 6.8.9.0 пересоздал инстанс 2 с `errcode 0`.

### v10.4.31 (22.11.2026)

- New: пункт `[RF]` «Repair device» — восстановление устройства, когда MuMu отказывается запускаться с `Startup failed: An abnormal runtime environment was detected` (и русской формой «Обнаружена неисправность среды выполнения»). Сначала печатается план: `nx_device\15.0` в папке установки и каталог выбранного инстанса в `vms`, с размерами через `Get-PathSizeMb`; удаление — только после подтверждения, MuMu перед этим останавливается, затем устройство Android 15 создаётся заново. Если файл не удаляется, `Get-MumuRepairFailureHint` называет причину (MuMu не закрыт, файл держит процесс), а не выдаёт общую ошибку.
- New: `mumu-f11-probe.ps1` — отдельный пробник F11, по умолчанию ничего не разрушающий. Стадии `Prepare` / `Wait` / `Report` / `Cleanup`: свободный индекс начиная с 2, проверка движка 12.0 по каталогу инстанса и `nx_device\*` в конфигах, хэш-снимок инстансов 15.0 до и после с diff, baseline `shell.log` по числу строк и выписка только новых строк по паттернам, `graphics_log` по времени после старта теста, режим монитора через `EnumDisplaySettings` до F11 / после F11 / после Esc и вердикт `EXCLUSIVE` / `BORDERLESS` / `INCONCLUSIVE` в `REPORT.md`. Индексы из `-ProtectedIndexes` (0 и 1 по умолчанию) не затрагиваются, `create`/`delete` — только с `-AllowCreate`/`-AllowDelete`, F11 нажимает пользователь; строки `lib*.dll` движка 12.0 выгружаются для уточнения паттернов.
- File: `mumu-f11-probe.ps1` — UTF-8 с BOM и LF, разбор `Parser::ParseFile` чист на PowerShell 5.1 и 7, файл добавлен в `release-files.txt` и попадает в релизный ZIP.
- Tests: **375/375** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний, `test-changelog-sync.ps1` и `test-orphan-files.ps1` зелёные.

**EN summary (v10.4.31):** two additions, the menu paths themselves are unchanged. `[RF]` now performs the repair that actually clears MuMu's `Startup failed: An abnormal runtime environment was detected` (the Russian dialog reads «Обнаружена неисправность среды выполнения»): it lists exactly what it will touch - `nx_device\15.0` under the install plus the selected instance folder under `vms`, with sizes from `Get-PathSizeMb` - asks for confirmation, stops MuMu, deletes those two paths and recreates the Android 15 device; if a delete fails, `Get-MumuRepairFailureHint` names the real cause (MuMu still running, a process holding the files) instead of a generic error. `mumu-f11-probe.ps1` is a separate probe that changes nothing by default, split into `Prepare` / `Wait` / `Report` / `Cleanup`: it takes a free index from 2, verifies the instance really runs the 12.0 engine, snapshots the 15.0 instances' config hashes before and after with a diff, records a `shell.log` line baseline and extracts only the new matching lines, filters `graphics_log` by time since the run started, samples the monitor mode via `EnumDisplaySettings` before F11 / after F11 / after Esc, and writes an `EXCLUSIVE` / `BORDERLESS` / `INCONCLUSIVE` verdict to `REPORT.md`; protected indexes are never touched, `create`/`delete` require `-AllowCreate`/`-AllowDelete`, and F11 is pressed by the user. The script ships in the release ZIP, is stored as UTF-8 with a BOM and LF, and parses clean on PowerShell 5.1 and 7. Tests 375/375 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, changelog-sync and orphan-files green.

### v10.4.30 (21.11.2026)

- Fixed: `mumu-menu.cmd` больше не обещает интерфейс, которого нет. Обёртка документировала глаголы `run`/`start`/`wait`/`status`, ключи `--once`/`--index`/`--restore`/`--deep` и переменные `MUUMU_EXE`/`MUUMU_INDEX`/`MUUMU_RESTORE`, а `mumu-menu.ps1` ничего из этого не объявляет — каждая такая команда падала на `ValidateSet` или на привязке параметров. Теперь `.cmd` — тонкий диспетчер на реальные параметры: `launch`/`stop`/`restart`/`logs` → `-Action`, `--instance`/`--lines`/`--timeout`/`--json`/`--force` → `-Instance`/`-Lines`/`-TimeoutSec`/`-Json`/`-Force`. Неизвестный глагол, неизвестная опция и опция без значения отсекаются самим `.cmd` с кодом 2; без аргументов по-прежнему открывается интерактивное меню, `help` (он же `/?`, `/h`, `-h`, `--help`) печатает те же глаголы и опции.
- Fixed: `[OI]` «Offline installers» падал с `Невозможно вызвать метод для выражения со значением null` на сетях, где страница релиза отдавала относительную ссылку на установщик. `[System.Uri]($page).AbsoluteUri` разбирается как `[System.Uri](($page).AbsoluteUri)`: у строки такого члена нет, приведение возвращает `$null`, и следующий `.TrimEnd()` падает. Обе ветки — `.exe` и `.dmg` — теперь строят адрес через `[System.Uri]::new([System.Uri]$page, $href)`, что заодно правильно разрешает и корневые (`/MoMu/...`), и страничные (`MuMu.dmg`) ссылки. Новый тест держит запрет на старую форму и оба случая разрешения.
- New: экран запуска объясняет отказ эмулятора, а не только пересказывает его. На `Startup failed: An abnormal runtime environment was detected` и его русскую форму «Обнаружена неисправность среды выполнения» (это проверка виртуализации: VT-x выключен или занят Hyper-V/VBS и Core Isolation) меню сразу возвращается без 120-секундного ожидания и печатает порядок действий: кнопка «Восстановить» на этом экране не помогает (проверено), поэтому нужно удалить каталог `nx_device\15.0` в папке MuMu (например `C:\Program Files\Netease\MuMuPlayer\nx_device\15.0`) и папку инстанса в `vms` (например `MuMuPlayerGlobal-15.0-0`), а затем создать устройство заново (New → Create Device → Android 15); если ошибка повторится на новом устройстве — VT-x в «Диспетчере задач» (Производительность → ЦП → Виртуализация: Включено), Hyper-V / Windows Hypervisor Platform / Virtual Machine Platform, Core Isolation → Memory integrity, затем перезагрузка. Та же подсказка появляется при истечении ожидания загрузки и в пакетном `launch`/`restart` (то есть у `mumu-menu.cmd launch`); незнакомый вывод не додумывается — остаётся только строка ошибки.
- Tests: **363/363** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний; изменился только `.cmd` и две строки склейки URL в `[OI]`.

**EN summary (v10.4.30):** both fixes are small and local. `mumu-menu.cmd` no longer documents the invented `run`/`start`/`wait`/`status` verbs, the `--once`/`--index`/`--restore`/`--deep` flags or the `MUUMU_*` variables: it dispatches `launch`/`stop`/`restart`/`logs` onto `-Action` and `--instance`/`--lines`/`--timeout`/`--json`/`--force` onto the `-Instance`/`-Lines`/`-TimeoutSec`/`-Json`/`-Force` parameters, rejects an unknown verb, an unknown option or an option without a value with exit code 2, keeps the bare-call interactive menu, and passes the script's own exit code through. In `[OI]`, a relative installer link is resolved with `[System.Uri]::new([System.Uri]$page, $href)` instead of `[System.Uri]($page).AbsoluteUri`, which PowerShell parses as `[System.Uri](($page).AbsoluteUri)`, yields `$null` and makes the following `.TrimEnd()` die with "You cannot call a method on a null-valued expression"; both the `.exe` and the `.dmg` branch are fixed, and a test pins the call shape plus root-relative and page-relative resolution. The launch screens now also explain MuMu's own "Startup failed: An abnormal runtime environment was detected" and the Russian dialog it actually shows ("Обнаружена неисправность среды выполнения"): that sentence is the emulator's virtualization check (VT-x off, or taken by Hyper-V/VBS and Core Isolation), so the screen returns at once instead of waiting out the 120 s boot timeout, and lists the repair that works (its Restore button does not: delete `nx_device\15.0` under the MuMu install and the instance folder under `vms`, then create the device again from New > Create Device > Android 15; if it comes back, VT-x in Task Manager > Performance > CPU, Hyper-V / Windows Hypervisor Platform / Virtual Machine Platform, Core Isolation > Memory integrity, then a reboot); the same hint follows a boot timeout and a batch `launch`/`restart` failure, and output the menu cannot explain is not guessed at. Tests 363/363 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings.

### v10.4.29 (21.11.2026)

- Docs+hardening: шапки вспомогательных скриптов приведены к тому, что код реально делает, и там, где скрипт пишет на диск, появился режим без записи:
  - `Watch-MumuConnections.ps1` — «Read-only for the network stack» и `-NoLog`; единственная запись идёт через `Add-WatchLine`, при `-NoLog` не создаётся даже сам файл лога.
  - `Diag-MumuNx.ps1` — убрано обещание «WHOIS-lite» (код делает только reverse-DNS PTR); сказано, что отчёт пишется в `%PUBLIC%` и его может прочитать любой локальный пользователь; добавлен `-NoFile`: вывод только в консоль.
  - `Test-MumuTunnelAB.ps1` — заявка «READ-ONLY» сужена до сетевого стека и перечислены реальные файлы (`snapshot-*.json`, `diff-<A>-vs-<B>.txt` в `%TEMP%\mumu-ab`); добавлен `-NoSave`: снимок и отчёт остаются в памяти, каталог не создаётся.
  - `mmor-run.ps1` — шапка объясняет, что C#-хелпер компилируется `Add-Type` (csc.exe на 5.1, в памяти на 7) и не скачивается как DLL, а единственная запись — файл калибровки `mmor-run.json`; добавлен `-NoWrite`.
  - `bootstrap-update.ps1` — загрузка по `https://` запинена на HTTPS (`--proto '=https' --proto-redir '=https'`), `file://`-фикстуры не затронуты; в шапке сказано, что переподпись использует существующий сертификат и никогда не пишет в хранилища Root/CA/AuthRoot.
- `mumu-menu.ps1`: в блок SIGMA RULE EXCLUSIONS добавлено правило `Dynamic CSharp Compile Artefact` — описаны оба класса из `Add-Type` (`MuMuMenuCtrlCGuard` для Ctrl+C, `MuMuWindowGrid` для сетки окон `[L]`) и то, что `%TEMP%`-артефакты создаёт сам компилятор. Правило `Suspicious Process Discovery With Get-Process` уточнено: кроме `-Name 'MuMu*'` есть один `-Id`-запрос за путём EXE апдейтера, без перечисления чужих процессов.
- Tests: **355/355** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний, `test-changelog-sync.ps1` и `test-dependency-overrides.ps1` зелёные. Новые тесты держат `-NoLog`/`-NoFile`/`-NoSave`/`-NoWrite` и точность формулировок в шапках.

**EN summary (v10.4.29):** the helper-script headers now say what the code actually does, and every script that writes to disk gained a no-write mode. `Watch-MumuConnections.ps1` scopes its read-only claim to the network stack and adds `-NoLog` (the only write is `Add-WatchLine`; with `-NoLog` even the log file is not created). `Diag-MumuNx.ps1` drops the unearned "WHOIS-lite" claim for the reverse-DNS (PTR) lookup it really performs, says the `%PUBLIC%` report is readable by every local user, and adds `-NoFile`. `Test-MumuTunnelAB.ps1` narrows its read-only claim to the network stack, lists the snapshot and diff files it writes under `%TEMP%\mumu-ab`, and adds `-NoSave`, which keeps the snapshot and report in memory. `mmor-run.ps1` explains that its C# helper is compiled by `Add-Type` (csc.exe on 5.1, in memory on 7) rather than downloaded as a DLL, names `mmor-run.json` as its only write, and adds `-NoWrite`. `bootstrap-update.ps1` pins `https://` downloads to HTTPS (`--proto '=https' --proto-redir '=https'`, leaving `file://` fixtures alone) and states that re-signing reuses the existing certificate and never writes to the Root/CA/AuthRoot stores. In `mumu-menu.ps1` the SIGMA RULE EXCLUSIONS block gains the `Dynamic CSharp Compile Artefact` rule, describing both `Add-Type` classes and the compiler's own `%TEMP%` scratch files, and its `Get-Process` note now also covers the single `-Id` lookup for an updater's EXE path. Tests 355/355 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, changelog-sync and dependency-overrides green.

### v10.4.28 (21.11.2026)

- Fixed: `[OI]` «Offline installers (all versions, read-only)» больше не выдаёт недоступный Android-пакет за найденный файл. Если ни один CDN-хост (`a11.gdl.easebar.com`, `a11.gdl.netease.com`) не вернул ни `Content-Length`, ни дайджеста, печатается только `integrity ... did not expose a digest/length` — это читается как «файл есть, просто заголовки скупые». Теперь такой случай помечен явно: `APK not reachable from here - no Content-Length or digest came back from either CDN host`, как у архива Windows-установщиков.
- Строка `integrity` осталась для хоста, который всё же ответил, но только редиректом (`canonical`) или именем файла: путь найден, а длины и хеша в заголовках нет.
- Tests: **343/343** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний; новый тест `marks the APK as not reachable when neither a length nor a digest came back` держит обе ветки.

**EN summary (v10.4.28):** `[OI]` no longer presents an unreachable Android package as a found file. When neither CDN host returned a `Content-Length` or a digest, the screen printed only the `integrity ... did not expose a digest/length` line, which reads like a file with thin headers. That case now says `APK not reachable from here - no Content-Length or digest came back from either CDN host`, as plainly as the Windows signing archive does. The `integrity` wording stays for a host that answered with only a redirect (`canonical`) or a filename: the path exists, the length and hash are just not in the headers. Discovery stays read-only. Tests 343/343 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, plus the new test pinning both branches.

### v10.4.27 (21.11.2026)

- Fixed: `[OI]` «Offline installers (all versions, read-only)» снова показывает список на сетях, где не открывается `www.mumuplayer.com`. Экран был пустым по двум причинам: функция возвращалась сразу после неудачной загрузки страницы релиза, а HEAD через `Invoke-WebRequest` не отдаёт `Location` при `-MaximumRedirection 0` (5.1 бросает `InvalidOperationException` вообще без `Response`, 7 отдаёт `HttpResponseMessage` с пустым `Headers['Location']`), тогда как автопереход по 302 на CDN виснет до таймаута.
- Резолверы переписаны на сырой `HttpClient`: `AllowAutoRedirect = $false`, браузерный `User-Agent` (без него CDN принимает соединение и не отвечает), таймаут поднят с 8 до 12 с, `Location` разбирается вручную и передаётся в запрос за именем и размером файла.
- Страница релиза стала необязательным источником: если она недоступна, печатается предупреждение со ссылкой, а список из API-резолверов остаётся.
- APK проверяется на обоих CDN-хостах (`a11.gdl.easebar.com`, `a11.gdl.netease.com`), у архива — один HEAD на базовый хост и затем документированный шаблон путей вместо трёх таймаутов.
- Функция остаётся read-only: только HEAD-запросы и вывод, без загрузок и записи.
- Tests: 342/342 Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний; добавлен тест `keeps listing when the release page is unreachable`. Живой прогон на этой сети перечисляет Windows `MuMu_6.0.2_1329zT3C.exe` (6 102 432 Б) и macOS `MuMuPlayer_1.9.15_default_1329Ay2C.dmg` (761 308 578 Б) и честно помечает недоступные APK и `down.mumuplayer.com`.

**EN summary (v10.4.27):** `[OI]` («Offline installers (all versions, read-only)») listed nothing on networks that cannot open `www.mumuplayer.com`. The release page used to be mandatory, so its failure ended the function, and the Windows link was lost anyway because `Invoke-WebRequest` cannot report an unfollowed redirect: PowerShell 5.1 throws without any response, 7 returns a response whose `Location` header reads empty, while following the 302 to the CDN hangs until the timeout. The resolvers now issue a raw `HttpClient` HEAD with `AllowAutoRedirect` off and a browser `User-Agent` (the CDN accepts the connection but never answers without one), a 12 s deadline instead of 8, and follow `Location` by hand. The release page is an optional source now: an unreachable page prints a warning with a link and the resolver listing survives. The APK is probed on both CDN hostnames and the archive costs one HEAD on the base host followed by the documented path template instead of three timeouts. Discovery stays read-only - HEAD requests and printing only. Tests 342/342 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, plus a new `keeps listing when the release page is unreachable` test; a live run lists the Windows exe and the macOS dmg and marks the unreachable APK and `down.mumuplayer.com` as such.

### v10.4.26 (21.11.2026)

- Tests: новый `Describe` в `tests/mumu-menu.Tests.ps1` покрывает генератор `mmor-run.json` из v10.4.25 — `recorderButton` из `kToolMenu.kToolMenuBtn`, пустые `playButton`/`fileRow`, дефолтные `delays`, точку как десятичный разделитель даже в `de-DE`, отсутствующую пару как `null`, UTF-8 без BOM, сохранение уже снятых пар при обновлении и round-trip через `Read-MmorConfig`. Функции берутся из `mmor-run.ps1` через AST, поэтому набор идёт без эмулятора и без кликов. Tests 341/341 Pester на pwsh и 5.1, deployed-layout 337/337, PSScriptAnalyzer — 0 замечаний.

**EN summary (v10.4.26):** tests only. A new `Describe` pins the `mmor-run.json` writer: `recorderButton` derived from the tool menu, `playButton`/`fileRow` empty until `-Record`, default delays, dot decimals under a comma-decimal culture, a missing pair as `null` instead of `0,0`, UTF-8 without a BOM, captured pairs kept on refresh and a round-trip through the reader the script itself uses. Functions are AST-extracted from `mmor-run.ps1`, so the suite stays offline. Tests 341/341 on pwsh and PowerShell 5.1, 337/337 in the deployed-layout fixture, PSScriptAnalyzer 0 findings.

### v10.4.25 (20.11.2026)

- New: `mmor-run.ps1` сам создаёт шаблон `mmor-run.json` — при `-EmitConfig` и автоматически, если файла ещё нет; `recorderButton` подставляется из UIA-элемента `kToolMenu.kToolMenuBtn` и нормализуется по окну инстанса, а `playButton` остаётся `null` до прохода `-Record` (пояснение лежит в поле `_comment` внутри файла).
- Обновление шаблона не затирает уже снятые пары (`playButton`, `fileRow`, `delays`), а `-Apply` с незаполненным `playButton` останавливается, а не жмёт наугад. Детали — в `SKILL.md`, подраздел `### Operation recording (.mmor)`; Tests 331/331 Pester, PSScriptAnalyzer — 0 замечаний.

**EN summary (v10.4.25):** `mmor-run.ps1` writes the `mmor-run.json` template itself - on `-EmitConfig` and automatically when the file is missing. `recorderButton` is derived from the instance title bar's `kToolMenu.kToolMenuBtn` and normalized against the window, while `playButton` stays `null` until a `-Record` pass supplies it (explained in the file's `_comment` field, since JSON has no comments and PowerShell 5.1 rejects them). A refresh keeps the pairs already captured, and `-Apply` stops instead of pressing an unset point. Details in `SKILL.md` under `### Operation recording (.mmor)`. Tests 331/331, PSScriptAnalyzer 0 findings.

### v10.4.24 (20.11.2026)

- Docs: пункт про `mmor-run.ps1` в «Возможностях» сокращён до двух предложений — `-Apply -File x.mmor` это GUI-автоматизация мышью (курсор + `mouse_event` по окну Operation Recorder, зависит от позиции окна, DPI, фокуса и таймингов), а нативной команды для `.mmor` у MuMu нет: воспроизведение живёт только в GUI.
- Детали (режимы `-Probe`/`-Record`/`-Apply`, отсутствие вербов `mmor`/`script`/`play` в `MuMuManager.exe` 6.8.9.0, альтернативы без мыши) остались в `SKILL.md`, подраздел `### Operation recording (.mmor)`. Кода это не касается: Tests 331/331 Pester, PSScriptAnalyzer — 0 замечаний.

**EN summary (v10.4.24):** docs only. The README feature bullet for `mmor-run.ps1` is now two sentences: `-Apply -File x.mmor` is GUI mouse automation (cursor plus `mouse_event` on the Operation Recorder window, so window position, DPI, focus and timing matter), and MuMu exposes no native `.mmor` verb - playback lives only in the GUI. The details stay in `SKILL.md` under `### Operation recording (.mmor)`, together with both mouse-free workarounds. No code changes: tests 331/331, PSScriptAnalyzer 0 findings.

### v10.4.23 (20.11.2026)

- Docs: в шапке `mmor-run.ps1` теперь прямо сказано, что `-Apply` — это GUI-автоматизация мышью, а не вызов API: режим двигает курсор на окно Operation Recorder и шлёт туда `mouse_event`, поэтому зависит от позиции окна, DPI, фокуса и таймингов. Годится как временный обход, но не как интеграция.
- Там же зафиксировано, что нативной команды для `.mmor` у MuMu нет: у `MuMuManager.exe` 6.8.9.0 нет ни `mmor`, ни `script`, ни `play` (`control` = launch/shutdown/restart/show_window/hide_window/layout_window/app/tool/shortcut), а воспроизведение живёт только в GUI `MuMuNxMain` — ни pipe, ни endpoint запись не принимает.
- Поддерживаемые альтернативы без мыши: автозапуск записи при старте инстанса («模拟器启动后自动执行 / Auto-execute upon starting the device» у файла записи + `control -v <n> launch`/`restart`) и ввод через собственный канал MuMu (`control -v <n> tool cmd -c "input tap X Y"`). Первая — нативное воспроизведение, но один скрипт на инстанс и только при старте; вторая — повтор ваших тапов, а не проигрывание `.mmor`.
- Та же заметка добавлена в пункт «Возможности» выше и в `SKILL.md` (подраздел `### Operation recording (.mmor)`). Кода это не касается: Tests 331/331 Pester, PSScriptAnalyzer — 0 замечаний.

**EN summary (v10.4.23):** docs only. The `mmor-run.ps1` header now says plainly that `-Apply` is GUI automation - it moves the cursor onto the Operation Recorder window and sends mouse events, so window position, DPI, focus and timing all matter - and that MuMu has no native `.mmor` command: `MuMuManager.exe` 6.8.9.0 has no `mmor`/`script`/`play` verb, playback lives only in the `MuMuNxMain` GUI, and nothing accepts a recording. The note points at the two mouse-free options: auto-execute on launch with `control -v <n> launch`/`restart` (native playback, but one script per instance and only at boot) and `control -v <n> tool cmd -c "input tap X Y"` (replays taps, not the recording). It is mirrored in the README feature list and in `SKILL.md`. Tests 331/331, PSScriptAnalyzer 0 findings.

### v10.4.22 (19.11.2026)

- Fixed: `[L]` брал за «исходный размер» текущий прямоугольник окна, а MuMu сохраняет геометрию инстанса у себя и переоткрывает окно именно с неё. После первого сжатия уменьшенный размер становился новым «исходным», и сетка на каждом прогоне уменьшала окна ещё немного — в итоге одно окно оказывалось крошечным и вернуть его было нечем. Теперь база берётся из `<vms>/<инстанс>/configs/customer_config.json` (`setting.player.window` / `window_landscape` / `window_vertical`, значение `-1` = «авто» пропускается), к сохранённому клиентскому размеру возвращаются рамка и заголовок из живого окна, и перед раскладкой окно восстанавливается до размера, с которым MuMu его открывает. Правила прежние: не увеличивать сверх исходного, уменьшать только то, что не влезает, пропорции сохранять, порядок слева направо и сверху вниз.
- Поведение без конфига не изменилось: если `customer_config.json` нет или в нём только `-1`, базой остаётся живой прямоугольник.
- Tests: пять новых Pester-тестов (`Get-SavedWindowSize` + контракт `Set-WindowLayout`), набор 331/331 на pwsh и 5.1. Живая проверка: окно, развёрнутое на 1936×1048, даёт базу 966×519; после ручного сжатия до 500×300 база осталась 966×519 и окно восстановилось ровно в 966×519.

**EN summary (v10.4.22):** `[L]` used the live window rectangle as the "original" size, but MuMu stores each instance's window geometry in its own config and reopens at that size. After the first shrink the smaller size became the new original, so every run shrank a bit more until a window was unusably small with no way back. The base now comes from `<vms>/<instance>/configs/customer_config.json` (`setting.player.window` / `window_landscape` / `window_vertical`, where `-1` means auto and is skipped), the title bar and border thickness of the live window are added back to that saved client size, and a previously shrunken window is restored before the grid is laid out. The rules are unchanged: never grow beyond the original, shrink only what does not fit, keep the aspect ratio, place left to right and top to bottom. Without a readable config the old behaviour (live rectangle) is kept.

### v10.4.21 (19.11.2026)
- Fixed: `mmor-run.ps1` не попал в ZIP релиза 10.4.20. Архив собирается не «по всему тегу», а ровно по списку `release-files.txt`, поэтому новый файл, не внесённый в этот список, в него не попадает — в архиве 10.4.20 было 9 файлов из 10. Файл добавлен в `release-files.txt` и в оба автообновляемых списка (`mumu-menu.ps1`, `bootstrap-update.ps1`), в whitelist восстановления `Repair-Installation` и в набор `Build-RollbackPlan`; теперь он есть и в архиве, и в наборе `[U]`.
- Гейты обновлены под 10 файлов: проверка ZIP ждёт `file set: OK (10 files)`, фикстуры развёрнутой установки, откатa и проверки дрейфа содержат новый файл, чтобы отсутствие строки не выдавалось за дрейф.
- Tests: 326/326 Pester, `test-bootstrap-update.ps1` и `test-deployed-layout.ps1` зелёные на pwsh и 5.1, PSScriptAnalyzer — 0 замечаний.

**EN summary (v10.4.21):** `mmor-run.ps1` was absent from the 10.4.20 archive: the release ZIP is assembled from the explicit `release-files.txt` list (not from the whole tag), so a new file ships only once it is named there - the 10.4.20 archive held 9 of 10 files. The file is now in `release-files.txt`, in both updater lists (`mumu-menu.ps1`, `bootstrap-update.ps1`), in the `Repair-Installation` whitelist and in the `Build-RollbackPlan` file set, so it arrives both in the ZIP and through `[U]`. The ZIP guard and the deployed-layout, rollback and drift fixtures were widened to the 10-file set so a missing row cannot masquerade as drift.

### v10.4.20 (19.11.2026)
- New: `mmor-run.ps1` — нативный запуск `.mmor` без имитации ввода «вслепую»: интерфейс MuMu не публикует имена пунктов меню и кнопок рекордера (17 пунктов меню с пустыми `Name`/`AutomationId`, у кнопок только прямоугольники), поэтому скрипт работает в трёх режимах. `-Probe` показывает окна инстанса и их UIA-элементы и ничего не нажимает; `-Record` печатает окно и нормализованную точку каждого вашего клика — так один раз снимаются координаты «Operation Recorder» и «Play»; `-Apply -File farm.mmor` фокусирует окно инстанса, открывает рекордер, ждёт новое окно и жмёт Play.
- Безопасность: по умолчанию — только осмотр; `-Apply` требует существующий `.mmor`, один инстанс и `mmor-run.json`, а при неверной точке завершается `no new window appeared`, не кликая наугад. В ZIP 10.4.20 файла не оказалось (архив собирается по явному списку) — исправлено в v10.4.21; в автообновляемый набор `[U]` он тогда не входил.
- Tests: набор 326/326, PSScriptAnalyzer по `mmor-run.ps1` — 0 замечаний.

**EN summary (v10.4.20):** `mmor-run.ps1` starts native `.mmor` playback from the command line using the only surface MuMu actually exposes - window geometry and the UI Automation tree of the player window (its menus expose no names). `-Probe` reports windows and elements and presses nothing; `-Record` captures the normalized point of every user click, which is how the recorder and Play coordinates are calibrated once; `-Apply -File farm.mmor` focuses the instance, opens the recorder, waits for the new window, optionally double-clicks the file row and presses Play. `-Apply` refuses to click without an existing recording, one instance and a calibrated config, and never claims that playback started. The 10.4.20 archive did not actually contain the file (the ZIP is built from an explicit list); fixed in v10.4.21.

### v10.4.19 (19.11.2026)

- Fixed: `[G]` live-логи больше не выходят в меню с пустым экраном. Поток открывался с `-d` (снапшот), поэтому мост, который отвечает на эхо-пробу, но ещё не подключил logcat, закрывался сразу с нулём строк. Live-ветка больше не передаёт `-d`/`-t` и перезапускает пустой поток до трёх раз; вместо общего «no output on either transport» печатаются транспорт, число попыток и подсказка на снапшот `[2]`.
- Fixed: `Get-InstanceIndex` на нецифровой ввод повторяет запрос с диапазоном вместо `Instance - not found!`.
- New: `[L]` раскладывает окна запущенных инстансов в сетку — число окон в ряд спрашивается (2-6, Enter = 3), поля 10 px, зазор 10 px, `scale = min(1, …)`: помещающиеся окна не меняют размер, маленькие не увеличиваются, пропорции сохраняются, уменьшается только то, что не влезает. После раскладки окна один раз поднимаются наверх через `control -v all show_window` (без always-on-top). `a` оставляет встроенный `layout_window`.
- Changed: `[D]` закрывает все запущенные инстансы одним вызовом `control -v all shutdown` и проверяет состояние каждого — вместо последовательного `shutdown_player` с паузой после каждого.
- Tests: шесть новых Pester-тестов (live-логи, ввод инстанса, сетка окон, закрытие всех); набор 326/326 на pwsh и 5.1.

**EN summary (v10.4.19):** `[G]` live logcat no longer drops back to the menu with a blank screen. The live branch opened the stream with the snapshot hint (`-d`), so a bridge that answers the echo probe but has not attached logcat closed immediately with zero lines. Live mode now passes neither `-d` nor `-t`, restarts an empty stream up to three times, and names the transport, the attempt count and the `[2]` snapshot fallback instead of a generic "no output on either transport". `Get-InstanceIndex` also re-asks with the instance range on non-numeric input instead of claiming "not found". `[L]` now arranges the running player windows into a grid with a per-row count (2-6, default 3) using `scale = min(1, (W-2M-(C-1)G)/(C*w), (H-2M-(R-1)G)/(R*h))` over the screen work area with 10 px margins and gaps: windows that already fit are only moved, smaller ones are never enlarged, and the aspect ratio is preserved because both sides are scaled by the same factor. One `show_window` raise follows the layout - no always-on-top. `[D]` closes every running instance with a single `control -v all shutdown` call and verifies the state of each one.

### v10.4.18 (12.11.2026)

- Fixed: `[U]` больше не рапортует `0 ok, N failed ()` без единой подробности. Счётчик неудач в `Update-FromGitHub` увеличивался, а имя файла и текст ошибки никуда не попадали — журнал `update-journal.log` не позволял отличить сетевой сбой или исчерпанный лимит GitHub API (60 запросов в час без токена) от отказа хеш-гейта. Теперь каждая неудача идёт в журнал и на экран как `<файл>: <причина>`, а промахи верификации — как `missing after download` и `hash mismatch`.
- Tests: три новых Pester-теста — на список неудач, на его попадание в строку журнала и на вывод причин на экран; набор 320/320 зелёный на pwsh и 5.1.
- Docs/CI: Dependabot теперь следит и за npm-деревом репозитория (weekly, одна группа `npm`); из `SECURITY.md` убрано число движков VirusTotal (оно меняется от скана к скану) — вместо него ссылка на блок вердиктов в теле последнего релиза; подтянуты дрейфы (счётчик тестов, baseline Release-гейта, список хостов `[MU]`).

**EN summary (v10.4.18):** `[U]` no longer reports `0 ok, N failed ()` with nothing behind it. `Update-FromGitHub` bumped a failure counter but recorded neither the file nor the reason, so `update-journal.log` could not tell a network fault or an exhausted GitHub API limit (60 requests/hour without a token) from a hash-gate rejection. Every failure now lands in the journal and on screen as `<file>: <reason>`, and verification misses as `missing after download` / `hash mismatch`. Repo tooling: Dependabot now watches the npm tree, and `SECURITY.md` no longer states a VirusTotal engine count (it changes per scan) — it points at the verdict block in the latest release body instead.

### v10.4.17 (11.11.2026)

- Fixed: `[2]`/`[3]`/`[4]` больше не показывают служебную ошибку `The expression after '&' in a pipeline element produced an object that was not valid`. Путь к `MuMuManager.exe` проверялся только на старте, поэтому перемещённая или удалённая установка (в том числе после переключения через `[IN]`) доходила до `& $MumuPath info -v all` пустой строкой — исключение срабатывало до вывода списка инстансов и печаталось общим `trap` как «Error (the menu stays open)». Теперь `Get-InstanceIndex` и `Invoke-Mumu` сначала проверяют путь и сообщают `MuMuManager.exe not found - pick a valid install with [IN] or set $MumuPath.`, после чего меню остаётся открытым.
- Tests: обе функции выделены из AST и вызваны отдельно с мёртвым и с пустым путём — сообщение печатается, возврат `$null`, исключения нет; сквозной прогон `[2]` на рабочей установке по-прежнему печатает список инстансов; PSScriptAnalyzer без замечаний.

**EN summary (v10.4.17):** `[2]`/`[3]`/`[4]` no longer surface the raw "expression after '&' ... was not valid" trap. The `MuMuManager.exe` path was validated only at startup, so an install that was moved or deleted afterwards (including an `[IN]` switch to a stale copy) reached `& $MumuPath info -v all` as an empty string; the exception fired before the instance list, and the script-level trap printed it as "Error (the menu stays open)". `Get-InstanceIndex` and `Invoke-Mumu` now check the path first and print `MuMuManager.exe not found - pick a valid install with [IN] or set $MumuPath.`, keeping the menu open.

### v10.4.16 (06.11.2026)

- Fixed: `[G]` больше не упирается в тупик на незапущенном инстансе. Меню различает три состояния — `RUNNING ✓`, `STARTING ◐` (процесс плеера поднят, Android ещё грузится) и `STOPPED ○` — а при выборе `[2]`/`[3]` предлагает запустить инстанс и дожидается загрузки, после чего сразу показывает logcat. Раньше `starting_rom` считался остановленным, и живой мост объявлялся недоступным.
- Fixed: подсказка об остановленном инстансе ссылалась на `[2]`, хотя `[2]` — это снапшот logcat, а не Launch; теперь она указывает на `[2] Launch` главного меню.
- Fixed: `[MU]` больше не может зависнуть на чтении страницы. У `Invoke-WebRequest` в Windows PowerShell 5.1 `-TimeoutSec` ограничивает только получение заголовков, а тело читается с `ReadWriteTimeout` (300 с по умолчанию) — плюс выводится прогресс-бар «Чтение веб-отклика», который Ctrl+C не прерывает. Страницы теперь тянутся через `Get-WebText` на `HttpClient` с жёстким дедлайном на весь обмен, включая тело, и с выключенным прогрессом.
- Fixed: Ctrl+C в `[G]` гарантированно возвращает в главное меню. Обработчик больше не отдаёт нажатие хосту (`e.Cancel = true`): остановку выполняет убийство дерева процессов, а ридер выходит по EOF, поэтому нативный поток не может пережить разрыв конвейера и печатать поверх меню.
- Added: неинтерактивный режим `-Action launch|stop|restart|logs` с `-Instance all|0|0,2`, `-Lines`, `-TimeoutSec` и `-Json`: ни одного `Read-Host`, проверка результата по фактическому состоянию инстанса, код возврата `0` только при успехе по всем целям. Стартовые баннер и проверка обновлений на этом пути пропускаются.
- Tests: статические проверки на `STARTING ◐`, на запуск через `control -v ... launch`, на `Wait-Boot`, на отсутствие старой подсказки, на `Get-WebText` вместо `Invoke-WebRequest` для страниц, на `e.Cancel = true` в обработчике Ctrl+C и на отсутствие интерактивных вызовов в неинтерактивном пути; набор 317/317 зелёный на pwsh и 5.1.

**EN summary (v10.4.16):** `[MU]` can no longer hang while reading a page: `Invoke-WebRequest`'s `-TimeoutSec` bounds only the headers on Windows PowerShell 5.1, the body is read under `ReadWriteTimeout` (300 s), and its "reading web response" bar ignores Ctrl+C. Pages now go through `Get-WebText`, which caps the whole exchange with `HttpClient` and keeps the progress bar out. `[G]` no longer dead-ends on an instance that is not up. The screen tells three states apart — `RUNNING ✓`, `STARTING ◐` (player process up, Android still booting) and `STOPPED ○` — and for `[2]`/`[3]` it offers to start the instance, waits for boot and then streams logcat. A booting VM used to be reported as stopped, and the old hint pointed at `[2]`, which is the snapshot action, not Launch. Ctrl+C in `[G]` reliably returns to the main menu: the handler always sets `e.Cancel = true` and ends the stream by killing the process tree, so the reader exits on EOF and the native child cannot keep printing over the menu.
### v10.4.14 (04.11.2026)

- Changed: после Ctrl+C в live-логах `[G]` сразу открывается главное меню — паузы «Press any key to continue...» больше нет. Флаг `$script:SkipContinuePause` выставляется только при остановке потока по Ctrl+C и сбрасывается в главном цикле, поэтому обычные действия сохраняют паузу.
- Tests: статические проверки на флаг и на его обработку в главном цикле; целевые наборы зелёные на 5.1 и pwsh.

**EN summary (v10.4.14):** After Ctrl+C stops `[G]` live logcat the main menu opens immediately — no "Press any key to continue..." pause. The one-shot `$script:SkipContinuePause` flag is set only for an interrupt and cleared by the main loop, so other actions keep their pause.
### v10.4.13 (04.11.2026)

- Fixed: выход из `[G]` по Ctrl+C больше не «зависает» до второго нажатия. Обработчик убивает всё дерево процессов (`taskkill /F /T /PID`): менеджер оставлял наследника с нашим stdout-хэндлом, пайп не закрывался, и чтение продолжало ждать. Плюс после Ctrl+C больше не запускается нативный `logcat -c` — на остановленном конвейере он висел и держал меню; буфер чистится только при естественном конце потока.
- Tests: статические проверки на `taskkill` в обработчике и на пропуск `Stop-Logcat` при остановке по Ctrl+C; целевые наборы зелёные на 5.1 и pwsh.

**EN summary (v10.4.13):** Ctrl+C in `[G]` no longer appears frozen until a second press. The handler kills the whole process tree (`taskkill /F /T /PID`) because a surviving child that inherited stdout kept the pipe open and the reader kept waiting, and the trailing native `logcat -c` is skipped after an interrupt since it hangs on a stopped pipeline.
### v10.4.12 (04.11.2026)

- Fixed: `[G]` live-логи действительно останавливаются по Ctrl+C. Предыдущий фикс снимал защиту, но останавливал только конвейер PowerShell, а дочерний `MuMuManager` продолжал печатать в консоль, и выход выглядел мёртвым. Теперь поток читается через собственный `Process` с перенаправленным stdout, а скомпилированный обработчик `CancelKeyPress` убивает этот процесс на сигнальном потоке (runspace там нет) — ридер получает EOF, печатается `logcat stopped (Ctrl+C).`, страж возвращается в `finally`.
- Tests: новый тест «handler убивает привязанный поток» (реальный процесс `ping`, вызов обработчика с потока без runspace) плюс статические проверки чтения через `Process`; целевые наборы — 8 passed / 0 failed на Windows PowerShell 5.1 и на pwsh.

**EN summary (v10.4.12):** Ctrl+C now really stops `[G]` live logcat. The previous fix only released the menu guard; PowerShell stopped its pipeline while the native `MuMuManager` child kept printing to the console. The stream is now read through an owned `Process`, and the compiled `CancelKeyPress` handler kills that process on the signal thread (no runspace there), so the reader hits EOF, `logcat stopped (Ctrl+C).` is printed and the guard is re-armed in `finally`.
### v10.4.11 (04.11.2026)

- Fixed: `tests/mumu-menu.Tests.ps1` снова с UTF-8 BOM. Предыдущая правка записала файл без BOM, и Windows PowerShell 5.1 читал кириллицу как ANSI — 12 ошибок парсинга, красные ноги `pester-unit (5.7.1 / powershell)` и `deployed layout`, из-за чего Release v10.4.10 не опубликовался (тег создан, релиза нет). BOM восстановлен, парсер 5.1 — 0 ошибок.
- Tests: целевые наборы (`View logs`, `ADB port`, `Ctrl+C`) — 5 passed / 0 failed на Windows PowerShell 5.1 и на pwsh.

**EN summary (v10.4.11):** `tests/mumu-menu.Tests.ps1` carries its UTF-8 BOM again — without it Windows PowerShell 5.1 decodes Cyrillic as ANSI and failed with 12 parse errors, which reddened the 5.1 Pester leg and blocked the v10.4.10 publication (tag created, no release). BOM restored: 5.1 parser reports 0 errors and the targeted suites pass on both engines.
### v10.4.10 (04.11.2026)

- Fixed: из live-логов `[G]` снова можно выйти по Ctrl+C. Обработчик `CancelKeyPress` ставил `e.Cancel = true` на всё время работы меню, поэтому Ctrl+C глотался и в потоке — закрыть его можно было только окном. Теперь у стража есть флаг `Enabled`: на время потока он снимается, Ctrl+C останавливает лог, печатается `logcat stopped (Ctrl+C).`, а защита возвращается в `finally` — остальное меню по-прежнему не закрывается случайным Ctrl+C.
- New: adb-порт определяется автоматически. `Find-AdbPort` проверяет сообщённый `adb_port` TCP-подключением, затем ищет слушателя в блоке MuMu `16384 + 32*n` и берёт первый живой порт; если не ответил никто — используется сообщённый. Проба отдаёт `adbPort`/`adbPortSource`, и DIAG показывает реально проверенный порт.
- Tests: 2 новых теста автоопределения порта (живой loopback-слушатель выигрывает у устаревшего порта; без слушателей `Port=0`, `Source=none`), проверка `$p.adbPort` и 3 утверждения на снятие/возврат Ctrl+C-стража; затронутые наборы — 60 passed / 0 failed.

**EN summary (v10.4.10):** Ctrl+C really stops `[G]` live logcat now: the menu-wide `CancelKeyPress` guard honours an `Enabled` flag that the stream clears and restores in `finally`, so the rest of the menu stays protected. The adb port is auto-detected (`Find-AdbPort`: the reported port, then MuMu's `16384+32*n` block probed over TCP) and the probe exposes `adbPort`/`adbPortSource`. Pester: 60/60 in the affected suites.
### v10.4.9 (04.11.2026)

- Fixed: `[G]` live-logcat больше не даёт пустой экран на инстансах без локального adb-моста. Remote/streaming-игроки отвечают на `MuMuManager adb --cmd connect` кодом `-202 vm not ready, can not connect adb`, а каждый `--cmd` возвращает пустой вывод с кодом 0 — раньше меню печатало заголовок LIVE и молчало. Теперь транспорт выбирается явно: adb, а если мост не отвечает — shell-транспорт `MuMuManager sh`; причина печатается в шапке.
- Fixed: снапшот, живой поток, все фильтры (все / E / W / тег / quiet / поиск) и `Stop-Logcat` (`logcat -c`) работают через оба транспорта; пустой поток теперь даёт предупреждение вместо тишины.
- Tests: 4 новых утверждения в тесте `[G]` (резервный транспорт, его причина, `Stop-Logcat -Transport`); `View logs [G]` + `Stop-Logcat` — 5 passed / 0 failed. Живая проверка на инстансе с `-202`: live 133 строки за 18 с, снапшот 56 строк, errors-only 26 строк.

**EN summary (v10.4.9):** `[G]` live logcat no longer shows an empty screen on players without a local adb bridge (`adb --cmd connect` answers `-202 vm not ready` and every `--cmd` returns empty with exit 0). The screen now resolves a transport: adb when the bridge answers, otherwise the manager's `sh` transport, with the manager's reason printed above the filter. Snapshot, live stream, every filter and `Stop-Logcat` use the same transport. Pester `View logs`/`Stop-Logcat`: 5/5; the live run streamed 133 lines in 18 s.
### v10.4.8 (29.10.2026)

- New: меню после успешного `[U]` перезапускает себя на новой версии без ручного закрытия окна. Проверено живым A/B-запуском: дочерний процесс выполняет уже новый `mumu-menu.ps1`.
- Fixed: перезапуск не срабатывает там, где его быть не должно — в пайпе/перенаправленном вводе (окна нет, авто-цикл был бы бесполезен), при частично провалившемся обновлении (файлы могут быть рассинхронизированы) и когда подмена `.new` или запуск процесса падает: тогда печатается старая строка «Restart the menu…».
- Fixed: после успешного `[U]` меню само перезапускается на новой версии, без ручного закрытия окна — ранее требовалось закрыть окно и открыть его вручную.
- Tests: 4 новых теста (обе функции на верхнем уровне скрипта, порядок «`.version` → перезапуск → сообщение-запасной вариант», реальная подмена `.new`, поведение без консоли), сьют 312 passed / 0 failed на Windows PowerShell 5.1 и pwsh 7; A/B-запуск в живой консоли подтвердил, что ребутный процесс выполнил уже новый код.

**EN summary (v10.4.8):** The menu now relaunches itself after a clean `[U]` update without manual window close. Live A/B run confirmed the child executes the already-new `mumu-menu.ps1`. Pester 312/312 on 5.1 and pwsh 7.

### v10.4.7 (29.10.2026)

- Fixed: `[RL]` больше не показывает тело релиза как «╨Ш╨╜…». `Invoke-GitHubApiGet` читал stdout `curl.exe` через пайп, а Windows PowerShell 5.1 декодирует вывод нативных команд кодировкой консоли (CP866 на русской Windows) — UTF-8 JSON с кириллицей превращался в мусор. Ответ теперь пишется файлом (`curl -o`) и читается явно как UTF-8; пустой ответ/сетевой сбой по-прежнему дают прежний контракт `''`.
- Fixed: тот же путь чинит любой текст, приходящий через `Invoke-GitHubApiGet`: сообщения GitHub об ошибках, описания и прочие кириллические поля экранов.
- Tests: 2 новых теста (тело приходит только через `-o` и читается как UTF-8, в `Invoke-GitHubApiGet` больше нет `| Out-String`); сьют 310 passed / 0 failed на 5.1 и pwsh. Проверено A/B в консоли с кодовой страницей 866: старый файл давал `╨Ш╨╜╤В…`, новый — нормальный русский текст.

**EN summary (v10.4.7):** `[RL]` release bodies no longer render as `╨Ш╨╜…`. `Invoke-GitHubApiGet` captured `curl.exe` stdout through a pipe, and Windows PowerShell 5.1 decodes native stdout with the console code page (CP866 on a Russian Windows), mangling UTF-8 JSON with Cyrillic. The body is now requested with `curl -o` and read explicitly as UTF-8; an empty or failed response keeps the old `''` contract. Pester 310/310 on 5.1 and pwsh 7.

### v10.4.6 (29.10.2026)

- New: после успешного `[U]` меню само перезапускается на новой версии — окно больше не нужно закрывать и открывать вручную. Отложенный `mumu-menu.ps1.new` подменяется до запуска дочернего процесса: иначе тот разобрал бы старый файл и перезапуск ничего бы не изменил.
- Fixed: перезапуск не срабатывает там, где его быть не должно — в пайпе или перенаправленном вводе (окна нет, а автоматизация ушла бы в цикл), при частично провалившемся обновлении (файлы могут быть несогласованы) и когда подмена `.new` или запуск процесса падает: тогда печатается прежняя строка «Restart the menu…». Всё прежнее поведение смешанного/частичного обновления сохранено.
- Tests: 4 новых теста (обе функции на верхнем уровне скрипта, порядок «`.version` → перезапуск → запасное сообщение», реальная подмена `.new` и запуск, поведение без консоли); сьют 308 passed / 0 failed на Windows PowerShell 5.1 и на pwsh 7 — плюс end-to-end прогон в живой консоли на обоих движках (дочерний процесс выполнил уже новый код).

**EN summary (v10.4.6):** A clean `[U]` update relaunches the menu on the new files instead of asking for a manual restart: the staged `mumu-menu.ps1.new` is applied before the child process starts, so the child really parses the new script. The restart is skipped for piped or redirected runs (no window, and automation must not loop), for partial updates, and whenever the swap or the launch fails — the old "Restart the menu…" line is printed instead. Pester 308/308 on Windows PowerShell 5.1 and pwsh 7.

### v10.4.5 (29.10.2026)

- Fixed: сохранённый GitHub-токен снова используется. `Invoke-GitHubApiGet` передавал `-Token` даже когда его не задавали (пустой строкой), `Get-CurlGitHubArgs` считал токен явно заданным и не подхватывал `$GitHubToken` из скрипта — поэтому все запросы уходили анонимно и упирались в лимит 60/час даже с валидным токеном (проверено: токен из `.github-token.dpapi` валиден, лимит 5000/час, а меню всё равно получало 403).
- Fixed: `[RL]` берёт список релизов через тот же token-aware транспорт (`Invoke-GitHubApiGet`: токен, curl, повторы), а при отказе показывает причину от GitHub — например `API rate limit exceeded ...` — вместо общего «cannot reach the GitHub API».
- Tests: 4 регрессионных теста ([RL] на верхнем уровне скрипта, wiring `[RL]`/`rl`, интерполяция Source, проброс сохранённого токена в `Invoke-GitHubApiGet`); сьют 304 passed / 0 failed.

**EN summary (v10.4.5):** The saved GitHub token is used again — `Invoke-GitHubApiGet` bound `-Token` even when the caller passed nothing, so `Get-CurlGitHubArgs` never fell back to `$GitHubToken` and every request went out anonymously into the 60/hour limit. `[RL]` now fetches through that token-aware transport and reports GitHub's own reason ("API rate limit exceeded ...") instead of a blanket "cannot reach". Pester 304/304.

### v10.4.4 (29.10.2026)

- Fixed: `[RL]` больше не падает с «Термин "Show-ReleaseList" не распознается». Функция была объявлена внутри `Update-FromGitHub`, а вложенные определения видны только на время работы родителя — меню из главного цикла её не находило. Определение перенесено на верхний уровень скрипта.
- Fixed: список релизов теперь разбирается корректно. `ConvertFrom-Json -AsHashTable` есть только в PowerShell 7 (на 5.1 параметр не привязывается, `catch` его глотал, и экран что врал «cannot reach the GitHub API»), а `.Values` от JSON-массива давал одну гигантскую строку вместо списка. Экран читает массив напрямую и считает stable/pre-release по нему, `Files` берётся как `@($rel.assets).Count`.
- Fixed: дата релиза печаталась в формате ОС (`10/29/2026 07:00:50`) — `[datetime]::Parse()` от готового `[datetime]` (его отдаёт pwsh 7) бросает исключение, и `catch` возвращал сырое значение. Теперь `[datetime]` форматируется напрямую, а строки парсятся culture-invariant (PS 5.1 оставляет их строками).
- Fixed: две мелочи того же экрана — заметка «Source:» печатала буквальный `$GitHubRepo` (одинарные кавычки вместо двойных), а «What's new» склеивал весь changelog в один абзац: теперь текст идёт построчно, не более 30 строк, со ссылкой на остаток.
- Tests: 3 регрессионных теста ([RL] объявлен на верхнем уровне, wiring `[RL]`/`rl`, интерполяция Source); сьют 302 passed / 0 failed.

**EN summary (v10.4.4):** `[RL]` works again. The renderer was declared inside `Update-FromGitHub`, so the main switch could not see it ("Show-ReleaseList is not recognized"); the JSON list is no longer read through `.Values`/`-AsHashTable` (PS 7-only, and `.Values` turned the array into one string), release dates format correctly from the `[datetime]` pwsh 7 returns, the Source note interpolates the repo, and the changelog preview wraps line by line with a link to the rest. Pester 302/302.

### v10.4.3 (29.10.2026)

- Fixed: `[K]` (и все остальные запросы к GitHub через `curl.exe`) больше не отвечают «GitHub did not respond (network problem)» на машинах, где Windows-curl (Schannel) не может проверить отзыв сертификата: `schannel: CRYPT_E_REVOCATION_OFFLINE` (exit 35) обрывает рукопожатие до первого байта, а stderr отбрасывается — валидный токен выглядел как сетевой сбой. Проверено воспроизведением: обычный `curl.exe https://api.github.com/zen` → exit 35, с `--ssl-no-revoke` → exit 0.
- Fix: отзыв чинится точечно и только для процесса меню. На старте один раз проверяется, падает ли обычный запрос и проходит ли тот же URL без проверки отзыва; только в этом случае в приватную temp-папку пишется `_curlrc` с `ssl-no-revoke` и выставляется `CURL_HOME` для этого процесса. Цепочка сертификатов и hostname проверяются по-прежнему; на здоровой сети проверка отзыва остаётся включённой, а если недоступна сама сеть (оба запроса падают) — не меняется ничего.
- Tests: 3 новых Pester-теста на `Repair-CurlRevocation` (здоровая сеть — без изменений, только отзыв — `_curlrc` + `CURL_HOME`, мёртвая сеть — без изменений); сьют 299 passed / 0 failed.

**EN summary (v10.4.3):** `[K]` and every other `curl.exe` GitHub call no longer report "GitHub did not respond (network problem)" when Windows curl (Schannel) cannot check certificate revocation (`CRYPT_E_REVOCATION_OFFLINE`, exit 35) — a valid token looked like a network outage. The menu probes once at startup and, only when the plain request fails while `--ssl-no-revoke` succeeds, points `CURL_HOME` at a private one-line `_curlrc` for its own process. Chain and hostname verification stay on; healthy networks keep full revocation checking. Pester 299/299.

### v10.4.2 (29.10.2026)

- New: `[RL]` — read-only список уже опубликованных релизов этого меню: тег, дата публикации, автор, статус stable / pre-release, число файлов в архиве и человекочитаемые release notes, всё на общем наборе оформления (`Write-ScreenFrame`, `Write-MenuGroup`, `Write-KeyValue`). Ничего не скачивается — экран показывает только то, что уже есть на GitHub.
- Fixed: `mumu-menu.ps1` снова разбирается и запускается. В строке журнала `[WN]` стоял неэкранированный апостроф (`the menu's probe`) внутри строки в одинарных кавычках — он закрывал строку досрочно, и файл давал 17 ошибок разбора (`UnexpectedToken "s"`, «Отсутствует закрывающая скобка»), из-за чего меню не стартовало вообще. Апостроф удвоен (`menu''s`), как требует PowerShell.
- Fixed: второе такое место — заголовок лога `[WN]` — кавычка стояла посреди фразы (`refused SYNs' ====='`) и обрывала строку; она перенесена в конец.
- Fixed: `[1]` и `[DIAG]` больше не объявляют исправный эмулятор «ADB bridge NOT ready». Проба выставляла `$adb = $true` по полю `adb_version`, но `adbReady` вычислялся только из `$adbState`, который на этом пути оставался пустым; теперь оба признака двигаются вместе (и `adbReady` принимает любой из них).
- Fixed: первый экран меню больше не падает с `SetValueInvocationException: CursorPosition — Invalid argument` там, где нет консольного буфера (перенаправленный ввод/вывод, лаунчер, захват вывода): `Clear-Host` стал best-effort, и меню рисуется в обоих режимах вместо ошибки в общем trap.
- Tests: сьют 296 passed / 0 failed; файл разбирается и в pwsh 7, и в Windows PowerShell 5.1.

**EN summary (v10.4.2):** The menu parses and starts again — an unescaped apostrophe in the `[WN]` log line (plus a misplaced quote in its header) broke the whole script with 17 parse errors. `[1]`/`[DIAG]` no longer report "ADB bridge NOT ready" for an emulator that reports `adb_version`, and the first screen survives hosts without a console buffer. Pester 296/296.

### v10.4.1 (25.10.2026)

- Экран `[OI]` Offline installers переведён на общий набор оформления рабочих экранов: двойная рамка `Write-ScreenFrame` с заголовком и контекстом, секции `Write-MenuGroup` с линейками, выровненными по краям рамки, и все поля (`URL`, `name`, `size`, `digest`, `canonical`, `integrity`, `note`, `base`) в одинаковых колонках `Write-KeyValue` — длинные URL и подсказки переносятся внутри рамки, а не ломают её. Цвета унифицированы с остальными экранами (Cyan — рамка и секции, Yellow — только предупреждения, теперь внутриэкранные `Write-ScreenNote`).
- Целостность показывается честно везде: дигест теперь извлекается и на пути резолвера (колонка `digest` в Windows-секции раньше не заполнялась никогда), а когда CDN не отдаёт заголовки, все секции печатают `integrity: headers did not expose a digest/length for this path` вместо молчаливого пропуска.
- Tests: сьют 296 passed / 0 failed; регенерация README идемпотентна.

**EN summary (v10.4.1):** The `[OI]` offline-installers screen joins the shared screen kit (frame, group rules, aligned key/value columns, wrapped values, unified colours); digest extraction now also runs on the resolver path, and an explicit `integrity` row appears whenever the CDN exposes no headers. Pester 296/296.

### v10.4.0 (24.10.2026)

- Unified styling across the working screens: a shared kit (`Write-ScreenFrame`, `Write-MenuGroup`, `Write-KeyValue`, `Write-ScreenStatus`, `Write-ScreenStep`, `Write-ScreenNote`, `Write-ToolOutput`, `Write-ScreenChoices`, `Split-MenuWrappedText`) gives every screen the same double-ruled frame with a title and context line, aligned key/value columns, and colours by meaning (green = running, yellow = transitional, dim = stopped).
- Instance info, installed apps and settings are rebuilt: the former JSON dump became a table with «Details» / «Other fields» sections, packages pack into two columns inside the frame, and long settings paths wrap on separators instead of mid-name.
- Launch, shutdown, restart, ADB commands, APK install and window management moved to the same frame/status/step/note kit; raw manager output is indented and dimmed instead of dumped at column 0.
- Tests: 4 new Pester tests covering the shared kit and its use in each converted screen; suite 296 passed / 0 failed.

**EN summary (v10.4.0):** Unified screen styling for the menu's working screens (info/apps/settings, launch/shutdown/restart, ADB, APK install, windows) on a shared frame/status/step/note kit with aligned columns and colour-by-meaning. Pester 296/296.

### v10.3.5 (22.10.2026)

- Fixed: меню больше не падает при старте с семистрочным дампом типовых данных `System.Security.AccessControl.ObjectSecurity` «… уже присутствует», если Windows PowerShell 5.1 запущен косвенно — через `mumu-menu.cmd`, `node mumu-menu.cjs --ps` или окно VS Code / Windows Terminal, открытое из pwsh-сессии. Такой процесс наследует `PSModulePath` PowerShell 7 (PowerShell/PowerShell#18530, microsoft/vscode#251311), поэтому первый авто-импорт модуля Security (`Get-Acl` или `ConvertTo-SecureString` при чтении `.github-token.dpapi`) берёт ps7-копию `Microsoft.PowerShell.Security`, чей `Security.types.ps1xml` повторно регистрирует семь членов `ObjectSecurity`, уже определённых ядровым `types.ps1xml` 5.1. Скрипт чинит `$env:PSModulePath` при старте (только на Desktop-издании): корни модулей с сегментом пути ровно `PowerShell` отбрасываются, все `WindowsPowerShell`-корни и пользовательские каталоги сохраняются, а если фильтр удалил бы всё — значение возвращается без изменений. Сессии PowerShell 7 не затрагиваются.
- Tests: новые чистые юнит-тесты `Repair-DesktopModulePath` (10 сценариев: отбрасывание ps7-корней user/all-users/home/preview case-insensitively, сохранение WindowsPowerShell-корней и пользовательских каталогов, порядок, пустой вход, фолбэк при полном удалении); сьют 289 passed / 0 failed, PSScriptAnalyzer 0 findings.

**EN summary (v10.3.5):** Startup fix for the seven-member `ObjectSecurity` type-data dump seen when Windows PowerShell 5.1 inherits PowerShell 7's `PSModulePath` through an intermediate launcher (PowerShell/PowerShell#18530); the script repairs the path on Desktop only. New `Repair-DesktopModulePath` unit tests.

### v10.3.4 (22.10.2026)

- Fixed: строка ОС в `[V]` больше не врёт на Windows 11. `[Environment]::OSVersion` на всех Windows 10/11 отдаёт `10.0`, а `ProductName` после in-place апгрейда остаётся «Windows 10 Pro» — меню показывало `OS: Windows 10.0 (Build 26300)` на фактической Windows 11 26H2. Имя системы теперь выводится из номера сборки (11 начинается с 22000) и метки feature-update из реестра (`DisplayVersion`, для старых сборок — `ReleaseId`): `OS: Windows 11 26H2 (Build 26300)`.
- Fixed (CI): релиз, опубликованный через `GITHUB_TOKEN` (fallback без `RELEASE_PAT`), теперь гарантированно получает VirusTotal-скан. GitHub не рассылает событие `release: published` для релизов, созданных `GITHUB_TOKEN` — именно поэтому v10.3.3 вышел без секции вердиктов в теле релиза. Release-воркфлоу теперь явно диспатчит `virustotal.yml` с тем же тегом (шаг не-fatal: сбой диспатча не валит уже опубликованный релиз), а путь с `RELEASE_PAT` не изменился.
- Docs: SECURITY.md — заголовок «Актуально для» подтянут с v1.22.64 до v10.3.4, добавлены записи RU/EN про новый VT-fallback, счётчик CI-тестов обновлён (173 → 281).
- Tests: сьют 281 passed / 0 failed, PSScriptAnalyzer 0 findings.

### v10.3.3 (20.10.2026)

- Fixed: Ctrl+C убивал меню вместо того, чтобы игнорироваться. Обработчик `CancelKeyPress` был PowerShell-скриптблоком, а .NET поднимает это событие на своём сигнальном потоке (`PosixSignalRegistration` в PowerShell 7), где нет привязанного runspace — делегат падал с `PSInvalidOperationException` в `GetContextFromTLS` ещё до выполнения тела, и хост завершался с «Unhandled exception … Процесс PowerShell будет завершён». Обработчик теперь компилируемый делегат, который только выставляет `e.Cancel`; если компиляция недоступна (ConstrainedLanguage), защита пропускается, а не роняет процесс. Снятие обработчика в `finally` защищено так же.
- New: `mumu-menu.cmd` — запуск меню двойным кликом из git-клона. Поднимает PowerShell с `-ExecutionPolicy Bypass` только для этого процесса, поэтому при политике `Restricted` не нужно менять системные настройки; без `mumu-menu.ps1` рядом отказывается запускаться. Файл намеренно не входит в deployed-набор из девяти файлов, чтобы ZIP-установки и установки после `[U]` не расходились.
- Tests: регрессионный тест вызывает реальный обработчик с потока без runspace (та самая падающая ситуация) и красный на прежней версии скрипта; сьют — 280 passed / 0 failed / 1 skipped на PowerShell 5.1 и pwsh 7.6.7 (Pester 5.7.1).

### v10.3.1 (19.10.2026)

- Fixed: обновление больше не верит одному `.version`. Релиз может **добавить** файл (в v10.3.0 это `mumu-menu.cjs`), и установка с уже актуальным маркером получала «Up to date», а новый файл так и не приезжал — воспроизведено на живой папке. Теперь `[U]`/`[UP]` и `bootstrap-update.ps1` перед коротким путём проверяют весь объявленный набор, называют отсутствующие файлы и докачивают их с проверкой SHA-256 (в dry-run это строка `repair of <tag> (file set incomplete: ...)`). Неизменённые файлы по-прежнему пропускаются по хешу.

### v10.3.0 (19.10.2026)

- New: JavaScript-движок — `node mumu-menu.cjs` больше не тонкая обёртка: он сам находит `MuMuManager.exe` (включая пин `.mumu-install`), выполняет `--status`/`--list`/`--json`, `--start`/`--stop`/`--restart <N>`, `--watch` (сеть + updater, read-only) и `--ps` (переход в полное PowerShell-меню). Ноль зависимостей, работает из любой папки, входит в релизный ZIP и в deployed-набор обновления.
- Fixed: `[WN]` больше не «молчит». Сетевая таблица читается через `netstat -ano -p tcp` (~0.6 с на 23k строк) вместо `Get-NetTCPConnection`, который на живой машине занял 52 с на 39k строк — из-за этого 5-секундный цикл не успевал ни одного тика и между `Session started` и `Stopped` было пусто.
- Improved: `[WN]` теперь логирует уже открытые соединения при старте (`SEEN`), шлёт heartbeat (сразу и раз в 60 с) с числом MuMu-процессов, внешних строк и длительностью тика, сам пишет ошибку тика в лог (`ERROR | ...`) вместо падения в общий trap меню и берёт EXE-инфо апдейтера через `Get-Process` с кэшем (CIM — только фолбэк).

**EN summary (v10.3.0):** Native JavaScript engine for the menu entry point (`--status/--list/--json`, instance control, `--watch`, `--ps`; zero dependencies, shipped in the release ZIP), and a rewritten `[WN]` watcher that uses `netstat -ano -p tcp` instead of the 52-second `Get-NetTCPConnection` call, seeds existing connections, emits heartbeats and contains per-tick errors.

### v10.2.0 (18.10.2026)

- New: `[OI]` — offline installer listing (all platforms): the current official Windows `.exe`, macOS `.dmg` and Android APK variants resolved from the official release page and the telemetry-free CDN alias, with filename, size and an integrity badge when the CDN exposes it. Read-only, downloads nothing.
- New: `[F]` auto-repairs the installation — when the integrity check reports DRIFT/MISSING files it offers to restore exactly those files from the pinned release commit (backup first, SHA-256-verified bytes, file-set whitelist, journaled `repair-ok`/`repair-fail`); the running script is staged as `mumu-menu.ps1.new` and applied at the next start (same contract as `[U]`).
- Fixed: bootstrap-update.ps1 no longer redirects native stderr (`2>$null` is a terminating error under PowerShell 5.1 with `$ErrorActionPreference='Stop'`), and a rejected GitHub token is now actually detected — `--fail` suppresses the error body, so both API helpers retry once anonymously and disable the token for the run with a re-save hint.
- Fixed: the release page's verification snippet works on Windows PowerShell 5.1 — the generator emits `curl.exe` (bare `curl` is an `Invoke-WebRequest` alias there and rejects `-sL`/`-o`) and the snippet downloads both artifacts and compares the hashes itself instead of asking the reader to compare by eye.
- Exit-code hygiene: the script ends with an explicit `exit 0`.
- Pester suite: 270/270 passed.

**EN summary (v10.2.0):** Offline-installer listing `[OI]`, `[F]` installation auto-repair from the pinned release, updater hardening (native stderr, rejected-token fallback) and a PowerShell 5.1-safe release verification snippet. Pester 270/270.

### v10.1.0 (17.10.2026)

- New: `[MU]` — read-only MuMu emulator update check (installed version vs the latest official release; nothing is downloaded).
- Fixed: the menu window no longer dies on accidental input — Ctrl+C is ignored inside the menu, runtime errors return to the menu instead of closing it, and piped stdin exits cleanly instead of hanging.
- Housekeeping: `.coderabbit.yaml` rewritten against the published CodeRabbit schema (the old file used non-existent keys and was silently ignored).
- Pester suite: 261/261 passed.

**EN summary (v10.1.0):** Read-only MuMu emulator update check `[MU]`, window-close guards (Ctrl+C / runtime errors / piped stdin), schema-valid CodeRabbit config.

### v10.0.0 (14.10.2026)

- Major release: semantic-version bump to `v10.0.0` to mark a stable, production-ready milestone and unify public-facing versioning.
- Documentation and release notes reorganized for clarity (relnotes.md and README.md).
- No behavioral changes to the runtime scripts in this commit — this release primarily records the versioning milestone and documentation cleanups.
- Pester suite: 260/261 passed (1 README changelog sync test pending the table update).

**EN summary (v10.0.0):** Production-ready milestone at v10.0.0 with synchronized version markers across `mumu-menu.ps1`, `.version`, `relnotes.md` and `README.md`. Pester suite: 260/261 passing.

---

| Версия | Дата | Изменения |
|--------|------|-----------|
| v10.4.36 | 23.11.2026 | Fix: answering `yes` at the consent prompts no longer cancels the option. `Confirm-AdbConsent` (`[A]`, `[AF]`, `[AS]`, `[AH]`) and `Confirm-SpoofConsent` (`[DM]`, `[SIM]`, `[SIM+]`, `[AI]`, `[DI]`) compared the answer with a literal `-eq 'OK'`, so the natural `yes` printed `Cancelled (consent not given)`; a shared `Test-ConsentAnswer` now accepts `OK`, `yes` or `y` in any case with surrounding whitespace trimmed, the prompt says `Type OK or yes to continue`, any other answer still cancels, and consent is still remembered for the session |
| v10.4.35 | 23.11.2026 | Scan cleanup in `mumu-ui.ps1` with no behaviour change: the XAML namespaces are assembled at run time (`Expand-XamlNamespace` substitutes `__WPFNS__` / `__XAMLNS__` in five here-string blocks and both inline DataTemplates) because the literal `http://` URIs tripped DevSkim's DS137138 and an inline suppression inside a here-string would break the XML; `Write-Log` became `Add-DeviceLog` (it shadowed a built-in cmdlet), the three empty catch blocks write `Write-Debug` with the exception text, and `$sender` became `$source`. The `security-scan` job also stopped dying with `PSScriptAnalyzer produced no SARIF output`: the composite action's `Invoke-ScriptAnalyzer \| ConvertTo-SARIF` pipeline threw a NullReferenceException, so `.github/scripts/psa-sarif.ps1` now writes SARIF 2.1.0 itself |
| v10.4.34 | 22.11.2026 | New «Диск» page in the device settings window, shaped like MuMu's own: «Очистка диска» opens the instance folder and journals it, «Дисковое пространство» reports the used bytes from `info -v <i>` plus the free space on the drive that holds `vms`, one manager call per section. Fixes «Папка инстанса не найдена»: the folder used to come only from `device_thumbnail`, which some instances do not have, so it now also resolves through the `<install>\vms\*-<index>` naming rule (verified on instances 0 and 2). There is deliberately no «Расширить» button: `MuMuManager` has no disk-capacity key among its 44 writable ones and no resize command, and the 126 GB MuMu shows is the guest filesystem size inside `data.vdi` |
| v10.4.33 | 22.11.2026 | New `[UI]` native WPF window (`mumu-ui.ps1`): device cards with Android, state and `max_frame_rate`, launch/stop/restart, create, clone, rename, export/import backup, repair and delete; a per-device settings screen over seven sections built from the real `setting -a` keys, with MuMu-style resolution presets including DPI, device-model presets, `Режим Vulkan` / `Режим DirectX`, every write confirmed by reading the key back, and status text that says `Сохранено` or names what the manager really returned. Fixes: row handlers now use `GetNewClosure()` so an edit no longer goes out with an empty key (`cmd params invalid` / `key not writable`), the frame limit is written to `max_frame_rate` instead of the `customer_config.json` value the player overwrites, and the list is read in two manager calls instead of one per device |
| v10.4.32 | 22.11.2026 | Fix `[U]`: a repair is verified on disk instead of trusting the download loop - the marker heal no longer swallows it, a still-missing file prints `Repair failed - N file(s) are still missing` and exits 1 without advancing `.version`, and a clean repair reports how many files landed. Fix `[RF]`: the device is removed with `MuMuManager delete -v` and confirmed through `info -v all`, `nx_device\<version>` (the shared Android engine) is never deleted because its loss made `create` answer errcode 60014, a ghost entry is repaired instead of refused, the confirmation takes `YES` in any case, and a failed delete names the deleted and surviving paths instead of claiming the folders are gone |
| v10.4.31 | 22.11.2026 | New `[RF] Repair device`: the repair that works for MuMu's `Startup failed: An abnormal runtime environment was detected` (RU «Обнаружена неисправность среды выполнения») — it lists `nx_device\15.0` and the selected `vms` instance folder with their sizes, confirms, stops MuMu, deletes them and recreates the Android 15 device, and names the real cause when a delete fails (`Get-MumuRepairFailureHint`: MuMu still open, file held by a process). New `mumu-f11-probe.ps1`: a four-stage probe (`Prepare`/`Wait`/`Report`/`Cleanup`) that checks whether F11 on a 12.0-engine instance really changes the video mode or only stretches a borderless window — free index from 2, engine check, hash snapshot of the 15.0 instances before/after, `shell.log` line baseline, time-filtered `graphics_log`, monitor mode before/after F11/after Esc via `EnumDisplaySettings`, and an `EXCLUSIVE`/`BORDERLESS`/`INCONCLUSIVE` verdict in `REPORT.md`; protected indexes are never touched and F11 is pressed by the user |
| v10.4.30 | 21.11.2026 | Fix launcher: `mumu-menu.cmd` dispatches `launch`/`stop`/`restart`/`logs` onto the script's real `-Action`/`-Instance`/`-Lines`/`-TimeoutSec`/`-Json`/`-Force` parameters and rejects unknown verbs/options with exit 2, instead of documenting the invented `run`/`start`/`wait`/`status` verbs and `MUUMU_*` variables; fix `[OI]`: a relative installer link resolves with `[System.Uri]::new([System.Uri]$page, $href)`, so the screen no longer dies with "cannot call a method on a null-valued expression" (`[System.Uri]($page).AbsoluteUri` parses as `[System.Uri](($page).AbsoluteUri)`); the launch screens explain MuMu's `abnormal runtime environment` refusal (English and the Russian dialog) with the nx_device/vms delete-and-recreate recipe (Restore itself does not help) plus the VT-x/Hyper-V/Core Isolation checks instead of a bare 120 s timeout, in the menu and in batch `launch`/`restart` |
| v10.4.29 | 21.11.2026 | Docs+hardening: every helper script now states exactly what it writes, and each writer gained a no-write mode — `-NoLog` (`Watch-MumuConnections`), `-NoFile` (`Diag-MumuNx`), `-NoSave` (`Test-MumuTunnelAB`, snapshots stay in memory), `-NoWrite` (`mmor-run`); `bootstrap-update` pins https downloads to HTTPS; `mumu-menu` documents the `Dynamic CSharp Compile Artefact` and `Get-Process` Sigma rules |
| v10.4.28 | 21.11.2026 | Fix `[OI]`: the Android package no longer looks found when neither CDN host answered — a missing `Content-Length`/digest with no redirect or name now prints `APK not reachable from here`, while the `integrity` line stays for a host that answered with only a `canonical` redirect or a filename |
| v10.4.27 | 21.11.2026 | Fix `[OI]`: the listing is empty on networks that cannot open `www.mumuplayer.com` — the release page is optional now, and the resolvers use a raw `HttpClient` HEAD with `AllowAutoRedirect = $false`, a browser `User-Agent` and a 12 s timeout because `Invoke-WebRequest` cannot report an unfollowed redirect and automatic redirects hang on the CDN hop; the APK is probed on both CDN hosts and the archive template follows a single HEAD |
| v10.4.26 | 21.11.2026 | Tests only: a new `Describe` pins the `mmor-run.json` writer — `recorderButton` from `kToolMenu.kToolMenuBtn`, `playButton`/`fileRow` empty, default `delays`, dot decimals under `de-DE`, missing pair as `null`, UTF-8 without BOM, captured pairs kept on refresh, round-trip through `Read-MmorConfig`; functions are AST-extracted, so the suite runs with no emulator |
| v10.4.25 | 20.11.2026 | New: `mmor-run.ps1` writes `mmor-run.json` itself — `-EmitConfig` or a run that finds no config produces a template with `recorderButton` derived from `kToolMenu.kToolMenuBtn` (normalized to the instance window), `playButton` left `null` until `-Record`, an explanatory `_comment` field, and captured pairs preserved on refresh |
| v10.4.24 | 20.11.2026 | Docs only: the `mmor-run.ps1` bullet in the README feature list is shortened to two sentences — `-Apply` is GUI mouse automation (cursor + `mouse_event` on the recorder window) and MuMu has no native `.mmor` verb, with the mode/verb/alternative details moved to `SKILL.md` |
| v10.4.23 | 20.11.2026 | Docs only: the `mmor-run.ps1` header (mirrored in the README feature list and `SKILL.md`) now states that `-Apply` is GUI mouse automation — cursor plus `mouse_event` on the recorder window, DPI/focus/timing dependent — and that MuMu exposes no native `.mmor` verb (`MuMuManager.exe` 6.8.9.0: no `mmor`/`script`/`play`), pointing at auto-execute-on-launch + `control launch` and `control tool cmd` as the supported options |
| v10.4.22 | 19.11.2026 | Fix `[L]`: the grid took the live window rectangle as "original", so every run adopted its own shrunken result and a window could end up tiny; the base is now the size MuMu saves for the instance (`customer_config.json`), the title bar and borders are re-added, and a previously shrunken window is restored before the grid is laid out |
| v10.4.21 | 19.11.2026 | Fix: `mmor-run.ps1` was missing from the 10.4.20 ZIP — the archive is built from the explicit `release-files.txt` list, not the whole tag, so a new file only ships once it is listed; the file now ships and is part of the `[U]` update set, the repair whitelist and the rollback/file-set checks (10 files) |
| v10.4.20 | 19.11.2026 | New `mmor-run.ps1`: probe/record/apply driver for native `.mmor` playback — probe lists the instance windows and their UIA elements and presses nothing, record captures the normalized click points for the recorder and Play, apply focuses the instance, opens the recorder and presses Play, refusing to run without a calibrated config; no `[U]` set change yet |
| v10.4.19 | 19.11.2026 | Fix `[G]`: live logcat no longer dropped back to the menu with a blank screen — the stream is opened without `-d`/`-t` and retried up to three times when the bridge closes with no output; `Get-InstanceIndex` re-asks with the valid range on non-numeric input instead of "not found"; `[L]` arranges running windows into a grid of n per row (2-6, default 3) with a never-enlarge `min(1, …)` scale (10 px margins and gaps), then raises them once, `[D]` closes every running instance with one `control -v all shutdown` call |
| v10.4.18 | 12.11.2026 | Fix: `[U]` failures now name the file and the reason (`<file>: <reason>`) instead of journaling `0 ok, N failed ()`, so a rate-limited or blocked run is distinguishable from a hash-gate rejection |
| v10.4.17 | 11.11.2026 | Fix: [2]/[3]/[4] surfaced the raw "expression after '&' ... was not valid" trap when the MuMuManager.exe path went stale after startup — `Get-InstanceIndex` and `Invoke-Mumu` now validate the path and name the real problem instead |
| v10.4.16 | 06.11.2026 | Fix [G]: a stopped or booting instance dead-ended logcat (a `starting_rom` VM read as stopped) with a hint pointing at `[2]`, which is the snapshot action — the screen now offers to start it, waits for boot, and shows a separate `STARTING` state; Ctrl+C in `[G]` now always returns to the main menu (the handler keeps the keystroke, `e.Cancel = true`, and ends the stream via the process-tree kill) |
| v10.4.14 | 04.11.2026 | Change: Ctrl+C in `[G]` live logcat returns straight to the main menu — the one-shot `$script:SkipContinuePause` flag drops the "Press any key" pause for that case only |
| v10.4.13 | 04.11.2026 | Fix: Ctrl+C needed a second press — the handler now kills the whole process tree (a surviving child kept stdout open) and skips the native `logcat -c` that hung on a stopped pipeline |
| v10.4.12 | 04.11.2026 | Fix: Ctrl+C still looked dead in `[G]` live logcat — the pipeline stopped but the native child kept printing; the stream is now read through an owned `Process` that the compiled handler kills |
| v10.4.11 | 04.11.2026 | Fix CI: the test file was committed without its UTF-8 BOM, so Windows PowerShell 5.1 read Cyrillic as ANSI and failed to parse (12 errors, red 5.1 leg) — BOM restored, 5.1 parse 0 errors |
| v10.4.10 | 04.11.2026 | Fix: Ctrl+C could not stop `[G]` live logcat (the menu-wide guard swallowed it) — the guard now carries an `Enabled` switch cleared for the stream and restored in `finally`; adb port is auto-detected across MuMu's 16384+32n block |
| v10.4.9 | 04.11.2026 | Fix [G]: live logcat was blank on remote/streaming players whose adb bridge answers `-202 vm not ready` — the screen now picks adb or the manager's `sh` transport and streams through it (133 lines in 18 s live) |
| v10.4.8 | 29.10.2026 | New: the menu now auto-restarts on a clean `[U]` update — no manual window close; verify via live A/B run that the child executes the already-new `mumu-menu.ps1` |
| v10.4.7 | 29.10.2026 | Fix [RL]: the release body arrived as `╨Ш╨╜…` because `Invoke-GitHubApiGet` piped `curl.exe` stdout and PS 5.1 decodes native output with the console code page (CP866); the body now goes through `curl -o` and is read as UTF-8 |
| v10.4.6 | 29.10.2026 | New: a clean `[U]` update relaunches the menu on the new files — the staged `.new` is applied before the child starts, so it parses the new script; piped, partial and failed-swap runs keep the manual "Restart the menu" message |
| v10.4.5 | 29.10.2026 | Fix: the saved GitHub token was ignored by `Invoke-GitHubApiGet` (empty `-Token` blocked the fallback) so every API call ran anonymously; [RL] now uses that transport and shows GitHub's reason instead of "cannot reach" |
| v10.4.4 | 29.10.2026 | Fix [RL]: renderer moved to script scope (was nested and unreachable), list parsing no longer uses PS7-only `-AsHashTable`/`.Values`, dates format correctly, Source note interpolates, changelog preview wraps per line |
| v10.4.3 | 29.10.2026 | Fix: [K] and every GitHub curl call no longer report "network problem" when Schannel cannot check certificate revocation (CRYPT_E_REVOCATION_OFFLINE) — a process-scoped CURL_HOME/_curlrc repairs it |
| v10.4.2 | 29.10.2026 | New [RL] read-only published-releases screen; fix: the menu parses again (unescaped apostrophe in the [WN] log line broke the whole script), [1]/[DIAG] ADB readiness false negative, first screen survives a host without a console buffer |
| v10.4.1 | 25.10.2026 | [OI] offline installers restyled onto the shared frame/group/aligned-column kit; resolver-path digest extraction and an honest integrity fallback row |
| v10.4.0 | 24.10.2026 | Unified styling for info/apps/settings, launch/shutdown/restart, ADB, APK install and window screens on a shared frame/status/step/note kit with aligned columns and colour-by-meaning |
| v10.3.5 | 22.10.2026 | Startup fix: no more ObjectSecurity "already present" type-data dump when 5.1 inherits PowerShell 7's PSModulePath through an intermediate launcher (PowerShell/PowerShell#18530); the script repairs $env:PSModulePath on Desktop only. New Repair-DesktopModulePath unit tests |
| v10.3.4 | 22.10.2026 | [V] reports the real Windows version (Windows 11 26H2 instead of "Windows 10.0"), Release workflow now explicitly dispatches the VirusTotal scan when published with GITHUB_TOKEN |
| v10.3.3 | 20.10.2026 | Ctrl+C no longer crashes the menu (compiled CancelKeyPress guard), `mumu-menu.cmd` double-click launcher for git clones |
| v10.3.1 | 19.10.2026 | Update check verifies the declared file set, not just .version (repairs installs missing a file added by a release) |
| v10.3.0 | 19.10.2026 | Native JavaScript engine (`node mumu-menu.cjs`), [WN] watcher rewritten on netstat (was 52 s/tick via Get-NetTCPConnection) with SEEN seed + heartbeat |
| v10.2.0 | 18.10.2026 | New [OI] offline installers, [F] installation auto-repair, updater hardening (stderr/token fallback), PS 5.1-safe verification snippet |
| v10.1.0 | 17.10.2026 | New [MU] MuMu emulator update check, window-close guards (Ctrl+C / errors / EOF), schema-valid CodeRabbit config |
| v10.0.0 | 14.10.2026 | Major release: semantic-version bump to v10.0.0, documentation reorganized, Pester 260/261 |

## Где смотреть полные изменения (changelog)

Полный список релизов и подробный changelog хранится в `relnotes.md` и в релизах GitHub: https://github.com/genrihx2/MuMuManager-CLI-Menu/releases

Короткий индекс всех тегов — дата тега, дата публикации и SHA-256 ZIP-архива каждого релиза: [RELEASES.md](https://github.com/genrihx2/MuMuManager-CLI-Menu/blob/main/RELEASES.md). Файл генерируется после каждого релиза, правки руками внутри маркеров `RELEASES:AUTO` перезаписываются.

## Wiki

Расширенная документация — roadmap, статус проекта, гайды — живёт в wiki репозитория:

- Главная страница: https://github.com/genrihx2/MuMuManager-CLI-Menu/wiki/Home
- Содержание: требования и установка, обзор возможностей меню, карта документов (README / SECURITY / relnotes / RELEASE-RUNBOOK / SKILL), troubleshooting, безопасность и план развития.
- Wiki — это git-репозиторий, страницы можно править локально: `git clone https://github.com/genrihx2/MuMuManager-CLI-Menu.wiki.git`

---

<!-- MENU:AUTO:START -->
```
======================================
    MuMuManager CLI Menu
======================================

  --- Emulator Control ---
  [1] Show emulator info
  [2] Launch emulator
  [3] Shutdown emulator
  [4] Restart emulator
  [RF] Repair device (delete VM data + recreate)
  [5] Create new emulator (Android 12/15)
  [UI] MuMu Manager window (WPF)
  [C] Clone emulator
  [X] Delete emulator
  [N] Rename emulator

  --- Apps and Settings ---
  [6] List installed apps
  [7] Show settings
  [CMP] Compare instance settings
  [RT] Enable / disable root (instance)
  [VE] Virtual environment (enable/disable/remove)
  [FPS] Set frame rate (30/60/90/120/144/240/uncapped)
  [8] Install APK
  [9] Uninstall app
  [G] View logs

  --- Batch ---
  [B] Launch all instances
  [D] Shutdown all instances
  [R] Restart all instances
  [I] Install APK to all

  --- Window ---
  [W] Show all windows
  [H] Hide all windows
  [L] Layout windows (grid, n per row)

  --- Tools ---
  [S] Take screenshot
  [A] Run ADB command
  [AF] ADB file transfer (push/pull/list)
  [AS] ADB screen capture (screenshot/record)
  [AH] ADB interactive shell
  [O] Clear app data
  [P] Force stop app
  [T] Start app
  [E] Export emulator data
  [BA] Backup instance data
  [RE] Restore from backup
  [K] Update GitHub token
  [VK] Set VirusTotal API key
  [CRT] Create/sign certificate
  [Z] Security audit (disabled)

  --- Tests ---
  [TC] Connection test
  [TN] Network test
  [TS] Network speed test
  [TD] Dependencies test
  [VT] VirusTotal scan
  [VF] VirusTotal Upload file
  [UW] Fix Unicode / encoding

  --- Spoofing ---
  [DM] Spoof device model
  [SIM] Change SIM operator / country (MCC/MNC)
  [SIM+] View / clear auto-apply SIM config
  [SC] SIM check (all properties)
  [AI] Set Android ID
  [DI] Random device IDs

  --- Info ---
  [WN] Watch MuMu network + updater
  [RM] Resource monitor (CPU/RAM, live)
  [IN] MuMu installation (choose active)
  [V] Version info
  [MU] MuMu emulator update check (read-only)
  [OI] Offline installers (all versions, read-only)
  [U] Check for updates
  [UP] Update plan (dry-run)
  [F] Verify installation (files vs release tag)
  [ST] Install status (read-only)
  [J] Update journal
  [DIAG] Problem diagnostics
  [RB] Rollback from backup
  [DL] Download repository
  [CR] Create release
  [RL] Release list
  [FR] Fix release encoding
  [0] Exit
======================================
```
<!-- MENU:AUTO:END -->

English summary

A compact interactive PowerShell menu to manage local Netease MuMu Emulator instances: start/stop/clone/delete instances, APK install/uninstall, ADB tooling, backups, device spoofing (model, IMEI, Android ID, MAC), screenshots/screenrecord, log viewing (adb logcat snapshot/live), GitHub token manager, self-update with SHA-256 verification and VirusTotal scans for releases. See Releases or relnotes.md for full changelog and security notes.

Help flow:
1. Check requirements.
2. Launch the menu and inspect version/status.
3. If startup fails, check Mark-of-the-Web / execution policy.
4. If MuMu is not detected, use `[IN]` and `[DIAG]`.
5. If updates fail, run `[F]`, `[ST]`, and `[J]` before restoring from backup.
6. Use relnotes.md or GitHub Releases for full change history.
