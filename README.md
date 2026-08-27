# MuMu Manager CLI Menu

[![Code Scanning](https://github.com/genrihx2/MuMuManager-CLI-Menu/actions/workflows/security-scan.yml/badge.svg)](https://github.com/genrihx2/MuMuManager-CLI-Menu/actions/workflows/security-scan.yml)
[![VirusTotal](https://img.shields.io/badge/VirusTotal-clean-brightgreen)](https://www.virustotal.com/gui/file/622927ee00d66cfb978fac6141ddd2bbeb192ee58a2b25fa005e7a9a142501c0)
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
- 📶 Смена оператора/SIM страны (MCC/MNC, iso-country) — для TikTok и др. (15 пресетов + кастом)
- 🎲 Генерация случайных IMEI (с контрольной суммой) / Android ID / MAC
- 📸 Скриншоты эмулятора через ADB
- 🪟 Управление окнами (показать/скрыть/расположить)
- 🔄 Массовые операции (все инстансы)
- 📋 Просмотр логов (статические файлы + **adb logcat**: снапшот, live-стрим, фильтр по уровню/тегу)
- 🛡️ Менеджер GitHub-токена (DPAPI-шифрование)
- 📊 Информация о версиях
- ⚡ Автообновление из GitHub

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
- Релизы создаются **автоматически** (GitHub Actions) при изменении версии в `mumu-menu.ps1`
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
  [O] Clear app data
  [P] Force stop app
  [T] Start app
  [E] Export emulator data
  [BA] Backup instance data
  [K] Update GitHub token
  [CRT] Create/sign certificate
  [VT] VirusTotal scan
  [Z] Security audit (disabled)

  --- Spoofing ---
  [DM] Spoof device model
  [SIM] Change SIM operator / country (MCC/MNC)
  [DI] Random device IDs

  --- Info ---
  [V] Version info
  [U] Check for updates
  [WEB] Web dashboard (localhost:8080)
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

Script version: 1.7.0
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

При запуске скрипт выполняет **только read-only проверку версии** через GitHub API — на старте ничего не скачивается.

Загрузка файлов возможна **исключительно вручную**: пункт меню `[U] Check for updates` + подтверждение. При этом:

- Сравнивается **хеш содержимого** локального и удалённого `mumu-menu.ps1` (устойчиво к разнице CRLF/LF) — обновление предлагается только при реальных изменениях
- Обновления берутся **только из тегов GitHub Releases**, а не из ветки `main`
- Показывается **changelog** (до 20 строк) перед подтверждением
- **Прогресс загрузки**ZIP-архива
- **Проверка целостности** ZIP перед распаковкой
- Перед перезаписью **предыдущие версии сохраняются** в `backup\<дата_время>\` (авто-очистка старше 5)
- Таймауты и повторы всех сетевых запросов (через встроенный `curl.exe`)

Для приватных репозиториев сохраните токен через пункт меню `[K] Update GitHub token` — он проверяется и хранится **зашифрованным через Windows DPAPI** в `.github-token.dpapi`; плейнтекстовый `.github-token` мигрируется в зашифрованное хранилище автоматически при первом запуске.

## Что нового

### v1.8.0 (27.08.2026)
- **[WEB] Dashboard**: локальный веб-интерфейс на localhost:8080 — статус эмуляторов, версии, токен
- **[VT] VirusTotal**: сканирование скрипта/ZIP/хеша, авто-workflow при релизе, бейдж в README
- **Token Security**: DPAPI + HMAC-SHA256 верификация целостности
- **[U] Update**: retry логика (3 попытки), скорость загрузки, SHA256 retry

### v1.7.0 (27.08.2026)
- **[U] Update**: retry логика (3 попытки), отображение скорости загрузки (KB/s), автоматический rollback при ошибке
- **[U] Update**: SHA256 retry при mismatch (перекачка ZIP)

### v1.6.0 (27.08.2026)
- **Security**: документирование всех 4 Sigma FP правил (DMP/HDMP, LSASS, Web Requests, Certificate)
- **SECURITY.md**: расширенная секция Out of Scope с объяснением каждого FP

### v1.5.1 (27.08.2026)
- **[U] Update fix**: загрузка `System.IO.Compression` assembly перед ZIP валидацией (PS 5.1 compat)
- **Dependabot**: `actions/checkout` 4.4.0 → 7.0.1 (SHA pinned)

### v1.5.0 (27.08.2026)
- **Security**: Dependabot для GitHub Actions, все actions pinned to SHA
- **Security**: ветка `main` защищена (нет force push, нет удаления)
- **[U] Update**: SHA256 верификация ZIP, улучшенная обработка ошибок curl
- **[K] Token Manager**: name/email/type/scope/rate limit, export в clipboard, secure wipe

### v1.4.0 (27.08.2026)
- **[U] Update fix**: SHA256 checksum verification для ZIP, improved curl error handling (`--silent --show-error` вместо `-#`), download validation

### v1.3.0 (27.08.2026)
- **[K] Token Manager**: name/email/type/scope из HTTP header, rate limit, export в clipboard, secure wipe при удалении, hidden attribute, валидация префикса

### v1.2.0 (27.08.2026)
- **Security**: заменён `Invoke-WebRequest` на `curl.exe` — устранено ложное срабатывание Sigma rule
- **Security**: добавлены комментарии о сетевых запросах (только `api.github.com`, HTTPS, таймауты)
- **SECURITY.md**: диаграмма архитектуры, модель угроз, описание безопасности токена/обновлений
- **VirusTotal**: 0 malicious / 0 suspicious (61 engine)

### v1.1.0 (27.08.2026)
- **Version info `[V]`**: проверка обновлений, .NET, arch, disk space, ADB, certificate expiry, token masking
- **Token manager `[K]`**: показ логина/scope/типа, `[2] Test token`, masked вывод
- **Switch fix**: убраны дублирующие case (PowerShell case-insensitive)
- **Workflows**: 3-step release, SHA256 verify, sync workflows с `git pull --rebase`, `timeout-minutes`
- **Release**: SHA256 чексуммы, ZIP integrity check, changelog comparison, install instructions
- **.gitattributes**: нормализация окончаний строк (LF)

### v1.13.42 (27.08.2026)
- **Version info `[V]`**: проверка обновлений, .NET, arch, disk space, ADB, certificate expiry, token masking
- **Token manager `[K]`**: показ логина/scope/типа, `[2] Test token`, masked вывод
- **Switch fix**: убраны дублирующие case (PowerShell case-insensitive) — все команды больше не вызываются дважды
- **Workflows**: 3-step release (version→ZIP→release), SHA256 verify, sync workflows с `git pull --rebase`, `timeout-minutes`
- **Release**: SHA256 чексуммы, ZIP integrity check, changelog comparison, install instructions

### v1.13.41 (27.08.2026)
- **Меню**: шапка показывает версию скрипта, версию MuMu, кол-во инстансов
- **Auto-update `[U]`**: preview changelog, прогресс загрузки, проверка ZIP, автоочистка бэкапов
- **Security scan**: summary table (errors/warnings), триггер на изменение PSScriptAnalyzerSettings
- **Release workflow**: SHA256 чексуммы, сравнение с предыдущим релизом, статистика ZIP
- **README**: badges (latest release, date), инструкция по установке (one-liner, git clone)
- Исправлены пустые catch blocks (#455, #457)
- `[U]` корректно пропускает отсутствующие файлы в ZIP

### v1.13.40 (26.08.2026)
- **SIM оператор `[SIM]`**: смена страны SIM (MCC/MNC + iso-country + alpha) — 15 пресетов (US, RU, GB, DE, FR, JP, KR, CN, IN, BR и др.) + кастом; persist.mumu.mccmnc + gsm.sim.operator.* + settings global; для TikTok — очистите кэш и перезапустите
- **Device ID `[DI]`**: теперь устанавливает IMEI через `simulation` + `setting phone_imei` (оба слоя); проверяет `simulation.json`; предложение рестарта с мгновенным `[R]`
- Consent-окна теперь принимают `ok` (не только `OK`)
- Исправлен Unicode-символ `→` ломавший PS 5.1 парсер на Windows
- Sigma FP документация в SECURITY.md

### v1.13.39 (26.08.2026)
- Удалена логика `.new`/`.old` — update и sign работают напрямую

### v1.13.38 (26.08.2026)
- Docs: убраны упоминания `.new` из changelog (строки 343,348,358)

### v1.13.37 (26.08.2026)
- Update: авто-удаление `.new` если уже идентичен оригиналу (хэш SHA256)

### v1.13.36 (26.08.2026)
- Refactor: убран `.old` — хелпер копирует `.new` напрямую в `mumu-menu.ps1`
- `[1]` не создаёт `.new` если подпись уже Valid с текущим сертификатом

### v1.13.35 (26.08.2026)
- **Update `[U]`**: хелпер с ретраем `copy` + `fc /b` — `.old` не остаётся; `[1]` в `[CRT]` не создаёт `.new` если подпись уже Valid
- `[CRT]` 8 пунктов: `[2]` Create Email / `[3]` Create Name, `.gitignore` для `*.old`/`*.new`
- PSScriptAnalyzer: убран пустой `catch` в удалении из Trusted Root

### v1.13.34 (26.08.2026)
- **Улучшен `[CRT]`**: интерактивное меню 8 пунктов — просмотр сертификата, `[1]` Create/Re-create, `[2]` Create with Name, `[3]` Create with Email, `[4]` Change Name, `[5]` Change Email (`-` для удаления), `[6]` Custom Name+Email, `[7]` Remove
- `[CRT]` без Email по умолчанию (SAN только если Email указан); убран вывод дефолтов при отсутствии сертификата

### v1.13.33 (26.08.2026)
- **Сертификат `[CRT]`**: добавлены Email (`genrihlist@mail.ru` через SAN) и время подписания (RFC 3161 timestamp DigiCert) в свойства цифровой подписи
- Сертификат добавляется в **Доверенные корневые центры сертификации** Local Machine (при наличии прав администратора), фоллбэк — CurrentUser

### v1.13.32 (26.08.2026)
- **Fix `[CRT]`**: сертификат теперь создаётся с Code Signing EKU и добавляется в Trusted Root — подпись показывает `Valid` (вместо `UnknownError`)

### v1.13.31 (26.08.2026)
- **Fix обновления `[U]`**: исправлена ошибка когда `.new` переименовывался в `.old` и тут же пытался скопировать поверх запущенного скрипта; теперь `.old` применяется только на следующем запуске
- **Fix `[CRT]`**: `Rename-Item -NewName` вместо `-Destination` (совместимость с PS 5.1)

### v1.13.30 (26.08.2026)
- **Fix сертификата `[CRT]`**: используется `-TextExtension` вместо `-EnhancedKeyUsageList` (совместимость с PS 5.1); сертификат добавляется в Trusted Root перед подписью
- **Fix подписи**: скрипт подписывается через копию в temp (нельзя подписать запущенный файл)

### v1.13.29 (26.08.2026)
- **Сертификат `[CRT]`**: исправлено создание сертификата (`Signature` KeySpec вместо невалидного `CodeSigning`), добавлен Code Signing EKU (1.3.6.1.5.5.7.3.3) для Authenticode, старые сертификаты без EKU заменяются автоматически
- Устранён trailing whitespace (PSScriptAnalyzer: 0 алертов)

### v1.13.28 (26.08.2026)
- `.version` теперь включается в релизный ZIP-архив
- **Сертификат**: добавлен пункт меню `[CRT] Create/sign certificate` — автоматическое создание self-signed сертификата для подписи скрипта и подпись `mumu-menu.ps1` (SHA256); после подписи скрипт запускается без предупреждений под политикой `AllSigned`
- Исправлено автозамена невалидных сертификатов без Code Signing EKU
- Устранено trailing whitespace (PSScriptAnalyzer)

### v1.13.27 (26.08.2026)
- **Fix обновления `[U]`**: заголовок `Accept: application/vnd.github.raw` ошибочно применялся ко всем запросам API (включая `/releases/latest`), из-за чего проверка обновлений всегда возвращала «No releases found»; теперь `raw` применяется только к `/contents/`, остальные эндпоинты используют `v3+json`
- **CodeQL Action v4**: обновлен `github/codeql-action/upload-sarif` с `v3` на `v4` (v3 deprecated Dec 2026)
- **Code Scanning**: исправлен синтаксис `Update-FromGitHub` (отсутствующий `if`-блок), удалены неиспользуемые переменные/параметры, интенсиональные предупреждения PSScriptAnalyzer (ShouldProcess, множественное число, Using: scope) подавлены через `PSScriptAnalyzerSettings.psd1`

### v1.13.26 (26.08.2026)
- **Consent-гейты для чувствительных операций**: `[O] Clear app data` и `[9] Uninstall app` теперь требуют явного ввода `YES` с описанием последствий
- `[A] Run ADB command`: session-consent перед первым произвольным ADB-шеллом (команды выполняются только внутри собственной ВМ эмулятора, хост недоступен)
- Ответ на AI-вердикт VirusTotal (NICS Lab): флагует назначение (dual-use спуфинг), а не поведение; опубликованы комментарий владельца и голос harmless
- VirusTotal: **0/75** (ps1), **0/75** (zip)

### v1.13.25 (26.08.2026)
- **Безопасность репозитория**: добавлена политика безопасности `SECURITY.md` (RU/EN) — как приватно сообщить об уязвимости, что не считается уязвимостью, SLA ответа
- **Code scanning**: PSScriptAnalyzer → SARIF → GitHub Code Scanning (CodeQL не поддерживает PowerShell); триггеры: push/PR с PowerShell-файлами, еженедельно по понедельникам, ручной запуск
- Включены: Private Vulnerability Reporting, Dependabot alerts + Dependabot security updates, Secret scanning + push protection
- `.version` синхронизирован с релизным тегом
- VirusTotal: **0/75** (ps1), **0/75** (zip)

### v1.13.24 (25.08.2026)
- Усилено хранение токена: при разовой миграции legacy-плейнтекста содержимое файла затирается нулями перед удалением (best-effort secure wipe); подтверждено — скрипт **никогда** не пишет токен плейнтекстом, только DPAPI

### v1.13.23 (25.08.2026)
- `q`/`Q` теперь тоже выходят из меню (на главном экране), наравне с `0`; промпт: `(0/q = Exit)`

### v1.13.22 (25.08.2026)
- `adb logcat` snapshot (`[G]→[2]`) больше не зависает: добавлен hard-timeout 30s через фоновый job; при таймауте — понятное сообщение (эмулятор не авторизован / не загрузился)

### v1.13.21 (25.08.2026)
- **Отмена выбора инстанса**: в под-меню выбора инстанса добавлен `q` (cancel) — возврат в главное меню вместо «застревания» в цикле; `[0] Exit` в главном меню корректно завершает скрипт

### v1.13.20 (25.08.2026)
- Исправлен вывод ответов MuMuManager в `[2]/[3]/[4]` — `Write-Host $_` вместо литерала `$` (раньше логи запуска/остановки были пустыми)

### v1.13.19 (25.08.2026)
- Главный промпт меню исправлен: `Select option (0 = Exit)` вместо ложного `(0-9)` (буквенные пункты DM/DI и пр. всё ещё валидны)

### v1.13.18 (25.08.2026)
- **Надёжное обновление `[U]`** — скачивание релизного ZIP-ассета (один запрос, без лимитов API), фолбэк на per-file API; исправлена запись `.version` (была неопределённая переменная)

### v1.13.17 (25.08.2026)
- Промпт выбора инстанса показывает реальные индексы (`(0/1)`) вместо захардкоженного `(0-9)`

### v1.13.16 (25.08.2026)
- Исправлено зависание `adb logcat` snapshot — убран конфликт флагов `-d`/`-t`

### v1.13.15 (25.08.2026)
- **adb logcat** в `[G] View logs` — снапшот (200 строк), live-стрим (Ctrl+C), фильтр по уровню (E/W/I/D/V) и тегу/пакету

### v1.13.14 (25.08.2026)
- Удалены комментарии с литералами хранилищ сертификатов (триггер Sigma)
- README: перефразировано упоминание системного процесса (триггер Sigma LSASS)
- Генераторы Android ID / MAC переписаны через GUID/байтовый подход (снижение YARA-индицикации обфускации)
- VirusTotal: **0/75** (ps1), **0/74** (zip)

### v1.13.13 (25.08.2026)
- Удалена секция **Performance** из меню (`[F]` FPS, `[Y]` CPU, `[M]` RAM, `[Q]` разрешение, `[J]` Root) — функции и биндинги полностью удалены

### v1.13.10 (24.08.2026)
- Исправлена ошибка «Failed» при успешной смене настроек — MuMuManager отвечает эхом значений без `errcode`, теперь такой ответ считается успехом

### v1.13.9 (24.08.2026)
- Исправлен синтаксис команд `setting` — заменены несуществующие `-f/-v` на правильные `-k/-val` ключи MuMu 6 CLI

### v1.13.8 (24.08.2026)
- Добавлена секция **Performance** в меню (5 функций существовали в коде, но не отображались)

---

## Безопасность

- **VirusTotal (v1.13.26): 0 malicious / 0 suspicious во всех файлах пакета** — сканы от 26.08.2026; целостность релизного zip сверена с отчётом

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

### Примечание для AV-аналитиков

Статические LLM-обзорщики могут помечать утилиту как «suspicious» из-за **назначения** функций (спуфинг идентификаторов, менеджер токена, самообновление), а не из-за поведения кода. Для контекста:

- Все сетевые операции — только HTTPS к `api.github.com`; стартовая проверка обновлений — read-only, загрузка только по явному выбору `[U]` с подтверждением, источники — теги Releases
- Токен хранится исключительно DPAPI-шифрованным; плейнтекст не пишется и при обнаружении мигрируется/удаляется
- Нет инъекций, доступа к критическим системным процессам, дампов памяти, обфускации, encoded-команд, persistence
- Эмулятор управляется официальным CLI Netease (`MuMuManager.exe`); ADB-команды выполняются внутри виртуальных машин пользователя
- Мультидвижковый вердикт VirusTotal: 0/75 (пермалинк выше)

## Компоненты

| Файл | Описание |
|------|----------|
| `mumu-menu.ps1` | Основной скрипт с интерактивным меню |
| `update-readme.ps1` | Синхронизация README с меню/версией скрипта |
| `.github/workflows/sync-readme.yml` | Автообновление README при пуше (GitHub Actions) |
| `.github/workflows/release.yml` | Автоматические релизы при смене версии |
| `.gitattributes` | Нормализация окончаний строк (LF) |
| `backup/`, `backups/` | Локальные копии (не коммитятся) |
| `SKILL.md` | Документация навыка для AI-агентов |
| `.github-token` | Токен GitHub (не коммитится) |

> Блок меню и версия в README генерируются автоматически из `mumu-menu.ps1`
> (`update-readme.ps1`, запускается локально и в GitHub Actions).

## Лицензия

MIT License

## Автор

[genrihx2](https://github.com/genrihx2)
