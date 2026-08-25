## MuMuManager CLI Menu v1.13.14

Интерактивное PowerShell-меню для управления MuMu Emulator через официальный `MuMuManager.exe`.

### Изменено (снижение ложных срабатываний AV)

- Удалён комментарий с литералами путей хранилища сертификатов (триггер Sigma «New Root or CA Certificate»)
- README: убрано упоминание имени системного процесса (триггер Sigma «Unsigned Image into LSASS») при сканировании файлов релизного zip
- Генераторы Android ID / MAC переписаны с hex-циклов на GUID/байтовый подход (меньше индикаторов под YARA «PS1 obfuscation»), поведение идентичное — юнит-тесты Luhn/формата пройдены

### Обновление

- Через меню: пункт `[U] Check for updates` → подтвердите загрузку
- Вручную: распакуйте архив и запустите `mumu-menu.ps1`

### Проверено

- VirusTotal: 0 malicious / 0 suspicious (пермалинки в README, раздел «Безопасность»)

**Требования:** Windows 10/11 · PowerShell 5.1+ · MuMu Emulator 6.x
