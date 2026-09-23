#!/usr/bin/env bash
# Runs each given integration_test/*_test.dart file in its own `flutter test`
# process against the given device, so state never bleeds between suites
# (see the comment on the integration_test job in flutter_ci.yml for why).
#
# Not inlined into flutter_ci.yml: reactivecircus/android-emulator-runner's
# `script` input splits multi-line scripts into separate single-line shell
# invocations, so a real for-loop can't live there directly.
set -uo pipefail

device="${1:?usage: run_integration_tests.sh <device-id> <test-file>...}"
shift

if [ "$#" -eq 0 ]; then
  echo "::error::no test files given"
  exit 1
fi

failures=0

# Tells the workflow that the emulator was usable and testing actually began.
# The emulator action can fail before this script ever runs (it unlocks the
# screen the moment `sys.boot_completed` flips, which can be before the
# `input` service is registered), and that case is worth retrying while a
# failed test is not. See the retry step in flutter_ci.yml.
touch integration-tests-started

for test_file in "$@"; do
  echo "== Running $test_file =="
  if ! flutter test "$test_file" -d "$device"; then
    failures=$((failures + 1))
    echo "::error::$test_file failed"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "::error::$failures integration test file(s) failed"
  exit 1
fi
