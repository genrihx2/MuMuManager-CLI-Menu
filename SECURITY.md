# Security Policy / Политика безопасности

> Языки: [Русский](#русский) · [English](#english)

---

## Русский

### Поддерживаемые версии

Обновления безопасности выпускаются только для актуального релиза.

| Версия | Поддержка |
| --- | --- |
| v1.13.27+ (см. [Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)) | ✅ |
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

- Первичный ответ: **до 72 часов**
- Оценка и план исправления: до 7 дней
- Критичные уязвимости — патч вне очереди, в приоритете

### Архитектура безопасности

```
┌──────────────────────────────────────────────────────┐
│                    mumu-menu.ps1                     │
│                                                      │
│  ┌─────────┐  ┌──────────┐  ┌────────────────────┐  │
│  │ Token   │  │Certificate│  │ ADB Management     │  │
│  │ DPAPI   │  │ Self-signed│  │ File Transfer      │  │
│  │ Encrypt │  │ CodeSign  │  │ Screen Capture     │  │
│  └─────────┘  └──────────┘  │ Interactive Shell   │  │
│                              └────────────────────┘  │
│  ┌──────────────────────────────────────────────┐    │
│  │              MuMuManager.exe                 │    │
│  │     (Official Netease CLI tool)              │    │
│  │  clone · launch · quit · modify · adb · backup│   │
│  └──────────────────────────────────────────────┘    │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │              GitHub API (curl.exe)            │    │
│  │   api.github.com  ·  raw.githubusercontent.com│   │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

### Модель угроз

| Угроза | Митигация |
|--------|-----------|
| Токен в открытом виде | DPAPI-шифрование (CurrentUser), `.gitignore` для `.github-token` |
| Подмена скрипта | Authenticode-подпись через `[CRT]`, проверка SHA256 при обновлении |
| MITM при обновлении | HTTPS через `api.github.com` / `raw.githubusercontent.com`, проверка содержимого перед записью |
| Вредоносный ZIP | Валидация структуры ZIP, проверка наличия всех файлов |
| Инъекция команд | Параметризованные вызовы `MuMuManager.exe`, escaping аргументов |
| ADB-инъекция | Параметризованные вызовы `adb push/pull/shell`, escaping аргументов |
| LSASS injection | Нет — DPAPI через .NET `ProtectedData`, без DLL/EXE в LSASS |

### Токен безопасности

**Хранение:**
- Windows DPAPI (scope: CurrentUser) в `.github-token.dpapi`
- Плейнтекстовый `.github-token` автоматически мигрируется при первом запуске
- `.gitignore` исключает оба файла из репозитория

**Использование:**
- Только для GitHub API (проверка версий, загрузка обновлений)
- Никогда не логируется и не передаётся третьим лицам
- Можно удалить через `[K] Update GitHub token → [2] Remove`

**Валидация:**
- Тест токена перед сохранением (запрос к `/user`)
- Маскированный вывод: `ghp_***3L0a9i`
- Проверка scope и типа при отображении

### Код-подпись

**Создание:** `[CRT] Create certificate`
- Self-signed сертификат (RSA 2048, SHA256)
- Добавление в Trusted Root — **явное действие пользователя**
- Lifetime: 1 год (проверка через `[V] Version info`)

**Подписание:** автоматическое при обновлении через `[U]`
- `Set-AuthenticodeSignature` на `mumu-menu.ps1`
- PowerShell ExecutionPolicy: `RemoteSigned` или `Bypass`

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

### Управление ADB

Функции управления ADB (`[AF]`, `[AS]`, `[AH]`) работают через локальный ADB-клиент с подключённым эмулятором:

- **File Transfer** (`adb push/pull`): копирование файлов между PC и эмулятором
- **Screen Capture** (`adb shell screencap/screenrecord`): скриншоты и запись экрана
- **Interactive Shell** (`adb shell`): прямой доступ к shell эмулятора

Все операции ADB требуют согласия пользователя (`Confirm-AdbConsent`). ADB-команды передаются параметризованно — аргументы экранируются.

### Что НЕ считается уязвимостью

Это задокументированные возможности проекта (см. «Примечание для AV-аналитиков» в README):

- Спуфинг модели устройства и генерация IMEI / Android ID / MAC — функции приватности для **собственных** инстансов пользователя
- Хранение GitHub-токена через Windows DPAPI (CurrentUser) — расшифровка возможна только от имени того же пользователя Windows
- Read-only проверка обновлений при старте (HTTPS к `api.github.com`) — загрузка файлов происходит только вручную через `[U]`
- Самообновление из тегов GitHub Releases с проверкой содержимого
- ADB shell / push / pull — управление эмулятором, выполняется только по явному запросу пользователя
- **Sigma FP #1** (`DMP/HDMP File Creation`): скрипт **НЕ создаёт** .dmp/.hdmp файлы. DPAPI хранит зашифрованный текст в `.github-token.dpapi` — это не memory dump
- **Sigma FP #2** (`Unsigned Image Loaded Into LSASS`): DPAPI через `ConvertFrom-SecureString` (.NET ProtectedData CurrentUser), **без** загрузки DLL/EXE в LSASS и **без** инъекции; скрипт подписан через `[CRT]`
- **Sigma FP #3** (`Web Request Commands`): `curl.exe` (нативный Windows) используется для `api.github.com` (проверка версий, загрузка обновлений, валидация токена) и `raw.githubusercontent.com` (загрузка файлов обновления); **без** `Invoke-WebRequest`, **без** exfiltration
- **Sigma FP #4** (`New Root/CA Certificate`): `[CRT]` добавляет self-signed CodeSigning сертификат в Trusted Root — **явное действие пользователя** для Authenticode-подписи, **не** тихая установка
- **Sigma FP #5** (`ADB Shell Commands`): `adb shell` / `adb push` / `adb pull` используются для управления эмулятором MuMu (спуфинг ID, скриншоты, передача файлов) — **явное действие пользователя**, **без** выполнения кода на хост-машине
- **Sigma FP #6** (`Device Model Modification`): `MuMuManager.exe modify` изменяет модель устройства для **собственных** инстансов — функция приватности, **не** подмена чужих устройств

### Благодарности

Имена репортёров (с их согласия) указываются в примечаниях к релизу.

---

## English

### Supported Versions

Security fixes are released only for the latest release.

| Version | Supported |
| --- | --- |
| v1.13.27+ ([Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)) | ✅ |
| older | ❌ |

### Reporting a Vulnerability

**Do not open a public issue for security reports.**

Use a private channel:

1. **GitHub Private Vulnerability Reporting**: repository tab **Security → Report a vulnerability**; or
2. Open an issue labeled `contact-requested` so the maintainer can set up a private channel.

Please include: description and impact, reproduction steps (PoC welcome), script version (`[V] Version info`), OS / PowerShell / MuMu versions.

You will receive an initial response within **72 hours**. Critical issues are patched with priority.

### Security Architecture

**Token:** DPAPI-encrypted (CurrentUser scope), `.gitignore`-excluded, masked in output, validated before save.

**Code signing:** Self-signed certificate via `[CRT]`, added to Trusted Root (explicit user action), Authenticode signature on `mumu-menu.ps1`.

**Update integrity:** HTTPS only, retry with backoff (3 attempts), backup before overwrite, version comparison before download.

**ADB management:** File transfer (`push/pull`), screen capture, interactive shell — all require explicit user consent.

### Threat Model

| Threat | Mitigation |
|--------|------------|
| Token leakage | DPAPI encryption, `.gitignore`, masked output |
| Script tampering | Authenticode signing, SHA256 verification |
| MITM on update | HTTPS, GitHub API only, content validation |
| Malicious ZIP | Structure validation, file presence check |
| Command injection | Parameterized MuMuManager calls |
| ADB injection | Parameterized adb calls with argument escaping |
| LSASS injection | No — DPAPI via .NET ProtectedData only |

### Out of Scope

Documented features are not vulnerabilities (see "Note for AV analysts" in README):
- Device-model spoofing and random identifier generation (privacy for user-owned instances)
- DPAPI-protected token storage (CurrentUser scope)
- Read-only update check at startup over HTTPS
- ADB shell / push / pull for emulator management (explicit user action)
- **Sigma FP #1** (`DMP/HDMP File Creation`): script does NOT create .dmp/.hdmp files — DPAPI stores encrypted text, not memory dumps
- **Sigma FP #2** (`Unsigned Image Loaded Into LSASS`): DPAPI via `ConvertFrom-SecureString` (.NET ProtectedData) — no DLL/EXE in LSASS, no injection; script is Authenticode-signed
- **Sigma FP #3** (`Web Request Commands`): `curl.exe` (Windows native) to `api.github.com` and `raw.githubusercontent.com` ONLY — version check, updates, file download, token validation; no `Invoke-WebRequest`, no exfiltration
- **Sigma FP #4** (`New Root/CA Certificate`): `[CRT]` adds self-signed CodeSigning cert to Trusted Root — explicit user action for Authenticode, not silent install
- **Sigma FP #5** (`ADB Shell Commands`): `adb shell` / `adb push` / `adb pull` for MuMu emulator management — explicit user action, no code execution on host
- **Sigma FP #6** (`Device Model Modification`): `MuMuManager.exe modify` changes device model for user's own instances — privacy feature, not impersonation
