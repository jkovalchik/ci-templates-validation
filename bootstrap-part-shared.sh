# shellcheck shell=bash
# Part: shared cross-stack scripts and actions. Sourced by bootstrap-ci-templates.sh.

w shared/scripts/junit_summary.py <<'__FILE__'
#!/usr/bin/env python3
"""Summarise JUnit XML reports for any stack.

Writes a table to the GitHub step summary and emits one ::error annotation per
failed or errored test case. Always exits 0: the test command's exit code is
what fails the pipeline; this script only makes the failure easy to read.

Usage: junit_summary.py "<glob> [<glob> ...]" "<title>"
"""
import glob
import os
import sys
import xml.etree.ElementTree as ET


def esc_data(value):
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def esc_prop(value):
    return esc_data(value).replace(":", "%3A").replace(",", "%2C")


def write_summary(lines):
    text = "\n".join(lines) + "\n"
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if target:
        with open(target, "a", encoding="utf-8") as fh:
            fh.write(text)
    else:
        print(text)


def main():
    patterns = sys.argv[1].split() if len(sys.argv) > 1 else []
    title = sys.argv[2] if len(sys.argv) > 2 else "Test results"
    files = sorted({f for p in patterns for f in glob.glob(p, recursive=True)})

    total = failed = skipped = 0
    failures = []
    for path in files:
        try:
            root = ET.parse(path).getroot()
        except (ET.ParseError, OSError) as exc:
            print(f"::warning title=Unreadable test report::{esc_data(path + ': ' + str(exc))}")
            continue
        for case in root.iter("testcase"):
            total += 1
            if case.find("skipped") is not None:
                skipped += 1
            problem = case.find("failure")
            if problem is None:
                problem = case.find("error")
            if problem is None:
                continue
            failed += 1
            name = ".".join(x for x in (case.get("classname"), case.get("name")) if x)
            detail = (problem.get("message") or problem.text or problem.tag).strip()
            first_line = detail.splitlines()[0] if detail else problem.tag
            failures.append((name, first_line))
            print(f"::error title={esc_prop('Test failed: ' + name)}::{esc_data(first_line)}")

    lines = [f"### {title}", ""]
    if not files:
        msg = "No JUnit reports found matching: " + (" ".join(patterns) or "(none)")
        print(f"::warning title=No test reports::{esc_data(msg)}")
        lines.append(f"> {msg}")
    else:
        passed = total - failed - skipped
        lines += [
            f"**{'FAILED' if failed else 'PASSED'}** - {len(files)} report file(s)",
            "",
            "| Total | Passed | Failed | Skipped |",
            "|---:|---:|---:|---:|",
            f"| {total} | {passed} | {failed} | {skipped} |",
        ]
        if failures:
            lines += ["", "| Failed test | Message |", "|---|---|"]
            for name, msg in failures[:50]:
                safe = msg.replace("|", "\\|")[:300]
                lines.append(f"| `{name}` | {safe} |")
            if len(failures) > 50:
                lines.append(f"| ... | {len(failures) - 50} more failures, see the job log |")
    write_summary(lines)
    return 0


if __name__ == "__main__":
    sys.exit(main())
__FILE__

w shared/scripts/coverage_gate.py <<'__FILE__'
#!/usr/bin/env python3
"""Cross-stack line-coverage gate.

Reads Cobertura XML (PHPUnit, c8/nyc, Jest), JaCoCo XML (Maven) or LCOV
(node --test, Jest, c8). Multiple reports (e.g. Maven modules) are summed.

Usage: coverage_gate.py "<glob> [<glob> ...]" <threshold-percent> "<title>"
A threshold of 0 reports coverage without enforcing it.
"""
import glob
import os
import sys
import xml.etree.ElementTree as ET


def read_report(path):
    with open(path, "rb") as fh:
        head = fh.read(512).lstrip(b"\xef\xbb\xbf \t\r\n")
    if not head.startswith(b"<"):
        covered = total = 0
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("LF:"):
                    total += int(line[3:])
                elif line.startswith("LH:"):
                    covered += int(line[3:])
        return "lcov", covered, total
    root = ET.parse(path).getroot()
    if root.tag == "report":
        for counter in root.findall("counter"):
            if counter.get("type") == "LINE":
                covered = int(counter.get("covered", "0"))
                return "jacoco", covered, covered + int(counter.get("missed", "0"))
        return "jacoco", 0, 0
    if root.tag == "coverage":
        if root.get("lines-valid") is not None:
            return (
                "cobertura",
                int(float(root.get("lines-covered", "0"))),
                int(float(root.get("lines-valid", "0"))),
            )
        lines = list(root.iter("line"))
        return "cobertura", sum(1 for ln in lines if int(ln.get("hits", "0")) > 0), len(lines)
    raise ValueError(f"unrecognised coverage format (root element <{root.tag}>)")


def write_summary(lines):
    text = "\n".join(lines) + "\n"
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if target:
        with open(target, "a", encoding="utf-8") as fh:
            fh.write(text)
    else:
        print(text)


def main():
    patterns = sys.argv[1].split() if len(sys.argv) > 1 else []
    raw_threshold = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else "0"
    title = sys.argv[3] if len(sys.argv) > 3 else "Coverage"
    try:
        threshold = float(raw_threshold)
    except ValueError:
        print(f"::error title=Invalid coverage-threshold::Expected a number, got '{raw_threshold}'")
        return 1

    files = sorted({f for p in patterns for f in glob.glob(p, recursive=True)})
    covered = total = 0
    formats = set()
    for path in files:
        try:
            fmt, c, t = read_report(path)
        except (ET.ParseError, ValueError, OSError) as exc:
            print(f"::warning title=Unreadable coverage report::{path}: {exc}")
            continue
        formats.add(fmt)
        covered += c
        total += t

    if total == 0:
        msg = "No usable coverage data found (looked for: " + (" ".join(patterns) or "(none)") + ")"
        write_summary([f"### {title}", "", f"> {msg}"])
        if threshold > 0:
            print(f"::error title=Coverage missing::{msg}. coverage-threshold is {threshold:g}%, so a coverage report is required.")
            return 1
        print(f"::warning title=Coverage missing::{msg}")
        return 0

    pct = 100.0 * covered / total
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as fh:
            fh.write(f"percent={pct:.2f}\n")

    passed = pct >= threshold
    if threshold <= 0:
        result = "report only (threshold 0)"
    elif passed:
        result = f"PASSED (>= {threshold:g}%)"
    else:
        result = f"FAILED (< {threshold:g}%)"
    write_summary([
        f"### {title}",
        "",
        "| Line coverage | Lines covered | Threshold | Result |",
        "|---:|---:|---:|---|",
        f"| {pct:.2f}% | {covered}/{total} | {threshold:g}% | {result} |",
    ])
    print(f"Line coverage: {pct:.2f}% ({covered}/{total} lines; format: {', '.join(sorted(formats))})")
    if threshold > 0 and not passed:
        print(f"::error title=Coverage below threshold::Line coverage {pct:.2f}% is below the required {threshold:g}%")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
__FILE__

w shared/scripts/stage.sh <<'__FILE__'
#!/usr/bin/env bash
# Copy files matching patterns (relative to the current directory) into a staging
# directory, preserving relative paths, so they upload as one artifact whose
# layout mirrors the working directory.
#
# Usage: stage.sh <dest-dir> "<pattern> [<pattern> ...]"
#   Patterns may be files, directories (copied recursively) or globs (** supported).
#   STAGE_REQUIRE=1 turns "nothing matched" into an error.
# Writes `dir` and `count` to $GITHUB_OUTPUT when available.
set -euo pipefail

dest="$1"
patterns="${2:-}"
rm -rf "$dest"
mkdir -p "$dest"
shopt -s globstar nullglob dotglob

count=0
copy() {
  case "$1" in
    /*|../*|*/../*)
      echo "::warning::Skipping path outside the working directory: $1"
      return 0
      ;;
  esac
  cp --parents "$1" "$dest/"
  count=$((count + 1))
}

# Word splitting and glob expansion of $patterns are intentional.
# shellcheck disable=SC2086
for match in $patterns; do
  match="${match%/}"
  if [ -d "$match" ]; then
    while IFS= read -r -d '' file; do
      copy "$file"
    done < <(find "$match" -type f -print0)
  elif [ -f "$match" ]; then
    copy "$match"
  fi
done

echo "Staged ${count} file(s) matching: ${patterns}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "dir=${dest}"
    echo "count=${count}"
  } >> "$GITHUB_OUTPUT"
fi
if [ "$count" -eq 0 ] && [ "${STAGE_REQUIRE:-0}" = "1" ]; then
  echo "::error title=Nothing to upload::No files matched: ${patterns}"
  exit 1
fi
__FILE__

w shared/scripts/test_scripts.py <<'__FILE__'
"""Unit tests for the shared scripts. Run: python3 -m unittest discover -s shared/scripts -p 'test_*.py'"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


class ScriptTestCase(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = tmp.name
        self.summary = os.path.join(self.tmp, "summary.md")
        self.env = {
            **os.environ,
            "GITHUB_STEP_SUMMARY": self.summary,
            "GITHUB_OUTPUT": os.path.join(self.tmp, "output"),
        }

    def write(self, name, text):
        path = os.path.join(self.tmp, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        return path

    def run_script(self, script, *args):
        return subprocess.run(
            [sys.executable, os.path.join(HERE, script), *args],
            capture_output=True, text=True, env=self.env, check=False,
        )

    def summary_text(self):
        with open(self.summary, encoding="utf-8") as fh:
            return fh.read()


class CoverageGateTest(ScriptTestCase):
    def test_lcov_below_threshold_fails(self):
        path = self.write("lcov.info", "SF:a.js\nLF:10\nLH:5\nend_of_record\n")
        result = self.run_script("coverage_gate.py", path, "80", "Node")
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("50.00%", result.stdout)
        self.assertIn("Coverage below threshold", result.stdout)

    def test_jacoco_above_threshold_passes(self):
        path = self.write(
            "jacoco.xml",
            '<?xml version="1.0"?><report name="x">'
            '<counter type="INSTRUCTION" missed="0" covered="30"/>'
            '<counter type="LINE" missed="1" covered="9"/></report>',
        )
        result = self.run_script("coverage_gate.py", path, "80", "Java")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("90.00%", result.stdout)

    def test_cobertura_reports_without_threshold(self):
        path = self.write("cobertura.xml", '<coverage lines-covered="1" lines-valid="10"></coverage>')
        result = self.run_script("coverage_gate.py", path, "0", "PHP")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("report only", self.summary_text())

    def test_missing_report_fails_only_when_threshold_set(self):
        missing = os.path.join(self.tmp, "nope.xml")
        self.assertEqual(self.run_script("coverage_gate.py", missing, "50").returncode, 1)
        self.assertEqual(self.run_script("coverage_gate.py", missing, "0").returncode, 0)


class JunitSummaryTest(ScriptTestCase):
    def test_failures_become_annotations_and_summary_rows(self):
        path = self.write(
            "junit.xml",
            '<testsuite><testcase classname="Calc" name="adds"/>'
            '<testcase classname="Calc" name="subtracts"><failure message="expected 5, got -1"/></testcase>'
            '<testcase classname="Calc" name="later"><skipped/></testcase></testsuite>',
        )
        result = self.run_script("junit_summary.py", path, "Tests")
        self.assertEqual(result.returncode, 0)
        self.assertIn("::error title=Test failed%3A Calc.subtracts::expected 5, got -1", result.stdout)
        self.assertIn("| 3 | 1 | 1 | 1 |", self.summary_text())

    def test_no_reports_warns(self):
        result = self.run_script("junit_summary.py", os.path.join(self.tmp, "none/*.xml"), "Tests")
        self.assertEqual(result.returncode, 0)
        self.assertIn("::warning title=No test reports", result.stdout)


if __name__ == "__main__":
    unittest.main()
__FILE__

w shared/test-report/action.yml <<'__FILE__'
name: "ci-templates: test report"
description: Summarise JUnit XML reports (any stack) into the job summary and annotate failed tests.
inputs:
  working-directory:
    description: Directory the glob is relative to.
    default: "."
  junit-glob:
    description: Space-separated glob(s) of JUnit XML files (** supported).
    required: true
  title:
    description: Heading used in the job summary.
    default: Test results
runs:
  using: composite
  steps:
    - name: Summarise test results
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        JUNIT_GLOB: ${{ inputs.junit-glob }}
        TITLE: ${{ inputs.title }}
        SCRIPTS: ${{ github.action_path }}/../scripts
      run: python3 "$SCRIPTS/junit_summary.py" "$JUNIT_GLOB" "$TITLE"
__FILE__

w shared/coverage-gate/action.yml <<'__FILE__'
name: "ci-templates: coverage gate"
description: Enforce a minimum line-coverage percentage from Cobertura, JaCoCo or LCOV reports (any stack).
inputs:
  working-directory:
    description: Directory the coverage path is relative to.
    default: "."
  coverage-file:
    description: Space-separated path(s) or glob(s) of coverage reports.
    required: true
  coverage-threshold:
    description: Minimum line coverage in percent. 0 = report only.
    default: "0"
  title:
    description: Heading used in the job summary.
    default: Coverage
outputs:
  percent:
    description: Measured line coverage (empty if no report was found).
    value: ${{ steps.gate.outputs.percent }}
runs:
  using: composite
  steps:
    - name: Coverage gate
      id: gate
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        COVERAGE_FILE: ${{ inputs.coverage-file }}
        THRESHOLD: ${{ inputs.coverage-threshold }}
        TITLE: ${{ inputs.title }}
        SCRIPTS: ${{ github.action_path }}/../scripts
      run: python3 "$SCRIPTS/coverage_gate.py" "$COVERAGE_FILE" "$THRESHOLD" "$TITLE"
__FILE__
