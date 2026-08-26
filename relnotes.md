## MuMuManager CLI Menu v1.13.25

Интерактивное PowerShell-меню для управления MuMu Emulator через официальный `MuMuManager.exe`.

### Что нового
### v1.13.25 (26.08.2026)
- **Безопасность репозитория**: добавлена политика безопасности `SECURITY.md` (RU/EN) — как приватно сообщить об уязвимости, что не считается уязвимостью, SLA ответа
- **Code scanning**: PSScriptAnalyzer → SARIF → GitHub Code Scanning (CodeQL не поддерживает PowerShell); триггеры: push/PR с PowerShell-файлами, еженедельно по понедельникам, ручной запуск
- Включены: Private Vulnerability Reporting, Dependabot alerts + Dependabot security updates, Secret scanning + push protection
- `.version` синхронизирован с релизным тегом

### Обновление
- Через меню: пункт `[U] Check for updates` → подтвердите загрузку
- Вручную: распакуйте архив и запустите `mumu-menu.ps1`

### Проверено
- VirusTotal: 0 malicious / 0 suspicious (пермалинки в README, раздел «Безопасность»)

**Требования:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x
