#!/usr/bin/env bash
# Unit tests, then headless smoke runs of the real game. Fails on any test
# failure, or any engine/script error printed while the game runs.
#   tests/run.sh            everything
#   tests/run.sh breaker    only unit tests whose name or file contains "breaker"
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
status=0

# Runs a Godot command; fails if it exits non-zero or prints an engine error.
run() {
	local label="$1"; shift
	echo "== $label"
	out="$(timeout 400 "$GODOT" --headless --path . "$@" 2>&1)"
	code=$?
	echo "$out" | grep -v "^Godot Engine"
	if [ $code -ne 0 ] || grep -qE "ERROR|Parse Error" <<<"$out"; then
		echo "-- FAILED (exit $code)"
		status=1
	fi
}

run "Unit tests" -s tests/run_tests.gd -- "${1:-}"
if [ -z "${1:-}" ]; then
	run "Smoke: main scene loads" --quit-after 300 -- --no-save
	run "Smoke: play 20 jobs" --fixed-fps 60 -s tests/smoke/play_jobs.gd
fi

[ $status -eq 0 ] && echo "== ALL PASSED" || echo "== FAILED"
exit $status
