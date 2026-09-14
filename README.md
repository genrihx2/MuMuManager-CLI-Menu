# MuMu Manager CLI Menu

[![Code Scanning](https://github.com/genrihx2/MuMuManager-CLI-Menu/actions/workflows/security-scan.yml/badge.svg)](https://github.com/genrihx2/MuMuManager-CLI-Menu/actions/workflows/security-scan.yml)
[![Latest Release](https://img.shields.io/github/v/release/genrihx2/MuMuManager-CLI-Menu?label=latest)](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)
[![Release Date](https://img.shields.io/github/release-date/genrihx2/MuMuManager-CLI-Menu)](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases)

> **Открытый исходный код.** Скрипт предназначен исключительно для управления 
> локальными инстансами MuMu Emulator на вашем компьютере. Функции подмены 
> устройства (IMEI/Android ID/MAC) предназначены для приватности и тестирования 
> приложений на **собственных** инстансах. Полное объяснение — в разделе 
> «Примечание для AV-аналитиков» ниже.

Интерактивное PowerShell-меню для управления MuMu Emulator 6.0

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
- 🪟 Управление окнами (показать/скрыть/расположить)
- 🔄 Массовые операции (все инстансы)
- 📋 Просмотр логов (статические файлы + **adb logcat**: снапшот, live-стрим, фильтр по уровню/тегу)
- 🛡️ Менеджер GitHub-токена (DPAPI-шифрование)
- 📊 Информация о версиях
- ⚡ Автообновление из GitHub
- 🗄️ Загрузка репозитория (git clone, ZIP, отдельный файл)

## Требования

- **Windows 10/11**
- **PowerShell 5.1+** или **PowerShell 7+**
- **MuMu Emulator 6.0** (версия 4.0.0.3179 или выше)

## Установка

### Через Git
```powershell
git clone https://github.com/genrihx2/MuMuManager-CLI-Menu.git
cd MuMuManager-CLI-Menu
.\mumu-menu.ps1
```

### Вручную
1. Скачайте `mumu-menu.ps1`
2. Поместите в любую папку
3. Запустите `.\mumu-menu.ps1`

Опционально: чтобы открывать меню командой `mumu`, вставьте сниппет в свой PowerShell-профиль (`notepad $PROFILE`):
```powershell
function mumu { & "C:\путь\к\mumu-menu.ps1" }
```

### Готовая сборка (Releases)
Скачайте актуальный zip со страницы [Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest), распакуйте и запустите `mumu-menu.ps1`.

**Как работают релизы:**
- Релизы создаются **автоматически** (GitHub Actions) из тегов `v*`: пуш тега или `[CR]` в меню — ZIP всегда собирается из содержимого тега
- Релиз не публикуется, если `$scriptVer` в `mumu-menu.ps1` не совпадает с версией тега
- Каждый релиз привязан к **тегу** (например `v1.13.40`) — обновления берутся только из тегов
- ZIP-архив содержит: `mumu-menu.ps1`, `README.md`, `SKILL.md`, `.version`
- Теги нельзя удалить/перезаписать — это гарантирует целостность истории обновлений

**Способы установки:**

1. **Быстрый запуск** (одна команда — скачивает и запускает):
```powershell
irm https://raw.githubusercontent.com/genrihx2/MuMuManager-CLI-Menu/main/mumu-menu.ps1 -OutFile $env:TEMP\mumu-menu.ps1; & $env:TEMP\mumu-menu.ps1
```

2. **Git clone** (с возможностью обновления через `[U]`):
```powershell
git clone https://github.com/genrihx2/MuMuManager-CLI-Menu.git
cd MuMuManager-CLI-Menu
.\mumu-menu.ps1
```

3. **Скачать ZIP** вручную со страницы [Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest), распаковать и запустить `mumu-menu.ps1`.

## Использование

### Запуск меню
```powershell
.\mumu-menu.ps1
```

### Меню опций

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
  [5] Create new emulator (Android 12/15)
  [C] Clone emulator
  [X] Delete emulator
  [N] Rename emulator

  --- Apps and Settings ---
  [6] List installed apps
  [7] Show settings
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
  [L] Layout windows

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
  [V] Version info
  [U] Check for updates
  [DL] Download repository
  [CR] Create release
  [FR] Fix release encoding
  [0] Exit
======================================
```
<!-- MENU:AUTO:END -->

### Примеры

#### Запуск эмулятора
```
Select option: 2

Select instance to launch (0-9): 0

Launching instance 0...
  [#-----------------------------]  2% [ 3s]  state: starting_vm
  [##----------------------------]  5% [ 6s]  state: starting_rom
  [##############################] 100% Emulator is running! (booted in ~20s)
```

#### Массовый запуск
```
Select option: B

Found 3 instance(s)
  [0] Android Device - launching...
  [1] Game Phone - launching...
  [2] Test Device - launching...

All instances launched. Polling boot status...
  [5 s] still booting...
  [10 s] still booting...
  All instances ready in ~15s!
```

#### Установка APK на все инстансы
```
Select option: I

Enter APK file path: C:\Downloads\game.apk

Installing game.apk (45.2 MB) to 3 instance(s)...

  [0] Android Device - installing...
  [0] Android Device - OK
  [1] Game Phone - installing...
  [1] Game Phone - OK
  [2] Test Device - skipped (not running)

Done! Success: 2, Failed: 0
```

#### Клонирование инстанса
```
Select option: C

Select instance to clone (0-9): 0

Cloning instance 0...
Source: [0] Android Device

Clone completed!

Current instances:
  [0] Android Device - start_finished <-- source
  [1] Android Device (1) - stopped
```

#### Удаление инстанса
```
Select option: X

Select instance to DELETE (0-9): 1

WARNING: This will permanently delete instance 1!
Type YES to confirm: YES

Deleting instance 1...
Instance deleted!
```

#### Переименование инстанса
```
Select option: N

Select instance to rename (0-9): 0

Current name: Android Device
Enter new name: My Phone

Renaming to 'My Phone'...
Renamed to 'My Phone'!
```

#### Управление окнами
```
Select option: L

Arranging emulator windows...
Done! Windows arranged.
```

#### Подмена модели устройства
```
Select option: DM

Select instance: 0

Current device model:
  Brand: Samsung
  Model: Galaxy A54
  Code:  SM-A546E

Device presets:
  [ 1] Samsung Galaxy S23 Ultra (SM-S918B)
  [ 2] Samsung Galaxy A54 (SM-A546E)
  [ 3] Google Pixel 8 Pro (G1MNW)
  ...
Select device: 3

Setting device to Google Pixel 8 Pro (G1MNW)...
Device model set to Google Pixel 8 Pro!
Device name updated live.
Restart the emulator to fully apply build properties.
```

#### Случайные идентификаторы устройства
```
Select option: DI

Select instance: 0

Current simulated properties:
  IMEI:       353240116262762
  Android ID: (not set)
  MAC:        (not set)

Randomize:
  [1] IMEI
  [2] Android ID
  [3] MAC address
  [4] All of the above
Select option: 4

  IMEI -> 356821728580688
  Android ID -> 13f454f21c0f5f57
  MAC -> e2:fa:65:e3:f5:38

Done! Restart the emulator to apply.
```

#### Скриншот
```
Select option: S

Select instance (0-9): 0

Taking screenshot of instance 0...
Screenshot saved: screenshots\screenshot_0_20260821_153000.png
Size: 1614.1 KB
```

#### Информация о версиях
```
Select option: V

=== MuMu Manager CLI Menu ===

Script version: 1.18.10
MuMu version: 6.5.2.0
PowerShell: 5.1.28000.2704
OS: Windows 10.0
Repository: genrihx2/MuMuManager-CLI-Menu
GitHub token: configured
Instances: 1 (1 running)
```

## Путь к MuMuManager.exe

По умолчанию скрипт ищет:
```
C:\Program Files\Netease\MuMuPlayer\nx_main\MuMuManager.exe
```

Если MuMu установлен в другое место, измените переменную `$MumuPath` в начале файла `mumu-menu.ps1`.

## Автообновление

При запуске скрипт выполняет **быструю проверку версии** через GitHub API (сравнение тегов без скачивания файлов) — на старте ничего не скачивается.

Загрузка файлов возможна **исключительно вручную**: пункт меню `[U] Check for updates` + подтверждение. При этом:

- **Быстрый путь**: сравнение локального `.version` с тегом релиза (мгновенно, без скачивания)
- **Медленный путь**: при различии тегов скачивание файлов для сравнения хешей (устойчиво к разнице CRLF/LF)
- Обновления берутся **только из тегов GitHub Releases**, а не из ветки `main`
- Показывается **changelog** (до 20 строк) перед подтверждением
- **Прогресс загрузки** с отображением скорости и размера (`curl.exe -#`)
- Перед перезаписью **предыдущие версии сохраняются** в `backup\<дата_время>\` (авто-очистка старше 5)
- Таймауты и повторы всех сетевых запросов (через встроенный `curl.exe`)

Для приватных репозиториев сохраните токен через пункт меню `[K] Update GitHub token` — он проверяется и хранится **зашифрованным через Windows DPAPI** в `.github-token.dpapi`; плейнтекстовый `.github-token` мигрирует в зашифрованное хранилище автоматически при первом запуске.

## Что нового

### v1.18.10 (14.09.2026)
- **bootstrap-update.ps1 в релизном ZIP**: установщик обновлений теперь поставляется в каждом релизе — инсталляция всегда может починить/обновить сам обновлятор (урок v1.18.8: ZIP не содержал фикс обновлятора)
- **VT-скан всех файлов релиза (issue #14)**: CI сканирует не только ZIP, но и `mumu-menu.ps1` + `SKILL.md` извлечённые из того же ZIP; повторно известные VT объекты переиспользуются по SHA-256, в step summary — таблица вердиктов с пермалинками

### v1.18.9 (14.09.2026)
- **Sigma #8 (NTFS Alternate Data Stream)**: MIME-литерал в коде загрузки VT давал подстроку «-stream» в том же скриптблоке, где есть `Set-Content` — правило срабатывало ложно; загрузка переведена на `curl.exe` multipart, литерал удалён. Скрипт никогда не работал с ADS
- Фикс не меняет поведение: те же эндпоинты, тот же DPAPI-ключ, та же логика `Set-Content` — только корректный multipart через `curl.exe`

### v1.18.8 (14.09.2026)
- **Fix bootstrap-update**: JSON-детектор ложно срабатывал на raw `mumu-menu.ps1` («Received JSON metadata instead of raw file») — raw-скрипт содержит литералы `"name":` и `_links` в собственных API-проверках; теперь JSON-проверки применяются только когда тело ответа начинается с `{`
- **Fix [U] Check for updates**: та же защита в обновляторе меню (тот же класс ложного срабатывания)
- **Fix .version**: bootstrap-update обновляет `.version` только при успешной загрузке всех файлов — частичный сбой больше не оставляет `.version` впереди фактической версии скрипта

### v1.18.7 (14.09.2026)
- **Release pipeline**: tag-driven Release workflow — ZIP и SHA256 собираются строго из содержимого тега (`git archive`), проверка соответствия `$scriptVer` тегу, идемпотентные перезапуски
- **VirusTotal в CI**: автоматический скан релизного ZIP после публикации (секрет `VT_API_KEY`); исправлен невалидный YAML в `virustotal.yml`, из-за которого workflow не мог запуститься
- **CI lint**: actionlint + shellcheck по всем workflow (`lint.yml`); VT-вердикты v1.18.6 — 0 malicious / 0 suspicious (ZIP, `mumu-menu.ps1`, `SKILL.md`); добавлен `RELEASE-RUNBOOK.md`

### v1.18.6 (04.09.2026)
- **Auto-detect MuMuManager.exe path**: добавлены generic `shell\` пути для автоопределения MuMuManager.exe, registry fallback проверяет и `nx_main\`, и `shell\`

### v1.18.5 (04.09.2026)
- **Fix download helpers**: убраны stale $LASTEXITCODE проверки, добавлена проверка длины токена

### v1.18.4 (04.09.2026)
- **Fix VT menu**: опция [2] Save API key больше не показывает "Invalid selection"

### v1.18.3 (04.09.2026)
- **Fix update download**: токен теперь передаётся при скачивании обновлений, добавлено определение rate limit

### v1.18.2 (04.09.2026)
- **SECURITY.md**: обновлена политика безопасности — VT API ключ, сетевые эндпоинты, sigma false positive #7, secure installation steps

### v1.18.1 (04.09.2026)
- **[VF] VirusTotal Upload file**: загрузка произвольного файла на VirusTotal через API с проверкой существующих результатов, поллингом анализа и отображением вердикта
- **Сводная таблица изменений**: добавлена для быстрого обзора всех версий
- **PSScriptAnalyzer #534**: заменён пустой catch block в Upload-VirusTotal на Write-Debug

### v1.18.0 (04.09.2026)
- **SIM check**: `[SC]` группированная таблица всех SIM-свойств с сводкой состояния
- **debug.tracing.mcc/mnc**: SIM-спуфинг теперь также устанавливает внутренние MCC/MNC эмулятора
- **ADB wait loop**: `Set-SimOperator` и `Apply-SavedSim` теперь ждут до 30с пока ADB будет онлайн перед установкой свойств
- **Shell escaping**: символы `&`, `;`, `|`, `$` в именах операторов заменяются на `_` для надёжной работы в shell
- **PSScriptAnalyzer**: подавлены предупреждения `PSUseApprovedVerbs` и `PSUseDeclaredVarsMoreThanAssignments` на уровне скрипта
- **bootstrap-update.ps1**: добавлен Bad credentials fallback для API-запросов и скачивания файлов

### v1.13.29 (31.08.2026)
- **VirusTotal интеграция**: `[VT]` сканирование файлов через VT API, `[VK]` управление API ключом (DPAPI-шифрование)
- **Исправлена ошибка DPAPI**: добавлен `.Trim()` перед расшифровкой токена — исправляет ошибку «incorrect format» с BOM/CRLF
- **Улучшена загрузка репозитория**: `[2]` показывает список релизов с датами и описаниями, `[3]` fallback на скачивание файлов без ZIP
- **Обновления `[DL] → [4]`**: сравнение версий, changelog, обновление .version после ZIP
- **JSON валидация**: все пути скачивания проверяют ответ API — предотвращает сохранение JSON-метаданных как файл
- **AI-сканер ответ**: добавлена таблица-разбор в SECURITY.md для AI/LLM анализаторов
- **Удалён Cloudsmith**: полностью убрана интеграция с Cloudsmith

### v1.13.28 (30.08.2026)
- **ADB управление**: `[AF]` передача файлов (push/pull/list), `[AS]` скриншоты и запись экрана, `[AH]` интерактивная ADB-сессия
- **Улучшена загрузка репозитория**: `[5]` скачивание отдельного файла
- **Быстрая проверка обновлений**: сравнение версий без скачивания скрипта
- **Исправлена ошибка скачивания**: пустой `Authorization` заголовок при отсутствии токена
- **Исправлен пустой catch**: PSScriptAnalyzer #518 — `catch {}` теперь логирует ошибку

### v1.13.27 (29.08.2026)
- **Исправлен `$scriptVer`**: переменная версии скрипта определена в глобальной области видимости — меню теперь корректно показывает версию в шапке
- **Исправлен `$InstalledVersion`**: переменная версии MuMu теперь инициализируется до проверки — `Show-QuickStatus` не падает при ошибке `MuMuManager.exe version`
- **Прогресс-бар загрузки `[U]`**: заменён молчаливый `WebClient` на `curl.exe -#` с отображением скорости, размера и прогресса
- **Защита от краша при запуске**: проверка обновлений `Update-FromGitHub -Passive` обёрнута в `try/catch` — ошибки сети не убивают скрипт до появления меню

### v1.13.26 (26.08.2026)
- **Consent-гейты для чувствительных операций**: `[O] Clear app data` и `[9] Uninstall app` теперь требуют явного ввода `YES` с описанием последствий
- `[A] Run ADB command`: session-consent перед первым произвольным ADB-шеллом (команды выполняются только внутри собственной ВМ эмулятора, хост недоступен)
- VirusTotal: **0/75** (ps1), **0/75** (zip)

### v1.13.25 (26.08.2026)
- **Безопасность репозитория**: добавлена политика безопасности `SECURITY.md` (RU/EN) — как приватно сообщить об уязвимости, что не считается уязвимостью, SLA ответа
- **Code scanning**: PSScriptAnalyzer → SARIF → GitHub Code Scanning
- `.version` синхронизирован с релизным тегом

Полный журнал изменений: [relnotes.md](relnotes.md)

### Сводная таблица изменений

| Версия | Дата | Изменения |
|--------|------|-----------|
| v1.18.10 | 14.09.2026 | bootstrap-update.ps1 в релизном ZIP; VT-скан ZIP + ps1 + SKILL.md в CI (issue #14) |
| v1.18.9 | 14.09.2026 | Sigma #8 (NTFS ADS): убран MIME-литерал «-stream», VT-загрузка через curl.exe multipart |
| v1.18.8 | 14.09.2026 | Fix bootstrap-update/[U]: JSON-детектор самоматчился на raw ps1; .version только при полном успехе |
| v1.18.7 | 14.09.2026 | Release pipeline: tag-driven CI, VT-скан релиза в CI, actionlint/shellcheck, RELEASE-RUNBOOK |
| v1.18.6 | 04.09.2026 | Auto-detect MuMuManager.exe: generic shell\ paths + registry shell fallback |
| v1.18.5 | 04.09.2026 | Fix download helpers: stale $LASTEXITCODE, token length check |
| v1.18.4 | 04.09.2026 | Fix VT меню: [2] Save API key «Invalid selection» fix |
| v1.18.3 | 04.09.2026 | Fix update download: token в загрузках, rate limit detection |
| v1.18.2 | 04.09.2026 | SECURITY.md: VT API, сетевые эндпоинты, sigma #7, secure installation |
| v1.18.1 | 04.09.2026 | `[VF]` загрузка файлов на VirusTotal, сводная таблица, PSScriptAnalyzer #534 fix |
| v1.18.0 | 04.09.2026 | `[SC]` проверка SIM, debug.tracing.mcc/mnc, ADB wait loop, shell escaping, PSScriptAnalyzer suppress, bootstrap Bad credentials fallback |
| v1.13.29 | 31.08.2026 | `[VT]` VirusTotal scan, `[VK]` API ключ, DPAPI fix, JSON валидация, AI-сканер ответ, удалён Cloudsmith |
| v1.13.28 | 30.08.2026 | `[AF]` ADB файлы, `[AS]` скриншоты, `[AH]` ADB shell, быстрая проверка обновлений, прогресс-бар загрузки |
| v1.13.27 | 29.08.2026 | Исправлены `$scriptVer` и `$InstalledVersion`, прогресс-бар `[U]`, защита от краша при запуске |
| v1.13.26 | 26.08.2026 | Consent-гейты для `[O]` и `[9]`, session-consent для `[A]` ADB shell |
| v1.13.25 | 26.08.2026 | `SECURITY.md` (RU/EN), PSScriptAnalyzer → SARIF → GitHub Code Scanning |

---

## Безопасность

- **VirusTotal (v1.18.10): 0 malicious / 0 suspicious** — релизный ZIP (66 движков), `mumu-menu.ps1` (62), SKILL.md — скан CI (run #209, все файлы релиза)
- CI автоматически сканирует релизный ZIP, а также `mumu-menu.ps1` и `SKILL.md` из его состава (`virustotal.yml`, секрет `VT_API_KEY`); известные VT объекты переиспользуются по SHA-256
- Встроенное сканирование: `[VT] VirusTotal scan` — проверяет файлы через VT API

| Файл | SHA-256 | Движков | Отчёт |
|------|---------|---------|-------|
| релизный `MuMuManager-CLI-Menu-v1.18.10.zip` | `f8f60e081053…768e` | 66 | [отчёт](https://www.virustotal.com/gui/file/f8f60e081053f04bb587f6b5d1e7db2405f4f42a0f1a8d371311e2f2e9c9768e) |
| `mumu-menu.ps1` (v1.18.10) | `ad98ccb10814…a46` | 62 | [отчёт](https://www.virustotal.com/gui/file/ad98ccb10814877584db660ab1c77e39eb5ca78571d1da88786ac4c6ef543a46) |
| релизный `MuMuManager-CLI-Menu-v1.18.9.zip` | `a4e6312fdc31…6922` | 65 | [отчёт](https://www.virustotal.com/gui/file/a4e6312fdc31c3f08909cbd4d7b373a2d7bf22fee6fa7270010f4bd27acd6922) |
| `mumu-menu.ps1` (v1.18.9) | `9188407bd1d1…f181` | 62 | [отчёт](https://www.virustotal.com/gui/file/9188407bd1d1577f09e50611c80f6f5e2bfb9aa6f6181f36918e7c500d67f181) |
| релизный `MuMuManager-CLI-Menu-v1.18.8.zip` | `93e6cc95eb4a…8f21` | 65 | [отчёт](https://www.virustotal.com/gui/file/93e6cc95eb4a1c4ab1f3554d6811a107b2b89e6499bd9b7d07cff20f4e918f21) |
| `mumu-menu.ps1` (v1.18.8) | `f1eb73e49f70…ea70` | 61 | [отчёт](https://www.virustotal.com/gui/file/f1eb73e49f70cc53bfc1eb413ee2deeccc71534482c6eb6b1dce38ecca9eea70) |
| релизный `MuMuManager-CLI-Menu-v1.18.7.zip` | `63b1dce6583b…7596` | 66 | [отчёт](https://www.virustotal.com/gui/file/63b1dce6583be8e46e386d2877a718c9e7c9a511ab2a9f4b41929849a7a27596) |
| `mumu-menu.ps1` (v1.18.7) | `0c8427f956c8…45b2` | 62 | [отчёт](https://www.virustotal.com/gui/file/0c8427f956c870cf63ffec3f858aa9af09c5e1c6f0b270ec2f3d7d275b8c45b2) |
| релизный `MuMuManager-CLI-Menu-v1.18.6.zip` | `42a5bb22d3a1…50cc` | 66 | [отчёт](https://www.virustotal.com/gui/file/42a5bb22d3a1a2bdac5487fe011fb5d9389b2a1d0e0378743c375ef5a62350cc) |
| `mumu-menu.ps1` (v1.18.6) | `cff9e179648c…6664` | 60 | [отчёт](https://www.virustotal.com/gui/file/cff9e179648cc4395d3b0da8373f5b07f8361a0c339880f3f03508ba3f006664) |
| `SKILL.md` (v1.18.6) | `ce1f9c9ae730…7382` | 61 | [отчёт](https://www.virustotal.com/gui/file/ce1f9c9ae730afba9eece06e8c38a8164faf645f64b3caea433d2a8e80367382) |
| `mumu-menu.ps1` (v1.13.29) | `874542b1ae26…d251` | 62 | [отчёт](https://www.virustotal.com/gui/file/874542b1ae264d7dd543ef44670b98ff2eb0b021375151e8d22c8a83d037d251) |
| `bootstrap-update.ps1` | `2d4430c15c7b…be30` | 60 | [отчёт](https://www.virustotal.com/gui/file/2d4430c15c7b90b486d6a5225a6728889b39acdaaeb917f0d8fc73084243be30) |
| `mumu-menu.ps1` (v1.13.26) | `318132d22881…f8c` | 75 | [отчёт](https://www.virustotal.com/gui/file/318132d2288194413cd559b100309f6900d6cbe6ee29df8cb0f80e4020299f8c) |

| Файл | SHA-256 | Движков | Отчёт |
|------|---------|---------|-------|
| `mumu-menu.ps1` (v1.13.26) | `318132d22881…f8c` | 75 | [отчёт](https://www.virustotal.com/gui/file/318132d2288194413cd559b100309f6900d6cbe6ee29df8cb0f80e4020299f8c) |
| релизный `MuMuManager-CLI-Menu-v1.13.26.zip` | `c10e5da08f30…ec5` | 75 | [отчёт](https://www.virustotal.com/gui/file/c10e5da08f3041eeae7ba762871a486f7c1ee08394492fc8422ecb8aa66d3ec5) |
| `mumu-menu.ps1` (v1.13.25) | `825982aa50e3…652` | 75 | [отчёт](https://www.virustotal.com/gui/file/825982aa50e3017b78473acb28715745b510c8a999ef6e1ae36f64664b239652) |
| релизный `MuMuManager-CLI-Menu-v1.13.25.zip` | `08be745ca928…4d3` | 75 | [отчёт](https://www.virustotal.com/gui/file/08be745ca9286e99b7bfce87ccaacbd13c19b166cb235c8d491f0096c14448d3) |
| `mumu-menu.ps1` (v1.13.14) | `97cfac7eb2ce…912` | 75 | [отчёт](https://www.virustotal.com/gui/file/97cfac7eb2ced8644579aae38c84bf81760ebf633568061312fa2277e3f94912) |
| релизный `MuMuManager-CLI-Menu-v1.13.14.zip` | `0da34de075d4…bde` | 74 | [отчёт](https://www.virustotal.com/gui/file/0da34de075d43ce043cace86303ab41776ce5552a4aea9742addcd18aa69cbde) |
| `mumu-menu.ps1` (v1.13.7) | `4cfb3fd0679d…1f0c` | 60 | [отчёт](https://www.virustotal.com/gui/file/4cfb3fd0679da38a575619d4e54514acae6855b1913bf6150fab3bd261b51f0c) |
| релизный `MuMuManager-CLI-Menu-v1.13.7.zip` | `5d7ae270346a…5a9e` | 64 | [отчёт](https://www.virustotal.com/gui/file/5d7ae270346a089305c7a5c52568814f382a7ffb6873604a0ffc0327c5565a9e) |
| `mumu-menu.ps1` (v1.13.6) | `f3e00f73e2fc…f6fab4` | 60 | [отчёт](https://www.virustotal.com/gui/file/f3e00f73e2fc1dc9644ce375a78f20a52340c39fab0a94e1d5cc82c665f6fab4) |
| `mumu-menu.ps1` (v1.13.4) | `201de575dcd3…c3081` | 60 | [отчёт](https://www.virustotal.com/gui/file/201de575dcd35d962e3980c73ef7e5d4d5d2c4f96dda189eeff92cea297c3081) |
| `mumu-menu.ps1` (v1.13.3) | `35fd20035859…4ec1e` | 44+ | [отчёт](https://www.virustotal.com/gui/file/35fd200358598ecd71978cdd29a06fdd26182d8698942d19a81fe5fd9014ec1e) |
| `update-readme.ps1` | `618c48dc0809…e6854` | 60 | [отчёт](https://www.virustotal.com/gui/file/618c48dc0809f68c178634470d15dcdf708f90f3e32ffb9a31dfd9a9ff7e6854) |
| `README.md` | `868a1a7db4cf…03ddf` | 60 | [отчёт](https://www.virustotal.com/gui/file/868a1a7db4cf7df3f9fc51e4e0a9dd738f3cd17192df775dd6cdff1ead003ddf) |
| `SKILL.md` | `1e60372d8fbe…8f2e7b` | 60 | [отчёт](https://www.virustotal.com/gui/file/1e60372d8fbea80854619fcbca10c0c39a3bea74f35999bfefc55dfb6a8f2e7b) |
| релизный `MuMuManager-CLI-Menu-v1.13.5.zip` | `940264ef8e12…02cc` | 64 | [отчёт](https://www.virustotal.com/gui/file/940264ef8e1225f7111d73c8d806d0580a484129b1877dbf47e21f61f87f02cc) |

### URL-репутация

URL-сканеры (SafeToOpen, Chong Lua Dao) помечают ссылки вида `raw.githubusercontent.com/.../*.ps1` как «malicious» **по шаблону адреса**, не анализируя содержимое — файл по ссылке чист (0/61). В ответ:

- оставлен комментарий владельца к URL-объекту на VirusTotal;
- начиная с v1.13.3 самообновление скачивает файлы только через официальный `api.github.com` и больше не обращается к `raw.githubusercontent.com`.
- Самообновление скачивает только текстовые файлы (.ps1/.md), никаких исполняемых файлов
- GitHub-токен хранится только в шифрованном виде (Windows DPAPI, CurrentUser); плейнтекст не записывается на диск
- Нет обфускации, автозагрузки, задач планировщика и модификаций сертификатов
- Подмена модели и генерация идентификаторов предназначены для приватности и тестирования приложений на собственных инстансах пользователя

### Примечание для AV-аналитиков и AI-сканеров

Статические LLM-обзорщики могут помечать утилиту как «suspicious» из-за **назначения** функций (спуфинг идентификаторов, менеджер токена, самообновление), а не из-за поведения кода. Вот разбор каждого担忧:

| Тревога AI-сканера | Реальность |
|-------------------|------------|
| «Spoofing device identifiers» | Функция приватности для СОБСТВЕННЫХ экземпляров эмулятора. Требует подтверждения «OK». Не влияет на реальные устройства. |
| «Handling sensitive information» | Токен GitHub зашифрован через Windows DPAPI (CurrentUser scope). Расшифровывается только тем же пользователем Windows. Плейнтекст не хранится. |
| «Extensive access to emulator internals» | Все операции используют официальный CLI Netease (`MuMuManager.exe`) и стандартный `adb.exe`. Нет reverse engineering. |
| «Risk of misuse» | Каждая чувствительная операция требует ввода «OK». Скрипт документирует намерения в комментариях и политике безопасности. |
| «Self-update mechanism» | Обновления ТОЛЬКО из tagged GitHub Releases с проверкой SHA256. Нет выполнения кода из недоверенных источников. |
| «Certificate management» | Self-signed CodeSigning сертификат только для подписи скрипта. Явное действие через меню `[CRT]`. |

**Ключевые факты:**

- Все сетевые операции — только HTTPS к `api.github.com` (проверка версий, загрузка обновлений, валидация токена); стартовая проверка — read-only, загрузка только по явному выбору `[U]` с подтверждением
- Токен хранится исключительно DPAPI-шифрованным; плейнтекст не пишется и при обнаружении мигрируется/удаляется
- Нет инъекций, доступа к критическим системным процессам, дампов памяти, обфускации, encoded-команд, persistence
- Эмулятор управляется официальным CLI Netease (`MuMuManager.exe`); ADB-команды выполняются только по явному запросу пользователя внутри виртуальных машин
- Мультидвижковый вердикт VirusTotal: **0 malicious / 0 suspicious** (62 движка)
- Подробнее: [SECURITY.md](SECURITY.md)

## Компоненты

| Файл | Описание |
|------|----------|
| `mumu-menu.ps1` | Основной скрипт с интерактивным меню |
| `update-readme.ps1` | Синхронизация README с меню/версией скрипта |
| `.github/workflows/sync-readme.yml` | Автообновление README при пуше (GitHub Actions) |
| `.github/workflows/release.yml` | Автоматические релизы при смене версии |
| `.github/workflows/security-scan.yml` | PSScriptAnalyzer → SARIF → Code Scanning |
| `SECURITY.md` | Политика безопасности (RU/EN) |
| `relnotes.md` | Журнал изменений |
| `.gitattributes` | Нормализация окончаний строк (LF) |
| `backup/`, `backups/` | Локальные копии (не коммитятся) |
| `SKILL.md` | Документация навыка для AI-агентов |
| `bootstrap-update.ps1` | аварийное обновление (восстановление при поломке [U]) |
| `.github-token.dpapi` | Токен GitHub DPAPI-шифрованный (не коммитится) |
| `.vt-apikey.dpapi` | API ключ VirusTotal DPAPI-шифрованный (не коммитится) |

> Блок меню и версия в README генерируются автоматически из `mumu-menu.ps1`
> (`update-readme.ps1`, запускается локально и в GitHub Actions).

## Лицензия

MIT License

## Автор

[genrihx2](https://github.com/genrihx2)
