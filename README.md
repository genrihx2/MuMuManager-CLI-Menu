# MuMu Manager CLI Menu

Интерактивное PowerShell-меню для управления MuMu Emulator 6.0.

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
- 📋 Просмотр логов
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
1. Скачайте файлы:
   - `mumu-menu.ps1`
   - `mumu-profile.ps1`
2. Поместите в любую папку
3. Запустите `.\mumu-menu.ps1`

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
  [5] Create new emulator
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
  [Z] Security audit

  --- Spoofing ---
  [DM] Spoof device model
  [DI] Random device IDs

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

Script version: 1.12.3
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

При каждом запуске скрипт проверяет GitHub на наличие обновлений:
- Если версия актуальна — тихо продолжает работу
- Если есть обновление — спрашивает подтверждение
- Скачивает обновлённые файлы и перезапускается

Для приватных репозиториев сохраните токен:
```powershell
Set-Content '.github-token' 'ghp_ВашТокенЗдесь'
```

## Компоненты

| Файл | Описание |
|------|----------|
| `mumu-menu.ps1` | Основной скрипт с интерактивным меню |
| `mumu-profile.ps1` | PowerShell-профиль (опционально) |
| `update-readme.ps1` | Синхронизация README с меню/версией скрипта |
| `.github/workflows/sync-readme.yml` | Автообновление README при пуше (GitHub Actions) |
| `SKILL.md` | Документация навыка для AI-агентов |
| `.github-token` | Токен GitHub (не коммитится) |

> Блок меню и версия в README генерируются автоматически из `mumu-menu.ps1`
> (`update-readme.ps1`, запускается локально и в GitHub Actions).

## Лицензия

MIT License

## Автор

[genrihx2](https://github.com/genrihx2)
