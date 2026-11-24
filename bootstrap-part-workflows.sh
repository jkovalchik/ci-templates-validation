# shellcheck shell=bash
# Part: reusable workflows (one per stack). Sourced by bootstrap-ci-templates.sh.

w .github/workflows/node-ci.yml <<'__FILE__'
name: Node.js CI (reusable)

on:
  workflow_call:
    inputs:
      working-directory: { type: string, default: ".", description: "Directory containing package.json." }
      runtime-version: { type: string, default: "", description: "Node.js version; empty = .nvmrc/.node-version, else 22." }
      runs-on: { type: string, default: "ubuntu-latest", description: "Runner label." }
      timeout-minutes: { type: number, default: 20, description: "Per-job timeout." }
      run-lint: { type: boolean, default: true, description: "Run the Lint job." }
      run-tests: { type: boolean, default: true, description: "Run the Test job." }
      run-quality: { type: boolean, default: true, description: "Run the Code quality job." }
      run-package: { type: boolean, default: true, description: "Run the Package job." }
      lint-command: { type: string, default: "", description: "Replaces the default lint logic." }
      test-command: { type: string, default: "", description: "Replaces npm test." }
      quality-command: { type: string, default: "", description: "Extra quality command (e.g. npx tsc --noEmit)." }
      package-command: { type: string, default: "", description: "Replaces build + npm pack." }
      max-warnings: { type: string, default: "-1", description: "ESLint --max-warnings (-1 = unlimited)." }
      junit-glob: { type: string, default: "reports/junit/**/*.xml", description: "JUnit report glob(s)." }
      coverage-file: { type: string, default: "coverage/lcov.info", description: "Coverage report (LCOV/Cobertura)." }
      coverage-threshold: { type: number, default: 0, description: "Minimum line coverage %; 0 = report only." }
      audit: { type: boolean, default: true, description: "Run npm audit on production deps." }
      audit-level: { type: string, default: "high", description: "npm audit failure level." }
      registry-url: { type: string, default: "", description: "npm registry URL (uses secret NPM_TOKEN)." }
      package-path: { type: string, default: "dist/", description: "Packaged output to upload." }
      artifact-name: { type: string, default: "", description: "Artifact base name; empty = package.json name." }
      retention-days: { type: number, default: 14, description: "Artifact retention days." }
      dependency-review: { type: boolean, default: false, description: "Run dependency review on pull requests." }
    secrets:
      NPM_TOKEN:
        required: false
        description: Token for private npm registries (exposed as NODE_AUTH_TOKEN).
    outputs:
      artifact-name:
        description: Uploaded package artifact name.
        value: ${{ jobs.package.outputs.artifact-name }}
      version:
        description: package.json version.
        value: ${{ jobs.package.outputs.version }}

permissions:
  contents: read

env:
  NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
  REPORTS_ARTIFACT: ${{ format('{0}-test-reports', inputs.artifact-name || github.event.repository.name || 'ci') }}

jobs:
  lint:
    name: Lint
    if: ${{ inputs.run-lint }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/node/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          registry-url: ${{ inputs.registry-url }}
      - uses: __CI_TEMPLATES_REPO__/node/lint@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          lint-command: ${{ inputs.lint-command }}
          max-warnings: ${{ inputs.max-warnings }}

  test:
    name: Test
    if: ${{ inputs.run-tests }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/node/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          registry-url: ${{ inputs.registry-url }}
      - uses: __CI_TEMPLATES_REPO__/node/test@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          test-command: ${{ inputs.test-command }}
          junit-glob: ${{ inputs.junit-glob }}
          coverage-file: ${{ inputs.coverage-file }}
          reports-artifact-name: ${{ env.REPORTS_ARTIFACT }}
          retention-days: ${{ inputs.retention-days }}

  quality:
    name: Code quality
    needs: test
    if: ${{ !cancelled() && inputs.run-quality && (needs.test.result == 'success' || needs.test.result == 'skipped') }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/node/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          registry-url: ${{ inputs.registry-url }}
      - name: Download test reports
        if: ${{ needs.test.result == 'success' }}
        continue-on-error: true
        uses: actions/download-artifact@v4
        with:
          name: ${{ env.REPORTS_ARTIFACT }}
          path: ${{ inputs.working-directory }}
      - uses: __CI_TEMPLATES_REPO__/node/quality@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          coverage-file: ${{ inputs.coverage-file }}
          coverage-threshold: ${{ inputs.coverage-threshold }}
          audit: ${{ inputs.audit }}
          audit-level: ${{ inputs.audit-level }}
          quality-command: ${{ inputs.quality-command }}

  package:
    name: Package
    needs: [lint, test, quality]
    if: ${{ !cancelled() && inputs.run-package && !contains(needs.*.result, 'failure') }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    outputs:
      artifact-name: ${{ steps.package.outputs.artifact-name }}
      version: ${{ steps.package.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/node/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          registry-url: ${{ inputs.registry-url }}
      - id: package
        uses: __CI_TEMPLATES_REPO__/node/package@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          package-command: ${{ inputs.package-command }}
          package-path: ${{ inputs.package-path }}
          artifact-name: ${{ inputs.artifact-name }}
          retention-days: ${{ inputs.retention-days }}

  dependency-review:
    name: Dependency review
    if: ${{ inputs.dependency-review && github.event_name == 'pull_request' }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/dependency-review-action@v4
        with:
          fail-on-severity: high
__FILE__

w .github/workflows/java-ci.yml <<'__FILE__'
name: Java CI (reusable)

on:
  workflow_call:
    inputs:
      working-directory: { type: string, default: ".", description: "Directory containing pom.xml." }
      runtime-version: { type: string, default: "21", description: "JDK version." }
      distribution: { type: string, default: "temurin", description: "JDK distribution." }
      runs-on: { type: string, default: "ubuntu-latest", description: "Runner label." }
      timeout-minutes: { type: number, default: 20, description: "Per-job timeout." }
      run-lint: { type: boolean, default: true, description: "Run the Lint job." }
      run-tests: { type: boolean, default: true, description: "Run the Test job." }
      run-quality: { type: boolean, default: true, description: "Run the Code quality job." }
      run-package: { type: boolean, default: true, description: "Run the Package job." }
      lint-command: { type: string, default: "", description: "Replaces the default Checkstyle run." }
      test-command: { type: string, default: "", description: "Replaces mvn test (+JaCoCo)." }
      quality-command: { type: string, default: "", description: "Extra quality command." }
      package-command: { type: string, default: "", description: "Replaces mvn package -DskipTests." }
      checkstyle-plugin-version: { type: string, default: "3.4.0", description: "maven-checkstyle-plugin version." }
      jacoco-version: { type: string, default: "0.8.12", description: "jacoco-maven-plugin version." }
      spotbugs: { type: boolean, default: true, description: "Run SpotBugs." }
      spotbugs-version: { type: string, default: "4.8.6.4", description: "spotbugs-maven-plugin version." }
      spotbugs-threshold: { type: string, default: "High", description: "SpotBugs threshold (High/Medium/Low)." }
      junit-glob: { type: string, default: "**/target/surefire-reports/TEST-*.xml", description: "JUnit report glob(s)." }
      coverage-file: { type: string, default: "**/target/site/jacoco/jacoco.xml", description: "JaCoCo XML report glob." }
      coverage-threshold: { type: number, default: 0, description: "Minimum line coverage %; 0 = report only." }
      package-path: { type: string, default: "target/*.jar target/*.war", description: "Packaged output to upload." }
      artifact-name: { type: string, default: "", description: "Artifact base name; empty = artifactId." }
      retention-days: { type: number, default: 14, description: "Artifact retention days." }
      dependency-review: { type: boolean, default: false, description: "Run dependency review on pull requests." }
    outputs:
      artifact-name:
        description: Uploaded package artifact name.
        value: ${{ jobs.package.outputs.artifact-name }}
      version:
        description: Maven project.version.
        value: ${{ jobs.package.outputs.version }}

permissions:
  contents: read

env:
  REPORTS_ARTIFACT: ${{ format('{0}-test-reports', inputs.artifact-name || github.event.repository.name || 'ci') }}

jobs:
  lint:
    name: Lint
    if: ${{ inputs.run-lint }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/java/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          distribution: ${{ inputs.distribution }}
      - uses: __CI_TEMPLATES_REPO__/java/lint@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          lint-command: ${{ inputs.lint-command }}
          checkstyle-plugin-version: ${{ inputs.checkstyle-plugin-version }}

  test:
    name: Test
    if: ${{ inputs.run-tests }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/java/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          distribution: ${{ inputs.distribution }}
      - uses: __CI_TEMPLATES_REPO__/java/test@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          test-command: ${{ inputs.test-command }}
          jacoco-version: ${{ inputs.jacoco-version }}
          junit-glob: ${{ inputs.junit-glob }}
          coverage-file: ${{ inputs.coverage-file }}
          reports-artifact-name: ${{ env.REPORTS_ARTIFACT }}
          retention-days: ${{ inputs.retention-days }}

  quality:
    name: Code quality
    needs: test
    if: ${{ !cancelled() && inputs.run-quality && (needs.test.result == 'success' || needs.test.result == 'skipped') }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/java/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          distribution: ${{ inputs.distribution }}
      - name: Download test reports
        if: ${{ needs.test.result == 'success' }}
        continue-on-error: true
        uses: actions/download-artifact@v4
        with:
          name: ${{ env.REPORTS_ARTIFACT }}
          path: ${{ inputs.working-directory }}
      - uses: __CI_TEMPLATES_REPO__/java/quality@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          spotbugs: ${{ inputs.spotbugs }}
          spotbugs-version: ${{ inputs.spotbugs-version }}
          spotbugs-threshold: ${{ inputs.spotbugs-threshold }}
          coverage-file: ${{ inputs.coverage-file }}
          coverage-threshold: ${{ inputs.coverage-threshold }}
          quality-command: ${{ inputs.quality-command }}

  package:
    name: Package
    needs: [lint, test, quality]
    if: ${{ !cancelled() && inputs.run-package && !contains(needs.*.result, 'failure') }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    outputs:
      artifact-name: ${{ steps.package.outputs.artifact-name }}
      version: ${{ steps.package.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/java/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          distribution: ${{ inputs.distribution }}
      - id: package
        uses: __CI_TEMPLATES_REPO__/java/package@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          package-command: ${{ inputs.package-command }}
          package-path: ${{ inputs.package-path }}
          artifact-name: ${{ inputs.artifact-name }}
          retention-days: ${{ inputs.retention-days }}

  dependency-review:
    name: Dependency review
    if: ${{ inputs.dependency-review && github.event_name == 'pull_request' }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/dependency-review-action@v4
        with:
          fail-on-severity: high
__FILE__

w .github/workflows/php-ci.yml <<'__FILE__'
name: PHP CI (reusable)

on:
  workflow_call:
    inputs:
      working-directory: { type: string, default: ".", description: "PHP project directory." }
      runtime-version: { type: string, default: "8.4", description: "PHP version." }
      extensions: { type: string, default: "", description: "PHP extensions (comma-separated)." }
      coverage-driver: { type: string, default: "pcov", description: "pcov, xdebug or none." }
      runs-on: { type: string, default: "ubuntu-latest", description: "Runner label." }
      timeout-minutes: { type: number, default: 20, description: "Per-job timeout." }
      run-lint: { type: boolean, default: true, description: "Run the Lint job." }
      run-tests: { type: boolean, default: true, description: "Run the Test job." }
      run-quality: { type: boolean, default: true, description: "Run the Code quality job." }
      run-package: { type: boolean, default: true, description: "Run the Package job." }
      lint-command: { type: string, default: "", description: "Replaces the coding-standard step (php -l still runs)." }
      test-command: { type: string, default: "", description: "Replaces the PHPUnit run." }
      quality-command: { type: string, default: "", description: "Extra quality command." }
      package-command: { type: string, default: "", description: "Replaces the archive build." }
      phpstan-level: { type: string, default: "1", description: "PHPStan level for the baseline config." }
      audit: { type: boolean, default: true, description: "Run composer audit." }
      junit-glob: { type: string, default: "reports/junit/**/*.xml", description: "JUnit report glob(s)." }
      coverage-file: { type: string, default: "coverage/cobertura.xml", description: "Cobertura coverage file." }
      coverage-threshold: { type: number, default: 0, description: "Minimum line coverage %; 0 = report only." }
      package-path: { type: string, default: "dist/", description: "Packaged output to upload." }
      artifact-name: { type: string, default: "", description: "Artifact base name; empty = composer name or dir." }
      retention-days: { type: number, default: 14, description: "Artifact retention days." }
      dependency-review: { type: boolean, default: false, description: "Run dependency review on pull requests." }
    secrets:
      COMPOSER_AUTH:
        required: false
        description: Composer auth JSON for private repositories.
    outputs:
      artifact-name:
        description: Uploaded package artifact name.
        value: ${{ jobs.package.outputs.artifact-name }}
      version:
        description: composer.json version (or 0.0.0).
        value: ${{ jobs.package.outputs.version }}

permissions:
  contents: read

env:
  COMPOSER_AUTH: ${{ secrets.COMPOSER_AUTH }}
  REPORTS_ARTIFACT: ${{ format('{0}-test-reports', inputs.artifact-name || github.event.repository.name || 'ci') }}

jobs:
  lint:
    name: Lint
    if: ${{ inputs.run-lint }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/php/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          extensions: ${{ inputs.extensions }}
          coverage-driver: none
      - uses: __CI_TEMPLATES_REPO__/php/lint@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          lint-command: ${{ inputs.lint-command }}

  test:
    name: Test
    if: ${{ inputs.run-tests }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/php/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          extensions: ${{ inputs.extensions }}
          coverage-driver: ${{ inputs.coverage-driver }}
      - uses: __CI_TEMPLATES_REPO__/php/test@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          test-command: ${{ inputs.test-command }}
          junit-glob: ${{ inputs.junit-glob }}
          coverage-file: ${{ inputs.coverage-file }}
          reports-artifact-name: ${{ env.REPORTS_ARTIFACT }}
          retention-days: ${{ inputs.retention-days }}

  quality:
    name: Code quality
    needs: test
    if: ${{ !cancelled() && inputs.run-quality && (needs.test.result == 'success' || needs.test.result == 'skipped') }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/php/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          extensions: ${{ inputs.extensions }}
          coverage-driver: none
      - name: Download test reports
        if: ${{ needs.test.result == 'success' }}
        continue-on-error: true
        uses: actions/download-artifact@v4
        with:
          name: ${{ env.REPORTS_ARTIFACT }}
          path: ${{ inputs.working-directory }}
      - uses: __CI_TEMPLATES_REPO__/php/quality@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          audit: ${{ inputs.audit }}
          phpstan-level: ${{ inputs.phpstan-level }}
          coverage-file: ${{ inputs.coverage-file }}
          coverage-threshold: ${{ inputs.coverage-threshold }}
          quality-command: ${{ inputs.quality-command }}

  package:
    name: Package
    needs: [lint, test, quality]
    if: ${{ !cancelled() && inputs.run-package && !contains(needs.*.result, 'failure') }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    outputs:
      artifact-name: ${{ steps.package.outputs.artifact-name }}
      version: ${{ steps.package.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - uses: __CI_TEMPLATES_REPO__/php/setup@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          runtime-version: ${{ inputs.runtime-version }}
          extensions: ${{ inputs.extensions }}
          coverage-driver: none
      - id: package
        uses: __CI_TEMPLATES_REPO__/php/package@v1
        with:
          working-directory: ${{ inputs.working-directory }}
          package-command: ${{ inputs.package-command }}
          package-path: ${{ inputs.package-path }}
          artifact-name: ${{ inputs.artifact-name }}
          retention-days: ${{ inputs.retention-days }}

  dependency-review:
    name: Dependency review
    if: ${{ inputs.dependency-review && github.event_name == 'pull_request' }}
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/dependency-review-action@v4
        with:
          fail-on-severity: high
__FILE__
