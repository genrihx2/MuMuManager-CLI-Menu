# MuMuManager CLI Menu

Интерактивное PowerShell-меню для управления MuMu Emulator через официальный `MuMuManager.exe`.

---

## v1.22.5 (16.09.2026)

### Fixed

- **[DIAG] «ADB bridge not ready» на здоровом эмуляторе — вечный ложный warning, пойман вживую**. Две реальные причины: (1) мост MuMu **слушает** порт, но adb не подключается к нему сам — голый `adb devices` остаётся пустым до явного `adb connect`; (2) реальный `adb.exe` лежит **рядом с MuMuManager.exe** (`nx_main\adb.exe`), а проба искала только `<root>\shell\adb.exe` и PATH. Теперь проба делает явный идемпотентный `adb connect 127.0.0.1:<port>` перед чтением списка устройств, ищет adb по 5 кандидатам (`<dir>\adb.exe/.cmd`, `<root>\shell\adb.exe/.cmd`, PATH) и сообщает, какой именно adb использован (новое поле `adbExeUsed`).
- **Бонус из отладки: зависание меню при холодном adb-сервере**. In-band поднятие демона adb может блокировать вызов на десятки секунд — теперь **все** внешние вызовы пробы (`MuMuManager info`, adb connect/devices) идут через kill-on-timeout обёртку (`Invoke-Quick`, 5–10 с, kill по превышению). Зависший MuMu RPC или adb больше не замораживают меню; зависание честно деградирует в `adbReady=false`/`error`.
- Регрессионные тесты (119-я серия): connect-файл пишется стабом до проверки устройств, порядок кандидатов (`nx_main` побеждает `shell`), зависший adb-стаб убивается таймаутом за <15 с.

## v1.22.4 (16.09.2026)

### Security / hardening

- **Аудит всех curl-вызовов: строковая сборка через `cmd /c` полностью убрана**. Все 18 оставшихся вызовов в `mumu-menu.ps1` (загрузка релизов/файлов/ZIP, ветки, список файлов, PATCH/POST релизов, `-D`-проверка токена) и 2 в `bootstrap-update.ps1` (`Invoke-CurlGet` с auth-fallback, `Download-File`) переведены на **массивы аргументов** PowerShell. Это устраняет класс рисков раз и навсегда: токен больше не попадает в командную строку `cmd.exe` (был виден в `wmic`/мониторах процессов), спецсимволы в путях (`&`, `!`, `%`, скобки) не ломают кавычки, PS 5.1 не склеивает опции в один аргумент (первопричина бага v1.22.3). Три оставшихся честных исключения: `--config`-файлы VT (ключ не в cmdline), ADB-диагностика (не curl), wget/busybox внутри гостевого Android (другой хост).
- Регрессионные тесты (116-я серия): в обоих скриптах запрещены `cmd /c` + строковые билдеры `$curlCmd/$dlCmd/...`, каждый запуск curl обязан идти через splat `@`, интерполяция retry-строк в прямых вызовах запрещена.

## v1.22.3 (16.09.2026)

### Fixed

- **[K] «Token invalid!» при валидном токене**: прямые вызовы `curl.exe -s$CurlRetryStr` склеивали `-s` и retry-опции в один аргумент (PS 5.1) — curl отвечал exit 2, ответа не было, и меню объявляло токен недействительным. Все 5 прямых вызовов переведены на `Invoke-GitHubApiGet` (массив аргументов), пустой ответ теперь честно сообщает о проблеме сети, а rejection от GitHub различает «Bad credentials» и неожиданный ответ. Проба retry-capability стабилизирована (exit 2 = нет поддержки; стабильный URL).

## v1.22.2 (16.09.2026)

- **Honest rate-limit verdicts (from the E2E drill)**: when the update check fails because GitHub rate-limits the IP, both update paths now say so instead of a bare "Could not check releases" / "Update check failed". `bootstrap-update.ps1` parses the API error body and explains: no token → 60 requests/hour per IP (shared networks exhaust it fast), fix = save a token via menu [K] (DPAPI-encrypted, bootstrap picks it up automatically) or wait for the hourly reset; with a token → quota exhausted or token invalid, re-save via [K]. The `[U]` catch and the rate-limit message path got the same token-aware wording, and `[V]` now distinguishes "rate limit" from "cannot check". T12 in the bootstrap suite pins the verdict wiring.

## v1.22.1 (16.09.2026)
- **Fixed: the ETag cache never populated (caught by the E2E drill)**. GitHub sends the header as `ETag:` with a capital E, but the response parser matched only lowercase `^etag:` - so `$r1.ETag` was always empty, the #22 304-replay never fired and the new #28 file store stayed empty. The pattern is now case-insensitive (`(?im)^etag:`), with a regression test pinning both spellings. Symptom before the fix: `ETag cache: empty` forever and every deep check re-downloading all bodies.

## v1.22.0 (16.09.2026)
- **Persistent ETag cache (issue #28)**: the session ETag cache now survives menu restarts - `.etag-cache.json` next to `.version` stores url → {etag, body, sha256, timestamp}. On load every body is validated against its stored hash (a tampered/truncated entry is dropped, not trusted); a missing/corrupt/schema-invalid file degrades to plain fetches, never an error. Only real content is persisted (the #22 rule - API error bodies are never cached), saves are best-effort. `-Force` suppresses the cache file so repair runs always fetch fresh content over the wire.
- **[ST] session drift cache (issue #28)**: a repeat `d` in the same session replays the cached deep-check verdict instantly with an age note ("from session cache, age N min"), invalidated when the version marker changes. Fresh `d` on first use or after invalidation.
- **[ST] cache-state line**: `ETag cache: N URL(s), last entry HH:MM` under the screen header - the #25 mockup line, now real. `empty` when no entries yet.
- 6 new Pester tests (107 total): file round-trip, tampered-entry drop, corrupt/missing/schema-invalid degradation, state line, `-Force` suppression, session-cache wiring.

## v1.21.10 (16.09.2026)
- **Startup auto-diag (issue #30)**: the menu now runs the `[DIAG]` findings collector once per process, silently, at startup and surfaces ONE line under the status bar only when errors or warnings exist: `[auto-diag] Problems found: N error(s), M warning(s) - details: [DIAG]`. Info findings ("no .version marker yet", emulator idle states) never nag - they stay in `[DIAG]`. Healthy installs render nothing. `MUMU_MENU_NO_AUTODIAG=1` suppresses the check; the collector is guarded by try/catch so diagnostics can never block startup, and the verdict is collected once (cached for every menu redraw). 8 new Pester tests: formatter severity filter, info suppression, cache behavior, real-fixture wiring, env opt-out.

## v1.21.9 (16.09.2026)
- **Retry hardening for flaky networks (fixes "Update check failed: Request failed (exit 35)")**: curl's built-in `--retry` never retries TLS handshake failures (exit 35) - one flaky-network reset killed the whole update check. All GitHub fetches now carry `--retry-all-errors` (probed once per run: the option exists since curl 7.71, older builds degrade to plain `--retry` instead of aborting on an unknown option), the menu's ETag fetch has a PS-level second attempt for every transport failure, `[V]` does 2 attempts, and the bootstrap reports the curl exit code on each retry. Stub-based Pester tests pin the exit-code classification (35 = capable, 2 = not, 0 = capable, no curl = degrade).
- **Hardened the diagnostics probes under `ErrorActionPreference = Stop`**: a stderr write from the real `adb` ("daemon not running") or from curl surfaced as a terminating error inside `Invoke-MumuManagerProbe`/`_Fetch` under Pester and strict hosts; both are now caught and treated as an empty attempt (caught live in the test run).

## v1.21.8 (15.09.2026)
- **`[RB]` Rollback from backup (issue #27)**: list `backup\YYYYMMDD_HHMMSS` folders (newest first, size + date + completeness), pick one, confirm with `ROLLBACK`, restore the 4 files. The `.version` marker is **earned from the restored content's own `$scriptVer`** - never guessed (backups carry no marker; guard principle of v1.20.5). Journals `rollback` (from = marker before, to = restored claim) or `rollback-fail`; offers `[F]` verification after. Pure helpers (`Get-BackupFolders`, `Build-RollbackPlan`, `Invoke-Rollback`) covered by 5 Pester tests incl. journal assertions.
- **`bootstrap-update.ps1 -Diagnose` (issue #29)**: the menu-free diagnostics entry point for installs where `mumu-menu.ps1` will not start. Prints the `[DIAG]`-style findings report (marker vs the scriptVer parsed from raw - possibly broken - menu text, lock states, journal health, MuMu path, disk) with **no network and no mutations**; exit 0 when clean, exit 1 on error/warn findings (scriptable for support). T11 in the bootstrap suite asserts the parse-from-broken-file behavior and the wiring.
- **Fixed a false positive in the ADB-bridge readiness check (caught on a real machine)**: some MuMu builds never report `adb_version` in `info -v all`, so v1.21.7 warned "ADB bridge not ready" forever. The probe now falls back to asking ADB itself - `adb devices` against the instance's `adb_port` (local socket only), resolved from the MuMu `shell\adb.exe`, with a cold-daemon retry. Regression-tested with an injected stub adb.

## v1.21.7 (15.09.2026)
- **Emulator diagnostics in `[DIAG]` (issue #32)**: one `MuMuManager info -v all` query adds the emulator side to the problem screen - instance count, running state, and ADB-bridge readiness. No instances / none running are info (create/launch hints), a running instance with no ready ADB bridge is a warning (the exact state that made in-emulator commands like `curl` fail with "inaccessible or not found"), and a MuMuManager that does not answer cleanly warns without breaking the diagnostics. Live catch fixed before ship: the real binary emits pretty-printed multi-line JSON, which pwsh 7 parses line-by-line in a pipeline - the probe now joins lines before parsing (regression-tested). 9 new Pester tests with a real-child-process `.cmd` stub; suite 81 green on PS 5.1 and pwsh 7.

## v1.21.6 (15.09.2026)
- Release carrying the `[ST]` deep-check false-DRIFT fix (`07f30fa`): `Get-IntegrityVerdict` classifies the integrity report by its own `summary|` verdict, so metadata lines can never masquerade as drift. Suite 73 green.

## v1.21.5 (15.09.2026)
- **Fix `[ST]` deep-check false DRIFT (caught live minutes after ship)**: the drift-check wrapper treated the integrity report's informational lines (`verify-start|`, `ref-pin|`, even `summary|ok|`) as drift because they don't start with `OK` - a fully healthy install self-reported DRIFT. Now a dedicated `Get-IntegrityVerdict` classifies the report by its own verdict line (`summary|ok|` / `summary|drift|<files>` / `summary|partial|` / `error|`), so metadata never masquerades as drift; a rate-limited check still degrades honestly to "unknown". 4 Pester tests incl. the exact regression report from the live catch; suite 73 green.
- **Install status screen `[ST]` (issue #25)**: one read-only screen answering "what am I on and am I OK?" - script version, local marker, latest release, version state, drift check, last ZIP verification (from the journal), and a journal summary. Fast path (Enter) is fully offline with honest unknown states; `d` in the menu adds the release comparison and the full drift check vs the tag. Status is built by a testable `Get-InstallStatus` collector with injected network/drift sources (6 Pester tests: fast path, release compare ok/behind/ahead, drift OK/DRIFT/failure, missing journal, FAILED zip verdict surfaced, menu wiring); suite 69 green. The key `[S]` stays with screenshots; status is `[ST]`.
- **README recovery section (issue #26)**: "Восстановление после сбоя обновления / Recovering from a failed update" - the four scenarios (HASH MISMATCH, wedged marker, broken files/backup restore, lock refusal) with a symptom-cause-action table covering all updater verdicts, plus an English summary. Diagnosis-first principle: `[ST]`/`[DIAG]`/`[F]`/`[J]` before any action.
- This closes the v1.21.0 milestone "Drift Hardening & Journal Tooling" (#22 ETag/pinning, #23 journal export, #24 single-flight lock, #25 status screen, #26 recovery docs).

## v1.21.4 (15.09.2026)
- **Problem diagnostics `[DIAG]`**: new read-only, local-only screen that answers "is anything wrong with this install?" in one view. Checks: install layout (menu script present), version marker vs the script's own `$scriptVer` - a marker AHEAD of content is reported as the wedge error (the v1.20.5 heal-bug class that makes the updater say "Up to date" forever), content ahead of marker warns about an interrupted update; pending `.new`/`.old` files; update lock (held right now = warning with the owner PID, stale = info about the auto-break, claim residue = info); journal health (malformed lines, fail events, `update-skipped` count, rotation size); MuMu environment (missing `MuMuManager.exe` = error, version below minimum = warning) and low disk space.
- Findings are collected by a pure, path-parameterized `Get-ProblemFindings` (9 new Pester tests over fixture installs: healthy/zero, wedge, interrupted, missing files, lock states, journal health, MuMu, pending files, menu wiring); suite 63 green on PowerShell 5.1 and pwsh 7. Nothing on screen is ever mutated, and no network calls are made (the online comparison stays in `[F]`).

## v1.21.3 (15.09.2026)
- **`[J]` journal export (issue #23)**: new `[J] -> 5 Export` writes the selected events to Markdown (issue-ready table, pipes escaped), RFC-4180 CSV (header + quoting for comma/quote/newline cells) or JSON (top-level object with `generator`/`count`/`events`, fields verbatim). Format -> range (last 20 / full / errors-only, same as the viewer) -> path (Enter = `update-journal-YYYYMMDD-HHMMSS.<ext>` next to the journal). Output is UTF-8 with BOM (repo rule from alert #535), the journal itself is never modified, and repeat exports are byte-identical.
- JSON is a top-level object rather than a bare array: top-level arrays hit inconsistent parse shapes in some PowerShell 5.1 consumers (verified live - python parsed the same artifact as 3 elements while 5.1's pipeline form wrapped it); an object property parses uniformly in PS 5.1/7, jq and Python. JSON is compact single-line; MD/CSV are the human formats.
- Tests: 6 golden Pester tests (MD header/escaping, CSV quoting, JSON round-trip, BOM + idempotency + untouched journal, errors-only range, unknown-format error); suite 54 green on PowerShell 5.1 and pwsh 7.

## v1.21.2 (15.09.2026)
- **Single-flight update lock (issue #24)**: `[U]` and `bootstrap-update.ps1` now claim a `.update-lock` file (PID + timestamp) with an atomic `CreateNew` open before touching any install file - two concurrent updaters (menu in two windows, menu + bootstrap) can no longer corrupt `.version`/scripts/journal or double-apply an update. A refused run prints the holder's PID and the lock's age, journals `update-skipped`, and exits without changing anything. A lock older than 10 minutes is treated as the leftover of a crashed updater and is broken safely (create-then-break claim file closes the break/recreate race). The lock is always released in `finally`, including Ctrl+C mid-download.
- `[J]` viewer: `update-skipped` renders yellow (a skip is not an error), and the "errors only" mode's all-clear message now counts skips as successes.
- Tests: 6 new Pester tests (atomic acquire + payload, concurrent refusal + `update-skipped` journaling, staleness threshold, stale-break re-acquire, refusal message, claim-file cleanup) and a T10 block in the bootstrap regression suite (including the cross-script wiring assertions); suite 48 green; live-verified (same-process refusal, cross-process refusal via a child PowerShell, stale break, re-acquire after release).

## v1.21.1 (15.09.2026)
- **Fix a v1.21.0 regression in `[F]`**: the tag-pin overwrote `$Tag` with the commit SHA, silently disabling the semantic `.version` comparison - a healthy marker was reported as DRIFT on every check (caught live on the `C:\test` install right after v1.21.0 shipped). `$Tag` now stays the human-readable tag for the semantic compare, while content fetches go through a separate pinned `$FetchRef`. A Pester regression guard asserts the tag/SHA split in the function text.

## v1.21.0 (15.09.2026)
- **Tag→commit-SHA pinning everywhere (issue #22)**: every `?ref=<tag>` contents fetch in `[U]`, `[F]`, the heal and the bootstrap is rewritten to `?ref=<commit sha>`. The contents API resolves a ref at fetch time, so a CDN edge can serve the previous commit's blob minutes after a tag push - the bug class behind the v1.20.3-v1.20.6 incident fixes. A commit SHA is immutable; a stale read is impossible by construction. If resolution fails, the plain tag URL is used and SHA-256 verification still covers every byte.
- **ETag cache with 304 replay** in `Invoke-GitHubGet`: repeat fetches of the same URL within one menu session send `If-None-Match` and replay the cached body on `304 Not Modified` without transferring it. Only real content bodies are cached - API error responses (rate limits) stay retryable and never anchor an ETag.
- **`bootstrap-update.ps1` pins its tag too**: in reference-hash collection and the download loop, with the post-download SHA-256 verification as the always-on fallback.
- **Fixed the dead `[U]` heal**: the version-fix block referenced `$localText`/`$remoteText` that were never assigned - the heal could never fire. Local text is now read, and the fetched reference is commit-pinned before comparing.
- **Honest retreat on "cheap hashes"**: the `application/vnd.github.sha` media type is not supported by the contents endpoint (verified live) - reference hashes still come from bodies; repeat fetches got cheaper via the ETag cache instead.
- Tests: 6 new Pester tests (304 replay, error-not-cached, pinning call order, annotated-tag deref, unresolvable-ref null), extended bootstrap regression suite (40-hex gate, pinned ref resolution); suite 41 green; live-verified against the real API (resolve → pinned fetch → sha-vs-tag equality → repeat fetch).

## v1.20.6 (15.09.2026)
- **`[J]` journal viewer polish**: an empty `from` field renders as `(new) -> vX.Y.Z` (first-ever event on a fresh install, marker file absent), and consecutive events from the same run (identical timestamp + actor, e.g. `update-ok` + `updater-refresh`) are grouped - continuations print with an ASCII `- ` marker instead of repeating the timestamp/actor columns. No box-drawing glyphs: they are not in OEM console codepages.

## v1.20.5 (15.09.2026)
- **Fix the startup `.version` heal**: fetched content must claim the tag's own `scriptVer` or the heal is skipped - a stale CDN blob of the *previous* release can no longer raise the marker to a tag whose content never arrived (seen live on v1.20.4: the install wedged on "Up to date" with v1.20.3 content under a v1.20.4 marker).

## v1.20.4 (15.09.2026)
- **`[F]` Verify installation**: the `.version` marker is now compared **semantically** - a local marker equal to or newer than the tag's lagged marker (the sync-version bot lands after the tag) is no longer false DRIFT (seen live on v1.20.3).
- **One re-fetch before declaring DRIFT**: a GitHub CDN edge can serve a stale blob for minutes after a tag push (seen live: `bootstrap-update.ps1` was byte-identical to the tag, yet the fetch returned old content). Genuine drift still drifts.
- **`[F]` → ZIP verify: a missing archive is not tampering** - prints "No ZIP found ... nothing to verify" instead of the alarming "FAILED - do not install".

## v1.20.3 (15.09.2026)
- **Fix bootstrap post-download hash verification (regression of v1.20.2)**: reference content was fetched through a `cmd /c`-captured curl invocation, which decodes output in the console OEM codepage - Cyrillic in README/SKILL.md got mangled and every file false-alarmed `HASH MISMATCH` (caught live; the safety design worked - the update was aborted and journaled). Reference hashes now come from a byte-exact raw fetch (curl → temp file → UTF-8 decode), same as the menu. Regression test extended with a non-ASCII body.

## v1.20.2 (15.09.2026)
> [!WARNING]
> **В bootstrap этого релиза есть баг пост-проверки хешей** (OEM-кодировка искажает эталонные SHA-256) — каждый файл даёт ложный `HASH MISMATCH`. Обновлятор отрабатывает fail-closed, вреда нет; исправлено в v1.20.3. Если вы на v1.20.2: запустите `bootstrap-update.ps1 -NoVerify` один раз.
- **Post-download SHA-256 verification in `bootstrap-update.ps1` (parity with `[U]`)**: every downloaded file is re-hashed and compared with the expected hash from the release tag content - `OK (hash OK)` / `HASH MISMATCH`. A mismatch fails the update: `.version` is not advanced, the updater self-refresh is cancelled, and `update-fail` is journaled.
- Same hashing contract as the menu (CR/BOM/symmetric TrimEnd) factored into `Get-ContentHash` / `Get-ExpectedHashes`; API JSON error bodies (rate limit) are never accepted as the reference.
- `-NoVerify` opt-out; if expected hashes are unavailable the update proceeds and is marked `unverified` in the journal.
- **Regression test T9**: SHA-256 vectors, symmetric trailing trim, rate-limit JSON skip, `-NoVerify` wiring.

## v1.20.1 (15.09.2026)
- **Fix `[U]` post-download hash verification (regression of v1.20.0)**: the local side was hashed without a trailing trim while expected hashes came from the TrimEnd-ed API response - any file ending with a newline false-alarmed `HASH MISMATCH` and aborted a legitimate update. The trim now lives inside `Get-ContentHash`, so every consumer is symmetric by construction. Regression test added to the Pester suite.

## v1.20.0 (15.09.2026)
- **SHA-256 в подтверждении обновления (issue #17)**: `[U]` показывает таблицу ожидаемых хешей всех файлов (парсится из VT-вердиктов релиза) и после загрузки сверяет каждый файл — при расхождении установка останавливается
- **Pester-юнит-тесты (issue #20)**: 26+ тестов AST-извлечённых чистых функций в `tests/mumu-menu.Tests.ps1`, отдельный job `pester-unit` в CI; раннер `tests/run-pester.ps1` для PS 5.1
- **Хелперы для тестируемости**: `Compare-ScriptVersion`, `Format-JournalEvent`, `ConvertTo-ShellSafe`, `Get-ExpectedFileHashes` вынесены как чистые функции

## v1.19.6 (15.09.2026)
- **Самопроверка релизного ZIP перед установкой (issue #19)**: `Test-ReleaseZip` — SHA-256 ZIP против `.sha256`-сайдкара, точный набор из 5 файлов, `$scriptVer` из архива против тега релиза; при несоответствии — «FAILED - do not install» и событие `zip-verify-fail` в журнале
- **Как использовать**: `bootstrap-update.ps1 -VerifyZip <файл.zip>` или запрос после `[F] Verify installation`
- **Регресс-тест T8**: 12 ассертов на реальных ZIP-фикстурах (подменённый байт, неверный сайдкар, несовпадение версий, неполный набор, отсутствие архива)

## v1.19.5 (15.09.2026)
- **DNS и HTTP-тесты через busybox-fallback**: в образах MuMu 12 нет `nslookup`/`curl`, но есть `/system/xbin/busybox` — тесты используют `busybox nslookup` и `busybox wget` (с `-q -O /dev/null --timeout`, код выхода решает), если нативных инструментов нет
- **Живая проверка**: ping по ICMP фильтруется MuMu NAT — DNS ✓ / HTTP ✓ при FAILED-пингах означает рабочий интернет без ICMP

## v1.19.4 (15.09.2026)
- **Диагностика сети эмулятора честнее**: перед тестами определяется наличие инструментов в гостевой ОС (`ping`, `nslookup`/`getent`, `curl`) — отсутствие инструмента выводится как `N/A` с пояснением, а не как `FAILED` сети
- **Парсер ping понимает toybox**: вывод Android toybox (`round-trip min/avg/max`, `2 packets received`) распознаётся наравне с busybox/iputils
- **PowerShell 5.1**: stderr гостя больше не оборачивается в NativeCommandError — вместо красных блоков ошибок обычный текст

## v1.19.3 (14.09.2026)

### Что нового
- **[F] Verify installation (issue #18)**: сверка локальных файлов с тегом релиза по SHA-256 — OK / DRIFT (с обоими хешами) / MISSING / N/A
- Итог: «Installation matches vX.Y.Z» либо «Drift detected (files: ...)» — единственный способ заметить подмену/дрейф локального файла между релизами
- Устаревший маркер `.version` при совпадающем контенте помечается отдельно (лечится через `[U]`)

### Детали
- Работает без токена для публичного репо; те же API-хелперы и нормализация (CRLF/BOM/концевые пробелы), что и путь обновления
- Ответ API с ошибкой (rate limit) не принимается за контент — файл N/A, честный partial-итог вместо ложного drift
- Регресс-тест T7: 14 hermetic-ассертов на функциях, извлечённых через AST (без сети)

---

## v1.19.2 (14.09.2026)

### Что нового
- **Самоновляемый обновлятор (#21)**: `bootstrap-update.ps1` больше не единственный файл, который обновление не может починить — теперь он обновляет сам себя при каждом обновлении
- `[U]` скачивает обновлятор в общем списке файлов (перезапись напрямую: меню работает, обновлятор не запущен)
- `bootstrap-update.ps1` кладёт свою новую копию в `bootstrap-update.ps1.new` и применяет её в конце успешного прогона; если файл занят — `.new` остаётся, и меню применит его при старте

### Детали
- Скачанный обновлятор проходит те же проверки (не пустой, не JSON-метаданные)
- Журнал: события `updater-refresh` при применении `.new` (из bootstrap и из меню)
- Регресс-тест T6: оба списка файлов содержат обновлятор; `Apply-PendingUpdater` меняет содержимое, удаляет `.new` и пишет событие
- Миграция: инсталляции старше v1.18.10 получают рабочий обновлятор через сам `[U]`

---

## v1.19.1 (14.09.2026)

### Что нового
- **Журнал обновлений [J]**: оба обновлятора — `[U]` и `bootstrap-update.ps1` — пишут события в общий `update-journal.log` рядом с установкой: успехи, частичные сбои, автовосстановление `.version`, самоприменение `.new`
- **Просмотр в меню**: новый пункт `[J] Update journal` — последние 20 событий / весь журнал / только ошибки / открытие в блокноте
- **-LogDir**: bootstrap-update принимает `-LogDir` для записи журнала в произвольный каталог (если каталог установки только для чтения)

### Детали
- Формат: UTF-8, таб-разделённый, `время\tактор\tсобытие\tверсия\tверсия\tдетали`; акторы `menu` и `bootstrap`
- Санитизация: табы и переводы строк в деталях заменяются, чтобы строка журнала всегда оставалась однострочной
- Ротация: при 256 KB журнал переименовывается в `update-journal.log.old`; запись журнала никогда не ломает само обновление

---

## v1.19.0 (14.09.2026)

### Milestone «Verification UX» — завершён
- **VT-скан всех файлов релиза** (#14): CI сканирует ZIP, `mumu-menu.ps1` и `SKILL.md` из состава ZIP; известные VT объекты переиспользуются по SHA-256; таблица вердиктов в step summary
- **Вердикты в описании релиза** (#15): маркерная секция «VirusTotal verdicts» — таблица с SHA-256 и пермалинками отчётов, статус CLEAN/DETECTIONS, ссылка на scan-run, блок самопроверки `sha256sum -c`; идемпотентно при перезапусках
- **Автозапуск скана после CI-публикации** (#16): релиз публикуется с `RELEASE_PAT` (fallback на `GITHUB_TOKEN` — публикация никогда не ломается), чтобы триггер `on: release published` срабатывал; цепочка «бамп версии → тег → релиз → скан → вердикты в notes» работает без единого ручного действия

---

## v1.18.10 (14.09.2026)

### Сборка и безопасность
- **bootstrap-update.ps1 в релизном ZIP**: обновлятор теперь входит в состав каждого релиза — установка всегда несёт актуальную версию обновлятора (урок v1.18.8: ZIP не содержал фикс JSON-детектора, и старые установки не могли сами починить обновлятор)
- **VT-скан всех файлов релиза (issue #14)**: CI-скан расширен с ZIP на `mumu-menu.ps1` + `SKILL.md`, извлечённые из того же ZIP; известные VT объекты переиспользуются по SHA-256 (без повторной загрузки); в step summary — таблица вердиктов с пермалинками отчётов

---

## v1.18.9 (14.09.2026)

### Безопасность
- **Sigma #8 (NTFS Alternate Data Stream)**: MIME-литерал в коде загрузки VT (многотомный multipart строился вручную) давал подстроку «-stream» в том же скриптблоке, где есть `Set-Content` — правило «NTFS Alternate Data Stream» срабатывало ложно
- Загрузка VT переведена на `curl.exe` multipart (как в CI-workflow), MIME-литерал удалён из скрипта; поведение не изменилось (те же эндпоинты, тот же DPAPI-ключ)
- Скрипт никогда не читал и не писал NTFS alternate data streams — задокументировано в SECURITY.md (#8) и в шапке скрипта

---

## v1.18.8 (14.09.2026)

### Исправления
- **bootstrap-update.ps1**: JSON-детектор («Received JSON metadata instead of raw file») ложно срабатывал на собственном коде `mumu-menu.ps1` — raw-скрипт содержит литералы `"name":` и `_links` в своих API-проверках; теперь JSON-проверки применяются только когда тело ответа начинается с `{`
- **[U] Check for updates**: та же защита в обновляторе меню (тот же класс ложного срабатывания)
- **.version**: bootstrap-update обновляет `.version` только при успешной загрузке всех файлов — частичный сбой больше не оставляет `.version` впереди фактической версии скрипта

---

## v1.18.7 (14.09.2026)

### Сборка и безопасность
- **Release pipeline**: tag-driven Release workflow — ZIP и SHA256 собираются строго из содержимого тега (`git archive`), проверка соответствия `$scriptVer` тегу, идемпотентные перезапуски
- **VirusTotal в CI**: автоматический скан релизного ZIP после публикации (секрет `VT_API_KEY`); исправлен невалидный YAML в `virustotal.yml` (workflow не мог запуститься)
- **CI lint**: actionlint + shellcheck по всем workflow (`lint.yml`); VT-вердикты v1.18.6 — 0 malicious / 0 suspicious (ZIP, ps1, SKILL.md); добавлен `RELEASE-RUNBOOK.md`

---

## v1.18.6 (04.09.2026)

### Исправления
- **Auto-detect MuMuManager.exe path**: добавлены generic `shell\` пути (`$env:ProgramFiles\Netease\MuMuPlayer\shell\` и `$env:ProgramFiles(x86)\...`) для автоопределения; registry fallback теперь проверяет и `nx_main\`, и `shell\` поддиректории

---

## v1.18.5 (04.09.2026)

### Исправления
- **Download helpers**: убраны проверки $LASTEXITCODE из _DlFile и _Fetch (stale exit code пропускал JSON-метаданные GitHub API); добавлена проверка длины токена

---

## v1.18.4 (04.09.2026)

### Исправления
- **VT меню**: опция [2] Save API key выводила "Invalid selection" — PowerShell switch без break выполняет все совпавшие ветки, добавлен break

---

## v1.18.3 (04.09.2026)

### Исправления
- **Update download**: исправлена ошибка — токен GitHub не передавался при скачивании файлов обновления, из-за чего запросы шли без аутентификации и упирались в лимит 60 запросов/час; добавлено определение rate limit с подсказкой обновить токен

---

## v1.18.2 (04.09.2026)

### Исправления
- **SECURITY.md**: обновлена политика безопасности — добавлены [VF] VirusTotal Upload, VT API ключ (DPAPI), сетевые эндпоинты, модель угроз, sigma false positive #7

---

## v1.18.1 (04.09.2026)

### Что нового
- **[VF] VirusTotal Upload file**: загрузка произвольного файла на VirusTotal через API с проверкой существующих результатов, поллингом анализа и отображением вердикта
- **Сводная таблица изменений**: добавлена в README.md для быстрого обзора всех версий

### Исправления
- **PSScriptAnalyzer #534**: заменён пустой catch block в Upload-VirusTotal на Write-Debug

---

## v1.18.0 (04.09.2026)

### Что нового
- **[SC] SIM check**: новая опция для просмотра всех SIM-свойств в одной группированной таблице с сводкой состояния
- **debug.tracing.mcc/mnc**: SIM-спуфинг теперь также устанавливает внутренние MCC/MNC эмулятора
- **ADB wait loop**: Set-SimOperator и Apply-SavedSim теперь ждут до 30с пока ADB будет онлайн перед установкой свойств
- **Shell escaping**: символы &, ;, |, $ в именах операторов заменяются на _ для надёжной работы в shell

### Исправления
- **PSScriptAnalyzer**: подавлены предупреждения PSUseApprovedVerbs и PSUseDeclaredVarsMoreThanAssignments на уровне скрипта
- **bootstrap-update.ps1**: добавлен Bad credentials fallback для API-запросов и скачивания файлов

---

## v1.17.1 (03.09.2026)

### Исправления
- **PSScriptAnalyzer #532**: исправлены позиционные параметры в Write-Host в функции SIM Check

---

## v1.17.0 (03.09.2026)

### Что нового
- **debug.tracing.mcc/mnc**: SIM-спуфинг теперь также устанавливает `debug.tracing.mcc` и `debug.tracing.mnc` — внутренние свойства эмулятора для сетевой трассировки. Это writable property, в отличие от `nemud.device.*` (которые не являются Android system properties и не доступны через setprop).

### Исследование
- `nemud.device.imsi`, `nemud.device.sim.serialno`, `nemud.device.line1num` — **НЕ** являются Android system properties, не доступны через `setprop`
- `debug.tracing.mcc` — writable, контролирует внутренний MCC эмулятора (был 460, теперь ставится为目标 MCC)
- `nemu-vcontrolmanager.dll` содержит захардкоженный список MCC/MNC (46000-46005) — бинарный патч невозможен

---

## v1.16.0 (03.09.2026)

### Что нового
- **nemud.device.imsi**: SIM-спуфинг теперь также устанавливает `nemud.device.imsi` — свойство, которое читает `nemu-vcontrolmanager.dll` для предоставления данных SIM-карты Android-слою телефонии. Это может позволить DLL использовать подменённый IMSI вместо захардкоженных китайских MCC/MNC.

### Исследование
- **nemu-vcontrolmanager.dll**: найден захардкоженный список MCC/MNC (46000, 46002, 46007, 46001, 46006, 46003, 46005) и номеров телефонов Китая. DLL читает `nemud.device.imsi`, `nemud.device.sim.serialno`, `nemud.device.line1num`. Бинарный патч невозможен (разная длина строк 46000 vs 310260).

---

## v1.15.1 (03.09.2026)

### Исправления
- **Self-update ошибка загрузки**: заменена вложенная функция _Dl-Retry на инлайн curl с перехватом вывода — теперь при ошибке скачивания отображается реальная причина вместо «Unknown error»

---

## v1.15.0 (03.09.2026)

### Что нового
- **[AI] Set Android ID**: новая опция в меню для просмотра, установки или очистки Android ID для конкретного экземпляра эмулятора. Варианты: случайная генерация (16 hex), пользовательское значение, сброс к значению по умолчанию. Использует MuMuManager simulation. Включает верификацию и предложение перезапуска.

---

## v1.14.5 (03.09.2026)

### Улучшения
- **Предупреждение о SIM-спуфинге**: после установки SIM-оператора отображается таблица с описанием того, что спуфинг покрывает (gsm.sim.*, persist.mumu.mccmnc, settings global) и что не покрывает (Android Settings → SIM cards, telephony registry, networkCountryIso)

---

## v1.14.4 (03.09.2026)

### Улучшения
- **Производительность меню**: кэширование MuMuManager info на 5 секунд — убирает лаг при каждом отрисовке меню (особенно во время перезагрузки эмулятора)

---

## v1.14.3 (03.09.2026)

### Исправления
- **SIM спецсимволы**: экранирование `&`, `;`, `|`, `$` в именах операторов перед передачей в ADB shell — исправляет ошибку «/system/bin/sh: T: inaccessible or not found» для AT&T и других операторов со спецсимволами

---

## v1.14.2 (03.09.2026)

### Исправления
- **SIM config сохранение**: `Get-SimConfig` теперь возвращает hashtable вместо PSCustomObject — исправляет ошибку «Cannot find property 3» при сохранении конфигурации для инстансов с числовыми индексами

---

## v1.14.1 (03.09.2026)

### Исправления
- **Self-update Bad credentials**: файл `[U]` теперь повторяет скачивание без токена при ошибке «Bad credentials» — исправляет ошибку «JSON metadata instead of raw file content» для .ps1 файлов

---

## v1.14.0 (03.09.2026)

### Что нового
- **[SIM] Улучшенное меню выбора оператора**: поиск/фильтр по имени, CC, MCC или региону (NA/EU/EA/SEA/SA/ME/AF/LA/OC); диалог подтверждения с таблицей изменений перед применением
- **[SIM+] Расширенное управление конфигурацией**: таблица с состоянием инстансов (running/stopped), новые опции — [A] применить сохранённую конфигурацию, [E] редактировать, [V] проверить текущие props

---

## v1.13.33 (03.09.2026)

### Исправления
- **SIM меню зависание**: добавлен таймаут 10с на ADB getprop — меню больше не зависает когда ADB ещё не готов (состояние `start_finished`)

---

## v1.13.32 (03.09.2026)

### Исправления
- **Bad credentials fallback**: если сохранённый GitHub-токен невалиден, проверка обновлений автоматически повторяет запрос без авторизации вместо ошибки «Bad credentials»

---

## v1.13.31 (03.09.2026)

### Что нового
- **Расширены SIM-пресеты**: добавлены 21 новый оператор из 8 регионов (AT&T/Verizon US, Rogers CA, Telcel MX, TIM IT, Movistar ES, KPN NL, Play PL, AIS TH, Globe PH, Maxis MY, Singtel SG, Jazz PK, Grameenphone BD, STC SA, Etisalat AE, Vodafone EG, MTN NG, Telstra/Optus AU, Spark NZ) — всего 38 пресетов + кастом
- **Организация пресетов по регионам**: пресеты сгруппированы с комментариями для удобства навигации

### Исправления
- **Save-SimConfig**: исправлена ошибка преобразования типов (PSCustomObject vs Hashtable) при сохранении SIM-конфигурации после настройки оператора
- **SIM+ отображение**: удалён лишний символ 'n' в цикле отображения конфигурации SIM

---

## v1.13.30 (02.09.2026)

### Что нового
- **SIM пресеты для Китая**: добавлены пресеты China Mobile (460/00), China Unicom (460/01) и China Telecom (460/03) — три основных оператора Китая для TikTok и других приложений

---

## v1.13.28 (30.08.2026)

### Что нового
- **ADB управление**: `[AF]` передача файлов (push/pull/list), `[AS]` скриншоты и запись экрана, `[AH]` интерактивная ADB-сессия
- **Улучшена загрузка репозитория**: `[5]` скачивание отдельного файла, показ доступных веток при git clone
- **Быстрая проверка обновлений**: сравнение версий без скачивания скрипта (мгновенно)
- **Исправлена ошибка скачивания**: пустой `Authorization` заголовок при отсутствии токена вызывал 401
- **Видимость ошибок curl**: ошибки скачивания теперь отображаются подробно
- **Исправлен пустой catch**: PSScriptAnalyzer #518 — `catch {}` теперь логирует ошибку

### Исправления (позже)
- **Download Repository fallback**: при отсутствии ZIP-ассета в релизе файлы скачиваются по одному через `api.github.com`
- **Нет дублирования директорий**: git clone не создаёт `MuMuManager-CLI-Menu\MuMuManager-CLI-Menu`
- **NativeCommandError**: stderr от `git clone` и `curl` больше не льётся в консоль
- **Сетевой отказ**: скачивание переключается с `raw.githubusercontent.com` на `api.github.com`
- **Bootstrap update**: полная перезапись — `curl.exe` вместо `Invoke-WebRequest`, токен DPAPI, retry, бэкап перед записью
- **Security audit**: `git safe.directory` предотвращает ошибку "dubious ownership"
- **PSScriptAnalyzer**: удалены неиспользуемые переменные (`$remoteMsg`, `$hasHighBytes`, `$startOffset`, `$androidVer`, `$vmName`)
- **BOM**: все `.ps1` файлы имеют UTF-8 BOM

---

## v1.13.27 (29.08.2026)

### Что нового
- **Исправлен `$scriptVer`**: переменная версии скрипта определена в глобальной области видимости — меню теперь корректно показывает версию в шапке
- **Исправлен `$InstalledVersion`**: переменная версии MuMu теперь инициализируется до проверки — `Show-QuickStatus` не падает при ошибке `MuMuManager.exe version`
- **Прогресс-бар загрузки `[U]`**: заменён молчаливый `WebClient` на `curl.exe -#` с отображением скорости, размера и прогресса
- **Защита от краша при запуске**: проверка обновлений `Update-FromGitHub -Passive` обёрнута в `try/catch` — ошибки сети не убивают скрипт до появления меню

---

## v1.13.26 (26.08.2026)

### Что нового
- **Consent-гейты для чувствительных операций**: `[O] Clear app data` и `[9] Uninstall app` теперь требуют явного ввода `YES` с описанием последствий
- `[A] Run ADB command`: session-consent перед первым произвольным ADB-шеллом (команды выполняются только внутри собственной ВМ эмулятора, хост недоступен)
- Ответ на AI-вердикт VirusTotal (NICS Lab): флагует назначение (dual-use спуфинг), а не поведение; опубликованы комментарий владельца и голос harmless на оба файла v1.13.25

---

## Установка

- **Через меню**: `[DL] Download repository` → выбор метода (git clone, release ZIP, отдельный файл)
- **Bootstrap**: `powershell -ExecutionPolicy Bypass -File bootstrap-update.ps1`
- **Вручную**: скачайте `mumu-menu.ps1` из [Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest) и запустите

## Проверено

- **VirusTotal**: 0/75 (ps1), 0/75 (zip) — пермалинки в README, раздел «Безопасность»
- **PSScriptAnalyzer**: 0 ошибок, 0 пустых catch-блоков
- **E2E verification**: parse, BOM, download, token decryption, git safe.directory — всё пройдено

**Требования:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x
