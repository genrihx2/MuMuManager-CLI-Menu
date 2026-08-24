# MuMu Manager CLI Menu

Интерактивное PowerShell-меню для управления MuMu Emulator 6.0

## Возможности

- 🚀 Запуск, выключение, перезагрузка эмулятора
- 🐑 Клонирование инстансов
- 🗑️ Удаление инстансов
- ✏️ Переименование инстансов
- 📦 Установка и удаление приложений (APK)
- 📱 ADB-команды
- 🧹 Очистка данных приложения, force stop, запуск приложения
- ⚙️ Тюнинг производительности: FPS, CPU, RAM, разрешение
- 🔓 Включение / выключение Root
- 💾 Экспорт данных инстанса (.mumudata)
- 💾 Резервное копирование папки данных инстанса (vms) с прогрессом
- 🗜️ Сжатие бэкапа в ZIP (встроенный tar, опционально с удалением исходной папки)
- 🎭 Подмена модели устройства (brand / model / код модели)
- 🎲 Генерация случайных IMEI (с контрольной суммой) / Android ID / MAC
- 📸 Скриншоты эмулятора через ADB
- 🪟 Управление окнами (показать/скрыть/расположить)
- 🔄 Массовые операции (все инстансы)
- 📋 Просмотр логов (реальные файлы логов MuMu)
- 🛡️ Аудит безопасности и менеджер GitHub-токена
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
Релизы создаются автоматически при изменении версии в скрипте (GitHub Actions).

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
  [Z] Security audit (disabled)

  --- Spoofing ---
  [DM] Spoof device model
  [DI] Random device IDs

  --- Performance ---
  [F] Set FPS limit
  [Y] Set CPU cores
  [M] Set RAM size
  [Q] Set resolution
  [J] Toggle root

  --- Info ---
  [V] Version info
  [U] Check for updates
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

Script version: 1.13.9
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
- Показывается название релиза
- Перед перезаписью **предыдущие версии сохраняются** в `backup\<дата_время>\`
- Каждый скачанный файл **проверяется на корректность** перед записью (только текстовые `.ps1`/`.md`)
- Таймауты и повторы всех сетевых запросов (через встроенный `curl.exe`)

Для приватных репозиториев сохраните токен через пункт меню `[K] Update GitHub token` — он проверяется и хранится **зашифрованным через Windows DPAPI** в `.github-token.dpapi`; плейнтекстовый `.github-token` мигрируется в зашифрованное хранилище автоматически при первом запуске.

## Безопасность

- **VirusTotal (v1.13.7): 0 malicious / 0 suspicious во всех файлах пакета** — сканы от 24.08.2026; целостность релизного zip сверена с отчётом

| Файл | SHA-256 | Движков | Отчёт |
|------|---------|---------|-------|
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
- Нет инъекций, доступа к системным процессам (lsass и пр.), дампов памяти, обфускации, encoded-команд, persistence
- Эмулятор управляется официальным CLI Netease (`MuMuManager.exe`); ADB-команды выполняются внутри виртуальных машин пользователя
- Мультидвижковый вердикт VirusTotal: 0/61 (пермалинк выше)

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
