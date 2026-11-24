# shellcheck shell=bash
# Part: Node.js composite actions. Sourced by bootstrap-ci-templates.sh.

w node/setup/action.yml <<'__FILE__'
name: "ci-templates: Node.js setup"
description: Install Node.js (with npm cache) and the project's dependencies using npm ci.
inputs:
  working-directory:
    description: Directory containing package.json, relative to the repository root.
    default: "."
  runtime-version:
    description: Node.js version. Empty = read .nvmrc / .node-version, falling back to 22.
    default: ""
  install:
    description: Run `npm ci` after installing Node.js ("true"/"false").
    default: "true"
  registry-url:
    description: Optional npm registry URL; writes an .npmrc that uses NODE_AUTH_TOKEN.
    default: ""
outputs:
  node-version:
    description: The installed Node.js version.
    value: ${{ steps.node.outputs.node-version }}
runs:
  using: composite
  steps:
    - name: Resolve Node.js version and cache
      id: detect
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        REQUESTED: ${{ inputs.runtime-version }}
        WD: ${{ inputs.working-directory }}
      run: |
        set -euo pipefail
        prefix=""
        if [ "$WD" != "." ]; then prefix="${WD%/}/"; fi
        version="$REQUESTED"
        file=""
        if [ -z "$version" ]; then
          for f in .nvmrc .node-version; do
            if [ -z "$file" ] && [ -f "$f" ]; then file="${prefix}${f}"; fi
          done
          if [ -z "$file" ]; then version="22"; fi
        fi
        cache=""
        lock=""
        if [ -f package-lock.json ]; then
          cache="npm"
          lock="${prefix}package-lock.json"
        fi
        {
          echo "version=${version}"
          echo "file=${file}"
          echo "cache=${cache}"
          echo "lock=${lock}"
        } >> "$GITHUB_OUTPUT"
    - name: Set up Node.js
      id: node
      uses: actions/setup-node@v4
      with:
        node-version: ${{ steps.detect.outputs.version }}
        node-version-file: ${{ steps.detect.outputs.file }}
        cache: ${{ steps.detect.outputs.cache }}
        cache-dependency-path: ${{ steps.detect.outputs.lock }}
        registry-url: ${{ inputs.registry-url }}
    - name: Install dependencies (npm ci)
      if: ${{ inputs.install == 'true' }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: |
        set -euo pipefail
        if [ ! -f package-lock.json ]; then
          echo "::error title=Missing package-lock.json::The CI standard requires a committed package-lock.json so installs are reproducible. Run 'npm install' locally and commit package-lock.json."
          exit 1
        fi
        npm ci --no-audit --no-fund
__FILE__

w node/lint/eslint.config.mjs <<'__FILE__'
// ci-templates baseline ESLint config, used only when a repo has no `lint`
// script and no ESLint config of its own. Correctness-focused: eslint:recommended
// plus Node.js globals. Paths are relative to the working directory.
import { readFileSync } from "node:fs";
import js from "@eslint/js";
import globals from "globals";

let isModule = false;
try {
  isModule = JSON.parse(readFileSync("package.json", "utf8")).type === "module";
} catch {
  // no package.json: treat .js as CommonJS
}

export default [
  {
    ignores: [
      "**/node_modules/",
      "**/dist/",
      "**/build/",
      "**/coverage/",
      "**/reports/",
      "**/vendor/",
      "**/*.min.js",
    ],
  },
  js.configs.recommended,
  {
    files: ["**/*.js"],
    languageOptions: { sourceType: isModule ? "module" : "commonjs" },
  },
  {
    languageOptions: {
      ecmaVersion: "latest",
      globals: { ...globals.node },
    },
    rules: {
      "no-unused-vars": ["error", { args: "after-used", caughtErrors: "none", ignoreRestSiblings: true }],
    },
  },
];
__FILE__

w node/lint/action.yml <<'__FILE__'
name: "ci-templates: Node.js lint"
description: >-
  Lint with the project's `npm run lint`, else the project's ESLint config, else the
  ci-templates baseline ESLint config. ESLint errors fail the step and are annotated.
inputs:
  working-directory:
    description: Directory containing package.json.
    default: "."
  lint-command:
    description: Command that replaces the default lint logic entirely.
    default: ""
  max-warnings:
    description: ESLint --max-warnings for project-config and baseline runs (-1 = unlimited).
    default: "-1"
runs:
  using: composite
  steps:
    - name: Lint (ESLint)
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        LINT_COMMAND: ${{ inputs.lint-command }}
        MAX_WARNINGS: ${{ inputs.max-warnings }}
        BASELINE_DIR: ${{ github.action_path }}
      run: |
        set -euo pipefail
        if [ -n "$LINT_COMMAND" ]; then
          echo "Running lint-command: $LINT_COMMAND"
          eval "$LINT_COMMAND"
          exit 0
        fi
        if node -e "process.exit(require('./package.json').scripts?.lint ? 0 : 1)"; then
          echo "Running project lint script: npm run lint"
          npm run lint
          exit 0
        fi
        if compgen -G "eslint.config.*" > /dev/null || compgen -G ".eslintrc*" > /dev/null; then
          echo "Found a project ESLint config; running the project's ESLint"
          npx --no-install eslint --max-warnings "$MAX_WARNINGS" .
          exit 0
        fi
        echo "::notice title=Baseline lint::No 'lint' script or ESLint config found; using the ci-templates baseline ESLint config. Add a 'lint' script to package.json to take control."
        tool="$RUNNER_TEMP/ci-templates-eslint"
        mkdir -p "$tool"
        cp "$BASELINE_DIR/eslint.config.mjs" "$tool/eslint.config.mjs"
        npm install --prefix "$tool" --no-save --no-audit --no-fund --loglevel=error eslint@9 @eslint/js@9 globals@15
        "$tool/node_modules/.bin/eslint" --config "$tool/eslint.config.mjs" --max-warnings "$MAX_WARNINGS" .
__FILE__

w node/test/action.yml <<'__FILE__'
name: "ci-templates: Node.js test"
description: >-
  Run `npm test` (required) or a custom command, summarise JUnit results, annotate failed
  tests and upload test/coverage reports for the quality stage.
inputs:
  working-directory:
    description: Directory containing package.json.
    default: "."
  test-command:
    description: Command that replaces `npm test`.
    default: ""
  junit-glob:
    description: JUnit XML report glob(s), relative to working-directory.
    default: "reports/junit/**/*.xml"
  coverage-file:
    description: Coverage report path(s)/glob(s) to upload (LCOV or Cobertura).
    default: "coverage/lcov.info"
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
    - name: Run tests
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        TEST_COMMAND: ${{ inputs.test-command }}
      run: |
        set -euo pipefail
        if [ -n "$TEST_COMMAND" ]; then
          echo "Running test-command: $TEST_COMMAND"
          eval "$TEST_COMMAND"
          exit 0
        fi
        if ! node -e "process.exit(require('./package.json').scripts?.test ? 0 : 1)"; then
          echo "::error title=No test script::package.json has no \"test\" script. The CI standard requires one; set run-tests: false to opt out explicitly."
          exit 1
        fi
        npm test
    - name: Summarise test results
      if: ${{ always() }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        JUNIT_GLOB: ${{ inputs.junit-glob }}
        SCRIPTS: ${{ github.action_path }}/../../shared/scripts
      run: python3 "$SCRIPTS/junit_summary.py" "$JUNIT_GLOB" "Node.js tests"
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

w node/quality/action.yml <<'__FILE__'
name: "ci-templates: Node.js code quality"
description: >-
  npm dependency audit, optional project quality command (e.g. tsc --noEmit) and the shared
  coverage gate. Every check runs; the step fails if any check failed.
inputs:
  working-directory:
    description: Directory containing package.json.
    default: "."
  coverage-file:
    description: Coverage report path(s)/glob(s) (LCOV or Cobertura).
    default: "coverage/lcov.info"
  coverage-threshold:
    description: Minimum line coverage percent. 0 = report only.
    default: "0"
  audit:
    description: Run `npm audit` on production dependencies ("true"/"false").
    default: "true"
  audit-level:
    description: Minimum advisory severity that fails the audit (low, moderate, high, critical).
    default: "high"
  quality-command:
    description: Extra project quality command, e.g. "npx tsc --noEmit".
    default: ""
runs:
  using: composite
  steps:
    - name: Dependency audit (npm audit)
      if: ${{ inputs.audit == 'true' }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        AUDIT_LEVEL: ${{ inputs.audit-level }}
      run: npm audit --omit=dev --audit-level="$AUDIT_LEVEL"
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
      run: python3 "$SCRIPTS/coverage_gate.py" "$COVERAGE_FILE" "$THRESHOLD" "Node.js coverage"
__FILE__

w node/package/action.yml <<'__FILE__'
name: "ci-templates: Node.js package"
description: >-
  `npm run build --if-present` + `npm pack` (or a custom command), then upload the result as
  `<name>-<version>-<sha7>`.
inputs:
  working-directory:
    description: Directory containing package.json.
    default: "."
  package-command:
    description: Command that replaces build + npm pack. Must write its output under package-path.
    default: ""
  package-path:
    description: Path(s)/glob(s) to upload, relative to working-directory.
    default: "dist/"
  artifact-name:
    description: Artifact base name. Empty = package.json name (without @scope/).
    default: ""
  retention-days:
    description: Artifact retention in days.
    default: "14"
outputs:
  artifact-name:
    description: Uploaded artifact name (<name>-<version>-<sha7>).
    value: ${{ steps.meta.outputs.artifact }}
  version:
    description: Version from package.json.
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
        version="$(node -p "require('./package.json').version || '0.0.0'")"
        name="$ARTIFACT_NAME"
        if [ -z "$name" ]; then
          name="$(node -p "(require('./package.json').name || 'package').replace(/^@[^/]+\//, '')")"
        fi
        echo "version=${version}" >> "$GITHUB_OUTPUT"
        echo "artifact=${name}-${version}-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
    - name: Build and pack
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        PACKAGE_COMMAND: ${{ inputs.package-command }}
      run: |
        set -euo pipefail
        if [ -n "$PACKAGE_COMMAND" ]; then
          echo "Running package-command: $PACKAGE_COMMAND"
          eval "$PACKAGE_COMMAND"
          exit 0
        fi
        npm run build --if-present
        mkdir -p dist
        npm pack --pack-destination dist
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
