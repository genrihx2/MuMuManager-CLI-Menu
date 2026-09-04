# Security Policy / Политика безопасности

> Языки: [Русский](#русский) · [English](#english)

---

## Русский

### Поддерживаемые версии

Обновления безопасности выпускаются только для актуального релиза.

| Версия | Поддержка |
| --- | --- |
| v1.18.1+ (см. [Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)) | ✅ |
| предыдущие версии | ❌ |

### Как сообщить об уязвимости

**Пожалуйста, не создавайте публичный Issue для уязвимостей.**

Используйте приватный канал:

1. **GitHub Private Vulnerability Reporting**: вкладка репозитория **Security → Report a vulnerability**; либо
2. Email: создайте Issue с пометкой «contact requested», чтобы автор назначил приватный канал.

В отчёте укажите:

- Описание проблемы и потенциальное влияние
- Шаги воспроизведения (PoC-скрипт приветствуется)
- Версию скрипта: пункт меню `[V] Version info`
- ОС, версию PowerShell и MuMu Emulator
- Файлы конфигурации/логов, если относятся (без секретов)

### Сроки ответа

| Приоритет | Срок |
|-----------|------|
| Первичный ответ | **до 72 часов** |
| Оценка и план исправления | до 7 дней |
| Критичные уязвимости | патч вне очереди, в приоритете |
| Подтверждение получения | **до 24 часов** |

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
│  │  api.github.com · raw.githubusercontent.com           │    │
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
| MITM при обновлении | HTTPS через `api.github.com` / `raw.githubusercontent.com`, проверка содержимого | 🟠 Высокий |
| Инъекция команд | Параметризованные вызовы `MuMuManager.exe`, escaping аргументов | 🔴 Критический |
| ADB-инъекция | Параметризованные вызовы `adb push/pull/shell`, escaping аргументов | 🟠 Высокий |
| Вредоносный ZIP | Валидация структуры ZIP, проверка наличия всех файлов | 🟠 Высокий |
| Replay-атака на токен | Токен одноразовый для API, не передаётся в URL-параметрах | 🟡 Средний |
| LSASS injection | Нет — DPAPI через .NET `ProtectedData`, без DLL/EXE в LSASS | ✅ Нет риска |

### Сетевые эндпоинты

Скрипт обращается **только** к следующим доменам:

| Домен | Протокол | Использование | Аутентификация |
|-------|----------|---------------|----------------|
| `api.github.com` | HTTPS (TLS 1.2+) | Проверка версий, загрузка обновлений, валидация токена | Bearer token (опционально) |
| `raw.githubusercontent.com` | HTTPS (TLS 1.2+) | Загрузка файлов обновления | Bearer token (опционально) |
| `www.virustotal.com` | HTTPS (TLS 1.2+) | `[VF]` загрузка файлов, проверка результатов сканирования | `x-apikey` (VT API key) |

**Не используются:** `Invoke-WebRequest`, `Invoke-RestMethod`, WebSocket, SMTP, FTP, DNS-over-HTTPS.

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
1. [U] → быстрая проверка версии (сравнение .version с тегом релиза)
2. Если версии различаются — скачивание файлов из GitHub Releases
3. curl.exe с retry (3 попытки, connect-timeout 30с)
4. Бэкап текущей версии в backup/<дата>/
5. Запись новых файлов (только .ps1 и .md)
6. Проверка подписи
```

**Гарантии:**
- Загрузка только текстовых файлов (`.ps1`, `.md`)
- Никаких исполняемых файлов
- Никаких скрытых загрузок
- Пользователь подтверждает каждое действие
- Бэкап перед перезаписью (авто-очистка старше 5)

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
   Invoke-ScriptAnalyzer -Path mumu-menu.ps1 -Severity Warning
   ```

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
- **#3** (`Web Request Commands`): `curl.exe` (нативный Windows) используется **только** для `api.github.com` и `raw.githubusercontent.com` — **без** `Invoke-WebRequest`, **без** exfiltration
- **#4** (`New Root/CA Certificate`): `[CRT]` добавляет self-signed CodeSigning сертификат в Trusted Root — **явное действие пользователя**, **не** тихая установка
- **#5** (`ADB Shell Commands`): `adb shell` / `adb push` / `adb pull` для управления эмулятором — **явное действие пользователя**, **без** выполнения кода на хост-машине
- **#6** (`Device Model Modification`): `MuMuManager.exe modify` изменяет модель устройства для **собственных** инстансов — функция приватности, **не** подмена чужих устройств
- **#7** (`File Upload to External Service`): `[VF] VirusTotal Upload` — загрузка файла на VirusTotal для анализа, **явное действие пользователя**, файл上传 только на `www.virustotal.com`, лимит 32 MB

### Благодарности

Имена репортёров (с их согласия) указываются в примечаниях к релизу.

---

## English

### Supported Versions

Security fixes are released only for the latest release.

| Version | Supported |
| --- | --- |
| v1.18.1+ ([Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)) | ✅ |
| older | ❌ |

### Reporting a Vulnerability

**Do not open a public issue for security reports.**

Use a private channel:

1. **GitHub Private Vulnerability Reporting**: repository tab **Security → Report a vulnerability**; or
2. Open an issue labeled `contact-requested` so the maintainer can set up a private channel.

Please include: description and impact, reproduction steps (PoC welcome), script version (`[V] Version info`), OS / PowerShell / MuMu versions.

| Priority | SLA |
|----------|-----|
| Initial response | **within 72 hours** |
| Assessment and fix plan | within 7 days |
| Critical vulnerabilities | emergency patch, highest priority |
| Receipt confirmation | **within 24 hours** |

### Security Architecture

**Token:** DPAPI-encrypted (CurrentUser scope), `.gitignore`-excluded, masked in output, validated before save. Legacy plaintext tokens are migrated with secure wipe (zero-fill before delete).

**Code signing:** Self-signed certificate via `[CRT]`, Code Signing EKU (1.3.6.1.5.5.7.3.3), added to Trusted Root (explicit user action), Authenticode signature on `mumu-menu.ps1`.

**Update integrity:** HTTPS only (TLS 1.2+), retry with backoff (3 attempts), backup before overwrite, version comparison before download. Only `.ps1` and `.md` files are downloaded.

**ADB management:** File transfer (`push/pull`), screen capture, interactive shell — all require explicit user consent. Commands are parameterized with argument escaping. Executes only inside the emulator VM.

### Network Endpoints

The script connects **only** to:

| Domain | Protocol | Purpose | Auth |
|--------|----------|---------|------|
| `api.github.com` | HTTPS (TLS 1.2+) | Version check, updates, token validation | Bearer token (optional) |
| `raw.githubusercontent.com` | HTTPS (TLS 1.2+) | Update file download | Bearer token (optional) |
| `www.virustotal.com` | HTTPS (TLS 1.2+) | `[VF]` file upload, scan result lookup | `x-apikey` (VT API key) |

**Not used:** `Invoke-WebRequest`, `Invoke-RestMethod`, WebSocket, SMTP, FTP, DNS-over-HTTPS.

### Threat Model

| Threat | Mitigation | Severity |
|--------|------------|----------|
| GitHub token leakage | DPAPI encryption, `.gitignore`, masked output, secure wipe | 🔴 Critical |
| VT API key leakage | DPAPI encryption (CurrentUser), `.gitignore`, masked output | 🔴 Critical |
| Script tampering | Authenticode signing, SHA256 verification | 🔴 Critical |
| MITM on update | HTTPS only, GitHub API only, content validation | 🟠 High |
| Command injection | Parameterized MuMuManager calls with escaping | 🔴 Critical |
| ADB injection | Parameterized adb calls with argument escaping | 🟠 High |
| Malicious ZIP | Structure validation, file presence check | 🟠 High |
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
   Invoke-ScriptAnalyzer -Path mumu-menu.ps1 -Severity Warning
   ```

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
- **#3** (`Web Request Commands`): `curl.exe` to `api.github.com` and `raw.githubusercontent.com` ONLY — no `Invoke-WebRequest`, no exfiltration
- **#4** (`New Root/CA Certificate`): `[CRT]` adds self-signed CodeSigning cert to Trusted Root — explicit user action, not silent install
- **#5** (`ADB Shell Commands`): `adb shell` / `adb push` / `adb pull` for MuMu emulator — explicit user action, no host code execution
- **#6** (`Device Model Modification`): `MuMuManager.exe modify` for user's own instances — privacy feature, not impersonation
- **#7** (`File Upload to External Service`): `[VF] VirusTotal Upload` — user-initiated file upload to VirusTotal for analysis, upload only to `www.virustotal.com`, 32 MB limit

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
