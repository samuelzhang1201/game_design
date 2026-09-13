#!/bin/sh
# Tests must never make live API calls, even with a real .env present.
export CC_FORCE_OFFLINE=1
set -e

TEST_OUTPUT="/tmp/gut_test_output_$$.txt"
trap 'rm -f "$TEST_OUTPUT"' EXIT

# Import assets headless. Exit code 134 (SIGABRT on macOS) is expected due to a Godot
# shutdown issue, but the import completes successfully before the crash. Exit code 0
# is also acceptable (no crash on other platforms). Show diagnostics on real failure.
code=0
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import || code=$?
if [ "$code" != "0" ] && [ "$code" != "134" ]; then
  echo "import failed with exit code $code" >&2
  exit "$code"
fi

# Run tests. Redirect (not pipe) to a file so we can capture Godot/GUT's own
# exit code: piping into `tee` under /bin/sh yields the pipeline's status,
# which is tee's exit code, not Godot's — a red suite would exit 0.
code=0
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit > "$TEST_OUTPUT" 2>&1 || code=$?
cat "$TEST_OUTPUT"

# GUT silently SKIPS a test script that fails to parse ("Ignoring script ...
# because it does not extend GutTest") and still reports the suite green —
# verified 2026-08-30 when a parse error in test_llm_config.gd dropped 6
# tests without failing the run. Treat any skipped script, and any mismatch
# between test scripts on disk and scripts GUT ran, as fatal.
if grep -q "Ignoring script" "$TEST_OUTPUT"; then
  echo ""
  echo "FATAL: GUT ignored a test script (parse error?):"
  grep "Ignoring script" "$TEST_OUTPUT"
  exit 1
fi
DISK_SCRIPTS=$(find tests -name "test_*.gd" | wc -l | tr -d ' ')
RAN_SCRIPTS=$(grep "^Scripts" "$TEST_OUTPUT" | awk '{print $NF}')
if [ "$DISK_SCRIPTS" != "$RAN_SCRIPTS" ]; then
  echo ""
  echo "FATAL: $DISK_SCRIPTS test scripts on disk but GUT ran $RAN_SCRIPTS"
  exit 1
fi

# Validate error count: the suite must be clean. This expected 2 for as long as
# the gdai-mcp-plugin-godot GExtension was vendored (it registered native
# classes that GUT's stubber could not resolve headless); the plugin was removed
# 2026-09-13, and with it the last known-good errors. GUT omits the line
# entirely when there are none, so an absent line counts as 0.
ERROR_COUNT=$(grep "^Errors" "$TEST_OUTPUT" | awk '{print $NF}')
[ -z "$ERROR_COUNT" ] && ERROR_COUNT=0
if [ "$ERROR_COUNT" != "0" ]; then
  echo ""
  echo "FATAL: Unexpected error count: $ERROR_COUNT (expected a clean suite)"
  echo "       Check for new errors or broken tests"
  exit 1
fi

# GUT sets a nonzero exit code when any test fails (see
# addons/gut/gui/GutRunner.gd:_handle_quit). Propagate it so a red suite
# fails the script.
if [ "$code" != "0" ]; then
  echo ""
  echo "FATAL: GUT exited with code $code (test failures)"
  exit "$code"
fi
