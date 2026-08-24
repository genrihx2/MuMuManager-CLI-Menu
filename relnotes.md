## MuMuManager CLI Menu v1.13.9

Интерактивное PowerShell-меню для управления MuMu Emulator через официальный `MuMuManager.exe`.

### Исправлено

- `[M]` Set RAM: команда `setting -f ram` не поддерживалась MuMu 6 (`errcode -1, not handle cmd`) — теперь используется корректный ключ `performance_mem.custom` + `performance_mode=custom`, значения в ГБ
- `[F]` FPS → `max_frame_rate`, `[Y]` CPU → `performance_cpu.custom`, `[Q]` разрешение → `resolution_width/height.custom`, `[J]` Root → `root_permission` (все были с тем же сломанным синтаксисом `-f/-v`)
- Определение успеха теперь считает пустой ответ валидным; после CPU/RAM/разрешения показывается напоминание о перезапуске
- Убран паразитный символ в блоке catch функции Version info (`[V]`)

### Обновление

- Через меню: пункт `[U] Check for updates` → подтвердите загрузку
- Вручную: распакуйте архив и запустите `mumu-menu.ps1`

### Проверено

- VirusTotal: 0 malicious / 0 suspicious (пермалинки в README, раздел «Безопасность»)

**Требования:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x
