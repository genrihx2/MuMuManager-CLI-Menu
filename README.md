# MuMu Manager CLI Menu

Интерактивное PowerShell-меню для управления MuMu Emulator 12.

## Возможности

- 🚀 Запуск, выключение, перезагрузка эмулятора
- 📦 Установка и удаление приложений (APK)
- 📱 ADB-команды
- 🔄 Массовые операции (запуск/выключение всех инстансов)
- 📸 Скриншоты эмулятора через ADB
- 🎨 Progress bar с отслеживанием загрузки
- ⚡ Автообновление из GitHub
- 📋 Информация о версиях
- 🐑 Клонирование инстансов

## Требования

- **Windows 10/11**
- **PowerShell 5.1+** или **PowerShell 7+**
- **MuMu Emulator 12** (версия 4.0.0.3179 или выше)

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

## Использование

### Запуск меню
```powershell
.\mumu-menu.ps1
```

### Меню опций

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

  --- Apps and Settings ---
  [6] List installed apps
  [7] Show settings
  [8] Install APK
  [9] Uninstall app

  --- Batch ---
  [B] Launch all instances
  [D] Shutdown all instances
  [R] Restart all instances
  [I] Install APK to all

  --- Other ---
  [S] Take screenshot
  [A] Run ADB command
  [V] Version info
  [U] Check for updates
  [0] Exit
```

### Примеры

#### Запуск эмулятора
```
Select option: 2
Select instance to launch: 0

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

Script version: 1.1.0
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
| `SKILL.md` | Документация навыка для AI-агентов |
| `.github-token` | Токен GitHub (не коммитится) |

## Лицензия

MIT License

## Автор

[genrihx2](https://github.com/genrihx2)
