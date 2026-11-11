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
