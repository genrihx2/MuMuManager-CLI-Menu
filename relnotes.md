## MuMuManager CLI Menu v1.13.10

Интерактивное PowerShell-меню для управления MuMu Emulator через официальный `MuMuManager.exe`.

### Исправлено

- `[M]`/`[Y]`/`[Q]`/`[F]`/`[J]`: успешная смена RAM/CPU/разрешения/FPS/Root ошибочно помечалась как «Failed» — MuMuManager на успех отвечает эхом применённых значений без `errcode`, такая проверка теперь считается успехом; ошибкой считается только ненулевой `errcode`/`errmsg`

### Обновление

- Через меню: пункт `[U] Check for updates` → подтвердите загрузку
- Вручную: распакуйте архив и запустите `mumu-menu.ps1`

### Проверено

- VirusTotal: 0 malicious / 0 suspicious (пермалинки в README, раздел «Безопасность»)

**Требования:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x
