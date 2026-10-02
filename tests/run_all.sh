#!/bin/bash
# Every test, each in its own clean saved-game folder, a few at a time.
#
#   GODOT=/path/to/godot tests/run_all.sh [-j N] [--qa] [--only name,name]
#
# - Each test gets a fresh user data folder (XDG_DATA_HOME), so no test sees
#   another's career, settings or records, and none touches yours.
# - The cloud tests get their own stand-in server (tests/tools/fake_cloud.py).
# - Online racing runs a host and a client together (direct, and through the
#   stand-in relay).
# - Tests that need a renderer (scenery_clear_test, a track at a time) run
#   under xvfb when it's there, and are skipped (said so) when it isn't.
# - Benches (*_bench.gd) and screenshot scripts (shots_*.gd) aren't tests and
#   aren't run.
# - --qa adds the full-race QA: a full-rules race at every track.
# Logs go to $OUT (default /tmp/st_tests); a summary is printed at the end and
# the exit status is the number of failures.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=${OUT:-/tmp/st_tests}
JOBS=$(( $(nproc 2>/dev/null || echo 2) / 2 ))
[ "$JOBS" -lt 1 ] && JOBS=1
QA=0
ONLY=""
while [ $# -gt 0 ]; do
	case "$1" in
		-j) JOBS=$2; shift ;;
		--qa) QA=1 ;;
		--only) ONLY=$2; shift ;;
	esac
	shift
done
rm -rf "$OUT"
mkdir -p "$OUT/home"
: > "$OUT/results.txt"

CLOUD_TESTS="cloud_test cloud_save_test friction_test"
TOUCH_TESTS="touch_ui_test access_test"
RENDER_TESTS="scenery_clear_test"
SPECIAL="net_test"

# One job: "kind name [arg]".
run_one() {
	local kind=$1 name=$2 arg=${3:-}
	local tag=$name${arg:+_$arg}
	local home="$OUT/home/$tag"
	mkdir -p "$home"
	local log="$OUT/$tag.txt"
	local env=(XDG_DATA_HOME="$home" ST_NO_INTRO=1)
	local code=0
	local start=$(date +%s)
	case $kind in
		plain)
			[[ " $TOUCH_TESTS " == *" $name "* ]] && env+=(ST_TOUCH=1)
			env "${env[@]}" timeout 1500 "$GODOT" --headless --fixed-fps 60 -s "tests/$name.gd" > "$log" 2>&1 || code=$?
			;;
		cloud)
			local port=$(( 25000 + RANDOM % 4000 ))
			python3 tests/tools/fake_cloud.py $port > "$OUT/$tag.server.txt" 2>&1 &
			local spid=$!
			sleep 1
			env "${env[@]}" ST_CLOUD=http://127.0.0.1:$port timeout 900 "$GODOT" --headless --fixed-fps 60 -s "tests/$name.gd" > "$log" 2>&1 || code=$?
			kill $spid 2>/dev/null
			;;
		render)
			if ! command -v xvfb-run > /dev/null; then
				echo "SKIPPED (needs xvfb-run)" > "$log"
				echo "SKIP $tag" >> "$OUT/results.txt"
				return
			fi
			env "${env[@]}" TRACK="$arg" timeout 1500 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 --resolution 1280x720 -s "tests/$name.gd" > "$log" 2>&1 || code=$?
			;;
		net)
			local port=$(( 29000 + RANDOM % 3000 ))
			local extra=()
			local rpid=""
			if [ "$arg" = relay ]; then
				python3 tests/tools/fake_realtime.py $port > "$OUT/$tag.relay.txt" 2>&1 &
				rpid=$!
				sleep 1
				extra=(RELAY=1 ST_RELAY=ws://127.0.0.1:$port)
			else
				extra=(RELAY=0)
			fi
			env "${env[@]}" "${extra[@]}" ROLE=host timeout 900 "$GODOT" --headless --fixed-fps 60 -s tests/net_test.gd > "$log.host" 2>&1 &
			local hpid=$!
			sleep 3
			env "${env[@]}" "${extra[@]}" ROLE=client timeout 900 "$GODOT" --headless --fixed-fps 60 -s tests/net_test.gd > "$log" 2>&1 || code=$?
			wait $hpid || code=$(( code + $? ))
			[ -n "$rpid" ] && kill $rpid 2>/dev/null
			cat "$log.host" >> "$log"
			;;
		qa)
			env "${env[@]}" TRACK=$arg timeout 2400 "$GODOT" --headless --fixed-fps 60 -s tests/full_race_qa.gd > "$log" 2>&1 || code=$?
			;;
	esac
	local secs=$(( $(date +%s) - start ))
	local fails=$(grep -c "^  FAIL\|SCRIPT ERROR" "$log" 2>/dev/null)
	if [ "$code" -eq 0 ] && [ "$fails" -eq 0 ]; then
		echo "PASS $tag (${secs}s)" >> "$OUT/results.txt"
	else
		echo "FAIL $tag (exit $code, $fails failed checks/errors, ${secs}s) - $log" >> "$OUT/results.txt"
	fi
}
export -f run_one
export OUT GODOT CLOUD_TESTS TOUCH_TESTS

jobs_list() {
	for f in tests/*_test.gd; do
		local n=$(basename "$f" .gd)
		[ -n "$ONLY" ] && [[ ",$ONLY," != *",$n,"* ]] && continue
		if [[ " $SPECIAL " == *" $n "* ]]; then
			echo "net net_test direct"
			echo "net net_test relay"
		elif [[ " $CLOUD_TESTS " == *" $n "* ]]; then
			echo "cloud $n"
		elif [[ " $RENDER_TESTS " == *" $n "* ]]; then
			for t in 0 1 2 3 4 5 6 7 8 9 10; do
				echo "render $n $t" # a track each: one renders slowly
			done
		else
			echo "plain $n"
		fi
	done
	if [ "$QA" = 1 ]; then
		for t in 0 1 2 3 4 5 6 7 8 9 10; do
			echo "qa full_race_qa $t"
		done
	fi
}

echo "running with $JOBS at a time, logs in $OUT"
jobs_list | xargs -P "$JOBS" -L 1 bash -c 'run_one "$@"' _
sort "$OUT/results.txt"
FAILS=$(grep -c "^FAIL" "$OUT/results.txt")
echo "$(grep -c "^PASS" "$OUT/results.txt") passed, $FAILS failed, $(grep -c "^SKIP" "$OUT/results.txt") skipped"
exit $FAILS
