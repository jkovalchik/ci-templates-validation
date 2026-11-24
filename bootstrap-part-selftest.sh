# shellcheck shell=bash
# Part: self-test + release smoke workflows and Dependabot. Sourced by bootstrap-ci-templates.sh.

w .github/workflows/self-test.yml <<'__FILE__'
# Verifies the composite actions from this commit (local `uses: ./...`) against fixtures:
#   pass   -> every stage must succeed (coverage gate at 80%)
#   broken -> lint AND tests must fail (acceptance criterion 3)
#   samples -> the real averittintdev LTL Java/Node.js samples plus their adoption changes
#              (test-fixtures/samples/) must pass every module (acceptance criterion 2)
# plus informational runs against the LTL sample repos exactly as they are today.
name: Self-test

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: self-test-${{ github.ref }}
  cancel-in-progress: true

jobs:
  static:
    name: Static checks
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: actionlint
        run: |
          bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
          ./actionlint -color
      - name: Shared script unit tests
        run: python3 -m unittest discover -s shared/scripts -p 'test_*.py' -v
      - name: Shell syntax
        run: bash -n shared/scripts/stage.sh

  node-pass:
    name: Node.js fixture (pass)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      WD: test-fixtures/node/pass
    steps:
      - uses: actions/checkout@v4
      - uses: ./node/setup
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./node/lint
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./node/test
        with: { working-directory: "${{ env.WD }}", reports-artifact-name: selftest-node-pass-reports, retention-days: "1" }
      - uses: ./node/quality
        with: { working-directory: "${{ env.WD }}", coverage-threshold: "80" }
      - id: package
        uses: ./node/package
        with: { working-directory: "${{ env.WD }}", artifact-name: selftest-node, retention-days: "1" }
      - name: Assert package outputs
        env:
          VERSION: ${{ steps.package.outputs.version }}
          ARTIFACT: ${{ steps.package.outputs.artifact-name }}
        run: |
          test "$VERSION" = "1.0.0"
          case "$ARTIFACT" in selftest-node-1.0.0-*) ;; *) echo "unexpected artifact: $ARTIFACT"; exit 1 ;; esac

  node-broken:
    name: Node.js fixture (broken must fail)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      WD: test-fixtures/node/broken
    steps:
      - uses: actions/checkout@v4
      - uses: ./node/setup
        with: { working-directory: "${{ env.WD }}" }
      - id: lint
        continue-on-error: true
        uses: ./node/lint
        with: { working-directory: "${{ env.WD }}" }
      - id: test
        continue-on-error: true
        uses: ./node/test
        with: { working-directory: "${{ env.WD }}", upload-reports: "false" }
      - name: Assert lint and tests failed
        if: ${{ always() }}
        env:
          LINT: ${{ steps.lint.outcome }}
          TEST: ${{ steps.test.outcome }}
        run: |
          echo "lint=$LINT test=$TEST"
          test "$LINT" = "failure" && test "$TEST" = "failure"

  java-pass:
    name: Java fixture (pass)
    runs-on: ubuntu-latest
    timeout-minutes: 20
    env:
      WD: test-fixtures/java/pass
    steps:
      - uses: actions/checkout@v4
      - uses: ./java/setup
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./java/lint
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./java/test
        with: { working-directory: "${{ env.WD }}", reports-artifact-name: selftest-java-pass-reports, retention-days: "1" }
      - uses: ./java/quality
        with: { working-directory: "${{ env.WD }}", coverage-threshold: "80" }
      - id: package
        uses: ./java/package
        with: { working-directory: "${{ env.WD }}", artifact-name: selftest-java, retention-days: "1" }
      - name: Assert package outputs
        env:
          VERSION: ${{ steps.package.outputs.version }}
        run: test "$VERSION" = "1.0.0-SNAPSHOT"

  java-broken:
    name: Java fixture (broken must fail)
    runs-on: ubuntu-latest
    timeout-minutes: 20
    env:
      WD: test-fixtures/java/broken
    steps:
      - uses: actions/checkout@v4
      - uses: ./java/setup
        with: { working-directory: "${{ env.WD }}" }
      - id: lint
        continue-on-error: true
        uses: ./java/lint
        with: { working-directory: "${{ env.WD }}" }
      - id: test
        continue-on-error: true
        uses: ./java/test
        with: { working-directory: "${{ env.WD }}", upload-reports: "false" }
      - name: Assert lint and tests failed
        if: ${{ always() }}
        env:
          LINT: ${{ steps.lint.outcome }}
          TEST: ${{ steps.test.outcome }}
        run: |
          echo "lint=$LINT test=$TEST"
          test "$LINT" = "failure" && test "$TEST" = "failure"

  php-pass:
    name: PHP fixture (pass)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      WD: test-fixtures/php/pass
    steps:
      - uses: actions/checkout@v4
      - uses: ./php/setup
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./php/lint
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./php/test
        with: { working-directory: "${{ env.WD }}", reports-artifact-name: selftest-php-pass-reports, retention-days: "1" }
      - uses: ./php/quality
        with: { working-directory: "${{ env.WD }}", coverage-threshold: "80" }
      - uses: ./php/package
        with: { working-directory: "${{ env.WD }}", artifact-name: selftest-php, retention-days: "1" }

  php-broken:
    name: PHP fixture (broken must fail)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      WD: test-fixtures/php/broken
    steps:
      - uses: actions/checkout@v4
      - uses: ./php/setup
        with: { working-directory: "${{ env.WD }}" }
      - id: lint
        continue-on-error: true
        uses: ./php/lint
        with: { working-directory: "${{ env.WD }}" }
      - id: test
        continue-on-error: true
        uses: ./php/test
        with: { working-directory: "${{ env.WD }}", upload-reports: "false" }
      - name: Assert lint and tests failed
        if: ${{ always() }}
        env:
          LINT: ${{ steps.lint.outcome }}
          TEST: ${{ steps.test.outcome }}
        run: |
          echo "lint=$LINT test=$TEST"
          test "$LINT" = "failure" && test "$TEST" = "failure"

  # Acceptance criterion 2: every module must pass on the real LTL sample repos plus the
  # adoption changes in test-fixtures/samples/ (the PR each sample needs; see its README).
  sample-node:
    name: LTL Node.js sample + adoption changes (must pass)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      WD: samples/node
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with: { repository: averittintdev/ltl-tracking-api-client-sample-nodejs, path: samples/node }
      - name: Apply adoption changes (test-fixtures/samples/node)
        run: |
          set -euo pipefail
          cp -Rv test-fixtures/samples/node/. "$WD/"
          # The adoption PR bumps Express; refresh the lockfile exactly as that PR does.
          cd "$WD"
          npm install --package-lock-only --no-audit --no-fund
      - uses: ./node/setup
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./node/lint
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./node/test
        with: { working-directory: "${{ env.WD }}", reports-artifact-name: selftest-ltl-node-reports, retention-days: "1" }
      - uses: ./node/quality
        with: { working-directory: "${{ env.WD }}", coverage-threshold: "70" }
      - id: package
        uses: ./node/package
        with: { working-directory: "${{ env.WD }}", artifact-name: selftest-ltl-node, retention-days: "1" }
      - name: Assert package outputs
        env:
          VERSION: ${{ steps.package.outputs.version }}
        run: test "$VERSION" = "1.0.0"

  sample-java:
    name: LTL Java sample + adoption changes (must pass)
    runs-on: ubuntu-latest
    timeout-minutes: 20
    env:
      WD: samples/java
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with: { repository: averittintdev/ltl-tracking-api-client-sample-java, path: samples/java }
      - name: Apply adoption changes (test-fixtures/samples/java)
        run: cp -Rv test-fixtures/samples/java/. "$WD/"
      - uses: ./java/setup
        with: { working-directory: "${{ env.WD }}", runtime-version: "11" }
      - uses: ./java/lint
        with: { working-directory: "${{ env.WD }}" }
      - uses: ./java/test
        with: { working-directory: "${{ env.WD }}", reports-artifact-name: selftest-ltl-java-reports, retention-days: "1" }
      - uses: ./java/quality
        with: { working-directory: "${{ env.WD }}", coverage-threshold: "50" }
      - id: package
        uses: ./java/package
        with: { working-directory: "${{ env.WD }}", artifact-name: selftest-ltl-java, retention-days: "1" }
      - name: Assert package outputs
        env:
          VERSION: ${{ steps.package.outputs.version }}
        run: test "$VERSION" = "0.0.1-SNAPSHOT"

  # Informational: the sample repos exactly as they are today. Each stage's outcome goes to the
  # job summary; failures here show the clear output an adopting repo gets (criterion 3) and
  # never fail the self-test. Once the adoption PRs are merged these jobs turn green.
  upstream-node:
    name: Upstream sample (Node.js, informational)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      WD: samples/node
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with: { repository: averittintdev/ltl-tracking-api-client-sample-nodejs, path: samples/node }
      - id: setup
        continue-on-error: true
        uses: ./node/setup
        with: { working-directory: "${{ env.WD }}" }
      - id: lint
        continue-on-error: true
        uses: ./node/lint
        with: { working-directory: "${{ env.WD }}" }
      - id: test
        continue-on-error: true
        uses: ./node/test
        with: { working-directory: "${{ env.WD }}", upload-reports: "false" }
      - id: quality
        continue-on-error: true
        uses: ./node/quality
        with: { working-directory: "${{ env.WD }}" }
      - id: package
        continue-on-error: true
        uses: ./node/package
        with: { working-directory: "${{ env.WD }}", artifact-name: upstream-node, retention-days: "1" }
      - name: Outcome summary
        if: ${{ always() }}
        run: |
          {
            echo "### Upstream Node.js sample"
            echo "| Stage | Outcome |"
            echo "|---|---|"
            echo "| setup | ${{ steps.setup.outcome }} |"
            echo "| lint | ${{ steps.lint.outcome }} |"
            echo "| test | ${{ steps.test.outcome }} |"
            echo "| quality | ${{ steps.quality.outcome }} |"
            echo "| package | ${{ steps.package.outcome }} |"
          } >> "$GITHUB_STEP_SUMMARY"

  upstream-java:
    name: Upstream sample (Java, informational)
    runs-on: ubuntu-latest
    timeout-minutes: 20
    env:
      WD: samples/java
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with: { repository: averittintdev/ltl-tracking-api-client-sample-java, path: samples/java }
      - id: setup
        continue-on-error: true
        uses: ./java/setup
        with: { working-directory: "${{ env.WD }}", runtime-version: "11" }
      - id: lint
        continue-on-error: true
        uses: ./java/lint
        with: { working-directory: "${{ env.WD }}" }
      - id: test
        continue-on-error: true
        uses: ./java/test
        with: { working-directory: "${{ env.WD }}", upload-reports: "false" }
      - id: quality
        continue-on-error: true
        uses: ./java/quality
        with: { working-directory: "${{ env.WD }}" }
      - id: package
        continue-on-error: true
        uses: ./java/package
        with: { working-directory: "${{ env.WD }}", artifact-name: upstream-java, retention-days: "1" }
      - name: Outcome summary
        if: ${{ always() }}
        run: |
          {
            echo "### Upstream Java sample"
            echo "| Stage | Outcome |"
            echo "|---|---|"
            echo "| setup | ${{ steps.setup.outcome }} |"
            echo "| lint | ${{ steps.lint.outcome }} |"
            echo "| test | ${{ steps.test.outcome }} |"
            echo "| quality | ${{ steps.quality.outcome }} |"
            echo "| package | ${{ steps.package.outcome }} |"
          } >> "$GITHUB_STEP_SUMMARY"

  upstream-php:
    name: Upstream sample (PHP, informational)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    env:
      WD: samples/php
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with: { repository: averittintdev/ltl-tracking-api-client-sample-php, path: samples/php }
      - id: setup
        continue-on-error: true
        uses: ./php/setup
        with: { working-directory: "${{ env.WD }}" }
      - id: lint
        continue-on-error: true
        uses: ./php/lint
        with: { working-directory: "${{ env.WD }}" }
      - id: test
        continue-on-error: true
        uses: ./php/test
        with: { working-directory: "${{ env.WD }}", upload-reports: "false" }
      - id: quality
        continue-on-error: true
        uses: ./php/quality
        with: { working-directory: "${{ env.WD }}" }
      - id: package
        continue-on-error: true
        uses: ./php/package
        with: { working-directory: "${{ env.WD }}", artifact-name: upstream-php, retention-days: "1" }
      - name: Outcome summary
        if: ${{ always() }}
        run: |
          {
            echo "### Upstream PHP sample"
            echo "| Stage | Outcome |"
            echo "|---|---|"
            echo "| setup | ${{ steps.setup.outcome }} |"
            echo "| lint | ${{ steps.lint.outcome }} |"
            echo "| test | ${{ steps.test.outcome }} |"
            echo "| quality | ${{ steps.quality.outcome }} |"
            echo "| package | ${{ steps.package.outcome }} |"
          } >> "$GITHUB_STEP_SUMMARY"
__FILE__

w .github/workflows/release-smoke.yml <<'__FILE__'
# End-to-end check of the reusable workflows as consumers call them. Reusable workflows
# reference the composite actions at @v1, so run this after moving the v1 tag
# (workflow_dispatch) or automatically when a v* tag is pushed.
name: Release smoke test

on:
  push:
    tags: ["v*"]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  node:
    uses: ./.github/workflows/node-ci.yml
    with:
      working-directory: test-fixtures/node/pass
      coverage-threshold: 80
      artifact-name: smoke-node
      retention-days: 1
  java:
    uses: ./.github/workflows/java-ci.yml
    with:
      working-directory: test-fixtures/java/pass
      coverage-threshold: 80
      artifact-name: smoke-java
      retention-days: 1
  php:
    uses: ./.github/workflows/php-ci.yml
    with:
      working-directory: test-fixtures/php/pass
      coverage-threshold: 80
      artifact-name: smoke-php
      retention-days: 1
  check-outputs:
    name: Check workflow outputs
    needs: [node, java, php]
    runs-on: ubuntu-latest
    steps:
      - env:
          NODE_VERSION: ${{ needs.node.outputs.version }}
          JAVA_VERSION: ${{ needs.java.outputs.version }}
          PHP_ARTIFACT: ${{ needs.php.outputs.artifact-name }}
        run: |
          test "$NODE_VERSION" = "1.0.0"
          test "$JAVA_VERSION" = "1.0.0-SNAPSHOT"
          case "$PHP_ARTIFACT" in smoke-php-*) ;; *) echo "unexpected: $PHP_ARTIFACT"; exit 1 ;; esac
__FILE__

w .github/dependabot.yml <<'__FILE__'
version: 2
updates:
  - package-ecosystem: github-actions
    directories: ["/", "/node/*", "/java/*", "/php/*", "/shared/*"]
    schedule:
      interval: weekly
    groups:
      actions:
        patterns: ["*"]
__FILE__
