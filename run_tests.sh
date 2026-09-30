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
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gpre_run_script=res://tests/pre_run.gd -gpost_run_script=res://tests/post_run.gd -gexit > "$TEST_OUTPUT" 2>&1 || code=$?
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

# Validate error count. The gdai-mcp-plugin-godot GExtension registers native
# classes (GDAIBaseTool, GDAIConfig, ...) at engine startup; headless, GUT's
# stubber builds a class database over every global class and fails to parse
# the dynamic script that references them, twice. Those 2 errors are
# unavoidable without modifying the closed-source binary, so the suite expects
# exactly 2 while the extension is installed and exactly 0 without it (the
# binaries are git-ignored, so a fresh clone has none). Any other count means
# new errors or broken tests. GUT omits the line when there are none.
EXPECTED_ERRORS=0
[ -f addons/gdai-mcp-plugin-godot/gdai_mcp_plugin.gdextension ] && EXPECTED_ERRORS=2
ERROR_COUNT=$(grep "^Errors" "$TEST_OUTPUT" | awk '{print $NF}')
[ -z "$ERROR_COUNT" ] && ERROR_COUNT=0
if [ "$ERROR_COUNT" != "$EXPECTED_ERRORS" ]; then
  echo ""
  echo "FATAL: Unexpected error count: $ERROR_COUNT (expected $EXPECTED_ERRORS)"
  echo "       Check for new errors or broken tests"
  exit 1
fi

# GUT does not count a runtime SCRIPT ERROR: a test that dies partway (an
# engine assert, a bad key on a result) stops at that line and is still
# reported as passing on the asserts it made before — verified 2026-09-30
# when test_building_needs_a_free_slot_and_can_be_pulled_down died on its
# first build ("An abbey needs a chapel standing first") and passed with 1
# assert of 21. So any SCRIPT ERROR is fatal unless its location is on this
# allow-list, one res://path:line per line, each with its reason:
#   res://addons/gut/gut_loader.gd:35 — GUT's own loader reads an unset
#     project setting into a bool at startup, once per run, before any test.
SCRIPT_ERROR_ALLOW="res://addons/gut/gut_loader.gd:35"
# While the gdai-mcp-plugin-godot extension is installed (the same condition
# as EXPECTED_ERRORS=2 above), the class-database probing behind those 2
# errors also prints ~100 SCRIPT ERRORs (98 measured 2026-09-30), all
# before any test runs: the dynamic script listing every class fails to
# parse on each GDAI* native class ('Identifier "GDAI..." not declared', at
# gut_dynamic_script_N.gd; 96 lines), and stubber.gd:35 then calls new() on
# the int error code it got back instead of a script (2 lines). They are the probe failing, not a test aborting, so
# they are allowed by their whole message — only then; without the
# extension the gate stays strict and any such line is fatal. Each is one
# extended regex over the joined "SCRIPT ERROR: <message> at: <where>" line.
SCRIPT_ERROR_ALLOW_GDAI='^SCRIPT ERROR: Parse Error: Identifier "GDAI[A-Za-z0-9_]*" not declared in the current scope\. at: GDScript::reload \(res://addons/gut/not_a_real_file/gut_dynamic_script_[0-9]+\.gd:[0-9]+\)$'"
^SCRIPT ERROR: Invalid call\. Nonexistent function 'new' in base 'int'\. at: _make_crazy_dynamic_over_engineered_class_db_hash \(res://addons/gut/stubber\.gd:35\)$"
UNEXPECTED=$(awk '/SCRIPT ERROR:/ { msg = $0; getline; sub(/^[ \t]+/, ""); print msg " " $0 }' "$TEST_OUTPUT" \
  | grep -v -F "$(printf '%s\n' "$SCRIPT_ERROR_ALLOW" | sed 's/.*/(&)/')" || true)
if [ -n "$UNEXPECTED" ] && [ "$EXPECTED_ERRORS" = "2" ]; then
  UNEXPECTED=$(printf '%s\n' "$UNEXPECTED" | grep -v -E "$SCRIPT_ERROR_ALLOW_GDAI" || true)
fi
if [ -n "$UNEXPECTED" ]; then
  echo ""
  echo "FATAL: SCRIPT ERROR outside the allow-list (a test may have aborted partway):"
  echo "$UNEXPECTED"
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
