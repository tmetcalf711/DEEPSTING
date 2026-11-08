#!/usr/bin/env bash
# Runs the GUT suite headless and the data validator. Fails on test failures AND on script parse
# errors (GUT silently skips test scripts that fail to parse).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1
# Every script must parse and the main menu must boot (the smoke run starts in-run, not at the menu).
checks="$("$GODOT" --headless -s res://tools/check_scripts.gd 2>&1)"
echo "$checks" | grep -E "check_scripts"
if echo "$checks" | grep -qE "SCRIPT ERROR|Parse Error|check_scripts: [^O]" || ! echo "$checks" | grep -q "check_scripts: OK"; then
  echo "$checks" | grep -E "SCRIPT ERROR|Parse Error|ERROR" -A2 | head -30
  echo "run_tests: script check failed" >&2
  exit 1
fi
out="$("$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit 2>&1)"
status=$?
echo "$out" | grep -vE '^\s*$'
if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error|Ignoring script"; then
  echo "run_tests: script errors detected" >&2
  status=1
fi
if ! echo "$out" | grep -q "All tests passed"; then
  status=1
fi
"$GODOT" --headless -s res://tools/validate_data.gd || status=1
smoke="$("$GODOT" --headless -s res://tools/smoke_run.gd 2>&1)"
echo "$smoke" | grep -E "smoke: (OK|FAIL|bench|door)"
if echo "$smoke" | grep -qE "SCRIPT ERROR|Parse Error|smoke: FAIL|smoke: TIMEOUT" || ! echo "$smoke" | grep -q "smoke: OK"; then
  echo "$smoke" | grep -E "SCRIPT ERROR|ERROR|FAIL" -A3 | head -40
  echo "run_tests: smoke run failed" >&2
  status=1
fi
exit $status
