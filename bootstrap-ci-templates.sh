#!/usr/bin/env bash
# Generates the ci-templates repository (reusable CI modules for Node.js, Java and PHP).
#
# Usage (Git Bash, macOS or Linux):
#   ./bootstrap-ci-templates.sh [target-dir] [owner/repo]
#     target-dir  directory to create (default: ./ci-templates); must not exist
#     owner/repo  where the template repo will live (default: averittintdev/ci-templates)
#
# Keep this script next to its parts: bootstrap-part-*.sh and CI-STANDARDS.md.
set -euo pipefail

TARGET="${1:-ci-templates}"
TEMPLATES_REPO="${2:-averittintdev/ci-templates}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -e "$TARGET" ]; then
  echo "Refusing to overwrite existing path: $TARGET" >&2
  exit 1
fi

# w <path>: write stdin to <path>, creating parent directories.
w() {
  mkdir -p "$(dirname "$1")"
  cat > "$1"
}

mkdir -p "$TARGET"
cd "$TARGET"

for part in shared node java php workflows selftest fixtures samples docs; do
  # shellcheck source=/dev/null
  . "$HERE/bootstrap-part-${part}.sh"
done

if [ -f "$HERE/CI-STANDARDS.md" ]; then
  mkdir -p docs
  cp "$HERE/CI-STANDARDS.md" docs/STANDARDS.md
fi

{ grep -rl '__CI_TEMPLATES_REPO__' . || true; } | while IFS= read -r f; do
  sed -i.bak "s#__CI_TEMPLATES_REPO__#${TEMPLATES_REPO}#g" "$f" && rm -f "$f.bak"
done
chmod +x shared/scripts/*.sh shared/scripts/*.py

echo "Created $(find . -type f | wc -l | tr -d ' ') files in $(pwd)"
echo "Next: git init && git add -A && git commit -m 'ci-templates v1' && push to ${TEMPLATES_REPO}, then tag v1.0.0 and v1."
