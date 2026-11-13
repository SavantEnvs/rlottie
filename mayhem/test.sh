#!/usr/bin/env bash
#
# mayhem/test.sh — RUN rlottie's own gtest suites and a known-answer probe (all built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TEST_DIR="$SRC/build/tests"
passed=0; failed=0

# 1) upstream's gtest suites (vectorTestSuite, animationTestSuite). Judge them by gtest's own summary
#    lines, not by exit code: a neutered binary prints nothing, so it counts as a failure.
for suite in vectorTestSuite animationTestSuite; do
  bin="$TEST_DIR/test/$suite"
  if [ ! -x "$bin" ]; then echo "FAIL: $bin missing (mayhem/build.sh should have built it)"; failed=$((failed+1)); continue; fi
  out="$(cd "$TEST_DIR/test" && "$bin" 2>&1)"; echo "$out" | tail -5
  ran="$(echo "$out" | sed -n 's/^\[==========\] \([0-9]*\) tests\? from .* ran\..*/\1/p' | tail -1)"
  ok="$(echo "$out" | sed -n 's/^\[  PASSED  \] \([0-9]*\) tests\?\./\1/p' | tail -1)"
  if [ -z "$ran" ] || [ "${ran:-0}" -eq 0 ] || [ "${ok:-x}" != "$ran" ]; then
    echo "FAIL: $suite ran=${ran:-none} passed=${ok:-none}"; failed=$((failed+1))
  else
    passed=$((passed+ran))
  fi
done

# 2) known-answer probe: the library's computed facts for fixed inputs, compared to exact values.
kat="$TEST_DIR/rlottie_kat"
if [ ! -x "$kat" ]; then
  echo "FAIL: $kat missing (mayhem/build.sh should have built it)"; failed=$((failed+1))
else
  actual="$("$kat" "$SRC/example/resource" 2>&1)"
  expected="missing=null
garbage=null
mask frames=31 size=500x500 fps=60 duration=0.5 layers=1
solid frames=51 size=200x100 fps=25 duration=2 layers=1
solid red_pixels=20000 corner=ffff0000 center=ffff0000"
  if [ "$actual" = "$expected" ]; then
    echo "known-answer probe OK"; passed=$((passed+1))
  else
    echo "FAIL: known-answer probe differs"; echo "--- expected"; echo "$expected"; echo "--- actual"; echo "$actual"
    failed=$((failed+1))
  fi
fi

emit_ctrf "gtest+kat" "$passed" "$failed" 0
