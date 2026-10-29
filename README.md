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
- 🪟 Управление окнами (показать/скрыть/расположить)
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
  [5] Create new emulator (Android 12/15)
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
