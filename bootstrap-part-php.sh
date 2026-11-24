# shellcheck shell=bash
# Part: PHP composite actions. Sourced by bootstrap-ci-templates.sh.

w php/setup/action.yml <<'__FILE__'
name: "ci-templates: PHP setup"
description: >-
  Install PHP (with cs2pr, phpcs, phpstan, phpunit tools available) and Composer
  dependencies with caching. composer.lock is required when composer.json exists.
inputs:
  working-directory:
    description: Directory containing composer.json (optional for plain PHP projects).
    default: "."
  runtime-version:
    description: PHP version.
    default: "8.4"
  extensions:
    description: Comma-separated PHP extensions for shivammathur/setup-php.
    default: ""
  coverage-driver:
    description: Coverage driver (pcov, xdebug, none).
    default: "pcov"
runs:
  using: composite
  steps:
    - name: Set up PHP
      uses: shivammathur/setup-php@v2
      with:
        php-version: ${{ inputs.runtime-version }}
        extensions: ${{ inputs.extensions }}
        coverage: ${{ inputs.coverage-driver }}
        tools: composer:v2, cs2pr, phpcs, phpstan, phpunit
    - name: Resolve Composer cache
      id: composer
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: |
        set -euo pipefail
        if [ -f composer.json ]; then
          echo "present=true" >> "$GITHUB_OUTPUT"
          echo "dir=$(composer config cache-files-dir)" >> "$GITHUB_OUTPUT"
          hash="nolock"
          if [ -f composer.lock ]; then hash="$(sha256sum composer.lock | cut -c1-40)"; fi
          echo "key=composer-${RUNNER_OS}-$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-${hash}" >> "$GITHUB_OUTPUT"
        else
          echo "present=false" >> "$GITHUB_OUTPUT"
          echo "::notice title=No composer.json::Plain PHP project; skipping Composer install. Global phpcs/phpstan/phpunit tools are used."
        fi
    - name: Cache Composer downloads
      if: ${{ steps.composer.outputs.present == 'true' }}
      uses: actions/cache@v4
      with:
        path: ${{ steps.composer.outputs.dir }}
        key: ${{ steps.composer.outputs.key }}
        restore-keys: composer-${{ runner.os }}-
    - name: Install dependencies (composer install)
      if: ${{ steps.composer.outputs.present == 'true' }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: |
        set -euo pipefail
        if [ ! -f composer.lock ]; then
          echo "::error title=Missing composer.lock::The CI standard requires a committed composer.lock so installs are reproducible. Run 'composer install' locally and commit composer.lock."
          exit 1
        fi
        composer install --no-interaction --no-progress --prefer-dist
__FILE__

w php/lint/phpcs.xml <<'__FILE__'
<?xml version="1.0"?>
<!-- ci-templates baseline: PSR-12. Used only when the repo has no phpcs.xml(.dist). -->
<ruleset name="ci-templates-baseline">
  <description>ci-templates baseline PHP coding standard (PSR-12)</description>
  <arg name="extensions" value="php"/>
  <arg name="colors"/>
  <arg value="s"/>
  <exclude-pattern>*/vendor/*</exclude-pattern>
  <exclude-pattern>*/node_modules/*</exclude-pattern>
  <rule ref="PSR12"/>
</ruleset>
__FILE__

w php/lint/action.yml <<'__FILE__'
name: "ci-templates: PHP lint"
description: >-
  composer validate, `php -l` syntax check on every PHP file, then the project's
  `composer lint` script or PHP_CodeSniffer (project ruleset, else baseline PSR-12).
  All checks run; errors fail the step and are annotated.
inputs:
  working-directory:
    description: Directory containing the PHP project.
    default: "."
  lint-command:
    description: Command that replaces the coding-standard step (syntax check still runs).
    default: ""
runs:
  using: composite
  steps:
    - name: Lint (php -l + PHP_CodeSniffer)
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        LINT_COMMAND: ${{ inputs.lint-command }}
        BASELINE_DIR: ${{ github.action_path }}
        WD: ${{ inputs.working-directory }}
      run: |
        set -uo pipefail
        status=0
        prefix=""
        if [ "$WD" != "." ]; then prefix="${WD%/}/"; fi

        if [ -f composer.json ]; then
          echo "::group::composer validate"
          composer validate --no-check-publish || status=1
          echo "::endgroup::"
        fi

        echo "::group::PHP syntax check (php -l)"
        checked=0
        while IFS= read -r -d '' f; do
          checked=$((checked + 1))
          if ! out="$(php -l "$f" 2>&1)"; then
            status=1
            line="$(printf '%s' "$out" | sed -n 's/.* on line \([0-9][0-9]*\).*/\1/p' | head -n1)"
            msg="$(printf '%s' "$out" | grep -m1 -i 'error' || printf '%s' "$out" | head -n1)"
            echo "::error file=${prefix}${f#./},line=${line:-1},title=PHP syntax error::${msg}"
          fi
        done < <(find . -type f -name '*.php' -not -path './vendor/*' -not -path './node_modules/*' -not -path './.git/*' -print0)
        echo "Checked ${checked} PHP file(s)"
        echo "::endgroup::"

        if [ -n "$LINT_COMMAND" ]; then
          echo "Running lint-command: $LINT_COMMAND"
          eval "$LINT_COMMAND" || status=1
          exit "$status"
        fi
        if [ -f composer.json ] && php -r '$c=json_decode(file_get_contents("composer.json"),true); exit(isset($c["scripts"]["lint"])?0:1);'; then
          echo "Running project lint script: composer run-script lint"
          composer run-script lint || status=1
          exit "$status"
        fi

        phpcs="phpcs"
        if [ -x vendor/bin/phpcs ]; then phpcs="vendor/bin/phpcs"; fi
        args=()
        if [ ! -f phpcs.xml ] && [ ! -f phpcs.xml.dist ] && [ ! -f .phpcs.xml ] && [ ! -f .phpcs.xml.dist ]; then
          echo "::notice title=Baseline lint::No phpcs.xml found; using the ci-templates baseline (PSR-12). Add phpcs.xml.dist to take control."
          args=(--standard="$BASELINE_DIR/phpcs.xml" .)
        fi
        report="$RUNNER_TEMP/ci-templates-phpcs.xml"
        "$phpcs" --runtime-set ignore_warnings_on_exit 1 --basepath="$GITHUB_WORKSPACE" \
          --report-full --report-checkstyle="$report" "${args[@]}" || status=1
        if [ -s "$report" ]; then cs2pr --graceful-warnings "$report" > /dev/null || true; fi
        exit "$status"
__FILE__

w php/test/action.yml <<'__FILE__'
name: "ci-templates: PHP test"
description: >-
  PHPUnit (project phpunit.xml(.dist) required) with JUnit + Cobertura output, or a custom
  command; summarise results, annotate failed tests and upload reports for the quality stage.
inputs:
  working-directory:
    description: Directory containing the PHP project.
    default: "."
  test-command:
    description: Command that replaces the default PHPUnit run.
    default: ""
  junit-glob:
    description: JUnit XML report glob(s), relative to working-directory.
    default: "reports/junit/**/*.xml"
  coverage-file:
    description: Cobertura coverage file written by PHPUnit.
    default: "coverage/cobertura.xml"
  upload-reports:
    description: Upload JUnit and coverage reports as an artifact ("true"/"false").
    default: "true"
  reports-artifact-name:
    description: Name of the uploaded reports artifact (must be unique per workflow run).
    default: "test-reports"
  retention-days:
    description: Artifact retention in days.
    default: "14"
runs:
  using: composite
  steps:
    - name: Run tests (PHPUnit)
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        TEST_COMMAND: ${{ inputs.test-command }}
        COVERAGE_FILE: ${{ inputs.coverage-file }}
      run: |
        set -euo pipefail
        if [ -n "$TEST_COMMAND" ]; then
          echo "Running test-command: $TEST_COMMAND"
          eval "$TEST_COMMAND"
          exit 0
        fi
        if [ ! -f phpunit.xml ] && [ ! -f phpunit.xml.dist ] && [ ! -f phpunit.dist.xml ]; then
          echo "::error title=No PHPUnit config::No phpunit.xml / phpunit.xml.dist found. The CI standard requires tests; set run-tests: false to opt out explicitly."
          exit 1
        fi
        phpunit="phpunit"
        if [ -x vendor/bin/phpunit ]; then phpunit="vendor/bin/phpunit"; fi
        mkdir -p reports/junit "$(dirname "$COVERAGE_FILE")"
        "$phpunit" --colors=always --log-junit reports/junit/phpunit.xml --coverage-cobertura "$COVERAGE_FILE"
    - name: Summarise test results
      if: ${{ always() }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        JUNIT_GLOB: ${{ inputs.junit-glob }}
        SCRIPTS: ${{ github.action_path }}/../../shared/scripts
      run: python3 "$SCRIPTS/junit_summary.py" "$JUNIT_GLOB" "PHP tests"
    - name: Stage test reports
      id: stage
      if: ${{ always() && inputs.upload-reports == 'true' }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        PATTERNS: ${{ inputs.junit-glob }} ${{ inputs.coverage-file }}
        SCRIPTS: ${{ github.action_path }}/../../shared/scripts
      run: bash "$SCRIPTS/stage.sh" "$RUNNER_TEMP/ci-test-reports" "$PATTERNS"
    - name: Upload test reports
      if: ${{ always() && inputs.upload-reports == 'true' && steps.stage.outputs.count != '0' }}
      uses: actions/upload-artifact@v4
      with:
        name: ${{ inputs.reports-artifact-name }}
        path: ${{ steps.stage.outputs.dir }}
        retention-days: ${{ inputs.retention-days }}
        if-no-files-found: ignore
__FILE__

w php/quality/action.yml <<'__FILE__'
name: "ci-templates: PHP code quality"
description: >-
  composer audit, PHPStan (project phpstan.neon(.dist) or a generated baseline), optional
  project quality command and the shared coverage gate. Every check runs.
inputs:
  working-directory:
    description: Directory containing the PHP project.
    default: "."
  audit:
    description: Run `composer audit` on locked production dependencies ("true"/"false").
    default: "true"
  phpstan-level:
    description: PHPStan level for the generated baseline config (ignored when the repo has its own).
    default: "1"
  coverage-file:
    description: Coverage report path(s)/glob(s) (Cobertura).
    default: "coverage/cobertura.xml"
  coverage-threshold:
    description: Minimum line coverage percent. 0 = report only.
    default: "0"
  quality-command:
    description: Extra project quality command, e.g. "vendor/bin/psalm".
    default: ""
runs:
  using: composite
  steps:
    - name: Dependency audit (composer audit)
      if: ${{ inputs.audit == 'true' }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: |
        set -euo pipefail
        if [ -f composer.lock ]; then
          composer audit --locked --no-dev --abandoned=report
        else
          echo "No composer.lock; nothing to audit."
        fi
    - name: Static analysis (PHPStan)
      if: ${{ always() }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        LEVEL: ${{ inputs.phpstan-level }}
      run: |
        set -euo pipefail
        phpstan="phpstan"
        if [ -x vendor/bin/phpstan ]; then phpstan="vendor/bin/phpstan"; fi
        args=()
        if [ ! -f phpstan.neon ] && [ ! -f phpstan.neon.dist ] && [ ! -f phpstan.dist.neon ]; then
          echo "::notice title=Baseline static analysis::No phpstan.neon found; using a generated baseline at level ${LEVEL}. Add phpstan.neon.dist to take control."
          src="$PWD"
          if [ -d src ]; then src="$PWD/src"; fi
          neon="$RUNNER_TEMP/ci-templates-phpstan.neon"
          {
            echo "parameters:"
            echo "  level: ${LEVEL}"
            echo "  paths:"
            echo "    - '${src}'"
            echo "  excludePaths:"
            echo "    analyseAndScan:"
            echo "      - '*/vendor/*'"
            echo "      - '*/node_modules/*'"
            echo "      - '*/tests/*'"
            if [ -f vendor/autoload.php ]; then
              echo "  bootstrapFiles:"
              echo "    - '${PWD}/vendor/autoload.php'"
            fi
          } > "$neon"
          args=(--configuration="$neon")
        fi
        "$phpstan" analyse --no-progress --memory-limit=1G --error-format=github "${args[@]}"
    - name: Project quality command
      if: ${{ always() && inputs.quality-command != '' }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        QUALITY_COMMAND: ${{ inputs.quality-command }}
      run: |
        set -euo pipefail
        echo "Running quality-command: $QUALITY_COMMAND"
        eval "$QUALITY_COMMAND"
    - name: Coverage gate
      if: ${{ always() }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        COVERAGE_FILE: ${{ inputs.coverage-file }}
        THRESHOLD: ${{ inputs.coverage-threshold }}
        SCRIPTS: ${{ github.action_path }}/../../shared/scripts
      run: python3 "$SCRIPTS/coverage_gate.py" "$COVERAGE_FILE" "$THRESHOLD" "PHP coverage"
__FILE__

w php/package/action.yml <<'__FILE__'
name: "ci-templates: PHP package"
description: >-
  Production `composer install --no-dev -o` and a .tar.gz of the project (or a custom command),
  uploaded as `<name>-<version>-<sha7>`.
inputs:
  working-directory:
    description: Directory containing the PHP project.
    default: "."
  package-command:
    description: Command that replaces the default archive build. Must write under package-path.
    default: ""
  package-path:
    description: Path(s)/glob(s) to upload, relative to working-directory.
    default: "dist/"
  artifact-name:
    description: Artifact base name. Empty = composer.json name (without vendor/), else directory name.
    default: ""
  retention-days:
    description: Artifact retention in days.
    default: "14"
outputs:
  artifact-name:
    description: Uploaded artifact name (<name>-<version>-<sha7>).
    value: ${{ steps.meta.outputs.artifact }}
  version:
    description: composer.json version, else 0.0.0.
    value: ${{ steps.meta.outputs.version }}
runs:
  using: composite
  steps:
    - name: Resolve name and version
      id: meta
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        ARTIFACT_NAME: ${{ inputs.artifact-name }}
      run: |
        set -euo pipefail
        name=""
        version="0.0.0"
        if [ -f composer.json ]; then
          name="$(php -r '$c=json_decode(file_get_contents("composer.json"),true); $n=$c["name"]??""; echo substr($n, strpos($n, "/") === false ? 0 : strpos($n, "/") + 1);')"
          v="$(php -r '$c=json_decode(file_get_contents("composer.json"),true); echo $c["version"]??"";')"
          if [ -n "$v" ]; then version="$v"; fi
        fi
        if [ -n "$ARTIFACT_NAME" ]; then name="$ARTIFACT_NAME"; fi
        if [ -z "$name" ]; then name="$(basename "$PWD")"; fi
        echo "name=${name}" >> "$GITHUB_OUTPUT"
        echo "version=${version}" >> "$GITHUB_OUTPUT"
        echo "artifact=${name}-${version}-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
    - name: Build archive
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        PACKAGE_COMMAND: ${{ inputs.package-command }}
        ARCHIVE: ${{ steps.meta.outputs.name }}-${{ steps.meta.outputs.version }}.tar.gz
      run: |
        set -euo pipefail
        if [ -n "$PACKAGE_COMMAND" ]; then
          echo "Running package-command: $PACKAGE_COMMAND"
          eval "$PACKAGE_COMMAND"
          exit 0
        fi
        if [ -f composer.json ]; then
          composer install --no-dev --optimize-autoloader --no-interaction --no-progress --prefer-dist
        fi
        tar --exclude-vcs --exclude=./dist --exclude=./tests --exclude=./reports \
          --exclude=./coverage --exclude=./node_modules --exclude=./.github --exclude=./.idea \
          -czf "$RUNNER_TEMP/$ARCHIVE" .
        mkdir -p dist
        mv "$RUNNER_TEMP/$ARCHIVE" dist/
        echo "Created dist/$ARCHIVE"
    - name: Stage package
      id: stage
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        PACKAGE_PATH: ${{ inputs.package-path }}
        STAGE_REQUIRE: "1"
        SCRIPTS: ${{ github.action_path }}/../../shared/scripts
      run: bash "$SCRIPTS/stage.sh" "$RUNNER_TEMP/ci-package" "$PACKAGE_PATH"
    - name: Upload package
      uses: actions/upload-artifact@v4
      with:
        name: ${{ steps.meta.outputs.artifact }}
        path: ${{ steps.stage.outputs.dir }}
        retention-days: ${{ inputs.retention-days }}
        if-no-files-found: error
__FILE__
