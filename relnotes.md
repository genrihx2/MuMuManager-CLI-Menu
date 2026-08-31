# MuMuManager CLI Menu

Интерактивное PowerShell-меню для управления MuMu Emulator через официальный `MuMuManager.exe`.

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
