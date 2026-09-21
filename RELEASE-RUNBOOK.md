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

## CDN sync — авто-пурж зеркала jsDelivr (.github/workflows/cdn-sync.yml)

Зеркало `cdn.jsdelivr.net/gh/<repo>@main/<path>` кеширует пути на срок до
12 часов: свежий пуш в main может сутки не появляться на зеркале.
Обновляющий транспорт этому не подвержен (его CDN-фолбэк пинится к точному
commit SHA, а не к ветке), поэтому от stale-кеша страдают только внешние
ссылки: README, проба [TN] и ручное скачивание через зеркало.

Воркфлоу закрывает это тремя триггерами:

- **push в main** (4 дистрибутируемых файла + сам воркфлоу) — пурж сразу
  после коммита;
- **еженедельно** (пн 03:07 UTC) — страховочный пурж, самозалечивает любой
  дрейф кеша провайдера;
- **workflow_dispatch** — ручной запуск одной кнопкой.

Механика: запрос к публичному `purge.jsdelivr.net/gh/...@main/<file>` для
`.version` и четырёх файлов; ответ-квитанция со `"status": "finished"`
означает инвалидацию на обоих провайдерах (CF/FY). Отсутствие квитанции не
фатально (зеркало само обновится за ≤12 ч) — воркфлоу даёт `::warning::` и
не роняет ран. Канареечная проверка читает `scriptVer` с зеркала, чтобы
увидеть версию после пуржа в логе.

## Release guard — еженедельный аудит релизов (.github/workflows/release-guard.yml)

Введён 2026-09-16 (коммиты `a230d98`, `b12624a`) как ответ на класс багов
«молчаливые пустые релизы» (v1.18.1–v1.18.6 жили без ассетов по несколько
дней). Конвейер релизов к тому моменту уже был честным — страж добавил
независимый контроль результата. Расписание: каждый понедельник 06:30 UTC
(после security-scan, до европейского рабочего дня), плюс `workflow_dispatch`
(Actions → **Release guard** → Run workflow) и запуск при правках самого
файла workflow. Checkout не делает — только GitHub API через `gh`
(встроенный `--jq`, без внешних зависимостей).

**Что проверяет:**

1. **Комплектация релизов.** Каждый опубликованный (не draft, не prerelease)
   релиз **строго новее v1.18.6** обязан иметь:
   - ZIP с каноническим именем `MuMuManager-CLI-Menu-<тег>.zip`;
   - сайдкар `<имя>.zip.sha256`;
   - секцию вердиктов VirusTotal в теле релиза (маркер `VIRUSTOTAL-VERDICTS`,
     который ставит VT workflow).

   Вне скоупа: черновики, пререлизы, сам v1.18.6 и всё старше — линия
   v1.18.1–v1.18.5 и эпоха v1.2.x осознанно остались «только теги»
   (чистка пустых релизов 2026-09-16, теги сохранены).

2. **Сверка версий.** Тег последнего опубликованного релиза
   (`/releases/latest`) должен совпадать с `.version` на default-ветке.
   Расхождение — симптом вставшего конвейера (бамп версии запушен, а
   Release workflow упал) или релиза, выложенного мимо бампа (ручной тег).

**Результаты прогона:**

- Отчёт всегда попадает в **Step Summary** запуска: таблица по каждому
  релизу (ZIP / SHA256 / VT), вердикт `Status: CLEAN` либо список
  нарушений; сверка версий — в секции «Version consistency».
- **Есть нарушения** → открывается или обновляется один идемпотентный
  issue `[release-guard] Release audit: missing assets/VT verdicts or
  version drift` (тело помечено маркером `<!-- release-guard-audit -->`,
  повторные прогоны обновляют тот же issue), а сам запуск падает —
  бейдж и почта уведомляют мейнтейнера.
- **Прогон чист** → ранее открытый guard-issue закрывается автоматически
  с комментарием; вручную закрывать не нужно.

**Что делать, если issue появился:**

- **Не хватает ZIP/SHA256 у релиза** — рецепт Пути 3 этого регламента:
  удалить пустой релиз с сохранением тега (`gh release delete <тег> --yes`),
  затем Actions → Release → Run workflow с этим тегом (идемпотентно;
  force-push тега тоже запускает публикацию).
- **Не хватает VT-вердиктов** — dispatch VirusTotal scan с тегом;
  уже известные VT файлы переиспользуются, повторный скан быстрый.
- **Version drift: `.version` опережает релизы** — конвейер сломался на
  бампе: смотрите свежие запуски Release workflow на коммите бампа,
  чините причину и перезапускайте (существующий релиз с ассетами →
  успешный no-op), либо выпустите тег через Путь 1.
- **Version drift: релизы опережают `.version`** — релиз выложен мимо
  бампа (например, ручным тегом): подтяните `.version` + `$scriptVer` +
  relnotes/README при следующем бампе или исправьте сразу, чтобы
  автообновлятор `[U]` не застрял на старой версии.

После исправления ускорить закрытие issue можно ручным запуском
Release guard (Actions → Run workflow) — иначе следующий еженедельный
прогон закроет его сам.

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

Отдельно `tests/test-changelog-sync.ps1` (CI: `changelog-check.yml`)
проверяет консистентность changelog в README: каждой строке таблицы
соответствует секция «Что нового» и наоборот, без дублей — иначе
генератор описания релиза молча теряет версию (так пропала v1.19.1).

**VT-скан упал с «Analysis timed out» (v1.19.5, 15.09.2026, повтор):** даже
10-минутного бюджета хватило не всегда — очередь VT продержала новый файл
в `queued` все 40 опросов при успешной загрузке. Дополнительно: перед
объявлением таймаута скан перечитывает объект файла
(`/files/{sha}` — он часто уже содержит статистику, когда
`/analyses/{id}` ещё отстаёт); бюджет поднят до ~20 минут на файл,
`timeout-minutes: 90`. Восстановление прежнее — dispatch с тегом: ZIP
обычно уже отсканирован, повторный прогон почти мгновенный.

**VT-скан упал с «Analysis timed out» (v1.19.3, 14.09.2026):** очередь
VirusTotal может отставать — загрузка висит в `status=queued` дольше
3 минут, и старый лимит в 12 опросов (3 мин) объявлял таймаут и ронял
весь скан, не оставляя вердиктов в заметках. Исправлено: до ~10 минут
опроса на файл (40×15 с), `timeout-minutes: 45`. Восстановление —
dispatch VT workflow с тегом: `workflow_dispatch` запускает файл
workflow с HEAD `main`, поэтому фикс подхватывается без нового тега.
Файлы, уже известные VT, переиспользуются, так что повторный скан
быстрый.

---

## English summary

Release runbook for the tag-driven `.github/workflows/release.yml` (merged
via PR #13, shellcheck fixes in `88677d6`). **Status:** the v1.18.6 backfill
is done (2026-09-14), and v1.18.7 was cut end-to-end through Path 2
(2026-09-14, commit `1f699bd` → Release run #276): version bump → CI-created
tag → ZIP + SHA256 published → VirusTotal scan clean (0 malicious /
0 suspicious, 66 engines). The full flow is proven. v1.19.0
(2026-09-14, commit `03287ed`) went all the way hands-off: version
bump → tag → release → auto VT scan (run #218, `release` event) →
verdicts posted into the release notes - zero manual dispatches.

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
silently skipped scanning since v1.18.0. The secret is configured now.
Since v1.18.10 the scan covers the ZIP plus `mumu-menu.ps1`/`SKILL.md`
extracted from it, and the workflow posts the verdict table with
permalinks into the release notes (marker-scoped «VirusTotal verdicts»
section, idempotent on re-runs).

**Auto-trigger (issue #16, fixed):** GitHub suppresses workflow triggers
for releases created with `GITHUB_TOKEN`, which used to make every VT
scan a manual dispatch. The Release workflow publishes with the
`RELEASE_PAT` secret when present and **valid** (a cheap `/user` probe
runs first; an absent, expired, or insufficient PAT falls back to
`GITHUB_TOKEN` so publishing never breaks) so `on: release published`
fires and the scan runs automatically. Note for future readers: a
`release`-event run executes the workflow file at the tagged commit —
improvements to the VT workflow only post sections automatically for
releases tagged after the improvement lands; older/edited releases can
always be refreshed by dispatching the workflow with the tag as input.
Rebuild note: re-cutting the same tag produces a new ZIP artifact hash
(zip embeds timestamps) while the file contents stay byte-identical to
the tag; the sidecar matches the rebuilt ZIP.

**Guarantees:** the ZIP always contains exactly the five release files from
the tag (never branch HEAD) - including `bootstrap-update.ps1` since v1.18.10,
so every install ships with the current updater; tag/`$scriptVer` mismatches
fail hard; re-runs are idempotent; users verify downloads with
`sha256sum -c MuMuManager-CLI-Menu-vX.Y.Z.zip.sha256`.

**Release guard (2026-09-16, `.github/workflows/release-guard.yml`):** a
weekly watchtower (Mondays 06:30 UTC, plus manual dispatch) that audits the
outcome, not the intent: every published release newer than v1.18.6 must
ship the canonical asset set (ZIP named `MuMuManager-CLI-Menu-<tag>.zip`
plus its `.sha256` sidecar) and the VirusTotal verdicts section in its
body, and the latest published release tag must equal `.version` on the
default branch (drift = the release pipeline stalled, or a release landed
past the bump). The report always lands in the run's Step Summary;
violations open/update one marker-scoped idempotent issue
(`<!-- release-guard-audit -->`) and fail the run; a clean run closes a
stale guard issue automatically. Remediation: empty release → Path 3
(delete the empty release, keep the tag, re-dispatch Release); missing
verdicts → dispatch the VT workflow with the tag; version drift → check
the Release workflow runs for the bump commit and re-run. Checkout-free -
everything goes through `gh api` with the built-in `--jq`.
