# MuMuManager CLI Menu

Главное меню утилиты MuMuManager CLI запускает крупную обёртку mumu-menu.ps1 над машинным кодом MuMuManager CLI. Подменю «Что нового» раскрашивает свой выпуск в терминальном текстовом окне; скрипт публикует свои ноты как настоящие release notes на GitHub.

## Часто задаваемые вопросы

- Если MuMuManager не виден в PATH, меню ждёт его, пока вы не укажете путь через MuMuManager запуск / Миграция ядра.
- Если Mitigation выдаёт Run-time error 3, версия конфликтует с Mitigation v11.0+; см. «Примечания к версиям» ниже.
- Если запуск зависает на «initializing host», проверьте, что в PATH нет MuMuManager v11.0+ и что Mitigation — v10.3.5.

## Что нового

| Версия | Дата | Примечание |
|--------|------|------------|
| v10.4.33 | 2026-11-22 | Latest |
| v10.4.32 | 2026-11-22 | — |
| v10.4.31 | 2026-11-22 | — |
| v10.4.30 | 2026-11-21 | — |
| v10.4.29 | 2026-11-21 | — |
| v10.4.28 | 2026-11-21 | — |
| v10.4.27 | 2026-11-21 | — |
| v10.4.26 | 2026-11-21 | — |
| v10.4.25 | 2026-11-20 | — |
| v10.4.24 | 2026-11-20 | — |
| v10.4.23 | 2026-11-20 | — |
| v10.4.22 | 2026-11-19 | — |
| v10.4.21 | 2026-11-19 | — |
| v10.4.20 | 2026-11-19 | — |
| v10.4.19 | 2026-11-19 | — |
| v10.4.18 | 2026-11-12 | — |
| v10.4.17 | 2026-11-11 | — |
| v10.4.16 | 2026-11-06 | — |

## v10.4.33 (2026-11-22)

- New: пункт `[UI]` — нативное окно `mumu-ui.ps1` (WPF) поверх того же `MuMuManager.exe`, без новых зависимостей и без сети. Карточки устройств показывают Android, состояние и текущий `max_frame_rate`; кнопки запускают, останавливают и перезапускают выбранный инстанс, а лог печатает сырые ответы менеджера.
- New: экран «Настройки устройства» — семь разделов по реальным ключам `setting -v <i> -a` (Производительность, Дисплей, Звук, Сеть, Модель, Для разработчиков, Другие). Разрешение списком как в MuMu (`1920 × 1080, 280 DPI (Планшет)` … `Пользовательский`), готовая модель устройства подставляет бренд, модель и код сразу, рендерер — `Режим Vulkan` / `Режим DirectX` (значения `gles`, `gl`, `opengl`, `directx` менеджер молча отклоняет, проверено чтением обратно).
- New: `Копировать` (`clone`), `Переименовать` (`rename`), `Резервная копия` (`export`), `Восстановить` (`import`) и `Удалить` (`delete -v`) — действия из контекстного меню MuMu, кроме «Очистки диска» и ярлыка на рабочем столе: у `MuMuManager` для них нет команд, и окно их не имитирует.
- Fixed: правка настройки больше не уходит с пустым ключом. Обработчики строк создавались без `GetNewClosure()`, поэтому к моменту клика `$Key` уже не разрешался: в журнал шло `setting 2  = false`, менеджер отвечал `cmd params invalid` / `key not writable`, а значение не менялось.
- Fixed: FPS пишется в `max_frame_rate` через `MuMuManager setting`, а не в `customer_config.json` → `setting.frame_setting.desired_framerate`: файл перезаписывается из хранилища плеера, поэтому «FPS changed: 60 -> 144» не менял «Максимальный FPS» в настройках устройства.
- Fixed: список устройств читается двумя вызовами менеджера (`info -v all` и `setting -v all -k max_frame_rate`) вместо вызова на каждый инстанс, а сохранение настройки читает обратно только свой ключ — окно перестало замирать на каждом действии.
- File: `mumu-ui.ps1` — UTF-8 с BOM и LF, `Parser::ParseFile` чист на PowerShell 5.1 и 7; файл добавлен в `release-files.txt`, в списки набора `mumu-menu.ps1` / `bootstrap-update.ps1` и в фикстуры тестов, ZIP теперь 12 файлов.
- Tests: **381/381** Pester на pwsh, `test-changelog-sync.ps1` и `test-orphan-files.ps1` зелёные.

## v10.4.32 (2026-11-22)

- Fixed: `[U]` больше не рапортует «Up to date» вместо починки. После `Repairing: downloading the release file set` блок лечения маркера больше не срабатывает: локальный `mumu-menu.ps1` совпадал по хэшу с тегом, печаталось `Up to date (v10.4.31)` и функция выходила до цикла скачивания — отсутствующий файл (живой случай: `mumu-f11-probe.ps1`) не появлялся никогда.
- Fixed: набор файлов после докачки перепроверяется по диску, а не по счётчику цикла. Если файл так и не лёг — `Repair failed - N file(s) are still missing: ...`, запись `update-fail` в журнал, `.version` не двигается, код возврата 1. При успехе печатается `Repaired N file(s), up to date (vX.Y.Z)`.
- Fixed: `[RF]` удаляет устройство через `MuMuManager delete -v <index>` и проверяет по `info -v all`, что индекс исчез. Ручное удаление каталогов оставляло «призрак»: менеджер продолжал перечислять устройство, а MuMu рисовал бесконечный спиннер.
- Fixed: `[RF]` больше не удаляет `nx_device\<version>`. Это общий Android-рантайм для всех инстансов версии, и его удаление давало `errcode 60014 "android engine not installed"` — создать устройство было нельзя до переустановки MuMu.
- Fixed: призрак (индекс в списке менеджера, папки `vms` нет) чинится, а не отвергается; выбранный индекс считается существующим, даже если опрос `info -v all` не ответил.
- Fixed: подтверждение `[RF]` принимает `YES` в любом регистре с `Trim()`; приглашение — `Type YES (any case) to repair`, а при отказе печатается введённое значение, так что осечка видна сразу.
- Fixed: неудачное удаление называет пути, которые реально удалены, и те, что остались (`Nothing was deleted - the device is exactly as it was`), вместо прежнего `the deleted folders are gone` на нетронутом устройстве. Резерв удаления папок — один проход с одним повтором после закрытия процессов MuMu, запущенных из этих папок; движок не трогается.
- Tests: **381/381** Pester на pwsh и PowerShell 5.1, `test-changelog-sync.ps1` и `test-orphan-files.ps1` зелёные; живой прогон `[RF]` на MuMu 6.8.9.0 пересоздал инстанс 2 с `errcode 0`.

**EN summary (v10.4.32):** both screens now tell the truth about what happened. `[U]` no longer answers `Up to date` instead of repairing: the marker-heal block, which matched the local menu to the tag by hash and returned before the download loop, is skipped during a repair, and the file set is re-read from disk afterwards - a path that is still missing prints `Repair failed - N file(s) are still missing`, journals `update-fail`, keeps `.version` untouched and exits 1, while a clean repair reports how many files it fetched. `[RF]` removes the device with `MuMuManager delete -v` and confirms through `info -v all` that the index is gone, because deleting the folders by hand left a ghost the manager kept listing and MuMu drew as an endless spinner; it no longer deletes `nx_device\<version>`, which is the Android runtime shared by every instance of that version and whose removal made `create` answer errcode 60014 `android engine not installed`; a ghost (listed index, no vms folder) is repaired instead of refused and the picked index counts as listed even when the info scan times out; a failed delete names the paths that are gone and the ones still there instead of claiming the folders were deleted; and the confirmation takes `YES` in any case, echoes what was typed on refusal, and the folder fallback is one pass with one retry after closing the MuMu processes that hold them. Tests 381/381 on pwsh and PowerShell 5.1, changelog-sync and orphan-files green, and a live `[RF]` run on MuMu 6.8.9.0 recreated instance 2 with errcode 0.

## v10.4.31 (2026-11-22)

- New: пункт `[RF]` «Repair device» — восстановление устройства, когда MuMu отказывается запускаться с `Startup failed: An abnormal runtime environment was detected` (и русской формой «Обнаружена неисправность среды выполнения»). Перед изменениями печатает план: `nx_device\15.0` в папке установки и каталог выбранного инстанса в `vms`, с размерами через `Get-PathSizeMb`, — и только после подтверждения останавливает MuMu и удаляет их, затем пересоздаёт устройство Android 15. Если удалить не удалось, `Get-MumuRepairFailureHint` называет причину (MuMu не закрыт, файл держит процесс) вместо общей ошибки.
- New: `mumu-f11-probe.ps1` — отдельный пробник F11, по умолчанию ничего не разрушающий. Стадии `Prepare` / `Wait` / `Report` / `Cleanup`: свободный индекс начиная с 2, проверка движка 12.0 по каталогу инстанса и `nx_device\*` в конфигах, хэш-снимок инстансов 15.0 до и после с diff, baseline `shell.log` по числу строк и выписка только новых строк по паттернам, `graphics_log` по времени после старта теста, режим монитора через `EnumDisplaySettings` до F11 / после F11 / после Esc и вердикт `EXCLUSIVE` / `BORDERLESS` / `INCONCLUSIVE` в `REPORT.md`. Индексы из `-ProtectedIndexes` (по умолчанию 0 и 1) не затрагиваются, `create` и `delete` — только с `-AllowCreate` / `-AllowDelete`, F11 нажимает пользователь. Строки `lib*.dll` движка 12.0 выгружаются для уточнения паттернов.
- File: `mumu-f11-probe.ps1` записан как UTF-8 с BOM и LF; разбор `Parser::ParseFile` чист на PowerShell 5.1 и 7 (0 ошибок), скрипт добавлен в `release-files.txt`.
- Tests: **375/375** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний, `test-changelog-sync.ps1` и `test-orphan-files.ps1` зелёные.

**EN summary (v10.4.31):** two additions, no behaviour change to the menu paths themselves. `[RF]` gains a working repair for MuMu's `Startup failed: An abnormal runtime environment was detected` (the Russian dialog says «Обнаружена неисправность среды выполнения»): it lists what it is about to touch (`nx_device\15.0` under the install and the selected instance folder under `vms`, with sizes from `Get-PathSizeMb`), asks for confirmation, stops MuMu, deletes those two paths and recreates the Android 15 device, and on failure `Get-MumuRepairFailureHint` names the real cause (MuMu still open, a process holding the files) instead of a generic error. `mumu-f11-probe.ps1` is a separate, non-destructive-by-default F11 probe built as four stages - `Prepare` / `Wait` / `Report` / `Cleanup`: it picks a free index from 2, verifies the instance really runs the 12.0 engine (instance folder name and `nx_device\*` paths in its configs), snapshots the 15.0 instances' config hashes before and after with a diff, records a `shell.log` line baseline and extracts only the new lines matching the fullscreen patterns, filters `graphics_log` by time since the test started, samples the monitor mode with `EnumDisplaySettings` before F11, after F11 and after Esc, and writes a `EXCLUSIVE` / `BORDERLESS` / `INCONCLUSIVE` verdict to `REPORT.md`; indexes in `-ProtectedIndexes` (0 and 1 by default) are never touched, `create`/`delete` need `-AllowCreate`/`-AllowDelete`, and the user presses F11 themselves. The script ships in the ZIP, is stored as UTF-8 with a BOM and LF, and parses clean on PowerShell 5.1 and 7. Tests 375/375 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, changelog-sync and orphan-files green.

## v10.4.30 (2026-11-21)

- Fixed: `mumu-menu.cmd` больше не обещает интерфейс, которого нет. Обёртка документировала глаголы `run`/`start`/`wait`/`status`, ключи `--once`/`--index`/`--restore`/`--deep` и переменные `MUUMU_EXE`/`MUUMU_INDEX`/`MUUMU_RESTORE`, а `mumu-menu.ps1` ничего из этого не объявляет — каждая такая команда падала на `ValidateSet` или на привязке параметров. Теперь `.cmd` — тонкий диспетчер на реальные параметры: `launch`/`stop`/`restart`/`logs` → `-Action`, `--instance`/`--lines`/`--timeout`/`--json`/`--force` → `-Instance`/`-Lines`/`-TimeoutSec`/`-Json`/`-Force`. Неизвестный глагол, неизвестная опция и опция без значения отсекаются самим `.cmd` с кодом 2; без аргументов по-прежнему открывается интерактивное меню, `help` (он же `/?`, `/h`, `-h`, `--help`) печатает те же глаголы и опции.
- Fixed: `[OI]` «Offline installers» падал с `Невозможно вызвать метод для выражения со значением null` на сетях, где страница релиза отдавала относительную ссылку на установщик. `[System.Uri]($page).AbsoluteUri` разбирается как `[System.Uri](($page).AbsoluteUri)`: у строки такого члена нет, приведение возвращает `$null`, и следующий `.TrimEnd()` падает. Обе ветки — `.exe` и `.dmg` — теперь строят адрес через `[System.Uri]::new([System.Uri]$page, $href)`, что заодно правильно разрешает и корневые (`/MoMu/...`), и страничные (`MuMu.dmg`) ссылки. Новый тест держит запрет на старую форму и оба случая разрешения.
- New: экран запуска объясняет отказ эмулятора, а не только пересказывает его. На `Startup failed: An abnormal runtime environment was detected` и его русскую форму «Обнаружена неисправность среды выполнения» (это проверка виртуализации: VT-x выключен или занят Hyper-V/VBS и Core Isolation) меню сразу возвращается без 120-секундного ожидания и печатает порядок действий: кнопка «Восстановить» на этом экране не помогает (проверено), поэтому нужно удалить каталог `nx_device\15.0` в папке MuMu (например `C:\Program Files\Netease\MuMuPlayer\nx_device\15.0`) и папку инстанса в `vms` (например `MuMuPlayerGlobal-15.0-0`), а затем создать устройство заново (New → Create Device → Android 15); если ошибка повторится на новом устройстве — VT-x в «Диспетчере задач» (Производительность → ЦП → Виртуализация: Включено), Hyper-V / Windows Hypervisor Platform / Virtual Machine Platform, Core Isolation → Memory integrity, затем перезагрузка. Та же подсказка появляется при истечении ожидания загрузки и в пакетном `launch`/`restart` (то есть у `mumu-menu.cmd launch`); незнакомый вывод не додумывается — остаётся только строка ошибки.
- Tests: **363/363** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний; изменился только `.cmd` и две строки склейки URL в `[OI]`.

**EN summary (v10.4.30):** both fixes are small and local. `mumu-menu.cmd` no longer documents the invented `run`/`start`/`wait`/`status` verbs, the `--once`/`--index`/`--restore`/`--deep` flags or the `MUUMU_*` variables: it dispatches `launch`/`stop`/`restart`/`logs` onto `-Action` and `--instance`/`--lines`/`--timeout`/`--json`/`--force` onto the `-Instance`/`-Lines`/`-TimeoutSec`/`-Json`/`-Force` parameters, rejects an unknown verb, an unknown option or an option without a value with exit code 2, keeps the bare-call interactive menu, and passes the script's own exit code through. In `[OI]`, a relative installer link is resolved with `[System.Uri]::new([System.Uri]$page, $href)` instead of `[System.Uri]($page).AbsoluteUri`, which PowerShell parses as `[System.Uri](($page).AbsoluteUri)`, yields `$null` and makes the following `.TrimEnd()` die with "You cannot call a method on a null-valued expression"; both the `.exe` and the `.dmg` branch are fixed, and a test pins the call shape plus root-relative and page-relative resolution. The launch screens now also explain MuMu's own "Startup failed: An abnormal runtime environment was detected" and the Russian dialog it actually shows ("Обнаружена неисправность среды выполнения"): that sentence is the emulator's virtualization check (VT-x off, or taken by Hyper-V/VBS and Core Isolation), so the screen returns at once instead of waiting out the 120 s boot timeout, and lists the repair that works (its Restore button does not: delete `nx_device\15.0` under the MuMu install and the instance folder under `vms`, then create the device again from New > Create Device > Android 15; if it comes back, VT-x in Task Manager > Performance > CPU, Hyper-V / Windows Hypervisor Platform / Virtual Machine Platform, Core Isolation > Memory integrity, then a reboot); the same hint follows a boot timeout and a batch `launch`/`restart` failure, and output the menu cannot explain is not guessed at. Tests 363/363 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings.

## v10.4.29 (2026-11-21)

- Docs+hardening: шапки вспомогательных скриптов приведены к тому, что код реально делает, и там, где скрипт пишет на диск, появился режим без записи:
  - `Watch-MumuConnections.ps1` — «Read-only for the network stack» и `-NoLog`; единственная запись идёт через `Add-WatchLine`, при `-NoLog` не создаётся даже сам файл лога.
  - `Diag-MumuNx.ps1` — убрано обещание «WHOIS-lite» (код делает только reverse-DNS PTR); сказано, что отчёт пишется в `%PUBLIC%` и его может прочитать любой локальный пользователь; добавлен `-NoFile`: вывод только в консоль.
  - `Test-MumuTunnelAB.ps1` — заявка «READ-ONLY» сужена до сетевого стека и перечислены реальные файлы (`snapshot-*.json`, `diff-<A>-vs-<B>.txt` в `%TEMP%\mumu-ab`); добавлен `-NoSave`: снимок и отчёт остаются в памяти, каталог не создаётся.
  - `mmor-run.ps1` — шапка объясняет, что C#-хелпер компилируется `Add-Type` (csc.exe на 5.1, в памяти на 7) и не скачивается как DLL, а единственная запись — файл калибровки `mmor-run.json`; добавлен `-NoWrite`.
  - `bootstrap-update.ps1` — загрузка по `https://` запинена на HTTPS (`--proto '=https' --proto-redir '=https'`), `file://`-фикстуры не затронуты; в шапке сказано, что переподпись использует существующий сертификат и никогда не пишет в хранилища Root/CA/AuthRoot.
- `mumu-menu.ps1`: в блок SIGMA RULE EXCLUSIONS добавлено правило `Dynamic CSharp Compile Artefact` — описаны оба класса из `Add-Type` (`MuMuMenuCtrlCGuard` для Ctrl+C, `MuMuWindowGrid` для сетки окон `[L]`) и то, что `%TEMP%`-артефакты создаёт сам компилятор. Правило `Suspicious Process Discovery With Get-Process` уточнено: кроме `-Name 'MuMu*'` есть один `-Id`-запрос за путём EXE апдейтера, без перечисления чужих процессов.
- Tests: **355/355** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний, `test-changelog-sync.ps1` и `test-dependency-overrides.ps1` зелёные. Новые тесты держат `-NoLog`/`-NoFile`/`-NoSave`/`-NoWrite` и точность формулировок в шапках.

**EN summary (v10.4.29):** the helper-script headers now say what the code actually does, and every script that writes to disk gained a no-write mode. `Watch-MumuConnections.ps1` scopes its read-only claim to the network stack and adds `-NoLog` (the only write is `Add-WatchLine`; with `-NoLog` even the log file is not created). `Diag-MumuNx.ps1` drops the unearned "WHOIS-lite" claim for the reverse-DNS (PTR) lookup it really performs, says the `%PUBLIC%` report is readable by every local user, and adds `-NoFile`. `Test-MumuTunnelAB.ps1` narrows its read-only claim to the network stack, lists the snapshot and diff files it writes under `%TEMP%\mumu-ab`, and adds `-NoSave`, which keeps the snapshot and report in memory. `mmor-run.ps1` explains that its C# helper is compiled by `Add-Type` (csc.exe on 5.1, in memory on 7) rather than downloaded as a DLL, names `mmor-run.json` as its only write, and adds `-NoWrite`. `bootstrap-update.ps1` pins `https://` downloads to HTTPS (`--proto '=https' --proto-redir '=https'`, leaving `file://` fixtures alone) and states that re-signing reuses the existing certificate and never writes to the Root/CA/AuthRoot stores. In `mumu-menu.ps1` the SIGMA RULE EXCLUSIONS block gains the `Dynamic CSharp Compile Artefact` rule, describing both `Add-Type` classes and the compiler's own `%TEMP%` scratch files, and its `Get-Process` note now also covers the single `-Id` lookup for an updater's EXE path. Tests 355/355 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, changelog-sync and dependency-overrides green.

## v10.4.28 (2026-11-21)

- Fixed: `[OI]` «Offline installers (all versions, read-only)» больше не выдаёт недоступный Android-пакет за найденный файл. Когда ни один из CDN-хостов (`a11.gdl.easebar.com`, `a11.gdl.netease.com`) не вернул ни `Content-Length`, ни дайджеста, печаталась только строка `integrity ... headers did not expose a digest/length for this path`, которую легко прочитать как «файл найден, просто заголовки скупые». Теперь в этом случае выводится явная пометка `APK not reachable from here - no Content-Length or digest came back from either CDN host` — так же честно, как у архива Windows-установщиков (`down.mumuplayer.com`).
- Прежняя формулировка `integrity` сохранена для случая, когда хост всё же ответил, но только редиректом (`canonical`) или именем файла: путь существует, а длины и хеша в заголовках просто нет — объявлять его недоступным было бы неправдой.
- Функция по-прежнему read-only: HEAD-запросы и вывод, без загрузок и записи файлов.
- Tests: **343/343** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний, `test-changelog-sync.ps1` и `test-dependency-overrides.ps1` зелёные, разбор скрипта без ошибок в обоих движках. Добавлен тест `marks the APK as not reachable when neither a length nor a digest came back`: он держит обе ветки — явный маркер недоступности и сохранённую строку `integrity`.

**EN summary (v10.4.28):** `[OI]` no longer presents an unreachable Android package as a found file. When neither CDN host (`a11.gdl.easebar.com`, `a11.gdl.netease.com`) returned a `Content-Length` or a digest, the screen printed only the `integrity ... headers did not expose a digest/length for this path` line, which reads like a file with thin headers. That case now prints `APK not reachable from here - no Content-Length or digest came back from either CDN host`, as plainly as the Windows signing archive already does. The `integrity` wording stays for a host that did answer, but only with a redirect (`canonical`) or a filename: the path exists, the length and hash are just not in the headers. Discovery remains read-only - HEAD requests and printing only. Tests 343/343 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, changelog-sync and dependency-overrides green, parse clean on both engines; the new test pins both branches.

## v10.4.27 (2026-11-21)

- Fixed: `[OI]` «Offline installers (all versions, read-only)» снова показывает список на сетях, где не открывается `www.mumuplayer.com`. Раньше экран был пустым: страница релиза была обязательной, и функция возвращалась сразу после её неудачной загрузки; ссылка на Windows терялась и по второй причине — HEAD через `Invoke-WebRequest` не отдаёт `Location` при `-MaximumRedirection 0` (5.1 бросает `InvalidOperationException` вообще без `Response`, 7 отдаёт `HttpResponseMessage` с пустым `Headers['Location']`), а автопереход по 302 на CDN виснет до таймаута.
- Резолверы переписаны на сырой `HttpClient`: `AllowAutoRedirect = $false`, браузерный `User-Agent` (без него CDN принимает соединение и не отвечает), таймаут поднят с 8 до 12 с. `Location` разбирается вручную и передаётся в запрос за именем файла (из `Content-Disposition`) и размером, поэтому бейджи `name:`/`size:` снова появляются, а не только голая ссылка.
- Страница релиза стала необязательным источником: при недоступности печатается предупреждение со ссылкой на `www.mumuplayer.com/update/`, а список из API-резолверов остаётся на экране. Ранний `return` убран.
- APK проверяется на обоих CDN-хостах (`a11.gdl.easebar.com` и `a11.gdl.netease.com`): раньше проверялся только один, и на сети, где он не отвечает, пункт выглядел отсутствующим. У архива — один HEAD на базовый хост, затем документированный шаблон путей, то есть без трёх последовательных таймаутов.
- Функция остаётся read-only: только HEAD-запросы и вывод, без загрузки и записи файлов; тесты по-прежнему требуют отсутствия `Invoke-RestMethod`, `MumuManager` и `adb` в теле функции.
- Tests: **342/342** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний, разбор скрипта без ошибок в обоих движках, `mumu-menu.ps1` и набор тестов остаются с UTF-8 BOM и LF. Добавлен тест `keeps listing when the release page is unreachable`; два существующих обновлены под контракт HEAD (`HttpMethod]::Head`, `AllowAutoRedirect = $false`, `TryAddWithoutValidation('User-Agent'`, оба APK-хоста). Живой прогон на этой сети: Windows `MuMu_6.0.2_1329zT3C.exe` (6 102 432 Б) и macOS `MuMuPlayer_1.9.15_default_1329Ay2C.dmg` (761 308 578 Б) перечисляются, APK и `down.mumuplayer.com` недоступны и честно помечены.

**EN summary (v10.4.27):** `[OI]` («Offline installers (all versions, read-only)») listed nothing on networks that cannot open `www.mumuplayer.com`. The release page was mandatory, so its failure ended the function before the resolvers ran; the Windows link was lost anyway, because `Invoke-WebRequest` cannot report an unfollowed redirect - PowerShell 5.1 throws with no response at all, 7 returns an `HttpResponseMessage` whose `Location` header reads empty - and following the 302 to the CDN automatically hangs until the timeout. The resolvers now build a raw `HttpClient` HEAD with `AllowAutoRedirect = $false` and a browser `User-Agent` (without it the CDN accepts the connection and never answers), raise the deadline from 8 s to 12 s, and follow `Location` by hand for the `Content-Disposition` name and the length, so the `name:`/`size:` badges are back instead of a bare link. The release page is optional now: an unreachable page prints a warning with a link and the resolver listing stays. The APK is probed on both CDN hostnames instead of one, and the archive costs a single HEAD on the base host followed by the documented path template rather than three timeouts. Discovery remains read-only - HEAD requests and printing only, and the tests still forbid `Invoke-RestMethod`, `MumuManager` and `adb` in the function body. Tests 342/342 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, parse clean on both engines; a new `keeps listing when the release page is unreachable` test came with two updated ones, and a live run lists the Windows exe (6,102,432 bytes) and the macOS dmg (761,308,578 bytes) while marking the unreachable APK and `down.mumuplayer.com` as such.

## v10.4.26 (2026-11-21)

- Tests: в `tests/mumu-menu.Tests.ps1` добавлен `Describe 'mmor-run.ps1 calibration template'` — десять тестов на генератор `mmor-run.json`, который появился в v10.4.25 и до сих пор проверялся только руками. Функции (`Format-MmorNumber`, `Format-MmorPair`, `Read-MmorConfig`, `Write-MmorConfigTemplate`) берутся из настоящего `mmor-run.ps1` через AST, как и остальной набор, поэтому проверки идут офлайн: без эмулятора, без перечисления окон и без кликов.
- Покрыто поведение шаблона: `recorderButton` подставляется из `kToolMenu.kToolMenuBtn`, а `playButton` и `fileRow` остаются пустыми, `delays` — 2500/800/500; поле `_comment` действительно называет `playButton` и `-Record`; файл пишется UTF-8 **без BOM** с переводом строки в конце.
- Покрыто и то, что легко сломать при следующей правке: числа форматируются через точку даже в культуре с десятичной запятой (`de-DE`), отсутствующая или одноэлементная пара рендерится как `null`, а не `0,0`; без окна и без базы `recorderButton` тоже `null`; обновление шаблона сохраняет уже снятые `playButton`, `fileRow` и `delays`; свежевыведенный `recorderButton` перекрывает сохранённый; записанное читается обратно через `Read-MmorConfig`.
- Tests: **341/341** Pester на pwsh и PowerShell 5.1, PSScriptAnalyzer — 0 замечаний по файлу тестов; deployed-layout фикстура (`tests/test-deployed-layout.ps1`) — **337/337** на обоих движках, 4 теста с тегом `RepoFiles` в ней не запускаются по замыслу, пропусков (`Skipped`) нет. Кода и поведения в этом выпуске не менялось.

**EN summary (v10.4.26):** tests only. A new `Describe` in `tests/mumu-menu.Tests.ps1` pins the `mmor-run.json` writer added in v10.4.25, which until now was checked by hand only: `recorderButton` comes from `kToolMenu.kToolMenuBtn`, `playButton` and `fileRow` stay empty, `delays` default to 2500/800/500, the `_comment` field really names `playButton` and `-Record`, and the file is written as UTF-8 without a BOM with a trailing newline. It also pins what is easy to break next: numbers keep a dot even under a comma-decimal culture (`de-DE`), a missing or single-element pair renders as `null` rather than `0,0`, a missing window leaves `recorderButton` `null`, a refresh keeps the captured `playButton`/`fileRow`/`delays`, a freshly derived `recorderButton` wins over the stored one, and the result round-trips through `Read-MmorConfig`. The functions are AST-extracted from the real script, so the suite stays offline - no emulator, no window enumeration, no clicks. Tests 341/341 on pwsh and PowerShell 5.1, PSScriptAnalyzer 0 findings, and 337/337 in the deployed-layout fixture on both engines (4 `RepoFiles`-tagged tests are not run there by design; nothing is skipped). No code or behaviour changes.

## v10.4.25 (2026-11-20)

- New: `mmor-run.ps1` сам создаёт шаблон `mmor-run.json` — больше не нужно собирать его руками по выводу `-Record`. Файл пишется при `-EmitConfig` и автоматически, если его нет (`-Probe` или обычный запуск), после чего сразу печатается «Click plan» уже по нему.
- `recorderButton` подставляется автоматически: точка берётся из UIA-элемента `kToolMenu.kToolMenuBtn` (единственного со стабильным `AutomationId`) и нормализуется по прямоугольнику окна инстанса. Если запущенного инстанса нет, значение остаётся `null`, а в консоли сказано запустить инстанс и повторить `-EmitConfig` — в «нулевые» координаты скрипт не стреляет.
- `playButton` остаётся `null` намеренно: кнопки рекордера не публикуют ни имени, ни `AutomationId`, поэтому вторую пару по-прежнему даёт `-Record`. Пояснение лежит в самом файле в поле `_comment` (не в комментариях JSON: `ConvertFrom-Json` в PowerShell 5.1 их не разбирает). `-Apply` в таком состоянии останавливается с `playButton is missing`, а не жмёт в угол окна.
- Обновление через `-EmitConfig` не затирает уже снятые пары: `playButton`, `fileRow` и `delays` сохраняются, обновляется только вход в рекордер. Об этом же дописан абзац в шапке скрипта и в `SKILL.md` (подраздел `### Operation recording (.mmor)`).
- Tests: 331/331 Pester, PSScriptAnalyzer по `mmor-run.ps1` — 0 замечаний; разбор скрипта без ошибок в PowerShell 7 и 5.1, `mmor-run.ps1` остаётся с UTF-8 BOM и LF. Живой прогон на остановленном инстансе: шаблон создан, JSON валиден, обновление сохранило уже снятые пары.

**EN summary (v10.4.25):** `mmor-run.ps1` now writes the `mmor-run.json` template itself, so it no longer has to be assembled by hand from `-Record` output. The file is written by `-EmitConfig` and automatically on a run that finds none, and the click plan is then printed from it. `recorderButton` is filled in from the instance title bar's `kToolMenu.kToolMenuBtn` - the one control with a stable AutomationId - normalized against the instance window rectangle; with no running instance it stays `null` and the script says to start one and re-run `-EmitConfig` instead of clicking guessed coordinates. `playButton` stays `null` on purpose, because the recorder's buttons expose neither a name nor an id, so the second pair still comes from `-Record`; the reason sits in the file's `_comment` field (JSON has no comments, and PowerShell 5.1's `ConvertFrom-Json` rejects `//`). A refresh keeps pairs that were already captured - only the recorder entry is recalculated - and `-Apply` refuses to press an unset point. The header and the `SKILL.md` section say the same. Tests 331/331, PSScriptAnalyzer 0 findings, parse clean on PowerShell 7 and 5.1; a run against a stopped instance produced a valid template and preserved the captured pairs.

## v10.4.24 (2026-11-20)

- Docs: пункт про `mmor-run.ps1` в «Возможностях» README сокращён до двух предложений. В нём осталось главное: `-Apply -File x.mmor` — это GUI-автоматизация мышью (курсор + `mouse_event` по окну Operation Recorder, поэтому зависит от позиции окна, DPI, фокуса и таймингов), и нативной команды для `.mmor` у MuMu нет — воспроизведение живёт только в GUI.
- Детали ушли в `SKILL.md`, подраздел `### Operation recording (.mmor)`: три режима скрипта, отсутствие вербов `mmor`/`script`/`play` в `MuMuManager.exe` 6.8.9.0 и обе альтернативы без мыши — автозапуск записи при старте инстанса («模拟器启动后自动执行 / Auto-execute upon starting the device» + `control -v <n> launch`/`restart`) и ввод через `control -v <n> tool cmd -c "input tap X Y"`.
- Поведение не менялось: правка только в документации. Tests: 331/331 Pester, PSScriptAnalyzer — 0 замечаний; версия поднята вместе в `relnotes.md`, `.version`, `$scriptVer` и `package.json`/`package-lock.json`.

**EN summary (v10.4.24):** docs only. The `mmor-run.ps1` bullet in the README feature list is down to two sentences: `-Apply -File x.mmor` is GUI mouse automation (cursor plus `mouse_event` on the Operation Recorder window, so window position, DPI, focus and timing all matter), and MuMu has no native `.mmor` verb - playback lives only in the GUI. The details - the three modes, the missing `mmor`/`script`/`play` verbs in `MuMuManager.exe` 6.8.9.0 and both mouse-free workarounds (auto-execute on launch plus `control launch`/`restart`, and `control tool cmd -c "input tap X Y"`) - now live in `SKILL.md` under `### Operation recording (.mmor)`. No behaviour changes: tests 331/331, PSScriptAnalyzer 0 findings; the version is bumped together in `relnotes.md`, `.version`, `$scriptVer` and `package.json`/`package-lock.json`.

## v10.4.23 (2026-11-20)

- Docs: `mmor-run.ps1` теперь прямо говорит в шапке, что `-Apply` — это GUI-автоматизация мышью, а не вызов API: режим двигает курсор на окно Operation Recorder и шлёт туда `mouse_event`, поэтому результат зависит от позиции окна, DPI, фокуса и таймингов. Годится как временный обход, но не как интеграция.
- Там же зафиксировано, что нативной команды для `.mmor` у MuMu нет: у `MuMuManager.exe` 6.8.9.0 нет вербов `mmor`/`script`/`play` (`control` = `launch shutdown restart show_window hide_window layout_window app tool shortcut`), а воспроизведение живёт только в GUI `MuMuNxMain` (`ScriptManagerPresenterImpl[runScript]`, `OperationRecorderExecute`) — ни pipe, ни endpoint запись не принимает.
- В заметке перечислены поддерживаемые альтернативы без мыши и без перехвата фокуса: у файла записи включить «模拟器启动后自动执行 / Auto-execute upon starting the device» и вызывать `control -v <n> launch` (или `restart`) — нативное воспроизведение, но один скрипт на инстанс и только при старте; либо `control -v <n> tool cmd -c "input tap X Y"` — ввод через собственный канал MuMu, но это повтор ваших тапов, а не проигрывание `.mmor`.
- То же самое добавлено в README (пункт в «Возможности») и в `SKILL.md` (подраздел `### Operation recording (.mmor)`), чтобы ограничение было видно до запуска, а не после.
- Кода это не касается: меняются только комментарии и документация, поведение `-Probe`/`-Record`/`-Apply` прежнее. Tests: 331/331 Pester, PSScriptAnalyzer — 0 замечаний, `mmor-run.ps1` остаётся с UTF-8 BOM и LF.

**EN summary (v10.4.23):** docs only. `mmor-run.ps1` now states in its header that `-Apply` is GUI automation - it moves the cursor onto the Operation Recorder window and sends mouse events there, so window position, DPI, focus and timing all affect the result, which makes it a stopgap rather than an integration. The same note records that MuMu exposes no native `.mmor` command: `MuMuManager.exe` 6.8.9.0 has no `mmor`/`script`/`play` verb, playback lives only in the `MuMuNxMain` GUI, and no pipe or endpoint accepts a recording. It also points at the two mouse-free options - "Auto-execute upon starting the device" plus `control -v <n> launch` (or `restart`), and `control -v <n> tool cmd -c "input tap X Y"` - and the note is mirrored in the README feature list and in `SKILL.md`. No code changes: tests 331/331, PSScriptAnalyzer 0 findings.

## v10.4.22 (2026-11-19)

- Fixed: `[L]` считал «исходным» текущий размер окна, а MuMu хранит геометрию инстанса у себя (`<vms>/<инстанс>/configs/customer_config.json`) и переоткрывает окно с неё. После первого сжатия уменьшенный размер становился новым «исходным», и каждый следующий прогон уменьшал окна ещё сильнее — в итоге одно окно становилось крошечным, и вернуть его было нечем. Теперь база берётся из конфига (`setting.player.window` / `window_landscape` / `window_vertical`, `-1` = «авто» пропускается), к сохранённому клиентскому размеру возвращаются рамка и заголовок живого окна, и перед раскладкой окно восстанавливается до размера, с которым его открывает MuMu.
- Правила раскладки не изменились: `scale = min(1, (W-2M-(C-1)G)/(C*w), (H-2M-(R-1)G)/(R*h))`, M = G = 10 px, `C = min(окон в ряд, N)`, `R = ceil(N/C)`, порядок слева направо и сверху вниз, однократный подъём наверх без always-on-top. Если конфиг недоступен или в нём только `-1`, базой остаётся живой прямоугольник — то есть поведение на «чужих» раскладках прежнее.
- Tests: пять новых Pester-тестов (`Get-SavedWindowSize` на фикстурах конфига и контракт `Set-WindowLayout`), набор 331/331 на pwsh и 5.1. Живая проверка: развёрнутое окно 1936×1048 даёт базу 966×519 (958×515 клиент + рамка), после ручного сжатия до 500×300 база не изменилась, окно восстановилось в 966×519.

**EN summary (v10.4.22):** `[L]` treated the live rectangle as the original size, while MuMu keeps each instance's window geometry in `customer_config.json` and reopens at that size - so the first shrink became the new original and every later run shrank the wall a little more, until a window was too small to use. The base is read from the instance config now (`setting.player.window` / `window_landscape` / `window_vertical`, skipping `-1` auto pairs), the live chrome is added back to the saved client size, and a shrunken window is restored before the grid is applied. Layout rules are unchanged: one `min(1, ...)` scale, 10 px margin and gap, left to right and top to bottom, a single raise, no always-on-top. Unreadable config falls back to the live rectangle.

## v10.4.21 (2026-11-19)
- Fixed: `mmor-run.ps1` не попал в ZIP релиза 10.4.20. Архив собирается не «по всему тегу», а ровно по списку `release-files.txt` — новый файл, не внесённый в этот список, в архив не попадает, и в 10.4.20 их оказалось 9 вместо 10. Файл добавлен в `release-files.txt` и в оба автообновляемых списка (`mumu-menu.ps1` и `bootstrap-update.ps1`), в whitelist восстановления `Repair-Installation` и в набор `Build-RollbackPlan`; теперь он есть и в архиве, и в наборе `[U]`.
- Гейты: проверка ZIP ждёт `file set: OK (10 files)`; фикстуры развёрнутой установки, откатa и проверки дрейфа дополнены новым файлом — иначе его отсутствие в тестовом каталоге выдавалось за дрейф.
- Tests: 326/326 Pester, `test-bootstrap-update.ps1` и `test-deployed-layout.ps1` зелёные на pwsh и 5.1, PSScriptAnalyzer по репозиторию — 0 замечаний.

**EN summary (v10.4.21):** the 10.4.20 archive was missing `mmor-run.ps1`. The release ZIP is assembled from the explicit `release-files.txt` list rather than from the whole tag, so a new file ships only once it is named there - and the 10.4.20 archive held 9 of the 10 files. The file now appears in `release-files.txt`, in both updater lists (`mumu-menu.ps1`, `bootstrap-update.ps1`), in the `Repair-Installation` whitelist and in the `Build-RollbackPlan` file set, so it arrives in the ZIP and through `[U]`. The ZIP guard now expects `file set: OK (10 files)`, and the deployed-layout, rollback and drift fixtures were widened so a missing row cannot be mistaken for drift.

## v10.4.20 (2026-11-19)
- New: `mmor-run.ps1` — первый шаг к нативному запуску `.mmor` из командной строки. MuMu не даёт для этого ни команды, ни канала: у `MuMuManager.exe` нет ни `script`, ни `play`, а интерфейс рекордера не публикует имена — у меню инстанса 17 пунктов с пустыми `Name`/`AutomationId`, у кнопок рекордера только прямоугольники. Поэтому скрипт работает с тем, что интерфейс действительно отдаёт, и в трёх режимах: `-Probe` печатает окна инстанса и его UIA-элементы (`kToolMenu.kToolMenuBtn`, `kWinMini.kWinMiniBtn`, координаты и размеры) и ничего не нажимает; `-Record` печатает окно и нормализованную точку каждого вашего клика, чтобы один раз снять координаты «Operation Recorder» и «Play»; `-Apply -File farm.mmor` фокусирует окно инстанса, открывает рекордер по этой точке, ждёт появления нового окна, при желании дважды кликает по строке файла и жмёт Play.
- Безопасность: по умолчанию скрипт только осматривает. `-Apply` требует существующий `.mmor`, ровно один инстанс и заполненный `mmor-run.json`; при неверной точке он падает с `no new window appeared within N s` (или `recording not found` / `No calibration config`), а не кликает наугад. Факт воспроизведения по списку окон не проверяется — это прямо сказано в выводе, поэтому «playback started» скрипт никогда не рапортует.
- Ограничение: `mmor-run.ps1` не был включён в автообновляемый набор `[U]`, а в ZIP 10.4.20 его вообще не оказалось (архив собирается по явному списку) — исправлено в v10.4.21, где файл есть и в архиве, и в `[U]`.
- Tests: набор 326/326, PSScriptAnalyzer по новому скрипту — 0 замечаний, BOM/LF на месте. Живая проверка: probe нашёл 20 элементов у окна инстанса и 40 у шелла, калибровочный слушатель поймал клик и напечатал `normalized: [0.7789, 0.8664]`, `-Apply` с точкой по заголовку честно упёрся в «no new window».

**EN summary (v10.4.20):** `mmor-run.ps1` is the first step toward native `.mmor` playback from a command line. MuMu offers neither a command nor a channel for it: `MuMuManager.exe` has no `script`/`play` verb, and the recorder UI publishes no names - the instance menu has 17 items with empty `Name`/`AutomationId` and the recorder buttons expose only rectangles. The script therefore works with what the UI does expose, in three modes: `-Probe` prints the instance windows and their UI Automation elements (ids, rectangles) and presses nothing; `-Record` prints the window and the normalized point of every click the user makes, so the "Operation Recorder" and "Play" coordinates can be captured once; `-Apply -File farm.mmor` focuses the instance window, opens the recorder at that point, waits for a new window, optionally double-clicks the file row and presses Play. `-Apply` refuses to run without an existing `.mmor`, a single instance and a filled-in `mmor-run.json`, and stops with `no new window appeared within N s` instead of clicking at a guess; playback is never reported as started, only that the clicks were sent.

## v10.4.19 (2026-11-19)

- Fixed: `[G]` live-логи больше не возвращают в меню с пустым экраном. Поток открывался с подсказкой снапшота (`logcat -d`), поэтому мост MuMu, который отвечает на эхо-пробу, но ещё не подключил logcat, закрывался сразу с нулём строк — и экран LIVE оставался пустым. Live-ветка больше не передаёт `-d`/`-t`, а пустой прогон перезапускается до трёх раз; после третьего отказа печатается транспорт, число попыток и подсказка на снапшот `[2]`.
- Fixed: `Get-InstanceIndex` на нецифровой ввод (случайный `-` или опечатка) повторяет запрос с диапазоном `Enter an instance number (0-1) or q to cancel.` вместо ложного `Instance - not found!`.
- Проверка: живой прогон на MuMu 6.8.9.0, инстанс 0 (Android 15) — `[G]` → `0` → `[3]` → `[1] All`: поток шёл непрерывно больше шести минут (лог Android 07:40:16→07:46:02), в меню не возвращался. Сырой мост `MuMuManager.exe adb --vmindex 0 --cmd "logcat -v time *:*"` отдал 11 411 строк за 13 с и не завершился, то есть на этой сборке дело было в аргументах снапшота, а не в мосте.
- Tests: два новых Pester-теста — повтор запроса инстанса и отсутствие `-d` в live-аргументах; ещё четыре — на сетку окон и закрытие всех; набор 326/326 на pwsh и 5.1, PSScriptAnalyzer без замечаний.
- New: `[L]` раскладывает окна запущенных инстансов в сетку с выбором числа окон в ряд (2-6, по умолчанию 3). Размер берётся из рабочей области экрана (без панели задач) с полями 10 px и зазором 10 px: `scale = min(1, (W-2M-(C-1)G)/(C*w), (H-2M-(R-1)G)/(R*h))`. Единица в `min` — это и есть правило «не увеличивать»: окна, которые уже помещаются, только переставляются, мелкие остаются мелкими, а пропорции сохраняются, потому что и ширина, и высота умножаются на один коэффициент. Раскладка идёт слева направо и сверху вниз (margin 10 px от краёв), после неё окна один раз поднимаются наверх штатным `control -v all show_window` — без always-on-top, другие программы снова могут их перекрыть. Ответ `a` оставлен для встроенного `layout_window`.
- Changed: `[D]` закрывает все запущенные инстансы одним вызовом `control -v all shutdown` и проверяет результат по фактическому состоянию. Шесть игроков закрылись за ~18 с одним round trip вместо шести последовательных `shutdown_player` с паузой после каждого; зависший инстанс честно остаётся в строке «still running after 60 s».

## v10.4.18 (2026-11-12)

- `[U]` больше не скрывает причину сбоя. В `Update-FromGitHub` блок `catch` увеличивал счётчик неудач, но не записывал ни имя файла, ни сообщение движка — журнал получал строку вида `0 ok, 8 failed ()`. Именно так выглядел прогон, у которого анонимный лимит GitHub API (60 запросов в час) закончился посреди обновления: на экране было «Update finished with 8 failed file(s)», в журнале — пустые скобки, и отличить лимит от сетевого сбоя или отказа хеш-гейта было нечем.
- Теперь каждая неудача идёт в журнал и на экран как `<файл>: <причина>`; промахи пост-верификации добавляются тем же списком (`missing after download`, `hash mismatch`). Размеры успешно скачанных файлов остались в `$fileResults`, причины — в отдельном `$failedFiles`, поэтому формат события `update-ok` не изменился.
- Проверка: под pwsh 7 в песочнице прогнан полный апдейт (`.version` на предыдущем теге, локально подпорченный `mumu-menu.ps1`) — все файлы скачаны, `mumu-menu.ps1` выложен как `.new`, `.version` поднят до метки релиза, журнал `update-ok`; следующий запуск применяет `.new`, и файл совпадает с содержимым тега; тот же сценарий на 5.1 дал те же восемь загрузок и `update-ok`. Прогон без токена при исчерпанном лимите теперь журналирует `2 ok, 6 failed (SKILL.md: API rate limit exceeded …; README.md: …)`, а `.version` не двигается. Плюс три новых Pester-теста на список неудач; набор 320/320 на pwsh и 5.1.

- `[2]`/`[3]`/`[4]` больше не падают со служебным тексом `The expression after '&' in a pipeline element produced an object that was not valid`. Так выглядел общий `trap`: путь к `MuMuManager.exe` проверялся только на старте, и если к моменту выбора пункта копия была перемещена или удалена (а `[IN]` мог переключить сессию на уже несуществующую установку), первая же строка `& $MumuPath info -v all` уходила в исключение до вывода списка инстансов.
- Проверка пути добавлена в `Get-InstanceIndex` и `Invoke-Mumu`: вместо исключения печатается `MuMuManager.exe not found - pick a valid install with [IN] or set $MumuPath.`, функция возвращает `$null`/ничего, меню остаётся открытым.
- Проверка: обе функции выделены из AST и вызваны с мёртвым и с пустым путём — сообщение печатается, исключения нет; сквозной прогон `[2]` с рабочей установкой по-прежнему выводит список инстансов; анализатор без замечаний.

## v10.4.16 (2026-11-06)

- `[G]` различает три состояния инстанса: `RUNNING ✓`, `STARTING ◐` (плеер поднят, Android грузится) и `STOPPED ○`. Раньше `starting_rom` отображался как остановленный, и logcat объявлялся недоступным на живой виртуалке.
- На незапущенном инстансе `[2]`/`[3]` предлагают запустить его и дожидаются загрузки, после чего сразу открывают logcat — вместо возврата в меню.
- Подсказка больше не ссылается на `[2]` как на Launch: `[2]` — это снапшот logcat, запуск живёт в главном меню.
- `[MU]` больше не зависает на чтении страницы: у `Invoke-WebRequest` в 5.1 `-TimeoutSec` ограничивает только заголовки, тело читается с `ReadWriteTimeout` (300 с), а прогресс-бар не прерывается Ctrl+C. Страницы тянутся через `Get-WebText` на `HttpClient` с дедлайном на весь обмен.
- Ctrl+C в `[G]` больше не отдаётся хосту: обработчик выставляет `e.Cancel = true`, поток завершается убийством дерева процессов, ридер выходит по EOF — меню возвращается сразу и ничего не печатает поверх него.
- Добавлен неинтерактивный режим: `-Action launch|stop|restart|logs` с `-Instance all|0|0,2`, `-Lines`, `-TimeoutSec` и `-Json`. Ни одного вопроса, результат проверяется по фактическому состоянию инстанса, код возврата `0` только при успехе по всем целям; стартовые баннер и проверка обновлений на этом пути пропускаются.
- Проверка: наборы зелёные (317/317 на pwsh и 5.1).

## v10.4.14 (2026-11-04)

- После Ctrl+C в live-логах `[G]` сразу открывается главное меню: пауза «Press any key to continue...» для этого выхода убрана (флаг `$script:SkipContinuePause`), остальные действия её сохраняют.
- Проверка: статические тесты на флаг и его обработку в главном цикле; целевые наборы зелёные на 5.1 и pwsh.
## v10.4.13 (2026-11-04)

- Ctrl+C в `[G]` больше не требует второго нажатия: обработчик убивает дерево процессов (`taskkill /F /T`), а нативный `logcat -c` после прерывания не запускается — он висел на остановленном конвейере.
- Проверка: статические тесты на tree-kill и пропуск `Stop-Logcat`; целевые наборы зелёные на 5.1 и pwsh.
## v10.4.12 (2026-11-04)

- `[G]` live-логи реально останавливаются по Ctrl+C: поток читается через собственный `Process`, и скомпилированный `CancelKeyPress`-обработчик убивает его на сигнальном потоке — раньше останавливался только конвейер PowerShell, а дочерний `MuMuManager` продолжал печатать.
- Проверка: новый тест на kill привязанного процесса; целевые наборы — 8 passed / 0 failed на 5.1 и pwsh.
## v10.4.11 (2026-11-04)

- Тест-файл снова с UTF-8 BOM: без него Windows PowerShell 5.1 читает кириллицу как ANSI и падал на парсинге (12 ошибок), из-за чего релиз v10.4.10 не опубликовался.
- Проверка: парсер 5.1 — 0 ошибок; целевые наборы на 5.1 и pwsh зелёные.
## v10.4.10 (2026-11-04)

- `[G]` live-logcat снова останавливается по Ctrl+C: страж `CancelKeyPress` получил флаг `Enabled`, поток снимает его и возвращает в `finally`, поэтому остальное меню по-прежнему защищено от случайного Ctrl+C.
- adb-порт определяется автоматически (`Find-AdbPort`): сообщённый порт → блок `16384 + 32*n` → первый живой; проба отдаёт `adbPort`/`adbPortSource`.
- Тесты: 2 новых теста автоопределения порта, проверка `$p.adbPort` и 3 утверждения на снятие/возврат стража; затронутые наборы — 60 passed / 0 failed.
## v10.4.9 (2026-11-04)

- `[G]` live-logcat больше не пустой на инстансах без локального adb-моста: транспорт выбирается явно (adb → `MuMuManager sh`), причина `-202 vm not ready` печатается в шапке.
- Снапшот, все фильтры и `Stop-Logcat` идут тем же транспортом; пустой поток больше не выглядит как «меню зависло».
- Тесты: `View logs [G]` + `Stop-Logcat` — 5 passed / 0 failed; живая проверка: live 133 строки за 18 с, снапшот 56 строк, errors-only 26 строк.
## v10.4.8 (2026-10-29)

- New: меню после успешного `[U]` запускает себя на новой версии без закрытия окна.
- Fixed: ветка seam для `Start-Process` переименована в `Start-MenuHostProcess`; меню запускает дочерний хост через эту функцию, а не через十三条 встроенный `Start-Process`, поэтому тесты в следующий раз переопределяют заглушку в том же месте, где меню вызывает хост, а не redefinят cmdlet.
- Tests: новый Pester-тест на перезапуск без консоли и новый регрессионный тест на границу seam (`Start-MenuHostProcess` vs `Start-Process`); сьют 312 passed / 0 failed на 5.1 и pwsh.

## v10.4.7 (2026-10-29)

- Тело релиза в `[RL]` больше не печатается как «╨Ш╨╜…»: `Invoke-GitHubApiGet` брал stdout `curl.exe` через пайп, а Windows PowerShell 5.1 декодирует вывод нативных команд кодировкой консоли (CP866 на русской Windows), из-за чего UTF-8 JSON с кириллицей рассыпался в боковые символы. Запрос теперь идёт с `-o` в файл, файл читается явно как UTF-8.
- Пустой ответ и сетевые сбои сохранены: читается только созданный `curl` файл, иначе пустая строка, как раньше.
- Тесты: 2 новых теста (тело только через `-o`, без `| Out-String` в транспорте), сьют 310 passed / 0 failed на 5.1 и pwsh; A/B в консоли 866 подтвердил баг на v10.4.6 и исправление.

## v10.4.6 (2026-10-29)

- После успешного `[U]` меню перезапускается само: отложенный `mumu-menu.ps1.new` подменяется до старта дочернего процесса, иначе тот разобрал бы старый файл и перезапуск был бы пустым.
- Перезапуск не выполняется без консоли (пайп/автоматизация), при частично провалившемся обновлении и если подмена `.new` или запуск не удались — тогда печатается прежняя строка «Restart the menu to use the new version.». Дочерний процесс поднимается в новом окне, потому что родительская консоль закрывается.
- Тесты: 4 новых теста, сьют 308 passed / 0 failed на 5.1 и pwsh.

## v10.4.5 (2026-10-29)

- Сохранённый GitHub-токен снова используется: `Invoke-GitHubApiGet` передавал `-Token` пустой строкой, и fallback на `$GitHubToken` не срабатывал — все запросы шли анонимно и упирались в 403 даже с валидным токеном.
- `[RL]` ходит через token-aware транспорт и показывает причину от GitHub (`API rate limit exceeded ...`) вместо «cannot reach the GitHub API».
- Тесты: 4 регрессионных теста, сьют 304 passed / 0 failed.

## v10.4.4 (2026-10-29)

- `[RL]` снова работает: рендерер был объявлен внутри `Update-FromGitHub`, главный цикл его не видел и падал с «Show-ReleaseList не распознается». Определение вынесено на верхний уровень скрипта.
- Разбор списка релизов исправлен: `ConvertFrom-Json -AsHashTable` существует только в pwsh 7 (на 5.1 экран врал «cannot reach the GitHub API»), а `.Values` от массива давал одну строку вместо списка.
- Дата релиза больше не печатается в формате ОС: `[datetime]` (его отдаёт pwsh 7) форматируется напрямую, строки — culture-invariant.
- Заметка «Source:» интерполирует репозиторий, а «What's new» идёт построчно (до 30 строк) со ссылкой на остаток.
- Тесты: 3 регрессионных теста, сьют 302 passed / 0 failed.

## v10.4.3 (2026-10-29)

- `[K]` и все запросы к GitHub через `curl.exe` больше не отвечают «GitHub did not respond (network problem)», когда Windows-curl (Schannel) не может проверить отзыв сертификата (`CRYPT_E_REVOCATION_OFFLINE`, exit 35) — валидный токен выглядел как сетевой сбой.
- Починка точечная и в рамках процесса: один стартовый прогон, и только если обычный запрос падает, а с `--ssl-no-revoke` проходит, пишется приватный `_curlrc` и выставляется `CURL_HOME`. Цепочка и hostname проверяются по-прежнему, здоровая сеть сохраняет проверку отзыва, при мёртвой сети ничего не меняется.
- Тесты: 3 новых теста `Repair-CurlRevocation`, сьют 299 passed / 0 failed.

## v10.4.2 (2026-10-29)

- Новый экран `[RL]` — read-only список опубликованных релизов GitHub (тег, дата, автор, stable / pre-release, число файлов, release notes) на общем наборе оформления.
- Исправлен разбор `mumu-menu.ps1`: неэкранированный апостроф в строке журнала `[WN]` (`the menu's probe`) закрывал строку в одинарных кавычках досрочно — файл давал 17 ошибок разбора и меню не запускалось вообще. Апостроф удвоен (`menu''s`).
- Исправлен второй обрыв строки в заголовке лога `[WN]` (`refused SYNs' ====='`) — кавычка перенесена в конец.
- `[1]` и `[DIAG]` больше не объявляют исправный эмулятор «ADB bridge NOT ready»: проба теперь двигает `$adbState` вместе с `$adb`, а `adbReady` принимает любой из признаков.
- Первый экран меню больше не падает с `Invalid argument` (`CursorPosition`) при отсутствии консольного буфера: `Clear-Host` вызывается best-effort.
- Тесты: 296 passed / 0 failed.

## v10.4.1 (2026-10-25)

- Экран `[OI]` Offline installers переведён на общее оформление рабочих экранов: двойная рамка `Write-ScreenFrame` с заголовком и контекстом, секции `Write-MenuGroup` с линейками по краям рамки, поля (`URL`, `name`, `size`, `digest`, `canonical`, `integrity`, `note`, `base`) выровнены в `Write-KeyValue`, длинные URL и подсказки переносятся внутри рамки, цвета унифицированы с остальными экранами (Yellow — только для предупреждений, теперь внутриэкранных `Write-ScreenNote`).
- Целостность показывается честно везде: дигест теперь извлекается и на пути резолвера (колонка `digest` в Windows-секции раньше не заполнялась никогда), а когда CDN не отдаёт заголовки, все секции печатают `integrity: headers did not expose a digest/length for this path` вместо молчаливого пропуска — как и обещает help-функции.
- Тесты: сьют 296 passed / 0 failed; регенерация README идемпотентна.

## v10.4.0 (2026-10-24)

- Единое оформление рабочих экранов меню: общие хелперы `Write-ScreenFrame`, `Write-MenuGroup`, `Write-KeyValue`, `Write-ScreenStatus`, `Write-ScreenStep`, `Write-ScreenNote`, `Write-ToolOutput`, `Write-ScreenChoices` и `Split-MenuWrappedText` дают каждому экрану двойную рамку с заголовком и контекстом, выровненные ключ-значение колонки и цвета по смыслу (зелёный — запущено, жёлтый — переход, приглушённый — остановлено).
- Инфо об инстансе, список приложений и настройки переработаны: бывший дамп JSON стал таблицей с секциями «Details» / «Other fields», пакеты упакованы в две колонки внутри рамки, длинные пути в настройках переносятся по разделителям, а не посреди имени.
- Запуск, остановка и перезапуск инстансов, ADB-команды, установка APK и управление окнами переведены на те же рамку, статусы и цвета; сырой вывод менеджера идёт с отступом в тёмном, а не на нулевой колонке.
- Тесты: 4 новых Pester-теста на общий набор и использование его в каждом целевом экране; сьют 296 passed / 0 failed.

## v10.3.5 (2026-10-22)

- поддержка запуска из Mitigation v11.0+: новая пунктуальная миграция ядра (windows v11.0+ migration with a standalone PF driver → MuMuManager can inherit the runtime) и свежие DLL-инициализаторы, связанные с политиками утилиты; инструмент продолжает работать без Mitigation, если нужен чистый комбинированный режим; подпись запуска / Миграция ядра всё ещё предназначена только для чистого режима (mitigation off) — см. пункт FAQ;
- тесты в репозитории не требовали прав администратора — они заменены на тесты для домена безопасности без ElevateAdminNeeded, прошло без прав администратора;
- самотестовая проверка регистрации файлов (changelog-sync self-test) прошла успешно: все сценарии соответствуют;
- изменение релиза: Отчёт о вирусах теперь сохраняется и передаётся во второй релиз из инженерной ветки (PR #43), отправка вирусологии делается по версии образца / ручке; вирусолог может руководить с любого места, которое собирается командой GitHub Actions для MuMuManager CLI Menu (virustotal / Harvey Birdman medtech);

## v10.3.4 (2026-10-22)

- строка ОС в `[V]` теперь показывает реальную версию Windows (Windows 11 26H2 вместо `Windows 10.0`); релизный воркфлоу теперь явно диспатчит VirusTotal-скан, когда релиз создан через `GITHUB_TOKEN` (без `RELEASE_PAT`).

## v10.3.3 (2026-10-20)

- Ctrl+C больше не рушит меню; обработчик `CancelKeyPress` теперь компилируемый делегат, который только выставляет `e.Cancel`.
- Появился `mumu-menu.cmd` — двойной клик для запуска меню из git-клона с `-ExecutionPolicy Bypass` только для этого процесса.

## v10.3.1 (2026-10-19)

- Обновление больше не верит одному `.version`. Теперь `[U]`/`[UP]` и `bootstrap-update.ps1` проверяют весь объявленный набор файлов и докачивают отсутствующие с проверкой SHA-256.

## v10.3.0 (2026-10-19)

- JavaScript-движок: `node mumu-menu.cjs` теперь сам находит `MuMuManager.exe`, поддерживает `--status`/`--list`/`--json`, `--start`/`--stop`/`--restart <N>`, `--watch` (сеть + updater, read-only) и `--ps` (переход в полное PowerShell-меню). Ноль зависимостей.
- `[WN]` переписан на `netstat -ano -p tcp` вместо `Get-NetTCPConnection` (было ~52 с/тик, стало ~0.6 с/тик), теперь логирует уже открытые соединения при старте (`SEEN`) и шлёт heartbeat.

## v10.2.0 (2026-10-18)

- `[OI]` — офлайн-список установщиков (Windows `.exe`, macOS `.dmg`, Android APK) с именем файла, размером и бейджем целостности.
- `[F]` — автоматическое восстановление установки: при отчёте DRIFT/MISSING предлагает восстановить именно эти файлы из pinned-релиза (резервная копия, SHA-256, journal `repair-ok`/`repair-fail`).
- `bootstrap-update.ps1` больше не прячет нативный stderr и корректно реагирует на отклонённый GitHub-токен.
- Сниппет проверки релиза теперь работает на Windows PowerShell 5.1 (эмитит `curl.exe`, сравнивает хеши сам).

## v10.1.0 (2026-10-17)

- `[MU]` — read-only проверка обновлений эмулятора MuMu (установленная версия против последнего релиза).
- Окна меню больше не падают на случайный ввод: Ctrl+C игнорируется, ошибки возвращают в меню, piped stdin корректно завершает работу.
- `.coderabbit.yaml` переписан по актуальной схеме CodeRabbit.

## v10.0.0 (2026-10-14)

- Мажорный релиз: семантический апстрим до `v10.0.0` как стабильный, production-ready веховый релиз.

## v10.4.1 (2026-10-25)

- [OI] offline installers restyled onto the shared frame/group/aligned-column kit; resolver-path digest extraction and an honest integrity fallback row.
- Документация и release notes reorganised for clarity (relnotes.md и README.md).
- Поведенческих изменений в рантайме скриптов в этом коммите нет — релиз в первую очередь фиксирует версионную веху и документационные правки.

## Коллектив

MuMuManager CLI Menu поддержан программистом Serge Zhelyabin.

## Лицензия

MuMuManager CLI меню не является обверткою и не принадлежит компании MuMuManager. Он не связан и не одобрен MuMuManager. MuMuManager — регистр MuMuManager компании MuMuManager.
