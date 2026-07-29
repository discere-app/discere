#!/usr/bin/env bash
# Runs every integration_test/*_test.dart file in its own `flutter test`
# process against the given device, so state never bleeds between suites
# (see the comment on the integration_test job in flutter_ci.yml for why).
#
# Not inlined into flutter_ci.yml: reactivecircus/android-emulator-runner's
# `script` input splits multi-line scripts into separate single-line shell
# invocations, so a real for-loop can't live there directly.
set -uo pipefail

device="${1:?usage: run_integration_tests.sh <device-id>}"
failures=0

for test_file in integration_test/*_test.dart; do
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
