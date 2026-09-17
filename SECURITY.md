# Security Policy / Политика безопасности

> Языки: [Русский](#русский) · [English](#english)

---

## Русский

> Актуально для **v1.22.12** (обновлено 2026-09-17).

### Поддерживаемые версии

Обновления безопасности выпускаются только для актуального релиза.

| Версия | Поддержка |
| --- | --- |
| актуальный релиз ([Releases/latest](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)) | ✅ |
| предыдущие версии | ❌ |

### Как сообщить об уязвимости

**Пожалуйста, не создавайте публичный Issue для уязвимостей.**

Используйте приватный канал:

1. **GitHub Private Vulnerability Reporting**: вкладка репозитория **Security → Report a vulnerability** — предпочтительный канал; либо
2. Обходной путь: создайте Issue с пометкой «contact requested», чтобы автор назначил приватный канал.

В отчёте укажите:

- Описание проблемы и потенциальное влияние
- Шаги воспроизведения (PoC-скрипт приветствуется)
- Затронутый файл: `mumu-menu.ps1` или `bootstrap-update.ps1`
- Версию скрипта: пункт меню `[V] Version info` либо `bootstrap-update.ps1 -Diagnose`
- ОС, версию PowerShell и MuMu Emulator
- Файлы конфигурации/логов, если относятся (**без секретов** — токены и ключи предварительно вымарать)

**Что происходит дальше:**

- Фикс разрабатывается в приватной ветке и выходит через штатный tag-driven конвейер с CI-верификацией (ZIP + SHA256 + VT-вердикты)
- Публичное раскрытие — только после выхода исправленного релиза
- Вы указаны в благодарностях и примечаниях к релизу (по вашему согласию)

**Safe harbor:** добросовестное исследование в рамках этой политики (без DoS, спама, спуфинга пользователей и доступа к чужим данным) не повлечёт юридических или административных действий со стороны автора. Bounty-программы нет.

**Не относится к уязвимостям:** задокументированные возможности проекта — см. раздел «Что НЕ считается уязвимостью» ниже.

### Сроки ответа

| Приоритет | Срок |
|-----------|------|
| Первичный ответ | **до 72 часов** |
| Оценка и план исправления | до 7 дней |
| Критичные уязвимости | патч вне очереди, emergency-релиз |
| Подтверждение получения | **до 24 часов** |

**Постоянный автоматизированный контроль:** еженедельный PSScriptAnalyzer с загрузкой SARIF в Security-таб (пн 06:00 UTC), CI VirusTotal-скан каждого релиза, еженедельный Release guard по комплектности релизов, групповые Dependabot-обновления экшенов, actionlint + shellcheck на все workflows.

### Архитектура безопасности

```
┌────────────────────────────────────────────────────────────────┐
│                        mumu-menu.ps1                          │
│                                                                │
│  ┌──────────┐  ┌────────────┐  ┌───────────────────────────┐  │
│  │  Token   │  │ Certificate│  │     ADB Management        │  │
│  │  DPAPI   │  │ Self-signed│  │ [AF] push/pull/list       │  │
│  │  Encrypt │  │ CodeSign   │  │ [AS] screencap/record     │  │
│  └──────────┘  └────────────┘  │ [AH] interactive shell    │  │
│                                 └───────────────────────────┘  │
│  ┌──────────┐  ┌──────────────────────────────────────────┐    │
│  │ VT API   │  │           MuMuManager.exe                │    │
│  │ Key      │  │      (Official Netease CLI tool)         │    │
│  │ DPAPI    │  │  clone · launch · quit · modify · adb   │    │
│  └──────────┘  └──────────────────────────────────────────┘    │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              GitHub API + VirusTotal API                │    │
│  │  api.github.com (contents API)                        │    │
│  │  www.virustotal.com (file upload, scan results)        │    │
│  └────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────┘
```

### Модель угроз

| Угроза | Митигация | Уровень |
|--------|-----------|---------|
| Токен GitHub в открытом виде | DPAPI-шифрование (CurrentUser), `.gitignore` для `.github-token` | 🔴 Критический |
| Токен VT API в открытом виде | DPAPI-шифрование (CurrentUser) в `.vt-apikey.dpapi`, `.gitignore` для `.vt-apikey*` | 🔴 Критический |
| Подмена скрипта | Authenticode-подпись через `[CRT]`, проверка SHA256 при обновлении | 🔴 Критический |
| MITM при обновлении | HTTPS через `api.github.com` (contents API), проверка SHA-256 каждого файла | 🟠 Высокий |
| Инъекция команд | Параметризованные вызовы `MuMuManager.exe`, escaping аргументов | 🔴 Критический |
| ADB-инъекция | Параметризованные вызовы `adb push/pull/shell`, escaping аргументов | 🟠 Высокий |
| Вредоносный ZIP | Валидация структуры ZIP, проверка наличия всех файлов | 🟠 Высокий |
| Подмена через stale-CDN (тег отдаёт старый коммит) | Пин тега на commit SHA (bootstrap, [F]) + SHA-256 каждого файла против контента тега; несовпадение = update-fail | 🟠 Высокий |
| Параллельные обновлятели (гонка файлов) | Single-flight lock с атомарным созданием, stale-брейк после 10 мин (issue #24) | 🟡 Средний |
| Пустой/битый релиз в репозитории | Release guard: еженедельный CI-аудит (ZIP + SHA256 + VT + сверка `.version`) | 🟠 Высокий |
| Replay-атака на токен | Токен одноразовый для API, не передаётся в URL-параметрах | 🟡 Средний |
| LSASS injection | Нет — DPAPI через .NET `ProtectedData`, без DLL/EXE в LSASS | ✅ Нет риска |

### Сетевые эндпоинты

Скрипт обращается **только** к следующим доменам:

| Домен | Протокол | Использование | Аутентификация |
|-------|----------|---------------|----------------|
| `api.github.com` | HTTPS (TLS 1.2+) | Проверка версий, загрузка обновлений (contents API), валидация токена | Bearer token (опционально) |
| `www.virustotal.com` | HTTPS (TLS 1.2+) | `[VF]` загрузка файлов, проверка результатов сканирования | `x-apikey` (VT API key) |

**Не используются:** `raw.githubusercontent.com` (обновления идут только через contents API `api.github.com` — сырой домен не содержит механизма версионирования), `Invoke-WebRequest`, `Invoke-RestMethod`, WebSocket, SMTP, FTP, DNS-over-HTTPS.

### Токены безопасности

#### GitHub Token

**Хранение:**
- Windows DPAPI (scope: CurrentUser) в `.github-token.dpapi`
- Плейнтекстовый `.github-token` автоматически мигрируется при первом запуске
- `.gitignore` исключает оба файла из репозитория
- Миграция включает **затирание нулями** плейнтекста перед удалением (secure wipe)

**Использование:**
- Только для GitHub API (проверка версий, загрузка обновлений)
- Никогда не логируется и не передаётся третьим лицам
- Можно удалить через `[K] Update GitHub token → [2] Remove`

**Валидация:**
- Тест токена перед сохранением (запрос к `/user`)
- Маскированный вывод: `ghp_***3L0a9i`
- Проверка scope и типа при отображении
- Автоматическое обнаружение и миграция legacy-токенов

#### VirusTotal API Key

**Хранение:**
- Windows DPAPI (scope: CurrentUser) в `.vt-apikey.dpapi`
- `.gitignore` исключает `.vt-apikey*` из репозитория
- Маскированный вывод: `abcd****`

**Использование:**
- `[VF]` загрузка файлов на VirusTotal
- `[VT]` сканирование файлов через VT API
- Проверка результатов ранее загруженных файлов
- Никогда не логируется и не передаётся третьим лицам
- Можно удалить через `[VK] Set VirusTotal API key → [3] Delete`

**Ограничения:**
- VT Free API: 4 запроса/мин, лимит 32 MB на файл
- Ключ хранится локально, не синхронизируется между машинами

### Код-подпись

**Создание:** `[CRT] Create certificate`
- Self-signed сертификат (RSA 2048, SHA256)
- Code Signing EKU (1.3.6.1.5.5.7.3.3) для Authenticode
- Добавление в Trusted Root — **явное действие пользователя**
- Lifetime: 1 год (проверка через `[V] Version info`)

**Подписание:** автоматическое при обновлении через `[U]`
- `Set-AuthenticodeSignature` на `mumu-menu.ps1`
- PowerShell ExecutionPolicy: `RemoteSigned` или `Bypass`
- Подпись через копию в temp (нельзя подписать запущенный файл)

### Безопасность обновлений

```
1. Проверка версии — только против тегированных GitHub Releases (никогда main)
2. Подтверждение пользователя (y/N) + single-flight lock: параллельные обновлятели
   исключены (issue #24), lock старше 10 минут считается зависшим и ломается
3. Скачивание через contents API api.github.com (curl.exe, retry 3, connect-timeout 30с)
4. SHA-256 каждого скачанного файла сверяется с контентом тега ДО записи .version (issue #20)
5. Бэкап заменяемых файлов в backup\<timestamp> (хранятся последние 5)
6. Повторная подпись Authenticode (если настроена через [CRT])
```

**Гарантии:**
- Загрузка только текстовых файлов (`.ps1`, `.md`) — никаких исполняемых
- Никаких скрытых загрузок; каждое действие подтверждается пользователем или журналируется
- Несовпадение хеша = update-fail: `.version` не двигается, установка остаётся консистентной (issue #20)
- `.version` — семантический маркер с защитой от клина: heal выполняется только при совпадении контента с тегом через fetch, запиненный на commit SHA, и при совпадении scriptVer (issue #22)
- Все события пишутся в `update-journal.log` (update-ok / update-fail / self-apply / updater-refresh)
- Dry-run везде: `[UP]` в меню и `-WhatIf` в bootstrap показывают план обновления без единой мутации
- Bootstrap-обновлятор дополнительно пинит тег на commit SHA и умеет верифицировать релизный ZIP целиком (`-VerifyZip`)

### Безопасность конвейера релизов

- **Tag-driven Release workflow**: релиз собирается только из тега; ZIP + `.sha256`-сайдкар публикуются автоматически
- **VirusTotal**: каждый релиз сканируется в CI (3 файла), вердикты публикуются в теле релиза
- **Release guard**: еженедельный CI-аудит — каждый релиз новее v1.18.6 обязан иметь ZIP + SHA256 + VT-вердикты, latest release сверяется с `.version`; расхождения открывают идемпотентный issue
- **Зависимости экшенов**: еженедельные групповые Dependabot-обновления
- **CI-гейты**: PSScriptAnalyzer, Pester (133 теста), bootstrap-регрессия, changelog-sync

### Управление ADB

Функции управления ADB (`[AF]`, `[AS]`, `[AH]`) работают через локальный ADB-клиент с подключённым эмулятором:

| Функция | Команды ADB | Описание |
|---------|-------------|----------|
| File Transfer `[AF]` | `adb push`, `adb pull`, `adb shell ls` | Копирование файлов между PC и эмулятором |
| Screen Capture `[AS]` | `adb shell screencap`, `adb shell screenrecord` | Скриншоты и запись экрана (до 180с) |
| Interactive Shell `[AH]` | `adb shell` | Прямой доступ к shell эмулятора |

**Безопасность ADB:**
- Все операции требуют согласия пользователя (`Confirm-AdbConsent`)
- ADB-команды передаются параметризованно — аргументы экранируются
- Команды выполняются **только внутри ВМ эмулятора**, хост-машина недоступна
- Session-consent перед первым произвольным ADB-шеллом

### Политика выполнения (Execution Policy)

Рекомендуемые политики PowerShell:

| Политика | Описание | Рекомендация |
|----------|----------|--------------|
| `RemoteSigned` | Скрипты с подписью запускаются без запроса | ✅ Рекомендуется |
| `AllSigned` | Все скрипты должны быть подписаны | ⚠️ Требует подписи через `[CRT]` |
| `Bypass` | Без ограничений | 🔴 Только для тестирования |

**Установка:**
```powershell
# Текущий пользователь
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Все пользователи (требует администратора)
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
```

### Безопасная установка

1. **Скачайте** скрипт только из [Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)
2. **Проверьте** цифровую подпись: `[V] Version info` → статус подписи
3. **Настройте** ExecutionPolicy: `RemoteSigned` (см. выше)
4. **Создайте** сертификат: `[CRT] Create certificate` → подпишите скрипт
5. **Настройте** GitHub токен: `[K] Update GitHub token` (DPAPI-шифрование)
6. **Настройте** VT API ключ (опционально): `[VK] Set VirusTotal API key` для `[VF]`/`[VT]`
7. **Проверьте** зависимости: `[TD] Dependencies test`

### Тестирование безопасности

Для проверки безопасности скрипта:

1. **PSScriptAnalyzer:**
   ```powershell
   Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
   # с настройками репозитория (как в CI) - без -Settings будут сотни
   # ложных PSAvoidUsingWriteHost: проект сознательно использует Write-Host
   Invoke-ScriptAnalyzer -Path mumu-menu.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
   Invoke-ScriptAnalyzer -Path bootstrap-update.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
   ```
   Ожидаемый результат для релизных файлов: **0 замечаний** (эталон — CI-джоба `psscriptanalyzer` на последнем коммите `main`).

2. **VirusTotal:** проверьте файлы на [virustotal.com](https://www.virustotal.com) (0/75 — чисто)

3. **Подпись:** `[V] Version info` → статус подписи должен быть `Valid`

4. **Сетевой трафик:** мониторьте с помощью Wireshark — только HTTPS к `api.github.com`

### Что НЕ считается уязвимостью

Это задокументированные возможности проекта (см. «Примечание для AV-аналитиков» в README):

**Функции приватности (явное действие пользователя):**
- Спуфинг модели устройства и генерация IMEI / Android ID / MAC — для **собственных** инстансов
- `[DM]` Spoof device model — изменение brand/model/code
- `[DI]` Random device IDs — генерация случайных идентификаторов
- `[SIM]` Change SIM operator — смена MCC/MNC для TikTok и др.

**Хранение токенов:**
- Windows DPAPI (CurrentUser) — расшифровка возможна только от имени того же пользователя Windows
- GitHub token: `.github-token.dpapi` — проверка версий, загрузка обновлений
- VT API key: `.vt-apikey.dpapi` — загрузка файлов и сканирование через `[VF]`/`[VT]`
- Legacy `.github-token` автоматически мигрируется с secure wipe

**VirusTotal интеграция:**
- `[VF]` Upload file: загрузка файла на VirusTotal для анализа (лимит 32 MB, free API)
- `[VT]` Scan: проверка файлов проекта через VT API, загрузка если ещё не сканировались
- `[VK]` Управление API ключом: DPAPI-шифрование, маскированный вывод, явное действие пользователя

**Обновления:**
- Read-only проверка при старте (HTTPS к `api.github.com`) — загрузка только через `[U]`
- Самообновление из тегов GitHub Releases с проверкой содержимого

**ADB:**
- ADB shell / push / pull — управление эмулятором, только по явному запросу пользователя

**Sigma False Positives:**
- **#1** (`DMP/HDMP File Creation`): скрипт **НЕ создаёт** .dmp/.hdmp файлы. DPAPI хранит зашифрованный текст — это не memory dump
- **#2** (`Unsigned Image Loaded Into LSASS`): DPAPI через .NET ProtectedData CurrentUser, **без** загрузки DLL/EXE в LSASS и **без** инъекции; скрипт подписан через `[CRT]`
- **#3** (`Web Request Commands`): `curl.exe` (нативный Windows) используется **только** для `api.github.com` — **без** `Invoke-WebRequest`, **без** exfiltration
- **#4** (`New Root/CA Certificate`): `[CRT]` добавляет self-signed CodeSigning сертификат в Trusted Root — **явное действие пользователя**, **не** тихая установка
- **#5** (`ADB Shell Commands`): `adb shell` / `adb push` / `adb pull` для управления эмулятором — **явное действие пользователя**, **без** выполнения кода на хост-машине
- **#6** (`Device Model Modification`): `MuMuManager.exe modify` изменяет модель устройства для **собственных** инстансов — функция приватности, **не** подмена чужих устройств
- **#7** (`File Upload to External Service`): `[VF] VirusTotal Upload` — загрузка файла на VirusTotal для анализа, **явное действие пользователя**, файл上传 только на `www.virustotal.com`, лимит 32 MB
- **#8** (`NTFS Alternate Data Stream`): до v1.18.8 MIME-литерал в коде загрузки VT давал подстроку «-stream», которая вместе с `Set-Content` в том же скриптблоке попадала под правило; **скрипт никогда не читает и не пишет ADS**. С v1.18.9 загрузка идёт через `curl.exe` multipart, литерал удалён

### Благодарности

Имена репортёров (с их согласия) указываются в примечаниях к релизу.

---

## English

> Current for **v1.22.12** (updated 2026-09-17).

### Supported Versions

Security fixes are released only for the latest release.

| Version | Supported |
| --- | --- |
| latest release ([Releases/latest](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)) | ✅ |
| older | ❌ |

### Reporting a Vulnerability

**Do not open a public issue for security reports.**

Use a private channel:

1. **GitHub Private Vulnerability Reporting**: repository tab **Security → Report a vulnerability** — preferred; or
2. Fallback: open an issue labeled `contact-requested` so the maintainer can set up a private channel.

Please include: description and impact, reproduction steps (PoC welcome), affected file (`mumu-menu.ps1` or `bootstrap-update.ps1`), script version (`[V] Version info` or `bootstrap-update.ps1 -Diagnose`), OS / PowerShell / MuMu versions, and any relevant config/log files (**with secrets redacted** — tokens and API keys must be removed first).

**What happens next:**

- The fix is developed on a private branch and ships through the standard tag-driven pipeline with CI verification (ZIP + SHA256 + VT verdicts)
- Public disclosure happens only after the fixed release is published
- You are credited in the acknowledgements and release notes (with your consent)

**Safe harbor:** good-faith research within this policy (no DoS, spam, user spoofing, or access to other people's data) will not result in legal or administrative action from the maintainer. There is no bounty program.

**Not a vulnerability:** documented project features — see "Out of Scope" below.

| Priority | SLA |
|----------|-----|
| Initial response | **within 72 hours** |
| Assessment and fix plan | within 7 days |
| Critical vulnerabilities | emergency patch, out-of-band release |
| Receipt confirmation | **within 24 hours** |

**Continuous automated monitoring:** weekly PSScriptAnalyzer with SARIF upload to the Security tab (Mon 06:00 UTC), CI VirusTotal scan of every release, weekly Release guard audit, grouped Dependabot action updates, actionlint + shellcheck on all workflows.

### Security Architecture

**Token:** DPAPI-encrypted (CurrentUser scope), `.gitignore`-excluded, masked in output, validated before save. Legacy plaintext tokens are migrated with secure wipe (zero-fill before delete).

**Code signing:** Self-signed certificate via `[CRT]`, Code Signing EKU (1.3.6.1.5.5.7.3.3), added to Trusted Root (explicit user action), Authenticode signature on `mumu-menu.ps1`.

**Update integrity:** HTTPS only (TLS 1.2+), `api.github.com` contents API only (never `raw.githubusercontent.com`, never `main`), tag pinned to its commit SHA in bootstrap and `[F]`, SHA-256 of every downloaded file verified against the tag content before `.version` is advanced (issue #20), single-flight lock (issue #24), retry with backoff (3 attempts), backup before overwrite (last 5 kept), dry-run plan modes (`[UP]`, bootstrap `-WhatIf`). Only `.ps1` and `.md` files are downloaded.

**ADB management:** File transfer (`push/pull`), screen capture, interactive shell — all require explicit user consent. Commands are parameterized with argument escaping. Executes only inside the emulator VM.

**Release pipeline security:** tag-driven Release workflow (ZIP + `.sha256` sidecar), CI VirusTotal scan with verdicts in the release body, weekly **Release guard** audit (every release newer than v1.18.6 must ship ZIP + SHA256 + VT verdicts; latest release must match `.version`; discrepancies open an idempotent issue), grouped weekly Dependabot action updates, CI gates: PSScriptAnalyzer + Pester (133 tests) + bootstrap regression + changelog-sync.

### Network Endpoints

The script connects **only** to:

| Domain | Protocol | Purpose | Auth |
|--------|----------|---------|------|
| `api.github.com` | HTTPS (TLS 1.2+) | Version check, updates (contents API), token validation | Bearer token (optional) |
| `www.virustotal.com` | HTTPS (TLS 1.2+) | `[VF]` file upload, scan result lookup | `x-apikey` (VT API key) |

**Not used:** `raw.githubusercontent.com` (updates come from the versioned contents API only), `Invoke-WebRequest`, `Invoke-RestMethod`, WebSocket, SMTP, FTP, DNS-over-HTTPS.

### Threat Model

| Threat | Mitigation | Severity |
|--------|------------|----------|
| GitHub token leakage | DPAPI encryption, `.gitignore`, masked output, secure wipe | 🔴 Critical |
| VT API key leakage | DPAPI encryption (CurrentUser), `.gitignore`, masked output | 🔴 Critical |
| Script tampering | Authenticode signing, SHA256 verification | 🔴 Critical |
| MITM on update | HTTPS only, GitHub API only, content validation | 🟠 High |
| Command injection | Parameterized MuMuManager calls with escaping | 🔴 Critical |
| ADB injection | Parameterized adb calls with argument escaping | 🟠 High |
| Malicious ZIP | Structure validation, file presence check, whole-ZIP verification (`-VerifyZip`) | 🟠 High |
| Stale-CDN tag mapping (tag serves an old commit) | Tag pinned to commit SHA (bootstrap, `[F]`); per-file SHA-256 vs tag content; mismatch = update-fail | 🟠 High |
| Concurrent updaters (file race) | Single-flight lock with atomic create, stale-break after 10 min (issue #24) | 🟡 Medium |
| Empty/broken release in the repo | Release guard: weekly CI audit (ZIP + SHA256 + VT + `.version` sync) | 🟠 High |
| Token replay | Token used for API only, never in URL parameters | 🟡 Medium |
| LSASS injection | No — DPAPI via .NET ProtectedData only | ✅ No risk |

### Execution Policy

Recommended PowerShell policies:

| Policy | Description | Recommendation |
|--------|-------------|----------------|
| `RemoteSigned` | Signed scripts run without prompt | ✅ Recommended |
| `AllSigned` | All scripts must be signed | ⚠️ Requires `[CRT]` signing |
| `Bypass` | No restrictions | 🔴 Testing only |

```powershell
# Current user
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# All users (requires admin)
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
```

### Secure Installation

1. **Download** script only from [Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)
2. **Verify** digital signature: `[V] Version info` → signature status
3. **Set** ExecutionPolicy: `RemoteSigned` (see above)
4. **Create** certificate: `[CRT] Create certificate` → sign the script
5. **Configure** GitHub token: `[K] Update GitHub token` (DPAPI-encrypted)
6. **Configure** VT API key (optional): `[VK] Set VirusTotal API key` for `[VF]`/`[VT]`
7. **Test** dependencies: `[TD] Dependencies test`

### Security Testing

To verify script security:

1. **PSScriptAnalyzer:**
   ```powershell
   Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
   # repo settings (same as CI) - without -Settings you get hundreds of
   # PSAvoidUsingWriteHost noise: the project uses Write-Host by design
   Invoke-ScriptAnalyzer -Path mumu-menu.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
   Invoke-ScriptAnalyzer -Path bootstrap-update.ps1 -Settings PSScriptAnalyzerSettings.psd1 -Severity Warning,Error
   ```
   Expected result for release files: **0 findings** (reference: the `psscriptanalyzer` CI job on the latest `main` commit).

2. **VirusTotal:** check files at [virustotal.com](https://www.virustotal.com) (0/75 — clean)

3. **Signature:** `[V] Version info` → signature status should be `Valid`

4. **Network traffic:** monitor with Wireshark — only HTTPS to `api.github.com`

### Out of Scope

Documented features are not vulnerabilities (see "Note for AV analysts" in README):

**Privacy features (explicit user action):**
- Device-model spoofing and random identifier generation (IMEI/Android ID/MAC) for user-owned instances
- `[DM]` Spoof device model, `[DI]` Random device IDs, `[SIM]` Change SIM operator

**Token storage:**
- DPAPI-protected GitHub token (CurrentUser scope) — decryption only by the same Windows user
- DPAPI-protected VT API key (CurrentUser scope) — used for `[VF]` upload and `[VT]` scan
- Legacy `.github-token` automatically migrated with secure wipe

**VirusTotal integration:**
- `[VF]` Upload file: user-initiated file upload to VirusTotal for analysis (32 MB limit, free API)
- `[VT]` Scan: check project files against VT database, upload if not yet scanned
- `[VK]` API key management: DPAPI-encrypted storage, masked display, explicit user action

**Updates:**
- Read-only update check at startup over HTTPS
- Self-update from tagged GitHub Releases with content verification

**ADB:**
- ADB shell / push / pull for emulator management (explicit user action)

**Sigma False Positives:**
- **#1** (`DMP/HDMP File Creation`): script does NOT create .dmp/.hdmp files — DPAPI stores encrypted text, not memory dumps
- **#2** (`Unsigned Image Loaded Into LSASS`): DPAPI via .NET ProtectedData — no DLL/EXE in LSASS, no injection; script is Authenticode-signed
- **#3** (`Web Request Commands`): `curl.exe` to `api.github.com` ONLY — no `Invoke-WebRequest`, no exfiltration
- **#4** (`New Root/CA Certificate`): `[CRT]` adds self-signed CodeSigning cert to Trusted Root — explicit user action, not silent install
- **#5** (`ADB Shell Commands`): `adb shell` / `adb push` / `adb pull` for MuMu emulator — explicit user action, no host code execution
- **#6** (`Device Model Modification`): `MuMuManager.exe modify` for user's own instances — privacy feature, not impersonation
- **#7** (`File Upload to External Service`): `[VF] VirusTotal Upload` — user-initiated file upload to VirusTotal for analysis, upload only to `www.virustotal.com`, 32 MB limit
- **#8** (`NTFS Alternate Data Stream`): before v1.18.8 a MIME literal in the VT upload code provided the "-stream" substring that, combined with `Set-Content` in the same script block, matched the rule; **the script never reads or writes ADS**. Since v1.18.9 uploads go through `curl.exe` multipart and the literal is removed

### AI/LLM Scanner Response

Automated code analysis tools may flag this script due to its capabilities. Here is a point-by-point response:

| Concern | Reality |
|---------|--------|
| "Spoofing device identifiers" | Privacy feature for user's OWN emulator instances. Requires explicit OK confirmation. Cannot affect real devices. |
| "Handling sensitive information" | GitHub token encrypted via Windows DPAPI (CurrentUser scope). Only the same Windows user can decrypt. No plaintext storage. |
| "Extensive access to emulator internals" | All operations use official Netease `MuMuManager.exe` CLI and standard `adb.exe`. No reverse engineering or undocumented APIs. |
| "Risk of misuse" | Every sensitive operation requires typing "OK" to confirm. Script documents intent in comments and security policy. |
| "Self-update mechanism" | Updates ONLY from tagged GitHub Releases with SHA256 verification. No code execution from untrusted sources. |
| "Certificate management" | Self-signed CodeSigning certificate for script signing only. Explicit user action via `[CRT]` menu. |
