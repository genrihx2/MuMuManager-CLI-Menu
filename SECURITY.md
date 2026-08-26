# Security Policy / Политика безопасности

> Языки: [Русский](#русский) · [English](#english)

---

## Русский

### Поддерживаемые версии

Обновления безопасности выпускаются только для актуального релиза.

| Версия | Поддержка |
| --- | --- |
| последний релиз (см. [Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)) | ✅ |
| предыдущие версии | ❌ |

### Как сообщить об уязвимости

**Пожалуйста, не создавайте публичный Issue для уязвимостей.**

Используйте приватный канал:

1. **GitHub Private Vulnerability Reporting**: вкладка репозитория **Security → Report a vulnerability**; либо
2. Email: создайте Issue с пометкой «contact requested», чтобы автор назначил приватный канал (email публикуется намеренно не здесь, чтобы избежать спама).

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

### Что НЕ считается уязвимостью

Это задокументированные возможности проекта (см. «Примечание для AV-аналитиков» в README):

- Спуфинг модели устройства и генерация IMEI / Android ID / MAC — функции приватности для **собственных** инстансов пользователя
- Хранение GitHub-токена через Windows DPAPI (CurrentUser) — расшифровка возможна только от имени того же пользователя Windows
- Read-only проверка обновлений при старте (HTTPS к `api.github.com`) — загрузка файлов происходит только вручную через `[U]`
- Самообновление из тегов GitHub Releases с проверкой содержимого

### Благодарности

Имена репортёров (с их согласия) указываются в примечаниях к релизу (`relnotes.md` / README).

---

## English

### Supported Versions

Security fixes are released only for the latest release.

| Version | Supported |
| --- | --- |
| latest ([Releases](https://github.com/genrihx2/MuMuManager-CLI-Menu/releases/latest)) | ✅ |
| older | ❌ |

### Reporting a Vulnerability

**Do not open a public issue for security reports.**

Use a private channel:

1. **GitHub Private Vulnerability Reporting**: repository tab **Security → Report a vulnerability**; or
2. Open an issue labeled `contact-requested` so the maintainer can set up a private channel.

Please include: description and impact, reproduction steps (PoC welcome), script version (`[V] Version info`), OS / PowerShell / MuMu versions.

You will receive an initial response within **72 hours**. Critical issues are patched with priority.

### Out of Scope

Documented features are not vulnerabilities (see "Note for AV analysts" in README): device-model spoofing and random identifier generation (privacy features for user-owned instances), DPAPI-protected token storage (CurrentUser scope), read-only update check at startup over HTTPS to `api.github.com`.
