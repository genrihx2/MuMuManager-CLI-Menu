# Релизный регламент (tag-driven release.yml)

**Языки:** [Русский](#релизный-регламент-tag-driven-releaseyml) · [English summary](#english-summary)

Относится к тег-ориентированному `.github/workflows/release.yml`, CI-задаче
линта (`lint.yml`) и исправлению YAML-парсинга `virustotal.yml` — смёржено
в апстрим через PR #13, с исправлениями shellcheck в `88677d6`. Статус:
**бэкфилл v1.18.6 выполнен** (2026-09-14), и **v1.18.7 выпущена end-to-end
через Путь 2** (2026-09-14, коммит `1f699bd` → Release run #276): бамп версии
в `main` → тег создан CI → опубликованы ZIP + SHA256 → скан VirusTotal чист
(0 malicious / 0 suspicious, 66 движков). Полный поток проверен на практике.

Все три пути релиза заканчиваются одним конвейером: **тег → проверка
соответствия `$scriptVer` → сборка ZIP из содержимого тега → прикрепление
ZIP + .sha256 к релизу**.

## Путь 1 — релиз пушем тега (рекомендуемый)

```bash
# 1. Убедитесь, что в mumu-menu.ps1 на коммите тега $scriptVer = '<версия>'
git checkout main && git pull
grep -oP "scriptVer\s*=\s*'\K[\d\.]+" mumu-menu.ps1   # например 1.18.7

# 2. Тег и пуш
git tag v1.18.7
git push origin main v1.18.7
```

Workflow запускается по пушу тега и публикует релиз. Если `$scriptVer` не
совпадает с тегом, запуск **падает с ошибкой вместо публикации пустого
релиза** — исправьте несоответствие, удалите/пересоздайте тег и перезапустите.

## Путь 2 — релиз бампом версии (классический поток)

Поднимите `$scriptVer` в `mumu-menu.ps1`, закоммитьте, запушьте в `main`.
Workflow прочитает версию на HEAD, создаст и запушит тег `v<версия>`, если
его ещё нет, и опубликует релиз. Если тег уже существует на origin, запуск —
чистый no-op.

## Путь 3 — ручной запуск (бэкфилл / повторное прикрепление ассетов)

Для существующего тега, у которого релиз без ассетов (например, v1.18.1–v1.18.6):

1. **Предусловие:** `$scriptVer` на теге должен равняться версии тега.
   Проверьте сначала: `git show v1.18.6:mumu-menu.ps1 | grep scriptVer`
2. GitHub → Actions → **Release** → *Run workflow* → введите тег, например
   `v1.18.6` → Run.
3. Результат: ассеты появятся на существующем релизе (при уже существующем
   релизе workflow **падает** на `gh release create` — сначала удалите пустой
   релиз: `gh release delete v1.18.6 --yes`, тег сохраните, перезапустите).

Историческая справка: теги v1.18.1–v1.18.5 содержат `scriptVer = '1.18.0'`,
поэтому версионный гейт их (справедливо) отклоняет — они остаются историей
«только теги». v1.18.6 был добит 2026-09-14: тег переправлен на исправленный
`main`, пустой релиз удалён, CI опубликовал официальные ZIP + SHA256.

## Публикация фикса и бэкфилл GitHub Releases (мейнтейнер)

> ✅ **Выполнено 2026-09-14:** PR #13 смёржен, `v1.18.6` переправлен, пустой
> релиз удалён, CI run #272 опубликовал официальные ZIP + SHA256.

Фикс workflow вступает в силу только после попадания в `main` официального
репозитория:

```bash
git push origin HEAD:main            # прямой пуш (мейнтейнер), либо:
git push origin HEAD:fix/release-pipeline   # затем открыть PR из ветки
```

**Бэкфилл v1.18.6 (актуальный последний релиз, пустой с 2026-09-12):**

```bash
# 1. Переправьте тег на исправленное содержимое (на текущем main scriptVer = 1.18.6)
git tag -f v1.18.6 f3ed722
git push origin v1.18.6 --force       # перезапишет тег на GitHub

# 2. Удалите только ПУСТОЙ релиз (тег сохраните!)
gh release delete v1.18.6 --yes      # без --cleanup-tag

# 3. Force-push тега запускает новый Release workflow ->
#    ZIP + .sha256 собираются из тега и публикуются автоматически.
#    Если не сработало: Actions -> Release -> Run workflow -> tag=v1.18.6
```

**Более старые пустые релизы (v1.18.1–v1.18.5):** в их тегированном
`mumu-menu.ps1` до сих пор `scriptVer = '1.18.0'`, поэтому версионный гейт
их (справедливо) отклонит. Оставьте их как историю «только теги», удалите
пустые релизы — или, самое чистое, выпустите свежий исправленный релиз
(например v1.18.7) через Путь 1, и пусть v1.18.6+ будет проверяемой линией.

**Сканирование VirusTotal (выполнено 2026-09-14):** раньше в репозитории не
было секрета `VT_API_KEY`, поэтому каждый VT-запуск со времён v1.18.0 молча
пропускал загрузку («успех» без сканирования). Теперь секрет настроен,
запуск workflow #205 успешно просканировал релизный ZIP v1.18.6, а будущие
релизы сканируются автоматически при публикации. Вердикты (0 malicious /
0 suspicious) — в разделе «Безопасность» README. Нюанс: релизы, публикуемые
Release workflow через `GITHUB_TOKEN`, не автотриггерят VT workflow (GitHub
подавляет workflow, вызванные `GITHUB_TOKEN`) — запускайте вручную:
Actions → VirusTotal scan → Run workflow → tag = версия.

## Лендинг фиксов извне как внешний контрибьютор (форк + PR)

Справочник на будущее. Использовался для фикса релизного конвейера, который
влётел как PR #13 (смёржен 2026-09-14). Если прямой пуш недоступен — через форк.

```bash
# 0. Однократно: авторизация (делает шаги 1-3 однострочниками)
gh auth login

# 1. Форкните репозиторий под своим аккаунтом (клон не нужен - worktree готов)
gh repo fork genrihx2/MuMuManager-CLI-Menu --clone=false

# 2. Добавьте форк как remote и запушьте ветку под чистым именем
git remote add fork https://github.com/<ВАШ-НИК>/MuMuManager-CLI-Menu.git
git push -u fork HEAD:fix/release-pipeline

# 3. Откройте PR в официальный репозиторий
gh pr create \
  --repo genrihx2/MuMuManager-CLI-Menu \
  --base main \
  --head <ВАШ-НИК>:fix/release-pipeline \
  --title "fix: tag-driven Release workflow + CI lint; repair virustotal.yml YAML" \
  --body-file ISSUE-DRAFT.md
```

Альтернатива без CLI: форк через веб-интерфейс (кнопка «Fork»), пуш обычным
git, затем PR из баннера «Compare & pull request» на GitHub.

**Советы по содержанию PR:**

- Хорошее описание PR совмещает функции issue-репорта (корневая причина,
  доказательства, фикс, устранение). При желании сначала заведите issue и
  ссылайтесь на него как `#N` в PR, чтобы у обсуждения было стабильное место.
- Если мейнтейнеру удобнее патчи в email-стиле, сгенерируйте:
  `git format-patch origin/main..HEAD --stdout > fix.patch` — применяется
  через `git am`.
- PR затрагивает только `.github/workflows/release.yml`,
  `.github/workflows/lint.yml`, `.github/workflows/virustotal.yml`,
  `README.md`, `SKILL.md` — никаких релизных ZIP или рабочих артефактов
  (они намеренно untracked).
- CI на PR: `lint.yml` гоняет actionlint + shellcheck по изменённым
  workflow — исправляйте находки до слияния. Урок PR #13: lint-задача сразу
  поймала до-существовавшие SC2086/SC2129, исправлено в `88677d6`.

**После смержения PR #13** был выполнен бэкфилл из раздела выше: релиз
v1.18.6 теперь содержит `MuMuManager-CLI-Menu-v1.18.6.zip` + `.zip.sha256`,
опубликованные `github-actions[bot]` (run #272).

## Гарантии workflow

- ZIP содержит ровно `mumu-menu.ps1`, `README.md`, `SKILL.md`, `.version`
  из тега — никогда с ветки HEAD.
- Жёсткое падение при несовпадении тега и `$scriptVer` (больше никаких
  молчаливых пустых релизов).
- Идемпотентность: существующий релиз с ассетами → успешный no-op запуск.
- Пользователи проверяют загрузки привычно:
  `sha256sum -c MuMuManager-CLI-Menu-vX.Y.Z.zip.sha256`.

## Регрессионные тесты JSON-детектора

`tests/test-bootstrap-update.ps1` защищает фикс v1.18.8: JSON-проверки в
`bootstrap-update.ps1` не должны срабатывать на raw `mumu-menu.ps1`
(самоматч на литералах `"name":` / `_links` в собственном коде скрипта).
Тест извлекает **настоящую** функцию `Download-File` из
`bootstrap-update.ps1` через AST (без копии логики, которая могла бы
разойтись с продакшеном) и проверяет оба направления:

- T1: загрузка `mumu-menu.ps1` через реальный GitHub contents API — файл
  принимается, парсится как PowerShell и содержит ожидаемые маркеры;
- T2: GitHub-подобный JSON-метадата-ответ — отвергается;
- T3: ответ «Bad credentials» при настроенном токене — отвергается.

Локально: `powershell -ExecutionPolicy Bypass -File tests\test-bootstrap-update.ps1`.
В CI: `.github/workflows/tests.yml` (windows-latest) — запускается при
изменениях `bootstrap-update.ps1`, `mumu-menu.ps1`, `tests/**`.

---

## English summary

Release runbook for the tag-driven `.github/workflows/release.yml` (merged
via PR #13, shellcheck fixes in `88677d6`). **Status:** the v1.18.6 backfill
is done (2026-09-14), and v1.18.7 was cut end-to-end through Path 2
(2026-09-14, commit `1f699bd` → Release run #276): version bump → CI-created
tag → ZIP + SHA256 published → VirusTotal scan clean (0 malicious /
0 suspicious, 66 engines). The full flow is proven.

**Three release paths, one pipeline** (tag → `$scriptVer` gate → ZIP built
from tag content via `git archive` → ZIP + `.sha256` attached):

1. **Tag push (recommended):** ensure `$scriptVer` in `mumu-menu.ps1` equals
   the tag version, then `git tag vX.Y.Z && git push origin main vX.Y.Z`.
   A mismatch fails the run loudly instead of publishing an empty release.
2. **Version bump:** push a `$scriptVer` bump to `main`; CI creates and
   releases the matching tag, or no-ops if it already exists.
3. **Manual dispatch (backfill):** for an existing tag with missing assets —
   verify `$scriptVer` at the tag, delete the empty release if one exists
   (keep the tag), then run the workflow with the tag as input.

**VirusTotal:** the repo previously had no `VT_API_KEY` secret, so VT runs
silently skipped scanning since v1.18.0. The secret is configured now;
releases are scanned on publish, but releases published by the Release
workflow's `GITHUB_TOKEN` do not auto-trigger the VT workflow (GitHub
suppression) — dispatch it manually with the tag as input.

**Guarantees:** the ZIP always contains exactly the four release files from
the tag (never branch HEAD); tag/`$scriptVer` mismatches fail hard; re-runs
are idempotent; users verify downloads with
`sha256sum -c MuMuManager-CLI-Menu-vX.Y.Z.zip.sha256`.
