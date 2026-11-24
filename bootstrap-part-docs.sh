# shellcheck shell=bash
# Part: README, examples and repo hygiene files. Sourced by bootstrap-ci-templates.sh.

w .gitattributes <<'__FILE__'
* text=auto eol=lf
*.jar binary
__FILE__

w .gitignore <<'__FILE__'
node_modules/
target/
vendor/
dist/
coverage/
reports/
.phpunit.cache/
.phpunit.result.cache
.idea/
.vscode/
*.log
__FILE__

w examples/node-ci.yml <<'__FILE__'
# Copy to .github/workflows/ci.yml in a Node.js repo.
name: CI
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    uses: __CI_TEMPLATES_REPO__/.github/workflows/node-ci.yml@v1
    with:
      coverage-threshold: 60
      # quality-command: npx tsc --noEmit      # TypeScript repos
      # registry-url: https://npm.pkg.github.com
    # secrets:
    #   NPM_TOKEN: ${{ secrets.NPM_TOKEN }}     # only for private registries
__FILE__

w examples/java-ci.yml <<'__FILE__'
# Copy to .github/workflows/ci.yml in a Maven repo.
name: CI
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    uses: __CI_TEMPLATES_REPO__/.github/workflows/java-ci.yml@v1
    with:
      runtime-version: "17"          # match maven.compiler.release
      coverage-threshold: 60
__FILE__

w examples/php-ci.yml <<'__FILE__'
# Copy to .github/workflows/ci.yml in a PHP repo.
name: CI
on:
  pull_request:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    uses: __CI_TEMPLATES_REPO__/.github/workflows/php-ci.yml@v1
    with:
      runtime-version: "8.3"
      extensions: mbstring, intl
      coverage-threshold: 60
    # secrets:
    #   COMPOSER_AUTH: ${{ secrets.COMPOSER_AUTH }}   # only for private packages
__FILE__

w examples/composite-actions.yml <<'__FILE__'
# Advanced: compose the actions yourself (e.g. extra services or a matrix).
name: CI (custom)
on: [pull_request]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node: ["20", "22"]
    services:
      redis:
        image: redis:7
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/node/setup@v1
        with: { runtime-version: "${{ matrix.node }}" }
      - uses: __CI_TEMPLATES_REPO__/node/lint@v1
      - uses: __CI_TEMPLATES_REPO__/node/test@v1
        with: { reports-artifact-name: "test-reports-node${{ matrix.node }}" }
      - uses: __CI_TEMPLATES_REPO__/node/quality@v1
        with: { coverage-threshold: "70" }
__FILE__

w README.md <<'__FILE__'
# ci-templates

Reusable CI modules for **Node.js**, **Java (Maven)** and **PHP**: lint, unit tests, code
quality and packaging. Each stage is a composite action, and each stack has one reusable
workflow that wires the stages together. The standards behind them are in
[docs/STANDARDS.md](docs/STANDARDS.md).

- [Quick start](#quick-start)
- [How each stage decides what to run](#how-each-stage-decides-what-to-run)
- [Reusable workflow inputs](#reusable-workflow-inputs)
- [Composite actions](#composite-actions)
- [Failure output](#failure-output)
- [Versioning and releases](#versioning-and-releases)
- [Developing ci-templates](#developing-ci-templates)

## Quick start

Add `.github/workflows/ci.yml` to your repo (complete files are in [`examples/`](examples)):

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  ci:
    uses: __CI_TEMPLATES_REPO__/.github/workflows/node-ci.yml@v1   # java-ci.yml / php-ci.yml
    with:
      coverage-threshold: 60
```

Each workflow runs four jobs:

```
Lint ─────────────┐
Test ──► Code quality ──► Package
```

Lint and Test run in parallel. Code quality runs only if Test passed or was disabled.
Package runs only if no earlier job failed. Mark `ci / Lint`, `ci / Test`,
`ci / Code quality` and `ci / Package` as required status checks.

What your repo must provide (details in [docs/STANDARDS.md §3.1](docs/STANDARDS.md)):

| Node.js | Java | PHP |
|---|---|---|
| `package-lock.json`, a `test` script, `.nvmrc` | `pom.xml` (Maven wrapper recommended) | `composer.json` + `composer.lock` (if you have dependencies), `phpunit.xml.dist` |

## How each stage decides what to run

Every stage follows the same order: **your command input → your project's own config →
the ci-templates baseline**. When the baseline is used, a `::notice` says so.

| Stage | Node.js | Java | PHP |
|---|---|---|---|
| Lint | `lint-command` → `npm run lint` → project ESLint config → baseline `node/lint/eslint.config.mjs` | `lint-command` → POM-configured `maven-checkstyle-plugin` → `checkstyle.xml` / `config/checkstyle/checkstyle.xml` → baseline `java/lint/checkstyle.xml` | `composer validate` and `php -l` always run, then `lint-command` → `composer lint` → `phpcs.xml(.dist)` → baseline PSR-12 `php/lint/phpcs.xml` |
| Test | `test-command` → `npm test` (missing = error) | `test-command` → `mvn test` + JaCoCo | `test-command` → PHPUnit (missing config = error) with JUnit + Cobertura |
| Quality | `npm audit`, `quality-command`, coverage gate | SpotBugs, `quality-command`, coverage gate | `composer audit`, PHPStan (project neon or baseline), `quality-command`, coverage gate |
| Package | `package-command` → `npm run build --if-present` + `npm pack` | `package-command` → `mvn package -DskipTests` | `package-command` → `composer install --no-dev -o` + `tar.gz` |

`*-command` inputs run with `bash` in `working-directory`. They are trusted repo configuration;
never build them from PR titles or other user-controlled text.

## Reusable workflow inputs

### Common to `node-ci.yml`, `java-ci.yml` and `php-ci.yml`

| Input | Type | Default | Description |
|---|---|---|---|
| `working-directory` | string | `.` | Project directory (monorepos: call the workflow once per project with distinct `artifact-name`s). |
| `runtime-version` | string | Node `''` (→ `.nvmrc` / `.node-version` → `22`), Java `21`, PHP `8.4` | Runtime version. |
| `runs-on` | string | `ubuntu-latest` | Runner label (Linux with bash and python3). |
| `timeout-minutes` | number | `20` | Per-job timeout. |
| `run-lint` / `run-tests` / `run-quality` / `run-package` | boolean | `true` | Turn a stage off. Turning off tests is an explicit, reviewable opt-out. |
| `lint-command` | string | `''` | Replaces the default lint logic (PHP: replaces the coding-standard step only). |
| `test-command` | string | `''` | Replaces the default test command. Write JUnit XML to `junit-glob` to get summaries. |
| `quality-command` | string | `''` | Extra quality check, run in addition to the defaults. |
| `package-command` | string | `''` | Replaces the default packaging. Output must land under `package-path`. |
| `junit-glob` | string | Node/PHP `reports/junit/**/*.xml`, Java `**/target/surefire-reports/TEST-*.xml` | JUnit XML report glob(s), space-separated. |
| `coverage-file` | string | Node `coverage/lcov.info`, Java `**/target/site/jacoco/jacoco.xml`, PHP `coverage/cobertura.xml` | Coverage report (LCOV, JaCoCo or Cobertura are auto-detected). |
| `coverage-threshold` | number | `0` | Minimum line coverage %. `0` = report only. |
| `package-path` | string | Node/PHP `dist/`, Java `target/*.jar target/*.war` | What to upload as the package artifact. |
| `artifact-name` | string | `''` | Artifact base name. Default: package.json name (no scope) / artifactId / composer name (no vendor) / directory name. |
| `retention-days` | number | `14` | Artifact retention. |
| `dependency-review` | boolean | `false` | On pull requests, run GitHub Dependency Review (fails on high severity). |

### Node.js only (`node-ci.yml`)

| Input | Type | Default | Description |
|---|---|---|---|
| `max-warnings` | string | `-1` | ESLint `--max-warnings` for project-config and baseline runs (`0` = warnings fail). |
| `audit` | boolean | `true` | `npm audit --omit=dev`. |
| `audit-level` | string | `high` | `low`, `moderate`, `high` or `critical`. |
| `registry-url` | string | `''` | Private registry; authenticates with secret `NPM_TOKEN`. |

| Secret | Description |
|---|---|
| `NPM_TOKEN` | Optional. Exposed as `NODE_AUTH_TOKEN`. |

### Java only (`java-ci.yml`)

| Input | Type | Default | Description |
|---|---|---|---|
| `distribution` | string | `temurin` | JDK distribution for `actions/setup-java`. |
| `checkstyle-plugin-version` | string | `3.4.0` | Used when the POM does not configure Checkstyle. |
| `jacoco-version` | string | `0.8.12` | JaCoCo agent/report version. |
| `spotbugs` | boolean | `true` | Run SpotBugs. |
| `spotbugs-version` | string | `4.8.6.4` | Used when the POM does not configure SpotBugs. |
| `spotbugs-threshold` | string | `High` | `High`, `Medium` or `Low`. `spotbugs-exclude.xml` at the project root is honoured. |

### PHP only (`php-ci.yml`)

| Input | Type | Default | Description |
|---|---|---|---|
| `extensions` | string | `''` | PHP extensions, comma-separated. |
| `coverage-driver` | string | `pcov` | `pcov`, `xdebug` or `none` (test job only). |
| `audit` | boolean | `true` | `composer audit --locked --no-dev`. |
| `phpstan-level` | string | `1` | Level for the baseline PHPStan config (ignored when `phpstan.neon(.dist)` exists). |

| Secret | Description |
|---|---|
| `COMPOSER_AUTH` | Optional. Composer auth JSON for private packages. |

### Outputs (all workflows)

| Output | Description |
|---|---|
| `artifact-name` | Package artifact: `<name>-<version>-<sha7>`. |
| `version` | Version from package.json / POM / composer.json (`0.0.0` if absent). |

Artifacts per run: `<artifact-name or repo>-test-reports` (JUnit + coverage) and the package artifact.

## Composite actions

Use `__CI_TEMPLATES_REPO__/<stack>/<stage>@v1`. Every action accepts `working-directory`
(default `.`). Run `<stack>/setup` first in the same job. The other inputs match the workflow
inputs of the same name (string-typed, e.g. `"true"`, `"80"`):

| Action | Inputs | Outputs |
|---|---|---|
| `node/setup` | `runtime-version`, `install` (`true`), `registry-url` | `node-version` |
| `node/lint` | `lint-command`, `max-warnings` | |
| `node/test` | `test-command`, `junit-glob`, `coverage-file`, `upload-reports` (`true`), `reports-artifact-name` (`test-reports`), `retention-days` | |
| `node/quality` | `coverage-file`, `coverage-threshold`, `audit`, `audit-level`, `quality-command` | |
| `node/package` | `package-command`, `package-path`, `artifact-name`, `retention-days` | `artifact-name`, `version` |
| `java/setup` | `runtime-version` (`21`), `distribution` | sets env `CI_MVN` (`./mvnw` or `mvn`) |
| `java/lint` | `lint-command`, `checkstyle-plugin-version` | |
| `java/test` | `test-command`, `jacoco-version`, `junit-glob`, `coverage-file`, `upload-reports`, `reports-artifact-name`, `retention-days` | |
| `java/quality` | `spotbugs`, `spotbugs-version`, `spotbugs-threshold`, `coverage-file`, `coverage-threshold`, `quality-command` | |
| `java/package` | `package-command`, `package-path`, `artifact-name`, `retention-days` | `artifact-name`, `version` |
| `php/setup` | `runtime-version` (`8.4`), `extensions`, `coverage-driver` | |
| `php/lint` | `lint-command` | |
| `php/test` | `test-command`, `junit-glob`, `coverage-file`, `upload-reports`, `reports-artifact-name`, `retention-days` | |
| `php/quality` | `audit`, `phpstan-level`, `coverage-file`, `coverage-threshold`, `quality-command` | |
| `php/package` | `package-command`, `package-path`, `artifact-name`, `retention-days` | `artifact-name`, `version` |
| `shared/test-report` | `junit-glob`, `title` | |
| `shared/coverage-gate` | `coverage-file`, `coverage-threshold`, `title` | `percent` |

`reports-artifact-name` must be unique within a workflow run (e.g. include the matrix value).
See [`examples/composite-actions.yml`](examples/composite-actions.yml).

## Failure output

- **Lint errors** fail the Lint job. The tool's own output stays in the log, and errors become file/line
  annotations on the PR (ESLint via setup-node's matcher, Checkstyle via a bundled matcher,
  PHPCS via `cs2pr`, PHP syntax errors via `::error`).
- **Test failures** fail the Test job. The runner's output stays in the log, each failed test gets an
  annotation, and the job summary shows a totals table plus the failed tests.
- **Quality** checks all run even if one fails, so you see every problem at once. The coverage
  gate writes a summary table.
- Missing prerequisites (lockfile, test script, PHPUnit config, pom.xml) fail with a titled
  error that explains the fix.

## Versioning and releases

- Semantic version tags (`v1.2.3`) plus a moving major tag (`v1`). Callers pin `@v1`, or a
  full commit SHA for maximum supply-chain safety.
- Breaking changes (renamed inputs, stricter defaults) need a new major version.
- Release: merge to `main` → tag `vX.Y.Z` → move `v1` (`git tag -f v1 && git push -f origin v1`)
  → run **Release smoke test** (it also runs on tag push).
- The reusable workflows call the composite actions at `@v1`, so a workflow and its actions
  always come from the same major version.

## Developing ci-templates

- `self-test.yml` runs on every PR. It runs actionlint and the shared-script unit tests, runs every
  action against `test-fixtures/<stack>/pass` (must succeed, coverage ≥ 80%) and
  `test-fixtures/<stack>/broken` (lint **and** tests must fail), runs every Node.js and Java action
  against the real `ltl-tracking-api-client-sample-{nodejs,java}` repos with the adoption changes
  in `test-fixtures/samples/` applied (must succeed), and runs informational checks against the
  `ltl-tracking-api-client-sample-*` repos exactly as they are today.
- Local unit tests: `python3 -m unittest discover -s shared/scripts -p 'test_*.py' -v`.
- Requirements: Linux runners (GitHub-hosted `ubuntu-*` or self-hosted with bash, python3, tar).
- Out of scope for v1: Gradle, Python, container images, SonarQube, pnpm/yarn (see
  [docs/STANDARDS.md](docs/STANDARDS.md)).
__FILE__
