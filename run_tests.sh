#!/bin/sh
# Tests must never make live API calls, even with a real .env present.
export CC_FORCE_OFFLINE=1
set -e

TEST_OUTPUT="/tmp/gut_test_output_$$.txt"
trap 'rm -f "$TEST_OUTPUT"' EXIT

# Root cause of GUT's "Errors 2": The gdai-mcp-plugin-godot GExtension registers
# native classes (GDAIBaseTool, GDAIConfig, GDAIToolGetGodotErrors) at engine startup.
# In headless mode, GUT's stubber attempts to build a class database including all
# global classes, and fails with error 43 (parse error) twice when generating a dynamic
# script that references these unavailable native classes. Attempts to remove the
# autoload or editor_plugins don't help because the GExtension registers classes
# at Godot startup regardless. The 2 errors are unavoidable without modifying the
# vendored plugins or GExtension binary.

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

# Validate error count: exactly 2 known errors from GExtension class database issues.
# Any other count indicates new errors or broken tests.
ERROR_COUNT=$(grep "^Errors" "$TEST_OUTPUT" | awk '{print $NF}')
if [ "$ERROR_COUNT" != "2" ]; then
  echo ""
  echo "FATAL: Unexpected error count: $ERROR_COUNT (expected 2 known GExtension class DB errors)"
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
