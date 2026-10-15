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
- 📊 Информация о версиях
- ⚡ Автообновление из GitHub
- 🗄️ Загрузка репозитория (git clone, ZIP, отдельный файл)

Для полного списка функций и опций см. SKILL.md или запустите меню.

## Требования

- Windows 10/11
- PowerShell 5.1+ или PowerShell 7+
- MuMu Emulator 6.x (тестировано на V6.7.1, минимально поддерживаемая версия: 4.0.0.3179)

## Установка

Через Git:

```powershell
git clone https://github.com/genrihx2/MuMuManager-CLI-Menu.git
cd MuMuManager-CLI-Menu
.\mumu-menu.ps1
```

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

### v10.0.0 (14.10.2026)

- Major release: semantic-version bump to `v10.0.0` to mark a stable, production-ready milestone and unify public-facing versioning.
- Documentation and release notes reorganized for clarity (relnotes.md and README.md).
- No behavioral changes to the runtime scripts in this commit — this release primarily records the versioning milestone and documentation cleanups.
- Pester suite: 260/261 passed (1 README changelog sync test pending the table update).

**EN summary (v10.0.0):** Production-ready milestone at v10.0.0 with synchronized version markers across `mumu-menu.ps1`, `.version`, `relnotes.md` and `README.md`. Pester suite: 260/261 passing.

---

| Версия | Дата | Изменения |
|--------|------|-----------|
| v10.0.0 | 14.10.2026 | Major release: semantic-version bump to v10.0.0, documentation reorganized, Pester 260/261 |

## Где смотреть полные изменения (changelog)

Полный список релизов и подробный changelog хранится в `relnotes.md` и в релизах GitHub: https://github.com/genrihx2/MuMuManager-CLI-Menu/releases

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
  [U] Check for updates
  [UP] Update plan (dry-run)
  [F] Verify installation (files vs release tag)
  [ST] Install status (read-only)
  [J] Update journal
  [DIAG] Problem diagnostics
  [RB] Rollback from backup
  [DL] Download repository
  [CR] Create release
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
