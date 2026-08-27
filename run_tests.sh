#!/bin/sh
set -e

PROJECT_GODOT="./project.godot"
PROJECT_GODOT_BACKUP="${PROJECT_GODOT}.backup.$$"
TEST_OUTPUT="/tmp/gut_test_output_$$.txt"

# Backup project.godot and remove the problematic autoload and editor plugins.
# The GDAIMCPRuntime autoload and gdai-mcp-plugin-godot (editor plugin with @tool)
# reference native classes (GDAIBaseTool, GDAIConfig). The GExtension binary registers
# these classes at startup, but GUT's stubber fails (error 43: parse error) when trying
# to generate a dynamic script referencing them. Removing the autoload and plugins
# from project.godot for headless runs prevents their initialization, reducing the
# error count. However, the GExtension itself still registers these classes at startup,
# causing 2 unavoidable "Could not create script" errors in GUT's class database setup.
# These 2 errors are expected and allowed; any other error count indicates a real problem.
cp "$PROJECT_GODOT" "$PROJECT_GODOT_BACKUP"
trap "mv '$PROJECT_GODOT_BACKUP' '$PROJECT_GODOT' 2>/dev/null || true; rm -f '$TEST_OUTPUT'" EXIT

# Remove .godot cache to force Godot to rebuild without plugin/autoload references
rm -rf .godot

# Remove the autoload and editor_plugins sections from project.godot for this test run
sed -i.bak '/^\[autoload\]$/,/^\[/{ /^\[autoload\]$/d; /^GDAIMCPRuntime=/d; }' "$PROJECT_GODOT"
sed -i.bak '/^\[editor_plugins\]$/,/^\[/{  /^\[editor_plugins\]$/d; /^enabled=/d; }' "$PROJECT_GODOT"
rm -f "${PROJECT_GODOT}.bak"

# Import assets headless. Exit code 134 (SIGABRT) is expected due to a Godot
# engine shutdown issue on macOS, but the import completes successfully before
# the crash occurs. We allow this specific exit code.
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import 2>/dev/null || \
  [ $? -eq 134 ] || exit $?

# Run tests with plugins and autoload disabled. Capture output to check error count.
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit 2>&1 | tee "$TEST_OUTPUT"

# Validate error count: exactly 2 known errors from GDAIBaseTool/GDAIConfig class DB issues
ERROR_COUNT=$(grep "^Errors" "$TEST_OUTPUT" | awk '{print $NF}')
if [ "$ERROR_COUNT" != "2" ]; then
  echo ""
  echo "FATAL: Unexpected error count: $ERROR_COUNT (expected 2 known GExtension class DB errors)"
  echo "       Check for new errors or broken tests"
  exit 1
fi
