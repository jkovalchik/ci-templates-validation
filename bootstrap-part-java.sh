# shellcheck shell=bash
# Part: Java (Maven) composite actions. Sourced by bootstrap-ci-templates.sh.

w java/setup/action.yml <<'__FILE__'
name: "ci-templates: Java setup"
description: >-
  Install a JDK with Maven dependency caching. Uses the Maven wrapper (./mvnw) when present,
  otherwise the runner's `mvn`. Exports CI_MVN for the other Java actions.
inputs:
  working-directory:
    description: Directory containing pom.xml.
    default: "."
  runtime-version:
    description: JDK version.
    default: "21"
  distribution:
    description: JDK distribution for actions/setup-java.
    default: "temurin"
runs:
  using: composite
  steps:
    - name: Detect Maven project
      id: detect
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        WD: ${{ inputs.working-directory }}
      run: |
        set -euo pipefail
        if [ ! -f pom.xml ]; then
          if compgen -G "build.gradle*" > /dev/null; then
            echo "::error title=Gradle not supported yet::ci-templates v1 supports Maven projects only. See the README roadmap."
          else
            echo "::error title=No pom.xml::No pom.xml found in '$WD'."
          fi
          exit 1
        fi
        prefix=""
        if [ "$WD" != "." ]; then prefix="${WD%/}/"; fi
        echo "poms=${prefix}**/pom.xml" >> "$GITHUB_OUTPUT"
        if [ -f mvnw ]; then
          chmod +x mvnw
          echo "CI_MVN=./mvnw" >> "$GITHUB_ENV"
          echo "Using the Maven wrapper (./mvnw)"
        else
          echo "CI_MVN=mvn" >> "$GITHUB_ENV"
          echo "::notice title=No Maven wrapper::Using the runner's mvn. The CI standard recommends committing mvnw for reproducible builds."
        fi
    - name: Set up JDK
      uses: actions/setup-java@v4
      with:
        distribution: ${{ inputs.distribution }}
        java-version: ${{ inputs.runtime-version }}
        cache: maven
        cache-dependency-path: ${{ steps.detect.outputs.poms }}
__FILE__

w java/lint/checkstyle.xml <<'__FILE__'
<?xml version="1.0"?>
<!DOCTYPE module PUBLIC
    "-//Checkstyle//DTD Checkstyle Configuration 1.3//EN"
    "https://checkstyle.org/dtds/configuration_1_3.dtd">
<!--
  ci-templates baseline Checkstyle config. Used only when the repo has no checkstyle.xml
  and does not configure maven-checkstyle-plugin itself. Deliberately correctness-focused
  (no formatting/Javadoc rules) so existing code can adopt it without mass reformatting.
  Suppress a finding with @SuppressWarnings("checkstyle:RuleName").
-->
<module name="Checker">
  <property name="severity" value="error"/>
  <property name="charset" value="UTF-8"/>
  <property name="fileExtensions" value="java"/>

  <module name="SuppressWarningsFilter"/>
  <module name="FileTabCharacter"/>
  <module name="LineLength">
    <property name="max" value="160"/>
    <property name="ignorePattern" value="^(package|import) .*$|https?://"/>
  </module>

  <module name="TreeWalker">
    <module name="SuppressWarningsHolder"/>
    <module name="UnusedImports"/>
    <module name="RedundantImport"/>
    <module name="IllegalImport"/>
    <module name="EmptyStatement"/>
    <module name="EmptyCatchBlock"/>
    <module name="EqualsHashCode"/>
    <module name="CovariantEquals"/>
    <module name="StringLiteralEquality"/>
    <module name="SimplifyBooleanExpression"/>
    <module name="OneStatementPerLine"/>
    <module name="UpperEll"/>
    <module name="ArrayTypeStyle"/>
    <module name="PackageName"/>
    <module name="TypeName"/>
  </module>
</module>
__FILE__

w java/lint/checkstyle-problem-matcher.json <<'__FILE__'
{
  "problemMatcher": [
    {
      "owner": "ci-templates-checkstyle",
      "severity": "error",
      "pattern": [
        {
          "regexp": "^\\[ERROR\\]\\s+(.+?\\.java):\\[(\\d+)(?:,(\\d+))?\\]\\s+\\(([^)]+)\\)\\s+(.*)$",
          "file": 1,
          "line": 2,
          "column": 3,
          "code": 4,
          "message": 5
        }
      ]
    }
  ]
}
__FILE__

w java/lint/action.yml <<'__FILE__'
name: "ci-templates: Java lint"
description: >-
  Checkstyle via Maven: the project's plugin configuration if present, else the repo's
  checkstyle.xml, else the ci-templates baseline. Violations fail the step and are annotated.
inputs:
  working-directory:
    description: Directory containing pom.xml.
    default: "."
  lint-command:
    description: Command that replaces the default lint logic entirely.
    default: ""
  checkstyle-plugin-version:
    description: maven-checkstyle-plugin version used when the project does not configure it.
    default: "3.4.0"
runs:
  using: composite
  steps:
    - name: Lint (Checkstyle)
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        LINT_COMMAND: ${{ inputs.lint-command }}
        PLUGIN_VERSION: ${{ inputs.checkstyle-plugin-version }}
        BASELINE_DIR: ${{ github.action_path }}
      run: |
        set -euo pipefail
        MVN="${CI_MVN:-mvn}"
        if [ -n "$LINT_COMMAND" ]; then
          echo "Running lint-command: $LINT_COMMAND"
          eval "$LINT_COMMAND"
          exit 0
        fi
        echo "::add-matcher::$BASELINE_DIR/checkstyle-problem-matcher.json"
        if grep -q "maven-checkstyle-plugin" pom.xml; then
          echo "Using the project's maven-checkstyle-plugin configuration"
          "$MVN" -B -ntp checkstyle:check -Dcheckstyle.consoleOutput=true
          exit 0
        fi
        config=""
        for f in checkstyle.xml config/checkstyle/checkstyle.xml; do
          if [ -z "$config" ] && [ -f "$f" ]; then config="$PWD/$f"; fi
        done
        if [ -z "$config" ]; then
          config="$BASELINE_DIR/checkstyle.xml"
          echo "::notice title=Baseline lint::No Checkstyle config found; using the ci-templates baseline. Add checkstyle.xml to take control."
        fi
        "$MVN" -B -ntp "org.apache.maven.plugins:maven-checkstyle-plugin:${PLUGIN_VERSION}:check" \
          -Dcheckstyle.config.location="$config" \
          -Dcheckstyle.consoleOutput=true \
          -Dcheckstyle.violationSeverity=error \
          -Dcheckstyle.includeTestSourceDirectory=true
    - name: Remove Checkstyle problem matcher
      if: ${{ always() }}
      shell: bash
      run: echo "::remove-matcher owner=ci-templates-checkstyle::"
__FILE__

w java/test/action.yml <<'__FILE__'
name: "ci-templates: Java test"
description: >-
  `mvn test` with the JaCoCo agent (or a custom command), summarise Surefire JUnit results,
  annotate failed tests and upload test/coverage reports for the quality stage.
inputs:
  working-directory:
    description: Directory containing pom.xml.
    default: "."
  test-command:
    description: Command that replaces the default Maven test invocation.
    default: ""
  jacoco-version:
    description: jacoco-maven-plugin version.
    default: "0.8.12"
  junit-glob:
    description: JUnit XML report glob(s), relative to working-directory.
    default: "**/target/surefire-reports/TEST-*.xml"
  coverage-file:
    description: Coverage report path(s)/glob(s) to upload (JaCoCo XML).
    default: "**/target/site/jacoco/jacoco.xml"
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
    - name: Run tests (Maven + JaCoCo)
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        TEST_COMMAND: ${{ inputs.test-command }}
        JACOCO: org.jacoco:jacoco-maven-plugin:${{ inputs.jacoco-version }}
      run: |
        set -euo pipefail
        MVN="${CI_MVN:-mvn}"
        if [ -n "$TEST_COMMAND" ]; then
          echo "Running test-command: $TEST_COMMAND"
          eval "$TEST_COMMAND"
          exit 0
        fi
        "$MVN" -B -ntp "${JACOCO}:prepare-agent" test "${JACOCO}:report"
    - name: Summarise test results
      if: ${{ always() }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        JUNIT_GLOB: ${{ inputs.junit-glob }}
        SCRIPTS: ${{ github.action_path }}/../../shared/scripts
      run: python3 "$SCRIPTS/junit_summary.py" "$JUNIT_GLOB" "Java tests"
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

w java/quality/action.yml <<'__FILE__'
name: "ci-templates: Java code quality"
description: >-
  SpotBugs static analysis, optional project quality command and the shared coverage gate.
  Every check runs; the step fails if any check failed.
inputs:
  working-directory:
    description: Directory containing pom.xml.
    default: "."
  spotbugs:
    description: Run SpotBugs ("true"/"false").
    default: "true"
  spotbugs-version:
    description: spotbugs-maven-plugin version used when the project does not configure it.
    default: "4.8.6.4"
  spotbugs-threshold:
    description: Lowest bug rank that is reported and fails the build (High, Medium, Low).
    default: "High"
  coverage-file:
    description: Coverage report path(s)/glob(s) (JaCoCo XML).
    default: "**/target/site/jacoco/jacoco.xml"
  coverage-threshold:
    description: Minimum line coverage percent. 0 = report only.
    default: "0"
  quality-command:
    description: Extra project quality command, e.g. "./mvnw -B pmd:check".
    default: ""
runs:
  using: composite
  steps:
    - name: Static analysis (SpotBugs)
      if: ${{ inputs.spotbugs == 'true' }}
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        SPOTBUGS_VERSION: ${{ inputs.spotbugs-version }}
        THRESHOLD: ${{ inputs.spotbugs-threshold }}
      run: |
        set -euo pipefail
        MVN="${CI_MVN:-mvn}"
        if grep -q "spotbugs-maven-plugin" pom.xml; then
          echo "Using the project's spotbugs-maven-plugin configuration"
          "$MVN" -B -ntp compile com.github.spotbugs:spotbugs-maven-plugin:check
          exit 0
        fi
        args=("-Dspotbugs.threshold=${THRESHOLD}" "-Dspotbugs.failThreshold=${THRESHOLD}")
        if [ -f spotbugs-exclude.xml ]; then
          args+=("-Dspotbugs.excludeFilterFile=${PWD}/spotbugs-exclude.xml")
        fi
        "$MVN" -B -ntp compile "com.github.spotbugs:spotbugs-maven-plugin:${SPOTBUGS_VERSION}:check" "${args[@]}"
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
      run: python3 "$SCRIPTS/coverage_gate.py" "$COVERAGE_FILE" "$THRESHOLD" "Java coverage"
__FILE__

w java/package/action.yml <<'__FILE__'
name: "ci-templates: Java package"
description: >-
  `mvn package -DskipTests` (or a custom command), then upload the jar/war as
  `<name>-<version>-<sha7>`.
inputs:
  working-directory:
    description: Directory containing pom.xml.
    default: "."
  package-command:
    description: Command that replaces `mvn package -DskipTests`.
    default: ""
  package-path:
    description: Path(s)/glob(s) to upload, relative to working-directory.
    default: "target/*.jar target/*.war"
  artifact-name:
    description: Artifact base name. Empty = Maven artifactId.
    default: ""
  retention-days:
    description: Artifact retention in days.
    default: "14"
outputs:
  artifact-name:
    description: Uploaded artifact name (<name>-<version>-<sha7>).
    value: ${{ steps.meta.outputs.artifact }}
  version:
    description: Maven project.version.
    value: ${{ steps.meta.outputs.version }}
runs:
  using: composite
  steps:
    - name: Build package
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        PACKAGE_COMMAND: ${{ inputs.package-command }}
      run: |
        set -euo pipefail
        MVN="${CI_MVN:-mvn}"
        if [ -n "$PACKAGE_COMMAND" ]; then
          echo "Running package-command: $PACKAGE_COMMAND"
          eval "$PACKAGE_COMMAND"
          exit 0
        fi
        "$MVN" -B -ntp package -DskipTests
    - name: Resolve name and version
      id: meta
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        ARTIFACT_NAME: ${{ inputs.artifact-name }}
      run: |
        set -euo pipefail
        MVN="${CI_MVN:-mvn}"
        evaluate() {
          "$MVN" -B -q -ntp org.apache.maven.plugins:maven-help-plugin:3.4.0:evaluate \
            -Dexpression="$1" -DforceStdout | tail -n 1
        }
        version="$(evaluate project.version)"
        name="$ARTIFACT_NAME"
        if [ -z "$name" ]; then name="$(evaluate project.artifactId)"; fi
        echo "version=${version}" >> "$GITHUB_OUTPUT"
        echo "artifact=${name}-${version}-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
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
